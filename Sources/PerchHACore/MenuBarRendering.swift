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

public struct ValueThresholds: Codable, Equatable, Sendable {
    public let warning: ValueThreshold?
    public let critical: ValueThreshold?

    public init(warning: ValueThreshold? = nil, critical: ValueThreshold? = nil) {
        self.warning = warning
        self.critical = critical
    }
}

public struct MenuBarItemConfiguration: Codable, Equatable, Sendable {
    public let entityID: EntityID
    public let style: MenuBarDisplayStyle
    public let showsLabel: Bool
    public let showsUnit: Bool
    public let maximumFractionDigits: Int
    public let absoluteTotal: Double?
    public let totalEntityID: EntityID?
    public let thresholds: ValueThresholds
    public let defaultHistoryRange: HistoryRange
    /// Which controls a cover entity exposes in the panel.
    public let coverControlMode: CoverControlMode
    /// The selected unit that converts and formats this entity's value, or `nil`
    /// to use the unit detected from the entity's Home Assistant unit.
    public let displayUnit: ValueUnit?
    /// The optional lower bound mapped to `0` for percentage/icon units.
    public let minValue: Double?
    /// The optional upper bound mapped to `1` for percentage/icon units.
    public let maxValue: Double?

    public init(
        entityID: EntityID,
        style: MenuBarDisplayStyle = .text,
        showsLabel: Bool = false,
        showsUnit: Bool = true,
        maximumFractionDigits: Int = 0,
        absoluteTotal: Double? = nil,
        totalEntityID: EntityID? = nil,
        thresholds: ValueThresholds = ValueThresholds(),
        defaultHistoryRange: HistoryRange = .hour,
        coverControlMode: CoverControlMode = .both,
        displayUnit: ValueUnit? = nil,
        minValue: Double? = nil,
        maxValue: Double? = nil
    ) {
        self.entityID = entityID
        self.style = style
        self.showsLabel = showsLabel
        self.showsUnit = showsUnit
        self.maximumFractionDigits = max(0, maximumFractionDigits)
        self.absoluteTotal = absoluteTotal
        self.totalEntityID = totalEntityID
        self.thresholds = thresholds
        self.defaultHistoryRange = defaultHistoryRange
        self.coverControlMode = coverControlMode
        self.displayUnit = displayUnit
        self.minValue = minValue
        self.maxValue = maxValue
    }

    public func updating(
        style: MenuBarDisplayStyle? = nil,
        showsLabel: Bool? = nil,
        showsUnit: Bool? = nil,
        maximumFractionDigits: Int? = nil,
        absoluteTotal: Double? = nil,
        totalEntityID: EntityID? = nil,
        thresholds: ValueThresholds? = nil,
        defaultHistoryRange: HistoryRange? = nil,
        coverControlMode: CoverControlMode? = nil,
        displayUnit: ValueUnit? = nil,
        minValue: Double? = nil,
        maxValue: Double? = nil
    ) -> MenuBarItemConfiguration {
        MenuBarItemConfiguration(
            entityID: entityID,
            style: style ?? self.style,
            showsLabel: showsLabel ?? self.showsLabel,
            showsUnit: showsUnit ?? self.showsUnit,
            maximumFractionDigits: maximumFractionDigits ?? self.maximumFractionDigits,
            absoluteTotal: absoluteTotal ?? self.absoluteTotal,
            totalEntityID: totalEntityID ?? self.totalEntityID,
            thresholds: thresholds ?? self.thresholds,
            defaultHistoryRange: defaultHistoryRange ?? self.defaultHistoryRange,
            coverControlMode: coverControlMode ?? self.coverControlMode,
            displayUnit: displayUnit ?? self.displayUnit,
            minValue: minValue ?? self.minValue,
            maxValue: maxValue ?? self.maxValue
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
            showsLabel: showsLabel,
            showsUnit: showsUnit,
            maximumFractionDigits: maximumFractionDigits,
            absoluteTotal: absoluteTotal,
            totalEntityID: totalEntityID,
            thresholds: thresholds,
            defaultHistoryRange: defaultHistoryRange,
            coverControlMode: coverControlMode,
            displayUnit: unit,
            minValue: minValue,
            maxValue: maxValue
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
            showsLabel: showsLabel,
            showsUnit: showsUnit,
            maximumFractionDigits: maximumFractionDigits,
            absoluteTotal: absoluteTotal,
            totalEntityID: totalEntityID,
            thresholds: thresholds,
            defaultHistoryRange: defaultHistoryRange,
            coverControlMode: coverControlMode,
            displayUnit: displayUnit,
            minValue: minValue,
            maxValue: maxValue
        )
    }

    public func settingAbsoluteTotal(_ total: Double?) -> MenuBarItemConfiguration {
        MenuBarItemConfiguration(
            entityID: entityID,
            style: style,
            showsLabel: showsLabel,
            showsUnit: showsUnit,
            maximumFractionDigits: maximumFractionDigits,
            absoluteTotal: total,
            totalEntityID: nil,
            thresholds: thresholds,
            defaultHistoryRange: defaultHistoryRange,
            coverControlMode: coverControlMode,
            displayUnit: displayUnit,
            minValue: minValue,
            maxValue: maxValue
        )
    }

    public func settingTotalEntityID(_ id: EntityID?) -> MenuBarItemConfiguration {
        MenuBarItemConfiguration(
            entityID: entityID,
            style: style,
            showsLabel: showsLabel,
            showsUnit: showsUnit,
            maximumFractionDigits: maximumFractionDigits,
            absoluteTotal: nil,
            totalEntityID: id,
            thresholds: thresholds,
            defaultHistoryRange: defaultHistoryRange,
            coverControlMode: coverControlMode,
            displayUnit: displayUnit,
            minValue: minValue,
            maxValue: maxValue
        )
    }

    public func settingWarningThreshold(_ threshold: ValueThreshold?) -> MenuBarItemConfiguration {
        settingThresholds(
            ValueThresholds(
                warning: threshold,
                critical: thresholds.critical
            )
        )
    }

    public func settingCriticalThreshold(_ threshold: ValueThreshold?) -> MenuBarItemConfiguration {
        settingThresholds(
            ValueThresholds(
                warning: thresholds.warning,
                critical: threshold
            )
        )
    }

    public func settingThresholds(_ thresholds: ValueThresholds) -> MenuBarItemConfiguration {
        MenuBarItemConfiguration(
            entityID: entityID,
            style: style,
            showsLabel: showsLabel,
            showsUnit: showsUnit,
            maximumFractionDigits: maximumFractionDigits,
            absoluteTotal: absoluteTotal,
            totalEntityID: totalEntityID,
            thresholds: thresholds,
            defaultHistoryRange: defaultHistoryRange,
            coverControlMode: coverControlMode,
            displayUnit: displayUnit,
            minValue: minValue,
            maxValue: maxValue
        )
    }

    private enum CodingKeys: String, CodingKey {
        case entityID
        case style
        case showsLabel
        case showsUnit
        case maximumFractionDigits
        case absoluteTotal
        case totalEntityID
        case thresholds
        case defaultHistoryRange
        case coverControlMode
        case displayUnit
        case minValue
        case maxValue
        case temperatureUnit
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        entityID = try container.decode(EntityID.self, forKey: .entityID)
        style = try container.decodeIfPresent(MenuBarDisplayStyle.self, forKey: .style) ?? .text
        showsLabel = try container.decodeIfPresent(Bool.self, forKey: .showsLabel) ?? false
        showsUnit = try container.decodeIfPresent(Bool.self, forKey: .showsUnit) ?? true
        maximumFractionDigits = max(
            0,
            try container.decodeIfPresent(Int.self, forKey: .maximumFractionDigits) ?? 0
        )
        absoluteTotal = try container.decodeIfPresent(Double.self, forKey: .absoluteTotal)
        totalEntityID = try container.decodeIfPresent(EntityID.self, forKey: .totalEntityID)
        thresholds = try container.decodeIfPresent(ValueThresholds.self, forKey: .thresholds) ?? ValueThresholds()
        defaultHistoryRange = try container.decodeIfPresent(HistoryRange.self, forKey: .defaultHistoryRange) ?? .hour
        coverControlMode = try container.decodeIfPresent(CoverControlMode.self, forKey: .coverControlMode) ?? .both
        displayUnit = Self.decodeDisplayUnit(from: container)
        minValue = try container.decodeIfPresent(Double.self, forKey: .minValue)
        maxValue = try container.decodeIfPresent(Double.self, forKey: .maxValue)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(entityID, forKey: .entityID)
        try container.encode(style, forKey: .style)
        try container.encode(showsLabel, forKey: .showsLabel)
        try container.encode(showsUnit, forKey: .showsUnit)
        try container.encode(maximumFractionDigits, forKey: .maximumFractionDigits)
        try container.encodeIfPresent(absoluteTotal, forKey: .absoluteTotal)
        try container.encodeIfPresent(totalEntityID, forKey: .totalEntityID)
        try container.encode(thresholds, forKey: .thresholds)
        try container.encode(defaultHistoryRange, forKey: .defaultHistoryRange)
        try container.encode(coverControlMode, forKey: .coverControlMode)
        try container.encodeIfPresent(displayUnit, forKey: .displayUnit)
        try container.encodeIfPresent(minValue, forKey: .minValue)
        try container.encodeIfPresent(maxValue, forKey: .maxValue)
    }

    /// Decodes the optional `displayUnit`, mapping legacy payloads to `nil`.
    ///
    /// The dropped `"automatic"` value (and a legacy `temperatureUnit` of
    /// `"automatic"`) decode to `nil`, meaning "use the detected default". A
    /// legacy `temperatureUnit` of `"celsius"`/`"fahrenheit"` maps to the
    /// matching scale.
    ///
    /// - Parameter container: The decoding container for the configuration.
    /// - Returns: The decoded unit, or `nil` for auto-detect.
    private static func decodeDisplayUnit(
        from container: KeyedDecodingContainer<CodingKeys>
    ) -> ValueUnit? {
        if let raw = try? container.decodeIfPresent(String.self, forKey: .displayUnit) {
            if raw == "automatic" {
                return nil
            }
            return ValueUnit(rawValue: raw)
        }
        switch try? container.decodeIfPresent(String.self, forKey: .temperatureUnit) {
        case "celsius":
            return .celsius
        case "fahrenheit":
            return .fahrenheit
        default:
            return nil
        }
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
        let value = EntityValueFormatter(
            locale: locale,
            maximumFractionDigits: configuration.maximumFractionDigits,
            displayUnit: configuration.displayUnit,
            showsUnit: configuration.showsUnit,
            minValue: configuration.minValue,
            maxValue: configuration.maxValue
        ).format(entity, isStale: isStale)
        let gauge = gauge(for: entity, configuration: configuration, availableEntities: availableEntities)
        let severity = severity(for: entity, gauge: gauge, configuration: configuration)
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
        return nil
    }

    private func severity(
        for entity: DiscoveredEntity,
        gauge: MenuBarGauge?,
        configuration: MenuBarItemConfiguration
    ) -> ValueSeverity {
        let metric = gauge?.percent ?? numericState(entity.state)
        guard let metric else {
            return .normal
        }
        if configuration.thresholds.critical?.matches(metric) == true {
            return .critical
        }
        if configuration.thresholds.warning?.matches(metric) == true {
            return .warning
        }
        return .normal
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
