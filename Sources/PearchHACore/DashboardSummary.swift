import Foundation

/// The pure projection behind the dashboard header's summary strip.
///
/// The popover replaces its old search bar with a compact header plus a strip of
/// at most three summary readouts built **only** from real snapshot data:
///
/// - a connection status pill (always present, carrying its own text),
/// - an optional primary metric (the first promoted menu-bar entity if any, else
///   the first numeric entity) with a resolvable `0...1` gauge fraction,
/// - an optional warning count of unavailable/stale entities.
///
/// The strip never renders empty decoration: when there is no numeric entity the
/// primary metric is absent, and the warning count is absent (rather than a
/// fabricated zero) only when there is no data context at all. Keeping the choice
/// here — pure and `Sendable` — lets the view stay a thin renderer and lets the
/// behavior be unit-tested without SwiftUI.
public struct PearchHADashboardSummary: Equatable, Sendable {
    /// A resolved primary metric: the entity, its formatted value text, and an
    /// optional gauge fraction/severity for a ring readout.
    public struct PrimaryMetric: Equatable, Sendable {
        /// The entity backing the metric.
        public let entityID: EntityID
        /// The entity's display name.
        public let name: String
        /// The formatted value text (for example `"44%"`).
        public let valueText: String
        /// The resolved gauge fraction in `0...1`, or `nil` for a plain value.
        public let fraction: Double?
        /// The threshold severity driving the readout tint.
        public let severity: ValueSeverity

        public init(
            entityID: EntityID,
            name: String,
            valueText: String,
            fraction: Double?,
            severity: ValueSeverity
        ) {
            self.entityID = entityID
            self.name = name
            self.valueText = valueText
            self.fraction = fraction.map { min(1.0, max(0.0, $0)) }
            self.severity = severity
        }
    }

    /// A user-selected summary readout resolved from a chosen entity.
    ///
    /// Unlike ``PrimaryMetric``, a selected metric is shown verbatim in the order
    /// the user picked it and is never tinted by gauge severity — it is a plain
    /// label/value pair. When the chosen entity is missing or its value cannot be
    /// read, ``isAvailable`` is `false` and ``valueText`` carries a muted
    /// placeholder so the metric stays visible rather than vanishing.
    public struct SelectedMetric: Equatable, Sendable {
        /// The chosen entity identifier (retained even when unresolved).
        public let entityID: EntityID
        /// The entity's display name, or the raw identifier when unresolved.
        public let name: String
        /// The formatted value text, or a placeholder when unavailable.
        public let valueText: String
        /// Whether the entity resolved to a real, readable value.
        public let isAvailable: Bool

        public init(entityID: EntityID, name: String, valueText: String, isAvailable: Bool) {
            self.entityID = entityID
            self.name = name
            self.valueText = valueText
            self.isAvailable = isAvailable
        }
    }

    /// The connection state, driving the status pill text and color.
    public let connectionState: ConnectionState
    /// A short connection label (for example `"Connected"`).
    public let connectionLabel: String
    /// The primary metric, or `nil` when no numeric entity is available.
    public let primaryMetric: PrimaryMetric?
    /// The number of unavailable/unknown/stale entities, or `nil` when there are
    /// no visible entities at all (so no count chip is drawn).
    public let warningCount: Int?
    /// The user-selected, ordered summary metrics. Empty means "automatic": the
    /// header derives its own metrics from ``primaryMetric``/``warningCount``.
    public let selectedMetrics: [SelectedMetric]

    public init(
        connectionState: ConnectionState,
        connectionLabel: String,
        primaryMetric: PrimaryMetric?,
        warningCount: Int?,
        selectedMetrics: [SelectedMetric] = []
    ) {
        self.connectionState = connectionState
        self.connectionLabel = connectionLabel
        self.primaryMetric = primaryMetric
        self.warningCount = warningCount
        self.selectedMetrics = selectedMetrics
    }
}
