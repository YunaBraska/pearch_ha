import Foundation
import Darwin
import FakeHA
import PerchHAClient

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

    static func run(arguments: [String]) async throws {
        guard let command = arguments.first else {
            print(helpText)
            return
        }

        switch command {
        case "capture":
            let options = try CommandOptions(
                arguments: Array(arguments.dropFirst()),
                valueOptions: ["--env", "--output"],
                flagOptions: ["--review", "--write", "--websocket"]
            )
            try await capture(options: options)
        case "verify":
            let options = try CommandOptions(
                arguments: Array(arguments.dropFirst()),
                valueOptions: ["--fixtures"],
                flagOptions: []
            )
            try verify(options: options)
        case "oauth-check":
            let options = try CommandOptions(
                arguments: Array(arguments.dropFirst()),
                valueOptions: ["--env"],
                flagOptions: []
            )
            try await oauthCheck(options: options)
        case "serve":
            let options = try CommandOptions(
                arguments: Array(arguments.dropFirst()),
                valueOptions: ["--fixtures", "--token"],
                flagOptions: []
            )
            try serve(options: options)
        case "--help", "-h", "help":
            print(helpText)
        default:
            throw CommandError.unknownCommand(command)
        }
    }

    private static func capture(options: CommandOptions) async throws {
        let envPath = options.value(for: "--env") ?? ".env.local"
        let outputPath = options.value(for: "--output") ?? "Fixtures/mirror"
        let shouldWrite = options.has("--write")
        let includeWebSocket = options.has("--websocket")
        if shouldWrite && options.has("--review") {
            throw CommandError.conflictingOptions("--review", "--write")
        }
        let environment = try HAMirrorEnvironment.load(from: envPath)
        let fixtureSet = try await HAMirrorCaptureService().capture(
            environment: environment,
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
            let urls = try HAMirrorFixtureWriter().write(
                fixtureSet,
                to: URL(fileURLWithPath: outputPath, isDirectory: true)
            )
            urls.forEach { print("wrote \($0.path)") }
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

    private static func oauthCheck(options: CommandOptions) async throws {
        let envPath = options.value(for: "--env") ?? ".env.local"
        let environment = try HAOAuthClientWebsiteEnvironment.load(from: envPath)
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

    private static func serve(options: CommandOptions) throws {
        let fixturePath = options.value(for: "--fixtures") ?? "Fixtures/mirror"
        let token = options.value(for: "--token") ?? "fake-token"
        let fixtures = try FakeHAFixtures.load(
            from: URL(fileURLWithPath: fixturePath, isDirectory: true),
            bearerToken: token
        )
        let server = try FakeHARESTServer(fixtures: fixtures)
        server.start()
        print("FakeHA serving \(fixturePath) at \(server.baseURL.absoluteString)")
        print("Press Ctrl-C to stop.")
        fflush(stdout)
        withExtendedLifetime(server) {
            while true {
                Thread.sleep(forTimeInterval: 3600)
            }
        }
    }

    private static let helpText = """
    hamirror

    Captures and verifies anonymized Home Assistant fixtures for PerchHA tests.

    Usage:
      hamirror capture --env .env.local --output Fixtures/mirror --review
      hamirror capture --env .env.local --output Fixtures/private/mirror --websocket --write
      hamirror verify --fixtures Fixtures/mirror
      hamirror oauth-check --env .env.local
      hamirror serve --fixtures Fixtures/mirror --token fake-token

    Capture reads url, url2, and token from the env file. User/password are not sent to REST.
    OAuth check reads only PERCHHA_OAUTH_CLIENT_ID and PERCHHA_OAUTH_REDIRECT_URI.
    """

    private static func availabilityText(_ evidence: HAMirrorWebSocketCommandEvidence) -> String {
        if evidence.available {
            return "available"
        }
        return "unavailable\(evidence.errorCode.map { " (\($0))" } ?? "")"
    }
}

struct CommandOptions {
    private let arguments: [String]
    private let valueOptions: Set<String>
    private let flagOptions: Set<String>

    init(arguments: [String], valueOptions: Set<String>, flagOptions: Set<String>) throws {
        self.arguments = arguments
        self.valueOptions = valueOptions
        self.flagOptions = flagOptions

        var index = 0
        while index < arguments.count {
            let argument = arguments[index]
            guard argument.hasPrefix("--") else {
                throw CommandError.invalidArgument(argument)
            }
            if flagOptions.contains(argument) {
                index += 1
            } else if valueOptions.contains(argument) {
                guard index + 1 < arguments.count else {
                    throw CommandError.missingValue(argument)
                }
                index += 2
            } else {
                throw CommandError.unknownOption(argument)
            }
        }
    }

    func has(_ key: String) -> Bool {
        arguments.contains(key)
    }

    func value(for key: String) -> String? {
        guard let index = arguments.firstIndex(of: key), index + 1 < arguments.count else {
            return nil
        }
        return arguments[index + 1]
    }
}

enum CommandError: Error, CustomStringConvertible {
    case unknownCommand(String)
    case unknownOption(String)
    case invalidArgument(String)
    case missingValue(String)
    case conflictingOptions(String, String)

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
        }
    }
}
