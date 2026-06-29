#if canImport(XCTest)
import XCTest
import PerchHASupport

final class PerchHASupportTests: XCTestCase {
    func testModuleDeclaresResponsibility() {
        XCTAssertEqual(PerchHASupport.module.name, "PerchHASupport")
        XCTAssertTrue(PerchHASupport.module.responsibility.contains("rate limits"))
        XCTAssertTrue(PerchHASupport.module.responsibility.contains("command-line parsing"))
    }

    func testCommandLineOptionsParseFlagsAndRepeatedValues() throws {
        let options = try PerchHACommandLineOptions(
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
            try PerchHACommandLineOptions(
                arguments: ["--env", "--json"],
                valueOptions: ["--env"],
                flagOptions: ["--json"]
            )
        ) { error in
            XCTAssertEqual(error as? PerchHACommandLineParseError, .missingValue("--env"))
        }
    }

    func testCommandLineOptionsCanTreatBareArgumentsAsInvalid() {
        XCTAssertThrowsError(
            try PerchHACommandLineOptions(
                arguments: ["fixtures"],
                valueOptions: [],
                flagOptions: [],
                nonOptionBehavior: .invalidArgument
            )
        ) { error in
            XCTAssertEqual(error as? PerchHACommandLineParseError, .invalidArgument("fixtures"))
        }
    }

    func testRateLimiterRefillsOverTime() {
        let start = PerchInstant(nanosecondsSinceStart: 0)
        var limiter = TokenBucketRateLimiter(capacity: 2, refillPerSecond: 1, now: start)

        XCTAssertTrue(limiter.tryAcquire(at: start))
        XCTAssertTrue(limiter.tryAcquire(at: start))
        XCTAssertFalse(limiter.tryAcquire(at: start))
        XCTAssertTrue(limiter.tryAcquire(at: start.advanced(by: .seconds(1))))
    }

    func testRateLimiterRejectsImpossibleRequestsExplicitly() {
        let start = PerchInstant(nanosecondsSinceStart: 0)
        var limiter = TokenBucketRateLimiter(capacity: 2, refillPerSecond: 1, now: start)

        XCTAssertEqual(
            limiter.nextAvailability(for: 3, at: start),
            .impossible(capacity: 2, requested: 3)
        )
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
        let clock = TestPerchClock()

        await assertEqualAsync(await clock.now(), PerchInstant(nanosecondsSinceStart: 0))
        _ = await clock.advance(by: .seconds(3))
        await assertEqualAsync(await clock.now(), PerchInstant(nanosecondsSinceStart: 3_000_000_000))
    }

    func testTestClockWakesSleepersOnAdvance() async throws {
        let clock = TestPerchClock()
        let deadline = PerchInstant(nanosecondsSinceStart: 2_000_000_000)
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
        let clock = TestPerchClock()
        let sleeper = Task {
            try await clock.sleep(until: PerchInstant(nanosecondsSinceStart: 2_000_000_000))
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

    func testRequestCoalescerRunsOneOperationPerKey() async throws {
        let coalescer = RequestCoalescer<String, Int>()
        let counter = TestCounter()
        let gate = TestGate()

        let first = Task {
            try await coalescer.value(for: "same") {
                _ = await counter.increment()
                await gate.wait()
                return 42
            }
        }

        try await waitUntil("coalescer has first task") {
            await coalescer.activeRequestCount() == 1
        }

        let second = Task {
            try await coalescer.value(for: "same") {
                _ = await counter.increment()
                await gate.wait()
                return 13
            }
        }
        try await waitUntil("coalescer has second caller") {
            await coalescer.coalescedWaiterCount() == 1
        }

        _ = await gate.open()

        let values = try await [first.value, second.value]
        XCTAssertEqual(values, [42, 42])
        await assertEqualAsync(await counter.value, 1)
        await assertEqualAsync(await coalescer.activeRequestCount(), 0)
        await assertEqualAsync(await coalescer.coalescedWaiterCount(), 0)
    }

    func testRequestCoalescerClearsFailedOperations() async throws {
        let coalescer = RequestCoalescer<String, Int>()
        let counter = TestCounter()
        let gate = TestGate()
        let first = Task {
            try await coalescer.value(for: "same") {
                _ = await counter.increment()
                await gate.wait()
                throw CoalescerTestError.planned
            }
        }

        try await waitUntil("coalescer has failing task") {
            await coalescer.activeRequestCount() == 1
        }

        let second = Task {
            try await coalescer.value(for: "same") {
                _ = await counter.increment()
                return 13
            }
        }
        try await waitUntil("coalescer has second failing caller") {
            await coalescer.coalescedWaiterCount() == 1
        }
        _ = await gate.open()

        do {
            _ = try await first.value
            XCTFail("first coalesced call unexpectedly succeeded")
        } catch CoalescerTestError.planned {}

        do {
            _ = try await second.value
            XCTFail("second coalesced call unexpectedly succeeded")
        } catch CoalescerTestError.planned {}

        await assertEqualAsync(await counter.value, 1)
        await assertEqualAsync(await coalescer.activeRequestCount(), 0)
        await assertEqualAsync(await coalescer.coalescedWaiterCount(), 0)

        let retry = try await coalescer.value(for: "same") {
            _ = await counter.increment()
            return 99
        }

        XCTAssertEqual(retry, 99)
        await assertEqualAsync(await counter.value, 2)
    }

    func test_t_rate_limit_hygiene() async throws {
        let start = PerchInstant(nanosecondsSinceStart: 0)
        var limiter = TokenBucketRateLimiter(capacity: 1, refillPerSecond: 1, now: start)
        XCTAssertTrue(limiter.tryAcquire(at: start))
        XCTAssertFalse(limiter.tryAcquire(at: start))
        XCTAssertEqual(
            limiter.nextAvailability(at: start),
            .available(start.advanced(by: .seconds(1)))
        )

        var scheduler = JitteredScheduler(base: .seconds(10), fraction: 0.2, seed: 42)
        let jitter = scheduler.nextDelay()
        XCTAssertGreaterThanOrEqual(jitter, .seconds(8))
        XCTAssertLessThanOrEqual(jitter, .seconds(12))

        var backoff = ExponentialBackoff(base: .seconds(1), cap: .seconds(8), seed: 7)
        XCTAssertLessThanOrEqual(backoff.delay(forAttempt: 4), .seconds(8))

        let coalescer = RequestCoalescer<String, Int>()
        let counter = TestCounter()
        let gate = TestGate()
        let first = Task {
            try await coalescer.value(for: "same") {
                _ = await counter.increment()
                await gate.wait()
                return 1
            }
        }
        try await waitUntil("coalescer has first hygiene task") {
            await coalescer.activeRequestCount() == 1
        }
        let second = Task {
            try await coalescer.value(for: "same") {
                _ = await counter.increment()
                return 2
            }
        }
        try await waitUntil("coalescer has second hygiene caller") {
            await coalescer.coalescedWaiterCount() == 1
        }
        _ = await gate.open()
        try await assertEqualAsync(try await [first.value, second.value], [1, 1])
        await assertEqualAsync(await counter.value, 1)
        await assertEqualAsync(await coalescer.coalescedWaiterCount(), 0)
    }
}

enum CoalescerTestError: Error, Equatable {
    case planned
}

func waitUntil(_ message: String, condition: @escaping () async -> Bool) async throws {
    for _ in 0..<100 {
        if await condition() {
            return
        }
        await Task.yield()
    }
    throw WaitFailure(message)
}

struct WaitFailure: Error, CustomStringConvertible {
    let description: String

    init(_ description: String) {
        self.description = description
    }
}

actor TestCounter {
    private(set) var value = 0

    func increment() -> Int {
        value += 1
        return value
    }
}

actor TestGate {
    private var isOpen = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        if isOpen {
            return
        }
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    func open() -> Int {
        isOpen = true
        let continuations = waiters
        waiters.removeAll()
        continuations.forEach { $0.resume() }
        return continuations.count
    }
}
#endif
