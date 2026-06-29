import Foundation

public struct EntitySelectionConfiguration: Equatable, Codable, Sendable {
    public let selectedEntityIDs: [EntityID]
    public let roomOrder: [RoomID]
    public let entityOrder: [EntityID]
    public let isExplicit: Bool

    public init(
        selectedEntityIDs: [EntityID] = [],
        roomOrder: [RoomID] = [],
        entityOrder: [EntityID] = [],
        isExplicit: Bool = false
    ) {
        self.selectedEntityIDs = selectedEntityIDs
        self.roomOrder = roomOrder
        self.entityOrder = entityOrder
        self.isExplicit = isExplicit
    }
}

public struct SelectableEntity: Equatable, Sendable {
    public let entity: DiscoveredEntity
    public let isSelected: Bool

    public init(entity: DiscoveredEntity, isSelected: Bool) {
        self.entity = entity
        self.isSelected = isSelected
    }
}

public struct SelectableRoom: Equatable, Sendable {
    public let id: RoomID
    public let name: String
    public let entities: [SelectableEntity]

    public init(id: RoomID, name: String, entities: [SelectableEntity]) {
        self.id = id
        self.name = name
        self.entities = entities
    }
}

public enum SelectionMoveDirection: Equatable, Sendable {
    case up
    case down
}

public enum SelectionDropPlacement: Equatable, Sendable {
    case before
    case after
}

public struct EntitySelectionProjector: Sendable {
    public init() {}

    public func selectionTree(
        rooms: [Room],
        configuration: EntitySelectionConfiguration,
        query: String = ""
    ) -> [SelectableRoom] {
        let selected = Set(configuration.selectedEntityIDs)
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        return orderedRooms(rooms, roomOrder: configuration.roomOrder).compactMap { room in
            let roomMatches = normalizedQuery.isEmpty || room.name.lowercased().contains(normalizedQuery)
            let entities = orderedEntities(room.entities, entityOrder: configuration.entityOrder)
                .filter { entity in
                    roomMatches || entity.name.lowercased().contains(normalizedQuery) || entity.id.rawValue.lowercased().contains(normalizedQuery)
                }
                .map { entity in
                    SelectableEntity(entity: entity, isSelected: !configuration.isExplicit || selected.contains(entity.id))
                }
            guard !entities.isEmpty else {
                return nil
            }
            return SelectableRoom(id: room.id, name: room.name, entities: entities)
        }
    }

    public func selectedRooms(
        rooms: [Room],
        configuration: EntitySelectionConfiguration
    ) -> [Room] {
        let selected = Set(configuration.selectedEntityIDs)
        if !configuration.isExplicit {
            return orderedRooms(rooms, roomOrder: configuration.roomOrder).map { room in
                Room(
                    id: room.id,
                    name: room.name,
                    entities: orderedEntities(room.entities, entityOrder: configuration.entityOrder)
                )
            }
        }
        guard !selected.isEmpty else {
            return []
        }

        return orderedRooms(rooms, roomOrder: configuration.roomOrder).compactMap { room in
            let entities = orderedEntities(room.entities, entityOrder: configuration.entityOrder)
                .filter { selected.contains($0.id) }
            guard !entities.isEmpty else {
                return nil
            }
            return Room(id: room.id, name: room.name, entities: entities)
        }
    }

    private func orderedRooms(_ rooms: [Room], roomOrder: [RoomID]) -> [Room] {
        let order = indexedOrder(roomOrder)
        return rooms.enumerated().sorted { left, right in
            compare(order[left.element.id], left.offset, order[right.element.id], right.offset)
        }.map(\.element)
    }

    private func orderedEntities(_ entities: [DiscoveredEntity], entityOrder: [EntityID]) -> [DiscoveredEntity] {
        let order = indexedOrder(entityOrder)
        return entities.enumerated().sorted { left, right in
            compare(order[left.element.id], left.offset, order[right.element.id], right.offset)
        }.map(\.element)
    }

    private func indexedOrder<T: Hashable>(_ values: [T]) -> [T: Int] {
        var result: [T: Int] = [:]
        for value in values where result[value] == nil {
            result[value] = result.count
        }
        return result
    }

    private func compare(_ leftOrder: Int?, _ leftFallback: Int, _ rightOrder: Int?, _ rightFallback: Int) -> Bool {
        switch (leftOrder, rightOrder) {
        case let (left?, right?):
            left == right ? leftFallback < rightFallback : left < right
        case (.some, nil):
            true
        case (nil, .some):
            false
        case (nil, nil):
            leftFallback < rightFallback
        }
    }
}

public struct EntitySelectionReorderer: Sendable {
    public init() {}

    public func moveRoom(
        _ id: RoomID,
        direction: SelectionMoveDirection,
        rooms: [Room],
        configuration: EntitySelectionConfiguration
    ) -> EntitySelectionConfiguration {
        let orderedRooms = EntitySelectionProjector().selectedRooms(
            rooms: rooms,
            configuration: EntitySelectionConfiguration(
                roomOrder: configuration.roomOrder,
                entityOrder: configuration.entityOrder
            )
        )
        let orderedRoomIDs = orderedRooms.map(\.id)
        let roomIDs = move(id, in: orderedRoomIDs, direction: direction)
        guard roomIDs != orderedRoomIDs else {
            return configuration
        }
        let entityIDs = entityOrder(from: rooms, roomOrder: roomIDs, entityOrder: configuration.entityOrder)

        return EntitySelectionConfiguration(
            selectedEntityIDs: selectedEntityIDs(from: entityIDs, configuration: configuration),
            roomOrder: roomIDs,
            entityOrder: entityIDs,
            isExplicit: configuration.isExplicit
        )
    }

    public func moveRoom(
        _ id: RoomID,
        relativeTo targetID: RoomID,
        placement: SelectionDropPlacement,
        rooms: [Room],
        configuration: EntitySelectionConfiguration
    ) -> EntitySelectionConfiguration {
        let orderedRooms = EntitySelectionProjector().selectedRooms(
            rooms: rooms,
            configuration: EntitySelectionConfiguration(
                roomOrder: configuration.roomOrder,
                entityOrder: configuration.entityOrder
            )
        )
        let orderedRoomIDs = orderedRooms.map(\.id)
        let roomIDs = place(id, relativeTo: targetID, placement: placement, in: orderedRoomIDs)
        guard roomIDs != orderedRoomIDs else {
            return configuration
        }
        let entityIDs = entityOrder(from: rooms, roomOrder: roomIDs, entityOrder: configuration.entityOrder)

        return EntitySelectionConfiguration(
            selectedEntityIDs: selectedEntityIDs(from: entityIDs, configuration: configuration),
            roomOrder: roomIDs,
            entityOrder: entityIDs,
            isExplicit: configuration.isExplicit
        )
    }

    public func moveEntity(
        _ id: EntityID,
        direction: SelectionMoveDirection,
        rooms: [Room],
        configuration: EntitySelectionConfiguration
    ) -> EntitySelectionConfiguration {
        let projectedRooms = EntitySelectionProjector().selectedRooms(
            rooms: rooms,
            configuration: EntitySelectionConfiguration(
                roomOrder: configuration.roomOrder,
                entityOrder: configuration.entityOrder
            )
        )
        let orderedEntityIDs = projectedRooms.flatMap(\.entities).map(\.id)
        let movedRooms = projectedRooms.map { room in
            Room(
                id: room.id,
                name: room.name,
                entities: move(id, in: room.entities.map(\.id), direction: direction)
                    .compactMap { movedID in
                        room.entities.first { $0.id == movedID }
                    }
            )
        }
        let entityIDs = movedRooms.flatMap(\.entities).map(\.id)
        guard entityIDs != orderedEntityIDs else {
            return configuration
        }

        return EntitySelectionConfiguration(
            selectedEntityIDs: selectedEntityIDs(from: entityIDs, configuration: configuration),
            roomOrder: movedRooms.map(\.id),
            entityOrder: entityIDs,
            isExplicit: configuration.isExplicit
        )
    }

    public func moveEntity(
        _ id: EntityID,
        relativeTo targetID: EntityID,
        placement: SelectionDropPlacement,
        rooms: [Room],
        configuration: EntitySelectionConfiguration
    ) -> EntitySelectionConfiguration {
        let projectedRooms = EntitySelectionProjector().selectedRooms(
            rooms: rooms,
            configuration: EntitySelectionConfiguration(
                roomOrder: configuration.roomOrder,
                entityOrder: configuration.entityOrder
            )
        )
        let sourceRoomID = projectedRooms.first { room in
            room.entities.contains { $0.id == id }
        }?.id
        let targetRoomID = projectedRooms.first { room in
            room.entities.contains { $0.id == targetID }
        }?.id
        guard let sourceRoomID, sourceRoomID == targetRoomID else {
            return configuration
        }

        let orderedEntityIDs = projectedRooms.flatMap(\.entities).map(\.id)
        let movedRooms = projectedRooms.map { room in
            guard room.id == sourceRoomID else {
                return room
            }
            return Room(
                id: room.id,
                name: room.name,
                entities: place(id, relativeTo: targetID, placement: placement, in: room.entities.map(\.id))
                    .compactMap { movedID in
                        room.entities.first { $0.id == movedID }
                    }
            )
        }
        let entityIDs = movedRooms.flatMap(\.entities).map(\.id)
        guard entityIDs != orderedEntityIDs else {
            return configuration
        }

        return EntitySelectionConfiguration(
            selectedEntityIDs: selectedEntityIDs(from: entityIDs, configuration: configuration),
            roomOrder: movedRooms.map(\.id),
            entityOrder: entityIDs,
            isExplicit: configuration.isExplicit
        )
    }

    private func selectedEntityIDs(from entityOrder: [EntityID], configuration: EntitySelectionConfiguration) -> [EntityID] {
        guard configuration.isExplicit else {
            return []
        }
        let selected = Set(configuration.selectedEntityIDs)
        return entityOrder.filter { selected.contains($0) }
    }

    private func entityOrder(from rooms: [Room], roomOrder: [RoomID], entityOrder: [EntityID]) -> [EntityID] {
        EntitySelectionProjector().selectedRooms(
            rooms: rooms,
            configuration: EntitySelectionConfiguration(
                roomOrder: roomOrder,
                entityOrder: entityOrder
            )
        )
        .flatMap(\.entities)
        .map(\.id)
    }

    private func move<T: Equatable>(_ value: T, in values: [T], direction: SelectionMoveDirection) -> [T] {
        guard let index = values.firstIndex(of: value) else {
            return values
        }
        let targetIndex: Int
        switch direction {
        case .up:
            guard index > values.startIndex else {
                return values
            }
            targetIndex = values.index(before: index)
        case .down:
            guard index < values.index(before: values.endIndex) else {
                return values
            }
            targetIndex = values.index(after: index)
        }

        var moved = values
        moved.swapAt(index, targetIndex)
        return moved
    }

    private func place<T: Equatable>(
        _ value: T,
        relativeTo targetValue: T,
        placement: SelectionDropPlacement,
        in values: [T]
    ) -> [T] {
        guard value != targetValue, values.contains(value), values.contains(targetValue) else {
            return values
        }

        var moved = values.filter { $0 != value }
        guard let targetIndex = moved.firstIndex(of: targetValue) else {
            return values
        }
        let insertIndex: Int
        switch placement {
        case .before:
            insertIndex = targetIndex
        case .after:
            insertIndex = moved.index(after: targetIndex)
        }
        moved.insert(value, at: insertIndex)
        return moved
    }
}

public enum EntityValueStatus: Equatable, Sendable {
    case available
    case unavailable
    case unknown
    case stale
}

public struct FormattedEntityValue: Equatable, Sendable {
    public let text: String
    public let status: EntityValueStatus

    public init(text: String, status: EntityValueStatus) {
        self.text = text
        self.status = status
    }
}

/// Pure helpers for recognizing and converting temperature units.
public enum TemperatureConversion {
    /// Whether a Home Assistant unit string denotes a temperature scale.
    ///
    /// - Parameter unit: The raw unit string (for example `°C`, `F`, or `K`).
    /// - Returns: `true` for Celsius, Fahrenheit, or Kelvin variants.
    public static func isTemperatureUnit(_ unit: String?) -> Bool {
        scale(of: unit) != nil
    }

    /// The recognized scale for a unit string, or `nil` when not a temperature.
    public static func scale(of unit: String?) -> TemperatureScale? {
        guard let trimmed = unit?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }
        let normalized = trimmed
            .replacingOccurrences(of: "°", with: "")
            .replacingOccurrences(of: " ", with: "")
            .uppercased()
        switch normalized {
        case "C", "CELSIUS":
            return .celsius
        case "F", "FAHRENHEIT":
            return .fahrenheit
        case "K", "KELVIN":
            return .kelvin
        default:
            return nil
        }
    }

    /// Converts a numeric temperature between scales.
    ///
    /// - Parameters:
    ///   - value: The numeric value in `from`.
    ///   - from: The source scale.
    ///   - to: The destination scale.
    /// - Returns: The value expressed in the `to` scale.
    public static func convert(_ value: Double, from: TemperatureScale, to: TemperatureScale) -> Double {
        let celsius = from.toCelsius(value)
        return to.fromCelsius(celsius)
    }
}

/// A recognized temperature scale.
public enum TemperatureScale: Equatable, Sendable {
    case celsius
    case fahrenheit
    case kelvin

    /// The canonical unit label for this scale.
    public var unitLabel: String {
        switch self {
        case .celsius:
            "°C"
        case .fahrenheit:
            "°F"
        case .kelvin:
            "K"
        }
    }

    func toCelsius(_ value: Double) -> Double {
        switch self {
        case .celsius:
            value
        case .fahrenheit:
            (value - 32) * 5 / 9
        case .kelvin:
            value - 273.15
        }
    }

    func fromCelsius(_ celsius: Double) -> Double {
        switch self {
        case .celsius:
            celsius
        case .fahrenheit:
            celsius * 9 / 5 + 32
        case .kelvin:
            celsius + 273.15
        }
    }
}

/// A selectable display unit that self-converts a raw entity value into a
/// readable string, in the spirit of Grafana's unit picker.
///
/// Each case owns its own conversion and formatting rules. Cases that need a
/// numeric value fall back to the raw state verbatim when the value cannot be
/// parsed as a number (for example `HOME` or `off`).
public enum ValueUnit: String, CaseIterable, Codable, Equatable, Sendable {
    /// Keep the entity's Home Assistant unit, compacting only large magnitudes
    /// (>= 10000) with SI suffixes; smaller values format with the configured
    /// decimals exactly as before.
    case automatic
    /// A plain number with the configured decimals and thousands grouping,
    /// keeping the Home Assistant unit but never converting the value.
    case number
    /// Always SI-compacted (k/M/B/T), keeping the Home Assistant unit.
    case compact
    /// A percentage value rendered with a trailing `%`.
    case percent
    /// Interpret the value via the entity's temperature unit and show Celsius.
    case celsius
    /// Interpret the value via the entity's temperature unit and show Fahrenheit.
    case fahrenheit
    /// Interpret the value via the entity's temperature unit and show Kelvin.
    case kelvin
    /// Interpret the raw value as bytes and render as B/KB/MB/GB/TB (1024-based).
    case bytes
    /// Interpret the raw value as seconds and render as a compact duration.
    case duration

    /// A human-friendly label for this unit, shown in the settings picker.
    public var displayName: String {
        switch self {
        case .automatic:
            "Automatic"
        case .number:
            "Number"
        case .compact:
            "Compact (SI)"
        case .percent:
            "Percent"
        case .celsius:
            "Celsius"
        case .fahrenheit:
            "Fahrenheit"
        case .kelvin:
            "Kelvin"
        case .bytes:
            "Bytes"
        case .duration:
            "Duration"
        }
    }

    /// The threshold at or above which `.automatic` compacts a magnitude.
    private static let compactionThreshold = 10_000.0

    /// Renders a raw value as display text for this unit.
    ///
    /// - Parameters:
    ///   - rawNumericValue: The parsed numeric value, when the state is numeric.
    ///   - rawState: The trimmed raw state, used as a passthrough fallback.
    ///   - haUnit: The trimmed Home Assistant unit, when present.
    ///   - decimals: The configured maximum fraction digits (clamped to >= 0).
    ///   - showsUnit: Whether a trailing unit suffix should be appended.
    ///   - formatter: A configured `NumberFormatter` for locale-aware output.
    /// - Returns: The display text, including any unit suffix.
    public func display(
        rawNumericValue: Double?,
        rawState: String,
        haUnit: String?,
        decimals: Int,
        showsUnit: Bool,
        formatter: NumberFormatter
    ) -> String {
        let unit = (haUnit?.isEmpty == false) ? haUnit : nil
        switch self {
        case .automatic:
            guard let value = rawNumericValue else {
                return rawState
            }
            let number = abs(value) >= Self.compactionThreshold
                ? Self.compacted(value)
                : (formatter.string(from: NSNumber(value: value)) ?? rawState)
            return Self.appendUnit(number, unit: unit, showsUnit: showsUnit)
        case .number:
            guard let value = rawNumericValue else {
                return rawState
            }
            let number = formatter.string(from: NSNumber(value: value)) ?? rawState
            return Self.appendUnit(number, unit: unit, showsUnit: showsUnit)
        case .compact:
            guard let value = rawNumericValue else {
                return rawState
            }
            return Self.appendUnit(Self.compacted(value), unit: unit, showsUnit: showsUnit)
        case .percent:
            guard let value = rawNumericValue else {
                return rawState
            }
            let number = formatter.string(from: NSNumber(value: value)) ?? rawState
            return showsUnit ? "\(number)%" : number
        case .celsius, .fahrenheit, .kelvin:
            guard let value = rawNumericValue, let target = scale else {
                return rawState
            }
            let source = TemperatureConversion.scale(of: haUnit) ?? target
            let converted = TemperatureConversion.convert(value, from: source, to: target)
            let number = formatter.string(from: NSNumber(value: converted)) ?? rawState
            return showsUnit ? "\(number) \(target.unitLabel)" : number
        case .bytes:
            guard let value = rawNumericValue else {
                return rawState
            }
            return Self.bytes(value, showsUnit: showsUnit)
        case .duration:
            guard let value = rawNumericValue else {
                return rawState
            }
            return Self.duration(value)
        }
    }

    /// The temperature scale this unit targets, if any.
    private var scale: TemperatureScale? {
        switch self {
        case .celsius:
            .celsius
        case .fahrenheit:
            .fahrenheit
        case .kelvin:
            .kelvin
        default:
            nil
        }
    }

    private static func appendUnit(_ value: String, unit: String?, showsUnit: Bool) -> String {
        guard showsUnit, let unit, !unit.isEmpty else {
            return value
        }
        return "\(value) \(unit)"
    }

    /// Compacts a magnitude to roughly three significant digits with an SI
    /// suffix (k, M, B, T). Values below 1000 are returned without a suffix.
    static func compacted(_ value: Double) -> String {
        let suffixes: [(threshold: Double, suffix: String)] = [
            (1_000_000_000_000, "T"),
            (1_000_000_000, "B"),
            (1_000_000, "M"),
            (1_000, "k")
        ]
        let magnitude = abs(value)
        for entry in suffixes where magnitude >= entry.threshold {
            let scaled = value / entry.threshold
            return "\(threeSignificant(scaled))\(entry.suffix)"
        }
        return trimmedNumber(value)
    }

    /// Renders a value to about three significant digits, trimming trailing zeros.
    private static func threeSignificant(_ value: Double) -> String {
        let magnitude = abs(value)
        let decimals: Int = magnitude >= 100 ? 0 : (magnitude >= 10 ? 1 : 2)
        return trimmedNumber((value * pow(10, Double(decimals))).rounded() / pow(10, Double(decimals)))
    }

    /// Renders raw bytes as B/KB/MB/GB/TB (1024-based) to two decimals.
    static func bytes(_ value: Double, showsUnit: Bool) -> String {
        let units = ["B", "KB", "MB", "GB", "TB"]
        var magnitude = abs(value)
        var index = 0
        while magnitude >= 1024, index < units.count - 1 {
            magnitude /= 1024
            index += 1
        }
        let signed = value < 0 ? -magnitude : magnitude
        let number = index == 0 ? trimmedNumber(signed) : trimmedNumber((signed * 100).rounded() / 100)
        return showsUnit ? "\(number) \(units[index])" : number
    }

    /// Renders seconds as a compact human duration (for example `1h 2m`).
    static func duration(_ value: Double) -> String {
        let total = Int(abs(value).rounded())
        let sign = value < 0 ? "-" : ""
        let days = total / 86_400
        let hours = (total % 86_400) / 3_600
        let minutes = (total % 3_600) / 60
        let seconds = total % 60
        var parts: [String] = []
        if days > 0 { parts.append("\(days)d") }
        if hours > 0 { parts.append("\(hours)h") }
        if minutes > 0 { parts.append("\(minutes)m") }
        if seconds > 0 || parts.isEmpty { parts.append("\(seconds)s") }
        return sign + parts.prefix(2).joined(separator: " ")
    }

    private static func trimmedNumber(_ value: Double) -> String {
        if value == value.rounded() {
            return String(Int(value))
        }
        var text = String(format: "%.2f", value)
        while text.hasSuffix("0") {
            text.removeLast()
        }
        if text.hasSuffix(".") {
            text.removeLast()
        }
        return text
    }
}

public struct EntityValueFormatter: Sendable {
    public let localeIdentifier: String
    public let maximumFractionDigits: Int
    public let displayUnit: ValueUnit
    public let showsUnit: Bool

    public init(
        locale: Locale = .current,
        maximumFractionDigits: Int = 2,
        displayUnit: ValueUnit = .automatic,
        showsUnit: Bool = true
    ) {
        self.localeIdentifier = locale.identifier
        self.maximumFractionDigits = max(0, maximumFractionDigits)
        self.displayUnit = displayUnit
        self.showsUnit = showsUnit
    }

    public func format(_ entity: DiscoveredEntity, isStale: Bool = false) -> FormattedEntityValue {
        let normalizedState = entity.state.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if normalizedState == "unavailable" {
            return FormattedEntityValue(text: "Unavailable", status: .unavailable)
        }
        if normalizedState == "unknown" {
            return FormattedEntityValue(text: "Unknown", status: .unknown)
        }

        let value = valueText(state: entity.state, unit: entity.unit)
        if isStale {
            return FormattedEntityValue(text: "Stale: \(value)", status: .stale)
        }
        return FormattedEntityValue(text: value, status: .available)
    }

    private func valueText(state: String, unit: String?) -> String {
        let trimmedState = state.trimmingCharacters(in: .whitespacesAndNewlines)
        let numeric = Decimal(string: trimmedState, locale: Locale(identifier: "en_US_POSIX"))
            .map { NSDecimalNumber(decimal: $0).doubleValue }
        let resolvedUnit = unit?.trimmingCharacters(in: .whitespacesAndNewlines)
        return displayUnit.display(
            rawNumericValue: numeric,
            rawState: trimmedState,
            haUnit: resolvedUnit,
            decimals: maximumFractionDigits,
            showsUnit: showsUnit,
            formatter: numberFormatter()
        )
    }

    private func numberFormatter() -> NumberFormatter {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: localeIdentifier)
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = maximumFractionDigits
        formatter.roundingMode = .halfUp
        return formatter
    }
}

/// Pure, domain-aware defaults for a newly seen entity's display configuration.
///
/// These keep known entities sensible out of the box (battery sensors default
/// to the battery gauge, temperatures keep the reported unit, covers expose
/// both control styles) while leaving every option editable for unknowns.
public enum EntityDisplayDefaults {
    /// The default per-entity menu-bar/display configuration for an entity.
    ///
    /// - Parameter entity: The entity to derive defaults for.
    /// - Returns: A configuration carrying domain-appropriate defaults.
    public static func configuration(for entity: DiscoveredEntity) -> MenuBarItemConfiguration {
        MenuBarItemConfiguration(
            entityID: entity.id,
            style: defaultStyle(for: entity),
            coverControlMode: .both,
            displayUnit: displayUnit(for: entity)
        )
    }

    /// The smart default display unit derived from an entity's HA unit.
    ///
    /// - Parameter entity: The entity to inspect.
    /// - Returns: `.percent` for `%`, the matching temperature scale for
    ///   temperature units, `.bytes` for byte units, and `.automatic` otherwise.
    public static func displayUnit(for entity: DiscoveredEntity) -> ValueUnit {
        let trimmed = entity.unit?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let trimmed, !trimmed.isEmpty else {
            return .automatic
        }
        if trimmed == "%" {
            return .percent
        }
        switch TemperatureConversion.scale(of: trimmed) {
        case .celsius:
            return .celsius
        case .fahrenheit:
            return .fahrenheit
        case .kelvin:
            return .kelvin
        case nil:
            break
        }
        if isByteUnit(trimmed) {
            return .bytes
        }
        return .automatic
    }

    private static func isByteUnit(_ unit: String) -> Bool {
        let normalized = unit.replacingOccurrences(of: " ", with: "").uppercased()
        let byteUnits: Set<String> = [
            "B", "KB", "MB", "GB", "TB", "PB",
            "KIB", "MIB", "GIB", "TIB", "PIB",
            "BYTE", "BYTES"
        ]
        return byteUnits.contains(normalized)
    }

    /// The default menu-bar gauge style for an entity.
    ///
    /// - Parameter entity: The entity to inspect.
    /// - Returns: `.battery` for battery-named or percentage battery sensors,
    ///   otherwise `.text`.
    public static func defaultStyle(for entity: DiscoveredEntity) -> MenuBarDisplayStyle {
        isBatteryLike(entity) ? .battery : .text
    }

    private static func isBatteryLike(_ entity: DiscoveredEntity) -> Bool {
        let name = entity.name.lowercased()
        let id = entity.id.rawValue.lowercased()
        let unit = entity.unit?.trimmingCharacters(in: .whitespacesAndNewlines)
        let mentionsBattery = name.contains("battery")
            || name.contains("batt ")
            || id.contains("battery")
        return mentionsBattery && unit == "%"
    }
}
