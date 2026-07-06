import Foundation
import Darwin
import FakeHA
import PerchHAClient
import PerchHASupport

typealias CommandOptions = PerchHACommandLineOptions

@main
struct HAMirrorCommand {
    static func main() async {
        do {
            try await run(arguments: Array(CommandLine.arguments.dropFirst()))
        } catch {
            fputs("hamirror: \(error)\n", stderr)
            Foundation.exit(1)
        }
    }

    static func run(
        arguments: [String],
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) async throws {
        guard let command = arguments.first else {
            print(helpText)
            return
        }

        switch command {
        case "capture":
            let options = try parseOptions(
                arguments: Array(arguments.dropFirst()),
                valueOptions: ["--env", "--output"],
                flagOptions: ["--review", "--write", "--websocket"]
            )
            try await capture(options: options, environment: environment)
        case "verify":
            let options = try parseOptions(
                arguments: Array(arguments.dropFirst()),
                valueOptions: ["--fixtures"],
                flagOptions: []
            )
            try verify(options: options)
        case "doctor":
            let options = try parseOptions(
                arguments: Array(arguments.dropFirst()),
                valueOptions: ["--env"],
                flagOptions: ["--strict", "--json", "--probe"]
            )
            try await doctor(options: options, environment: environment)
        case "oauth-check":
            let options = try parseOptions(
                arguments: Array(arguments.dropFirst()),
                valueOptions: ["--env"],
                flagOptions: []
            )
            try await oauthCheck(options: options, environment: environment)
        case "serve":
            let options = try parseOptions(
                arguments: Array(arguments.dropFirst()),
                valueOptions: ["--fixtures", "--token", "--path-prefix"],
                flagOptions: []
            )
            try serve(options: options)
        case "--help", "-h", "help":
            print(helpText)
        default:
            throw CommandError.unknownCommand(command)
        }
    }

    private static func capture(options: CommandOptions, environment: [String: String]) async throws {
        let outputPath = options.value(for: "--output") ?? "Fixtures/mirror"
        let shouldWrite = options.has("--write")
        let includeWebSocket = options.has("--websocket")
        if shouldWrite && options.has("--review") {
            throw CommandError.conflictingOptions("--review", "--write")
        }
        let mirrorEnvironment = try HAMirrorEnvironment.fromEnvironment(
            environment,
            environmentFilePath: options.value(for: "--env")
        )
        let fixtureSet = try await HAMirrorCaptureService().capture(
            environment: mirrorEnvironment,
            includeWebSocketEvidence: includeWebSocket
        )

        print("Captured Home Assistant mirror:")
        print("- /api/ status: \(fixtureSet.api.statusCode), bytes: \(fixtureSet.api.bodyText.utf8.count)")
        print("- /api/states status: \(fixtureSet.states.statusCode), bytes: \(fixtureSet.states.bodyText.utf8.count)")
        if let webSocket = fixtureSet.webSocket {
            print("- WebSocket \(webSocket.entityRegistryDisplayList.command): \(availabilityText(webSocket.entityRegistryDisplayList))")
            print("- WebSocket \(webSocket.subscribeEntities.command): \(availabilityText(webSocket.subscribeEntities))")
            if !webSocket.subscribeEntities.eventKeys.isEmpty {
                print("- WebSocket subscribe_entities event keys: \(webSocket.subscribeEntities.eventKeys.joined(separator: ","))")
            }
        }

        if shouldWrite {
            let outputURL = URL(fileURLWithPath: outputPath, isDirectory: true)
            let urls = try HAMirrorFixtureWriter().write(
                fixtureSet,
                to: outputURL
            )
            urls.forEach { print("wrote \($0.path)") }
            _ = try HAMirrorFixtureVerifier().verify(directory: outputURL)
            print("fixture set verified: \(outputURL.path)")
            if HAMirrorFixtureOutputPolicy.requiresIgnoredDirectoryVerification(outputURL) {
                try verifyIgnoredFixtureOutput(urls)
                print("fixture output ignored by git: \(outputURL.path)")
            }
        } else {
            print("review only: pass --write to persist redacted fixtures")
        }
    }

    private static func verify(options: CommandOptions) throws {
        let fixturePath = options.value(for: "--fixtures") ?? "Fixtures/mirror"
        let directory = URL(fileURLWithPath: fixturePath, isDirectory: true)
        _ = try HAMirrorFixtureVerifier().verify(directory: directory)
        print("fixture set verified: \(directory.path)")
    }

    private static func doctor(options: CommandOptions, environment: [String: String]) async throws {
        let envPath = resolvedEnvironmentFilePath(options: options, environment: environment)
        let mirrorEnvironment = try HAMirrorEnvironment.fromEnvironment(
            environment,
            environmentFilePath: options.value(for: "--env")
        )
        let report = mirrorEnvironment.readinessReport
        let liveProbe = options.has("--probe")
            ? await HAMirrorCaptureService().probe(environment: mirrorEnvironment)
            : nil

        if options.has("--json") {
            if let liveProbe {
                print(try renderDoctorProbeJSON(report: report, envPath: envPath, probe: liveProbe))
            } else {
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
                let data = try encoder.encode(report.diagnostic(envPath: envPath))
                print(String(data: data, encoding: .utf8) ?? "{}")
            }
        } else {
            print("Mirror environment readiness: \(envPath)")
            print("- url: present")
            print("- url2: \(presence(report.hasFallbackURL))")
            print("- token: \(presence(report.hasToken))")
            print("- user: \(presence(report.hasUser))")
            print("- password: \(presence(report.hasPassword))")
            print("- PERCHHA_OAUTH_CLIENT_ID: \(presence(report.hasOAuthClientID))")
            print("- PERCHHA_OAUTH_REDIRECT_URI: \(presence(report.hasOAuthRedirectURI))")
            print("- Capture: \(report.canCaptureMirror ? "ready" : "blocked")")
            print("- OAuth check: \(report.canCheckOAuthClientWebsite ? "ready" : "blocked")")
            if let liveProbe {
                print("- Live probe: \(liveProbe.anyReady ? "ready" : "blocked")")
                print("- Primary /api/: \(liveProbe.primary.state.rawValue) - \(liveProbe.primary.message)")
                if let guidance = liveProbe.primary.guidance {
                    print("  hint: \(guidance)")
                }
                if let fallback = liveProbe.fallback {
                    print("- Fallback /api/: \(fallback.state.rawValue) - \(fallback.message)")
                    if let guidance = fallback.guidance {
                        print("  hint: \(guidance)")
                    }
                }
            }
            if !report.issues.isEmpty {
                print("Issues:")
                report.issues.forEach { print("- \($0.description)") }
            }
            let nextSteps = doctorNextSteps(report: report, envPath: envPath, probe: liveProbe)
            if !nextSteps.isEmpty {
                print("Next steps:")
                nextSteps.forEach { print("- \($0)") }
            }
            let suggestedCommands = doctorSuggestedCommands(report: report, envPath: envPath, probe: liveProbe)
            if !suggestedCommands.isEmpty {
                print("Suggested commands:")
                suggestedCommands.forEach { print("- \($0)") }
            }
        }

        if options.has("--strict") && !report.canCaptureMirror {
            throw CommandError.mirrorEnvironmentBlocked(report.blockingMessages(envPath: envPath))
        }
        if options.has("--strict"), let liveProbe, !liveProbe.anyReady {
            throw CommandError.liveProbeBlocked(
                probeBlockingMessages(probe: liveProbe)
            )
        }
    }

    private static func oauthCheck(options: CommandOptions, environment: [String: String]) async throws {
        let envPath = resolvedEnvironmentFilePath(options: options, environment: environment)
        let mirrorEnvironment = try HAMirrorEnvironment.fromEnvironment(
            environment,
            environmentFilePath: options.value(for: "--env")
        )
        let report = mirrorEnvironment.readinessReport
        guard report.canCheckOAuthClientWebsite else {
            throw CommandError.oauthEnvironmentBlocked(report.oauthCheckBlockingMessages(envPath: envPath))
        }
        let environment = try HAOAuthClientWebsiteEnvironment.fromEnvironment(
            environment,
            environmentFilePath: options.value(for: "--env")
        )
        let result = await HomeAssistantClient().verifyOAuthClientWebsite(
            clientID: environment.clientID,
            redirectURI: environment.redirectURI
        )
        switch result {
        case let .success(check):
            if check.websiteFetched {
                print("OAuth client website verified: \(check.clientID)")
                print("OAuth redirect URI declared: \(check.redirectURI)")
            } else {
                print("OAuth client website check skipped: redirect URI shares client website origin")
                print("OAuth redirect URI: \(check.redirectURI)")
            }
        case let .failure(failure):
            throw failure
        }
    }

    private static func resolvedEnvironmentFilePath(
        options: CommandOptions,
        environment: [String: String]
    ) -> String {
        HAMirrorEnvironment.resolvedEnvironmentFilePath(
            environment: environment,
            overridePath: options.value(for: "--env")
        )
    }

    private static func serve(options: CommandOptions) throws {
        let fixturePath = options.value(for: "--fixtures") ?? "Fixtures/mirror"
        let token = options.value(for: "--token") ?? "fake-token"
        let pathPrefix = options.value(for: "--path-prefix") ?? ""
        let directory = URL(fileURLWithPath: fixturePath, isDirectory: true)
        let fixtureSet = try HAMirrorFixtureVerifier().verify(directory: directory)
        let fixtures = try FakeHAFixtures.load(from: directory, bearerToken: token)
        let webSocketMode = FakeHAWebSocketMode.mirrored(
            commandAvailability: mirroredCommandAvailability(from: fixtureSet.webSocket)
        )
        let restServer = try FakeHARESTServer(fixtures: fixtures, pathPrefix: pathPrefix)
        let webSocketServer = try FakeHAWebSocketServer(
            fixtures: fixtures,
            mode: webSocketMode,
            pathPrefix: pathPrefix
        )
        restServer.start()
        webSocketServer.start()
        print("FakeHA serving \(fixturePath)")
        print("- REST: \(restServer.baseURL.absoluteString)")
        print("- WebSocket: \(webSocketURLString(baseURL: webSocketServer.baseURL))")
        if let webSocket = fixtureSet.webSocket {
            for availability in mirroredCommandAvailability(from: webSocket) where !availability.available {
                let suffix = availability.errorCode.map { " (\($0))" } ?? ""
                print("- unavailable: \(availability.command)\(suffix)")
            }
        }
        print("Press Ctrl-C to stop.")
        fflush(stdout)
        withExtendedLifetime((restServer, webSocketServer)) {
            while true {
                Thread.sleep(forTimeInterval: 3600)
            }
        }
    }

    private static let helpText = """
    hamirror

    Captures and verifies anonymized Home Assistant fixtures for PerchHA tests.

    Usage:
      hamirror help
      hamirror capture --env .env.local --output Fixtures/mirror --review
      hamirror capture --env .env.local --output Fixtures/private/mirror --websocket --write
      hamirror verify --fixtures Fixtures/mirror
      hamirror doctor --env .env.local
      hamirror doctor --env .env.local --json
      hamirror doctor --env .env.local --probe
      hamirror oauth-check --env .env.local
      hamirror serve --fixtures Fixtures/mirror --token fake-token
      hamirror serve --fixtures Fixtures/private/m8-real --token fake-token --path-prefix /ha

    Capture reads url, url2, and token from the env file. It tries url first and reuses url2 when the primary capture endpoint fails. User/password are not sent to REST.
    Capture with --write re-verifies the written fixture set immediately; private outputs under Fixtures/private/ also prove they stay ignored by Git.
    Doctor prints redacted key presence/status plus next-step hints. Pass --probe for a live /api/ probe against primary and fallback URLs with endpoint-specific remediation hints, --json for scriptable output, and --strict to fail when capture is blocked.
    OAuth check reads only PERCHHA_OAUTH_CLIENT_ID and PERCHHA_OAUTH_REDIRECT_URI, and reports redacted readiness guidance when they are missing.
    """

    private static func mirroredCommandAvailability(from webSocket: HAMirrorWebSocketEvidence?) -> [FakeHAWebSocketCommandAvailability] {
        guard let webSocket else {
            return []
        }
        return [
            FakeHAWebSocketCommandAvailability(
                command: webSocket.entityRegistryDisplayList.command,
                available: webSocket.entityRegistryDisplayList.available,
                errorCode: webSocket.entityRegistryDisplayList.errorCode
            ),
            FakeHAWebSocketCommandAvailability(
                command: webSocket.subscribeEntities.command,
                available: webSocket.subscribeEntities.available,
                errorCode: webSocket.subscribeEntities.errorCode
            )
        ]
    }

    private static func webSocketURLString(baseURL: URL) -> String {
        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)
        components?.scheme = baseURL.scheme == "https" ? "wss" : "ws"
        components?.path = appendingPath("/api/websocket", to: baseURL.path)
        return components?.url?.absoluteString ?? baseURL.absoluteString
    }

    private static func appendingPath(_ path: String, to basePath: String) -> String {
        let normalizedBase = basePath == "/" ? "" : basePath.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let prefix = normalizedBase.isEmpty ? "" : "/\(normalizedBase)"
        return "\(prefix)\(path)"
    }

    private static func verifyIgnoredFixtureOutput(_ urls: [URL]) throws {
        let root = try gitRepositoryRoot()
        for url in urls {
            let normalizedURL = URL(fileURLWithPath: url.path, isDirectory: false)
                .standardizedFileURL
                .resolvingSymlinksInPath()
            guard normalizedURL.path.hasPrefix(root.path + "/") else {
                throw CommandError.fixtureOutputOutsideRepository(normalizedURL.path)
            }
            let relativePath = String(normalizedURL.path.dropFirst(root.path.count + 1))
            let result = try runGit(arguments: ["check-ignore", "-q", "--", relativePath], currentDirectoryURL: root)
            guard result == 0 else {
                throw CommandError.fixtureOutputNotIgnored(relativePath)
            }
        }
    }

    private static func gitRepositoryRoot() throws -> URL {
        let pipe = Pipe()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["rev-parse", "--show-toplevel"]
        process.standardOutput = pipe
        process.standardError = Pipe()
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw CommandError.gitRepositoryUnavailable
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let text = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty
        else {
            throw CommandError.gitRepositoryUnavailable
        }
        return URL(fileURLWithPath: text, isDirectory: true)
            .standardizedFileURL
            .resolvingSymlinksInPath()
    }

    private static func runGit(arguments: [String], currentDirectoryURL: URL) throws -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.currentDirectoryURL = currentDirectoryURL
        process.arguments = arguments
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        try process.run()
        process.waitUntilExit()
        return process.terminationStatus
    }

    private static func availabilityText(_ evidence: HAMirrorWebSocketCommandEvidence) -> String {
        if evidence.available {
            return "available"
        }
        return "unavailable\(evidence.errorCode.map { " (\($0))" } ?? "")"
    }

    private static func presence(_ value: Bool) -> String {
        value ? "present" : "missing"
    }

    private static func probeBlockingMessages(
        probe: HAMirrorCaptureProbeReport
    ) -> [String] {
        var messages = [probeSummary(label: "primary", endpoint: probe.primary)]
        if let fallback = probe.fallback {
            messages.append(probeSummary(label: "fallback", endpoint: fallback))
        }
        return messages
    }

    private static func doctorNextSteps(
        report: HAMirrorEnvironmentReadinessReport,
        envPath: String,
        probe: HAMirrorCaptureProbeReport?
    ) -> [String] {
        var steps = report.nextSteps(envPath: envPath)
        guard let probe else {
            return steps
        }
        if !probe.anyReady {
            steps.append(contentsOf: probeEndpointNextSteps(label: "Primary", endpoint: probe.primary))
            if let fallback = probe.fallback {
                steps.append(contentsOf: probeEndpointNextSteps(label: "Fallback", endpoint: fallback))
            }
        }
        return steps
    }

    private static func doctorSuggestedCommands(
        report: HAMirrorEnvironmentReadinessReport,
        envPath: String,
        probe: HAMirrorCaptureProbeReport?
    ) -> [String] {
        guard probe?.anyReady != false else {
            return report.canCheckOAuthClientWebsite
                ? ["swift run hamirror oauth-check --env \(shellQuoted(envPath))"]
                : []
        }
        return report.suggestedCommands(envPath: envPath)
    }

    private static func probeEndpointNextSteps(
        label: String,
        endpoint: HAMirrorCaptureEndpointProbe
    ) -> [String] {
        guard let guidance = endpoint.guidance else {
            return []
        }
        return ["\(label) probe: \(guidance)"]
    }

    private static func probeSummary(
        label: String,
        endpoint: HAMirrorCaptureEndpointProbe
    ) -> String {
        let prefix = "\(label) \(endpoint.state.rawValue): \(endpoint.message)"
        guard let guidance = endpoint.guidance else {
            return prefix
        }
        return "\(prefix) Hint: \(guidance)"
    }

    private static func renderDoctorProbeJSON(
        report: HAMirrorEnvironmentReadinessReport,
        envPath: String,
        probe: HAMirrorCaptureProbeReport
    ) throws -> String {
        let baseDiagnostic = report.diagnostic(envPath: envPath)
        let nextSteps = doctorNextSteps(report: report, envPath: envPath, probe: probe)
        let suggestedCommands = doctorSuggestedCommands(report: report, envPath: envPath, probe: probe)
        let primaryObject: [String: Any] = [
            "state": probe.primary.state.rawValue,
            "message": probe.primary.message,
            "guidance": probe.primary.guidance as Any
        ]
        let fallbackObject: Any = probe.fallback.map { endpoint in
            [
                "state": endpoint.state.rawValue,
                "message": endpoint.message,
                "guidance": endpoint.guidance as Any
            ] as [String: Any]
        } ?? NSNull()
        let probeObject: [String: Any] = [
            "ready": probe.anyReady,
            "primary": primaryObject,
            "fallback": fallbackObject
        ]
        let object: [String: Any] = [
            "envPath": baseDiagnostic.envPath,
            "url": baseDiagnostic.url.rawValue,
            "url2": baseDiagnostic.url2.rawValue,
            "token": baseDiagnostic.token.rawValue,
            "user": baseDiagnostic.user.rawValue,
            "password": baseDiagnostic.password.rawValue,
            "oauthClientID": baseDiagnostic.oauthClientID.rawValue,
            "oauthRedirectURI": baseDiagnostic.oauthRedirectURI.rawValue,
            "capture": baseDiagnostic.capture.rawValue,
            "oauthCheck": baseDiagnostic.oauthCheck.rawValue,
            "issues": baseDiagnostic.issues.map {
                [
                    "code": $0.code.rawValue,
                    "description": $0.description
                ]
            },
            "nextSteps": nextSteps,
            "suggestedCommands": suggestedCommands,
            "probe": probeObject
        ]
        let data = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
        return String(data: data, encoding: .utf8) ?? "{}"
    }

    private static func shellQuoted(_ value: String) -> String {
        let safe = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "/._-"))
        if !value.isEmpty && value.unicodeScalars.allSatisfy({ safe.contains($0) }) {
            return value
        }
        let escaped = value.replacingOccurrences(of: "'", with: "'\"'\"'")
        return "'\(escaped)'"
    }

    private static func parseOptions(
        arguments: [String],
        valueOptions: Set<String>,
        flagOptions: Set<String>
    ) throws -> PerchHACommandLineOptions {
        do {
            return try PerchHACommandLineOptions(
                arguments: arguments,
                valueOptions: valueOptions,
                flagOptions: flagOptions,
                nonOptionBehavior: .invalidArgument
            )
        } catch let error as PerchHACommandLineParseError {
            throw CommandError(parseError: error)
        }
    }
}

enum CommandError: Error, CustomStringConvertible {
    case unknownCommand(String)
    case unknownOption(String)
    case invalidArgument(String)
    case missingValue(String)
    case conflictingOptions(String, String)
    case mirrorEnvironmentBlocked([String])
    case liveProbeBlocked([String])
    case oauthEnvironmentBlocked([String])
    case fixtureOutputNotIgnored(String)
    case fixtureOutputOutsideRepository(String)
    case gitRepositoryUnavailable

    init(parseError: PerchHACommandLineParseError) {
        switch parseError {
        case let .unknownOption(option):
            self = .unknownOption(option)
        case let .invalidArgument(argument):
            self = .invalidArgument(argument)
        case let .missingValue(option):
            self = .missingValue(option)
        }
    }

    var description: String {
        switch self {
        case let .unknownCommand(command):
            "unknown command: \(command)"
        case let .unknownOption(option):
            "unknown option: \(option)"
        case let .invalidArgument(argument):
            "invalid argument: \(argument)"
        case let .missingValue(argument):
            "missing value for \(argument)"
        case let .conflictingOptions(first, second):
            "conflicting options: \(first) and \(second)"
        case let .mirrorEnvironmentBlocked(issues):
            "mirror environment is not capture-ready: \(issues.joined(separator: "; "))"
        case let .liveProbeBlocked(issues):
            "mirror live probe is not ready: \(issues.joined(separator: "; "))"
        case let .oauthEnvironmentBlocked(issues):
            "OAuth client website check is not ready: \(issues.joined(separator: "; "))"
        case let .fixtureOutputNotIgnored(path):
            "fixture output must stay ignored by git: \(path)"
        case let .fixtureOutputOutsideRepository(path):
            "fixture output must stay inside the repository worktree for ignored-path verification: \(path)"
        case .gitRepositoryUnavailable:
            "git repository root is unavailable for private fixture verification"
        }
    }
}
