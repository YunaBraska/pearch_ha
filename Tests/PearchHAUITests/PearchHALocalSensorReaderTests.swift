import XCTest
@testable import PearchHAAppShell

final class PearchHALocalSensorReaderTests: XCTestCase {
    @MainActor
    func testObservationDeliversThermalChangesUntilInvalidated() async {
        let firstChange = expectation(description: "thermal change")
        var changeCount = 0
        let observation = PearchHALocalSensorObservation {
            changeCount += 1
            firstChange.fulfill()
        }
        NotificationCenter.default.post(name: ProcessInfo.thermalStateDidChangeNotification, object: nil)
        await fulfillment(of: [firstChange], timeout: 1)

        observation.invalidate()
        NotificationCenter.default.post(name: ProcessInfo.thermalStateDidChangeNotification, object: nil)
        await Task.yield()
        XCTAssertEqual(changeCount, 1)
        observation.invalidate()
    }

    func testEmptyRequestDoesNotReadOrReturnMetrics() async {
        let reader = PearchHALocalSensorReader()
        let result = await reader.sample(metrics: [])
        XCTAssertTrue(result.isEmpty)
    }

    func testCPURequiresTwoSamplesAndReturnsBoundedUsage() async {
        let reader = PearchHALocalSensorReader()
        let first = await reader.sample(metrics: [PearchHALocalSensorReader.cpuUsageKey])
        XCTAssertEqual(first[PearchHALocalSensorReader.cpuUsageKey], "unknown")

        var usage: Double?
        var samples: [[String: String]] = []
        for _ in 0..<4 {
            try? await Task.sleep(for: .milliseconds(20))
            let sample = await reader.sample(metrics: [PearchHALocalSensorReader.cpuUsageKey])
            samples.append(sample)
            if let value = sample[PearchHALocalSensorReader.cpuUsageKey], let parsed = Double(value) {
                usage = parsed
                break
            }
        }
        XCTAssertNotNil(usage, "CPU samples: \(samples)")
        if let usage {
            XCTAssertTrue((0...100).contains(usage))
        }
    }

    func testMemoryAndThermalSamplesAreSupportedAndBounded() async {
        let reader = PearchHALocalSensorReader()
        let result = await reader.sample(metrics: [
            PearchHALocalSensorReader.memoryUsageKey,
            PearchHALocalSensorReader.thermalStateKey
        ])
        guard let memory = result[PearchHALocalSensorReader.memoryUsageKey], let usage = Double(memory) else {
            XCTFail("expected a numeric memory sample, got \(result)")
            return
        }
        XCTAssertTrue((0...100).contains(usage))
        XCTAssertTrue(["nominal", "fair", "serious", "critical", "unavailable"].contains(result[PearchHALocalSensorReader.thermalStateKey]))
    }

    func testBatteryMetricsAreOmittedWithoutPowerSourceOrFormattedWhenPresent() async throws {
        let reader = PearchHALocalSensorReader()
        let result = await reader.sample(metrics: [
            PearchHALocalSensorReader.batteryLevelKey,
            PearchHALocalSensorReader.batteryChargingKey
        ])
        if let level = result[PearchHALocalSensorReader.batteryLevelKey] {
            if level != "unavailable" {
                let percentage = try XCTUnwrap(Double(level))
                XCTAssertTrue((0...100).contains(percentage))
            }
            XCTAssertTrue(["on", "off", "unavailable"].contains(result[PearchHALocalSensorReader.batteryChargingKey]))
        } else {
            XCTAssertNil(result[PearchHALocalSensorReader.batteryChargingKey])
        }
    }
}
