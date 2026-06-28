import Foundation

public struct HAMirrorEnvironment: Equatable, Sendable {
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
            oauthClientID: blankToNil(fields["perchha_oauth_client_id"]),
            oauthRedirectURI: blankToNil(fields["perchha_oauth_redirect_uri"])
        )
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

    public static func parse(_ contents: String) throws -> HAOAuthClientWebsiteEnvironment {
        let fields = try HAMirrorEnvironment.parseFields(contents)
        return try HAOAuthClientWebsiteEnvironment(
            clientID: fields["perchha_oauth_client_id"] ?? "",
            redirectURI: fields["perchha_oauth_redirect_uri"] ?? ""
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
    case missingURL
    case invalidURL(String)
    case missingOAuthClientID
    case missingOAuthRedirectURI

    public var description: String {
        switch self {
        case let .invalidLine(line):
            "invalid .env line \(line)"
        case .missingURL:
            "missing url in environment file"
        case let .invalidURL(value):
            "invalid URL: \(value)"
        case .missingOAuthClientID:
            "missing PERCHHA_OAUTH_CLIENT_ID in environment file"
        case .missingOAuthRedirectURI:
            "missing PERCHHA_OAUTH_REDIRECT_URI in environment file"
        }
    }
}
