import Foundation

/// Monotonic duration used by PearchHA support primitives.
public struct PearchDuration: Comparable, Equatable, Sendable {
    public let nanoseconds: Int64

    public init(nanoseconds: Int64) {
        self.nanoseconds = max(0, nanoseconds)
    }

    public static func milliseconds(_ value: Int64) -> PearchDuration {
        PearchDuration(nanoseconds: value * 1_000_000)
    }

    public static func seconds(_ value: Int64) -> PearchDuration {
        PearchDuration(nanoseconds: value * 1_000_000_000)
    }

    public static func < (lhs: PearchDuration, rhs: PearchDuration) -> Bool {
        lhs.nanoseconds < rhs.nanoseconds
    }
}

/// Monotonic instant used for deterministic scheduling and tests.
public struct PearchInstant: Comparable, Equatable, Sendable {
    public let nanosecondsSinceStart: Int64

    public init(nanosecondsSinceStart: Int64) {
        self.nanosecondsSinceStart = nanosecondsSinceStart
    }

    public func advanced(by duration: PearchDuration) -> PearchInstant {
        PearchInstant(nanosecondsSinceStart: nanosecondsSinceStart + duration.nanoseconds)
    }

    public func duration(to other: PearchInstant) -> PearchDuration {
        PearchDuration(nanoseconds: other.nanosecondsSinceStart - nanosecondsSinceStart)
    }

    public static func < (lhs: PearchInstant, rhs: PearchInstant) -> Bool {
        lhs.nanosecondsSinceStart < rhs.nanosecondsSinceStart
    }
}

/// Clock boundary for production time and deterministic tests.
public protocol PearchClock: Sendable {
    func now() async -> PearchInstant
    func sleep(until deadline: PearchInstant) async throws -> PearchInstant
}

public extension PearchClock {
    func sleep(for duration: PearchDuration) async throws -> PearchInstant {
        let deadline = await now().advanced(by: duration)
        return try await sleep(until: deadline)
    }
}

/// Production monotonic clock.
public struct SystemPearchClock: PearchClock {
    public init() {}

    public func now() async -> PearchInstant {
        PearchInstant(nanosecondsSinceStart: Int64(DispatchTime.now().uptimeNanoseconds))
    }

    public func sleep(until deadline: PearchInstant) async throws -> PearchInstant {
        let current = await now()
        guard deadline > current else {
            return current
        }
        let duration = current.duration(to: deadline)
        try await Task.sleep(nanoseconds: UInt64(duration.nanoseconds))
        return await now()
    }
}

/// Manually advanced test clock.
public actor TestPearchClock: PearchClock {
    private var current: PearchInstant
    private var sleepers: [Sleeper] = []
    private var nextSleeperID: UInt64 = 1

    public init(start: PearchInstant = PearchInstant(nanosecondsSinceStart: 0)) {
        current = start
    }

    public func now() -> PearchInstant {
        current
    }

    public func advance(by duration: PearchDuration) -> PearchInstant {
        current = current.advanced(by: duration)
        resumeDueSleepers()
        return current
    }

    public func sleep(until deadline: PearchInstant) async throws -> PearchInstant {
        if Task.isCancelled {
            throw CancellationError()
        }
        if deadline <= current {
            return current
        }

        let id = nextSleeperID
        nextSleeperID += 1

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                sleepers.append(Sleeper(id: id, deadline: deadline, continuation: continuation))
            }
        } onCancel: {
            Task {
                await self.cancelSleeper(id: id)
            }
        }
    }

    public func sleepingTaskCount() -> Int {
        sleepers.count
    }

    private func cancelSleeper(id: UInt64) -> Int {
        guard let index = sleepers.firstIndex(where: { $0.id == id }) else {
            return sleepers.count
        }
        let sleeper = sleepers.remove(at: index)
        sleeper.continuation.resume(throwing: CancellationError())
        return sleepers.count
    }

    private func resumeDueSleepers() {
        let due = sleepers.filter { $0.deadline <= current }
        sleepers.removeAll { $0.deadline <= current }
        due.forEach { sleeper in
            sleeper.continuation.resume(returning: current)
        }
    }
}

private struct Sleeper {
    let id: UInt64
    let deadline: PearchInstant
    let continuation: CheckedContinuation<PearchInstant, Error>
}
