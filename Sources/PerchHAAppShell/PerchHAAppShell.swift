import AppKit
import AuthenticationServices
import PerchHACore
import PerchHAClient
import PerchHAPersistence
import PerchHAUI
import Security
import SwiftUI

private enum AppShellLayout {
    static let panelContentSize = NSSize(width: 360, height: 420)
    static let settingsMinContentSize = NSSize(width: 520, height: 560)
}

final class PerchHAStatusPanel: NSPanel {
    override var canBecomeKey: Bool {
        true
    }

    override var canBecomeMain: Bool {
        true
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard event.type == .keyDown,
              event.modifierFlags.intersection(.deviceIndependentFlagsMask).contains(.command),
              let characters = event.charactersIgnoringModifiers?.lowercased()
        else {
            return super.performKeyEquivalent(with: event)
        }

        let action: Selector?
        switch characters {
        case "x":
            action = #selector(NSText.cut(_:))
        case "c":
            action = #selector(NSText.copy(_:))
        case "v":
            action = #selector(NSText.paste(_:))
        case "a":
            action = #selector(NSText.selectAll(_:))
        case "z":
            action = event.modifierFlags.contains(.shift)
                ? Selector(("redo:"))
                : Selector(("undo:"))
        default:
            action = nil
        }

        if let action {
            // Route to this panel's own first responder (the focused field's
            // field editor) so editing shortcuts work whether or not the panel
            // is the application's key window; fall back to the responder chain.
            if let firstResponder, NSApp.sendAction(action, to: firstResponder, from: self) {
                return true
            }
            if NSApp.sendAction(action, to: nil, from: self) {
                return true
            }
        }
        return super.performKeyEquivalent(with: event)
    }
}

/// An observable description of a single live menu-bar status item.
public struct PerchHAMenuBarStatusItemSnapshot: Equatable, Sendable {
    public let title: String?
    public let accessibilityLabel: String?
    public let hasImage: Bool
    public let imageWidth: Int?
    public let imageHeight: Int?
    public let imageIsTemplate: Bool?
    public let hasAction: Bool
    public let targetIsApplication: Bool

    public init(
        title: String?,
        accessibilityLabel: String?,
        hasImage: Bool,
        imageWidth: Int?,
        imageHeight: Int?,
        imageIsTemplate: Bool?,
        hasAction: Bool,
        targetIsApplication: Bool
    ) {
        self.title = title
        self.accessibilityLabel = accessibilityLabel
        self.hasImage = hasImage
        self.imageWidth = imageWidth
        self.imageHeight = imageHeight
        self.imageIsTemplate = imageIsTemplate
        self.hasAction = hasAction
        self.targetIsApplication = targetIsApplication
    }
}

public struct PerchHAApplicationSnapshot: Equatable, Sendable {
    public let statusItemTitle: String?
    public let statusItemAccessibilityLabel: String?
    public let statusItemHasImage: Bool
    public let statusItemImageWidth: Int?
    public let statusItemImageHeight: Int?
    public let statusItemImageIsTemplate: Bool?
    public let statusItemTargetIsApplication: Bool
    public let statusItemHasAction: Bool
    /// One entry per live menu-bar status item, in promoted order. Always holds
    /// at least one entry (the fallback fish-logo item when nothing is promoted).
    public let menuBarItems: [PerchHAMenuBarStatusItemSnapshot]
    public let hasPanel: Bool
    public let hasPanelModel: Bool
    public let panelCanBecomeKey: Bool
    public let panelCanBecomeMain: Bool
    public let panelIsFloating: Bool
    public let panelHidesOnDeactivate: Bool
    public let panelContentWidth: Int?
    public let panelContentHeight: Int?
    public let selectedEntityIDs: [EntityID]
    public let menuBarEntityIDs: [EntityID]
    public let menuBarItemConfigurations: [MenuBarItemConfiguration]
    public let menuBarDisplayConfiguration: MenuBarDisplayConfiguration
    public let customActionConfiguration: CustomActionConfiguration
    public let roomOrder: [RoomID]
    public let entityOrder: [EntityID]
    public let isEntitySelectionExplicit: Bool
    public let displayPersistenceFailureDescription: String?
    public let customActionPersistenceFailureDescription: String?
    public let serviceMetadata: [HAServiceMetadata]
    public let serviceMetadataFailureDescription: String?
    public let configurationPersistenceState: PerchHAConfigurationPersistenceState
    public let historyState: PerchHAHistoryPanelState
    public let historyPresentationEntityID: EntityID?
    public let controlActionState: PerchHAControlActionState
    public let lastExternalURLEvent: PerchHAExternalURLEvent?
    public let connectionState: ConnectionState
    public let connectionForm: PerchHAConnectionForm
    public let hasTokenInput: Bool
}

public enum PerchHAConfigurationPersistenceState: Equatable, Sendable {
    case ready
    case unavailable
    case loadFailed(String)
    case saveFailed(String)
}

public struct PerchHAExternalURLEvent: Equatable, Sendable {
    public let scheme: String?
    public let host: String?
    public let port: Int?
    public let path: String
    public let hasQuery: Bool
    public let hasFragment: Bool
    public let disposition: PerchHAExternalURLDisposition
}

public enum PerchHAExternalURLDisposition: Equatable, Sendable {
    case acceptedOAuthCallback
    case rejectedOAuthNotConfigured
    case rejectedUnsupportedScheme
    case rejectedRedirectMismatch
}

public protocol PerchHAAuthSessionStorage: Sendable {
    @discardableResult func save(_ session: PerchHAAuthSession) throws -> PerchHAAuthSessionWriteResult
    func load() throws -> PerchHAAuthSession
    func loadAccessToken() throws -> String
    @discardableResult func saveAccessToken(_ accessToken: String) throws -> SecretWriteResult
    @discardableResult func replaceAccessToken(_ accessToken: String) throws -> SecretWriteResult
    @discardableResult func clear() throws -> PerchHAAuthSessionClearResult
}

extension PerchHAAuthSessionStore: PerchHAAuthSessionStorage {}

public protocol PerchHARefreshingHomeAssistantClient: Sendable {
    func discovery(_ input: HAConnectionInput) async -> HAClientResult<DiscoverySnapshot>
    func history(_ input: HAConnectionInput, entityID: EntityID, range: HistoryRange, end: Date) async -> HAClientResult<HistorySeries>
    func services(_ input: HAConnectionInput) async -> HAClientResult<[HAServiceMetadata]>
    func callService(_ input: HAConnectionInput, call: HAServiceCall) async -> HAClientResult<HAServiceCallResult>
    func refreshAccessToken(baseURL: URL, refreshToken: String, clientID: String) async -> HAClientResult<HAOAuthToken>
}

public protocol PerchHAServerTrustRefreshingHomeAssistantClient: PerchHARefreshingHomeAssistantClient {
    func refreshAccessToken(
        baseURL: URL,
        refreshToken: String,
        clientID: String,
        serverTrustPolicy: HAServerTrustPolicy
    ) async -> HAClientResult<HAOAuthToken>
}

extension HomeAssistantClient: PerchHARefreshingHomeAssistantClient {}
extension HomeAssistantClient: PerchHAServerTrustRefreshingHomeAssistantClient {}

public struct PerchHAAuthorizedHomeAssistantGateway: Sendable {
    private let client: any PerchHARefreshingHomeAssistantClient
    private let authSessionStore: any PerchHAAuthSessionStorage

    public init(
        client: any PerchHARefreshingHomeAssistantClient = HomeAssistantClient(),
        authSessionStore: any PerchHAAuthSessionStorage = PerchHAAuthSessionStore()
    ) {
        self.client = client
        self.authSessionStore = authSessionStore
    }

    public func connect(form: PerchHAConnectionForm) async -> PerchHAConnectionAttemptResult {
        guard let primaryURL = form.primaryURL() else {
            return .failure(.protocolError("invalid Home Assistant URL"))
        }

        let result = await perform(form: form, primaryURL: primaryURL) { input in
            await client.discovery(input)
        }
        switch result {
        case let .success(snapshot):
            return .success(rooms: RoomResolver().resolve(snapshot: snapshot))
        case let .failure(failure):
            return .failure(failure.connectionFailure)
        }
    }

    public func history(
        form: PerchHAConnectionForm,
        entityID: EntityID,
        range: HistoryRange
    ) async -> PerchHAHistoryProviderResult {
        guard let primaryURL = form.primaryURL() else {
            return .unavailable("invalid Home Assistant URL")
        }

        let result = await perform(form: form, primaryURL: primaryURL) { input in
            await client.history(input, entityID: entityID, range: range, end: Date())
        }
        switch result {
        case let .success(series):
            return .success(series)
        case let .failure(failure):
            return .unavailable(failure.connectionFailure.historyDescription)
        }
    }

    public func services(form: PerchHAConnectionForm) async -> PerchHAServiceMetadataProviderResult {
        guard let primaryURL = form.primaryURL() else {
            return .unavailable("invalid Home Assistant URL")
        }

        let result = await perform(form: form, primaryURL: primaryURL) { input in
            await client.services(input)
        }
        switch result {
        case let .success(metadata):
            return .success(metadata)
        case let .failure(failure):
            return .unavailable(failure.connectionFailure.historyDescription)
        }
    }

    public func action(form: PerchHAConnectionForm, action: ActionSpec) async -> PerchHAActionResult {
        guard let primaryURL = form.primaryURL() else {
            return .failed("invalid Home Assistant URL")
        }

        let result = await perform(form: form, primaryURL: primaryURL) { input in
            await client.callService(input, call: action)
        }
        switch result {
        case .success:
            return .success
        case let .failure(failure):
            return .failed(failure.connectionFailure.actionDescription)
        }
    }

    private func perform<Value: Sendable>(
        form: PerchHAConnectionForm,
        primaryURL: URL,
        operation: @Sendable (HAConnectionInput) async -> HAClientResult<Value>
    ) async -> HAClientResult<Value> {
        let resolved = resolveInput(form: form, primaryURL: primaryURL)
        switch resolved {
        case let .failure(failure):
            return .failure(failure)
        case let .success(authorizedInput):
            let primaryInput = authorizedInput.input(for: primaryURL)
            let primary = await operation(primaryInput)
            if case let .failure(failure) = primary,
               shouldRetryOnFallback(failure),
               let fallbackURL = form.fallbackURL() {
                let fallbackInput = authorizedInput.input(for: fallbackURL)
                return await resolveAuthenticationFailure(
                    await operation(fallbackInput),
                    authorizedInput: authorizedInput,
                    attemptedInput: fallbackInput,
                    refreshBaseURL: fallbackURL,
                    operation: operation
                )
            }
            return await resolveAuthenticationFailure(
                primary,
                authorizedInput: authorizedInput,
                attemptedInput: primaryInput,
                refreshBaseURL: primaryURL,
                operation: operation
            )
        }
    }

    private func resolveInput(form: PerchHAConnectionForm, primaryURL: URL) -> HAClientResult<PerchHAAuthorizedInput> {
        let endpoint = HAEndpoint(primaryURL: primaryURL, fallbackURL: form.fallbackURL())
        let serverTrustPolicy = HAServerTrustPolicy(trustsAllHosts: true)
        if !form.trimmedToken.isEmpty {
            return .success(
                PerchHAAuthorizedInput(
                    input: HAConnectionInput(
                        endpoint: endpoint,
                        token: form.trimmedToken,
                        serverTrustPolicy: serverTrustPolicy
                    ),
                    session: nil
                )
            )
        }
        guard form.usesStoredAuthSession else {
            return .failure(.authentication)
        }
        do {
            let accessToken = try authSessionStore.loadAccessToken()
            let session = try? authSessionStore.load()
            return .success(
                PerchHAAuthorizedInput(
                    input: HAConnectionInput(
                        endpoint: endpoint,
                        token: accessToken,
                        serverTrustPolicy: serverTrustPolicy
                    ),
                    session: session
                )
            )
        } catch SecretStoreError.notFound(_) {
            return .failure(.authentication)
        } catch {
            return .failure(.transport(String(describing: error)))
        }
    }

    private func resolveAuthenticationFailure<Value: Sendable>(
        _ result: HAClientResult<Value>,
        authorizedInput: PerchHAAuthorizedInput,
        attemptedInput: HAConnectionInput,
        refreshBaseURL: URL,
        operation: @Sendable (HAConnectionInput) async -> HAClientResult<Value>
    ) async -> HAClientResult<Value> {
        guard case .failure(.authentication) = result, let session = authorizedInput.session else {
            return result
        }
        guard let clientID = session.clientID else {
            _ = try? authSessionStore.clear()
            return .failure(.authentication)
        }
        let refresh = await refreshAccessToken(
            baseURL: refreshBaseURL,
            refreshToken: session.refreshToken,
            clientID: clientID,
            serverTrustPolicy: attemptedInput.serverTrustPolicy
        )
        switch refresh {
        case let .success(token):
            do {
                try persistRefreshedToken(token, previousSession: session)
            } catch {
                return .failure(.transport(String(describing: error)))
            }
            let retryInput = HAConnectionInput(
                endpoint: attemptedInput.endpoint,
                token: token.accessToken,
                serverTrustPolicy: attemptedInput.serverTrustPolicy
            )
            return await operation(retryInput)
        case .failure:
            _ = try? authSessionStore.clear()
            return .failure(.authentication)
        }
    }

    private func refreshAccessToken(
        baseURL: URL,
        refreshToken: String,
        clientID: String,
        serverTrustPolicy: HAServerTrustPolicy
    ) async -> HAClientResult<HAOAuthToken> {
        if let trustPolicyClient = client as? any PerchHAServerTrustRefreshingHomeAssistantClient {
            return await trustPolicyClient.refreshAccessToken(
                baseURL: baseURL,
                refreshToken: refreshToken,
                clientID: clientID,
                serverTrustPolicy: serverTrustPolicy
            )
        }
        return await client.refreshAccessToken(baseURL: baseURL, refreshToken: refreshToken, clientID: clientID)
    }

    private func shouldRetryOnFallback(_ failure: HAClientFailure) -> Bool {
        switch failure {
        case .unreachable, .tlsRejected, .transport:
            true
        case .authentication, .invalidURL, .invalidResponse, .invalidPayload, .httpStatus, .webSocketProtocol, .webSocketCommand:
            false
        }
    }

    private func persistRefreshedToken(_ token: HAOAuthToken, previousSession: PerchHAAuthSession) throws {
        if let refreshToken = token.refreshToken {
            try authSessionStore.save(
                PerchHAAuthSession(
                    accessToken: token.accessToken,
                    refreshToken: refreshToken,
                    clientID: previousSession.clientID
                )
            )
            return
        }
        try authSessionStore.replaceAccessToken(token.accessToken)
    }
}

private struct PerchHAAuthorizedInput: Sendable {
    let input: HAConnectionInput
    let session: PerchHAAuthSession?

    func input(for baseURL: URL) -> HAConnectionInput {
        HAConnectionInput(
            endpoint: HAEndpoint(primaryURL: baseURL, fallbackURL: nil),
            token: input.token,
            serverTrustPolicy: input.serverTrustPolicy
        )
    }
}

public struct PerchHAOAuthApplicationConfiguration: Equatable, Sendable {
    public static let clientIDEnvironmentKey = "PERCHHA_OAUTH_CLIENT_ID"
    public static let redirectURIEnvironmentKey = "PERCHHA_OAUTH_REDIRECT_URI"
    public static let environmentFileEnvironmentKey = "PERCHHA_ENV_FILE"
    public static let defaultEnvironmentFilePath = ".env.local"

    public let clientID: String
    public let redirectURI: String
    public let callbackURLScheme: String

    public init(clientID: String, redirectURI: String) throws {
        let normalizedClientID = clientID.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedRedirectURI = redirectURI.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedClientID.isEmpty else {
            throw PerchHAOAuthSignInFailure.configuration("OAuth client ID is not configured")
        }
        guard let clientIDURL = URL(string: normalizedClientID),
              ["http", "https"].contains(clientIDURL.scheme?.lowercased() ?? ""),
              clientIDURL.host?.isEmpty == false
        else {
            throw PerchHAOAuthSignInFailure.configuration("OAuth client ID must be an application website URL")
        }
        guard let redirectURL = URL(string: normalizedRedirectURI),
              let scheme = redirectURL.scheme,
              !scheme.isEmpty
        else {
            throw PerchHAOAuthSignInFailure.configuration("OAuth redirect URI is invalid")
        }

        self.clientID = normalizedClientID
        self.redirectURI = normalizedRedirectURI
        self.callbackURLScheme = scheme
    }

    public func acceptsCallbackURL(_ callbackURL: URL) -> Bool {
        guard let expectedRedirectComponents = URLComponents(string: redirectURI),
              let callbackComponents = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false)
        else {
            return false
        }
        return callbackComponents.scheme?.caseInsensitiveCompare(expectedRedirectComponents.scheme ?? "") == .orderedSame
            && normalizedHost(callbackComponents.host) == normalizedHost(expectedRedirectComponents.host)
            && callbackComponents.port == expectedRedirectComponents.port
            && callbackComponents.path == expectedRedirectComponents.path
            && callbackComponents.user == expectedRedirectComponents.user
            && callbackComponents.password == expectedRedirectComponents.password
    }

    public static func fromEnvironment(_ environment: [String: String] = ProcessInfo.processInfo.environment) throws -> PerchHAOAuthApplicationConfiguration? {
        let environmentClientID = environmentValue(for: clientIDEnvironmentKey, environment: environment)
        let environmentRedirectURI = environmentValue(for: redirectURIEnvironmentKey, environment: environment)
        if environmentClientID != nil, environmentRedirectURI != nil {
            return try PerchHAOAuthApplicationConfiguration(
                clientID: environmentClientID ?? "",
                redirectURI: environmentRedirectURI ?? ""
            )
        }

        let fileValues = try environmentFileValues(environment: environment)
        let clientID = environmentClientID ?? nonBlank(fileValues[clientIDEnvironmentKey])
        let redirectURI = environmentRedirectURI ?? nonBlank(fileValues[redirectURIEnvironmentKey])
        guard clientID != nil || redirectURI != nil else {
            return nil
        }
        return try PerchHAOAuthApplicationConfiguration(
            clientID: clientID ?? "",
            redirectURI: redirectURI ?? ""
        )
    }

    public static func parseEnvironmentFile(_ contents: String) throws -> [String: String] {
        var values: [String: String] = [:]
        for (index, rawLine) in contents.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("#") {
                continue
            }
            guard let separator = line.firstIndex(of: "=") else {
                throw PerchHAOAuthEnvironmentFileError.invalidLine(index + 1)
            }
            let key = String(line[..<separator]).trimmingCharacters(in: .whitespaces)
            let value = String(line[line.index(after: separator)...]).trimmingCharacters(in: .whitespaces)
            values[key] = unquote(value)
        }
        return values
    }

    private static func environmentFileValues(environment: [String: String]) throws -> [String: String] {
        let path = nonBlank(environment[environmentFileEnvironmentKey]) ?? defaultEnvironmentFilePath
        let explicitPath = nonBlank(environment[environmentFileEnvironmentKey]) != nil
        guard FileManager.default.fileExists(atPath: path) else {
            if explicitPath {
                throw PerchHAOAuthEnvironmentFileError.missingFile(path)
            }
            return [:]
        }
        do {
            let contents = try String(contentsOfFile: path, encoding: .utf8)
            return try parseEnvironmentFile(contents)
        } catch let error as PerchHAOAuthEnvironmentFileError {
            throw error
        } catch {
            throw PerchHAOAuthEnvironmentFileError.unreadableFile(path)
        }
    }

    private static func environmentValue(
        for key: String,
        environment: [String: String]
    ) -> String? {
        if let environmentValue = environment[key] {
            return environmentValue.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return nil
    }

    private static func nonBlank(_ value: String?) -> String? {
        guard let value else {
            return nil
        }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
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

    private func normalizedHost(_ host: String?) -> String? {
        host?.lowercased()
    }
}

public enum PerchHAOAuthEnvironmentFileError: Error, Equatable, CustomStringConvertible, Sendable {
    case missingFile(String)
    case invalidLine(Int)
    case unreadableFile(String)

    public var description: String {
        switch self {
        case let .missingFile(path):
            "missing OAuth environment file: \(path)"
        case let .invalidLine(line):
            "invalid .env line \(line)"
        case let .unreadableFile(path):
            "unreadable OAuth environment file: \(path)"
        }
    }
}

public enum PerchHAOAuthPresentationResult: Equatable, Sendable {
    case callback(URL)
    case cancelled
    case failed(String)
}

public protocol PerchHAOAuthAuthorizationPresenter: Sendable {
    @MainActor func callbackURL(
        authorizationURL: URL,
        callbackURLScheme: String
    ) async -> PerchHAOAuthPresentationResult
}

public enum PerchHAOAuthSignInFailure: Error, Equatable, CustomStringConvertible, Sendable {
    case configuration(String)
    case authorizationURL(String)
    case presentation(String)
    case cancelled
    case callback(String)
    case exchange(String)
    case storage(String)

    public var description: String {
        switch self {
        case let .configuration(message):
            message
        case let .authorizationURL(message):
            message
        case let .presentation(message):
            message
        case .cancelled:
            "sign-in was cancelled"
        case let .callback(message):
            message
        case let .exchange(message):
            message
        case let .storage(message):
            message
        }
    }
}

public struct PerchHAOAuthSignInCoordinator: Sendable {
    private let configuration: PerchHAOAuthApplicationConfiguration?
    private let client: HomeAssistantClient
    private let authSessionStore: any PerchHAAuthSessionStorage
    private let presenter: any PerchHAOAuthAuthorizationPresenter
    private let stateGenerator: @Sendable () -> String

    @MainActor
    public init(
        configuration: PerchHAOAuthApplicationConfiguration?,
        client: HomeAssistantClient = HomeAssistantClient(),
        authSessionStore: any PerchHAAuthSessionStorage = PerchHAAuthSessionStore(),
        presenter: any PerchHAOAuthAuthorizationPresenter = PerchHAASWebAuthenticationSessionPresenter(),
        stateGenerator: @escaping @Sendable () -> String = PerchHAOAuthSignInCoordinator.secureState
    ) {
        self.configuration = configuration
        self.client = client
        self.authSessionStore = authSessionStore
        self.presenter = presenter
        self.stateGenerator = stateGenerator
    }

    @MainActor
    public func signIn(form: PerchHAConnectionForm) async -> PerchHAOAuthSignInResult {
        do {
            try await performSignIn(form: form)
            return .success
        } catch let failure as PerchHAOAuthSignInFailure {
            return .failed(failure.description)
        } catch {
            return .failed(String(describing: error))
        }
    }

    @MainActor
    private func performSignIn(form: PerchHAConnectionForm) async throws {
        guard let configuration else {
            throw PerchHAOAuthSignInFailure.configuration("OAuth sign-in is not configured")
        }
        guard let primaryURL = form.primaryURL() else {
            throw PerchHAOAuthSignInFailure.callback("invalid Home Assistant URL")
        }

        let state = stateGenerator()
        let authorization = client.authorizationURL(
            for: HAOAuthAuthorizationRequest(
                baseURL: primaryURL,
                clientID: configuration.clientID,
                redirectURI: configuration.redirectURI,
                state: state
            )
        )
        let authorizationURL: URL
        switch authorization {
        case let .success(url):
            authorizationURL = url
        case let .failure(failure):
            throw PerchHAOAuthSignInFailure.authorizationURL(failure.description)
        }

        let callbackResult = await presenter.callbackURL(
            authorizationURL: authorizationURL,
            callbackURLScheme: configuration.callbackURLScheme
        )
        let callbackURL: URL
        switch callbackResult {
        case let .callback(url):
            callbackURL = url
        case .cancelled:
            throw PerchHAOAuthSignInFailure.cancelled
        case let .failed(message):
            throw PerchHAOAuthSignInFailure.presentation(message)
        }

        let callback = try parseCallback(
            callbackURL,
            expectedState: state,
            expectedRedirectURI: configuration.redirectURI
        )
        let exchange = await client.exchangeAuthorizationCode(
            baseURL: primaryURL,
            code: callback.code,
            clientID: configuration.clientID,
            serverTrustPolicy: HAServerTrustPolicy(trustsAllHosts: true)
        )
        let token: HAOAuthToken
        switch exchange {
        case let .success(value):
            token = value
        case let .failure(failure):
            throw PerchHAOAuthSignInFailure.exchange(failure.description)
        }
        guard let refreshToken = token.refreshToken else {
            throw PerchHAOAuthSignInFailure.exchange("refresh_token is required")
        }

        do {
            try authSessionStore.save(
                PerchHAAuthSession(
                    accessToken: token.accessToken,
                    refreshToken: refreshToken,
                    clientID: configuration.clientID
                )
            )
        } catch {
            throw PerchHAOAuthSignInFailure.storage(String(describing: error))
        }
    }

    private func parseCallback(
        _ callbackURL: URL,
        expectedState: String,
        expectedRedirectURI: String
    ) throws -> PerchHAOAuthCallback {
        guard let expectedRedirectComponents = URLComponents(string: expectedRedirectURI),
              let expectedCallbackURLScheme = expectedRedirectComponents.scheme
        else {
            throw PerchHAOAuthSignInFailure.callback("invalid OAuth redirect URI")
        }
        guard callbackURL.scheme?.caseInsensitiveCompare(expectedCallbackURLScheme) == .orderedSame else {
            throw PerchHAOAuthSignInFailure.callback("OAuth callback scheme did not match")
        }
        guard configuration?.acceptsCallbackURL(callbackURL) == true else {
            throw PerchHAOAuthSignInFailure.callback("OAuth callback redirect URI did not match")
        }
        guard let components = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false) else {
            throw PerchHAOAuthSignInFailure.callback("invalid OAuth callback")
        }
        let values = Dictionary(grouping: components.queryItems ?? [], by: \.name)
            .compactMapValues { $0.last?.value }
        if let error = values["error"] {
            let description = values["error_description"].map { ": \($0)" } ?? ""
            throw PerchHAOAuthSignInFailure.callback("\(error)\(description)")
        }
        guard values["state"] == expectedState else {
            throw PerchHAOAuthSignInFailure.callback("OAuth state did not match")
        }
        guard let code = values["code"], !code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw PerchHAOAuthSignInFailure.callback("OAuth callback is missing code")
        }
        return PerchHAOAuthCallback(code: code)
    }

    public static func secureState() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        guard status == errSecSuccess else {
            return "\(UUID().uuidString)\(UUID().uuidString)"
        }
        return bytes.map { String(format: "%02x", $0) }.joined()
    }
}

private struct PerchHAOAuthCallback: Sendable {
    let code: String
}

@MainActor
public final class PerchHAASWebAuthenticationSessionPresenter: NSObject, PerchHAOAuthAuthorizationPresenter, ASWebAuthenticationPresentationContextProviding, @unchecked Sendable {
    private var activeSession: ASWebAuthenticationSession?

    public func callbackURL(
        authorizationURL: URL,
        callbackURLScheme: String
    ) async -> PerchHAOAuthPresentationResult {
        await withCheckedContinuation { continuation in
            let session = ASWebAuthenticationSession(
                url: authorizationURL,
                callbackURLScheme: callbackURLScheme
            ) { [weak self] callbackURL, error in
                Task { @MainActor in
                    self?.activeSession = nil
                }
                if let callbackURL {
                    continuation.resume(returning: .callback(callbackURL))
                    return
                }
                if let error = error as? ASWebAuthenticationSessionError,
                   error.code == .canceledLogin
                {
                    continuation.resume(returning: .cancelled)
                    return
                }
                continuation.resume(returning: .failed(error.map { String(describing: $0) } ?? "OAuth sign-in failed"))
            }
            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = false
            activeSession = session
            guard session.start() else {
                activeSession = nil
                continuation.resume(returning: .failed("OAuth sign-in could not be started"))
                return
            }
        }
    }

    public func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        NSApplication.shared.keyWindow ?? NSApplication.shared.windows.first ?? NSWindow()
    }
}

@MainActor
public final class PerchHAApplication: NSObject, NSApplicationDelegate {
    private var statusItems: [PerchHAStatusItemEntry] = []
    private var panel: NSPanel?
    private var settingsWindow: NSWindow?
    private var panelModel: PerchHAPanelModel?
    private var autoConnectTask: Task<Void, Never>?
    private let configStore: ConfigStore?
    private let authSessionStore: (any PerchHAAuthSessionStorage)?
    private let connector: PerchHAPanelModel.Connector
    private let historyProvider: PerchHAPanelModel.HistoryProvider
    private let serviceMetadataProvider: PerchHAPanelModel.ServiceMetadataProvider
    private let actionRunner: PerchHAPanelModel.ActionRunner
    private let oauthSignInRunner: PerchHAPanelModel.OAuthSignInRunner
    private let protectedActionValueStore: any ProtectedActionValueStore
    private let oauthApplicationConfiguration: PerchHAOAuthApplicationConfiguration?
    private let menuBarPresenter: PerchHAMenuBarPresenter
    private let gaugeImageRenderer: any PerchHAStatusItemGaugeImageRendering
    private let logoImageRenderer = PerchHAStatusItemLogoImageRenderer()
    private var statusItemLogoImageCache: NSImage?
    private var configuration = PerchHAConfiguration.empty
    private var configurationPersistenceState = PerchHAConfigurationPersistenceState.unavailable
    private var lastExternalURLEvent: PerchHAExternalURLEvent?

    public override convenience init() {
        self.init(configStore: nil)
    }

    public convenience init(configStore: ConfigStore?) {
        let authSessionStore = PerchHAAuthSessionStore()
        let gateway = PerchHAAuthorizedHomeAssistantGateway(authSessionStore: authSessionStore)
        let oauthSignInRunner: PerchHAPanelModel.OAuthSignInRunner
        let oauthApplicationConfiguration: PerchHAOAuthApplicationConfiguration?
        do {
            let configuration = try PerchHAOAuthApplicationConfiguration.fromEnvironment()
            let signInCoordinator = PerchHAOAuthSignInCoordinator(
                configuration: configuration,
                authSessionStore: authSessionStore
            )
            oauthSignInRunner = signInCoordinator.signIn(form:)
            oauthApplicationConfiguration = configuration
        } catch {
            oauthSignInRunner = { _ in .failed(String(describing: error)) }
            oauthApplicationConfiguration = nil
        }
        self.init(
            configStore: configStore,
            authSessionStore: authSessionStore,
            connector: gateway.connect(form:),
            historyProvider: gateway.history(form:entityID:range:),
            serviceMetadataProvider: gateway.services(form:),
            actionRunner: gateway.action(form:action:),
            protectedActionValueStore: KeychainProtectedActionValueStore(),
            oauthSignInRunner: oauthSignInRunner,
            oauthApplicationConfiguration: oauthApplicationConfiguration
        )
    }

    public convenience init(
        configStore: ConfigStore?,
        authSessionStore: any PerchHAAuthSessionStorage,
        client: any PerchHARefreshingHomeAssistantClient = HomeAssistantClient()
    ) {
        let gateway = PerchHAAuthorizedHomeAssistantGateway(
            client: client,
            authSessionStore: authSessionStore
        )
        self.init(
            configStore: configStore,
            authSessionStore: authSessionStore,
            connector: gateway.connect(form:),
            historyProvider: gateway.history(form:entityID:range:),
            serviceMetadataProvider: gateway.services(form:),
            actionRunner: gateway.action(form:action:),
            protectedActionValueStore: KeychainProtectedActionValueStore(),
            oauthSignInRunner: { _ in .failed("OAuth sign-in is not configured") },
            oauthApplicationConfiguration: nil
        )
    }

    public convenience init(
        configStore: ConfigStore?,
        connector: @escaping PerchHAPanelModel.Connector,
        serviceMetadataProvider: @escaping PerchHAPanelModel.ServiceMetadataProvider = { _ in .success([]) },
        protectedActionValueStore: any ProtectedActionValueStore = KeychainProtectedActionValueStore(),
        authSessionStore: (any PerchHAAuthSessionStorage)? = nil,
        oauthApplicationConfiguration: PerchHAOAuthApplicationConfiguration? = nil,
        menuBarPresenter: PerchHAMenuBarPresenter = PerchHAMenuBarPresenter(),
        gaugeImageRenderer: any PerchHAStatusItemGaugeImageRendering = PerchHAStatusItemGaugeImageRenderer()
    ) {
        self.init(
            configStore: configStore,
            authSessionStore: authSessionStore,
            connector: connector,
            historyProvider: PerchHAApplication.history(form:entityID:range:),
            serviceMetadataProvider: serviceMetadataProvider,
            actionRunner: PerchHAApplication.action(form:action:),
            protectedActionValueStore: protectedActionValueStore,
            oauthApplicationConfiguration: oauthApplicationConfiguration,
            menuBarPresenter: menuBarPresenter,
            gaugeImageRenderer: gaugeImageRenderer
        )
    }

    public init(
        configStore: ConfigStore?,
        authSessionStore: (any PerchHAAuthSessionStorage)? = nil,
        connector: @escaping PerchHAPanelModel.Connector,
        historyProvider: @escaping PerchHAPanelModel.HistoryProvider,
        serviceMetadataProvider: @escaping PerchHAPanelModel.ServiceMetadataProvider = { _ in .success([]) },
        actionRunner: @escaping PerchHAPanelModel.ActionRunner = PerchHAApplication.action(form:action:),
        protectedActionValueStore: any ProtectedActionValueStore = KeychainProtectedActionValueStore(),
        oauthSignInRunner: @escaping PerchHAPanelModel.OAuthSignInRunner = { _ in .failed("OAuth sign-in is not configured") },
        oauthApplicationConfiguration: PerchHAOAuthApplicationConfiguration? = nil,
        menuBarPresenter: PerchHAMenuBarPresenter = PerchHAMenuBarPresenter(),
        gaugeImageRenderer: any PerchHAStatusItemGaugeImageRendering = PerchHAStatusItemGaugeImageRenderer()
    ) {
        self.configStore = configStore
        self.authSessionStore = authSessionStore
        self.connector = connector
        self.historyProvider = historyProvider
        self.serviceMetadataProvider = serviceMetadataProvider
        self.actionRunner = actionRunner
        self.protectedActionValueStore = protectedActionValueStore
        self.oauthSignInRunner = oauthSignInRunner
        self.oauthApplicationConfiguration = oauthApplicationConfiguration
        self.menuBarPresenter = menuBarPresenter
        self.gaugeImageRenderer = gaugeImageRenderer
        super.init()
    }

    public static func main() {
        let application = NSApplication.shared
        let delegate = PerchHAApplication(configStore: try? JSONConfigStore())
        application.delegate = delegate
        application.setActivationPolicy(.accessory)
        application.run()
    }

    public func applicationDidFinishLaunching(_ notification: Notification) {
        releaseShell()
        configuration = loadConfiguration()
        let rememberedForm = restoredConnectionForm()

        let model = PerchHAPanelModel(
            snapshot: PerchHAPanelSnapshot(
                connectionForm: rememberedForm,
                hasTokenInput: rememberedForm.usesStoredAuthSession
            ),
            connector: { [weak self] form in
                guard let self else {
                    return .failure(.protocolError("application deallocated"))
                }
                let result = await self.connector(form)
                if case .success = result {
                    await MainActor.run {
                        self.rememberConnection(form)
                    }
                }
                return result
            },
            historyProvider: historyProvider,
            serviceMetadataProvider: serviceMetadataProvider,
            actionRunner: actionRunner,
            oauthSignInRunner: oauthSignInRunner,
            selectionConfiguration: configuration.selectionConfiguration,
            menuBarDisplayConfiguration: configuration.menuBarDisplayConfiguration,
            customActionConfiguration: configuration.customActionConfiguration,
            selectionSink: { [weak self] selection in
                self?.persist(selection: selection) ?? .failed("configuration store unavailable")
            },
            menuBarDisplaySink: { [weak self] displayConfiguration in
                self?.persist(menuBarDisplayConfiguration: displayConfiguration) ?? .failed("configuration store unavailable")
            },
            customActionSink: { [weak self] customActions in
                self?.persist(customActionConfiguration: customActions) ?? .failed("configuration store unavailable")
            },
            protectedActionValueStore: protectedActionValueStore,
            snapshotSink: { [weak self] snapshot in
                self?.updateStatusItems(from: snapshot)
            },
            signOutHandler: { [weak self] in
                self?.clearStoredAuthSession()
            }
        )
        panelModel = model
        panel = Self.makePanel(model: model) { [weak self] in
            self?.openSettingsWindow()
        }
        updateStatusItems(from: model.snapshot)
        autoConnectTask = startAutoConnect(form: rememberedForm, model: model)
    }

    /// Reconnects automatically on launch when a connection profile and a stored
    /// access token are already present, so a relaunch restores the live session
    /// instead of returning to the connection form. Returns the running task, or
    /// `nil` when no stored session is available to reconnect with.
    @discardableResult
    private func startAutoConnect(form: PerchHAConnectionForm, model: PerchHAPanelModel) -> Task<Void, Never>? {
        guard form.usesStoredAuthSession, form.primaryURL() != nil else {
            return nil
        }
        return Task { @MainActor in
            await model.connect()
        }
    }

    /// Awaits any in-flight launch auto-connect and reports the resulting
    /// connection state. Returns the current connection state immediately when no
    /// auto-connect is in flight. Makes the launch auto-connect path observable.
    public func awaitAutoConnect() async -> ConnectionState {
        await autoConnectTask?.value
        return panelModel?.snapshot.connectionState ?? .disconnected
    }

    public func applicationWillTerminate(_ notification: Notification) {
        releaseShell()
    }

    public func application(_ application: NSApplication, open urls: [URL]) {
        handleExternalURLs(urls)
    }

    @discardableResult
    public func handleExternalURLs(_ urls: [URL]) -> [PerchHAExternalURLEvent] {
        let events = urls.map(externalURLEvent(for:))
        if let last = events.last {
            lastExternalURLEvent = last
        }
        return events
    }

    public var snapshot: PerchHAApplicationSnapshot {
        let menuBarItems = statusItems.map { statusItemSnapshot(for: $0.item) }
        let first = menuBarItems.first
        let contentSize = panel.map { $0.contentRect(forFrameRect: $0.frame).size }
        return PerchHAApplicationSnapshot(
            statusItemTitle: first?.title,
            statusItemAccessibilityLabel: first?.accessibilityLabel,
            statusItemHasImage: first?.hasImage ?? false,
            statusItemImageWidth: first?.imageWidth,
            statusItemImageHeight: first?.imageHeight,
            statusItemImageIsTemplate: first?.imageIsTemplate,
            statusItemTargetIsApplication: first?.targetIsApplication ?? false,
            statusItemHasAction: first?.hasAction ?? false,
            menuBarItems: menuBarItems,
            hasPanel: panel != nil,
            hasPanelModel: panelModel != nil,
            panelCanBecomeKey: panel?.canBecomeKey ?? false,
            panelCanBecomeMain: panel?.canBecomeMain ?? false,
            panelIsFloating: panel?.isFloatingPanel ?? false,
            panelHidesOnDeactivate: panel?.hidesOnDeactivate ?? false,
            panelContentWidth: contentSize.map { Int($0.width.rounded()) },
            panelContentHeight: contentSize.map { Int($0.height.rounded()) },
            selectedEntityIDs: panelModel?.snapshot.selectionConfiguration.selectedEntityIDs ?? [],
            menuBarEntityIDs: panelModel?.snapshot.menuBarDisplayConfiguration.promotedEntityIDs ?? configuration.menuBarEntityIDs,
            menuBarItemConfigurations: panelModel?.snapshot.menuBarDisplayConfiguration.itemConfigurations ?? configuration.menuBarItemConfigurations,
            menuBarDisplayConfiguration: panelModel?.snapshot.menuBarDisplayConfiguration ?? configuration.menuBarDisplayConfiguration,
            customActionConfiguration: panelModel?.customActionConfiguration ?? configuration.customActionConfiguration,
            roomOrder: panelModel?.snapshot.selectionConfiguration.roomOrder ?? [],
            entityOrder: panelModel?.snapshot.selectionConfiguration.entityOrder ?? [],
            isEntitySelectionExplicit: panelModel?.snapshot.selectionConfiguration.isExplicit ?? false,
            displayPersistenceFailureDescription: panelModel?.snapshot.displayPersistenceFailureDescription,
            customActionPersistenceFailureDescription: panelModel?.customActionPersistenceFailureDescription,
            serviceMetadata: panelModel?.snapshot.serviceMetadata ?? [],
            serviceMetadataFailureDescription: panelModel?.snapshot.serviceMetadataFailureDescription,
            configurationPersistenceState: configurationPersistenceState,
            historyState: panelModel?.snapshot.historyState ?? .idle,
            historyPresentationEntityID: panelModel?.snapshot.historyPresentationEntityID,
            controlActionState: panelModel?.snapshot.controlActionState ?? .idle,
            lastExternalURLEvent: lastExternalURLEvent,
            connectionState: panelModel?.snapshot.connectionState ?? .disconnected,
            connectionForm: panelModel?.snapshot.connectionForm ?? PerchHAConnectionForm(),
            hasTokenInput: panelModel?.snapshot.hasTokenInput ?? false
        )
    }

    public func updateConnectionForm(
        urlString: String? = nil,
        fallbackURLString: String? = nil,
        token: String? = nil,
        usesStoredAuthSession: Bool? = nil
    ) {
        panelModel?.updateConnectionForm(
            urlString: urlString,
            fallbackURLString: fallbackURLString,
            token: token,
            usesStoredAuthSession: usesStoredAuthSession
        )
    }

    public func connect() async {
        await panelModel?.connect()
    }

    /// Signs the user out, clearing the stored Keychain session while keeping the
    /// saved connection profile so the user can reconnect easily.
    public func signOut() {
        panelModel?.signOut()
    }

    private func clearStoredAuthSession() {
        _ = try? authSessionStore?.clear()
    }

    public func startOAuthSignIn() async {
        await panelModel?.signInWithOAuth()
    }

    public func loadHistory(_ id: EntityID, range: HistoryRange) async {
        await panelModel?.loadHistory(id, range: range)
    }

    @discardableResult
    public func setEntityControl(_ id: EntityID, isOn: Bool) async -> Bool {
        await panelModel?.setEntityControl(id, isOn: isOn) ?? false
    }

    @discardableResult
    public func setCoverControl(_ id: EntityID, command: PerchHACoverCommand) async -> Bool {
        await panelModel?.setCoverControl(id, command: command) ?? false
    }

    @discardableResult
    public func setCoverPosition(_ id: EntityID, position: Int) async -> Bool {
        await panelModel?.setCoverPosition(id, position: position) ?? false
    }

    @discardableResult
    public func setCustomAction(_ action: EntityCustomAction) -> Bool {
        panelModel?.setCustomAction(action) ?? false
    }

    @discardableResult
    public func removeCustomAction(_ id: CustomActionID) -> Bool {
        panelModel?.removeCustomAction(id) ?? false
    }

    @discardableResult
    public func moveCustomAction(_ id: CustomActionID, direction: SelectionMoveDirection) -> Bool {
        panelModel?.moveCustomAction(id, direction: direction) ?? false
    }

    @discardableResult
    public func setCustomActionService(_ id: CustomActionID, domain: String, service: String) -> Bool {
        panelModel?.setCustomActionService(id, domain: domain, service: service) ?? false
    }

    @discardableResult
    public func setCustomActionServiceDataValue(_ id: CustomActionID, key: String, value: ActionValue) -> Bool {
        panelModel?.setCustomActionServiceDataValue(id, key: key, value: value) ?? false
    }

    @discardableResult
    public func setCustomActionServiceDataValue(
        _ id: CustomActionID,
        path: [PerchHACustomActionServiceDataPathComponent],
        value: ActionValue
    ) -> Bool {
        panelModel?.setCustomActionServiceDataValue(id, path: path, value: value) ?? false
    }

    @discardableResult
    public func appendCustomActionServiceDataArrayValue(
        _ id: CustomActionID,
        path: [PerchHACustomActionServiceDataPathComponent],
        value: ActionValue
    ) -> Bool {
        panelModel?.appendCustomActionServiceDataArrayValue(id, path: path, value: value) ?? false
    }

    @discardableResult
    public func setCustomActionServiceDataText(
        _ id: CustomActionID,
        key: String,
        text: String,
        kind: PerchHACustomActionServiceDataValueKind
    ) -> Bool {
        panelModel?.setCustomActionServiceDataText(id, key: key, text: text, kind: kind) ?? false
    }

    @discardableResult
    public func setCustomActionServiceDataText(
        _ id: CustomActionID,
        path: [PerchHACustomActionServiceDataPathComponent],
        text: String,
        kind: PerchHACustomActionServiceDataValueKind
    ) -> Bool {
        panelModel?.setCustomActionServiceDataText(id, path: path, text: text, kind: kind) ?? false
    }

    @discardableResult
    public func renameCustomActionServiceDataKey(_ id: CustomActionID, from oldKey: String, to newKey: String) -> Bool {
        panelModel?.renameCustomActionServiceDataKey(id, from: oldKey, to: newKey) ?? false
    }

    @discardableResult
    public func renameCustomActionServiceDataKey(
        _ id: CustomActionID,
        parentPath: [PerchHACustomActionServiceDataPathComponent],
        from oldKey: String,
        to newKey: String
    ) -> Bool {
        panelModel?.renameCustomActionServiceDataKey(id, parentPath: parentPath, from: oldKey, to: newKey) ?? false
    }

    @discardableResult
    public func removeCustomActionServiceDataKey(_ id: CustomActionID, key: String) -> Bool {
        panelModel?.removeCustomActionServiceDataKey(id, key: key) ?? false
    }

    @discardableResult
    public func removeCustomActionServiceDataValue(
        _ id: CustomActionID,
        path: [PerchHACustomActionServiceDataPathComponent]
    ) -> Bool {
        panelModel?.removeCustomActionServiceDataValue(id, path: path) ?? false
    }

    @discardableResult
    public func moveCustomActionServiceDataArrayValue(
        _ id: CustomActionID,
        path: [PerchHACustomActionServiceDataPathComponent],
        direction: SelectionMoveDirection
    ) -> Bool {
        panelModel?.moveCustomActionServiceDataArrayValue(id, path: path, direction: direction) ?? false
    }

    @discardableResult
    public func runCustomAction(_ id: CustomActionID, confirmed: Bool = false) async -> Bool {
        await panelModel?.runCustomAction(id, confirmed: confirmed) ?? false
    }

    @discardableResult
    public func applyLiveState(_ state: EntityState) -> Bool {
        panelModel?.applyLiveState(state) ?? false
    }

    @discardableResult
    public func setMenuBarEntity(_ id: EntityID, isVisible: Bool) -> Bool {
        panelModel?.setMenuBarEntity(id, isVisible: isVisible) ?? false
    }

    @discardableResult
    public func moveMenuBarEntity(_ id: EntityID, direction: SelectionMoveDirection) -> Bool {
        panelModel?.moveMenuBarEntity(id, direction: direction) ?? false
    }

    @discardableResult
    public func moveMenuBarEntity(_ id: EntityID, relativeTo targetID: EntityID, placement: SelectionDropPlacement) -> Bool {
        panelModel?.moveMenuBarEntity(id, relativeTo: targetID, placement: placement) ?? false
    }

    @discardableResult
    public func setMenuBarDisplayStyle(_ id: EntityID, style: MenuBarDisplayStyle) -> Bool {
        panelModel?.setMenuBarDisplayStyle(id, style: style) ?? false
    }

    @discardableResult
    public func setMenuBarShowsLabel(_ id: EntityID, showsLabel: Bool) -> Bool {
        panelModel?.setMenuBarShowsLabel(id, showsLabel: showsLabel) ?? false
    }

    @discardableResult
    public func setMenuBarShowsUnit(_ id: EntityID, showsUnit: Bool) -> Bool {
        panelModel?.setMenuBarShowsUnit(id, showsUnit: showsUnit) ?? false
    }

    @discardableResult
    public func setMenuBarMaximumFractionDigits(_ id: EntityID, maximumFractionDigits: Int) -> Bool {
        panelModel?.setMenuBarMaximumFractionDigits(id, maximumFractionDigits: maximumFractionDigits) ?? false
    }

    @discardableResult
    public func setMenuBarDefaultHistoryRange(_ id: EntityID, defaultHistoryRange: HistoryRange) -> Bool {
        panelModel?.setMenuBarDefaultHistoryRange(id, defaultHistoryRange: defaultHistoryRange) ?? false
    }

    @discardableResult
    public func setMenuBarAbsoluteTotal(_ id: EntityID, total: Double?) -> Bool {
        panelModel?.setMenuBarAbsoluteTotal(id, total: total) ?? false
    }

    @discardableResult
    public func setMenuBarTotalEntityID(_ id: EntityID, totalEntityID: EntityID?) -> Bool {
        panelModel?.setMenuBarTotalEntityID(id, totalEntityID: totalEntityID) ?? false
    }

    @discardableResult
    public func setCoverControlMode(_ id: EntityID, mode: CoverControlMode) -> Bool {
        panelModel?.setCoverControlMode(id, mode: mode) ?? false
    }

    @discardableResult
    public func setDisplayUnit(_ id: EntityID, displayUnit: ValueUnit) -> Bool {
        panelModel?.setDisplayUnit(id, displayUnit: displayUnit) ?? false
    }

    @discardableResult
    public func setMenuBarWarningThreshold(_ id: EntityID, threshold: ValueThreshold?) -> Bool {
        panelModel?.setMenuBarWarningThreshold(id, threshold: threshold) ?? false
    }

    @discardableResult
    public func setMenuBarCriticalThreshold(_ id: EntityID, threshold: ValueThreshold?) -> Bool {
        panelModel?.setMenuBarCriticalThreshold(id, threshold: threshold) ?? false
    }

    @discardableResult
    public func persist(selection: EntitySelectionConfiguration) -> SelectionPersistenceResult {
        guard let configStore else {
            configurationPersistenceState = .unavailable
            return .failed("configuration store unavailable")
        }
        if case let .loadFailed(message) = configurationPersistenceState {
            return .failed("configuration load failed; save blocked: \(message)")
        }

        let nextConfiguration = PerchHAConfiguration(
            schemaVersion: configuration.schemaVersion,
            selectedEntityIDs: selection.selectedEntityIDs,
            menuBarEntityIDs: configuration.menuBarEntityIDs,
            menuBarItemConfigurations: configuration.menuBarItemConfigurations,
            customActions: configuration.customActions,
            connectionProfile: configuration.connectionProfile,
            roomOrder: selection.roomOrder,
            entityOrder: selection.entityOrder,
            isEntitySelectionExplicit: selection.isExplicit
        )
        do {
            configuration = try configStore.save(nextConfiguration)
            configurationPersistenceState = .ready
            return .saved
        } catch {
            let message = String(describing: error)
            configurationPersistenceState = .saveFailed(message)
            return .failed(message)
        }
    }

    @discardableResult
    public func persist(menuBarDisplayConfiguration displayConfiguration: MenuBarDisplayConfiguration) -> SelectionPersistenceResult {
        guard let configStore else {
            configurationPersistenceState = .unavailable
            return .failed("configuration store unavailable")
        }
        if case let .loadFailed(message) = configurationPersistenceState {
            return .failed("configuration load failed; save blocked: \(message)")
        }

        let nextConfiguration = PerchHAConfiguration(
            schemaVersion: configuration.schemaVersion,
            selectedEntityIDs: configuration.selectedEntityIDs,
            menuBarEntityIDs: displayConfiguration.promotedEntityIDs,
            menuBarItemConfigurations: displayConfiguration.itemConfigurations,
            customActions: configuration.customActions,
            connectionProfile: configuration.connectionProfile,
            roomOrder: configuration.roomOrder,
            entityOrder: configuration.entityOrder,
            isEntitySelectionExplicit: configuration.isEntitySelectionExplicit
        )
        do {
            configuration = try configStore.save(nextConfiguration)
            configurationPersistenceState = .ready
            return .saved
        } catch {
            let message = String(describing: error)
            configurationPersistenceState = .saveFailed(message)
            return .failed(message)
        }
    }

    @discardableResult
    public func persist(customActionConfiguration: CustomActionConfiguration) -> SelectionPersistenceResult {
        guard let configStore else {
            configurationPersistenceState = .unavailable
            return .failed("configuration store unavailable")
        }
        if case let .loadFailed(message) = configurationPersistenceState {
            return .failed("configuration load failed; save blocked: \(message)")
        }
        if let failure = customActionConfiguration.validationFailure() {
            let message = "custom action configuration is invalid: \(failure.description)"
            configurationPersistenceState = .saveFailed(message)
            return .failed(message)
        }

        let nextConfiguration = PerchHAConfiguration(
            schemaVersion: configuration.schemaVersion,
            selectedEntityIDs: configuration.selectedEntityIDs,
            menuBarEntityIDs: configuration.menuBarEntityIDs,
            menuBarItemConfigurations: configuration.menuBarItemConfigurations,
            customActions: customActionConfiguration.actions,
            connectionProfile: configuration.connectionProfile,
            roomOrder: configuration.roomOrder,
            entityOrder: configuration.entityOrder,
            isEntitySelectionExplicit: configuration.isEntitySelectionExplicit
        )
        do {
            configuration = try configStore.save(nextConfiguration)
            configurationPersistenceState = .ready
            return .saved
        } catch {
            let message = String(describing: error)
            configurationPersistenceState = .saveFailed(message)
            return .failed(message)
        }
    }

    public static func makePanel(
        model: PerchHAPanelModel,
        onOpenSettings: (() -> Void)? = nil
    ) -> NSPanel {
        let panel = PerchHAStatusPanel(
            contentRect: NSRect(origin: .zero, size: AppShellLayout.panelContentSize),
            styleMask: [.nonactivatingPanel, .titled, .fullSizeContentView],
            backing: .buffered,
            defer: true
        )
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = true
        panel.contentViewController = NSHostingController(
            rootView: PerchHAPanelView(model: model, onOpenSettings: onOpenSettings)
        )
        panel.setContentSize(AppShellLayout.panelContentSize)
        return panel
    }

    public static func makeSettingsWindow(
        model: PerchHAPanelModel,
        initialTab: PerchHASettingsView.Tab = .connection
    ) -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: AppShellLayout.settingsMinContentSize),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: true
        )
        window.title = "PearchHA Settings"
        window.isReleasedWhenClosed = false
        window.contentMinSize = AppShellLayout.settingsMinContentSize
        // Host the SwiftUI tree through a hosting controller (not a bare
        // contentView) so the responder chain is wired and text fields accept
        // keyboard input and paste.
        window.contentViewController = NSHostingController(
            rootView: PerchHASettingsView(model: model, initialTab: initialTab)
        )
        window.setContentSize(AppShellLayout.settingsMinContentSize)
        return window
    }

    private func openSettingsWindow() {
        guard let panelModel else {
            return
        }
        // Opening Settings dismisses the drop-down panel so the two windows do
        // not overlap.
        panel?.orderOut(nil)
        let window = settingsWindow ?? Self.makeSettingsWindow(model: panelModel)
        settingsWindow = window
        if !window.isVisible {
            window.center()
        }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func togglePanel(_ sender: NSStatusBarButton) {
        guard let panel else {
            return
        }
        if panel.isVisible {
            panel.orderOut(sender)
            return
        }

        position(panel: panel, relativeTo: sender)
        panel.makeKeyAndOrderFront(sender)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func position(panel: NSPanel, relativeTo sender: NSStatusBarButton) {
        guard let window = sender.window, let screenFrame = window.screen?.visibleFrame else {
            panel.center()
            return
        }

        let buttonFrame = window.convertToScreen(sender.frame)
        let size = panel.frame.size
        let x = min(max(buttonFrame.midX - size.width / 2, screenFrame.minX + 8), screenFrame.maxX - size.width - 8)
        let y = buttonFrame.minY - size.height - 8
        panel.setFrameOrigin(NSPoint(x: x, y: max(y, screenFrame.minY + 8)))
    }

    private func releaseShell() {
        autoConnectTask?.cancel()
        autoConnectTask = nil
        panelModel?.cancelInFlightAction()
        panel?.orderOut(nil)
        panel?.contentViewController = nil
        panel = nil
        settingsWindow?.orderOut(nil)
        settingsWindow?.contentViewController = nil
        settingsWindow = nil
        panelModel = nil

        for entry in statusItems {
            NSStatusBar.system.removeStatusItem(entry.item)
        }
        statusItems = []
    }

    /// Reconciles the live menu-bar status items against the presenter output:
    /// one item per promoted entity (in order), or a single fallback fish-logo
    /// item when nothing is promoted. Creates, updates, and removes items in
    /// place so each item keeps the same toggle target/action and a per-entity
    /// image cache, preserving gauge-redraw throttling.
    private func updateStatusItems(from snapshot: PerchHAPanelSnapshot) {
        let presentations = menuBarPresenter.presentations(
            configuration: configuration,
            panelSnapshot: snapshot
        )

        while statusItems.count > presentations.count {
            let removed = statusItems.removeLast()
            NSStatusBar.system.removeStatusItem(removed.item)
        }
        while statusItems.count < presentations.count {
            statusItems.append(PerchHAStatusItemEntry(item: makeStatusItem()))
        }

        for (index, presentation) in presentations.enumerated() {
            apply(presentation, to: &statusItems[index])
        }
    }

    private func makeStatusItem() -> NSStatusItem {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.target = self
        item.button?.action = #selector(togglePanel(_:))
        return item
    }

    private func apply(_ presentation: PerchHAMenuBarPresentation, to entry: inout PerchHAStatusItemEntry) {
        let image: NSImage?
        let title: String
        if let renderedItem = presentation.renderedItem,
           renderedItem.gauge != nil || renderedItem.value.iconSymbolName != nil {
            image = cachedStatusItemImage(for: renderedItem, in: &entry)
            // Icon units carry the value in the glyph, so the title is dropped.
            title = renderedItem.value.iconSymbolName != nil ? "" : presentation.statusItemTitle
        } else if presentation == .fallback {
            // Nothing is promoted: show the template logo glyph instead of text.
            entry.imageCache = nil
            image = cachedStatusItemLogoImage()
            title = ""
        } else {
            entry.imageCache = nil
            image = nil
            title = presentation.statusItemTitle
        }
        entry.presentation = presentation
        let button = entry.item.button
        button?.image = image
        button?.imagePosition = image == nil ? .noImage : .imageLeading
        button?.title = title
        button?.toolTip = presentation.accessibilityLabel
        button?.setAccessibilityLabel(presentation.accessibilityLabel)
    }

    private func cachedStatusItemImage(for item: RenderedMenuBarItem, in entry: inout PerchHAStatusItemEntry) -> NSImage? {
        let key = PerchHAStatusItemImageCacheKey(item: item)
        if let imageCache = entry.imageCache, imageCache.key == key {
            return imageCache.image
        }
        let image = gaugeImageRenderer.image(for: item)
        entry.imageCache = (key, image)
        return image
    }

    private func statusItemSnapshot(for item: NSStatusItem) -> PerchHAMenuBarStatusItemSnapshot {
        let button = item.button
        return PerchHAMenuBarStatusItemSnapshot(
            title: button?.title,
            accessibilityLabel: button?.accessibilityLabel(),
            hasImage: button?.image != nil,
            imageWidth: button?.image.map { Int($0.size.width.rounded()) },
            imageHeight: button?.image.map { Int($0.size.height.rounded()) },
            imageIsTemplate: button?.image?.isTemplate,
            hasAction: button?.action != nil,
            targetIsApplication: (button?.target as AnyObject?) === self
        )
    }

    private func cachedStatusItemLogoImage() -> NSImage? {
        if let statusItemLogoImageCache {
            return statusItemLogoImageCache
        }
        let image = appIconStatusItemImage() ?? logoImageRenderer.image()
        statusItemLogoImageCache = image
        return image
    }

    /// The application icon scaled to the menu-bar logo size, or nil when no
    /// usable app icon is available.
    ///
    /// The result is a non-template (colored) image fitted into the renderer's
    /// square size, preserving aspect ratio and centered.
    private func appIconStatusItemImage() -> NSImage? {
        let appIcon = NSApp.applicationIconImage ?? NSImage(named: NSImage.applicationIconName)
        guard let appIcon, appIcon.size.width > 0, appIcon.size.height > 0 else {
            return nil
        }
        let target = logoImageRenderer.size
        let scale = min(target.width / appIcon.size.width, target.height / appIcon.size.height)
        let drawSize = NSSize(width: appIcon.size.width * scale, height: appIcon.size.height * scale)
        let origin = NSPoint(
            x: (target.width - drawSize.width) / 2,
            y: (target.height - drawSize.height) / 2
        )
        let scaled = NSImage(size: target)
        scaled.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .high
        appIcon.draw(
            in: NSRect(origin: origin, size: drawSize),
            from: .zero,
            operation: .sourceOver,
            fraction: 1
        )
        scaled.unlockFocus()
        scaled.isTemplate = false
        return scaled
    }

    private func loadConfiguration() -> PerchHAConfiguration {
        guard let configStore else {
            configurationPersistenceState = .unavailable
            return .empty
        }
        do {
            let loadedConfiguration = try configStore.load()
            if let failure = loadedConfiguration.customActionConfiguration.validationFailure() {
                configurationPersistenceState = .loadFailed("custom action configuration is invalid: \(failure.description)")
                return .empty
            }
            configurationPersistenceState = .ready
            return loadedConfiguration
        } catch {
            configurationPersistenceState = .loadFailed(String(describing: error))
            return .empty
        }
    }

    private func restoredConnectionForm() -> PerchHAConnectionForm {
        let profile = configuration.connectionProfile
        let usesStoredAuthSession: Bool
        if let authSessionStore {
            usesStoredAuthSession = (try? authSessionStore.loadAccessToken()) != nil
        } else {
            usesStoredAuthSession = false
        }
        return PerchHAConnectionForm(
            urlString: profile?.urlString ?? "",
            fallbackURLString: profile?.fallbackURLString ?? "",
            token: "",
            usesStoredAuthSession: usesStoredAuthSession
        )
    }

    private func rememberConnection(_ form: PerchHAConnectionForm) {
        if let authSessionStore, !form.trimmedToken.isEmpty {
            _ = try? authSessionStore.saveAccessToken(form.trimmedToken)
        }
        guard let configStore else {
            return
        }
        if case .loadFailed = configurationPersistenceState {
            return
        }
        let nextConfiguration = PerchHAConfiguration(
            schemaVersion: configuration.schemaVersion,
            selectedEntityIDs: configuration.selectedEntityIDs,
            menuBarEntityIDs: configuration.menuBarEntityIDs,
            menuBarItemConfigurations: configuration.menuBarItemConfigurations,
            customActions: configuration.customActions,
            connectionProfile: PerchHAConnectionProfile(
                urlString: PerchHAConnectionForm.normalizedHomeAssistantURLString(form.urlString),
                fallbackURLString: PerchHAConnectionForm.normalizedHomeAssistantURLString(form.fallbackURLString)
            ),
            roomOrder: configuration.roomOrder,
            entityOrder: configuration.entityOrder,
            isEntitySelectionExplicit: configuration.isEntitySelectionExplicit
        )
        do {
            configuration = try configStore.save(nextConfiguration)
            configurationPersistenceState = .ready
        } catch {
            configurationPersistenceState = .saveFailed(String(describing: error))
        }
    }

    private func externalURLEvent(for url: URL) -> PerchHAExternalURLEvent {
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let scheme = components?.scheme ?? url.scheme
        let disposition: PerchHAExternalURLDisposition
        if let oauthApplicationConfiguration {
            if scheme?.caseInsensitiveCompare(oauthApplicationConfiguration.callbackURLScheme) != .orderedSame {
                disposition = .rejectedUnsupportedScheme
            } else if oauthApplicationConfiguration.acceptsCallbackURL(url) {
                disposition = .acceptedOAuthCallback
            } else {
                disposition = .rejectedRedirectMismatch
            }
        } else {
            disposition = .rejectedOAuthNotConfigured
        }
        return PerchHAExternalURLEvent(
            scheme: scheme,
            host: components?.host ?? url.host,
            port: components?.port ?? url.port,
            path: components?.path ?? url.path,
            hasQuery: components?.query?.isEmpty == false,
            hasFragment: components?.fragment?.isEmpty == false,
            disposition: disposition
        )
    }

    private static func connect(form: PerchHAConnectionForm) async -> PerchHAConnectionAttemptResult {
        await PerchHAAuthorizedHomeAssistantGateway().connect(form: form)
    }

    private static func history(
        form: PerchHAConnectionForm,
        entityID: EntityID,
        range: HistoryRange
    ) async -> PerchHAHistoryProviderResult {
        await PerchHAAuthorizedHomeAssistantGateway().history(form: form, entityID: entityID, range: range)
    }

    public static func services(form: PerchHAConnectionForm) async -> PerchHAServiceMetadataProviderResult {
        await PerchHAAuthorizedHomeAssistantGateway().services(form: form)
    }

    public static func action(form: PerchHAConnectionForm, action: ActionSpec) async -> PerchHAActionResult {
        await PerchHAAuthorizedHomeAssistantGateway().action(form: form, action: action)
    }
}

/// A live menu-bar status item paired with its last presentation and a
/// per-entity gauge-image cache so redraws only happen when the item changes.
private struct PerchHAStatusItemEntry {
    let item: NSStatusItem
    var presentation: PerchHAMenuBarPresentation = .fallback
    var imageCache: (key: PerchHAStatusItemImageCacheKey, image: NSImage?)?
}

private struct PerchHAStatusItemImageCacheKey: Equatable {
    let style: MenuBarDisplayStyle
    let gauge: MenuBarGauge?
    let severity: ValueSeverity
    let iconSymbolName: String?

    init(item: RenderedMenuBarItem) {
        style = item.style
        gauge = item.gauge
        severity = item.severity
        iconSymbolName = item.value.iconSymbolName
    }
}

private extension ConnectionFailure {
    var historyDescription: String {
        switch self {
        case .authentication:
            "authentication failed"
        case let .unreachable(host):
            "unreachable at \(host)"
        case let .tlsRejected(host):
            "TLS rejected for \(host)"
        case let .unsupportedCommand(command):
            "unsupported command \(command)"
        case let .protocolError(message):
            message
        }
    }

    var actionDescription: String {
        switch self {
        case .authentication:
            "authentication failed"
        case let .unreachable(host):
            "unreachable at \(host)"
        case let .tlsRejected(host):
            "TLS rejected for \(host)"
        case let .unsupportedCommand(command):
            "unsupported command \(command)"
        case let .protocolError(message):
            message
        }
    }
}
