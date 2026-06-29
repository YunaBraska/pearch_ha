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
    public var allowsSelfSignedCertificates: Bool

    public init(
        urlString: String = "",
        fallbackURLString: String = "",
        token: String = "",
        usesStoredAuthSession: Bool = false,
        allowsSelfSignedCertificates: Bool = false
    ) {
        self.urlString = urlString
        self.fallbackURLString = fallbackURLString
        self.token = token
        self.usesStoredAuthSession = usesStoredAuthSession
        self.allowsSelfSignedCertificates = allowsSelfSignedCertificates
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

    public func selfSignedCertificateHosts() -> Set<String> {
        guard allowsSelfSignedCertificates else {
            return []
        }
        return Set([primaryURL(), fallbackURL()].compactMap(Self.secureHost))
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

    private static func secureHost(_ url: URL?) -> String? {
        guard url?.scheme?.lowercased() == "https",
              let host = url?.host?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
              !host.isEmpty
        else {
            return nil
        }
        return host
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
    case noNumericData
    case statistics(PerchHAHistoryStatistics)

    public init(series: HistorySeries) {
        let samples = series.chronologicalNumericSamples
        let values = samples.map(\.value)
        guard let current = samples.last?.value,
              let minimum = values.min(),
              let maximum = values.max()
        else {
            self = .noNumericData
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
    case noNumericData
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
            case .noNumericData:
                self = .noNumericData
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

private struct PerchHAHistoryNumericSample: Sendable {
    let timestamp: Date
    let value: Double
    let sourceIndex: Int
}

private extension HistorySeries {
    var chronologicalNumericSamples: [PerchHAHistoryNumericSample] {
        samples.enumerated()
            .compactMap { index, sample -> PerchHAHistoryNumericSample? in
                guard let value = sample.numericValue else {
                    return nil
                }
                return PerchHAHistoryNumericSample(
                    timestamp: sample.timestamp,
                    value: value,
                    sourceIndex: index
                )
            }
            .sorted { lhs, rhs in
                if lhs.timestamp == rhs.timestamp {
                    return lhs.sourceIndex < rhs.sourceIndex
                }
                return lhs.timestamp < rhs.timestamp
            }
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
        "PerchHA \(connectionSummary.lowercased()), \(visibleEntityCount) visible values"
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

    public func formattedValue(for entity: DiscoveredEntity, locale: Locale = .current) -> FormattedEntityValue {
        EntityValueFormatter(locale: locale).format(entity, isStale: valuesAreStale)
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
                usesStoredAuthSession: connectionForm.usesStoredAuthSession,
                allowsSelfSignedCertificates: connectionForm.allowsSelfSignedCertificates
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

private struct PerchHAHistoryCacheKey: Hashable {
    let entityID: EntityID
    let range: HistoryRange
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
    private let historyCacheConfiguration: PerchHAHistoryCacheConfiguration
    private let selectionSink: SelectionConfigurationSink
    private let menuBarDisplaySink: MenuBarDisplayConfigurationSink
    private let customActionSink: CustomActionConfigurationSink
    private let protectedActionValueStore: any ProtectedActionValueStore
    private let snapshotSink: SnapshotSink
    private var historyCache = PerchHAHistoryCache()
    private var lastConnectedForm: PerchHAConnectionForm?
    private var editableForm: PerchHAConnectionForm
    private var actionTask: Task<Void, Never>?
    private var controlActionTask: Task<Void, Never>?
    private var pendingControlChange: PendingControlChange?
    private var historyTask: Task<Void, Never>?
    private var historyRequestGeneration = 0
    private var protectedValueDrafts: [String: String] = [:]

    public init(
        snapshot: PerchHAPanelSnapshot = PerchHAPanelSnapshot(),
        connector: @escaping Connector = { _ in .failure(.protocolError("connection client is not configured")) },
        historyProvider: @escaping HistoryProvider = { _, _, _ in .unavailable("history client is not configured") },
        serviceMetadataProvider: @escaping ServiceMetadataProvider = { _ in .success([]) },
        actionRunner: @escaping ActionRunner = { _, _ in .failed("action client is not configured") },
        oauthSignInRunner: @escaping OAuthSignInRunner = { _ in .failed("OAuth sign-in is not configured") },
        clock: any PerchClock = SystemPerchClock(),
        historyDebounce: PerchDuration = .milliseconds(150),
        historyCacheConfiguration: PerchHAHistoryCacheConfiguration = PerchHAHistoryCacheConfiguration(),
        selectionConfiguration: EntitySelectionConfiguration = EntitySelectionConfiguration(),
        menuBarDisplayConfiguration: MenuBarDisplayConfiguration = MenuBarDisplayConfiguration(),
        customActionConfiguration: CustomActionConfiguration = CustomActionConfiguration(),
        selectionSink: @escaping SelectionConfigurationSink = { _ in .saved },
        menuBarDisplaySink: @escaping MenuBarDisplayConfigurationSink = { _ in .saved },
        customActionSink: @escaping CustomActionConfigurationSink = { _ in .saved },
        protectedActionValueStore: (any ProtectedActionValueStore)? = nil,
        snapshotSink: @escaping SnapshotSink = { _ in }
    ) {
        self.snapshotSink = snapshotSink
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
        self.historyCacheConfiguration = historyCacheConfiguration
        self.selectionSink = selectionSink
        self.menuBarDisplaySink = menuBarDisplaySink
        self.customActionSink = customActionSink
        self.protectedActionValueStore = protectedActionValueStore ?? UnavailableProtectedActionValueStore()
    }

    deinit {
        actionTask?.cancel()
        controlActionTask?.cancel()
        historyTask?.cancel()
    }

    public func updateConnectionForm(
        urlString: String? = nil,
        fallbackURLString: String? = nil,
        token: String? = nil,
        usesStoredAuthSession: Bool? = nil,
        allowsSelfSignedCertificates: Bool? = nil
    ) {
        let nextUsesStoredAuthSession = usesStoredAuthSession
            ?? (token?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false ? false : editableForm.usesStoredAuthSession)
        editableForm = PerchHAConnectionForm(
            urlString: urlString ?? editableForm.urlString,
            fallbackURLString: fallbackURLString ?? editableForm.fallbackURLString,
            token: token ?? editableForm.token,
            usesStoredAuthSession: nextUsesStoredAuthSession,
            allowsSelfSignedCertificates: allowsSelfSignedCertificates ?? editableForm.allowsSelfSignedCertificates
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
                usesStoredAuthSession: true,
                allowsSelfSignedCertificates: form.allowsSelfSignedCertificates
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

    public func startHistoryHover(_ id: EntityID, range: HistoryRange? = nil) {
        let resolvedRange = range ?? snapshot.menuBarDisplayConfiguration.itemConfiguration(for: id).defaultHistoryRange
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

    public func cancelHistoryHover() {
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

    public func dismissHistoryPopover() {
        cancelHistoryHover()
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
                historyRequestGeneration += 1
                historyCache = PerchHAHistoryCache()
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
            usesStoredAuthSession: form.usesStoredAuthSession,
            allowsSelfSignedCertificates: form.allowsSelfSignedCertificates
        )
    }

    private func hasToken(in form: PerchHAConnectionForm) -> Bool {
        !form.trimmedToken.isEmpty || form.usesStoredAuthSession
    }

    fileprivate func protectedValueDraft(
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

    fileprivate func isSensitiveServiceDataPath(_ path: [PerchHACustomActionServiceDataPathComponent]) -> Bool {
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

private enum MenuBarTotalMode: Hashable {
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

private extension ActionValue {
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
    private let state: PerchHAHistoryPanelState
    private let increaseContrastOverride: Bool?
    @Binding private var selectedRange: HistoryRange
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast

    public init(
        entityID: EntityID,
        entityName: String,
        valueText: String,
        state: PerchHAHistoryPanelState,
        increaseContrastOverride: Bool? = nil,
        selectedRange: Binding<HistoryRange>
    ) {
        self.entityID = entityID
        self.entityName = entityName
        self.valueText = valueText
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
        case .noNumericData:
            Text("No history data")
                .font(.callout)
                .foregroundStyle(.secondary)
                .accessibilityLabel("\(entityName) history has no numeric data")
        case let .statistics(series, statistics):
            VStack(alignment: .leading, spacing: 8) {
                HistorySparkline(series: series)
                    .stroke(.primary, style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
                    .frame(height: 46)
                    .accessibilityHidden(true)
                historyStats(statistics)
            }
        case let .unavailable(message):
            Text(message)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityLabel("\(entityName) history unavailable: \(message)")
        }
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

fileprivate func menuBarNumberLabel(_ value: Double?) -> String {
    guard let value else {
        return "Off"
    }
    if value.rounded() == value {
        return "\(Int(value))"
    }
    return String(format: "%.1f", value)
}

public struct PerchHAPanelView: View {
    private enum CustomActionEditorLayout {
        static let serviceDataTypePickerWidth: CGFloat = 92
        static let serviceDataValueMinWidth: CGFloat = 144
    }

    @ObservedObject private var model: PerchHAPanelModel
    private let accessibilityPreferencesOverride: PerchHAAccessibilityPreferences?
    @State private var draggedSelectionItem: SelectionDragItem?
    @State private var pendingCustomActionID: CustomActionID?
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast

    public init(
        model: PerchHAPanelModel,
        accessibilityPreferencesOverride: PerchHAAccessibilityPreferences? = nil
    ) {
        self.model = model
        self.accessibilityPreferencesOverride = accessibilityPreferencesOverride
    }

    public var body: some View {
        let accessibility = Self.rootAccessibilityPresentation(
            snapshot: model.snapshot,
            preferences: accessibilityPreferences
        )
        VStack(alignment: .leading, spacing: 0) {
            header
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

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text("PerchHA")
                    .font(.headline)
                Text(model.snapshot.connectionSummary)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                model.startRefresh()
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .disabled(!model.snapshot.canRefresh)
            .help("Refresh")
            .accessibilityLabel("Refresh")
        }
        .padding(14)
    }

    @ViewBuilder
    private var content: some View {
        if model.snapshot.isSettingsPresented {
            settingsView
        } else {
            switch model.snapshot.phase {
            case .firstRun, .connecting, .failed:
                connectionForm
            case .connectedEmpty:
                connectedEmptyState
            case .connectedData, .reconnecting, .failedStale:
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        ForEach(model.snapshot.rooms, id: \.id.rawValue) { room in
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
                model.toggleSettings()
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
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Connect to Home Assistant")
                        .font(.headline)
                    Text("Enter your Home Assistant address, then sign in or paste an access token.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityElement(children: .combine)

                connectionStatusBanner

                VStack(alignment: .leading, spacing: 4) {
                    PerchHANativeTextField(
                        placeholder: "Home Assistant URL",
                        text: urlBinding,
                        contentType: {
                            if #available(macOS 14.0, *) {
                                return .URL
                            }
                            return nil
                        }(),
                        normalizeOnCommit: PerchHAConnectionForm.normalizedHomeAssistantURLString
                    )
                    PerchHANativeTextField(
                        placeholder: "Fallback URL",
                        text: fallbackURLBinding,
                        contentType: {
                            if #available(macOS 14.0, *) {
                                return .URL
                            }
                            return nil
                        }(),
                        normalizeOnCommit: PerchHAConnectionForm.normalizedHomeAssistantURLString
                    )
                    Text("Optional remote or backup address.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Button {
                        model.startOAuthSignIn()
                    } label: {
                        Label(oauthSignInButtonTitle, systemImage: "person.crop.circle")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(isConnectionBusy)
                    .help("Open Home Assistant in your browser to sign in. Recommended.")
                    Text("Opens Home Assistant in your browser to approve access. No password is stored.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                HStack(spacing: 8) {
                    line
                    Text("or use an access token")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize()
                    line
                }

                VStack(alignment: .leading, spacing: 4) {
                    PerchHANativeSecureField(
                        placeholder: "Access token",
                        text: tokenBinding,
                        contentType: .password
                    )
                    Text("Create one in Home Assistant under your profile → Security → Long-lived access tokens.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityLabel("Where to find a token: Home Assistant profile, Security, Long-lived access tokens.")
                    Button("Connect with token") {
                        model.startConnect()
                    }
                    .buttonStyle(.bordered)
                    .disabled(isConnectionBusy)
                }

                DisclosureGroup("Advanced") {
                    VStack(alignment: .leading, spacing: 8) {
                        Toggle(
                            "Allow self-signed certificates for these hosts",
                            isOn: selfSignedCertificateBinding
                        )
                        Text("Only enable this if you connect over HTTPS with your own certificate.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.top, 4)
                }
                .font(.callout)
            }
            .textFieldStyle(.roundedBorder)
            .padding(14)
        }
    }

    @ViewBuilder
    private var connectionStatusBanner: some View {
        if let failureDescription = model.snapshot.failureDescription {
            connectionMessage(
                failureDescription,
                hint: connectionFailureHint(failureDescription),
                accessibilityPrefix: "Connection error"
            )
        }
        if let oauthFailureDescription {
            connectionMessage(
                oauthFailureDescription,
                hint: connectionFailureHint(oauthFailureDescription),
                accessibilityPrefix: "Sign-in error"
            )
        }
        if let connectionProgressMessage {
            HStack(spacing: 6) {
                Image(systemName: "hourglass")
                    .accessibilityHidden(true)
                Text(connectionProgressMessage)
            }
            .font(.callout)
            .foregroundStyle(.secondary)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(connectionProgressMessage)
        }
    }

    private var line: some View {
        Rectangle()
            .fill(Color.secondary.opacity(0.25))
            .frame(height: 1)
            .accessibilityHidden(true)
    }

    @ViewBuilder
    private func connectionMessage(
        _ message: String,
        hint: String?,
        accessibilityPrefix: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(message)
                .font(.callout)
                .foregroundStyle(.red)
                .fixedSize(horizontal: false, vertical: true)
            if let hint {
                Text(hint)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(accessibilityPrefix): \(message)\(hint.map { ". \($0)" } ?? "")")
    }

    private func connectionFailureHint(_ message: String) -> String? {
        let lowered = message.lowercased()
        if lowered.contains("auth") || lowered.contains("token") || lowered.contains("401") {
            return "Check your access token, or use Sign in instead."
        }
        if lowered.contains("unreachable") || lowered.contains("could not") || lowered.contains("connect") || lowered.contains("host") {
            return "Check the Home Assistant address and that this Mac can reach it."
        }
        if lowered.contains("tls") || lowered.contains("certificate") || lowered.contains("ssl") {
            return "If you use a self-signed certificate, enable it under Advanced."
        }
        return nil
    }

    private var oauthFailureDescription: String? {
        if case let .failed(message) = model.oauthSignInState {
            return message
        }
        return nil
    }

    private var oauthSignInButtonTitle: String {
        model.oauthSignInState == .signingIn ? "Signing in..." : "Sign in"
    }

    private var connectionProgressMessage: String? {
        if model.oauthSignInState == .signingIn {
            return "Signing in"
        }
        if model.snapshot.connectionState == .connecting {
            return "Connecting to Home Assistant"
        }
        return nil
    }

    private var isConnectionBusy: Bool {
        model.snapshot.connectionState == .connecting || model.oauthSignInState == .signingIn
    }

    private var settingsView: some View {
        VStack(alignment: .leading, spacing: 10) {
            TextField("Search", text: selectionSearchBinding)
                .textFieldStyle(.roundedBorder)
            if let selectionPersistenceFailure = model.snapshot.selectionPersistenceFailureDescription {
                Text(selectionPersistenceFailure)
                    .font(.callout)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityLabel("Selection settings error: \(selectionPersistenceFailure)")
            }
            if let displayPersistenceFailure = model.snapshot.displayPersistenceFailureDescription {
                Text(displayPersistenceFailure)
                    .font(.callout)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityLabel("Display settings error: \(displayPersistenceFailure)")
            }
            if let serviceMetadataFailure = model.snapshot.serviceMetadataFailureDescription {
                Text(serviceMetadataFailure)
                    .font(.callout)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityLabel("Service metadata error: \(serviceMetadataFailure)")
            }
            if let customActionPersistenceFailure = model.customActionPersistenceFailureDescription {
                Text(customActionPersistenceFailure)
                    .font(.callout)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityLabel("Action settings error: \(customActionPersistenceFailure)")
            }
            if !model.orphanedCustomActions.isEmpty {
                orphanedCustomActionControls
            }
            if model.snapshot.selectionTree.isEmpty {
                Text("No matching values.")
                    .foregroundStyle(.secondary)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        ForEach(Array(settingsTree.enumerated()), id: \.element.id.rawValue) { index, room in
                            selectionRoom(
                                room,
                                canMoveUp: canReorderSelection && index > settingsTree.startIndex,
                                canMoveDown: canReorderSelection && index < settingsTree.index(before: settingsTree.endIndex)
                            )
                        }
                    }
                }
            }
        }
        .padding(14)
    }

    private var orphanedCustomActionControls: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("Unmatched actions")
                .font(.caption)
                .foregroundStyle(.secondary)
            ForEach(model.orphanedCustomActions, id: \.id.rawValue) { action in
                HStack(spacing: 6) {
                    Text("\(action.title) - \(action.entityID.rawValue)")
                        .font(.caption)
                        .lineLimit(1)
                    Spacer()
                    Button {
                        model.removeCustomAction(action.id)
                    } label: {
                        Image(systemName: "trash")
                            .frame(width: 18, height: 18)
                    }
                    .buttonStyle(.borderless)
                    .controlSize(.small)
                    .help("Delete unmatched action")
                    .accessibilityLabel("Delete unmatched action \(action.title)")
                }
            }
        }
    }

    private var settingsTree: [SelectableRoom] {
        model.snapshot.selectionTree
    }

    private var canReorderSelection: Bool {
        model.snapshot.canReorderSelectionWithKeyboard
    }

    private func selectionRoom(_ room: SelectableRoom, canMoveUp: Bool, canMoveDown: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            selectionDragDrop(
                HStack(alignment: .firstTextBaseline) {
                    Text(room.name)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    Spacer()
                    selectionMoveButtons(
                        up: {
                            model.moveRoom(room.id, direction: .up)
                        },
                        down: {
                            model.moveRoom(room.id, direction: .down)
                        },
                        upLabel: "Move \(room.name) up",
                        downLabel: "Move \(room.name) down",
                        canMoveUp: canMoveUp,
                        canMoveDown: canMoveDown
                    )
                },
                item: .room(room.id)
            )
            ForEach(Array(room.entities.enumerated()), id: \.element.entity.id.rawValue) { index, selectable in
                selectionDragDrop(
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(alignment: .firstTextBaseline) {
                            Toggle(
                                selectable.entity.name,
                                isOn: selectionBinding(for: selectable.entity.id)
                            )
                            .toggleStyle(.checkbox)
                            .lineLimit(1)
                            Spacer()
                            selectionMoveButtons(
                                up: {
                                    model.moveEntity(selectable.entity.id, direction: .up)
                                },
                                down: {
                                    model.moveEntity(selectable.entity.id, direction: .down)
                                },
                                upLabel: "Move \(selectable.entity.name) up",
                                downLabel: "Move \(selectable.entity.name) down",
                                canMoveUp: canReorderSelection && index > room.entities.startIndex,
                                canMoveDown: canReorderSelection && index < room.entities.index(before: room.entities.endIndex)
                            )
                        }
                        menuBarControls(for: selectable.entity)
                        customActionControls(for: selectable.entity)
                    },
                    item: .entity(selectable.entity.id)
                )
            }
        }
    }

    private func menuBarControls(for entity: DiscoveredEntity) -> some View {
        let configuration = model.snapshot.menuBarDisplayConfiguration.itemConfiguration(for: entity.id)
        let isPromoted = model.snapshot.menuBarDisplayConfiguration.isPromoted(entity.id)
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Toggle("Menu bar", isOn: menuBarVisibilityBinding(for: entity.id))
                    .toggleStyle(.checkbox)
                    .fixedSize()
                    .accessibilityLabel("Show \(entity.name) in menu bar")
                if isPromoted {
                    menuBarMoveButtons(for: entity)
                    Spacer(minLength: 0)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if isPromoted {
                HStack(spacing: 10) {
                    Text("Style")
                        .foregroundStyle(.secondary)
                    Picker("Style", selection: menuBarStyleBinding(for: entity.id)) {
                        ForEach(MenuBarDisplayStyle.allCases, id: \.rawValue) { style in
                            Text(style.displayName).tag(style)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 110)
                    .accessibilityLabel("\(entity.name) menu bar style")
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                HStack(spacing: 12) {
                    Toggle("Label", isOn: menuBarLabelBinding(for: entity.id))
                        .toggleStyle(.checkbox)
                        .fixedSize()
                        .accessibilityLabel("Show \(entity.name) label in menu bar")
                    Toggle("Unit", isOn: menuBarUnitBinding(for: entity.id))
                        .toggleStyle(.checkbox)
                        .fixedSize()
                        .accessibilityLabel("Show \(entity.name) unit in menu bar")
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                HStack(spacing: 8) {
                    Stepper(
                        "Decimals \(configuration.maximumFractionDigits)",
                        value: menuBarDecimalsBinding(for: entity.id),
                        in: 0...3
                    )
                    .fixedSize()
                    .accessibilityLabel("\(entity.name) decimals")
                    Picker("History", selection: menuBarHistoryRangeBinding(for: entity.id)) {
                        ForEach(HistoryRange.allCases, id: \.rawValue) { range in
                            Text(range.displayName).tag(range)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 86)
                    .accessibilityLabel("\(entity.name) default history range")
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if configuration.style != .text && menuBarCanUseGaugeTotal(for: entity) {
                    menuBarTotalControls(for: entity, configuration: configuration)
                }
                menuBarThresholdControls(for: entity, configuration: configuration)
            }
        }
        .font(.caption)
        .controlSize(.small)
    }

    private func customActionControls(for entity: DiscoveredEntity) -> some View {
        let actions = model.customActions(for: entity)
        return VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Text("Actions")
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    addCustomAction(for: entity)
                } label: {
                    Image(systemName: "plus")
                        .frame(width: 18, height: 18)
                }
                .buttonStyle(.borderless)
                .controlSize(.small)
                .help("Add action")
                .accessibilityLabel("Add action for \(entity.name)")
            }
            ForEach(Array(actions.enumerated()), id: \.element.id.rawValue) { index, action in
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        TextField("Title", text: customActionTitleBinding(for: action.id))
                            .textFieldStyle(.roundedBorder)
                            .accessibilityLabel("\(entity.name) action title")
                        Toggle("Confirm", isOn: customActionConfirmationBinding(for: action.id))
                            .toggleStyle(.checkbox)
                            .accessibilityLabel("\(action.title) confirmation")
                        customActionMoveButtons(
                            for: action,
                            entityName: entity.name,
                            canMoveUp: canReorderSelection && index > actions.startIndex,
                            canMoveDown: canReorderSelection && index < actions.index(before: actions.endIndex)
                        )
                        Button {
                            model.removeCustomAction(action.id)
                        } label: {
                            Image(systemName: "trash")
                                .frame(width: 18, height: 18)
                        }
                        .buttonStyle(.borderless)
                        .controlSize(.small)
                        .help("Delete action")
                        .accessibilityLabel("Delete \(action.title)")
                    }
                    customActionServiceSelector(action)
                    TextField("Target entity", text: customActionTargetBinding(for: action.id))
                        .textFieldStyle(.roundedBorder)
                        .accessibilityLabel("\(action.title) target entity")
                    customActionServiceDataControls(action)
                }
            }
        }
        .font(.caption)
        .controlSize(.small)
    }

    @ViewBuilder
    private func customActionServiceSelector(_ action: EntityCustomAction) -> some View {
        if model.snapshot.serviceMetadata.isEmpty {
            HStack(spacing: 6) {
                TextField("Domain", text: customActionDomainBinding(for: action.id))
                    .textFieldStyle(.roundedBorder)
                    .accessibilityLabel("\(action.title) domain")
                TextField("Service", text: customActionServiceBinding(for: action.id))
                    .textFieldStyle(.roundedBorder)
                    .accessibilityLabel("\(action.title) service")
            }
        } else {
            HStack(spacing: 6) {
                Picker("Domain", selection: customActionMetadataDomainBinding(for: action.id)) {
                    if !metadataDomains.contains(action.action.domain) {
                        Text(action.action.domain).tag(action.action.domain)
                    }
                    ForEach(metadataDomains, id: \.self) { domain in
                        Text(domain).tag(domain)
                    }
                }
                .frame(width: 132)
                .accessibilityLabel("\(action.title) domain")
                Picker("Service", selection: customActionMetadataServiceBinding(for: action.id)) {
                    let services = metadataServices(for: action.action.domain)
                    if !services.contains(where: { $0.service == action.action.service }) {
                        Text(action.action.service).tag(action.action.service)
                    }
                    ForEach(services, id: \.service) { metadata in
                        Text(metadata.service).tag(metadata.service)
                    }
                }
                .frame(width: 132)
                .accessibilityLabel("\(action.title) service")
            }
        }
    }

    private func customActionMoveButtons(
        for action: EntityCustomAction,
        entityName: String,
        canMoveUp: Bool,
        canMoveDown: Bool
    ) -> some View {
        HStack(spacing: 2) {
            Button {
                model.moveCustomAction(action.id, direction: .up)
            } label: {
                Image(systemName: "chevron.up")
                    .frame(width: 18, height: 18)
            }
            .buttonStyle(.borderless)
            .controlSize(.small)
            .disabled(!canMoveUp)
            .help(moveControlHelp(canMove: canMoveUp, boundaryReason: "Already first"))
            .accessibilityLabel("Move \(action.title) earlier for \(entityName)")
            .accessibilityHint(moveControlHelp(canMove: canMoveUp, boundaryReason: "Already first"))

            Button {
                model.moveCustomAction(action.id, direction: .down)
            } label: {
                Image(systemName: "chevron.down")
                    .frame(width: 18, height: 18)
            }
            .buttonStyle(.borderless)
            .controlSize(.small)
            .disabled(!canMoveDown)
            .help(moveControlHelp(canMove: canMoveDown, boundaryReason: "Already last"))
            .accessibilityLabel("Move \(action.title) later for \(entityName)")
            .accessibilityHint(moveControlHelp(canMove: canMoveDown, boundaryReason: "Already last"))
        }
    }

    private func addCustomAction(for entity: DiscoveredEntity) {
        let action = EntityCustomAction(
            id: nextCustomActionID(for: entity.id),
            entityID: entity.id,
            title: "Update",
            action: ActionSpec(domain: "homeassistant", service: "update_entity", targetEntityID: entity.id)
        )
        model.setCustomAction(action)
    }

    private func customActionServiceDataControls(_ action: EntityCustomAction) -> some View {
        let keys = action.action.serviceData.keys.sorted()
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text("Service data")
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    addCustomActionServiceDataValue(action.id)
                } label: {
                    Image(systemName: "plus")
                        .frame(width: 18, height: 18)
                }
                .buttonStyle(.borderless)
                .controlSize(.small)
                .help("Add service data")
                .accessibilityLabel("Add service data for \(action.title)")
            }
            ForEach(keys, id: \.self) { key in
                customActionServiceDataObjectEntry(action, parentPath: [], key: key, nesting: 0)
            }
        }
    }

    private func customActionServiceDataObjectEntry(
        _ action: EntityCustomAction,
        parentPath: [PerchHACustomActionServiceDataPathComponent],
        key: String,
        nesting: Int
    ) -> AnyView {
        let path = parentPath + [.key(key)]
        let value = customActionServiceDataValue(for: action.id, path: path) ?? .null
        return AnyView(
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    TextField("Key", text: customActionServiceDataKeyBinding(for: action.id, parentPath: parentPath, key: key))
                        .textFieldStyle(.roundedBorder)
                        .frame(minWidth: 92, idealWidth: 118)
                        .accessibilityLabel("\(action.title) service data key")
                    customActionServiceDataTypePicker(action, path: path, value: value)
                    customActionServiceDataInlineValueField(action, path: path, value: value)
                    Button {
                        model.removeCustomActionServiceDataValue(action.id, path: path)
                    } label: {
                        Image(systemName: "trash")
                            .frame(width: 18, height: 18)
                    }
                    .buttonStyle(.borderless)
                    .controlSize(.small)
                    .help("Delete service data")
                    .accessibilityLabel("Delete \(key) from \(action.title)")
                }
                .padding(.leading, CGFloat(nesting) * 12)
                customActionNestedServiceDataControls(action, path: path, value: value, nesting: nesting)
            }
        )
    }

    private func customActionServiceDataArrayEntry(
        _ action: EntityCustomAction,
        parentPath: [PerchHACustomActionServiceDataPathComponent],
        index: Int,
        count: Int,
        nesting: Int
    ) -> AnyView {
        let path = parentPath + [.index(index)]
        let value = customActionServiceDataValue(for: action.id, path: path) ?? .null
        return AnyView(
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text("#\(index + 1)")
                        .foregroundStyle(.secondary)
                        .frame(width: 42, alignment: .leading)
                    customActionServiceDataTypePicker(action, path: path, value: value)
                    customActionServiceDataInlineValueField(action, path: path, value: value)
                    Button {
                        model.moveCustomActionServiceDataArrayValue(action.id, path: path, direction: .up)
                    } label: {
                        Image(systemName: "chevron.up")
                            .frame(width: 18, height: 18)
                    }
                    .buttonStyle(.borderless)
                    .controlSize(.small)
                    .disabled(index == 0)
                    .help("Move item up")
                    .accessibilityLabel("Move item \(index + 1) up in \(action.title)")
                    Button {
                        model.moveCustomActionServiceDataArrayValue(action.id, path: path, direction: .down)
                    } label: {
                        Image(systemName: "chevron.down")
                            .frame(width: 18, height: 18)
                    }
                    .buttonStyle(.borderless)
                    .controlSize(.small)
                    .disabled(index >= count - 1)
                    .help("Move item down")
                    .accessibilityLabel("Move item \(index + 1) down in \(action.title)")
                    Button {
                        model.removeCustomActionServiceDataValue(action.id, path: path)
                    } label: {
                        Image(systemName: "trash")
                            .frame(width: 18, height: 18)
                    }
                    .buttonStyle(.borderless)
                    .controlSize(.small)
                    .help("Delete list item")
                    .accessibilityLabel("Delete item \(index + 1) from \(action.title)")
                }
                .padding(.leading, CGFloat(nesting) * 12)
                customActionNestedServiceDataControls(action, path: path, value: value, nesting: nesting)
            }
        )
    }

    private func customActionServiceDataTypePicker(
        _ action: EntityCustomAction,
        path: [PerchHACustomActionServiceDataPathComponent],
        value: ActionValue
    ) -> some View {
        Picker("Type", selection: customActionServiceDataTypeBinding(for: action.id, path: path)) {
            Text("Text").tag(PerchHACustomActionServiceDataValueKind.string)
            Text("Number").tag(PerchHACustomActionServiceDataValueKind.number)
            Text("Bool").tag(PerchHACustomActionServiceDataValueKind.bool)
            Text("Object").tag(PerchHACustomActionServiceDataValueKind.object)
            Text("List").tag(PerchHACustomActionServiceDataValueKind.array)
        }
        .labelsHidden()
        .frame(width: CustomActionEditorLayout.serviceDataTypePickerWidth)
        .disabled(model.isSensitiveServiceDataPath(path))
        .accessibilityLabel("\(action.title) service data type")
    }

    @ViewBuilder
    private func customActionServiceDataInlineValueField(
        _ action: EntityCustomAction,
        path: [PerchHACustomActionServiceDataPathComponent],
        value: ActionValue
    ) -> some View {
        if value.isInlineEditable {
            if model.isSensitiveServiceDataPath(path) {
                SecureField(
                    customActionProtectedValuePlaceholder(for: action.id, path: path),
                    text: customActionProtectedValueBinding(for: action.id, path: path)
                )
                .textFieldStyle(.roundedBorder)
                .frame(minWidth: CustomActionEditorLayout.serviceDataValueMinWidth)
                .layoutPriority(1)
                .accessibilityLabel("\(action.title) protected service data value")
            } else {
                TextField("Value", text: customActionServiceDataValueBinding(for: action.id, path: path))
                    .textFieldStyle(.roundedBorder)
                    .frame(minWidth: CustomActionEditorLayout.serviceDataValueMinWidth)
                    .layoutPriority(1)
                    .accessibilityLabel("\(action.title) service data value")
            }
        } else {
            Text(value.editorText)
                .foregroundStyle(.secondary)
                .frame(minWidth: CustomActionEditorLayout.serviceDataValueMinWidth, maxWidth: .infinity, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityLabel("\(action.title) service data nested value")
        }
    }

    private func customActionNestedServiceDataControls(
        _ action: EntityCustomAction,
        path: [PerchHACustomActionServiceDataPathComponent],
        value: ActionValue,
        nesting: Int
    ) -> AnyView {
        switch value {
        case let .object(values):
            let keys = values.keys.sorted()
            return AnyView(
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(keys, id: \.self) { childKey in
                        customActionServiceDataObjectEntry(action, parentPath: path, key: childKey, nesting: nesting + 1)
                    }
                    Button {
                        addCustomActionObjectServiceDataValue(action.id, parentPath: path)
                    } label: {
                        Label("Add field", systemImage: "plus")
                    }
                    .buttonStyle(.borderless)
                    .controlSize(.small)
                    .padding(.leading, CGFloat(nesting + 1) * 12)
                    .accessibilityLabel("Add nested service data field for \(action.title)")
                }
            )
        case let .array(values):
            return AnyView(
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(values.indices), id: \.self) { index in
                        customActionServiceDataArrayEntry(
                            action,
                            parentPath: path,
                            index: index,
                            count: values.count,
                            nesting: nesting + 1
                        )
                    }
                    Button {
                        model.appendCustomActionServiceDataArrayValue(action.id, path: path, value: .string(""))
                    } label: {
                        Label("Add item", systemImage: "plus")
                    }
                    .buttonStyle(.borderless)
                    .controlSize(.small)
                    .padding(.leading, CGFloat(nesting + 1) * 12)
                    .accessibilityLabel("Add list item for \(action.title)")
                }
            )
        case .string, .protectedString, .number, .bool, .null:
            return AnyView(EmptyView())
        }
    }

    private func addCustomActionServiceDataValue(_ id: CustomActionID) {
        addCustomActionObjectServiceDataValue(id, parentPath: [])
    }

    private func addCustomActionObjectServiceDataValue(
        _ id: CustomActionID,
        parentPath: [PerchHACustomActionServiceDataPathComponent]
    ) {
        guard let action = model.customAction(id: id) else {
            return
        }
        let values: [String: ActionValue]
        if parentPath.isEmpty {
            values = action.action.serviceData
        } else if case let .object(nestedValues) = customActionServiceDataValue(for: id, path: parentPath) {
            values = nestedValues
        } else {
            return
        }
        var index = 1
        var key = "value\(index)"
        while values[key] != nil {
            index += 1
            key = "value\(index)"
        }
        model.setCustomActionServiceDataValue(id, path: parentPath + [.key(key)], value: .string(""))
    }

    private var metadataDomains: [String] {
        Array(Set(model.snapshot.serviceMetadata.map(\.domain))).sorted()
    }

    private func metadataServices(for domain: String) -> [HAServiceMetadata] {
        model.snapshot.serviceMetadata
            .filter { $0.domain == domain }
            .sorted { lhs, rhs in lhs.service < rhs.service }
    }

    private func customActionMetadataDomainBinding(for id: CustomActionID) -> Binding<String> {
        Binding(
            get: {
                model.customAction(id: id)?.action.domain ?? ""
            },
            set: { domain in
                guard let action = model.customAction(id: id) else {
                    return
                }
                let service = metadataServices(for: domain).first?.service ?? action.action.service
                model.setCustomActionService(id, domain: domain, service: service)
            }
        )
    }

    private func customActionMetadataServiceBinding(for id: CustomActionID) -> Binding<String> {
        Binding(
            get: {
                model.customAction(id: id)?.action.service ?? ""
            },
            set: { service in
                guard let action = model.customAction(id: id) else {
                    return
                }
                model.setCustomActionService(id, domain: action.action.domain, service: service)
            }
        )
    }

    private func customActionServiceDataKeyBinding(
        for id: CustomActionID,
        parentPath: [PerchHACustomActionServiceDataPathComponent],
        key: String
    ) -> Binding<String> {
        Binding(
            get: {
                key
            },
            set: { newKey in
                model.renameCustomActionServiceDataKey(id, parentPath: parentPath, from: key, to: newKey)
            }
        )
    }

    private func customActionServiceDataTypeBinding(
        for id: CustomActionID,
        path: [PerchHACustomActionServiceDataPathComponent]
    ) -> Binding<PerchHACustomActionServiceDataValueKind> {
        Binding(
            get: {
                customActionServiceDataValue(for: id, path: path)?.editorType ?? .string
            },
            set: { type in
                model.setCustomActionServiceDataType(id, path: path, kind: type)
            }
        )
    }

    private func customActionServiceDataValueBinding(
        for id: CustomActionID,
        path: [PerchHACustomActionServiceDataPathComponent]
    ) -> Binding<String> {
        Binding(
            get: {
                customActionServiceDataValue(for: id, path: path)?.editorText ?? ""
            },
            set: { text in
                let type = customActionServiceDataValue(for: id, path: path)?.editorType ?? .string
                model.setCustomActionServiceDataText(id, path: path, text: text, kind: type)
            }
        )
    }

    private func customActionProtectedValueBinding(
        for id: CustomActionID,
        path: [PerchHACustomActionServiceDataPathComponent]
    ) -> Binding<String> {
        Binding(
            get: {
                model.protectedValueDraft(for: id, path: path)
            },
            set: { text in
                model.setCustomActionServiceDataText(id, path: path, text: text, kind: .string)
            }
        )
    }

    private func customActionProtectedValuePlaceholder(
        for id: CustomActionID,
        path: [PerchHACustomActionServiceDataPathComponent]
    ) -> String {
        if case .protectedString = customActionServiceDataValue(for: id, path: path) {
            return "Stored in Keychain"
        }
        return "Value"
    }

    private func customActionServiceDataValue(
        for id: CustomActionID,
        path: [PerchHACustomActionServiceDataPathComponent]
    ) -> ActionValue? {
        guard let first = path.first,
              case let .key(rawKey) = first
        else {
            return nil
        }
        let trimmedKey = rawKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard var value = model.customAction(id: id)?.action.serviceData[trimmedKey] else {
            return nil
        }
        for component in path.dropFirst() {
            switch (component, value) {
            case let (.key(key), .object(values)):
                let trimmedKey = key.trimmingCharacters(in: .whitespacesAndNewlines)
                guard let nextValue = values[trimmedKey] else {
                    return nil
                }
                value = nextValue
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

    private func nextCustomActionID(for entityID: EntityID) -> CustomActionID {
        let base = "action-\(entityID.rawValue.replacingOccurrences(of: ".", with: "-"))"
        var index = 1
        var id = CustomActionID("\(base)-\(index)")
        while model.customAction(id: id) != nil {
            index += 1
            id = CustomActionID("\(base)-\(index)")
        }
        return id
    }

    private func customActionTitleBinding(for id: CustomActionID) -> Binding<String> {
        Binding(
            get: {
                model.customAction(id: id)?.title ?? ""
            },
            set: { title in
                updateCustomAction(id) { action in
                    EntityCustomAction(
                        id: action.id,
                        entityID: action.entityID,
                        title: title,
                        action: action.action,
                        requiresConfirmation: action.requiresConfirmation
                    )
                }
            }
        )
    }

    private func customActionDomainBinding(for id: CustomActionID) -> Binding<String> {
        Binding(
            get: {
                model.customAction(id: id)?.action.domain ?? ""
            },
            set: { domain in
                updateCustomAction(id) { action in
                    EntityCustomAction(
                        id: action.id,
                        entityID: action.entityID,
                        title: action.title,
                        action: ActionSpec(
                            domain: domain,
                            service: action.action.service,
                            targetEntityID: action.action.targetEntityID,
                            serviceData: action.action.serviceData
                        ),
                        requiresConfirmation: action.requiresConfirmation
                    )
                }
            }
        )
    }

    private func customActionServiceBinding(for id: CustomActionID) -> Binding<String> {
        Binding(
            get: {
                model.customAction(id: id)?.action.service ?? ""
            },
            set: { service in
                updateCustomAction(id) { action in
                    EntityCustomAction(
                        id: action.id,
                        entityID: action.entityID,
                        title: action.title,
                        action: ActionSpec(
                            domain: action.action.domain,
                            service: service,
                            targetEntityID: action.action.targetEntityID,
                            serviceData: action.action.serviceData
                        ),
                        requiresConfirmation: action.requiresConfirmation
                    )
                }
            }
        )
    }

    private func customActionTargetBinding(for id: CustomActionID) -> Binding<String> {
        Binding(
            get: {
                model.customAction(id: id)?.action.targetEntityID?.rawValue ?? ""
            },
            set: { targetEntityID in
                updateCustomAction(id) { action in
                    let trimmedTarget = targetEntityID.trimmingCharacters(in: .whitespacesAndNewlines)
                    return EntityCustomAction(
                        id: action.id,
                        entityID: action.entityID,
                        title: action.title,
                        action: ActionSpec(
                            domain: action.action.domain,
                            service: action.action.service,
                            targetEntityID: trimmedTarget.isEmpty ? nil : EntityID(trimmedTarget),
                            serviceData: action.action.serviceData
                        ),
                        requiresConfirmation: action.requiresConfirmation
                    )
                }
            }
        )
    }

    private func customActionConfirmationBinding(for id: CustomActionID) -> Binding<Bool> {
        Binding(
            get: {
                model.customAction(id: id)?.requiresConfirmation ?? false
            },
            set: { requiresConfirmation in
                updateCustomAction(id) { action in
                    EntityCustomAction(
                        id: action.id,
                        entityID: action.entityID,
                        title: action.title,
                        action: action.action,
                        requiresConfirmation: requiresConfirmation
                    )
                }
            }
        )
    }

    private func updateCustomAction(
        _ id: CustomActionID,
        transform: (EntityCustomAction) -> EntityCustomAction
    ) {
        guard let action = model.customAction(id: id) else {
            return
        }
        model.setCustomAction(transform(action))
    }

    private func menuBarTotalControls(
        for entity: DiscoveredEntity,
        configuration: MenuBarItemConfiguration
    ) -> some View {
        let candidates = menuBarTotalCandidates(for: entity)
        return HStack(spacing: 8) {
            Picker("Total", selection: menuBarTotalModeBinding(for: entity.id)) {
                Text("No total").tag(MenuBarTotalMode.none)
                Text("Manual").tag(MenuBarTotalMode.absolute)
                if let totalEntityID = configuration.totalEntityID,
                   !candidates.contains(where: { $0.id == totalEntityID }) {
                    Text(totalEntityID.rawValue).tag(MenuBarTotalMode.entity(totalEntityID))
                }
                ForEach(candidates, id: \.id.rawValue) { candidate in
                    Text(candidate.name).tag(MenuBarTotalMode.entity(candidate.id))
                }
            }
            .frame(width: 132)
            .accessibilityLabel("\(entity.name) gauge total source")
            if configuration.absoluteTotal != nil {
                Stepper(
                    "Total \(menuBarNumberLabel(configuration.absoluteTotal))",
                    value: menuBarAbsoluteTotalBinding(for: entity.id),
                    in: 1...100_000,
                    step: 1
                )
                .accessibilityLabel("\(entity.name) manual gauge total")
            }
        }
    }

    private func menuBarThresholdControls(
        for entity: DiscoveredEntity,
        configuration: MenuBarItemConfiguration
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Toggle("Warn", isOn: menuBarWarningEnabledBinding(for: entity.id))
                    .toggleStyle(.checkbox)
                    .accessibilityLabel("\(entity.name) warning threshold")
                if configuration.thresholds.warning != nil {
                    Picker("Warn", selection: menuBarWarningDirectionBinding(for: entity.id)) {
                        Text(ValueThresholdDirection.aboveOrEqual.displayName).tag(ValueThresholdDirection.aboveOrEqual)
                        Text(ValueThresholdDirection.belowOrEqual.displayName).tag(ValueThresholdDirection.belowOrEqual)
                    }
                    .frame(width: 68)
                    .accessibilityLabel("\(entity.name) warning threshold direction")
                    Stepper(
                        "Warn \(menuBarNumberLabel(configuration.thresholds.warning?.value))",
                        value: menuBarWarningValueBinding(for: entity.id),
                        in: -100_000...100_000,
                        step: 1
                    )
                    .accessibilityLabel("\(entity.name) warning threshold value")
                }
            }
            HStack(spacing: 8) {
                Toggle("Crit", isOn: menuBarCriticalEnabledBinding(for: entity.id))
                    .toggleStyle(.checkbox)
                    .accessibilityLabel("\(entity.name) critical threshold")
                if configuration.thresholds.critical != nil {
                    Picker("Crit", selection: menuBarCriticalDirectionBinding(for: entity.id)) {
                        Text(ValueThresholdDirection.aboveOrEqual.displayName).tag(ValueThresholdDirection.aboveOrEqual)
                        Text(ValueThresholdDirection.belowOrEqual.displayName).tag(ValueThresholdDirection.belowOrEqual)
                    }
                    .frame(width: 68)
                    .accessibilityLabel("\(entity.name) critical threshold direction")
                    Stepper(
                        "Crit \(menuBarNumberLabel(configuration.thresholds.critical?.value))",
                        value: menuBarCriticalValueBinding(for: entity.id),
                        in: -100_000...100_000,
                        step: 1
                    )
                    .accessibilityLabel("\(entity.name) critical threshold value")
                }
            }
        }
    }

    private func menuBarMoveButtons(for entity: DiscoveredEntity) -> some View {
        let promotedIDs = model.snapshot.menuBarDisplayConfiguration.promotedEntityIDs
        let index = promotedIDs.firstIndex(of: entity.id)
        let canMoveUp = canReorderSelection && (index.map { $0 > promotedIDs.startIndex } ?? false)
        let canMoveDown = canReorderSelection && (index.map { $0 < promotedIDs.index(before: promotedIDs.endIndex) } ?? false)
        return HStack(spacing: 2) {
            Button {
                model.moveMenuBarEntity(entity.id, direction: .up)
            } label: {
                Image(systemName: "arrow.up.to.line")
                    .frame(width: 18, height: 18)
            }
            .buttonStyle(.borderless)
            .controlSize(.small)
            .disabled(!canMoveUp)
            .help(menuBarMoveHelp(canMove: canMoveUp, boundaryReason: "Already first in menu bar"))
            .accessibilityLabel("Move \(entity.name) earlier in menu bar")
            .accessibilityHint(menuBarMoveHelp(canMove: canMoveUp, boundaryReason: "Already first in menu bar"))

            Button {
                model.moveMenuBarEntity(entity.id, direction: .down)
            } label: {
                Image(systemName: "arrow.down.to.line")
                    .frame(width: 18, height: 18)
            }
            .buttonStyle(.borderless)
            .controlSize(.small)
            .disabled(!canMoveDown)
            .help(menuBarMoveHelp(canMove: canMoveDown, boundaryReason: "Already last in menu bar"))
            .accessibilityLabel("Move \(entity.name) later in menu bar")
            .accessibilityHint(menuBarMoveHelp(canMove: canMoveDown, boundaryReason: "Already last in menu bar"))
        }
    }

    private func menuBarMoveHelp(canMove: Bool, boundaryReason: String) -> String {
        model.snapshot.menuBarReorderAccessibilityHint(canMove: canMove, boundaryReason: boundaryReason)
    }

    @ViewBuilder
    private func selectionDragDrop<Row: View>(_ row: Row, item: SelectionDragItem) -> some View {
        if canReorderSelection {
            row
                .onDrag {
                    selectionDragProvider(item)
                }
                .onDrop(of: [.text], isTargeted: nil) { _ in
                    applySelectionDrop(onto: item)
                }
        } else {
            row
        }
    }

    private func selectionDragProvider(_ item: SelectionDragItem) -> NSItemProvider {
        draggedSelectionItem = item
        return NSItemProvider(object: item.providerText as NSString)
    }

    private func applySelectionDrop(onto target: SelectionDragItem) -> Bool {
        guard canReorderSelection, let draggedSelectionItem, draggedSelectionItem != target else {
            self.draggedSelectionItem = nil
            return false
        }
        defer {
            self.draggedSelectionItem = nil
        }

        switch SelectionDropTranslator().translate(source: draggedSelectionItem, target: target, tree: settingsTree) {
        case let .room(sourceID, targetID, placement):
            return model.moveRoom(sourceID, relativeTo: targetID, placement: placement)
        case let .entity(sourceID, targetID, placement):
            return model.moveEntity(sourceID, relativeTo: targetID, placement: placement)
        case .unsupported:
            return false
        }
    }

    private func selectionMoveButtons(
        up: @escaping () -> Void,
        down: @escaping () -> Void,
        upLabel: String,
        downLabel: String,
        canMoveUp: Bool,
        canMoveDown: Bool
    ) -> some View {
        HStack(spacing: 2) {
            Button(action: up) {
                Image(systemName: "chevron.up")
                    .frame(width: 18, height: 18)
            }
            .buttonStyle(.borderless)
            .controlSize(.small)
            .disabled(!canMoveUp)
            .help(moveControlHelp(canMove: canMoveUp, boundaryReason: "Already first"))
            .accessibilityLabel(upLabel)
            .accessibilityHint(moveControlHelp(canMove: canMoveUp, boundaryReason: "Already first"))

            Button(action: down) {
                Image(systemName: "chevron.down")
                    .frame(width: 18, height: 18)
            }
            .buttonStyle(.borderless)
            .controlSize(.small)
            .disabled(!canMoveDown)
            .help(moveControlHelp(canMove: canMoveDown, boundaryReason: "Already last"))
            .accessibilityLabel(downLabel)
            .accessibilityHint(moveControlHelp(canMove: canMoveDown, boundaryReason: "Already last"))
        }
    }

    private func moveControlHelp(canMove: Bool, boundaryReason: String) -> String {
        model.snapshot.selectionReorderAccessibilityHint(canMove: canMove, boundaryReason: boundaryReason)
    }

    private func roomSection(_ room: Room) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(room.name)
                .font(.subheadline.weight(.semibold))
            ForEach(room.entities, id: \.id.rawValue) { entity in
                VStack(alignment: .leading, spacing: 2) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(entity.name)
                            .lineLimit(1)
                        Spacer()
                        Text(entityValue(entity).text)
                            .monospacedDigit()
                            .lineLimit(1)
                            .foregroundStyle(entityValue(entity).status == .available ? .primary : .secondary)
                        if let control = model.snapshot.control(for: entity) {
                            Toggle("", isOn: entityControlBinding(for: entity))
                                .labelsHidden()
                                .toggleStyle(.switch)
                                .controlSize(.small)
                                .disabled(control.isRunning)
                                .help(entityControlHelp(for: entity, control: control))
                                .accessibilityLabel("\(control.isOn ? "Turn off" : "Turn on") \(entity.name)")
                                .accessibilityHint(entityControlHelp(for: entity, control: control))
                        }
                        if let coverControl = model.snapshot.coverControl(for: entity) {
                            coverButtons(for: entity, control: coverControl)
                        }
                        ForEach(model.customActions(for: entity), id: \.id.rawValue) { action in
                            customActionButton(action)
                        }
                    }
                    .font(.body)
                    if let coverControl = model.snapshot.coverControl(for: entity),
                       let position = coverControl.position {
                        PerchHACoverPositionSlider(
                            position: position,
                            disabled: coverControl.isRunning,
                            accessibilityName: "\(entity.name) position"
                        ) { position in
                            model.startCoverPositionChange(entity.id, position: position)
                        }
                        .frame(width: 132)
                    }
                    if let failureMessage = model.snapshot.controlActionState.failureMessage(for: entity.id) {
                        Text(failureMessage)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityLabel("\(entity.name) control failed: \(failureMessage)")
                    }
                }
                .onHover { isInside in
                    if isInside {
                        model.startHistoryHover(entity.id)
                    } else {
                        model.cancelHistoryHover()
                    }
                }
                .popover(isPresented: historyPopoverBinding(for: entity.id)) {
                    historyPopover(for: entity)
                }
                .accessibilityElement(children: .contain)
                .accessibilityLabel("\(entity.name), \(entityValue(entity).text)")
            }
        }
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
        HStack(spacing: 2) {
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
            Image(systemName: icon)
                .frame(width: 18, height: 18)
        }
        .buttonStyle(.borderless)
        .controlSize(.small)
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
            state: model.snapshot.historyState,
            selectedRange: historyRangeBinding(for: entity)
        )
    }

    private var footer: some View {
        HStack {
            Text(model.snapshot.lastUpdateDescription)
                .foregroundStyle(.secondary)
            Spacer()
            Button(model.snapshot.isSettingsPresented ? "Done" : "Settings") {
                model.toggleSettings()
            }
            .disabled(model.snapshot.availableRooms.isEmpty)
            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
        }
        .font(.footnote)
        .padding(14)
    }

    private func entityValue(_ entity: DiscoveredEntity) -> FormattedEntityValue {
        model.snapshot.formattedValue(for: entity)
    }

    private var urlBinding: Binding<String> {
        Binding(
            get: {
                model.snapshot.showsConnectedContent ? "" : model.snapshot.connectionForm.urlString
            },
            set: { value in
                model.updateConnectionForm(urlString: value)
            }
        )
    }

    private var fallbackURLBinding: Binding<String> {
        Binding(
            get: {
                model.snapshot.showsConnectedContent ? "" : model.snapshot.connectionForm.fallbackURLString
            },
            set: { value in
                model.updateConnectionForm(fallbackURLString: value)
            }
        )
    }

    private var tokenBinding: Binding<String> {
        Binding(
            get: {
                model.snapshot.showsConnectedContent ? "" : model.tokenInputForView
            },
            set: { value in
                model.updateConnectionForm(token: value)
            }
        )
    }

    private var selfSignedCertificateBinding: Binding<Bool> {
        Binding(
            get: {
                model.snapshot.connectionForm.allowsSelfSignedCertificates
            },
            set: { value in
                model.updateConnectionForm(allowsSelfSignedCertificates: value)
            }
        )
    }

    private var selectionSearchBinding: Binding<String> {
        Binding(
            get: {
                model.snapshot.selectionQuery
            },
            set: { value in
                model.updateSelectionQuery(value)
            }
        )
    }

    private func selectionBinding(for id: EntityID) -> Binding<Bool> {
        Binding(
            get: {
                if !model.snapshot.selectionConfiguration.isExplicit {
                    return true
                }
                return model.snapshot.selectionConfiguration.selectedEntityIDs.contains(id)
            },
            set: { isSelected in
                model.setEntity(id, isSelected: isSelected)
            }
        )
    }

    private func menuBarVisibilityBinding(for id: EntityID) -> Binding<Bool> {
        Binding(
            get: {
                model.snapshot.menuBarDisplayConfiguration.isPromoted(id)
            },
            set: { isVisible in
                model.setMenuBarEntity(id, isVisible: isVisible)
            }
        )
    }

    private func menuBarStyleBinding(for id: EntityID) -> Binding<MenuBarDisplayStyle> {
        Binding(
            get: {
                model.snapshot.menuBarDisplayConfiguration.itemConfiguration(for: id).style
            },
            set: { style in
                model.setMenuBarDisplayStyle(id, style: style)
            }
        )
    }

    private func menuBarLabelBinding(for id: EntityID) -> Binding<Bool> {
        Binding(
            get: {
                model.snapshot.menuBarDisplayConfiguration.itemConfiguration(for: id).showsLabel
            },
            set: { showsLabel in
                model.setMenuBarShowsLabel(id, showsLabel: showsLabel)
            }
        )
    }

    private func menuBarUnitBinding(for id: EntityID) -> Binding<Bool> {
        Binding(
            get: {
                model.snapshot.menuBarDisplayConfiguration.itemConfiguration(for: id).showsUnit
            },
            set: { showsUnit in
                model.setMenuBarShowsUnit(id, showsUnit: showsUnit)
            }
        )
    }

    private func menuBarDecimalsBinding(for id: EntityID) -> Binding<Int> {
        Binding(
            get: {
                model.snapshot.menuBarDisplayConfiguration.itemConfiguration(for: id).maximumFractionDigits
            },
            set: { maximumFractionDigits in
                model.setMenuBarMaximumFractionDigits(id, maximumFractionDigits: maximumFractionDigits)
            }
        )
    }

    private func menuBarHistoryRangeBinding(for id: EntityID) -> Binding<HistoryRange> {
        Binding(
            get: {
                model.snapshot.menuBarDisplayConfiguration.itemConfiguration(for: id).defaultHistoryRange
            },
            set: { range in
                model.setMenuBarDefaultHistoryRange(id, defaultHistoryRange: range)
            }
        )
    }

    private func menuBarTotalModeBinding(for id: EntityID) -> Binding<MenuBarTotalMode> {
        Binding(
            get: {
                let configuration = model.snapshot.menuBarDisplayConfiguration.itemConfiguration(for: id)
                if let totalEntityID = configuration.totalEntityID {
                    return .entity(totalEntityID)
                }
                if configuration.absoluteTotal != nil {
                    return .absolute
                }
                return .none
            },
            set: { mode in
                let configuration = model.snapshot.menuBarDisplayConfiguration.itemConfiguration(for: id)
                switch mode {
                case .none:
                    model.setMenuBarTotalEntityID(id, totalEntityID: nil)
                case .absolute:
                    model.setMenuBarAbsoluteTotal(id, total: configuration.absoluteTotal ?? 100)
                case let .entity(totalEntityID):
                    model.setMenuBarTotalEntityID(id, totalEntityID: totalEntityID)
                }
            }
        )
    }

    private func menuBarAbsoluteTotalBinding(for id: EntityID) -> Binding<Double> {
        Binding(
            get: {
                model.snapshot.menuBarDisplayConfiguration.itemConfiguration(for: id).absoluteTotal ?? 100
            },
            set: { total in
                model.setMenuBarAbsoluteTotal(id, total: max(1, total))
            }
        )
    }

    private func menuBarWarningEnabledBinding(for id: EntityID) -> Binding<Bool> {
        Binding(
            get: {
                model.snapshot.menuBarDisplayConfiguration.itemConfiguration(for: id).thresholds.warning != nil
            },
            set: { isEnabled in
                let current = model.snapshot.menuBarDisplayConfiguration.itemConfiguration(for: id).thresholds.warning
                model.setMenuBarWarningThreshold(
                    id,
                    threshold: isEnabled
                        ? ValueThreshold(value: current?.value ?? 80, direction: current?.direction ?? .aboveOrEqual)
                        : nil
                )
            }
        )
    }

    private func menuBarWarningValueBinding(for id: EntityID) -> Binding<Double> {
        Binding(
            get: {
                model.snapshot.menuBarDisplayConfiguration.itemConfiguration(for: id).thresholds.warning?.value ?? 80
            },
            set: { value in
                let current = model.snapshot.menuBarDisplayConfiguration.itemConfiguration(for: id).thresholds.warning
                model.setMenuBarWarningThreshold(
                    id,
                    threshold: ValueThreshold(value: value, direction: current?.direction ?? .aboveOrEqual)
                )
            }
        )
    }

    private func menuBarWarningDirectionBinding(for id: EntityID) -> Binding<ValueThresholdDirection> {
        Binding(
            get: {
                model.snapshot.menuBarDisplayConfiguration.itemConfiguration(for: id).thresholds.warning?.direction
                    ?? .aboveOrEqual
            },
            set: { direction in
                let current = model.snapshot.menuBarDisplayConfiguration.itemConfiguration(for: id).thresholds.warning
                model.setMenuBarWarningThreshold(
                    id,
                    threshold: ValueThreshold(value: current?.value ?? 80, direction: direction)
                )
            }
        )
    }

    private func menuBarCriticalEnabledBinding(for id: EntityID) -> Binding<Bool> {
        Binding(
            get: {
                model.snapshot.menuBarDisplayConfiguration.itemConfiguration(for: id).thresholds.critical != nil
            },
            set: { isEnabled in
                let current = model.snapshot.menuBarDisplayConfiguration.itemConfiguration(for: id).thresholds.critical
                model.setMenuBarCriticalThreshold(
                    id,
                    threshold: isEnabled
                        ? ValueThreshold(value: current?.value ?? 90, direction: current?.direction ?? .aboveOrEqual)
                        : nil
                )
            }
        )
    }

    private func menuBarCriticalValueBinding(for id: EntityID) -> Binding<Double> {
        Binding(
            get: {
                model.snapshot.menuBarDisplayConfiguration.itemConfiguration(for: id).thresholds.critical?.value ?? 90
            },
            set: { value in
                let current = model.snapshot.menuBarDisplayConfiguration.itemConfiguration(for: id).thresholds.critical
                model.setMenuBarCriticalThreshold(
                    id,
                    threshold: ValueThreshold(value: value, direction: current?.direction ?? .aboveOrEqual)
                )
            }
        )
    }

    private func menuBarCriticalDirectionBinding(for id: EntityID) -> Binding<ValueThresholdDirection> {
        Binding(
            get: {
                model.snapshot.menuBarDisplayConfiguration.itemConfiguration(for: id).thresholds.critical?.direction
                    ?? .aboveOrEqual
            },
            set: { direction in
                let current = model.snapshot.menuBarDisplayConfiguration.itemConfiguration(for: id).thresholds.critical
                model.setMenuBarCriticalThreshold(
                    id,
                    threshold: ValueThreshold(value: current?.value ?? 90, direction: direction)
                )
            }
        )
    }

    private func menuBarTotalCandidates(for source: DiscoveredEntity) -> [DiscoveredEntity] {
        model.snapshot.availableRooms
            .flatMap(\.entities)
            .filter { entity in
                entity.id != source.id
                    && menuBarNumericState(entity.state) != nil
                    && menuBarUnitsAreCompatible(source.unit, entity.unit)
            }
    }

    private func menuBarCanUseGaugeTotal(for entity: DiscoveredEntity) -> Bool {
        menuBarNumericState(entity.state) != nil && !menuBarIsPercentUnit(entity.unit)
    }

    private func menuBarNumericState(_ state: String) -> Double? {
        Double(state.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private func menuBarIsPercentUnit(_ unit: String?) -> Bool {
        menuBarNormalizedUnit(unit) == "%"
    }

    private func menuBarUnitsAreCompatible(_ sourceUnit: String?, _ totalUnit: String?) -> Bool {
        menuBarNormalizedUnit(sourceUnit) == menuBarNormalizedUnit(totalUnit)
    }

    private func menuBarNormalizedUnit(_ unit: String?) -> String? {
        let trimmed = unit?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let trimmed, !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }

}

private extension PerchHAPanelSnapshot {
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
private struct PerchHANativeTextField: NSViewRepresentable {
    let placeholder: String
    @Binding var text: String
    let contentType: NSTextContentType?
    let normalizeOnCommit: ((String) -> String)?

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
private struct PerchHANativeSecureField: NSViewRepresentable {
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

private extension SelectionDragItem {
    var providerText: String {
        switch self {
        case let .room(id):
            "room:\(id.rawValue)"
        case let .entity(id):
            "entity:\(id.rawValue)"
        }
    }
}

private extension MenuBarDisplayStyle {
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

private extension ValueThresholdDirection {
    var displayName: String {
        switch self {
        case .aboveOrEqual:
            "High"
        case .belowOrEqual:
            "Low"
        }
    }
}

private extension HistoryRange {
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

private extension PerchHAPanelModel {
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
