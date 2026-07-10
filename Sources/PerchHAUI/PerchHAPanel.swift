import Foundation
import AppKit
import Combine
import OSLog
import SwiftUI
import UniformTypeIdentifiers
import PerchHACore
import PerchHASupport

@MainActor
public final class PerchHAPanelModel: ObservableObject {
    public typealias Connector = @Sendable (PerchHAConnectionForm) async -> PerchHAConnectionAttemptResult
    public typealias HistoryProvider = @Sendable (PerchHAConnectionForm, EntityID, HistoryRange) async -> PerchHAHistoryProviderResult
    /// Fetches history for many entities sharing a range in as few requests as
    /// possible. Used only by the background bulk sync loop (never by hover/detail).
    /// Returns a series per entity that came back; missing/failed entities are
    /// simply absent. Must never carry or leak a token.
    public typealias BulkHistoryProvider = @Sendable (PerchHAConnectionForm, [EntityID], HistoryRange) async -> [EntityID: HistorySeries]
    public typealias ServiceMetadataProvider = @Sendable (PerchHAConnectionForm) async -> PerchHAServiceMetadataProviderResult
    /// Opens one live update stream for the connection and delivers each pushed
    /// entity state through the handler. Returns only when the stream ends,
    /// with the failure that ended it. Must never carry or leak a token.
    public typealias LiveUpdateStreamer = @Sendable (
        PerchHAConnectionForm,
        @escaping @Sendable (EntityState) async -> Void
    ) async -> ConnectionFailure
    public typealias ActionRunner = @Sendable (PerchHAConnectionForm, ActionSpec) async -> PerchHAActionResult
    public typealias OAuthSignInRunner = @MainActor @Sendable (PerchHAConnectionForm) async -> PerchHAOAuthSignInResult
    public typealias ReleaseUpdateChecker = @Sendable (String) async -> PerchHAReleaseUpdateCheckResult
    public typealias SelectionConfigurationSink = @MainActor (EntitySelectionConfiguration) -> SelectionPersistenceResult
    public typealias MenuBarDisplayConfigurationSink = @MainActor (MenuBarDisplayConfiguration) -> SelectionPersistenceResult
    public typealias CustomActionConfigurationSink = @MainActor (CustomActionConfiguration) -> SelectionPersistenceResult
    public typealias SnapshotSink = @MainActor (PerchHAPanelSnapshot) -> Void
    /// Clears the persisted authentication session when the user signs out.
    public typealias SignOutHandler = @MainActor () -> Void

    @Published public private(set) var snapshot: PerchHAPanelSnapshot {
        didSet {
            let previousAvailableEntityIndexSignature = availableEntityIndexSignature
            rebuildAvailableEntityCaches(from: snapshot.availableRooms)
            let availableEntityIndexChanged = previousAvailableEntityIndexSignature != availableEntityIndexSignature
            if oldValue.rooms != snapshot.rooms
                || oldValue.availableRooms != snapshot.availableRooms
                || oldValue.menuBarDisplayConfiguration != snapshot.menuBarDisplayConfiguration
                || oldValue.valuesAreStale != snapshot.valuesAreStale {
                invalidateAllDisplayCaches()
            } else if oldValue.connectionState != snapshot.connectionState {
                formattedValueCache.removeAll(keepingCapacity: true)
            }
            snapshotSink(snapshot)
            refreshRetryBackoffState()
            if availableEntityIndexChanged
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
    @Published public private(set) var oauthSignInState = PerchHAOAuthSignInState.idle
    @Published public private(set) var releaseUpdateState = PerchHAReleaseUpdateState.idle

    /// The live dashboard display preferences the panel honors (row density,
    /// default history range, footer timestamp, hidden modules).
    ///
    /// Pushed in from the app shell whenever the user changes a Dashboard
    /// setting so the open panel re-renders at once; the snapshot itself is
    /// unaffected. Settings are the source of truth for persistence.
    @Published public private(set) var displayPreferences: PerchHADisplayPreferences = .defaults

    /// A monotonically increasing token bumped on every history cache mutation
    /// (insert from prefetch or hover load, and full-cache eviction).
    ///
    /// Inline-row previews read ``cachedHistorySeries(for:)``, which peeks the
    /// cache without itself being observable. Reading this published token in the
    /// same view makes SwiftUI re-evaluate the affected rows the moment new
    /// history lands, so a freshly prefetched sparkline appears immediately rather
    /// than waiting for an unrelated snapshot change. The token is a cheap counter,
    /// not the series data, so the existing chart redraw throttling is unaffected.
    @Published public private(set) var historyRevision = 0

    /// The deduplicated ring buffer of real diagnostic events (connection
    /// failures, reconnect attempts, recoveries, and periodic-refresh failures),
    /// recorded at the points where those transitions actually occur.
    ///
    /// Capped and consecutive-deduplicated, so it stays cheap and never floods.
    /// Messages are always sanitized failure/transition descriptions — no token
    /// or secret is ever recorded. Surfaced read-only in Settings → Diagnostics.
    @Published public private(set) var diagnosticEvents: [PerchHADiagnosticEvent] = []

    /// The current retry/backoff posture derived purely from the live connection
    /// state and the periodic-refresh backoff streak. Drives the Diagnostics
    /// "retry / backoff" line. Never carries a secret.
    @Published public private(set) var retryBackoffState: PerchHARetryBackoffState = .disconnected

    /// The most recent instant observed from the injected clock, used by the
    /// Diagnostics view to render each event's age relative to "now" without
    /// reaching for wall-clock time.
    @Published public private(set) var diagnosticsReferenceInstant = PerchInstant(nanosecondsSinceStart: 0)

    private let connector: Connector
    private let historyProvider: HistoryProvider
    private let bulkHistoryProvider: BulkHistoryProvider
    private let serviceMetadataProvider: ServiceMetadataProvider
    private let liveUpdateStreamer: LiveUpdateStreamer?
    private let liveUpdateConfiguration: PerchHALiveUpdateConfiguration
    /// Supplies the wall-clock time stamped into the footer's "Updated at"
    /// caption. Injectable so tests stay deterministic.
    private let wallClock: @Sendable () -> Date
    private let actionRunner: ActionRunner
    private let oauthSignInRunner: OAuthSignInRunner
    private let releaseUpdateChecker: ReleaseUpdateChecker
    private let currentApplicationVersionProvider: @Sendable () -> String
    private let clock: any PerchClock
    private let historyDebounce: PerchDuration
    private let historyHoverGrace: PerchDuration
    private let historyCacheConfiguration: PerchHAHistoryCacheConfiguration
    private let bulkSyncConfiguration: PerchHAHistoryBulkSyncConfiguration
    private let periodicRefreshConfiguration: PerchHAPeriodicRefreshConfiguration
    private let selectionSink: SelectionConfigurationSink
    private let menuBarDisplaySink: MenuBarDisplayConfigurationSink
    private let customActionSink: CustomActionConfigurationSink
    private let protectedActionValueStore: any ProtectedActionValueStore
    private let snapshotSink: SnapshotSink
    private let signOutHandler: SignOutHandler
    private static let inlineSparklineSampleBudget = 48
    private let performanceSignposter = OSSignposter(
        logger: Logger(subsystem: "dev.yuna.perchha", category: "Performance")
    )
    private var settingsSelectionTreeSignature: SettingsSelectionTreeSignature
    private var availableEntityIndexSignature = AvailableEntityIndexSignature(rooms: [])
    private var availableEntityLocations: [EntityID: AvailableEntityLocation] = [:]
    private var availableEntitiesByID: [EntityID: DiscoveredEntity] = [:]
    private var availableEntities: [DiscoveredEntity] = []
    private var averageCandidateCache: [EntityID: [DiscoveredEntity]] = [:]
    private var displayedEntityCache: [EntityID: DiscoveredEntity] = [:]
    private var formattedValueCache: [FormattedEntityValueCacheKey: FormattedEntityValue] = [:]
    private var rowPresentationCache: [EntityID: PerchHAEntityRowPresentation] = [:]
    private var inlineSparklineGeometryCache: [PerchHAHistoryCacheKey: PerchHAHistorySparklineGeometry?] = [:]
    private var historyRevisionSubjects: [EntityID: CurrentValueSubject<UInt64, Never>] = [:]
    private var historyCache = PerchHAHistoryCache()
    private var lastObservedInstant = PerchInstant(nanosecondsSinceStart: 0)
    private var lastConnectedForm: PerchHAConnectionForm?
    private var editableForm: PerchHAConnectionForm
    private var actionTask: Task<Void, Never>?
    private var controlActionTask: Task<Void, Never>?
    private var pendingControlChange: PendingControlChange?
    private var historyTask: Task<Void, Never>?
    private var historyDetailRefreshTask: Task<Void, Never>?
    private var historyRequestGeneration = 0
    private var historyHoverSuppressionDepth = 0
    private var transientUITrackingDepth = 0
    private var deferredLiveStates: [EntityID: EntityState] = [:]
    private var deferredBackgroundLiveStates: [EntityID: EntityState] = [:]
    private var deferredSilentRefreshRequested = false
    private var protectedValueDrafts: [String: String] = [:]
    /// Whether the panel is currently shown, gating all background fetching.
    /// Set through ``setPanelActive(_:)``; readable so the app shell's
    /// window-visibility wiring can be verified through the public boundary.
    public private(set) var isPanelActive = false
    private var visibleEntityIDs: [EntityID] = []
    /// The single re-arming background bulk-history sync loop. Active only while
    /// the panel is open and a session is connected.
    private var bulkSyncTask: Task<Void, Never>?
    /// Per-entity interest score: bumped when an entity is visible and when its
    /// detail/hover is opened. Drives prioritization — high-interest entities sync
    /// every cycle, cold ones every Nth cycle. Bounded so it never grows without
    /// limit (capped per entity; pruned to displayed/visible entities each cycle).
    private var entityInterest: [EntityID: Int] = [:]
    /// When each entity/range history layer last landed from a bulk cycle.
    /// Range-specific timestamps stop a fresh day sync from suppressing the week
    /// or month layer, which would otherwise leave long ranges stale while still
    /// paying their full fetch cost when opened later.
    private var entityLastSyncedAt: [PerchHAHistoryCacheKey: PerchInstant] = [:]
    /// Monotonic count of completed sync cycles, used to gate cold-entity refresh.
    private var bulkSyncCycle = 0
    private var periodicRefreshTask: Task<Void, Never>?
    private var periodicRefreshFailureStreak = 0
    /// The single long-lived live update loop. Runs while a session is
    /// connected — independent of panel visibility, so promoted menu-bar items
    /// stay live with the panel closed.
    private var liveUpdateTask: Task<Void, Never>?
    private var diagnosticLog = PerchHADiagnosticLog()
    /// Whether a connection/refresh failure has been recorded since the last
    /// successful connection. Gates the `.recovered` event so a routine
    /// successful refresh does not masquerade as a recovery.
    private var diagnosticIsDegraded = false
    /// True only while a background periodic-refresh tick is running, so a
    /// failure surfaced during it is recorded as `.refreshFailed` (with the
    /// backoff posture) rather than a fresh `.connectionFailed`.
    private var isPeriodicRefreshInFlight = false

    public init(
        snapshot: PerchHAPanelSnapshot = PerchHAPanelSnapshot(),
        connector: @escaping Connector = { _ in .failure(.protocolError("connection client is not configured")) },
        historyProvider: @escaping HistoryProvider = { _, _, _ in .unavailable("history client is not configured") },
        bulkHistoryProvider: @escaping BulkHistoryProvider = { _, _, _ in [:] },
        serviceMetadataProvider: @escaping ServiceMetadataProvider = { _ in .success([]) },
        liveUpdateStreamer: LiveUpdateStreamer? = nil,
        actionRunner: @escaping ActionRunner = { _, _ in .failed("action client is not configured") },
        oauthSignInRunner: @escaping OAuthSignInRunner = { _ in .failed("OAuth sign-in is not configured") },
        releaseUpdateChecker: @escaping ReleaseUpdateChecker = { _ in .failed("update checker is not configured") },
        currentApplicationVersionProvider: @escaping @Sendable () -> String = { PerchHAApplicationVersionInfo.currentBundle().releaseVersion },
        clock: any PerchClock = SystemPerchClock(),
        wallClock: @escaping @Sendable () -> Date = { Date() },
        historyDebounce: PerchDuration = .milliseconds(120),
        historyHoverGrace: PerchDuration = .milliseconds(300),
        historyCacheConfiguration: PerchHAHistoryCacheConfiguration = PerchHAHistoryCacheConfiguration(),
        bulkSyncConfiguration: PerchHAHistoryBulkSyncConfiguration = PerchHAHistoryBulkSyncConfiguration(),
        periodicRefreshConfiguration: PerchHAPeriodicRefreshConfiguration = PerchHAPeriodicRefreshConfiguration(),
        liveUpdateConfiguration: PerchHALiveUpdateConfiguration = PerchHALiveUpdateConfiguration(),
        selectionConfiguration: EntitySelectionConfiguration = EntitySelectionConfiguration(),
        menuBarDisplayConfiguration: MenuBarDisplayConfiguration = MenuBarDisplayConfiguration(),
        customActionConfiguration: CustomActionConfiguration = CustomActionConfiguration(),
        selectionSink: @escaping SelectionConfigurationSink = { _ in .saved },
        menuBarDisplaySink: @escaping MenuBarDisplayConfigurationSink = { _ in .saved },
        customActionSink: @escaping CustomActionConfigurationSink = { _ in .saved },
        protectedActionValueStore: (any ProtectedActionValueStore)? = nil,
        snapshotSink: @escaping SnapshotSink = { _ in },
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
        let initialSnapshot = PerchHAPanelSnapshot(
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
        self.historyHoverGrace = historyHoverGrace
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
        historyDetailRefreshTask?.cancel()
        bulkSyncTask?.cancel()
        periodicRefreshTask?.cancel()
        liveUpdateTask?.cancel()
    }

    public func updateConnectionForm(
        urlString: String? = nil,
        fallbackURLString: String? = nil,
        addresses: [PerchHAConnectionAddressField]? = nil,
        token: String? = nil,
        usesStoredAuthSession: Bool? = nil,
        allowsSelfSignedCertificates: Bool? = nil
    ) {
        let nextUsesStoredAuthSession = usesStoredAuthSession
            ?? (token?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false ? false : editableForm.usesStoredAuthSession)
        let nextAddresses: [PerchHAConnectionAddressField]
        if let addresses {
            nextAddresses = addresses
        } else if let fallbackURLString {
            nextAddresses = Self.replacingFirstAddress(in: editableForm.addresses, urlString: fallbackURLString)
        } else {
            nextAddresses = editableForm.addresses
        }
        editableForm = PerchHAConnectionForm(
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
        editableForm.addresses.append(PerchHAConnectionAddressField())
        publishEditableForm()
    }

    /// Removes the alternative address with the given identifier.
    ///
    /// - Parameter id: The address row identifier.
    public func removeConnectionAddress(id: PerchHAConnectionAddressField.ID) {
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
        id: PerchHAConnectionAddressField.ID,
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
    public func moveConnectionAddress(id: PerchHAConnectionAddressField.ID, direction: SelectionMoveDirection) -> Bool {
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
        in addresses: [PerchHAConnectionAddressField],
        urlString: String
    ) -> [PerchHAConnectionAddressField] {
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        var updated = addresses
        if updated.isEmpty {
            guard !trimmed.isEmpty else {
                return []
            }
            updated.append(PerchHAConnectionAddressField(urlString: urlString))
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
    public func applyDisplayPreferences(_ preferences: PerchHADisplayPreferences) {
        let previousPreferences = displayPreferences
        guard previousPreferences != preferences else {
            return
        }
        displayPreferences = preferences
        guard isPanelActive else {
            return
        }
        if previousPreferences.dataSyncInterval != preferences.dataSyncInterval {
            startHistoryBulkSync()
            startPeriodicRefresh(refreshImmediately: false)
        }
        if previousPreferences.historyDetailRefreshInterval != preferences.historyDetailRefreshInterval
            || previousPreferences.dataSyncInterval != preferences.dataSyncInterval {
            restartHistoryDetailRefresh()
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

    func rowPresentation(for entity: DiscoveredEntity) -> PerchHAEntityRowPresentation {
        if let cached = rowPresentationCache[entity.id] {
            return cached
        }
        let presentation = PerchHAEntityRowPresentation.resolve(
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
        let resolved = PerchHAEntityAveraging.averagedEntity(
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

    private func rebuildAvailableEntityCaches(from rooms: [Room]) {
        let signature = AvailableEntityIndexSignature(rooms: rooms)
        guard availableEntityIndexSignature != signature else {
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
    public func setMenuBarAppearance(_ id: EntityID, appearance: PerchHAMenuBarAppearance?) -> Bool {
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

    /// The effective chart range for an entity: its explicit per-entity range,
    /// or the global Appearance default when the entity inherits.
    ///
    /// - Parameter id: The entity whose range is resolved.
    /// - Returns: The range driving the inline preview and history popover.
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
        PerchHAEntityAveraging.familyIDs(
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
                && PerchHAEntityAveraging.areCompatible(source, candidate)
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
                  PerchHAEntityAveraging.areCompatible(source, peer) else {
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

    /// Begins presenting the history popover for an entity after the debounce.
    ///
    /// Re-entering a row cancels any pending grace-period close so the popover
    /// stays anchored beside the row while the cursor lingers.
    ///
    /// - Parameters:
    ///   - id: The entity whose history should be shown.
    ///   - range: An explicit range, or `nil` to use the entity's default.
    public func presentHistoryDetail(_ id: EntityID, range: HistoryRange? = nil) {
        startHistoryHover(id, range: range)
    }

    public func startHistoryHover(
        _ id: EntityID,
        range: HistoryRange? = nil
    ) {
        guard historyHoverSuppressionDepth == 0 else {
            return
        }
        let resolvedRange = range ?? historyRange(for: id)
        // Opening a detail/hover marks the entity as hot so the bulk sync keeps it
        // freshest across cycles.
        bumpInterest(id)
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
            restartHistoryDetailRefresh()
            if !Task.isCancelled {
                historyTask = nil
            }
        }
    }

    /// Closes and suppresses history hover briefly while the user scrolls.
    ///
    /// History is now explicit-selection driven, so scrolling simply dismisses
    /// the current detail surface instead of juggling hover suppression timers.
    public func notePanelScrollActivity() {
        closeHistoryHoverImmediately()
    }

    /// Suspends row-hover driven history changes while a native context menu is open.
    ///
    /// The currently shown history stays stable; row enter/exit events received
    /// while the context menu is active are ignored until the menu closes.
    public func beginHistoryHoverSuppression() {
        historyHoverSuppressionDepth += 1
    }

    /// Ends one level of context-menu hover suppression.
    public func endHistoryHoverSuppression() {
        historyHoverSuppressionDepth = max(0, historyHoverSuppressionDepth - 1)
    }

    public func beginTransientUITracking() {
        transientUITrackingDepth += 1
        beginHistoryHoverSuppression()
    }

    public func endTransientUITracking() {
        transientUITrackingDepth = max(0, transientUITrackingDepth - 1)
        endHistoryHoverSuppression()
        guard transientUITrackingDepth == 0 else {
            return
        }
        let deferredStates = deferredLiveStates.values.sorted { $0.id.rawValue < $1.id.rawValue }
        deferredLiveStates = [:]
        for state in deferredStates {
            _ = applyLiveState(state)
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

    /// Legacy compatibility entrypoint for tests and tooling that used the old
    /// hover-driven history panel. In the explicit-selection model, cancelling
    /// history simply dismisses the current detail immediately.
    public func cancelHistoryHover() {
        closeHistoryHoverImmediately()
    }

    /// Compatibility accessor retained for older tests that still talk in terms
    /// of a pinned hover target. The explicit-selection model exposes the same
    /// entity through `historyPresentationEntityID`.
    public var pinnedHistoryEntityID: EntityID? {
        snapshot.historyPresentationEntityID
    }

    /// Compatibility no-op for the retired hover-grace model.
    public func keepHistoryHoverAlive() {}

    /// Compatibility hook for the retired hover-surface tracking model.
    public func setHistorySurfaceHovering(_ isHovering: Bool) {
        if !isHovering {
            dismissHistoryPopover()
        }
    }

    /// Selection opens the history panel immediately from cache when possible,
    /// then refreshes the backing series through the normal debounced load path.
    private func primeHistoryPresentation(entityID: EntityID, range: HistoryRange) {
        applyHistoryPresentationEntityID(entityID)
        let cacheKey = PerchHAHistoryCacheKey(entityID: entityID, range: range)
        if let cachedSeries = historyCache.peekAllowingStale(for: cacheKey) {
            applyHistoryState(.loaded(cachedSeries))
            return
        }
        if snapshot.historyState.entityID != entityID || snapshot.historyState.range != range {
            applyHistoryState(.loading(entityID: entityID, range: range))
        }
    }

    /// Clears the history presentation right away, bypassing the grace period.
    ///
    /// Used by teardown paths (sign-out, reconnect, panel dismissal) where the
    /// popover must disappear without waiting.
    private func closeHistoryHoverImmediately() {
        historyTask?.cancel()
        historyTask = nil
        cancelHistoryDetailRefresh()
        historyRequestGeneration += 1
        applyHistoryPresentationEntityID(nil)
        if case .loading = snapshot.historyState {
            applyHistoryState(.idle)
        }
    }

    public func toggleHistoryPin(_ id: EntityID) {
        presentHistoryDetail(id)
    }

    public func loadHistory(_ id: EntityID, range: HistoryRange? = nil) async {
        let resolvedRange = range ?? historyRange(for: id)
        let cacheKey = PerchHAHistoryCacheKey(entityID: id, range: resolvedRange)
        let now = await clock.now()
        lastObservedInstant = now
        if let cachedSeries = historyCache.series(for: cacheKey, now: now) {
            applyHistoryState(.loaded(cachedSeries))
            return
        }
        let staleSeries = historyCache.peekAllowingStale(for: cacheKey)
        if let staleSeries {
            applyHistoryState(.loaded(staleSeries))
        }

        guard let form = lastConnectedForm else {
            if staleSeries == nil {
                applyHistoryState(
                    .unavailable(
                        entityID: id,
                        range: resolvedRange,
                        message: "history requires a connected Home Assistant session"
                    )
                )
            }
            return
        }

        historyRequestGeneration += 1
        let requestGeneration = historyRequestGeneration
        if staleSeries == nil {
            applyHistoryState(.loading(entityID: id, range: resolvedRange))
        }
        recordOutboundRequest()
        let result = await historyProvider(form, id, resolvedRange)
        guard !Task.isCancelled, requestGeneration == historyRequestGeneration else {
            return
        }

        switch result {
        case let .success(series):
            guard series.entityID == id, series.range == resolvedRange else {
                applyHistoryState(
                    .unavailable(
                        entityID: id,
                        range: resolvedRange,
                        message: "history provider returned the wrong series"
                    )
                )
                return
            }
            let insertNow = await clock.now()
            lastObservedInstant = insertNow
            insertHistory(series, for: cacheKey, now: insertNow)
            applyHistoryState(.loaded(series))
        case let .unavailable(message):
            if staleSeries == nil {
                applyHistoryState(.unavailable(entityID: id, range: resolvedRange, message: message))
            }
        }
    }

    private var effectivePeriodicRefreshInterval: PerchDuration {
        guard periodicRefreshConfiguration.isEnabled else {
            return .seconds(0)
        }
        let configuredDefault = PerchHAPeriodicRefreshConfiguration().interval
        if periodicRefreshConfiguration.interval != configuredDefault {
            return periodicRefreshConfiguration.interval
        }
        return PerchDuration.seconds(Int64(displayPreferences.dataSyncInterval.rawValue))
    }

    private var effectiveBulkSyncInterval: PerchDuration {
        guard bulkSyncConfiguration.isEnabled else {
            return .seconds(0)
        }
        let configuredDefault = PerchHAHistoryBulkSyncConfiguration().interval
        if bulkSyncConfiguration.interval != configuredDefault {
            return bulkSyncConfiguration.interval
        }
        return PerchDuration.seconds(Int64(displayPreferences.dataSyncInterval.rawValue))
    }

    private var effectiveHistoryDetailRefreshInterval: PerchDuration {
        PerchDuration.seconds(Int64(displayPreferences.historyDetailRefreshInterval.rawValue))
    }

    private func restartHistoryDetailRefresh() {
        cancelHistoryDetailRefresh()
        guard isPanelActive,
              let entityID = snapshot.historyPresentationEntityID,
              effectiveHistoryDetailRefreshInterval.nanoseconds > 0
        else {
            return
        }
        let interval = effectiveHistoryDetailRefreshInterval
        let range = snapshot.historyState.range ?? historyRange(for: entityID)
        historyDetailRefreshTask = Task { @MainActor [weak self, clock] in
            while !Task.isCancelled {
                do {
                    _ = try await clock.sleep(for: interval)
                } catch {
                    return
                }
                guard let model = self,
                      model.isPanelActive,
                      model.snapshot.historyPresentationEntityID == entityID,
                      (model.snapshot.historyState.range ?? model.historyRange(for: entityID)) == range
                else {
                    return
                }
                await model.refreshPresentedHistoryInBackground(entityID: entityID, range: range)
            }
        }
    }

    private func cancelHistoryDetailRefresh() {
        historyDetailRefreshTask?.cancel()
        historyDetailRefreshTask = nil
    }

    private func refreshPresentedHistoryInBackground(entityID: EntityID, range: HistoryRange) async {
        guard let form = lastConnectedForm else {
            return
        }
        recordOutboundRequest()
        let result = await historyProvider(form, entityID, range)
        guard !Task.isCancelled,
              snapshot.historyPresentationEntityID == entityID,
              (snapshot.historyState.range ?? historyRange(for: entityID)) == range
        else {
            return
        }
        switch result {
        case let .success(series):
            guard series.entityID == entityID, series.range == range else {
                return
            }
            let insertNow = await clock.now()
            lastObservedInstant = insertNow
            insertHistory(series, for: PerchHAHistoryCacheKey(entityID: entityID, range: range), now: insertNow)
            applyHistoryState(.loaded(series))
        case .unavailable:
            return
        }
    }

    /// Returns an already-cached history series for an entity without fetching.
    ///
    /// This is the *only* history access intended for visible-row rendering: it
    /// reads the in-memory cache without mutating recency, without evicting, and
    /// crucially without ever triggering a network fetch. Rows use it to draw an
    /// inline sparkline whenever the background bulk sync has warmed the
    /// entity — never gated on hover. Hover only drives the detail popover. When
    /// nothing is cached yet it returns `nil` and the row draws no sparkline.
    /// Re-rendering as fresh data lands is driven by ``historyRevision``; honoring
    /// the no-fetch contract keeps the idle-CPU and request-volume budgets intact.
    ///
    /// - Parameter id: The entity whose cached history is requested.
    /// - Returns: The cached series for the entity's default range, or `nil`.
    public func cachedHistorySeries(for id: EntityID) -> HistorySeries? {
        let range = historyRange(for: id)
        return cachedHistorySeries(for: id, range: range)
    }

    func knownUnavailableHistoryRanges(for id: EntityID) -> Set<HistoryRange> {
        Set(
            HistoryRange.uiSelectable.filter { range in
                if let series = cachedHistorySeries(for: id, range: range) {
                    return series.samples.isEmpty
                }
                if case let .unavailable(entityID, unavailableRange, _) = snapshot.historyState {
                    return entityID == id && unavailableRange == range
                }
                return false
            }
        )
    }

    func cachedHistorySeries(for id: EntityID, range: HistoryRange) -> HistorySeries? {
        let key = PerchHAHistoryCacheKey(entityID: id, range: range)
        // Display uses the stale-tolerant peek so the inline sparkline keeps
        // showing its last-known data instead of flickering out when the entry
        // crosses its TTL; the bulk sync loop refreshes it underneath.
        return historyCache.peekAllowingStale(for: key)
    }

    func cachedInlinePreview(for id: EntityID) -> PerchHAInlineHistoryPreviewData? {
        let range = historyRange(for: id)
        let key = PerchHAHistoryCacheKey(entityID: id, range: range)
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
            let geometry = PerchHAHistorySparklineGeometry(
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

    /// Inserts a series into the history cache and publishes an observable change.
    ///
    /// Every cache write (prefetch warm or hover load) flows through here so the
    /// inline-preview read path, which depends on ``historyRevision``, re-renders
    /// the affected rows immediately. The bump is a cheap counter; it carries no
    /// series payload, so chart redraw throttling stays intact.
    private func insertHistory(_ series: HistorySeries, for key: PerchHAHistoryCacheKey, now: PerchInstant) {
        historyCache.insert(
            series,
            for: key,
            now: now,
            capacity: historyCacheConfiguration.capacity,
            ttl: historyCacheTTL(for: key.range),
            protecting: protectedHistoryKeys()
        )
        inlineSparklineGeometryCache[key] = nil
        bumpHistoryRevisions(for: [key.entityID])
    }

    /// The cache keys that back the on-screen inline previews: the currently
    /// visible entities at their effective preview range, plus the opened
    /// detail entity's background-maintained layers. Keeping protection scoped
    /// to what the user can actually see keeps the cache from bloating around
    /// off-screen rows.
    private func protectedHistoryKeys() -> Set<PerchHAHistoryCacheKey> {
        var keys = Set(
            visibleEntityIDs.map { id in
                PerchHAHistoryCacheKey(
                    entityID: id,
                    range: historyRange(for: id)
                )
            }
        )
        if let presenting = snapshot.historyPresentationEntityID {
            for range in detailMaintenanceHistoryRanges(for: presenting) {
                keys.insert(PerchHAHistoryCacheKey(entityID: presenting, range: range))
            }
        }
        return keys
    }

    /// The extra ranges maintained for an opened history detail.
    ///
    /// Day stays close to live use and acts as the cheap maintenance pass.
    /// Week and month piggyback on that recurring visible-row maintenance only
    /// when those caches are older than 24 hours (or absent), so long-range
    /// fetches stay rare without depending on click-time warming.
    private static let detailMaintenanceBaseRange: HistoryRange = .day
    private static let detailLongRangeMaintenance: [HistoryRange] = [.week, .month]
    private static let longRangeMaintenanceAge = PerchDuration.seconds(86_400)

    private func detailMaintenanceHistoryRanges(for id: EntityID) -> [HistoryRange] {
        var ordered: [HistoryRange] = []
        func append(_ range: HistoryRange) {
            if !ordered.contains(range) {
                ordered.append(range)
            }
        }
        append(historyRange(for: id))
        append(Self.detailMaintenanceBaseRange)
        for range in Self.detailLongRangeMaintenance {
            append(range)
        }
        return ordered
    }

    private func historyCacheTTL(for range: HistoryRange) -> PerchDuration {
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

    private func minimumBulkSyncInterval(for range: HistoryRange) -> PerchDuration {
        switch range {
        case .week, .month:
            return Self.longRangeMaintenanceAge
        case .hour, .day:
            return bulkSyncConfiguration.interval
        }
    }

    private func scaledDuration(_ duration: PerchDuration, by multiplier: Int64) -> PerchDuration {
        let scaled = duration.nanoseconds.multipliedReportingOverflow(by: max(1, multiplier))
        return PerchDuration(nanoseconds: scaled.overflow ? Int64.max : scaled.partialValue)
    }

    /// Drops the entire history cache and publishes the eviction so previews that
    /// were drawing a now-cleared series re-render empty.
    private func evictAllHistory() {
        historyCache = PerchHAHistoryCache()
        inlineSparklineGeometryCache.removeAll(keepingCapacity: true)
        bumpHistoryRevisions(for: displayedEntityIDs())
    }

    // MARK: - History bulk sync loop

    /// Marks the panel as shown or hidden, gating the background history sync.
    ///
    /// The app shell calls this with `true` when the panel becomes visible and
    /// `false` when it is hidden or closed. While inactive the model does no
    /// background fetching whatsoever: the re-arming bulk sync loop is cancelled
    /// and no cycle runs. Re-activating with a known visible set re-arms the loop.
    ///
    /// - Parameter active: Whether the panel is currently shown.
    public func setPanelActive(_ active: Bool) {
        guard active != isPanelActive else {
            return
        }
        isPanelActive = active
        if active {
            flushDeferredBackgroundLiveStates()
            // A reopen starts cold so every displayed row refreshes in the first
            // cycle; previews that aged while the panel was hidden catch up
            // immediately instead of waiting out the warm-cycle rotation.
            bulkSyncCycle = 0
            startHistoryBulkSync()
            // Opening the panel should render from the current snapshot/cache
            // first, then let background refresh happen quietly afterward.
            startPeriodicRefresh(refreshImmediately: false)
            restartHistoryDetailRefresh()
        } else {
            closeHistoryHoverImmediately()
            cancelHistoryBulkSync()
            cancelPeriodicRefresh()
            cancelHistoryDetailRefresh()
        }
    }

    /// Starts the active-panel periodic refresh safety net.
    ///
    /// Refreshes once on open (a discovery/refresh when a session is connected),
    /// then repeats on the injected clock at the configured interval while the
    /// panel stays active. Refreshes coalesce with any in-flight action and never
    /// fire while the panel is closed. A failed refresh backs off exponentially up
    /// to the configured ceiling; a success resets the streak to the base
    /// interval. Live WebSocket push remains the primary update path; this is a
    /// gentle backstop that keeps the request-volume budget intact.
    private func startPeriodicRefresh(refreshImmediately: Bool = true) {
        periodicRefreshTask?.cancel()
        guard effectivePeriodicRefreshInterval.nanoseconds > 0, lastConnectedForm != nil else {
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
                guard let delay = self.map({ $0.periodicRefreshDelay() }), self?.isPanelActive == true else {
                    return
                }
                do {
                    _ = try await clock.sleep(for: delay)
                } catch {
                    return
                }
                guard !Task.isCancelled, let model = self, model.isPanelActive, model.lastConnectedForm != nil else {
                    return
                }
                await model.runPeriodicRefreshTick()
            }
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
    /// change immediately — the primary update path promised by the product;
    /// the periodic refresh is only a safety net. It runs independently of
    /// panel visibility so promoted menu-bar items stay live with the panel
    /// closed. A dropped stream reconnects with exponential backoff on the
    /// injected clock, resetting to the base delay once events flowed. The
    /// loop ends on cancellation or when the connection identity changes.
    private func startLiveUpdates() {
        liveUpdateTask?.cancel()
        liveUpdateTask = nil
        guard liveUpdateConfiguration.isEnabled,
              let streamer = liveUpdateStreamer,
              let form = lastConnectedForm
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
                let receipt = PerchHALiveEventReceipt()
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
                    : PerchDuration(nanoseconds: min(reconnectDelay.nanoseconds * 2, maximumBackoff.nanoseconds))
                model.recordDiagnostic(
                    .liveUpdatesInterrupted,
                    message: "Live updates interrupted: \(PerchHAPanelSnapshot.describe(failure))"
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
    private func recordDiagnostic(_ kind: PerchHADiagnosticEventKind, message: String) {
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
    public func relativeAgeDescription(for event: PerchHADiagnosticEvent) -> String {
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
        let next: PerchHARetryBackoffState
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
    private func periodicRefreshDelay() -> PerchDuration {
        guard periodicRefreshFailureStreak > 0 else {
            return effectivePeriodicRefreshInterval
        }
        // First failure already doubles the base interval, then 4x, 8x, … capped.
        let multiplier = Int64(1 << min(periodicRefreshFailureStreak, 8))
        let scaled = effectivePeriodicRefreshInterval.nanoseconds.multipliedReportingOverflow(by: multiplier)
        let capped = min(scaled.overflow ? Int64.max : scaled.partialValue, periodicRefreshConfiguration.maximumBackoff.nanoseconds)
        return PerchDuration(nanoseconds: capped)
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

    /// The maximum interest score any single entity can accumulate, so a row that
    /// stays visible for a long time cannot grow an unbounded score.
    private static let maxEntityInterest = 1_000

    /// Reports the entities currently visible in the panel, in display order.
    ///
    /// The view calls this as rows appear and disappear. Visibility feeds two
    /// things: the per-entity interest score (visible entities are "hot" and sync
    /// every cycle), and a re-arm of the bulk sync loop coalesced behind the
    /// configured settle delay so rapid scroll updates never thrash the sync.
    ///
    /// - Parameter ids: The visible entity IDs in display order.
    public func updateVisibleEntities(_ ids: [EntityID]) {
        guard ids != visibleEntityIDs else {
            return
        }
        visibleEntityIDs = ids
        for id in ids {
            bumpInterest(id)
        }
        startHistoryBulkSync()
    }

    /// Records user interest in an entity (visible row or opened detail/hover).
    ///
    /// Interest is the prioritization signal for the bulk sync loop: hot entities
    /// (interest above zero or currently visible) sync every cycle. The score is
    /// clamped so it can never grow without bound.
    private func bumpInterest(_ id: EntityID) {
        entityInterest[id] = min(Self.maxEntityInterest, (entityInterest[id] ?? 0) + 1)
    }

    /// The panel's displayed entities flattened in display order.
    private func displayedEntityIDs() -> [EntityID] {
        snapshot.rooms.flatMap(\.entities).map(\.id)
    }

    /// Starts (or re-arms) the single background bulk history sync loop.
    ///
    /// Cancelling and restarting the one task is what coalesces rapid visibility
    /// changes: only the loop armed by the final change survives the settle delay.
    /// The loop is silent (it overrides cache entries in place and never flips the
    /// connection state), gated on an active panel with a connected session, and
    /// re-arms itself every cycle — fixing "runs once then goes stale". Does
    /// nothing while inactive, disconnected, or when bulk sync is disabled.
    private func startHistoryBulkSync() {
        bulkSyncTask?.cancel()
        bulkSyncTask = nil
        let interval = effectiveBulkSyncInterval
        guard interval.nanoseconds > 0, isPanelActive, lastConnectedForm != nil else {
            return
        }
        let settleDelay = bulkSyncConfiguration.settleDelay
        bulkSyncTask = Task { @MainActor [weak self, clock] in
            do {
                // Settle first so scrolling coalesces into one armed loop.
                _ = try await clock.sleep(for: settleDelay)
            } catch {
                return
            }
            // Self is re-bound weakly each iteration so the long-lived loop
            // never pins the model; deinit stays reachable and cancels the task.
            while !Task.isCancelled {
                guard let model = self, model.isPanelActive, model.lastConnectedForm != nil else {
                    return
                }
                // While the connection is failed, fetching is pointless: the
                // periodic refresh (with its own exponential backoff) drives
                // recovery, and hammering every batch across every fallback URL
                // each cycle would just amplify the outage. Skip, keep sleeping.
                if !model.connectionStateIsFailed {
                    await model.runBulkSyncCycle()
                }
                guard !Task.isCancelled, self?.isPanelActive == true else {
                    return
                }
                do {
                    _ = try await clock.sleep(for: interval)
                } catch {
                    return
                }
            }
        }
    }

    private func cancelHistoryBulkSync() {
        bulkSyncTask?.cancel()
        bulkSyncTask = nil
    }

    /// Runs one bulk sync cycle: fetches history for the prioritized entities via
    /// the bulk provider (grouped by range), then overrides matching cache entries
    /// in place. Entities absent from a bulk result keep their existing cached
    /// series — a cycle never deletes a valid entry. Bounded by the batch cap and
    /// the concurrent-batch limit so request volume stays well below per-entity.
    private func runBulkSyncCycle() async {
        guard let form = lastConnectedForm else {
            return
        }
        guard transientUITrackingDepth == 0 else {
            return
        }
        let cycle = bulkSyncCycle
        bulkSyncCycle &+= 1
        pruneInterest()

        let now = await clock.now()
        let targets = bulkSyncTargets(cycle: cycle, now: now)
        guard !targets.isEmpty else {
            return
        }

        // Group entity/range targets by range so each bulk request covers a
        // single layer, then split each range group into client-capped batches.
        let byRange = Dictionary(grouping: targets) { key in
            key.range
        }
        var batches: [(range: HistoryRange, ids: [EntityID])] = []
        for (range, keys) in byRange {
            let ids = keys.map(\.entityID)
            var index = 0
            while index < ids.count {
                let upper = min(index + bulkSyncConfiguration.batchSize, ids.count)
                batches.append((range: range, ids: Array(ids[index..<upper])))
                index = upper
            }
        }
        guard !batches.isEmpty else {
            return
        }

        // Dispatch up to `maxConcurrentBatches` batches at a time. Each batch is a
        // single bulk request; results are applied on the MainActor after the
        // window completes so cache writes stay serialized.
        let limit = bulkSyncConfiguration.maxConcurrentBatches
        var index = 0
        while index < batches.count {
            // Identity compare, not value equality: a rebuilt-but-equivalent form
            // (fresh address-row UUIDs) must not abort the cycle mid-flight.
            guard !Task.isCancelled, isPanelActive, form.sameConnection(as: lastConnectedForm) else {
                return
            }
            let window = batches[index..<min(index + limit, batches.count)]
            index += limit
            for _ in window {
                recordOutboundRequest()
            }
            let results = await withTaskGroup(of: [PerchHAHistoryCacheKey: HistorySeries].self) { group in
                for batch in window {
                    let ids = batch.ids
                    let range = batch.range
                    group.addTask { [bulkHistoryProvider] in
                        let partial = await bulkHistoryProvider(form, ids, range)
                        var keyed: [PerchHAHistoryCacheKey: HistorySeries] = [:]
                        for (entityID, series) in partial {
                            keyed[PerchHAHistoryCacheKey(entityID: entityID, range: series.range)] = series
                        }
                        return keyed
                    }
                }
                var merged: [PerchHAHistoryCacheKey: HistorySeries] = [:]
                for await partial in group {
                    merged.merge(partial) { _, new in new }
                }
                return merged
            }
            await applyBulkSyncResults(results, from: form)
        }
    }

    /// The prioritized entity set to sync this cycle.
    ///
    /// Only currently visible rows participate in background sync. Every visible
    /// row keeps both its preview range and a day layer warm on the normal
    /// interval; that same recurring maintenance pass opportunistically refreshes
    /// week/month whenever those layers are older than 24 hours.
    private func bulkSyncTargets(cycle _: Int, now: PerchInstant) -> [PerchHAHistoryCacheKey] {
        let visible = Set(visibleEntityIDs)

        var seenKeys = Set<PerchHAHistoryCacheKey>()
        var targets: [PerchHAHistoryCacheKey] = []
        for id in visibleEntityIDs where visible.contains(id) {
            for range in visibleSyncRanges(for: id, now: now) {
                let key = PerchHAHistoryCacheKey(entityID: id, range: range)
                let minimumInterval = minimumBulkSyncInterval(for: range)
                if let lastSynced = entityLastSyncedAt[key],
                   now.nanosecondsSinceStart - lastSynced.nanosecondsSinceStart < minimumInterval.nanoseconds {
                    continue
                }
                if seenKeys.insert(key).inserted {
                    targets.append(key)
                }
            }
        }
        return targets
    }

    private func visibleSyncRanges(
        for id: EntityID,
        now: PerchInstant
    ) -> [HistoryRange] {
        var ranges: [HistoryRange] = []
        let previewRange = historyRange(for: id)
        if !ranges.contains(previewRange) {
            ranges.append(previewRange)
        }
        if !ranges.contains(Self.detailMaintenanceBaseRange) {
            ranges.append(Self.detailMaintenanceBaseRange)
        }
        let dayKey = PerchHAHistoryCacheKey(entityID: id, range: Self.detailMaintenanceBaseRange)
        let dayIsDue = entityLastSyncedAt[dayKey].map {
            now.nanosecondsSinceStart - $0.nanosecondsSinceStart >= bulkSyncConfiguration.interval.nanoseconds
        } ?? true
        guard dayIsDue else {
            return ranges
        }
        for range in Self.detailLongRangeMaintenance {
            let key = PerchHAHistoryCacheKey(entityID: id, range: range)
            let isOlderThanOneDay = entityLastSyncedAt[key].map {
                now.nanosecondsSinceStart - $0.nanosecondsSinceStart >= Self.longRangeMaintenanceAge.nanoseconds
            } ?? true
            if isOlderThanOneDay, !ranges.contains(range) {
                ranges.append(range)
            }
        }
        return ranges
    }

    /// Drops interest entries for entities no longer displayed so the score map
    /// stays bounded to the live working set.
    private func pruneInterest() {
        let live = Set(displayedEntityIDs() + visibleEntityIDs)
        entityInterest = entityInterest.filter { live.contains($0.key) }
        entityLastSyncedAt = entityLastSyncedAt.filter { live.contains($0.key.entityID) }
    }

    /// Whether the visible connection state is a failure (including failed-stale).
    private var connectionStateIsFailed: Bool {
        if case .failed = snapshot.connectionState {
            return true
        }
        return false
    }

    /// Overrides the cache in place for every series a cycle successfully fetched.
    /// Bumps ``historyRevision`` once per changed entry so inline previews redraw.
    /// Never removes an entry: entities absent here simply keep their prior series.
    ///
    /// Results are applied only while the cycle's connection is still the live
    /// one and the cycle has not been cancelled — a cancelled cycle finishing its
    /// in-flight batches must not write the previous connection's history into a
    /// freshly cleared cache (entity IDs overlap across HA instances).
    private func applyBulkSyncResults(_ results: [PerchHAHistoryCacheKey: HistorySeries], from form: PerchHAConnectionForm) async {
        guard !results.isEmpty, isPanelActive, !Task.isCancelled, form.sameConnection(as: lastConnectedForm) else {
            return
        }
        let now = await clock.now()
        lastObservedInstant = now
        var insertedAny = false
        var changedEntityIDs = Set<EntityID>()
        let protectedKeys = protectedHistoryKeys()
        for (key, series) in results {
            historyCache.insert(
                series,
                for: key,
                now: now,
                capacity: historyCacheConfiguration.capacity,
                ttl: historyCacheTTL(for: key.range),
                protecting: protectedKeys
            )
            inlineSparklineGeometryCache[key] = nil
            insertedAny = true
            entityLastSyncedAt[key] = now
            changedEntityIDs.insert(key.entityID)
        }
        let removedKeys = historyCache.pruneExpired(now: now, protecting: protectedKeys)
        for key in removedKeys {
            inlineSparklineGeometryCache[key] = nil
            entityLastSyncedAt[key] = nil
        }
        if insertedAny {
            bumpHistoryRevisions(for: changedEntityIDs)
        }
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
        closeHistoryHoverImmediately()
    }

    private func refreshSettingsSelectionTreeIfNeeded(newSnapshot: PerchHAPanelSnapshot) {
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
        path: [PerchHACustomActionServiceDataPathComponent],
        value: ActionValue
    ) -> Bool {
        updateCustomActionServiceData(id) { serviceData in
            PerchHAActionValuePathEditor.set(value, at: path, in: &serviceData)
        }
    }

    @discardableResult
    public func appendCustomActionServiceDataArrayValue(
        _ id: CustomActionID,
        path: [PerchHACustomActionServiceDataPathComponent],
        value: ActionValue
    ) -> Bool {
        updateCustomActionServiceData(id) { serviceData in
            PerchHAActionValuePathEditor.appendArrayValue(value, at: path, in: &serviceData)
        }
    }

    @discardableResult
    public func setCustomActionServiceDataText(
        _ id: CustomActionID,
        path: [PerchHACustomActionServiceDataPathComponent],
        text: String,
        kind: PerchHACustomActionServiceDataValueKind
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
        path: [PerchHACustomActionServiceDataPathComponent],
        kind: PerchHACustomActionServiceDataValueKind
    ) -> Bool {
        guard let action = customAction(id: id),
              let value = PerchHAActionValuePathEditor.value(at: path, in: action.action.serviceData)
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
        parentPath: [PerchHACustomActionServiceDataPathComponent],
        from oldKey: String,
        to newKey: String
    ) -> Bool {
        updateCustomActionServiceData(id) { serviceData in
            PerchHAActionValuePathEditor.renameKey(parentPath: parentPath, from: oldKey, to: newKey, in: &serviceData)
        }
    }

    @discardableResult
    public func removeCustomActionServiceDataValue(
        _ id: CustomActionID,
        path: [PerchHACustomActionServiceDataPathComponent]
    ) -> Bool {
        updateCustomActionServiceData(id) { serviceData in
            PerchHAActionValuePathEditor.remove(at: path, in: &serviceData)
        }
    }

    @discardableResult
    public func moveCustomActionServiceDataArrayValue(
        _ id: CustomActionID,
        path: [PerchHACustomActionServiceDataPathComponent],
        direction: SelectionMoveDirection
    ) -> Bool {
        updateCustomActionServiceData(id) { serviceData in
            PerchHAActionValuePathEditor.moveArrayValue(at: path, direction: direction, in: &serviceData)
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
        kind: PerchHACustomActionServiceDataValueKind
    ) -> Bool {
        let path: [PerchHACustomActionServiceDataPathComponent] = [.key(key)]
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
        kind: PerchHACustomActionServiceDataValueKind
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
        guard !snapshot.controlActionState.isRunning,
              let action = customActionConfiguration.action(id: id)
        else {
            return false
        }
        guard confirmed || !action.requiresConfirmation else {
            return false
        }
        controlActionTask?.cancel()
        controlActionTask = Task { @MainActor [weak self] in
            await self?.runCustomAction(id, confirmed: confirmed)
            if !Task.isCancelled {
                self?.controlActionTask = nil
            }
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

    @discardableResult
    public func startEntityControlToggle(_ id: EntityID, isOn: Bool) -> Bool {
        guard !snapshot.controlActionState.isRunning else {
            return false
        }
        guard canToggleEntityControl(id, isOn: isOn) else {
            return false
        }
        controlActionTask?.cancel()
        controlActionTask = Task { @MainActor [weak self] in
            await self?.setEntityControl(id, isOn: isOn)
            if !Task.isCancelled {
                self?.controlActionTask = nil
            }
        }
        return true
    }

    @discardableResult
    public func startCoverControl(_ id: EntityID, command: PerchHACoverCommand) -> Bool {
        guard !snapshot.controlActionState.isRunning else {
            return false
        }
        guard canRunCoverControl(id, command: command) else {
            return false
        }
        controlActionTask?.cancel()
        controlActionTask = Task { @MainActor [weak self] in
            await self?.setCoverControl(id, command: command)
            if !Task.isCancelled {
                self?.controlActionTask = nil
            }
        }
        return true
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
              let control = PerchHAEntityControl(entity: entity, actionState: snapshot.controlActionState)
        else {
            applyControlActionState(
                .failed(entityID: id, message: "entity does not support built-in controls"),
                lastUpdateDescription: "Control unavailable"
            )
            return false
        }
        guard control.isOn != isOn else {
            applyControlActionState(.idle)
            return false
        }

        let previousState = entity.state
        let previousPosition = entity.currentPosition
        let targetState = PerchHAEntityControl.optimisticState(isOn: isOn)
        let actionSpec = control.actionSpec(targetIsOn: isOn)
        pendingControlChange = PendingControlChange(
            entityID: id,
            previousState: previousState,
            previousPosition: previousPosition,
            targetState: targetState,
            targetPosition: previousPosition,
            name: entity.name
        )
        applyControlEntitySnapshot(
            id,
            state: targetState,
            currentPosition: previousPosition,
            actionState: .running(entityID: id),
            lastUpdateDescription: "Updating \(entity.name)"
        )

        recordOutboundRequest()
        let result = await actionRunner(form, actionSpec)
        guard !Task.isCancelled else {
            return false
        }

        switch result {
        case .success:
            pendingControlChange = nil
            applyControlEntitySnapshot(
                id,
                state: targetState,
                currentPosition: previousPosition,
                actionState: .idle,
                lastUpdateDescription: "Updated \(entity.name)"
            )
            return true
        case let .failed(message):
            pendingControlChange = nil
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

    @discardableResult
    public func setCoverPosition(_ id: EntityID, position: Int) async -> Bool {
        await setCoverControl(id, command: .setPosition(position))
    }

    @discardableResult
    public func setCoverControl(_ id: EntityID, command: PerchHACoverCommand) async -> Bool {
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
              let control = PerchHACoverControl(entity: entity, actionState: snapshot.controlActionState)
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
            if command.clampedPosition == control.position {
                applyControlActionState(.idle)
                return false
            }
        }

        let previousState = entity.state
        let previousPosition = entity.currentPosition
        let targetState = control.optimisticState(command: command, currentState: entity.state)
        let targetPosition = control.optimisticPosition(command: command)
        let actionSpec = control.actionSpec(command: command)
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
        let result = await actionRunner(form, actionSpec)
        guard !Task.isCancelled else {
            return false
        }

        switch result {
        case .success:
            pendingControlChange = nil
            applyControlEntitySnapshot(
                id,
                state: targetState,
                currentPosition: targetPosition,
                actionState: .idle,
                lastUpdateDescription: "Updated \(entity.name)"
            )
            return true
        case let .failed(message):
            pendingControlChange = nil
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

    private func applyHistoryState(_ historyState: PerchHAHistoryPanelState) {
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
              let control = PerchHAEntityControl(entity: entity, actionState: snapshot.controlActionState)
        else {
            return false
        }
        return control.isOn != isOn
    }

    private func canRunCoverControl(_ id: EntityID, command: PerchHACoverCommand) -> Bool {
        guard let entity = entity(for: id),
              let control = PerchHACoverControl(entity: entity, actionState: snapshot.controlActionState)
        else {
            return false
        }
        if case .setPosition = command {
            guard control.position != nil else {
                return false
            }
            return command.clampedPosition != control.position
        }
        return true
    }

    private func applyControlActionState(
        _ actionState: PerchHAControlActionState,
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
        actionState: PerchHAControlActionState,
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
        let nextPhase: PerchHAPanelPhase
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
                        currentPosition: currentPosition
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
        historyTask?.cancel()
        historyTask = nil
        historyRequestGeneration += 1
        pendingControlChange = nil
        evictAllHistory()
        cancelHistoryBulkSync()
        cancelPeriodicRefresh()
        cancelLiveUpdates()
        entityInterest = [:]
        entityLastSyncedAt = [:]
        bulkSyncCycle = 0
        visibleEntityIDs = []
        lastConnectedForm = nil
        oauthSignInState = .idle

        editableForm = PerchHAConnectionForm(
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
        await apply(result: result, form: form, refreshCount: snapshot.refreshCount)
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
        await apply(result: result, form: form, refreshCount: nextRefreshCount)
    }

    @discardableResult
    public func applyLiveState(_ state: EntityState) -> Bool {
        if transientUITrackingDepth > 0 {
            let exists = availableEntityLocations[state.id] != nil
            if exists {
                deferredLiveStates[state.id] = state
            }
            return exists
        }
        guard let location = availableEntityLocations[state.id] else {
            return false
        }
        if shouldDeferBackgroundLiveState(for: state.id) {
            deferredBackgroundLiveStates[state.id] = state
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
            currentPosition: state.currentPosition
        )
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
        let nextPhase: PerchHAPanelPhase
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
        let deferredStates = deferredBackgroundLiveStates.values.sorted { $0.id.rawValue < $1.id.rawValue }
        deferredBackgroundLiveStates = [:]
        for state in deferredStates {
            _ = applyLiveState(state)
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
        let trimmed = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return existing.name
        }
        let existingTrimmed = existing.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !existingTrimmed.isEmpty else {
            return trimmed
        }
        let lowered = trimmed.lowercased()
        let existingLowered = existingTrimmed.lowercased()
        let genericNames: Set<String> = [
            existing.id.rawValue.lowercased(),
            existing.id.domain.lowercased(),
            existing.id.domain.replacingOccurrences(of: "_", with: " ").lowercased(),
            "sensor",
            "select",
            "switch",
            "binary sensor",
            "number"
        ]
        if genericNames.contains(lowered) || lowered == existingLowered {
            return existingTrimmed
        }
        if liveNameIsLessSpecific(trimmed, than: existingTrimmed) {
            return existingTrimmed
        }
        return trimmed
    }

    private static func liveNameIsLessSpecific(_ candidate: String, than existing: String) -> Bool {
        let candidateTokens = normalizedEntityNameTokens(candidate)
        let existingTokens = normalizedEntityNameTokens(existing)
        guard !candidateTokens.isEmpty, !existingTokens.isEmpty else {
            return false
        }
        guard candidateTokens.count <= existingTokens.count else {
            return false
        }
        let existingTokenSet = Set(existingTokens)
        if Set(candidateTokens).isSubset(of: existingTokenSet) {
            return candidateTokens.count < existingTokens.count
                || candidate.count < existing.count
        }
        return false
    }

    private static func normalizedEntityNameTokens(_ raw: String) -> [String] {
        raw
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .split { !$0.isLetter && !$0.isNumber }
            .map(String.init)
    }

    private static func preferredLiveEntityUnit(_ candidate: String?, existing: DiscoveredEntity) -> String? {
        let trimmed = candidate?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let trimmed, !trimmed.isEmpty else {
            return existing.unit
        }
        return trimmed
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

    private func apply(result: PerchHAConnectionAttemptResult, form: PerchHAConnectionForm, refreshCount: Int) async {
        switch result {
        case let .success(rooms):
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
                entityInterest = [:]
                entityLastSyncedAt = [:]
                bulkSyncCycle = 0
                pendingControlChange = nil
            }
            lastConnectedForm = form
            editableForm = form
            let normalizedDisplayConfiguration = normalizedMenuBarDisplayConfiguration(
                snapshot.menuBarDisplayConfiguration,
                availableRooms: rooms
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
            let visibleRooms = selectedRooms(from: rooms, using: snapshot.selectionConfiguration)
            updateSnapshot { draft in
                draft.connectionState = .connected
                draft.phase = visibleRooms.isEmpty ? .connectedEmpty : .connectedData
                draft.rooms = visibleRooms
                draft.availableRooms = rooms
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
            if connectionChanged {
                // A genuine new connection cleared the cache and cancelled the bulk
                // sync above; re-arm so the visible rows warm again instead of
                // staying blank forever.
                startHistoryBulkSync()
            }
            if isPanelActive, periodicRefreshTask == nil {
                // First-run flow: the panel was opened before any session existed,
                // so activation could not arm the refresh safety net. Arm it now
                // that a connection exists; the immediate tick is skipped because
                // this connect just delivered fresh data.
                startPeriodicRefresh(refreshImmediately: false)
            }
            if connectionChanged || liveUpdateTask == nil {
                // The live push stream follows the session, not the panel: it
                // starts with the first successful connect and restarts when the
                // connection identity genuinely changes.
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

    private func refreshServiceMetadata(form: PerchHAConnectionForm) async {
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
        let detail = PerchHAPanelSnapshot.describe(failure)
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

    private func nonSecretForm(_ form: PerchHAConnectionForm) -> PerchHAConnectionForm {
        PerchHAConnectionForm(
            urlString: form.urlString,
            addresses: form.addresses,
            token: "",
            usesStoredAuthSession: form.usesStoredAuthSession,
            allowsSelfSignedCertificates: form.allowsSelfSignedCertificates
        )
    }

    private func hasToken(in form: PerchHAConnectionForm) -> Bool {
        !form.trimmedToken.isEmpty || form.usesStoredAuthSession
    }

    var tokenInputForView: String {
        editableForm.token
    }

    private func updateSnapshot(_ update: (inout PerchHAPanelSnapshot.Draft) -> Void) {
        snapshot = snapshot.updating { draft in
            draft.hasTokenInput = hasToken(in: editableForm)
            update(&draft)
        }
    }

    func protectedValueDraft(
        for id: CustomActionID,
        path: [PerchHACustomActionServiceDataPathComponent]
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
        path: [PerchHACustomActionServiceDataPathComponent]
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
        path: [PerchHACustomActionServiceDataPathComponent]
    ) {
        let pathKey = protectedValueDraftPathKey(id: id, path: path)
        protectedValueDrafts.removeValue(forKey: pathKey)
        if let reference = currentCustomActionServiceDataValue(for: id, path: path)?.protectedValueReference {
            protectedValueDrafts.removeValue(forKey: reference.rawValue)
        }
    }

    private func protectedValueDraftPathKey(
        id: CustomActionID,
        path: [PerchHACustomActionServiceDataPathComponent]
    ) -> String {
        "\(id.rawValue):\(serviceDataPathDescription(path))"
    }

    func isSensitiveServiceDataPath(_ path: [PerchHACustomActionServiceDataPathComponent]) -> Bool {
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
        path: [PerchHACustomActionServiceDataPathComponent]
    ) -> ActionValue? {
        guard let action = customActionConfiguration.action(id: id) else {
            return nil
        }
        return PerchHAActionValuePathEditor.value(at: path, in: action.action.serviceData)
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
        path: [PerchHACustomActionServiceDataPathComponent],
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
        path: [PerchHACustomActionServiceDataPathComponent],
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
        _ path: [PerchHACustomActionServiceDataPathComponent]
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
        let nextPhase: PerchHAPanelPhase
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
