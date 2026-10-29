#if canImport(XCTest)
import XCTest
import PearchHASupport
import PearchHATestSupport

final class PearchHASupportTests: XCTestCase {
    func testApplicationVersionInfoUsesOneValueWhenMarketingAndBuildMatch() {
        let version = PearchHAApplicationVersionInfo(marketingVersion: "2026.7.7", buildVersion: "2026.7.7")

        XCTAssertEqual(version.releaseVersion, "2026.7.7")
        XCTAssertEqual(version.displayText, "2026.7.7")
    }

    func testApplicationVersionInfoIncludesDistinctBuildVersionInDisplayText() {
        let version = PearchHAApplicationVersionInfo(marketingVersion: "1.2.3", buildVersion: "456")

        XCTAssertEqual(version.releaseVersion, "1.2.3")
        XCTAssertEqual(version.displayText, "1.2.3 (456)")
    }

    func testApplicationVersionInfoFallsBackToBuildVersionWhenMarketingVersionIsMissing() {
        let version = PearchHAApplicationVersionInfo(marketingVersion: nil, buildVersion: "456")

        XCTAssertEqual(version.releaseVersion, "456")
        XCTAssertEqual(version.displayText, "456")
    }

    func testCommandLineOptionsParseFlagsAndRepeatedValues() throws {
        let options = try PearchHACommandLineOptions(
            arguments: ["--env", ".env.local", "--strict", "--require-screenshot", "one.png", "--require-screenshot", "two.png"],
            valueOptions: ["--env", "--require-screenshot"],
            flagOptions: ["--strict"]
        )

        XCTAssertEqual(options.value(for: "--env"), ".env.local")
        XCTAssertEqual(options.values(for: "--require-screenshot"), ["one.png", "two.png"])
        XCTAssertTrue(options.has("--strict"))
    }

    func testCommandLineOptionsRejectMissingValueWhenNextTokenIsAnotherOption() {
        XCTAssertThrowsError(
            try PearchHACommandLineOptions(
                arguments: ["--env", "--json"],
                valueOptions: ["--env"],
                flagOptions: ["--json"]
            )
        ) { error in
            XCTAssertEqual(error as? PearchHACommandLineParseError, .missingValue("--env"))
        }
    }

    func testCommandLineOptionsCanTreatBareArgumentsAsInvalid() {
        XCTAssertThrowsError(
            try PearchHACommandLineOptions(
                arguments: ["fixtures"],
                valueOptions: [],
                flagOptions: [],
                nonOptionBehavior: .invalidArgument
            )
        ) { error in
            XCTAssertEqual(error as? PearchHACommandLineParseError, .invalidArgument("fixtures"))
        }
    }

    func testJitteredSchedulerStaysInsideConfiguredBounds() {
        var scheduler = JitteredScheduler(base: .seconds(10), fraction: 0.2, seed: 42)
        let delay = scheduler.nextDelay()

        XCTAssertGreaterThanOrEqual(delay, .seconds(8))
        XCTAssertLessThanOrEqual(delay, .seconds(12))
    }

    func testBackoffRespectsCap() {
        var backoff = ExponentialBackoff(base: .seconds(1), cap: .seconds(8), seed: 7)

        XCTAssertLessThanOrEqual(backoff.delay(forAttempt: 4), .seconds(8))
    }

    func testRedactorRemovesSensitiveHeadersAndMessages() {
        let redactor = Redactor()
        let headers = redactor.redact(headers: ["Authorization": "Bearer secret", "Accept": "application/json"])

        XCTAssertEqual(headers["Authorization"], "<redacted>")
        XCTAssertEqual(headers["Accept"], "application/json")
        XCTAssertTrue(redactor.redact(message: "token=secret value=ok").contains("token=<redacted>"))
        XCTAssertTrue(redactor.redact(message: "token=one password: two token=three").contains("password: <redacted>"))
        XCTAssertTrue(redactor.redact(message: "\"token\": \"secret\"").contains("\"token\": \"<redacted>\""))
        XCTAssertTrue(redactor.redact(message: "password = secret").contains("password = <redacted>"))
        XCTAssertTrue(redactor.redact(message: "\"code\":\"1234\"").contains("\"code\":\"<redacted>\""))
        XCTAssertTrue(redactor.redact(message: "pin=9999").contains("pin=<redacted>"))
        XCTAssertTrue(redactor.redact(message: "secret=hidden").contains("secret=<redacted>"))
        XCTAssertEqual(redactor.redact(message: "Authorization: Bearer secret"), "Authorization: <redacted>")
        XCTAssertEqual(
            redactor.redact(message: "Authorization: Bearer secret Accept: application/json"),
            "Authorization: <redacted> Accept: application/json"
        )
        XCTAssertTrue(redactor.redact(message: "ToKeN=secret").contains("ToKeN=<redacted>"))
        XCTAssertEqual(redactor.redact(message: "notoken=secret value=ok"), "notoken=secret value=ok")
        XCTAssertEqual(redactor.redact(message: "prefixauthorization: Bearer secret"), "prefixauthorization: Bearer secret")
        XCTAssertEqual(redactor.redact(message: "\"mytoken\": \"secret\""), "\"mytoken\": \"secret\"")
    }

    func testTestClockAdvancesDeterministically() async {
        let clock = TestPearchClock()

        await assertEqualAsync(await clock.now(), PearchInstant(nanosecondsSinceStart: 0))
        _ = await clock.advance(by: .seconds(3))
        await assertEqualAsync(await clock.now(), PearchInstant(nanosecondsSinceStart: 3_000_000_000))
    }

    func testTestClockWakesSleepersOnAdvance() async throws {
        let clock = TestPearchClock()
        let deadline = PearchInstant(nanosecondsSinceStart: 2_000_000_000)
        let sleeper = Task {
            try await clock.sleep(until: deadline)
        }

        try await waitUntil("test clock has sleeper") {
            await clock.sleepingTaskCount() == 1
        }

        _ = await clock.advance(by: .seconds(2))

        try await assertEqualAsync(try await sleeper.value, deadline)
    }

    func testTestClockCancelsSleepers() async throws {
        let clock = TestPearchClock()
        let sleeper = Task {
            try await clock.sleep(until: PearchInstant(nanosecondsSinceStart: 2_000_000_000))
        }

        try await waitUntil("test clock has cancellable sleeper") {
            await clock.sleepingTaskCount() == 1
        }
        sleeper.cancel()

        do {
            _ = try await sleeper.value
            XCTFail("cancelled sleeper completed")
        } catch is CancellationError {
            await assertEqualAsync(await clock.sleepingTaskCount(), 0)
        }
    }
}
#endif
