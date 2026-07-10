import AppKit
import AuthenticationServices
import OSLog
import PerchHACore
import PerchHAClient
import PerchHAPersistence
import PerchHASupport
import PerchHAUI
import Security
import ServiceManagement
import SwiftUI

private enum AppShellLayout {
    static let panelContentSize = NSSize(width: 384, height: 468)
    static let settingsMinContentSize = NSSize(width: 660, height: 560)
}

private final class PerchHAFirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }
}

private final class PerchHAFirstMouseHostingController<Content: View>: NSHostingController<Content> {
    override func loadView() {
        view = PerchHAFirstMouseHostingView(rootView: rootView)
    }
}

public final class PerchHAStatusPanel: NSPanel {
    /// Invoked when the user presses Cmd+, inside the panel, routing to the
    /// app shell's open-settings path. Set by the owning ``PerchHAApplication``.
    public var onOpenSettings: (() -> Void)?
    public var onScrollWheelEvent: (() -> Void)?

    /// Creates a status panel with the menu-bar drop-down style mask used by the
    /// app shell. Exposed so the interaction behavior (Escape to close, Cmd+, to
    /// open settings) can be exercised directly.
    public convenience init() {
        self.init(
            contentRect: NSRect(origin: .zero, size: AppShellLayout.panelContentSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        isFloatingPanel = true
        hidesOnDeactivate = true
        // The SwiftUI root paints the rounded dashboard surface and its shadow, so
        // the window itself is a clear, chrome-free host: no titlebar, no traffic
        // lights, no opaque background to bleed past the rounded corners.
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
    }

    public override var canBecomeKey: Bool {
        true
    }

    public override var canBecomeMain: Bool {
        true
    }

    /// Called with the panel's visibility whenever it genuinely changes.
    ///
    /// Every dismissal path funnels through here — Escape, the status-item
    /// toggle, programmatic `orderOut`, and the auto-hide that fires when the
    /// app deactivates (click-away) — so the shell can stop background work the
    /// moment the panel disappears instead of only on explicit toggles.
    public var onVisibilityChange: ((Bool) -> Void)?

    private var lastReportedVisibility: Bool?

    private func reportVisibilityIfChanged() {
        let visible = isVisible
        guard visible != lastReportedVisibility else {
            return
        }
        lastReportedVisibility = visible
        onVisibilityChange?(visible)
    }

    public override func order(_ place: NSWindow.OrderingMode, relativeTo otherWin: Int) {
        super.order(place, relativeTo: otherWin)
        reportVisibilityIfChanged()
    }

    public override func orderOut(_ sender: Any?) {
        super.orderOut(sender)
        reportVisibilityIfChanged()
    }

    public override func makeKeyAndOrderFront(_ sender: Any?) {
        super.makeKeyAndOrderFront(sender)
        reportVisibilityIfChanged()
    }

    public override func scrollWheel(with event: NSEvent) {
        onScrollWheelEvent?()
        super.scrollWheel(with: event)
    }

    public override init(
        contentRect: NSRect,
        styleMask style: NSWindow.StyleMask,
        backing backingStoreType: NSWindow.BackingStoreType,
        defer flag: Bool
    ) {
        super.init(contentRect: contentRect, styleMask: style, backing: backingStoreType, defer: flag)
        // The auto-hide that `hidesOnDeactivate` performs on click-away does not
        // route through the public ordering overrides, but it does flip the
        // occlusion state — observe it so click-away also reports visibility.
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowVisibilityMayHaveChanged(_:)),
            name: NSWindow.didChangeOcclusionStateNotification,
            object: self
        )
    }

    @objc private func windowVisibilityMayHaveChanged(_ notification: Notification) {
        reportVisibilityIfChanged()
    }

    /// Closes the panel when Escape is pressed, matching macOS popover behavior.
    public override func cancelOperation(_ sender: Any?) {
        orderOut(sender)
    }

    public override func keyDown(with event: NSEvent) {
        // Escape (key code 53) closes the panel even when no field has claimed
        // the event as a cancel operation.
        if event.keyCode == 53 {
            orderOut(self)
            return
        }
        super.keyDown(with: event)
    }

    public override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard event.type == .keyDown,
              event.modifierFlags.intersection(.deviceIndependentFlagsMask).contains(.command),
              let characters = event.charactersIgnoringModifiers?.lowercased()
        else {
            return super.performKeyEquivalent(with: event)
        }

        // Cmd+, opens Settings, mirroring the standard macOS Preferences shortcut.
        if characters == ",", let onOpenSettings {
            onOpenSettings()
            return true
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
    public let showsLoadingIndicator: Bool
    public let imageWidth: Int?
    public let imageHeight: Int?
    public let imageIsTemplate: Bool?
    public let hasAction: Bool
    public let targetIsApplication: Bool

    public init(
        title: String?,
        accessibilityLabel: String?,
        hasImage: Bool,
        showsLoadingIndicator: Bool,
        imageWidth: Int?,
        imageHeight: Int?,
        imageIsTemplate: Bool?,
        hasAction: Bool,
        targetIsApplication: Bool
    ) {
        self.title = title
        self.accessibilityLabel = accessibilityLabel
        self.hasImage = hasImage
        self.showsLoadingIndicator = showsLoadingIndicator
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
    public let statusItemShowsLoadingIndicator: Bool
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
    /// A shell-level Keychain/configuration-store problem the user must see,
    /// or `nil` when shell persistence is healthy.
    public let shellPersistenceFailureDescription: String?
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
    func historyBatch(_ input: HAConnectionInput, entityIDs: [EntityID], range: HistoryRange, end: Date) async -> HAClientResult<[EntityID: HistorySeries]>
    func services(_ input: HAConnectionInput) async -> HAClientResult<[HAServiceMetadata]>
    func callService(_ input: HAConnectionInput, call: HAServiceCall) async -> HAClientResult<HAServiceCallResult>
    func refreshAccessToken(baseURL: URL, refreshToken: String, clientID: String) async -> HAClientResult<HAOAuthToken>
    func streamEntityStateChanges(
        _ input: HAConnectionInput,
        onEvent: @escaping @Sendable (EntityState) async -> Void
    ) async -> HAClientFailure
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

    /// Fetches history for many entities sharing a range in as few requests as
    /// possible, for the background bulk sync loop.
    ///
    /// Routes through the same authorized-request path as every other call, so
    /// an expired OAuth access token is refreshed and retried once instead of
    /// silently starving the background sync after the token's 30-minute
    /// lifetime. Non-fatal batch failures are absorbed by the client — a
    /// partial result simply returns the entities that came back. No token is
    /// ever logged or leaked.
    ///
    /// - Parameters:
    ///   - form: The active connection profile.
    ///   - entityIDs: The entities to fetch.
    ///   - range: The shared history range.
    /// - Returns: A series per entity that came back; missing entities are
    ///   absent. Empty when the whole call failed — the sync loop keeps prior
    ///   cache entries and retries next cycle.
    public func bulkHistory(
        form: PerchHAConnectionForm,
        entityIDs: [EntityID],
        range: HistoryRange
    ) async -> [EntityID: HistorySeries] {
        guard let primaryURL = form.primaryURL(), !entityIDs.isEmpty else {
            return [:]
        }
        let result = await perform(form: form, primaryURL: primaryURL) { input in
            await client.historyBatch(input, entityIDs: entityIDs, range: range, end: Date())
        }
        guard case let .success(series) = result else {
            return [:]
        }
        return series
    }

    /// Streams live entity state updates for the connection until the stream
    /// ends, delivering each update through `onEvent`.
    ///
    /// Rides the same authorized-request machinery as every other call: an
    /// expired OAuth access token is refreshed and the stream restarted once,
    /// and an unreachable address falls through to the next configured URL for
    /// the initial connection. Returns only when the stream is over — the
    /// caller owns reconnect pacing.
    ///
    /// - Parameters:
    ///   - form: The active connection profile.
    ///   - onEvent: Invoked for each live entity state update.
    /// - Returns: The failure that ended the stream.
    public func streamLiveUpdates(
        form: PerchHAConnectionForm,
        onEvent: @escaping @Sendable (EntityState) async -> Void
    ) async -> ConnectionFailure {
        guard let primaryURL = form.primaryURL() else {
            return .protocolError("invalid Home Assistant URL")
        }
        // A healthy stream never returns, so the operation's value is never
        // produced; wrapping the terminal failure keeps the shared refresh and
        // URL-fallback machinery applicable.
        let result: HAClientResult<Bool> = await perform(form: form, primaryURL: primaryURL) { input in
            .failure(await client.streamEntityStateChanges(input, onEvent: onEvent))
        }
        switch result {
        case .success:
            return .protocolError("live update stream ended without a failure")
        case let .failure(failure):
            return failure.connectionFailure
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
            let urls = form.urls()
            var lastResult: HAClientResult<Value> = .failure(.transport("no endpoint configured"))
            for (index, baseURL) in urls.enumerated() {
                let attemptInput = authorizedInput.input(for: baseURL)
                let attempt = await resolveAuthenticationFailure(
                    await operation(attemptInput),
                    authorizedInput: authorizedInput,
                    attemptedInput: attemptInput,
                    refreshBaseURL: baseURL,
                    operation: operation
                )
                lastResult = attempt
                let isLast = index == urls.count - 1
                if case let .failure(failure) = attempt, shouldRetryOnFallback(failure), !isLast {
                    continue
                }
                return attempt
            }
            return lastResult
        }
    }

    private func resolveInput(form: PerchHAConnectionForm, primaryURL: URL) -> HAClientResult<PerchHAAuthorizedInput> {
        let urls = form.urls()
        let endpoint = HAEndpoint(urls: urls.isEmpty ? [primaryURL] : urls)
        let serverTrustPolicy = PerchHAServerTrustPolicyResolver.policy(for: form)
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

/// Maps a connection form's certificate preference to the client trust policy.
///
/// Certificate validation is strict by default. Only an explicit user opt-in on
/// the form produces an allowance, and that allowance is scoped to the form's
/// current HTTPS hosts — the app never trusts all hosts.
public enum PerchHAServerTrustPolicyResolver {
    /// Resolves the trust policy for a connection form.
    ///
    /// - Parameter form: The connection form describing the target addresses and
    ///   the user's self-signed certificate preference.
    /// - Returns: The default strict policy, or a policy allowing self-signed
    ///   certificates for exactly the form's HTTPS hosts when the user opted in.
    public static func policy(for form: PerchHAConnectionForm) -> HAServerTrustPolicy {
        guard form.allowsSelfSignedCertificates else {
            return .default
        }
        return HAServerTrustPolicy(allowedSelfSignedCertificateHosts: form.selfSignedCertificateHosts())
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
            serverTrustPolicy: PerchHAServerTrustPolicyResolver.policy(for: form)
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
    private var pendingStatusItemSnapshot: PerchHAPanelSnapshot?
    private var statusItemRefreshTask: Task<Void, Never>?
    private var lastStatusItemRefreshAt: Date?
    private var panel: NSPanel?
    private var settingsWindow: NSWindow?
    /// Restores the accessory activation policy when Settings closes.
    private var settingsWindowCloseObserver: NSObjectProtocol?
    private var panelModel: PerchHAPanelModel?
    private var autoConnectTask: Task<Void, Never>?
    private let configStore: ConfigStore?
    private let authSessionStore: (any PerchHAAuthSessionStorage)?
    private let connector: PerchHAPanelModel.Connector
    private let historyProvider: PerchHAPanelModel.HistoryProvider
    private let bulkHistoryProvider: PerchHAPanelModel.BulkHistoryProvider
    private let serviceMetadataProvider: PerchHAPanelModel.ServiceMetadataProvider
    private let liveUpdateStreamer: PerchHAPanelModel.LiveUpdateStreamer?
    private let actionRunner: PerchHAPanelModel.ActionRunner
    private let oauthSignInRunner: PerchHAPanelModel.OAuthSignInRunner
    private let releaseUpdateChecker: PerchHAPanelModel.ReleaseUpdateChecker
    private let protectedActionValueStore: any ProtectedActionValueStore
    private let oauthApplicationConfiguration: PerchHAOAuthApplicationConfiguration?
    private let menuBarPresenter: PerchHAMenuBarPresenter
    private let gaugeImageRenderer: any PerchHAStatusItemGaugeImageRendering
    private let logoImageRenderer = PerchHAStatusItemLogoImageRenderer()
    private let performanceSignposter = OSSignposter(
        logger: Logger(subsystem: "dev.yuna.perchha", category: "Performance")
    )
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
            bulkHistoryProvider: gateway.bulkHistory(form:entityIDs:range:),
            serviceMetadataProvider: gateway.services(form:),
            liveUpdateStreamer: gateway.streamLiveUpdates(form:onEvent:),
            actionRunner: gateway.action(form:action:),
            releaseUpdateChecker: { currentVersion in
                await PerchHAGitHubReleaseUpdateChecker().checkLatest(currentVersion: currentVersion)
            },
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
            bulkHistoryProvider: gateway.bulkHistory(form:entityIDs:range:),
            serviceMetadataProvider: gateway.services(form:),
            liveUpdateStreamer: gateway.streamLiveUpdates(form:onEvent:),
            actionRunner: gateway.action(form:action:),
            releaseUpdateChecker: { currentVersion in
                await PerchHAGitHubReleaseUpdateChecker().checkLatest(currentVersion: currentVersion)
            },
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
        bulkHistoryProvider: @escaping PerchHAPanelModel.BulkHistoryProvider = { _, _, _ in [:] },
        serviceMetadataProvider: @escaping PerchHAPanelModel.ServiceMetadataProvider = { _ in .success([]) },
        liveUpdateStreamer: PerchHAPanelModel.LiveUpdateStreamer? = nil,
        actionRunner: @escaping PerchHAPanelModel.ActionRunner = PerchHAApplication.action(form:action:),
        releaseUpdateChecker: @escaping PerchHAPanelModel.ReleaseUpdateChecker = { currentVersion in
            await PerchHAGitHubReleaseUpdateChecker().checkLatest(currentVersion: currentVersion)
        },
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
        self.bulkHistoryProvider = bulkHistoryProvider
        self.serviceMetadataProvider = serviceMetadataProvider
        self.liveUpdateStreamer = liveUpdateStreamer
        self.actionRunner = actionRunner
        self.releaseUpdateChecker = releaseUpdateChecker
        self.protectedActionValueStore = protectedActionValueStore
        self.oauthSignInRunner = oauthSignInRunner
        self.oauthApplicationConfiguration = oauthApplicationConfiguration
        self.menuBarPresenter = menuBarPresenter
        self.gaugeImageRenderer = gaugeImageRenderer
        super.init()
    }

    public static func main() {
        let application = NSApplication.shared
        ProcessInfo.processInfo.processName = "PearchHA"
        let delegate = PerchHAApplication(configStore: try? JSONConfigStore())
        application.delegate = delegate
        application.setActivationPolicy(.accessory)
        applyPearchApplicationIcon()
        // An accessory app has no visible menu bar, but the main menu still
        // drives keyboard equivalents: without an Edit menu, Cmd+C/V/X/A and
        // undo are dead in the Settings window's text fields.
        application.mainMenu = standardMainMenu()
        application.run()
    }

    /// Builds the minimal main menu an accessory app needs: a standard Edit
    /// menu so text fields in the Settings window get the system keyboard
    /// equivalents (cut, copy, paste, select-all, undo, redo).
    ///
    /// - Returns: The main menu to install on the shared application.
    public static func standardMainMenu() -> NSMenu {
        let mainMenu = NSMenu()
        let editItem = NSMenuItem()
        mainMenu.addItem(editItem)
        let editMenu = NSMenu(title: "Edit")
        editItem.submenu = editMenu
        editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        let redoItem = NSMenuItem(title: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        editMenu.addItem(redoItem)
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        return mainMenu
    }

    public func applicationDidFinishLaunching(_ notification: Notification) {
        releaseShell()
        configuration = loadConfiguration()
        applyAppearancePreferences()
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
                } else {
                    await MainActor.run {
                        if self.shouldRememberAttemptedManualToken(form: form, result: result) {
                            self.rememberAttemptedManualToken(form)
                        }
                    }
                }
                return result
            },
            historyProvider: historyProvider,
            bulkHistoryProvider: bulkHistoryProvider,
            serviceMetadataProvider: serviceMetadataProvider,
            liveUpdateStreamer: liveUpdateStreamer,
            actionRunner: actionRunner,
            oauthSignInRunner: oauthSignInRunner,
            releaseUpdateChecker: releaseUpdateChecker,
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
                self?.scheduleStatusItemRefresh(from: snapshot)
                self?.scheduleDisplayConfigurationRepairIfNeeded(after: snapshot)
            },
            signOutHandler: { [weak self] in
                self?.clearStoredAuthSession()
            }
        )
        model.applyDisplayPreferences(configuration.displayPreferences)
        panelModel = model
        panel = Self.makePanel(
            model: model,
            onOpenSettings: { [weak self] in
                self?.openSettingsWindow()
            },
            onOpenEntitySettings: { [weak self] entityID in
                self?.openSettingsWindow(
                    initialTab: .entities,
                    initiallyExpandedEntityIDs: [entityID]
                )
            }
        )
        scheduleStatusItemRefresh(from: model.snapshot, force: true)
        autoConnectTask = startAutoConnect(form: rememberedForm, model: model)
    }

    /// Reconnects automatically on launch when a connection profile and a stored
    /// access token are already present, so a relaunch restores the live session
    /// instead of returning to the connection form. Returns the running task, or
    /// `nil` when no stored session is available to reconnect with.
    @discardableResult
    private func startAutoConnect(form: PerchHAConnectionForm, model: PerchHAPanelModel) -> Task<Void, Never>? {
        guard form.primaryURL() != nil else {
            return nil
        }
        guard let autoConnectForm = storedSessionFormIfAvailable(for: form) else {
            return nil
        }
        return Task { @MainActor in
            if !model.snapshot.connectionForm.sameConnection(as: autoConnectForm)
                || !model.snapshot.connectionForm.usesStoredAuthSession {
                model.updateConnectionForm(
                    urlString: autoConnectForm.urlString,
                    addresses: autoConnectForm.addresses,
                    token: "",
                    usesStoredAuthSession: true,
                    allowsSelfSignedCertificates: autoConnectForm.allowsSelfSignedCertificates
                )
            }
            let retryDelays: [UInt64] = [
                250_000_000,
                500_000_000,
                1_000_000_000,
                2_000_000_000,
                4_000_000_000
            ]
            var attempt = 0
            while !Task.isCancelled {
                await model.connect()
                if shouldStopAutoConnectRetry(model: model, originalForm: autoConnectForm) {
                    return
                }
                let delay = retryDelays[min(attempt, retryDelays.count - 1)]
                attempt += 1
                try? await Task.sleep(nanoseconds: delay)
            }
        }
    }

    private func storedSessionFormIfAvailable(for form: PerchHAConnectionForm) -> PerchHAConnectionForm? {
        if form.usesStoredAuthSession {
            return form
        }
        guard let authSessionStore else {
            return nil
        }
        do {
            _ = try authSessionStore.loadAccessToken()
            return PerchHAConnectionForm(
                urlString: form.urlString,
                addresses: form.addresses,
                token: "",
                usesStoredAuthSession: true,
                allowsSelfSignedCertificates: form.allowsSelfSignedCertificates
            )
        } catch SecretStoreError.notFound(_) {
            return nil
        } catch {
            panelModel?.reportShellPersistenceFailure(
                "Could not load the stored session from the Keychain: \(error)"
            )
            return nil
        }
    }

    private func shouldStopAutoConnectRetry(
        model: PerchHAPanelModel,
        originalForm: PerchHAConnectionForm
    ) -> Bool {
        if model.snapshot.connectionState == .connected {
            return true
        }
        if !model.snapshot.connectionForm.sameConnection(as: originalForm) {
            return true
        }
        if !model.snapshot.connectionForm.usesStoredAuthSession {
            return true
        }
        switch model.snapshot.connectionState {
        case .failed(.authentication), .failed(.protocolError):
            return true
        case .disconnected, .connecting, .connected, .reconnecting, .failed:
            return false
        }
    }

    private func scheduleDisplayConfigurationRepairIfNeeded(after snapshot: PerchHAPanelSnapshot) {
        guard displayConfigurationRepairIsNeeded(after: snapshot) else {
            return
        }
        Task { @MainActor [weak self] in
            _ = self?.panelModel?.normalizeDisplayConfigurationForAvailableEntities()
        }
    }

    private func displayConfigurationRepairIsNeeded(after snapshot: PerchHAPanelSnapshot) -> Bool {
        guard !snapshot.availableRooms.isEmpty else {
            return false
        }
        let entitiesByID = Dictionary(
            uniqueKeysWithValues: snapshot.availableRooms.flatMap(\.entities).map { ($0.id, $0) }
        )
        var normalizedItems = snapshot.menuBarDisplayConfiguration.itemConfigurations.map { item in
            guard let entity = entitiesByID[item.entityID] else {
                return item
            }
            return EntityDisplayDefaults.normalizedConfiguration(for: entity, configuration: item)
        }
        let existingIDs = Set(normalizedItems.map(\.entityID))
        for promotedID in snapshot.menuBarDisplayConfiguration.promotedEntityIDs where !existingIDs.contains(promotedID) {
            guard let entity = entitiesByID[promotedID] else {
                continue
            }
            normalizedItems.append(EntityDisplayDefaults.configuration(for: entity))
        }
        let normalized = MenuBarDisplayConfiguration(
            promotedEntityIDs: snapshot.menuBarDisplayConfiguration.promotedEntityIDs,
            itemConfigurations: normalizedItems
        )
        return normalized != snapshot.menuBarDisplayConfiguration
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
            statusItemShowsLoadingIndicator: first?.showsLoadingIndicator ?? false,
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
            shellPersistenceFailureDescription: panelModel?.shellPersistenceFailureDescription,
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
        addresses: [PerchHAConnectionAddressField]? = nil,
        token: String? = nil,
        usesStoredAuthSession: Bool? = nil,
        allowsSelfSignedCertificates: Bool? = nil
    ) {
        panelModel?.updateConnectionForm(
            urlString: urlString,
            fallbackURLString: fallbackURLString,
            addresses: addresses,
            token: token,
            usesStoredAuthSession: usesStoredAuthSession,
            allowsSelfSignedCertificates: allowsSelfSignedCertificates
        )
    }

    private func forceStatusItemRefreshIfNeeded(after changed: Bool) {
        guard changed, let panelModel else {
            return
        }
        scheduleStatusItemRefresh(from: panelModel.snapshot, force: true)
    }

    public func connect() async {
        await panelModel?.connect()
        if let panelModel {
            scheduleStatusItemRefresh(from: panelModel.snapshot, force: true)
        }
    }

    /// Signs the user out, clearing the stored Keychain session while keeping the
    /// saved connection profile so the user can reconnect easily.
    public func signOut() {
        panelModel?.signOut()
    }

    private func clearStoredAuthSession() {
        do {
            _ = try authSessionStore?.clear()
            panelModel?.reportShellPersistenceFailure(nil)
        } catch {
            // A failed clear means the token is still in the Keychain even
            // though the user believes they signed out — that must be visible.
            panelModel?.reportShellPersistenceFailure(
                "Sign-out could not remove the stored session from the Keychain: \(error)"
            )
        }
    }

    public func startOAuthSignIn() async {
        await panelModel?.signInWithOAuth()
    }

    public func loadHistory(_ id: EntityID, range: HistoryRange) async {
        await panelModel?.loadHistory(id, range: range)
    }

    @discardableResult
    public func setEntityControl(_ id: EntityID, isOn: Bool) async -> Bool {
        let changed = await panelModel?.setEntityControl(id, isOn: isOn) ?? false
        forceStatusItemRefreshIfNeeded(after: changed)
        return changed
    }

    @discardableResult
    public func setCoverControl(_ id: EntityID, command: PerchHACoverCommand) async -> Bool {
        let changed = await panelModel?.setCoverControl(id, command: command) ?? false
        forceStatusItemRefreshIfNeeded(after: changed)
        return changed
    }

    @discardableResult
    public func setCoverPosition(_ id: EntityID, position: Int) async -> Bool {
        let changed = await panelModel?.setCoverPosition(id, position: position) ?? false
        forceStatusItemRefreshIfNeeded(after: changed)
        return changed
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
        let changed = panelModel?.applyLiveState(state) ?? false
        forceStatusItemRefreshIfNeeded(after: changed)
        return changed
    }

    @discardableResult
    public func setMenuBarEntity(_ id: EntityID, isVisible: Bool) -> Bool {
        let changed = panelModel?.setMenuBarEntity(id, isVisible: isVisible) ?? false
        if changed, let panelModel {
            scheduleStatusItemRefresh(from: panelModel.snapshot, force: true)
        }
        return changed
    }

    @discardableResult
    public func moveMenuBarEntity(_ id: EntityID, direction: SelectionMoveDirection) -> Bool {
        let changed = panelModel?.moveMenuBarEntity(id, direction: direction) ?? false
        forceStatusItemRefreshIfNeeded(after: changed)
        return changed
    }

    @discardableResult
    public func moveMenuBarEntity(_ id: EntityID, relativeTo targetID: EntityID, placement: SelectionDropPlacement) -> Bool {
        let changed = panelModel?.moveMenuBarEntity(id, relativeTo: targetID, placement: placement) ?? false
        forceStatusItemRefreshIfNeeded(after: changed)
        return changed
    }

    @discardableResult
    public func setMenuBarDisplayStyle(_ id: EntityID, style: MenuBarDisplayStyle) -> Bool {
        let changed = panelModel?.setMenuBarDisplayStyle(id, style: style) ?? false
        forceStatusItemRefreshIfNeeded(after: changed)
        return changed
    }

    @discardableResult
    public func setMenuBarShowsLabel(_ id: EntityID, showsLabel: Bool) -> Bool {
        let changed = panelModel?.setMenuBarShowsLabel(id, showsLabel: showsLabel) ?? false
        forceStatusItemRefreshIfNeeded(after: changed)
        return changed
    }

    @discardableResult
    public func setMenuBarAppearance(_ id: EntityID, appearance: PerchHAMenuBarAppearance?) -> Bool {
        let changed = panelModel?.setMenuBarAppearance(id, appearance: appearance) ?? false
        forceStatusItemRefreshIfNeeded(after: changed)
        return changed
    }

    @discardableResult
    public func setMenuBarShowsUnit(_ id: EntityID, showsUnit: Bool) -> Bool {
        let changed = panelModel?.setMenuBarShowsUnit(id, showsUnit: showsUnit) ?? false
        forceStatusItemRefreshIfNeeded(after: changed)
        return changed
    }

    @discardableResult
    public func setMenuBarMaximumFractionDigits(_ id: EntityID, maximumFractionDigits: Int) -> Bool {
        let changed = panelModel?.setMenuBarMaximumFractionDigits(id, maximumFractionDigits: maximumFractionDigits) ?? false
        forceStatusItemRefreshIfNeeded(after: changed)
        return changed
    }

    @discardableResult
    public func setMenuBarDefaultHistoryRange(_ id: EntityID, defaultHistoryRange: HistoryRange?) -> Bool {
        let changed = panelModel?.setMenuBarDefaultHistoryRange(id, defaultHistoryRange: defaultHistoryRange) ?? false
        forceStatusItemRefreshIfNeeded(after: changed)
        return changed
    }

    @discardableResult
    public func setMenuBarAbsoluteTotal(_ id: EntityID, total: Double?) -> Bool {
        let changed = panelModel?.setMenuBarAbsoluteTotal(id, total: total) ?? false
        forceStatusItemRefreshIfNeeded(after: changed)
        return changed
    }

    @discardableResult
    public func setMenuBarTotalEntityID(_ id: EntityID, totalEntityID: EntityID?) -> Bool {
        let changed = panelModel?.setMenuBarTotalEntityID(id, totalEntityID: totalEntityID) ?? false
        forceStatusItemRefreshIfNeeded(after: changed)
        return changed
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
        let changed = panelModel?.setMenuBarWarningThreshold(id, threshold: threshold) ?? false
        forceStatusItemRefreshIfNeeded(after: changed)
        return changed
    }

    @discardableResult
    public func setMenuBarCriticalThreshold(_ id: EntityID, threshold: ValueThreshold?) -> Bool {
        let changed = panelModel?.setMenuBarCriticalThreshold(id, threshold: threshold) ?? false
        forceStatusItemRefreshIfNeeded(after: changed)
        return changed
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

        let nextConfiguration = configuration.replacing(
            selectedEntityIDs: selection.selectedEntityIDs,
            roomOrder: selection.roomOrder,
            entityOrder: selection.entityOrder,
            isEntitySelectionExplicit: selection.isExplicit
        )
        let interval = performanceSignposter.beginInterval("PersistSelectionConfiguration")
        do {
            configuration = try configStore.save(nextConfiguration)
            configurationPersistenceState = .ready
            performanceSignposter.endInterval("PersistSelectionConfiguration", interval)
            return .saved
        } catch {
            let message = String(describing: error)
            configurationPersistenceState = .saveFailed(message)
            performanceSignposter.endInterval("PersistSelectionConfiguration", interval)
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

        let nextConfiguration = configuration.replacing(
            menuBarEntityIDs: displayConfiguration.promotedEntityIDs,
            menuBarItemConfigurations: displayConfiguration.itemConfigurations
        )
        let interval = performanceSignposter.beginInterval("PersistMenuBarDisplayConfiguration")
        do {
            configuration = try configStore.save(nextConfiguration)
            configurationPersistenceState = .ready
            performanceSignposter.endInterval("PersistMenuBarDisplayConfiguration", interval)
            return .saved
        } catch {
            let message = String(describing: error)
            configurationPersistenceState = .saveFailed(message)
            performanceSignposter.endInterval("PersistMenuBarDisplayConfiguration", interval)
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

        let nextConfiguration = configuration.replacing(
            customActions: customActionConfiguration.actions
        )
        let interval = performanceSignposter.beginInterval("PersistCustomActionConfiguration")
        do {
            configuration = try configStore.save(nextConfiguration)
            configurationPersistenceState = .ready
            performanceSignposter.endInterval("PersistCustomActionConfiguration", interval)
            return .saved
        } catch {
            let message = String(describing: error)
            configurationPersistenceState = .saveFailed(message)
            performanceSignposter.endInterval("PersistCustomActionConfiguration", interval)
            return .failed(message)
        }
    }

    /// Applies the persisted appearance preferences (theme override and accent
    /// color) to the running application and shared theme. Called at launch and
    /// after a display-preference change so the panel and settings reflect the
    /// choice immediately.
    private func applyAppearancePreferences() {
        NSApplication.shared.appearance = appearance(for: configuration.themeMode)
        PerchHATheme.apply(accentColor: configuration.accentColor)
    }

    private func appearance(for themeMode: PerchHAThemeMode) -> NSAppearance? {
        switch themeMode {
        case .system:
            nil
        case .light:
            NSAppearance(named: .aqua)
        case .dark:
            NSAppearance(named: .darkAqua)
        }
    }

    /// The current display preferences exposed for the Settings UI bindings.
    public var displayPreferences: PerchHADisplayPreferences {
        configuration.displayPreferences
    }

    /// Persists updated display preferences, re-applies theme/accent, and
    /// re-renders the live menu-bar items so appearance changes take effect at
    /// once.
    ///
    /// - Parameter preferences: The new display preferences.
    /// - Returns: The persistence outcome (`.saved`, `.failed`, or unavailable).
    @discardableResult
    public func persist(displayPreferences preferences: PerchHADisplayPreferences) -> SelectionPersistenceResult {
        guard let configStore else {
            configurationPersistenceState = .unavailable
            return .failed("configuration store unavailable")
        }
        if case let .loadFailed(message) = configurationPersistenceState {
            return .failed("configuration load failed; save blocked: \(message)")
        }

        let nextConfiguration = configuration.applying(displayPreferences: preferences)
        let interval = performanceSignposter.beginInterval("PersistDisplayPreferences")
        do {
            configuration = try configStore.save(nextConfiguration)
            configurationPersistenceState = .ready
            applyAppearancePreferences()
            if let panelModel {
                panelModel.applyDisplayPreferences(preferences)
                scheduleStatusItemRefresh(from: panelModel.snapshot, force: true)
            }
            performanceSignposter.endInterval("PersistDisplayPreferences", interval)
            return .saved
        } catch {
            let message = String(describing: error)
            configurationPersistenceState = .saveFailed(message)
            performanceSignposter.endInterval("PersistDisplayPreferences", interval)
            return .failed(message)
        }
    }

    /// Whether the app is currently registered to launch at login.
    ///
    /// Returns `false` when the login-item service is unavailable or in any
    /// non-enabled status, so the toggle reflects the live `SMAppService` state.
    public var launchesAtLogin: Bool {
        SMAppService.mainApp.status == .enabled
    }

    /// Registers or unregisters the app as a login item via `SMAppService`.
    ///
    /// - Parameter enabled: `true` to register the app to launch at login,
    ///   `false` to unregister it.
    /// - Returns: `true` when the requested state was reached (or already in
    ///   effect), `false` when the service threw or the resulting status did not
    ///   match the request. Never crashes on failure.
    @discardableResult
    public func setLaunchAtLogin(_ enabled: Bool) -> Bool {
        do {
            if enabled {
                if SMAppService.mainApp.status != .enabled {
                    try SMAppService.mainApp.register()
                }
            } else {
                if SMAppService.mainApp.status == .enabled {
                    try SMAppService.mainApp.unregister()
                }
            }
            return launchesAtLogin == enabled
        } catch {
            return false
        }
    }

    public static func makePanel(
        model: PerchHAPanelModel,
        onOpenSettings: (() -> Void)? = nil,
        onOpenEntitySettings: ((EntityID) -> Void)? = nil
    ) -> NSPanel {
        let panel = PerchHAStatusPanel(
            contentRect: NSRect(origin: .zero, size: AppShellLayout.panelContentSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        // A borderless, transparent host: the SwiftUI root paints the rounded
        // dashboard surface, clips to it, and provides the soft shadow, so the
        // window contributes no titlebar, traffic lights, or opaque frame.
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = true
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        let hostingController = PerchHAFirstMouseHostingController(
            rootView: PerchHAPanelView(
                model: model,
                onOpenSettings: onOpenSettings,
                onOpenEntitySettings: onOpenEntitySettings
            )
        )
        hostingController.view.wantsLayer = true
        hostingController.view.layer?.backgroundColor = NSColor.clear.cgColor
        panel.contentViewController = hostingController
        // Route the panel-local Cmd+, shortcut to the same open-settings path.
        panel.onOpenSettings = onOpenSettings
        // Gate background work on real window visibility so every dismissal
        // path — Escape, click-away auto-hide, status-item toggle — stops the
        // model's sync loops, not just the explicit toggle.
        panel.onVisibilityChange = { [weak model] visible in
            model?.setPanelActive(visible)
        }
        panel.onScrollWheelEvent = { [weak model] in
            model?.notePanelScrollActivity()
        }
        // Size to the fixed SwiftUI content so the borderless window matches the
        // rounded surface exactly (no chrome inset). The root paints at this size.
        panel.setContentSize(AppShellLayout.panelContentSize)
        return panel
    }

    /// Builds the resizable Settings window hosting the SwiftUI settings tree.
    ///
    /// - Parameters:
    ///   - model: The shared panel model driving the settings controls.
    ///   - initialTab: The tab selected when the window first appears.
    ///   - initiallyExpandedEntityIDs: Entity rows in the Entities tab whose
    ///     per-entity configuration should be disclosed on first render. Empty
    ///     by default; supplied by tests to reveal a specific entity's controls.
    /// - Returns: A configured, non-visible `NSWindow`.
    public static func makeSettingsWindow(
        model: PerchHAPanelModel,
        initialTab: PerchHASettingsView.Tab = .connection,
        initiallyExpandedEntityIDs: Set<EntityID> = [],
        displayPreferencesProvider: @escaping () -> PerchHADisplayPreferences = { .defaults },
        displayPreferencesSink: @escaping (PerchHADisplayPreferences) -> Void = { _ in },
        launchAtLoginProvider: @escaping () -> Bool = { false },
        launchAtLoginSink: @escaping (Bool) -> Bool = { _ in false }
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
        window.contentViewController = PerchHAFirstMouseHostingController(
            rootView: PerchHASettingsView(
                model: model,
                initialTab: initialTab,
                initiallyExpandedEntityIDs: initiallyExpandedEntityIDs,
                displayPreferencesProvider: displayPreferencesProvider,
                displayPreferencesSink: displayPreferencesSink,
                launchAtLoginProvider: launchAtLoginProvider,
                launchAtLoginSink: launchAtLoginSink
            )
        )
        window.setContentSize(AppShellLayout.settingsMinContentSize)
        return window
    }

    private func openSettingsWindow(
        initialTab: PerchHASettingsView.Tab = .connection,
        initiallyExpandedEntityIDs: Set<EntityID> = []
    ) {
        guard let panelModel else {
            return
        }
        panelModel.dismissHistoryPopover()
        // Opening Settings dismisses the drop-down panel so the two windows do
        // not overlap.
        panel?.orderOut(nil)
        panelModel.setPanelActive(false)
        let window = settingsWindow ?? Self.makeSettingsWindow(
            model: panelModel,
            initialTab: initialTab,
            initiallyExpandedEntityIDs: initiallyExpandedEntityIDs,
            displayPreferencesProvider: { [weak self] in
                self?.displayPreferences ?? .defaults
            },
            displayPreferencesSink: { [weak self] preferences in
                self?.persist(displayPreferences: preferences)
            },
            launchAtLoginProvider: { [weak self] in
                self?.launchesAtLogin ?? false
            },
            launchAtLoginSink: { [weak self] enabled in
                self?.setLaunchAtLogin(enabled) ?? false
            }
        )
        if settingsWindow != nil {
            window.contentViewController = PerchHAFirstMouseHostingController(
                rootView: PerchHASettingsView(
                    model: panelModel,
                    initialTab: initialTab,
                    initiallyExpandedEntityIDs: initiallyExpandedEntityIDs,
                    displayPreferencesProvider: { [weak self] in
                        self?.displayPreferences ?? .defaults
                    },
                    displayPreferencesSink: { [weak self] preferences in
                        self?.persist(displayPreferences: preferences)
                    },
                    launchAtLoginProvider: { [weak self] in
                        self?.launchesAtLogin ?? false
                    },
                    launchAtLoginSink: { [weak self] enabled in
                        self?.setLaunchAtLogin(enabled) ?? false
                    }
                )
            )
        }
        settingsWindow = window
        if settingsWindowCloseObserver == nil {
            settingsWindowCloseObserver = NotificationCenter.default.addObserver(
                forName: NSWindow.willCloseNotification,
                object: window,
                queue: .main
            ) { [weak self] _ in
                // Back to a pure menu-bar presence once Settings closes.
                Task { @MainActor in
                    NSApp.setActivationPolicy(.accessory)
                    guard let self else {
                        return
                    }
                    self.settingsWindow?.contentViewController = nil
                    self.settingsWindow = nil
                    if let observer = self.settingsWindowCloseObserver {
                        NotificationCenter.default.removeObserver(observer)
                        self.settingsWindowCloseObserver = nil
                    }
                }
            }
        }
        if !window.isVisible {
            window.center()
        }
        // Settings is a real document-style window: give the app a Dock icon
        // and app switcher presence while it is open.
        NSApp.setActivationPolicy(.regular)
        // The Dock tile is built when the app turns regular; an icon set while
        // the app was still an accessory does not reliably survive the switch,
        // so it is (re)applied here every time.
        Self.applyPearchApplicationIcon()
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    /// Applies the bundled Pearch mark as the application icon for unbundled
    /// (SwiftPM dev) runs, where AppKit would otherwise show the generic
    /// executable icon in the Dock and the About panel. Bundled builds carry
    /// the icon through Info.plist and are left untouched.
    private static func applyPearchApplicationIcon() {
        guard Bundle.main.bundleURL.pathExtension != "app",
              let icon = pearchApplicationIcon()
        else {
            return
        }
        NSApp.applicationIconImage = icon
        NSApp.dockTile.display()
    }

    /// The bundled Pearch application icon loaded from the module resources.
    ///
    /// - Returns: The icon image, or `nil` when the resource is unavailable.
    public static func pearchApplicationIcon() -> NSImage? {
        guard let iconURL = Bundle.module.url(forResource: "PearchHA", withExtension: "icns") else {
            return nil
        }
        return NSImage(contentsOf: iconURL)
    }

    // TODO: A system-wide global hotkey to toggle the panel from any app is
    // intentionally not implemented. Doing so cleanly requires either Carbon's
    // `RegisterEventHotKey` (a deprecated, low-level C API that is fiddly to
    // unregister safely) or the Accessibility/Input-Monitoring permission with a
    // `CGEventTap` (which prompts the user for a sensitive system permission and
    // is overkill for a menu-bar utility). A third-party dependency
    // (e.g. KeyboardShortcuts) would also solve it but is disallowed here. Until
    // one of those trade-offs is accepted, only the panel-local Cmd+, and Escape
    // shortcuts are supported; the status-item click below toggles the panel.
    @objc private func togglePanel(_ sender: NSStatusBarButton) {
        guard let panel else {
            return
        }
        panelModel?.dismissHistoryPopover()
        if panel.isVisible {
            panel.orderOut(sender)
            panelModel?.setPanelActive(false)
            return
        }

        position(panel: panel, relativeTo: sender)
        panel.makeKeyAndOrderFront(sender)
        panelModel?.setPanelActive(true)
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
        let anchorY = max(buttonFrame.minY, window.frame.minY)
        let y = anchorY - size.height + 2
        panel.setFrameOrigin(NSPoint(x: x, y: max(y, screenFrame.minY + 8)))
    }

    private func releaseShell() {
        statusItemRefreshTask?.cancel()
        statusItemRefreshTask = nil
        pendingStatusItemSnapshot = nil
        lastStatusItemRefreshAt = nil
        autoConnectTask?.cancel()
        autoConnectTask = nil
        panelModel?.cancelInFlightAction()
        panelModel?.setPanelActive(false)
        panel?.orderOut(nil)
        panel?.contentViewController = nil
        panel = nil
        settingsWindow?.orderOut(nil)
        settingsWindow?.contentViewController = nil
        settingsWindow = nil
        if let settingsWindowCloseObserver {
            NotificationCenter.default.removeObserver(settingsWindowCloseObserver)
            self.settingsWindowCloseObserver = nil
        }
        panelModel = nil

        for entry in statusItems {
            NSStatusBar.system.removeStatusItem(entry.item)
        }
        statusItems = []
    }

    private func scheduleStatusItemRefresh(
        from snapshot: PerchHAPanelSnapshot,
        force: Bool = false
    ) {
        pendingStatusItemSnapshot = snapshot
        let interval = displayPreferences.menuBarRefreshInterval.timeInterval
        let now = Date()
        let lastRefreshAt = lastStatusItemRefreshAt ?? .distantPast
        let elapsed = now.timeIntervalSince(lastRefreshAt)

        if force || elapsed >= interval {
            flushScheduledStatusItemRefresh()
            return
        }

        guard statusItemRefreshTask == nil else {
            return
        }

        let remaining = max(0, interval - elapsed)
        statusItemRefreshTask = Task { [weak self] in
            let duration = UInt64((remaining * 1_000_000_000).rounded())
            if duration > 0 {
                try? await Task.sleep(nanoseconds: duration)
            }
            await MainActor.run {
                guard let self else {
                    return
                }
                self.statusItemRefreshTask = nil
                self.flushScheduledStatusItemRefresh()
            }
        }
    }

    private func flushScheduledStatusItemRefresh() {
        statusItemRefreshTask?.cancel()
        statusItemRefreshTask = nil
        guard let snapshot = pendingStatusItemSnapshot else {
            return
        }
        pendingStatusItemSnapshot = nil
        lastStatusItemRefreshAt = Date()
        updateStatusItems(from: snapshot)
    }

    /// Reconciles the live menu-bar status items against the presenter output:
    /// one item per promoted entity (in order), or a single fallback fish-logo
    /// item when nothing is promoted. Creates, updates, and removes items in
    /// place so each item keeps the same toggle target/action and a per-entity
    /// image cache, preserving gauge-redraw throttling.
    private func updateStatusItems(from snapshot: PerchHAPanelSnapshot) {
        let interval = performanceSignposter.beginInterval("UpdateStatusItems")
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
            if statusItems[index].presentation == presentation,
               statusItemAlreadyRendered(statusItems[index]) {
                updateLoadingIndicator(
                    shouldShow: index == 0 && shouldShowStatusItemLoadingIndicator(for: snapshot),
                    for: &statusItems[index]
                )
                continue
            }
            apply(presentation, to: &statusItems[index])
            updateLoadingIndicator(
                shouldShow: index == 0 && shouldShowStatusItemLoadingIndicator(for: snapshot),
                for: &statusItems[index]
            )
        }

        if presentations.isEmpty == false {
            for index in presentations.count..<statusItems.count {
                updateLoadingIndicator(shouldShow: false, for: &statusItems[index])
            }
        }
        performanceSignposter.endInterval("UpdateStatusItems", interval)
    }

    private func statusItemAlreadyRendered(_ entry: PerchHAStatusItemEntry) -> Bool {
        guard let button = entry.item.button else {
            return false
        }
        return button.image != nil
            || !button.title.isEmpty
            || !button.attributedTitle.string.isEmpty
            || entry.loadingIndicator != nil
    }

    private func makeStatusItem() -> NSStatusItem {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.target = self
        item.button?.action = #selector(togglePanel(_:))
        item.button?.sendAction(on: [.leftMouseDown])
        return item
    }

    private func apply(_ presentation: PerchHAMenuBarPresentation, to entry: inout PerchHAStatusItemEntry) {
        var image: NSImage?
        var title: String
        if let renderedItem = presentation.renderedItem,
           renderedItem.gauge != nil || renderedItem.value.iconSymbolName != nil {
            image = cachedStatusItemImage(for: renderedItem, in: &entry)
            // Icon units carry the value in the glyph, so the title is dropped.
            title = renderedItem.value.iconSymbolName != nil ? "" : presentation.statusItemTitle
        } else if let iconSymbolName = presentation.iconSymbolName {
            // The per-entity "Show icon" option: a template SF Symbol beside
            // (or instead of, per the resolved appearance) the value text.
            entry.imageCache = nil
            image = NSImage(
                systemSymbolName: iconSymbolName,
                accessibilityDescription: presentation.accessibilityLabel
            )
            image?.isTemplate = true
            title = presentation.statusItemTitle
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

        // The fallback (fish-logo) item always keeps its glyph; only promoted
        // value items honor the resolved (per-entity, else global) icon-only /
        // text-only appearance.
        if presentation != .fallback {
            if !presentation.showsImage {
                entry.imageCache = nil
                image = nil
            }
            if !presentation.showsTitle {
                title = ""
            }
            // Never let a promoted item collapse to a zero-width, invisible
            // status item: if the resolved appearance left it with no image and
            // no title, fall back to a short visible title (value text, entity
            // name, or abbreviation) so every promoted entity stays visible.
            if image == nil && title.isEmpty {
                title = presentation.visibleFallbackTitle
            }
        }

        entry.presentation = presentation
        let button = entry.item.button
        button?.image = image
        button?.imagePosition = image == nil ? .noImage : .imageLeading
        // The stacked (label-above-value) style only replaces a full title; the
        // empty title and the visibility fallback keep their plain rendering.
        if let stackedLabel = presentation.stackedLabel,
           title == presentation.statusItemTitle,
           let valueText = presentation.renderedItem?.value.text,
           !valueText.isEmpty {
            applyStackedTitle(label: stackedLabel, value: valueText, to: button)
        } else {
            applyTitle(title, to: button, stableWidth: configuration.stableMenuBarWidth)
        }
        button?.toolTip = presentation.accessibilityLabel
        button?.setAccessibilityLabel(presentation.accessibilityLabel)
    }

    private func shouldShowStatusItemLoadingIndicator(for snapshot: PerchHAPanelSnapshot) -> Bool {
        switch snapshot.phase {
        case .connecting:
            true
        case .firstRun:
            snapshot.connectionForm.primaryURL() != nil
                && snapshot.connectionForm.usesStoredAuthSession
                && snapshot.availableRooms.isEmpty
        case .connectedEmpty, .connectedData, .reconnecting, .failed, .failedStale:
            false
        }
    }

    private func updateLoadingIndicator(
        shouldShow: Bool,
        for entry: inout PerchHAStatusItemEntry
    ) {
        guard let button = entry.item.button else {
            return
        }
        if shouldShow {
            let indicator = entry.loadingIndicator ?? makeStatusItemLoadingIndicator()
            if indicator.superview !== button {
                button.addSubview(indicator)
            }
            entry.loadingIndicator = indicator
            button.image = nil
            button.imagePosition = .noImage
            button.title = ""
            button.attributedTitle = NSAttributedString(string: "")
            button.toolTip = "PearchHA is starting"
            button.setAccessibilityLabel("PearchHA is starting")
            positionLoadingIndicator(indicator, in: button)
            indicator.startAnimation(nil)
            return
        }

        entry.loadingIndicator?.stopAnimation(nil)
        entry.loadingIndicator?.removeFromSuperview()
        entry.loadingIndicator = nil
    }

    private func makeStatusItemLoadingIndicator() -> NSProgressIndicator {
        let indicator = NSProgressIndicator(frame: NSRect(x: 0, y: 0, width: 14, height: 14))
        indicator.style = .spinning
        indicator.controlSize = .small
        indicator.isDisplayedWhenStopped = false
        indicator.usesThreadedAnimation = false
        return indicator
    }

    private func positionLoadingIndicator(_ indicator: NSProgressIndicator, in button: NSStatusBarButton) {
        indicator.sizeToFit()
        let frame = indicator.frame
        indicator.frame = NSRect(
            x: floor((button.bounds.width - frame.width) / 2),
            y: floor((button.bounds.height - frame.height) / 2),
            width: frame.width,
            height: frame.height
        )
        indicator.autoresizingMask = [
            .minXMargin,
            .maxXMargin,
            .minYMargin,
            .maxYMargin
        ]
    }

    /// Sets a two-line status-item title in the iStat Menus stacked style: a
    /// tiny tracked caps label above a monospaced-digit value, centered, sized
    /// so both lines fit the standard menu-bar height.
    private func applyStackedTitle(label: String, value: String, to button: NSStatusBarButton?) {
        guard let button else {
            return
        }
        let labelParagraph = NSMutableParagraphStyle()
        labelParagraph.alignment = .center
        labelParagraph.minimumLineHeight = 8
        labelParagraph.maximumLineHeight = 8
        let valueParagraph = NSMutableParagraphStyle()
        valueParagraph.alignment = .center
        valueParagraph.minimumLineHeight = 11
        valueParagraph.maximumLineHeight = 11
        let title = NSMutableAttributedString(
            string: label.uppercased() + "\n",
            attributes: [
                .font: NSFont.systemFont(ofSize: 7.5, weight: .medium),
                .kern: 0.4,
                .paragraphStyle: labelParagraph
            ]
        )
        title.append(NSAttributedString(
            string: value,
            attributes: [
                .font: NSFont.monospacedDigitSystemFont(ofSize: 10.5, weight: .medium),
                .paragraphStyle: valueParagraph
            ]
        ))
        button.attributedTitle = title
    }

    /// Sets the status-item button title, optionally as a monospaced-digit
    /// attributed title so the value does not jitter horizontally as it changes.
    ///
    /// When `stableWidth` is on, the title is rendered with the menu-bar font at a
    /// monospaced-digit variant; otherwise the plain title is used, matching the
    /// historic behavior.
    private func applyTitle(_ title: String, to button: NSStatusBarButton?, stableWidth: Bool) {
        guard let button else {
            return
        }
        guard stableWidth, !title.isEmpty else {
            button.attributedTitle = NSAttributedString(string: "")
            button.title = title
            return
        }
        let baseFont = button.font ?? NSFont.menuBarFont(ofSize: 0)
        let monospacedFont = NSFont.monospacedDigitSystemFont(
            ofSize: baseFont.pointSize,
            weight: .regular
        )
        button.attributedTitle = NSAttributedString(
            string: title,
            attributes: [.font: monospacedFont]
        )
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
        let title = {
            let plain = button?.title ?? ""
            if plain.isEmpty == false {
                return plain
            }
            let attributed = button?.attributedTitle.string ?? ""
            return attributed
        }()
        let showsLoadingIndicator = button?.subviews.contains(where: {
            guard let indicator = $0 as? NSProgressIndicator else {
                return false
            }
            return indicator.isHidden == false
        }) ?? false
        return PerchHAMenuBarStatusItemSnapshot(
            title: title,
            accessibilityLabel: button?.accessibilityLabel(),
            hasImage: button?.image != nil,
            showsLoadingIndicator: showsLoadingIndicator,
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
        // Outside a real .app bundle (bare SwiftPM executable, tests) AppKit
        // reports the generic executable document icon — that is what used to
        // replace the Pearch logo in the menu bar. Only trust the icon when a
        // bundled app actually provides one.
        guard Bundle.main.bundleURL.pathExtension == "app" else {
            return nil
        }
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
        let profileAddresses = profile?.addresses ?? []
        let primaryURLString = profileAddresses.first?.urlString ?? ""
        let alternativeFields = profileAddresses.dropFirst().map { address in
            PerchHAConnectionAddressField(label: address.label, urlString: address.urlString)
        }
        return PerchHAConnectionForm(
            urlString: primaryURLString,
            addresses: Array(alternativeFields),
            token: "",
            usesStoredAuthSession: usesStoredAuthSession,
            allowsSelfSignedCertificates: profile?.allowsSelfSignedCertificates ?? true
        )
    }

    private func rememberConnection(_ form: PerchHAConnectionForm) {
        if !form.trimmedToken.isEmpty {
            rememberAccessToken(form.trimmedToken)
        }
        guard let configStore else {
            panelModel?.reportShellPersistenceFailure(
                "Settings cannot be saved: the configuration store is unavailable."
            )
            return
        }
        if case .loadFailed = configurationPersistenceState {
            return
        }
        let nextConfiguration = configuration.replacing(
            connectionProfile: PerchHAConnectionProfile(
                addresses: [
                    PerchHAConnectionAddress(
                        urlString: PerchHAConnectionForm.normalizedHomeAssistantURLString(form.urlString)
                    )
                ] + form.addresses.map { address in
                    PerchHAConnectionAddress(
                        label: address.label,
                        urlString: PerchHAConnectionForm.normalizedHomeAssistantURLString(address.urlString)
                    )
                },
                allowsSelfSignedCertificates: form.allowsSelfSignedCertificates
            )
        )
        do {
            configuration = try configStore.save(nextConfiguration)
            configurationPersistenceState = .ready
        } catch {
            configurationPersistenceState = .saveFailed(String(describing: error))
        }
    }

    private func rememberAccessToken(_ token: String) {
        guard let authSessionStore else {
            return
        }
        do {
            _ = try authSessionStore.saveAccessToken(token)
            panelModel?.reportShellPersistenceFailure(nil)
        } catch {
            // Losing this write silently would make the user re-enter the
            // token on every launch with no explanation.
            panelModel?.reportShellPersistenceFailure(
                "Could not remember the session in the Keychain: \(error)"
            )
        }
    }

    private func rememberAttemptedManualToken(_ form: PerchHAConnectionForm) {
        rememberAccessToken(form.trimmedToken)
    }

    private func shouldRememberAttemptedManualToken(
        form: PerchHAConnectionForm,
        result: PerchHAConnectionAttemptResult
    ) -> Bool {
        guard !form.usesStoredAuthSession,
              !form.trimmedToken.isEmpty,
              let authSessionStore
        else {
            return false
        }
        guard case let .failure(failure) = result,
              failure != .authentication
        else {
            return false
        }
        return (try? authSessionStore.loadAccessToken()) == nil
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
    weak var loadingIndicator: NSProgressIndicator?
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
