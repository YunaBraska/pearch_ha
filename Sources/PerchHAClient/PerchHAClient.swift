import Foundation
import PerchHACore
import PerchHASupport
import Security

/// An ordered, non-empty list of Home Assistant base URLs.
///
/// The client tries the URLs in order: it advances to the next URL only on a
/// retryable failure (unreachable / TLS-rejected / transport) and stops
/// immediately on any other failure (authentication, invalid response, HTTP
/// status, and so on). The first URL is the primary; the rest are alternatives
/// (internal, external, VPN, ...).
public struct HAEndpoint: Equatable, Sendable {
    /// The ordered base URLs, guaranteed non-empty.
    public let urls: [URL]

    /// Creates an endpoint from an ordered list of URLs.
    ///
    /// - Parameter urls: The ordered base URLs. Must be non-empty.
    /// - Precondition: `urls` is not empty.
    public init(urls: [URL]) {
        precondition(!urls.isEmpty, "HAEndpoint requires at least one URL")
        self.urls = urls
    }

    /// Creates an endpoint from a primary URL and an optional single fallback.
    ///
    /// Retained so existing call sites compile unchanged.
    ///
    /// - Parameters:
    ///   - primaryURL: The primary base URL.
    ///   - fallbackURL: An optional fallback base URL.
    public init(primaryURL: URL, fallbackURL: URL?) {
        self.init(urls: [primaryURL] + (fallbackURL.map { [$0] } ?? []))
    }

    /// The primary (first) URL.
    public var primaryURL: URL {
        urls[0]
    }

    /// The first alternative URL, or `nil` when only the primary is configured.
    public var fallbackURL: URL? {
        urls.count > 1 ? urls[1] : nil
    }
}

public struct HAConnectionInput: Equatable, Sendable {
    public let endpoint: HAEndpoint
    public let token: String
    public let serverTrustPolicy: HAServerTrustPolicy

    public init(endpoint: HAEndpoint, token: String, serverTrustPolicy: HAServerTrustPolicy = .default) {
        self.endpoint = endpoint
        self.token = token
        self.serverTrustPolicy = serverTrustPolicy
    }
}

public struct HAServerTrustPolicy: Equatable, Sendable {
    public static let `default` = HAServerTrustPolicy()

    /// Hosts whose self-signed TLS certificates are trusted when ``trustsAllHosts`` is false.
    public let allowedSelfSignedCertificateHosts: Set<String>

    /// When true, every secure (`https`/`wss`) host is trusted regardless of certificate origin.
    ///
    /// This takes precedence over ``allowedSelfSignedCertificateHosts``: any secure host is
    /// trusted, including hosts presenting self-signed certificates.
    public let trustsAllHosts: Bool

    /// Creates a server-trust policy.
    ///
    /// - Parameters:
    ///   - allowedSelfSignedCertificateHosts: Hosts whose self-signed certificates are trusted
    ///     when `trustsAllHosts` is false. Hosts are normalized (trimmed, lowercased); blanks are dropped.
    ///   - trustsAllHosts: When true, all secure hosts are trusted unconditionally.
    public init(allowedSelfSignedCertificateHosts: Set<String> = [], trustsAllHosts: Bool = false) {
        self.allowedSelfSignedCertificateHosts = Set(
            allowedSelfSignedCertificateHosts.compactMap(Self.normalizedHost)
        )
        self.trustsAllHosts = trustsAllHosts
    }

    /// Reports whether the certificate presented by `url` should be trusted.
    ///
    /// - Parameter url: The URL whose host is evaluated. Only `https`/`wss` schemes can be trusted.
    /// - Returns: True for secure schemes when ``trustsAllHosts`` is set or the host is allow-listed.
    public func allowsSelfSignedCertificate(for url: URL) -> Bool {
        let scheme = url.scheme?.lowercased() ?? ""
        guard ["https", "wss"].contains(scheme) else {
            return false
        }
        if trustsAllHosts {
            return true
        }
        return allowsSelfSignedCertificate(forHost: url.host)
    }

    /// Reports whether the certificate presented by `host` should be trusted.
    ///
    /// - Parameter host: The host to evaluate.
    /// - Returns: True when ``trustsAllHosts`` is set (for any non-empty host) or the host is allow-listed.
    public func allowsSelfSignedCertificate(forHost host: String?) -> Bool {
        guard let host = host.flatMap(Self.normalizedHost) else {
            return false
        }
        if trustsAllHosts {
            return true
        }
        return allowedSelfSignedCertificateHosts.contains(host)
    }

    private static func normalizedHost(_ host: String) -> String? {
        let normalized = host.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return normalized.isEmpty ? nil : normalized
    }
}

public struct HARESTRequest: Equatable, Sendable {
    public let method: String
    public let url: URL
    public let headers: [String: String]
    public let body: Data?
    public let serverTrustPolicy: HAServerTrustPolicy

    public init(
        method: String,
        url: URL,
        headers: [String: String],
        body: Data? = nil,
        serverTrustPolicy: HAServerTrustPolicy = .default
    ) {
        self.method = method
        self.url = url
        self.headers = headers
        self.body = body
        self.serverTrustPolicy = serverTrustPolicy
    }
}

public struct HARESTResponse: Equatable, Sendable {
    public let statusCode: Int
    public let headers: [String: String]
    public let body: Data

    public init(statusCode: Int, headers: [String: String], body: Data) {
        self.statusCode = statusCode
        self.headers = headers
        self.body = body
    }
}

public protocol HARESTTransport: Sendable {
    func send(_ request: HARESTRequest) async throws -> HARESTResponse
}

public struct URLSessionHARESTTransport: HARESTTransport {
    public init() {}

    public func send(_ request: HARESTRequest) async throws -> HARESTResponse {
        var urlRequest = URLRequest(url: request.url)
        urlRequest.httpMethod = request.method
        request.headers.forEach { key, value in
            urlRequest.setValue(value, forHTTPHeaderField: key)
        }
        urlRequest.httpBody = request.body

        let session: URLSession
        if request.serverTrustPolicy.allowsSelfSignedCertificate(for: request.url) {
            session = URLSession(
                configuration: .ephemeral,
                delegate: HAServerTrustPolicyURLSessionDelegate(policy: request.serverTrustPolicy),
                delegateQueue: nil
            )
        } else {
            session = .shared
        }
        defer {
            if session !== URLSession.shared {
                session.finishTasksAndInvalidate()
            }
        }

        let (data, response) = try await session.data(for: urlRequest)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw HAClientTransportError.nonHTTPResponse
        }

        var headers: [String: String] = [:]
        for (key, value) in httpResponse.allHeaderFields {
            guard let key = key as? String else {
                continue
            }
            headers[key] = String(describing: value)
        }

        return HARESTResponse(statusCode: httpResponse.statusCode, headers: headers, body: data)
    }
}

private final class HAServerTrustPolicyURLSessionDelegate: NSObject, URLSessionDelegate, @unchecked Sendable {
    private let policy: HAServerTrustPolicy

    init(policy: HAServerTrustPolicy) {
        self.policy = policy
    }

    func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge
    ) async -> (URLSession.AuthChallengeDisposition, URLCredential?) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              policy.allowsSelfSignedCertificate(forHost: challenge.protectionSpace.host),
              let trust = challenge.protectionSpace.serverTrust,
              policy.trustsAllHosts || Self.isAllowedSelfSignedTrust(trust, host: challenge.protectionSpace.host)
        else {
            return (.performDefaultHandling, nil)
        }
        return (.useCredential, URLCredential(trust: trust))
    }

    private static func isAllowedSelfSignedTrust(_ trust: SecTrust, host: String) -> Bool {
        guard let certificateChain = SecTrustCopyCertificateChain(trust) as? [SecCertificate],
              certificateChain.count == 1,
              isSelfIssued(certificateChain[0])
        else {
            return false
        }
        SecTrustSetPolicies(trust, SecPolicyCreateSSL(true, host as CFString))
        SecTrustSetAnchorCertificates(trust, certificateChain as CFArray)
        SecTrustSetAnchorCertificatesOnly(trust, true)
        return SecTrustEvaluateWithError(trust, nil)
    }

    private static func isSelfIssued(_ certificate: SecCertificate) -> Bool {
        guard let subject = SecCertificateCopyNormalizedSubjectSequence(certificate) as Data?,
              let issuer = SecCertificateCopyNormalizedIssuerSequence(certificate) as Data?
        else {
            return false
        }
        return subject == issuer
    }
}

public enum HAClientTransportError: Error, Equatable {
    case nonHTTPResponse
}

public enum HAClientResult<Value: Sendable>: Sendable {
    case success(Value)
    case failure(HAClientFailure)

    public func flatMap<NewValue: Sendable>(_ transform: (Value) -> HAClientResult<NewValue>) -> HAClientResult<NewValue> {
        switch self {
        case let .success(value):
            transform(value)
        case let .failure(failure):
            .failure(failure)
        }
    }

    public func map<NewValue: Sendable>(_ transform: (Value) -> NewValue) -> HAClientResult<NewValue> {
        switch self {
        case let .success(value):
            .success(transform(value))
        case let .failure(failure):
            .failure(failure)
        }
    }
}

extension HAClientResult: Equatable where Value: Equatable {}

public struct HAOAuthAuthorizationRequest: Equatable, Sendable {
    public let baseURL: URL
    public let clientID: String
    public let redirectURI: String
    public let state: String?

    public init(baseURL: URL, clientID: String, redirectURI: String, state: String? = nil) {
        self.baseURL = baseURL
        self.clientID = clientID
        self.redirectURI = redirectURI
        self.state = state
    }
}

public struct HAOAuthToken: Equatable, Sendable {
    public let accessToken: String
    public let refreshToken: String?
    public let expiresInSeconds: Int
    public let tokenType: String

    public init(accessToken: String, refreshToken: String?, expiresInSeconds: Int, tokenType: String) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.expiresInSeconds = expiresInSeconds
        self.tokenType = tokenType
    }
}

public struct HAOAuthClientWebsiteCheck: Equatable, Sendable {
    public let clientID: String
    public let redirectURI: String
    public let websiteFetched: Bool
    public let redirectURIDeclared: Bool

    public init(clientID: String, redirectURI: String, websiteFetched: Bool, redirectURIDeclared: Bool) {
        self.clientID = clientID
        self.redirectURI = redirectURI
        self.websiteFetched = websiteFetched
        self.redirectURIDeclared = redirectURIDeclared
    }
}

public enum HAOAuthRevokeResult: Equatable, Sendable {
    case revoked
}

public struct HARESTCheck: Equatable, Sendable {
    public let message: String

    public init(message: String) {
        self.message = message
    }
}

public struct HAWebSocketCheck: Equatable, Sendable {
    public let haVersion: String

    public init(haVersion: String) {
        self.haVersion = haVersion
    }
}

public typealias HAJSONValue = ActionValue
public typealias HAServiceCall = ActionSpec

public struct HAServiceCallResult: Equatable, Sendable {
    public let contextID: String?

    public init(contextID: String?) {
        self.contextID = contextID
    }
}

public enum HAClientFailure: Error, Equatable, Sendable, CustomStringConvertible {
    case authentication
    case unreachable(host: String)
    case tlsRejected(host: String)
    case invalidURL(path: String)
    case invalidResponse(path: String)
    case invalidPayload(path: String, reason: String)
    case httpStatus(path: String, statusCode: Int)
    case webSocketProtocol(String)
    case webSocketCommand(id: Int?, code: String?, message: String?)
    case transport(String)

    public var description: String {
        switch self {
        case .authentication:
            "Home Assistant rejected the access token"
        case let .unreachable(host):
            "Home Assistant is unreachable at \(host)"
        case let .tlsRejected(host):
            "Home Assistant TLS certificate was rejected for \(host)"
        case let .invalidURL(path):
            "invalid Home Assistant URL path: \(path)"
        case let .invalidResponse(path):
            "Home Assistant returned a non-HTTP response for \(path)"
        case let .invalidPayload(path, reason):
            "Home Assistant returned invalid payload for \(path): \(reason)"
        case let .httpStatus(path, statusCode):
            "Home Assistant returned HTTP \(statusCode) for \(path)"
        case let .webSocketProtocol(message):
            "Home Assistant WebSocket protocol error: \(message)"
        case let .webSocketCommand(id, code, message):
            "Home Assistant WebSocket command \(id.map(String.init) ?? "?") failed: \([code, message].compactMap { $0 }.joined(separator: " - "))"
        case let .transport(message):
            "Home Assistant transport failed: \(message)"
        }
    }

    public var connectionFailure: ConnectionFailure {
        switch self {
        case .authentication:
            .authentication
        case let .unreachable(host):
            .unreachable(host: host)
        case let .tlsRejected(host):
            .tlsRejected(host: host)
        case let .invalidURL(path):
            .protocolError("invalid URL path: \(path)")
        case let .invalidResponse(path):
            .protocolError("non-HTTP response for \(path)")
        case let .invalidPayload(path, reason):
            .protocolError("invalid payload for \(path): \(reason)")
        case let .httpStatus(path, statusCode):
            .protocolError("HTTP \(statusCode) for \(path)")
        case let .webSocketProtocol(message):
            .protocolError("WebSocket protocol error: \(message)")
        case let .webSocketCommand(id, code, message):
            .protocolError("WebSocket command \(id.map(String.init) ?? "?") failed: \([code, message].compactMap { $0 }.joined(separator: " - "))")
        case let .transport(message):
            .protocolError(message)
        }
    }
}

public protocol HAClient: Sendable {
    func describe() -> PerchHAModule
    func checkRESTConnection(_ input: HAConnectionInput) async -> HAClientResult<HARESTCheck>
    func states(_ input: HAConnectionInput) async -> HAClientResult<[EntityState]>
    func checkWebSocketConnection(_ input: HAConnectionInput) async -> HAClientResult<HAWebSocketCheck>
    func webSocketStates(_ input: HAConnectionInput) async -> HAClientResult<[EntityState]>
    func nextStateChangedEvent(_ input: HAConnectionInput) async -> HAClientResult<EntityState>
    func services(_ input: HAConnectionInput) async -> HAClientResult<[HAServiceMetadata]>
    func callService(_ input: HAConnectionInput, call: HAServiceCall) async -> HAClientResult<HAServiceCallResult>
    func discovery(_ input: HAConnectionInput) async -> HAClientResult<DiscoverySnapshot>
    func history(_ input: HAConnectionInput, entityID: EntityID, range: HistoryRange, end: Date) async -> HAClientResult<HistorySeries>
}

public struct PlannedHAClient: HAClient {
    private let client: HomeAssistantClient

    public init(transport: any HARESTTransport = URLSessionHARESTTransport()) {
        client = HomeAssistantClient(transport: transport)
    }

    public func describe() -> PerchHAModule {
        PerchHAClient.module
    }

    public func checkRESTConnection(_ input: HAConnectionInput) async -> HAClientResult<HARESTCheck> {
        await client.checkRESTConnection(input)
    }

    public func states(_ input: HAConnectionInput) async -> HAClientResult<[EntityState]> {
        await client.states(input)
    }

    public func checkWebSocketConnection(_ input: HAConnectionInput) async -> HAClientResult<HAWebSocketCheck> {
        await client.checkWebSocketConnection(input)
    }

    public func webSocketStates(_ input: HAConnectionInput) async -> HAClientResult<[EntityState]> {
        await client.webSocketStates(input)
    }

    public func nextStateChangedEvent(_ input: HAConnectionInput) async -> HAClientResult<EntityState> {
        await client.nextStateChangedEvent(input)
    }

    public func services(_ input: HAConnectionInput) async -> HAClientResult<[HAServiceMetadata]> {
        await client.services(input)
    }

    public func callService(_ input: HAConnectionInput, call: HAServiceCall) async -> HAClientResult<HAServiceCallResult> {
        await client.callService(input, call: call)
    }

    public func discovery(_ input: HAConnectionInput) async -> HAClientResult<DiscoverySnapshot> {
        await client.discovery(input)
    }

    public func history(_ input: HAConnectionInput, entityID: EntityID, range: HistoryRange, end: Date = Date()) async -> HAClientResult<HistorySeries> {
        await client.history(input, entityID: entityID, range: range, end: end)
    }
}

public struct HomeAssistantClient: HAClient {
    private let transport: any HARESTTransport
    private let redactor: Redactor

    public init(transport: any HARESTTransport = URLSessionHARESTTransport(), redactor: Redactor = Redactor()) {
        self.transport = transport
        self.redactor = redactor
    }

    public func describe() -> PerchHAModule {
        PerchHAClient.module
    }

    public func authorizationURL(for request: HAOAuthAuthorizationRequest) -> HAClientResult<URL> {
        guard isHTTPHomeAssistantBaseURL(request.baseURL) else {
            return .failure(.invalidURL(path: "/auth/authorize"))
        }
        let clientID = request.clientID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clientID.isEmpty else {
            return .failure(.invalidPayload(path: "/auth/authorize", reason: "client_id is required"))
        }
        let redirectURI = request.redirectURI.trimmingCharacters(in: .whitespacesAndNewlines)
        guard
            !redirectURI.isEmpty,
            let parsedRedirectURI = URL(string: redirectURI),
            parsedRedirectURI.scheme?.isEmpty == false
        else {
            return .failure(.invalidPayload(path: "/auth/authorize", reason: "redirect_uri is invalid"))
        }
        do {
            let url = try request.baseURL.homeAssistantURL(path: "/auth/authorize")
            guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
                return .failure(.invalidURL(path: "/auth/authorize"))
            }
            var queryItems = [
                URLQueryItem(name: "client_id", value: clientID),
                URLQueryItem(name: "redirect_uri", value: redirectURI)
            ]
            if let state = request.state?.trimmingCharacters(in: .whitespacesAndNewlines), !state.isEmpty {
                queryItems.append(URLQueryItem(name: "state", value: state))
            }
            components.percentEncodedQuery = Self.formURLEncodedString(queryItems)
            guard let authorizationURL = components.url else {
                return .failure(.invalidURL(path: "/auth/authorize"))
            }
            return .success(authorizationURL)
        } catch {
            return .failure(.invalidURL(path: "/auth/authorize"))
        }
    }

    public func verifyOAuthClientWebsite(clientID: String, redirectURI: String) async -> HAClientResult<HAOAuthClientWebsiteCheck> {
        let normalizedClientID = clientID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let clientURL = URL(string: normalizedClientID),
              isHTTPHomeAssistantBaseURL(clientURL)
        else {
            return .failure(.invalidPayload(path: "/auth/client_id", reason: "client_id must be an application website URL"))
        }
        let normalizedRedirectURI = redirectURI.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let redirectURL = URL(string: normalizedRedirectURI),
              redirectURL.scheme?.isEmpty == false
        else {
            return .failure(.invalidPayload(path: "/auth/client_id", reason: "redirect_uri is invalid"))
        }
        if redirectURLMatchesClientWebsite(redirectURL: redirectURL, clientURL: clientURL) {
            return .success(
                HAOAuthClientWebsiteCheck(
                    clientID: normalizedClientID,
                    redirectURI: normalizedRedirectURI,
                    websiteFetched: false,
                    redirectURIDeclared: false
                )
            )
        }

        let request = HARESTRequest(
            method: "GET",
            url: clientURL,
            headers: ["Accept": "text/html,application/xhtml+xml"]
        )
        do {
            let response = try await transport.send(request)
            guard 200..<300 ~= response.statusCode else {
                return .failure(.httpStatus(path: normalizedClientID, statusCode: response.statusCode))
            }
            let firstTenKB = response.body.prefix(10_000)
            let html = String(decoding: firstTenKB, as: UTF8.self)
            guard Self.htmlDeclaresRedirectURI(html, redirectURI: normalizedRedirectURI) else {
                return .failure(.invalidPayload(path: normalizedClientID, reason: "redirect_uri link is required in first 10000 bytes"))
            }
            return .success(
                HAOAuthClientWebsiteCheck(
                    clientID: normalizedClientID,
                    redirectURI: normalizedRedirectURI,
                    websiteFetched: true,
                    redirectURIDeclared: true
                )
            )
        } catch let error as HAClientTransportError {
            switch error {
            case .nonHTTPResponse:
                return .failure(.invalidResponse(path: normalizedClientID))
            }
        } catch let error as URLError {
            return .failure(map(urlError: error, baseURL: clientURL))
        } catch {
            return .failure(.transport(redactor.redact(message: String(describing: error))))
        }
    }

    public func exchangeAuthorizationCode(
        baseURL: URL,
        code: String,
        clientID: String,
        serverTrustPolicy: HAServerTrustPolicy = .default
    ) async -> HAClientResult<HAOAuthToken> {
        await sendAuthTokenRequest(
            baseURL: baseURL,
            formItems: [
                URLQueryItem(name: "grant_type", value: "authorization_code"),
                URLQueryItem(name: "code", value: code.trimmingCharacters(in: .whitespacesAndNewlines)),
                URLQueryItem(name: "client_id", value: clientID.trimmingCharacters(in: .whitespacesAndNewlines))
            ],
            requiresRefreshToken: true,
            serverTrustPolicy: serverTrustPolicy
        )
    }

    public func refreshAccessToken(
        baseURL: URL,
        refreshToken: String,
        clientID: String
    ) async -> HAClientResult<HAOAuthToken> {
        await refreshAccessToken(
            baseURL: baseURL,
            refreshToken: refreshToken,
            clientID: clientID,
            serverTrustPolicy: .default
        )
    }

    public func refreshAccessToken(
        baseURL: URL,
        refreshToken: String,
        clientID: String,
        serverTrustPolicy: HAServerTrustPolicy
    ) async -> HAClientResult<HAOAuthToken> {
        await sendAuthTokenRequest(
            baseURL: baseURL,
            formItems: [
                URLQueryItem(name: "grant_type", value: "refresh_token"),
                URLQueryItem(name: "refresh_token", value: refreshToken.trimmingCharacters(in: .whitespacesAndNewlines)),
                URLQueryItem(name: "client_id", value: clientID.trimmingCharacters(in: .whitespacesAndNewlines))
            ],
            requiresRefreshToken: false,
            serverTrustPolicy: serverTrustPolicy
        )
    }

    public func revokeRefreshToken(
        baseURL: URL,
        refreshToken: String,
        serverTrustPolicy: HAServerTrustPolicy = .default
    ) async -> HAClientResult<HAOAuthRevokeResult> {
        await sendAuthRevokeRequest(
            baseURL: baseURL,
            formItems: [
                URLQueryItem(name: "token", value: refreshToken.trimmingCharacters(in: .whitespacesAndNewlines)),
                URLQueryItem(name: "action", value: "revoke")
            ],
            serverTrustPolicy: serverTrustPolicy
        )
    }

    public func checkRESTConnection(_ input: HAConnectionInput) async -> HAClientResult<HARESTCheck> {
        await get(path: "/api/", input: input) { response in
            decode(path: "/api/", response: response, as: HARESTCheckDTO.self).map { dto in
                HARESTCheck(message: dto.message)
            }
        }
    }

    public func states(_ input: HAConnectionInput) async -> HAClientResult<[EntityState]> {
        await get(path: "/api/states", input: input) { response in
            decode(path: "/api/states", response: response, as: [HAStateDTO].self).map { states in
                states.map(\.entityState)
            }
        }
    }

    public func checkWebSocketConnection(_ input: HAConnectionInput) async -> HAClientResult<HAWebSocketCheck> {
        let result = await authenticateWebSocket(input)
        switch result {
        case let .success(session):
            session.close(code: .goingAway)
            return .success(session.check)
        case let .failure(failure):
            return .failure(failure)
        }
    }

    public func webSocketStates(_ input: HAConnectionInput) async -> HAClientResult<[EntityState]> {
        let result = await authenticateWebSocket(input)
        switch result {
        case let .success(session):
            defer {
                session.close(code: .goingAway)
            }
            return await sendGetStates(on: session.task)
        case let .failure(failure):
            return .failure(failure)
        }
    }

    public func nextStateChangedEvent(_ input: HAConnectionInput) async -> HAClientResult<EntityState> {
        let firstAttempt = await nextStateChangedEventAttempt(input)
        switch firstAttempt {
        case .success:
            return firstAttempt
        case let .failure(failure) where failure.shouldRetryLiveSubscription:
            return await nextStateChangedEventAttempt(input)
        case .failure:
            return firstAttempt
        }
    }

    private func nextStateChangedEventAttempt(_ input: HAConnectionInput) async -> HAClientResult<EntityState> {
        let result = await authenticateWebSocket(input)
        switch result {
        case let .success(session):
            defer {
                session.close(code: .goingAway)
            }
            return await subscribeForOneEntityUpdateThenFallback(on: session.task)
        case let .failure(failure):
            return .failure(failure)
        }
    }

    public func callService(_ input: HAConnectionInput, call: HAServiceCall) async -> HAClientResult<HAServiceCallResult> {
        let result = await authenticateWebSocket(input)
        switch result {
        case let .success(session):
            defer {
                session.close(code: .goingAway)
            }
            return await sendCallService(on: session.task, call: call)
        case let .failure(failure):
            return .failure(failure)
        }
    }

    public func services(_ input: HAConnectionInput) async -> HAClientResult<[HAServiceMetadata]> {
        let result = await authenticateWebSocket(input)
        switch result {
        case let .success(session):
            defer {
                session.close(code: .goingAway)
            }
            return await sendGetServices(on: session.task)
        case let .failure(failure):
            return .failure(failure)
        }
    }

    public func discovery(_ input: HAConnectionInput) async -> HAClientResult<DiscoverySnapshot> {
        let result = await authenticateWebSocket(input)
        switch result {
        case let .success(session):
            defer {
                session.close(code: .goingAway)
            }

            let areas = await registryValuesOrEmptyIfUnavailable(
                sendAreaRegistryList(on: session.task, id: 1)
            )
            guard case let .success(areaValues) = areas else {
                if case let .failure(failure) = areas {
                    return .failure(failure)
                }
                return .failure(.webSocketProtocol("area registry failed without an error"))
            }

            let devices = await registryValuesOrEmptyIfUnavailable(
                sendDeviceRegistryList(on: session.task, id: 2)
            )
            guard case let .success(deviceValues) = devices else {
                if case let .failure(failure) = devices {
                    return .failure(failure)
                }
                return .failure(.webSocketProtocol("device registry failed without an error"))
            }

            let entities = await sendEntityRegistryDisplayListThenFallback(on: session.task)
            guard case let .success(entityValues) = entities else {
                if case let .failure(failure) = entities {
                    return .failure(failure)
                }
                return .failure(.webSocketProtocol("entity registry failed without an error"))
            }

            let states = await sendGetStates(on: session.task, id: 5)
            guard case let .success(stateValues) = states else {
                if case let .failure(failure) = states {
                    return .failure(failure)
                }
                return .failure(.webSocketProtocol("state discovery failed without an error"))
            }

            return .success(
                DiscoverySnapshot(
                    areas: areaValues,
                    devices: deviceValues,
                    entities: entityValues,
                    states: stateValues
                )
            )
        case let .failure(failure):
            return .failure(failure)
        }
    }

    public func history(_ input: HAConnectionInput, entityID: EntityID, range: HistoryRange, end: Date = Date()) async -> HAClientResult<HistorySeries> {
        let start = end.addingTimeInterval(-range.historyDuration)
        if range.prefersRecorderStatistics {
            let recorderStatistics = await recorderStatisticsHistory(input, entityID: entityID, range: range, start: start, end: end)
            switch recorderStatistics {
            case .success:
                return recorderStatistics
            case let .failure(failure) where failure.shouldFallbackFromRecorderStatisticsToREST:
                return await restHistory(input, entityID: entityID, range: range, start: start, end: end)
            case .failure:
                return recorderStatistics
            }
        }
        return await restHistory(input, entityID: entityID, range: range, start: start, end: end)
    }

    private func restHistory(
        _ input: HAConnectionInput,
        entityID: EntityID,
        range: HistoryRange,
        start: Date,
        end: Date
    ) async -> HAClientResult<HistorySeries> {
        let path = "/api/history/period/\(Self.historyDateFormatter.string(from: start))"
        return await get(
            path: path,
            queryItems: [
                URLQueryItem(name: "filter_entity_id", value: entityID.rawValue),
                URLQueryItem(name: "end_time", value: Self.historyDateFormatter.string(from: end)),
                URLQueryItem(name: "minimal_response", value: "true"),
                URLQueryItem(name: "no_attributes", value: "true")
            ],
            input: input
        ) { response in
            decode(path: "/api/history/period", response: response, as: [[HAHistoryStateDTO]].self).map { groups in
                let samples = groups
                    .flatMap { $0 }
                    .filter { $0.entityID == nil || $0.entityID == entityID.rawValue }
                    .map(\.sample)
                    .sorted { $0.timestamp < $1.timestamp }
                return HistorySeries(entityID: entityID, range: range, samples: samples)
            }
        }
    }

    private func recorderStatisticsHistory(
        _ input: HAConnectionInput,
        entityID: EntityID,
        range: HistoryRange,
        start: Date,
        end: Date
    ) async -> HAClientResult<HistorySeries> {
        let result = await authenticateWebSocket(input)
        switch result {
        case let .success(session):
            defer {
                session.close(code: .goingAway)
            }
            return await sendRecorderStatisticsHistory(
                on: session.task,
                entityID: entityID,
                range: range,
                start: start,
                end: end
            )
        case let .failure(failure):
            return .failure(failure)
        }
    }

    private func get<Value: Sendable>(
        path: String,
        queryItems: [URLQueryItem] = [],
        input: HAConnectionInput,
        transform: @Sendable (HARESTResponse) -> HAClientResult<Value>
    ) async -> HAClientResult<Value> {
        var lastFailure: HAClientFailure?
        for baseURL in input.endpoint.urls {
            let attempt = await sendGET(
                path: path,
                queryItems: queryItems,
                baseURL: baseURL,
                token: input.token,
                serverTrustPolicy: input.serverTrustPolicy
            )
            switch attempt {
            case let .success(response):
                return transform(response)
            case let .failure(failure):
                guard shouldRetryOnFallback(failure) else {
                    return .failure(failure)
                }
                lastFailure = failure
            }
        }
        return .failure(lastFailure ?? .transport("no endpoint configured"))
    }

    private func sendGET(
        path: String,
        queryItems: [URLQueryItem] = [],
        baseURL: URL,
        token: String,
        serverTrustPolicy: HAServerTrustPolicy
    ) async -> HAClientResult<HARESTResponse> {
        let url: URL
        do {
            url = try baseURL.homeAssistantURL(path: path, queryItems: queryItems)
        } catch {
            return .failure(.invalidURL(path: path))
        }

        let request = HARESTRequest(
            method: "GET",
            url: url,
            headers: [
                "Accept": "application/json",
                "Authorization": "Bearer \(token)"
            ],
            serverTrustPolicy: serverTrustPolicy
        )

        do {
            let response = try await transport.send(request)
            switch response.statusCode {
            case 200..<300:
                return .success(response)
            case 401, 403:
                return .failure(.authentication)
            default:
                return .failure(.httpStatus(path: path, statusCode: response.statusCode))
            }
        } catch let error as HAClientTransportError {
            switch error {
            case .nonHTTPResponse:
                return .failure(.invalidResponse(path: path))
            }
        } catch let error as URLError {
            return .failure(map(urlError: error, baseURL: baseURL))
        } catch {
            return .failure(.transport(redactor.redact(message: String(describing: error))))
        }
    }

    private func sendAuthTokenRequest(
        baseURL: URL,
        formItems: [URLQueryItem],
        requiresRefreshToken: Bool,
        serverTrustPolicy: HAServerTrustPolicy
    ) async -> HAClientResult<HAOAuthToken> {
        guard let validationFailure = authFormValidationFailure(path: "/auth/token", formItems: formItems) else {
            return await postForm(
                path: "/auth/token",
                baseURL: baseURL,
                formItems: formItems,
                serverTrustPolicy: serverTrustPolicy
            ).flatMap { response in
                decodeOAuthToken(response: response, requiresRefreshToken: requiresRefreshToken)
            }
        }
        return .failure(validationFailure)
    }

    private func sendAuthRevokeRequest(
        baseURL: URL,
        formItems: [URLQueryItem],
        serverTrustPolicy: HAServerTrustPolicy
    ) async -> HAClientResult<HAOAuthRevokeResult> {
        guard let validationFailure = authFormValidationFailure(path: "/auth/token", formItems: formItems) else {
            return await postForm(
                path: "/auth/token",
                baseURL: baseURL,
                formItems: formItems,
                serverTrustPolicy: serverTrustPolicy
            ).map { _ in .revoked }
        }
        return .failure(validationFailure)
    }

    private func postForm(
        path: String,
        baseURL: URL,
        formItems: [URLQueryItem],
        serverTrustPolicy: HAServerTrustPolicy
    ) async -> HAClientResult<HARESTResponse> {
        guard isHTTPHomeAssistantBaseURL(baseURL) else {
            return .failure(.invalidURL(path: path))
        }

        let url: URL
        do {
            url = try baseURL.homeAssistantURL(path: path)
        } catch {
            return .failure(.invalidURL(path: path))
        }

        let request = HARESTRequest(
            method: "POST",
            url: url,
            headers: [
                "Accept": "application/json",
                "Content-Type": "application/x-www-form-urlencoded"
            ],
            body: Self.formURLEncodedData(formItems),
            serverTrustPolicy: serverTrustPolicy
        )

        do {
            let response = try await transport.send(request)
            switch response.statusCode {
            case 200..<300:
                return .success(response)
            case 400:
                return .failure(.invalidPayload(path: path, reason: "HTTP 400 invalid request"))
            case 401, 403:
                return .failure(.authentication)
            default:
                return .failure(.httpStatus(path: path, statusCode: response.statusCode))
            }
        } catch let error as HAClientTransportError {
            switch error {
            case .nonHTTPResponse:
                return .failure(.invalidResponse(path: path))
            }
        } catch let error as URLError {
            return .failure(map(urlError: error, baseURL: baseURL))
        } catch {
            return .failure(.transport(redactor.redact(message: String(describing: error))))
        }
    }

    private func authFormValidationFailure(path: String, formItems: [URLQueryItem]) -> HAClientFailure? {
        for item in formItems {
            guard let value = item.value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
                return .invalidPayload(path: path, reason: "\(item.name) is required")
            }
        }
        return nil
    }

    private func decodeOAuthToken(response: HARESTResponse, requiresRefreshToken: Bool) -> HAClientResult<HAOAuthToken> {
        let decoded = decode(path: "/auth/token", response: response, as: HAOAuthTokenDTO.self)
        switch decoded {
        case let .success(dto):
            guard dto.tokenType.caseInsensitiveCompare("Bearer") == .orderedSame else {
                return .failure(.invalidPayload(path: "/auth/token", reason: "token_type must be Bearer"))
            }
            guard !dto.accessToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return .failure(.invalidPayload(path: "/auth/token", reason: "access_token is required"))
            }
            guard dto.expiresIn > 0 else {
                return .failure(.invalidPayload(path: "/auth/token", reason: "expires_in must be positive"))
            }
            if let refreshToken = dto.refreshToken,
               refreshToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            {
                return .failure(.invalidPayload(path: "/auth/token", reason: "refresh_token is required"))
            }
            if requiresRefreshToken, dto.refreshToken == nil {
                return .failure(.invalidPayload(path: "/auth/token", reason: "refresh_token is required"))
            }
            return .success(
                HAOAuthToken(
                    accessToken: dto.accessToken,
                    refreshToken: dto.refreshToken,
                    expiresInSeconds: dto.expiresIn,
                    tokenType: dto.tokenType
                )
            )
        case let .failure(failure):
            return .failure(failure)
        }
    }

    private func redirectURLMatchesClientWebsite(redirectURL: URL, clientURL: URL) -> Bool {
        guard ["http", "https"].contains(redirectURL.scheme?.lowercased() ?? "") else {
            return false
        }
        return redirectURL.host?.lowercased() == clientURL.host?.lowercased()
            && effectivePort(redirectURL) == effectivePort(clientURL)
    }

    private func effectivePort(_ url: URL) -> Int? {
        if let port = url.port {
            return port
        }
        switch url.scheme?.lowercased() {
        case "http":
            return 80
        case "https":
            return 443
        default:
            return nil
        }
    }

    private static func htmlDeclaresRedirectURI(_ html: String, redirectURI: String) -> Bool {
        guard let linkExpression = try? NSRegularExpression(
            pattern: "<link\\b[^>]*>",
            options: [.caseInsensitive, .dotMatchesLineSeparators]
        ) else {
            return false
        }
        let range = NSRange(html.startIndex..<html.endIndex, in: html)
        return linkExpression.matches(in: html, range: range).contains { match in
            guard let tagRange = Range(match.range, in: html) else {
                return false
            }
            let tag = String(html[tagRange])
            let rel = attributeValue(named: "rel", in: tag)
            let href = attributeValue(named: "href", in: tag)
            let relTokens = rel?.split(whereSeparator: { $0.isWhitespace }).map { $0.lowercased() } ?? []
            return relTokens.contains("redirect_uri") && href == redirectURI
        }
    }

    private static func attributeValue(named name: String, in tag: String) -> String? {
        let escapedName = NSRegularExpression.escapedPattern(for: name)
        guard let expression = try? NSRegularExpression(
            pattern: #"(?i)\b"# + escapedName + #"\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s>]+))"#,
            options: []
        ) else {
            return nil
        }
        let range = NSRange(tag.startIndex..<tag.endIndex, in: tag)
        guard let match = expression.firstMatch(in: tag, range: range) else {
            return nil
        }
        for index in 1..<match.numberOfRanges {
            guard match.range(at: index).location != NSNotFound,
                  let valueRange = Range(match.range(at: index), in: tag)
            else {
                continue
            }
            return String(tag[valueRange]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return nil
    }

    private func isHTTPHomeAssistantBaseURL(_ baseURL: URL) -> Bool {
        ["http", "https"].contains(baseURL.scheme?.lowercased() ?? "") && baseURL.host?.isEmpty == false
    }

    private static func formURLEncodedData(_ items: [URLQueryItem]) -> Data {
        Data(formURLEncodedString(items).utf8)
    }

    private static func formURLEncodedString(_ items: [URLQueryItem]) -> String {
        items.map { item in
            "\(formURLEncodedComponent(item.name))=\(formURLEncodedComponent(item.value ?? ""))"
        }
        .joined(separator: "&")
    }

    private static func formURLEncodedComponent(_ value: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._*")
        return value
            .addingPercentEncoding(withAllowedCharacters: allowed)?
            .replacingOccurrences(of: "%20", with: "+") ?? ""
    }

    private func decode<Value: Decodable>(path: String, response: HARESTResponse, as type: Value.Type) -> HAClientResult<Value> {
        do {
            return .success(try JSONDecoder().decode(type, from: response.body))
        } catch {
            return .failure(.invalidPayload(path: path, reason: redactor.redact(message: String(describing: error))))
        }
    }

    private func shouldRetryOnFallback(_ failure: HAClientFailure) -> Bool {
        switch failure {
        case .unreachable, .tlsRejected, .transport:
            true
        case .authentication, .invalidURL, .invalidResponse, .invalidPayload, .httpStatus, .webSocketProtocol, .webSocketCommand:
            false
        }
    }

    private func map(urlError: URLError, baseURL: URL) -> HAClientFailure {
        let host = baseURL.host ?? baseURL.absoluteString
        switch urlError.code {
        case .secureConnectionFailed,
             .serverCertificateHasBadDate,
             .serverCertificateUntrusted,
             .serverCertificateHasUnknownRoot,
             .serverCertificateNotYetValid,
             .clientCertificateRejected,
             .clientCertificateRequired,
             .cannotLoadFromNetwork:
            return .tlsRejected(host: host)
        case .cannotFindHost,
             .cannotConnectToHost,
             .networkConnectionLost,
             .dnsLookupFailed,
             .notConnectedToInternet,
             .timedOut,
             .internationalRoamingOff,
             .callIsActive,
             .dataNotAllowed:
            return .unreachable(host: host)
        default:
            return .transport(redactor.redact(message: urlError.localizedDescription))
        }
    }

    private func map(transportError error: Error, baseURL: URL) -> HAClientFailure {
        if let urlError = error as? URLError {
            return map(urlError: urlError, baseURL: baseURL)
        }
        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain {
            return map(
                urlError: URLError(URLError.Code(rawValue: nsError.code)),
                baseURL: baseURL
            )
        }
        return .transport(redactor.redact(message: String(describing: error)))
    }

    private func authenticateWebSocket(_ input: HAConnectionInput) async -> HAWebSocketAuthenticationResult {
        var lastFailure: HAClientFailure?
        for baseURL in input.endpoint.urls {
            let attempt = await authenticateWebSocket(
                baseURL: baseURL,
                token: input.token,
                serverTrustPolicy: input.serverTrustPolicy
            )
            switch attempt {
            case .success:
                return attempt
            case let .failure(failure):
                guard shouldRetryOnFallback(failure) else {
                    return .failure(failure)
                }
                lastFailure = failure
            }
        }
        return .failure(lastFailure ?? .transport("no endpoint configured"))
    }

    private func authenticateWebSocket(
        baseURL: URL,
        token: String,
        serverTrustPolicy: HAServerTrustPolicy
    ) async -> HAWebSocketAuthenticationResult {
        let url: URL
        do {
            url = try baseURL.homeAssistantWebSocketURL(path: "/api/websocket")
        } catch {
            return .failure(.invalidURL(path: "/api/websocket"))
        }

        let context = makeWebSocketTask(url: url, serverTrustPolicy: serverTrustPolicy)
        let task = context.task
        task.resume()

        let required = await receiveWebSocketEnvelope(task: task, path: "/api/websocket")
        switch required {
        case let .success(envelope):
            guard envelope.type == "auth_required" else {
                task.cancel(with: .protocolError, reason: nil)
                context.invalidate()
                return .failure(.webSocketProtocol("expected auth_required, received \(envelope.type)"))
            }
        case let .failure(failure):
            task.cancel(with: .goingAway, reason: nil)
            context.invalidate()
            return .failure(failure)
        }

        let auth = HAWebSocketAuthCommand(accessToken: token)
        guard let authMessage = encodeWebSocketMessage(auth) else {
            task.cancel(with: .protocolError, reason: nil)
            context.invalidate()
            return .failure(.invalidPayload(path: "/api/websocket", reason: "could not encode auth command"))
        }
        do {
            try await task.send(.string(authMessage))
        } catch {
            task.cancel(with: .goingAway, reason: nil)
            context.invalidate()
            return .failure(map(transportError: error, baseURL: baseURL))
        }

        let response = await receiveWebSocketEnvelope(task: task, path: "/api/websocket")
        switch response {
        case let .success(envelope):
            if envelope.type == "auth_ok" {
                return .success(
                    AuthenticatedWebSocket(
                        task: task,
                        session: context.session,
                        shouldInvalidateSession: context.shouldInvalidateSession,
                        check: HAWebSocketCheck(haVersion: envelope.haVersion ?? "")
                    )
                )
            }
            if envelope.type == "auth_invalid" {
                task.cancel(with: .goingAway, reason: nil)
                context.invalidate()
                return .failure(.authentication)
            }
            task.cancel(with: .protocolError, reason: nil)
            context.invalidate()
            return .failure(.webSocketProtocol("expected auth_ok, received \(envelope.type)"))
        case let .failure(failure):
            task.cancel(with: .goingAway, reason: nil)
            context.invalidate()
            return .failure(failure)
        }
    }

    private func makeWebSocketTask(
        url: URL,
        serverTrustPolicy: HAServerTrustPolicy
    ) -> HAWebSocketTaskContext {
        if serverTrustPolicy.allowsSelfSignedCertificate(for: url) {
            let session = URLSession(
                configuration: .ephemeral,
                delegate: HAServerTrustPolicyURLSessionDelegate(policy: serverTrustPolicy),
                delegateQueue: nil
            )
            return HAWebSocketTaskContext(
                task: session.webSocketTask(with: url),
                session: session,
                shouldInvalidateSession: true
            )
        }
        return HAWebSocketTaskContext(
            task: URLSession.shared.webSocketTask(with: url),
            session: URLSession.shared,
            shouldInvalidateSession: false
        )
    }

    private func sendGetStates(on task: URLSessionWebSocketTask, id: Int = 1) async -> HAClientResult<[EntityState]> {
        let response = await sendWebSocketCommandEnvelope(
            on: task,
            command: HAWebSocketCommand(id: id, type: "get_states"),
            expectedID: id,
            commandName: "get_states"
        )
        switch response {
        case let .success(envelope):
            guard let result = envelope.resultStates else {
                return .failure(.invalidPayload(path: "/api/websocket", reason: "missing get_states result"))
            }
            return .success(result.map(\.entityState))
        case let .failure(failure):
            return .failure(failure)
        }
    }

    private func sendAreaRegistryList(on task: URLSessionWebSocketTask, id: Int) async -> HAClientResult<[Area]> {
        let response = await sendWebSocketCommandEnvelope(
            on: task,
            command: HAWebSocketCommand(id: id, type: "config/area_registry/list"),
            expectedID: id,
            commandName: "config/area_registry/list"
        )
        switch response {
        case let .success(envelope):
            guard let areas = envelope.resultAreas else {
                return .failure(.invalidPayload(path: "/api/websocket", reason: "missing area registry result"))
            }
            return .success(areas.map(\.area))
        case let .failure(failure):
            return .failure(failure)
        }
    }

    private func sendDeviceRegistryList(on task: URLSessionWebSocketTask, id: Int) async -> HAClientResult<[Device]> {
        let response = await sendWebSocketCommandEnvelope(
            on: task,
            command: HAWebSocketCommand(id: id, type: "config/device_registry/list"),
            expectedID: id,
            commandName: "config/device_registry/list"
        )
        switch response {
        case let .success(envelope):
            guard let devices = envelope.resultDevices else {
                return .failure(.invalidPayload(path: "/api/websocket", reason: "missing device registry result"))
            }
            return .success(devices.map(\.device))
        case let .failure(failure):
            return .failure(failure)
        }
    }

    private func sendEntityRegistryDisplayList(on task: URLSessionWebSocketTask, id: Int) async -> HAClientResult<[EntityRegistryEntry]> {
        let response = await sendWebSocketCommandEnvelope(
            on: task,
            command: HAWebSocketCommand(id: id, type: "config/entity_registry/list_for_display"),
            expectedID: id,
            commandName: "config/entity_registry/list_for_display"
        )
        switch response {
        case let .success(envelope):
            guard let displayList = envelope.resultEntityRegistryDisplayList else {
                return .failure(.invalidPayload(path: "/api/websocket", reason: "missing entity registry display result"))
            }
            return .success(displayList.entities.map(\.entry))
        case let .failure(failure):
            return .failure(failure)
        }
    }

    private func sendEntityRegistryList(on task: URLSessionWebSocketTask, id: Int) async -> HAClientResult<[EntityRegistryEntry]> {
        let response = await sendWebSocketCommandEnvelope(
            on: task,
            command: HAWebSocketCommand(id: id, type: "config/entity_registry/list"),
            expectedID: id,
            commandName: "config/entity_registry/list"
        )
        switch response {
        case let .success(envelope):
            guard let entities = envelope.resultEntityRegistryEntries else {
                return .failure(.invalidPayload(path: "/api/websocket", reason: "missing entity registry result"))
            }
            return .success(entities.map(\.entry))
        case let .failure(failure):
            return .failure(failure)
        }
    }

    private func sendEntityRegistryDisplayListThenFallback(on task: URLSessionWebSocketTask) async -> HAClientResult<[EntityRegistryEntry]> {
        let displayList = await sendEntityRegistryDisplayList(on: task, id: 3)
        switch displayList {
        case .success:
            return displayList
        case let .failure(failure) where failure.isUnavailableCommand:
            return registryValuesOrEmptyIfUnavailable(
                await sendEntityRegistryList(on: task, id: 4)
            )
        case .failure:
            return displayList
        }
    }

    private func registryValuesOrEmptyIfUnavailable<Value>(_ result: HAClientResult<[Value]>) -> HAClientResult<[Value]> {
        switch result {
        case .success:
            return result
        case let .failure(failure) where failure.isUnavailableCommand:
            return .success([])
        case .failure:
            return result
        }
    }

    private func subscribeForOneEntityUpdateThenFallback(on task: URLSessionWebSocketTask) async -> HAClientResult<EntityState> {
        let optimized = await subscribeForOneEntityUpdate(on: task)
        switch optimized {
        case .success:
            return optimized
        case let .failure(failure) where failure.isUnavailableCommand:
            return await subscribeForOneStateChangedEvent(on: task, id: 3)
        case .failure:
            return optimized
        }
    }

    private func subscribeForOneEntityUpdate(on task: URLSessionWebSocketTask) async -> HAClientResult<EntityState> {
        let currentStates = await sendGetStates(on: task, id: 1)
        var knownStates: [EntityID: EntityState]
        switch currentStates {
        case let .success(states):
            knownStates = Dictionary(uniqueKeysWithValues: states.map { ($0.id, $0) })
        case let .failure(failure):
            return .failure(failure)
        }

        guard let message = encodeWebSocketMessage(HAWebSocketSubscribeEntitiesCommand(id: 2)) else {
            return .failure(.invalidPayload(path: "/api/websocket", reason: "could not encode subscribe_entities command"))
        }
        do {
            try await task.send(.string(message))
        } catch {
            return .failure(
                map(
                    transportError: error,
                    baseURL: task.currentRequest?.url ?? URL(fileURLWithPath: "/")
                )
            )
        }

        let ack = await receiveWebSocketEnvelope(task: task, path: "/api/websocket")
        switch ack {
        case let .success(envelope):
            guard envelope.type == "result", envelope.id == 2 else {
                return .failure(.webSocketProtocol("expected subscribe_entities result"))
            }
            guard envelope.success == true else {
                return .failure(.webSocketCommand(id: envelope.id, code: envelope.error?.code, message: envelope.error?.message))
            }
        case let .failure(failure):
            return .failure(failure)
        }

        while true {
            let event = await receiveWebSocketEnvelope(task: task, path: "/api/websocket")
            switch event {
            case let .success(envelope):
                guard envelope.type == "event", envelope.id == 2 else {
                    return .failure(.webSocketProtocol("expected subscribe_entities event"))
                }
                if let state = envelope.event?.firstEntityUpdate(updating: &knownStates) {
                    return .success(state)
                }
            case let .failure(failure):
                return .failure(failure)
            }
        }
    }

    private func subscribeForOneStateChangedEvent(on task: URLSessionWebSocketTask, id: Int = 1) async -> HAClientResult<EntityState> {
        guard let message = encodeWebSocketMessage(HAWebSocketSubscribeEventsCommand(id: id, eventType: "state_changed")) else {
            return .failure(.invalidPayload(path: "/api/websocket", reason: "could not encode subscribe_events command"))
        }
        do {
            try await task.send(.string(message))
        } catch {
            return .failure(
                map(
                    transportError: error,
                    baseURL: task.currentRequest?.url ?? URL(fileURLWithPath: "/")
                )
            )
        }

        let ack = await receiveWebSocketEnvelope(task: task, path: "/api/websocket")
        switch ack {
        case let .success(envelope):
            guard envelope.type == "result", envelope.id == id, envelope.success == true else {
                return .failure(.webSocketProtocol("expected subscribe_events result"))
            }
        case let .failure(failure):
            return .failure(failure)
        }

        let event = await receiveWebSocketEnvelope(task: task, path: "/api/websocket")
        switch event {
        case let .success(envelope):
            guard envelope.type == "event", envelope.id == id, envelope.event?.eventType == "state_changed" else {
                return .failure(.webSocketProtocol("expected state_changed event"))
            }
            guard let state = envelope.event?.data?.newState else {
                return .failure(.invalidPayload(path: "/api/websocket", reason: "missing new_state"))
            }
            return .success(state.entityState)
        case let .failure(failure):
            return .failure(failure)
        }
    }

    private func sendCallService(on task: URLSessionWebSocketTask, call: HAServiceCall) async -> HAClientResult<HAServiceCallResult> {
        let response = await sendWebSocketCommandEnvelope(
            on: task,
            command: HAWebSocketCallServiceCommand(id: 1, call: call),
            expectedID: 1,
            commandName: "call_service"
        )
        switch response {
        case let .success(envelope):
            return .success(HAServiceCallResult(contextID: envelope.serviceCallResult?.context?.id))
        case let .failure(failure):
            return .failure(failure)
        }
    }

    private func sendGetServices(on task: URLSessionWebSocketTask) async -> HAClientResult<[HAServiceMetadata]> {
        let response = await sendWebSocketCommandEnvelope(
            on: task,
            command: HAWebSocketCommand(id: 1, type: "get_services"),
            expectedID: 1,
            commandName: "get_services"
        )
        switch response {
        case let .success(envelope):
            guard let services = envelope.resultServices else {
                return .failure(.invalidPayload(path: "/api/websocket", reason: "missing services result"))
            }
            return .success(
                services.keys.sorted().flatMap { domain in
                    (services[domain] ?? [:]).keys.sorted().map { service in
                        services[domain]?[service]?.metadata(domain: domain, service: service)
                            ?? HAServiceMetadata(domain: domain, service: service, name: nil, description: nil)
                    }
                }
            )
        case let .failure(failure):
            return .failure(failure)
        }
    }

    private func sendRecorderStatisticsHistory(
        on task: URLSessionWebSocketTask,
        entityID: EntityID,
        range: HistoryRange,
        start: Date,
        end: Date
    ) async -> HAClientResult<HistorySeries> {
        guard let period = range.recorderStatisticsPeriod else {
            return .failure(.invalidPayload(path: "/api/websocket", reason: "\(range.rawValue) does not support recorder statistics"))
        }
        let response = await sendWebSocketCommandEnvelope(
            on: task,
            command: HAWebSocketRecorderStatisticsCommand(
                id: 1,
                statisticID: entityID.rawValue,
                period: period,
                startTime: Self.historyDateFormatter.string(from: start),
                endTime: Self.historyDateFormatter.string(from: end)
            ),
            expectedID: 1,
            commandName: "recorder/statistics_during_period"
        )
        switch response {
        case let .success(envelope):
            guard let statistics = envelope.resultStatistics else {
                return .failure(.invalidPayload(path: "/api/websocket", reason: "missing recorder statistics result"))
            }
            let samples = (statistics[entityID.rawValue] ?? [])
                .compactMap(\.sample)
                .sorted { $0.timestamp < $1.timestamp }
            return .success(HistorySeries(entityID: entityID, range: range, samples: samples))
        case let .failure(failure):
            return .failure(failure)
        }
    }

    private func sendWebSocketCommandEnvelope<T: Encodable>(
        on task: URLSessionWebSocketTask,
        command: T,
        expectedID: Int,
        commandName: String
    ) async -> HAClientResult<HAWebSocketEnvelopeDTO> {
        guard let message = encodeWebSocketMessage(command) else {
            return .failure(.invalidPayload(path: "/api/websocket", reason: "could not encode \(commandName) command"))
        }
        do {
            try await task.send(.string(message))
        } catch {
            return .failure(
                map(
                    transportError: error,
                    baseURL: task.currentRequest?.url ?? URL(fileURLWithPath: "/")
                )
            )
        }

        let response = await receiveWebSocketEnvelope(task: task, path: "/api/websocket")
        switch response {
        case let .success(envelope):
            guard envelope.type == "result" else {
                return .failure(.webSocketProtocol("expected result, received \(envelope.type)"))
            }
            guard envelope.id == expectedID else {
                return .failure(.webSocketProtocol("expected result id \(expectedID), received \(envelope.id.map(String.init) ?? "nil")"))
            }
            guard envelope.success == true else {
                return .failure(.webSocketCommand(id: envelope.id, code: envelope.error?.code, message: envelope.error?.message))
            }
            return .success(envelope)
        case let .failure(failure):
            return .failure(failure)
        }
    }

    private func receiveWebSocketEnvelope(task: URLSessionWebSocketTask, path: String) async -> HAClientResult<HAWebSocketEnvelopeDTO> {
        do {
            let message = try await task.receive()
            let data: Data
            switch message {
            case let .string(text):
                data = Data(text.utf8)
            case let .data(raw):
                data = raw
            @unknown default:
                return .failure(.invalidPayload(path: path, reason: "unknown WebSocket message"))
            }
            return decode(path: path, response: HARESTResponse(statusCode: 200, headers: [:], body: data), as: HAWebSocketEnvelopeDTO.self)
        } catch {
            return .failure(
                map(
                    transportError: error,
                    baseURL: task.currentRequest?.url ?? URL(fileURLWithPath: "/")
                )
            )
        }
    }

    private func encodeWebSocketMessage<T: Encodable>(_ message: T) -> String? {
        guard let data = try? JSONEncoder().encode(message) else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    private static var historyDateFormatter: ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter
    }
}

public enum PerchHAClient {
    public static let module = PerchHAModule(
        name: "PerchHAClient",
        responsibility: "Home Assistant REST and WebSocket transport."
    )
}

private struct HARESTCheckDTO: Decodable {
    let message: String
}

private struct HAOAuthTokenDTO: Decodable {
    let accessToken: String
    let refreshToken: String?
    let expiresIn: Int
    let tokenType: String

    private enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresIn = "expires_in"
        case tokenType = "token_type"
    }
}

private struct HAStateDTO: Decodable {
    let entityID: String
    let state: String
    let attributes: HAStateAttributesDTO?

    var entityState: EntityState {
        EntityState(
            id: EntityID(entityID),
            name: attributes?.friendlyName ?? entityID,
            state: state,
            unit: attributes?.unitOfMeasurement,
            currentPosition: attributes?.currentPosition
        )
    }

    private enum CodingKeys: String, CodingKey {
        case entityID = "entity_id"
        case state
        case attributes
    }
}

private struct HAStateAttributesDTO: Decodable {
    let friendlyName: String?
    let unitOfMeasurement: String?
    let currentPosition: Int?

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        friendlyName = try container.decodeIfPresent(String.self, forKey: .friendlyName)
        unitOfMeasurement = try container.decodeIfPresent(String.self, forKey: .unitOfMeasurement)
        currentPosition = Self.decodeCurrentPosition(from: container)
    }

    private enum CodingKeys: String, CodingKey {
        case friendlyName = "friendly_name"
        case unitOfMeasurement = "unit_of_measurement"
        case currentPosition = "current_position"
    }

    private static func decodeCurrentPosition(from container: KeyedDecodingContainer<CodingKeys>) -> Int? {
        if let value = try? container.decode(Int.self, forKey: .currentPosition) {
            return clamp(value)
        }
        if let value = try? container.decode(Double.self, forKey: .currentPosition), value.isFinite {
            return clamp(Int(value.rounded()))
        }
        if let rawValue = try? container.decode(String.self, forKey: .currentPosition),
           let value = Double(rawValue.trimmingCharacters(in: .whitespacesAndNewlines)),
           value.isFinite {
            return clamp(Int(value.rounded()))
        }
        return nil
    }

    private static func clamp(_ value: Int) -> Int {
        min(max(value, 0), 100)
    }
}

private struct HAHistoryStateDTO: Decodable {
    let entityID: String?
    let state: String
    let timestamp: Date

    var sample: HistorySample {
        return HistorySample(
            timestamp: timestamp,
            state: state,
            numericValue: Double(state)
        )
    }

    private enum CodingKeys: String, CodingKey {
        case entityID = "entity_id"
        case state
        case lastChanged = "last_changed"
        case lastUpdated = "last_updated"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        entityID = try container.decodeIfPresent(String.self, forKey: .entityID)
        state = try container.decode(String.self, forKey: .state)
        let lastChanged = try container.decodeHistoryDateIfPresent(forKey: .lastChanged)
        let lastUpdated = try container.decodeHistoryDateIfPresent(forKey: .lastUpdated)
        guard let timestamp = lastChanged ?? lastUpdated else {
            throw DecodingError.dataCorruptedError(
                forKey: .lastChanged,
                in: container,
                debugDescription: "history state is missing last_changed and last_updated"
            )
        }
        self.timestamp = timestamp
    }
}

private struct HAAreaDTO: Decodable {
    let areaID: String
    let name: String

    var area: Area {
        Area(id: AreaID(areaID), name: name)
    }

    private enum CodingKeys: String, CodingKey {
        case areaID = "area_id"
        case name
    }
}

private struct HADeviceDTO: Decodable {
    let id: String
    let name: String?
    let nameByUser: String?
    let areaID: String?

    var device: Device {
        Device(
            id: DeviceID(id),
            name: nonEmpty(nameByUser) ?? nonEmpty(name),
            areaID: nonEmpty(areaID).map { AreaID($0) }
        )
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case nameByUser = "name_by_user"
        case areaID = "area_id"
    }
}

private struct HAEntityRegistryEntryDTO: Decodable {
    let entityID: String
    let name: String?
    let originalName: String?
    let areaID: String?
    let deviceID: String?

    var entry: EntityRegistryEntry {
        EntityRegistryEntry(
            id: EntityID(entityID),
            name: nonEmpty(name) ?? nonEmpty(originalName),
            areaID: nonEmpty(areaID).map { AreaID($0) },
            deviceID: nonEmpty(deviceID).map { DeviceID($0) }
        )
    }

    private enum CodingKeys: String, CodingKey {
        case entityID = "entity_id"
        case name
        case originalName = "original_name"
        case areaID = "area_id"
        case deviceID = "device_id"
    }
}

private struct HAEntityRegistryDisplayListDTO: Decodable {
    let entities: [HAEntityRegistryDisplayEntryDTO]
}

private struct HAEntityRegistryDisplayEntryDTO: Decodable {
    let entityID: String
    let name: String?
    let areaID: String?
    let deviceID: String?

    var entry: EntityRegistryEntry {
        EntityRegistryEntry(
            id: EntityID(entityID),
            name: nonEmpty(name),
            areaID: nonEmpty(areaID).map { AreaID($0) },
            deviceID: nonEmpty(deviceID).map { DeviceID($0) }
        )
    }

    private enum CodingKeys: String, CodingKey {
        case entityID = "ei"
        case name = "en"
        case areaID = "ai"
        case deviceID = "di"
    }
}

private func nonEmpty(_ value: String?) -> String? {
    guard let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
        return nil
    }
    return value
}

private struct HAWebSocketAuthCommand: Encodable {
    let type = "auth"
    let accessToken: String

    private enum CodingKeys: String, CodingKey {
        case type
        case accessToken = "access_token"
    }
}

private struct HAWebSocketCommand: Encodable {
    let id: Int
    let type: String
}

private struct HAWebSocketSubscribeEventsCommand: Encodable {
    let id: Int
    let type = "subscribe_events"
    let eventType: String

    private enum CodingKeys: String, CodingKey {
        case id
        case type
        case eventType = "event_type"
    }
}

private struct HAWebSocketSubscribeEntitiesCommand: Encodable {
    let id: Int
    let type = "subscribe_entities"
}

private struct HAWebSocketCallServiceCommand: Encodable {
    let id: Int
    let type = "call_service"
    let domain: String
    let service: String
    let target: [String: String]?
    let serviceData: [String: HAJSONValue]

    init(id: Int, call: HAServiceCall) {
        self.id = id
        self.domain = call.domain
        self.service = call.service
        self.target = call.targetEntityID.map { ["entity_id": $0.rawValue] }
        self.serviceData = call.serviceData
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case type
        case domain
        case service
        case target
        case serviceData = "service_data"
    }
}

private struct HAWebSocketRecorderStatisticsCommand: Encodable {
    let id: Int
    let type = "recorder/statistics_during_period"
    let statisticIDs: [String]
    let period: String
    let startTime: String
    let endTime: String
    let types: [String]

    init(id: Int, statisticID: String, period: String, startTime: String, endTime: String) {
        self.id = id
        self.statisticIDs = [statisticID]
        self.period = period
        self.startTime = startTime
        self.endTime = endTime
        self.types = ["mean", "state"]
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case type
        case statisticIDs = "statistic_ids"
        case period
        case startTime = "start_time"
        case endTime = "end_time"
        case types
    }
}

private struct HAWebSocketEnvelopeDTO: Decodable {
    let id: Int?
    let type: String
    let success: Bool?
    let haVersion: String?
    let message: String?
    let resultStates: [HAStateDTO]?
    let resultAreas: [HAAreaDTO]?
    let resultDevices: [HADeviceDTO]?
    let resultEntityRegistryEntries: [HAEntityRegistryEntryDTO]?
    let resultEntityRegistryDisplayList: HAEntityRegistryDisplayListDTO?
    let resultStatistics: [String: [HARecorderStatisticDTO]]?
    let resultServices: [String: [String: HAServiceMetadataDTO]]?
    let serviceCallResult: HAServiceCallResultDTO?
    let error: HAWebSocketErrorDTO?
    let event: HAWebSocketEventDTO?

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(Int.self, forKey: .id)
        type = try container.decode(String.self, forKey: .type)
        success = try container.decodeIfPresent(Bool.self, forKey: .success)
        haVersion = try container.decodeIfPresent(String.self, forKey: .haVersion)
        message = try container.decodeIfPresent(String.self, forKey: .message)
        error = try container.decodeIfPresent(HAWebSocketErrorDTO.self, forKey: .error)
        event = try container.decodeIfPresent(HAWebSocketEventDTO.self, forKey: .event)
        resultStates = try? container.decodeIfPresent([HAStateDTO].self, forKey: .result)
        resultAreas = try? container.decodeIfPresent([HAAreaDTO].self, forKey: .result)
        resultDevices = try? container.decodeIfPresent([HADeviceDTO].self, forKey: .result)
        resultEntityRegistryEntries = try? container.decodeIfPresent([HAEntityRegistryEntryDTO].self, forKey: .result)
        resultEntityRegistryDisplayList = try? container.decodeIfPresent(HAEntityRegistryDisplayListDTO.self, forKey: .result)
        resultStatistics = try? container.decodeIfPresent([String: [HARecorderStatisticDTO]].self, forKey: .result)
        resultServices = try? container.decodeIfPresent([String: [String: HAServiceMetadataDTO]].self, forKey: .result)
        serviceCallResult = try? container.decodeIfPresent(HAServiceCallResultDTO.self, forKey: .result)
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case type
        case success
        case haVersion = "ha_version"
        case message
        case result
        case error
        case event
    }
}

private struct HARecorderStatisticDTO: Decodable {
    let start: Double
    let mean: Double?
    let state: Double?

    var sample: HistorySample? {
        guard let value = mean ?? state else {
            return nil
        }
        return HistorySample(
            timestamp: Date(timeIntervalSince1970: start / 1000),
            state: String(value),
            numericValue: value
        )
    }
}

private struct HAWebSocketErrorDTO: Decodable {
    let code: String?
    let message: String?
}

private struct HAWebSocketEventDTO: Decodable {
    let eventType: String?
    let data: HAWebSocketEventDataDTO?
    let entityAdditions: [String: HACompactEntityStateDTO]?
    let entityChanges: [String: HACompactEntityDiffDTO]?
    let entityRemovals: [String]?

    func firstEntityUpdate(updating knownStates: inout [EntityID: EntityState]) -> EntityState? {
        for removedEntityID in entityRemovals ?? [] {
            knownStates.removeValue(forKey: EntityID(removedEntityID))
        }
        if let addition = entityAdditions?.sorted(by: { $0.key < $1.key }).first {
            let id = EntityID(addition.key)
            let state = addition.value.entityState(id: id)
            knownStates[id] = state
            return state
        }
        guard let entityChanges else {
            return nil
        }
        for change in entityChanges.sorted(by: { $0.key < $1.key }) {
            let id = EntityID(change.key)
            guard let previous = knownStates[id],
                  let updated = change.value.updatedState(id: id, previous: previous)
            else {
                continue
            }
            knownStates[id] = updated
            return updated
        }
        return nil
    }

    private enum CodingKeys: String, CodingKey {
        case eventType = "event_type"
        case data
        case entityAdditions = "a"
        case entityChanges = "c"
        case entityRemovals = "r"
    }
}

private struct HAWebSocketEventDataDTO: Decodable {
    let newState: HAStateDTO?

    private enum CodingKeys: String, CodingKey {
        case newState = "new_state"
    }
}

private struct HACompactEntityStateDTO: Decodable {
    let state: String?
    let attributes: HAStateAttributesDTO?

    func entityState(id: EntityID) -> EntityState {
        EntityState(
            id: id,
            name: attributes?.friendlyName ?? id.rawValue,
            state: state ?? "",
            unit: attributes?.unitOfMeasurement,
            currentPosition: attributes?.currentPosition
        )
    }

    func updatedState(id: EntityID, previous: EntityState) -> EntityState {
        EntityState(
            id: id,
            name: attributes?.friendlyName ?? previous.name,
            state: state ?? previous.state,
            unit: attributes?.unitOfMeasurement ?? previous.unit,
            currentPosition: attributes?.currentPosition ?? previous.currentPosition
        )
    }

    private enum CodingKeys: String, CodingKey {
        case state = "s"
        case attributes = "a"
    }
}

private struct HACompactEntityDiffDTO: Decodable {
    let additions: HACompactEntityStateDTO?
    let removals: HACompactEntityRemoveDTO?

    func updatedState(id: EntityID, previous: EntityState) -> EntityState? {
        guard additions != nil || removals != nil else {
            return nil
        }
        var updated = additions?.updatedState(id: id, previous: previous) ?? previous
        if removals?.attributes.contains("friendly_name") == true {
            updated = EntityState(
                id: id,
                name: id.rawValue,
                state: updated.state,
                unit: updated.unit,
                currentPosition: updated.currentPosition
            )
        }
        if removals?.attributes.contains("unit_of_measurement") == true {
            updated = EntityState(
                id: id,
                name: updated.name,
                state: updated.state,
                unit: nil,
                currentPosition: updated.currentPosition
            )
        }
        if removals?.attributes.contains("current_position") == true {
            updated = EntityState(id: id, name: updated.name, state: updated.state, unit: updated.unit)
        }
        return updated
    }

    private enum CodingKeys: String, CodingKey {
        case additions = "+"
        case removals = "-"
    }
}

private struct HACompactEntityRemoveDTO: Decodable {
    let attributes: [String]

    private enum CodingKeys: String, CodingKey {
        case attributes = "a"
    }
}

private struct HAServiceMetadataDTO: Decodable {
    let name: String?
    let description: String?
    let fields: [String: HAServiceFieldMetadataDTO]?

    func metadata(domain: String, service: String) -> HAServiceMetadata {
        HAServiceMetadata(
            domain: domain,
            service: service,
            name: nonEmpty(name),
            description: nonEmpty(description),
            fields: (fields ?? [:]).keys.sorted().map { key in
                fields?[key]?.metadata(key: key)
                    ?? HAServiceFieldMetadata(key: key, name: nil, description: nil, required: false, example: nil, selector: nil)
            }
        )
    }
}

private struct HAServiceFieldMetadataDTO: Decodable {
    let name: String?
    let description: String?
    let required: Bool?
    let example: HAJSONValue?
    let selector: HAJSONValue?

    func metadata(key: String) -> HAServiceFieldMetadata {
        HAServiceFieldMetadata(
            key: key,
            name: nonEmpty(name),
            description: nonEmpty(description),
            required: required ?? false,
            example: example,
            selector: selector
        )
    }
}

private struct HAServiceCallResultDTO: Decodable {
    let context: HAContextDTO?
}

private struct HAContextDTO: Decodable {
    let id: String?
}

private extension HAClientFailure {
    var isUnavailableCommand: Bool {
        switch self {
        case let .webSocketCommand(_, code, _):
            code == "unknown_command" || code == "unsupported_command"
        case .authentication, .unreachable, .tlsRejected, .invalidURL, .invalidResponse, .invalidPayload, .httpStatus, .webSocketProtocol, .transport:
            false
        }
    }

    var shouldRetryLiveSubscription: Bool {
        switch self {
        case .unreachable, .transport:
            true
        case .authentication, .tlsRejected, .invalidURL, .invalidResponse, .invalidPayload, .httpStatus, .webSocketProtocol, .webSocketCommand:
            false
        }
    }

    var shouldFallbackFromRecorderStatisticsToREST: Bool {
        switch self {
        case .unreachable, .tlsRejected, .transport:
            true
        case .webSocketCommand:
            isUnavailableCommand
        case .authentication, .invalidURL, .invalidResponse, .invalidPayload, .httpStatus, .webSocketProtocol:
            false
        }
    }
}

private extension HistoryRange {
    var historyDuration: TimeInterval {
        switch self {
        case .hour:
            60 * 60
        case .day:
            24 * 60 * 60
        case .week:
            7 * 24 * 60 * 60
        case .month:
            30 * 24 * 60 * 60
        }
    }

    var prefersRecorderStatistics: Bool {
        switch self {
        case .week, .month:
            true
        case .hour, .day:
            false
        }
    }

    var recorderStatisticsPeriod: String? {
        switch self {
        case .week:
            "hour"
        case .month:
            "day"
        case .hour, .day:
            nil
        }
    }
}

private extension KeyedDecodingContainer {
    func decodeHistoryDateIfPresent(forKey key: Key) throws -> Date? {
        guard let value = try decodeIfPresent(String.self, forKey: key) else {
            return nil
        }
        return Self.historyDateFormatterWithFractionalSeconds.date(from: value)
            ?? Self.historyDateFormatter.date(from: value)
    }

    private static var historyDateFormatter: ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }

    private static var historyDateFormatterWithFractionalSeconds: ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }
}

private enum HAWebSocketAuthenticationResult {
    case success(AuthenticatedWebSocket)
    case failure(HAClientFailure)
}

private struct AuthenticatedWebSocket: @unchecked Sendable {
    let task: URLSessionWebSocketTask
    let session: URLSession
    let shouldInvalidateSession: Bool
    let check: HAWebSocketCheck

    func close(code: URLSessionWebSocketTask.CloseCode) {
        task.cancel(with: code, reason: nil)
        if shouldInvalidateSession {
            session.finishTasksAndInvalidate()
        }
    }
}

private struct HAWebSocketTaskContext: @unchecked Sendable {
    let task: URLSessionWebSocketTask
    let session: URLSession
    let shouldInvalidateSession: Bool

    func invalidate() {
        if shouldInvalidateSession {
            session.finishTasksAndInvalidate()
        }
    }
}

private extension URL {
    func homeAssistantURL(path: String, queryItems: [URLQueryItem] = []) throws -> URL {
        guard path.hasPrefix("/") else {
            throw HAClientFailure.invalidURL(path: path)
        }
        var components = URLComponents(url: self, resolvingAgainstBaseURL: false)
        components?.path = appendingHomeAssistantPath(path)
        if !queryItems.isEmpty {
            components?.queryItems = queryItems
        }
        guard let url = components?.url else {
            throw HAClientFailure.invalidURL(path: path)
        }
        return url
    }

    func homeAssistantWebSocketURL(path: String) throws -> URL {
        guard path.hasPrefix("/") else {
            throw HAClientFailure.invalidURL(path: path)
        }
        var components = URLComponents(url: self, resolvingAgainstBaseURL: false)
        switch components?.scheme?.lowercased() {
        case "http":
            components?.scheme = "ws"
        case "https":
            components?.scheme = "wss"
        default:
            throw HAClientFailure.invalidURL(path: path)
        }
        components?.path = appendingHomeAssistantPath(path)
        guard let url = components?.url else {
            throw HAClientFailure.invalidURL(path: path)
        }
        return url
    }

    private func appendingHomeAssistantPath(_ path: String) -> String {
        let basePath = self.path
        let normalizedBase = basePath == "/" ? "" : basePath.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let prefix = normalizedBase.isEmpty ? "" : "/\(normalizedBase)"
        return "\(prefix)\(path)"
    }
}
