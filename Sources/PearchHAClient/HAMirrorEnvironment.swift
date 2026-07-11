import Foundation

public struct HAMirrorEnvironment: Equatable, Sendable {
    public static let environmentFileEnvironmentKey = "PEARCHHA_ENV_FILE"
    public static let defaultEnvironmentFilePath = ".env.local"
    public static let primaryURLEnvironmentKey = "PEARCHHA_HA_URL"
    public static let fallbackURLEnvironmentKey = "PEARCHHA_HA_FALLBACK_URL"
    public static let tokenEnvironmentKey = "PEARCHHA_HA_TOKEN"
    public static let userEnvironmentKey = "PEARCHHA_HA_USER"
    public static let passwordEnvironmentKey = "PEARCHHA_HA_PASSWORD"
    public static let oauthClientIDEnvironmentKey = "PEARCHHA_OAUTH_CLIENT_ID"
    public static let oauthRedirectURIEnvironmentKey = "PEARCHHA_OAUTH_REDIRECT_URI"

    public let primaryURL: URL
    public let fallbackURL: URL?
    public let token: String?
    public let user: String?
    public let password: String?
    public let oauthClientID: String?
    public let oauthRedirectURI: String?

    public init(
        primaryURL: URL,
        fallbackURL: URL?,
        token: String?,
        user: String?,
        password: String?,
        oauthClientID: String? = nil,
        oauthRedirectURI: String? = nil
    ) {
        self.primaryURL = primaryURL
        self.fallbackURL = fallbackURL
        self.token = token
        self.user = user
        self.password = password
        self.oauthClientID = oauthClientID
        self.oauthRedirectURI = oauthRedirectURI
    }

    public static func load(from path: String) throws -> HAMirrorEnvironment {
        let contents = try String(contentsOfFile: path, encoding: .utf8)
        return try parse(contents)
    }

    public static func fromEnvironment(
        _ environment: [String: String] = ProcessInfo.processInfo.environment,
        environmentFilePath: String? = nil
    ) throws -> HAMirrorEnvironment {
        let environmentPrimaryURL = environmentValue(for: primaryURLEnvironmentKey, environment: environment)
        let fileValues = try environmentFileValues(
            environment: environment,
            overridePath: environmentFilePath,
            tolerateReadErrors: environmentPrimaryURL != nil
        )

        guard let rawURL = environmentPrimaryURL ?? nonBlank(fileValues["url"]) else {
            throw HAMirrorEnvironmentError.missingURL
        }
        guard let primaryURL = parseHomeAssistantBaseURL(rawURL) else {
            throw HAMirrorEnvironmentError.invalidURL(rawURL)
        }

        let rawFallbackURL = environmentValue(for: fallbackURLEnvironmentKey, environment: environment)
            ?? nonBlank(fileValues["url2"])
        let fallbackURL: URL?
        if let rawFallbackURL {
            guard let parsed = parseHomeAssistantBaseURL(rawFallbackURL) else {
                throw HAMirrorEnvironmentError.invalidURL(rawFallbackURL)
            }
            fallbackURL = parsed
        } else {
            fallbackURL = nil
        }

        return HAMirrorEnvironment(
            primaryURL: primaryURL,
            fallbackURL: fallbackURL,
            token: environmentValue(for: tokenEnvironmentKey, environment: environment)
                ?? blankToNil(fileValues["token"]),
            user: environmentValue(for: userEnvironmentKey, environment: environment)
                ?? blankToNil(fileValues["user"]),
            password: environmentValue(for: passwordEnvironmentKey, environment: environment)
                ?? blankToNil(fileValues["password"]),
            oauthClientID: environmentValue(for: oauthClientIDEnvironmentKey, environment: environment)
                ?? blankToNil(fileValues["pearchha_oauth_client_id"]),
            oauthRedirectURI: environmentValue(for: oauthRedirectURIEnvironmentKey, environment: environment)
                ?? blankToNil(fileValues["pearchha_oauth_redirect_uri"])
        )
    }

    public static func parse(_ contents: String) throws -> HAMirrorEnvironment {
        let fields = try parseFields(contents)

        guard let rawURL = fields["url"], !rawURL.isEmpty else {
            throw HAMirrorEnvironmentError.missingURL
        }
        guard let primaryURL = parseHomeAssistantBaseURL(rawURL) else {
            throw HAMirrorEnvironmentError.invalidURL(rawURL)
        }

        let fallbackURL: URL?
        if let rawFallback = fields["url2"], !rawFallback.isEmpty {
            guard let parsed = parseHomeAssistantBaseURL(rawFallback) else {
                throw HAMirrorEnvironmentError.invalidURL(rawFallback)
            }
            fallbackURL = parsed
        } else {
            fallbackURL = nil
        }

        return HAMirrorEnvironment(
            primaryURL: primaryURL,
            fallbackURL: fallbackURL,
            token: blankToNil(fields["token"]),
            user: blankToNil(fields["user"]),
            password: blankToNil(fields["password"]),
            oauthClientID: blankToNil(fields["pearchha_oauth_client_id"]),
            oauthRedirectURI: blankToNil(fields["pearchha_oauth_redirect_uri"])
        )
    }

    public var readinessReport: HAMirrorEnvironmentReadinessReport {
        HAMirrorEnvironmentReadinessReport(environment: self)
    }

    static func parseFields(_ contents: String) throws -> [String: String] {
        var fields: [String: String] = [:]

        for (index, rawLine) in contents.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("#") {
                continue
            }
            guard let separator = line.firstIndex(of: "=") else {
                throw HAMirrorEnvironmentError.invalidLine(index + 1)
            }
            let key = String(line[..<separator]).trimmingCharacters(in: .whitespaces).lowercased()
            let value = String(line[line.index(after: separator)...]).trimmingCharacters(in: .whitespaces)
            fields[key] = unquote(value)
        }
        return fields
    }

    private static func blankToNil(_ value: String?) -> String? {
        guard let value, !value.isEmpty else {
            return nil
        }
        return value
    }

    private static func unquote(_ value: String) -> String {
        guard value.count >= 2 else {
            return value
        }
        if (value.first == "\"" && value.last == "\"") || (value.first == "'" && value.last == "'") {
            return String(value.dropFirst().dropLast())
        }
        return value
    }

    private static func parseHomeAssistantBaseURL(_ value: String) -> URL? {
        if let url = URL(string: value), url.isSupportedHomeAssistantBaseURL {
            return url
        }
        guard !value.contains("://"),
              let url = URL(string: "http://\(value)"),
              url.isSupportedHomeAssistantBaseURL
        else {
            return nil
        }
        return url
    }

    static func environmentValue(for key: String, environment: [String: String]) -> String? {
        blankToNil(environment[key]?.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    public static func resolvedEnvironmentFilePath(
        environment: [String: String],
        overridePath: String? = nil
    ) -> String {
        if let overridePath = blankToNil(overridePath) {
            return overridePath
        }
        if let environmentPath = environmentValue(for: environmentFileEnvironmentKey, environment: environment) {
            return environmentPath
        }
        return defaultEnvironmentFilePath
    }

    static func environmentFileValues(
        environment: [String: String],
        overridePath: String? = nil,
        tolerateReadErrors: Bool = false
    ) throws -> [String: String] {
        let path = resolvedEnvironmentFilePath(environment: environment, overridePath: overridePath)
        let explicitPath = blankToNil(overridePath) != nil
            || environmentValue(for: environmentFileEnvironmentKey, environment: environment) != nil
        guard FileManager.default.fileExists(atPath: path) else {
            if explicitPath && !tolerateReadErrors {
                throw HAMirrorEnvironmentError.missingFile(path)
            }
            return [:]
        }
        do {
            let contents = try String(contentsOfFile: path, encoding: .utf8)
            return try parseFields(contents)
        } catch let error as HAMirrorEnvironmentError {
            if tolerateReadErrors {
                return [:]
            }
            throw error
        } catch {
            if tolerateReadErrors {
                return [:]
            }
            throw HAMirrorEnvironmentError.unreadableFile(path)
        }
    }

    private static func nonBlank(_ value: String?) -> String? {
        blankToNil(value?.trimmingCharacters(in: .whitespacesAndNewlines))
    }
}

public enum HAMirrorEnvironmentReadinessIssue: String, Codable, Equatable, Sendable, CustomStringConvertible {
    case missingCaptureToken
    case usernamePasswordNotCaptureCredentials
    case incompleteOAuthClientWebsiteConfiguration

    public var description: String {
        switch self {
        case .missingCaptureToken:
            "missing token for REST and WebSocket mirror capture"
        case .usernamePasswordNotCaptureCredentials:
            "user/password are present but are not sent to REST or WebSocket APIs"
        case .incompleteOAuthClientWebsiteConfiguration:
            "OAuth client website check requires PEARCHHA_OAUTH_CLIENT_ID and PEARCHHA_OAUTH_REDIRECT_URI"
        }
    }
}

public struct HAMirrorEnvironmentReadinessReport: Equatable, Sendable {
    public let hasFallbackURL: Bool
    public let hasToken: Bool
    public let hasUser: Bool
    public let hasPassword: Bool
    public let hasOAuthClientID: Bool
    public let hasOAuthRedirectURI: Bool

    public init(
        hasFallbackURL: Bool,
        hasToken: Bool,
        hasUser: Bool,
        hasPassword: Bool,
        hasOAuthClientID: Bool,
        hasOAuthRedirectURI: Bool
    ) {
        self.hasFallbackURL = hasFallbackURL
        self.hasToken = hasToken
        self.hasUser = hasUser
        self.hasPassword = hasPassword
        self.hasOAuthClientID = hasOAuthClientID
        self.hasOAuthRedirectURI = hasOAuthRedirectURI
    }

    public init(environment: HAMirrorEnvironment) {
        self.init(
            hasFallbackURL: environment.fallbackURL != nil,
            hasToken: environment.token != nil,
            hasUser: environment.user != nil,
            hasPassword: environment.password != nil,
            hasOAuthClientID: environment.oauthClientID != nil,
            hasOAuthRedirectURI: environment.oauthRedirectURI != nil
        )
    }

    public var canCaptureMirror: Bool {
        hasToken
    }

    public var canCheckOAuthClientWebsite: Bool {
        hasOAuthClientID && hasOAuthRedirectURI
    }

    public var issues: [HAMirrorEnvironmentReadinessIssue] {
        var result: [HAMirrorEnvironmentReadinessIssue] = []
        if !hasToken {
            result.append(.missingCaptureToken)
        }
        if hasUser || hasPassword {
            result.append(.usernamePasswordNotCaptureCredentials)
        }
        if hasOAuthClientID != hasOAuthRedirectURI {
            result.append(.incompleteOAuthClientWebsiteConfiguration)
        }
        return result
    }

    public var nextSteps: [String] {
        nextSteps(envPath: "<file>")
    }

    public func nextSteps(envPath: String) -> [String] {
        var result: [String] = []
        let quotedEnvPath = Self.shellQuoted(envPath)
        if !hasToken {
            result.append(
                "Set token= in \(envPath) or export PEARCHHA_HA_TOKEN to a Home Assistant bearer access token before mirror capture. A long-lived access token works, or use the native OAuth sign-in flow and copy the resulting access token."
            )
        }
        if (hasUser || hasPassword) && !hasToken {
            result.append(
                "user/password alone cannot authenticate the REST or WebSocket APIs. Keep them only for browser sign-in or manual work; mirror capture still needs token= in \(envPath) or PEARCHHA_HA_TOKEN in the process environment."
            )
        }
        if !hasOAuthClientID && !hasOAuthRedirectURI {
            result.append(
                "If you want native OAuth sign-in instead of a long-lived token, set both PEARCHHA_OAUTH_CLIENT_ID and PEARCHHA_OAUTH_REDIRECT_URI in \(envPath), or export both values, then run hamirror oauth-check --env \(quotedEnvPath)."
            )
        } else if hasOAuthClientID != hasOAuthRedirectURI {
            result.append(
                "Set both PEARCHHA_OAUTH_CLIENT_ID and PEARCHHA_OAUTH_REDIRECT_URI in \(envPath), or export both values, then rerun hamirror oauth-check --env \(quotedEnvPath)."
            )
        }
        return result
    }

    public func suggestedCommands(envPath: String) -> [String] {
        var result: [String] = []
        let quotedEnvPath = Self.shellQuoted(envPath)
        if canCaptureMirror {
            result.append(
                "swift run hamirror capture --env \(quotedEnvPath) --output Fixtures/private/m8-real --websocket --write"
            )
        }
        if canCheckOAuthClientWebsite {
            result.append(
                "swift run hamirror oauth-check --env \(quotedEnvPath)"
            )
        }
        return result
    }

    public var blockingMessages: [String] {
        issues.map(\.description) + nextSteps
    }

    public func blockingMessages(envPath: String) -> [String] {
        issues.map(\.description) + nextSteps(envPath: envPath)
    }

    public func oauthCheckBlockingMessages(envPath: String) -> [String] {
        var result: [String] = []
        if !hasOAuthClientID && !hasOAuthRedirectURI {
            result.append("OAuth client website check requires PEARCHHA_OAUTH_CLIENT_ID and PEARCHHA_OAUTH_REDIRECT_URI")
        } else if hasOAuthClientID != hasOAuthRedirectURI {
            result.append(HAMirrorEnvironmentReadinessIssue.incompleteOAuthClientWebsiteConfiguration.description)
        }
        result.append(
            contentsOf: nextSteps(envPath: envPath).filter {
                $0.contains("hamirror oauth-check") || $0.contains("PEARCHHA_OAUTH_CLIENT_ID")
            }
        )
        return result
    }

    public func diagnostic(envPath: String) -> HAMirrorEnvironmentReadinessDiagnostic {
        HAMirrorEnvironmentReadinessDiagnostic(report: self, envPath: envPath)
    }

    private static func shellQuoted(_ value: String) -> String {
        let safe = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "/._-"))
        if !value.isEmpty && value.unicodeScalars.allSatisfy({ safe.contains($0) }) {
            return value
        }
        let escaped = value.replacingOccurrences(of: "'", with: "'\"'\"'")
        return "'\(escaped)'"
    }
}

public enum HAMirrorEnvironmentReadinessPresence: String, Codable, Equatable, Sendable {
    case present
    case missing

    public init(_ value: Bool) {
        self = value ? .present : .missing
    }
}

public enum HAMirrorEnvironmentReadinessState: String, Codable, Equatable, Sendable {
    case ready
    case blocked

    public init(_ value: Bool) {
        self = value ? .ready : .blocked
    }
}

public struct HAMirrorEnvironmentReadinessDiagnosticIssue: Codable, Equatable, Sendable {
    public let code: HAMirrorEnvironmentReadinessIssue
    public let description: String

    public init(code: HAMirrorEnvironmentReadinessIssue, description: String) {
        self.code = code
        self.description = description
    }
}

public struct HAMirrorEnvironmentReadinessDiagnostic: Codable, Equatable, Sendable {
    public let envPath: String
    public let url: HAMirrorEnvironmentReadinessPresence
    public let url2: HAMirrorEnvironmentReadinessPresence
    public let token: HAMirrorEnvironmentReadinessPresence
    public let user: HAMirrorEnvironmentReadinessPresence
    public let password: HAMirrorEnvironmentReadinessPresence
    public let oauthClientID: HAMirrorEnvironmentReadinessPresence
    public let oauthRedirectURI: HAMirrorEnvironmentReadinessPresence
    public let capture: HAMirrorEnvironmentReadinessState
    public let oauthCheck: HAMirrorEnvironmentReadinessState
    public let issues: [HAMirrorEnvironmentReadinessDiagnosticIssue]
    public let nextSteps: [String]
    public let suggestedCommands: [String]

    public init(report: HAMirrorEnvironmentReadinessReport, envPath: String) {
        self.envPath = envPath
        url = .present
        url2 = HAMirrorEnvironmentReadinessPresence(report.hasFallbackURL)
        token = HAMirrorEnvironmentReadinessPresence(report.hasToken)
        user = HAMirrorEnvironmentReadinessPresence(report.hasUser)
        password = HAMirrorEnvironmentReadinessPresence(report.hasPassword)
        oauthClientID = HAMirrorEnvironmentReadinessPresence(report.hasOAuthClientID)
        oauthRedirectURI = HAMirrorEnvironmentReadinessPresence(report.hasOAuthRedirectURI)
        capture = HAMirrorEnvironmentReadinessState(report.canCaptureMirror)
        oauthCheck = HAMirrorEnvironmentReadinessState(report.canCheckOAuthClientWebsite)
        issues = report.issues.map {
            HAMirrorEnvironmentReadinessDiagnosticIssue(code: $0, description: $0.description)
        }
        nextSteps = report.nextSteps(envPath: envPath)
        suggestedCommands = report.suggestedCommands(envPath: envPath)
    }
}

public struct HAOAuthClientWebsiteEnvironment: Equatable, Sendable {
    public let clientID: String
    public let redirectURI: String

    public init(clientID: String, redirectURI: String) throws {
        let normalizedClientID = clientID.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedRedirectURI = redirectURI.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedClientID.isEmpty else {
            throw HAMirrorEnvironmentError.missingOAuthClientID
        }
        guard !normalizedRedirectURI.isEmpty else {
            throw HAMirrorEnvironmentError.missingOAuthRedirectURI
        }
        self.clientID = normalizedClientID
        self.redirectURI = normalizedRedirectURI
    }

    public static func load(from path: String) throws -> HAOAuthClientWebsiteEnvironment {
        let contents = try String(contentsOfFile: path, encoding: .utf8)
        return try parse(contents)
    }

    public static func fromEnvironment(
        _ environment: [String: String] = ProcessInfo.processInfo.environment,
        environmentFilePath: String? = nil
    ) throws -> HAOAuthClientWebsiteEnvironment {
        let environmentClientID = HAMirrorEnvironment.environmentValue(
            for: HAMirrorEnvironment.oauthClientIDEnvironmentKey,
            environment: environment
        )
        let environmentRedirectURI = HAMirrorEnvironment.environmentValue(
            for: HAMirrorEnvironment.oauthRedirectURIEnvironmentKey,
            environment: environment
        )
        let hasRequiredEnvironmentValues = environmentClientID != nil && environmentRedirectURI != nil
        let fileValues = try HAMirrorEnvironment.environmentFileValues(
            environment: environment,
            overridePath: environmentFilePath,
            tolerateReadErrors: hasRequiredEnvironmentValues
        )
        return try HAOAuthClientWebsiteEnvironment(
            clientID: environmentClientID ?? fileValues["pearchha_oauth_client_id"] ?? "",
            redirectURI: environmentRedirectURI ?? fileValues["pearchha_oauth_redirect_uri"] ?? ""
        )
    }

    public static func parse(_ contents: String) throws -> HAOAuthClientWebsiteEnvironment {
        let fields = try HAMirrorEnvironment.parseFields(contents)
        return try HAOAuthClientWebsiteEnvironment(
            clientID: fields["pearchha_oauth_client_id"] ?? "",
            redirectURI: fields["pearchha_oauth_redirect_uri"] ?? ""
        )
    }
}

private extension URL {
    var isSupportedHomeAssistantBaseURL: Bool {
        guard let scheme = scheme?.lowercased(), scheme == "http" || scheme == "https" else {
            return false
        }
        guard let host, !host.isEmpty else {
            return false
        }
        return true
    }
}

public enum HAMirrorEnvironmentError: Error, Equatable, CustomStringConvertible {
    case invalidLine(Int)
    case missingFile(String)
    case unreadableFile(String)
    case missingURL
    case invalidURL(String)
    case missingOAuthClientID
    case missingOAuthRedirectURI

    public var description: String {
        switch self {
        case let .invalidLine(line):
            "invalid .env line \(line)"
        case let .missingFile(path):
            "environment file does not exist: \(path)"
        case let .unreadableFile(path):
            "environment file is unreadable: \(path)"
        case .missingURL:
            "missing url in environment file"
        case let .invalidURL(value):
            "invalid URL: \(value)"
        case .missingOAuthClientID:
            "missing PEARCHHA_OAUTH_CLIENT_ID in environment file"
        case .missingOAuthRedirectURI:
            "missing PEARCHHA_OAUTH_REDIRECT_URI in environment file"
        }
    }
}
