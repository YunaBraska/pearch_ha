import AppKit
import Darwin
import Foundation
import SwiftUI
import FakeHA
import PerchHACore
import PerchHAClient
import PerchHAPackaging
import PerchHAAppShell
import PerchHACoverageCheck
import PerchHAPersistence
import PerchHARepoAudit
import PerchHASupport
import PerchHAUI

@main
struct PerchHASmoke {
    static func main() async {
        do {
            try await run(arguments: Array(CommandLine.arguments.dropFirst()))
        } catch {
            fputs("perchha-smoke: \(error)\n", stderr)
            Foundation.exit(1)
        }
    }

    @MainActor
    private static func run(arguments: [String]) async throws {
        let options = try SmokeOptions(arguments: arguments)
        if options.showsHelp {
            print(SmokeOptions.help)
            return
        }
        try verifySmokeOptions()
        if options.repeatCount > 1 {
            try runRepeatedProcesses(arguments: arguments, repeatCount: options.repeatCount)
            print("PerchHA smoke verification passed.")
            return
        }
        try await runOnce(options: options)
        print("PerchHA smoke verification passed.")
    }

    @MainActor
    private static func runOnce(options: SmokeOptions) async throws {
        try expect(PerchHASupport.module.name == "PerchHASupport", "support module is named")
        try expect(PerchHACore.module.name == "PerchHACore", "core module is named")
        try expect(PlannedHAClient().describe().name == "PerchHAClient", "client module is named")
        try expect(PlannedConfigStore().describe().name == "PerchHAPersistence", "persistence module is named")
        try expect(PerchHAUI.module.name == "PerchHAUI", "UI module is named")

        let id: EntityID = "sensor.office_temperature"
        try expect(id.rawValue == "sensor.office_temperature", "entity ID preserves raw value")

        let location = ConfigLocation()
        try expect(location.applicationSupportDirectoryName == "PerchHA", "config location uses app name")
        try verifyRateLimiter()
        try verifyJitter()
        try verifyBackoff()
        try verifyRedaction()
        try verifyCoverageGate()
        try verifyRepositoryAuditGate()
        try verifyXcodeDoctor()
        try await verifyCoalescing()
        try await verifyTestClock()
        try await verifyMirrorAndFakeHA()
        try await verifyHAMirrorDoctorCLIUsesExportedOverrides()
        try await verifyHAMirrorDoctorProbeReportsLiveGuidance()
        try await verifyHAMirrorOAuthCheckReportsMissingConfigurationGuidance()
        try await verifyHAMirrorCaptureCLI()
        try await verifyHAMirrorServeCLI()
        try verifyFakeHAConcurrentStartup()
        try verifyFakeHACoalescedWebSocketReads()
        try await verifyHAClientContract()
        try await verifyHAWebSocketContract()
        try await verifyDiscoveryAndPersistence()
        try await verifyPanelModelAgainstFakeHA()
        try verifyAppShellPanelFactory()
        try await verifyBuiltInControlsPanelFactory()
        try await verifySettingsCustomActionEditorTextFieldFocusPath()
        try await verifySettingsCustomActionEditorNativeMutation()
        try await verifySettingsCustomActionEditorNativePopupMutation()
        try verifyPanelOpenPerformance()
        try await verifyApplicationLifecycleMemorySoak()
        try await verifyIdleCPUAtRest()
        try await verifyPanelSnapshotRendering(options: options)
        try verifyOAuthConfigurationFromEnvironmentFile()
        try await verifyOAuthClientWebsitePackaging()
        try verifyAppBundlePackaging()
        try await verifyApplicationLaunchWiring()
        try verifySelectionOrderingAndFormatting()
        try await verifyMenuBarRenderingAndPromotion()
    }

    private static func runRepeatedProcesses(arguments: [String], repeatCount: Int) throws {
        let childArguments = removingRepeatOption(from: arguments)
        let executableURL = URL(fileURLWithPath: CommandLine.arguments[0], isDirectory: false)
        for run in 1...repeatCount {
            let process = Process()
            process.executableURL = executableURL
            process.arguments = childArguments
            process.environment = ProcessInfo.processInfo.environment
            process.standardOutput = FileHandle.standardOutput
            process.standardError = FileHandle.standardError
            try process.run()
            process.waitUntilExit()
            guard process.terminationReason == .exit, process.terminationStatus == 0 else {
                throw SmokeFailure("smoke repeat run \(run)/\(repeatCount) failed")
            }
            print("PerchHA smoke verification passed (\(run)/\(repeatCount)).")
        }
    }

    private static func removingRepeatOption(from arguments: [String]) -> [String] {
        var result: [String] = []
        var index = 0
        while index < arguments.count {
            if arguments[index] == "--repeat" {
                index += 2
                continue
            }
            result.append(arguments[index])
            index += 1
        }
        return result
    }

    private static func verifySmokeOptions() throws {
        let defaults = try SmokeOptions(arguments: [])
        try expect(defaults.repeatCount == 1, "smoke options default repeat count is one")

        let repeated = try SmokeOptions(arguments: ["--repeat", "3"])
        try expect(repeated.repeatCount == 3, "smoke options parse repeat count")

        let help = try SmokeOptions(arguments: ["--help"])
        try expect(help.showsHelp, "smoke options expose help flag")

        do {
            _ = try SmokeOptions(arguments: ["--repeat", "0"])
            throw SmokeFailure("smoke options accept zero repeat count")
        } catch let error as SmokeFailure {
            try expect(error.description == "invalid repeat count: 0", "smoke options reject zero repeat count")
        }

        do {
            _ = try SmokeOptions(arguments: ["--repeat", "many"])
            throw SmokeFailure("smoke options accept non-numeric repeat count")
        } catch let error as SmokeFailure {
            try expect(error.description == "invalid repeat count: many", "smoke options reject non-numeric repeat count")
        }
    }

    private static func verifyRateLimiter() throws {
        let start = PerchInstant(nanosecondsSinceStart: 0)
        var limiter = TokenBucketRateLimiter(capacity: 2, refillPerSecond: 1, now: start)

        try expect(limiter.tryAcquire(at: start), "first token is available")
        try expect(limiter.tryAcquire(at: start), "second token is available")
        try expect(!limiter.tryAcquire(at: start), "bucket is empty")
        try expect(limiter.tryAcquire(at: start.advanced(by: .seconds(1))), "bucket refills over time")
        try expect(
            limiter.nextAvailability(for: 3, at: start) == .impossible(capacity: 2, requested: 3),
            "impossible token requests fail explicitly"
        )
    }

    private static func verifyJitter() throws {
        var scheduler = JitteredScheduler(base: .seconds(10), fraction: 0.2, seed: 42)
        let delay = scheduler.nextDelay()

        try expect(delay >= .seconds(8), "jitter lower bound is respected")
        try expect(delay <= .seconds(12), "jitter upper bound is respected")
    }

    private static func verifyBackoff() throws {
        var backoff = ExponentialBackoff(base: .seconds(1), cap: .seconds(8), seed: 7)
        let delay = backoff.delay(forAttempt: 4)

        try expect(delay <= .seconds(8), "backoff cap is respected")
    }

    private static func verifyRedaction() throws {
        let redactor = Redactor()
        let headers = redactor.redact(headers: ["Authorization": "Bearer secret", "Accept": "application/json"])

        try expect(headers["Authorization"] == "<redacted>", "authorization header is redacted")
        try expect(headers["Accept"] == "application/json", "safe header is preserved")
        try expect(redactor.redact(message: "token=secret value=ok").contains("token=<redacted>"), "message token is redacted")
        try expect(
            redactor.redact(message: "token=one password: two token=three").contains("password: <redacted>"),
            "message password is redacted"
        )
        try expect(redactor.redact(message: "\"token\": \"secret\"").contains("\"token\": \"<redacted>\""), "pretty JSON token is redacted")
        try expect(redactor.redact(message: "password = secret").contains("password = <redacted>"), "spaced password assignment is redacted")
        try expect(redactor.redact(message: "\"code\":\"1234\"").contains("\"code\":\"<redacted>\""), "service code is redacted")
        try expect(redactor.redact(message: "pin=9999").contains("pin=<redacted>"), "service pin is redacted")
        try expect(redactor.redact(message: "Authorization: Bearer secret") == "Authorization: <redacted>", "bearer header message is redacted")
        try expect(
            redactor.redact(message: "Authorization: Bearer secret Accept: application/json") == "Authorization: <redacted> Accept: application/json",
            "bearer header message preserves following fields"
        )
        try expect(redactor.redact(message: "notoken=secret value=ok") == "notoken=secret value=ok", "larger non-secret key is preserved")
        try expect(redactor.redact(message: "prefixauthorization: Bearer secret") == "prefixauthorization: Bearer secret", "prefixed authorization key is preserved")
        try expect(redactor.redact(message: "\"mytoken\": \"secret\"") == "\"mytoken\": \"secret\"", "quoted larger key is preserved")
    }

    private static func verifyCoverageGate() throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("PerchHACoverageSmoke-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: directory)
        }

        let missingBranchURL = directory.appendingPathComponent("missing-branches.json", isDirectory: false)
        try Data(
            """
            {"data":[{"files":[{"filename":"Sources/PerchHACore/Foo.swift","summary":{"lines":{"count":10,"covered":10}}}]}]}
            """.utf8
        ).write(to: missingBranchURL)
        let missingBranch = runCoverageGate([
            "--coverage-json",
            missingBranchURL.path,
            "--branch-target",
            "PerchHACore=90"
        ])
        try expect(missingBranch.exitCode == 1, "coverage gate rejects missing branch metric")
        try expect(
            missingBranch.error.contains("branch coverage for Sources/PerchHACore"),
            "coverage gate reports missing branch metric explicitly"
        )

        let zeroBranchURL = directory.appendingPathComponent("zero-branches.json", isDirectory: false)
        try Data(
            """
            {"data":[{"files":[{"filename":"Sources/PerchHACore/Foo.swift","summary":{"lines":{"count":1,"covered":1},"branches":{"count":0,"covered":0}}}]}]}
            """.utf8
        ).write(to: zeroBranchURL)
        let zeroBranch = runCoverageGate([
            "--coverage-json",
            zeroBranchURL.path,
            "--branch-target",
            "PerchHACore=100"
        ])
        try expect(zeroBranch.exitCode == 0, "coverage gate accepts available zero-count branch metric")
        try expect(
            zeroBranch.output.contains("PerchHACore branch: 100.00% >= 100.00% (0/0)"),
            "coverage gate reports zero-count branch metric"
        )
    }

    private static func verifyXcodeDoctor() throws {
        var output: [String] = []
        var errors: [String] = []
        let exitCode = PerchHAXcodeDoctorCommand.run(
            arguments: ["--json"],
            standardOutput: { output.append($0) },
            standardError: { errors.append($0) }
        )
        try expect(exitCode == 0, "xcode doctor json exits successfully")
        try expect(errors.isEmpty, "xcode doctor json stays quiet on stderr")

        let diagnostic = try JSONDecoder().decode(
            PerchHAXcodePreflightDiagnostic.self,
            from: Data(output.joined(separator: "\n").utf8)
        )
        try expect(diagnostic.project == .present, "xcode doctor sees checked-in Xcode project")
        try expect(diagnostic.sharedScheme == .present, "xcode doctor sees checked-in shared scheme")
        if diagnostic.nativeVerification == .ready {
            try expect(diagnostic.projectListing == .ready, "xcode doctor ready state proves xcodebuild project listing")
        } else {
            try expect(diagnostic.projectListing == .blocked, "xcode doctor blocked state marks project listing blocked")
        }

        var strictErrors: [String] = []
        let strictExitCode = PerchHAXcodeDoctorCommand.run(
            arguments: ["--json", "--strict"],
            standardOutput: { _ in },
            standardError: { strictErrors.append($0) }
        )
        try expect(strictErrors.isEmpty, "xcode doctor strict mode stays quiet on stderr")
        if diagnostic.nativeVerification == .ready {
            try expect(strictExitCode == 0, "xcode doctor strict mode succeeds when native verification is ready")
            try expect(diagnostic.issues.isEmpty, "xcode doctor ready state has no issues")
            try expect(
                diagnostic.suggestedCommands.contains("swift test --disable-swift-testing --enable-xctest list"),
                "xcode doctor ready state suggests XCTest listing"
            )
        } else {
            try expect(strictExitCode == 1, "xcode doctor strict mode fails when native verification is blocked")
            try expect(!diagnostic.issues.isEmpty, "xcode doctor blocked state reports actionable issues")
        }
    }

    private static func runCoverageGate(_ arguments: [String]) -> CoverageGateSmokeResult {
        var output: [String] = []
        var errors: [String] = []
        let exitCode = PerchHACoverageCheckCommand.run(
            arguments: arguments,
            standardOutput: { output.append($0) },
            standardError: { errors.append($0) }
        )
        return CoverageGateSmokeResult(
            exitCode: exitCode,
            output: output.joined(separator: "\n"),
            error: errors.joined()
        )
    }

    private static func verifyRepositoryAuditGate() throws {
        try verifyRepositoryAuditRejects(
            relativePath: ".env.local",
            contents: "token=do-not-commit\n",
            expectedError: ".env.local: local environment files must stay ignored",
            addToIndex: true,
            message: "repository audit rejects local env files"
        )
        try verifyRepositoryAuditRejects(
            relativePath: ".env.local",
            contents: "token=do-not-commit\n",
            expectedError: ".env.local: local environment files must stay ignored",
            addToIndex: false,
            message: "repository audit rejects unignored local env files"
        )
        try verifyRepositoryAuditRejects(
            relativePath: "Fixtures/private/capture.json",
            contents: #"{"private":true}"#,
            expectedError: "Fixtures/private/capture.json: private fixture captures must stay ignored",
            addToIndex: true,
            message: "repository audit rejects private fixture captures"
        )
        try verifyRepositoryAuditRejects(
            relativePath: "Fixtures/private/capture.json",
            contents: #"{"private":true}"#,
            expectedError: "Fixtures/private/capture.json: private fixture captures must stay ignored",
            addToIndex: false,
            message: "repository audit rejects unignored private fixture captures"
        )
        try verifyRepositoryAuditRejects(
            relativePath: ".build/output.txt",
            contents: "build output\n",
            expectedError: ".build/output.txt: build output must stay ignored",
            addToIndex: true,
            message: "repository audit rejects build output"
        )
        try verifyRepositoryAuditRejects(
            relativePath: ".build/output.txt",
            contents: "build output\n",
            expectedError: ".build/output.txt: build output must stay ignored",
            addToIndex: false,
            message: "repository audit rejects unignored build output"
        )
        try verifyRepositoryAuditRejects(
            relativePath: "keys/AuthKey_TEST.p8",
            contents: "private key\n",
            expectedError: "keys/AuthKey_TEST.p8: credential artifact must not be committed",
            addToIndex: true,
            message: "repository audit rejects Apple private key artifacts"
        )
        try verifyRepositoryAuditRejects(
            relativePath: "keys/AuthKey_TEST.p8",
            contents: "private key\n",
            expectedError: "keys/AuthKey_TEST.p8: credential artifact must not be committed",
            addToIndex: false,
            message: "repository audit rejects unignored Apple private key artifacts"
        )
        try verifyRepositoryAuditRejects(
            relativePath: "Sources/App/Telemetry.swift",
            contents: ["import", "Sentry"].joined(separator: " ") + "\n",
            expectedError: "Sources/App/Telemetry.swift: telemetry SDK import must not be present by default",
            addToIndex: true,
            message: "repository audit rejects telemetry imports"
        )
        try verifyRepositoryAuditRejects(
            relativePath: "Sources/App/Telemetry.swift",
            contents: ["@preconcurrency", "import", "Firebase"].joined(separator: " ") + "\n",
            expectedError: "Sources/App/Telemetry.swift: telemetry SDK import must not be present by default",
            addToIndex: true,
            message: "repository audit rejects attributed telemetry imports"
        )
        try verifyRepositoryAuditRejects(
            relativePath: "Sources/App/Telemetry.swift",
            contents: ["public", "import", "FirebaseAnalytics"].joined(separator: " ") + "\n",
            expectedError: "Sources/App/Telemetry.swift: telemetry SDK import must not be present by default",
            addToIndex: true,
            message: "repository audit rejects access-qualified telemetry imports"
        )
        try verifyRepositoryAuditRejects(
            relativePath: "Sources/App/Telemetry.swift",
            contents: #"let endpoint = "\#("https://o123." + "ingest." + "sentry.io/api")""#,
            expectedError: "Sources/App/Telemetry.swift: telemetry dependency or collection endpoint must not be present by default",
            addToIndex: true,
            message: "repository audit rejects telemetry collection endpoints"
        )
        try verifyRepositoryAuditRejects(
            relativePath: "PerchHA.xcodeproj/project.pbxproj",
            contents: "repositoryURL = https://github.com/" + "get" + "sentry" + "/" + "sentry" + "-cocoa;\n",
            expectedError: "PerchHA.xcodeproj/project.pbxproj: telemetry dependency or collection endpoint must not be present by default",
            addToIndex: true,
            message: "repository audit rejects telemetry references in Xcode projects"
        )

        let cleanRepository = try createRepositoryAuditSmokeRepository(
            relativePath: ".env.example",
            contents: "token=\n",
            addToIndex: true
        )
        defer {
            try? FileManager.default.removeItem(at: cleanRepository)
        }
        let clean = runRepositoryAudit(["--root", cleanRepository.path])
        try expect(clean.exitCode == 0, "repository audit allows example env files")
        try expect(clean.output.contains("Repository audit passed."), "repository audit reports clean repository")
    }

    private static func verifyRepositoryAuditRejects(
        relativePath: String,
        contents: String,
        expectedError: String,
        addToIndex: Bool,
        message: String
    ) throws {
        let repository = try createRepositoryAuditSmokeRepository(
            relativePath: relativePath,
            contents: contents,
            addToIndex: addToIndex
        )
        defer {
            try? FileManager.default.removeItem(at: repository)
        }

        let result = runRepositoryAudit(["--root", repository.path])
        try expect(result.exitCode == 1, message)
        try expect(result.error.contains(expectedError), "\(message) with explicit reason")
    }

    private static func createRepositoryAuditSmokeRepository(
        relativePath: String,
        contents: String,
        addToIndex: Bool
    ) throws -> URL {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("PerchHARepoAuditSmoke-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try runGit(["init", "-q"], in: directory)
        let fileURL = directory.appendingPathComponent(relativePath, isDirectory: false)
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(contents.utf8).write(to: fileURL)
        if addToIndex {
            try runGit(["add", "-f", relativePath], in: directory)
        }
        return directory
    }

    private static func runRepositoryAudit(_ arguments: [String]) -> RepoAuditSmokeResult {
        var output: [String] = []
        var errors: [String] = []
        let exitCode = PerchHARepoAuditCommand.run(
            arguments: arguments,
            standardOutput: { output.append($0) },
            standardError: { errors.append($0) }
        )
        return RepoAuditSmokeResult(
            exitCode: exitCode,
            output: output.joined(separator: "\n"),
            error: errors.joined()
        )
    }

    private static func runGit(_ arguments: [String], in directory: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["git", "-C", directory.path] + arguments
        let errors = Pipe()
        process.standardError = errors
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let message = String(data: errors.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? "git failed"
            throw SmokeFailure("git \(arguments.joined(separator: " ")) failed: \(message)")
        }
    }

    private static func verifyCoalescing() async throws {
        let coalescer = RequestCoalescer<String, Int>()
        let counter = Counter()
        let gate = Gate()

        let first = Task {
            try await coalescer.value(for: "same") {
                _ = await counter.increment()
                await gate.wait()
                return 42
            }
        }

        try await spinUntil("coalescer has first task") {
            await coalescer.activeRequestCount() == 1
        }

        let second = Task {
            try await coalescer.value(for: "same") {
                _ = await counter.increment()
                await gate.wait()
                return 13
            }
        }
        try await spinUntil("coalescer has second caller") {
            await coalescer.coalescedWaiterCount() == 1
        }

        _ = await gate.open()
        let values = try await [first.value, second.value]

        try expect(values == [42, 42], "coalesced callers share the first result")
        try await expectAsync(await counter.value == 1, "coalesced operation runs once")
        try await expectAsync(await coalescer.coalescedWaiterCount() == 0, "coalesced waiter count returns to zero")

        let failing = RequestCoalescer<String, Int>()
        let failures = Counter()
        let failureGate = Gate()
        let firstFailure = Task {
            try await failing.value(for: "same") {
                _ = await failures.increment()
                await failureGate.wait()
                throw SmokeFailure("planned coalescer failure")
            }
        }
        try await spinUntil("coalescer has failing task") {
            await failing.activeRequestCount() == 1
        }
        let secondFailure = Task {
            try await failing.value(for: "same") {
                _ = await failures.increment()
                return 7
            }
        }
        try await spinUntil("coalescer has second failing caller") {
            await failing.coalescedWaiterCount() == 1
        }
        _ = await failureGate.open()

        do {
            _ = try await firstFailure.value
            throw SmokeFailure("first coalesced failure unexpectedly succeeded")
        } catch is SmokeFailure {}

        do {
            _ = try await secondFailure.value
            throw SmokeFailure("second coalesced failure unexpectedly succeeded")
        } catch is SmokeFailure {}

        try await expectAsync(await failing.activeRequestCount() == 0, "failed coalesced request is cleared")
        try await expectAsync(await failing.coalescedWaiterCount() == 0, "failed coalesced waiter count returns to zero")

        let retry = try await failing.value(for: "same") {
            _ = await failures.increment()
            return 99
        }
        try expect(retry == 99, "coalescer retries after failure")
    }

    private static func verifyTestClock() async throws {
        let clock = TestPerchClock()

        try await expectAsync(await clock.now() == PerchInstant(nanosecondsSinceStart: 0), "test clock starts at zero")
        _ = await clock.advance(by: .seconds(3))
        try await expectAsync(await clock.now() == PerchInstant(nanosecondsSinceStart: 3_000_000_000), "test clock advances")

        let wakeDeadline = PerchInstant(nanosecondsSinceStart: 5_000_000_000)
        let sleeper = Task {
            try await clock.sleep(until: wakeDeadline)
        }
        try await spinUntil("test clock has sleeper") {
            await clock.sleepingTaskCount() == 1
        }
        _ = await clock.advance(by: .seconds(2))
        let wakeInstant = try await sleeper.value
        try expect(wakeInstant == wakeDeadline, "test clock wakes sleepers on advance")

        let cancelled = Task {
            try await clock.sleep(until: PerchInstant(nanosecondsSinceStart: 10_000_000_000))
        }
        try await spinUntil("test clock has cancellable sleeper") {
            await clock.sleepingTaskCount() == 1
        }
        cancelled.cancel()
        do {
            _ = try await cancelled.value
            throw SmokeFailure("test clock cancelled sleeper unexpectedly completed")
        } catch is CancellationError {
            try await expectAsync(await clock.sleepingTaskCount() == 0, "test clock removes cancelled sleepers")
        }
    }

    private static func verifyMirrorAndFakeHA() async throws {
        let server = try FakeHARESTServer()
        server.start()
        defer {
            server.stop()
        }

        let environment = HAMirrorEnvironment(
            primaryURL: server.baseURL,
            fallbackURL: nil,
            token: "fake-token",
            user: nil,
            password: nil
        )
        let fixtures = try await HAMirrorCaptureService().capture(environment: environment)

        try expect(fixtures.api.path == "/api/", "mirror captures trailing slash API path")
        try expect(fixtures.api.statusCode == 200, "mirror captures API status")
        try expect(fixtures.api.bodyText == #"{"message":"API running."}"#, "mirror captures API body")
        try expect(fixtures.states.statusCode == 200, "mirror captures states status")
        try expect(fixtures.states.bodyText == #"[]"#, "mirror captures states body")

        try await spinUntil("FakeHA journals mirror requests") {
            await server.journal.snapshot().count >= 2
        }
        let entries = await server.journal.snapshot()
        try expect(entries.map { $0.path }.contains("/api/"), "FakeHA journals API path")
        try expect(entries.map { $0.path }.contains("/api/states"), "FakeHA journals states path")
        try expect(entries.allSatisfy { $0.headers["authorization"] == "<redacted>" }, "FakeHA redacts authorization headers")

        let unauthorizedEnvironment = HAMirrorEnvironment(
            primaryURL: server.baseURL,
            fallbackURL: nil,
            token: "wrong-token",
            user: nil,
            password: nil
        )
        do {
            _ = try await HAMirrorCaptureService().capture(environment: unauthorizedEnvironment)
            throw SmokeFailure("mirror accepted unauthorized Home Assistant response")
        } catch let error as HAMirrorCaptureError {
            try expect(
                error == .unexpectedStatus(path: "/api/", statusCode: 401),
                "mirror rejects unauthorized Home Assistant response"
            )
            try expect(!error.description.contains("wrong-token"), "mirror status errors do not leak tokens")
        }

        let fixtureDirectory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("perchha-smoke-fixtures-\(UUID().uuidString)", isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: fixtureDirectory)
        }
        let written = try HAMirrorFixtureWriter().write(fixtures, to: fixtureDirectory)
        try expect(written.count == 3, "mirror writer writes all fixture files")
        for file in ["api.json", "states.json", "manifest.json"] {
            try expect(FileManager.default.fileExists(atPath: fixtureDirectory.appendingPathComponent(file).path), "fixture file exists: \(file)")
        }
        _ = try HAMirrorFixtureVerifier().verify(directory: fixtureDirectory)

        let loaded = try FakeHAFixtures.load(from: fixtureDirectory)
        try expect(loaded.apiBody == #"{"message":"API running."}"#, "FakeHA loads API fixture body")
        try expect(loaded.statesBody == #"[]"#, "FakeHA loads states fixture body")

        let auth = FakeHAWebSocketAuth()
        try expect(auth.authRequiredMessage == #"{"type":"auth_required","ha_version":"fake-ha"}"#, "FakeHA exposes auth_required")
        try expect(
            auth.authenticate(clientMessage: #"{"type":"auth","access_token":"fake-token"}"#) == #"{"type":"auth_ok","ha_version":"fake-ha"}"#,
            "FakeHA accepts valid WebSocket auth"
        )
        try expect(
            auth.authenticate(clientMessage: #"{"type":"auth","access_token":"wrong"}"#) == #"{"type":"auth_invalid","message":"Invalid access token"}"#,
            "FakeHA rejects invalid WebSocket auth"
        )

        let webSocketMirrorServer = try FakeHAWebSocketServer(
            fixtures: FakeHAFixtures(
                apiBody: #"{"message":"API running."}"#,
                statesBody: #"[]"#,
                stateChangedEventBody: #"{"entity_id":"sensor.office_temperature","state":"22.0","attributes":{"friendly_name":"Office temperature","unit_of_measurement":"°C"}}"#,
                entityRegistryDisplayBody: #"{"entities":[{"ei":"sensor.office_temperature","en":"Office temperature","ai":"office"}]}"#
            )
        )
        webSocketMirrorServer.start()
        defer {
            webSocketMirrorServer.stop()
        }
        let webSocketEvidence = try await HAMirrorCaptureService().captureOptimizedWebSocketEvidence(
            environment: HAMirrorEnvironment(
                primaryURL: webSocketMirrorServer.baseURL,
                fallbackURL: nil,
                token: "fake-token",
                user: nil,
                password: nil
            ),
            captureSubscribeEventKeys: true
        )
        try expect(webSocketEvidence.entityRegistryDisplayList.available, "mirror captures entity registry display-list evidence")
        try expect(webSocketEvidence.subscribeEntities.available, "mirror captures subscribe_entities evidence")
        try expect(webSocketEvidence.subscribeEntities.eventKeys == ["a"], "mirror records subscribe_entities event shape only")

        let silentWebSocketMirrorServer = try FakeHAWebSocketServer(mode: .silentAfterAuth)
        silentWebSocketMirrorServer.start()
        defer {
            silentWebSocketMirrorServer.stop()
        }
        do {
            _ = try await HAMirrorCaptureService(webSocketReceiveTimeoutNanoseconds: 50_000_000).captureOptimizedWebSocketEvidence(
                environment: HAMirrorEnvironment(
                    primaryURL: silentWebSocketMirrorServer.baseURL,
                    fallbackURL: nil,
                    token: "fake-token",
                    user: nil,
                    password: nil
                )
            )
            throw SmokeFailure("mirror WebSocket evidence capture did not time out")
        } catch HAMirrorCaptureError.webSocketTimeout {
            try expect(true, "mirror WebSocket evidence capture times out explicitly")
        }
    }

    private static func verifyHAMirrorServeCLI() async throws {
        let fixtureDirectory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("perchha-smoke-serve-\(UUID().uuidString)", isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: fixtureDirectory)
        }

        let fixtureSet = HAMirrorFixtureSet(
            api: HAMirrorCapturedEndpoint(
                method: "GET",
                path: "/api/",
                statusCode: 200,
                headers: [:],
                bodyText: #"{"message":"API running."}"#
            ),
            states: HAMirrorCapturedEndpoint(
                method: "GET",
                path: "/api/states",
                statusCode: 200,
                headers: [:],
                bodyText: #"[{"entity_id":"sensor.entity_001","state":"21.4","attributes":{"friendly_name":"<redacted>","unit_of_measurement":"°C"}}]"#
            )
        )
        _ = try HAMirrorFixtureWriter().write(fixtureSet, to: fixtureDirectory)

        let serveProcess = try launchHAMirrorServe(fixtures: fixtureDirectory, pathPrefix: "/ha")
        defer {
            stopProcess(serveProcess.process)
            try? FileManager.default.removeItem(at: serveProcess.outputURL)
        }

        let output = try await waitForServeOutput(serveProcess)
        let restURL = try parseServeURL(label: "REST", output: output)
        let webSocketURL = try parseServeURL(label: "WebSocket", output: output)
        try expect(restURL.path == "/ha", "hamirror serve preserves requested path prefix in REST base URL")
        try expect(webSocketURL.path == "/ha/api/websocket", "hamirror serve preserves requested path prefix in WebSocket URL")

        let states = try await waitForGET(path: "/api/states", baseURL: restURL)
        try expect(states.status == 200, "hamirror serve replays mirrored states over REST")
        try expect(states.body.contains("sensor.entity_001"), "hamirror serve returns mirrored state payload")

        let task = URLSession.shared.webSocketTask(with: webSocketURL)
        task.resume()
        defer {
            task.cancel(with: .goingAway, reason: nil)
        }
        let authRequired = try await receiveWebSocketString(task)
        try expect(authRequired == #"{"type":"auth_required","ha_version":"fake-ha"}"#, "hamirror serve replays FakeHA WebSocket auth handshake")
        try await task.send(.string(#"{"type":"auth","access_token":"fake-token"}"#))
        let authOK = try await receiveWebSocketString(task)
        try expect(authOK == #"{"type":"auth_ok","ha_version":"fake-ha"}"#, "hamirror serve accepts configured WebSocket token")
        try await task.send(.string(#"{"id":5,"type":"config/entity_registry/list_for_display"}"#))
        let result = try await receiveWebSocketString(task)
        try expect(result.contains(#""success":true"#), "hamirror serve synthesizes mirrored display-list results when WebSocket evidence is absent")
        try expect(result.contains(#""ei":"sensor.entity_001""#), "hamirror serve preserves mirrored entity ID in synthesized display-list results")
        try expect(result.contains(#""en":"<redacted>""#), "hamirror serve preserves sanitized mirrored friendly name in synthesized display-list results")
    }

    private static func verifyHAMirrorCaptureCLI() async throws {
        let server = try FakeHARESTServer()
        server.start()
        defer {
            server.stop()
        }

        let envURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("perchha-smoke-hamirror-\(UUID().uuidString).env", isDirectory: false)
        let outputDirectory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
            .appendingPathComponent("Fixtures/private/hamirror-smoke-\(UUID().uuidString)", isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: envURL)
            try? FileManager.default.removeItem(at: outputDirectory)
        }

        try """
        url=\(server.baseURL.absoluteString)
        """.write(to: envURL, atomically: true, encoding: .utf8)

        let executable = try toolExecutable(named: "hamirror")
        let output = try runHAMirrorProcess(
            executable: executable,
            arguments: [
                "capture",
                "--output", outputDirectory.path,
                "--write"
            ],
            environment: [
                HAMirrorEnvironment.environmentFileEnvironmentKey: envURL.path,
                HAMirrorEnvironment.tokenEnvironmentKey: "fake-token"
            ]
        )

        try expect(output.terminationStatus == 0, "hamirror capture CLI writes fixture set successfully (\(output.text))")
        try expect(output.text.contains("fixture set verified: \(outputDirectory.path)"), "hamirror capture CLI verifies written fixtures")
        try expect(output.text.contains("fixture output ignored by git: \(outputDirectory.path)"), "hamirror capture CLI verifies ignored private fixture output")
        for file in ["api.json", "states.json", "manifest.json"] {
            try expect(FileManager.default.fileExists(atPath: outputDirectory.appendingPathComponent(file).path), "hamirror capture CLI wrote \(file)")
        }
    }

    private static func verifyHAMirrorDoctorCLIUsesExportedOverrides() async throws {
        let server = try FakeHARESTServer()
        server.start()
        defer {
            server.stop()
        }

        let envURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("perchha-smoke-hamirror-doctor-\(UUID().uuidString).env", isDirectory: false)
        defer {
            try? FileManager.default.removeItem(at: envURL)
        }

        try """
        url=\(server.baseURL.absoluteString)
        """.write(to: envURL, atomically: true, encoding: .utf8)

        let executable = try toolExecutable(named: "hamirror")
        let output = try runHAMirrorProcess(
            executable: executable,
            arguments: [
                "doctor",
                "--json"
            ],
            environment: [
                HAMirrorEnvironment.environmentFileEnvironmentKey: envURL.path,
                HAMirrorEnvironment.tokenEnvironmentKey: "fake-token",
                HAMirrorEnvironment.oauthClientIDEnvironmentKey: "https://perchha.dev/app",
                HAMirrorEnvironment.oauthRedirectURIEnvironmentKey: "perchha://auth"
            ]
        )

        try expect(output.terminationStatus == 0, "hamirror doctor CLI accepts exported override readiness path")
        let diagnostic = try JSONDecoder().decode(
            HAMirrorEnvironmentReadinessDiagnostic.self,
            from: Data(output.text.utf8)
        )
        try expect(diagnostic.capture == .ready, "hamirror doctor CLI marks capture ready from exported token override")
        try expect(diagnostic.oauthCheck == .ready, "hamirror doctor CLI marks oauth check ready from exported overrides")
        try expect(diagnostic.token == .present, "hamirror doctor CLI reports present token without exposing it")
        try expect(diagnostic.oauthClientID == .present, "hamirror doctor CLI reports present OAuth client ID override")
        try expect(diagnostic.oauthRedirectURI == .present, "hamirror doctor CLI reports present OAuth redirect URI override")
    }

    private static func verifyHAMirrorDoctorProbeReportsLiveGuidance() async throws {
        let fallbackServer = try FakeHARESTServer()
        fallbackServer.start()
        defer {
            fallbackServer.stop()
        }

        let envURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("perchha-smoke-hamirror-doctor-probe-\(UUID().uuidString).env", isDirectory: false)
        defer {
            try? FileManager.default.removeItem(at: envURL)
        }

        try """
        url=http://127.0.0.1:1
        url2=\(fallbackServer.baseURL.absoluteString)
        token=wrong-token
        """.write(to: envURL, atomically: true, encoding: .utf8)

        let executable = try toolExecutable(named: "hamirror")
        let output = try runHAMirrorProcess(
            executable: executable,
            arguments: [
                "doctor",
                "--env", envURL.path,
                "--probe"
            ],
            environment: [:]
        )

        try expect(output.terminationStatus == 0, "hamirror doctor --probe succeeds without strict mode")
        try expect(
            output.text.contains("- Primary /api/: unavailable - Home Assistant request for /api/ failed: Could not connect to the server."),
            "hamirror doctor --probe reports primary transport failure"
        )
        try expect(
            output.text.contains("hint: Verify the Home Assistant URL, local network or VPN reachability, DNS, and that the instance is running."),
            "hamirror doctor --probe suggests transport remediation"
        )
        try expect(
            output.text.contains("- Fallback /api/: blocked - Home Assistant returned HTTP 401 for /api/"),
            "hamirror doctor --probe reports fallback authorization failure"
        )
        try expect(
            output.text.contains("hint: Refresh the long-lived access token and verify it belongs to this Home Assistant instance."),
            "hamirror doctor --probe suggests token remediation"
        )
        try expect(
            !output.text.contains("swift run hamirror capture --env"),
            "hamirror doctor --probe omits capture suggestion when no live endpoint is ready"
        )
        try expect(
            !output.text.contains(fallbackServer.baseURL.absoluteString),
            "hamirror doctor --probe keeps live endpoint URLs redacted"
        )

        let strictOutput = try runHAMirrorProcess(
            executable: executable,
            arguments: [
                "doctor",
                "--env", envURL.path,
                "--probe",
                "--strict"
            ],
            environment: [:]
        )

        try expect(strictOutput.terminationStatus != 0, "hamirror doctor --probe --strict fails when no endpoint is ready")
        try expect(
            strictOutput.text.contains("mirror live probe is not ready"),
            "hamirror doctor --probe --strict reports live probe failure precisely"
        )
        try expect(
            strictOutput.text.contains("primary unavailable: Home Assistant request for /api/ failed: Could not connect to the server. Hint: Verify the Home Assistant URL, local network or VPN reachability, DNS, and that the instance is running."),
            "hamirror doctor --probe --strict labels the primary failure and carries guidance"
        )
        try expect(
            strictOutput.text.contains("fallback blocked: Home Assistant returned HTTP 401 for /api/ Hint: Refresh the long-lived access token and verify it belongs to this Home Assistant instance."),
            "hamirror doctor --probe --strict labels the fallback failure and carries guidance"
        )

        let jsonOutput = try runHAMirrorProcess(
            executable: executable,
            arguments: [
                "doctor",
                "--env", envURL.path,
                "--probe",
                "--json"
            ],
            environment: [:]
        )

        try expect(jsonOutput.terminationStatus == 0, "hamirror doctor --probe --json succeeds")
        guard let object = try JSONSerialization.jsonObject(with: Data(jsonOutput.text.utf8)) as? [String: Any] else {
            throw SmokeFailure("hamirror doctor --probe --json emitted a non-object payload")
        }
        guard let probe = object["probe"] as? [String: Any] else {
            throw SmokeFailure("hamirror doctor --probe --json omitted the probe object")
        }
        guard let primary = probe["primary"] as? [String: Any] else {
            throw SmokeFailure("hamirror doctor --probe --json omitted the primary probe object")
        }
        guard let fallback = probe["fallback"] as? [String: Any] else {
            throw SmokeFailure("hamirror doctor --probe --json omitted the fallback probe object")
        }
        try expect(primary["guidance"] as? String == "Verify the Home Assistant URL, local network or VPN reachability, DNS, and that the instance is running.", "hamirror doctor --probe --json exports primary guidance")
        try expect(fallback["guidance"] as? String == "Refresh the long-lived access token and verify it belongs to this Home Assistant instance.", "hamirror doctor --probe --json exports fallback guidance")
        let suggestedCommands = probe["ready"] as? Bool == false ? (object["suggestedCommands"] as? [String] ?? []) : []
        try expect(suggestedCommands.isEmpty, "hamirror doctor --probe --json omits capture suggestion when no live endpoint is ready")
    }

    private static func verifyHAMirrorOAuthCheckReportsMissingConfigurationGuidance() async throws {
        let server = try FakeHARESTServer()
        server.start()
        defer {
            server.stop()
        }

        let envURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("perchha-smoke-hamirror-oauth-check-\(UUID().uuidString).env", isDirectory: false)
        defer {
            try? FileManager.default.removeItem(at: envURL)
        }

        try """
        url=\(server.baseURL.absoluteString)
        user=owner@example.invalid
        password=secret-password
        """.write(to: envURL, atomically: true, encoding: .utf8)

        let executable = try toolExecutable(named: "hamirror")
        let output = try runHAMirrorProcess(
            executable: executable,
            arguments: [
                "oauth-check",
                "--env", envURL.path
            ],
            environment: [:]
        )

        try expect(output.terminationStatus != 0, "hamirror oauth-check CLI fails when OAuth config is missing")
        try expect(
            output.text.contains("OAuth client website check is not ready"),
            "hamirror oauth-check CLI reports OAuth-specific readiness failure"
        )
        try expect(
            output.text.contains("PERCHHA_OAUTH_CLIENT_ID and PERCHHA_OAUTH_REDIRECT_URI"),
            "hamirror oauth-check CLI explains required OAuth configuration"
        )
        try expect(
            output.text.contains("hamirror oauth-check --env \(envURL.path)"),
            "hamirror oauth-check CLI suggests the rerun command with the explicit env path"
        )
        try expect(!output.text.contains("secret-password"), "hamirror oauth-check CLI does not leak environment secrets")
        try expect(!output.text.contains("owner@example.invalid"), "hamirror oauth-check CLI keeps credential hints redacted")
    }

    private static func runHAMirrorProcess(
        executable: URL,
        arguments: [String],
        environment: [String: String]
    ) throws -> (terminationStatus: Int32, text: String) {
        try runProcess(
            executable: executable,
            arguments: arguments,
            environment: environment
        )
    }

    private static func runProcess(
        executable: URL,
        arguments: [String],
        environment: [String: String]
    ) throws -> (terminationStatus: Int32, text: String) {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        process.environment = ProcessInfo.processInfo.environment.merging(environment) { _, new in new }
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        process.waitUntilExit()
        let text = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        return (process.terminationStatus, text)
    }

    private static func verifyFakeHAConcurrentStartup() throws {
        var restServers: [FakeHARESTServer] = []
        var webSocketServers: [FakeHAWebSocketServer] = []
        defer {
            for server in restServers {
                server.stop()
            }
            for server in webSocketServers {
                server.stop()
            }
        }

        for _ in 0..<12 {
            let rest = try FakeHARESTServer()
            rest.start()
            restServers.append(rest)

            let webSocket = try FakeHAWebSocketServer()
            webSocket.start()
            webSocketServers.append(webSocket)
        }

        let restPorts = Set(restServers.compactMap { $0.baseURL.port })
        let webSocketPorts = Set(webSocketServers.compactMap { $0.baseURL.port })
        try expect(restPorts.count == restServers.count, "FakeHA REST servers start on distinct ports")
        try expect(webSocketPorts.count == webSocketServers.count, "FakeHA WebSocket servers start on distinct ports")
        try expect(restPorts.isDisjoint(with: webSocketPorts), "FakeHA REST and WebSocket ports do not collide")
    }

    private static func launchHAMirrorServe(fixtures: URL, pathPrefix: String) throws -> ServeProcessHandle {
        let executable = try toolExecutable(named: "hamirror")

        let outputURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("perchha-smoke-serve-log-\(UUID().uuidString).txt", isDirectory: false)
        FileManager.default.createFile(atPath: outputURL.path, contents: Data())
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = [
            "-c",
            [
                shellQuoted(executable.path),
                "serve",
                "--fixtures", shellQuoted(fixtures.path),
                "--token", "fake-token",
                "--path-prefix", shellQuoted(pathPrefix),
                ">", shellQuoted(outputURL.path),
                "2>&1"
            ].joined(separator: " ")
        ]
        try process.run()
        return ServeProcessHandle(process: process, outputURL: outputURL)
    }

    private static func stopProcess(_ process: Process) {
        guard process.isRunning else {
            return
        }
        process.terminate()
        process.waitUntilExit()
    }

    private static func launchStaticFileServer(
        directory: URL,
        port: UInt16,
        logURL: URL
    ) throws -> Process {
        FileManager.default.createFile(atPath: logURL.path, contents: Data())
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = [
            "-c",
            [
                shellQuoted("/usr/bin/python3"),
                "-m", "http.server",
                String(port),
                "--bind", "127.0.0.1",
                "--directory", shellQuoted(directory.path),
                ">", shellQuoted(logURL.path),
                "2>&1"
            ].joined(separator: " ")
        ]
        try process.run()
        return process
    }

    private static func waitForServeOutput(_ handle: ServeProcessHandle) async throws -> String {
        for _ in 0..<150 {
            let output = (try? String(contentsOf: handle.outputURL, encoding: .utf8)) ?? ""
            if output.contains("- REST: http://") && output.contains("- WebSocket: ws://") {
                return output
            }
            if !handle.process.isRunning, !output.isEmpty {
                throw SmokeFailure("hamirror serve exited before announcing URLs: \(output.trimmingCharacters(in: .whitespacesAndNewlines))")
            }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        throw SmokeFailure("hamirror serve reports REST and WebSocket URLs")
    }

    private static func waitForStaticFileServer(
        url: URL,
        process: Process,
        logURL: URL
    ) async throws {
        for _ in 0..<150 {
            let response = try? await URLSession.shared.data(from: url)
            if let response,
               let http = response.1 as? HTTPURLResponse,
               (200...299).contains(http.statusCode) {
                return
            }
            if !process.isRunning {
                let output = (try? String(contentsOf: logURL, encoding: .utf8)) ?? ""
                throw SmokeFailure("static file server exited before serving OAuth site: \(output.trimmingCharacters(in: .whitespacesAndNewlines))")
            }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        throw SmokeFailure("static file server serves published OAuth client website")
    }

    private static func availableLoopbackPort() throws -> UInt16 {
        let socketDescriptor = socket(AF_INET, SOCK_STREAM, 0)
        guard socketDescriptor >= 0 else {
            throw SmokeFailure("failed to allocate loopback socket")
        }
        defer {
            Darwin.close(socketDescriptor)
        }

        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.stride)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = in_port_t(0).bigEndian
        address.sin_addr = in_addr(s_addr: inet_addr("127.0.0.1"))

        let bindResult = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.bind(socketDescriptor, $0, socklen_t(MemoryLayout<sockaddr_in>.stride))
            }
        }
        guard bindResult == 0 else {
            throw SmokeFailure("failed to bind loopback socket")
        }

        var boundAddress = sockaddr_in()
        var boundLength = socklen_t(MemoryLayout<sockaddr_in>.stride)
        let nameResult = withUnsafeMutablePointer(to: &boundAddress) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.getsockname(socketDescriptor, $0, &boundLength)
            }
        }
        guard nameResult == 0 else {
            throw SmokeFailure("failed to read loopback socket port")
        }
        return UInt16(bigEndian: boundAddress.sin_port)
    }

    private static func shellQuoted(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\"'\"'") + "'"
    }

    private static func toolExecutable(named name: String) throws -> URL {
        let currentDirectory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
        let sibling = URL(fileURLWithPath: CommandLine.arguments[0])
            .deletingLastPathComponent()
            .appendingPathComponent(name, isDirectory: false)
        let candidates = [
            currentDirectory.appendingPathComponent(".build/debug/\(name)", isDirectory: false),
            currentDirectory.appendingPathComponent(".build/arm64-apple-macosx/debug/\(name)", isDirectory: false),
            sibling
        ]
        for candidate in candidates where FileManager.default.isExecutableFile(atPath: candidate.path) {
            return candidate
        }
        let buildDirectory = currentDirectory.appendingPathComponent(".build", isDirectory: true)
        if let enumerator = FileManager.default.enumerator(at: buildDirectory, includingPropertiesForKeys: nil) {
            for case let url as URL in enumerator where url.lastPathComponent == name {
                if FileManager.default.isExecutableFile(atPath: url.path) {
                    return url
                }
            }
        }
        throw SmokeFailure("\(name) executable is not available in .build")
    }

    private static func parseServeURL(label: String, output: String) throws -> URL {
        let prefix = "- \(label): "
        guard let line = output.split(separator: "\n").map(String.init).first(where: { $0.hasPrefix(prefix) }) else {
            throw SmokeFailure("hamirror serve did not print \(label) URL")
        }
        guard let url = URL(string: String(line.dropFirst(prefix.count))) else {
            throw SmokeFailure("hamirror serve printed invalid \(label) URL")
        }
        return url
    }

    private static func get(path: String, baseURL: URL) async throws -> (status: Int, body: String) {
        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)
        components?.path = appendingPath(path, to: baseURL.path)
        let url = components?.url ?? baseURL
        var request = URLRequest(url: url)
        request.setValue("Bearer fake-token", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw SmokeFailure("hamirror serve returned a non-HTTP response")
        }
        return (http.statusCode, String(data: data, encoding: .utf8) ?? "")
    }

    private static func waitForGET(path: String, baseURL: URL) async throws -> (status: Int, body: String) {
        for _ in 0..<150 {
            do {
                return try await get(path: path, baseURL: baseURL)
            } catch {
                try await Task.sleep(nanoseconds: 20_000_000)
            }
        }
        return try await get(path: path, baseURL: baseURL)
    }

    private static func receiveWebSocketString(_ task: URLSessionWebSocketTask) async throws -> String {
        switch try await task.receive() {
        case let .string(text):
            return text
        case let .data(data):
            return String(data: data, encoding: .utf8) ?? ""
        @unknown default:
            throw SmokeFailure("hamirror serve returned an unknown WebSocket message")
        }
    }

    private static func appendingPath(_ path: String, to basePath: String) -> String {
        let normalizedBase = basePath == "/" ? "" : basePath.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let prefix = normalizedBase.isEmpty ? "" : "/\(normalizedBase)"
        return "\(prefix)\(path)"
    }

    private static func verifyFakeHACoalescedWebSocketReads() throws {
        let server = try FakeHAWebSocketServer(
            fixtures: FakeHAFixtures(
                apiBody: #"{"message":"API running."}"#,
                statesBody: #"[{"entity_id":"sensor.office_temperature","state":"21.4","attributes":{"friendly_name":"Office temperature","unit_of_measurement":"°C"}}]"#
            )
        )
        server.start()
        defer {
            server.stop()
        }

        let probe = FakeHARawWebSocketProbe()
        let coalescedAuth = try probe.authenticateWithCoalescedUpgrade(baseURL: server.baseURL)
        try expect(coalescedAuth.range(of: Data(#""type":"auth_ok""#.utf8)) != nil, "FakeHA consumes auth frame coalesced with HTTP upgrade")

        let coalescedCommands = try probe.authenticateThenSendCoalescedCommands(baseURL: server.baseURL)
        try expect(coalescedCommands.range(of: Data(#""id":1"#.utf8)) != nil, "FakeHA consumes first coalesced WebSocket command")
        try expect(coalescedCommands.range(of: Data(#""id":2"#.utf8)) != nil, "FakeHA consumes second coalesced WebSocket command")
    }

    private static func verifyHAClientContract() async throws {
        let oauthTransport = SmokeHARESTTransport(
            responses: [
                HARESTResponse(
                    statusCode: 200,
                    headers: ["Content-Type": "text/html"],
                    body: Data(#"<link rel="redirect_uri" href="perchha://auth">"#.utf8)
                )
            ]
        )
        let oauthCheck = await HomeAssistantClient(transport: oauthTransport).verifyOAuthClientWebsite(
            clientID: "https://perchha.dev/app",
            redirectURI: "perchha://auth"
        )
        try expect(
            oauthCheck == .success(
                HAOAuthClientWebsiteCheck(
                    clientID: "https://perchha.dev/app",
                    redirectURI: "perchha://auth",
                    websiteFetched: true,
                    redirectURIDeclared: true
                )
            ),
            "HA OAuth client website readiness check accepts native redirect declaration"
        )

        let fixtures = FakeHAFixtures(
            apiBody: #"{"message":"API running."}"#,
            statesBody: #"[{"entity_id":"sensor.office_temperature","state":"21.4","attributes":{"friendly_name":"Office temperature","unit_of_measurement":"°C"}},{"entity_id":"binary_sensor.window","state":"off","attributes":{}}]"#,
            historyBody: """
            [[
              {"entity_id":"sensor.office_temperature","state":"21.4","last_changed":"2026-06-27T10:30:00+00:00"},
              {"state":"22.0","last_changed":"2026-06-27T11:00:00+00:00"},
              {"entity_id":"sensor.office_temperature","state":"22.5","last_updated":"2026-06-27T11:30:00+00:00"}
            ]]
            """
        )
        let server = try FakeHARESTServer(fixtures: fixtures)
        server.start()
        defer {
            server.stop()
        }

        let client = HomeAssistantClient()
        let input = HAConnectionInput(
            endpoint: HAEndpoint(primaryURL: server.baseURL, fallbackURL: nil),
            token: "fake-token"
        )

        let connectionResult = await client.checkRESTConnection(input)
        try expect(
            connectionResult == .success(HARESTCheck(message: "API running.")),
            "HA client REST smoke succeeds against FakeHA"
        )
        let statesResult = await client.states(input)
        try expect(
            statesResult == .success([
                EntityState(id: "sensor.office_temperature", name: "Office temperature", state: "21.4", unit: "°C"),
                EntityState(id: "binary_sensor.window", name: "binary_sensor.window", state: "off", unit: nil)
            ]),
            "HA client maps FakeHA states"
        )
        let historyResult = await client.history(
            input,
            entityID: "sensor.office_temperature",
            range: .hour,
            end: try historyDate("2026-06-27T12:00:00+00:00")
        )
        let expectedHistory = HistorySeries(
            entityID: "sensor.office_temperature",
            range: .hour,
            samples: [
                HistorySample(timestamp: try historyDate("2026-06-27T10:30:00+00:00"), state: "21.4", numericValue: 21.4),
                HistorySample(timestamp: try historyDate("2026-06-27T11:00:00+00:00"), state: "22.0", numericValue: 22.0),
                HistorySample(timestamp: try historyDate("2026-06-27T11:30:00+00:00"), state: "22.5", numericValue: 22.5)
            ]
        )
        try expect(
            historyResult == .success(expectedHistory),
            "HA client maps REST history samples"
        )

        let badInput = HAConnectionInput(
            endpoint: HAEndpoint(primaryURL: server.baseURL, fallbackURL: nil),
            token: "wrong-token"
        )
        let authFailure = await client.checkRESTConnection(badInput)
        try expect(
            authFailure == .failure(.authentication),
            "HA client reports auth failure"
        )

        try await spinUntil("FakeHA journals HA client requests") {
            await server.journal.snapshot().count >= 4
        }
        let entries = await server.journal.snapshot()
        try expect(entries.contains { $0.path == "/api/" }, "HA client hits API smoke path")
        try expect(entries.contains { $0.path == "/api/states" }, "HA client hits states path")
        try expect(entries.contains { $0.path.hasPrefix("/api/history/period/") }, "HA client hits history path")
        try expect(entries.contains { $0.path.contains("filter_entity_id=sensor.office_temperature") }, "HA client filters history entity")
        try expect(entries.allSatisfy { $0.headers["authorization"] == "<redacted>" }, "HA client requests are journaled redacted")

        let tlsIdentity = try FakeHASelfSignedIdentity()
        let tlsServer = try FakeHARESTServer(
            fixtures: FakeHAFixtures(
                apiBody: #"{"message":"API running."}"#,
                statesBody: #"[]"#
            ),
            tlsIdentity: tlsIdentity.identity
        )
        tlsServer.start()
        defer {
            tlsServer.stop()
        }
        let strictTLSInput = HAConnectionInput(
            endpoint: HAEndpoint(primaryURL: tlsServer.baseURL, fallbackURL: nil),
            token: "fake-token"
        )
        let allowedTLSInput = HAConnectionInput(
            endpoint: HAEndpoint(primaryURL: tlsServer.baseURL, fallbackURL: nil),
            token: "fake-token",
            serverTrustPolicy: HAServerTrustPolicy(allowedSelfSignedCertificateHosts: ["127.0.0.1"])
        )
        let strictTLSResult = await client.checkRESTConnection(strictTLSInput)
        let allowedTLSResult = await client.checkRESTConnection(allowedTLSInput)
        try expect(
            strictTLSResult == .failure(.tlsRejected(host: "127.0.0.1")),
            "HA client rejects self-signed REST by default"
        )
        try expect(
            allowedTLSResult == .success(HARESTCheck(message: "API running.")),
            "HA client accepts explicitly allowed self-signed REST host: \(String(describing: allowedTLSResult))"
        )
    }

    private static func verifyHAWebSocketContract() async throws {
        let fixtures = FakeHAFixtures(
            apiBody: #"{"message":"API running."}"#,
            statesBody: #"[{"entity_id":"sensor.office_temperature","state":"21.4","attributes":{"friendly_name":"Office temperature","unit_of_measurement":"°C"}}]"#
        )
        let server = try FakeHAWebSocketServer(fixtures: fixtures)
        server.start()
        defer {
            server.stop()
        }

        let client = HomeAssistantClient()
        let input = HAConnectionInput(
            endpoint: HAEndpoint(primaryURL: server.baseURL, fallbackURL: nil),
            token: "fake-token"
        )
        let auth = await client.checkWebSocketConnection(input)
        try expect(auth == .success(HAWebSocketCheck(haVersion: "fake-ha")), "HA client WebSocket auth succeeds against FakeHA")
        let states = await client.webSocketStates(input)
        try expect(
            states == .success([
                EntityState(id: "sensor.office_temperature", name: "Office temperature", state: "21.4", unit: "°C")
            ]),
            "HA client WebSocket get_states maps FakeHA states"
        )

        let historyFixtures = FakeHAFixtures(
            apiBody: #"{"message":"API running."}"#,
            statesBody: #"[]"#,
            recorderStatisticsBody: """
            {
              "sensor.office_temperature": [
                {"start":1782554400000,"end":1782558000000,"state":21.4},
                {"start":1782558000000,"end":1782561600000,"mean":22.0}
              ]
            }
            """
        )
        let historyServer = try FakeHAWebSocketServer(fixtures: historyFixtures)
        historyServer.start()
        defer {
            historyServer.stop()
        }
        let historyInput = HAConnectionInput(
            endpoint: HAEndpoint(primaryURL: historyServer.baseURL, fallbackURL: nil),
            token: "fake-token"
        )
        let recorderHistory = await client.history(
            historyInput,
            entityID: "sensor.office_temperature",
            range: .week,
            end: try historyDate("2026-06-27T12:00:00+00:00")
        )
        let expectedRecorderHistory = HistorySeries(
            entityID: "sensor.office_temperature",
            range: .week,
            samples: [
                HistorySample(timestamp: try historyDate("2026-06-27T10:00:00+00:00"), state: "21.4", numericValue: 21.4),
                HistorySample(timestamp: try historyDate("2026-06-27T11:00:00+00:00"), state: "22.0", numericValue: 22.0)
            ]
        )
        try expect(
            recorderHistory == .success(expectedRecorderHistory),
            "HA client maps recorder statistics history samples"
        )
        try await spinUntil("FakeHA journals recorder statistics") {
            await historyServer.journal.snapshot().contains { $0.path == "/api/websocket/recorder/statistics_during_period" }
        }
        let historyCommand = await historyServer.journal.snapshot().first { $0.path == "/api/websocket/recorder/statistics_during_period" }
        try expect(
            historyCommand?.bodyText?.contains(#""period":"hour""#) == true,
            "HA client routes week history through hourly recorder statistics"
        )
        let recorderMonthHistory = await client.history(
            historyInput,
            entityID: "sensor.office_temperature",
            range: .month,
            end: try historyDate("2026-06-27T12:00:00+00:00")
        )
        let expectedRecorderMonthHistory = HistorySeries(
            entityID: "sensor.office_temperature",
            range: .month,
            samples: [
                HistorySample(timestamp: try historyDate("2026-06-27T10:00:00+00:00"), state: "21.4", numericValue: 21.4),
                HistorySample(timestamp: try historyDate("2026-06-27T11:00:00+00:00"), state: "22.0", numericValue: 22.0)
            ]
        )
        try expect(
            recorderMonthHistory == .success(expectedRecorderMonthHistory),
            "HA client maps month recorder statistics history samples"
        )
        try await spinUntil("FakeHA journals month recorder statistics") {
            await historyServer.journal.snapshot().filter { $0.path == "/api/websocket/recorder/statistics_during_period" }.count >= 2
        }
        let recorderCommands = await historyServer.journal.snapshot().filter { $0.path == "/api/websocket/recorder/statistics_during_period" }
        try expect(
            recorderCommands.last?.bodyText?.contains(#""period":"day""#) == true,
            "HA client routes month history through daily recorder statistics"
        )

        let fallbackHistoryFixtures = FakeHAFixtures(
            apiBody: #"{"message":"API running."}"#,
            statesBody: #"[]"#,
            historyBody: """
            [[{"entity_id":"sensor.office_temperature","state":"23.0","last_changed":"2026-06-27T11:30:00+00:00"}]]
            """
        )
        let fallbackHistoryServer = try FakeHAWebSocketServer(
            fixtures: fallbackHistoryFixtures,
            mode: .unavailableCommands(["recorder/statistics_during_period"], code: .unknownCommand),
            pathPrefix: "/ha"
        )
        fallbackHistoryServer.start()
        defer {
            fallbackHistoryServer.stop()
        }
        let fallbackHistory = await client.history(
            HAConnectionInput(
                endpoint: HAEndpoint(primaryURL: fallbackHistoryServer.baseURL, fallbackURL: nil),
                token: "fake-token"
            ),
            entityID: "sensor.office_temperature",
            range: .month,
            end: try historyDate("2026-06-27T12:00:00+00:00")
        )
        let expectedFallbackHistory = HistorySeries(
            entityID: "sensor.office_temperature",
            range: .month,
            samples: [
                HistorySample(timestamp: try historyDate("2026-06-27T11:30:00+00:00"), state: "23.0", numericValue: 23.0)
            ]
        )
        try expect(
            fallbackHistory == .success(expectedFallbackHistory),
            "HA client falls back to REST history when recorder statistics is unavailable"
        )
        try await spinUntil("FakeHA journals recorder statistics fallback") {
            let paths = await fallbackHistoryServer.journal.snapshot().map(\.path)
            return paths.contains("/api/websocket/recorder/statistics_during_period")
                && paths.contains { $0.hasPrefix("/ha/api/history/period/") }
        }
        let fallbackPaths = await fallbackHistoryServer.journal.snapshot().map(\.path)
        try expect(
            fallbackPaths.first == "/ha/api/websocket",
            "HA client preserves prefixed recorder statistics WebSocket paths"
        )

        let legacyFallbackServer = try FakeHAWebSocketServer(
            fixtures: fallbackHistoryFixtures,
            mode: .unsupportedCommands(["recorder/statistics_during_period"])
        )
        legacyFallbackServer.start()
        defer {
            legacyFallbackServer.stop()
        }
        let legacyFallback = await client.history(
            HAConnectionInput(
                endpoint: HAEndpoint(primaryURL: legacyFallbackServer.baseURL, fallbackURL: nil),
                token: "fake-token"
            ),
            entityID: "sensor.office_temperature",
            range: .month,
            end: try historyDate("2026-06-27T12:00:00+00:00")
        )
        try expect(
            legacyFallback == .success(expectedFallbackHistory),
            "HA client falls back to REST history when recorder statistics is legacy unsupported"
        )
        try await spinUntil("FakeHA journals legacy recorder statistics fallback") {
            let paths = await legacyFallbackServer.journal.snapshot().map(\.path)
            return paths.contains("/api/websocket/recorder/statistics_during_period")
                && paths.contains { $0.hasPrefix("/api/history/period/") }
        }

        let transportFailureServer = try FakeHAWebSocketServer(
            fixtures: fallbackHistoryFixtures,
            mode: .disconnectOnCommands(["recorder/statistics_during_period"])
        )
        transportFailureServer.start()
        defer {
            transportFailureServer.stop()
        }
        let transportFailureFallback = await client.history(
            HAConnectionInput(
                endpoint: HAEndpoint(
                    primaryURL: transportFailureServer.baseURL,
                    fallbackURL: nil
                ),
                token: "fake-token"
            ),
            entityID: "sensor.office_temperature",
            range: .month,
            end: try historyDate("2026-06-27T12:00:00+00:00")
        )
        try expect(
            transportFailureFallback == .success(expectedFallbackHistory),
            "HA client falls back to REST after recorder statistics transport failure"
        )
        try await spinUntil("FakeHA journals transport recorder statistics fallback") {
            let paths = await transportFailureServer.journal.snapshot().map(\.path)
            return paths.contains("/api/websocket/recorder/statistics_during_period")
                && paths.contains { $0.hasPrefix("/api/history/period/") }
        }

        let liveFixtures = FakeHAFixtures(
            apiBody: #"{"message":"API running."}"#,
            statesBody: #"[]"#,
            stateChangedEventBody: #"{"entity_id":"sensor.office_temperature","state":"22.0","attributes":{"friendly_name":"Office temperature","unit_of_measurement":"°C"}}"#
        )
        let liveServer = try FakeHAWebSocketServer(fixtures: liveFixtures)
        liveServer.start()
        defer {
            liveServer.stop()
        }
        let liveInput = HAConnectionInput(
            endpoint: HAEndpoint(primaryURL: liveServer.baseURL, fallbackURL: nil),
            token: "fake-token"
        )
        let liveUpdate = await client.nextStateChangedEvent(liveInput)
        try expect(
            liveUpdate == .success(EntityState(id: "sensor.office_temperature", name: "Office temperature", state: "22.0", unit: "°C")),
            "HA client WebSocket subscribe_entities maps compact live state"
        )
        try await spinUntil("FakeHA journals subscribe_entities") {
            await liveServer.journal.snapshot().contains { $0.path == "/api/websocket/subscribe_entities" }
        }
        let livePaths = await liveServer.journal.snapshot().map(\.path)
        try expect(
            !livePaths.contains("/api/websocket/subscribe_events"),
            "optimized live update skips subscribe_events when subscribe_entities is supported"
        )

        let restartLiveServer = try FakeHAWebSocketServer(
            fixtures: liveFixtures,
            mode: .disconnectOnceAfterSubscribeEntitiesResult
        )
        restartLiveServer.start()
        defer {
            restartLiveServer.stop()
        }
        let restartLiveUpdate = await client.nextStateChangedEvent(
            HAConnectionInput(
                endpoint: HAEndpoint(primaryURL: restartLiveServer.baseURL, fallbackURL: nil),
                token: "fake-token"
            )
        )
        try expect(
            restartLiveUpdate == .success(EntityState(id: "sensor.office_temperature", name: "Office temperature", state: "22.0", unit: "°C")),
            "HA client reconnects and resubscribes when live WebSocket drops after subscription"
        )
        try await spinUntil("FakeHA journals restart reconnect live subscriptions") {
            let paths = await restartLiveServer.journal.snapshot().map(\.path)
            return paths.filter { $0 == "/api/websocket" }.count == 2
                && paths.filter { $0 == "/api/websocket/subscribe_entities" }.count == 2
        }
        let restartLivePaths = await restartLiveServer.journal.snapshot().map(\.path)
        try expect(
            !restartLivePaths.contains("/api/websocket/subscribe_events"),
            "restart recovery keeps optimized subscribe_entities path"
        )

        let fallbackLiveServer = try FakeHAWebSocketServer(
            fixtures: liveFixtures,
            mode: .unavailableCommands(["subscribe_entities"], code: .unknownCommand)
        )
        fallbackLiveServer.start()
        defer {
            fallbackLiveServer.stop()
        }
        let fallbackLiveUpdate = await client.nextStateChangedEvent(
            HAConnectionInput(
                endpoint: HAEndpoint(primaryURL: fallbackLiveServer.baseURL, fallbackURL: nil),
                token: "fake-token"
            )
        )
        try expect(
            fallbackLiveUpdate == .success(EntityState(id: "sensor.office_temperature", name: "Office temperature", state: "22.0", unit: "°C")),
            "HA client falls back to subscribe_events when subscribe_entities is unavailable"
        )
        try await spinUntil("FakeHA journals subscribe_events fallback") {
            await fallbackLiveServer.journal.snapshot().contains { $0.path == "/api/websocket/subscribe_events" }
        }
        let fallbackLivePaths = await fallbackLiveServer.journal.snapshot().map(\.path)
        try expect(
            fallbackLivePaths.contains("/api/websocket/subscribe_entities"),
            "fallback live update tries subscribe_entities first"
        )

        let partialLiveServer = try FakeHAWebSocketServer(
            fixtures: FakeHAFixtures(
                apiBody: #"{"message":"API running."}"#,
                statesBody: #"[{"entity_id":"sensor.office_temperature","state":"21.4","attributes":{"friendly_name":"Office temperature","unit_of_measurement":"°C"}}]"#,
                stateChangedEventBody: #"{"entity_id":"sensor.office_temperature","state":"22.0","attributes":{"friendly_name":"Office temperature","unit_of_measurement":"°C"}}"#
            ),
            mode: .partialSubscribeEntitiesChange
        )
        partialLiveServer.start()
        defer {
            partialLiveServer.stop()
        }
        let partialLiveUpdate = await client.nextStateChangedEvent(
            HAConnectionInput(
                endpoint: HAEndpoint(primaryURL: partialLiveServer.baseURL, fallbackURL: nil),
                token: "fake-token"
            )
        )
        try expect(
            partialLiveUpdate == .success(EntityState(id: "sensor.office_temperature", name: "Office temperature", state: "22.0", unit: "°C")),
            "HA client merges partial subscribe_entities changes"
        )
        let partialLivePaths = await partialLiveServer.journal.snapshot().map(\.path)
        try expect(
            !partialLivePaths.contains("/api/websocket/subscribe_events"),
            "partial subscribe_entities changes do not fall back to subscribe_events"
        )

        let attributeRemovalLiveServer = try FakeHAWebSocketServer(
            fixtures: FakeHAFixtures(
                apiBody: #"{"message":"API running."}"#,
                statesBody: #"[{"entity_id":"sensor.office_temperature","state":"21.4","attributes":{"friendly_name":"Office temperature","unit_of_measurement":"°C"}}]"#,
                stateChangedEventBody: #"{"entity_id":"sensor.office_temperature","state":"22.0","attributes":{"friendly_name":"Office temperature","unit_of_measurement":"°C"}}"#
            ),
            mode: .attributeRemovalSubscribeEntitiesChange
        )
        attributeRemovalLiveServer.start()
        defer {
            attributeRemovalLiveServer.stop()
        }
        let attributeRemovalLiveUpdate = await client.nextStateChangedEvent(
            HAConnectionInput(
                endpoint: HAEndpoint(primaryURL: attributeRemovalLiveServer.baseURL, fallbackURL: nil),
                token: "fake-token"
            )
        )
        try expect(
            attributeRemovalLiveUpdate == .success(EntityState(id: "sensor.office_temperature", name: "sensor.office_temperature", state: "21.4", unit: nil)),
            "HA client applies subscribe_entities attribute removals"
        )
        let attributeRemovalLivePaths = await attributeRemovalLiveServer.journal.snapshot().map(\.path)
        try expect(
            !attributeRemovalLivePaths.contains("/api/websocket/subscribe_events"),
            "attribute-removal subscribe_entities changes do not fall back to subscribe_events"
        )

        let entityRemovalLiveServer = try FakeHAWebSocketServer(
            fixtures: FakeHAFixtures(
                apiBody: #"{"message":"API running."}"#,
                statesBody: #"[{"entity_id":"sensor.office_temperature","state":"21.4","attributes":{"friendly_name":"Office temperature","unit_of_measurement":"°C"}}]"#,
                stateChangedEventBody: #"{"entity_id":"sensor.office_temperature","state":"22.0","attributes":{"friendly_name":"Office temperature","unit_of_measurement":"°C"}}"#
            ),
            mode: .entityRemovalThenSubscribeEntitiesAddition
        )
        entityRemovalLiveServer.start()
        defer {
            entityRemovalLiveServer.stop()
        }
        let entityRemovalLiveUpdate = await client.nextStateChangedEvent(
            HAConnectionInput(
                endpoint: HAEndpoint(primaryURL: entityRemovalLiveServer.baseURL, fallbackURL: nil),
                token: "fake-token"
            )
        )
        try expect(
            entityRemovalLiveUpdate == .success(EntityState(id: "sensor.office_temperature", name: "Office temperature", state: "22.0", unit: "°C")),
            "HA client waits past subscribe_entities entity removals"
        )
        let entityRemovalLivePaths = await entityRemovalLiveServer.journal.snapshot().map(\.path)
        try expect(
            !entityRemovalLivePaths.contains("/api/websocket/subscribe_events"),
            "entity-removal subscribe_entities changes do not fall back to subscribe_events"
        )

        let manyRemovalLiveServer = try FakeHAWebSocketServer(
            fixtures: FakeHAFixtures(
                apiBody: #"{"message":"API running."}"#,
                statesBody: #"[{"entity_id":"sensor.office_temperature","state":"21.4","attributes":{"friendly_name":"Office temperature","unit_of_measurement":"°C"}}]"#,
                stateChangedEventBody: #"{"entity_id":"sensor.office_temperature","state":"22.0","attributes":{"friendly_name":"Office temperature","unit_of_measurement":"°C"}}"#
            ),
            mode: .manyEntityRemovalsThenSubscribeEntitiesAddition(count: 17)
        )
        manyRemovalLiveServer.start()
        defer {
            manyRemovalLiveServer.stop()
        }
        let manyRemovalLiveUpdate = await client.nextStateChangedEvent(
            HAConnectionInput(
                endpoint: HAEndpoint(primaryURL: manyRemovalLiveServer.baseURL, fallbackURL: nil),
                token: "fake-token"
            )
        )
        try expect(
            manyRemovalLiveUpdate == .success(EntityState(id: "sensor.office_temperature", name: "Office temperature", state: "22.0", unit: "°C")),
            "HA client waits past many subscribe_entities entity removals"
        )

        let removalThenPartialLiveServer = try FakeHAWebSocketServer(
            fixtures: FakeHAFixtures(
                apiBody: #"{"message":"API running."}"#,
                statesBody: #"[{"entity_id":"sensor.office_temperature","state":"21.4","attributes":{"friendly_name":"Old temperature","unit_of_measurement":"old"}}]"#,
                stateChangedEventBody: #"{"entity_id":"sensor.office_temperature","state":"22.0","attributes":{"friendly_name":"Office temperature","unit_of_measurement":"°C"}}"#
            ),
            mode: .entityRemovalThenPartialSubscribeEntitiesChangeThenAddition
        )
        removalThenPartialLiveServer.start()
        defer {
            removalThenPartialLiveServer.stop()
        }
        let removalThenPartialLiveUpdate = await client.nextStateChangedEvent(
            HAConnectionInput(
                endpoint: HAEndpoint(primaryURL: removalThenPartialLiveServer.baseURL, fallbackURL: nil),
                token: "fake-token"
            )
        )
        try expect(
            removalThenPartialLiveUpdate == .success(EntityState(id: "sensor.office_temperature", name: "Office temperature", state: "22.0", unit: "°C")),
            "HA client does not merge partial changes after entity removal"
        )

        let serviceServer = try FakeHAWebSocketServer()
        serviceServer.start()
        defer {
            serviceServer.stop()
        }
        let serviceInput = HAConnectionInput(
            endpoint: HAEndpoint(primaryURL: serviceServer.baseURL, fallbackURL: nil),
            token: "fake-token"
        )
        let serviceResult = await client.callService(
            serviceInput,
            call: HAServiceCall(
                domain: "script",
                service: "turn_on",
                targetEntityID: "sensor.office_temperature",
                serviceData: ["mode": "boost", "duration": 15]
            )
        )
        try expect(
            serviceResult == .success(HAServiceCallResult(contextID: "fake-context")),
            "HA client WebSocket call_service succeeds"
        )
        try await spinUntil("FakeHA journals service call") {
            await serviceServer.journal.snapshot().contains { $0.path == "/api/websocket/call_service" }
        }

        let badAuth = await client.checkWebSocketConnection(
            HAConnectionInput(endpoint: input.endpoint, token: "wrong-token")
        )
        try expect(badAuth == .failure(.authentication), "HA client WebSocket auth failure is typed")

        let tlsIdentity = try FakeHASelfSignedIdentity()
        let tlsServer = try FakeHAWebSocketServer(tlsIdentity: tlsIdentity.identity)
        tlsServer.start()
        defer {
            tlsServer.stop()
        }
        let strictTLSInput = HAConnectionInput(
            endpoint: HAEndpoint(primaryURL: tlsServer.baseURL, fallbackURL: nil),
            token: "fake-token"
        )
        let allowedTLSInput = HAConnectionInput(
            endpoint: HAEndpoint(primaryURL: tlsServer.baseURL, fallbackURL: nil),
            token: "fake-token",
            serverTrustPolicy: HAServerTrustPolicy(allowedSelfSignedCertificateHosts: ["127.0.0.1"])
        )
        let strictTLSWebSocketResult = await client.checkWebSocketConnection(strictTLSInput)
        let allowedTLSWebSocketResult = await client.checkWebSocketConnection(allowedTLSInput)
        try expect(
            strictTLSWebSocketResult == .failure(.tlsRejected(host: "127.0.0.1")),
            "HA client rejects self-signed WebSocket by default: \(String(describing: strictTLSWebSocketResult))"
        )
        try expect(
            allowedTLSWebSocketResult == .success(HAWebSocketCheck(haVersion: "fake-ha")),
            "HA client accepts explicitly allowed self-signed WebSocket host: \(String(describing: allowedTLSWebSocketResult))"
        )
    }

    private static func verifyDiscoveryAndPersistence() async throws {
        let fixtures = FakeHAFixtures(
            apiBody: #"{"message":"API running."}"#,
            statesBody: """
            [
              {"entity_id":"sensor.kitchen_temperature","state":"21.4","attributes":{"friendly_name":"Kitchen temperature","unit_of_measurement":"°C"}},
              {"entity_id":"switch.office_lamp","state":"off","attributes":{"friendly_name":"Office lamp"}},
              {"entity_id":"sensor.loose_battery","state":"87","attributes":{"friendly_name":"Loose battery","unit_of_measurement":"%"}}
            ]
            """,
            areaRegistryBody: """
            [
              {"area_id":"kitchen","name":"Kitchen"},
              {"area_id":"office","name":"Office"}
            ]
            """,
            deviceRegistryBody: """
            [
              {"id":"office_bridge","name":"Office bridge","area_id":"office"}
            ]
            """,
            entityRegistryDisplayBody: """
            {
              "entities": [
                {"ei":"sensor.kitchen_temperature","en":"Kitchen temperature","ai":"kitchen"},
                {"ei":"switch.office_lamp","en":"Office lamp","di":"office_bridge"},
                {"ei":"sensor.loose_battery","en":"Loose battery"}
              ]
            }
            """,
            entityRegistryBody: """
            [
              {"entity_id":"sensor.kitchen_temperature","name":"Kitchen temperature","area_id":"kitchen"},
              {"entity_id":"switch.office_lamp","name":"Office lamp","device_id":"office_bridge"},
              {"entity_id":"sensor.loose_battery","name":"Loose battery"}
            ]
            """
        )
        let server = try FakeHAWebSocketServer(fixtures: fixtures)
        server.start()
        defer {
            server.stop()
        }

        let input = HAConnectionInput(
            endpoint: HAEndpoint(primaryURL: server.baseURL, fallbackURL: nil),
            token: "fake-token"
        )
        let discovery = await HomeAssistantClient().discovery(input)
        guard case let .success(snapshot) = discovery else {
            throw SmokeFailure("HA discovery unexpectedly failed")
        }
        let rooms = RoomResolver().resolve(snapshot: snapshot)
        try expect(rooms.map(\.name) == ["Kitchen", "Office", "Unassigned"], "discovery groups rooms")
        try expect(rooms.flatMap(\.entities).map(\.id) == ["sensor.kitchen_temperature", "switch.office_lamp", "sensor.loose_battery"], "discovery preserves entities")
        try await spinUntil("FakeHA journals optimized entity registry display list") {
            await server.journal.snapshot().contains { $0.path == "/api/websocket/config/entity_registry/list_for_display" }
        }
        let optimizedDiscoveryPaths = await server.journal.snapshot().map(\.path)
        try expect(
            !optimizedDiscoveryPaths.contains("/api/websocket/config/entity_registry/list"),
            "optimized discovery skips full entity registry when display list is supported"
        )

        let fallbackFixtures = FakeHAFixtures(
            apiBody: #"{"message":"API running."}"#,
            statesBody: """
            [
              {"entity_id":"sensor.fallback_temperature","state":"19.5","attributes":{"friendly_name":"Fallback temperature","unit_of_measurement":"°C"}}
            ]
            """
        )
        let fallbackServer = try FakeHAWebSocketServer(
            fixtures: fallbackFixtures,
            mode: .unavailableCommands([
                "config/area_registry/list",
                "config/device_registry/list",
                "config/entity_registry/list_for_display",
                "config/entity_registry/list"
            ], code: .unknownCommand)
        )
        fallbackServer.start()
        defer {
            fallbackServer.stop()
        }
        let fallbackDiscovery = await HomeAssistantClient().discovery(
            HAConnectionInput(
                endpoint: HAEndpoint(primaryURL: fallbackServer.baseURL, fallbackURL: nil),
                token: "fake-token"
            )
        )
        guard case let .success(fallbackSnapshot) = fallbackDiscovery else {
            throw SmokeFailure("HA discovery fallback unexpectedly failed")
        }
        let fallbackRooms = RoomResolver().resolve(snapshot: fallbackSnapshot)
        try expect(fallbackRooms.map(\.name) == ["Unassigned"], "unavailable registry discovery falls back to states")
        try expect(
            fallbackRooms.flatMap(\.entities).map(\.id) == ["sensor.fallback_temperature"],
            "states-only discovery keeps available entities"
        )

        let configURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("perchha-smoke-config-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("config.json")
        defer {
            try? FileManager.default.removeItem(at: configURL.deletingLastPathComponent())
        }
        let configStore = JSONConfigStore(fileURL: configURL)
        let configuration = PerchHAConfiguration(
            selectedEntityIDs: ["sensor.kitchen_temperature", "switch.office_lamp"],
            menuBarEntityIDs: ["sensor.kitchen_temperature"],
            roomOrder: ["kitchen", "office"],
            entityOrder: ["switch.office_lamp", "sensor.kitchen_temperature"]
        )
        let savedConfiguration = try configStore.save(configuration)
        let loadedConfiguration = try configStore.load()
        try expect(savedConfiguration == configuration, "config save returns written value")
        try expect(loadedConfiguration == configuration, "config store round-trips JSON")

        let secretStore = KeychainSecretStore(service: "dev.perchha.smoke.\(UUID().uuidString)")
        defer {
            _ = try? secretStore.delete(.accessToken)
            _ = try? secretStore.delete(.refreshToken)
        }
        let missingSecret = try secretStore.delete(.accessToken)
        let createdSecret = try secretStore.save("smoke-secret-token", for: .accessToken)
        let firstSecret = try secretStore.read(.accessToken)
        let updatedSecret = try secretStore.save("smoke-rotated-token", for: .accessToken)
        let secondSecret = try secretStore.read(.accessToken)
        try expect(missingSecret == .notFound, "missing Keychain secret is explicit")
        try expect(createdSecret == .created, "Keychain creates access token")
        try expect(firstSecret == "smoke-secret-token", "Keychain reads access token")
        try expect(updatedSecret == .updated, "Keychain updates access token")
        try expect(secondSecret == "smoke-rotated-token", "Keychain reads updated access token")
        try expect(!SecretStoreError.notFound(.accessToken).description.contains("smoke-rotated-token"), "secret errors do not leak tokens")
    }

    @MainActor
    private static func verifyPanelModelAgainstFakeHA() async throws {
        let fixtures = FakeHAFixtures(
            apiBody: #"{"message":"API running."}"#,
            statesBody: #"[{"entity_id":"sensor.office_temperature","state":"21.4","attributes":{"friendly_name":"Office temperature","unit_of_measurement":"°C"}}]"#,
            areaRegistryBody: #"[{"area_id":"office","name":"Office"}]"#,
            deviceRegistryBody: #"[]"#,
            entityRegistryDisplayBody: #"{"entities":[{"ei":"sensor.office_temperature","en":"Office temperature","ai":"office"}]}"#,
            entityRegistryBody: #"[{"entity_id":"sensor.office_temperature","name":"Office temperature","area_id":"office"}]"#
        )
        let server = try FakeHAWebSocketServer(fixtures: fixtures)
        server.start()
        defer {
            server.stop()
        }

        let client = HomeAssistantClient()
        let model = PerchHAPanelModel(
            connector: { form in
                guard let primaryURL = form.primaryURL() else {
                    return .failure(.protocolError("invalid Home Assistant URL"))
                }
                let input = HAConnectionInput(
                    endpoint: HAEndpoint(primaryURL: primaryURL, fallbackURL: form.fallbackURL()),
                    token: form.trimmedToken,
                    serverTrustPolicy: HAServerTrustPolicy(trustsAllHosts: true)
                )
                switch await client.discovery(input) {
                case let .success(snapshot):
                    return .success(rooms: RoomResolver().resolve(snapshot: snapshot))
                case let .failure(failure):
                    return .failure(failure.connectionFailure)
                }
            },
            serviceMetadataProvider: { form in
                guard let primaryURL = form.primaryURL() else {
                    return .unavailable("invalid Home Assistant URL")
                }
                let input = HAConnectionInput(
                    endpoint: HAEndpoint(primaryURL: primaryURL, fallbackURL: form.fallbackURL()),
                    token: form.trimmedToken,
                    serverTrustPolicy: HAServerTrustPolicy(trustsAllHosts: true)
                )
                switch await client.services(input) {
                case let .success(metadata):
                    return .success(metadata)
                case let .failure(failure):
                    return .unavailable(failure.description)
                }
            }
        )

        let expectedReconnectPathCounts = [
            "/api/websocket": 2,
            "/api/websocket/config/area_registry/list": 1,
            "/api/websocket/config/device_registry/list": 1,
            "/api/websocket/config/entity_registry/list_for_display": 1,
            "/api/websocket/get_services": 1
        ]
        let expectedReconnectPathCount = expectedReconnectPathCounts.values.reduce(0, +)

        func pathCounts(_ paths: [String]) -> [String: Int] {
            Dictionary(grouping: paths, by: { $0 }).mapValues(\.count)
        }

        func requestPaths(after index: Int) async -> [String] {
            let paths = await server.journal.snapshot().map(\.path)
            return Array(paths.dropFirst(index))
        }

        func waitForRequestPaths(after index: Int, count: Int, message: String) async throws -> [String] {
            var latestPaths: [String] = []
            for _ in 0..<100 {
                let paths = await requestPaths(after: index)
                latestPaths = paths
                if paths.count >= count {
                    return paths
                }
                await Task.yield()
            }
            throw SmokeFailure("\(message): \(latestPaths)")
        }

        func assertBoundedReconnectPaths(_ paths: [String], _ message: String) throws {
            try expect(pathCounts(paths) == expectedReconnectPathCounts, message)
            try expect(
                !paths.contains("/api/websocket/config/entity_registry/list"),
                "\(message) without full entity registry fallback"
            )
        }

        model.updateConnectionForm(urlString: server.baseURL.absoluteString, token: "fake-token")
        try expect(model.snapshot.connectionForm.token.isEmpty, "panel model keeps edited token out of published snapshot")
        try expect(model.snapshot.hasTokenInput, "panel model publishes token presence without token value")
        await model.connect()
        try expect(model.snapshot.connectionState == .connected, "panel model connects against FakeHA")
        try expect(model.snapshot.connectionForm.token.isEmpty, "panel model removes token from published snapshot after connect")
        try expect(model.snapshot.hasTokenInput, "panel model preserves token presence after connect")
        try expect(model.snapshot.availableRooms.count == 1, "panel model keeps discovered rooms for selection")
        try expect(model.snapshot.visibleEntityCount == 1, "panel model exposes visible values")
        try expect(model.snapshot.rooms.first?.name == "Office", "panel model exposes room")
        try expect(model.snapshot.rooms.first?.entities.first?.name == "Office temperature", "panel model exposes entity")
        let initialRequestPaths = try await waitForRequestPaths(
            after: 0,
            count: expectedReconnectPathCount,
            message: "FakeHA journals bounded initial panel request volume"
        )
        try assertBoundedReconnectPaths(
            initialRequestPaths,
            "panel initial connect uses one optimized discovery and one service metadata request"
        )

        let beforeRefreshRequestCount = initialRequestPaths.count
        await model.refresh()
        try expect(model.snapshot.refreshCount == 1, "panel model manual refresh increments")
        let reconnectRequestPaths = try await waitForRequestPaths(
            after: beforeRefreshRequestCount,
            count: expectedReconnectPathCount,
            message: "FakeHA journals bounded reconnect request volume"
        )
        try assertBoundedReconnectPaths(
            reconnectRequestPaths,
            "panel reconnect uses one optimized discovery and one service metadata request"
        )

        let empty = PerchHAPanelModel { _ in
            .success(rooms: [])
        }
        empty.updateConnectionForm(urlString: "http://127.0.0.1:8123", token: "fake-token")
        await empty.connect()
        try expect(empty.snapshot.phase == .connectedEmpty, "panel model exposes connected empty state")
        try expect(empty.snapshot.canRefresh, "panel model can refresh after successful empty connection")

        let failing = PerchHAPanelModel()
        failing.updateConnectionForm(urlString: "not-a-url", token: "")
        await failing.connect()
        try expect(
            failing.snapshot.connectionState == .failed(.protocolError("invalid Home Assistant URL")),
            "panel model exposes first-run failure"
        )
        try expect(failing.snapshot.failureDescription == "invalid Home Assistant URL", "panel model exposes first-run failure text")
        try expect(!failing.snapshot.canRefresh, "panel model disables refresh after invalid first-run input")

        let secretRecorder = ConnectionFormRecorder()
        let secret = PerchHAPanelModel { form in
            await secretRecorder.record(form)
            return .failure(.authentication)
        }
        secret.updateConnectionForm(urlString: "http://127.0.0.1:8123", token: "secret-token")
        try expect(secret.snapshot.connectionForm.token.isEmpty, "panel model keeps first-run token private while editing")
        try expect(secret.snapshot.hasTokenInput, "panel model exposes first-run token presence")
        await secret.connect()
        try expect(secret.snapshot.connectionForm.token.isEmpty, "panel model keeps failed token private")
        try expect(secret.snapshot.hasTokenInput, "panel model keeps failed token presence visible")
        await secret.connect()
        let recordedTokens = await secretRecorder.tokens()
        try expect(recordedTokens == ["secret-token", "secret-token"], "panel retry reuses the visible private token")

        let sequencingRecorder = ConnectionFormRecorder()
        let sequenced = PerchHAPanelModel { form in
            await sequencingRecorder.record(form)
            return .success(rooms: [])
        }
        sequenced.updateConnectionForm(token: "secret-token")
        sequenced.updateConnectionForm(urlString: "http://127.0.0.1:8123")
        sequenced.updateConnectionForm(fallbackURLString: "http://127.0.0.1:8124")
        await sequenced.connect()
        try expect(sequenced.snapshot.connectionState == .connected, "panel form sequencing connects")
        try expect(sequenced.snapshot.connectionForm.token.isEmpty, "panel form sequencing keeps token private")
        try expect(sequenced.snapshot.hasTokenInput, "panel form sequencing keeps token presence")
        let sequencingTokens = await sequencingRecorder.tokens()
        try expect(sequencingTokens == ["secret-token"], "panel form sequencing preserves private token after URL edits")

        let clearedRecorder = ConnectionFormRecorder()
        let cleared = PerchHAPanelModel { form in
            await clearedRecorder.record(form)
            return .success(rooms: [])
        }
        cleared.updateConnectionForm(urlString: "http://127.0.0.1:8123", token: "secret-token")
        cleared.updateConnectionForm(token: "")
        await cleared.connect()
        try expect(cleared.snapshot.connectionState == .failed(.authentication), "panel model rejects cleared token")
        try expect(!cleared.snapshot.hasTokenInput, "panel model clears token presence")
        let clearedCalls = await clearedRecorder.callCount()
        try expect(clearedCalls == 0, "panel model does not connect after token clear")

        let invalidFallback = PerchHAPanelModel()
        invalidFallback.updateConnectionForm(
            urlString: "http://127.0.0.1:8123",
            fallbackURLString: "fallback.invalid:8123",
            token: "fake-token"
        )
        await invalidFallback.connect()
        try expect(
            invalidFallback.snapshot.connectionState == .failed(.protocolError("invalid alternative address")),
            "panel model rejects invalid fallback URL"
        )
        try expect(invalidFallback.snapshot.failureDescription == "invalid alternative address", "panel model exposes fallback failure text")

        let recorder = ConnectionFormRecorder()
        let fallback = PerchHAPanelModel { form in
            await recorder.record(form)
            return .success(rooms: [])
        }
        fallback.updateConnectionForm(
            urlString: "http://127.0.0.1:8123",
            fallbackURLString: "http://127.0.0.1:8124",
            token: "fake-token"
        )
        await fallback.connect()
        let fallbackURLString = await recorder.fallbackURLString()
        try expect(fallbackURLString == "http://127.0.0.1:8124", "panel model forwards valid fallback URL")

        let certificateRecorder = ConnectionFormRecorder()
        let certificate = PerchHAPanelModel { form in
            await certificateRecorder.record(form)
            return .success(rooms: [])
        }
        certificate.updateConnectionForm(
            urlString: "https://homeassistant.local:8123",
            fallbackURLString: "https://fallback.example",
            token: "secret-token"
        )
        await certificate.connect()
        try expect(certificate.snapshot.connectionForm.token.isEmpty, "panel model keeps certificate-form token private")

        let historyClock = TestPerchClock()
        let historyProbe = HistoryProviderProbe(
            series: HistorySeries(
                entityID: "sensor.office_temperature",
                range: .hour,
                samples: [
                    HistorySample(
                        timestamp: try historyDate("2026-06-27T10:30:00+00:00"),
                        state: "21.4",
                        numericValue: 21.4
                    ),
                    HistorySample(
                        timestamp: try historyDate("2026-06-27T11:00:00+00:00"),
                        state: "22.0",
                        numericValue: 22.0
                    )
                ]
            )
        )
        let historyRooms = model.snapshot.rooms
        let historyPanel = PerchHAPanelModel(
            connector: { _ in .success(rooms: historyRooms) },
            historyProvider: { form, entityID, range in
                await historyProbe.provide(form: form, entityID: entityID, range: range)
            },
            clock: historyClock,
            historyDebounce: .seconds(1),
            historyHoverGrace: .milliseconds(300)
        )
        historyPanel.updateConnectionForm(urlString: "http://127.0.0.1:8123", token: "fake-token")
        await historyPanel.connect()
        historyPanel.startHistoryHover("sensor.office_temperature", range: .hour)
        for _ in 0..<100 {
            if await historyClock.sleepingTaskCount() == 1 {
                break
            }
            await Task.yield()
        }
        let sleepingHistoryTasks = await historyClock.sleepingTaskCount()
        let providerCallsBeforeDebounce = await historyProbe.callCount()
        try expect(sleepingHistoryTasks == 1, "panel history debounce has sleeper")
        try expect(providerCallsBeforeDebounce == 0, "panel history hover waits for debounce")
        try expect(
            PerchHAHistoryBodyPresentation(
                state: .loading(entityID: "sensor.office_temperature", range: .hour),
                entityID: "sensor.office_temperature"
            ) == .loadingSkeleton,
            "panel history loading presentation uses skeleton"
        )
        _ = await historyClock.advance(by: .seconds(1))
        for _ in 0..<100 {
            if case .loaded = historyPanel.snapshot.historyState {
                break
            }
            await Task.yield()
        }
        if case .loaded = historyPanel.snapshot.historyState {
            try expect(true, "panel history loaded")
        } else {
            throw SmokeFailure("panel history loaded")
        }
        try expect(
            historyPanel.snapshot.historyPresentationEntityID == "sensor.office_temperature",
            "panel history opens popover presentation"
        )
        historyPanel.cancelHistoryHover()
        for _ in 0..<100 {
            if await historyClock.sleepingTaskCount() == 1 {
                break
            }
            await Task.yield()
        }
        try expect(
            historyPanel.snapshot.historyPresentationEntityID == "sensor.office_temperature",
            "panel history hover-out keeps popover open during grace period"
        )
        _ = await historyClock.advance(by: .milliseconds(300))
        for _ in 0..<100 {
            if historyPanel.snapshot.historyPresentationEntityID == nil {
                break
            }
            await Task.yield()
        }
        try expect(historyPanel.snapshot.historyPresentationEntityID == nil, "panel history hover-out closes popover")
        let providerCallsAfterDebounce = await historyProbe.callCount()
        try expect(providerCallsAfterDebounce == 1, "panel history provider called after debounce")
        await historyPanel.loadHistory("sensor.office_temperature", range: .hour)
        let providerCallsAfterCacheHit = await historyProbe.callCount()
        try expect(providerCallsAfterCacheHit == 1, "panel history cache avoids duplicate provider call")
        let sparkline = PerchHAHistorySparklineGeometry(
            series: HistorySeries(
                entityID: "sensor.office_temperature",
                range: .hour,
                samples: [
                    HistorySample(timestamp: try historyDate("2026-06-27T10:00:00+00:00"), state: "10", numericValue: 10),
                    HistorySample(timestamp: try historyDate("2026-06-27T10:30:00+00:00"), state: "20", numericValue: 20),
                    HistorySample(timestamp: try historyDate("2026-06-27T11:00:00+00:00"), state: "15", numericValue: 15)
                ]
            )
        )
        try expect(
            sparkline.points == [
                PerchHAHistorySparklinePoint(x: 0, y: 1),
                PerchHAHistorySparklinePoint(x: 0.5, y: 0),
                PerchHAHistorySparklinePoint(x: 1, y: 0.5)
            ],
            "panel history sparkline maps time and values into normalized points"
        )
        let mixedHistorySummary = PerchHAHistoryContentSummary(
            series: HistorySeries(
                entityID: "sensor.office_temperature",
                range: .hour,
                samples: [
                    HistorySample(timestamp: try historyDate("2026-06-27T11:00:00+00:00"), state: "30", numericValue: 30),
                    HistorySample(timestamp: try historyDate("2026-06-27T10:00:00+00:00"), state: "10", numericValue: 10),
                    HistorySample(timestamp: try historyDate("2026-06-27T11:30:00+00:00"), state: "unknown", numericValue: nil),
                    HistorySample(timestamp: try historyDate("2026-06-27T10:30:00+00:00"), state: "20", numericValue: 20)
                ]
            )
        )
        try expect(
            mixedHistorySummary == .statistics(
                PerchHAHistoryStatistics(current: 30, minimum: 10, average: 20, maximum: 30)
            ),
            "panel history summary uses latest chronological numeric sample"
        )
        let unsortedSparkline = PerchHAHistorySparklineGeometry(
            series: HistorySeries(
                entityID: "sensor.office_temperature",
                range: .hour,
                samples: [
                    HistorySample(timestamp: try historyDate("2026-06-27T11:00:00+00:00"), state: "15", numericValue: 15),
                    HistorySample(timestamp: try historyDate("2026-06-27T10:00:00+00:00"), state: "10", numericValue: 10),
                    HistorySample(timestamp: try historyDate("2026-06-27T11:30:00+00:00"), state: "unknown", numericValue: nil),
                    HistorySample(timestamp: try historyDate("2026-06-27T10:30:00+00:00"), state: "20", numericValue: 20)
                ]
            )
        )
        try expect(
            unsortedSparkline.points == [
                PerchHAHistorySparklinePoint(x: 0, y: 1),
                PerchHAHistorySparklinePoint(x: 0.5, y: 0),
                PerchHAHistorySparklinePoint(x: 1, y: 0.5)
            ],
            "panel history sparkline sorts numeric samples chronologically"
        )
        let flatSparkline = PerchHAHistorySparklineGeometry(
            series: HistorySeries(
                entityID: "sensor.office_temperature",
                range: .hour,
                samples: [
                    HistorySample(timestamp: try historyDate("2026-06-27T10:00:00+00:00"), state: "21.4", numericValue: 21.4),
                    HistorySample(timestamp: try historyDate("2026-06-27T10:00:00+00:00"), state: "21.4", numericValue: 21.4)
                ]
            )
        )
        try expect(
            flatSparkline.points == [
                PerchHAHistorySparklinePoint(x: 0, y: 0.5),
                PerchHAHistorySparklinePoint(x: 1, y: 0.5)
            ],
            "panel history sparkline centers constant equal-time values"
        )

        let disconnectedHistory = PerchHAPanelModel()
        await disconnectedHistory.loadHistory("sensor.office_temperature", range: .hour)
        try expect(
            disconnectedHistory.snapshot.historyState == .unavailable(
                entityID: "sensor.office_temperature",
                range: .hour,
                message: "history requires a connected Home Assistant session"
            ),
            "panel history exposes disconnected unavailable state"
        )

        let gate = Gate()
        let cancellable = PerchHAPanelModel { _ in
            await gate.wait()
            return .success(
                rooms: [
                    Room(
                        id: "office",
                        name: "Office",
                        entities: [
                            DiscoveredEntity(
                                id: "sensor.office_temperature",
                                name: "Office temperature",
                                state: "21.4",
                                unit: "°C",
                                areaID: "office",
                                deviceID: nil
                            )
                        ]
                    )
                ]
            )
        }
        cancellable.updateConnectionForm(urlString: "http://127.0.0.1:8123", token: "secret-token")
        cancellable.startConnect()
        for _ in 0..<100 {
            if cancellable.snapshot.connectionState == .connecting {
                break
            }
            await Task.yield()
        }
        try expect(cancellable.snapshot.connectionState == .connecting, "panel model enters connecting state")
        cancellable.cancelInFlightAction()
        _ = await gate.open()
        await Task.yield()
        try expect(cancellable.snapshot.connectionState == .disconnected, "panel model cancellation restores first-run state")
        try expect(cancellable.snapshot.rooms.isEmpty, "panel model cancellation ignores late connector result")
        try expect(cancellable.snapshot.connectionForm.token.isEmpty, "panel model cancellation keeps token private")
        try expect(cancellable.snapshot.hasTokenInput, "panel model cancellation keeps token presence")

        let staleSnapshot = PerchHAPanelSnapshot(
            connectionState: .reconnecting(attempt: 1),
            phase: .reconnecting(attempt: 1),
            rooms: [
                Room(
                    id: "office",
                    name: "Office",
                    entities: [
                        DiscoveredEntity(
                            id: "sensor.office_temperature",
                            name: "Office temperature",
                            state: "21.4",
                            unit: "°C",
                            areaID: nil,
                            deviceID: nil
                        )
                    ]
                )
            ]
        )
        try expect(
            staleSnapshot.rooms.first?.entities.first.map { staleSnapshot.formattedValue(for: $0, locale: Locale(identifier: "en_US")) } == FormattedEntityValue(text: "Stale: 21.4 °C", status: .stale),
            "panel snapshot renders reconnecting values as stale"
        )

        let refreshSequence = ConnectionResultSequence(
            results: [
                .success(
                    rooms: [
                        Room(
                            id: "office",
                            name: "Office",
                            entities: [
                                DiscoveredEntity(
                                    id: "sensor.office_temperature",
                                    name: "Office temperature",
                                    state: "21.4",
                                    unit: "°C",
                                    areaID: nil,
                                    deviceID: nil
                                )
                            ]
                        )
                    ]
                ),
                .failure(.unreachable(host: "homeassistant.local"))
            ]
        )
        let failingRefresh = PerchHAPanelModel { _ in
            await refreshSequence.next()
        }
        failingRefresh.updateConnectionForm(urlString: "http://127.0.0.1:8123", token: "fake-token")
        await failingRefresh.connect()
        await failingRefresh.refresh()
        try expect(failingRefresh.snapshot.phase == .failedStale(.unreachable(host: "homeassistant.local")), "panel refresh failure keeps stale data phase")
        try expect(failingRefresh.snapshot.visibleEntityCount == 1, "panel refresh failure keeps last-known rows")
        try expect(
            failingRefresh.snapshot.rooms.first?.entities.first.map { failingRefresh.snapshot.formattedValue(for: $0, locale: Locale(identifier: "en_US")) } == FormattedEntityValue(text: "Stale: 21.4 °C", status: .stale),
            "panel refresh failure renders stale row values"
        )

        let selectionProbe = SelectionSinkProbe()
        let selectable = PerchHAPanelModel(
            connector: { _ in
                .success(
                    rooms: [
                        Room(
                            id: "office",
                            name: "Office",
                            entities: [
                                DiscoveredEntity(
                                    id: "sensor.office_temperature",
                                    name: "Office temperature",
                                    state: "21.4",
                                    unit: "°C",
                                    areaID: nil,
                                    deviceID: nil
                                ),
                                DiscoveredEntity(
                                    id: "sensor.office_humidity",
                                    name: "Office humidity",
                                    state: "44",
                                    unit: "%",
                                    areaID: nil,
                                    deviceID: nil
                                )
                            ]
                        )
                    ]
                )
            },
            selectionConfiguration: EntitySelectionConfiguration(
                selectedEntityIDs: ["sensor.office_humidity"],
                entityOrder: ["sensor.office_humidity"],
                isExplicit: true
            ),
            selectionSink: { selection in
                selectionProbe.record(selection)
            }
        )
        selectable.updateConnectionForm(urlString: "http://127.0.0.1:8123", token: "fake-token")
        await selectable.connect()
        try expect(selectable.snapshot.rooms.flatMap(\.entities).map(\.id) == ["sensor.office_humidity"], "panel model applies explicit selection")
        selectable.toggleSettings()
        selectable.updateSelectionQuery("temperature")
        try expect(selectable.snapshot.selectionTree.first?.entities.map(\.entity.id) == ["sensor.office_temperature"], "panel settings search filters entity tree")
        selectable.setEntity("sensor.office_temperature", isSelected: true)
        try expect(Set(selectionProbe.lastSelection?.selectedEntityIDs ?? []) == Set<EntityID>(["sensor.office_humidity", "sensor.office_temperature"]), "panel settings persists selection changes")
        try expect(selectionProbe.lastSelection?.isExplicit == true, "panel settings persists explicit selection state")

        let controlRooms = [
            Room(
                id: "controls",
                name: "Controls",
                entities: [
                    DiscoveredEntity(
                        id: "switch.office_lamp",
                        name: "Office lamp",
                        state: "off",
                        unit: nil,
                        areaID: nil,
                        deviceID: nil
                    ),
                    DiscoveredEntity(
                        id: "light.kitchen_counter",
                        name: "Kitchen counter",
                        state: "on",
                        unit: nil,
                        areaID: nil,
                        deviceID: nil
                    ),
                    DiscoveredEntity(
                        id: "cover.office_blinds",
                        name: "Office blinds",
                        state: "open",
                        unit: nil,
                        areaID: nil,
                        deviceID: nil,
                        currentPosition: 42
                    ),
                    DiscoveredEntity(
                        id: "sensor.office_temperature",
                        name: "Office temperature",
                        state: "21.4",
                        unit: "°C",
                        areaID: nil,
                        deviceID: nil
                    )
                ]
            )
        ]
        let controlServer = try FakeHAWebSocketServer()
        controlServer.start()
        defer {
            controlServer.stop()
        }
        let protectedStore = InMemoryProtectedActionValueStore()
        let controls = PerchHAPanelModel(
            connector: { _ in .success(rooms: controlRooms) },
            actionRunner: { form, action in
                guard let primaryURL = form.primaryURL() else {
                    return .failed("invalid URL")
                }
                let input = HAConnectionInput(
                    endpoint: HAEndpoint(primaryURL: primaryURL, fallbackURL: form.fallbackURL()),
                    token: form.trimmedToken
                )
                switch await HomeAssistantClient().callService(input, call: action) {
                case .success:
                    return .success
                case let .failure(failure):
                    return .failed(failure.description)
                }
            },
            protectedActionValueStore: protectedStore
        )
        controls.updateConnectionForm(urlString: controlServer.baseURL.absoluteString, token: "fake-token")
        await controls.connect()
        let controlSucceeded = await controls.setEntityControl("switch.office_lamp", isOn: true)
        try expect(controlSucceeded, "panel built-in switch toggle succeeds")
        let controlServiceEntries = await controlServer.journal.snapshot().filter { $0.path == "/api/websocket/call_service" }
        try expect(controlServiceEntries.count == 1, "panel built-in control emits one service call")
        try expect(controlServiceEntries.first?.bodyText?.contains(#""domain":"switch""#) == true, "panel built-in control sends switch domain")
        try expect(controlServiceEntries.first?.bodyText?.contains(#""service":"turn_on""#) == true, "panel built-in control sends turn_on service")
        try expect(controlServiceEntries.first?.bodyText?.contains(#""entity_id":"switch.office_lamp""#) == true, "panel built-in control targets entity")
        try expect(
            controls.snapshot.availableRooms.flatMap(\.entities).first { $0.id == "switch.office_lamp" }?.state == "on",
            "panel built-in control keeps optimistic state after success"
        )
        let coverSucceeded = await controls.setCoverPosition("cover.office_blinds", position: 75)
        try expect(coverSucceeded, "panel built-in cover position succeeds")
        let coverServiceEntries = await controlServer.journal.snapshot().filter { $0.path == "/api/websocket/call_service" }
        try expect(coverServiceEntries.count == 2, "panel built-in cover emits one additional service call")
        let coverServiceEntry = coverServiceEntries.last
        try expect(coverServiceEntry?.bodyText?.contains(#""domain":"cover""#) == true, "panel built-in cover sends cover domain")
        try expect(coverServiceEntry?.bodyText?.contains(#""service":"set_cover_position""#) == true, "panel built-in cover sends set position service")
        try expect(coverServiceEntry?.bodyText?.contains(#""entity_id":"cover.office_blinds""#) == true, "panel built-in cover targets entity")
        try expect(coverServiceEntry?.bodyText?.contains(#""position":75"#) == true, "panel built-in cover sends position payload")
        try expect(
            controls.snapshot.availableRooms.flatMap(\.entities).first { $0.id == "cover.office_blinds" }?.currentPosition == 75,
            "panel built-in cover keeps optimistic position after success"
        )
        let coverOpenSucceeded = await controls.setCoverControl("cover.office_blinds", command: .open)
        try expect(coverOpenSucceeded, "panel built-in cover open succeeds")
        let coverCloseSucceeded = await controls.setCoverControl("cover.office_blinds", command: .close)
        try expect(coverCloseSucceeded, "panel built-in cover close succeeds")
        let coverStopSucceeded = await controls.setCoverControl("cover.office_blinds", command: .stop)
        try expect(coverStopSucceeded, "panel built-in cover stop succeeds")
        let coverButtonServiceEntries = await controlServer.journal.snapshot().filter { $0.path == "/api/websocket/call_service" }
        try expect(coverButtonServiceEntries.count == 5, "panel built-in cover buttons emit one service call each")
        try expect(coverButtonServiceEntries[2].bodyText?.contains(#""service":"open_cover""#) == true, "panel built-in cover open sends open service")
        try expect(coverButtonServiceEntries[3].bodyText?.contains(#""service":"close_cover""#) == true, "panel built-in cover close sends close service")
        try expect(coverButtonServiceEntries[4].bodyText?.contains(#""service":"stop_cover""#) == true, "panel built-in cover stop sends stop service")
        try expect(
            coverButtonServiceEntries[2...4].allSatisfy { $0.bodyText?.contains(#""entity_id":"cover.office_blinds""#) == true },
            "panel built-in cover buttons target entity"
        )
        let customAction = EntityCustomAction(
            id: "boost-air",
            entityID: "sensor.office_temperature",
            title: "Boost air",
            action: ActionSpec(
                domain: "script",
                service: "turn_on",
                targetEntityID: "script.air_cleaner_boost",
                serviceData: [
                    "mode": "boost",
                    "duration": 15,
                    "payload": .object([
                        "steps": .array([
                            .object([
                                "service": "fan.set_preset_mode",
                                "data": .object([
                                    "preset_mode": "boost"
                                ])
                            ])
                        ])
                    ])
                ]
            )
        )
        try expect(controls.setCustomAction(customAction), "panel custom action attaches to sensor row")
        let customActionSucceeded = await controls.runCustomAction(customAction.id)
        try expect(customActionSucceeded, "panel custom action succeeds")
        let customActionServiceEntries = await controlServer.journal.snapshot().filter { $0.path == "/api/websocket/call_service" }
        try expect(customActionServiceEntries.count == 6, "panel custom action emits one service call")
        let customActionServiceEntry = customActionServiceEntries.last
        try expect(customActionServiceEntry?.bodyText?.contains(#""domain":"script""#) == true, "panel custom action sends script domain")
        try expect(customActionServiceEntry?.bodyText?.contains(#""service":"turn_on""#) == true, "panel custom action sends configured service")
        try expect(customActionServiceEntry?.bodyText?.contains(#""entity_id":"script.air_cleaner_boost""#) == true, "panel custom action targets configured entity")
        try expect(customActionServiceEntry?.bodyText?.contains(#""mode":"boost""#) == true, "panel custom action preserves string payload")
        try expect(customActionServiceEntry?.bodyText?.contains(#""duration":15"#) == true, "panel custom action preserves numeric payload")
        let nestedService = try jsonString(
            customActionServiceEntry?.bodyText,
            path: ["service_data", "payload", "steps", 0, "service"]
        )
        let nestedPresetMode = try jsonString(
            customActionServiceEntry?.bodyText,
            path: ["service_data", "payload", "steps", 0, "data", "preset_mode"]
        )
        try expect(
            nestedService == "fan.set_preset_mode",
            "panel custom action preserves nested array service"
        )
        try expect(
            nestedPresetMode == "boost",
            "panel custom action preserves nested object payload"
        )
        try expect(
            controls.snapshot.availableRooms.flatMap(\.entities).first { $0.id == "sensor.office_temperature" }?.state == "21.4",
            "panel custom action does not mutate sensor state"
        )
        let protectedActionRecorder = ActionInvocationRecorder()
        let protectedControls = PerchHAPanelModel(
            connector: { _ in .success(rooms: controlRooms) },
            actionRunner: { _, action in
                await protectedActionRecorder.record(action)
                return .success
            },
            protectedActionValueStore: protectedStore
        )
        protectedControls.updateConnectionForm(urlString: controlServer.baseURL.absoluteString, token: "fake-token")
        await protectedControls.connect()
        let protectedCustomAction = EntityCustomAction(
            id: "arm-alarm",
            entityID: "sensor.office_temperature",
            title: "Arm alarm",
            action: ActionSpec(
                domain: "alarm_control_panel",
                service: "alarm_arm_home",
                targetEntityID: "alarm_control_panel.home",
                serviceData: [
                    "pin": "1234",
                    "payload": .object([
                        "code": "2468",
                        "profile": "night"
                    ])
                ]
            ),
            requiresConfirmation: true
        )
        try expect(protectedControls.setCustomAction(protectedCustomAction), "panel custom action stores protected payload fields in Keychain")
        guard let storedProtectedAction = protectedControls.customAction(id: protectedCustomAction.id),
              case let .protectedString(pinReference) = storedProtectedAction.action.serviceData["pin"],
              case let .object(protectedPayload) = storedProtectedAction.action.serviceData["payload"],
              case let .protectedString(codeReference) = protectedPayload["code"] else {
            throw SmokeFailure("panel custom action did not persist protected payload references")
        }
        let storedPin = try protectedStore.load(pinReference)
        let storedCode = try protectedStore.load(codeReference)
        try expect(storedPin == "1234", "panel custom action stores root protected value outside JSON config")
        try expect(storedCode == "2468", "panel custom action stores nested protected value outside JSON config")
        let protectedConfigurationText = String(data: try JSONEncoder().encode(protectedControls.customActionConfiguration), encoding: .utf8)
        try expect(protectedConfigurationText?.contains("1234") == false, "panel custom action config omits root secret bytes")
        try expect(protectedConfigurationText?.contains("2468") == false, "panel custom action config omits nested secret bytes")
        let protectedCustomActionSucceeded = await protectedControls.runCustomAction(protectedCustomAction.id, confirmed: true)
        try expect(protectedCustomActionSucceeded, "panel protected custom action resolves secrets before execution")
        let resolvedProtectedAction = await protectedActionRecorder.lastAction()
        try expect(resolvedProtectedAction?.domain == "alarm_control_panel", "panel protected custom action sends configured domain")
        try expect(resolvedProtectedAction?.service == "alarm_arm_home", "panel protected custom action sends configured service")
        try expect(resolvedProtectedAction?.targetEntityID == "alarm_control_panel.home", "panel protected custom action targets configured entity")
        try expect(resolvedProtectedAction?.serviceData["pin"] == "1234", "panel protected custom action resolves root protected values into the live payload")
        guard case let .object(resolvedProtectedPayload)? = resolvedProtectedAction?.serviceData["payload"] else {
            throw SmokeFailure("panel protected custom action preserves nested payload object")
        }
        try expect(resolvedProtectedPayload["code"] == "2468", "panel protected custom action resolves nested protected values into the live payload")
        try expect(resolvedProtectedPayload["profile"] == "night", "panel protected custom action preserves non-secret nested payload values")
        try expect(
            protectedControls.snapshot.availableRooms.flatMap(\.entities).first { $0.id == "sensor.office_temperature" }?.state == "21.4",
            "panel protected custom action does not mutate sensor state"
        )

        let failingControl = PerchHAPanelModel(
            connector: { _ in .success(rooms: controlRooms) },
            actionRunner: { _, _ in .failed("planned service failure") }
        )
        failingControl.updateConnectionForm(urlString: "http://127.0.0.1:8123", token: "fake-token")
        await failingControl.connect()
        let failingControlSucceeded = await failingControl.setEntityControl("switch.office_lamp", isOn: true)
        try expect(!failingControlSucceeded, "panel built-in control reports service failure")
        try expect(
            failingControl.snapshot.availableRooms.flatMap(\.entities).first { $0.id == "switch.office_lamp" }?.state == "off",
            "panel built-in control rolls back after failure"
        )
        try expect(
            failingControl.snapshot.controlActionState == .failed(entityID: "switch.office_lamp", message: "planned service failure"),
            "panel built-in control exposes inline failure state"
        )

        let reorderProbe = SelectionSinkProbe()
        let reorder = PerchHAPanelModel(
            connector: { _ in
                .success(
                    rooms: [
                        Room(
                            id: "office",
                            name: "Office",
                            entities: [
                                DiscoveredEntity(
                                    id: "sensor.office_temperature",
                                    name: "Office temperature",
                                    state: "21.4",
                                    unit: "°C",
                                    areaID: nil,
                                    deviceID: nil
                                ),
                                DiscoveredEntity(
                                    id: "sensor.office_humidity",
                                    name: "Office humidity",
                                    state: "44",
                                    unit: "%",
                                    areaID: nil,
                                    deviceID: nil
                                )
                            ]
                        ),
                        Room(
                            id: "kitchen",
                            name: "Kitchen",
                            entities: [
                                DiscoveredEntity(
                                    id: "switch.kitchen_light",
                                    name: "Kitchen light",
                                    state: "off",
                                    unit: nil,
                                    areaID: nil,
                                    deviceID: nil
                                )
                            ]
                        )
                    ]
                )
            },
            selectionConfiguration: EntitySelectionConfiguration(
                selectedEntityIDs: ["sensor.office_temperature", "sensor.office_humidity", "switch.kitchen_light"],
                isExplicit: true
            ),
            selectionSink: { selection in
                reorderProbe.record(selection)
            }
        )
        reorder.updateConnectionForm(urlString: "http://127.0.0.1:8123", token: "fake-token")
        await reorder.connect()
        try expect(reorder.moveRoom("office", relativeTo: "kitchen", placement: .after), "panel settings drops rooms onto reorder targets")
        try expect(reorder.snapshot.rooms.map(\.id) == ["kitchen", "office"], "panel settings applies moved room order")
        try expect(reorderProbe.lastSelection?.roomOrder == ["kitchen", "office"], "panel settings persists moved room order")
        try expect(
            reorder.moveEntity("sensor.office_temperature", relativeTo: "sensor.office_humidity", placement: .after),
            "panel settings drops entities onto reorder targets"
        )
        try expect(
            reorder.snapshot.rooms.flatMap(\.entities).map(\.id) == ["switch.kitchen_light", "sensor.office_humidity", "sensor.office_temperature"],
            "panel settings applies moved entity order"
        )
        try expect(
            reorderProbe.lastSelection?.selectedEntityIDs == ["switch.kitchen_light", "sensor.office_humidity", "sensor.office_temperature"],
            "panel settings persists moved selected entity order"
        )

        let vanishedProbe = SelectionSinkProbe()
        let vanished = PerchHAPanelModel(
            connector: { _ in
                .success(
                    rooms: [
                        Room(
                            id: "office",
                            name: "Office",
                            entities: [
                                DiscoveredEntity(
                                    id: "sensor.office_temperature",
                                    name: "Office temperature",
                                    state: "21.4",
                                    unit: "°C",
                                    areaID: nil,
                                    deviceID: nil
                                )
                            ]
                        )
                    ]
                )
            },
            selectionConfiguration: EntitySelectionConfiguration(
                selectedEntityIDs: ["sensor.missing", "sensor.office_temperature"],
                isExplicit: true
            ),
            selectionSink: { selection in
                vanishedProbe.record(selection)
            }
        )
        vanished.updateConnectionForm(urlString: "http://127.0.0.1:8123", token: "fake-token")
        await vanished.connect()
        vanished.setEntity("sensor.office_temperature", isSelected: true)
        try expect(vanishedProbe.lastSelection?.selectedEntityIDs == ["sensor.office_temperature"], "panel settings drops vanished selected IDs when saving")
    }

    @MainActor
    private static func verifyAppShellPanelFactory() throws {
        _ = NSApplication.shared
        let panel = PerchHAApplication.makePanel(model: PerchHAPanelModel())
        defer {
            panel.orderOut(nil)
            panel.contentViewController = nil
        }

        let frameSize = panel.frame.size
        try expect(panel.canBecomeKey, "app shell panel accepts first-run text focus")
        try expect(panel.canBecomeMain, "app shell panel can become main while open")
        try expect(panel.styleMask.contains(.nonactivatingPanel), "app shell panel is nonactivating")
        try expect(panel.styleMask.contains(.borderless), "app shell panel is borderless (SwiftUI paints the rounded surface)")
        try expect(!panel.styleMask.contains(.titled), "app shell panel has no titled window chrome")
        try expect(!panel.isOpaque, "app shell panel is transparent so the rounded corners show")
        try expect(panel.backgroundColor == .clear, "app shell panel clears its window background")
        try expect(!panel.hasShadow, "app shell panel defers its shadow to the SwiftUI root")
        try expect(panel.isFloatingPanel, "app shell panel floats above normal windows")
        try expect(panel.hidesOnDeactivate, "app shell panel hides on deactivate")
        try expect(panel.contentViewController != nil, "app shell hosts SwiftUI content")
        try expect(Int(frameSize.width.rounded()) == 384, "app shell panel frame width is stable")
        try expect(Int(frameSize.height.rounded()) >= 468, "app shell panel frame height fits first-run content")

        panel.makeKeyAndOrderFront(nil)
        drainMainRunLoop()
        panel.contentView?.layoutSubtreeIfNeeded()
        let textFields = nativeTextFields(in: panel.contentView)
        let focusDebug = nativeControlDebugSummary(in: panel.contentView)
        let urlField = textFields.first { $0.placeholderString == "Home Assistant URL" }
        let tokenField = textFields.first { $0.placeholderString == "Access token" }
        try expect(urlField != nil, "app shell panel exposes native Home Assistant URL field (\(focusDebug))")
        try expect(tokenField != nil, "app shell panel exposes native token field (\(focusDebug))")

        if let urlField {
            try expect(panel.makeFirstResponder(urlField), "app shell panel accepts native URL field focus")
            let firstResponder = panel.firstResponder as AnyObject?
            try expect(firstResponder === urlField.currentEditor() || firstResponder === urlField, "app shell panel installs the URL field as first responder")
            guard let next = urlField.nextValidKeyView else {
                throw SmokeFailure("app shell panel URL field has no next valid key view")
            }
            try expect(next !== urlField, "app shell panel native key view loop advances from URL field")
        }
        if let tokenField {
            try expect(tokenField.acceptsFirstResponder, "app shell panel token field is natively focusable")
        }
    }

    @MainActor
    private static func verifySettingsCustomActionEditorTextFieldFocusPath() async throws {
        _ = NSApplication.shared
        let model = try await panelSnapshotModel(for: .customActionEditorLight)
        let panel = PerchHAApplication.makeSettingsWindow(model: model, initialTab: .entities, initiallyExpandedEntityIDs: ["sensor.office_humidity"])
        defer {
            panel.orderOut(nil)
            panel.contentView = nil
        }

        panel.makeKeyAndOrderFront(nil)
        drainMainRunLoop()
        panel.contentView?.layoutSubtreeIfNeeded()

        let textFields = nativeTextFields(in: panel.contentView)
        let popUpButtons = nativePopUpButtons(in: panel.contentView)
        let focusDebug = nativeControlDebugSummary(in: panel.contentView)
        let nameField = textFields.first { $0.placeholderString == "Name" }

        try expect(nameField != nil, "settings button editor exposes a native name field (\(focusDebug))")
        try expect(textFields.first { $0.placeholderString == "Title" } == nil, "settings button editor removes the raw title field (\(focusDebug))")
        try expect(textFields.first { $0.placeholderString == "Domain" } == nil, "settings button editor removes the raw domain field (\(focusDebug))")
        try expect(textFields.first { $0.placeholderString == "Service" } == nil, "settings button editor removes the raw service field (\(focusDebug))")
        try expect(textFields.first { $0.placeholderString == "Target entity" } == nil, "settings button editor removes the raw target field (\(focusDebug))")
        try expect(textFields.first { $0.placeholderString == "Key" } == nil, "settings button editor removes the service-data key field (\(focusDebug))")
        try expect(textFields.first { $0.placeholderString == "Value" } == nil, "settings button editor removes the service-data value field (\(focusDebug))")
        let selectedPopupTitles = Set(popUpButtons.compactMap(\.titleOfSelectedItem))
        try expect(selectedPopupTitles.contains("Script: Turn on"), "settings button editor exposes the guided what-it-does selection (\(focusDebug))")
        if let nameField {
            try expect(panel.makeFirstResponder(nameField), "settings button editor accepts native name focus")
            let firstResponder = panel.firstResponder as AnyObject?
            try expect(firstResponder === nameField.currentEditor() || firstResponder === nameField, "settings button editor installs the name field as first responder")
        }
    }

    @MainActor
    private static func verifySettingsCustomActionEditorNativeMutation() async throws {
        _ = NSApplication.shared
        let protectedStore = InMemoryProtectedActionValueStore()
        try protectedStore.save("1234", for: "snapshot-boost-air-pin")
        let snapshot = SmokePanelSnapshotVariant.customActionEditorLight.snapshot
        let model = PerchHAPanelModel(
            snapshot: snapshot,
            selectionConfiguration: snapshot.selectionConfiguration,
            menuBarDisplayConfiguration: snapshot.menuBarDisplayConfiguration,
            customActionConfiguration: SmokePanelSnapshotVariant.customActionEditorLight.customActionConfiguration,
            protectedActionValueStore: protectedStore
        )
        let panel = PerchHAApplication.makeSettingsWindow(model: model, initialTab: .entities, initiallyExpandedEntityIDs: ["sensor.office_humidity"])
        defer {
            panel.orderOut(nil)
            panel.contentView = nil
        }

        panel.makeKeyAndOrderFront(nil)
        drainMainRunLoop()
        panel.contentView?.layoutSubtreeIfNeeded()

        let textFields = nativeTextFields(in: panel.contentView)
        let popUpButtons = nativePopUpButtons(in: panel.contentView)
        let focusDebug = nativeControlDebugSummary(in: panel.contentView)
        guard let nameField = textFields.first(where: { $0.placeholderString == "Name" && $0.stringValue == "Boost air" }) else {
            throw SmokeFailure("settings button editor name field is missing for mutation (\(focusDebug))")
        }
        guard let targetPopUp = popUpButtons.first(where: { $0.titleOfSelectedItem == "script.air_cleaner_boost" }) else {
            throw SmokeFailure("settings button editor target picker is missing for mutation (\(focusDebug))")
        }
        try setNativeTextFieldValue("Boost harder", for: nameField, in: panel)
        try setNativePopUpButtonSelection("Office lamp", for: targetPopUp)

        guard let action = model.customActionConfiguration.action(id: "snapshot-boost-air") else {
            throw SmokeFailure("settings button editor lost the seeded custom action")
        }
        try expect(action.title == "Boost harder", "settings button editor commits name edits through the native name field")
        try expect(action.action.targetEntityID == "switch.office_lamp", "settings button editor commits target edits through the guided target picker")
        guard case let .protectedString(reference) = action.action.serviceData["pin"] else {
            throw SmokeFailure("settings button editor did not preserve protected value reference")
        }
        let storedProtectedValue = try protectedStore.load(reference)
        try expect(storedProtectedValue == "1234", "settings button editor preserves protected values outside JSON config")
        try expect(
            action.action.serviceData == [
                "variables": .object([
                    "steps": .array(["fan", "purifier"])
                ]),
                "pin": .protectedString(reference)
            ],
            "settings button editor preserves the stored service-data payload untouched"
        )
        let encoded = try JSONEncoder().encode(model.customActionConfiguration)
        let text = String(decoding: encoded, as: UTF8.self)
        try expect(!text.contains("1234"), "settings button editor keeps protected values out of JSON config")
        try expect(!focusDebug.contains("1234"), "settings button editor does not leak protected values through visible native control text")
    }

    @MainActor
    private static func verifySettingsCustomActionEditorNativePopupMutation() async throws {
        _ = NSApplication.shared
        let protectedStore = InMemoryProtectedActionValueStore()
        try protectedStore.save("1234", for: "snapshot-boost-air-pin")
        let rooms = [
            Room(
                id: "office",
                name: "Office",
                entities: [
                    DiscoveredEntity(
                        id: "sensor.office_humidity",
                        name: "Office humidity",
                        state: "44",
                        unit: "%",
                        areaID: nil,
                        deviceID: nil
                    )
                ]
            )
        ]
        let snapshot = PerchHAPanelSnapshot(
            connectionState: .connected,
            phase: .connectedData,
            rooms: rooms,
            availableRooms: rooms,
            selectionQuery: "humidity",
            isSettingsPresented: true,
            lastUpdateDescription: "Snapshot ready",
            canRetry: true,
            serviceMetadata: [
                HAServiceMetadata(
                    domain: "script",
                    service: "turn_on",
                    name: "Turn on",
                    description: nil,
                    fields: [
                        HAServiceFieldMetadata(
                            key: "variables",
                            name: "Variables",
                            description: nil,
                            required: false,
                            example: .object([
                                "steps": .array(["fan", "purifier"])
                            ]),
                            selector: .object(["object": .object([:])])
                        ),
                        HAServiceFieldMetadata(
                            key: "pin",
                            name: "PIN",
                            description: "Alarm code",
                            required: false,
                            example: "1234",
                            selector: .object(["text": .object([:])])
                        )
                    ]
                ),
                HAServiceMetadata(
                    domain: "script",
                    service: "turn_off",
                    name: "Turn off",
                    description: nil,
                    fields: [
                        HAServiceFieldMetadata(
                            key: "transition",
                            name: "Transition",
                            description: nil,
                            required: false,
                            example: 3,
                            selector: .object(["number": .object(["min": 0])])
                        )
                    ]
                )
            ]
        )
        let model = PerchHAPanelModel(
            snapshot: snapshot,
            selectionConfiguration: snapshot.selectionConfiguration,
            menuBarDisplayConfiguration: snapshot.menuBarDisplayConfiguration,
            customActionConfiguration: CustomActionConfiguration(actions: [
                EntityCustomAction(
                    id: "snapshot-boost-air",
                    entityID: "sensor.office_humidity",
                    title: "Boost air",
                    action: ActionSpec(
                        domain: "script",
                        service: "turn_on",
                        targetEntityID: "script.air_cleaner_boost",
                        serviceData: [
                            "variables": .object([
                                "steps": .array(["fan", "purifier"])
                            ]),
                            "pin": .protectedString("snapshot-boost-air-pin")
                        ]
                    ),
                    requiresConfirmation: true
                )
            ]),
            protectedActionValueStore: protectedStore
        )
        let panel = PerchHAApplication.makeSettingsWindow(model: model, initialTab: .entities, initiallyExpandedEntityIDs: ["sensor.office_humidity"])
        defer {
            panel.orderOut(nil)
            panel.contentView = nil
        }

        panel.makeKeyAndOrderFront(nil)
        drainMainRunLoop()
        panel.contentView?.layoutSubtreeIfNeeded()

        let popUpButtons = nativePopUpButtons(in: panel.contentView)
        let focusDebug = nativeControlDebugSummary(in: panel.contentView)
        guard let servicePopUp = popUpButtons.first(where: { $0.titleOfSelectedItem == "Script: Turn on" }) else {
            throw SmokeFailure("settings button editor what-it-does picker is missing for mutation (\(focusDebug))")
        }

        try setNativePopUpButtonSelection("Script: Turn off", for: servicePopUp)

        guard let action = model.customActionConfiguration.action(id: "snapshot-boost-air") else {
            throw SmokeFailure("settings button editor lost the seeded custom action after popup mutation")
        }
        try expect(
            action.action.domain == "script" && action.action.service == "turn_off",
            "settings button editor commits the what-it-does selection through the panel model: \(action.action.domain)/\(action.action.service)"
        )
        guard case let .protectedString(reference) = action.action.serviceData["pin"] else {
            throw SmokeFailure("settings button editor preserves protected value references through popup mutation")
        }
        guard case let .object(variables) = action.action.serviceData["variables"] else {
            throw SmokeFailure("settings button editor preserves variables object through popup mutation")
        }
        try expect(
            variables["steps"] == .array(["fan", "purifier"]),
            "settings button editor preserves the stored payload through the what-it-does selection: \(String(describing: variables["steps"]))"
        )
        try expect(
            action.action.serviceData["transition"] == 3,
            "settings button editor applies new metadata defaults after the service change: \(String(describing: action.action.serviceData["transition"]))"
        )
        try expect(
            action.action.serviceData["pin"] == .protectedString(reference),
            "settings button editor keeps protected references through popup mutation: \(String(describing: action.action.serviceData["pin"]))"
        )
    }

    @MainActor
    private static func verifyBuiltInControlsPanelFactory() async throws {
        _ = NSApplication.shared
        let model = try await panelSnapshotModel(for: .builtInControlsLight)
        let panel = PerchHAApplication.makePanel(model: model)
        defer {
            panel.orderOut(nil)
            panel.contentViewController = nil
        }

        panel.makeKeyAndOrderFront(nil)
        drainMainRunLoop()
        panel.contentView?.layoutSubtreeIfNeeded()

        let switches = nativeSwitches(in: panel.contentView)
        let sliders = nativeSliders(in: panel.contentView)
        let buttons = nativeButtons(in: panel.contentView)
        let focusDebug = nativeControlDebugSummary(in: panel.contentView)
        let controlSwitch = switches.first
        let coverSlider = sliders.first
        let coverButtons = buttons.filter { String(describing: type(of: $0)).contains("SwiftUIAppKitButton") }

        try expect(switches.count == 1, "built-in controls panel exposes exactly one native switch in the built-in controls state (\(focusDebug))")
        try expect(sliders.count == 1, "built-in controls panel exposes exactly one native slider in the built-in controls state (\(focusDebug))")
        try expect(coverButtons.count >= 3, "built-in controls panel exposes native cover buttons in the built-in controls state (\(focusDebug))")
        try expect(
            controlSwitch.map { String(describing: type(of: $0)).contains("PlatformSwitch") } == true,
            "built-in controls panel uses the native switch control class for toggle rows (\(focusDebug))"
        )
        try expect(
            coverSlider.map { String(describing: type(of: $0)).contains("CustomMarkedSlider") } == true,
            "built-in controls panel uses the marked native slider class for cover position (\(focusDebug))"
        )
        if let controlSwitch {
            try expect(controlSwitch.acceptsFirstResponder, "built-in controls native switch can accept focus (\(focusDebug))")
            try expect(panel.makeFirstResponder(controlSwitch), "built-in controls panel accepts built-in switch focus")
            let firstResponder = panel.firstResponder as AnyObject?
            try expect(firstResponder === controlSwitch || firstResponder === controlSwitch.currentEditor(), "built-in controls panel installs the built-in switch as first responder")
        }
        if let slider = coverSlider {
            try expect(slider.acceptsFirstResponder, "built-in controls native slider can accept focus (\(focusDebug))")
            try expect(panel.makeFirstResponder(slider), "built-in controls panel accepts built-in cover slider focus")
            let firstResponder = panel.firstResponder as AnyObject?
            try expect(firstResponder === slider || firstResponder === slider.currentEditor(), "built-in controls panel installs the built-in cover slider as first responder")
        }
    }

    @MainActor
    private static func setNativeTextFieldValue(_ value: String, for textField: NSTextField, in panel: NSWindow) throws {
        try expect(panel.makeFirstResponder(textField), "panel accepts focus for native text field mutation")
        drainMainRunLoop()
        if let editor = textField.currentEditor() {
            editor.string = value
            textField.stringValue = value
            NotificationCenter.default.post(
                name: NSControl.textDidChangeNotification,
                object: textField,
                userInfo: ["NSFieldEditor": editor]
            )
            NotificationCenter.default.post(
                name: NSControl.textDidEndEditingNotification,
                object: textField,
                userInfo: ["NSFieldEditor": editor]
            )
        }
        textField.stringValue = value
        textField.validateEditing()
        textField.sendAction(textField.action, to: textField.target)
        panel.endEditing(for: nil)
        _ = panel.makeFirstResponder(nil)
        drainMainRunLoop()
    }

    @MainActor
    private static func setNativePopUpButtonSelection(_ title: String, for popUpButton: NSPopUpButton) throws {
        try expect(popUpButton.itemTitles.contains(title), "native popup exposes requested selection \(title)")
        popUpButton.selectItem(withTitle: title)
        popUpButton.synchronizeTitleAndSelectedItem()
        if let index = popUpButton.indexOfSelectedItem as Int?, index >= 0 {
            popUpButton.menu?.performActionForItem(at: index)
        }
        if let action = popUpButton.action {
            _ = NSApp.sendAction(action, to: popUpButton.target, from: popUpButton)
        }
        popUpButton.sendAction(popUpButton.action, to: popUpButton.target)
        drainMainRunLoop()
    }

    @MainActor
    private static func nativeTextFields(in root: NSView?) -> [NSTextField] {
        guard let root else {
            return []
        }
        var result: [NSTextField] = []
        func collect(_ view: NSView) {
            if let textField = view as? NSTextField, !textField.isHiddenOrHasHiddenAncestor, textField.isEditable {
                result.append(textField)
            }
            view.subviews.forEach(collect)
        }
        collect(root)
        return result
    }

    @MainActor
    private static func nativeSwitches(in root: NSView?) -> [NSSwitch] {
        guard let root else {
            return []
        }
        var result: [NSSwitch] = []
        func collect(_ view: NSView) {
            if let controlSwitch = view as? NSSwitch, !controlSwitch.isHiddenOrHasHiddenAncestor {
                result.append(controlSwitch)
            }
            view.subviews.forEach(collect)
        }
        collect(root)
        return result
    }

    @MainActor
    private static func nativeSliders(in root: NSView?) -> [NSSlider] {
        guard let root else {
            return []
        }
        var result: [NSSlider] = []
        func collect(_ view: NSView) {
            if let slider = view as? NSSlider, !slider.isHiddenOrHasHiddenAncestor {
                result.append(slider)
            }
            view.subviews.forEach(collect)
        }
        collect(root)
        return result
    }

    @MainActor
    private static func nativeButtons(in root: NSView?) -> [NSButton] {
        guard let root else {
            return []
        }
        var result: [NSButton] = []
        func collect(_ view: NSView) {
            if let button = view as? NSButton, !button.isHiddenOrHasHiddenAncestor {
                result.append(button)
            }
            view.subviews.forEach(collect)
        }
        collect(root)
        return result
    }

    @MainActor
    private static func nativePopUpButtons(in root: NSView?) -> [NSPopUpButton] {
        guard let root else {
            return []
        }
        var result: [NSPopUpButton] = []
        func collect(_ view: NSView) {
            if let popUpButton = view as? NSPopUpButton, !popUpButton.isHiddenOrHasHiddenAncestor {
                result.append(popUpButton)
            }
            view.subviews.forEach(collect)
        }
        collect(root)
        return result
    }

    @MainActor
    private static func nativeKeyViewLoopLabels(startingAt start: NSView) -> [String] {
        var labels: [String] = []
        var visited: Set<ObjectIdentifier> = []
        var current: NSView? = start

        while let view = current, labels.count < 64 {
            let identifier = ObjectIdentifier(view)
            if !visited.insert(identifier).inserted {
                break
            }
            labels.append(nativeControlLabel(for: view))
            current = view.nextValidKeyView
        }

        return labels
    }

    @MainActor
    private static func nativeControlLabel(for view: NSView) -> String {
        if let textField = view as? NSTextField {
            let placeholder = textField.placeholderString ?? ""
            return "\(type(of: view))(placeholder:\(placeholder))"
        }
        if let button = view as? NSButton {
            let label = button.accessibilityLabel() ?? ""
            return "\(type(of: view))(title:\(button.title),label:\(label))"
        }
        return String(describing: type(of: view))
    }

    @MainActor
    private static func nativeControlDebugSummary(in root: NSView?) -> String {
        guard let root else {
            return "no-root-view"
        }
        var result: [String] = []
        func collect(_ view: NSView) {
            if let control = view as? NSControl {
                let placeholder = (control as? NSTextField)?.placeholderString ?? ""
                let title = control is NSButton ? (control as? NSButton)?.title ?? "" : ""
                let label = control.accessibilityLabel() ?? ""
                result.append("\(type(of: control))(placeholder:\(placeholder),title:\(title),label:\(label),enabled:\(control.isEnabled),hidden:\(control.isHiddenOrHasHiddenAncestor))")
            }
            view.subviews.forEach(collect)
        }
        collect(root)
        return result.prefix(12).joined(separator: " | ")
    }

    @MainActor
    private static func verifyPanelOpenPerformance() throws {
        _ = try measureCachedPanelOpenNanoseconds()
        let samples = try (0..<9).map { _ in
            try measureCachedPanelOpenNanoseconds()
        }
        let sortedSamples = samples.sorted()
        let median = sortedSamples[sortedSamples.count / 2]
        let maximum = sortedSamples[sortedSamples.index(before: sortedSamples.endIndex)]

        try expect(
            median <= SmokePerformanceBudget.panelOpenMedianNanoseconds,
            "cached panel open median exceeds \(SmokePerformanceBudget.panelOpenMedianMilliseconds) ms: \(milliseconds(median)) ms"
        )
        try expect(
            maximum <= SmokePerformanceBudget.panelOpenMaximumNanoseconds,
            "cached panel open max exceeds \(SmokePerformanceBudget.panelOpenMaximumMilliseconds) ms: \(milliseconds(maximum)) ms"
        )
    }

    @MainActor
    private static func measureCachedPanelOpenNanoseconds() throws -> UInt64 {
        let model = PerchHAPanelModel(
            snapshot: SmokePanelSnapshotVariant.connectedLight.snapshot,
            customActionConfiguration: SmokePanelSnapshotVariant.connectedLight.customActionConfiguration
        )
        let start = DispatchTime.now().uptimeNanoseconds
        let panel = PerchHAApplication.makePanel(model: model)
        panel.orderFrontRegardless()
        panel.contentView?.layoutSubtreeIfNeeded()
        panel.displayIfNeeded()
        let elapsed = DispatchTime.now().uptimeNanoseconds - start
        panel.orderOut(nil)
        panel.contentViewController = nil
        return elapsed
    }

    private static func milliseconds(_ nanoseconds: UInt64) -> String {
        String(format: "%.2f", Double(nanoseconds) / 1_000_000)
    }

    @MainActor
    private static func verifyApplicationLifecycleMemorySoak() async throws {
        _ = NSApplication.shared
        let server = try FakeHAWebSocketServer(fixtures: appShellPerformanceFixtures)
        server.start()
        defer {
            server.stop()
        }
        let client = HomeAssistantClient()
        let connector = fakeHAConnector(client: client)
        let serviceMetadataProvider = fakeHAServiceMetadataProvider(client: client)

        for _ in 0..<SmokePerformanceBudget.lifecycleSoakWarmupIterations {
            try await runApplicationLifecycleSoakIteration(
                server: server,
                connector: connector,
                serviceMetadataProvider: serviceMetadataProvider
            )
        }
        drainMainRunLoop()
        let baseline = try residentMemoryBytes()

        for _ in 0..<SmokePerformanceBudget.lifecycleSoakMeasuredIterations {
            try await runApplicationLifecycleSoakIteration(
                server: server,
                connector: connector,
                serviceMetadataProvider: serviceMetadataProvider
            )
        }
        drainMainRunLoop()
        let afterSoak = try residentMemoryBytes()
        let growth = afterSoak > baseline ? afterSoak - baseline : 0
        try expect(
            growth <= SmokePerformanceBudget.lifecycleSoakMaximumGrowthBytes,
            "app shell lifecycle memory grew \(megabytes(growth)) MB after \(SmokePerformanceBudget.lifecycleSoakMeasuredIterations) iterations"
        )
    }

    @MainActor
    private static func verifyIdleCPUAtRest() async throws {
        _ = NSApplication.shared
        let server = try FakeHAWebSocketServer(fixtures: appShellPerformanceFixtures)
        server.start()
        defer {
            server.stop()
        }
        let client = HomeAssistantClient()
        let connector = fakeHAConnector(client: client)
        let serviceMetadataProvider = fakeHAServiceMetadataProvider(client: client)
        let configURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("perchha-smoke-idle-cpu-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("config.json")
        defer {
            try? FileManager.default.removeItem(at: configURL.deletingLastPathComponent())
        }
        let store = JSONConfigStore(fileURL: configURL)
        _ = try store.save(
            PerchHAConfiguration(
                selectedEntityIDs: ["sensor.office_humidity", "sensor.energy_today"],
                menuBarEntityIDs: ["sensor.office_humidity"],
                isEntitySelectionExplicit: true
            )
        )
        let application = PerchHAApplication(
            configStore: store,
            connector: connector,
            serviceMetadataProvider: serviceMetadataProvider
        )
        application.applicationDidFinishLaunching(Notification(name: NSApplication.didFinishLaunchingNotification))
        defer {
            application.applicationWillTerminate(Notification(name: NSApplication.willTerminateNotification))
            drainMainRunLoop()
        }
        application.updateConnectionForm(urlString: server.baseURL.absoluteString, token: "fake-token")
        await application.connect()
        try expect(application.snapshot.statusItemTitle == "44%", "idle CPU launches connected app shell")
        try expect(application.setMenuBarDisplayStyle("sensor.office_humidity", style: .battery), "idle CPU renders stable gauge once")
        runMainRunLoop(for: SmokePerformanceBudget.idleWarmupSeconds)

        let cpuStart = try processCPUTimeSeconds()
        runMainRunLoop(for: SmokePerformanceBudget.idleObservationSeconds)
        let cpuSeconds = try processCPUTimeSeconds() - cpuStart

        try expect(
            cpuSeconds <= SmokePerformanceBudget.idleMaximumCPUSeconds,
            "idle app shell used \(seconds(cpuSeconds)) CPU seconds over \(seconds(SmokePerformanceBudget.idleObservationSeconds)) observed seconds"
        )
    }

    private static var appShellPerformanceFixtures: FakeHAFixtures {
        FakeHAFixtures(
            apiBody: #"{"message":"API running."}"#,
            statesBody: #"[{"entity_id":"sensor.office_humidity","state":"44","attributes":{"friendly_name":"Office humidity","unit_of_measurement":"%"}},{"entity_id":"sensor.energy_today","state":"30","attributes":{"friendly_name":"Energy today","unit_of_measurement":"kWh"}},{"entity_id":"sensor.energy_budget","state":"120","attributes":{"friendly_name":"Energy budget","unit_of_measurement":"kWh"}}]"#,
            areaRegistryBody: #"[{"area_id":"office","name":"Office"}]"#,
            deviceRegistryBody: #"[]"#,
            entityRegistryDisplayBody: #"{"entities":[{"ei":"sensor.office_humidity","en":"Office humidity","ai":"office"},{"ei":"sensor.energy_today","en":"Energy today","ai":"office"},{"ei":"sensor.energy_budget","en":"Energy budget","ai":"office"}]}"#,
            entityRegistryBody: #"[]"#,
            servicesBody: #"{}"#
        )
    }

    private static func fakeHAConnector(client: HomeAssistantClient) -> PerchHAPanelModel.Connector {
        { form in
            guard let primaryURL = form.primaryURL() else {
                return .failure(.protocolError("invalid Home Assistant URL"))
            }
            let input = HAConnectionInput(
                endpoint: HAEndpoint(primaryURL: primaryURL, fallbackURL: form.fallbackURL()),
                token: form.trimmedToken
            )
            switch await client.discovery(input) {
            case let .success(snapshot):
                return .success(rooms: RoomResolver().resolve(snapshot: snapshot))
            case let .failure(failure):
                return .failure(failure.connectionFailure)
            }
        }
    }

    private static func fakeHAServiceMetadataProvider(client: HomeAssistantClient) -> PerchHAPanelModel.ServiceMetadataProvider {
        { form in
            guard let primaryURL = form.primaryURL() else {
                return .unavailable("invalid Home Assistant URL")
            }
            let input = HAConnectionInput(
                endpoint: HAEndpoint(primaryURL: primaryURL, fallbackURL: form.fallbackURL()),
                token: form.trimmedToken
            )
            switch await client.services(input) {
            case let .success(metadata):
                return .success(metadata)
            case let .failure(failure):
                return .unavailable(failure.description)
            }
        }
    }

    @MainActor
    private static func runApplicationLifecycleSoakIteration(
        server: FakeHAWebSocketServer,
        connector: @escaping PerchHAPanelModel.Connector,
        serviceMetadataProvider: @escaping PerchHAPanelModel.ServiceMetadataProvider
    ) async throws {
        let configURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("perchha-smoke-lifecycle-soak-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("config.json")
        defer {
            try? FileManager.default.removeItem(at: configURL.deletingLastPathComponent())
        }
        let store = JSONConfigStore(fileURL: configURL)
        _ = try store.save(
            PerchHAConfiguration(
                selectedEntityIDs: ["sensor.office_humidity", "sensor.energy_today"],
                menuBarEntityIDs: ["sensor.office_humidity"],
                isEntitySelectionExplicit: true
            )
        )
        let application = PerchHAApplication(
            configStore: store,
            connector: connector,
            serviceMetadataProvider: serviceMetadataProvider
        )
        application.applicationDidFinishLaunching(Notification(name: NSApplication.didFinishLaunchingNotification))
        application.updateConnectionForm(urlString: server.baseURL.absoluteString, token: "fake-token")
        await application.connect()
        try expect(application.snapshot.hasPanel, "memory soak launches panel")
        try expect(application.snapshot.hasPanelModel, "memory soak launches panel model")
        try expect(application.snapshot.statusItemTitle == "44%", "memory soak renders promoted status item")
        try expect(application.setMenuBarDisplayStyle("sensor.office_humidity", style: .battery), "memory soak enables gauge style")
        try expect(application.snapshot.statusItemHasImage, "memory soak renders status item image")
        try expect(
            application.applyLiveState(EntityState(id: "sensor.office_humidity", name: "Office humidity", state: "45", unit: "%")),
            "memory soak applies live value update"
        )
        application.applicationWillTerminate(Notification(name: NSApplication.willTerminateNotification))
        let released = application.snapshot
        try expect(!released.hasPanel, "memory soak releases panel")
        try expect(!released.hasPanelModel, "memory soak releases panel model")
        try expect(released.statusItemTitle == nil, "memory soak removes status item")
        drainMainRunLoop()
    }

    private static func residentMemoryBytes() throws -> UInt64 {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size / MemoryLayout<natural_t>.size)
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { rebound in
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), rebound, &count)
            }
        }
        guard result == KERN_SUCCESS else {
            throw SmokeFailure("could not read resident memory: \(result)")
        }
        return UInt64(info.resident_size)
    }

    private static func megabytes(_ bytes: UInt64) -> String {
        String(format: "%.2f", Double(bytes) / 1_048_576)
    }

    private static func processCPUTimeSeconds() throws -> Double {
        var usage = rusage()
        guard getrusage(RUSAGE_SELF, &usage) == 0 else {
            throw SmokeFailure("could not read process CPU time")
        }
        return timeValueSeconds(usage.ru_utime) + timeValueSeconds(usage.ru_stime)
    }

    private static func timeValueSeconds(_ value: timeval) -> Double {
        Double(value.tv_sec) + (Double(value.tv_usec) / 1_000_000)
    }

    private static func seconds(_ value: Double) -> String {
        String(format: "%.3f", value)
    }

    @MainActor
    private static func drainMainRunLoop() {
        for _ in 0..<3 {
            _ = RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.001))
        }
    }

    @MainActor
    private static func runMainRunLoop(for seconds: Double) {
        let end = Date(timeIntervalSinceNow: seconds)
        repeat {
            _ = RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.01))
        } while Date() < end
    }

    @MainActor
    private static func verifyPanelSnapshotRendering(options: SmokeOptions) async throws {
        var signatures: [SmokePanelSnapshotVariant: SmokePanelRenderSignature] = [:]
        var captures: [(variant: SmokePanelSnapshotVariant, bitmap: NSBitmapImageRep)] = []
        let exportDirectory = panelSnapshotExportDirectory()
        if let exportDirectory {
            try? FileManager.default.removeItem(at: exportDirectory)
            try FileManager.default.createDirectory(at: exportDirectory, withIntermediateDirectories: true)
        }
        for variant in SmokePanelSnapshotVariant.allCases {
            let capture = try await renderPanelSnapshot(variant)
            signatures[variant] = capture.signature
            captures.append((variant: variant, bitmap: capture.bitmap))
            if let exportDirectory {
                try writePanelSnapshot(capture.bitmap, variant: variant, to: exportDirectory)
            }
            try expect(capture.signature.pixelsWide >= 360, "\(variant.rawValue) snapshot has expected width")
            try expect(capture.signature.pixelsHigh >= 420, "\(variant.rawValue) snapshot has expected height")
            try expect(capture.signature.visiblePixelCount > 1_500, "\(variant.rawValue) snapshot is not blank")
            try expect(capture.signature.topEdgeVisiblePixelCount > capture.signature.pixelsWide * 9 / 10, "\(variant.rawValue) snapshot top edge is filled")
            try expect(capture.signature.bottomEdgeVisiblePixelCount > capture.signature.pixelsWide * 9 / 10, "\(variant.rawValue) snapshot bottom edge is filled")
        }
        let baselineVariants = SmokePanelSnapshotVariant.allCases.compactMap { variant in
            signatures[variant].map {
                SmokePanelReviewBaseline.Entry(
                    name: "\(variant.rawValue).png",
                    signature: $0
                )
            }
        }
        try expect(
            baselineVariants.count == SmokePanelSnapshotVariant.allCases.count,
            "panel snapshot baseline includes every rendered variant"
        )
        let contactSheetEntry: SmokePanelReviewBaseline.Entry
        if let exportDirectory {
            let contactSheet = try writePanelReviewContactSheet(captures, to: exportDirectory)
            let contactSheetSignature = SmokePanelRenderSignature(bitmap: contactSheet)
            try expect(contactSheetSignature.visiblePixelCount > 15_000, "panel review contact sheet is not blank")
            try expect(
                FileManager.default.fileExists(atPath: exportDirectory.appendingPathComponent("review-contact-sheet.png").path),
                "panel review contact sheet is exported"
            )
            contactSheetEntry = SmokePanelReviewBaseline.Entry(
                name: "review-contact-sheet.png",
                signature: contactSheetSignature
            )
        } else {
            let contactSheet = try renderPanelReviewContactSheet(captures)
            let contactSheetSignature = SmokePanelRenderSignature(bitmap: contactSheet)
            try expect(contactSheetSignature.visiblePixelCount > 15_000, "panel review contact sheet is not blank")
            contactSheetEntry = SmokePanelReviewBaseline.Entry(
                name: "review-contact-sheet.png",
                signature: contactSheetSignature
            )
        }
        let reviewBaseline = SmokePanelReviewBaseline(
            variants: baselineVariants,
            contactSheet: contactSheetEntry
        )
        if let exportDirectory {
            let storedBaseline = options.updatesReviewBaseline
                ? reviewBaseline
                : try loadPanelReviewBaseline(from: options.reviewBaselineURL)
            try writePanelReviewBaseline(
                reviewBaseline,
                to: exportDirectory.appendingPathComponent("review-baseline-current.json", isDirectory: false)
            )
            try expect(
                FileManager.default.fileExists(atPath: exportDirectory.appendingPathComponent("review-baseline-current.json").path),
                "panel review baseline report is exported"
            )
            try writePanelReviewBaseline(
                storedBaseline,
                to: exportDirectory.appendingPathComponent(
                    PerchHAReleaseEvidenceReview.expectedBaselineFilename,
                    isDirectory: false
                )
            )
            try expect(
                FileManager.default.fileExists(
                    atPath: exportDirectory.appendingPathComponent(
                        PerchHAReleaseEvidenceReview.expectedBaselineFilename
                    ).path
                ),
                "panel stored review baseline is exported"
            )
        }
        if options.updatesReviewBaseline {
            try writePanelReviewBaseline(reviewBaseline, to: options.reviewBaselineURL)
            try expect(
                FileManager.default.fileExists(atPath: options.reviewBaselineURL.path),
                "panel review baseline is written"
            )
        } else {
            let storedBaseline = try loadPanelReviewBaseline(from: options.reviewBaselineURL)
            try expect(
                storedBaseline == reviewBaseline,
                reviewBaselineMismatchMessage(
                    expected: storedBaseline,
                    actual: reviewBaseline,
                    baselineURL: options.reviewBaselineURL
                )
            )
        }

        guard let connectedLight = signatures[.connectedLight],
              let connectedDark = signatures[.connectedDark],
              let increasedContrast = signatures[.connectedDarkIncreasedContrast],
              let reducedMotion = signatures[.connectedLightReducedMotion],
              let historyLoaded = signatures[.historyLoadedLight],
              let historyLoadedIncreasedContrast = signatures[.historyLoadedLightIncreasedContrast],
              let customActionEditor = signatures[.customActionEditorLight],
              let builtInControls = signatures[.builtInControlsLight],
              let firstRun = signatures[.firstRunLight],
              let connecting = signatures[.connectingLight],
              let signingIn = signatures[.signingInLight],
              let settingsSelection = signatures[.settingsSelectionLight],
              let reconnecting = signatures[.reconnectingLight],
              let emptyLight = signatures[.emptyLight],
              let errorDark = signatures[.errorDark]
        else {
            throw SmokeFailure("panel snapshot signatures missing")
        }

        try expect(
            connectedLight.sampledHash != connectedDark.sampledHash,
            "dashboard popover renders a designed light and a designed dark appearance (it follows the resolved theme)"
        )
        try expect(
            connectedDark.sampledHash != increasedContrast.sampledHash,
            "dashboard popover still distinguishes increased contrast"
        )
        try expect(
            reducedMotion.pixelsWide == connectedLight.pixelsWide && reducedMotion.pixelsHigh == connectedLight.pixelsHigh,
            "panel reduced-motion snapshot preserves stable dimensions"
        )
        try expect(
            historyLoaded.sampledHash != connectedLight.sampledHash,
            "panel history-loaded snapshot renders distinct chart state"
        )
        try expect(
            historyLoadedIncreasedContrast.sampledHash != historyLoaded.sampledHash,
            "panel history-loaded snapshot distinguishes increased contrast"
        )
        try expect(
            customActionEditor.sampledHash != connectedLight.sampledHash,
            "panel custom-action editor snapshot renders distinct settings state"
        )
        try expect(
            builtInControls.sampledHash != connectedLight.sampledHash,
            "panel built-in controls snapshot renders distinct control state"
        )
        try expect(
            firstRun.sampledHash != connectedLight.sampledHash,
            "panel first-run snapshot renders distinct onboarding state"
        )
        try expect(
            connecting.sampledHash != firstRun.sampledHash,
            "panel connecting snapshot renders distinct loading state"
        )
        try expect(
            signingIn.sampledHash != firstRun.sampledHash,
            "panel signing-in snapshot renders distinct OAuth loading state"
        )
        try expect(
            settingsSelection.sampledHash != connectedLight.sampledHash,
            "panel settings selection snapshot renders distinct selection state"
        )
        let connectingModel = try await panelSnapshotModel(for: .connectingLight)
        try expect(
            connectingModel.snapshot.accessibilityPresentation().contentLabel == "Connecting to Home Assistant",
            "panel connecting snapshot exposes loading accessibility state"
        )
        let signingInModel = try await panelSnapshotModel(for: .signingInLight)
        defer {
            signingInModel.cancelInFlightAction()
        }
        try expect(
            signingInModel.oauthSignInState == .signingIn,
            "panel signing-in snapshot uses public OAuth sign-in state"
        )
        try expect(
            reconnecting.sampledHash != connectedLight.sampledHash,
            "panel reconnecting snapshot renders distinct stale state"
        )
        let settingsSelectionModel = try await panelSnapshotModel(for: .settingsSelectionLight)
        let selectedState = settingsSelectionModel.snapshot.selectionTree.flatMap { room in
            room.entities.map { selectable in
                "\(selectable.entity.id.rawValue):\(selectable.isSelected)"
            }
        }
        try expect(
            selectedState == [
                "switch.kitchen_light:true",
                "sensor.office_humidity:true",
                "switch.office_lamp:false",
                "cover.office_blinds:false"
            ],
            "panel settings selection snapshot preserves explicit selected rows"
        )
        try expect(
            settingsSelectionModel.snapshot.menuBarDisplayConfiguration.promotedEntityIDs == ["sensor.office_humidity"],
            "panel settings selection snapshot preserves menu bar promotion"
        )
        let reconnectingModel = try await panelSnapshotModel(for: .reconnectingLight)
        guard let reconnectingEntity = reconnectingModel.snapshot.rooms.first?.entities.first else {
            throw SmokeFailure("panel reconnecting snapshot has no visible entity")
        }
        try expect(
            reconnectingModel.snapshot.formattedValue(
                for: reconnectingEntity,
                locale: Locale(identifier: "en_US")
            ).text.hasPrefix("Stale:"),
            "panel reconnecting snapshot renders stale values"
        )
        try expect(
            Set([
                connectedLight.sampledHash,
                historyLoaded.sampledHash,
                historyLoadedIncreasedContrast.sampledHash,
                customActionEditor.sampledHash,
                builtInControls.sampledHash,
                firstRun.sampledHash,
                connecting.sampledHash,
                signingIn.sampledHash,
                settingsSelection.sampledHash,
                reconnecting.sampledHash,
                emptyLight.sampledHash,
                errorDark.sampledHash
            ]).count == 12,
            "panel snapshots distinguish success, history, increased-contrast history, custom action, controls, first-run, connecting, signing-in, settings, reconnecting, empty, and error states"
        )
    }

    @MainActor
    private static func panelSnapshotModel(for variant: SmokePanelSnapshotVariant) async throws -> PerchHAPanelModel {
        let snapshot = variant.snapshot
        if variant.warmsInlineHistory {
            return try await warmedInlineHistoryModel(for: variant)
        }
        let model = PerchHAPanelModel(
            snapshot: snapshot,
            oauthSignInRunner: variant.oauthSignInRunner,
            selectionConfiguration: snapshot.selectionConfiguration,
            menuBarDisplayConfiguration: snapshot.menuBarDisplayConfiguration,
            customActionConfiguration: variant.customActionConfiguration
        )
        if variant.startsOAuthSignInForSnapshot {
            model.startOAuthSignIn()
            for _ in 0..<100 {
                if model.oauthSignInState == PerchHAOAuthSignInState.signingIn {
                    break
                }
                await Task.yield()
            }
            try expect(
                model.oauthSignInState == PerchHAOAuthSignInState.signingIn,
                "\(variant.rawValue) snapshot reaches OAuth sign-in state"
            )
        }
        return model
    }

    /// Builds a connected panel model whose inline-history cache has been warmed
    /// through the real public prefetch path (panel active + visible entities +
    /// settle-delay clock advance), so the graph-forward rows render their
    /// full-width sparkline and state-timeline bands from cache without any
    /// render-time fetch. Mirrors the prefetch coordinator's own flow rather than
    /// poking private cache state.
    @MainActor
    private static func warmedInlineHistoryModel(
        for variant: SmokePanelSnapshotVariant
    ) async throws -> PerchHAPanelModel {
        let snapshot = variant.snapshot
        let clock = TestPerchClock()
        let settleDelay = PerchDuration.milliseconds(250)
        let series = SmokePanelSnapshotVariant.inlineHistorySeries
        let model = PerchHAPanelModel(
            snapshot: snapshot,
            connector: { _ in .success(rooms: snapshot.rooms) },
            historyProvider: { _, entityID, range in
                guard let match = series[entityID], match.range == range else {
                    return .unavailable("no warmed series")
                }
                return .success(match)
            },
            oauthSignInRunner: variant.oauthSignInRunner,
            clock: clock,
            historyPrefetchConfiguration: PerchHAHistoryPrefetchConfiguration(settleDelay: settleDelay),
            selectionConfiguration: snapshot.selectionConfiguration,
            menuBarDisplayConfiguration: snapshot.menuBarDisplayConfiguration,
            customActionConfiguration: variant.customActionConfiguration
        )
        model.updateConnectionForm(urlString: "http://127.0.0.1:8123", token: "fake-token")
        await model.connect()
        model.setPanelActive(true)
        model.updateVisibleEntities(snapshot.rooms.flatMap(\.entities).map(\.id))
        for _ in 0..<200 where await clock.sleepingTaskCount() != 1 {
            await Task.yield()
        }
        _ = await clock.advance(by: settleDelay)
        let expected = series.keys.count
        for _ in 0..<200 {
            let warmed = series.keys.filter { model.cachedHistorySeries(for: $0) != nil }.count
            if warmed >= expected {
                break
            }
            await Task.yield()
        }
        try expect(
            series.keys.allSatisfy { model.cachedHistorySeries(for: $0) != nil },
            "\(variant.rawValue) snapshot warms inline history cache"
        )
        return model
    }

    @MainActor
    private static func renderPanelSnapshot(_ variant: SmokePanelSnapshotVariant) async throws -> SmokePanelRenderCapture {
        let model = try await panelSnapshotModel(for: variant)
        defer {
            if variant.startsOAuthSignInForSnapshot {
                model.cancelInFlightAction()
            }
        }
        let view: AnyView
        let size: NSSize
        if variant == .historyLoadedLight || variant == .historyLoadedLightIncreasedContrast {
            view = AnyView(
                PerchHAHistoryPopoverContent(
                    entityID: "sensor.office_humidity",
                    entityName: "Office humidity",
                    valueText: "44%",
                    state: .loaded(SmokePanelSnapshotVariant.loadedHistorySeries),
                    increaseContrastOverride: variant.colorSchemeContrast == .increased,
                    selectedRange: .constant(.day)
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .background(Color(nsColor: NSColor.windowBackgroundColor))
                .environment(\.colorScheme, variant.colorScheme)
            )
            size = NSSize(width: 360, height: 420)
        } else if variant == .customActionEditorLight || variant == .settingsSelectionLight {
            view = AnyView(
                PerchHASettingsView(
                    model: model,
                    accessibilityPreferencesOverride: variant.accessibilityPreferences,
                    initialTab: .entities,
                    initiallyExpandedEntityIDs: ["sensor.office_humidity"]
                )
                .tabContentForSnapshot(.entities)
                .environment(\.colorScheme, variant.colorScheme)
            )
            size = NSSize(width: 520, height: 560)
        } else {
            view = AnyView(
                PerchHAPanelView(
                    model: model,
                    accessibilityPreferencesOverride: variant.accessibilityPreferences
                )
                .environment(\.colorScheme, variant.colorScheme)
            )
            size = NSSize(width: 384, height: 468)
        }
        let hostingView = NSHostingView(rootView: view)

        hostingView.appearance = NSAppearance(named: variant.appearanceName)
        hostingView.frame = NSRect(origin: .zero, size: size)
        hostingView.layoutSubtreeIfNeeded()
        hostingView.displayIfNeeded()

        guard let bitmap = hostingView.bitmapImageRepForCachingDisplay(in: hostingView.bounds) else {
            throw SmokeFailure("\(variant.rawValue) snapshot bitmap allocation failed")
        }
        bitmap.size = hostingView.bounds.size
        hostingView.cacheDisplay(in: hostingView.bounds, to: bitmap)
        return SmokePanelRenderCapture(bitmap: bitmap)
    }

    private static func panelSnapshotExportDirectory() -> URL? {
        guard let value = ProcessInfo.processInfo.environment["PERCHHA_SMOKE_SNAPSHOT_DIR"]?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty
        else {
            return nil
        }
        return URL(fileURLWithPath: value, isDirectory: true)
            .appendingPathComponent("current", isDirectory: true)
    }

    private static func writePanelSnapshot(
        _ bitmap: NSBitmapImageRep,
        variant: SmokePanelSnapshotVariant,
        to directory: URL
    ) throws {
        guard let data = bitmap.representation(using: .png, properties: [:]) else {
            throw SmokeFailure("\(variant.rawValue) snapshot PNG export failed")
        }
        try data.write(to: directory.appendingPathComponent("\(variant.rawValue).png", isDirectory: false), options: .atomic)
    }

    @MainActor
    private static func writePanelReviewContactSheet(
        _ captures: [(variant: SmokePanelSnapshotVariant, bitmap: NSBitmapImageRep)],
        to directory: URL
    ) throws -> NSBitmapImageRep {
        let output = try renderPanelReviewContactSheet(captures)
        guard let data = output.representation(using: .png, properties: [:]) else {
            throw SmokeFailure("panel review contact sheet PNG export failed")
        }
        try data.write(to: directory.appendingPathComponent("review-contact-sheet.png", isDirectory: false), options: .atomic)
        return output
    }

    @MainActor
    private static func renderPanelReviewContactSheet(
        _ captures: [(variant: SmokePanelSnapshotVariant, bitmap: NSBitmapImageRep)]
    ) throws -> NSBitmapImageRep {
        let columns = 3
        let thumbnailSize = NSSize(width: 180, height: 210)
        let labelHeight: CGFloat = 36
        let cellSize = NSSize(width: 212, height: 262)
        let padding: CGFloat = 18
        let rows = Int(ceil(Double(captures.count) / Double(columns)))
        let outputSize = NSSize(
            width: padding * 2 + CGFloat(columns) * cellSize.width,
            height: padding * 2 + CGFloat(rows) * cellSize.height
        )
        guard let output = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(outputSize.width.rounded()),
            pixelsHigh: Int(outputSize.height.rounded()),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ),
              let context = NSGraphicsContext(bitmapImageRep: output)
        else {
            throw SmokeFailure("panel review contact sheet bitmap allocation failed")
        }

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        NSColor(calibratedWhite: 0.96, alpha: 1).setFill()
        NSBezierPath(rect: NSRect(origin: .zero, size: outputSize)).fill()

        let labelParagraphStyle = NSMutableParagraphStyle()
        labelParagraphStyle.lineBreakMode = .byWordWrapping
        let labelAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 10, weight: .regular),
            .paragraphStyle: labelParagraphStyle,
            .foregroundColor: NSColor(calibratedWhite: 0.18, alpha: 1)
        ]
        let borderColor = NSColor(calibratedWhite: 0.78, alpha: 1)

        for (index, capture) in captures.enumerated() {
            let column = index % columns
            let row = index / columns
            let cellOrigin = NSPoint(
                x: padding + CGFloat(column) * cellSize.width,
                y: outputSize.height - padding - CGFloat(row + 1) * cellSize.height
            )
            let imageRect = NSRect(
                x: cellOrigin.x + (cellSize.width - thumbnailSize.width) / 2,
                y: cellOrigin.y + labelHeight + 4,
                width: thumbnailSize.width,
                height: thumbnailSize.height
            )
            let image = NSImage(size: capture.bitmap.size)
            image.addRepresentation(capture.bitmap)
            image.draw(in: imageRect, from: .zero, operation: .copy, fraction: 1)
            borderColor.setStroke()
            NSBezierPath(rect: imageRect).stroke()

            let labelRect = NSRect(
                x: cellOrigin.x + 6,
                y: cellOrigin.y,
                width: cellSize.width - 12,
                height: labelHeight
            )
            (capture.variant.rawValue as NSString).draw(in: labelRect, withAttributes: labelAttributes)
        }
        NSGraphicsContext.restoreGraphicsState()
        return output
    }

    private static func verifyOAuthConfigurationFromEnvironmentFile() throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("perchha-smoke-env-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: directory)
        }
        let fileURL = directory.appendingPathComponent(".env.local", isDirectory: false)
        try """
        token=ignored-token
        PERCHHA_OAUTH_CLIENT_ID=https://perchha.dev/app
        PERCHHA_OAUTH_REDIRECT_URI=perchha://auth
        """.write(to: fileURL, atomically: true, encoding: .utf8)

        let configuration = try PerchHAOAuthApplicationConfiguration.fromEnvironment([
            PerchHAOAuthApplicationConfiguration.environmentFileEnvironmentKey: fileURL.path
        ])

        try expect(configuration?.clientID == "https://perchha.dev/app", "OAuth config reads client ID from env file")
        try expect(configuration?.redirectURI == "perchha://auth", "OAuth config reads redirect URI from env file")
        try expect(configuration?.callbackURLScheme == "perchha", "OAuth config derives callback scheme")
    }

    private static func verifyOAuthClientWebsitePackaging() async throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("perchha-smoke-oauth-site-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: directory)
        }
        let envURL = directory.appendingPathComponent(".env.local", isDirectory: false)
        let outputURL = directory.appendingPathComponent("site/index.html", isDirectory: false)
        try """
        PERCHHA_OAUTH_CLIENT_ID=https://perchha.dev/app
        PERCHHA_OAUTH_REDIRECT_URI=perchha://auth
        """.write(to: envURL, atomically: true, encoding: .utf8)

        let executable = try toolExecutable(named: "perchha-package-app")
        let writeOutput = try runProcess(
            executable: executable,
            arguments: [
                "--write-oauth-site", outputURL.path,
                "--oauth-env", envURL.path
            ],
            environment: [:]
        )
        try expect(writeOutput.terminationStatus == 0, "OAuth client website packaging writes artifact successfully (\(writeOutput.text))")
        try expect(
            writeOutput.text.contains("OAuth client website verified: https://perchha.dev/app -> perchha://auth"),
            "OAuth client website packaging reports verification details"
        )
        let html = try String(contentsOf: outputURL, encoding: .utf8)
        try expect(html.contains(#"<link rel="redirect_uri" href="perchha://auth">"#), "OAuth client website artifact declares redirect URI")

        let verificationOutput = try runProcess(
            executable: executable,
            arguments: [
                "--verify-oauth-site", outputURL.path,
                "--oauth-env", envURL.path
            ],
            environment: [:]
        )
        try expect(verificationOutput.terminationStatus == 0, "OAuth client website verification succeeds (\(verificationOutput.text))")

        let publishedPort = try availableLoopbackPort()
        let publishedDirectory = directory.appendingPathComponent("published-site", isDirectory: true)
        try FileManager.default.createDirectory(at: publishedDirectory, withIntermediateDirectories: true)
        let publishedOutputURL = publishedDirectory.appendingPathComponent("index.html", isDirectory: false)
        let publishedEnvURL = directory.appendingPathComponent("published.env", isDirectory: false)
        let publishedURL = URL(string: "http://127.0.0.1:\(publishedPort)/index.html")!
        try """
        PERCHHA_OAUTH_CLIENT_ID=\(publishedURL.absoluteString)
        PERCHHA_OAUTH_REDIRECT_URI=perchha://auth
        """.write(to: publishedEnvURL, atomically: true, encoding: .utf8)
        let publishedWriteOutput = try runProcess(
            executable: executable,
            arguments: [
                "--write-oauth-site", publishedOutputURL.path,
                "--oauth-env", publishedEnvURL.path
            ],
            environment: [:]
        )
        try expect(
            publishedWriteOutput.terminationStatus == 0,
            "published OAuth client website packaging writes artifact successfully (\(publishedWriteOutput.text))"
        )
        let publishedLogURL = directory.appendingPathComponent("python-http.log", isDirectory: false)
        let publishedProcess = try launchStaticFileServer(
            directory: publishedDirectory,
            port: publishedPort,
            logURL: publishedLogURL
        )
        defer {
            stopProcess(publishedProcess)
        }
        try await waitForStaticFileServer(
            url: publishedURL,
            process: publishedProcess,
            logURL: publishedLogURL
        )

        let publishedVerificationOutput = try runProcess(
            executable: executable,
            arguments: [
                "--verify-published-oauth-site",
                "--oauth-env", publishedEnvURL.path
            ],
            environment: [:]
        )
        try expect(
            publishedVerificationOutput.terminationStatus == 0,
            "published OAuth client website verification succeeds (\(publishedVerificationOutput.text))"
        )
        try expect(
            publishedVerificationOutput.text.contains("Published OAuth client website verified: \(publishedURL.absoluteString)"),
            "published OAuth client website verification reports the deployed URL"
        )

        let transport = SmokeHARESTTransport(
            responses: [
                HARESTResponse(
                    statusCode: 200,
                    headers: ["Content-Type": "text/html"],
                    body: Data(html.utf8)
                )
            ]
        )
        let check = await HomeAssistantClient(transport: transport).verifyOAuthClientWebsite(
            clientID: "https://perchha.dev/app",
            redirectURI: "perchha://auth"
        )
        try expect(
            check == .success(
                HAOAuthClientWebsiteCheck(
                    clientID: "https://perchha.dev/app",
                    redirectURI: "perchha://auth",
                    websiteFetched: true,
                    redirectURIDeclared: true
                )
            ),
            "generated OAuth client website stays compatible with the Home Assistant website verifier"
        )
    }

    private static func verifyAppBundlePackaging() throws {
        let buildDirectory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent(".build", isDirectory: true)
        try FileManager.default.createDirectory(at: buildDirectory, withIntermediateDirectories: true)
        let executableURL = URL(fileURLWithPath: "/usr/bin/true", isDirectory: false)
        let uniqueID = UUID().uuidString.lowercased()
        let callbackScheme = "perchha-smoke-\(uniqueID)"
        let outputURL = buildDirectory.appendingPathComponent("perchha-smoke-\(uniqueID).app", isDirectory: true)
        let dmgURL = buildDirectory.appendingPathComponent("perchha-smoke-\(uniqueID).dmg", isDirectory: false)
        defer {
            try? FileManager.default.removeItem(at: outputURL)
            try? FileManager.default.removeItem(at: dmgURL)
        }
        let result = try PerchHAAppBundleBuilder().build(
            PerchHAAppBundleBuildConfiguration(
                executableURL: executableURL,
                outputURL: outputURL,
                manifest: try PerchHAAppBundleManifest(
                    bundleIdentifier: "dev.perchha.smoke.\(uniqueID.replacingOccurrences(of: "-", with: ""))",
                    callbackURLScheme: callbackScheme
                )
            )
        )
        defer {
            unregisterBundle(at: result.appURL)
        }
        let plist = try PropertyListSerialization.propertyList(
            from: Data(contentsOf: result.infoPlistURL),
            options: [],
            format: nil
        )
        guard let dictionary = plist as? [String: Any],
              let urlTypes = dictionary["CFBundleURLTypes"] as? [[String: Any]],
              let schemes = urlTypes.first?["CFBundleURLSchemes"] as? [String]
        else {
            throw SmokeFailure("app bundle Info.plist did not contain URL scheme metadata")
        }
        try expect(schemes == [callbackScheme], "app bundle declares OAuth callback URL scheme")
        try expect(FileManager.default.isExecutableFile(atPath: result.executableURL.path), "app bundle contains executable")
        let launchServices = try PerchHALaunchServicesVerifier().verify(
            PerchHALaunchServicesVerificationConfiguration(
                appURL: result.appURL,
                callbackURLScheme: callbackScheme
            )
        )
        try expect(launchServices.callbackURL.absoluteString == "\(callbackScheme)://auth", "LaunchServices verifier uses OAuth callback URL")
        try expect(launchServices.registeredApplicationURL.path == launchServices.appURL.path, "LaunchServices records callback scheme claim for generated app")
        let signing = try PerchHACodeSigner().sign(
            PerchHACodeSigningConfiguration(
                appURL: result.appURL,
                identity: "-",
                hardenedRuntime: false,
                timestamp: false
            )
        )
        try expect(signing.identity == "-", "app bundle supports local ad-hoc code signing")
        let signature = try PerchHACodeSignatureVerifier().verify(
            PerchHACodeSignatureVerificationConfiguration(appURL: result.appURL)
        )
        try expect(signature.appURL.path == result.appURL.path, "app bundle code signature verifies")
        let dmg = try PerchHADMGBuilder().build(
            PerchHADMGBuildConfiguration(
                appURL: result.appURL,
                outputURL: dmgURL,
                volumeName: "PerchHA Smoke"
            )
        )
        try expect(FileManager.default.fileExists(atPath: dmg.dmgURL.path), "DMG builder creates disk image")
        let dmgVerification = try PerchHADMGVerifier().verify(PerchHADMGVerificationConfiguration(dmgURL: dmg.dmgURL))
        try expect(dmgVerification.dmgURL.path == dmgURL.path, "DMG verifier validates disk image")
        let dmgContents = try PerchHADMGContentVerifier().verify(
            PerchHADMGContentVerificationConfiguration(
                dmgURL: dmg.dmgURL,
                appBundleName: result.appURL.lastPathComponent
            )
        )
        try expect(dmgContents.mountedAppURL.lastPathComponent == result.appURL.lastPathComponent, "DMG contains app bundle")
        try expect(dmgContents.applicationsShortcutURL?.lastPathComponent == "Applications", "DMG contains Applications shortcut")
    }

    @MainActor
    private static func verifyApplicationLaunchWiring() async throws {
        _ = NSApplication.shared
        let application = PerchHAApplication(
            configStore: nil,
            connector: { _ in .success(rooms: []) },
            oauthApplicationConfiguration: try PerchHAOAuthApplicationConfiguration(
                clientID: "https://perchha.dev/app",
                redirectURI: "perchha://auth"
            )
        )
        application.applicationDidFinishLaunching(Notification(name: NSApplication.didFinishLaunchingNotification))
        defer {
            application.applicationWillTerminate(Notification(name: NSApplication.willTerminateNotification))
        }

        let snapshot = application.snapshot
        try expect(snapshot.statusItemTitle == "", "app launch shows the logo glyph with no title")
        try expect(snapshot.statusItemHasImage, "app launch shows the fallback logo image")
        // The fallback may be the app icon (non-template) or the drawn fish (template).
        try expect(snapshot.statusItemImageIsTemplate != nil, "fallback logo image has a template flag")
        try expect(snapshot.statusItemTargetIsApplication, "app launch wires status item target")
        try expect(snapshot.statusItemHasAction, "app launch wires status item action")
        try expect(snapshot.hasPanel, "app launch creates panel")
        try expect(snapshot.hasPanelModel, "app launch creates panel model")
        try expect(snapshot.panelCanBecomeKey, "app launch creates key-capable panel")
        try expect(snapshot.panelCanBecomeMain, "app launch creates main-capable panel")
        try expect(snapshot.panelIsFloating, "app launch creates floating panel")
        try expect(snapshot.panelHidesOnDeactivate, "app launch creates dismissible panel")
        try expect(snapshot.panelContentWidth == 384, "app launch preserves panel content width")
        try expect(snapshot.panelContentHeight == 468, "app launch preserves panel content height")
        try expect(snapshot.menuBarEntityIDs.isEmpty, "app launch starts without promoted menu bar entities")

        guard let callbackURL = URL(string: "perchha://auth?code=smoke-code&state=smoke-state") else {
            throw SmokeFailure("smoke OAuth callback URL is invalid")
        }
        guard let callbackEvent = application.handleExternalURLs([callbackURL]).first else {
            throw SmokeFailure("app shell did not record external URL callback")
        }
        try expect(
            callbackEvent.disposition == PerchHAExternalURLDisposition.acceptedOAuthCallback,
            "app shell accepts configured OAuth callback URL"
        )
        try expect(!String(describing: callbackEvent).contains("smoke-code"), "app shell does not retain OAuth callback code")
        try expect(!String(describing: callbackEvent).contains("smoke-state"), "app shell does not retain OAuth callback state")

        application.applicationWillTerminate(Notification(name: NSApplication.willTerminateNotification))
        let released = application.snapshot
        try expect(released.statusItemTitle == nil, "app termination removes status item")
        try expect(!released.statusItemHasImage, "app termination removes status item image")
        try expect(!released.hasPanel, "app termination releases panel")
        try expect(!released.hasPanelModel, "app termination releases panel model")

        let configURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("perchha-smoke-app-config-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("config.json")
        defer {
            try? FileManager.default.removeItem(at: configURL.deletingLastPathComponent())
        }
        let store = JSONConfigStore(fileURL: configURL)
        _ = try store.save(
            PerchHAConfiguration(
                selectedEntityIDs: ["sensor.office_humidity"],
                menuBarEntityIDs: ["sensor.office_humidity"],
                roomOrder: ["office"],
                entityOrder: ["sensor.office_humidity"],
                isEntitySelectionExplicit: true
            )
        )
        let configured = PerchHAApplication(configStore: store)
        configured.applicationDidFinishLaunching(Notification(name: NSApplication.didFinishLaunchingNotification))
        var configuredIsRunning = true
        defer {
            if configuredIsRunning {
                configured.applicationWillTerminate(Notification(name: NSApplication.willTerminateNotification))
            }
        }
        try expect(configured.snapshot.selectedEntityIDs == ["sensor.office_humidity"], "app launch loads persisted selection config")
        try expect(configured.snapshot.menuBarEntityIDs == ["sensor.office_humidity"], "app launch loads persisted menu bar promotion config")
        try expect(configured.snapshot.isEntitySelectionExplicit, "app launch loads explicit selection flag")
        try expect(configured.snapshot.configurationPersistenceState == .ready, "app launch reports ready config persistence")
        try expect(
            configured.persist(
                selection: EntitySelectionConfiguration(
                    roomOrder: ["kitchen", "office"],
                    entityOrder: ["switch.kitchen_light", "sensor.office_humidity", "sensor.office_temperature"]
                )
            ) == .saved,
            "app shell saves reordered selection config"
        )
        configured.applicationWillTerminate(Notification(name: NSApplication.willTerminateNotification))
        configuredIsRunning = false

        let relaunched = PerchHAApplication(configStore: store)
        relaunched.applicationDidFinishLaunching(Notification(name: NSApplication.didFinishLaunchingNotification))
        defer {
            relaunched.applicationWillTerminate(Notification(name: NSApplication.willTerminateNotification))
        }
        try expect(relaunched.snapshot.roomOrder == ["kitchen", "office"], "app relaunch preserves room order")
        try expect(
            relaunched.snapshot.entityOrder == ["switch.kitchen_light", "sensor.office_humidity", "sensor.office_temperature"],
            "app relaunch preserves entity order"
        )

        let loadFailureStore = SmokeConfigStore(
            loadError: .malformedConfig(URL(fileURLWithPath: "/tmp/perchha-bad-config.json"), message: "bad json")
        )
        let loadFailure = PerchHAApplication(configStore: loadFailureStore)
        loadFailure.applicationDidFinishLaunching(Notification(name: NSApplication.didFinishLaunchingNotification))
        defer {
            loadFailure.applicationWillTerminate(Notification(name: NSApplication.willTerminateNotification))
        }
        if case let .loadFailed(message) = loadFailure.snapshot.configurationPersistenceState {
            try expect(message.contains("bad json"), "app shell reports config load failure details")
        } else {
            throw SmokeFailure("app shell reports config load failure")
        }
        if case let .failed(message) = loadFailure.persist(selection: EntitySelectionConfiguration(selectedEntityIDs: ["sensor.office_temperature"], isExplicit: true)) {
            try expect(message.contains("save blocked"), "app shell reports blocked save reason")
        } else {
            throw SmokeFailure("app shell blocks save after config load failure")
        }
        try expect(loadFailureStore.saveCallCount == 0, "app shell does not overwrite a config that failed to load")

        let saveFailureStore = SmokeConfigStore(
            loadedConfiguration: PerchHAConfiguration(selectedEntityIDs: ["sensor.office_temperature"], isEntitySelectionExplicit: true),
            saveError: .writeFailed(URL(fileURLWithPath: "/tmp/perchha-config.json"), message: "disk full")
        )
        let saveFailure = PerchHAApplication(configStore: saveFailureStore)
        saveFailure.applicationDidFinishLaunching(Notification(name: NSApplication.didFinishLaunchingNotification))
        defer {
            saveFailure.applicationWillTerminate(Notification(name: NSApplication.willTerminateNotification))
        }
        if case let .failed(message) = saveFailure.persist(selection: EntitySelectionConfiguration(selectedEntityIDs: ["sensor.office_humidity"], isExplicit: true)) {
            try expect(message.contains("disk full"), "app shell reports failed config save")
        } else {
            throw SmokeFailure("app shell reports failed config save")
        }
        if case let .saveFailed(message) = saveFailure.snapshot.configurationPersistenceState {
            try expect(message.contains("disk full"), "app shell exposes save failure details")
        } else {
            throw SmokeFailure("app shell exposes save failure state")
        }

        let panelSaveFailure = PerchHAApplication(configStore: saveFailureStore)
        panelSaveFailure.applicationDidFinishLaunching(Notification(name: NSApplication.didFinishLaunchingNotification))
        defer {
            panelSaveFailure.applicationWillTerminate(Notification(name: NSApplication.willTerminateNotification))
        }
        let panel = PerchHAPanelModel(
            connector: { _ in
                .success(
                    rooms: [
                        Room(
                            id: "office",
                            name: "Office",
                            entities: [
                                DiscoveredEntity(
                                    id: "sensor.office_temperature",
                                    name: "Office temperature",
                                    state: "21.4",
                                    unit: "°C",
                                    areaID: nil,
                                    deviceID: nil
                                ),
                                DiscoveredEntity(
                                    id: "sensor.office_humidity",
                                    name: "Office humidity",
                                    state: "44",
                                    unit: "%",
                                    areaID: nil,
                                    deviceID: nil
                                )
                            ]
                        ),
                        Room(
                            id: "kitchen",
                            name: "Kitchen",
                            entities: [
                                DiscoveredEntity(
                                    id: "switch.kitchen_light",
                                    name: "Kitchen light",
                                    state: "off",
                                    unit: nil,
                                    areaID: nil,
                                    deviceID: nil
                                )
                            ]
                        )
                    ]
                )
            },
            selectionSink: { selection in
                panelSaveFailure.persist(selection: selection)
            }
        )
        panel.updateConnectionForm(urlString: "http://127.0.0.1:8123", token: "fake-token")
        await panel.connect()
        try expect(!panel.moveRoom("kitchen", direction: .up), "panel rejects reorder when config save fails")
        try expect(panel.snapshot.rooms.map(\.id) == ["office", "kitchen"], "panel keeps previous order after failed save")
        try expect(!panel.moveEntity("sensor.office_humidity", direction: .up), "panel rejects entity move when config save fails")
        try expect(
            panel.snapshot.rooms.first?.entities.map(\.id) == ["sensor.office_temperature", "sensor.office_humidity"],
            "panel keeps previous entity order after failed save"
        )
        panel.setEntity("sensor.office_temperature", isSelected: false)
        try expect(!panel.snapshot.selectionConfiguration.isExplicit, "panel rejects checkbox change when config save fails")
        try expect(panel.snapshot.visibleEntityCount == 3, "panel keeps previous selected rows after failed checkbox save")
        try expect(
            panel.snapshot.selectionPersistenceFailureDescription?.contains("disk full") == true,
            "panel exposes selection save failure"
        )
    }

    private static func verifySelectionOrderingAndFormatting() throws {
        let rooms = [
            Room(
                id: "office",
                name: "Office",
                entities: [
                    DiscoveredEntity(
                        id: "sensor.office_temperature",
                        name: "Office temperature",
                        state: "21.45",
                        unit: "°C",
                        areaID: nil,
                        deviceID: nil
                    ),
                    DiscoveredEntity(
                        id: "sensor.office_humidity",
                        name: "Office humidity",
                        state: "44",
                        unit: "%",
                        areaID: nil,
                        deviceID: nil
                    )
                ]
            ),
            Room(
                id: "kitchen",
                name: "Kitchen",
                entities: [
                    DiscoveredEntity(
                        id: "switch.kitchen_light",
                        name: "Kitchen light",
                        state: "unavailable",
                        unit: nil,
                        areaID: nil,
                        deviceID: nil
                    )
                ]
            )
        ]
        let configuration = EntitySelectionConfiguration(
            selectedEntityIDs: ["sensor.office_humidity", "switch.kitchen_light"],
            roomOrder: ["kitchen", "office"],
            entityOrder: ["switch.kitchen_light", "sensor.office_humidity"],
            isExplicit: true
        )
        let projector = EntitySelectionProjector()
        let tree = projector.selectionTree(rooms: rooms, configuration: configuration, query: "office")
        try expect(tree.map(\.id) == ["office"], "selection tree searches rooms and entities")
        try expect(tree.first?.entities.map(\.entity.id) == ["sensor.office_humidity", "sensor.office_temperature"], "room search includes room entities in configured order")
        try expect(tree.first?.entities.map(\.isSelected) == [true, false], "selection tree marks selected entities")

        let selectedRooms = projector.selectedRooms(rooms: rooms, configuration: configuration)
        try expect(selectedRooms.map(\.id) == ["kitchen", "office"], "selection projector applies room order")
        try expect(selectedRooms.flatMap(\.entities).map(\.id) == ["switch.kitchen_light", "sensor.office_humidity"], "selection projector applies entity order")

        let formatter = EntityValueFormatter(locale: Locale(identifier: "de_DE"), maximumFractionDigits: 1)
        try expect(
            formatter.format(
                DiscoveredEntity(
                    id: "sensor.office_temperature",
                    name: "Office temperature",
                    state: "21.45",
                    unit: "°C",
                    areaID: nil,
                    deviceID: nil
                )
            ) == FormattedEntityValue(text: "21,5 °C", status: .available),
            "value formatter uses locale decimal separator"
        )
        try expect(
            formatter.format(
                DiscoveredEntity(
                    id: "sensor.kitchen_light",
                    name: "Kitchen light",
                    state: "unavailable",
                    unit: nil,
                    areaID: nil,
                    deviceID: nil
                )
            ) == FormattedEntityValue(text: "Unavailable", status: .unavailable),
            "value formatter exposes unavailable state"
        )
        try expect(
            formatter.format(
                DiscoveredEntity(
                    id: "sensor.office_temperature",
                    name: "Office temperature",
                    state: "21.45",
                    unit: "°C",
                    areaID: nil,
                    deviceID: nil
                ),
                isStale: true
            ) == FormattedEntityValue(text: "Stale: 21,5 °C", status: .stale),
            "value formatter exposes stale state"
        )
    }

    @MainActor
    private static func verifyMenuBarRenderingAndPromotion() async throws {
        let officeHumidity = DiscoveredEntity(
            id: "sensor.office_humidity",
            name: "Office humidity",
            state: "44",
            unit: "%",
            areaID: nil,
            deviceID: nil
        )
        let battery = MenuBarItemRenderer().render(
            entity: officeHumidity,
            configuration: MenuBarItemConfiguration(entityID: "sensor.office_humidity", style: .battery),
            locale: Locale(identifier: "en_US")
        )
        try expect(battery.title == "BAT[####------] 44%", "menu bar renders percent battery gauge")
        try expect(
            battery.gauge == MenuBarGauge(percent: 44, filledSegments: 4, segmentCount: 10),
            "menu bar normalizes percent gauge"
        )
        try expect(
            battery.accessibilityLabel == "Office humidity, 44%, 44 percent, battery",
            "menu bar gauge exposes accessible text"
        )

        let energy = DiscoveredEntity(
            id: "sensor.energy_today",
            name: "Energy today",
            state: "30",
            unit: "kWh",
            areaID: nil,
            deviceID: nil
        )
        let energyBudget = DiscoveredEntity(
            id: "sensor.energy_budget",
            name: "Energy budget",
            state: "60",
            unit: "kWh",
            areaID: nil,
            deviceID: nil
        )
        let utilityHumidity = DiscoveredEntity(
            id: "sensor.utility_humidity",
            name: "Utility humidity",
            state: "44",
            unit: "%",
            areaID: nil,
            deviceID: nil
        )
        let ring = MenuBarItemRenderer().render(
            entity: energy,
            configuration: MenuBarItemConfiguration(entityID: "sensor.energy_today", style: .ring, absoluteTotal: 120),
            locale: Locale(identifier: "en_US")
        )
        try expect(ring.title == "RING 25%", "menu bar renders explicit-total ring gauge")
        try expect(
            ring.gauge == MenuBarGauge(percent: 25, filledSegments: 3, segmentCount: 10),
            "menu bar normalizes absolute gauge"
        )
        let ringImage = PerchHAStatusItemGaugeImageRenderer().image(for: ring)
        try expect(ringImage != nil, "status item renderer creates a real gauge image")
        try expect(ringImage?.isTemplate == false, "status item gauge image preserves threshold colors")
        try expect(
            ringImage.map { Int($0.size.width.rounded()) } == 24 && ringImage.map { Int($0.size.height.rounded()) } == 18,
            "status item gauge image has stable dimensions"
        )
        let smokePalette = PerchHAStatusItemGaugePalette(
            normal: NSColor(calibratedRed: 0, green: 0, blue: 1, alpha: 1),
            warning: NSColor(calibratedRed: 1, green: 0.5, blue: 0, alpha: 1),
            critical: NSColor(calibratedRed: 1, green: 0, blue: 0, alpha: 1),
            track: NSColor(calibratedWhite: 0.25, alpha: 1)
        )
        let warningGauge = MenuBarItemRenderer().render(
            entity: officeHumidity,
            configuration: MenuBarItemConfiguration(
                entityID: "sensor.office_humidity",
                style: .bar,
                thresholds: ValueThresholds(warning: ValueThreshold(value: 40, direction: .aboveOrEqual))
            ),
            locale: Locale(identifier: "en_US")
        )
        let warningImage = PerchHAStatusItemGaugeImageRenderer(palette: smokePalette).image(for: warningGauge)
        try expect(
            warningImage.map { imageContainsPixel($0, closeTo: smokePalette.warning) } == true,
            "status item gauge image draws warning severity color"
        )
        let criticalRing = MenuBarItemRenderer().render(
            entity: energy,
            configuration: MenuBarItemConfiguration(
                entityID: "sensor.energy_today",
                style: .ring,
                absoluteTotal: 120,
                thresholds: ValueThresholds(critical: ValueThreshold(value: 20, direction: .aboveOrEqual))
            ),
            locale: Locale(identifier: "en_US")
        )
        let criticalRingImage = PerchHAStatusItemGaugeImageRenderer(palette: smokePalette).image(for: criticalRing)
        try expect(
            criticalRingImage.map { imageContainsPixel($0, closeTo: smokePalette.critical) } == true,
            "status item ring gauge image draws critical severity color"
        )

        let rooms = [
            Room(
                id: "office",
                name: "Office",
                entities: [officeHumidity, energy, energyBudget, utilityHumidity]
            )
        ]
        let promoted = MenuBarItemProjector().promotedEntities(
            rooms: rooms,
            menuBarEntityIDs: ["sensor.missing", "sensor.energy_today", "sensor.office_humidity"]
        )
        try expect(
            promoted.map(\.id) == ["sensor.energy_today", "sensor.office_humidity"],
            "menu bar promotion preserves configured order"
        )

        let configURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("perchha-smoke-menu-bar-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("config.json")
        defer {
            try? FileManager.default.removeItem(at: configURL.deletingLastPathComponent())
        }
        let store = JSONConfigStore(fileURL: configURL)
        _ = try store.save(
            PerchHAConfiguration(
                selectedEntityIDs: ["sensor.office_humidity"],
                menuBarEntityIDs: ["sensor.office_humidity"],
                isEntitySelectionExplicit: true
            )
        )
        let gaugeRenderer = CountingStatusItemGaugeImageRenderer()
        let application = PerchHAApplication(
            configStore: store,
            connector: { _ in .success(rooms: rooms) },
            gaugeImageRenderer: gaugeRenderer
        )
        application.applicationDidFinishLaunching(Notification(name: NSApplication.didFinishLaunchingNotification))
        defer {
            application.applicationWillTerminate(Notification(name: NSApplication.willTerminateNotification))
        }

        try expect(application.snapshot.statusItemTitle == "", "app shell menu bar shows the logo glyph before entity data loads")
        // The fallback may be the app icon (non-template) or the drawn fish (template).
        try expect(application.snapshot.statusItemImageIsTemplate != nil, "app shell fallback logo has a template flag")
        application.updateConnectionForm(urlString: "http://127.0.0.1:8123", token: "fake-token")
        await application.connect()
        try expect(gaugeRenderer.renderCount == 0, "menu bar skips gauge rendering before image style is active")
        try expect(application.snapshot.statusItemTitle == "44%", "app shell renders promoted menu bar entity")
        try expect(
            application.snapshot.statusItemAccessibilityLabel == "Office humidity, 44%",
            "app shell exposes promoted menu bar accessibility label"
        )
        try expect(
            application.applyLiveState(EntityState(id: "sensor.office_humidity", name: "Office humidity", state: "47", unit: "%")),
            "app shell accepts live state for promoted entity"
        )
        try expect(application.snapshot.statusItemTitle == "47%", "app shell updates menu bar from live state without refresh")
        try expect(
            application.setMenuBarEntity("sensor.energy_today", isVisible: true),
            "app shell persists a second promoted menu bar entity"
        )
        try expect(
            application.moveMenuBarEntity("sensor.energy_today", direction: .up),
            "app shell moves promoted menu bar entity earlier"
        )
        try expect(application.snapshot.statusItemTitle == "30 kWh", "menu bar reorder changes the visible status item immediately")
        try expect(
            application.moveMenuBarEntity("sensor.office_humidity", relativeTo: "sensor.energy_today", placement: .before),
            "app shell places promoted menu bar entity before another"
        )
        try expect(application.snapshot.statusItemTitle == "47%", "relative menu bar reorder restores visible status item")
        try expect(
            !application.moveMenuBarEntity("sensor.office_humidity", direction: .up),
            "app shell ignores menu bar boundary reorder"
        )
        let savedMenuBarOrder = try store.load().menuBarEntityIDs
        try expect(
            savedMenuBarOrder == ["sensor.office_humidity", "sensor.energy_today"],
            "menu bar reorder survives JSON save"
        )
        let searchedMenuBar = PerchHAPanelModel(
            connector: { _ in .success(rooms: rooms) },
            menuBarDisplayConfiguration: MenuBarDisplayConfiguration(
                promotedEntityIDs: ["sensor.office_humidity", "sensor.energy_today"]
            )
        )
        searchedMenuBar.updateConnectionForm(urlString: "http://127.0.0.1:8123", token: "fake-token")
        await searchedMenuBar.connect()
        searchedMenuBar.toggleSettings()
        searchedMenuBar.updateSelectionQuery("humidity")
        try expect(
            !searchedMenuBar.moveMenuBarEntity("sensor.office_humidity", direction: .down),
            "settings search blocks promoted menu bar reorder"
        )
        try expect(
            searchedMenuBar.snapshot.menuBarDisplayConfiguration.promotedEntityIDs == [
                "sensor.office_humidity",
                "sensor.energy_today"
            ],
            "blocked searched menu bar reorder keeps order stable"
        )

        let reconnectGate = Gate()
        let reconnectCounter = Counter()
        let reconnecting = PerchHAPanelModel { _ in
            let call = await reconnectCounter.increment()
            if call == 1 {
                return .success(rooms: rooms)
            }
            await reconnectGate.wait()
            return .success(rooms: rooms)
        }
        reconnecting.updateConnectionForm(urlString: "http://127.0.0.1:8123", token: "fake-token")
        await reconnecting.connect()
        reconnecting.startRefresh()
        for _ in 0..<100 {
            if reconnecting.snapshot.connectionState == .reconnecting(attempt: 1) {
                break
            }
            await Task.yield()
        }
        try expect(reconnecting.snapshot.connectionState == .reconnecting(attempt: 1), "panel model enters reconnecting before live update")
        try expect(
            reconnecting.applyLiveState(EntityState(id: "sensor.office_humidity", name: "Office humidity", state: "48", unit: "%")),
            "panel model accepts live state while reconnecting"
        )
        let reconnectHumidity = reconnecting.snapshot.rooms.first?.entities.first { $0.id == "sensor.office_humidity" }
        try expect(reconnecting.snapshot.phase == .reconnecting(attempt: 1), "live update keeps reconnecting phase")
        try expect(
            reconnectHumidity.map { reconnecting.snapshot.formattedValue(for: $0, locale: Locale(identifier: "en_US")) }
                == FormattedEntityValue(text: "Stale: 48%", status: .stale),
            "live update keeps reconnecting values stale"
        )
        reconnecting.cancelInFlightAction()
        _ = await reconnectGate.open()

        let failedCounter = Counter()
        let failed = PerchHAPanelModel { _ in
            let call = await failedCounter.increment()
            if call == 1 {
                return .success(rooms: rooms)
            }
            return .failure(.unreachable(host: "homeassistant.local"))
        }
        failed.updateConnectionForm(urlString: "http://127.0.0.1:8123", token: "fake-token")
        await failed.connect()
        await failed.refresh()
        try expect(
            failed.applyLiveState(EntityState(id: "sensor.office_humidity", name: "Office humidity", state: "49", unit: "%")),
            "panel model accepts live state after refresh failure"
        )
        let failedHumidity = failed.snapshot.rooms.first?.entities.first { $0.id == "sensor.office_humidity" }
        try expect(
            failed.snapshot.phase == .failedStale(.unreachable(host: "homeassistant.local")),
            "live update keeps failed-stale phase"
        )
        try expect(
            failedHumidity.map { failed.snapshot.formattedValue(for: $0, locale: Locale(identifier: "en_US")) }
                == FormattedEntityValue(text: "Stale: 49%", status: .stale),
            "live update keeps failed-stale values stale"
        )

        try expect(
            application.setMenuBarDisplayStyle("sensor.office_humidity", style: .battery),
            "app shell persists menu bar display style"
        )
        try expect(application.snapshot.statusItemTitle == "47%", "display style keeps value title in status item")
        try expect(application.snapshot.statusItemHasImage, "display style draws status item gauge image")
        try expect(application.snapshot.statusItemImageWidth == 24, "status item gauge image has stable width")
        try expect(application.snapshot.statusItemImageHeight == 18, "status item gauge image has stable height")
        try expect(application.snapshot.statusItemImageIsTemplate == false, "status item gauge image preserves severity colors")
        try expect(gaugeRenderer.renderCount == 1, "menu bar renders first gauge image once")
        try expect(
            application.snapshot.statusItemAccessibilityLabel == "Office humidity, 47%, 47 percent, battery",
            "display style applies to status item accessibility immediately"
        )
        try expect(
            application.applyLiveState(EntityState(id: "sensor.office_humidity", name: "Office humidity", state: "47", unit: "%")),
            "app shell accepts identical live state for promoted entity"
        )
        try expect(gaugeRenderer.renderCount == 1, "menu bar reuses gauge image for unchanged live state")
        try expect(
            application.setMenuBarShowsLabel("sensor.office_humidity", showsLabel: true),
            "app shell persists menu bar label visibility"
        )
        try expect(gaugeRenderer.renderCount == 1, "menu bar reuses gauge image when label text changes")
        try expect(
            application.snapshot.statusItemTitle == "Office humidity 47%",
            "label visibility applies to status item value title immediately"
        )
        try expect(
            application.applyLiveState(EntityState(id: "sensor.office_humidity", name: "Office humidity", state: "47.4", unit: "%")),
            "app shell accepts decimal live state for promoted entity"
        )
        try expect(gaugeRenderer.renderCount == 2, "menu bar redraws gauge image when gauge value changes")
        try expect(
            application.setMenuBarMaximumFractionDigits("sensor.office_humidity", maximumFractionDigits: 1),
            "app shell persists menu bar decimal precision"
        )
        try expect(gaugeRenderer.renderCount == 2, "menu bar reuses gauge image when decimal text changes")
        let expectedHumidityValue = EntityValueFormatter(
            locale: .current,
            maximumFractionDigits: 1
        ).format(
            DiscoveredEntity(
                id: "sensor.office_humidity",
                name: "Office humidity",
                state: "47.4",
                unit: "%",
                areaID: nil,
                deviceID: nil
            )
        ).text
        try expect(
            application.snapshot.statusItemAccessibilityLabel
                == "Office humidity, \(expectedHumidityValue), 47 percent, battery",
            "decimal precision applies to status item accessibility immediately"
        )
        try expect(
            application.snapshot.statusItemTitle == "Office humidity \(expectedHumidityValue)",
            "decimal precision applies to status item value title immediately"
        )
        try expect(
            application.setMenuBarDefaultHistoryRange("sensor.office_humidity", defaultHistoryRange: .day),
            "app shell persists default history range"
        )
        try expect(gaugeRenderer.renderCount == 2, "menu bar reuses gauge image when default history range changes")
        try expect(
            application.snapshot.statusItemTitle == "Office humidity \(expectedHumidityValue)",
            "default history range leaves status item value title stable"
        )
        let savedDisplayConfiguration = try store.load()
        try expect(
            savedDisplayConfiguration.menuBarItemConfigurations.first?.style == .battery,
            "display style survives JSON save"
        )
        try expect(
            savedDisplayConfiguration.menuBarItemConfigurations.first?.showsLabel == true,
            "display label visibility survives JSON save"
        )
        try expect(
            savedDisplayConfiguration.menuBarItemConfigurations.first?.maximumFractionDigits == 1,
            "display decimal precision survives JSON save"
        )
        try expect(
            savedDisplayConfiguration.menuBarItemConfigurations.first?.defaultHistoryRange == .day,
            "default history range survives JSON save"
        )

        try expect(application.setMenuBarEntity("sensor.office_humidity", isVisible: false), "app shell can remove a promoted menu bar entity")
        try expect(application.snapshot.statusItemTitle == "30 kWh", "app shell promotes absolute sensor as text before total")
        try expect(
            application.setMenuBarDisplayStyle("sensor.energy_today", style: .ring),
            "app shell persists absolute sensor gauge style"
        )
        try expect(application.snapshot.statusItemTitle == "30 kWh", "absolute sensor waits for a total before drawing gauge")
        try expect(
            application.setMenuBarAbsoluteTotal("sensor.energy_today", total: 120),
            "app shell persists manual gauge total"
        )
        try expect(application.snapshot.statusItemTitle == "30 kWh", "manual gauge total keeps value title in status item")
        try expect(application.snapshot.statusItemHasImage, "manual gauge total draws status item gauge image")
        try expect(
            !application.setMenuBarAbsoluteTotal("sensor.energy_today", total: 0),
            "app shell rejects zero manual gauge total"
        )
        try expect(
            !application.setMenuBarTotalEntityID("sensor.energy_today", totalEntityID: "sensor.utility_humidity"),
            "app shell rejects incompatible total entity"
        )
        try expect(application.snapshot.statusItemTitle == "30 kWh", "rejected gauge total keeps status item stable")
        try expect(
            application.setMenuBarWarningThreshold(
                "sensor.energy_today",
                threshold: ValueThreshold(value: 20, direction: .aboveOrEqual)
            ),
            "app shell persists warning threshold"
        )
        try expect(
            application.snapshot.statusItemAccessibilityLabel == "Energy today, 30 kWh, 25 percent, warning, ring",
            "warning threshold repaints status item accessibility"
        )
        try expect(
            application.setMenuBarTotalEntityID("sensor.energy_today", totalEntityID: "sensor.energy_budget"),
            "app shell persists total entity gauge source"
        )
        try expect(application.snapshot.statusItemTitle == "30 kWh", "total entity gauge source keeps value title in status item")
        try expect(
            application.setMenuBarWarningThreshold("sensor.energy_today", threshold: nil),
            "app shell clears warning threshold"
        )
        let savedEnergyDisplayConfiguration = try store.load()
            .menuBarDisplayConfiguration
            .itemConfiguration(for: "sensor.energy_today")
        try expect(savedEnergyDisplayConfiguration.absoluteTotal == nil, "total entity clears manual gauge total in JSON")
        try expect(
            savedEnergyDisplayConfiguration.totalEntityID == "sensor.energy_budget",
            "total entity gauge source survives JSON save"
        )
        try expect(savedEnergyDisplayConfiguration.thresholds.warning == nil, "cleared warning threshold survives JSON save")
    }

    private static func spinUntil(_ message: String, condition: @escaping () async -> Bool) async throws {
        for _ in 0..<100 {
            if await condition() {
                return
            }
            await Task.yield()
        }
        throw SmokeFailure(message)
    }

    private static func historyDate(_ value: String) throws -> Date {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        guard let date = formatter.date(from: value) else {
            throw SmokeFailure("invalid history test date: \(value)")
        }
        return date
    }

    private static func imageContainsPixel(_ image: NSImage, closeTo expectedColor: NSColor) -> Bool {
        var proposedRect = NSRect(origin: .zero, size: image.size)
        guard let cgImage = image.cgImage(forProposedRect: &proposedRect, context: nil, hints: nil),
              let expected = expectedColor.usingColorSpace(.sRGB)
        else {
            return false
        }
        let bitmap = NSBitmapImageRep(cgImage: cgImage)
        for x in 0..<bitmap.pixelsWide {
            for y in 0..<bitmap.pixelsHigh {
                guard let actual = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB),
                      actual.alphaComponent > 0.75
                else {
                    continue
                }
                if abs(actual.redComponent - expected.redComponent) < 0.08,
                   abs(actual.greenComponent - expected.greenComponent) < 0.08,
                   abs(actual.blueComponent - expected.blueComponent) < 0.08 {
                    return true
                }
            }
        }
        return false
    }

    private static func unregisterBundle(at url: URL) {
        let lsregisterURL = URL(fileURLWithPath: "/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister")
        guard FileManager.default.isExecutableFile(atPath: lsregisterURL.path) else {
            return
        }
        let process = Process()
        process.executableURL = lsregisterURL
        process.arguments = ["-u", url.path]
        try? process.run()
        process.waitUntilExit()
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        guard condition() else {
            throw SmokeFailure(message)
        }
    }

    private static func expectAsync(_ condition: @autoclosure () async -> Bool, _ message: String) async throws {
        guard await condition() else {
            throw SmokeFailure(message)
        }
    }

}

struct SmokeFailure: Error, CustomStringConvertible {
    let description: String

    init(_ description: String) {
        self.description = description
    }
}

private struct CoverageGateSmokeResult {
    let exitCode: Int32
    let output: String
    let error: String
}

private struct RepoAuditSmokeResult {
    let exitCode: Int32
    let output: String
    let error: String
}

private struct ServeProcessHandle {
    let process: Process
    let outputURL: URL
}

private enum SmokePerformanceBudget {
    static let panelOpenMedianMilliseconds: UInt64 = 150
    static let panelOpenMaximumMilliseconds: UInt64 = 300
    static let panelOpenMedianNanoseconds = panelOpenMedianMilliseconds * 1_000_000
    static let panelOpenMaximumNanoseconds = panelOpenMaximumMilliseconds * 1_000_000
    static let lifecycleSoakWarmupIterations = 3
    static let lifecycleSoakMeasuredIterations = 15
    static let lifecycleSoakMaximumGrowthBytes: UInt64 = 32 * 1_024 * 1_024
    static let idleWarmupSeconds = 0.15
    static let idleObservationSeconds = 0.50
    static let idleMaximumCPUSeconds = 0.08
}

private func jsonString(_ text: String?, path: [AnyHashable]) throws -> String? {
    guard let text,
          let data = text.data(using: .utf8)
    else {
        return nil
    }
    var value: Any = try JSONSerialization.jsonObject(with: data)
    for component in path {
        if let key = component.base as? String,
           let object = value as? [String: Any],
           let next = object[key] {
            value = next
        } else if let index = component.base as? Int,
                  let array = value as? [Any],
                  array.indices.contains(index) {
            value = array[index]
        } else {
            return nil
        }
    }
    return value as? String
}

private enum SmokePanelSnapshotVariant: String, CaseIterable {
    case connectedLight = "connected-light"
    case connectedDark = "connected-dark"
    case connectedDarkIncreasedContrast = "connected-dark-increased-contrast"
    case connectedLightReducedMotion = "connected-light-reduced-motion"
    case historyLoadedLight = "history-loaded-light"
    case historyLoadedLightIncreasedContrast = "history-loaded-light-increased-contrast"
    case customActionEditorLight = "custom-action-editor-light"
    case builtInControlsLight = "built-in-controls-light"
    case firstRunLight = "first-run-light"
    case connectingLight = "connecting-light"
    case signingInLight = "signing-in-light"
    case settingsSelectionLight = "settings-selection-light"
    case reconnectingLight = "reconnecting-light"
    case emptyLight = "empty-light"
    case errorDark = "error-dark"

    var colorScheme: ColorScheme {
        switch self {
        case .connectedDark, .connectedDarkIncreasedContrast, .errorDark:
            .dark
        case .connectedLight,
             .connectedLightReducedMotion,
             .historyLoadedLight,
             .historyLoadedLightIncreasedContrast,
             .customActionEditorLight,
             .builtInControlsLight,
             .firstRunLight,
             .connectingLight,
             .signingInLight,
             .settingsSelectionLight,
             .reconnectingLight,
             .emptyLight:
            .light
        }
    }

    var colorSchemeContrast: ColorSchemeContrast {
        switch self {
        case .connectedDarkIncreasedContrast, .historyLoadedLightIncreasedContrast:
            .increased
        default:
            .standard
        }
    }

    var reduceMotion: Bool {
        self == .connectedLightReducedMotion
    }

    var accessibilityPreferences: PerchHAAccessibilityPreferences {
        PerchHAAccessibilityPreferences(
            reduceMotion: reduceMotion,
            increaseContrast: colorSchemeContrast == .increased
        )
    }

    var appearanceName: NSAppearance.Name {
        switch colorScheme {
        case .dark:
            .darkAqua
        case .light:
            .aqua
        @unknown default:
            .aqua
        }
    }

    var snapshot: PerchHAPanelSnapshot {
        switch self {
        case .connectedLight, .connectedDark, .connectedDarkIncreasedContrast, .connectedLightReducedMotion:
            PerchHAPanelSnapshot(
                connectionState: .connected,
                phase: .connectedData,
                rooms: Self.connectedRooms,
                availableRooms: Self.connectedRooms,
                lastUpdateDescription: "Snapshot ready",
                canRetry: true
            )
        case .historyLoadedLight, .historyLoadedLightIncreasedContrast:
            PerchHAPanelSnapshot(
                connectionState: .connected,
                phase: .connectedData,
                rooms: Self.connectedRooms,
                availableRooms: Self.connectedRooms,
                lastUpdateDescription: "Snapshot ready",
                canRetry: true,
                historyState: .loaded(Self.loadedHistorySeries),
                historyPresentationEntityID: "sensor.office_humidity"
            )
        case .customActionEditorLight:
            PerchHAPanelSnapshot(
                connectionState: .connected,
                phase: .connectedData,
                rooms: Self.connectedRooms,
                availableRooms: Self.connectedRooms,
                selectionQuery: "humidity",
                isSettingsPresented: true,
                lastUpdateDescription: "Snapshot ready",
                canRetry: true,
                serviceMetadata: Self.customActionServiceMetadata
            )
        case .builtInControlsLight:
            PerchHAPanelSnapshot(
                connectionState: .connected,
                phase: .connectedData,
                rooms: Self.connectedRooms,
                availableRooms: Self.connectedRooms,
                lastUpdateDescription: "Snapshot ready",
                canRetry: true,
                controlActionState: .failed(entityID: "switch.office_lamp", message: "planned service failure")
            )
        case .firstRunLight:
            PerchHAPanelSnapshot(
                connectionState: .disconnected,
                phase: .firstRun,
                connectionForm: PerchHAConnectionForm(
                    urlString: "https://homeassistant.local:8123",
                    fallbackURLString: "http://backup.local:8123",
                    token: "",
                    usesStoredAuthSession: false
                ),
                canRetry: false
            )
        case .connectingLight:
            PerchHAPanelSnapshot(
                connectionState: .connecting,
                phase: .connecting,
                connectionForm: PerchHAConnectionForm(
                    urlString: "https://homeassistant.local:8123",
                    fallbackURLString: "http://backup.local:8123",
                    token: "",
                    usesStoredAuthSession: false
                ),
                lastUpdateDescription: "Connecting",
                canRetry: false
            )
        case .signingInLight:
            PerchHAPanelSnapshot(
                connectionState: .disconnected,
                phase: .firstRun,
                connectionForm: PerchHAConnectionForm(
                    urlString: "https://homeassistant.local:8123",
                    fallbackURLString: "http://backup.local:8123",
                    token: "",
                    usesStoredAuthSession: false
                ),
                canRetry: false
            )
        case .settingsSelectionLight:
            PerchHAPanelSnapshot(
                connectionState: .connected,
                phase: .connectedData,
                rooms: Self.connectedRooms,
                availableRooms: Self.settingsRooms,
                selectionConfiguration: EntitySelectionConfiguration(
                    selectedEntityIDs: ["sensor.office_humidity", "switch.kitchen_light"],
                    roomOrder: ["kitchen", "office"],
                    entityOrder: ["switch.kitchen_light", "sensor.office_humidity", "sensor.office_temperature"],
                    isExplicit: true
                ),
                menuBarDisplayConfiguration: MenuBarDisplayConfiguration(
                    promotedEntityIDs: ["sensor.office_humidity"]
                ),
                isSettingsPresented: true,
                lastUpdateDescription: "Snapshot ready",
                canRetry: true
            )
        case .reconnectingLight:
            PerchHAPanelSnapshot(
                connectionState: .reconnecting(attempt: 1),
                phase: .reconnecting(attempt: 1),
                rooms: Self.connectedRooms,
                availableRooms: Self.connectedRooms,
                lastUpdateDescription: "Retrying",
                refreshCount: 1,
                canRetry: true
            )
        case .emptyLight:
            PerchHAPanelSnapshot(
                connectionState: .connected,
                phase: .connectedEmpty,
                availableRooms: Self.connectedRooms,
                lastUpdateDescription: "Snapshot ready",
                canRetry: true
            )
        case .errorDark:
            PerchHAPanelSnapshot(
                connectionState: .failed(.authentication),
                phase: .failed(.authentication),
                lastUpdateDescription: "Snapshot failed",
                canRetry: false
            )
        }
    }

    var customActionConfiguration: CustomActionConfiguration {
        switch self {
        case .connectedLight,
             .connectedDark,
             .connectedDarkIncreasedContrast,
             .connectedLightReducedMotion,
             .historyLoadedLight,
             .historyLoadedLightIncreasedContrast,
             .reconnectingLight:
            CustomActionConfiguration(actions: [
                EntityCustomAction(
                    id: "snapshot-boost-air",
                    entityID: "sensor.office_humidity",
                    title: "Boost air",
                    action: ActionSpec(domain: "script", service: "turn_on", targetEntityID: "script.air_cleaner_boost")
                )
            ])
        case .customActionEditorLight:
            CustomActionConfiguration(actions: [
                EntityCustomAction(
                    id: "snapshot-boost-air",
                    entityID: "sensor.office_humidity",
                    title: "Boost air",
                    action: ActionSpec(
                        domain: "script",
                        service: "turn_on",
                        targetEntityID: "script.air_cleaner_boost",
                        serviceData: [
                            "variables": .object([
                                "steps": .array(["fan", "purifier"])
                            ]),
                            "pin": .protectedString("snapshot-boost-air-pin")
                        ]
                    ),
                    requiresConfirmation: true
                )
            ])
        case .builtInControlsLight, .firstRunLight, .connectingLight, .signingInLight, .settingsSelectionLight, .emptyLight, .errorDark:
            CustomActionConfiguration()
        }
    }

    var startsOAuthSignInForSnapshot: Bool {
        self == .signingInLight
    }

    /// Whether this variant warms the inline-history cache so the graph-forward
    /// rows render their full-width sparkline and state-timeline bands.
    var warmsInlineHistory: Bool {
        switch self {
        case .connectedLight, .connectedDark, .connectedDarkIncreasedContrast, .connectedLightReducedMotion:
            true
        case .historyLoadedLight, .historyLoadedLightIncreasedContrast, .customActionEditorLight,
             .builtInControlsLight, .firstRunLight, .connectingLight, .signingInLight,
             .settingsSelectionLight, .reconnectingLight, .emptyLight, .errorDark:
            false
        }
    }

    /// Warmed inline-history series for connected snapshots: a numeric humidity
    /// trend (rendered as a line sparkline) and a cover state timeline (rendered
    /// as a colored band). Keyed by entity ID at the default `.hour` range.
    fileprivate static let inlineHistorySeries: [EntityID: HistorySeries] = [
        "sensor.office_humidity": HistorySeries(
            entityID: "sensor.office_humidity",
            range: .hour,
            samples: [
                HistorySample(timestamp: Date(timeIntervalSince1970: 1_803_600_000), state: "41", numericValue: 41),
                HistorySample(timestamp: Date(timeIntervalSince1970: 1_803_601_800), state: "43", numericValue: 43),
                HistorySample(timestamp: Date(timeIntervalSince1970: 1_803_603_600), state: "47", numericValue: 47),
                HistorySample(timestamp: Date(timeIntervalSince1970: 1_803_605_400), state: "45", numericValue: 45),
                HistorySample(timestamp: Date(timeIntervalSince1970: 1_803_607_200), state: "44", numericValue: 44)
            ]
        ),
        "cover.office_blinds": HistorySeries(
            entityID: "cover.office_blinds",
            range: .hour,
            samples: [
                HistorySample(timestamp: Date(timeIntervalSince1970: 1_803_600_000), state: "closed", numericValue: nil),
                HistorySample(timestamp: Date(timeIntervalSince1970: 1_803_604_000), state: "open", numericValue: nil),
                HistorySample(timestamp: Date(timeIntervalSince1970: 1_803_607_200), state: "open", numericValue: nil)
            ]
        )
    ]

    var oauthSignInRunner: PerchHAPanelModel.OAuthSignInRunner {
        switch self {
        case .signingInLight:
            return { _ in
                do {
                    try await Task.sleep(nanoseconds: 5_000_000_000)
                } catch {
                    return .failed("sign-in cancelled")
                }
                return .failed("sign-in did not finish")
            }
        default:
            return { _ in .failed("OAuth sign-in is not configured") }
        }
    }

    private static let connectedRooms = [
        Room(
            id: "office",
            name: "Office",
            entities: [
                DiscoveredEntity(
                    id: "sensor.office_humidity",
                    name: "Office humidity",
                    state: "44",
                    unit: "%",
                    areaID: nil,
                    deviceID: nil
                ),
                DiscoveredEntity(
                    id: "switch.office_lamp",
                    name: "Office lamp",
                    state: "off",
                    unit: nil,
                    areaID: nil,
                    deviceID: nil
                ),
                DiscoveredEntity(
                    id: "cover.office_blinds",
                    name: "Office blinds",
                    state: "open",
                    unit: nil,
                    areaID: nil,
                    deviceID: nil,
                    currentPosition: 42
                )
            ]
        )
    ]

    private static let settingsRooms = connectedRooms + [
        Room(
            id: "kitchen",
            name: "Kitchen",
            entities: [
                DiscoveredEntity(
                    id: "switch.kitchen_light",
                    name: "Kitchen light",
                    state: "off",
                    unit: nil,
                    areaID: nil,
                    deviceID: nil
                )
            ]
        )
    ]

    fileprivate static let loadedHistorySeries = HistorySeries(
        entityID: "sensor.office_humidity",
        range: .day,
        samples: [
            HistorySample(timestamp: Date(timeIntervalSince1970: 1_803_600_000), state: "42", numericValue: 42),
            HistorySample(timestamp: Date(timeIntervalSince1970: 1_803_603_600), state: "44", numericValue: 44),
            HistorySample(timestamp: Date(timeIntervalSince1970: 1_803_607_200), state: "47", numericValue: 47),
            HistorySample(timestamp: Date(timeIntervalSince1970: 1_803_610_800), state: "45", numericValue: 45)
        ]
    )

    private static let customActionServiceMetadata = [
        HAServiceMetadata(
            domain: "script",
            service: "turn_on",
            name: "Turn on",
            description: "Runs a script.",
            fields: [
                HAServiceFieldMetadata(
                    key: "variables",
                    name: "Variables",
                    description: nil,
                    required: false,
                    example: .object([
                        "steps": .array(["fan", "purifier"])
                    ]),
                    selector: .object(["object": .object([:])])
                ),
                HAServiceFieldMetadata(
                    key: "pin",
                    name: "PIN",
                    description: "Alarm code",
                    required: false,
                    example: "1234",
                    selector: .object(["text": .object([:])])
                )
            ]
        )
    ]
}

private final class InMemoryProtectedActionValueStore: ProtectedActionValueStore, @unchecked Sendable {
    private var values: [ProtectedActionValueReference: String] = [:]

    func save(_ value: String, for reference: ProtectedActionValueReference) throws {
        guard !value.isEmpty else {
            throw SecretStoreError.emptySecret(.customActionProtectedValues)
        }
        values[reference] = value
    }

    func load(_ reference: ProtectedActionValueReference) throws -> String {
        guard let value = values[reference] else {
            throw ProtectedActionValueStoreError.missingValue(reference)
        }
        return value
    }

    func delete(_ reference: ProtectedActionValueReference) throws {
        values.removeValue(forKey: reference)
    }
}

private actor ActionInvocationRecorder {
    private var action: ActionSpec?

    func record(_ action: ActionSpec) {
        self.action = action
    }

    func lastAction() -> ActionSpec? {
        action
    }
}

private struct SmokePanelRenderSignature: Equatable {
    let pixelsWide: Int
    let pixelsHigh: Int
    let visiblePixelCount: Int
    let topEdgeVisiblePixelCount: Int
    let bottomEdgeVisiblePixelCount: Int
    let sampledHash: UInt64

    init(bitmap: NSBitmapImageRep) {
        pixelsWide = bitmap.pixelsWide
        pixelsHigh = bitmap.pixelsHigh

        var visible = 0
        var topEdgeVisible = 0
        var bottomEdgeVisible = 0
        var hash: UInt64 = 14_695_981_039_346_656_037
        let sampleXStride = max(1, bitmap.pixelsWide / 48)
        let sampleYStride = max(1, bitmap.pixelsHigh / 48)

        for y in 0..<bitmap.pixelsHigh {
            for x in 0..<bitmap.pixelsWide {
                guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else {
                    continue
                }
                if color.alphaComponent > 0.05 {
                    visible += 1
                    if y == 0 {
                        topEdgeVisible += 1
                    }
                    if y == bitmap.pixelsHigh - 1 {
                        bottomEdgeVisible += 1
                    }
                }
                guard x.isMultiple(of: sampleXStride), y.isMultiple(of: sampleYStride) else {
                    continue
                }
                let red = UInt64((color.redComponent * 255).rounded())
                let green = UInt64((color.greenComponent * 255).rounded())
                let blue = UInt64((color.blueComponent * 255).rounded())
                let alpha = UInt64((color.alphaComponent * 255).rounded())
                hash = (hash ^ red) &* 1_099_511_628_211
                hash = (hash ^ green) &* 1_099_511_628_211
                hash = (hash ^ blue) &* 1_099_511_628_211
                hash = (hash ^ alpha) &* 1_099_511_628_211
            }
        }

        visiblePixelCount = visible
        topEdgeVisiblePixelCount = topEdgeVisible
        bottomEdgeVisiblePixelCount = bottomEdgeVisible
        sampledHash = hash
    }
}

private struct SmokePanelRenderCapture {
    let bitmap: NSBitmapImageRep
    let signature: SmokePanelRenderSignature

    init(bitmap: NSBitmapImageRep) {
        self.bitmap = bitmap
        self.signature = SmokePanelRenderSignature(bitmap: bitmap)
    }
}

private struct SmokePanelReviewBaseline: Codable, Equatable {
    struct Entry: Codable, Equatable {
        let name: String
        let pixelsWide: Int
        let pixelsHigh: Int
        let visiblePixelCount: Int
        let sampledHashHex: String

        init(name: String, signature: SmokePanelRenderSignature) {
            self.name = name
            self.pixelsWide = signature.pixelsWide
            self.pixelsHigh = signature.pixelsHigh
            self.visiblePixelCount = signature.visiblePixelCount
            self.sampledHashHex = signature.sampledHashHex
        }
    }

    let schemaVersion: Int
    let variants: [Entry]
    let contactSheet: Entry

    init(variants: [Entry], contactSheet: Entry) {
        self.schemaVersion = 1
        self.variants = variants
        self.contactSheet = contactSheet
    }
}

private struct SmokeOptions {
    static let help = """
    perchha-smoke

    Runs PerchHA's public smoke verification suite and optional screenshot baseline refresh.

    Usage:
      perchha-smoke
      perchha-smoke help
      PERCHHA_SMOKE_SNAPSHOT_DIR=.build/perchha-snapshots perchha-smoke
      perchha-smoke --repeat 5
      perchha-smoke --update-review-baseline
      perchha-smoke --review-baseline docs/release-review-baseline.json

    Options:
      --review-baseline PATH        Review-baseline manifest to compare against.
                                    Default: docs/release-review-baseline.json
      --repeat COUNT               Run the full smoke suite COUNT times as fresh invocations.
                                   Default: 1
      --update-review-baseline      Refresh the review-baseline manifest intentionally.
      -h, --help                    Show this help text.

    Environment:
      PERCHHA_SMOKE_SNAPSHOT_DIR    Export screenshots under <dir>/current during the run.
    """

    let reviewBaselineURL: URL
    let repeatCount: Int
    let updatesReviewBaseline: Bool
    let showsHelp: Bool

    init(arguments: [String]) throws {
        let rootDirectory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
        var reviewBaselineURL = rootDirectory.appendingPathComponent("docs/release-review-baseline.json", isDirectory: false)
        var repeatCount = 1
        let updatesReviewBaseline: Bool
        let showsHelp: Bool
        do {
            let options = try PerchHACommandLineOptions(
                arguments: arguments,
                valueOptions: ["--repeat", "--review-baseline"],
                flagOptions: ["help", "-h", "--help", "--update-review-baseline"]
            )
            if let configuredReviewBaseline = options.value(for: "--review-baseline") {
                reviewBaselineURL = URL(fileURLWithPath: configuredReviewBaseline, isDirectory: false)
            }
            if let configuredRepeatCount = options.value(for: "--repeat") {
                guard let parsedRepeatCount = Int(configuredRepeatCount), parsedRepeatCount > 0 else {
                    throw SmokeFailure("invalid repeat count: \(configuredRepeatCount)")
                }
                repeatCount = parsedRepeatCount
            }
            updatesReviewBaseline = options.has("--update-review-baseline")
            showsHelp = options.has("help") || options.has("-h") || options.has("--help")
        } catch let error as PerchHACommandLineParseError {
            throw SmokeFailure(CommandLineOptions.parseErrorDescription(error))
        }
        self.reviewBaselineURL = reviewBaselineURL
        self.repeatCount = repeatCount
        self.updatesReviewBaseline = updatesReviewBaseline
        self.showsHelp = showsHelp
    }
}

private enum CommandLineOptions {
    static func parseErrorDescription(_ error: PerchHACommandLineParseError) -> String {
        switch error {
        case let .missingValue(option):
            "missing value for \(option)"
        case let .unknownOption(option), let .invalidArgument(option):
            "unknown option: \(option)"
        }
    }
}

private extension SmokePanelRenderSignature {
    var sampledHashHex: String {
        String(format: "%016llx", sampledHash)
    }
}

private func writePanelReviewBaseline(_ baseline: SmokePanelReviewBaseline, to url: URL) throws {
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    try encoder.encode(baseline).write(to: url, options: .atomic)
}

private func loadPanelReviewBaseline(from url: URL) throws -> SmokePanelReviewBaseline {
    guard FileManager.default.fileExists(atPath: url.path) else {
        throw SmokeFailure("panel review baseline is missing: \(url.path)")
    }
    do {
        return try JSONDecoder().decode(
            SmokePanelReviewBaseline.self,
            from: Data(contentsOf: url)
        )
    } catch {
        throw SmokeFailure("panel review baseline is unreadable: \(url.path)")
    }
}

private func reviewBaselineMismatchMessage(
    expected: SmokePanelReviewBaseline,
    actual: SmokePanelReviewBaseline,
    baselineURL: URL
) -> String {
    if expected.schemaVersion != actual.schemaVersion {
        return "panel review baseline schema drifted; update \(baselineURL.path) if intentional"
    }
    let expectedVariantNames = expected.variants.map(\.name)
    let actualVariantNames = actual.variants.map(\.name)
    if expectedVariantNames != actualVariantNames {
        return "panel review baseline variant list drifted; update \(baselineURL.path) if intentional"
    }
    for (expectedEntry, actualEntry) in zip(expected.variants, actual.variants) where expectedEntry != actualEntry {
        return "panel review baseline drifted for \(actualEntry.name): expected \(expectedEntry.sampledHashHex), got \(actualEntry.sampledHashHex); update \(baselineURL.path) if intentional"
    }
    if expected.contactSheet != actual.contactSheet {
        return "panel review contact sheet baseline drifted: expected \(expected.contactSheet.sampledHashHex), got \(actual.contactSheet.sampledHashHex); update \(baselineURL.path) if intentional"
    }
    return "panel review baseline drifted; update \(baselineURL.path) if intentional"
}

actor Counter {
    private(set) var value = 0

    func increment() -> Int {
        value += 1
        return value
    }
}

actor Gate {
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

actor ConnectionFormRecorder {
    private var recordedFallbackURLString: String?
    private var recordedTokens: [String] = []
    private var recordedCallCount = 0

    func record(_ form: PerchHAConnectionForm) {
        recordedCallCount += 1
        recordedFallbackURLString = form.fallbackURL()?.absoluteString
        recordedTokens.append(form.token)
    }

    func callCount() -> Int {
        recordedCallCount
    }

    func fallbackURLString() -> String? {
        recordedFallbackURLString
    }

    func tokens() -> [String] {
        recordedTokens
    }
}

actor HistoryProviderProbe {
    private let series: HistorySeries
    private var recordedForms: [PerchHAConnectionForm] = []
    private var recordedEntityIDs: [EntityID] = []
    private var recordedRanges: [HistoryRange] = []

    init(series: HistorySeries) {
        self.series = series
    }

    func provide(
        form: PerchHAConnectionForm,
        entityID: EntityID,
        range: HistoryRange
    ) -> PerchHAHistoryProviderResult {
        recordedForms.append(form)
        recordedEntityIDs.append(entityID)
        recordedRanges.append(range)
        guard series.entityID == entityID, series.range == range else {
            return .unavailable("history unavailable")
        }
        return .success(series)
    }

    func callCount() -> Int {
        recordedRanges.count
    }

    func ranges() -> [HistoryRange] {
        recordedRanges
    }

    func tokens() -> [String] {
        recordedForms.map(\.token)
    }
}

actor ConnectionResultSequence {
    private var results: [PerchHAConnectionAttemptResult]

    init(results: [PerchHAConnectionAttemptResult]) {
        self.results = results
    }

    func next() -> PerchHAConnectionAttemptResult {
        if results.isEmpty {
            return .failure(.protocolError("result sequence is empty"))
        }
        return results.removeFirst()
    }
}

actor SmokeHARESTTransport: HARESTTransport {
    private var responses: [HARESTResponse]

    init(responses: [HARESTResponse]) {
        self.responses = responses
    }

    func send(_ request: HARESTRequest) async throws -> HARESTResponse {
        guard !responses.isEmpty else {
            throw SmokeFailure("unexpected REST request: \(request.url.absoluteString)")
        }
        return responses.removeFirst()
    }
}

@MainActor
final class SelectionSinkProbe {
    private(set) var lastSelection: EntitySelectionConfiguration?

    func record(_ selection: EntitySelectionConfiguration) -> SelectionPersistenceResult {
        lastSelection = selection
        return .saved
    }
}

@MainActor
final class CountingStatusItemGaugeImageRenderer: PerchHAStatusItemGaugeImageRendering {
    private let renderer = PerchHAStatusItemGaugeImageRenderer()
    private(set) var renderedItems: [RenderedMenuBarItem] = []

    var renderCount: Int {
        renderedItems.count
    }

    func image(for item: RenderedMenuBarItem) -> NSImage? {
        renderedItems.append(item)
        return renderer.image(for: item)
    }
}

final class SmokeConfigStore: ConfigStore, @unchecked Sendable {
    private let loadedConfiguration: PerchHAConfiguration
    private let loadError: ConfigStoreError?
    private let saveError: ConfigStoreError?
    private(set) var saveCallCount = 0

    init(
        loadedConfiguration: PerchHAConfiguration = .empty,
        loadError: ConfigStoreError? = nil,
        saveError: ConfigStoreError? = nil
    ) {
        self.loadedConfiguration = loadedConfiguration
        self.loadError = loadError
        self.saveError = saveError
    }

    func describe() -> PerchHAModule {
        PerchHAPersistence.module
    }

    func load() throws -> PerchHAConfiguration {
        if let loadError {
            throw loadError
        }
        return loadedConfiguration
    }

    @discardableResult
    func save(_ configuration: PerchHAConfiguration) throws -> PerchHAConfiguration {
        saveCallCount += 1
        if let saveError {
            throw saveError
        }
        return configuration
    }
}
