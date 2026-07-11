import Foundation

public enum MenuBarDisplayStyle: String, CaseIterable, Codable, Equatable, Sendable {
    case text
    case bar
    case battery
    case ring
}

/// Controls which interactive elements a cover entity exposes in the panel.
public enum CoverControlMode: String, CaseIterable, Codable, Equatable, Sendable {
    /// Open, Stop, and Close buttons only.
    case buttons
    /// A position slider only, shown when a position is reported.
    case slider
    /// Both the buttons and the position slider (the default).
    case both

    /// Whether the Open/Stop/Close buttons should be rendered.
    public var showsButtons: Bool {
        switch self {
        case .buttons, .both:
            true
        case .slider:
            false
        }
    }

    /// Whether the position slider should be rendered when a position exists.
    public var showsSlider: Bool {
        switch self {
        case .slider, .both:
            true
        case .buttons:
            false
        }
    }
}

public enum HistoryRange: String, CaseIterable, Codable, Equatable, Hashable, Sendable {
    case hour
    case day
    case week
    case month
}

public enum ValueThresholdDirection: String, Codable, Equatable, Sendable {
    case aboveOrEqual
    case belowOrEqual
}

public enum ValueSeverity: String, Codable, Equatable, Sendable {
    case normal
    case warning
    case critical
}

public struct ValueThreshold: Codable, Equatable, Sendable {
    public let value: Double
    public let direction: ValueThresholdDirection

    public init(value: Double, direction: ValueThresholdDirection = .aboveOrEqual) {
        self.value = value
        self.direction = direction
    }

    public func matches(_ candidate: Double) -> Bool {
        switch direction {
        case .aboveOrEqual:
            candidate >= value
        case .belowOrEqual:
            candidate <= value
        }
    }
}

/// One Grafana-style threshold step: from this value upward (until a higher
/// step takes over) the value wears the step's color.
public struct ThresholdStep: Codable, Equatable, Sendable {
    /// The inclusive lower edge of the step (`value >= self.value`).
    public let value: Double
    /// The color applied while the step is active.
    public let color: PearchHAAccentColor

    /// Creates a step.
    ///
    /// - Parameters:
    ///   - value: The inclusive lower edge.
    ///   - color: The applied color.
    public init(value: Double, color: PearchHAAccentColor) {
        self.value = value
        self.color = color
    }
}

public struct StateThresholdRule: Codable, Equatable, Sendable, Identifiable {
    public let match: String
    public let color: PearchHAAccentColor

    public var id: String {
        normalizedMatch
    }

    public init(match: String, color: PearchHAAccentColor) {
        self.match = match
        self.color = color
    }

    var normalizedMatch: String {
        match.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}

public struct StateThresholds: Codable, Equatable, Sendable {
    public static let inheritingDefaults = StateThresholds(inheritsDefaults: true)

    public let rules: [StateThresholdRule]
    public let baseColor: PearchHAAccentColor?
    public let inheritsDefaults: Bool

    public init(
        rules: [StateThresholdRule] = [],
        baseColor: PearchHAAccentColor? = nil,
        inheritsDefaults: Bool = false
    ) {
        self.rules = Self.uniqueRules(rules)
        self.baseColor = baseColor
        self.inheritsDefaults = inheritsDefaults
    }

    public func color(for state: String) -> PearchHAAccentColor? {
        let normalized = state.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalized.isEmpty else {
            return baseColor
        }
        return rules.first(where: { normalized.contains($0.normalizedMatch) })?.color ?? baseColor
    }

    public func severity(for state: String) -> ValueSeverity? {
        guard let color = color(for: state) else {
            return nil
        }
        return ValueThresholds.severity(of: color)
    }

    private static func uniqueRules(_ rules: [StateThresholdRule]) -> [StateThresholdRule] {
        var seen: Set<String> = []
        var result: [StateThresholdRule] = []
        for rule in rules {
            let normalized = rule.normalizedMatch
            guard !normalized.isEmpty, !seen.contains(normalized) else {
                continue
            }
            seen.insert(normalized)
            result.append(
                StateThresholdRule(
                    match: rule.match.trimmingCharacters(in: .whitespacesAndNewlines),
                    color: rule.color
                )
            )
        }
        return result
    }
}

/// Grafana-style thresholds: ordered steps over a base color.
///
/// The highest step at or below the value wins; below every step the optional
/// base color applies. Severity (for gauges and accessibility text) derives
/// from the matched color: red-dominant reads as critical, yellow/orange as
/// warning, everything else as normal.
public struct ValueThresholds: Codable, Equatable, Sendable {
    /// The canonical warning color (orange).
    public static let warningColor = PearchHAAccentColor(red: 0.95, green: 0.61, blue: 0.07, alpha: 1)
    /// The canonical critical color (red).
    public static let criticalColor = PearchHAAccentColor(red: 0.91, green: 0.30, blue: 0.24, alpha: 1)
    /// The canonical healthy color (green).
    public static let okColor = PearchHAAccentColor(red: 0.18, green: 0.80, blue: 0.44, alpha: 1)

    /// The steps, evaluated highest-value-first.
    public let steps: [ThresholdStep]
    /// The color applied below every step, or `nil` for the default tint.
    public let baseColor: PearchHAAccentColor?

    /// Creates thresholds from steps and an optional base color.
    ///
    /// - Parameters:
    ///   - steps: The steps; order does not matter, evaluation sorts them.
    ///   - baseColor: The color below every step, or `nil`.
    public init(steps: [ThresholdStep] = [], baseColor: PearchHAAccentColor? = nil) {
        self.steps = steps
        self.baseColor = baseColor
    }

    /// Creates thresholds from a warning/critical pair.
    ///
    /// `aboveOrEqual` thresholds become steps at their value. `belowOrEqual`
    /// thresholds invert: the color becomes the base and a healthy step starts
    /// just above the value.
    ///
    /// - Parameters:
    ///   - warning: The warning threshold (mapped to orange).
    ///   - critical: The critical threshold (mapped to red).
    public init(warning: ValueThreshold?, critical: ValueThreshold?) {
        var steps: [ThresholdStep] = []
        var baseColor: PearchHAAccentColor?
        for (threshold, color) in [(warning, Self.warningColor), (critical, Self.criticalColor)] {
            guard let threshold else {
                continue
            }
            switch threshold.direction {
            case .aboveOrEqual:
                steps.append(ThresholdStep(value: threshold.value, color: color))
            case .belowOrEqual:
                baseColor = color
                steps.append(ThresholdStep(value: threshold.value.nextUp, color: Self.okColor))
            }
        }
        self.init(steps: steps, baseColor: baseColor)
    }

    /// The color for a value: the highest step at or below it, else the base.
    ///
    /// - Parameter value: The numeric value to classify.
    /// - Returns: The matched color, or `nil` for the default tint.
    public func color(for value: Double) -> PearchHAAccentColor? {
        steps
            .sorted { $0.value > $1.value }
            .first { value >= $0.value }?
            .color ?? baseColor
    }

    /// The severity communicated for the value, derived from the matched
    /// color: red-dominant is critical, yellow/orange is warning, everything
    /// else (or no match) is normal.
    ///
    /// - Parameter value: The numeric value to classify.
    /// - Returns: The severity for gauge palettes and accessibility text.
    public func severity(for value: Double) -> ValueSeverity {
        guard let color = color(for: value) else {
            return .normal
        }
        return Self.severity(of: color)
    }

    /// Classifies a color into the severity it visually communicates.
    ///
    /// - Parameter color: The threshold color.
    /// - Returns: Critical for red-dominant colors, warning for yellow/orange,
    ///   normal otherwise.
    public static func severity(of color: PearchHAAccentColor) -> ValueSeverity {
        if color.red > 0.6 && color.green < 0.45 && color.blue < 0.45 {
            return .critical
        }
        if color.red > 0.6 && color.green >= 0.45 && color.blue < 0.4 {
            return .warning
        }
        return .normal
    }

    /// Returns a copy where one threshold slot is replaced or removed.
    ///
    /// - Parameters:
    ///   - color: The slot color.
    ///   - threshold: The threshold, or `nil` to remove the slot.
    /// - Returns: The updated thresholds.
    public func replacingThresholdRule(color: PearchHAAccentColor, threshold: ValueThreshold?) -> ValueThresholds {
        var remaining = steps.filter { $0.color != color }
        var base = baseColor == color ? nil : baseColor
        if let threshold {
            switch threshold.direction {
            case .aboveOrEqual:
                remaining.append(ThresholdStep(value: threshold.value, color: color))
            case .belowOrEqual:
                base = color
                remaining.append(ThresholdStep(value: threshold.value.nextUp, color: Self.okColor))
            }
        }
        return ValueThresholds(steps: remaining, baseColor: base)
    }

    private enum CodingKeys: String, CodingKey {
        case steps
        case baseColor
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            steps: try container.decodeIfPresent([ThresholdStep].self, forKey: .steps) ?? [],
            baseColor: try container.decodeIfPresent(PearchHAAccentColor.self, forKey: .baseColor)
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(steps, forKey: .steps)
        try container.encodeIfPresent(baseColor, forKey: .baseColor)
    }
}

public struct MenuBarItemConfiguration: Codable, Equatable, Sendable {
    public let entityID: EntityID
    public let style: MenuBarDisplayStyle
    /// The per-entity menu-bar appearance (icon / text / both), or `nil` to
    /// inherit the global default appearance. A per-entity choice always wins
    /// over the global default.
    public let appearance: PearchHAMenuBarAppearance?
    public let showsLabel: Bool
    public let showsUnit: Bool
    public let maximumFractionDigits: Int
    public let absoluteTotal: Double?
    public let totalEntityID: EntityID?
    /// The shared averaging family for this entity, including the entity itself.
    /// Empty means no averaging.
    public let averageEntityIDs: [EntityID]
    public let thresholds: ValueThresholds
    public let stateThresholds: StateThresholds
    /// The chart range for this entity's inline preview and history popover,
    /// or `nil` to inherit the global Appearance default.
    public let defaultHistoryRange: HistoryRange?
    /// Which controls a cover entity exposes in the panel.
    public let coverControlMode: CoverControlMode
    /// The selected unit that converts and formats this entity's value, or `nil`
    /// to use the unit detected from the entity's Home Assistant unit.
    public let displayUnit: ValueUnit?
    /// A concrete target unit symbol within the chosen family, or `nil` to let
    /// the formatter auto-scale within the effective unit family.
    public let displayUnitSymbol: String?
    /// The optional lower bound mapped to `0` for percentage/icon units.
    public let minValue: Double?
    /// The optional upper bound mapped to `1` for percentage/icon units.
    public let maxValue: Double?
    /// Whether the promoted menu-bar item shows an icon beside its value.
    public let showsEntityIcon: Bool
    /// A custom SF Symbol name for the menu-bar icon, or `nil` to use the
    /// automatic domain-derived symbol.
    public let customIconName: String?

    public init(
        entityID: EntityID,
        style: MenuBarDisplayStyle = .text,
        appearance: PearchHAMenuBarAppearance? = nil,
        showsLabel: Bool = false,
        showsUnit: Bool = true,
        maximumFractionDigits: Int = 1,
        absoluteTotal: Double? = nil,
        totalEntityID: EntityID? = nil,
        averageEntityIDs: [EntityID] = [],
        thresholds: ValueThresholds = ValueThresholds(),
        stateThresholds: StateThresholds = .inheritingDefaults,
        defaultHistoryRange: HistoryRange? = nil,
        coverControlMode: CoverControlMode = .both,
        displayUnit: ValueUnit? = nil,
        displayUnitSymbol: String? = nil,
        minValue: Double? = nil,
        maxValue: Double? = nil,
        showsEntityIcon: Bool = true,
        customIconName: String? = nil
    ) {
        self.entityID = entityID
        self.style = style
        self.appearance = appearance
        self.showsLabel = showsLabel
        self.showsUnit = showsUnit
        self.maximumFractionDigits = max(0, maximumFractionDigits)
        self.absoluteTotal = absoluteTotal
        self.totalEntityID = totalEntityID
        self.averageEntityIDs = Self.uniqueAverageEntityIDs(averageEntityIDs)
        self.thresholds = thresholds
        self.stateThresholds = stateThresholds
        self.defaultHistoryRange = defaultHistoryRange
        self.coverControlMode = coverControlMode
        self.displayUnit = displayUnit
        let trimmedDisplayUnitSymbol = displayUnitSymbol?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.displayUnitSymbol = (trimmedDisplayUnitSymbol?.isEmpty ?? true) ? nil : trimmedDisplayUnitSymbol
        self.minValue = minValue
        self.maxValue = maxValue
        self.showsEntityIcon = showsEntityIcon
        let trimmedIcon = customIconName?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.customIconName = (trimmedIcon?.isEmpty ?? true) ? nil : trimmedIcon
    }

    public init(
        entityID: EntityID,
        style: MenuBarDisplayStyle = .text,
        appearance: PearchHAMenuBarAppearance? = nil,
        showsLabel: Bool = false,
        showsUnit: Bool = true,
        maximumFractionDigits: Int = 1,
        absoluteTotal: Double? = nil,
        totalEntityID: EntityID? = nil,
        averageEntityIDs: [EntityID] = [],
        thresholds: ValueThresholds = ValueThresholds(),
        stateThresholds: StateThresholds = .inheritingDefaults,
        defaultHistoryRange: HistoryRange? = nil,
        coverControlMode: CoverControlMode = .both,
        displayUnit: ValueUnit? = nil,
        minValue: Double? = nil,
        maxValue: Double? = nil,
        showsEntityIcon: Bool = true,
        customIconName: String? = nil
    ) {
        self.init(
            entityID: entityID,
            style: style,
            appearance: appearance,
            showsLabel: showsLabel,
            showsUnit: showsUnit,
            maximumFractionDigits: maximumFractionDigits,
            absoluteTotal: absoluteTotal,
            totalEntityID: totalEntityID,
            averageEntityIDs: averageEntityIDs,
            thresholds: thresholds,
            stateThresholds: stateThresholds,
            defaultHistoryRange: defaultHistoryRange,
            coverControlMode: coverControlMode,
            displayUnit: displayUnit,
            displayUnitSymbol: nil,
            minValue: minValue,
            maxValue: maxValue,
            showsEntityIcon: showsEntityIcon,
            customIconName: customIconName
        )
    }

    public init(
        entityID: EntityID,
        style: MenuBarDisplayStyle = .text,
        appearance: PearchHAMenuBarAppearance? = nil,
        showsLabel: Bool = false,
        showsUnit: Bool = true,
        maximumFractionDigits: Int = 1,
        absoluteTotal: Double? = nil,
        totalEntityID: EntityID? = nil,
        thresholds: ValueThresholds = ValueThresholds(),
        stateThresholds: StateThresholds = .inheritingDefaults,
        defaultHistoryRange: HistoryRange? = nil,
        coverControlMode: CoverControlMode = .both,
        displayUnit: ValueUnit? = nil,
        minValue: Double? = nil,
        maxValue: Double? = nil,
        showsEntityIcon: Bool = true,
        customIconName: String? = nil
    ) {
        self.init(
            entityID: entityID,
            style: style,
            appearance: appearance,
            showsLabel: showsLabel,
            showsUnit: showsUnit,
            maximumFractionDigits: maximumFractionDigits,
            absoluteTotal: absoluteTotal,
            totalEntityID: totalEntityID,
            averageEntityIDs: [],
            thresholds: thresholds,
            stateThresholds: stateThresholds,
            defaultHistoryRange: defaultHistoryRange,
            coverControlMode: coverControlMode,
            displayUnit: displayUnit,
            displayUnitSymbol: nil,
            minValue: minValue,
            maxValue: maxValue,
            showsEntityIcon: showsEntityIcon,
            customIconName: customIconName
        )
    }

    public func updating(
        style: MenuBarDisplayStyle? = nil,
        showsLabel: Bool? = nil,
        showsUnit: Bool? = nil,
        maximumFractionDigits: Int? = nil,
        absoluteTotal: Double? = nil,
        totalEntityID: EntityID? = nil,
        averageEntityIDs: [EntityID]? = nil,
        thresholds: ValueThresholds? = nil,
        stateThresholds: StateThresholds? = nil,
        coverControlMode: CoverControlMode? = nil,
        displayUnit: ValueUnit? = nil,
        displayUnitSymbol: String? = nil,
        minValue: Double? = nil,
        maxValue: Double? = nil
    ) -> MenuBarItemConfiguration {
        MenuBarItemConfiguration(
            entityID: entityID,
            style: style ?? self.style,
            appearance: appearance,
            showsLabel: showsLabel ?? self.showsLabel,
            showsUnit: showsUnit ?? self.showsUnit,
            maximumFractionDigits: maximumFractionDigits ?? self.maximumFractionDigits,
            absoluteTotal: absoluteTotal ?? self.absoluteTotal,
            totalEntityID: totalEntityID ?? self.totalEntityID,
            averageEntityIDs: averageEntityIDs ?? self.averageEntityIDs,
            thresholds: thresholds ?? self.thresholds,
            stateThresholds: stateThresholds ?? self.stateThresholds,
            defaultHistoryRange: defaultHistoryRange,
            coverControlMode: coverControlMode ?? self.coverControlMode,
            displayUnit: displayUnit ?? self.displayUnit,
            displayUnitSymbol: displayUnitSymbol ?? self.displayUnitSymbol,
            minValue: minValue ?? self.minValue,
            maxValue: maxValue ?? self.maxValue,
            showsEntityIcon: showsEntityIcon,
            customIconName: customIconName
        )
    }

    /// Returns a copy with the per-entity menu-bar appearance replaced.
    ///
    /// - Parameter appearance: The appearance to apply, or `nil` to inherit the
    ///   global default appearance.
    /// - Returns: An updated configuration value.
    public func settingAppearance(_ appearance: PearchHAMenuBarAppearance?) -> MenuBarItemConfiguration {
        MenuBarItemConfiguration(
            entityID: entityID,
            style: style,
            appearance: appearance,
            showsLabel: showsLabel,
            showsUnit: showsUnit,
            maximumFractionDigits: maximumFractionDigits,
            absoluteTotal: absoluteTotal,
            totalEntityID: totalEntityID,
            averageEntityIDs: averageEntityIDs,
            thresholds: thresholds,
            stateThresholds: stateThresholds,
            defaultHistoryRange: defaultHistoryRange,
            coverControlMode: coverControlMode,
            displayUnit: displayUnit,
            displayUnitSymbol: displayUnitSymbol,
            minValue: minValue,
            maxValue: maxValue,
            showsEntityIcon: showsEntityIcon,
            customIconName: customIconName
        )
    }

    /// Returns a copy with the selected display unit replaced.
    ///
    /// - Parameter unit: The unit to apply, or `nil` to use the detected default.
    /// - Returns: An updated configuration value.
    public func settingDisplayUnit(_ unit: ValueUnit?) -> MenuBarItemConfiguration {
        MenuBarItemConfiguration(
            entityID: entityID,
            style: style,
            appearance: appearance,
            showsLabel: showsLabel,
            showsUnit: showsUnit,
            maximumFractionDigits: maximumFractionDigits,
            absoluteTotal: absoluteTotal,
            totalEntityID: totalEntityID,
            averageEntityIDs: averageEntityIDs,
            thresholds: thresholds,
            stateThresholds: stateThresholds,
            defaultHistoryRange: defaultHistoryRange,
            coverControlMode: coverControlMode,
            displayUnit: unit,
            displayUnitSymbol: displayUnitSymbol,
            minValue: minValue,
            maxValue: maxValue,
            showsEntityIcon: showsEntityIcon,
            customIconName: customIconName
        )
    }

    public func settingDisplayUnitSymbol(_ symbol: String?) -> MenuBarItemConfiguration {
        MenuBarItemConfiguration(
            entityID: entityID,
            style: style,
            appearance: appearance,
            showsLabel: showsLabel,
            showsUnit: showsUnit,
            maximumFractionDigits: maximumFractionDigits,
            absoluteTotal: absoluteTotal,
            totalEntityID: totalEntityID,
            averageEntityIDs: averageEntityIDs,
            thresholds: thresholds,
            stateThresholds: stateThresholds,
            defaultHistoryRange: defaultHistoryRange,
            coverControlMode: coverControlMode,
            displayUnit: displayUnit,
            displayUnitSymbol: symbol,
            minValue: minValue,
            maxValue: maxValue,
            showsEntityIcon: showsEntityIcon,
            customIconName: customIconName
        )
    }

    /// Returns a copy with the percentage/icon normalization bounds replaced.
    ///
    /// - Parameters:
    ///   - minValue: The lower bound mapped to `0`, or `nil` to clear it.
    ///   - maxValue: The upper bound mapped to `1`, or `nil` to clear it.
    /// - Returns: An updated configuration value.
    public func settingBounds(minValue: Double?, maxValue: Double?) -> MenuBarItemConfiguration {
        MenuBarItemConfiguration(
            entityID: entityID,
            style: style,
            appearance: appearance,
            showsLabel: showsLabel,
            showsUnit: showsUnit,
            maximumFractionDigits: maximumFractionDigits,
            absoluteTotal: absoluteTotal,
            totalEntityID: totalEntityID,
            averageEntityIDs: averageEntityIDs,
            thresholds: thresholds,
            stateThresholds: stateThresholds,
            defaultHistoryRange: defaultHistoryRange,
            coverControlMode: coverControlMode,
            displayUnit: displayUnit,
            displayUnitSymbol: displayUnitSymbol,
            minValue: minValue,
            maxValue: maxValue,
            showsEntityIcon: showsEntityIcon,
            customIconName: customIconName
        )
    }

    public func settingAbsoluteTotal(_ total: Double?) -> MenuBarItemConfiguration {
        MenuBarItemConfiguration(
            entityID: entityID,
            style: style,
            appearance: appearance,
            showsLabel: showsLabel,
            showsUnit: showsUnit,
            maximumFractionDigits: maximumFractionDigits,
            absoluteTotal: total,
            totalEntityID: nil,
            averageEntityIDs: averageEntityIDs,
            thresholds: thresholds,
            stateThresholds: stateThresholds,
            defaultHistoryRange: defaultHistoryRange,
            coverControlMode: coverControlMode,
            displayUnit: displayUnit,
            displayUnitSymbol: displayUnitSymbol,
            minValue: minValue,
            maxValue: maxValue,
            showsEntityIcon: showsEntityIcon,
            customIconName: customIconName
        )
    }

    public func settingTotalEntityID(_ id: EntityID?) -> MenuBarItemConfiguration {
        MenuBarItemConfiguration(
            entityID: entityID,
            style: style,
            appearance: appearance,
            showsLabel: showsLabel,
            showsUnit: showsUnit,
            maximumFractionDigits: maximumFractionDigits,
            absoluteTotal: nil,
            totalEntityID: id,
            averageEntityIDs: averageEntityIDs,
            thresholds: thresholds,
            stateThresholds: stateThresholds,
            defaultHistoryRange: defaultHistoryRange,
            coverControlMode: coverControlMode,
            displayUnit: displayUnit,
            displayUnitSymbol: displayUnitSymbol,
            minValue: minValue,
            maxValue: maxValue,
            showsEntityIcon: showsEntityIcon,
            customIconName: customIconName
        )
    }

    public func settingWarningThreshold(_ threshold: ValueThreshold?) -> MenuBarItemConfiguration {
        settingThresholds(thresholds.replacingThresholdRule(color: ValueThresholds.warningColor, threshold: threshold))
    }

    public func settingCriticalThreshold(_ threshold: ValueThreshold?) -> MenuBarItemConfiguration {
        settingThresholds(thresholds.replacingThresholdRule(color: ValueThresholds.criticalColor, threshold: threshold))
    }

    /// Returns a copy with the chart range replaced.
    ///
    /// - Parameter range: The per-entity range, or `nil` to inherit the global
    ///   Appearance default.
    /// - Returns: An updated configuration value.
    public func settingDefaultHistoryRange(_ range: HistoryRange?) -> MenuBarItemConfiguration {
        MenuBarItemConfiguration(
            entityID: entityID,
            style: style,
            appearance: appearance,
            showsLabel: showsLabel,
            showsUnit: showsUnit,
            maximumFractionDigits: maximumFractionDigits,
            absoluteTotal: absoluteTotal,
            totalEntityID: totalEntityID,
            averageEntityIDs: averageEntityIDs,
            thresholds: thresholds,
            stateThresholds: stateThresholds,
            defaultHistoryRange: range,
            coverControlMode: coverControlMode,
            displayUnit: displayUnit,
            displayUnitSymbol: displayUnitSymbol,
            minValue: minValue,
            maxValue: maxValue,
            showsEntityIcon: showsEntityIcon,
            customIconName: customIconName
        )
    }

    public func settingThresholds(_ thresholds: ValueThresholds) -> MenuBarItemConfiguration {
        MenuBarItemConfiguration(
            entityID: entityID,
            style: style,
            appearance: appearance,
            showsLabel: showsLabel,
            showsUnit: showsUnit,
            maximumFractionDigits: maximumFractionDigits,
            absoluteTotal: absoluteTotal,
            totalEntityID: totalEntityID,
            averageEntityIDs: averageEntityIDs,
            thresholds: thresholds,
            stateThresholds: stateThresholds,
            defaultHistoryRange: defaultHistoryRange,
            coverControlMode: coverControlMode,
            displayUnit: displayUnit,
            displayUnitSymbol: displayUnitSymbol,
            minValue: minValue,
            maxValue: maxValue,
            showsEntityIcon: showsEntityIcon,
            customIconName: customIconName
        )
    }

    public func settingStateThresholds(_ stateThresholds: StateThresholds) -> MenuBarItemConfiguration {
        MenuBarItemConfiguration(
            entityID: entityID,
            style: style,
            appearance: appearance,
            showsLabel: showsLabel,
            showsUnit: showsUnit,
            maximumFractionDigits: maximumFractionDigits,
            absoluteTotal: absoluteTotal,
            totalEntityID: totalEntityID,
            averageEntityIDs: averageEntityIDs,
            thresholds: thresholds,
            stateThresholds: stateThresholds,
            defaultHistoryRange: defaultHistoryRange,
            coverControlMode: coverControlMode,
            displayUnit: displayUnit,
            displayUnitSymbol: displayUnitSymbol,
            minValue: minValue,
            maxValue: maxValue,
            showsEntityIcon: showsEntityIcon,
            customIconName: customIconName
        )
    }

    /// Returns a copy with the dashboard icon visibility replaced.
    ///
    /// - Parameter shows: Whether the dashboard row shows the entity icon.
    /// - Returns: An updated configuration value.
    public func settingShowsEntityIcon(_ shows: Bool) -> MenuBarItemConfiguration {
        MenuBarItemConfiguration(
            entityID: entityID,
            style: style,
            appearance: appearance,
            showsLabel: showsLabel,
            showsUnit: showsUnit,
            maximumFractionDigits: maximumFractionDigits,
            absoluteTotal: absoluteTotal,
            totalEntityID: totalEntityID,
            averageEntityIDs: averageEntityIDs,
            thresholds: thresholds,
            stateThresholds: stateThresholds,
            defaultHistoryRange: defaultHistoryRange,
            coverControlMode: coverControlMode,
            displayUnit: displayUnit,
            displayUnitSymbol: displayUnitSymbol,
            minValue: minValue,
            maxValue: maxValue,
            showsEntityIcon: shows,
            customIconName: customIconName
        )
    }

    /// Returns a copy with the custom dashboard icon replaced.
    ///
    /// - Parameter symbolName: The SF Symbol to show, or `nil` for the
    ///   automatic domain-derived icon. Blank strings clear to automatic.
    /// - Returns: An updated configuration value.
    public func settingCustomIconName(_ symbolName: String?) -> MenuBarItemConfiguration {
        MenuBarItemConfiguration(
            entityID: entityID,
            style: style,
            appearance: appearance,
            showsLabel: showsLabel,
            showsUnit: showsUnit,
            maximumFractionDigits: maximumFractionDigits,
            absoluteTotal: absoluteTotal,
            totalEntityID: totalEntityID,
            averageEntityIDs: averageEntityIDs,
            thresholds: thresholds,
            stateThresholds: stateThresholds,
            defaultHistoryRange: defaultHistoryRange,
            coverControlMode: coverControlMode,
            displayUnit: displayUnit,
            displayUnitSymbol: displayUnitSymbol,
            minValue: minValue,
            maxValue: maxValue,
            showsEntityIcon: showsEntityIcon,
            customIconName: symbolName
        )
    }

    public func settingAverageEntityIDs(_ ids: [EntityID]) -> MenuBarItemConfiguration {
        MenuBarItemConfiguration(
            entityID: entityID,
            style: style,
            appearance: appearance,
            showsLabel: showsLabel,
            showsUnit: showsUnit,
            maximumFractionDigits: maximumFractionDigits,
            absoluteTotal: absoluteTotal,
            totalEntityID: totalEntityID,
            averageEntityIDs: ids,
            thresholds: thresholds,
            stateThresholds: stateThresholds,
            defaultHistoryRange: defaultHistoryRange,
            coverControlMode: coverControlMode,
            displayUnit: displayUnit,
            displayUnitSymbol: displayUnitSymbol,
            minValue: minValue,
            maxValue: maxValue,
            showsEntityIcon: showsEntityIcon,
            customIconName: customIconName
        )
    }

    private enum CodingKeys: String, CodingKey {
        case entityID
        case style
        case appearance
        case showsLabel
        case showsUnit
        case maximumFractionDigits
        case absoluteTotal
        case totalEntityID
        case averageEntityIDs
        case thresholds
        case stateThresholds
        case defaultHistoryRange
        case coverControlMode
        case displayUnit
        case displayUnitSymbol
        case minValue
        case maxValue
        case temperatureUnit
        case showsEntityIcon
        case customIconName
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        entityID = try container.decode(EntityID.self, forKey: .entityID)
        style = try container.decodeIfPresent(MenuBarDisplayStyle.self, forKey: .style) ?? .text
        appearance = try container.decodeIfPresent(PearchHAMenuBarAppearance.self, forKey: .appearance)
        showsLabel = try container.decodeIfPresent(Bool.self, forKey: .showsLabel) ?? false
        showsUnit = try container.decodeIfPresent(Bool.self, forKey: .showsUnit) ?? true
        maximumFractionDigits = max(
            0,
            try container.decodeIfPresent(Int.self, forKey: .maximumFractionDigits) ?? 1
        )
        absoluteTotal = try container.decodeIfPresent(Double.self, forKey: .absoluteTotal)
        totalEntityID = try container.decodeIfPresent(EntityID.self, forKey: .totalEntityID)
        averageEntityIDs = Self.uniqueAverageEntityIDs(
            try container.decodeIfPresent([EntityID].self, forKey: .averageEntityIDs) ?? []
        )
        thresholds = try container.decodeIfPresent(ValueThresholds.self, forKey: .thresholds) ?? ValueThresholds()
        stateThresholds = try container.decodeIfPresent(StateThresholds.self, forKey: .stateThresholds) ?? .inheritingDefaults
        defaultHistoryRange = try container.decodeIfPresent(HistoryRange.self, forKey: .defaultHistoryRange)
        coverControlMode = try container.decodeIfPresent(CoverControlMode.self, forKey: .coverControlMode) ?? .both
        displayUnit = Self.decodeDisplayUnit(from: container)
        let decodedDisplayUnitSymbol = try container.decodeIfPresent(String.self, forKey: .displayUnitSymbol)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        displayUnitSymbol = (decodedDisplayUnitSymbol?.isEmpty ?? true) ? nil : decodedDisplayUnitSymbol
        minValue = try container.decodeIfPresent(Double.self, forKey: .minValue)
        maxValue = try container.decodeIfPresent(Double.self, forKey: .maxValue)
        showsEntityIcon = try container.decodeIfPresent(Bool.self, forKey: .showsEntityIcon) ?? true
        let decodedIcon = try container.decodeIfPresent(String.self, forKey: .customIconName)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        customIconName = (decodedIcon?.isEmpty ?? true) ? nil : decodedIcon
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(entityID, forKey: .entityID)
        try container.encode(style, forKey: .style)
        try container.encodeIfPresent(appearance, forKey: .appearance)
        try container.encode(showsLabel, forKey: .showsLabel)
        try container.encode(showsUnit, forKey: .showsUnit)
        try container.encode(maximumFractionDigits, forKey: .maximumFractionDigits)
        try container.encodeIfPresent(absoluteTotal, forKey: .absoluteTotal)
        try container.encodeIfPresent(totalEntityID, forKey: .totalEntityID)
        try container.encode(averageEntityIDs, forKey: .averageEntityIDs)
        try container.encode(thresholds, forKey: .thresholds)
        try container.encode(stateThresholds, forKey: .stateThresholds)
        try container.encodeIfPresent(defaultHistoryRange, forKey: .defaultHistoryRange)
        try container.encode(coverControlMode, forKey: .coverControlMode)
        try container.encodeIfPresent(displayUnit, forKey: .displayUnit)
        try container.encodeIfPresent(displayUnitSymbol, forKey: .displayUnitSymbol)
        try container.encodeIfPresent(minValue, forKey: .minValue)
        try container.encodeIfPresent(maxValue, forKey: .maxValue)
        try container.encode(showsEntityIcon, forKey: .showsEntityIcon)
        try container.encodeIfPresent(customIconName, forKey: .customIconName)
    }

    private static func uniqueAverageEntityIDs(_ ids: [EntityID]) -> [EntityID] {
        var seen: Set<EntityID> = []
        var result: [EntityID] = []
        for id in ids where !seen.contains(id) {
            seen.insert(id)
            result.append(id)
        }
        return result
    }

    /// Decodes the optional `displayUnit`.
    private static func decodeDisplayUnit(
        from container: KeyedDecodingContainer<CodingKeys>
    ) -> ValueUnit? {
        guard let raw = try? container.decodeIfPresent(String.self, forKey: .displayUnit) else {
            return nil
        }
        return ValueUnit(rawValue: raw)
    }
}

public struct MenuBarDisplayConfiguration: Codable, Equatable, Sendable {
    public let promotedEntityIDs: [EntityID]
    public let itemConfigurations: [MenuBarItemConfiguration]

    public init(
        promotedEntityIDs: [EntityID] = [],
        itemConfigurations: [MenuBarItemConfiguration] = []
    ) {
        self.promotedEntityIDs = Self.unique(promotedEntityIDs)
        self.itemConfigurations = Self.unique(itemConfigurations)
    }

    public func isPromoted(_ entityID: EntityID) -> Bool {
        promotedEntityIDs.contains(entityID)
    }

    public func itemConfiguration(for entityID: EntityID) -> MenuBarItemConfiguration {
        itemConfigurations.first { $0.entityID == entityID } ?? MenuBarItemConfiguration(entityID: entityID)
    }

    public func settingPromotion(_ entityID: EntityID, isPromoted: Bool) -> MenuBarDisplayConfiguration {
        if isPromoted {
            return MenuBarDisplayConfiguration(
                promotedEntityIDs: promotedEntityIDs + [entityID],
                itemConfigurations: itemConfigurations
            )
        }
        return MenuBarDisplayConfiguration(
            promotedEntityIDs: promotedEntityIDs.filter { $0 != entityID },
            itemConfigurations: itemConfigurations
        )
    }

    public func movingPromotion(_ entityID: EntityID, direction: SelectionMoveDirection) -> MenuBarDisplayConfiguration {
        MenuBarDisplayConfiguration(
            promotedEntityIDs: Self.move(entityID, in: promotedEntityIDs, direction: direction),
            itemConfigurations: itemConfigurations
        )
    }

    public func movingPromotion(
        _ entityID: EntityID,
        relativeTo targetID: EntityID,
        placement: SelectionDropPlacement
    ) -> MenuBarDisplayConfiguration {
        MenuBarDisplayConfiguration(
            promotedEntityIDs: Self.place(entityID, relativeTo: targetID, placement: placement, in: promotedEntityIDs),
            itemConfigurations: itemConfigurations
        )
    }

    public func replacingItemConfiguration(_ configuration: MenuBarItemConfiguration) -> MenuBarDisplayConfiguration {
        MenuBarDisplayConfiguration(
            promotedEntityIDs: promotedEntityIDs,
            itemConfigurations: itemConfigurations.filter { $0.entityID != configuration.entityID } + [configuration]
        )
    }

    private static func unique(_ ids: [EntityID]) -> [EntityID] {
        var seen: Set<EntityID> = []
        var result: [EntityID] = []
        for id in ids where !seen.contains(id) {
            seen.insert(id)
            result.append(id)
        }
        return result
    }

    private static func unique(_ configurations: [MenuBarItemConfiguration]) -> [MenuBarItemConfiguration] {
        var seen: Set<EntityID> = []
        var result: [MenuBarItemConfiguration] = []
        for configuration in configurations where !seen.contains(configuration.entityID) {
            seen.insert(configuration.entityID)
            result.append(configuration)
        }
        return result
    }

    private static func move(_ id: EntityID, in ids: [EntityID], direction: SelectionMoveDirection) -> [EntityID] {
        guard let index = ids.firstIndex(of: id) else {
            return ids
        }
        let targetIndex: Int
        switch direction {
        case .up:
            guard index > ids.startIndex else {
                return ids
            }
            targetIndex = ids.index(before: index)
        case .down:
            guard index < ids.index(before: ids.endIndex) else {
                return ids
            }
            targetIndex = ids.index(after: index)
        }
        var result = ids
        result.swapAt(index, targetIndex)
        return result
    }

    private static func place(
        _ id: EntityID,
        relativeTo targetID: EntityID,
        placement: SelectionDropPlacement,
        in ids: [EntityID]
    ) -> [EntityID] {
        guard id != targetID,
              ids.contains(id),
              let targetIndex = ids.firstIndex(of: targetID)
        else {
            return ids
        }

        var result = ids.filter { $0 != id }
        let adjustedTargetIndex = result.firstIndex(of: targetID) ?? targetIndex
        let insertionIndex: Int
        switch placement {
        case .before:
            insertionIndex = adjustedTargetIndex
        case .after:
            insertionIndex = result.index(after: adjustedTargetIndex)
        }
        result.insert(id, at: min(insertionIndex, result.endIndex))
        return result
    }
}

public struct MenuBarGauge: Equatable, Sendable {
    public let percent: Double
    public let filledSegments: Int
    public let segmentCount: Int

    public init(percent: Double, filledSegments: Int, segmentCount: Int) {
        self.percent = percent
        self.filledSegments = filledSegments
        self.segmentCount = segmentCount
    }
}

public struct RenderedMenuBarItem: Equatable, Sendable {
    public let title: String
    public let textTitle: String
    public let accessibilityLabel: String
    public let style: MenuBarDisplayStyle
    public let value: FormattedEntityValue
    public let gauge: MenuBarGauge?
    public let severity: ValueSeverity

    public init(
        title: String,
        textTitle: String,
        accessibilityLabel: String,
        style: MenuBarDisplayStyle,
        value: FormattedEntityValue,
        gauge: MenuBarGauge?,
        severity: ValueSeverity
    ) {
        self.title = title
        self.textTitle = textTitle
        self.accessibilityLabel = accessibilityLabel
        self.style = style
        self.value = value
        self.gauge = gauge
        self.severity = severity
    }
}

public struct MenuBarItemProjector: Sendable {
    public init() {}

    public func promotedEntities(rooms: [Room], menuBarEntityIDs: [EntityID]) -> [DiscoveredEntity] {
        var entitiesByID: [EntityID: DiscoveredEntity] = [:]
        for entity in rooms.flatMap(\.entities) where entitiesByID[entity.id] == nil {
            entitiesByID[entity.id] = entity
        }
        return menuBarEntityIDs.compactMap { entitiesByID[$0] }
    }
}

public struct MenuBarItemRenderer: Sendable {
    public let segmentCount: Int

    public init(segmentCount: Int = 10) {
        self.segmentCount = max(1, segmentCount)
    }

    public func render(
        entity: DiscoveredEntity,
        configuration: MenuBarItemConfiguration,
        availableEntities: [DiscoveredEntity] = [],
        locale: Locale = .current,
        isStale: Bool = false
    ) -> RenderedMenuBarItem {
        let displayedEntity = PearchHAEntityAveraging.averagedEntity(
            base: entity,
            configuration: configuration,
            availableEntities: availableEntities
        )
        let value = EntityValueFormatter(
            locale: locale,
            maximumFractionDigits: configuration.maximumFractionDigits,
            displayUnit: configuration.displayUnit,
            displayUnitSymbol: configuration.displayUnitSymbol,
            showsUnit: configuration.showsUnit,
            minValue: configuration.minValue,
            maxValue: configuration.maxValue
        ).format(displayedEntity, isStale: isStale)
        let gauge = gauge(for: displayedEntity, configuration: configuration, availableEntities: availableEntities)
        let severity = severity(for: displayedEntity, gauge: gauge, configuration: configuration)
        let textTitle = textTitle(for: entity, value: value, configuration: configuration)
        let title = title(textTitle: textTitle, entity: entity, gauge: gauge, configuration: configuration)
        let accessibilityLabel = accessibilityLabel(
            for: entity,
            value: value,
            gauge: gauge,
            configuration: configuration,
            severity: severity
        )

        return RenderedMenuBarItem(
            title: title,
            textTitle: textTitle,
            accessibilityLabel: accessibilityLabel,
            style: configuration.style,
            value: value,
            gauge: gauge,
            severity: severity
        )
    }

    private func textTitle(
        for entity: DiscoveredEntity,
        value: FormattedEntityValue,
        configuration: MenuBarItemConfiguration
    ) -> String {
        configuration.showsLabel ? "\(entity.name) \(value.text)" : value.text
    }

    private func title(
        textTitle: String,
        entity: DiscoveredEntity,
        gauge: MenuBarGauge?,
        configuration: MenuBarItemConfiguration
    ) -> String {
        guard let gauge else {
            return textTitle
        }

        let gaugeText = gaugeTitle(style: configuration.style, gauge: gauge)
        if configuration.showsLabel {
            return "\(entity.name) \(gaugeText)"
        }
        return gaugeText
    }

    private func gaugeTitle(style: MenuBarDisplayStyle, gauge: MenuBarGauge) -> String {
        let percent = Int(gauge.percent.rounded())
        switch style {
        case .text:
            return "\(percent)%"
        case .bar:
            return "BAR[\(segments(for: gauge))] \(percent)%"
        case .battery:
            return "BAT[\(segments(for: gauge))] \(percent)%"
        case .ring:
            return "RING \(percent)%"
        }
    }

    private func segments(for gauge: MenuBarGauge) -> String {
        let filled = String(repeating: "#", count: gauge.filledSegments)
        let empty = String(repeating: "-", count: max(0, gauge.segmentCount - gauge.filledSegments))
        return filled + empty
    }

    private func accessibilityLabel(
        for entity: DiscoveredEntity,
        value: FormattedEntityValue,
        gauge: MenuBarGauge?,
        configuration: MenuBarItemConfiguration,
        severity: ValueSeverity
    ) -> String {
        var parts = [entity.name, value.text]
        if let gauge {
            parts.append("\(Int(gauge.percent.rounded())) percent")
        }
        if severity != .normal {
            parts.append(severity.rawValue)
        }
        if configuration.style != .text {
            parts.append(configuration.style.rawValue)
        }
        return parts.joined(separator: ", ")
    }

    private func gauge(
        for entity: DiscoveredEntity,
        configuration: MenuBarItemConfiguration,
        availableEntities: [DiscoveredEntity]
    ) -> MenuBarGauge? {
        guard configuration.style != .text,
              let percent = normalizedPercent(for: entity, configuration: configuration, availableEntities: availableEntities)
        else {
            return nil
        }

        let filled = Int((percent / 100.0 * Double(segmentCount)).rounded(.toNearestOrAwayFromZero))
        return MenuBarGauge(
            percent: percent,
            filledSegments: min(segmentCount, max(0, filled)),
            segmentCount: segmentCount
        )
    }

    private func normalizedPercent(
        for entity: DiscoveredEntity,
        configuration: MenuBarItemConfiguration,
        availableEntities: [DiscoveredEntity]
    ) -> Double? {
        guard let value = numericState(entity.state) else {
            return nil
        }
        if entity.unit?.trimmingCharacters(in: .whitespacesAndNewlines) == "%" {
            return clampedPercent(value)
        }
        if let total = configuration.absoluteTotal, total > 0 {
            return clampedPercent(value / total * 100.0)
        }
        if let totalEntityID = configuration.totalEntityID,
           let totalEntity = availableEntities.first(where: { $0.id == totalEntityID }),
           let total = numericState(totalEntity.state),
           total > 0,
           unitsAreCompatible(entity.unit, totalEntity.unit) {
            return clampedPercent(value / total * 100.0)
        }
        if let minValue = configuration.minValue,
           let maxValue = configuration.maxValue,
           maxValue > minValue {
            return clampedPercent((value - minValue) / (maxValue - minValue) * 100.0)
        }
        return nil
    }

    private func severity(
        for entity: DiscoveredEntity,
        gauge: MenuBarGauge?,
        configuration: MenuBarItemConfiguration
    ) -> ValueSeverity {
        let metric = gauge?.percent ?? numericState(entity.state)
        if let metric {
            return EntityDisplayDefaults.effectiveThresholds(for: entity, configuration: configuration).severity(for: metric)
        }
        return EntityDisplayDefaults.semanticStateSeverity(
            for: entity.state,
            entity: entity,
            configuration: configuration
        )
    }

    private func numericState(_ state: String) -> Double? {
        Double(state.trimmingCharacters(in: .whitespacesAndNewlines))
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

    private func clampedPercent(_ value: Double) -> Double {
        min(100.0, max(0.0, value))
    }
}
