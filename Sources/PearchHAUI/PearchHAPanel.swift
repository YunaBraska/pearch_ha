import Foundation
import AppKit
import Combine
import OSLog
import SwiftUI
import UniformTypeIdentifiers
import PearchHACore
import PearchHASupport

@MainActor
public final class PearchHAPanelModel: ObservableObject {
    public typealias Connector = @Sendable (PearchHAConnectionForm) async -> PearchHAConnectionAttemptResult
    public typealias HistoryProvider = @Sendable (PearchHAConnectionForm, EntityID, HistoryRange) async -> PearchHAHistoryProviderResult
    /// Fetches history for many entities sharing a range in as few requests as
    /// possible. Used only by the background bulk sync loop (never by hover/detail).
    /// Returns a series per entity that came back; missing/failed entities are
    /// simply absent. Must never carry or leak a token.
    public typealias BulkHistoryProvider = @Sendable (PearchHAConnectionForm, [EntityID], HistoryRange) async -> [EntityID: HistorySeries]
    public typealias ServiceMetadataProvider = @Sendable (PearchHAConnectionForm) async -> PearchHAServiceMetadataProviderResult
    /// Opens one live update stream for the connection and delivers each pushed
    /// entity state through the handler. Returns only when the stream ends,
    /// with the failure that ended it. Must never carry or leak a token.
    public typealias LiveUpdateStreamer = @Sendable (
        PearchHAConnectionForm,
        @escaping @Sendable (EntityState) async -> Void
    ) async -> ConnectionFailure
    public typealias ActionRunner = @Sendable (PearchHAConnectionForm, ActionSpec) async -> PearchHAActionResult
    public typealias OAuthSignInRunner = @MainActor @Sendable (PearchHAConnectionForm) async -> PearchHAOAuthSignInResult
    public typealias ReleaseUpdateChecker = @Sendable (String) async -> PearchHAReleaseUpdateCheckResult
    public typealias SelectionConfigurationSink = @MainActor (EntitySelectionConfiguration) -> SelectionPersistenceResult
    public typealias MenuBarDisplayConfigurationSink = @MainActor (MenuBarDisplayConfiguration) -> SelectionPersistenceResult
    public typealias CustomActionConfigurationSink = @MainActor (CustomActionConfiguration) -> SelectionPersistenceResult
    public typealias SnapshotSink = @MainActor (PearchHAPanelSnapshot, Bool) -> Void
    /// Clears the persisted authentication session when the user signs out.
    public typealias SignOutHandler = @MainActor () -> Void

    @Published public private(set) var snapshot: PearchHAPanelSnapshot {
        didSet {
            rebuildAvailableEntityCaches(from: snapshot.availableRooms)
            if oldValue.rooms != snapshot.rooms
                || oldValue.availableRooms != snapshot.availableRooms
                || oldValue.menuBarDisplayConfiguration != snapshot.menuBarDisplayConfiguration
                || oldValue.valuesAreStale != snapshot.valuesAreStale {
                invalidateAllDisplayCaches()
            } else if oldValue.connectionState != snapshot.connectionState {
                formattedValueCache.removeAll(keepingCapacity: true)
            }
            // Menu-bar configuration edits and connection-phase transitions
            // affect visible shell state immediately (for example the launch
            // spinner and its removal), so those updates bypass the passive
            // refresh interval instead of waiting for the next throttle window.
            let forceStatusItemRefresh =
                oldValue.menuBarDisplayConfiguration != snapshot.menuBarDisplayConfiguration
                || oldValue.phase != snapshot.phase
            snapshotSink(snapshot, forceStatusItemRefresh)
            refreshRetryBackoffState()
            if oldValue.availableRooms != snapshot.availableRooms
                || oldValue.selectionConfiguration != snapshot.selectionConfiguration
                || oldValue.selectionQuery != snapshot.selectionQuery {
                refreshSettingsSelectionTreeIfNeeded(newSnapshot: snapshot)
            }
        }
    }

    /// The Settings Entities tree, recomputed only when the snapshot changes.
    /// The projection filters and orders every room and entity; computing it
    /// once per snapshot instead of several times per body evaluation is what
    /// keeps the Entities tab responsive on large installs.
    @Published public private(set) var settingsSelectionTree: [SelectableRoom] = []
    @Published public private(set) var customActionConfiguration: CustomActionConfiguration
    @Published public private(set) var customActionPersistenceFailureDescription: String?
    /// A persistence problem reported by the app shell that the user must see:
    /// the Keychain refused the remembered session, sign-out could not clear
    /// the stored token, or the configuration store is unavailable. `nil` when
    /// shell persistence is healthy. Never carries a secret.
    @Published public private(set) var shellPersistenceFailureDescription: String?
    @Published public private(set) var oauthSignInState = PearchHAOAuthSignInState.idle
    @Published public private(set) var releaseUpdateState = PearchHAReleaseUpdateState.idle

    /// The live dashboard display preferences the panel honors (row density,
    /// default history range, footer timestamp, hidden modules).
    ///
    /// Pushed in from the app shell whenever the user changes a Dashboard
    /// setting so the open panel re-renders at once; the snapshot itself is
    /// unaffected. Settings are the source of truth for persistence.
    @Published public private(set) var displayPreferences: PearchHADisplayPreferences = .defaults

    /// A monotonically increasing token bumped on history data or request changes
    /// (request start/finish, preview refresh or detail load, and eviction).
    ///
    /// Inline-row previews read ``cachedHistorySeries(for:)``, which peeks the
    /// cache without itself being observable. Reading this published token in the
    /// same view makes SwiftUI re-evaluate the affected rows the moment new
    /// history lands, so a refreshed sparkline appears immediately rather
    /// than waiting for an unrelated snapshot change. The token is a cheap counter,
    /// not the series data, so the existing chart redraw throttling is unaffected.
    @Published public private(set) var historyRevision = 0

    /// The first history request is pending. Empty results and failures also
    /// complete this initial presentation, while later refreshes stay inline.
    @Published private(set) var isInitialHistoryLoading = false

    /// The deduplicated ring buffer of real diagnostic events (connection
    /// failures, reconnect attempts, recoveries, and periodic-refresh failures),
    /// recorded at the points where those transitions actually occur.
    ///
    /// Capped and consecutive-deduplicated, so it stays cheap and never floods.
    /// Messages are always sanitized failure/transition descriptions — no token
    /// or secret is ever recorded. Surfaced read-only in Settings → Diagnostics.
    @Published public private(set) var diagnosticEvents: [PearchHADiagnosticEvent] = []

    /// The current retry/backoff posture derived purely from the live connection
    /// state and the periodic-refresh backoff streak. Drives the Diagnostics
    /// "retry / backoff" line. Never carries a secret.
    @Published public private(set) var retryBackoffState: PearchHARetryBackoffState = .disconnected

    /// The most recent instant observed from the injected clock, used by the
    /// Diagnostics view to render each event's age relative to "now" without
    /// reaching for wall-clock time.
    @Published public private(set) var diagnosticsReferenceInstant = PearchInstant(nanosecondsSinceStart: 0)

    private let connector: Connector
    private let historyProvider: HistoryProvider
    private let bulkHistoryProvider: BulkHistoryProvider
    private let serviceMetadataProvider: ServiceMetadataProvider
    private let liveUpdateStreamer: LiveUpdateStreamer?
    private let liveUpdateConfiguration: PearchHALiveUpdateConfiguration
    /// Supplies the wall-clock time stamped into the footer's "Updated at"
    /// caption. Injectable so tests stay deterministic.
    private let wallClock: @Sendable () -> Date
    private let actionRunner: ActionRunner
    private let oauthSignInRunner: OAuthSignInRunner
    private let releaseUpdateChecker: ReleaseUpdateChecker
    private let currentApplicationVersionProvider: @Sendable () -> String
    let clock: any PearchClock
    private let historyDebounce: PearchDuration
    private let historyCacheConfiguration: PearchHAHistoryCacheConfiguration
    private let bulkSyncConfiguration: PearchHAHistoryBulkSyncConfiguration
    private let periodicRefreshConfiguration: PearchHAPeriodicRefreshConfiguration
    private let selectionSink: SelectionConfigurationSink
    private let menuBarDisplaySink: MenuBarDisplayConfigurationSink
    private let customActionSink: CustomActionConfigurationSink
    private let protectedActionValueStore: any ProtectedActionValueStore
    private let snapshotSink: SnapshotSink
    private let signOutHandler: SignOutHandler
    private static let inlineSparklineSampleBudget = 48
    private let performanceSignposter = OSSignposter(
        logger: Logger(subsystem: "dev.yuna.pearchha", category: "Performance")
    )
    private var settingsSelectionTreeSignature: SettingsSelectionTreeSignature
    private var availableEntityIndexSignature = AvailableEntityIndexSignature(rooms: [])
    private var availableEntityLocations: [EntityID: AvailableEntityLocation] = [:]
    private var availableEntitiesByID: [EntityID: DiscoveredEntity] = [:]
    private var availableEntities: [DiscoveredEntity] = []
    private var averageCandidateCache: [EntityID: [DiscoveredEntity]] = [:]
    private var displayedEntityCache: [EntityID: DiscoveredEntity] = [:]
    private var formattedValueCache: [FormattedEntityValueCacheKey: FormattedEntityValue] = [:]
    private var rowPresentationCache: [EntityID: PearchHAEntityRowPresentation] = [:]
    private var inlineSparklineGeometryCache: [PearchHAHistoryCacheKey: PearchHAHistorySparklineGeometry?] = [:]
    private var historyRevisionSubjects: [EntityID: CurrentValueSubject<UInt64, Never>] = [:]
    private var historyCache = PearchHAHistoryCache()
    private var hasCompletedInitialHistoryLoad = false
    private var lastObservedInstant = PearchInstant(nanosecondsSinceStart: 0)
    private var lastConnectedForm: PearchHAConnectionForm?
    private var editableForm: PearchHAConnectionForm
    private var actionTask: Task<Void, Never>?
    private var controlActionTask: Task<Void, Never>?
    private var activeValueControlRequestID: UUID?
    private var pendingControlChange: PendingControlChange?
    private struct RequestedControlValue: Equatable {
        let requestID: UUID
        let value: ActionValue
    }
    /// Presentation only. A request is retired by the next report, not by service acceptance.
    @Published private var requestedControlValues: [EntityID: [String: RequestedControlValue]] = [:]
    private var historyTask: Task<Void, Never>?
    private var historyRequestGeneration = 0
    private var transientUITrackingDepth = 0
    private var deferredLiveStates: [EntityID: (state: EntityState, requests: [String: RequestedControlValue])] = [:]
    private var deferredBackgroundLiveStates: [EntityID: (state: EntityState, requests: [String: RequestedControlValue])] = [:]
    private var deferredSilentRefreshRequested = false
    private var protectedValueDrafts: [String: String] = [:]
    /// Whether the panel is currently shown, gating detail refresh and live updates.
    /// Set through ``setPanelActive(_:)``; readable so the app shell's
    /// window-visibility wiring can be verified through the public boundary.
    public private(set) var isPanelActive = false
    /// The single re-arming history loop for selected daily previews and open detail.
    private var bulkSyncTask: Task<Void, Never>?
    /// Tokens prevent detail loads and bulk batches from fetching the same key
    /// concurrently, including across cancellation and connection changes.
    private var historyRequests: [PearchHAHistoryCacheKey: UUID] = [:]
    private var historyRequestWaiters: [PearchHAHistoryCacheKey: [CheckedContinuation<Void, Never>]] = [:]
    private var historySyncNeedsReschedule = false
    private var periodicRefreshTask: Task<Void, Never>?
    private var periodicRefreshFailureStreak = 0
    /// The single long-lived live update loop. Runs only while the panel is
    /// visible and live updates are enabled.
    private var liveUpdateTask: Task<Void, Never>?
    private var diagnosticLog = PearchHADiagnosticLog()
    /// Whether a connection/refresh failure has been recorded since the last
    /// successful connection. Gates the `.recovered` event so a routine
    /// successful refresh does not masquerade as a recovery.
    private var diagnosticIsDegraded = false
    /// True only while a background periodic-refresh tick is running, so a
    /// failure surfaced during it is recorded as `.refreshFailed` (with the
    /// backoff posture) rather than a fresh `.connectionFailed`.
    private var isPeriodicRefreshInFlight = false

    public init(
        snapshot: PearchHAPanelSnapshot = PearchHAPanelSnapshot(),
        connector: @escaping Connector = { _ in .failure(.protocolError("connection client is not configured")) },
        historyProvider: @escaping HistoryProvider = { _, _, _ in .unavailable("history client is not configured") },
        bulkHistoryProvider: @escaping BulkHistoryProvider = { _, _, _ in [:] },
        serviceMetadataProvider: @escaping ServiceMetadataProvider = { _ in .success([]) },
        liveUpdateStreamer: LiveUpdateStreamer? = nil,
        actionRunner: @escaping ActionRunner = { _, _ in .failed("action client is not configured") },
        oauthSignInRunner: @escaping OAuthSignInRunner = { _ in .failed("OAuth sign-in is not configured") },
        releaseUpdateChecker: @escaping ReleaseUpdateChecker = { _ in .failed("update checker is not configured") },
        currentApplicationVersionProvider: @escaping @Sendable () -> String = { PearchHAApplicationVersionInfo.currentBundle().releaseVersion },
        clock: any PearchClock = SystemPearchClock(),
        wallClock: @escaping @Sendable () -> Date = { Date() },
        historyDebounce: PearchDuration = .milliseconds(120),
        historyCacheConfiguration: PearchHAHistoryCacheConfiguration = PearchHAHistoryCacheConfiguration(),
        bulkSyncConfiguration: PearchHAHistoryBulkSyncConfiguration = PearchHAHistoryBulkSyncConfiguration(),
        periodicRefreshConfiguration: PearchHAPeriodicRefreshConfiguration = PearchHAPeriodicRefreshConfiguration(),
        liveUpdateConfiguration: PearchHALiveUpdateConfiguration = PearchHALiveUpdateConfiguration(),
        selectionConfiguration: EntitySelectionConfiguration = EntitySelectionConfiguration(),
        menuBarDisplayConfiguration: MenuBarDisplayConfiguration = MenuBarDisplayConfiguration(),
        customActionConfiguration: CustomActionConfiguration = CustomActionConfiguration(),
        selectionSink: @escaping SelectionConfigurationSink = { _ in .saved },
        menuBarDisplaySink: @escaping MenuBarDisplayConfigurationSink = { _ in .saved },
        customActionSink: @escaping CustomActionConfigurationSink = { _ in .saved },
        protectedActionValueStore: (any ProtectedActionValueStore)? = nil,
        snapshotSink: @escaping SnapshotSink = { _, _ in },
        signOutHandler: @escaping SignOutHandler = {}
    ) {
        self.snapshotSink = snapshotSink
        self.signOutHandler = signOutHandler
        if let failure = customActionConfiguration.validationFailure() {
            self.customActionConfiguration = CustomActionConfiguration()
            self.customActionPersistenceFailureDescription = failure.description
        } else {
            self.customActionConfiguration = customActionConfiguration
            self.customActionPersistenceFailureDescription = nil
        }
        let initialSnapshot = PearchHAPanelSnapshot(
            connectionState: snapshot.connectionState,
            phase: snapshot.phase,
            rooms: snapshot.rooms,
            availableRooms: snapshot.availableRooms,
            selectionConfiguration: selectionConfiguration,
            menuBarDisplayConfiguration: menuBarDisplayConfiguration,
            selectionQuery: snapshot.selectionQuery,
            isSettingsPresented: snapshot.isSettingsPresented,
            connectionForm: snapshot.connectionForm,
            lastUpdateDescription: snapshot.lastUpdateDescription,
            refreshCount: snapshot.refreshCount,
            canRetry: snapshot.canRetry,
            hasTokenInput: snapshot.hasTokenInput,
            selectionPersistenceFailureDescription: snapshot.selectionPersistenceFailureDescription,
            displayPersistenceFailureDescription: snapshot.displayPersistenceFailureDescription,
            serviceMetadataFailureDescription: snapshot.serviceMetadataFailureDescription,
            historyState: snapshot.historyState,
            historyPresentationEntityID: snapshot.historyPresentationEntityID,
            controlActionState: snapshot.controlActionState,
            serviceMetadata: snapshot.serviceMetadata
        )
        self.snapshot = initialSnapshot
        self.editableForm = snapshot.connectionForm
        self.connector = connector
        self.historyProvider = historyProvider
        self.bulkHistoryProvider = bulkHistoryProvider
        self.serviceMetadataProvider = serviceMetadataProvider
        self.actionRunner = actionRunner
        self.oauthSignInRunner = oauthSignInRunner
        self.releaseUpdateChecker = releaseUpdateChecker
        self.currentApplicationVersionProvider = currentApplicationVersionProvider
        self.clock = clock
        self.wallClock = wallClock
        self.historyDebounce = historyDebounce
        self.historyCacheConfiguration = historyCacheConfiguration
        self.bulkSyncConfiguration = bulkSyncConfiguration
        self.periodicRefreshConfiguration = periodicRefreshConfiguration
        self.liveUpdateStreamer = liveUpdateStreamer
        self.liveUpdateConfiguration = liveUpdateConfiguration
        self.selectionSink = selectionSink
        self.menuBarDisplaySink = menuBarDisplaySink
        self.customActionSink = customActionSink
        self.protectedActionValueStore = protectedActionValueStore ?? UnavailableProtectedActionValueStore()
        self.settingsSelectionTreeSignature = SettingsSelectionTreeSignature(snapshot: initialSnapshot)
        self.settingsSelectionTree = initialSnapshot.selectionTree
        rebuildAvailableEntityCaches(from: initialSnapshot.availableRooms)
    }

    deinit {
        actionTask?.cancel()
        controlActionTask?.cancel()
        historyTask?.cancel()
        bulkSyncTask?.cancel()
        periodicRefreshTask?.cancel()
        liveUpdateTask?.cancel()
    }

    public func updateConnectionForm(
        urlString: String? = nil,
        fallbackURLString: String? = nil,
        addresses: [PearchHAConnectionAddressField]? = nil,
        token: String? = nil,
        usesStoredAuthSession: Bool? = nil,
        allowsSelfSignedCertificates: Bool? = nil
    ) {
        let nextUsesStoredAuthSession = usesStoredAuthSession
            ?? (token?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false ? false : editableForm.usesStoredAuthSession)
        let nextAddresses: [PearchHAConnectionAddressField]
        if let addresses {
            nextAddresses = addresses
        } else if let fallbackURLString {
            nextAddresses = Self.replacingFirstAddress(in: editableForm.addresses, urlString: fallbackURLString)
        } else {
            nextAddresses = editableForm.addresses
        }
        editableForm = PearchHAConnectionForm(
            urlString: urlString ?? editableForm.urlString,
            addresses: nextAddresses,
            token: token ?? editableForm.token,
            usesStoredAuthSession: nextUsesStoredAuthSession,
            allowsSelfSignedCertificates: allowsSelfSignedCertificates ?? editableForm.allowsSelfSignedCertificates
        )
        publishEditableForm()
    }

    /// Appends a new blank alternative address row.
    public func addConnectionAddress() {
        editableForm.addresses.append(PearchHAConnectionAddressField())
        publishEditableForm()
    }

    /// Removes the alternative address with the given identifier.
    ///
    /// - Parameter id: The address row identifier.
    public func removeConnectionAddress(id: PearchHAConnectionAddressField.ID) {
        editableForm.addresses.removeAll { $0.id == id }
        publishEditableForm()
    }

    /// Updates the label or URL of an alternative address row.
    ///
    /// - Parameters:
    ///   - id: The address row identifier.
    ///   - label: A new label, or `nil` to leave it unchanged.
    ///   - urlString: A new URL string, or `nil` to leave it unchanged.
    public func updateConnectionAddress(
        id: PearchHAConnectionAddressField.ID,
        label: String? = nil,
        urlString: String? = nil
    ) {
        guard let index = editableForm.addresses.firstIndex(where: { $0.id == id }) else {
            return
        }
        if let label {
            editableForm.addresses[index].label = label
        }
        if let urlString {
            editableForm.addresses[index].urlString = urlString
        }
        publishEditableForm()
    }

    /// Moves an alternative address one position up or down within the list.
    ///
    /// - Parameters:
    ///   - id: The address row identifier.
    ///   - direction: The direction to move the row.
    /// - Returns: True when the row moved; false when it was already at a boundary
    ///   or not found.
    @discardableResult
    public func moveConnectionAddress(id: PearchHAConnectionAddressField.ID, direction: SelectionMoveDirection) -> Bool {
        guard let index = editableForm.addresses.firstIndex(where: { $0.id == id }) else {
            return false
        }
        let target: Int
        switch direction {
        case .up:
            target = index - 1
        case .down:
            target = index + 1
        }
        guard editableForm.addresses.indices.contains(target) else {
            return false
        }
        editableForm.addresses.swapAt(index, target)
        publishEditableForm()
        return true
    }

    private static func replacingFirstAddress(
        in addresses: [PearchHAConnectionAddressField],
        urlString: String
    ) -> [PearchHAConnectionAddressField] {
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        var updated = addresses
        if updated.isEmpty {
            guard !trimmed.isEmpty else {
                return []
            }
            updated.append(PearchHAConnectionAddressField(urlString: urlString))
            return updated
        }
        updated[0].urlString = urlString
        return updated
    }

    private func publishEditableForm() {
        updateSnapshot { draft in
            draft.connectionForm = nonSecretForm(editableForm)
        }
    }

    public func startConnect() {
        startAction { [weak self] in
            await self?.connect()
        }
    }

    /// Re-applies the edited address list while keeping the stored session.
    ///
    /// Used by the "Update connection" affordance when the user edits, adds,
    /// removes, or reorders addresses while connected. It reconnects using the
    /// existing stored authentication session (no token is cleared); only an
    /// explicit sign-out clears the token.
    public func applyConnectionEdits() {
        startConnect()
    }

    /// Whether the form has a stored session, so address edits can be re-applied
    /// without signing in again.
    public var canApplyConnectionEdits: Bool {
        editableForm.usesStoredAuthSession || !editableForm.trimmedToken.isEmpty
    }

    public func startOAuthSignIn() {
        startAction { [weak self] in
            await self?.signInWithOAuth()
        }
    }

    public func signInWithOAuth() async {
        let form = editableForm
        guard form.primaryURL() != nil else {
            oauthSignInState = .failed("invalid Home Assistant URL")
            applyFailure(.protocolError("invalid Home Assistant URL"), refreshCount: snapshot.refreshCount, canRetry: false)
            return
        }
        for address in form.addresses where !address.urlString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            if address.validURL == nil {
                oauthSignInState = .failed("invalid alternative address")
                applyFailure(.protocolError("invalid alternative address"), refreshCount: snapshot.refreshCount, canRetry: false)
                return
            }
        }

        oauthSignInState = .signingIn
        let result = await oauthSignInRunner(form)
        guard !Task.isCancelled else {
            return
        }
        switch result {
        case .success:
            oauthSignInState = .idle
            updateConnectionForm(
                urlString: form.urlString,
                addresses: form.addresses,
                token: "",
                usesStoredAuthSession: true
            )
            await connect()
        case let .failed(message):
            oauthSignInState = .failed(message)
        }
    }

    public func checkForUpdates() async {
        releaseUpdateState = .checking
        let result = await releaseUpdateChecker(currentApplicationVersionProvider())
        guard !Task.isCancelled else {
            releaseUpdateState = .idle
            return
        }
        switch result {
        case let .upToDate(currentVersion, latestVersion, releaseURL):
            releaseUpdateState = .upToDate(
                currentVersion: currentVersion,
                latestVersion: latestVersion,
                releaseURL: releaseURL
            )
        case let .updateAvailable(update):
            releaseUpdateState = .updateAvailable(update)
        case let .failed(message):
            releaseUpdateState = .failed(message)
        }
    }

    /// Pushes new dashboard display preferences into the model so the open
    /// panel honors them immediately. Persistence is owned by the app shell;
    /// this only updates the in-memory value the panel view observes.
    ///
    /// - Parameter preferences: The new display preferences.
    public func applyDisplayPreferences(_ preferences: PearchHADisplayPreferences) {
        let previousPreferences = displayPreferences
        guard previousPreferences != preferences else {
            return
        }
        displayPreferences = preferences
        let liveUpdateSettingChanged = previousPreferences.liveUpdatesEnabled != preferences.liveUpdatesEnabled
        if previousPreferences.dataSyncInterval != preferences.dataSyncInterval {
            reconcilePeriodicRefreshLoop(refreshImmediately: false)
        }
        if previousPreferences.historyDetailRefreshInterval != preferences.historyDetailRefreshInterval
            || previousPreferences.dataSyncInterval != preferences.dataSyncInterval {
            startHistoryBulkSync()
        }
        if liveUpdateSettingChanged {
            if isPanelActive && preferences.liveUpdatesEnabled {
                startLiveUpdates()
            } else {
                cancelLiveUpdates()
            }
        }
    }

    /// Reports (or clears) a shell-level persistence problem so it surfaces in
    /// Settings instead of being swallowed.
    ///
    /// The app shell calls this when Keychain or configuration-store work it
    /// performs outside the model fails — losing a remembered session or
    /// failing to clear one on sign-out must be visible, not silent.
    ///
    /// - Parameter description: The sanitized, secret-free problem text, or
    ///   `nil` when the previously reported problem has been resolved.
    public func reportShellPersistenceFailure(_ description: String?) {
        shellPersistenceFailureDescription = description
    }

    func historyRevisionPublisher(for id: EntityID) -> AnyPublisher<UInt64, Never> {
        historyRevisionSubject(for: id).eraseToAnyPublisher()
    }

    func rowPresentation(for entity: DiscoveredEntity) -> PearchHAEntityRowPresentation {
        if let cached = rowPresentationCache[entity.id] {
            return cached
        }
        let presentation = PearchHAEntityRowPresentation.resolve(
            entity: entity,
            configuration: snapshot.effectiveMenuBarItemConfiguration(for: entity),
            availableEntities: snapshot.rooms.flatMap(\.entities)
        )
        rowPresentationCache[entity.id] = presentation
        return presentation
    }

    public func formattedValue(for entity: DiscoveredEntity, locale: Locale = .current) -> FormattedEntityValue {
        let key = FormattedEntityValueCacheKey(
            entityID: entity.id,
            localeIdentifier: locale.identifier
        )
        if let cached = formattedValueCache[key] {
            return cached
        }
        let configuration = snapshot.effectiveMenuBarItemConfiguration(for: entity)
        let value = EntityValueFormatter(
            locale: locale,
            displayUnit: configuration.displayUnit,
            displayUnitSymbol: configuration.displayUnitSymbol,
            showsUnit: configuration.showsUnit,
            minValue: configuration.minValue,
            maxValue: configuration.maxValue
        ).format(displayedEntity(for: entity), isStale: snapshot.valuesAreStale)
        formattedValueCache[key] = value
        return value
    }

    private func displayedEntity(for entity: DiscoveredEntity) -> DiscoveredEntity {
        if let cached = displayedEntityCache[entity.id] {
            return cached
        }
        let resolved = PearchHAEntityAveraging.averagedEntity(
            base: entity,
            configuration: snapshot.effectiveMenuBarItemConfiguration(for: entity),
            availableEntities: availableEntities
        )
        displayedEntityCache[entity.id] = resolved
        return resolved
    }

    private func invalidateAllDisplayCaches() {
        displayedEntityCache.removeAll(keepingCapacity: true)
        formattedValueCache.removeAll(keepingCapacity: true)
        rowPresentationCache.removeAll(keepingCapacity: true)
    }

    private func invalidateDisplayCaches(affectedBy entityID: EntityID) {
        let affectedIDs = Set(
            [entityID] + averageCandidateCache.compactMap { key, members in
                members.contains(where: { $0.id == entityID }) ? key : nil
            }
        )
        for affectedID in affectedIDs {
            displayedEntityCache.removeValue(forKey: affectedID)
            rowPresentationCache.removeValue(forKey: affectedID)
        }
        if !affectedIDs.isEmpty {
            formattedValueCache = formattedValueCache.filter { !affectedIDs.contains($0.key.entityID) }
        }
    }

    private func rebuildAvailableEntityCaches(from rooms: [Room], refreshingValues: Bool = false) {
        let signature = AvailableEntityIndexSignature(rooms: rooms)
        guard refreshingValues || availableEntityIndexSignature != signature else {
            return
        }
        let interval = performanceSignposter.beginInterval("RebuildAvailableEntityCaches")
        defer {
            performanceSignposter.endInterval("RebuildAvailableEntityCaches", interval)
        }
        availableEntityIndexSignature = signature
        var locations: [EntityID: AvailableEntityLocation] = [:]
        var byID: [EntityID: DiscoveredEntity] = [:]
        var flattened: [DiscoveredEntity] = []
        flattened.reserveCapacity(rooms.reduce(0) { $0 + $1.entities.count })
        for (roomIndex, room) in rooms.enumerated() {
            for (entityIndex, entity) in room.entities.enumerated() {
                locations[entity.id] = AvailableEntityLocation(roomIndex: roomIndex, entityIndex: entityIndex)
                byID[entity.id] = entity
                flattened.append(entity)
            }
        }
        availableEntityLocations = locations
        availableEntitiesByID = byID
        availableEntities = flattened
        averageCandidateCache.removeAll(keepingCapacity: true)
        inlineSparklineGeometryCache.removeAll(keepingCapacity: true)
        historyRevisionSubjects = historyRevisionSubjects.filter { byID[$0.key] != nil }
    }

    private func historyRevisionSubject(for id: EntityID) -> CurrentValueSubject<UInt64, Never> {
        if let subject = historyRevisionSubjects[id] {
            return subject
        }
        let subject = CurrentValueSubject<UInt64, Never>(0)
        historyRevisionSubjects[id] = subject
        return subject
    }

    private func bumpHistoryRevisions<S: Sequence>(for entityIDs: S) where S.Element == EntityID {
        var touched: Set<EntityID> = []
        for entityID in entityIDs {
            guard touched.insert(entityID).inserted else {
                continue
            }
            let subject = historyRevisionSubject(for: entityID)
            subject.value &+= 1
        }
        if !touched.isEmpty {
            historyRevision &+= 1
        }
    }

    public func toggleSettings() {
        updateSnapshot { draft in
            draft.isSettingsPresented.toggle()
        }
    }

    public func updateSelectionQuery(_ query: String) {
        updateSnapshot { draft in
            draft.selectionQuery = query
        }
    }

    public func setEntity(_ id: EntityID, isSelected: Bool) {
        let currentIDs = snapshot.selectionConfiguration.isExplicit
            ? snapshot.selectionConfiguration.selectedEntityIDs
            : orderedAvailableEntityIDs()
        var selected = Set(currentIDs)
        if isSelected {
            selected.insert(id)
        } else {
            selected.remove(id)
        }

        let ordered = orderedSelectionIDs(selected)
        updateSelectionConfiguration(
            EntitySelectionConfiguration(
                selectedEntityIDs: ordered,
                roomOrder: snapshot.selectionConfiguration.roomOrder,
                entityOrder: snapshot.selectionConfiguration.entityOrder,
                isExplicit: true
            ),
            persist: true
        )
    }

    /// Selects or deselects every discovered entity at once.
    ///
    /// - Parameter isSelected: When true, all available entities become visible
    ///   in the panel; when false, the selection is cleared. The change is
    ///   marked explicit and persisted.
    public func setAllEntities(isSelected: Bool) {
        let selected: Set<EntityID> = isSelected ? Set(orderedAvailableEntityIDs()) : []
        updateSelectionConfiguration(
            EntitySelectionConfiguration(
                selectedEntityIDs: orderedSelectionIDs(selected),
                roomOrder: snapshot.selectionConfiguration.roomOrder,
                entityOrder: snapshot.selectionConfiguration.entityOrder,
                isExplicit: true
            ),
            persist: true
        )
    }

    @discardableResult
    public func setMenuBarEntity(_ id: EntityID, isVisible: Bool) -> Bool {
        var configuration = snapshot.menuBarDisplayConfiguration
        if isVisible,
           configuration.itemConfigurations.contains(where: { $0.entityID == id }) == false,
           let entity = entity(for: id) {
            configuration = configuration.replacingItemConfiguration(
                EntityDisplayDefaults.configuration(for: entity)
            )
        }
        return updateMenuBarDisplayConfiguration(
            configuration.settingPromotion(id, isPromoted: isVisible),
            persist: true
        )
    }

    @discardableResult
    public func moveMenuBarEntity(_ id: EntityID, direction: SelectionMoveDirection) -> Bool {
        guard canReorderMenuBarDisplay else {
            return false
        }
        return updateMenuBarDisplayConfiguration(
            snapshot.menuBarDisplayConfiguration.movingPromotion(id, direction: direction),
            persist: true
        )
    }

    @discardableResult
    public func moveMenuBarEntity(_ id: EntityID, relativeTo targetID: EntityID, placement: SelectionDropPlacement) -> Bool {
        guard canReorderMenuBarDisplay else {
            return false
        }
        return updateMenuBarDisplayConfiguration(
            snapshot.menuBarDisplayConfiguration.movingPromotion(id, relativeTo: targetID, placement: placement),
            persist: true
        )
    }

    @discardableResult
    public func setMenuBarDisplayStyle(_ id: EntityID, style: MenuBarDisplayStyle) -> Bool {
        updateMenuBarItemConfiguration(
            snapshot.menuBarDisplayConfiguration.itemConfiguration(for: id).updating(style: style)
        )
    }

    @discardableResult
    public func setMenuBarShowsLabel(_ id: EntityID, showsLabel: Bool) -> Bool {
        updateMenuBarItemConfiguration(
            snapshot.menuBarDisplayConfiguration.itemConfiguration(for: id).updating(showsLabel: showsLabel)
        )
    }

    /// Sets the per-entity menu-bar appearance (icon / text / both), overriding
    /// the global default for this entity.
    ///
    /// - Parameters:
    ///   - id: The entity whose menu-bar appearance changes.
    ///   - appearance: The appearance to apply, or `nil` to inherit the global
    ///     default appearance.
    /// - Returns: `true` when the configuration was updated and persisted.
    @discardableResult
    public func setMenuBarAppearance(_ id: EntityID, appearance: PearchHAMenuBarAppearance?) -> Bool {
        updateMenuBarItemConfiguration(
            snapshot.menuBarDisplayConfiguration.itemConfiguration(for: id).settingAppearance(appearance)
        )
    }

    @discardableResult
    public func setMenuBarShowsUnit(_ id: EntityID, showsUnit: Bool) -> Bool {
        updateMenuBarItemConfiguration(
            snapshot.menuBarDisplayConfiguration.itemConfiguration(for: id).updating(showsUnit: showsUnit)
        )
    }

    @discardableResult
    public func setMenuBarMaximumFractionDigits(_ id: EntityID, maximumFractionDigits: Int) -> Bool {
        updateMenuBarItemConfiguration(
            snapshot.menuBarDisplayConfiguration.itemConfiguration(for: id).updating(
                maximumFractionDigits: maximumFractionDigits
            )
        )
    }

    @discardableResult
    public func setMenuBarDefaultHistoryRange(_ id: EntityID, defaultHistoryRange: HistoryRange?) -> Bool {
        updateMenuBarItemConfiguration(
            snapshot.menuBarDisplayConfiguration.itemConfiguration(for: id)
                .settingDefaultHistoryRange(defaultHistoryRange)
        )
    }

    /// The cover control mode configured for an entity.
    public func coverControlMode(for entity: DiscoveredEntity) -> CoverControlMode {
        snapshot.coverControlMode(for: entity)
    }

    @discardableResult
    public func setCoverControlMode(_ id: EntityID, mode: CoverControlMode) -> Bool {
        updateMenuBarItemConfiguration(
            snapshot.menuBarDisplayConfiguration.itemConfiguration(for: id).updating(coverControlMode: mode)
        )
    }

    @discardableResult
    public func setDisplayUnit(_ id: EntityID, displayUnit: ValueUnit?, displayUnitSymbol: String? = nil) -> Bool {
        let configuration = snapshot.menuBarDisplayConfiguration.itemConfiguration(for: id)
        guard let entity = entity(for: id) else {
            return updateMenuBarItemConfiguration(
                configuration
                    .settingDisplayUnit(displayUnit)
                    .settingDisplayUnitSymbol(displayUnitSymbol)
            )
        }

        let currentDefaultThresholds = EntityDisplayDefaults.defaultThresholds(
            for: entity,
            selectedUnit: configuration.displayUnit
        )
        let currentThresholds = EntityDisplayDefaults.effectiveThresholds(for: entity, configuration: configuration)
        let nextThresholds: ValueThresholds? = currentThresholds == currentDefaultThresholds
            ? EntityDisplayDefaults.defaultThresholds(for: entity, selectedUnit: displayUnit)
            : nil

        return updateMenuBarItemConfiguration(
            configuration
                .settingDisplayUnit(displayUnit)
                .settingDisplayUnitSymbol(displayUnitSymbol)
                .settingThresholds(nextThresholds ?? currentThresholds)
        )
    }

    /// Shows or hides the entity's leading icon on its dashboard row.
    ///
    /// - Parameters:
    ///   - id: The entity whose dashboard icon visibility changes.
    ///   - showsEntityIcon: Whether the icon column renders the icon.
    /// - Returns: `true` when the configuration was updated and persisted.
    @discardableResult
    public func setShowsEntityIcon(_ id: EntityID, showsEntityIcon: Bool) -> Bool {
        updateMenuBarItemConfiguration(
            snapshot.menuBarDisplayConfiguration.itemConfiguration(for: id).settingShowsEntityIcon(showsEntityIcon)
        )
    }

    /// The initial detail range for an entity: its explicit per-entity range,
    /// or the global Appearance default when the entity inherits.
    ///
    /// - Parameter id: The entity whose range is resolved.
    /// - Returns: The initial history popover range. Inline previews always use day.
    public func historyRange(for id: EntityID) -> HistoryRange {
        snapshot.menuBarDisplayConfiguration.itemConfiguration(for: id).defaultHistoryRange
            ?? displayPreferences.defaultHistoryRange
    }

    /// Replaces the entity's threshold steps and base color.
    ///
    /// - Parameters:
    ///   - id: The entity whose thresholds change.
    ///   - thresholds: The Grafana-style steps plus optional base color.
    /// - Returns: `true` when the configuration was updated and persisted.
    @discardableResult
    public func setThresholds(_ id: EntityID, thresholds: ValueThresholds) -> Bool {
        updateMenuBarItemConfiguration(
            snapshot.menuBarDisplayConfiguration.itemConfiguration(for: id)
                .settingThresholds(thresholds)
        )
    }

    /// Replaces the entity's state-to-color threshold rules.
    ///
    /// - Parameters:
    ///   - id: The entity whose string/state thresholds change.
    ///   - thresholds: The explicit string rules plus optional base color.
    /// - Returns: `true` when the configuration was updated and persisted.
    @discardableResult
    public func setStateThresholds(_ id: EntityID, thresholds: StateThresholds) -> Bool {
        updateMenuBarItemConfiguration(
            snapshot.menuBarDisplayConfiguration.itemConfiguration(for: id)
                .settingStateThresholds(thresholds)
        )
    }

    /// Overrides the entity's dashboard icon with a custom SF Symbol.
    ///
    /// - Parameters:
    ///   - id: The entity whose dashboard icon changes.
    ///   - symbolName: The SF Symbol name, or `nil` to restore the automatic
    ///     domain-derived icon.
    /// - Returns: `true` when the configuration was updated and persisted.
    @discardableResult
    public func setCustomEntityIcon(_ id: EntityID, symbolName: String?) -> Bool {
        updateMenuBarItemConfiguration(
            snapshot.menuBarDisplayConfiguration.itemConfiguration(for: id).settingCustomIconName(symbolName)
        )
    }

    @discardableResult
    public func setDisplayBounds(_ id: EntityID, minValue: Double?, maxValue: Double?) -> Bool {
        updateMenuBarItemConfiguration(
            snapshot.menuBarDisplayConfiguration.itemConfiguration(for: id)
                .settingBounds(minValue: minValue, maxValue: maxValue)
        )
    }

    /// The full shared averaging family for an entity, always including the
    /// entity itself. A single-id result means no active family.
    public func averageFamilyEntityIDs(for id: EntityID) -> [EntityID] {
        PearchHAEntityAveraging.familyIDs(
            for: id,
            configuration: snapshot.menuBarDisplayConfiguration.itemConfiguration(for: id)
        )
    }

    /// The linked peer ids contributing to an entity's average, excluding the
    /// entity itself.
    public func averageLinkedEntityIDs(for id: EntityID) -> [EntityID] {
        averageFamilyEntityIDs(for: id).filter { $0 != id }
    }

    public func averageLinkedEntities(for id: EntityID) -> [DiscoveredEntity] {
        averageLinkedEntityIDs(for: id).compactMap(entity(for:))
    }

    public func averageCandidateEntities(for id: EntityID) -> [DiscoveredEntity] {
        guard let source = entity(for: id) else {
            return []
        }
        if let cached = averageCandidateCache[id] {
            return cached
        }
        let currentFamily = Set(averageFamilyEntityIDs(for: id))
        let candidates = availableEntities.filter { candidate in
            !currentFamily.contains(candidate.id)
                && candidate.id != id
                && candidate.unit == source.unit
                && PearchHAEntityAveraging.areCompatible(source, candidate)
        }
        averageCandidateCache[id] = candidates
        return candidates
    }

    public func canAverage(_ id: EntityID) -> Bool {
        !averageCandidateEntities(for: id).isEmpty || !averageLinkedEntityIDs(for: id).isEmpty
    }

    @discardableResult
    public func setAverageLinkedEntityIDs(_ id: EntityID, linkedEntityIDs: [EntityID]) -> Bool {
        guard let source = entity(for: id) else {
            return false
        }
        let requestedPeers = uniqueEntityIDs(linkedEntityIDs).filter { $0 != id }
        let currentFamily = averageFamilyEntityIDs(for: id)
        var targetFamily: [EntityID] = [id]
        for peerID in requestedPeers {
            guard let peer = entity(for: peerID),
                  PearchHAEntityAveraging.areCompatible(source, peer) else {
                return false
            }
            targetFamily.append(peerID)
        }
        targetFamily = orderedAverageFamilyIDs(targetFamily)
        let storedTargetFamily = targetFamily.count > 1 ? targetFamily : []

        var displayConfiguration = snapshot.menuBarDisplayConfiguration
        let affected = Set(currentFamily + targetFamily)
        for memberID in affected {
            let memberFamily = storedTargetFamily.contains(memberID) ? storedTargetFamily : []
            let memberConfiguration = displayConfiguration.itemConfiguration(for: memberID)
                .settingAverageEntityIDs(memberFamily)
            displayConfiguration = displayConfiguration.replacingItemConfiguration(memberConfiguration)
        }
        return updateMenuBarDisplayConfiguration(displayConfiguration, persist: true)
    }

    @discardableResult
    public func setMenuBarAbsoluteTotal(_ id: EntityID, total: Double?) -> Bool {
        guard canSetAbsoluteTotal(id, total: total) else {
            return false
        }
        return updateMenuBarItemConfiguration(
            snapshot.menuBarDisplayConfiguration.itemConfiguration(for: id)
                .settingAbsoluteTotal(total)
        )
    }

    @discardableResult
    public func setMenuBarTotalEntityID(_ id: EntityID, totalEntityID: EntityID?) -> Bool {
        guard canSetTotalEntityID(id, totalEntityID: totalEntityID) else {
            return false
        }
        return updateMenuBarItemConfiguration(
            snapshot.menuBarDisplayConfiguration.itemConfiguration(for: id)
                .settingTotalEntityID(totalEntityID)
        )
    }

    @discardableResult
    public func setMenuBarWarningThreshold(_ id: EntityID, threshold: ValueThreshold?) -> Bool {
        guard canSetThreshold(threshold) else {
            return false
        }
        return updateMenuBarItemConfiguration(
            snapshot.menuBarDisplayConfiguration.itemConfiguration(for: id)
                .settingWarningThreshold(threshold)
        )
    }

    @discardableResult
    public func setMenuBarCriticalThreshold(_ id: EntityID, threshold: ValueThreshold?) -> Bool {
        guard canSetThreshold(threshold) else {
            return false
        }
        return updateMenuBarItemConfiguration(
            snapshot.menuBarDisplayConfiguration.itemConfiguration(for: id)
                .settingCriticalThreshold(threshold)
        )
    }

    @discardableResult
    public func moveRoom(_ id: RoomID, direction: SelectionMoveDirection) -> Bool {
        let configuration = EntitySelectionReorderer().moveRoom(
            id,
            direction: direction,
            rooms: snapshot.availableRooms,
            configuration: snapshot.selectionConfiguration
        )
        return updateSelectionConfiguration(configuration, persist: true)
    }

    @discardableResult
    public func moveRoom(_ id: RoomID, relativeTo targetID: RoomID, placement: SelectionDropPlacement) -> Bool {
        let configuration = EntitySelectionReorderer().moveRoom(
            id,
            relativeTo: targetID,
            placement: placement,
            rooms: snapshot.availableRooms,
            configuration: snapshot.selectionConfiguration
        )
        return updateSelectionConfiguration(configuration, persist: true)
    }

    @discardableResult
    public func moveEntity(_ id: EntityID, direction: SelectionMoveDirection) -> Bool {
        let configuration = EntitySelectionReorderer().moveEntity(
            id,
            direction: direction,
            rooms: snapshot.availableRooms,
            configuration: snapshot.selectionConfiguration
        )
        return updateSelectionConfiguration(configuration, persist: true)
    }

    @discardableResult
    public func moveEntity(_ id: EntityID, relativeTo targetID: EntityID, placement: SelectionDropPlacement) -> Bool {
        let configuration = EntitySelectionReorderer().moveEntity(
            id,
            relativeTo: targetID,
            placement: placement,
            rooms: snapshot.availableRooms,
            configuration: snapshot.selectionConfiguration
        )
        return updateSelectionConfiguration(configuration, persist: true)
    }

    public func startRefresh() {
        startAction { [weak self] in
            await self?.refresh()
        }
    }

    /// Presents cached history immediately and loads missing data after the debounce.
    /// Explicit selections remain available while a native menu is tracking input.
    ///
    /// - Parameters:
    ///   - id: The entity whose history should be shown.
    ///   - range: An explicit range, or `nil` to use the entity's default.
    public func presentHistoryDetail(_ id: EntityID, range: HistoryRange? = nil) {
        let resolvedRange = range ?? historyRange(for: id)
        historyTask?.cancel()
        primeHistoryPresentation(entityID: id, range: resolvedRange)
        historyTask = Task { @MainActor [weak self] in
            guard let self else {
                return
            }
            do {
                _ = try await clock.sleep(for: historyDebounce)
            } catch {
                return
            }
            applyHistoryPresentationEntityID(id)
            await loadHistory(id, range: resolvedRange)
            startHistoryBulkSync()
            if !Task.isCancelled {
                historyTask = nil
            }
        }
    }

    public func beginTransientUITracking() {
        transientUITrackingDepth += 1
    }

    public func endTransientUITracking() {
        transientUITrackingDepth = max(0, transientUITrackingDepth - 1)
        guard transientUITrackingDepth == 0 else {
            return
        }
        let deferredStates = deferredLiveStates.values.sorted { $0.state.id.rawValue < $1.state.id.rawValue }
        deferredLiveStates = [:]
        for report in deferredStates {
            _ = applyLiveState(report.state, reporting: report.requests)
        }
        if deferredSilentRefreshRequested, isPanelActive, lastConnectedForm != nil {
            deferredSilentRefreshRequested = false
            startAction { [weak self] in
                await self?.performRefresh(silent: true)
            }
        } else {
            deferredSilentRefreshRequested = false
        }
    }

    /// Selection opens the history panel immediately from cache when possible,
    /// then refreshes the backing series through the normal debounced load path.
    private func primeHistoryPresentation(entityID: EntityID, range: HistoryRange) {
        applyHistoryPresentationEntityID(entityID)
        let cacheKey = PearchHAHistoryCacheKey(entityID: entityID, range: range)
        if let state = cachedHistoryState(for: cacheKey) {
            applyHistoryState(state)
            return
        }
        if snapshot.historyState.entityID != entityID || snapshot.historyState.range != range {
            applyHistoryState(.loading(entityID: entityID, range: range))
        }
    }

    public func loadHistory(_ id: EntityID, range: HistoryRange? = nil) async {
        let resolvedRange = range ?? historyRange(for: id)
        let cacheKey = PearchHAHistoryCacheKey(entityID: id, range: resolvedRange)
        let waitingGeneration = historyRequestGeneration
        var now = await clock.now()
        while historyRequests[cacheKey] != nil {
            await withCheckedContinuation { historyRequestWaiters[cacheKey, default: []].append($0) }
            guard !Task.isCancelled, waitingGeneration == historyRequestGeneration else { return }
            now = await clock.now()
        }
        guard !Task.isCancelled, waitingGeneration == historyRequestGeneration else { return }
        lastObservedInstant = now
        if !historyIsDue(cacheKey, now: now),
           historyCache.series(for: cacheKey, now: now) != nil,
           let state = cachedHistoryState(for: cacheKey) {
            applyHistoryState(state)
            return
        }
        if let state = cachedHistoryState(for: cacheKey) {
            applyHistoryState(state)
        }

        guard let form = lastConnectedForm else {
            let message = "history requires a connected Home Assistant session"
            bumpHistoryRevisions(for: markHistoryFailure(cacheKey, message: message))
            applyHistoryState(cachedHistoryState(for: cacheKey) ?? .unavailable(entityID: id, range: resolvedRange, message: message))
            return
        }

        let requestID = UUID()
        beginHistoryRequest([cacheKey], requestID: requestID)
        var changedEntities = Set<EntityID>()
        var completed = false
        defer { finishHistoryRequest([cacheKey], requestID: requestID, completed: completed, changedEntities: changedEntities) }
        historyRequestGeneration += 1
        let requestGeneration = historyRequestGeneration
        applyHistoryState(historyState(for: id, range: resolvedRange))
        recordOutboundRequest()
        let result = await historyProvider(form, id, resolvedRange)
        guard !Task.isCancelled, requestGeneration == historyRequestGeneration,
              form.sameConnection(as: lastConnectedForm) else {
            return
        }

        switch result {
        case let .success(series):
            guard series.entityID == id, series.range == resolvedRange else {
                completed = true
                let message = "history provider returned the wrong series"
                changedEntities.formUnion(markHistoryFailure(cacheKey, message: message))
                applyHistoryState(cachedHistoryState(for: cacheKey) ?? .unavailable(entityID: id, range: resolvedRange, message: message))
                return
            }
            let insertNow = await clock.now()
            guard !Task.isCancelled, requestGeneration == historyRequestGeneration,
                  form.sameConnection(as: lastConnectedForm) else { return }
            lastObservedInstant = insertNow
            changedEntities.formUnion(insertHistory(series, for: cacheKey, now: insertNow))
            completed = true
            applyHistoryState(.loaded(series))
        case let .unavailable(message):
            changedEntities.formUnion(markHistoryFailure(cacheKey, message: message))
            completed = true
            applyHistoryState(cachedHistoryState(for: cacheKey) ?? .unavailable(entityID: id, range: resolvedRange, message: message))
        }
    }

    private var effectivePeriodicRefreshInterval: PearchDuration {
        guard periodicRefreshConfiguration.isEnabled else {
            return .seconds(0)
        }
        let configuredDefault = PearchHAPeriodicRefreshConfiguration().interval
        if periodicRefreshConfiguration.interval != configuredDefault {
            return periodicRefreshConfiguration.interval
        }
        return PearchDuration.seconds(Int64(displayPreferences.dataSyncInterval.rawValue))
    }

    private var effectiveBulkSyncInterval: PearchDuration {
        guard bulkSyncConfiguration.isEnabled else {
            return .seconds(0)
        }
        let configuredDefault = PearchHAHistoryBulkSyncConfiguration().interval
        if bulkSyncConfiguration.interval != configuredDefault {
            return bulkSyncConfiguration.interval
        }
        return PearchDuration.seconds(Int64(displayPreferences.dataSyncInterval.rawValue))
    }

    private var effectiveHistoryDetailRefreshInterval: PearchDuration {
        PearchDuration.seconds(Int64(displayPreferences.historyDetailRefreshInterval.rawValue))
    }

    private func beginHistoryRequest(_ keys: [PearchHAHistoryCacheKey], requestID: UUID) {
        for key in keys { historyRequests[key] = requestID }
        updateInitialHistoryLoading()
        bumpHistoryRevisions(for: keys.map(\.entityID))
        refreshPresentedHistoryFromCache()
    }

    private func finishHistoryRequest(
        _ keys: [PearchHAHistoryCacheKey], requestID: UUID, completed: Bool = false,
        changedEntities: Set<EntityID> = []
    ) {
        var changedEntities = changedEntities
        for key in keys where historyRequests[key] == requestID {
            if completed { hasCompletedInitialHistoryLoad = true }
            historyRequests[key] = nil
            changedEntities.insert(key.entityID)
            if snapshot.historyState.entityID == key.entityID, snapshot.historyState.range == key.range {
                applyHistoryState(cachedHistoryState(for: key) ?? .idle)
            }
            let waiters = historyRequestWaiters.removeValue(forKey: key) ?? []
            for waiter in waiters { waiter.resume() }
        }
        updateInitialHistoryLoading()
        bumpHistoryRevisions(for: changedEntities)
    }

    private func updateInitialHistoryLoading() {
        let loading = isPanelActive && !hasCompletedInitialHistoryLoad && !historyRequests.isEmpty
        if isInitialHistoryLoading != loading { isInitialHistoryLoading = loading }
    }

    private var presentedHistoryKey: PearchHAHistoryCacheKey? {
        guard isPanelActive, let id = snapshot.historyPresentationEntityID else { return nil }
        return PearchHAHistoryCacheKey(entityID: id, range: snapshot.historyState.range ?? historyRange(for: id))
    }

    private func historyRefreshInterval(for key: PearchHAHistoryCacheKey) -> PearchDuration {
        let previewInterval = effectiveBulkSyncInterval.nanoseconds > 0
            ? effectiveBulkSyncInterval : effectiveHistoryDetailRefreshInterval
        guard key == presentedHistoryKey else { return previewInterval }
        if key.range == .day, displayedEntityIDs().contains(key.entityID) {
            return PearchDuration(nanoseconds: min(previewInterval.nanoseconds, effectiveHistoryDetailRefreshInterval.nanoseconds))
        }
        return effectiveHistoryDetailRefreshInterval
    }

    private func historyIsDue(_ key: PearchHAHistoryCacheKey, now: PearchInstant) -> Bool {
        guard let fetchedAt = historyCache.fetchedAt(for: key) else { return true }
        return now.nanosecondsSinceStart - fetchedAt.nanosecondsSinceStart >= historyRefreshInterval(for: key).nanoseconds
    }

    private func cachedHistoryState(for key: PearchHAHistoryCacheKey) -> PearchHAHistoryPanelState? {
        let series = historyCache.peekAllowingStale(for: key)
        if historyRequests[key] != nil {
            return series.map(PearchHAHistoryPanelState.updating)
                ?? .loading(entityID: key.entityID, range: key.range)
        }
        if let message = historyCache.failureMessage(for: key) {
            return series.map { .stale($0, message: message) }
                ?? .unavailable(entityID: key.entityID, range: key.range, message: message)
        }
        return series.map(PearchHAHistoryPanelState.loaded)
    }

    /// Read-only presentation shared by previews and the opened history.
    func historyState(for id: EntityID, range: HistoryRange? = nil) -> PearchHAHistoryPanelState {
        cachedHistoryState(for: PearchHAHistoryCacheKey(entityID: id, range: range ?? .day)) ?? .idle
    }

    private func refreshPresentedHistoryFromCache() {
        guard let key = presentedHistoryKey, let state = cachedHistoryState(for: key) else { return }
        applyHistoryState(state)
    }

    private func markHistoryFailure(_ key: PearchHAHistoryCacheKey, message: String) -> Set<EntityID> {
        let changed = historyCache.markFailure(
            for: key, message: message, capacity: historyCacheConfiguration.capacity,
            protecting: protectedHistoryKeys()
        )
        for changedKey in changed where historyCache.peekAllowingStale(for: changedKey) == nil {
            inlineSparklineGeometryCache[changedKey] = nil
        }
        if key == presentedHistoryKey {
            applyHistoryState(cachedHistoryState(for: key) ?? .unavailable(entityID: key.entityID, range: key.range, message: message))
        }
        return Set(changed.map(\.entityID))
    }

    /// Returns an already-cached history series for an entity without fetching.
    ///
    /// This is the *only* history access intended for visible-row rendering: it
    /// reads the in-memory cache without mutating recency, without evicting, and
    /// crucially without ever triggering a network fetch. Rows use it to draw an
    /// inline sparkline whenever visible history has loaded. Clicking the preview
    /// opens the detail popover. Without cached data this returns `nil`.
    /// Re-rendering as fresh data lands is driven by ``historyRevision``; honoring
    /// the no-fetch contract keeps the idle-CPU and request-volume budgets intact.
    ///
    /// - Parameter id: The entity whose cached history is requested.
    /// - Returns: The cached daily preview, or `nil`.
    public func cachedHistorySeries(for id: EntityID) -> HistorySeries? {
        cachedHistorySeries(for: id, range: .day)
    }

    func knownUnavailableHistoryRanges(for id: EntityID) -> Set<HistoryRange> {
        Set(
            HistoryRange.uiSelectable.filter { range in
                if let series = cachedHistorySeries(for: id, range: range) {
                    let key = PearchHAHistoryCacheKey(entityID: id, range: range)
                    return series.samples.isEmpty && !historyIsDue(key, now: lastObservedInstant)
                }
                if case let .unavailable(entityID, unavailableRange, _) = snapshot.historyState {
                    return entityID == id && unavailableRange == range
                }
                return false
            }
        )
    }

    func cachedHistorySeries(for id: EntityID, range: HistoryRange) -> HistorySeries? {
        let key = PearchHAHistoryCacheKey(entityID: id, range: range)
        // Display uses the stale-tolerant peek so the inline sparkline keeps
        // showing its last-known data instead of flickering out when the entry
        // crosses its TTL; the bulk sync loop refreshes it underneath.
        return historyCache.peekAllowingStale(for: key)
    }

    func cachedInlinePreview(for id: EntityID) -> PearchHAInlineHistoryPreviewData? {
        let key = PearchHAHistoryCacheKey(entityID: id, range: .day)
        guard let series = historyCache.peekAllowingStale(for: key) else {
            return nil
        }
        let numericSamples = series.chronologicalNumericSamples
        if !numericSamples.isEmpty {
            if let cached = inlineSparklineGeometryCache[key] {
                if let geometry = cached {
                    return geometry.hasTrace ? .sparkline(geometry) : .placeholder
                }
                return .placeholder
            }
            let geometry = PearchHAHistorySparklineGeometry(
                samples: numericSamples,
                maxSamples: Self.inlineSparklineSampleBudget
            )
            inlineSparklineGeometryCache[key] = geometry.hasTrace ? geometry : nil
            return geometry.hasTrace ? .sparkline(geometry) : .placeholder
        }
        return .state(series)
    }

    /// The current number of cached history series kept in memory.
    public func historyCacheEntryCount() -> Int {
        historyCache.entryCount
    }

    /// The current total number of cached history samples kept in memory.
    public func historyCacheSampleCount() -> Int {
        historyCache.sampleCount
    }

    /// The configured maximum number of history series the cache keeps before
    /// evicting least-recently-used non-visible entries.
    public func historyCacheCapacity() -> Int {
        historyCacheConfiguration.capacity
    }

    /// Inserts a series and returns affected rows for one batched publication.
    ///
    /// Every cache write (preview refresh or detail load) flows through here so the
    /// inline-preview read path, which depends on ``historyRevision``, re-renders
    /// the affected rows. Callers publish once after their batch has landed.
    private func insertHistory(_ series: HistorySeries, for key: PearchHAHistoryCacheKey, now: PearchInstant) -> Set<EntityID> {
        let evicted = historyCache.insert(
            series,
            for: key,
            now: now,
            capacity: historyCacheConfiguration.capacity,
            ttl: historyCacheTTL(for: key.range),
            protecting: protectedHistoryKeys()
        )
        for evictedKey in evicted { inlineSparklineGeometryCache[evictedKey] = nil }
        inlineSparklineGeometryCache[key] = nil
        return Set(evicted.map(\.entityID)).union([key.entityID])
    }

    /// Keep selected daily previews and the open detail available between refreshes.
    private func protectedHistoryKeys() -> Set<PearchHAHistoryCacheKey> {
        var keys = Set(displayedEntityIDs().map { PearchHAHistoryCacheKey(entityID: $0, range: .day) })
        if let key = presentedHistoryKey {
            keys.insert(key)
        }
        return keys
    }

    private func historyCacheTTL(for range: HistoryRange) -> PearchDuration {
        scaledDuration(historyCacheConfiguration.ttl, by: historyCacheTTLMultiplier(for: range))
    }

    private func historyCacheTTLMultiplier(for range: HistoryRange) -> Int64 {
        switch range {
        case .hour:
            1
        case .day:
            3
        case .week:
            1_440
        case .month:
            1_440
        }
    }

    private func scaledDuration(_ duration: PearchDuration, by multiplier: Int64) -> PearchDuration {
        let scaled = duration.nanoseconds.multipliedReportingOverflow(by: max(1, multiplier))
        return PearchDuration(nanoseconds: scaled.overflow ? Int64.max : scaled.partialValue)
    }

    /// Drops the entire history cache and publishes the eviction so previews that
    /// were drawing a now-cleared series re-render empty.
    private func evictAllHistory() {
        historyCache = PearchHAHistoryCache()
        historyRequests.removeAll(keepingCapacity: true)
        hasCompletedInitialHistoryLoad = false
        updateInitialHistoryLoading()
        let waiters = historyRequestWaiters.values.flatMap { $0 }
        historyRequestWaiters.removeAll(keepingCapacity: true)
        for waiter in waiters { waiter.resume() }
        inlineSparklineGeometryCache.removeAll(keepingCapacity: true)
        bumpHistoryRevisions(for: displayedEntityIDs())
    }

    // MARK: - History bulk sync loop

    /// Marks the panel as shown or hidden, gating panel-only background work.
    ///
    /// The app shell calls this with `true` when the panel becomes visible and
    /// `false` when it is hidden or closed. While inactive the model cancels
    /// detail refresh and the live socket. Selected daily previews and timed
    /// data sync continue while closed.
    ///
    /// - Parameter active: Whether the panel is currently shown.
    public func setPanelActive(_ active: Bool) {
        guard active != isPanelActive else {
            return
        }
        isPanelActive = active
        updateInitialHistoryLoading()
        if active {
            flushDeferredBackgroundLiveStates()
            // Keep cached previews visible and refresh only keys that are due.
            startHistoryBulkSync()
            // Opening the panel should render from the current snapshot/cache
            // first, then let background refresh happen quietly afterward.
            startPeriodicRefresh(refreshImmediately: false)
            startLiveUpdates()
        } else {
            dismissHistoryPopover()
            cancelLiveUpdates()
            reconcilePeriodicRefreshLoop(refreshImmediately: false)
        }
    }

    /// Starts the timed refresh safety net.
    ///
    /// Refreshes once on demand (a discovery/refresh when a session is connected),
    /// then repeats on the injected clock while there is any visible/background
    /// consumer that needs fresh values: selected panel or promoted menu-bar
    /// entities. A failed refresh backs off exponentially up to the configured
    /// ceiling; a success resets the streak to the base interval. Live WebSocket
    /// push remains optional; this timed loop is the cheap fallback that keeps
    /// cached values moving without an always-on socket.
    private func startPeriodicRefresh(refreshImmediately: Bool = true) {
        periodicRefreshTask?.cancel()
        guard shouldRunPeriodicRefreshLoop else {
            periodicRefreshTask = nil
            return
        }
        periodicRefreshFailureStreak = 0
        periodicRefreshTask = Task { @MainActor [weak self, clock] in
            // Refresh immediately on open, then settle into the interval loop.
            // Arming right after a successful connect skips the immediate tick —
            // the data just arrived. Self is re-bound weakly each iteration so
            // the long-lived loop never pins the model; deinit stays reachable
            // and cancels the task.
            if refreshImmediately {
                await self?.runPeriodicRefreshTick()
            }
            while !Task.isCancelled {
                guard let delay = self.map({ $0.periodicRefreshDelay() }), self?.shouldRunPeriodicRefreshLoop == true else {
                    return
                }
                do {
                    _ = try await clock.sleep(for: delay)
                } catch {
                    return
                }
                guard !Task.isCancelled, let model = self, model.shouldRunPeriodicRefreshLoop else {
                    return
                }
                await model.runPeriodicRefreshTick()
            }
        }
    }

    private var shouldRunPeriodicRefreshLoop: Bool {
        guard effectivePeriodicRefreshInterval.nanoseconds > 0, lastConnectedForm != nil else {
            return false
        }
        return isPanelActive || !snapshot.menuBarDisplayConfiguration.promotedEntityIDs.isEmpty
            || (bulkSyncConfiguration.isEnabled && !snapshot.rooms.isEmpty)
    }

    private func reconcilePeriodicRefreshLoop(refreshImmediately: Bool) {
        if shouldRunPeriodicRefreshLoop {
            startPeriodicRefresh(refreshImmediately: refreshImmediately)
        } else {
            cancelPeriodicRefresh()
        }
    }

    private func cancelPeriodicRefresh() {
        periodicRefreshTask?.cancel()
        periodicRefreshTask = nil
    }

    // MARK: - Live update loop

    /// Starts (or restarts) the single live WebSocket update loop for the
    /// current connection.
    ///
    /// The loop holds one subscription open and applies each pushed state
    /// change immediately while the panel is visible and the user left live
    /// updates enabled. Periodic refresh remains the safety net. A dropped
    /// stream reconnects with exponential backoff on the injected clock,
    /// resetting to the base delay once events flowed. The loop ends on
    /// cancellation, panel close, disabled preference, or connection change.
    private func startLiveUpdates() {
        liveUpdateTask?.cancel()
        liveUpdateTask = nil
        guard liveUpdateConfiguration.isEnabled,
              let streamer = liveUpdateStreamer,
              let form = lastConnectedForm,
              isPanelActive,
              displayPreferences.liveUpdatesEnabled
        else {
            return
        }
        let baseDelay = liveUpdateConfiguration.reconnectDelay
        let maximumBackoff = liveUpdateConfiguration.maximumBackoff
        liveUpdateTask = Task { @MainActor [weak self, clock] in
            var reconnectDelay = baseDelay
            while !Task.isCancelled {
                // Re-bind weakly each iteration so a long-running loop never
                // pins the model alive; deinit stays reachable and cancels us.
                guard let current = self, form.sameConnection(as: current.lastConnectedForm) else {
                    return
                }
                current.recordOutboundRequest()
                let receipt = PearchHALiveEventReceipt()
                let failure = await streamer(form) { [weak self] state in
                    await receipt.mark()
                    await MainActor.run {
                        _ = self?.applyLiveState(state)
                    }
                }
                guard !Task.isCancelled, let model = self, form.sameConnection(as: model.lastConnectedForm) else {
                    return
                }
                let eventsFlowed = await receipt.didReceive
                reconnectDelay = eventsFlowed
                    ? baseDelay
                    : PearchDuration(nanoseconds: min(reconnectDelay.nanoseconds * 2, maximumBackoff.nanoseconds))
                model.recordDiagnostic(
                    .liveUpdatesInterrupted,
                    message: "Live updates interrupted: \(PearchHAPanelSnapshot.describe(failure))"
                )
                do {
                    _ = try await clock.sleep(for: reconnectDelay)
                } catch {
                    return
                }
            }
        }
    }

    private func cancelLiveUpdates() {
        liveUpdateTask?.cancel()
        liveUpdateTask = nil
    }

    // MARK: - Diagnostics ring buffer

    /// Records a real diagnostic event into the deduplicating ring buffer using
    /// the model's injected clock instant, then republishes the events and the
    /// derived retry/backoff posture so the Diagnostics view re-renders.
    ///
    /// - Parameters:
    ///   - kind: The event category for a transition that actually happened.
    ///   - message: The sanitized, secret-free message. Callers must pass only
    ///     redacted failure/transition text (never a token).
    private func recordDiagnostic(_ kind: PearchHADiagnosticEventKind, message: String) {
        diagnosticLog.record(kind: kind, message: message, now: lastObservedInstant)
        diagnosticEvents = diagnosticLog.newestFirst
        diagnosticsReferenceInstant = lastObservedInstant
        refreshRetryBackoffState()
    }

    // MARK: - Request-rate diagnostic

    /// Wall-clock timestamps of outbound Home Assistant requests within the
    /// rolling window, pruned on each record.
    private var outboundRequestDates: [Date] = []

    /// The rolling window for the requests-per-minute diagnostic.
    private static let requestRateWindow: TimeInterval = 60

    /// Counts one outbound Home Assistant request (REST call, WebSocket
    /// connect, or service call) for the requests-per-minute diagnostic.
    private func recordOutboundRequest() {
        let now = wallClock()
        outboundRequestDates.append(now)
        let cutoff = now.addingTimeInterval(-Self.requestRateWindow)
        if let first = outboundRequestDates.first, first < cutoff {
            outboundRequestDates.removeAll { $0 < cutoff }
        }
    }

    /// The number of outbound Home Assistant requests within the last minute,
    /// shown by the Diagnostics tab.
    ///
    /// - Returns: The request count in the rolling one-minute window ending now.
    public func requestsPerMinute() -> Int {
        let cutoff = wallClock().addingTimeInterval(-Self.requestRateWindow)
        return outboundRequestDates.filter { $0 >= cutoff }.count
    }

    /// The footer caption for a fresh update: a real, human-readable clock
    /// time ("Updated at 15:48:03") instead of a vague "just now".
    static func updatedDescription(at date: Date) -> String {
        "Updated at \(Self.updatedTimeFormatter.string(from: date))"
    }

    private static let updatedTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        // Minutes are enough for a glanceable "how fresh" answer; seconds
        // would tick constantly for no information gain.
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter
    }()

    /// A short, relative age label for a diagnostic event ("just now", "2m ago"),
    /// computed from the monotonic gap between the event and the latest observed
    /// clock instant. Pure; carries no secret.
    public func relativeAgeDescription(for event: PearchHADiagnosticEvent) -> String {
        let elapsedNanos = max(0, diagnosticsReferenceInstant.nanosecondsSinceStart - event.lastSeen.nanosecondsSinceStart)
        let seconds = elapsedNanos / 1_000_000_000
        if seconds < 5 {
            return "just now"
        }
        if seconds < 60 {
            return "\(seconds)s ago"
        }
        let minutes = seconds / 60
        if minutes < 60 {
            return "\(minutes)m ago"
        }
        let hours = minutes / 60
        return "\(hours)h ago"
    }

    /// Recomputes the published retry/backoff posture from the live connection
    /// state and the periodic-refresh backoff streak. Pure derivation; no I/O.
    private func refreshRetryBackoffState() {
        let next: PearchHARetryBackoffState
        switch snapshot.connectionState {
        case .connected:
            next = .connected
        case .connecting:
            next = lastConnectedForm == nil ? .connecting : .reconnecting(attempt: snapshot.refreshCount)
        case let .reconnecting(attempt):
            next = .reconnecting(attempt: attempt)
        case .disconnected:
            next = .disconnected
        case .failed:
            if periodicRefreshFailureStreak > 0 {
                let seconds = Int(periodicRefreshDelay().nanoseconds / 1_000_000_000)
                next = .backingOff(failureStreak: periodicRefreshFailureStreak, nextRetrySeconds: max(0, seconds))
            } else {
                next = .disconnected
            }
        }
        if retryBackoffState != next {
            retryBackoffState = next
        }
    }

    /// Empties the diagnostic ring buffer.
    ///
    /// Wired to the Diagnostics "Clear diagnostics" action. Clears only the
    /// recorded event history; the live connection, backoff streak, and values
    /// are untouched.
    public func clearDiagnostics() {
        diagnosticLog.clear()
        diagnosticEvents = []
    }

    /// The current refresh delay, growing exponentially with the failure streak up
    /// to the configured ceiling.
    private func periodicRefreshDelay() -> PearchDuration {
        guard periodicRefreshFailureStreak > 0 else {
            return effectivePeriodicRefreshInterval
        }
        // First failure already doubles the base interval, then 4x, 8x, … capped.
        let multiplier = Int64(1 << min(periodicRefreshFailureStreak, 8))
        let scaled = effectivePeriodicRefreshInterval.nanoseconds.multipliedReportingOverflow(by: multiplier)
        let capped = min(scaled.overflow ? Int64.max : scaled.partialValue, periodicRefreshConfiguration.maximumBackoff.nanoseconds)
        return PearchDuration(nanoseconds: capped)
    }

    /// Runs one refresh and updates the backoff streak from the resulting
    /// connection state. Skips when no session is connected.
    private func runPeriodicRefreshTick() async {
        guard lastConnectedForm != nil else {
            return
        }
        isPeriodicRefreshInFlight = true
        // Background sync is silent: a healthy session keeps its last-known values
        // on screen and overrides them in place when the result lands, so previews
        // never flicker through a reconnecting/stale blip every tick.
        await performRefresh(silent: true)
        isPeriodicRefreshInFlight = false
        if case .failed = snapshot.connectionState {
            periodicRefreshFailureStreak += 1
        } else {
            periodicRefreshFailureStreak = 0
        }
        // Republish the backoff posture now that the streak reflects this tick's
        // outcome (the failure event recorded the pre-increment posture).
        refreshRetryBackoffState()
    }

    /// The panel's displayed entities flattened in display order.
    private func displayedEntityIDs() -> [EntityID] {
        snapshot.rooms.flatMap(\.entities).map(\.id)
    }

    /// Re-arms the existing loop after connection, selection, interval or detail changes.
    /// Daily previews stay current while closed. Other ranges are fetched only for
    /// the open detail. Changes during a request rearm after its results land.
    private func startHistoryBulkSync() {
        if bulkSyncTask != nil, !historyRequests.isEmpty, !protectedHistoryKeys().isEmpty {
            historySyncNeedsReschedule = true
            return
        }
        historySyncNeedsReschedule = false
        bulkSyncTask?.cancel()
        bulkSyncTask = nil
        guard effectiveBulkSyncInterval.nanoseconds > 0,
              lastConnectedForm != nil, !protectedHistoryKeys().isEmpty else {
            return
        }
        let settleDelay = bulkSyncConfiguration.settleDelay
        bulkSyncTask = Task { @MainActor [weak self, clock] in
            do {
                // Coalesce selection and detail changes into one armed loop.
                _ = try await clock.sleep(for: settleDelay)
            } catch {
                return
            }
            // Self is re-bound weakly each iteration so the long-lived loop
            // never pins the model; deinit stays reachable and cancels the task.
            while !Task.isCancelled {
                guard self?.lastConnectedForm != nil,
                      self?.protectedHistoryKeys().isEmpty == false else {
                    return
                }
                // While the connection is failed, fetching is pointless: the
                // periodic refresh (with its own exponential backoff) drives
                // recovery, and hammering every batch across every fallback URL
                // each cycle would just amplify the outage. Skip, keep sleeping.
                self?.historySyncNeedsReschedule = false
                if self?.connectionStateIsFailed == false {
                    await self?.runBulkSyncCycle()
                }
                guard !Task.isCancelled else {
                    return
                }
                do {
                    let now = await clock.now()
                    guard let delay = self.map({ model in
                        model.historySyncNeedsReschedule
                            ? model.bulkSyncConfiguration.settleDelay
                            : model.nextHistorySyncDelay(now: now)
                    }) else { return }
                    _ = try await clock.sleep(for: delay)
                } catch {
                    return
                }
            }
        }
    }

    /// Wake when the oldest selected key is due, including a cache reopened just
    /// before its deadline. Failed or missing keys retry at their normal interval.
    private func nextHistorySyncDelay(now: PearchInstant) -> PearchDuration {
        let delays = protectedHistoryKeys().map { key in
            let interval = historyRefreshInterval(for: key).nanoseconds
            guard let fetchedAt = historyCache.fetchedAt(for: key) else { return interval }
            let remaining = interval - (now.nanosecondsSinceStart - fetchedAt.nanosecondsSinceStart)
            return remaining > 0 ? remaining : interval
        }
        return PearchDuration(nanoseconds: delays.min() ?? effectiveBulkSyncInterval.nanoseconds)
    }

    private func cancelHistoryBulkSync() {
        bulkSyncTask?.cancel()
        bulkSyncTask = nil
    }

    /// Fetches only due daily previews and the opened detail, in bounded batches.
    private func runBulkSyncCycle() async {
        guard let form = lastConnectedForm, transientUITrackingDepth == 0 else { return }
        let now = await clock.now()
        guard !Task.isCancelled, form.sameConnection(as: lastConnectedForm) else { return }
        let targets = protectedHistoryKeys().filter { historyIsDue($0, now: now) && historyRequests[$0] == nil }
        let requestID = UUID()
        beginHistoryRequest(Array(targets), requestID: requestID)
        defer { finishHistoryRequest(Array(targets), requestID: requestID) }
        let byRange = Dictionary(grouping: targets, by: \.range)
        var batches: [(range: HistoryRange, ids: [EntityID])] = []
        for range in HistoryRange.allCases {
            let keys = byRange[range] ?? []
            let ids = keys.map(\.entityID).sorted { $0.rawValue < $1.rawValue }
            for index in stride(from: 0, to: ids.count, by: bulkSyncConfiguration.batchSize) {
                batches.append((range, Array(ids[index..<min(index + bulkSyncConfiguration.batchSize, ids.count)])))
            }
        }
        for index in stride(from: 0, to: batches.count, by: bulkSyncConfiguration.maxConcurrentBatches) {
            guard !Task.isCancelled, form.sameConnection(as: lastConnectedForm) else { return }
            let activeKeys = protectedHistoryKeys()
            let window = batches[index..<min(index + bulkSyncConfiguration.maxConcurrentBatches, batches.count)].compactMap { batch -> (range: HistoryRange, ids: [EntityID])? in
                let ids = batch.ids.filter { activeKeys.contains(PearchHAHistoryCacheKey(entityID: $0, range: batch.range)) }
                return ids.isEmpty ? nil : (batch.range, ids)
            }
            for _ in window { recordOutboundRequest() }
            let results = await withTaskGroup(of: [PearchHAHistoryCacheKey: HistorySeries].self) { group in
                for batch in window {
                    group.addTask { [bulkHistoryProvider] in
                        let partial = await bulkHistoryProvider(form, batch.ids, batch.range)
                        var keyed: [PearchHAHistoryCacheKey: HistorySeries] = [:]
                        for id in batch.ids {
                            if let series = partial[id], series.entityID == id, series.range == batch.range {
                                keyed[PearchHAHistoryCacheKey(entityID: id, range: batch.range)] = series
                            }
                        }
                        return keyed
                    }
                }
                var merged: [PearchHAHistoryCacheKey: HistorySeries] = [:]
                for await partial in group { merged.merge(partial) { _, new in new } }
                return merged
            }
            let now = await clock.now()
            guard !Task.isCancelled, form.sameConnection(as: lastConnectedForm) else { return }
            lastObservedInstant = now
            var changedEntities = Set<EntityID>()
            for batch in window {
                for id in batch.ids {
                    let key = PearchHAHistoryCacheKey(entityID: id, range: batch.range)
                    if let series = results[key] {
                        changedEntities.formUnion(insertHistory(series, for: key, now: now))
                    } else {
                        changedEntities.formUnion(markHistoryFailure(key, message: "History could not be refreshed."))
                    }
                }
            }
            let finishedKeys = window.flatMap { batch in
                batch.ids.map { PearchHAHistoryCacheKey(entityID: $0, range: batch.range) }
            }
            finishHistoryRequest(finishedKeys, requestID: requestID, completed: true, changedEntities: changedEntities)
        }
    }

    /// Whether the current connection has failed, including retained stale values.
    private var connectionStateIsFailed: Bool {
        if case .failed = snapshot.connectionState { return true }
        return false
    }

    /// Dismisses the visible history popover, optionally only when it still
    /// belongs to a specific entity anchor.
    ///
    /// SwiftUI may send a dismissal callback from the previously presented row
    /// while the model has already switched the shared history surface to a new
    /// row. Guarding by `entityID` stops the stale row from clearing the newer
    /// presentation.
    public func dismissHistoryPopover(ifPresenting entityID: EntityID? = nil) {
        if let entityID, snapshot.historyPresentationEntityID != entityID {
            return
        }
        let wasPresenting = snapshot.historyPresentationEntityID != nil
        historyTask?.cancel()
        historyTask = nil
        historyRequestGeneration += 1
        applyHistoryPresentationEntityID(nil)
        if case .loading = snapshot.historyState {
            applyHistoryState(.idle)
        }
        if wasPresenting { startHistoryBulkSync() }
    }

    private func refreshSettingsSelectionTreeIfNeeded(newSnapshot: PearchHAPanelSnapshot) {
        let newSignature = SettingsSelectionTreeSignature(snapshot: newSnapshot)
        guard settingsSelectionTreeSignature != newSignature else {
            return
        }
        let interval = performanceSignposter.beginInterval("RefreshSettingsSelectionTree")
        defer {
            performanceSignposter.endInterval("RefreshSettingsSelectionTree", interval)
        }
        settingsSelectionTreeSignature = newSignature
        settingsSelectionTree = newSnapshot.selectionTree
    }

    public func customActions(for entity: DiscoveredEntity) -> [EntityCustomAction] {
        customActionConfiguration.actions(for: entity.id)
    }

    public var orphanedCustomActions: [EntityCustomAction] {
        let knownEntityIDs = Set(snapshot.availableRooms.flatMap(\.entities).map(\.id))
        guard !knownEntityIDs.isEmpty || snapshot.phase != .firstRun else {
            return []
        }
        return customActionConfiguration.actions.filter { !knownEntityIDs.contains($0.entityID) }
    }

    public func customAction(id: CustomActionID) -> EntityCustomAction? {
        customActionConfiguration.action(id: id)
    }

    @discardableResult
    public func setCustomActionService(_ id: CustomActionID, domain: String, service: String) -> Bool {
        let trimmedDomain = domain.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedService = service.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedDomain.isEmpty,
              !trimmedService.isEmpty,
              let action = customActionConfiguration.action(id: id)
        else {
            customActionPersistenceFailureDescription = "custom action service is incomplete"
            return false
        }
        let metadata = serviceMetadata(domain: trimmedDomain, service: trimmedService)
        let serviceData = serviceDataWithMetadataDefaults(
            action.action.serviceData,
            metadata: metadata,
            actionID: action.id
        )
        return setCustomAction(
            EntityCustomAction(
                id: action.id,
                entityID: action.entityID,
                title: action.title,
                action: ActionSpec(
                    domain: trimmedDomain,
                    service: trimmedService,
                    targetEntityID: action.action.targetEntityID,
                    serviceData: serviceData
                ),
                requiresConfirmation: action.requiresConfirmation
            )
        )
    }

    @discardableResult
    public func setCustomAction(_ action: EntityCustomAction) -> Bool {
        let existingAction = customActionConfiguration.action(id: action.id)
        let sanitized: SanitizedCustomAction
        do {
            sanitized = try sanitize(action: action, existingAction: existingAction)
        } catch {
            customActionPersistenceFailureDescription = String(describing: error)
            return false
        }
        if let failure = sanitized.action.validationFailure() {
            customActionPersistenceFailureDescription = failure.description
            return false
        }
        guard entity(for: sanitized.action.entityID) != nil else {
            customActionPersistenceFailureDescription = "custom action is incomplete"
            return false
        }
        return updateCustomActionConfiguration(
            customActionConfiguration.upserting(sanitized.action),
            persist: true,
            protectedValueUpserts: sanitized.protectedValueUpserts
        )
    }

    @discardableResult
    public func removeCustomAction(_ id: CustomActionID) -> Bool {
        let nextConfiguration = customActionConfiguration.removing(id)
        guard nextConfiguration != customActionConfiguration else {
            return false
        }
        return updateCustomActionConfiguration(nextConfiguration, persist: true)
    }

    @discardableResult
    public func moveCustomAction(_ id: CustomActionID, direction: SelectionMoveDirection) -> Bool {
        guard let action = customActionConfiguration.action(id: id) else {
            return false
        }
        var entityActions = customActionConfiguration.actions(for: action.entityID)
        guard let index = entityActions.firstIndex(where: { $0.id == id }) else {
            return false
        }
        let targetIndex: Int
        switch direction {
        case .up:
            guard index > entityActions.startIndex else {
                return false
            }
            targetIndex = entityActions.index(before: index)
        case .down:
            guard index < entityActions.index(before: entityActions.endIndex) else {
                return false
            }
            targetIndex = entityActions.index(after: index)
        }
        entityActions.swapAt(index, targetIndex)
        var reorderedEntityActions = entityActions.makeIterator()
        let nextActions = customActionConfiguration.actions.map { existingAction in
            existingAction.entityID == action.entityID ? reorderedEntityActions.next() ?? existingAction : existingAction
        }
        return updateCustomActionConfiguration(CustomActionConfiguration(actions: nextActions), persist: true)
    }

    @discardableResult
    public func setCustomActionServiceDataValue(_ id: CustomActionID, key: String, value: ActionValue) -> Bool {
        setCustomActionServiceDataValue(id, path: [.key(key)], value: value)
    }

    @discardableResult
    public func setCustomActionServiceDataValue(
        _ id: CustomActionID,
        path: [PearchHACustomActionServiceDataPathComponent],
        value: ActionValue
    ) -> Bool {
        updateCustomActionServiceData(id) { serviceData in
            PearchHAActionValuePathEditor.set(value, at: path, in: &serviceData)
        }
    }

    @discardableResult
    public func appendCustomActionServiceDataArrayValue(
        _ id: CustomActionID,
        path: [PearchHACustomActionServiceDataPathComponent],
        value: ActionValue
    ) -> Bool {
        updateCustomActionServiceData(id) { serviceData in
            PearchHAActionValuePathEditor.appendArrayValue(value, at: path, in: &serviceData)
        }
    }

    @discardableResult
    public func setCustomActionServiceDataText(
        _ id: CustomActionID,
        path: [PearchHACustomActionServiceDataPathComponent],
        text: String,
        kind: PearchHACustomActionServiceDataValueKind
    ) -> Bool {
        if isSensitiveServiceDataPath(path),
           text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let removed = removeCustomActionServiceDataValue(id, path: path)
            if removed {
                clearProtectedValueDraft(id: id, path: path)
            }
            return removed
        }
        guard let value = Self.customActionServiceDataValue(text: text, kind: kind) else {
            customActionPersistenceFailureDescription = "custom action service data value is invalid"
            return false
        }
        let updated = setCustomActionServiceDataValue(id, path: path, value: value)
        if updated, isSensitiveServiceDataPath(path) {
            setProtectedValueDraft(text, id: id, path: path)
        }
        return updated
    }

    @discardableResult
    public func setCustomActionServiceDataType(
        _ id: CustomActionID,
        path: [PearchHACustomActionServiceDataPathComponent],
        kind: PearchHACustomActionServiceDataValueKind
    ) -> Bool {
        guard let action = customAction(id: id),
              let value = PearchHAActionValuePathEditor.value(at: path, in: action.action.serviceData)
        else {
            customActionPersistenceFailureDescription = "custom action service data path is invalid"
            return false
        }
        let text = value.isInlineEditable ? value.editorText : ""
        return setCustomActionServiceDataText(id, path: path, text: text, kind: kind)
    }

    @discardableResult
    public func renameCustomActionServiceDataKey(
        _ id: CustomActionID,
        parentPath: [PearchHACustomActionServiceDataPathComponent],
        from oldKey: String,
        to newKey: String
    ) -> Bool {
        updateCustomActionServiceData(id) { serviceData in
            PearchHAActionValuePathEditor.renameKey(parentPath: parentPath, from: oldKey, to: newKey, in: &serviceData)
        }
    }

    @discardableResult
    public func removeCustomActionServiceDataValue(
        _ id: CustomActionID,
        path: [PearchHACustomActionServiceDataPathComponent]
    ) -> Bool {
        updateCustomActionServiceData(id) { serviceData in
            PearchHAActionValuePathEditor.remove(at: path, in: &serviceData)
        }
    }

    @discardableResult
    public func moveCustomActionServiceDataArrayValue(
        _ id: CustomActionID,
        path: [PearchHACustomActionServiceDataPathComponent],
        direction: SelectionMoveDirection
    ) -> Bool {
        updateCustomActionServiceData(id) { serviceData in
            PearchHAActionValuePathEditor.moveArrayValue(at: path, direction: direction, in: &serviceData)
        }
    }

    @discardableResult
    private func updateCustomActionServiceData(
        _ id: CustomActionID,
        update: (inout [String: ActionValue]) -> Bool
    ) -> Bool {
        guard let action = customActionConfiguration.action(id: id) else {
            customActionPersistenceFailureDescription = "custom action service data path is invalid"
            return false
        }
        var serviceData = action.action.serviceData
        guard update(&serviceData) else {
            customActionPersistenceFailureDescription = "custom action service data path is invalid"
            return false
        }
        return setCustomAction(action.withServiceData(serviceData))
    }

    @discardableResult
    public func setCustomActionServiceDataText(
        _ id: CustomActionID,
        key: String,
        text: String,
        kind: PearchHACustomActionServiceDataValueKind
    ) -> Bool {
        let path: [PearchHACustomActionServiceDataPathComponent] = [.key(key)]
        if isSensitiveServiceDataPath(path),
           text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let removed = removeCustomActionServiceDataKey(id, key: key)
            if removed {
                clearProtectedValueDraft(id: id, path: path)
            }
            return removed
        }
        guard let value = Self.customActionServiceDataValue(text: text, kind: kind) else {
            customActionPersistenceFailureDescription = "custom action service data value is invalid"
            return false
        }
        let updated = setCustomActionServiceDataValue(id, key: key, value: value)
        if updated, isSensitiveServiceDataPath(path) {
            setProtectedValueDraft(text, id: id, path: path)
        }
        return updated
    }

    @discardableResult
    public func renameCustomActionServiceDataKey(_ id: CustomActionID, from oldKey: String, to newKey: String) -> Bool {
        let trimmedOldKey = oldKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedNewKey = newKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedOldKey.isEmpty,
              !trimmedNewKey.isEmpty,
              let action = customActionConfiguration.action(id: id),
              action.action.serviceData[trimmedOldKey] != nil
        else {
            customActionPersistenceFailureDescription = "custom action service data key is incomplete"
            return false
        }
        guard trimmedOldKey == trimmedNewKey || action.action.serviceData[trimmedNewKey] == nil else {
            customActionPersistenceFailureDescription = "custom action service data key is duplicated"
            return false
        }
        return renameCustomActionServiceDataKey(id, parentPath: [], from: oldKey, to: newKey)
    }

    @discardableResult
    public func removeCustomActionServiceDataKey(_ id: CustomActionID, key: String) -> Bool {
        removeCustomActionServiceDataValue(id, path: [.key(key)])
    }

    private static func customActionServiceDataValue(
        text: String,
        kind: PearchHACustomActionServiceDataValueKind
    ) -> ActionValue? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        switch kind {
        case .string:
            return .string(text)
        case .number:
            guard !trimmed.isEmpty else {
                return .number(0)
            }
            guard let value = Double(trimmed),
                  value.isFinite
            else {
                return nil
            }
            return .number(value)
        case .bool:
            guard !trimmed.isEmpty else {
                return .bool(false)
            }
            switch trimmed.lowercased() {
            case "true", "1", "yes", "on":
                return .bool(true)
            case "false", "0", "no", "off":
                return .bool(false)
            default:
                return nil
            }
        case .object:
            return .object([:])
        case .array:
            return .array([])
        }
    }

    private func serviceMetadata(domain: String, service: String) -> HAServiceMetadata? {
        snapshot.serviceMetadata.first { $0.domain == domain && $0.service == service }
    }

    private func serviceDataWithMetadataDefaults(
        _ existing: [String: ActionValue],
        metadata: HAServiceMetadata?,
        actionID: CustomActionID
    ) -> [String: ActionValue] {
        guard let metadata else {
            return existing
        }
        var serviceData = existing
        for field in metadata.fields where serviceData[field.key] == nil && !Self.isTargetField(field.key) {
            if ActionSpec.isSensitiveServiceDataKey(field.key) {
                serviceData[field.key] = .protectedString(freshProtectedValueReference(for: actionID))
            } else {
                serviceData[field.key] = field.example ?? .string("")
            }
        }
        return serviceData
    }

    private static func isTargetField(_ key: String) -> Bool {
        ["entity_id", "device_id", "area_id", "target"].contains(key.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())
    }

    @discardableResult
    public func startCustomAction(_ id: CustomActionID, confirmed: Bool = false) -> Bool {
        guard let action = customActionConfiguration.action(id: id),
              confirmed || !action.requiresConfirmation else { return false }
        return startControlAction { await $0.runCustomAction(id, confirmed: confirmed) }
    }

    private func startControlAction(_ action: @escaping @MainActor (PearchHAPanelModel) async -> Bool) -> Bool {
        guard !snapshot.controlActionState.isRunning else { return false }
        controlActionTask?.cancel()
        controlActionTask = Task { @MainActor [weak self] in
            guard let self else { return }
            _ = await action(self)
            if !Task.isCancelled { controlActionTask = nil }
        }
        return true
    }

    @discardableResult
    public func runCustomAction(_ id: CustomActionID, confirmed: Bool = false) async -> Bool {
        guard !snapshot.controlActionState.isRunning else {
            return false
        }
        guard let action = customActionConfiguration.action(id: id) else {
            return false
        }
        guard confirmed || !action.requiresConfirmation else {
            return false
        }
        guard let form = lastConnectedForm else {
            applyControlActionState(
                .failed(entityID: action.entityID, message: "action requires a connected Home Assistant session"),
                lastUpdateDescription: "Action unavailable"
            )
            return false
        }

        applyControlActionState(
            .running(entityID: action.entityID),
            lastUpdateDescription: "Running \(action.title)"
        )
        let resolvedAction: ActionSpec
        do {
            // Keychain reads are synchronous system calls; resolve off the main
            // actor so the click that triggered the action never stalls the UI.
            let store = protectedActionValueStore
            let spec = action.action
            resolvedAction = try await Task.detached(priority: .userInitiated) {
                try spec.resolvedProtectedValues(using: store.load)
            }.value
        } catch {
            applyControlActionState(
                .failed(entityID: action.entityID, message: String(describing: error)),
                lastUpdateDescription: "Action unavailable for \(action.title)"
            )
            return false
        }
        recordOutboundRequest()
        let result = await actionRunner(form, resolvedAction)
        guard !Task.isCancelled else {
            return false
        }

        switch result {
        case .success:
            applyControlActionState(.idle, lastUpdateDescription: "Ran \(action.title)")
            return true
        case let .failed(message):
            applyControlActionState(
                .failed(entityID: action.entityID, message: message),
                lastUpdateDescription: "Action failed for \(action.title)"
            )
            return false
        }
    }

    /// Requested presentation values never replace Home Assistant's reported telemetry.
    func requestedControlValue(for id: EntityID, controlID: String) -> ActionValue? {
        requestedControlValues[id]?[controlID]?.value
    }

    func hasRequestedControls(for id: EntityID) -> Bool {
        requestedControlValues[id]?.isEmpty == false
    }

    var requestedControlsPublisher: AnyPublisher<Void, Never> {
        $requestedControlValues.map { _ in () }.eraseToAnyPublisher()
    }

    private func clearRequestedControls(requestID: UUID) {
        let remaining = requestedControlValues.mapValues { $0.filter { $0.value.requestID != requestID } }
            .filter { !$0.value.isEmpty }
        if remaining != requestedControlValues { requestedControlValues = remaining }
    }

    private func finishRequestedControls(for id: EntityID, entity: DiscoveredEntity?, reporting requests: [String: RequestedControlValue]) {
        guard var pending = requestedControlValues[id] else { return }
        let fields = entity.map(PearchHAEntityControlField.controls(for:)) ?? []
        for (controlID, request) in requests where pending[controlID]?.requestID == request.requestID {
            let hasReport: Bool
            if entity == nil || entity?.state == "unavailable" {
                hasReport = true
            } else if controlID == "state" {
                hasReport = true
            } else if controlID == "position" {
                hasReport = entity?.currentPosition != nil
            } else if let field = fields.first(where: { $0.id == controlID }) {
                hasReport = field.input.reportedValue != nil || field.actionSpec(value: request.value) == nil
            } else {
                hasReport = true // The control is no longer supported.
            }
            if hasReport {
                pending[controlID] = nil
                if controlID == "state", pendingControlChange?.entityID == id {
                    pendingControlChange = nil
                }
            }
        }
        if pending != requestedControlValues[id] {
            requestedControlValues[id] = pending.isEmpty ? nil : pending
        }
    }

    /// Schedules a capability-derived control. True means scheduled, not validated or executed.
    /// Returns false while another action is pending; execution failures appear in controlActionState.
    @discardableResult
    public func startEntityControlValue(_ id: EntityID, controlID: String, value: ActionValue? = nil, confirmed: Bool = false) -> Bool {
        guard controlActionTask == nil else { return false }
        return startControlAction {
            await $0.setEntityControlValue(id, controlID: controlID, value: value, confirmed: confirmed)
        }
    }

    /// Validates against the latest entity capabilities, then sends one action through the shared runner.
    /// No device state is guessed locally. A successful action refreshes state from Home Assistant.
    /// Returns false for unavailable controls, invalid input, missing confirmation, cancellation or service failure.
    /// A successful command returns true even if its follow-up refresh fails; the stale-state warning stays visible.
    @discardableResult
    public func setEntityControlValue(_ id: EntityID, controlID: String, value: ActionValue? = nil, confirmed: Bool = false) async -> Bool {
        guard !Task.isCancelled, !snapshot.controlActionState.isRunning else { return false }
        guard snapshot.connectionState == .connected, let form = lastConnectedForm,
              let entity = entity(for: id),
              let field = PearchHAEntityControlField.controls(for: entity).first(where: { $0.id == controlID }),
              let action = field.actionSpec(value: value),
              confirmed || !field.requiresConfirmation else {
            applyControlActionState(.failed(entityID: id, message: "Control unavailable, invalid value, or confirmation required"))
            return false
        }
        let requestID = UUID()
        activeValueControlRequestID = requestID
        if let value, field.input.reportsValue {
            requestedControlValues[id, default: [:]][controlID] = RequestedControlValue(requestID: requestID, value: value)
        }
        defer {
            if activeValueControlRequestID == requestID {
                activeValueControlRequestID = nil
                if Task.isCancelled {
                    clearRequestedControls(requestID: requestID)
                    applyControlActionState(.idle)
                }
            }
        }
        applyControlActionState(.running(entityID: id), lastUpdateDescription: "Updating \(entity.name)")
        recordOutboundRequest()
        let result = await actionRunner(form, action)
        guard !Task.isCancelled, activeValueControlRequestID == requestID, form.sameConnection(as: lastConnectedForm) else { return false }
        switch result {
        case .success:
            await performRefresh(silent: true)
            guard !Task.isCancelled, activeValueControlRequestID == requestID else { return false }
            if snapshot.connectionState == .connected {
                applyControlActionState(.idle)
            } else {
                applyControlActionState(.failed(entityID: id, message: "Command sent. State refresh failed; values may be stale."))
            }
            return true
        case let .failed(message):
            clearRequestedControls(requestID: requestID)
            applyControlActionState(.failed(entityID: id, message: message), lastUpdateDescription: "Control failed for \(entity.name)")
            return false
        }
    }

    @discardableResult
    public func startEntityControlToggle(_ id: EntityID, isOn: Bool) -> Bool {
        guard canToggleEntityControl(id, isOn: isOn) else { return false }
        return startControlAction { await $0.setEntityControl(id, isOn: isOn) }
    }

    @discardableResult
    public func startCoverControl(_ id: EntityID, command: PearchHACoverCommand) -> Bool {
        guard canRunCoverControl(id, command: command) else { return false }
        return startControlAction { await $0.setCoverControl(id, command: command) }
    }

    @discardableResult
    public func startCoverPositionChange(_ id: EntityID, position: Int) -> Bool {
        startCoverControl(id, command: .setPosition(position))
    }

    @discardableResult
    public func setEntityControl(_ id: EntityID, isOn: Bool) async -> Bool {
        guard !snapshot.controlActionState.isRunning else {
            return false
        }
        guard let form = lastConnectedForm else {
            applyControlActionState(
                .failed(entityID: id, message: "control requires a connected Home Assistant session"),
                lastUpdateDescription: "Control unavailable"
            )
            return false
        }
        guard let entity = entity(for: id),
              let control = PearchHAEntityControl(entity: entity, actionState: snapshot.controlActionState)
        else {
            applyControlActionState(
                .failed(entityID: id, message: "entity does not support built-in controls"),
                lastUpdateDescription: "Control unavailable"
            )
            return false
        }
        let currentIsOn = requestedControlValue(for: id, controlID: "state")?.controlString.map { $0 == "on" } ?? control.isOn
        guard currentIsOn != isOn else {
            applyControlActionState(.idle)
            return false
        }

        return await runOptimisticControl(
            entity, form: form, action: control.actionSpec(targetIsOn: isOn),
            targetState: PearchHAEntityControl.optimisticState(isOn: isOn),
            targetPosition: entity.currentPosition
        )
    }

    @discardableResult
    public func setCoverPosition(_ id: EntityID, position: Int) async -> Bool {
        await setCoverControl(id, command: .setPosition(position))
    }

    @discardableResult
    public func setCoverControl(_ id: EntityID, command: PearchHACoverCommand) async -> Bool {
        guard !snapshot.controlActionState.isRunning else {
            return false
        }
        guard let form = lastConnectedForm else {
            applyControlActionState(
                .failed(entityID: id, message: "control requires a connected Home Assistant session"),
                lastUpdateDescription: "Control unavailable"
            )
            return false
        }
        guard let entity = entity(for: id),
              let control = PearchHACoverControl(entity: entity, actionState: snapshot.controlActionState)
        else {
            applyControlActionState(
                .failed(entityID: id, message: "entity does not support built-in controls"),
                lastUpdateDescription: "Control unavailable"
            )
            return false
        }
        if case .setPosition = command, control.position == nil {
            applyControlActionState(
                .failed(entityID: id, message: "cover does not report a position"),
                lastUpdateDescription: "Control unavailable"
            )
            return false
        }
        if case .setPosition = command {
            let currentPosition = requestedControlValue(for: id, controlID: "position")?.controlNumber.map(Int.init) ?? control.position
            if command.clampedPosition == currentPosition {
                applyControlActionState(.idle)
                return false
            }
        }

        return await runOptimisticControl(
            entity, form: form, action: control.actionSpec(command: command),
            targetState: control.optimisticState(command: command, currentState: entity.state),
            targetPosition: control.optimisticPosition(command: command)
        )
    }

    private func runOptimisticControl(
        _ entity: DiscoveredEntity, form: PearchHAConnectionForm, action: ActionSpec,
        targetState: String, targetPosition: Int?
    ) async -> Bool {
        let id = entity.id
        let previousState = entity.state
        let previousPosition = entity.currentPosition
        let requestID = UUID()
        requestedControlValues[id, default: [:]]["state"] = RequestedControlValue(requestID: requestID, value: .string(targetState))
        if entity.id.domain == "cover", let targetPosition {
            requestedControlValues[id]?["position"] = RequestedControlValue(requestID: requestID, value: .number(Double(targetPosition)))
        }
        pendingControlChange = PendingControlChange(
            entityID: id,
            previousState: previousState,
            previousPosition: previousPosition,
            targetState: targetState,
            targetPosition: targetPosition,
            name: entity.name
        )
        applyControlEntitySnapshot(
            id,
            state: targetState,
            currentPosition: targetPosition,
            actionState: .running(entityID: id),
            lastUpdateDescription: "Updating \(entity.name)"
        )

        recordOutboundRequest()
        let result = await actionRunner(form, action)
        guard !Task.isCancelled else {
            return false
        }

        switch result {
        case .success:
            pendingControlChange = nil
            // A report received during the service call already owns the displayed state.
            applyControlActionState(.idle, lastUpdateDescription: "Requested \(entity.name)")
            return true
        case let .failed(message):
            pendingControlChange = nil
            let stillAwaitingReport = requestedControlValues[id]?["state"]?.requestID == requestID
            clearRequestedControls(requestID: requestID)
            guard stillAwaitingReport else {
                applyControlActionState(.failed(entityID: id, message: message))
                return false
            }
            applyControlEntitySnapshot(
                id,
                state: previousState,
                currentPosition: previousPosition,
                actionState: .failed(entityID: id, message: message),
                lastUpdateDescription: "Control failed for \(entity.name)"
            )
            return false
        }
    }

    public func cancelInFlightAction() {
        actionTask?.cancel()
        actionTask = nil
        controlActionTask?.cancel()
        controlActionTask = nil
        activeValueControlRequestID = nil
        requestedControlValues = [:]
        if let rollback = pendingControlChange {
            pendingControlChange = nil
            applyControlEntitySnapshot(
                rollback.entityID,
                state: rollback.previousState,
                currentPosition: rollback.previousPosition,
                actionState: .idle,
                lastUpdateDescription: "Control canceled for \(rollback.name)"
            )
        } else if snapshot.controlActionState.isRunning {
            applyControlActionState(.idle)
        }

        switch snapshot.connectionState {
        case .connecting:
            updateSnapshot { draft in
                draft.connectionState = .disconnected
                draft.phase = .firstRun
                draft.canRetry = false
            }
        case .reconnecting:
            updateSnapshot { draft in
                draft.connectionState = .reconnecting(attempt: snapshot.refreshCount)
                draft.phase = .reconnecting(attempt: snapshot.refreshCount)
                draft.canRetry = lastConnectedForm != nil
            }
        case .disconnected, .connected, .failed:
            break
        }
    }

    private func applyHistoryState(_ historyState: PearchHAHistoryPanelState) {
        guard snapshot.historyState != historyState else { return }
        updateSnapshot { draft in
            draft.historyState = historyState
        }
    }

    private func applyHistoryPresentationEntityID(_ entityID: EntityID?) {
        updateSnapshot { draft in
            draft.historyPresentationEntityID = entityID
        }
    }

    private func canToggleEntityControl(_ id: EntityID, isOn: Bool) -> Bool {
        guard let entity = entity(for: id),
              let control = PearchHAEntityControl(entity: entity, actionState: snapshot.controlActionState)
        else {
            return false
        }
        let currentIsOn = requestedControlValue(for: id, controlID: "state")?.controlString.map { $0 == "on" } ?? control.isOn
        return currentIsOn != isOn
    }

    private func canRunCoverControl(_ id: EntityID, command: PearchHACoverCommand) -> Bool {
        guard let entity = entity(for: id),
              let control = PearchHACoverControl(entity: entity, actionState: snapshot.controlActionState)
        else {
            return false
        }
        if case .setPosition = command {
            guard control.position != nil else {
                return false
            }
            let currentPosition = requestedControlValue(for: id, controlID: "position")?.controlNumber.map(Int.init) ?? control.position
            return command.clampedPosition != currentPosition
        }
        return true
    }

    private func applyControlActionState(
        _ actionState: PearchHAControlActionState,
        lastUpdateDescription: String? = nil
    ) {
        updateSnapshot { draft in
            draft.lastUpdateDescription = lastUpdateDescription ?? snapshot.lastUpdateDescription
            draft.controlActionState = actionState
        }
    }

    @discardableResult
    private func applyControlEntitySnapshot(
        _ id: EntityID,
        state: String,
        currentPosition: Int?,
        actionState: PearchHAControlActionState,
        lastUpdateDescription: String
    ) -> Bool {
        var didUpdate = false
        let availableRooms = replacingEntitySnapshot(
            in: snapshot.availableRooms,
            id: id,
            state: state,
            currentPosition: currentPosition,
            didUpdate: &didUpdate
        )
        guard didUpdate else {
            applyControlActionState(
                .failed(entityID: id, message: "entity disappeared before the control action completed"),
                lastUpdateDescription: "Control unavailable"
            )
            return false
        }

        if let roomIndex = availableEntityLocations[id]?.roomIndex,
           let entityIndex = availableEntityLocations[id]?.entityIndex,
           availableRooms.indices.contains(roomIndex),
           availableRooms[roomIndex].entities.indices.contains(entityIndex) {
            let updatedEntity = availableRooms[roomIndex].entities[entityIndex]
            availableEntitiesByID[id] = updatedEntity
            if let flatIndex = availableEntities.firstIndex(where: { $0.id == id }) {
                availableEntities[flatIndex] = updatedEntity
            }
            invalidateDisplayCaches(affectedBy: id)
        }

        let visibleRooms = selectedRooms(from: availableRooms, using: snapshot.selectionConfiguration)
        let nextPhase: PearchHAPanelPhase
        switch snapshot.phase {
        case .connectedData, .connectedEmpty:
            nextPhase = visibleRooms.isEmpty ? .connectedEmpty : .connectedData
        case .firstRun, .connecting, .reconnecting, .failed, .failedStale:
            nextPhase = snapshot.phase
        }
        updateSnapshot { draft in
            draft.phase = nextPhase
            draft.rooms = visibleRooms
            draft.availableRooms = availableRooms
            draft.lastUpdateDescription = lastUpdateDescription
            draft.controlActionState = actionState
        }
        return true
    }

    private func replacingEntitySnapshot(
        in rooms: [Room],
        id: EntityID,
        state: String,
        currentPosition: Int?,
        didUpdate: inout Bool
    ) -> [Room] {
        rooms.map { room in
            Room(
                id: room.id,
                name: room.name,
                entities: room.entities.map { entity in
                    guard entity.id == id else {
                        return entity
                    }
                    didUpdate = true
                    return DiscoveredEntity(
                        id: entity.id,
                        name: entity.name,
                        state: state,
                        unit: entity.unit,
                        areaID: entity.areaID,
                        deviceID: entity.deviceID,
                        deviceName: entity.deviceName,
                        deviceManufacturer: entity.deviceManufacturer,
                        deviceModel: entity.deviceModel,
                        deviceDomain: entity.deviceDomain,
                        currentPosition: currentPosition,
                        controlAttributes: entity.controlAttributes
                    )
                }
            )
        }
    }

    /// Signs the user out, returning the panel to a disconnected first-run state.
    ///
    /// Cancels any in-flight work, drops the in-memory access token and any stored
    /// auth-session flag, clears the live rooms, and invokes the injected
    /// ``SignOutHandler`` so the app shell can clear the Keychain session and
    /// persisted access token. The saved connection URL/fallback profile is kept
    /// so the user can reconnect without re-entering it.
    public func signOut() {
        actionTask?.cancel()
        actionTask = nil
        controlActionTask?.cancel()
        controlActionTask = nil
        activeValueControlRequestID = nil
        requestedControlValues = [:]
        historyTask?.cancel()
        historyTask = nil
        historyRequestGeneration += 1
        pendingControlChange = nil
        evictAllHistory()
        cancelHistoryBulkSync()
        cancelPeriodicRefresh()
        cancelLiveUpdates()
        lastConnectedForm = nil
        oauthSignInState = .idle

        editableForm = PearchHAConnectionForm(
            urlString: editableForm.urlString,
            addresses: editableForm.addresses,
            token: "",
            usesStoredAuthSession: false,
            allowsSelfSignedCertificates: editableForm.allowsSelfSignedCertificates
        )
        updateSnapshot { draft in
            draft.connectionState = .disconnected
            draft.phase = .firstRun
            draft.rooms = []
            draft.connectionForm = nonSecretForm(editableForm)
            draft.canRetry = false
            draft.hasTokenInput = false
            draft.serviceMetadataFailureDescription = nil
            draft.historyState = .idle
            draft.historyPresentationEntityID = nil
            draft.controlActionState = .idle
            draft.serviceMetadata = []
        }
        signOutHandler()
    }

    public func connect() async {
        let reporting = requestedControlValues
        lastObservedInstant = await clock.now()
        let form = editableForm
        if let failure = form.validationFailure {
            applyFailure(failure, refreshCount: snapshot.refreshCount, canRetry: false)
            return
        }

        updateSnapshot { draft in
            draft.connectionState = .connecting
            draft.phase = .connecting
            draft.connectionForm = nonSecretForm(form)
            draft.canRetry = false
            draft.hasTokenInput = hasToken(in: form)
        }
        recordOutboundRequest()
        let result = await connector(form)
        guard !Task.isCancelled else {
            return
        }
        await apply(result: result, form: form, refreshCount: snapshot.refreshCount, reporting: reporting)
    }

    public func refresh() async {
        await performRefresh(silent: false)
    }

    /// Refreshes the session.
    ///
    /// - Parameter silent: When `true` and the session is already healthily
    ///   connected, the in-flight refresh does NOT flip the UI into a visible
    ///   `.reconnecting` state. That matters because `.reconnecting` marks values
    ///   stale, which collapses bounded-gauge previews to placeholders and makes
    ///   inline previews flicker on every background tick. A silent sync keeps the
    ///   last-known values on screen and simply overrides them in place when the
    ///   result lands; genuine failures still surface via ``applyFailure`` below.
    ///   When the session is not currently healthy (recovering), `silent` has no
    ///   effect so reconnection remains visible.
    private func performRefresh(silent: Bool) async {
        guard let form = lastConnectedForm else {
            return
        }
        if transientUITrackingDepth > 0, silent {
            deferredSilentRefreshRequested = true
            return
        }
        let reporting = requestedControlValues
        lastObservedInstant = await clock.now()

        let nextRefreshCount = snapshot.refreshCount + 1
        let isHealthyConnected: Bool
        switch snapshot.phase {
        case .connectedData, .connectedEmpty:
            isHealthyConnected = true
        default:
            isHealthyConnected = false
        }
        if !(silent && isHealthyConnected) {
            // A reconnect attempt is only diagnostic when we are recovering from a
            // failure; a routine healthy periodic/manual refresh is not noise-worthy.
            if diagnosticIsDegraded {
                recordDiagnostic(.reconnecting, message: "Reconnecting, attempt \(nextRefreshCount)")
            }
            updateSnapshot { draft in
                draft.connectionState = .reconnecting(attempt: nextRefreshCount)
                draft.phase = .reconnecting(attempt: nextRefreshCount)
                draft.refreshCount = nextRefreshCount
                draft.canRetry = false
                draft.hasTokenInput = hasToken(in: form)
            }
        }
        recordOutboundRequest()
        let result = await connector(form)
        guard !Task.isCancelled else {
            return
        }
        await apply(result: result, form: form, refreshCount: nextRefreshCount, reporting: reporting)
    }

    @discardableResult
    public func applyLiveState(_ state: EntityState) -> Bool {
        applyLiveState(state, reporting: requestedControlValues[state.id] ?? [:])
    }

    private func applyLiveState(_ state: EntityState, reporting requests: [String: RequestedControlValue]) -> Bool {
        if transientUITrackingDepth > 0 {
            let exists = availableEntityLocations[state.id] != nil
            if exists {
                deferredLiveStates[state.id] = (state, requests)
            }
            return exists
        }
        guard let location = availableEntityLocations[state.id] else {
            return false
        }
        if shouldDeferBackgroundLiveState(for: state.id) {
            deferredBackgroundLiveStates[state.id] = (state, requests)
            return true
        }
        let signpostID = performanceSignposter.makeSignpostID()
        let interval = performanceSignposter.beginInterval("ApplyLiveState", id: signpostID)
        defer {
            performanceSignposter.endInterval("ApplyLiveState", interval)
        }

        var availableRooms = snapshot.availableRooms
        let room = availableRooms[location.roomIndex]
        var entities = room.entities
        let entity = entities[location.entityIndex]
        let updatedEntity = DiscoveredEntity(
            id: entity.id,
            name: Self.preferredLiveEntityName(state.name, existing: entity),
            state: state.state,
            unit: Self.preferredLiveEntityUnit(state.unit, existing: entity),
            areaID: entity.areaID,
            deviceID: entity.deviceID,
            deviceName: entity.deviceName,
            deviceManufacturer: entity.deviceManufacturer,
            deviceModel: entity.deviceModel,
            deviceDomain: entity.deviceDomain,
            currentPosition: state.currentPosition,
            controlAttributes: state.controlAttributes
        )
        finishRequestedControls(for: state.id, entity: updatedEntity, reporting: requests)
        guard updatedEntity != entity else {
            return true
        }
        entities[location.entityIndex] = updatedEntity
        availableRooms[location.roomIndex] = Room(id: room.id, name: room.name, entities: entities)
        availableEntitiesByID[state.id] = updatedEntity
        if let entityIndex = availableEntities.firstIndex(where: { $0.id == state.id }) {
            availableEntities[entityIndex] = updatedEntity
        }
        if updatedEntity.unit != entity.unit {
            averageCandidateCache.removeAll(keepingCapacity: true)
        }
        invalidateDisplayCaches(affectedBy: state.id)

        let visibleRooms = replacingVisibleEntity(updatedEntity, in: snapshot.rooms)
        let nextConnectionState: ConnectionState
        let nextPhase: PearchHAPanelPhase
        switch snapshot.phase {
        case .connectedData, .connectedEmpty:
            nextConnectionState = .connected
            nextPhase = visibleRooms.isEmpty ? .connectedEmpty : .connectedData
        case .firstRun, .connecting, .reconnecting, .failed, .failedStale:
            nextConnectionState = snapshot.connectionState
            nextPhase = snapshot.phase
        }
        updateSnapshot { draft in
            draft.connectionState = nextConnectionState
            draft.phase = nextPhase
            draft.rooms = visibleRooms
            draft.availableRooms = availableRooms
            draft.lastUpdateDescription = Self.updatedDescription(at: wallClock())
        }
        return true
    }

    private func shouldDeferBackgroundLiveState(for id: EntityID) -> Bool {
        guard !isPanelActive,
              !snapshot.menuBarDisplayConfiguration.isPromoted(id),
              snapshot.historyPresentationEntityID != id
        else {
            return false
        }
        return true
    }

    private func flushDeferredBackgroundLiveStates() {
        guard !deferredBackgroundLiveStates.isEmpty else {
            return
        }
        let deferredStates = deferredBackgroundLiveStates.values.sorted { $0.state.id.rawValue < $1.state.id.rawValue }
        deferredBackgroundLiveStates = [:]
        for report in deferredStates {
            _ = applyLiveState(report.state, reporting: report.requests)
        }
    }

    private func replacingVisibleEntity(_ entity: DiscoveredEntity, in rooms: [Room]) -> [Room] {
        var updatedRooms = rooms
        for roomIndex in updatedRooms.indices {
            guard let entityIndex = updatedRooms[roomIndex].entities.firstIndex(where: { $0.id == entity.id }) else {
                continue
            }
            var entities = updatedRooms[roomIndex].entities
            entities[entityIndex] = entity
            updatedRooms[roomIndex] = Room(
                id: updatedRooms[roomIndex].id,
                name: updatedRooms[roomIndex].name,
                entities: entities
            )
            break
        }
        return updatedRooms
    }

    private static func preferredLiveEntityName(_ candidate: String, existing: DiscoveredEntity) -> String {
        PearchHAEntityNaming.preferredName(
            between: candidate,
            and: existing.name,
            entityID: existing.id
        ) ?? existing.name
    }

    private static func preferredLiveEntityUnit(_ candidate: String?, existing: DiscoveredEntity) -> String? {
        PearchHAEntityNaming.preferredUnit(between: candidate, and: existing.unit)
    }

    private func stabilizedRefreshedRooms(_ refreshedRooms: [Room], preserving existingRooms: [Room]) -> [Room] {
        let existingEntities = Dictionary(
            uniqueKeysWithValues: existingRooms.flatMap(\.entities).map { ($0.id, $0) }
        )
        return refreshedRooms.map { room in
            Room(
                id: room.id,
                name: room.name,
                entities: room.entities.map { entity in
                    guard let existing = existingEntities[entity.id] else {
                        return entity
                    }
                    return DiscoveredEntity(
                        id: entity.id,
                        name: Self.preferredLiveEntityName(entity.name, existing: existing),
                        state: entity.state,
                        unit: Self.preferredLiveEntityUnit(entity.unit, existing: existing),
                        areaID: entity.areaID,
                        deviceID: entity.deviceID,
                        deviceName: entity.deviceName,
                        deviceManufacturer: entity.deviceManufacturer,
                        deviceModel: entity.deviceModel,
                        deviceDomain: entity.deviceDomain,
                        currentPosition: entity.currentPosition,
                        controlAttributes: entity.controlAttributes
                    )
                }
            )
        }
    }

    private func normalizedMenuBarDisplayConfiguration(
        _ configuration: MenuBarDisplayConfiguration,
        availableRooms: [Room]
    ) -> MenuBarDisplayConfiguration {
        let availableEntities = availableRooms.flatMap(\.entities)
        let entitiesByID = Dictionary(uniqueKeysWithValues: availableEntities.map { ($0.id, $0) })
        var itemConfigurations = configuration.itemConfigurations.map { item in
            guard let entity = entitiesByID[item.entityID] else {
                return item
            }
            return normalizedMenuBarItemConfiguration(item, entity: entity)
        }
        let existingIDs = Set(itemConfigurations.map(\.entityID))
        for promotedID in configuration.promotedEntityIDs where !existingIDs.contains(promotedID) {
            guard let entity = entitiesByID[promotedID] else {
                continue
            }
            itemConfigurations.append(EntityDisplayDefaults.configuration(for: entity))
        }
        return MenuBarDisplayConfiguration(
            promotedEntityIDs: configuration.promotedEntityIDs,
            itemConfigurations: itemConfigurations
        )
    }

    private func normalizedMenuBarItemConfiguration(
        _ configuration: MenuBarItemConfiguration,
        entity: DiscoveredEntity
    ) -> MenuBarItemConfiguration {
        EntityDisplayDefaults.normalizedConfiguration(for: entity, configuration: configuration)
    }

    /// Repairs the current menu-bar display configuration against the entities
    /// present in ``snapshot.availableRooms`` and persists the repaired value.
    ///
    /// Safe to call repeatedly: when no repair is needed it is a no-op and
    /// returns `false`.
    @discardableResult
    public func normalizeDisplayConfigurationForAvailableEntities() -> Bool {
        guard !snapshot.availableRooms.isEmpty else {
            return false
        }
        let normalized = normalizedMenuBarDisplayConfiguration(
            snapshot.menuBarDisplayConfiguration,
            availableRooms: snapshot.availableRooms
        )
        return updateMenuBarDisplayConfiguration(normalized, persist: true)
    }

    private func apply(result: PearchHAConnectionAttemptResult, form: PearchHAConnectionForm, refreshCount: Int,
                       reporting: [EntityID: [String: RequestedControlValue]]) async {
        switch result {
        case let .success(rooms):
            let previousEntityIDs = displayedEntityIDs()
            // Compare on the stable connection identity (URLs + token), NOT plain
            // form equality: the form's address rows carry volatile UUIDs, so a
            // rebuilt-but-equivalent form would otherwise look "changed" and wipe
            // the history cache on every reconnect, blanking previews permanently.
            let connectionChanged = !form.sameConnection(as: lastConnectedForm)
            if connectionChanged {
                historyTask?.cancel()
                historyTask = nil
                historyRequestGeneration += 1
                evictAllHistory()
                cancelHistoryBulkSync()
                pendingControlChange = nil
                requestedControlValues = [:]
            }
            lastConnectedForm = form
            editableForm = form
            let refreshedRooms = stabilizedRefreshedRooms(rooms, preserving: snapshot.availableRooms)
            // A full state response replaces values even when entity IDs are unchanged.
            rebuildAvailableEntityCaches(from: refreshedRooms, refreshingValues: true)
            let normalizedDisplayConfiguration = normalizedMenuBarDisplayConfiguration(
                snapshot.menuBarDisplayConfiguration,
                availableRooms: refreshedRooms
            )
            let nextDisplayConfiguration: MenuBarDisplayConfiguration
            let nextDisplayPersistenceFailureDescription: String?
            if normalizedDisplayConfiguration != snapshot.menuBarDisplayConfiguration {
                switch menuBarDisplaySink(normalizedDisplayConfiguration) {
                case .saved:
                    nextDisplayConfiguration = normalizedDisplayConfiguration
                    nextDisplayPersistenceFailureDescription = nil
                case let .failed(message):
                    nextDisplayConfiguration = snapshot.menuBarDisplayConfiguration
                    nextDisplayPersistenceFailureDescription = message
                }
            } else {
                nextDisplayConfiguration = snapshot.menuBarDisplayConfiguration
                nextDisplayPersistenceFailureDescription = snapshot.displayPersistenceFailureDescription
            }
            let visibleRooms = selectedRooms(from: refreshedRooms, using: snapshot.selectionConfiguration)
            updateSnapshot { draft in
                draft.connectionState = .connected
                draft.phase = visibleRooms.isEmpty ? .connectedEmpty : .connectedData
                draft.rooms = visibleRooms
                draft.availableRooms = refreshedRooms
                draft.menuBarDisplayConfiguration = nextDisplayConfiguration
                draft.connectionForm = nonSecretForm(form)
                draft.lastUpdateDescription = Self.updatedDescription(at: wallClock())
                draft.refreshCount = refreshCount
                draft.canRetry = true
                draft.hasTokenInput = hasToken(in: form)
                draft.displayPersistenceFailureDescription = nextDisplayPersistenceFailureDescription
                if connectionChanged {
                    draft.historyState = .idle
                    draft.historyPresentationEntityID = nil
                    draft.controlActionState = .idle
                    draft.serviceMetadata = []
                }
            }
            for (id, requests) in reporting {
                finishRequestedControls(for: id, entity: availableEntitiesByID[id], reporting: requests)
            }
            if connectionChanged || previousEntityIDs != displayedEntityIDs() {
                startHistoryBulkSync()
            }
            if isPanelActive, periodicRefreshTask == nil {
                // First-run flow: the panel was opened before any session existed,
                // so activation could not arm the refresh safety net. Arm it now
                // that a connection exists; the immediate tick is skipped because
                // this connect just delivered fresh data.
                startPeriodicRefresh(refreshImmediately: false)
            } else {
                reconcilePeriodicRefreshLoop(refreshImmediately: false)
            }
            if connectionChanged || liveUpdateTask == nil {
                startLiveUpdates()
            }
            if diagnosticIsDegraded {
                diagnosticIsDegraded = false
                recordDiagnostic(.recovered, message: "Recovered, connection restored")
            } else {
                refreshRetryBackoffState()
            }
            await refreshServiceMetadata(form: form)
        case let .failure(failure):
            applyFailure(failure, refreshCount: refreshCount, canRetry: lastConnectedForm != nil)
        }
    }

    private func refreshServiceMetadata(form: PearchHAConnectionForm) async {
        recordOutboundRequest()
        let result = await serviceMetadataProvider(form)
        // Identity compare, not value equality: a rebuilt-but-equivalent form
        // (fresh address-row UUIDs) must not silently drop the metadata result.
        guard !Task.isCancelled, form.sameConnection(as: lastConnectedForm) else {
            return
        }
        switch result {
        case let .success(metadata):
            applyServiceMetadata(metadata, failureDescription: nil)
        case let .unavailable(message):
            applyServiceMetadata(snapshot.serviceMetadata, failureDescription: message)
        }
    }

    private func applyServiceMetadata(_ metadata: [HAServiceMetadata], failureDescription: String?) {
        updateSnapshot { draft in
            draft.serviceMetadataFailureDescription = failureDescription
            draft.serviceMetadata = metadata
        }
    }

    private func applyFailure(_ failure: ConnectionFailure, refreshCount: Int, canRetry: Bool) {
        if case .authentication = failure,
           editableForm.usesStoredAuthSession,
           editableForm.trimmedToken.isEmpty
        {
            editableForm.usesStoredAuthSession = false
        }
        let hasLastKnownRows = canRetry && !snapshot.rooms.isEmpty
        updateSnapshot { draft in
            draft.connectionState = .failed(failure)
            draft.phase = hasLastKnownRows ? .failedStale(failure) : .failed(failure)
            draft.connectionForm = nonSecretForm(editableForm)
            draft.refreshCount = refreshCount
            draft.canRetry = canRetry
        }
        diagnosticIsDegraded = true
        let detail = PearchHAPanelSnapshot.describe(failure)
        var changedHistory = Set<EntityID>()
        for key in protectedHistoryKeys() { changedHistory.formUnion(markHistoryFailure(key, message: detail)) }
        bumpHistoryRevisions(for: changedHistory)
        if isPeriodicRefreshInFlight {
            recordDiagnostic(.refreshFailed, message: "Refresh failed: \(detail)")
        } else {
            recordDiagnostic(.connectionFailed, message: "Connection failed: \(detail)")
        }
    }

    private func startAction(_ operation: @escaping @MainActor @Sendable () async -> Void) {
        actionTask?.cancel()
        actionTask = Task { @MainActor [weak self] in
            await operation()
            if !Task.isCancelled {
                self?.actionTask = nil
            }
        }
    }

    private func nonSecretForm(_ form: PearchHAConnectionForm) -> PearchHAConnectionForm {
        PearchHAConnectionForm(
            urlString: form.urlString,
            addresses: form.addresses,
            token: "",
            usesStoredAuthSession: form.usesStoredAuthSession,
            allowsSelfSignedCertificates: form.allowsSelfSignedCertificates
        )
    }

    private func hasToken(in form: PearchHAConnectionForm) -> Bool {
        !form.trimmedToken.isEmpty || form.usesStoredAuthSession
    }

    var tokenInputForView: String {
        editableForm.token
    }

    private func updateSnapshot(_ update: (inout PearchHAPanelSnapshot.Draft) -> Void) {
        snapshot = snapshot.updating { draft in
            draft.hasTokenInput = hasToken(in: editableForm)
            update(&draft)
        }
    }

    func protectedValueDraft(
        for id: CustomActionID,
        path: [PearchHACustomActionServiceDataPathComponent]
    ) -> String {
        let value = currentCustomActionServiceDataValue(for: id, path: path)
        if let reference = value?.protectedValueReference,
           let draft = protectedValueDrafts[reference.rawValue] {
            return draft
        }
        return protectedValueDrafts[protectedValueDraftPathKey(id: id, path: path)] ?? ""
    }

    private func setProtectedValueDraft(
        _ value: String,
        id: CustomActionID,
        path: [PearchHACustomActionServiceDataPathComponent]
    ) {
        let pathKey = protectedValueDraftPathKey(id: id, path: path)
        if let reference = currentCustomActionServiceDataValue(for: id, path: path)?.protectedValueReference {
            protectedValueDrafts[reference.rawValue] = value
            protectedValueDrafts.removeValue(forKey: pathKey)
        } else {
            protectedValueDrafts[pathKey] = value
        }
    }

    private func clearProtectedValueDraft(
        id: CustomActionID,
        path: [PearchHACustomActionServiceDataPathComponent]
    ) {
        let pathKey = protectedValueDraftPathKey(id: id, path: path)
        protectedValueDrafts.removeValue(forKey: pathKey)
        if let reference = currentCustomActionServiceDataValue(for: id, path: path)?.protectedValueReference {
            protectedValueDrafts.removeValue(forKey: reference.rawValue)
        }
    }

    private func protectedValueDraftPathKey(
        id: CustomActionID,
        path: [PearchHACustomActionServiceDataPathComponent]
    ) -> String {
        "\(id.rawValue):\(serviceDataPathDescription(path))"
    }

    func isSensitiveServiceDataPath(_ path: [PearchHACustomActionServiceDataPathComponent]) -> Bool {
        path
            .reversed()
            .compactMap { component in
                if case let .key(key) = component {
                    return key
                }
                return nil
            }
            .first
            .map(ActionSpec.isSensitiveServiceDataKey(_:))
            ?? false
    }

    private func freshProtectedValueReference(for actionID: CustomActionID) -> ProtectedActionValueReference {
        ProtectedActionValueReference("custom-action:\(actionID.rawValue):\(UUID().uuidString)")
    }

    private func currentCustomActionServiceDataValue(
        for id: CustomActionID,
        path: [PearchHACustomActionServiceDataPathComponent]
    ) -> ActionValue? {
        guard let action = customActionConfiguration.action(id: id) else {
            return nil
        }
        return PearchHAActionValuePathEditor.value(at: path, in: action.action.serviceData)
    }

    private func sanitize(
        action: EntityCustomAction,
        existingAction: EntityCustomAction?
    ) throws -> SanitizedCustomAction {
        let sanitized = try sanitize(
            serviceData: action.action.serviceData,
            path: [],
            actionID: action.id,
            existingValue: existingAction.map { .object($0.action.serviceData) }
        )
        return SanitizedCustomAction(
            action: action.withServiceData(sanitized.value),
            protectedValueUpserts: sanitized.protectedValueUpserts
        )
    }

    private func sanitize(
        serviceData: [String: ActionValue],
        path: [PearchHACustomActionServiceDataPathComponent],
        actionID: CustomActionID,
        existingValue: ActionValue?
    ) throws -> SanitizedActionValue {
        var sanitized: [String: ActionValue] = [:]
        var upserts: [ProtectedActionValueReference: String] = [:]
        let existingObject: [String: ActionValue]
        if case let .object(values) = existingValue {
            existingObject = values
        } else {
            existingObject = [:]
        }
        for key in serviceData.keys.sorted() {
            guard let value = serviceData[key] else {
                continue
            }
            let existingChild = existingObject[key]
            let child = try sanitize(
                value: value,
                path: path + [.key(key)],
                actionID: actionID,
                existingValue: existingChild
            )
            sanitized[key] = child.value
            upserts.merge(child.protectedValueUpserts) { _, new in new }
        }
        return SanitizedActionValue(value: sanitized, protectedValueUpserts: upserts)
    }

    private func sanitize(
        value: ActionValue,
        path: [PearchHACustomActionServiceDataPathComponent],
        actionID: CustomActionID,
        existingValue: ActionValue?
    ) throws -> SanitizedScalarActionValue {
        if isSensitiveServiceDataPath(path) {
            switch value {
            case let .string(secret):
                let trimmed = secret.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else {
                    return SanitizedScalarActionValue(value: value, protectedValueUpserts: [:])
                }
                let reference = existingValue?.protectedValueReference ?? freshProtectedValueReference(for: actionID)
                return SanitizedScalarActionValue(
                    value: .protectedString(reference),
                    protectedValueUpserts: [reference: secret]
                )
            case .protectedString:
                return SanitizedScalarActionValue(value: value, protectedValueUpserts: [:])
            case let .object(values):
                let child = try sanitize(
                    serviceData: values,
                    path: path,
                    actionID: actionID,
                    existingValue: existingValue
                )
                return SanitizedScalarActionValue(
                    value: .object(child.value),
                    protectedValueUpserts: child.protectedValueUpserts
                )
            case let .array(values):
                var sanitizedValues: [ActionValue] = []
                var upserts: [ProtectedActionValueReference: String] = [:]
                let existingArray: [ActionValue]
                if case let .array(storedValues) = existingValue {
                    existingArray = storedValues
                } else {
                    existingArray = []
                }
                for (index, childValue) in values.enumerated() {
                    let child = try sanitize(
                        value: childValue,
                        path: path + [.index(index)],
                        actionID: actionID,
                        existingValue: existingArray.indices.contains(index) ? existingArray[index] : nil
                    )
                    sanitizedValues.append(child.value)
                    upserts.merge(child.protectedValueUpserts) { _, new in new }
                }
                return SanitizedScalarActionValue(
                    value: .array(sanitizedValues),
                    protectedValueUpserts: upserts
                )
            case .number, .bool, .null:
                return SanitizedScalarActionValue(value: value, protectedValueUpserts: [:])
            }
        }

        switch value {
        case let .protectedString(reference):
            return SanitizedScalarActionValue(
                value: .string(try protectedActionValueStore.load(reference)),
                protectedValueUpserts: [:]
            )
        case let .object(values):
            let child = try sanitize(
                serviceData: values,
                path: path,
                actionID: actionID,
                existingValue: existingValue
            )
            return SanitizedScalarActionValue(
                value: .object(child.value),
                protectedValueUpserts: child.protectedValueUpserts
            )
        case let .array(values):
            var sanitizedValues: [ActionValue] = []
            var upserts: [ProtectedActionValueReference: String] = [:]
            let existingArray: [ActionValue]
            if case let .array(storedValues) = existingValue {
                existingArray = storedValues
            } else {
                existingArray = []
            }
            for (index, childValue) in values.enumerated() {
                let child = try sanitize(
                    value: childValue,
                    path: path + [.index(index)],
                    actionID: actionID,
                    existingValue: existingArray.indices.contains(index) ? existingArray[index] : nil
                )
                sanitizedValues.append(child.value)
                upserts.merge(child.protectedValueUpserts) { _, new in new }
            }
            return SanitizedScalarActionValue(
                value: .array(sanitizedValues),
                protectedValueUpserts: upserts
            )
        case .string, .number, .bool, .null:
            return SanitizedScalarActionValue(value: value, protectedValueUpserts: [:])
        }
    }

    private func protectedActionValueSnapshots(
        for references: Set<ProtectedActionValueReference>
    ) throws -> [ProtectedActionValueReference: ProtectedActionValueSnapshot] {
        var snapshots: [ProtectedActionValueReference: ProtectedActionValueSnapshot] = [:]
        for reference in references.sorted(by: { $0.rawValue < $1.rawValue }) {
            do {
                snapshots[reference] = .present(try protectedActionValueStore.load(reference))
            } catch let error as ProtectedActionValueStoreError {
                switch error {
                case .missingValue:
                    snapshots[reference] = .missing
                case .invalidStoredValues, .unavailable:
                    throw error
                }
            }
        }
        return snapshots
    }

    private func restoreProtectedActionValueSnapshots(
        _ snapshots: [ProtectedActionValueReference: ProtectedActionValueSnapshot]
    ) throws {
        for reference in snapshots.keys.sorted(by: { $0.rawValue < $1.rawValue }) {
            guard let snapshot = snapshots[reference] else {
                continue
            }
            switch snapshot {
            case let .present(value):
                try protectedActionValueStore.save(value, for: reference)
            case .missing:
                try protectedActionValueStore.delete(reference)
            }
        }
    }

    private func applyProtectedValueUpserts(
        _ upserts: [ProtectedActionValueReference: String]
    ) throws {
        for reference in upserts.keys.sorted(by: { $0.rawValue < $1.rawValue }) {
            guard let value = upserts[reference] else {
                continue
            }
            try protectedActionValueStore.save(value, for: reference)
        }
    }

    private func deleteProtectedActionValues(
        references: Set<ProtectedActionValueReference>
    ) throws {
        for reference in references.sorted(by: { $0.rawValue < $1.rawValue }) {
            try protectedActionValueStore.delete(reference)
            protectedValueDrafts.removeValue(forKey: reference.rawValue)
        }
    }

    private func serviceDataPathDescription(
        _ path: [PearchHACustomActionServiceDataPathComponent]
    ) -> String {
        path.reduce(into: "serviceData") { description, component in
            switch component {
            case let .key(key):
                description.append(".\(key)")
            case let .index(index):
                description.append("[\(index)]")
            }
        }
    }

    private func canSetAbsoluteTotal(_ id: EntityID, total: Double?) -> Bool {
        guard let total else {
            return true
        }
        guard total.isFinite, total > 0 else {
            return false
        }
        guard let entity = entity(for: id) else {
            return true
        }
        return canUseGaugeTotal(for: entity)
    }

    private func canSetTotalEntityID(_ id: EntityID, totalEntityID: EntityID?) -> Bool {
        guard let totalEntityID else {
            return true
        }
        guard !totalEntityID.rawValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              totalEntityID != id
        else {
            return false
        }
        guard let sourceEntity = entity(for: id),
              let totalEntity = entity(for: totalEntityID)
        else {
            return false
        }
        return canUseGaugeTotal(for: sourceEntity)
            && numericState(totalEntity.state) != nil
            && unitsAreCompatible(sourceEntity.unit, totalEntity.unit)
    }

    private func canSetThreshold(_ threshold: ValueThreshold?) -> Bool {
        threshold?.value.isFinite ?? true
    }

    private func orderedAverageFamilyIDs(_ ids: [EntityID]) -> [EntityID] {
        let unique = Set(ids)
        return orderedAvailableEntityIDs().filter { unique.contains($0) }
    }

    private func uniqueEntityIDs(_ ids: [EntityID]) -> [EntityID] {
        var seen: Set<EntityID> = []
        var ordered: [EntityID] = []
        for id in ids where !seen.contains(id) {
            seen.insert(id)
            ordered.append(id)
        }
        return ordered
    }

    private func entity(for id: EntityID) -> DiscoveredEntity? {
        availableEntitiesByID[id]
    }

    private func canUseGaugeTotal(for entity: DiscoveredEntity) -> Bool {
        numericState(entity.state) != nil && !isPercentUnit(entity.unit)
    }

    private func numericState(_ state: String) -> Double? {
        Double(state.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private func isPercentUnit(_ unit: String?) -> Bool {
        normalizedUnit(unit) == "%"
    }

    private func unitsAreCompatible(_ sourceUnit: String?, _ totalUnit: String?) -> Bool {
        normalizedUnit(sourceUnit) == normalizedUnit(totalUnit)
    }

    private func normalizedUnit(_ unit: String?) -> String? {
        let trimmed = unit?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let trimmed, !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }

    @discardableResult
    private func updateSelectionConfiguration(_ configuration: EntitySelectionConfiguration, persist: Bool) -> Bool {
        guard configuration != snapshot.selectionConfiguration else {
            return false
        }

        if persist {
            switch selectionSink(configuration) {
            case .saved:
                break
            case let .failed(message):
                updateSnapshot { draft in
                    draft.selectionPersistenceFailureDescription = message
                }
                return false
            }
        }

        let visibleRooms = selectedRooms(from: snapshot.availableRooms, using: configuration)
        let nextPhase: PearchHAPanelPhase
        switch snapshot.phase {
        case .connectedData, .connectedEmpty:
            nextPhase = visibleRooms.isEmpty ? .connectedEmpty : .connectedData
        default:
            nextPhase = snapshot.phase
        }

        updateSnapshot { draft in
            draft.phase = nextPhase
            draft.rooms = visibleRooms
            draft.selectionConfiguration = configuration
            if persist {
                draft.selectionPersistenceFailureDescription = nil
            }
        }
        startHistoryBulkSync()
        reconcilePeriodicRefreshLoop(refreshImmediately: false)
        return true
    }

    @discardableResult
    private func updateMenuBarItemConfiguration(_ configuration: MenuBarItemConfiguration) -> Bool {
        updateMenuBarDisplayConfiguration(
            snapshot.menuBarDisplayConfiguration.replacingItemConfiguration(configuration),
            persist: true
        )
    }

    @discardableResult
    private func updateCustomActionConfiguration(
        _ configuration: CustomActionConfiguration,
        persist: Bool,
        protectedValueUpserts: [ProtectedActionValueReference: String] = [:]
    ) -> Bool {
        guard configuration != customActionConfiguration || !protectedValueUpserts.isEmpty else {
            return false
        }
        if let failure = configuration.validationFailure() {
            customActionPersistenceFailureDescription = failure.description
            return false
        }

        if persist {
            let previousReferences = customActionConfiguration.protectedValueReferences
            let nextReferences = configuration.protectedValueReferences
            let removedReferences = previousReferences.subtracting(nextReferences)
            let touchedReferences = previousReferences
                .union(nextReferences)
                .union(protectedValueUpserts.keys)
            var snapshots: [ProtectedActionValueReference: ProtectedActionValueSnapshot] = [:]
            do {
                snapshots = try protectedActionValueSnapshots(for: touchedReferences)
                try applyProtectedValueUpserts(protectedValueUpserts)
                try deleteProtectedActionValues(references: removedReferences)
                switch customActionSink(configuration) {
                case .saved:
                    break
                case let .failed(message):
                    try restoreProtectedActionValueSnapshots(snapshots)
                    customActionPersistenceFailureDescription = message
                    return false
                }
            } catch {
                try? restoreProtectedActionValueSnapshots(snapshots)
                customActionPersistenceFailureDescription = String(describing: error)
                return false
            }
        }

        customActionConfiguration = configuration
        customActionPersistenceFailureDescription = persist ? nil : customActionPersistenceFailureDescription
        return true
    }

    @discardableResult
    private func updateMenuBarDisplayConfiguration(_ configuration: MenuBarDisplayConfiguration, persist: Bool) -> Bool {
        guard configuration != snapshot.menuBarDisplayConfiguration else {
            return false
        }

        if persist {
            switch menuBarDisplaySink(configuration) {
            case .saved:
                break
            case let .failed(message):
                updateSnapshot { draft in
                    draft.displayPersistenceFailureDescription = message
                }
                return false
            }
        }

        updateSnapshot { draft in
            draft.menuBarDisplayConfiguration = configuration
            if persist {
                draft.displayPersistenceFailureDescription = nil
            }
        }
        reconcilePeriodicRefreshLoop(refreshImmediately: false)
        return true
    }

    private func selectedRooms(from rooms: [Room], using configuration: EntitySelectionConfiguration) -> [Room] {
        EntitySelectionProjector().selectedRooms(rooms: rooms, configuration: configuration)
    }

    private func orderedAvailableEntityIDs() -> [EntityID] {
        EntitySelectionProjector().selectedRooms(
            rooms: snapshot.availableRooms,
            configuration: EntitySelectionConfiguration(
                roomOrder: snapshot.selectionConfiguration.roomOrder,
                entityOrder: snapshot.selectionConfiguration.entityOrder
            )
        )
        .flatMap(\.entities)
        .map(\.id)
    }

    private func orderedSelectionIDs(_ selected: Set<EntityID>) -> [EntityID] {
        let visibleOrder = orderedAvailableEntityIDs().filter { selected.contains($0) }
        return visibleOrder
    }

    private var canReorderMenuBarDisplay: Bool {
        snapshot.canReorderSelectionWithKeyboard
    }
}
