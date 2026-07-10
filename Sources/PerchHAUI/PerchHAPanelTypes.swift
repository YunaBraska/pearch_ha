import Foundation
import AppKit
import Combine
import OSLog
import SwiftUI
import UniformTypeIdentifiers
import PerchHACore
import PerchHASupport

/// A single editable Home Assistant address in the connection form.
///
/// Carries an optional display label and a URL string, both edited inline in the
/// Connection settings. Empty labels are allowed; an empty URL marks a blank row
/// that is ignored when building the endpoint.
public struct PerchHAConnectionAddressField: Equatable, Identifiable, Sendable {
    public let id: UUID
    public var label: String
    public var urlString: String

    public init(id: UUID = UUID(), label: String = "", urlString: String = "") {
        self.id = id
        self.label = label
        self.urlString = urlString
    }

    /// Whether both the label and URL are blank.
    public var isBlank: Bool {
        label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && urlString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// The normalized, validated URL for this address, or `nil` when invalid or
    /// blank.
    public var validURL: URL? {
        guard !urlString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        return PerchHAConnectionForm.validURL(urlString)
    }
}

public struct PerchHAConnectionForm: Equatable, Sendable {
    public var urlString: String
    /// Ordered alternative addresses tried after the primary ``urlString``.
    public var addresses: [PerchHAConnectionAddressField]
    public var token: String
    public var usesStoredAuthSession: Bool
    /// Whether the user trusts self-signed TLS certificates for the form's
    /// current HTTPS hosts. On by default — home-lab Home Assistant commonly
    /// runs on a self-issued certificate — but the allowance is always scoped
    /// to exactly the hosts listed in this form, never all hosts, and can be
    /// switched off in Settings for strict validation.
    public var allowsSelfSignedCertificates: Bool

    public init(
        urlString: String = "",
        addresses: [PerchHAConnectionAddressField] = [],
        token: String = "",
        usesStoredAuthSession: Bool = false,
        allowsSelfSignedCertificates: Bool = true
    ) {
        self.urlString = urlString
        self.addresses = addresses
        self.token = token
        self.usesStoredAuthSession = usesStoredAuthSession
        self.allowsSelfSignedCertificates = allowsSelfSignedCertificates
    }

    /// Creates a form from a primary URL and a single fallback URL string.
    ///
    /// Retained for back-compatibility with the primary/fallback shape. An empty
    /// fallback produces no extra address.
    public init(
        urlString: String,
        fallbackURLString: String,
        token: String = "",
        usesStoredAuthSession: Bool = false,
        allowsSelfSignedCertificates: Bool = true
    ) {
        let trimmedFallback = fallbackURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        self.init(
            urlString: urlString,
            addresses: trimmedFallback.isEmpty ? [] : [PerchHAConnectionAddressField(urlString: fallbackURLString)],
            token: token,
            usesStoredAuthSession: usesStoredAuthSession,
            allowsSelfSignedCertificates: allowsSelfSignedCertificates
        )
    }

    public var trimmedToken: String {
        token.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The first alternative URL string, or `""` when none. Back-compat accessor.
    public var fallbackURLString: String {
        addresses.first?.urlString ?? ""
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

    /// The ordered, validated, de-duplicated list of base URLs to try.
    ///
    /// The primary ``urlString`` comes first, followed by each non-blank
    /// alternative address in order. Invalid or blank entries are dropped and
    /// duplicate URLs (by absolute string) are removed, preserving first-seen
    /// order. Returns an empty array when the primary URL is invalid.
    public func urls() -> [URL] {
        guard let primary = primaryURL() else {
            return []
        }
        var seen = Set<String>()
        var ordered: [URL] = []
        for url in [primary] + addresses.compactMap(\.validURL) {
            let key = url.absoluteString
            if seen.insert(key).inserted {
                ordered.append(url)
            }
        }
        return ordered
    }

    /// Whether two forms describe the SAME connection — the ordered resolved URLs,
    /// the token, and the stored-session flag — ignoring volatile UI identity such
    /// as address-row `id`s and cosmetic labels.
    ///
    /// Used to decide whether re-applying a form is a real connection change (which
    /// clears cached history) or the same session rebuilt from the stored profile.
    /// Plain `==` would differ on the per-row `UUID`s, so a rebuilt-but-equivalent
    /// form would wrongly wipe the history cache and leave previews blank.
    public func sameConnection(as other: PerchHAConnectionForm?) -> Bool {
        guard let other else {
            return false
        }
        return urls() == other.urls()
            && trimmedToken == other.trimmedToken
            && usesStoredAuthSession == other.usesStoredAuthSession
            && allowsSelfSignedCertificates == other.allowsSelfSignedCertificates
    }

    /// The lowercased HTTPS hosts a self-signed certificate allowance would be
    /// scoped to, derived from the form's current resolved URLs.
    ///
    /// Plain-HTTP addresses carry no certificate, so they never contribute a
    /// host. Returns an empty set when the form holds no valid HTTPS address.
    ///
    /// - Returns: The unique lowercased HTTPS hosts of ``urls()``.
    public func selfSignedCertificateHosts() -> Set<String> {
        Set(
            urls().compactMap { url in
                guard url.scheme?.lowercased() == "https", let host = url.host, !host.isEmpty else {
                    return nil
                }
                return host.lowercased()
            }
        )
    }

    public var validationFailure: ConnectionFailure? {
        guard primaryURL() != nil else {
            return .protocolError("invalid Home Assistant URL")
        }
        for address in addresses where !address.urlString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            if address.validURL == nil {
                return .protocolError("invalid alternative address")
            }
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

    static func validURL(_ text: String) -> URL? {
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

public struct PerchHAReleaseUpdate: Equatable, Sendable {
    public let currentVersion: String
    public let latestVersion: String
    public let releaseURL: URL
    public let downloadURL: URL

    public init(currentVersion: String, latestVersion: String, releaseURL: URL, downloadURL: URL) {
        self.currentVersion = currentVersion
        self.latestVersion = latestVersion
        self.releaseURL = releaseURL
        self.downloadURL = downloadURL
    }
}

public enum PerchHAReleaseUpdateCheckResult: Equatable, Sendable {
    case upToDate(currentVersion: String, latestVersion: String, releaseURL: URL)
    case updateAvailable(PerchHAReleaseUpdate)
    case failed(String)
}

public enum PerchHAReleaseUpdateState: Equatable, Sendable {
    case idle
    case checking
    case upToDate(currentVersion: String, latestVersion: String, releaseURL: URL)
    case updateAvailable(PerchHAReleaseUpdate)
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
    public let hasTrace: Bool

    /// Builds the sparkline geometry for a series.
    ///
    /// - Parameters:
    ///   - series: The numeric history series.
    ///   - maxSamples: An optional cap on the number of plotted samples. When set
    ///     (used by inline previews, ≈24–96), the series is evenly downsampled to
    ///     this many points so the mini-chart redraw budget stays bounded; the
    ///     first and last samples are always preserved. `nil` plots every sample.
    public init(series: HistorySeries, maxSamples: Int? = nil) {
        self.init(samples: series.chronologicalNumericSamples, maxSamples: maxSamples)
    }

    public init(samples: [PerchHAHistoryCursorSample], maxSamples: Int? = nil) {
        let samples = Self.downsample(samples, to: maxSamples)
        guard samples.count > 1 else {
            points = Self.midline
            hasTrace = false
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
            hasTrace = false
            return
        }

        let timeSpan = lastTime - firstTime
        let valueSpan = maximum - minimum
        let lastIndex = max(samples.count - 1, 1)
        hasTrace = true
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

    /// Evenly downsamples samples to at most `maxSamples`, preserving the first
    /// and last. Returns the input unchanged when no cap is set or the series is
    /// already within budget.
    private static func downsample(
        _ samples: [PerchHAHistoryCursorSample],
        to maxSamples: Int?
    ) -> [PerchHAHistoryCursorSample] {
        guard let maxSamples, maxSamples >= 2, samples.count > maxSamples else {
            return samples
        }
        let lastIndex = samples.count - 1
        var picked: [PerchHAHistoryCursorSample] = []
        picked.reserveCapacity(maxSamples)
        for step in 0..<maxSamples {
            let position = Double(step) / Double(maxSamples - 1)
            let index = Int((position * Double(lastIndex)).rounded())
            let sample = samples[min(index, lastIndex)]
            if picked.last?.timestamp != sample.timestamp {
                picked.append(sample)
            }
        }
        return picked
    }
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

public struct PerchHAPanelEntityContextPresentation: Equatable, Sendable {
    public let isPromotedToMenuBar: Bool
    public let hasAverageLinks: Bool
    public let showsEntityIcon: Bool
    public let showsLabel: Bool
    public let showsUnit: Bool

    public init(
        isPromotedToMenuBar: Bool,
        hasAverageLinks: Bool,
        showsEntityIcon: Bool,
        showsLabel: Bool,
        showsUnit: Bool
    ) {
        self.isPromotedToMenuBar = isPromotedToMenuBar
        self.hasAverageLinks = hasAverageLinks
        self.showsEntityIcon = showsEntityIcon
        self.showsLabel = showsLabel
        self.showsUnit = showsUnit
    }
}

extension HistorySeries {
    var chronologicalNumericSamples: [PerchHAHistoryCursorSample] {
        PerchHAHistoryCursor.numericSamples(of: self)
    }
}

public struct PerchHAHistoryCacheConfiguration: Equatable, Sendable {
    public let capacity: Int
    public let ttl: PerchDuration

    /// - Parameter capacity: The default holds the whole displayed working set —
    ///   the prefetch warms the entire displayed list (unbounded lookahead), so a
    ///   small cache would evict on-screen rows as the back of the list is fetched,
    ///   flickering their previews on and off. 256 comfortably covers a curated
    ///   menu-bar dashboard while staying cheap (downsampled inline series).
    public init(capacity: Int = 256, ttl: PerchDuration = .seconds(60)) {
        self.capacity = max(1, capacity)
        self.ttl = ttl
    }
}

/// Tuning for the active-panel periodic refresh safety net.
///
/// Live WebSocket push already updates values; this gentle periodic refresh only
/// runs while the panel is open and coalesces with any in-flight refresh, so it
/// never spams the request-volume budget. A failed refresh backs off
/// exponentially up to a cap before resuming the base interval.
public struct PerchHAPeriodicRefreshConfiguration: Equatable, Sendable {
    /// The base interval between refreshes while the panel is active.
    public let interval: PerchDuration
    /// The maximum backoff interval applied after consecutive failures.
    public let maximumBackoff: PerchDuration

    /// Creates a periodic refresh configuration.
    ///
    /// - Parameters:
    ///   - interval: The base refresh interval (default 45 s). A zero interval
    ///     disables the periodic safety net entirely (no immediate tick, no loop),
    ///     leaving live WebSocket push as the only update path.
    ///   - maximumBackoff: The backoff ceiling after failures (default 5 min).
    public init(
        interval: PerchDuration = .seconds(45),
        maximumBackoff: PerchDuration = .seconds(300)
    ) {
        self.interval = interval
        self.maximumBackoff = maximumBackoff
    }

    /// Whether the periodic safety net runs. `false` when the interval is zero.
    public var isEnabled: Bool {
        interval.nanoseconds > 0
    }

    /// A configuration that disables the periodic safety net.
    public static let disabled = PerchHAPeriodicRefreshConfiguration(interval: .seconds(0))
}

/// Tuning for the live WebSocket update loop.
///
/// While a session is connected the model holds one live subscription open and
/// applies each pushed state change immediately — this is the primary update
/// path; polling is only the safety net. When the stream drops, the loop
/// reconnects with exponential backoff and resets to the base delay once
/// events flow again.
public struct PerchHALiveUpdateConfiguration: Equatable, Sendable {
    /// The delay before the first reconnect attempt after a dropped stream.
    public let reconnectDelay: PerchDuration
    /// The backoff ceiling for repeated reconnect failures.
    public let maximumBackoff: PerchDuration

    /// Creates a live update configuration.
    ///
    /// - Parameters:
    ///   - reconnectDelay: Base reconnect delay (default 1 s). Zero disables
    ///     the live update loop entirely.
    ///   - maximumBackoff: Backoff ceiling (default 60 s).
    public init(
        reconnectDelay: PerchDuration = .seconds(1),
        maximumBackoff: PerchDuration = .seconds(60)
    ) {
        self.reconnectDelay = reconnectDelay
        self.maximumBackoff = maximumBackoff
    }

    /// Whether the live update loop runs. `false` when the delay is zero.
    public var isEnabled: Bool {
        reconnectDelay.nanoseconds > 0
    }

    /// A configuration that disables live updates.
    public static let disabled = PerchHALiveUpdateConfiguration(reconnectDelay: .seconds(0))
}

/// Tuning for the intelligent bulk history sync loop.
///
/// While the panel is open the model keeps the inline-history cache fresh with a
/// single re-arming background loop: each cycle fetches many entities' history in
/// as few requests as possible (bulk), prioritizing the rows the user is actually
/// looking at. Hot entities (visible or recently inspected) refresh every cycle;
/// cold ones refresh every `coldRefreshDivisor`-th cycle so everything stays
/// covered without inflating request volume. The loop re-arms itself each cycle —
/// that is what keeps the cache from going stale after a single pass.
public struct PerchHAHistoryBulkSyncConfiguration: Equatable, Sendable {
    /// The interval between sync cycles while the panel is active.
    public let interval: PerchDuration
    /// How long visibility must stay unchanged before the first cycle runs, so
    /// scrolling never thrashes the sync.
    public let settleDelay: PerchDuration
    /// Maximum entity IDs requested per bulk batch (mirrors the client cap).
    public let batchSize: Int
    /// Maximum bulk batches dispatched concurrently per cycle.
    public let maxConcurrentBatches: Int
    /// Cold (non-hot) entities are synced every `coldRefreshDivisor`-th cycle. A
    /// value of 1 syncs everything every cycle; larger values keep hot rows
    /// freshest while still covering the whole list periodically.
    public let coldRefreshDivisor: Int

    /// Creates a bulk sync configuration.
    ///
    /// - Parameters:
    ///   - interval: The cycle interval (default 30 s).
    ///   - settleDelay: Quiet period before the first cycle (default 250 ms).
    ///   - batchSize: Entity IDs per bulk request (default 40, clamped to >= 1).
    ///   - maxConcurrentBatches: Concurrent batch cap (default 2, clamped to >= 1).
    ///   - coldRefreshDivisor: Cold-entity refresh cadence (default 4, clamped to >= 1).
    public init(
        interval: PerchDuration = .seconds(30),
        settleDelay: PerchDuration = .milliseconds(250),
        batchSize: Int = 40,
        maxConcurrentBatches: Int = 2,
        coldRefreshDivisor: Int = 4
    ) {
        self.interval = interval
        self.settleDelay = settleDelay
        self.batchSize = max(1, batchSize)
        self.maxConcurrentBatches = max(1, maxConcurrentBatches)
        self.coldRefreshDivisor = max(1, coldRefreshDivisor)
    }

    /// Whether the bulk sync loop runs. `false` when the interval is zero.
    public var isEnabled: Bool {
        interval.nanoseconds > 0
    }

    /// A configuration that disables the bulk sync loop (no cycles run).
    public static let disabled = PerchHAHistoryBulkSyncConfiguration(interval: .seconds(0))
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

    struct Draft {
        var connectionState: ConnectionState
        var phase: PerchHAPanelPhase
        var rooms: [Room]
        var availableRooms: [Room]
        var selectionConfiguration: EntitySelectionConfiguration
        var menuBarDisplayConfiguration: MenuBarDisplayConfiguration
        var selectionQuery: String
        var isSettingsPresented: Bool
        var connectionForm: PerchHAConnectionForm
        var lastUpdateDescription: String
        var refreshCount: Int
        var canRetry: Bool
        var hasTokenInput: Bool
        var selectionPersistenceFailureDescription: String?
        var displayPersistenceFailureDescription: String?
        var serviceMetadataFailureDescription: String?
        var historyState: PerchHAHistoryPanelState
        var historyPresentationEntityID: EntityID?
        var controlActionState: PerchHAControlActionState
        var serviceMetadata: [HAServiceMetadata]

        init(snapshot: PerchHAPanelSnapshot) {
            connectionState = snapshot.connectionState
            phase = snapshot.phase
            rooms = snapshot.rooms
            availableRooms = snapshot.availableRooms
            selectionConfiguration = snapshot.selectionConfiguration
            menuBarDisplayConfiguration = snapshot.menuBarDisplayConfiguration
            selectionQuery = snapshot.selectionQuery
            isSettingsPresented = snapshot.isSettingsPresented
            connectionForm = snapshot.connectionForm
            lastUpdateDescription = snapshot.lastUpdateDescription
            refreshCount = snapshot.refreshCount
            canRetry = snapshot.canRetry
            hasTokenInput = snapshot.hasTokenInput
            selectionPersistenceFailureDescription = snapshot.selectionPersistenceFailureDescription
            displayPersistenceFailureDescription = snapshot.displayPersistenceFailureDescription
            serviceMetadataFailureDescription = snapshot.serviceMetadataFailureDescription
            historyState = snapshot.historyState
            historyPresentationEntityID = snapshot.historyPresentationEntityID
            controlActionState = snapshot.controlActionState
            serviceMetadata = snapshot.serviceMetadata
        }

        func snapshot() -> PerchHAPanelSnapshot {
            PerchHAPanelSnapshot(
                connectionState: connectionState,
                phase: phase,
                rooms: rooms,
                availableRooms: availableRooms,
                selectionConfiguration: selectionConfiguration,
                menuBarDisplayConfiguration: menuBarDisplayConfiguration,
                selectionQuery: selectionQuery,
                isSettingsPresented: isSettingsPresented,
                connectionForm: connectionForm,
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
    }

    func updating(_ update: (inout Draft) -> Void) -> PerchHAPanelSnapshot {
        var draft = Draft(snapshot: self)
        update(&draft)
        return draft.snapshot()
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

    /// Builds the dashboard header's summary strip projection from real data.
    ///
    /// The connection state always yields a status pill. The primary metric is the
    /// first promoted menu-bar entity that resolves to a numeric value, falling
    /// back to the first numeric entity across rooms; entities that present as a
    /// state pill (on/off, open/closed) are skipped so the metric is always a
    /// number. The warning count is the number of visible entities whose value is
    /// unavailable, unknown, or stale — `nil` when there are no visible entities so
    /// the chip is omitted rather than fabricated.
    ///
    /// - Parameters:
    ///   - selectedMetricIDs: The user's ordered summary-strip entity selection.
    ///     When empty (the default), the header keeps its automatic behavior;
    ///     when non-empty, each id is resolved to a ``SelectedMetric`` in order,
    ///     with a muted placeholder for entities that are missing or unreadable.
    ///   - locale: The locale used to format metric values.
    /// - Returns: A pure ``PerchHADashboardSummary`` for the header.
    public func dashboardSummary(
        selectedMetricIDs: [EntityID] = [],
        hiddenModuleIDs: Set<String> = [],
        locale: Locale = .current
    ) -> PerchHADashboardSummary {
        // Alerts and the primary metric must describe what the dashboard
        // actually shows: modules the user hid do not contribute, otherwise
        // the count is dominated by entities the user never sees.
        let visibleRooms = rooms.filter { !hiddenModuleIDs.contains($0.id.rawValue) }
        let countedRooms = visibleRooms.isEmpty ? rooms : visibleRooms
        let allEntities = countedRooms.flatMap(\.entities)
        let primary = resolvePrimaryMetric(allEntities: allEntities, locale: locale)
        let warningCount: Int? = allEntities.isEmpty
            ? nil
            : allEntities.reduce(0) { count, entity in
                switch formattedValue(for: entity, locale: locale).status {
                case .unavailable, .unknown, .stale:
                    count + 1
                case .available:
                    count
                }
            }
        // Explicitly selected metrics resolve against every room: the user
        // picked them by name, hiding their module should not blank them.
        let selectedMetrics = resolveSelectedMetrics(
            selectedMetricIDs: selectedMetricIDs,
            allEntities: rooms.flatMap(\.entities),
            locale: locale
        )
        return PerchHADashboardSummary(
            connectionState: connectionState,
            connectionLabel: connectionSummary,
            primaryMetric: primary,
            warningCount: warningCount,
            selectedMetrics: selectedMetrics
        )
    }

    /// Resolves the user's ordered summary-strip selection into displayable
    /// metrics. Each requested id keeps its slot: a resolvable entity yields its
    /// name and formatted value; a missing entity or one whose value is not
    /// available yields a muted placeholder so the readout never disappears.
    private func resolveSelectedMetrics(
        selectedMetricIDs: [EntityID],
        allEntities: [DiscoveredEntity],
        locale: Locale
    ) -> [PerchHADashboardSummary.SelectedMetric] {
        let capped = PerchHADisplayPreferences.cappedSummaryMetricEntityIDs(selectedMetricIDs)
        return capped.map { id in
            guard let entity = allEntities.first(where: { $0.id == id }) else {
                return PerchHADashboardSummary.SelectedMetric(
                    entityID: id,
                    name: id.rawValue,
                    valueText: "—",
                    isAvailable: false
                )
            }
            let value = formattedValue(for: entity, locale: locale)
            let available = value.status == .available
            return PerchHADashboardSummary.SelectedMetric(
                entityID: id,
                name: entity.name,
                valueText: available ? value.text : "—",
                isAvailable: available
            )
        }
    }

    private func resolvePrimaryMetric(
        allEntities: [DiscoveredEntity],
        locale: Locale
    ) -> PerchHADashboardSummary.PrimaryMetric? {
        let promotedFirst = menuBarDisplayConfiguration.promotedEntityIDs
            .compactMap { id in allEntities.first { $0.id == id } }
        for entity in promotedFirst + allEntities {
            let presentation = PerchHAEntityRowPresentation.resolve(
                entity: entity,
                configuration: effectiveMenuBarItemConfiguration(for: entity),
                availableEntities: allEntities,
                locale: locale
            )
            let value = formattedValue(for: entity, locale: locale)
            let averaged = displayedEntity(for: entity)
            switch presentation {
            case let .gauge(gauge):
                return PerchHADashboardSummary.PrimaryMetric(
                    entityID: entity.id,
                    name: entity.name,
                    valueText: value.text,
                    fraction: gauge.fraction,
                    severity: gauge.severity
                )
            case let .value(severity) where value.status == .available && Double(averaged.state) != nil:
                return PerchHADashboardSummary.PrimaryMetric(
                    entityID: entity.id,
                    name: entity.name,
                    valueText: value.text,
                    fraction: nil,
                    severity: severity
                )
            case .value, .statePill:
                continue
            }
        }
        return nil
    }

    /// The live-effective per-entity display configuration, with legacy saved
    /// fields repaired from the current entity metadata.
    ///
    /// This lets the UI render sensible defaults immediately even when the
    /// persisted configuration still carries an old `.number` display unit or
    /// an empty threshold payload from an earlier app version.
    public func effectiveMenuBarItemConfiguration(for entity: DiscoveredEntity) -> MenuBarItemConfiguration {
        EntityDisplayDefaults.normalizedConfiguration(
            for: entity,
            configuration: menuBarDisplayConfiguration.itemConfiguration(for: entity.id)
        )
    }

    public func formattedValue(for entity: DiscoveredEntity, locale: Locale = .current) -> FormattedEntityValue {
        let configuration = effectiveMenuBarItemConfiguration(for: entity)
        return EntityValueFormatter(
            locale: locale,
            displayUnit: configuration.displayUnit,
            displayUnitSymbol: configuration.displayUnitSymbol,
            showsUnit: configuration.showsUnit,
            minValue: configuration.minValue,
            maxValue: configuration.maxValue
        ).format(displayedEntity(for: entity), isStale: valuesAreStale)
    }

    private func displayedEntity(for entity: DiscoveredEntity) -> DiscoveredEntity {
        PerchHAEntityAveraging.averagedEntity(
            base: entity,
            configuration: effectiveMenuBarItemConfiguration(for: entity),
            availableEntities: availableRooms.flatMap(\.entities)
        )
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
                addresses: connectionForm.addresses,
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

/// Keyboard access for a dashboard row's history popover.
///
/// On macOS 14+ the row is focusable and Space toggles the popover, matching
/// the pointer hover affordance. The stock focus ring is replaced with a
/// subtle accent wash that also marks a pinned row — and, unlike the system
/// ring, it clears when the row is unpinned instead of lingering after a
/// click. Earlier systems keep the VoiceOver named action as the non-pointer
/// path; there is no pre-14 API to make an arbitrary row focusable without
/// hijacking its embedded controls.
private struct HistoryRowKeyboardAccess: ViewModifier {
    let isPresented: Bool
    let open: () -> Void
    let close: () -> Void

    @FocusState private var isFocused: Bool

    func body(content: Content) -> some View {
        if #available(macOS 14.0, *) {
            content
                .background(
                    (isPresented || isFocused) ? PerchHATheme.accent.opacity(0.08) : Color.clear
                )
                .focusable()
                .focused($isFocused)
                .focusEffectDisabled()
                .onKeyPress(.space) {
                    if isPresented {
                        close()
                    } else {
                        open()
                    }
                    return .handled
                }
                .onChange(of: isPresented) { _, presented in
                    // Unpinning releases the click-granted focus so the row
                    // does not stay highlighted after deselecting.
                    if !presented {
                        isFocused = false
                    }
                }
        } else {
            content
        }
    }
}

/// Marks whether a live stream delivered at least one event, deciding whether
/// the reconnect backoff resets (events flowed before the drop) or doubles
/// (the stream failed before producing anything).
actor PerchHALiveEventReceipt {
    private(set) var didReceive = false

    func mark() {
        didReceive = true
    }
}

struct PerchHAHistoryCacheKey: Hashable, Sendable {
    let entityID: EntityID
    let range: HistoryRange
}

private struct PerchHAHistoryCacheEntry {
    let series: HistorySeries
    let expiresAt: PerchInstant
}

struct PerchHAHistoryCache {
    private var entries: [PerchHAHistoryCacheKey: PerchHAHistoryCacheEntry] = [:]
    private var order: [PerchHAHistoryCacheKey] = []

    var entryCount: Int {
        entries.count
    }

    var sampleCount: Int {
        entries.values.reduce(0) { partial, entry in
            partial + entry.series.samples.count
        }
    }

    mutating func series(for key: PerchHAHistoryCacheKey, now: PerchInstant) -> HistorySeries? {
        guard let entry = entries[key] else {
            return nil
        }
        guard entry.expiresAt > now else {
            // Expired for the fetch path, but the entry stays: the stale-tolerant
            // display peek still needs it if the refetch fails, and a successful
            // refetch overwrites it in place. Deleting here used to blank inline
            // previews whenever a TTL-expired hover read raced a server hiccup.
            return nil
        }
        markRecentlyUsed(key)
        return entry.series
    }

    /// Reads a cached series for DISPLAY regardless of TTL expiry, so an
    /// already-fetched inline sparkline keeps rendering its last-known data
    /// instead of blinking out the moment the entry crosses its refresh TTL.
    /// The background bulk sync refreshes entries underneath; an entry only
    /// disappears here once it is truly evicted by capacity.
    func peekAllowingStale(for key: PerchHAHistoryCacheKey) -> HistorySeries? {
        entries[key]?.series
    }

    mutating func insert(
        _ series: HistorySeries,
        for key: PerchHAHistoryCacheKey,
        now: PerchInstant,
        capacity: Int,
        ttl: PerchDuration,
        protecting protected: Set<PerchHAHistoryCacheKey> = []
    ) {
        entries[key] = PerchHAHistoryCacheEntry(
            series: series,
            expiresAt: now.advanced(by: ttl)
        )
        markRecentlyUsed(key)
        trim(to: capacity, protecting: protected)
    }

    mutating func pruneExpired(
        now: PerchInstant,
        protecting protected: Set<PerchHAHistoryCacheKey> = []
    ) -> Set<PerchHAHistoryCacheKey> {
        let expiredKeys = entries.compactMap { key, entry in
            entry.expiresAt <= now && !protected.contains(key) ? key : nil
        }
        guard !expiredKeys.isEmpty else {
            return []
        }
        let removed = Set(expiredKeys)
        for key in removed {
            entries[key] = nil
        }
        order.removeAll { removed.contains($0) }
        return removed
    }

    private mutating func markRecentlyUsed(_ key: PerchHAHistoryCacheKey) {
        order.removeAll { $0 == key }
        order.append(key)
    }

    /// Evicts least-recently-used entries above capacity, never touching the
    /// protected keys (the displayed working set). On a dashboard larger than
    /// the configured capacity the cache overflows by the protected count rather
    /// than evicting on-screen rows — evicting those is what used to re-create
    /// the preview flicker on every cold sync cycle.
    private mutating func trim(to capacity: Int, protecting protected: Set<PerchHAHistoryCacheKey>) {
        guard order.count > capacity else {
            return
        }
        var removableInLRUOrder = order.filter { !protected.contains($0) }
        while order.count > capacity, !removableInLRUOrder.isEmpty {
            let removed = removableInLRUOrder.removeFirst()
            entries[removed] = nil
            order.removeAll { $0 == removed }
        }
    }
}

struct PendingControlChange {
    let entityID: EntityID
    let previousState: String
    let previousPosition: Int?
    let targetState: String
    let targetPosition: Int?
    let name: String
}

struct SettingsSelectionTreeSignature: Equatable {
    struct RoomSignature: Equatable {
        let id: RoomID
        let name: String
        let entities: [EntitySignature]
    }

    struct EntitySignature: Equatable {
        let id: EntityID
        let name: String
        let unit: String?
        let areaID: AreaID?
        let deviceID: DeviceID?
        let deviceName: String?
        let deviceManufacturer: String?
        let deviceModel: String?
        let deviceDomain: String?
    }

    let selectionConfiguration: EntitySelectionConfiguration
    let selectionQuery: String
    let rooms: [RoomSignature]

    init(snapshot: PerchHAPanelSnapshot) {
        self.selectionConfiguration = snapshot.selectionConfiguration
        self.selectionQuery = snapshot.selectionQuery
        self.rooms = snapshot.availableRooms.map { room in
            RoomSignature(
                id: room.id,
                name: room.name,
                entities: room.entities.map { entity in
                    EntitySignature(
                        id: entity.id,
                        name: entity.name,
                        unit: entity.unit,
                        areaID: entity.areaID,
                        deviceID: entity.deviceID,
                        deviceName: entity.deviceName,
                        deviceManufacturer: entity.deviceManufacturer,
                        deviceModel: entity.deviceModel,
                        deviceDomain: entity.deviceDomain
                    )
                }
            )
        }
    }
}

struct AvailableEntityIndexSignature: Equatable {
    let roomIDs: [RoomID]
    let entityIDs: [EntityID]

    init(rooms: [Room]) {
        self.roomIDs = rooms.map(\.id)
        self.entityIDs = rooms.flatMap { room in
            room.entities.map(\.id)
        }
    }
}

struct AvailableEntityLocation {
    let roomIndex: Int
    let entityIndex: Int
}

struct FormattedEntityValueCacheKey: Hashable {
    let entityID: EntityID
    let localeIdentifier: String
}

enum PerchHAInlineHistoryPreviewData {
    case sparkline(PerchHAHistorySparklineGeometry)
    case state(HistorySeries)
    case placeholder
}
