import Foundation
import Combine
import Darwin
import IOKit.ps

/// Reads a small set of documented macOS health metrics without side effects.
///
/// Values are formatted for menu-bar display. CPU usage is a delta measurement,
/// so the first sample after initialization or a counter discontinuity is
/// reported as `unknown`. Memory usage is active, wired, and compressed
/// physical pages divided by physical memory. Battery metrics are omitted
/// when no internal battery is present.
public actor PearchHALocalSensorReader {
    private static let posixLocale = Locale(identifier: "en_US_POSIX")
    public static let cpuUsageKey = "cpu_usage"
    public static let memoryUsageKey = "memory_usage"
    public static let batteryLevelKey = "battery_level"
    public static let batteryChargingKey = "battery_charging"
    public static let thermalStateKey = "thermal_state"

    private struct CPUReading {
        let total: UInt64
        let idle: UInt64
    }

    private var previousCPUReading: CPUReading?

    public init() {}

    /// Samples only the requested metrics.
    ///
    /// Battery metrics are omitted when no internal battery is
    /// published by macOS. Known metrics with an unreadable value return
    /// `unavailable`. CPU usage returns `unknown` until two valid samples exist.
    public func sample(metrics: Set<String>) -> [String: String] {
        var result: [String: String] = [:]
        let wantsCPU = metrics.contains(Self.cpuUsageKey)
        if wantsCPU {
            result[Self.cpuUsageKey] = sampleCPU()
        } else {
            previousCPUReading = nil
        }

        if metrics.contains(Self.memoryUsageKey) {
            result[Self.memoryUsageKey] = sampleMemory()
        }
        if metrics.contains(Self.batteryLevelKey) || metrics.contains(Self.batteryChargingKey) {
            let battery = sampleBattery()
            if metrics.contains(Self.batteryLevelKey), let level = battery.level {
                result[Self.batteryLevelKey] = level
            } else if metrics.contains(Self.batteryLevelKey), battery.hasPowerSource {
                result[Self.batteryLevelKey] = "unavailable"
            }
            if metrics.contains(Self.batteryChargingKey), let charging = battery.charging {
                result[Self.batteryChargingKey] = charging ? "on" : "off"
            } else if metrics.contains(Self.batteryChargingKey), battery.hasPowerSource {
                result[Self.batteryChargingKey] = "unavailable"
            }
        }
        if metrics.contains(Self.thermalStateKey) {
            result[Self.thermalStateKey] = thermalState()
        }
        return result
    }

    private func sampleCPU() -> String {
        let host = mach_host_self()
        defer { mach_port_deallocate(mach_task_self_, host) }
        var processorCount: mach_msg_type_number_t = 0
        var processorInfo: processor_info_array_t?
        var processorInfoCount: mach_msg_type_number_t = 0
        let result = host_processor_info(
            host,
            PROCESSOR_CPU_LOAD_INFO,
            &processorCount,
            &processorInfo,
            &processorInfoCount
        )
        defer {
            if let processorInfo {
                let size = vm_size_t(processorInfoCount) * vm_size_t(MemoryLayout<integer_t>.stride)
                vm_deallocate(mach_task_self_, vm_address_t(UInt(bitPattern: processorInfo)), size)
            }
        }
        let expectedCount = Int(processorCount) * Int(CPU_STATE_MAX)
        guard result == KERN_SUCCESS,
              let processorInfo,
              processorCount > 0,
              expectedCount > 0,
              Int(processorInfoCount) >= expectedCount
        else {
            previousCPUReading = nil
            return "unavailable"
        }

        let stride = Int(CPU_STATE_MAX)
        var total: UInt64 = 0
        var idle: UInt64 = 0
        for processor in 0..<Int(processorCount) {
            let offset = processor * stride
            total += (0..<stride).reduce(UInt64(0)) { partial, index in
                partial + UInt64(UInt32(bitPattern: processorInfo[offset + index]))
            }
            idle += UInt64(UInt32(bitPattern: processorInfo[offset + Int(CPU_STATE_IDLE)]))
        }
        let current = CPUReading(total: total, idle: idle)
        defer { previousCPUReading = current }
        guard let previousCPUReading,
              current.total > previousCPUReading.total,
              current.idle >= previousCPUReading.idle,
              current.total - previousCPUReading.total >= current.idle - previousCPUReading.idle
        else {
            return "unknown"
        }

        let totalDelta = current.total - previousCPUReading.total
        let busyDelta = totalDelta - (current.idle - previousCPUReading.idle)
        let percentage = min(100, max(0, Double(busyDelta) / Double(totalDelta) * 100))
        return String(format: "%.1f", locale: Self.posixLocale, percentage)
    }

    private func sampleMemory() -> String {
        let host = mach_host_self()
        defer { mach_port_deallocate(mach_task_self_, host) }
        var pageSize: vm_size_t = 0
        guard host_page_size(host, &pageSize) == KERN_SUCCESS, pageSize > 0 else {
            return "unavailable"
        }
        var statistics = vm_statistics64_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &statistics) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { rebound in
                host_statistics64(host, HOST_VM_INFO64, rebound, &count)
            }
        }
        guard result == KERN_SUCCESS else { return "unavailable" }
        let totalBytes = ProcessInfo.processInfo.physicalMemory
        guard totalBytes > 0 else { return "unavailable" }
        let usedPages = UInt64(statistics.active_count)
            + UInt64(statistics.wire_count)
            + UInt64(statistics.compressor_page_count)
        let usedBytes = usedPages * UInt64(pageSize)
        let percentage = min(100, max(0, Double(usedBytes) / Double(totalBytes) * 100))
        return String(format: "%.1f", locale: Self.posixLocale, percentage)
    }

    private struct BatteryReading {
        let hasPowerSource: Bool
        let level: String?
        let charging: Bool?
    }

    private func sampleBattery() -> BatteryReading {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef]
        else {
            return BatteryReading(hasPowerSource: false, level: nil, charging: nil)
        }
        guard let description = list.lazy
            .compactMap({ IOPSGetPowerSourceDescription(info, $0)?.takeUnretainedValue() as? [String: Any] })
            .first(where: { ($0[kIOPSTypeKey as String] as? String) == kIOPSInternalBatteryType })
        else {
            return BatteryReading(hasPowerSource: false, level: nil, charging: nil)
        }
        let current = description[kIOPSCurrentCapacityKey as String] as? NSNumber
        let maximum = description[kIOPSMaxCapacityKey as String] as? NSNumber
        let level: String?
        if let current, let maximum, maximum.doubleValue > 0 {
            let percentage = min(100, max(0, current.doubleValue / maximum.doubleValue * 100))
            level = String(format: "%.1f", locale: Self.posixLocale, percentage)
        } else {
            level = nil
        }
        let charging = description[kIOPSIsChargingKey as String] as? Bool
        return BatteryReading(hasPowerSource: true, level: level, charging: charging)
    }

    private func thermalState() -> String {
        switch ProcessInfo.processInfo.thermalState {
        case .nominal: return "nominal"
        case .fair: return "fair"
        case .serious: return "serious"
        case .critical: return "critical"
        @unknown default: return "unavailable"
        }
    }
}

/// Delivers thermal and power changes without polling. The shell owns one
/// observation. Explicit invalidation and resource deinitialization both cancel it.
@MainActor
public final class PearchHALocalSensorObservation {
    private let powerSource: LocalPowerSourceObservation
    private let thermalObserver: AnyCancellable

    public init(onChange: @escaping @MainActor @Sendable () -> Void) {
        powerSource = LocalPowerSourceObservation(onChange: onChange)
        thermalObserver = NotificationCenter.default.publisher(for: ProcessInfo.thermalStateDidChangeNotification)
            .sink { _ in Task { @MainActor in onChange() } }
    }

    public func invalidate() {
        thermalObserver.cancel()
        powerSource.invalidate()
    }
}

/// CF run-loop sources are invalidated before their unretained callback context
/// is released. This resource owner also handles deallocation off the main actor.
private final class LocalPowerSourceObservation {
    private final class Callback: Sendable {
        let action: @MainActor @Sendable () -> Void
        init(action: @escaping @MainActor @Sendable () -> Void) { self.action = action }
    }
    private let callback: Callback
    private let source: CFRunLoopSource?

    @MainActor
    init(onChange: @escaping @MainActor @Sendable () -> Void) {
        callback = Callback(action: onChange)
        source = IOPSNotificationCreateRunLoopSource({ context in
            guard let context else { return }
            let callback = Unmanaged<Callback>.fromOpaque(context).takeUnretainedValue()
            Task { @MainActor in callback.action() }
        }, Unmanaged.passUnretained(callback).toOpaque())?.takeRetainedValue()
        if let source { CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes) }
    }

    func invalidate() {
        if let source { CFRunLoopSourceInvalidate(source) }
    }

    deinit { invalidate() }
}
