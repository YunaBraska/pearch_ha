import Foundation
import AppKit
import SwiftUI
import UniformTypeIdentifiers
import PerchHACore
import PerchHASupport

public struct PerchHAConnectionForm: Equatable, Sendable {
    public var urlString: String
    public var fallbackURLString: String
    public var token: String
    public var usesStoredAuthSession: Bool

    public init(
        urlString: String = "",
        fallbackURLString: String = "",
        token: String = "",
        usesStoredAuthSession: Bool = false
    ) {
        self.urlString = urlString
        self.fallbackURLString = fallbackURLString
        self.token = token
        self.usesStoredAuthSession = usesStoredAuthSession
    }

    public var trimmedToken: String {
        token.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public func primaryURL() -> URL? {
        Self.validURL(urlString)
    }

    public func fallbackURL() -> URL? {
        let trimmed = fallbackURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }
        return Self.validURL(trimmed)
    }

    public var validationFailure: ConnectionFailure? {
        guard primaryURL() != nil else {
            return .protocolError("invalid Home Assistant URL")
        }
        if !fallbackURLString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, fallbackURL() == nil {
            return .protocolError("invalid fallback URL")
        }
        guard !trimmedToken.isEmpty || usesStoredAuthSession else {
            return .authentication
        }
        return nil
    }

    public static func normalizedHomeAssistantURLString(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              var components = URLComponents(string: trimmed),
              let scheme = components.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              let host = components.host?.trimmingCharacters(in: .whitespacesAndNewlines),
              !host.isEmpty
        else {
            return trimmed
        }

        components.scheme = scheme
        components.host = host.lowercased()
        components.user = nil
        components.password = nil
        components.query = nil
        components.fragment = nil
        components.path = normalizedHomeAssistantBasePath(components.path)

        return components.url?.absoluteString ?? trimmed
    }

    private static func validURL(_ text: String) -> URL? {
        let normalized = normalizedHomeAssistantURLString(text)
        guard let url = URL(string: normalized),
              ["http", "https"].contains(url.scheme?.lowercased() ?? ""),
              url.host?.isEmpty == false
        else {
            return nil
        }
        return url
    }

    private static func normalizedHomeAssistantBasePath(_ path: String) -> String {
        let segments = path
            .split(separator: "/", omittingEmptySubsequences: true)
            .map(String.init)
        guard !segments.isEmpty else {
            return ""
        }

        let trimmedSegments: [String]
        if let frontendIndex = segments.firstIndex(where: { frontendRouteSegments.contains($0.lowercased()) }) {
            trimmedSegments = Array(segments[..<frontendIndex])
        } else {
            trimmedSegments = segments
        }

        guard !trimmedSegments.isEmpty else {
            return ""
        }
        return "/" + trimmedSegments.joined(separator: "/")
    }

    private static let frontendRouteSegments: Set<String> = [
        "areas",
        "config",
        "dashboard",
        "developer-tools",
        "energy",
        "history",
        "lovelace",
        "map"
    ]
}

public enum PerchHAConnectionAttemptResult: Equatable, Sendable {
    case success(rooms: [Room])
    case failure(ConnectionFailure)
}

public enum PerchHAPanelPhase: Equatable, Sendable {
    case firstRun
    case connecting
    case connectedEmpty
    case connectedData
    case reconnecting(attempt: Int)
    case failed(ConnectionFailure)
    case failedStale(ConnectionFailure)
}

public enum SelectionPersistenceResult: Equatable, Sendable {
    case saved
    case failed(String)
}

public enum PerchHAHistoryProviderResult: Equatable, Sendable {
    case success(HistorySeries)
    case unavailable(String)
}

public enum PerchHAActionResult: Equatable, Sendable {
    case success
    case failed(String)
}

public enum PerchHAServiceMetadataProviderResult: Equatable, Sendable {
    case success([HAServiceMetadata])
    case unavailable(String)
}

public enum PerchHAOAuthSignInResult: Equatable, Sendable {
    case success
    case failed(String)
}

public enum PerchHAOAuthSignInState: Equatable, Sendable {
    case idle
    case signingIn
    case failed(String)
}

public enum PerchHACustomActionServiceDataValueKind: String, CaseIterable, Hashable, Sendable {
    case string
    case number
    case bool
    case object
    case array
}

public enum PerchHACustomActionServiceDataPathComponent: Equatable, Hashable, Sendable {
    case key(String)
    case index(Int)
}

public enum PerchHAControlActionState: Equatable, Sendable {
    case idle
    case running(entityID: EntityID)
    case failed(entityID: EntityID, message: String)

    public func isRunning(for entityID: EntityID) -> Bool {
        switch self {
        case let .running(runningEntityID):
            runningEntityID == entityID
        case .idle, .failed:
            false
        }
    }

    public func failureMessage(for entityID: EntityID) -> String? {
        switch self {
        case let .failed(failedEntityID, message) where failedEntityID == entityID:
            message
        case .idle, .running, .failed:
            nil
        }
    }

    public var isRunning: Bool {
        switch self {
        case .running:
            true
        case .idle, .failed:
            false
        }
    }
}

public struct PerchHAEntityControl: Equatable, Sendable {
    public let entityID: EntityID
    public let isOn: Bool
    public let isRunning: Bool
    public let failureMessage: String?

    public init?(entity: DiscoveredEntity, actionState: PerchHAControlActionState = .idle) {
        guard Self.supportedToggleDomains.contains(entity.id.domain),
              let isOn = Self.toggleState(entity.state)
        else {
            return nil
        }
        self.entityID = entity.id
        self.isOn = isOn
        self.isRunning = actionState.isRunning(for: entity.id)
        self.failureMessage = actionState.failureMessage(for: entity.id)
    }

    public func actionSpec(targetIsOn: Bool) -> ActionSpec {
        ActionSpec(
            domain: entityID.domain,
            service: targetIsOn ? "turn_on" : "turn_off",
            targetEntityID: entityID
        )
    }

    public static func optimisticState(isOn: Bool) -> String {
        isOn ? "on" : "off"
    }

    private static let supportedToggleDomains = Set(["switch", "light", "input_boolean"])

    private static func toggleState(_ state: String) -> Bool? {
        switch state.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "on":
            true
        case "off":
            false
        default:
            nil
        }
    }
}

public enum PerchHACoverCommand: Equatable, Sendable {
    case open
    case close
    case stop
    case setPosition(Int)

    public var service: String {
        switch self {
        case .open:
            "open_cover"
        case .close:
            "close_cover"
        case .stop:
            "stop_cover"
        case .setPosition:
            "set_cover_position"
        }
    }

    public var clampedPosition: Int? {
        switch self {
        case let .setPosition(position):
            min(max(position, 0), 100)
        case .open, .close, .stop:
            nil
        }
    }
}

public struct PerchHACoverControl: Equatable, Sendable {
    public let entityID: EntityID
    public let position: Int?
    public let isRunning: Bool
    public let failureMessage: String?

    public init?(entity: DiscoveredEntity, actionState: PerchHAControlActionState = .idle) {
        guard entity.id.domain == "cover" else {
            return nil
        }
        self.entityID = entity.id
        self.position = entity.currentPosition
        self.isRunning = actionState.isRunning(for: entity.id)
        self.failureMessage = actionState.failureMessage(for: entity.id)
    }

    public func actionSpec(command: PerchHACoverCommand) -> ActionSpec {
        let serviceData = command.clampedPosition.map { ["position": ActionValue.number(Double($0))] } ?? [:]
        return ActionSpec(
            domain: entityID.domain,
            service: command.service,
            targetEntityID: entityID,
            serviceData: serviceData
        )
    }

    public func optimisticState(command: PerchHACoverCommand, currentState: String) -> String {
        switch command {
        case .open:
            "open"
        case .close:
            "closed"
        case .stop:
            currentState
        case let .setPosition(position):
            min(max(position, 0), 100) == 0 ? "closed" : "open"
        }
    }

    public func optimisticPosition(command: PerchHACoverCommand) -> Int? {
        switch command {
        case .open:
            position.map { _ in 100 }
        case .close:
            position.map { _ in 0 }
        case .stop:
            position
        case let .setPosition(position):
            min(max(position, 0), 100)
        }
    }
}

public enum PerchHAHistoryPanelState: Equatable, Sendable {
    case idle
    case loading(entityID: EntityID, range: HistoryRange)
    case loaded(HistorySeries)
    case unavailable(entityID: EntityID, range: HistoryRange, message: String)

    public var entityID: EntityID? {
        switch self {
        case .idle:
            nil
        case let .loading(entityID, _), let .unavailable(entityID, _, _):
            entityID
        case let .loaded(series):
            series.entityID
        }
    }

    public var range: HistoryRange? {
        switch self {
        case .idle:
            nil
        case let .loading(_, range), let .unavailable(_, range, _):
            range
        case let .loaded(series):
            series.range
        }
    }
}

public struct PerchHAHistoryStatistics: Equatable, Sendable {
    public let current: Double
    public let minimum: Double
    public let average: Double
    public let maximum: Double

    public init(current: Double, minimum: Double, average: Double, maximum: Double) {
        self.current = current
        self.minimum = minimum
        self.average = average
        self.maximum = maximum
    }
}

public enum PerchHAHistoryContentSummary: Equatable, Sendable {
    /// The series fetched successfully but contained no samples at all.
    case empty
    /// The series contained samples, but none carried a numeric value. Retained
    /// only for genuinely empty state runs; non-numeric series with state samples
    /// surface as ``stateTimeline`` instead.
    case noNumericData
    /// The series carried only non-numeric state samples, collapsed into ordered
    /// timeline segments (covers, switches, binary sensors).
    case stateTimeline([HistoryStateSegment])
    case statistics(PerchHAHistoryStatistics)

    public init(series: HistorySeries) {
        guard !series.samples.isEmpty else {
            self = .empty
            return
        }
        let samples = series.chronologicalNumericSamples
        let values = samples.map(\.value)
        guard let current = samples.last?.value,
              let minimum = values.min(),
              let maximum = values.max()
        else {
            let segments = HistoryStateSegments.segments(of: series)
            self = segments.isEmpty ? .noNumericData : .stateTimeline(segments)
            return
        }
        self = .statistics(
            PerchHAHistoryStatistics(
                current: current,
                minimum: minimum,
                average: values.reduce(0, +) / Double(values.count),
                maximum: maximum
            )
        )
    }
}

public enum PerchHAHistoryBodyPresentation: Equatable, Sendable {
    case hidden
    case loadingSkeleton
    /// A successful fetch that returned no history for the selected range.
    case empty
    /// A successful fetch whose samples carried no numeric values and no state
    /// runs (a degenerate case kept for completeness).
    case noNumericData
    /// A successful fetch of a non-numeric series, presented as a state timeline.
    case stateTimeline(series: HistorySeries, segments: [HistoryStateSegment])
    case statistics(series: HistorySeries, statistics: PerchHAHistoryStatistics)
    case unavailable(String)

    public init(state: PerchHAHistoryPanelState, entityID: EntityID) {
        switch state {
        case .idle:
            self = .hidden
        case let .loading(loadingEntityID, _) where loadingEntityID == entityID:
            self = .loadingSkeleton
        case let .loaded(series) where series.entityID == entityID:
            switch PerchHAHistoryContentSummary(series: series) {
            case .empty:
                self = .empty
            case .noNumericData:
                self = .noNumericData
            case let .stateTimeline(segments):
                self = .stateTimeline(series: series, segments: segments)
            case let .statistics(statistics):
                self = .statistics(series: series, statistics: statistics)
            }
        case let .unavailable(unavailableEntityID, _, message) where unavailableEntityID == entityID:
            self = .unavailable(message)
        case .loading, .loaded, .unavailable:
            self = .hidden
        }
    }
}

public struct PerchHAHistorySparklinePoint: Equatable, Sendable {
    public let x: Double
    public let y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }
}

public struct PerchHAHistorySparklineGeometry: Equatable, Sendable {
    public let points: [PerchHAHistorySparklinePoint]

    public init(series: HistorySeries) {
        let samples = series.chronologicalNumericSamples
        guard samples.count > 1 else {
            points = Self.midline
            return
        }

        let times = samples.map { $0.timestamp.timeIntervalSince1970 }
        let values = samples.map(\.value)
        guard let firstTime = times.first,
              let lastTime = times.last,
              let minimum = values.min(),
              let maximum = values.max()
        else {
            points = Self.midline
            return
        }

        let timeSpan = lastTime - firstTime
        let valueSpan = maximum - minimum
        let lastIndex = max(samples.count - 1, 1)
        points = samples.enumerated().map { index, sample in
            let x = timeSpan > 0
                ? (sample.timestamp.timeIntervalSince1970 - firstTime) / timeSpan
                : Double(index) / Double(lastIndex)
            let y = valueSpan > 0
                ? 1 - ((sample.value - minimum) / valueSpan)
                : 0.5
            return PerchHAHistorySparklinePoint(
                x: x.clamped(to: 0...1),
                y: y.clamped(to: 0...1)
            )
        }
    }

    private static let midline = [
        PerchHAHistorySparklinePoint(x: 0, y: 0.5),
        PerchHAHistorySparklinePoint(x: 1, y: 0.5)
    ]
}

public enum PerchHAAccessibilityMotionPolicy: String, Equatable, Sendable {
    case system
    case reduced
}

public enum PerchHAAccessibilityContrastPolicy: String, Equatable, Sendable {
    case standard
    case increased
}

public struct PerchHAAccessibilityPreferences: Equatable, Sendable {
    public let reduceMotion: Bool
    public let increaseContrast: Bool

    public init(reduceMotion: Bool = false, increaseContrast: Bool = false) {
        self.reduceMotion = reduceMotion
        self.increaseContrast = increaseContrast
    }

    public var motionPolicy: PerchHAAccessibilityMotionPolicy {
        reduceMotion ? .reduced : .system
    }

    public var contrastPolicy: PerchHAAccessibilityContrastPolicy {
        increaseContrast ? .increased : .standard
    }
}

public struct PerchHAPanelAccessibilityPresentation: Equatable, Sendable {
    public let summary: String
    public let statusLabel: String
    public let contentLabel: String
    public let keyboardHint: String
    public let motionPolicy: PerchHAAccessibilityMotionPolicy
    public let contrastPolicy: PerchHAAccessibilityContrastPolicy

    public init(
        summary: String,
        statusLabel: String,
        contentLabel: String,
        keyboardHint: String,
        motionPolicy: PerchHAAccessibilityMotionPolicy,
        contrastPolicy: PerchHAAccessibilityContrastPolicy
    ) {
        self.summary = summary
        self.statusLabel = statusLabel
        self.contentLabel = contentLabel
        self.keyboardHint = keyboardHint
        self.motionPolicy = motionPolicy
        self.contrastPolicy = contrastPolicy
    }

    public var stateAnnouncement: String {
        "\(statusLabel), \(contentLabel)"
    }
}

public struct PerchHAControlAccessibilityPresentation: Equatable, Sendable {
    public let label: String
    public let hint: String
    public let isEnabled: Bool

    public init(label: String, hint: String, isEnabled: Bool) {
        self.label = label
        self.hint = hint
        self.isEnabled = isEnabled
    }
}

public struct PerchHAEntityRowAccessibilityPresentation: Equatable, Sendable {
    public let label: String
    public let value: String
    public let controls: [PerchHAControlAccessibilityPresentation]
    public let failureLabel: String?

    public init(
        label: String,
        value: String,
        controls: [PerchHAControlAccessibilityPresentation],
        failureLabel: String? = nil
    ) {
        self.label = label
        self.value = value
        self.controls = controls
        self.failureLabel = failureLabel
    }
}

public struct PerchHAPanelRootAccessibilityPresentation: Equatable, Sendable {
    public let label: String
    public let value: String
    public let hint: String
    public let motionPolicy: PerchHAAccessibilityMotionPolicy
    public let contrastPolicy: PerchHAAccessibilityContrastPolicy

    public init(panel: PerchHAPanelAccessibilityPresentation) {
        self.label = panel.summary
        self.value = panel.stateAnnouncement
        self.hint = panel.keyboardHint
        self.motionPolicy = panel.motionPolicy
        self.contrastPolicy = panel.contrastPolicy
    }
}

private extension HistorySeries {
    var chronologicalNumericSamples: [PerchHAHistoryCursorSample] {
        PerchHAHistoryCursor.numericSamples(of: self)
    }
}

public struct PerchHAHistoryCacheConfiguration: Equatable, Sendable {
    public let capacity: Int
    public let ttl: PerchDuration

    public init(capacity: Int = 32, ttl: PerchDuration = .seconds(60)) {
        self.capacity = max(1, capacity)
        self.ttl = ttl
    }
}

/// Tuning for the inline-history prefetch coordinator.
///
/// The coordinator warms the in-memory history cache for the rows the panel is
/// actually showing (plus a small lookahead) so the inline sparklines render
/// from cache without the row ever triggering a fetch. It is fully gated on the
/// panel being active and on settled visibility, and is bounded so it never
/// inflates request volume.
public struct PerchHAHistoryPrefetchConfiguration: Equatable, Sendable {
    /// Extra entities beyond the visible set to warm, taken in display order from
    /// the panel's ordered entity list.
    public let lookahead: Int
    /// How long visibility must stay unchanged before a prefetch pass runs, so
    /// scrolling never fetches.
    public let settleDelay: PerchDuration
    /// Refresh interval applied to visible entities. A visible entity is
    /// refetched once this interval has elapsed since its last fetch, even if its
    /// cached series is still within the cache TTL. Lookahead entities ignore this
    /// and only fetch when absent or expired by the cache TTL.
    public let activeRefreshInterval: PerchDuration
    /// Maximum number of history fetches allowed in flight at once during a pass.
    public let maxConcurrentFetches: Int

    /// Creates a prefetch configuration.
    ///
    /// - Parameters:
    ///   - lookahead: Entities to warm beyond the visible set (default 6).
    ///   - settleDelay: Quiet period before a pass runs (default 250 ms).
    ///   - activeRefreshInterval: Visible-entity refresh interval (default 30 s,
    ///     shorter than the typical 60 s cache TTL so visible rows refresh sooner).
    ///   - maxConcurrentFetches: In-flight fetch cap (default 3).
    public init(
        lookahead: Int = 6,
        settleDelay: PerchDuration = .milliseconds(250),
        activeRefreshInterval: PerchDuration = .seconds(30),
        maxConcurrentFetches: Int = 3
    ) {
        self.lookahead = max(0, lookahead)
        self.settleDelay = settleDelay
        self.activeRefreshInterval = activeRefreshInterval
        self.maxConcurrentFetches = max(1, maxConcurrentFetches)
    }
}

public struct PerchHAPanelSnapshot: Equatable, Sendable {
    public let connectionState: ConnectionState
    public let phase: PerchHAPanelPhase
    public let rooms: [Room]
    public let availableRooms: [Room]
    public let selectionConfiguration: EntitySelectionConfiguration
    public let menuBarDisplayConfiguration: MenuBarDisplayConfiguration
    public let selectionQuery: String
    public let isSettingsPresented: Bool
    public let connectionForm: PerchHAConnectionForm
    public let lastUpdateDescription: String
    public let refreshCount: Int
    public let canRetry: Bool
    public let hasTokenInput: Bool
    public let selectionPersistenceFailureDescription: String?
    public let displayPersistenceFailureDescription: String?
    public let serviceMetadataFailureDescription: String?
    public let historyState: PerchHAHistoryPanelState
    public let historyPresentationEntityID: EntityID?
    public let controlActionState: PerchHAControlActionState
    public let serviceMetadata: [HAServiceMetadata]

    public init(
        connectionState: ConnectionState = .disconnected,
        phase: PerchHAPanelPhase = .firstRun,
        rooms: [Room] = [],
        availableRooms: [Room] = [],
        selectionConfiguration: EntitySelectionConfiguration = EntitySelectionConfiguration(),
        menuBarDisplayConfiguration: MenuBarDisplayConfiguration = MenuBarDisplayConfiguration(),
        selectionQuery: String = "",
        isSettingsPresented: Bool = false,
        connectionForm: PerchHAConnectionForm = PerchHAConnectionForm(),
        lastUpdateDescription: String = "Never updated",
        refreshCount: Int = 0,
        canRetry: Bool = false,
        hasTokenInput: Bool = false,
        selectionPersistenceFailureDescription: String? = nil,
        displayPersistenceFailureDescription: String? = nil,
        serviceMetadataFailureDescription: String? = nil,
        historyState: PerchHAHistoryPanelState = .idle,
        historyPresentationEntityID: EntityID? = nil,
        controlActionState: PerchHAControlActionState = .idle,
            serviceMetadata: [HAServiceMetadata] = []
    ) {
        var sanitizedForm = connectionForm
        let tokenInputWasPresent = !sanitizedForm.trimmedToken.isEmpty
        sanitizedForm.token = ""
        self.connectionState = connectionState
        self.phase = phase
        self.rooms = rooms
        self.availableRooms = availableRooms
        self.selectionConfiguration = selectionConfiguration
        self.menuBarDisplayConfiguration = menuBarDisplayConfiguration
        self.selectionQuery = selectionQuery
        self.isSettingsPresented = isSettingsPresented
        self.connectionForm = sanitizedForm
        self.lastUpdateDescription = lastUpdateDescription
        self.refreshCount = refreshCount
        self.canRetry = canRetry
        self.hasTokenInput = hasTokenInput || tokenInputWasPresent
        self.selectionPersistenceFailureDescription = selectionPersistenceFailureDescription
        self.displayPersistenceFailureDescription = displayPersistenceFailureDescription
        self.serviceMetadataFailureDescription = serviceMetadataFailureDescription
        self.historyState = historyState
        self.historyPresentationEntityID = historyPresentationEntityID
        self.controlActionState = controlActionState
        self.serviceMetadata = serviceMetadata
    }

    public var visibleEntityCount: Int {
        rooms.reduce(0) { $0 + $1.entities.count }
    }

    public func control(for entity: DiscoveredEntity) -> PerchHAEntityControl? {
        PerchHAEntityControl(entity: entity, actionState: controlActionState)
    }

    public func coverControl(for entity: DiscoveredEntity) -> PerchHACoverControl? {
        PerchHACoverControl(entity: entity, actionState: controlActionState)
    }

    /// The cover control mode chosen for an entity.
    ///
    /// - Parameter entity: The entity to inspect.
    /// - Returns: The configured ``CoverControlMode`` (defaults to ``CoverControlMode/both``).
    public func coverControlMode(for entity: DiscoveredEntity) -> CoverControlMode {
        menuBarDisplayConfiguration.itemConfiguration(for: entity.id).coverControlMode
    }

    public var selectionTree: [SelectableRoom] {
        EntitySelectionProjector().selectionTree(
            rooms: availableRooms,
            configuration: selectionConfiguration,
            query: selectionQuery
        )
    }

    public var valuesAreStale: Bool {
        if case .reconnecting = phase {
            return true
        }
        if case .failedStale = phase {
            return true
        }
        return false
    }

    public var connectionSummary: String {
        switch connectionState {
        case .disconnected:
            "Disconnected"
        case .connecting:
            "Connecting"
        case .connected:
            "Connected"
        case let .reconnecting(attempt):
            "Reconnecting \(attempt)"
        case let .failed(failure):
            "Failed: \(Self.describe(failure))"
        }
    }

    public var accessibilitySummary: String {
        "PearchHA \(connectionSummary.lowercased()), \(visibleEntityCount) visible values"
    }

    public var failureDescription: String? {
        let failure: ConnectionFailure
        switch phase {
        case let .failed(value), let .failedStale(value):
            failure = value
        case .firstRun, .connecting, .connectedEmpty, .connectedData, .reconnecting:
            return nil
        }
        return Self.describe(failure)
    }

    public var canRefresh: Bool {
        canRetry
    }

    /// A short problem message for the panel footer, or `nil` when the connection
    /// is healthy.
    ///
    /// Reports a failure (``failureDescription``), reconnection, or a disconnected
    /// state. Returns `nil` while connecting or when connected and healthy so the
    /// footer stays silent during normal operation. Benign update chatter is never
    /// surfaced here.
    ///
    /// - Returns: A problem description suitable for the footer, or `nil`.
    public var problemDescription: String? {
        if let failureDescription {
            return failureDescription
        }
        switch phase {
        case let .reconnecting(attempt):
            return "Reconnecting (attempt \(attempt))"
        case .firstRun:
            switch connectionState {
            case .disconnected:
                return "Disconnected"
            case .connecting, .connected, .reconnecting, .failed:
                return nil
            }
        case .connecting, .connectedEmpty, .connectedData:
            return nil
        case .failed, .failedStale:
            return failureDescription
        }
    }

    public func formattedValue(for entity: DiscoveredEntity, locale: Locale = .current) -> FormattedEntityValue {
        let configuration = menuBarDisplayConfiguration.itemConfiguration(for: entity.id)
        return EntityValueFormatter(
            locale: locale,
            displayUnit: configuration.displayUnit,
            showsUnit: configuration.showsUnit,
            minValue: configuration.minValue,
            maxValue: configuration.maxValue
        ).format(entity, isStale: valuesAreStale)
    }

    public func accessibilityPresentation(
        preferences: PerchHAAccessibilityPreferences = PerchHAAccessibilityPreferences()
    ) -> PerchHAPanelAccessibilityPresentation {
        PerchHAPanelAccessibilityPresentation(
            summary: accessibilitySummary,
            statusLabel: "Connection status: \(connectionSummary)",
            contentLabel: accessibilityContentLabel,
            keyboardHint: accessibilityKeyboardHint,
            motionPolicy: preferences.motionPolicy,
            contrastPolicy: preferences.contrastPolicy
        )
    }

    public func accessibilityRow(
        for entity: DiscoveredEntity,
        customActions: [EntityCustomAction] = []
    ) -> PerchHAEntityRowAccessibilityPresentation {
        let value = formattedValue(for: entity)
        var controls: [PerchHAControlAccessibilityPresentation] = []

        if let control = control(for: entity) {
            controls.append(toggleAccessibility(for: entity, control: control))
        }
        if let coverControl = coverControl(for: entity) {
            controls.append(contentsOf: coverAccessibility(for: entity, control: coverControl))
        }
        controls.append(contentsOf: customActions.map(customActionAccessibility))

        return PerchHAEntityRowAccessibilityPresentation(
            label: "\(entity.name), \(value.text)",
            value: value.text,
            controls: controls,
            failureLabel: controlActionState.failureMessage(for: entity.id).map {
                "\(entity.name) control failed: \($0)"
            }
        )
    }

    public var canReorderSelectionWithKeyboard: Bool {
        selectionQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    public func selectionReorderAccessibilityHint(canMove: Bool, boundaryReason: String) -> String {
        if canMove {
            return "Changes display order"
        }
        if canReorderSelectionWithKeyboard {
            return boundaryReason
        }
        return "Clear search to reorder"
    }

    public func menuBarReorderAccessibilityHint(canMove: Bool, boundaryReason: String) -> String {
        if canMove {
            return "Changes menu bar order"
        }
        if canReorderSelectionWithKeyboard {
            return boundaryReason
        }
        return "Clear search to reorder"
    }

    public func redactedForDiagnostics() -> PerchHAPanelSnapshot {
        PerchHAPanelSnapshot(
            connectionState: connectionState,
            phase: phase,
            rooms: rooms,
            availableRooms: availableRooms,
            selectionConfiguration: selectionConfiguration,
            menuBarDisplayConfiguration: menuBarDisplayConfiguration,
            selectionQuery: selectionQuery,
            isSettingsPresented: isSettingsPresented,
            connectionForm: PerchHAConnectionForm(
                urlString: connectionForm.urlString,
                fallbackURLString: connectionForm.fallbackURLString,
                token: "",
                usesStoredAuthSession: connectionForm.usesStoredAuthSession
            ),
            lastUpdateDescription: lastUpdateDescription,
            refreshCount: refreshCount,
            canRetry: canRetry,
            hasTokenInput: hasTokenInput,
            selectionPersistenceFailureDescription: selectionPersistenceFailureDescription,
            displayPersistenceFailureDescription: displayPersistenceFailureDescription,
            serviceMetadataFailureDescription: serviceMetadataFailureDescription,
            historyState: historyState,
            historyPresentationEntityID: historyPresentationEntityID,
            controlActionState: controlActionState,
            serviceMetadata: serviceMetadata
        )
    }

    public static func describe(_ failure: ConnectionFailure) -> String {
        switch failure {
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

    private var accessibilityContentLabel: String {
        switch phase {
        case .firstRun:
            "Connection form"
        case .connecting:
            "Connecting to Home Assistant"
        case .connectedEmpty:
            "Connected, no selected values"
        case .connectedData:
            "\(visibleEntityCount) visible values"
        case let .reconnecting(attempt):
            "Reconnecting attempt \(attempt), showing stale values"
        case let .failed(failure):
            "Connection failed: \(Self.describe(failure))"
        case let .failedStale(failure):
            "Connection failed: \(Self.describe(failure)), showing stale values"
        }
    }

    private var accessibilityKeyboardHint: String {
        if isSettingsPresented {
            return "Use Tab to move through settings. Space toggles checkboxes. Reorder buttons move values without dragging."
        }
        switch phase {
        case .firstRun, .failed:
            return "Use Tab to move through connection fields. Return connects."
        case .connecting:
            return "Connection is in progress."
        case .connectedEmpty:
            return "Use Settings to choose visible values."
        case .connectedData, .reconnecting, .failedStale:
            return "Use Tab to move through values and controls. Space toggles switches. Sliders adjust cover positions."
        }
    }

    private func toggleAccessibility(
        for entity: DiscoveredEntity,
        control: PerchHAEntityControl
    ) -> PerchHAControlAccessibilityPresentation {
        let help = control.isRunning
            ? "Waiting for Home Assistant"
            : control.isOn ? "Turns \(entity.name) off" : "Turns \(entity.name) on"
        return PerchHAControlAccessibilityPresentation(
            label: "\(control.isOn ? "Turn off" : "Turn on") \(entity.name)",
            hint: help,
            isEnabled: !control.isRunning
        )
    }

    private func coverAccessibility(
        for entity: DiscoveredEntity,
        control: PerchHACoverControl
    ) -> [PerchHAControlAccessibilityPresentation] {
        var controls = [
            PerchHAControlAccessibilityPresentation(
                label: "Open \(entity.name)",
                hint: coverAccessibilityHint(for: entity, control: control, command: .open),
                isEnabled: !control.isRunning
            ),
            PerchHAControlAccessibilityPresentation(
                label: "Stop \(entity.name)",
                hint: coverAccessibilityHint(for: entity, control: control, command: .stop),
                isEnabled: !control.isRunning
            ),
            PerchHAControlAccessibilityPresentation(
                label: "Close \(entity.name)",
                hint: coverAccessibilityHint(for: entity, control: control, command: .close),
                isEnabled: !control.isRunning
            )
        ]
        if let position = control.position {
            controls.append(
                PerchHAControlAccessibilityPresentation(
                    label: "\(entity.name) position",
                    hint: "Current position \(position) percent",
                    isEnabled: !control.isRunning
                )
            )
        }
        return controls
    }

    private func coverAccessibilityHint(
        for entity: DiscoveredEntity,
        control: PerchHACoverControl,
        command: PerchHACoverCommand
    ) -> String {
        if control.isRunning {
            return "Waiting for Home Assistant"
        }
        switch command {
        case .open:
            return "Opens \(entity.name)"
        case .close:
            return "Closes \(entity.name)"
        case .stop:
            return "Stops \(entity.name)"
        case let .setPosition(position):
            return "Sets \(entity.name) to \(position) percent"
        }
    }

    private func customActionAccessibility(
        for action: EntityCustomAction
    ) -> PerchHAControlAccessibilityPresentation {
        let isEnabled = !controlActionState.isRunning
        return PerchHAControlAccessibilityPresentation(
            label: action.title,
            hint: isEnabled ? customActionAccessibilityHint(for: action) : "Waiting for Home Assistant",
            isEnabled: isEnabled
        )
    }

    private func customActionAccessibilityHint(for action: EntityCustomAction) -> String {
        action.requiresConfirmation ? "Asks before running" : "Runs saved Home Assistant service"
    }
}

private struct PerchHAHistoryCacheKey: Hashable, Sendable {
    let entityID: EntityID
    let range: HistoryRange
}

private struct PrefetchJob: Sendable {
    let entityID: EntityID
    let range: HistoryRange
    let key: PerchHAHistoryCacheKey
}

private struct PerchHAHistoryCacheEntry {
    let series: HistorySeries
    let expiresAt: PerchInstant
}

private struct PerchHAHistoryCache {
    private var entries: [PerchHAHistoryCacheKey: PerchHAHistoryCacheEntry] = [:]
    private var order: [PerchHAHistoryCacheKey] = []

    mutating func series(for key: PerchHAHistoryCacheKey, now: PerchInstant) -> HistorySeries? {
        guard let entry = entries[key] else {
            return nil
        }
        guard entry.expiresAt > now else {
            remove(key)
            return nil
        }
        markRecentlyUsed(key)
        return entry.series
    }

    /// Reads a cached series without touching recency or evicting expired
    /// entries, so views can opportunistically render an already-cached
    /// sparkline without mutating cache state or triggering any fetch.
    func peek(for key: PerchHAHistoryCacheKey, now: PerchInstant) -> HistorySeries? {
        guard let entry = entries[key], entry.expiresAt > now else {
            return nil
        }
        return entry.series
    }

    mutating func insert(
        _ series: HistorySeries,
        for key: PerchHAHistoryCacheKey,
        now: PerchInstant,
        configuration: PerchHAHistoryCacheConfiguration
    ) {
        entries[key] = PerchHAHistoryCacheEntry(
            series: series,
            expiresAt: now.advanced(by: configuration.ttl)
        )
        markRecentlyUsed(key)
        trim(to: configuration.capacity)
    }

    private mutating func markRecentlyUsed(_ key: PerchHAHistoryCacheKey) {
        order.removeAll { $0 == key }
        order.append(key)
    }

    private mutating func trim(to capacity: Int) {
        while order.count > capacity {
            let removed = order.removeFirst()
            entries[removed] = nil
        }
    }

    private mutating func remove(_ key: PerchHAHistoryCacheKey) {
        entries[key] = nil
        order.removeAll { $0 == key }
    }
}

private struct PendingControlChange {
    let entityID: EntityID
    let previousState: String
    let previousPosition: Int?
    let targetState: String
    let targetPosition: Int?
    let name: String
}

@MainActor
public final class PerchHAPanelModel: ObservableObject {
    public typealias Connector = @Sendable (PerchHAConnectionForm) async -> PerchHAConnectionAttemptResult
    public typealias HistoryProvider = @Sendable (PerchHAConnectionForm, EntityID, HistoryRange) async -> PerchHAHistoryProviderResult
    public typealias ServiceMetadataProvider = @Sendable (PerchHAConnectionForm) async -> PerchHAServiceMetadataProviderResult
    public typealias ActionRunner = @Sendable (PerchHAConnectionForm, ActionSpec) async -> PerchHAActionResult
    public typealias OAuthSignInRunner = @MainActor @Sendable (PerchHAConnectionForm) async -> PerchHAOAuthSignInResult
    public typealias SelectionConfigurationSink = @MainActor (EntitySelectionConfiguration) -> SelectionPersistenceResult
    public typealias MenuBarDisplayConfigurationSink = @MainActor (MenuBarDisplayConfiguration) -> SelectionPersistenceResult
    public typealias CustomActionConfigurationSink = @MainActor (CustomActionConfiguration) -> SelectionPersistenceResult
    public typealias SnapshotSink = @MainActor (PerchHAPanelSnapshot) -> Void
    /// Clears the persisted authentication session when the user signs out.
    public typealias SignOutHandler = @MainActor () -> Void

    @Published public private(set) var snapshot: PerchHAPanelSnapshot {
        didSet {
            snapshotSink(snapshot)
        }
    }
    @Published public private(set) var customActionConfiguration: CustomActionConfiguration
    @Published public private(set) var customActionPersistenceFailureDescription: String?
    @Published public private(set) var oauthSignInState = PerchHAOAuthSignInState.idle

    private let connector: Connector
    private let historyProvider: HistoryProvider
    private let serviceMetadataProvider: ServiceMetadataProvider
    private let actionRunner: ActionRunner
    private let oauthSignInRunner: OAuthSignInRunner
    private let clock: any PerchClock
    private let historyDebounce: PerchDuration
    private let historyHoverGrace: PerchDuration
    private let historyCacheConfiguration: PerchHAHistoryCacheConfiguration
    private let historyPrefetchConfiguration: PerchHAHistoryPrefetchConfiguration
    private let selectionSink: SelectionConfigurationSink
    private let menuBarDisplaySink: MenuBarDisplayConfigurationSink
    private let customActionSink: CustomActionConfigurationSink
    private let protectedActionValueStore: any ProtectedActionValueStore
    private let snapshotSink: SnapshotSink
    private let signOutHandler: SignOutHandler
    private var historyCache = PerchHAHistoryCache()
    private var lastObservedInstant = PerchInstant(nanosecondsSinceStart: 0)
    private var lastConnectedForm: PerchHAConnectionForm?
    private var editableForm: PerchHAConnectionForm
    private var actionTask: Task<Void, Never>?
    private var controlActionTask: Task<Void, Never>?
    private var pendingControlChange: PendingControlChange?
    private var historyTask: Task<Void, Never>?
    private var historyCloseTask: Task<Void, Never>?
    private var historyRequestGeneration = 0
    private var protectedValueDrafts: [String: String] = [:]
    private var isPanelActive = false
    private var visibleEntityIDs: [EntityID] = []
    private var prefetchTask: Task<Void, Never>?
    private var prefetchLastFetched: [PerchHAHistoryCacheKey: PerchInstant] = [:]
    private var prefetchQueue: [PrefetchJob] = []
    private var prefetchCursor = 0
    private var prefetchWorkers: [Task<Void, Never>] = []

    public init(
        snapshot: PerchHAPanelSnapshot = PerchHAPanelSnapshot(),
        connector: @escaping Connector = { _ in .failure(.protocolError("connection client is not configured")) },
        historyProvider: @escaping HistoryProvider = { _, _, _ in .unavailable("history client is not configured") },
        serviceMetadataProvider: @escaping ServiceMetadataProvider = { _ in .success([]) },
        actionRunner: @escaping ActionRunner = { _, _ in .failed("action client is not configured") },
        oauthSignInRunner: @escaping OAuthSignInRunner = { _ in .failed("OAuth sign-in is not configured") },
        clock: any PerchClock = SystemPerchClock(),
        historyDebounce: PerchDuration = .milliseconds(150),
        historyHoverGrace: PerchDuration = .milliseconds(300),
        historyCacheConfiguration: PerchHAHistoryCacheConfiguration = PerchHAHistoryCacheConfiguration(),
        historyPrefetchConfiguration: PerchHAHistoryPrefetchConfiguration = PerchHAHistoryPrefetchConfiguration(),
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
        self.snapshot = PerchHAPanelSnapshot(
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
        self.editableForm = snapshot.connectionForm
        self.connector = connector
        self.historyProvider = historyProvider
        self.serviceMetadataProvider = serviceMetadataProvider
        self.actionRunner = actionRunner
        self.oauthSignInRunner = oauthSignInRunner
        self.clock = clock
        self.historyDebounce = historyDebounce
        self.historyHoverGrace = historyHoverGrace
        self.historyCacheConfiguration = historyCacheConfiguration
        self.historyPrefetchConfiguration = historyPrefetchConfiguration
        self.selectionSink = selectionSink
        self.menuBarDisplaySink = menuBarDisplaySink
        self.customActionSink = customActionSink
        self.protectedActionValueStore = protectedActionValueStore ?? UnavailableProtectedActionValueStore()
    }

    deinit {
        actionTask?.cancel()
        controlActionTask?.cancel()
        historyTask?.cancel()
        historyCloseTask?.cancel()
        prefetchTask?.cancel()
        prefetchWorkers.forEach { $0.cancel() }
    }

    public func updateConnectionForm(
        urlString: String? = nil,
        fallbackURLString: String? = nil,
        token: String? = nil,
        usesStoredAuthSession: Bool? = nil
    ) {
        let nextUsesStoredAuthSession = usesStoredAuthSession
            ?? (token?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false ? false : editableForm.usesStoredAuthSession)
        editableForm = PerchHAConnectionForm(
            urlString: urlString ?? editableForm.urlString,
            fallbackURLString: fallbackURLString ?? editableForm.fallbackURLString,
            token: token ?? editableForm.token,
            usesStoredAuthSession: nextUsesStoredAuthSession
        )
        snapshot = PerchHAPanelSnapshot(
            connectionState: snapshot.connectionState,
            phase: snapshot.phase,
            rooms: snapshot.rooms,
            availableRooms: snapshot.availableRooms,
            selectionConfiguration: snapshot.selectionConfiguration,
            menuBarDisplayConfiguration: snapshot.menuBarDisplayConfiguration,
            selectionQuery: snapshot.selectionQuery,
            isSettingsPresented: snapshot.isSettingsPresented,
            connectionForm: nonSecretForm(editableForm),
            lastUpdateDescription: snapshot.lastUpdateDescription,
            refreshCount: snapshot.refreshCount,
            canRetry: snapshot.canRetry,
            hasTokenInput: hasToken(in: editableForm),
            selectionPersistenceFailureDescription: snapshot.selectionPersistenceFailureDescription,
            displayPersistenceFailureDescription: snapshot.displayPersistenceFailureDescription,
            serviceMetadataFailureDescription: snapshot.serviceMetadataFailureDescription,
            historyState: snapshot.historyState,
            historyPresentationEntityID: snapshot.historyPresentationEntityID,
            controlActionState: snapshot.controlActionState,
            serviceMetadata: snapshot.serviceMetadata
        )
    }

    public func startConnect() {
        startAction { [weak self] in
            await self?.connect()
        }
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
        if !form.fallbackURLString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, form.fallbackURL() == nil {
            oauthSignInState = .failed("invalid fallback URL")
            applyFailure(.protocolError("invalid fallback URL"), refreshCount: snapshot.refreshCount, canRetry: false)
            return
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
                fallbackURLString: form.fallbackURLString,
                token: "",
                usesStoredAuthSession: true
            )
            await connect()
        case let .failed(message):
            oauthSignInState = .failed(message)
        }
    }

    public func toggleSettings() {
        snapshot = PerchHAPanelSnapshot(
            connectionState: snapshot.connectionState,
            phase: snapshot.phase,
            rooms: snapshot.rooms,
            availableRooms: snapshot.availableRooms,
            selectionConfiguration: snapshot.selectionConfiguration,
            menuBarDisplayConfiguration: snapshot.menuBarDisplayConfiguration,
            selectionQuery: snapshot.selectionQuery,
            isSettingsPresented: !snapshot.isSettingsPresented,
            connectionForm: snapshot.connectionForm,
            lastUpdateDescription: snapshot.lastUpdateDescription,
            refreshCount: snapshot.refreshCount,
            canRetry: snapshot.canRetry,
            hasTokenInput: hasToken(in: editableForm),
            selectionPersistenceFailureDescription: snapshot.selectionPersistenceFailureDescription,
            displayPersistenceFailureDescription: snapshot.displayPersistenceFailureDescription,
            serviceMetadataFailureDescription: snapshot.serviceMetadataFailureDescription,
            historyState: snapshot.historyState,
            historyPresentationEntityID: snapshot.historyPresentationEntityID,
            controlActionState: snapshot.controlActionState,
            serviceMetadata: snapshot.serviceMetadata
        )
    }

    public func updateSelectionQuery(_ query: String) {
        snapshot = PerchHAPanelSnapshot(
            connectionState: snapshot.connectionState,
            phase: snapshot.phase,
            rooms: snapshot.rooms,
            availableRooms: snapshot.availableRooms,
            selectionConfiguration: snapshot.selectionConfiguration,
            menuBarDisplayConfiguration: snapshot.menuBarDisplayConfiguration,
            selectionQuery: query,
            isSettingsPresented: snapshot.isSettingsPresented,
            connectionForm: snapshot.connectionForm,
            lastUpdateDescription: snapshot.lastUpdateDescription,
            refreshCount: snapshot.refreshCount,
            canRetry: snapshot.canRetry,
            hasTokenInput: hasToken(in: editableForm),
            selectionPersistenceFailureDescription: snapshot.selectionPersistenceFailureDescription,
            displayPersistenceFailureDescription: snapshot.displayPersistenceFailureDescription,
            serviceMetadataFailureDescription: snapshot.serviceMetadataFailureDescription,
            historyState: snapshot.historyState,
            historyPresentationEntityID: snapshot.historyPresentationEntityID,
            controlActionState: snapshot.controlActionState,
            serviceMetadata: snapshot.serviceMetadata
        )
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
        updateMenuBarDisplayConfiguration(
            snapshot.menuBarDisplayConfiguration.settingPromotion(id, isPromoted: isVisible),
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
    public func setMenuBarDefaultHistoryRange(_ id: EntityID, defaultHistoryRange: HistoryRange) -> Bool {
        updateMenuBarItemConfiguration(
            snapshot.menuBarDisplayConfiguration.itemConfiguration(for: id).updating(
                defaultHistoryRange: defaultHistoryRange
            )
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
    public func setDisplayUnit(_ id: EntityID, displayUnit: ValueUnit?) -> Bool {
        updateMenuBarItemConfiguration(
            snapshot.menuBarDisplayConfiguration.itemConfiguration(for: id).settingDisplayUnit(displayUnit)
        )
    }

    @discardableResult
    public func setDisplayBounds(_ id: EntityID, minValue: Double?, maxValue: Double?) -> Bool {
        updateMenuBarItemConfiguration(
            snapshot.menuBarDisplayConfiguration.itemConfiguration(for: id)
                .settingBounds(minValue: minValue, maxValue: maxValue)
        )
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
    public func startHistoryHover(_ id: EntityID, range: HistoryRange? = nil) {
        let resolvedRange = range ?? snapshot.menuBarDisplayConfiguration.itemConfiguration(for: id).defaultHistoryRange
        cancelPendingHistoryClose()
        historyTask?.cancel()
        applyHistoryPresentationEntityID(id)
        historyTask = Task { @MainActor [weak self] in
            guard let self else {
                return
            }
            do {
                _ = try await clock.sleep(for: historyDebounce)
            } catch {
                return
            }
            await loadHistory(id, range: resolvedRange)
            if !Task.isCancelled {
                historyTask = nil
            }
        }
    }

    /// Keeps the history popover open while the cursor is inside it.
    ///
    /// Called when the cursor enters the popover content; cancels any pending
    /// grace-period close scheduled when the cursor left the underlying row.
    public func keepHistoryHoverAlive() {
        cancelPendingHistoryClose()
    }

    /// Schedules the history popover to close after the hover grace period.
    ///
    /// Called when the cursor leaves the row or the popover. The close does not
    /// happen immediately: a grace timer (``historyHoverGrace``) runs on the
    /// injected clock so the cursor can travel from the row into the popover
    /// without dismissing it. ``startHistoryHover(_:range:)`` or
    /// ``keepHistoryHoverAlive()`` called before the timer fires cancels the
    /// pending close.
    public func cancelHistoryHover() {
        let isLoading: Bool
        if case .loading = snapshot.historyState {
            isLoading = true
        } else {
            isLoading = false
        }
        guard snapshot.historyPresentationEntityID != nil || historyTask != nil || isLoading else {
            return
        }
        historyCloseTask?.cancel()
        historyCloseTask = Task { @MainActor [weak self] in
            guard let self else {
                return
            }
            do {
                _ = try await clock.sleep(for: historyHoverGrace)
            } catch {
                return
            }
            guard !Task.isCancelled else {
                return
            }
            historyCloseTask = nil
            closeHistoryHoverImmediately()
        }
    }

    private func cancelPendingHistoryClose() {
        historyCloseTask?.cancel()
        historyCloseTask = nil
    }

    /// Clears the history presentation right away, bypassing the grace period.
    ///
    /// Used by teardown paths (sign-out, reconnect, panel dismissal) where the
    /// popover must disappear without waiting.
    private func closeHistoryHoverImmediately() {
        cancelPendingHistoryClose()
        historyTask?.cancel()
        historyTask = nil
        historyRequestGeneration += 1
        applyHistoryPresentationEntityID(nil)
        if case .loading = snapshot.historyState {
            applyHistoryState(.idle)
        }
    }

    public func loadHistory(_ id: EntityID, range: HistoryRange? = nil) async {
        let resolvedRange = range ?? snapshot.menuBarDisplayConfiguration.itemConfiguration(for: id).defaultHistoryRange
        let cacheKey = PerchHAHistoryCacheKey(entityID: id, range: resolvedRange)
        let now = await clock.now()
        lastObservedInstant = now
        if let cachedSeries = historyCache.series(for: cacheKey, now: now) {
            applyHistoryState(.loaded(cachedSeries))
            return
        }

        guard let form = lastConnectedForm else {
            applyHistoryState(
                .unavailable(
                    entityID: id,
                    range: resolvedRange,
                    message: "history requires a connected Home Assistant session"
                )
            )
            return
        }

        historyRequestGeneration += 1
        let requestGeneration = historyRequestGeneration
        applyHistoryState(.loading(entityID: id, range: resolvedRange))
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
            historyCache.insert(
                series,
                for: cacheKey,
                now: insertNow,
                configuration: historyCacheConfiguration
            )
            applyHistoryState(.loaded(series))
        case let .unavailable(message):
            applyHistoryState(.unavailable(entityID: id, range: resolvedRange, message: message))
        }
    }

    /// Returns an already-cached history series for an entity without fetching.
    ///
    /// This is the *only* history access intended for visible-row rendering: it
    /// reads the in-memory cache without mutating recency, without evicting, and
    /// crucially without ever triggering a network fetch. Rows use it to draw an
    /// opportunistic inline sparkline only when the data is already present (for
    /// example after the user has hovered the row once). When nothing is cached it
    /// returns `nil` and the row draws no sparkline. Honoring this contract keeps
    /// the idle-CPU and request-volume budgets intact.
    ///
    /// - Parameter id: The entity whose cached history is requested.
    /// - Returns: The cached series for the entity's default range, or `nil`.
    public func cachedHistorySeries(for id: EntityID) -> HistorySeries? {
        let range = snapshot.menuBarDisplayConfiguration.itemConfiguration(for: id).defaultHistoryRange
        let key = PerchHAHistoryCacheKey(entityID: id, range: range)
        return historyCache.peek(for: key, now: lastObservedInstant)
    }

    // MARK: - History prefetch coordinator

    /// Marks the panel as shown or hidden, gating all history prefetch.
    ///
    /// The app shell calls this with `true` when the panel becomes visible and
    /// `false` when it is hidden or closed. While inactive the coordinator does no
    /// fetching whatsoever: any in-flight prefetch is cancelled and no background
    /// sync runs. Re-activating with a known visible set re-arms a settle pass.
    ///
    /// - Parameter active: Whether the panel is currently shown.
    public func setPanelActive(_ active: Bool) {
        guard active != isPanelActive else {
            return
        }
        isPanelActive = active
        if active {
            scheduleHistoryPrefetch()
        } else {
            cancelHistoryPrefetch()
        }
    }

    /// Reports the entities currently visible in the panel, in display order.
    ///
    /// The view calls this as rows appear and disappear. The coordinator warms the
    /// history cache for these entities plus the next ``PerchHAHistoryPrefetchConfiguration/lookahead``
    /// entities in the panel's ordered list. Calls are coalesced: a prefetch pass
    /// runs only once visibility has stayed unchanged for the configured settle
    /// delay, so rapid updates while scrolling never fetch.
    ///
    /// - Parameter ids: The visible entity IDs in display order.
    public func updateVisibleEntities(_ ids: [EntityID]) {
        guard ids != visibleEntityIDs else {
            return
        }
        visibleEntityIDs = ids
        scheduleHistoryPrefetch()
    }

    /// Arms (or re-arms) a debounced prefetch pass on the injected clock.
    ///
    /// Cancelling and restarting the single pending task is what coalesces rapid
    /// visibility changes: only the task armed by the final change survives the
    /// settle delay. Does nothing while the panel is inactive.
    private func scheduleHistoryPrefetch() {
        prefetchTask?.cancel()
        prefetchTask = nil
        guard isPanelActive, lastConnectedForm != nil, !visibleEntityIDs.isEmpty else {
            return
        }
        let settleDelay = historyPrefetchConfiguration.settleDelay
        prefetchTask = Task { @MainActor [weak self] in
            guard let self else {
                return
            }
            do {
                _ = try await clock.sleep(for: settleDelay)
            } catch {
                return
            }
            guard !Task.isCancelled else {
                return
            }
            await runHistoryPrefetchPass()
            if !Task.isCancelled {
                prefetchTask = nil
            }
        }
    }

    private func cancelHistoryPrefetch() {
        prefetchTask?.cancel()
        prefetchTask = nil
        prefetchWorkers.forEach { $0.cancel() }
        prefetchWorkers = []
    }

    /// Computes the prefetch target list: the visible entities plus the lookahead
    /// window, in display order, de-duplicated.
    private func prefetchTargets() -> [EntityID] {
        let ordered = displayedEntityIDs()
        let visible = Set(visibleEntityIDs)
        guard let lastVisibleIndex = ordered.lastIndex(where: { visible.contains($0) }) else {
            return visibleEntityIDs
        }
        let lookaheadEnd = min(ordered.count, lastVisibleIndex + 1 + historyPrefetchConfiguration.lookahead)
        let lookahead = ordered[(lastVisibleIndex + 1)..<lookaheadEnd]
        var seen = Set<EntityID>()
        var targets: [EntityID] = []
        for id in visibleEntityIDs + Array(lookahead) where seen.insert(id).inserted {
            targets.append(id)
        }
        return targets
    }

    /// The panel's displayed entities flattened in display order.
    private func displayedEntityIDs() -> [EntityID] {
        snapshot.rooms.flatMap(\.entities).map(\.id)
    }

    /// Runs one bounded prefetch pass for the current targets, skipping anything
    /// still fresh and capping concurrent fetches.
    private func runHistoryPrefetchPass() async {
        guard let form = lastConnectedForm else {
            return
        }
        let visible = Set(visibleEntityIDs)
        let now = await clock.now()
        lastObservedInstant = now

        let pending = prefetchTargets().compactMap { id -> PrefetchJob? in
            let range = snapshot.menuBarDisplayConfiguration.itemConfiguration(for: id).defaultHistoryRange
            let key = PerchHAHistoryCacheKey(entityID: id, range: range)
            return shouldPrefetch(key: key, isActive: visible.contains(id), now: now)
                ? PrefetchJob(entityID: id, range: range, key: key)
                : nil
        }
        guard !pending.isEmpty else {
            return
        }

        let limit = min(historyPrefetchConfiguration.maxConcurrentFetches, pending.count)
        prefetchQueue = pending
        prefetchCursor = 0
        // Up to `limit` workers run concurrently. Each pulls the next job from the
        // shared, MainActor-isolated cursor, so at most `limit` fetches are ever in
        // flight; the rest start only as a worker frees up.
        let workers: [Task<Void, Never>] = (0..<limit).map { _ in
            Task { @MainActor [weak self] in
                guard let self else {
                    return
                }
                await drainPrefetchQueue(form: form)
            }
        }
        prefetchWorkers = workers
        for worker in workers {
            await worker.value
        }
        prefetchWorkers = []
    }

    /// A single prefetch worker: repeatedly claims the next queued job and fetches
    /// it until the queue is drained, the task is cancelled, or the panel hides.
    private func drainPrefetchQueue(form: PerchHAConnectionForm) async {
        while !Task.isCancelled, isPanelActive {
            guard prefetchCursor < prefetchQueue.count else {
                return
            }
            let job = prefetchQueue[prefetchCursor]
            prefetchCursor += 1
            await prefetchOne(job, form: form)
        }
    }

    /// Decides whether an entity needs a fetch this pass.
    ///
    /// Lookahead entities fetch only when their cached series is absent or expired
    /// per the cache TTL. Visible (active) entities additionally refetch once the
    /// active refresh interval has elapsed since their last fetch, even while their
    /// cached series remains within the cache TTL.
    private func shouldPrefetch(key: PerchHAHistoryCacheKey, isActive: Bool, now: PerchInstant) -> Bool {
        let isCached = historyCache.peek(for: key, now: now) != nil
        guard isCached else {
            return true
        }
        guard isActive, let fetchedAt = prefetchLastFetched[key] else {
            return false
        }
        return fetchedAt.advanced(by: historyPrefetchConfiguration.activeRefreshInterval) <= now
    }

    /// Fetches one entity's history into the cache without touching the popover
    /// history state, recording the fetch instant for active-refresh accounting.
    private func prefetchOne(_ job: PrefetchJob, form: PerchHAConnectionForm) async {
        let result = await historyProvider(form, job.entityID, job.range)
        guard !Task.isCancelled, isPanelActive else {
            return
        }
        guard case let .success(series) = result, series.entityID == job.entityID, series.range == job.range else {
            return
        }
        let now = await clock.now()
        lastObservedInstant = now
        prefetchLastFetched[job.key] = now
        historyCache.insert(series, for: job.key, now: now, configuration: historyCacheConfiguration)
    }

    public func dismissHistoryPopover() {
        closeHistoryHoverImmediately()
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
            Self.setServiceDataValue(value, at: path, in: &serviceData)
        }
    }

    @discardableResult
    public func appendCustomActionServiceDataArrayValue(
        _ id: CustomActionID,
        path: [PerchHACustomActionServiceDataPathComponent],
        value: ActionValue
    ) -> Bool {
        updateCustomActionServiceData(id) { serviceData in
            Self.appendServiceDataArrayValue(value, at: path, in: &serviceData)
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
              let value = Self.serviceDataValue(at: path, in: action.action.serviceData)
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
            Self.renameServiceDataKey(parentPath: parentPath, from: oldKey, to: newKey, in: &serviceData)
        }
    }

    @discardableResult
    public func removeCustomActionServiceDataValue(
        _ id: CustomActionID,
        path: [PerchHACustomActionServiceDataPathComponent]
    ) -> Bool {
        updateCustomActionServiceData(id) { serviceData in
            Self.removeServiceDataValue(at: path, in: &serviceData)
        }
    }

    @discardableResult
    public func moveCustomActionServiceDataArrayValue(
        _ id: CustomActionID,
        path: [PerchHACustomActionServiceDataPathComponent],
        direction: SelectionMoveDirection
    ) -> Bool {
        updateCustomActionServiceData(id) { serviceData in
            Self.moveServiceDataArrayValue(at: path, direction: direction, in: &serviceData)
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

    private static func setServiceDataValue(
        _ value: ActionValue,
        at path: [PerchHACustomActionServiceDataPathComponent],
        in serviceData: inout [String: ActionValue]
    ) -> Bool {
        guard let first = path.first,
              case let .key(rawKey) = first
        else {
            return false
        }
        let trimmedKey = rawKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKey.isEmpty else {
            return false
        }
        let remainingPath = Array(path.dropFirst())
        guard !remainingPath.isEmpty else {
            serviceData[trimmedKey] = value
            return true
        }
        guard var existing = serviceData[trimmedKey] else {
            return false
        }
        guard setActionValue(value, at: remainingPath, in: &existing) else {
            return false
        }
        serviceData[trimmedKey] = existing
        return true
    }

    private static func setActionValue(
        _ value: ActionValue,
        at path: [PerchHACustomActionServiceDataPathComponent],
        in parent: inout ActionValue
    ) -> Bool {
        guard let first = path.first else {
            return false
        }
        switch (first, parent) {
        case let (.key(rawKey), .object(values)):
            let trimmedKey = rawKey.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedKey.isEmpty else {
                return false
            }
            var nextValues = values
            let remainingPath = Array(path.dropFirst())
            guard !remainingPath.isEmpty else {
                nextValues[trimmedKey] = value
                parent = .object(nextValues)
                return true
            }
            guard var child = nextValues[trimmedKey],
                  setActionValue(value, at: remainingPath, in: &child)
            else {
                return false
            }
            nextValues[trimmedKey] = child
            parent = .object(nextValues)
            return true
        case let (.index(index), .array(values)):
            guard values.indices.contains(index) else {
                return false
            }
            var nextValues = values
            let remainingPath = Array(path.dropFirst())
            guard !remainingPath.isEmpty else {
                nextValues[index] = value
                parent = .array(nextValues)
                return true
            }
            guard setActionValue(value, at: remainingPath, in: &nextValues[index]) else {
                return false
            }
            parent = .array(nextValues)
            return true
        case (.key, .string),
             (.key, .protectedString),
             (.key, .number),
             (.key, .bool),
             (.key, .array),
             (.key, .null),
             (.index, .string),
             (.index, .protectedString),
             (.index, .number),
             (.index, .bool),
             (.index, .object),
             (.index, .null):
            return false
        }
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

    private static func renameServiceDataKey(
        parentPath: [PerchHACustomActionServiceDataPathComponent],
        from oldKey: String,
        to newKey: String,
        in serviceData: inout [String: ActionValue]
    ) -> Bool {
        let trimmedOldKey = oldKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedNewKey = newKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedOldKey.isEmpty, !trimmedNewKey.isEmpty else {
            return false
        }
        guard !parentPath.isEmpty else {
            guard let value = serviceData[trimmedOldKey],
                  trimmedOldKey == trimmedNewKey || serviceData[trimmedNewKey] == nil
            else {
                return false
            }
            serviceData.removeValue(forKey: trimmedOldKey)
            serviceData[trimmedNewKey] = value
            return true
        }
        return updateServiceDataValue(at: parentPath, in: &serviceData) { parent in
            guard case let .object(values) = parent else {
                return false
            }
            guard let value = values[trimmedOldKey],
                  trimmedOldKey == trimmedNewKey || values[trimmedNewKey] == nil
            else {
                return false
            }
            var nextValues = values
            nextValues.removeValue(forKey: trimmedOldKey)
            nextValues[trimmedNewKey] = value
            parent = .object(nextValues)
            return true
        }
    }

    @discardableResult
    public func removeCustomActionServiceDataKey(_ id: CustomActionID, key: String) -> Bool {
        removeCustomActionServiceDataValue(id, path: [.key(key)])
    }

    private static func removeServiceDataValue(
        at path: [PerchHACustomActionServiceDataPathComponent],
        in serviceData: inout [String: ActionValue]
    ) -> Bool {
        guard let first = path.first,
              case let .key(rawKey) = first
        else {
            return false
        }
        let trimmedKey = rawKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKey.isEmpty else {
            return false
        }
        let remainingPath = Array(path.dropFirst())
        guard !remainingPath.isEmpty else {
            return serviceData.removeValue(forKey: trimmedKey) != nil
        }
        return updateServiceDataValue(at: [.key(trimmedKey)], in: &serviceData) { parent in
            removeActionValue(at: remainingPath, in: &parent)
        }
    }

    private static func removeActionValue(
        at path: [PerchHACustomActionServiceDataPathComponent],
        in parent: inout ActionValue
    ) -> Bool {
        guard let first = path.first else {
            return false
        }
        let remainingPath = Array(path.dropFirst())
        switch (first, parent) {
        case let (.key(rawKey), .object(values)):
            let trimmedKey = rawKey.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedKey.isEmpty else {
                return false
            }
            var nextValues = values
            guard !remainingPath.isEmpty else {
                guard nextValues.removeValue(forKey: trimmedKey) != nil else {
                    return false
                }
                parent = .object(nextValues)
                return true
            }
            guard var child = nextValues[trimmedKey],
                  removeActionValue(at: remainingPath, in: &child)
            else {
                return false
            }
            nextValues[trimmedKey] = child
            parent = .object(nextValues)
            return true
        case let (.index(index), .array(values)):
            guard values.indices.contains(index) else {
                return false
            }
            var nextValues = values
            guard !remainingPath.isEmpty else {
                nextValues.remove(at: index)
                parent = .array(nextValues)
                return true
            }
            guard removeActionValue(at: remainingPath, in: &nextValues[index]) else {
                return false
            }
            parent = .array(nextValues)
            return true
        case (.key, .string),
             (.key, .protectedString),
             (.key, .number),
             (.key, .bool),
             (.key, .array),
             (.key, .null),
             (.index, .string),
             (.index, .protectedString),
             (.index, .number),
             (.index, .bool),
             (.index, .object),
             (.index, .null):
            return false
        }
    }

    private static func appendServiceDataArrayValue(
        _ value: ActionValue,
        at path: [PerchHACustomActionServiceDataPathComponent],
        in serviceData: inout [String: ActionValue]
    ) -> Bool {
        updateServiceDataValue(at: path, in: &serviceData) { parent in
            guard case let .array(values) = parent else {
                return false
            }
            parent = .array(values + [value])
            return true
        }
    }

    private static func moveServiceDataArrayValue(
        at path: [PerchHACustomActionServiceDataPathComponent],
        direction: SelectionMoveDirection,
        in serviceData: inout [String: ActionValue]
    ) -> Bool {
        guard let last = path.last,
              case let .index(index) = last
        else {
            return false
        }
        let parentPath = Array(path.dropLast())
        return updateServiceDataValue(at: parentPath, in: &serviceData) { parent in
            guard case let .array(values) = parent,
                  values.indices.contains(index)
            else {
                return false
            }
            let targetIndex: Int
            switch direction {
            case .up:
                guard index > values.startIndex else {
                    return false
                }
                targetIndex = values.index(before: index)
            case .down:
                guard index < values.index(before: values.endIndex) else {
                    return false
                }
                targetIndex = values.index(after: index)
            }
            var nextValues = values
            nextValues.swapAt(index, targetIndex)
            parent = .array(nextValues)
            return true
        }
    }

    private static func updateServiceDataValue(
        at path: [PerchHACustomActionServiceDataPathComponent],
        in serviceData: inout [String: ActionValue],
        update: (inout ActionValue) -> Bool
    ) -> Bool {
        guard let first = path.first,
              case let .key(rawKey) = first
        else {
            return false
        }
        let trimmedKey = rawKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKey.isEmpty,
              var value = serviceData[trimmedKey]
        else {
            return false
        }
        let remainingPath = Array(path.dropFirst())
        let updated: Bool
        if remainingPath.isEmpty {
            updated = update(&value)
        } else {
            updated = updateActionValue(at: remainingPath, in: &value, update: update)
        }
        guard updated else {
            return false
        }
        serviceData[trimmedKey] = value
        return true
    }

    private static func serviceDataValue(
        at path: [PerchHACustomActionServiceDataPathComponent],
        in serviceData: [String: ActionValue]
    ) -> ActionValue? {
        guard let first = path.first,
              case let .key(rawKey) = first
        else {
            return nil
        }
        let trimmedKey = rawKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard var value = serviceData[trimmedKey] else {
            return nil
        }
        for component in path.dropFirst() {
            switch (component, value) {
            case let (.key(rawKey), .object(values)):
                let trimmedKey = rawKey.trimmingCharacters(in: .whitespacesAndNewlines)
                guard let child = values[trimmedKey] else {
                    return nil
                }
                value = child
            case let (.index(index), .array(values)):
                guard values.indices.contains(index) else {
                    return nil
                }
                value = values[index]
            case (.key, .string),
                 (.key, .protectedString),
                 (.key, .number),
                 (.key, .bool),
                 (.key, .array),
                 (.key, .null),
                 (.index, .string),
                 (.index, .protectedString),
                 (.index, .number),
                 (.index, .bool),
                 (.index, .object),
                 (.index, .null):
                return nil
            }
        }
        return value
    }

    private static func updateActionValue(
        at path: [PerchHACustomActionServiceDataPathComponent],
        in parent: inout ActionValue,
        update: (inout ActionValue) -> Bool
    ) -> Bool {
        guard let first = path.first else {
            return update(&parent)
        }
        let remainingPath = Array(path.dropFirst())
        switch (first, parent) {
        case let (.key(rawKey), .object(values)):
            let trimmedKey = rawKey.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedKey.isEmpty,
                  var child = values[trimmedKey]
            else {
                return false
            }
            let updated = remainingPath.isEmpty
                ? update(&child)
                : updateActionValue(at: remainingPath, in: &child, update: update)
            guard updated else {
                return false
            }
            var nextValues = values
            nextValues[trimmedKey] = child
            parent = .object(nextValues)
            return true
        case let (.index(index), .array(values)):
            guard values.indices.contains(index) else {
                return false
            }
            var nextValues = values
            let updated = remainingPath.isEmpty
                ? update(&nextValues[index])
                : updateActionValue(at: remainingPath, in: &nextValues[index], update: update)
            guard updated else {
                return false
            }
            parent = .array(nextValues)
            return true
        case (.key, .string),
             (.key, .protectedString),
             (.key, .number),
             (.key, .bool),
             (.key, .array),
             (.key, .null),
             (.index, .string),
             (.index, .protectedString),
             (.index, .number),
             (.index, .bool),
             (.index, .object),
             (.index, .null):
            return false
        }
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
            resolvedAction = try action.action.resolvedProtectedValues(using: protectedActionValueStore.load)
        } catch {
            applyControlActionState(
                .failed(entityID: action.entityID, message: String(describing: error)),
                lastUpdateDescription: "Action unavailable for \(action.title)"
            )
            return false
        }
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
            snapshot = PerchHAPanelSnapshot(
                connectionState: .disconnected,
                phase: .firstRun,
                rooms: snapshot.rooms,
                availableRooms: snapshot.availableRooms,
                selectionConfiguration: snapshot.selectionConfiguration,
                menuBarDisplayConfiguration: snapshot.menuBarDisplayConfiguration,
                selectionQuery: snapshot.selectionQuery,
                isSettingsPresented: snapshot.isSettingsPresented,
                connectionForm: snapshot.connectionForm,
                lastUpdateDescription: snapshot.lastUpdateDescription,
                refreshCount: snapshot.refreshCount,
                canRetry: false,
                hasTokenInput: hasToken(in: editableForm),
                selectionPersistenceFailureDescription: snapshot.selectionPersistenceFailureDescription,
                displayPersistenceFailureDescription: snapshot.displayPersistenceFailureDescription,
                serviceMetadataFailureDescription: snapshot.serviceMetadataFailureDescription,
                historyState: snapshot.historyState,
                historyPresentationEntityID: snapshot.historyPresentationEntityID,
                controlActionState: snapshot.controlActionState,
            serviceMetadata: snapshot.serviceMetadata
            )
        case .reconnecting:
            snapshot = PerchHAPanelSnapshot(
                connectionState: .reconnecting(attempt: snapshot.refreshCount),
                phase: .reconnecting(attempt: snapshot.refreshCount),
                rooms: snapshot.rooms,
                availableRooms: snapshot.availableRooms,
                selectionConfiguration: snapshot.selectionConfiguration,
                menuBarDisplayConfiguration: snapshot.menuBarDisplayConfiguration,
                selectionQuery: snapshot.selectionQuery,
                isSettingsPresented: snapshot.isSettingsPresented,
                connectionForm: snapshot.connectionForm,
                lastUpdateDescription: snapshot.lastUpdateDescription,
                refreshCount: snapshot.refreshCount,
                canRetry: lastConnectedForm != nil,
                hasTokenInput: hasToken(in: editableForm),
                selectionPersistenceFailureDescription: snapshot.selectionPersistenceFailureDescription,
                displayPersistenceFailureDescription: snapshot.displayPersistenceFailureDescription,
                serviceMetadataFailureDescription: snapshot.serviceMetadataFailureDescription,
                historyState: snapshot.historyState,
                historyPresentationEntityID: snapshot.historyPresentationEntityID,
                controlActionState: snapshot.controlActionState,
            serviceMetadata: snapshot.serviceMetadata
            )
        case .disconnected, .connected, .failed:
            break
        }
    }

    private func applyHistoryState(_ historyState: PerchHAHistoryPanelState) {
        snapshot = PerchHAPanelSnapshot(
            connectionState: snapshot.connectionState,
            phase: snapshot.phase,
            rooms: snapshot.rooms,
            availableRooms: snapshot.availableRooms,
            selectionConfiguration: snapshot.selectionConfiguration,
            menuBarDisplayConfiguration: snapshot.menuBarDisplayConfiguration,
            selectionQuery: snapshot.selectionQuery,
            isSettingsPresented: snapshot.isSettingsPresented,
            connectionForm: snapshot.connectionForm,
            lastUpdateDescription: snapshot.lastUpdateDescription,
            refreshCount: snapshot.refreshCount,
            canRetry: snapshot.canRetry,
            hasTokenInput: hasToken(in: editableForm),
            selectionPersistenceFailureDescription: snapshot.selectionPersistenceFailureDescription,
            displayPersistenceFailureDescription: snapshot.displayPersistenceFailureDescription,
            serviceMetadataFailureDescription: snapshot.serviceMetadataFailureDescription,
            historyState: historyState,
            historyPresentationEntityID: snapshot.historyPresentationEntityID,
            controlActionState: snapshot.controlActionState,
            serviceMetadata: snapshot.serviceMetadata
        )
    }

    private func applyHistoryPresentationEntityID(_ entityID: EntityID?) {
        snapshot = PerchHAPanelSnapshot(
            connectionState: snapshot.connectionState,
            phase: snapshot.phase,
            rooms: snapshot.rooms,
            availableRooms: snapshot.availableRooms,
            selectionConfiguration: snapshot.selectionConfiguration,
            menuBarDisplayConfiguration: snapshot.menuBarDisplayConfiguration,
            selectionQuery: snapshot.selectionQuery,
            isSettingsPresented: snapshot.isSettingsPresented,
            connectionForm: snapshot.connectionForm,
            lastUpdateDescription: snapshot.lastUpdateDescription,
            refreshCount: snapshot.refreshCount,
            canRetry: snapshot.canRetry,
            hasTokenInput: hasToken(in: editableForm),
            selectionPersistenceFailureDescription: snapshot.selectionPersistenceFailureDescription,
            displayPersistenceFailureDescription: snapshot.displayPersistenceFailureDescription,
            serviceMetadataFailureDescription: snapshot.serviceMetadataFailureDescription,
            historyState: snapshot.historyState,
            historyPresentationEntityID: entityID,
            controlActionState: snapshot.controlActionState,
            serviceMetadata: snapshot.serviceMetadata
        )
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
        snapshot = PerchHAPanelSnapshot(
            connectionState: snapshot.connectionState,
            phase: snapshot.phase,
            rooms: snapshot.rooms,
            availableRooms: snapshot.availableRooms,
            selectionConfiguration: snapshot.selectionConfiguration,
            menuBarDisplayConfiguration: snapshot.menuBarDisplayConfiguration,
            selectionQuery: snapshot.selectionQuery,
            isSettingsPresented: snapshot.isSettingsPresented,
            connectionForm: snapshot.connectionForm,
            lastUpdateDescription: lastUpdateDescription ?? snapshot.lastUpdateDescription,
            refreshCount: snapshot.refreshCount,
            canRetry: snapshot.canRetry,
            hasTokenInput: hasToken(in: editableForm),
            selectionPersistenceFailureDescription: snapshot.selectionPersistenceFailureDescription,
            displayPersistenceFailureDescription: snapshot.displayPersistenceFailureDescription,
            serviceMetadataFailureDescription: snapshot.serviceMetadataFailureDescription,
            historyState: snapshot.historyState,
            historyPresentationEntityID: snapshot.historyPresentationEntityID,
            controlActionState: actionState,
            serviceMetadata: snapshot.serviceMetadata
        )
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

        let visibleRooms = selectedRooms(from: availableRooms, using: snapshot.selectionConfiguration)
        let nextPhase: PerchHAPanelPhase
        switch snapshot.phase {
        case .connectedData, .connectedEmpty:
            nextPhase = visibleRooms.isEmpty ? .connectedEmpty : .connectedData
        case .firstRun, .connecting, .reconnecting, .failed, .failedStale:
            nextPhase = snapshot.phase
        }
        snapshot = PerchHAPanelSnapshot(
            connectionState: snapshot.connectionState,
            phase: nextPhase,
            rooms: visibleRooms,
            availableRooms: availableRooms,
            selectionConfiguration: snapshot.selectionConfiguration,
            menuBarDisplayConfiguration: snapshot.menuBarDisplayConfiguration,
            selectionQuery: snapshot.selectionQuery,
            isSettingsPresented: snapshot.isSettingsPresented,
            connectionForm: snapshot.connectionForm,
            lastUpdateDescription: lastUpdateDescription,
            refreshCount: snapshot.refreshCount,
            canRetry: snapshot.canRetry,
            hasTokenInput: hasToken(in: editableForm),
            selectionPersistenceFailureDescription: snapshot.selectionPersistenceFailureDescription,
            displayPersistenceFailureDescription: snapshot.displayPersistenceFailureDescription,
            serviceMetadataFailureDescription: snapshot.serviceMetadataFailureDescription,
            historyState: snapshot.historyState,
            historyPresentationEntityID: snapshot.historyPresentationEntityID,
            controlActionState: actionState,
            serviceMetadata: snapshot.serviceMetadata
        )
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
        historyCloseTask?.cancel()
        historyCloseTask = nil
        historyRequestGeneration += 1
        pendingControlChange = nil
        historyCache = PerchHAHistoryCache()
        cancelHistoryPrefetch()
        prefetchLastFetched = [:]
        visibleEntityIDs = []
        lastConnectedForm = nil
        oauthSignInState = .idle

        editableForm = PerchHAConnectionForm(
            urlString: editableForm.urlString,
            fallbackURLString: editableForm.fallbackURLString,
            token: "",
            usesStoredAuthSession: false
        )
        snapshot = PerchHAPanelSnapshot(
            connectionState: .disconnected,
            phase: .firstRun,
            rooms: [],
            availableRooms: snapshot.availableRooms,
            selectionConfiguration: snapshot.selectionConfiguration,
            menuBarDisplayConfiguration: snapshot.menuBarDisplayConfiguration,
            selectionQuery: snapshot.selectionQuery,
            isSettingsPresented: snapshot.isSettingsPresented,
            connectionForm: nonSecretForm(editableForm),
            lastUpdateDescription: snapshot.lastUpdateDescription,
            refreshCount: snapshot.refreshCount,
            canRetry: false,
            hasTokenInput: false,
            selectionPersistenceFailureDescription: snapshot.selectionPersistenceFailureDescription,
            displayPersistenceFailureDescription: snapshot.displayPersistenceFailureDescription,
            serviceMetadataFailureDescription: nil,
            historyState: .idle,
            historyPresentationEntityID: nil,
            controlActionState: .idle,
            serviceMetadata: []
        )
        signOutHandler()
    }

    public func connect() async {
        let form = editableForm
        if let failure = form.validationFailure {
            applyFailure(failure, refreshCount: snapshot.refreshCount, canRetry: false)
            return
        }

        snapshot = PerchHAPanelSnapshot(
            connectionState: .connecting,
            phase: .connecting,
            rooms: snapshot.rooms,
            availableRooms: snapshot.availableRooms,
            selectionConfiguration: snapshot.selectionConfiguration,
            menuBarDisplayConfiguration: snapshot.menuBarDisplayConfiguration,
            selectionQuery: snapshot.selectionQuery,
            isSettingsPresented: snapshot.isSettingsPresented,
            connectionForm: nonSecretForm(form),
            lastUpdateDescription: snapshot.lastUpdateDescription,
            refreshCount: snapshot.refreshCount,
            canRetry: false,
            hasTokenInput: hasToken(in: form),
            selectionPersistenceFailureDescription: snapshot.selectionPersistenceFailureDescription,
            displayPersistenceFailureDescription: snapshot.displayPersistenceFailureDescription,
            serviceMetadataFailureDescription: snapshot.serviceMetadataFailureDescription,
            historyState: snapshot.historyState,
            historyPresentationEntityID: snapshot.historyPresentationEntityID,
            controlActionState: snapshot.controlActionState,
            serviceMetadata: snapshot.serviceMetadata
        )
        let result = await connector(form)
        guard !Task.isCancelled else {
            return
        }
        await apply(result: result, form: form, refreshCount: snapshot.refreshCount)
    }

    public func refresh() async {
        guard let form = lastConnectedForm else {
            return
        }

        let nextRefreshCount = snapshot.refreshCount + 1
        snapshot = PerchHAPanelSnapshot(
            connectionState: .reconnecting(attempt: nextRefreshCount),
            phase: .reconnecting(attempt: nextRefreshCount),
            rooms: snapshot.rooms,
            availableRooms: snapshot.availableRooms,
            selectionConfiguration: snapshot.selectionConfiguration,
            menuBarDisplayConfiguration: snapshot.menuBarDisplayConfiguration,
            selectionQuery: snapshot.selectionQuery,
            isSettingsPresented: snapshot.isSettingsPresented,
            connectionForm: snapshot.connectionForm,
            lastUpdateDescription: snapshot.lastUpdateDescription,
            refreshCount: nextRefreshCount,
            canRetry: false,
            hasTokenInput: hasToken(in: form),
            selectionPersistenceFailureDescription: snapshot.selectionPersistenceFailureDescription,
            displayPersistenceFailureDescription: snapshot.displayPersistenceFailureDescription,
            serviceMetadataFailureDescription: snapshot.serviceMetadataFailureDescription,
            historyState: snapshot.historyState,
            historyPresentationEntityID: snapshot.historyPresentationEntityID,
            controlActionState: snapshot.controlActionState,
            serviceMetadata: snapshot.serviceMetadata
        )
        let result = await connector(form)
        guard !Task.isCancelled else {
            return
        }
        await apply(result: result, form: form, refreshCount: nextRefreshCount)
    }

    @discardableResult
    public func applyLiveState(_ state: EntityState) -> Bool {
        var didUpdate = false
        let availableRooms = snapshot.availableRooms.map { room in
            Room(
                id: room.id,
                name: room.name,
                entities: room.entities.map { entity in
                    guard entity.id == state.id else {
                        return entity
                    }
                    didUpdate = true
                    return DiscoveredEntity(
                        id: entity.id,
                        name: state.name == state.id.rawValue ? entity.name : state.name,
                        state: state.state,
                        unit: state.unit,
                        areaID: entity.areaID,
                        deviceID: entity.deviceID,
                        currentPosition: state.currentPosition
                    )
                }
            )
        }
        guard didUpdate else {
            return false
        }

        let visibleRooms = selectedRooms(from: availableRooms, using: snapshot.selectionConfiguration)
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
        snapshot = PerchHAPanelSnapshot(
            connectionState: nextConnectionState,
            phase: nextPhase,
            rooms: visibleRooms,
            availableRooms: availableRooms,
            selectionConfiguration: snapshot.selectionConfiguration,
            menuBarDisplayConfiguration: snapshot.menuBarDisplayConfiguration,
            selectionQuery: snapshot.selectionQuery,
            isSettingsPresented: snapshot.isSettingsPresented,
            connectionForm: snapshot.connectionForm,
            lastUpdateDescription: "Live update received",
            refreshCount: snapshot.refreshCount,
            canRetry: snapshot.canRetry,
            hasTokenInput: hasToken(in: editableForm),
            selectionPersistenceFailureDescription: snapshot.selectionPersistenceFailureDescription,
            displayPersistenceFailureDescription: snapshot.displayPersistenceFailureDescription,
            serviceMetadataFailureDescription: snapshot.serviceMetadataFailureDescription,
            historyState: snapshot.historyState,
            historyPresentationEntityID: snapshot.historyPresentationEntityID,
            controlActionState: snapshot.controlActionState,
            serviceMetadata: snapshot.serviceMetadata
        )
        return true
    }

    private func apply(result: PerchHAConnectionAttemptResult, form: PerchHAConnectionForm, refreshCount: Int) async {
        switch result {
        case let .success(rooms):
            let connectionChanged = lastConnectedForm != form
            if connectionChanged {
                historyTask?.cancel()
                historyTask = nil
                historyCloseTask?.cancel()
                historyCloseTask = nil
                historyRequestGeneration += 1
                historyCache = PerchHAHistoryCache()
                cancelHistoryPrefetch()
                prefetchLastFetched = [:]
                pendingControlChange = nil
            }
            lastConnectedForm = form
            editableForm = form
            let visibleRooms = selectedRooms(from: rooms, using: snapshot.selectionConfiguration)
            snapshot = PerchHAPanelSnapshot(
                connectionState: .connected,
                phase: visibleRooms.isEmpty ? .connectedEmpty : .connectedData,
                rooms: visibleRooms,
                availableRooms: rooms,
                selectionConfiguration: snapshot.selectionConfiguration,
                menuBarDisplayConfiguration: snapshot.menuBarDisplayConfiguration,
                selectionQuery: snapshot.selectionQuery,
                isSettingsPresented: snapshot.isSettingsPresented,
                connectionForm: nonSecretForm(form),
                lastUpdateDescription: refreshCount == 0 ? "Initial load complete" : "Refresh \(refreshCount) complete",
                refreshCount: refreshCount,
                canRetry: true,
                hasTokenInput: hasToken(in: form),
                selectionPersistenceFailureDescription: snapshot.selectionPersistenceFailureDescription,
                displayPersistenceFailureDescription: snapshot.displayPersistenceFailureDescription,
                serviceMetadataFailureDescription: snapshot.serviceMetadataFailureDescription,
                historyState: connectionChanged ? .idle : snapshot.historyState,
                historyPresentationEntityID: connectionChanged ? nil : snapshot.historyPresentationEntityID,
                controlActionState: connectionChanged ? .idle : snapshot.controlActionState,
            serviceMetadata: connectionChanged ? [] : snapshot.serviceMetadata
            )
            await refreshServiceMetadata(form: form)
        case let .failure(failure):
            applyFailure(failure, refreshCount: refreshCount, canRetry: lastConnectedForm != nil)
        }
    }

    private func refreshServiceMetadata(form: PerchHAConnectionForm) async {
        let result = await serviceMetadataProvider(form)
        guard !Task.isCancelled, lastConnectedForm == form else {
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
        snapshot = PerchHAPanelSnapshot(
            connectionState: snapshot.connectionState,
            phase: snapshot.phase,
            rooms: snapshot.rooms,
            availableRooms: snapshot.availableRooms,
            selectionConfiguration: snapshot.selectionConfiguration,
            menuBarDisplayConfiguration: snapshot.menuBarDisplayConfiguration,
            selectionQuery: snapshot.selectionQuery,
            isSettingsPresented: snapshot.isSettingsPresented,
            connectionForm: snapshot.connectionForm,
            lastUpdateDescription: snapshot.lastUpdateDescription,
            refreshCount: snapshot.refreshCount,
            canRetry: snapshot.canRetry,
            hasTokenInput: hasToken(in: editableForm),
            selectionPersistenceFailureDescription: snapshot.selectionPersistenceFailureDescription,
            displayPersistenceFailureDescription: snapshot.displayPersistenceFailureDescription,
            serviceMetadataFailureDescription: failureDescription,
            historyState: snapshot.historyState,
            historyPresentationEntityID: snapshot.historyPresentationEntityID,
            controlActionState: snapshot.controlActionState,
            serviceMetadata: metadata
        )
    }

    private func applyFailure(_ failure: ConnectionFailure, refreshCount: Int, canRetry: Bool) {
        if case .authentication = failure,
           editableForm.usesStoredAuthSession,
           editableForm.trimmedToken.isEmpty
        {
            editableForm.usesStoredAuthSession = false
        }
        let hasLastKnownRows = canRetry && !snapshot.rooms.isEmpty
        snapshot = PerchHAPanelSnapshot(
            connectionState: .failed(failure),
            phase: hasLastKnownRows ? .failedStale(failure) : .failed(failure),
            rooms: snapshot.rooms,
            availableRooms: snapshot.availableRooms,
            selectionConfiguration: snapshot.selectionConfiguration,
            menuBarDisplayConfiguration: snapshot.menuBarDisplayConfiguration,
            selectionQuery: snapshot.selectionQuery,
            isSettingsPresented: snapshot.isSettingsPresented,
            connectionForm: nonSecretForm(editableForm),
            lastUpdateDescription: snapshot.lastUpdateDescription,
            refreshCount: refreshCount,
            canRetry: canRetry,
            hasTokenInput: hasToken(in: editableForm),
            selectionPersistenceFailureDescription: snapshot.selectionPersistenceFailureDescription,
            displayPersistenceFailureDescription: snapshot.displayPersistenceFailureDescription,
            serviceMetadataFailureDescription: snapshot.serviceMetadataFailureDescription,
            historyState: snapshot.historyState,
            historyPresentationEntityID: snapshot.historyPresentationEntityID,
            controlActionState: snapshot.controlActionState,
            serviceMetadata: snapshot.serviceMetadata
        )
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
            fallbackURLString: form.fallbackURLString,
            token: "",
            usesStoredAuthSession: form.usesStoredAuthSession
        )
    }

    private func hasToken(in form: PerchHAConnectionForm) -> Bool {
        !form.trimmedToken.isEmpty || form.usesStoredAuthSession
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
        return Self.serviceDataValue(at: path, in: action.action.serviceData)
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

    private func entity(for id: EntityID) -> DiscoveredEntity? {
        snapshot.availableRooms
            .flatMap(\.entities)
            .first { $0.id == id }
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
                snapshot = PerchHAPanelSnapshot(
                    connectionState: snapshot.connectionState,
                    phase: snapshot.phase,
                    rooms: snapshot.rooms,
                    availableRooms: snapshot.availableRooms,
                    selectionConfiguration: snapshot.selectionConfiguration,
                    menuBarDisplayConfiguration: snapshot.menuBarDisplayConfiguration,
                    selectionQuery: snapshot.selectionQuery,
                    isSettingsPresented: snapshot.isSettingsPresented,
                    connectionForm: snapshot.connectionForm,
                    lastUpdateDescription: snapshot.lastUpdateDescription,
                    refreshCount: snapshot.refreshCount,
                    canRetry: snapshot.canRetry,
                    hasTokenInput: hasToken(in: editableForm),
                    selectionPersistenceFailureDescription: message,
                    displayPersistenceFailureDescription: snapshot.displayPersistenceFailureDescription,
                    serviceMetadataFailureDescription: snapshot.serviceMetadataFailureDescription,
                    historyState: snapshot.historyState,
                    historyPresentationEntityID: snapshot.historyPresentationEntityID,
                    controlActionState: snapshot.controlActionState,
            serviceMetadata: snapshot.serviceMetadata
                )
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

        snapshot = PerchHAPanelSnapshot(
            connectionState: snapshot.connectionState,
            phase: nextPhase,
            rooms: visibleRooms,
            availableRooms: snapshot.availableRooms,
            selectionConfiguration: configuration,
            menuBarDisplayConfiguration: snapshot.menuBarDisplayConfiguration,
            selectionQuery: snapshot.selectionQuery,
            isSettingsPresented: snapshot.isSettingsPresented,
            connectionForm: snapshot.connectionForm,
            lastUpdateDescription: snapshot.lastUpdateDescription,
            refreshCount: snapshot.refreshCount,
            canRetry: snapshot.canRetry,
            hasTokenInput: hasToken(in: editableForm),
            selectionPersistenceFailureDescription: persist ? nil : snapshot.selectionPersistenceFailureDescription,
            displayPersistenceFailureDescription: snapshot.displayPersistenceFailureDescription,
            serviceMetadataFailureDescription: snapshot.serviceMetadataFailureDescription,
            historyState: snapshot.historyState,
            historyPresentationEntityID: snapshot.historyPresentationEntityID,
            controlActionState: snapshot.controlActionState,
            serviceMetadata: snapshot.serviceMetadata
        )
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
                snapshot = PerchHAPanelSnapshot(
                    connectionState: snapshot.connectionState,
                    phase: snapshot.phase,
                    rooms: snapshot.rooms,
                    availableRooms: snapshot.availableRooms,
                    selectionConfiguration: snapshot.selectionConfiguration,
                    menuBarDisplayConfiguration: snapshot.menuBarDisplayConfiguration,
                    selectionQuery: snapshot.selectionQuery,
                    isSettingsPresented: snapshot.isSettingsPresented,
                    connectionForm: snapshot.connectionForm,
                    lastUpdateDescription: snapshot.lastUpdateDescription,
                    refreshCount: snapshot.refreshCount,
                    canRetry: snapshot.canRetry,
                    hasTokenInput: hasToken(in: editableForm),
                    selectionPersistenceFailureDescription: snapshot.selectionPersistenceFailureDescription,
                    displayPersistenceFailureDescription: message,
                    historyState: snapshot.historyState,
                    historyPresentationEntityID: snapshot.historyPresentationEntityID,
                    controlActionState: snapshot.controlActionState,
            serviceMetadata: snapshot.serviceMetadata
                )
                return false
            }
        }

        snapshot = PerchHAPanelSnapshot(
            connectionState: snapshot.connectionState,
            phase: snapshot.phase,
            rooms: snapshot.rooms,
            availableRooms: snapshot.availableRooms,
            selectionConfiguration: snapshot.selectionConfiguration,
            menuBarDisplayConfiguration: configuration,
            selectionQuery: snapshot.selectionQuery,
            isSettingsPresented: snapshot.isSettingsPresented,
            connectionForm: snapshot.connectionForm,
            lastUpdateDescription: snapshot.lastUpdateDescription,
            refreshCount: snapshot.refreshCount,
            canRetry: snapshot.canRetry,
            hasTokenInput: hasToken(in: editableForm),
            selectionPersistenceFailureDescription: snapshot.selectionPersistenceFailureDescription,
            displayPersistenceFailureDescription: persist ? nil : snapshot.displayPersistenceFailureDescription,
            historyState: snapshot.historyState,
            historyPresentationEntityID: snapshot.historyPresentationEntityID,
            controlActionState: snapshot.controlActionState,
            serviceMetadata: snapshot.serviceMetadata
        )
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

public enum SelectionDragItem: Equatable, Sendable {
    case room(RoomID)
    case entity(EntityID)
}

public enum SelectionDropTranslation: Equatable, Sendable {
    case room(source: RoomID, target: RoomID, placement: SelectionDropPlacement)
    case entity(source: EntityID, target: EntityID, placement: SelectionDropPlacement)
    case unsupported
}

enum MenuBarTotalMode: Hashable {
    case none
    case absolute
    case entity(EntityID)
}

private struct SanitizedCustomAction {
    let action: EntityCustomAction
    let protectedValueUpserts: [ProtectedActionValueReference: String]
}

private struct SanitizedActionValue {
    let value: [String: ActionValue]
    let protectedValueUpserts: [ProtectedActionValueReference: String]
}

private struct SanitizedScalarActionValue {
    let value: ActionValue
    let protectedValueUpserts: [ProtectedActionValueReference: String]
}

private enum ProtectedActionValueSnapshot {
    case present(String)
    case missing
}

private struct UnavailableProtectedActionValueStore: ProtectedActionValueStore {
    func save(_ value: String, for reference: ProtectedActionValueReference) throws {
        throw ProtectedActionValueStoreError.unavailable
    }

    func load(_ reference: ProtectedActionValueReference) throws -> String {
        throw ProtectedActionValueStoreError.unavailable
    }

    func delete(_ reference: ProtectedActionValueReference) throws {
        throw ProtectedActionValueStoreError.unavailable
    }
}

private extension EntityCustomAction {
    func withServiceData(_ serviceData: [String: ActionValue]) -> EntityCustomAction {
        EntityCustomAction(
            id: id,
            entityID: entityID,
            title: title,
            action: ActionSpec(
                domain: action.domain,
                service: action.service,
                targetEntityID: action.targetEntityID,
                serviceData: serviceData
            ),
            requiresConfirmation: requiresConfirmation
        )
    }
}

extension ActionValue {
    var editorType: PerchHACustomActionServiceDataValueKind {
        switch self {
        case .number:
            .number
        case .bool:
            .bool
        case .object:
            .object
        case .array:
            .array
        case .string, .protectedString, .null:
            .string
        }
    }

    var editorText: String {
        switch self {
        case let .string(value):
            return value
        case .protectedString:
            return ""
        case let .number(value):
            if value.isFinite,
               value.rounded() == value,
               value >= Double(Int.min),
               value <= Double(Int.max) {
                return String(Int(value))
            }
            return String(value)
        case let .bool(value):
            return value ? "true" : "false"
        case let .object(values):
            return "\(values.count) field\(values.count == 1 ? "" : "s")"
        case let .array(values):
            return "\(values.count) item\(values.count == 1 ? "" : "s")"
        case .null:
            return ""
        }
    }

    var isInlineEditable: Bool {
        switch self {
        case .string, .protectedString, .number, .bool, .null:
            true
        case .object, .array:
            false
        }
    }
}

public struct SelectionDropTranslator: Sendable {
    public init() {}

    public func translate(
        source: SelectionDragItem,
        target: SelectionDragItem,
        tree: [SelectableRoom]
    ) -> SelectionDropTranslation {
        guard source != target else {
            return .unsupported
        }
        switch (source, target) {
        case let (.room(sourceID), .room(targetID)):
            return .room(
                source: sourceID,
                target: targetID,
                placement: dropPlacement(sourceID, targetID: targetID, order: tree.map(\.id))
            )
        case let (.entity(sourceID), .entity(targetID)):
            guard let room = tree.first(where: { room in
                room.entities.contains { $0.entity.id == sourceID }
                    && room.entities.contains { $0.entity.id == targetID }
            }) else {
                return .unsupported
            }
            return .entity(
                source: sourceID,
                target: targetID,
                placement: dropPlacement(sourceID, targetID: targetID, order: room.entities.map(\.entity.id))
            )
        case (.room, .entity), (.entity, .room):
            return .unsupported
        }
    }

    private func dropPlacement<T: Equatable>(_ sourceID: T, targetID: T, order: [T]) -> SelectionDropPlacement {
        guard let sourceIndex = order.firstIndex(of: sourceID),
              let targetIndex = order.firstIndex(of: targetID)
        else {
            return .before
        }
        return sourceIndex < targetIndex ? .after : .before
    }
}

public struct PerchHAHistoryPopoverContent: View {
    private let entityID: EntityID
    private let entityName: String
    private let valueText: String
    private let unit: String?
    private let state: PerchHAHistoryPanelState
    private let increaseContrastOverride: Bool?
    @Binding private var selectedRange: HistoryRange
    @State private var cursorNormalizedX: Double?
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast

    public init(
        entityID: EntityID,
        entityName: String,
        valueText: String,
        unit: String? = nil,
        state: PerchHAHistoryPanelState,
        increaseContrastOverride: Bool? = nil,
        selectedRange: Binding<HistoryRange>
    ) {
        self.entityID = entityID
        self.entityName = entityName
        self.valueText = valueText
        self.unit = unit
        self.state = state
        self.increaseContrastOverride = increaseContrastOverride
        _selectedRange = selectedRange
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(entityName)
                    .font(.headline)
                    .lineLimit(1)
                Spacer()
                Text(valueText)
                    .monospacedDigit()
                    .foregroundStyle(historyValueForegroundStyle)
            }
            Picker("Range", selection: $selectedRange) {
                ForEach(HistoryRange.allCases, id: \.rawValue) { range in
                    Text(range.displayName).tag(range)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .accessibilityLabel("\(entityName) history range")
            historyBody
        }
        .padding(12)
        .frame(width: 280)
    }

    @ViewBuilder
    private var historyBody: some View {
        switch PerchHAHistoryBodyPresentation(state: state, entityID: entityID) {
        case .hidden:
            EmptyView()
        case .loadingSkeleton:
            HistoryLoadingSkeleton()
                .accessibilityLabel("\(entityName) history loading")
        case .empty:
            Text("No history for this range")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityLabel("\(entityName) has no history for this range")
        case .noNumericData:
            Text("No history data")
                .font(.callout)
                .foregroundStyle(.secondary)
                .accessibilityLabel("\(entityName) history has no numeric data")
        case let .stateTimeline(_, segments):
            // Constant height: the state timeline plus its legend occupy a fixed
            // block so hovering the cursor never resizes the popover window.
            PerchHAHistoryStateTimelinePopoverBody(
                segments: segments,
                entityName: entityName,
                labelColor: historyLabelForegroundStyle,
                valueColor: historyValueForegroundStyle
            )
        case let .statistics(series, statistics):
            // Keep a constant height: always show the chart and stats, and float
            // the cursor readout as an overlay on the chart. Swapping the area
            // below the chart would resize the popover window on hover, which
            // aborts inside NSPopover's animated resize.
            VStack(alignment: .leading, spacing: 8) {
                interactiveChart(series: series)
                historyStats(statistics)
            }
        case let .unavailable(message):
            VStack(alignment: .leading, spacing: 4) {
                Label("History unavailable", systemImage: "exclamationmark.triangle")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Move away and hover again to retry.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(entityName) history unavailable: \(message). Hover again to retry.")
        }
    }

    private func interactiveChart(series: HistorySeries) -> some View {
        let chartHeight: CGFloat = 46
        return GeometryReader { proxy in
            ZStack(alignment: .topLeading) {
                HistorySparkline(series: series)
                    .stroke(.primary, style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
                if let normalizedX = cursorNormalizedX {
                    let x = proxy.size.width * CGFloat(min(max(normalizedX, 0), 1))
                    Rectangle()
                        .fill(Color.secondary.opacity(0.6))
                        .frame(width: 1)
                        .frame(maxHeight: .infinity)
                        .offset(x: x)
                    if let readout = cursorReadout(for: series) {
                        Text(readout)
                            .font(.caption2)
                            .monospacedDigit()
                            .foregroundStyle(historyValueForegroundStyle)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 4))
                            .fixedSize()
                            .offset(x: min(max(x - 30, 0), max(proxy.size.width - 60, 0)))
                            .accessibilityHidden(true)
                    }
                }
            }
            .contentShape(Rectangle())
            .onContinuousHover { phase in
                switch phase {
                case let .active(location):
                    let width = proxy.size.width
                    cursorNormalizedX = width > 0 ? Double(location.x / width) : nil
                case .ended:
                    cursorNormalizedX = nil
                }
            }
        }
        .frame(height: chartHeight)
        .accessibilityHidden(true)
    }

    private func cursorReadout(for series: HistorySeries) -> String? {
        guard let normalizedX = cursorNormalizedX,
              let sample = PerchHAHistoryCursor.nearestSample(in: series, atNormalizedX: normalizedX)
        else {
            return nil
        }
        let value = formattedCursorValue(sample.value)
        let time = formattedCursorTimestamp(sample.timestamp, range: series.range)
        return "\(value) · \(time)"
    }

    private func formattedCursorValue(_ value: Double) -> String {
        let number = menuBarNumberLabel(value)
        let trimmedUnit = unit?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmedUnit.isEmpty ? number : "\(number) \(trimmedUnit)"
    }

    private func formattedCursorTimestamp(_ timestamp: Date, range: HistoryRange) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        switch range {
        case .hour, .day:
            formatter.timeStyle = .short
            formatter.dateStyle = .none
        case .week, .month:
            formatter.timeStyle = .none
            formatter.dateStyle = .short
        }
        return formatter.string(from: timestamp)
    }

    private func historyStats(_ statistics: PerchHAHistoryStatistics) -> some View {
        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 4) {
            GridRow {
                statisticLabel("Current")
                statisticValue(menuBarNumberLabel(statistics.current))
            }
            GridRow {
                statisticLabel("Min")
                statisticValue(menuBarNumberLabel(statistics.minimum))
                statisticLabel("Avg")
                statisticValue(menuBarNumberLabel(statistics.average))
                statisticLabel("Max")
                statisticValue(menuBarNumberLabel(statistics.maximum))
            }
        }
        .font(.caption)
    }

    @ViewBuilder
    private func statisticLabel(_ text: String) -> some View {
        Text(text)
            .foregroundStyle(historyLabelForegroundStyle)
    }

    @ViewBuilder
    private func statisticValue(_ text: String) -> some View {
        Text(text)
            .monospacedDigit()
            .foregroundStyle(historyValueForegroundStyle)
    }

    private var historyLabelForegroundStyle: Color {
        if isIncreasedContrast {
            return Color.primary
        }
        return colorScheme == .dark ? Color.white.opacity(0.72) : Color.black.opacity(0.62)
    }

    private var historyValueForegroundStyle: Color {
        if isIncreasedContrast {
            return Color.primary
        }
        return colorScheme == .dark ? Color.white.opacity(0.9) : Color.black.opacity(0.78)
    }

    private var isIncreasedContrast: Bool {
        increaseContrastOverride ?? (colorSchemeContrast == .increased)
    }
}

func menuBarNumberLabel(_ value: Double?) -> String {
    guard let value else {
        return "Off"
    }
    if value.rounded() == value {
        return "\(Int(value))"
    }
    return String(format: "%.1f", value)
}

public struct PerchHAPanelView: View {
    @ObservedObject private var model: PerchHAPanelModel
    private let accessibilityPreferencesOverride: PerchHAAccessibilityPreferences?
    private let onOpenSettings: (() -> Void)?
    @State private var pendingCustomActionID: CustomActionID?
    @State private var panelSearch: String = ""
    @State private var visibleEntityIDs: Set<EntityID> = []
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast

    public init(
        model: PerchHAPanelModel,
        accessibilityPreferencesOverride: PerchHAAccessibilityPreferences? = nil,
        onOpenSettings: (() -> Void)? = nil
    ) {
        self.model = model
        self.accessibilityPreferencesOverride = accessibilityPreferencesOverride
        self.onOpenSettings = onOpenSettings
    }

    private func openSettings() {
        if let onOpenSettings {
            onOpenSettings()
        } else {
            model.toggleSettings()
        }
    }

    public var body: some View {
        let accessibility = Self.rootAccessibilityPresentation(
            snapshot: model.snapshot,
            preferences: accessibilityPreferences
        )
        VStack(alignment: .leading, spacing: 0) {
            topBar
            Divider()
            content
            Divider()
            footer
        }
        .frame(width: 360, height: 420, alignment: .top)
        .background(.regularMaterial)
        .contrast(accessibility.contrastPolicy == .increased ? 1.12 : 1)
        .overlay {
            if accessibility.contrastPolicy == .increased {
                Rectangle()
                    .stroke(Color.primary.opacity(0.32), lineWidth: 1)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(accessibility.label)
        .accessibilityValue(accessibility.value)
        .accessibilityHint(accessibility.hint)
        .transaction { transaction in
            if accessibility.motionPolicy == .reduced {
                transaction.animation = nil
            }
        }
        .confirmationDialog(
            pendingCustomAction.map { "Run \($0.title)?" } ?? "Run action?",
            isPresented: customActionConfirmationBinding,
            titleVisibility: .visible
        ) {
            if let action = pendingCustomAction {
                Button(action.title) {
                    model.startCustomAction(action.id, confirmed: true)
                    pendingCustomActionID = nil
                }
            }
            Button("Cancel", role: .cancel) {
                pendingCustomActionID = nil
            }
        }
    }

    public static func rootAccessibilityPresentation(
        snapshot: PerchHAPanelSnapshot,
        preferences: PerchHAAccessibilityPreferences = PerchHAAccessibilityPreferences()
    ) -> PerchHAPanelRootAccessibilityPresentation {
        PerchHAPanelRootAccessibilityPresentation(
            panel: snapshot.accessibilityPresentation(preferences: preferences)
        )
    }

    private var accessibilityPreferences: PerchHAAccessibilityPreferences {
        if let accessibilityPreferencesOverride {
            return accessibilityPreferencesOverride
        }
        return PerchHAAccessibilityPreferences(
            reduceMotion: accessibilityReduceMotion,
            increaseContrast: colorSchemeContrast == .increased
        )
    }

    private var pendingCustomAction: EntityCustomAction? {
        pendingCustomActionID.flatMap { model.customAction(id: $0) }
    }

    private var customActionConfirmationBinding: Binding<Bool> {
        Binding(
            get: {
                pendingCustomActionID != nil
            },
            set: { isPresented in
                if !isPresented {
                    pendingCustomActionID = nil
                }
            }
        )
    }

    @ViewBuilder
    private var topBar: some View {
        switch model.snapshot.phase {
        case .connectedData, .reconnecting, .failedStale:
            searchBar
        case .firstRun, .connecting, .connectedEmpty, .failed:
            statusBar
        }
    }

    private var searchBar: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(connectionStatusColor)
                .frame(width: 8, height: 8)
                .accessibilityHidden(true)
            PerchHACapsuleField(systemImage: "magnifyingglass") {
                PerchHANativeTextField(
                    placeholder: "Search",
                    text: $panelSearch,
                    contentType: nil,
                    normalizeOnCommit: nil,
                    isBezeled: false
                )
                .frame(height: 18)
            }
            refreshButton
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
    }

    private var statusBar: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(connectionStatusColor)
                .frame(width: 8, height: 8)
                .accessibilityHidden(true)
            Spacer(minLength: 0)
            refreshButton
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    private var refreshButton: some View {
        Button {
            model.startRefresh()
        } label: {
            Image(systemName: "arrow.clockwise")
        }
        .disabled(!model.snapshot.canRefresh)
        .help("Refresh")
        .accessibilityLabel("Refresh")
    }

    private var connectionStatusColor: Color {
        switch model.snapshot.connectionState {
        case .connected:
            return .green
        case .connecting, .reconnecting:
            return .orange
        case .failed:
            return .red
        case .disconnected:
            return Color.secondary
        }
    }

    @ViewBuilder
    private var content: some View {
        switch model.snapshot.phase {
        case .firstRun, .connecting, .failed:
            connectionForm
        case .connectedEmpty:
            connectedEmptyState
        case .connectedData, .reconnecting, .failedStale:
            let rooms = PerchHARoomSearch.filter(model.snapshot.rooms, query: panelSearch)
            ScrollView {
                if rooms.isEmpty {
                    Text("No matching values")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(14)
                        .accessibilityLabel("No matching values")
                } else {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        ForEach(rooms, id: \.id.rawValue) { room in
                            roomSection(room)
                        }
                    }
                    .padding(14)
                }
            }
        }
    }

    private var connectedEmptyState: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "square.dashed")
                .font(.system(size: 34))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            VStack(spacing: 4) {
                Text("No values yet")
                    .font(.headline)
                Text("Pick the rooms and sensors you want to keep an eye on.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Button {
                openSettings()
            } label: {
                Label("Choose values…", systemImage: "slider.horizontal.3")
            }
            .buttonStyle(.borderedProminent)
            .disabled(model.snapshot.availableRooms.isEmpty)
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding(24)
        .accessibilityElement(children: .contain)
    }

    private var connectionForm: some View {
        ScrollView {
            PerchHAConnectionFormFields(model: model)
                .textFieldStyle(.roundedBorder)
                .padding(14)
        }
    }
    private func roomSection(_ room: Room) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) {
                Text(room.name.uppercased())
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .tracking(0.6)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 4)
            PerchHACard(cornerRadius: 12) {
                VStack(spacing: 0) {
                    ForEach(Array(room.entities.enumerated()), id: \.element.id.rawValue) { index, entity in
                        entityRow(entity)
                        if index < room.entities.count - 1 {
                            Divider()
                                .padding(.leading, 46)
                        }
                    }
                }
            }
        }
    }

    private func entityRow(_ entity: DiscoveredEntity) -> some View {
        let value = entityValue(entity)
        let presentation = rowPresentation(for: entity)
        let ringHero = ringGaugeHero(presentation: presentation, available: value.status == .available)
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 10) {
                if let gauge = ringHero {
                    ringGaugeAnchor(gauge: gauge, value: value)
                } else {
                    Image(systemName: entityIconName(for: entity))
                        .font(.system(size: 14))
                        .frame(width: 24, alignment: .center)
                        .foregroundStyle(value.status == .available ? PerchHATheme.accent : Color.secondary)
                        .accessibilityHidden(true)
                }
                VStack(alignment: .leading, spacing: 1) {
                    if ringHero == nil {
                        rowHero(entity: entity, value: value, presentation: presentation)
                    }
                    Text(entity.name)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                if ringHero == nil {
                    rowAccessory(entity: entity, value: value, presentation: presentation)
                }
                if let control = model.snapshot.control(for: entity) {
                    Toggle("", isOn: entityControlBinding(for: entity))
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .tint(PerchHATheme.accent)
                        .controlSize(.small)
                        .disabled(control.isRunning)
                        .help(entityControlHelp(for: entity, control: control))
                        .accessibilityLabel("\(control.isOn ? "Turn off" : "Turn on") \(entity.name)")
                        .accessibilityHint(entityControlHelp(for: entity, control: control))
                }
                if let coverControl = model.snapshot.coverControl(for: entity),
                   model.coverControlMode(for: entity).showsButtons {
                    coverButtons(for: entity, control: coverControl)
                }
                ForEach(model.customActions(for: entity), id: \.id.rawValue) { action in
                    customActionButton(action)
                }
            }
            .font(.body)
            if let coverControl = model.snapshot.coverControl(for: entity),
               model.coverControlMode(for: entity).showsSlider,
               let position = coverControl.position {
                PerchHACoverPositionSlider(
                    position: position,
                    disabled: coverControl.isRunning,
                    accessibilityName: "\(entity.name) position"
                ) { position in
                    model.startCoverPositionChange(entity.id, position: position)
                }
                .frame(width: 132)
                .padding(.leading, 32)
            }
            if let failureMessage = model.snapshot.controlActionState.failureMessage(for: entity.id) {
                Text(failureMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.leading, 32)
                    .accessibilityLabel("\(entity.name) control failed: \(failureMessage)")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .contentShape(Rectangle())
        .onAppear {
            markEntityVisible(entity.id, isVisible: true)
        }
        .onDisappear {
            markEntityVisible(entity.id, isVisible: false)
        }
        .onHover { isInside in
            if isInside {
                model.startHistoryHover(entity.id)
            } else {
                model.cancelHistoryHover()
            }
        }
        .popover(isPresented: historyPopoverBinding(for: entity.id), arrowEdge: .trailing) {
            historyPopover(for: entity)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(entity.name), \(value.text)")
    }

    /// Tracks a row's on-screen visibility and reports the visible set to the
    /// model in display order. Scrolling only mutates local state and hands the
    /// model a settled set; the model's debounce decides whether to fetch, so
    /// scrolling itself never triggers history requests.
    private func markEntityVisible(_ id: EntityID, isVisible: Bool) {
        if isVisible {
            visibleEntityIDs.insert(id)
        } else {
            visibleEntityIDs.remove(id)
        }
        let ordered = model.snapshot.rooms.flatMap(\.entities).map(\.id).filter { visibleEntityIDs.contains($0) }
        model.updateVisibleEntities(ordered)
    }

    private func entityIconName(for entity: DiscoveredEntity) -> String {
        perchHAEntityIconName(for: entity)
    }

    private func entityControlBinding(for entity: DiscoveredEntity) -> Binding<Bool> {
        Binding(
            get: {
                model.snapshot.control(for: entity)?.isOn ?? false
            },
            set: { isOn in
                model.startEntityControlToggle(entity.id, isOn: isOn)
            }
        )
    }

    private func entityControlHelp(for entity: DiscoveredEntity, control: PerchHAEntityControl) -> String {
        if control.isRunning {
            return "Waiting for Home Assistant"
        }
        return control.isOn ? "Turns \(entity.name) off" : "Turns \(entity.name) on"
    }

    private func customActionButton(_ action: EntityCustomAction) -> some View {
        Button {
            if action.requiresConfirmation {
                pendingCustomActionID = action.id
            } else {
                model.startCustomAction(action.id)
            }
        } label: {
            Label(action.title, systemImage: "play.fill")
                .lineLimit(1)
        }
        .controlSize(.small)
        .disabled(model.snapshot.controlActionState.isRunning)
        .help(customActionHelp(action))
        .accessibilityLabel(action.title)
        .accessibilityHint(customActionHelp(action))
    }

    private func customActionHelp(_ action: EntityCustomAction) -> String {
        if model.snapshot.controlActionState.isRunning(for: action.entityID) {
            return "Waiting for Home Assistant"
        }
        return action.requiresConfirmation ? "Asks before running" : "Runs saved Home Assistant service"
    }

    private func coverButtons(for entity: DiscoveredEntity, control: PerchHACoverControl) -> some View {
        HStack(spacing: 4) {
            coverButton(
                icon: "arrow.up.to.line",
                label: "Open \(entity.name)",
                help: coverControlHelp(for: entity, control: control, command: .open),
                disabled: control.isRunning
            ) {
                model.startCoverControl(entity.id, command: .open)
            }
            coverButton(
                icon: "stop.fill",
                label: "Stop \(entity.name)",
                help: coverControlHelp(for: entity, control: control, command: .stop),
                disabled: control.isRunning
            ) {
                model.startCoverControl(entity.id, command: .stop)
            }
            coverButton(
                icon: "arrow.down.to.line",
                label: "Close \(entity.name)",
                help: coverControlHelp(for: entity, control: control, command: .close),
                disabled: control.isRunning
            ) {
                model.startCoverControl(entity.id, command: .close)
            }
        }
    }

    private func coverButton(
        icon: String,
        label: String,
        help: String,
        disabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            PerchHACircularIconLabel(icon: icon, disabled: disabled)
        }
        .buttonStyle(.borderless)
        .disabled(disabled)
        .help(help)
        .accessibilityLabel(label)
        .accessibilityHint(help)
    }

    private func coverControlHelp(
        for entity: DiscoveredEntity,
        control: PerchHACoverControl,
        command: PerchHACoverCommand
    ) -> String {
        if control.isRunning {
            return "Waiting for Home Assistant"
        }
        switch command {
        case .open:
            return "Opens \(entity.name)"
        case .close:
            return "Closes \(entity.name)"
        case .stop:
            return "Stops \(entity.name)"
        case let .setPosition(position):
            return "Sets \(entity.name) to \(position) percent"
        }
    }

    private func historyPopoverBinding(for id: EntityID) -> Binding<Bool> {
        Binding(
            get: {
                model.snapshot.historyPresentationEntityID == id
            },
            set: { isPresented in
                if !isPresented {
                    model.dismissHistoryPopover()
                }
            }
        )
    }

    private func historyRangeBinding(for entity: DiscoveredEntity) -> Binding<HistoryRange> {
        Binding(
            get: {
                model.snapshot.historyState.range
                    ?? model.snapshot.menuBarDisplayConfiguration.itemConfiguration(for: entity.id).defaultHistoryRange
            },
            set: { range in
                model.startHistoryHover(entity.id, range: range)
            }
        )
    }

    private func historyPopover(for entity: DiscoveredEntity) -> some View {
        PerchHAHistoryPopoverContent(
            entityID: entity.id,
            entityName: entity.name,
            valueText: entityValue(entity).text,
            unit: entity.unit,
            state: model.snapshot.historyState,
            selectedRange: historyRangeBinding(for: entity)
        )
        .onHover { isInside in
            if isInside {
                model.keepHistoryHoverAlive()
            } else {
                model.cancelHistoryHover()
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 6) {
            if let problem = model.snapshot.problemDescription {
                Text(problem)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .accessibilityLabel("Status: \(problem)")
            }
            Spacer(minLength: 4)
            Button {
                openSettings()
            } label: {
                Label("Settings", systemImage: "gearshape")
                    .labelStyle(.titleAndIcon)
                    .lineLimit(1)
            }
            .buttonStyle(PerchHAIconButtonStyle())
            .disabled(model.snapshot.availableRooms.isEmpty)
            .help("Settings")
            .accessibilityLabel("Settings")
            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                Label("Quit", systemImage: "power")
                    .labelStyle(.titleAndIcon)
                    .lineLimit(1)
            }
            .buttonStyle(PerchHAIconButtonStyle())
            .help("Quit")
            .accessibilityLabel("Quit")
        }
        .font(.footnote)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
    }

    private func entityValue(_ entity: DiscoveredEntity) -> FormattedEntityValue {
        model.snapshot.formattedValue(for: entity)
    }

    private func rowPresentation(for entity: DiscoveredEntity) -> PerchHAEntityRowPresentation {
        PerchHAEntityRowPresentation.resolve(
            entity: entity,
            configuration: model.snapshot.menuBarDisplayConfiguration.itemConfiguration(for: entity.id),
            availableEntities: model.snapshot.rooms.flatMap(\.entities)
        )
    }

    /// The hero element of a row: a big value, a state pill, or an icon symbol.
    ///
    /// Numeric/gauge and plain-numeric rows show the big monospaced value; the
    /// name lives in the caption line. On/off & open/closed rows show a colored
    /// pill carrying the value text. Icon-unit entities render their dynamic
    /// glyph as the hero.
    @ViewBuilder
    private func rowHero(
        entity: DiscoveredEntity,
        value: FormattedEntityValue,
        presentation: PerchHAEntityRowPresentation
    ) -> some View {
        if let iconSymbolName = value.iconSymbolName {
            Image(systemName: iconSymbolName)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(value.status == .available ? Color.primary : Color.secondary)
                .accessibilityLabel(value.text)
        } else if case let .statePill(isActive) = presentation {
            statePill(text: value.text, isActive: isActive, available: value.status == .available)
        } else {
            Text(value.text)
                .font(.title2)
                .fontWeight(.medium)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .foregroundStyle(value.status == .available ? heroSeverityColor(presentation) : Color.secondary)
                .accessibilityHidden(true)
        }
    }

    private func heroSeverityColor(_ presentation: PerchHAEntityRowPresentation) -> Color {
        switch presentation {
        case let .gauge(gauge):
            gauge.severity == .normal ? Color.primary : PerchHATheme.color(for: gauge.severity)
        case let .value(severity):
            severity == .normal ? Color.primary : PerchHATheme.color(for: severity)
        case .statePill:
            Color.primary
        }
    }

    private func statePill(text: String, isActive: Bool, available: Bool) -> some View {
        let isAccent = isActive && available
        return Text(text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(isAccent ? Color.white : Color.secondary)
            .padding(.horizontal, 9)
            .padding(.vertical, 3)
            .background(
                Capsule(style: .continuous)
                    .fill(isAccent ? PerchHATheme.accent : Color.primary.opacity(0.08))
            )
            .accessibilityHidden(true)
    }

    /// The trailing accessory: a gauge for fraction-resolvable entities, or an
    /// opportunistic inline sparkline drawn only from already-cached history.
    @ViewBuilder
    private func rowAccessory(
        entity: DiscoveredEntity,
        value: FormattedEntityValue,
        presentation: PerchHAEntityRowPresentation
    ) -> some View {
        if case let .gauge(gauge) = presentation, value.status == .available {
            gaugeAccessory(gauge)
        } else if let series = model.cachedHistorySeries(for: entity.id) {
            // OPPORTUNISTIC ONLY: never fetches. Draws only when already cached.
            PerchHAInlineSparkline(series: series, color: PerchHATheme.accent.opacity(0.85))
                .frame(width: 48, height: 16)
        }
    }

    @ViewBuilder
    private func gaugeAccessory(_ gauge: PerchHAEntityGauge) -> some View {
        switch gauge.style {
        case .ring:
            PerchHAEntityGaugeView(gauge: gauge)
                .frame(width: 22, height: 22)
        case .bar:
            PerchHAEntityGaugeView(gauge: gauge)
                .frame(width: 60, height: 10)
        case .battery:
            PerchHAEntityGaugeView(gauge: gauge)
                .frame(width: 36, height: 18)
        }
    }

    /// The ring gauge to draw as the row's leading anchor, or `nil` when the row
    /// is not an available ring-style gauge (bar/battery/value/pill rows keep the
    /// leading icon and a trailing accessory).
    private func ringGaugeHero(presentation: PerchHAEntityRowPresentation, available: Bool) -> PerchHAEntityGauge? {
        guard available, case let .gauge(gauge) = presentation, gauge.style == .ring else {
            return nil
        }
        return gauge
    }

    /// A ~42 pt ring gauge with the hero value centered inside it, used as the
    /// clear visual anchor of a ring-gauge row. The value is the row hero; the
    /// entity name sits in the caption line beside it.
    private func ringGaugeAnchor(gauge: PerchHAEntityGauge, value: FormattedEntityValue) -> some View {
        ZStack {
            PerchHARingGauge(
                fraction: gauge.fraction,
                color: PerchHATheme.color(for: gauge.severity),
                lineWidth: 4
            )
            Text(value.text)
                .font(.system(.callout, design: .rounded).weight(.semibold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .foregroundStyle(gauge.severity == .normal ? Color.primary : PerchHATheme.color(for: gauge.severity))
                .padding(.horizontal, 4)
        }
        .frame(width: 42, height: 42)
        .accessibilityHidden(true)
    }

}

/// Resolves the SF Symbol name representing an entity's domain or measured
/// quantity.
///
/// The choice is derived first from the Home Assistant domain, then falls back
/// to heuristics over the entity name and unit (temperature, humidity, battery,
/// power, air quality, contact/motion) before a neutral gauge default. Shared by
/// the drop-down panel and the Settings entity overview so both present the same
/// leading glyph for a given entity.
///
/// - Parameter entity: The discovered entity to represent.
/// - Returns: A valid SF Symbol name; never empty.
func perchHAEntityIconName(for entity: DiscoveredEntity) -> String {
    let domain = entity.id.domain
    let name = entity.name.lowercased()
    let unit = (entity.unit ?? "").lowercased()
    switch domain {
    case "light":
        return "lightbulb"
    case "switch", "input_boolean":
        return "switch.2"
    case "cover":
        return "window.shade.open"
    case "fan":
        return "fanblades"
    case "lock":
        return "lock"
    case "climate", "water_heater":
        return "thermometer"
    case "media_player":
        return "play.rectangle"
    case "binary_sensor":
        return "dot.radiowaves.left.and.right"
    case "person", "device_tracker":
        return "person"
    default:
        if name.contains("temp") || unit.contains("°") || unit == "k" {
            return "thermometer"
        }
        if name.contains("humid") || unit == "%" {
            return "humidity"
        }
        if name.contains("batt") {
            return "battery.50"
        }
        if name.contains("power") || name.contains("energy") || unit == "w" || unit == "kw" || unit == "wh" || unit == "kwh" {
            return "bolt"
        }
        if name.contains("co2") || name.contains("air") || name.contains("quality") {
            return "aqi.medium"
        }
        if name.contains("door") || name.contains("window") || name.contains("motion") {
            return "sensor"
        }
        return "gauge.medium"
    }
}

extension PerchHAPanelSnapshot {
    var showsConnectedContent: Bool {
        switch phase {
        case .connectedData, .connectedEmpty:
            true
        case .firstRun, .connecting, .reconnecting, .failed, .failedStale:
            false
        }
    }
}

@MainActor
struct PerchHANativeTextField: NSViewRepresentable {
    let placeholder: String
    @Binding var text: String
    let contentType: NSTextContentType?
    let normalizeOnCommit: ((String) -> String)?
    /// When `false`, the field draws no bezel or background, so it can sit inside
    /// a custom capsule container (the panel search field) without the stock
    /// square text-field border. Defaults to `true` for the connection form.
    var isBezeled: Bool = true

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField()
        configure(field)
        field.delegate = context.coordinator
        return field
    }

    func updateNSView(_ nsView: NSTextField, context: Context) {
        context.coordinator.parent = self
        configure(nsView)
        if nsView.stringValue != text {
            nsView.stringValue = text
        }
    }

    private func configure(_ field: NSTextField) {
        field.placeholderString = placeholder
        field.isEditable = true
        field.isSelectable = true
        field.isBezeled = isBezeled
        field.bezelStyle = .roundedBezel
        field.drawsBackground = isBezeled
        field.isBordered = isBezeled
        field.usesSingleLineMode = true
        field.maximumNumberOfLines = 1
        field.lineBreakMode = .byTruncatingTail
        field.focusRingType = isBezeled ? .default : .none
        field.setAccessibilityLabel(placeholder)
        if field.stringValue != text {
            field.stringValue = text
        }
        if #available(macOS 11.0, *) {
            field.contentType = contentType
        }
    }

    @MainActor
    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: PerchHANativeTextField

        init(parent: PerchHANativeTextField) {
            self.parent = parent
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else {
                return
            }
            parent.text = field.stringValue
        }

        func controlTextDidEndEditing(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else {
                return
            }
            commit(field)
        }

        private func commit(_ field: NSTextField) {
            let normalized = parent.normalizeOnCommit?(field.stringValue) ?? field.stringValue
            if field.stringValue != normalized {
                field.stringValue = normalized
            }
            if parent.text != normalized {
                parent.text = normalized
            }
        }
    }
}

@MainActor
struct PerchHANativeSecureField: NSViewRepresentable {
    let placeholder: String
    @Binding var text: String
    let contentType: NSTextContentType?

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> NSSecureTextField {
        let field = NSSecureTextField()
        configure(field)
        field.delegate = context.coordinator
        return field
    }

    func updateNSView(_ nsView: NSSecureTextField, context: Context) {
        context.coordinator.parent = self
        configure(nsView)
        if nsView.stringValue != text {
            nsView.stringValue = text
        }
    }

    private func configure(_ field: NSSecureTextField) {
        field.placeholderString = placeholder
        field.isEditable = true
        field.isSelectable = true
        field.isBezeled = true
        field.bezelStyle = .roundedBezel
        field.drawsBackground = true
        field.usesSingleLineMode = true
        field.maximumNumberOfLines = 1
        field.lineBreakMode = .byTruncatingTail
        field.focusRingType = .default
        field.setAccessibilityLabel(placeholder)
        if field.stringValue != text {
            field.stringValue = text
        }
        if #available(macOS 11.0, *) {
            field.contentType = contentType
        }
    }

    @MainActor
    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: PerchHANativeSecureField

        init(parent: PerchHANativeSecureField) {
            self.parent = parent
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else {
                return
            }
            parent.text = field.stringValue
        }
    }
}

private struct HistorySparkline: Shape {
    let series: HistorySeries

    func path(in rect: CGRect) -> Path {
        let geometry = PerchHAHistorySparklineGeometry(series: series)
        return Path { path in
            for (index, point) in geometry.points.enumerated() {
                let x = rect.minX + rect.width * CGFloat(point.x)
                let y = rect.minY + rect.height * CGFloat(point.y)
                let point = CGPoint(x: x, y: y)
                if index == 0 {
                    path.move(to: point)
                } else {
                    path.addLine(to: point)
                }
            }
        }
    }
}

struct HistoryLoadingSkeletonLayout: Equatable {
    struct StatisticRow: Equatable, Identifiable {
        let id: Int
        let labelWidth: CGFloat
        let valueWidth: CGFloat
    }

    let cornerRadius: CGFloat
    let chartHeight: CGFloat
    let statisticPlaceholderHeight: CGFloat
    let statisticRows: [StatisticRow]

    static let standard = HistoryLoadingSkeletonLayout(
        cornerRadius: 2,
        chartHeight: 46,
        statisticPlaceholderHeight: 8,
        statisticRows: (0..<4).map { row in
            StatisticRow(id: row, labelWidth: 42, valueWidth: 54)
        }
    )
}

private struct PerchHACoverPositionSlider: View {
    let position: Int
    let disabled: Bool
    let accessibilityName: String
    let onCommit: (Int) -> Void

    @State private var draft: Double
    @State private var isEditing = false

    init(position: Int, disabled: Bool, accessibilityName: String, onCommit: @escaping (Int) -> Void) {
        self.position = position
        self.disabled = disabled
        self.accessibilityName = accessibilityName
        self.onCommit = onCommit
        _draft = State(initialValue: Double(position))
    }

    var body: some View {
        Slider(
            value: $draft,
            in: 0...100,
            step: 1,
            onEditingChanged: { editing in
                isEditing = editing
                if !editing {
                    onCommit(Int(draft.rounded()))
                }
            }
        )
        .disabled(disabled)
        .accessibilityLabel(accessibilityName)
        .accessibilityValue("\(Int(draft.rounded())) percent")
        .onChange(of: position) { newPosition in
            if !isEditing {
                draft = Double(newPosition)
            }
        }
    }
}

struct HistoryLoadingSkeleton: View {
    let layout: HistoryLoadingSkeletonLayout

    init(layout: HistoryLoadingSkeletonLayout = .standard) {
        self.layout = layout
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            RoundedRectangle(cornerRadius: layout.cornerRadius)
                .fill(.quaternary)
                .frame(height: layout.chartHeight)
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 4) {
                ForEach(layout.statisticRows) { row in
                    GridRow {
                        RoundedRectangle(cornerRadius: layout.cornerRadius)
                            .fill(.quaternary)
                            .frame(width: row.labelWidth, height: layout.statisticPlaceholderHeight)
                        RoundedRectangle(cornerRadius: layout.cornerRadius)
                            .fill(.quaternary)
                            .frame(width: row.valueWidth, height: layout.statisticPlaceholderHeight)
                    }
                }
            }
        }
        .accessibilityElement(children: .ignore)
    }
}

private extension Double {
    func clamped(to range: ClosedRange<Double>) -> Double {
        min(max(self, range.lowerBound), range.upperBound)
    }
}

extension SelectionDragItem {
    var providerText: String {
        switch self {
        case let .room(id):
            "room:\(id.rawValue)"
        case let .entity(id):
            "entity:\(id.rawValue)"
        }
    }
}

extension MenuBarDisplayStyle {
    var displayName: String {
        switch self {
        case .text:
            "Text"
        case .bar:
            "Bar"
        case .battery:
            "Battery"
        case .ring:
            "Ring"
        }
    }
}

extension ValueThresholdDirection {
    var displayName: String {
        switch self {
        case .aboveOrEqual:
            "High"
        case .belowOrEqual:
            "Low"
        }
    }
}

extension CoverControlMode {
    var displayName: String {
        switch self {
        case .buttons:
            "Buttons"
        case .slider:
            "Slider"
        case .both:
            "Both"
        }
    }
}


extension HistoryRange {
    var displayName: String {
        switch self {
        case .hour:
            "Hour"
        case .day:
            "Day"
        case .week:
            "Week"
        case .month:
            "Month"
        }
    }
}

extension PerchHAPanelModel {
    var tokenInputForView: String {
        editableForm.token
    }
}

public typealias PerchHABootstrapView = PerchHAPanelView

public enum PerchHAUI {
    public static let module = PerchHAModule(
        name: "PerchHAUI",
        responsibility: "SwiftUI and AppKit-facing user interface components."
    )
}
