import Foundation

/// How a panel entity row should present its value, decided purely so the view
/// stays a thin renderer and the choice can be unit-tested.
///
/// The cases mirror the iStat-Menus-style row treatments:
/// - ``gauge`` — a numeric value with a resolvable `0...1` fraction (a percent
///   unit, a configured absolute total, or a sibling total entity), drawn as a
///   ring/bar/battery.
/// - ``value`` — a plain numeric value with no resolvable range; the big number
///   stands alone.
/// - ``statePill`` — an on/off or open/closed state shown as a colored pill.
public enum PearchHAEntityRowPresentation: Equatable, Sendable {
    case gauge(PearchHAEntityGauge)
    case value(severity: ValueSeverity)
    case statePill(isActive: Bool)

    /// Resolves the presentation for an entity.
    ///
    /// The numeric fraction and severity are computed by the same
    /// ``MenuBarItemRenderer`` that drives the menu-bar gauges, so the panel and
    /// the menu bar never diverge. A row becomes a ``statePill`` only when the
    /// state is a recognized on/off or open/closed value *and* no numeric fraction
    /// is resolvable (a position-reporting cover with a numeric position still
    /// renders a gauge). A resolvable fraction yields a ``gauge`` carrying the
    /// entity's chosen ring/bar/battery style; otherwise a plain ``value``.
    ///
    /// - Parameters:
    ///   - entity: The entity to present.
    ///   - configuration: The entity's menu-bar item configuration (style,
    ///     bounds, thresholds, total).
    ///   - availableEntities: Sibling entities, used to resolve a configured
    ///     total entity.
    ///   - locale: The locale for value formatting.
    /// - Returns: The chosen row presentation.
    public static func resolve(
        entity: DiscoveredEntity,
        configuration: MenuBarItemConfiguration,
        availableEntities: [DiscoveredEntity] = [],
        locale: Locale = .current
    ) -> PearchHAEntityRowPresentation {
        let rendered = MenuBarItemRenderer().render(
            entity: entity,
            configuration: configuration,
            availableEntities: availableEntities,
            locale: locale
        )
        if let percent = gaugePercent(
            entity: entity,
            configuration: configuration,
            availableEntities: availableEntities,
            rendered: rendered
        ) {
            return .gauge(
                PearchHAEntityGauge(
                    fraction: min(1.0, max(0.0, percent / 100.0)),
                    severity: rendered.severity,
                    style: gaugeStyle(for: configuration.style)
                )
            )
        }
        if let isActive = activePillState(entity.state) {
            return .statePill(isActive: isActive)
        }
        return .value(severity: rendered.severity)
    }

    /// The `0...100` percent the renderer resolved for the entity, or `nil` when
    /// no fraction is meaningful.
    ///
    /// The renderer only emits a gauge for non-text styles; to keep the decision
    /// independent of the configured style we re-render with a ring style purely
    /// to probe whether a fraction exists, then keep the entity's real style.
    private static func gaugePercent(
        entity: DiscoveredEntity,
        configuration: MenuBarItemConfiguration,
        availableEntities: [DiscoveredEntity],
        rendered: RenderedMenuBarItem
    ) -> Double? {
        if let gauge = rendered.gauge {
            return gauge.percent
        }
        guard configuration.style == .text else {
            return nil
        }
        let probe = MenuBarItemRenderer().render(
            entity: entity,
            configuration: configuration.updating(style: .ring),
            availableEntities: availableEntities,
            locale: .current
        )
        return probe.gauge?.percent
    }

    private static func gaugeStyle(for style: MenuBarDisplayStyle) -> PearchHAGaugeStyle {
        switch style {
        case .ring, .text:
            .ring
        case .bar:
            .bar
        case .battery:
            .battery
        }
    }

    /// Recognizes on/open vs off/closed states for the pill treatment.
    ///
    /// - Returns: `true` for active states (on/open), `false` for inactive states
    ///   (off/closed), or `nil` when the state is neither.
    private static func activePillState(_ state: String) -> Bool? {
        switch state.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "on", "open":
            true
        case "off", "closed":
            false
        default:
            nil
        }
    }
}

/// The drawn gauge family a row uses.
public enum PearchHAGaugeStyle: String, Equatable, Sendable {
    case ring
    case bar
    case battery
}

/// A resolved gauge for an entity row: a `0...1` fraction, its severity, and the
/// drawn shape.
public struct PearchHAEntityGauge: Equatable, Sendable {
    /// The fill fraction, clamped to `0...1`.
    public let fraction: Double
    /// The threshold severity driving the gauge tint.
    public let severity: ValueSeverity
    /// The drawn gauge family.
    public let style: PearchHAGaugeStyle

    public init(fraction: Double, severity: ValueSeverity, style: PearchHAGaugeStyle) {
        self.fraction = min(1.0, max(0.0, fraction))
        self.severity = severity
        self.style = style
    }
}

/// Pure decisions for the dashboard inline-preview column, kept here so the view
/// stays a thin renderer and the choices can be unit-tested.
public enum PearchHADashboardPreview {
    /// Whether a bounded-gauge row should draw its meter for a given value status.
    ///
    /// The meter renders the entity's last-known fraction, so it stays visible
    /// while the value is momentarily ``EntityValueStatus/stale`` (a background
    /// sync or a brief WebSocket gap) instead of collapsing to a placeholder and
    /// flickering. Only a genuinely absent value (``EntityValueStatus/unavailable``
    /// or ``EntityValueStatus/unknown``) hides the meter.
    ///
    /// - Parameter status: The entity's current value status.
    /// - Returns: `true` to draw the meter, `false` to fall through to the cached
    ///   sparkline or placeholder.
    public static func meterShows(for status: EntityValueStatus) -> Bool {
        switch status {
        case .available, .stale:
            return true
        case .unavailable, .unknown:
            return false
        }
    }
}
