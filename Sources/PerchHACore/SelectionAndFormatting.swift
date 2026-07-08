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

/// Pure resolver for whether an Entities-tab room shows its entity rows.
///
/// Rooms default to collapsed; a room is expanded only when its id is present
/// in the caller's expanded set. Two situations force a room visible without
/// mutating that set, so the user's expanded state survives them: an active
/// search (matches must never hide behind a collapsed header) and the room that
/// holds the currently-inspected entity (so the open inspector stays reachable).
public enum SelectionRoomCollapse {
    /// Whether `roomID`'s rows should be shown.
    ///
    /// - Parameters:
    ///   - roomID: The room's identifier (matched against `expandedRoomIDs`).
    ///   - expandedRoomIDs: Room identifiers the user has explicitly expanded.
    ///   - isSearching: `true` while a non-empty search filter is active; forces
    ///     every shown room expanded.
    ///   - roomContainsInspectedEntity: `true` when the room holds the entity
    ///     whose inspector is open; forces this room expanded.
    /// - Returns: `true` when the room's entity rows should be visible.
    public static func isExpanded(
        roomID: String,
        expandedRoomIDs: Set<String>,
        isSearching: Bool,
        roomContainsInspectedEntity: Bool
    ) -> Bool {
        if isSearching || roomContainsInspectedEntity {
            return true
        }
        return expandedRoomIDs.contains(roomID)
    }

    /// Whether every room in `roomIDs` is collapsed, used to flip a
    /// collapse-all affordance to expand-all. An active search or an empty room
    /// list reports `false`, since neither presents a fully-collapsed list.
    ///
    /// - Parameters:
    ///   - roomIDs: The identifiers of the rooms currently shown.
    ///   - expandedRoomIDs: Room identifiers the user has explicitly expanded.
    ///   - isSearching: `true` while a non-empty search filter is active.
    /// - Returns: `true` when every shown room is collapsed.
    public static func allCollapsed(
        roomIDs: [String],
        expandedRoomIDs: Set<String>,
        isSearching: Bool
    ) -> Bool {
        guard !isSearching, !roomIDs.isEmpty else {
            return false
        }
        return roomIDs.allSatisfy { !expandedRoomIDs.contains($0) }
    }
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
                    roomMatches
                        || entity.name.lowercased().contains(normalizedQuery)
                        || entity.id.rawValue.lowercased().contains(normalizedQuery)
                        || entity.deviceID?.rawValue.lowercased().contains(normalizedQuery) == true
                        || entity.deviceName?.lowercased().contains(normalizedQuery) == true
                        || entity.deviceManufacturer?.lowercased().contains(normalizedQuery) == true
                        || entity.deviceModel?.lowercased().contains(normalizedQuery) == true
                        || entity.deviceDomain?.lowercased().contains(normalizedQuery) == true
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
    /// The SF Symbol name to render instead of (or beside) the text when the
    /// selected unit is icon-based, or `nil` for plain text units.
    public let iconSymbolName: String?

    public init(text: String, status: EntityValueStatus, iconSymbolName: String? = nil) {
        self.text = text
        self.status = status
        self.iconSymbolName = iconSymbolName
    }
}

/// A dynamic-symbol unit family whose rendered SF Symbol is chosen by a
/// normalized fraction in `0...1`.
///
/// Each family owns a pure mapping from a fraction to an SF Symbol name plus a
/// short accessible description (for example `"battery 50%"`). The mapping is
/// deterministic at the documented boundaries (`0`, `0.2`, `0.5`, `0.8`, `1.0`).
public enum DynamicIconStyle: String, CaseIterable, Codable, Equatable, Sendable {
    case battery
    case signal
    case sound
    case brightness
    case thermometer

    /// The SF Symbol and accessible label chosen for a normalized fraction.
    ///
    /// - Parameter fraction: The value mapped into `0...1`. Values outside the
    ///   range are clamped before selection.
    /// - Returns: The chosen SF Symbol name and a human-readable description that
    ///   embeds the rounded percent (for example `"battery 50%"`).
    public func icon(for fraction: Double) -> DynamicIcon {
        let clamped = min(1.0, max(0.0, fraction))
        let percent = Int((clamped * 100).rounded())
        let symbol: String
        switch self {
        case .battery:
            symbol = switch clamped {
            case ..<0.125: "battery.0percent"
            case ..<0.375: "battery.25percent"
            case ..<0.625: "battery.50percent"
            case ..<0.875: "battery.75percent"
            default: "battery.100percent"
            }
            return DynamicIcon(symbolName: symbol, accessibleText: "battery \(percent)%")
        case .signal:
            symbol = switch clamped {
            case ..<0.125: "wifi.slash"
            case ..<0.375: "wifi.exclamationmark"
            case ..<0.75: "wifi"
            default: "wifi"
            }
            return DynamicIcon(symbolName: symbol, accessibleText: "signal \(percent)%")
        case .sound:
            symbol = switch clamped {
            case ..<0.125: "speaker.slash.fill"
            case ..<0.375: "speaker.wave.1.fill"
            case ..<0.75: "speaker.wave.2.fill"
            default: "speaker.wave.3.fill"
            }
            return DynamicIcon(symbolName: symbol, accessibleText: "volume \(percent)%")
        case .brightness:
            symbol = switch clamped {
            case ..<0.25: "sun.min"
            case ..<0.75: "sun.max"
            default: "sun.max.fill"
            }
            return DynamicIcon(symbolName: symbol, accessibleText: "brightness \(percent)%")
        case .thermometer:
            symbol = switch clamped {
            case ..<0.25: "thermometer.low"
            case ..<0.75: "thermometer.medium"
            default: "thermometer.high"
            }
            return DynamicIcon(symbolName: symbol, accessibleText: "temperature \(percent)%")
        }
    }
}

/// A chosen dynamic icon: the SF Symbol name plus an accessible description.
public struct DynamicIcon: Equatable, Sendable {
    /// The SF Symbol name to render as a template image.
    public let symbolName: String
    /// A short accessible description, for example `"battery 50%"`.
    public let accessibleText: String

    public init(symbolName: String, accessibleText: String) {
        self.symbolName = symbolName
        self.accessibleText = accessibleText
    }
}

/// Maps a raw numeric value into a normalized fraction in `0...1`.
///
/// Used by percentage- and icon-based units. When `minimum`/`maximum` are
/// provided and `maximum > minimum`, the value is rescaled as
/// `(value - minimum) / (maximum - minimum)` and clamped. When the bounds are
/// absent (or invalid), the value is assumed to already be on a `0...100`
/// percentage scale and is clamped to `0...1` after dividing by 100.
public enum NormalizedFraction {
    /// Resolves a normalized fraction for a raw value.
    ///
    /// - Parameters:
    ///   - value: The raw numeric value.
    ///   - minimum: The optional lower bound mapped to `0`.
    ///   - maximum: The optional upper bound mapped to `1`.
    /// - Returns: A fraction clamped to `0...1`.
    public static func resolve(value: Double, minimum: Double?, maximum: Double?) -> Double {
        if let minimum, let maximum, maximum > minimum {
            return clamp((value - minimum) / (maximum - minimum))
        }
        return clamp(value / 100.0)
    }

    private static func clamp(_ value: Double) -> Double {
        min(1.0, max(0.0, value))
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
    /// A plain number with the configured decimals and thousands grouping,
    /// keeping the Home Assistant unit. Large magnitudes (>= 10000) are SI
    /// compacted so `4054396` renders as `4.05M`.
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
    /// Interpret the raw value as bytes and render as B/KB/MB/GB/TB/PB (1024-based).
    case bytes
    /// Interpret the raw value as bytes per second and auto-scale (B/s..PB/s).
    case dataRate
    /// Interpret the raw value as lux and compact large magnitudes (suffix `lx`).
    case illuminance
    /// Interpret the raw value as watts and auto-scale W/kW/MW/GW.
    case power
    /// Interpret the raw value as watt-hours and auto-scale Wh/kWh/MWh/GWh.
    case energy
    /// Interpret the raw value as grams and auto-scale g/kg/t.
    case mass
    /// Interpret the raw value as seconds and render as a compact duration.
    case duration
    /// Render a battery glyph chosen by the value's normalized fraction.
    case batteryIcon
    /// Render a Wi-Fi/connection glyph chosen by the value's normalized fraction.
    case signalIcon
    /// Render a speaker glyph chosen by the value's normalized fraction.
    case soundIcon
    /// Render a sun glyph chosen by the value's normalized fraction.
    case brightnessIcon
    /// Render a thermometer glyph chosen by the value's normalized fraction.
    case thermometerIcon

    /// A human-friendly label for this unit, shown in the settings picker.
    public var displayName: String {
        switch self {
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
        case .dataRate:
            "Data rate"
        case .illuminance:
            "Illuminance (lx)"
        case .power:
            "Power (W)"
        case .energy:
            "Energy (Wh)"
        case .mass:
            "Mass (g)"
        case .duration:
            "Duration"
        case .batteryIcon:
            "Battery icon"
        case .signalIcon:
            "Signal icon"
        case .soundIcon:
            "Sound icon"
        case .brightnessIcon:
            "Brightness icon"
        case .thermometerIcon:
            "Thermometer icon"
        }
    }

    /// The dynamic-icon family this unit renders, when it is icon-based.
    public var iconStyle: DynamicIconStyle? {
        switch self {
        case .batteryIcon: .battery
        case .signalIcon: .signal
        case .soundIcon: .sound
        case .brightnessIcon: .brightness
        case .thermometerIcon: .thermometer
        default: nil
        }
    }

    /// Whether this unit maps the value into `0...1` (percentage or icon based),
    /// so the per-entity min/max bounds become relevant.
    public var usesNormalizedFraction: Bool {
        self == .percent || iconStyle != nil
    }

    /// The threshold at or above which `.number`/`.illuminance` compact a magnitude.
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
        explicitUnitSymbol: String? = nil,
        decimals: Int,
        showsUnit: Bool,
        formatter: NumberFormatter
    ) -> String {
        let unit = (haUnit?.isEmpty == false) ? haUnit : nil
        switch self {
        case .number:
            guard let value = rawNumericValue else {
                return rawState
            }
            if let autoScaled = Self.autoScaledValue(
                value,
                inputUnit: unit,
                explicitOutputUnit: explicitUnitSymbol,
                showsUnit: showsUnit
            ) {
                return autoScaled
            }
            let number = abs(value) >= Self.compactionThreshold
                ? Self.compacted(value)
                : (formatter.string(from: NSNumber(value: value)) ?? rawState)
            return Self.appendUnit(number, unit: unit, showsUnit: showsUnit)
        case .compact:
            guard let value = rawNumericValue else {
                return rawState
            }
            if let autoScaled = Self.autoScaledValue(
                value,
                inputUnit: unit,
                explicitOutputUnit: explicitUnitSymbol,
                showsUnit: showsUnit
            ) {
                return autoScaled
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
            return Self.autoScaledValue(value, inputUnit: unit, explicitOutputUnit: explicitUnitSymbol, showsUnit: showsUnit)
                ?? Self.bytes(value, showsUnit: showsUnit)
        case .dataRate:
            guard let value = rawNumericValue else {
                return rawState
            }
            return Self.autoScaledValue(value, inputUnit: unit, explicitOutputUnit: explicitUnitSymbol, showsUnit: showsUnit)
                ?? Self.dataRate(value, showsUnit: showsUnit)
        case .illuminance:
            guard let value = rawNumericValue else {
                return rawState
            }
            let number = abs(value) >= Self.compactionThreshold
                ? Self.compacted(value)
                : Self.trimmedNumber(value)
            return showsUnit ? "\(number) lx" : number
        case .power:
            guard let value = rawNumericValue else {
                return rawState
            }
            return Self.autoScaledValue(value, inputUnit: unit, explicitOutputUnit: explicitUnitSymbol, showsUnit: showsUnit)
                ?? Self.scaled(value, units: ["W", "kW", "MW", "GW", "TW"], factor: 1000, showsUnit: showsUnit)
        case .energy:
            guard let value = rawNumericValue else {
                return rawState
            }
            return Self.autoScaledValue(value, inputUnit: unit, explicitOutputUnit: explicitUnitSymbol, showsUnit: showsUnit)
                ?? Self.scaled(value, units: ["Wh", "kWh", "MWh", "GWh", "TWh"], factor: 1000, showsUnit: showsUnit)
        case .mass:
            guard let value = rawNumericValue else {
                return rawState
            }
            return Self.autoScaledValue(value, inputUnit: unit, explicitOutputUnit: explicitUnitSymbol, showsUnit: showsUnit)
                ?? Self.scaled(value, units: ["g", "kg", "t"], factor: 1000, showsUnit: showsUnit)
        case .duration:
            guard let value = rawNumericValue else {
                return rawState
            }
            return Self.duration(value, unit: unit)
        case .batteryIcon, .signalIcon, .soundIcon, .brightnessIcon, .thermometerIcon:
            // Icon units render through `icon(...)`; this text is the fallback
            // (the raw state) used when no numeric value is parseable.
            guard rawNumericValue != nil else {
                return rawState
            }
            return ""
        }
    }

    /// The chosen dynamic icon for an icon-based unit, or `nil` for text units
    /// or non-numeric states.
    ///
    /// - Parameters:
    ///   - rawNumericValue: The parsed numeric value, when the state is numeric.
    ///   - minValue: The optional lower bound mapped to the empty icon level.
    ///   - maxValue: The optional upper bound mapped to the full icon level.
    /// - Returns: The selected icon, or `nil` when this unit is not icon-based or
    ///   the value cannot be parsed.
    public func icon(
        rawNumericValue: Double?,
        minValue: Double?,
        maxValue: Double?
    ) -> DynamicIcon? {
        guard let style = iconStyle, let value = rawNumericValue else {
            return nil
        }
        let fraction = NormalizedFraction.resolve(value: value, minimum: minValue, maximum: maxValue)
        return style.icon(for: fraction)
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

    private struct MeasurementScale {
        let label: String
        let multiplierToBase: Double
    }

    private struct MeasurementFamily {
        let aliases: [String: Double]
        let outputs: [MeasurementScale]
    }

    private enum MeasurementFamilyKind {
        case power
    }

    private static let wattPowerFamily = MeasurementFamily(
        aliases: [
            "nW": 0.000_000_001, "uW": 0.000_001, "mW": 0.001, "W": 1, "kW": 1_000, "MW": 1_000_000, "GW": 1_000_000_000
        ],
        outputs: [
            MeasurementScale(label: "nW", multiplierToBase: 0.000_000_001),
            MeasurementScale(label: "µW", multiplierToBase: 0.000_001),
            MeasurementScale(label: "mW", multiplierToBase: 0.001),
            MeasurementScale(label: "W", multiplierToBase: 1),
            MeasurementScale(label: "kW", multiplierToBase: 1_000),
            MeasurementScale(label: "MW", multiplierToBase: 1_000_000),
            MeasurementScale(label: "GW", multiplierToBase: 1_000_000_000)
        ]
    )

    private static let apparentPowerFamily = MeasurementFamily(
        aliases: [
            "nVA": 0.000_000_001, "uVA": 0.000_001, "mVA": 0.001, "VA": 1, "kVA": 1_000, "MVA": 1_000_000, "GVA": 1_000_000_000
        ],
        outputs: [
            MeasurementScale(label: "nVA", multiplierToBase: 0.000_000_001),
            MeasurementScale(label: "µVA", multiplierToBase: 0.000_001),
            MeasurementScale(label: "mVA", multiplierToBase: 0.001),
            MeasurementScale(label: "VA", multiplierToBase: 1),
            MeasurementScale(label: "kVA", multiplierToBase: 1_000),
            MeasurementScale(label: "MVA", multiplierToBase: 1_000_000),
            MeasurementScale(label: "GVA", multiplierToBase: 1_000_000_000)
        ]
    )

    private static let reactivePowerFamily = MeasurementFamily(
        aliases: [
            "nvar": 0.000_000_001, "uvar": 0.000_001, "mvar": 0.001, "var": 1, "kvar": 1_000, "Mvar": 1_000_000, "Gvar": 1_000_000_000
        ],
        outputs: [
            MeasurementScale(label: "nvar", multiplierToBase: 0.000_000_001),
            MeasurementScale(label: "µvar", multiplierToBase: 0.000_001),
            MeasurementScale(label: "mvar", multiplierToBase: 0.001),
            MeasurementScale(label: "var", multiplierToBase: 1),
            MeasurementScale(label: "kvar", multiplierToBase: 1_000),
            MeasurementScale(label: "Mvar", multiplierToBase: 1_000_000),
            MeasurementScale(label: "Gvar", multiplierToBase: 1_000_000_000)
        ]
    )

    private static let energyFamily = MeasurementFamily(
        aliases: [
            "nWh": 0.000_000_001, "uWh": 0.000_001, "mWh": 0.001, "Wh": 1, "kWh": 1_000, "MWh": 1_000_000, "GWh": 1_000_000_000
        ],
        outputs: [
            MeasurementScale(label: "nWh", multiplierToBase: 0.000_000_001),
            MeasurementScale(label: "µWh", multiplierToBase: 0.000_001),
            MeasurementScale(label: "mWh", multiplierToBase: 0.001),
            MeasurementScale(label: "Wh", multiplierToBase: 1),
            MeasurementScale(label: "kWh", multiplierToBase: 1_000),
            MeasurementScale(label: "MWh", multiplierToBase: 1_000_000),
            MeasurementScale(label: "GWh", multiplierToBase: 1_000_000_000)
        ]
    )

    private static let massFamily = MeasurementFamily(
        aliases: [
            "ng": 0.000_000_001, "ug": 0.000_001, "mg": 0.001, "g": 1, "kg": 1_000, "t": 1_000_000, "kt": 1_000_000_000
        ],
        outputs: [
            MeasurementScale(label: "ng", multiplierToBase: 0.000_000_001),
            MeasurementScale(label: "µg", multiplierToBase: 0.000_001),
            MeasurementScale(label: "mg", multiplierToBase: 0.001),
            MeasurementScale(label: "g", multiplierToBase: 1),
            MeasurementScale(label: "kg", multiplierToBase: 1_000),
            MeasurementScale(label: "t", multiplierToBase: 1_000_000),
            MeasurementScale(label: "kt", multiplierToBase: 1_000_000_000)
        ]
    )

    private static let currentFamily = MeasurementFamily(
        aliases: ["nA": 0.000_000_001, "uA": 0.000_001, "mA": 0.001, "A": 1, "kA": 1_000, "MA": 1_000_000, "GA": 1_000_000_000],
        outputs: [
            MeasurementScale(label: "nA", multiplierToBase: 0.000_000_001),
            MeasurementScale(label: "µA", multiplierToBase: 0.000_001),
            MeasurementScale(label: "mA", multiplierToBase: 0.001),
            MeasurementScale(label: "A", multiplierToBase: 1),
            MeasurementScale(label: "kA", multiplierToBase: 1_000),
            MeasurementScale(label: "MA", multiplierToBase: 1_000_000),
            MeasurementScale(label: "GA", multiplierToBase: 1_000_000_000)
        ]
    )

    private static let voltageFamily = MeasurementFamily(
        aliases: ["nV": 0.000_000_001, "uV": 0.000_001, "mV": 0.001, "V": 1, "kV": 1_000, "MV": 1_000_000, "GV": 1_000_000_000],
        outputs: [
            MeasurementScale(label: "nV", multiplierToBase: 0.000_000_001),
            MeasurementScale(label: "µV", multiplierToBase: 0.000_001),
            MeasurementScale(label: "mV", multiplierToBase: 0.001),
            MeasurementScale(label: "V", multiplierToBase: 1),
            MeasurementScale(label: "kV", multiplierToBase: 1_000),
            MeasurementScale(label: "MV", multiplierToBase: 1_000_000),
            MeasurementScale(label: "GV", multiplierToBase: 1_000_000_000)
        ]
    )

    private static let frequencyFamily = MeasurementFamily(
        aliases: ["nHz": 0.000_000_001, "uHz": 0.000_001, "mHz": 0.001, "Hz": 1, "kHz": 1_000, "MHz": 1_000_000, "GHz": 1_000_000_000],
        outputs: [
            MeasurementScale(label: "nHz", multiplierToBase: 0.000_000_001),
            MeasurementScale(label: "µHz", multiplierToBase: 0.000_001),
            MeasurementScale(label: "mHz", multiplierToBase: 0.001),
            MeasurementScale(label: "Hz", multiplierToBase: 1),
            MeasurementScale(label: "kHz", multiplierToBase: 1_000),
            MeasurementScale(label: "MHz", multiplierToBase: 1_000_000),
            MeasurementScale(label: "GHz", multiplierToBase: 1_000_000_000)
        ]
    )

    private static let volumeFamily = MeasurementFamily(
        aliases: ["nL": 0.000_000_001, "uL": 0.000_001, "mL": 0.001, "L": 1, "kL": 1_000, "ML": 1_000_000, "GL": 1_000_000_000],
        outputs: [
            MeasurementScale(label: "nL", multiplierToBase: 0.000_000_001),
            MeasurementScale(label: "µL", multiplierToBase: 0.000_001),
            MeasurementScale(label: "mL", multiplierToBase: 0.001),
            MeasurementScale(label: "L", multiplierToBase: 1),
            MeasurementScale(label: "kL", multiplierToBase: 1_000),
            MeasurementScale(label: "ML", multiplierToBase: 1_000_000),
            MeasurementScale(label: "GL", multiplierToBase: 1_000_000_000)
        ]
    )

    private static let pressureFamily = MeasurementFamily(
        aliases: [
            "nPa": 0.000_000_001, "uPa": 0.000_001, "mPa": 0.001, "Pa": 1, "hPa": 100, "kPa": 1_000,
            "MPa": 1_000_000, "GPa": 1_000_000_000, "mbar": 100, "bar": 100_000
        ],
        outputs: [
            MeasurementScale(label: "nPa", multiplierToBase: 0.000_000_001),
            MeasurementScale(label: "µPa", multiplierToBase: 0.000_001),
            MeasurementScale(label: "mPa", multiplierToBase: 0.001),
            MeasurementScale(label: "Pa", multiplierToBase: 1),
            MeasurementScale(label: "hPa", multiplierToBase: 100),
            MeasurementScale(label: "kPa", multiplierToBase: 1_000),
            MeasurementScale(label: "MPa", multiplierToBase: 1_000_000),
            MeasurementScale(label: "GPa", multiplierToBase: 1_000_000_000)
        ]
    )

    private static let storageFamily = MeasurementFamily(
        aliases: [
            "B": 1, "KB": 1_024, "MB": 1_048_576, "GB": 1_073_741_824, "TB": 1_099_511_627_776,
            "PB": 1_125_899_906_842_624, "EB": 1_152_921_504_606_846_976,
            "KiB": 1_024, "MiB": 1_048_576, "GiB": 1_073_741_824, "TiB": 1_099_511_627_776,
            "PiB": 1_125_899_906_842_624, "EiB": 1_152_921_504_606_846_976
        ],
        outputs: [
            MeasurementScale(label: "B", multiplierToBase: 1),
            MeasurementScale(label: "KB", multiplierToBase: 1_024),
            MeasurementScale(label: "MB", multiplierToBase: 1_048_576),
            MeasurementScale(label: "GB", multiplierToBase: 1_073_741_824),
            MeasurementScale(label: "TB", multiplierToBase: 1_099_511_627_776),
            MeasurementScale(label: "PB", multiplierToBase: 1_125_899_906_842_624),
            MeasurementScale(label: "EB", multiplierToBase: 1_152_921_504_606_846_976)
        ]
    )

    private static let dataRateFamily = MeasurementFamily(
        aliases: [
            "B/s": 1, "KB/s": 1_024, "MB/s": 1_048_576, "GB/s": 1_073_741_824, "TB/s": 1_099_511_627_776,
            "PB/s": 1_125_899_906_842_624, "KiB/s": 1_024, "MiB/s": 1_048_576, "GiB/s": 1_073_741_824,
            "TiB/s": 1_099_511_627_776, "PiB/s": 1_125_899_906_842_624
        ],
        outputs: [
            MeasurementScale(label: "B/s", multiplierToBase: 1),
            MeasurementScale(label: "KB/s", multiplierToBase: 1_024),
            MeasurementScale(label: "MB/s", multiplierToBase: 1_048_576),
            MeasurementScale(label: "GB/s", multiplierToBase: 1_073_741_824),
            MeasurementScale(label: "TB/s", multiplierToBase: 1_099_511_627_776),
            MeasurementScale(label: "PB/s", multiplierToBase: 1_125_899_906_842_624)
        ]
    )

    private static let concentrationMassFamily = MeasurementFamily(
        aliases: ["ng/m³": 0.000_000_001, "ug/m³": 0.000_001, "mg/m³": 0.001, "g/m³": 1, "kg/m³": 1_000],
        outputs: [
            MeasurementScale(label: "ng/m³", multiplierToBase: 0.000_000_001),
            MeasurementScale(label: "µg/m³", multiplierToBase: 0.000_001),
            MeasurementScale(label: "mg/m³", multiplierToBase: 0.001),
            MeasurementScale(label: "g/m³", multiplierToBase: 1),
            MeasurementScale(label: "kg/m³", multiplierToBase: 1_000)
        ]
    )

    private static let partsFamily = MeasurementFamily(
        aliases: ["ppb": 1, "ppm": 1_000],
        outputs: [
            MeasurementScale(label: "ppb", multiplierToBase: 1),
            MeasurementScale(label: "ppm", multiplierToBase: 1_000)
        ]
    )

    fileprivate static func normalizedUnitToken(_ unit: String?) -> String? {
        guard let unit = unit?.trimmingCharacters(in: .whitespacesAndNewlines), !unit.isEmpty else {
            return nil
        }
        return unit
            .replacingOccurrences(of: "µ", with: "u")
            .replacingOccurrences(of: "μ", with: "u")
            .replacingOccurrences(of: " ", with: "")
    }

    private static func family(for unit: String?) -> MeasurementFamily? {
        guard let normalized = normalizedUnitToken(unit) else {
            return nil
        }
        let families = [
            wattPowerFamily, apparentPowerFamily, reactivePowerFamily, energyFamily, massFamily,
            currentFamily, voltageFamily, frequencyFamily, volumeFamily, pressureFamily,
            storageFamily, dataRateFamily, concentrationMassFamily, partsFamily
        ]
        return families.first { $0.aliases[normalized] != nil }
    }

    private static func family(_ kind: MeasurementFamilyKind) -> MeasurementFamily {
        switch kind {
        case .power:
            wattPowerFamily
        }
    }

    fileprivate static func isPowerLikeUnit(_ normalized: String) -> Bool {
        [wattPowerFamily, apparentPowerFamily, reactivePowerFamily].contains { $0.aliases[normalized] != nil }
    }

    fileprivate static func isEnergyLikeUnit(_ normalized: String) -> Bool {
        energyFamily.aliases[normalized] != nil
    }

    fileprivate static func isMassLikeUnit(_ normalized: String) -> Bool {
        massFamily.aliases[normalized] != nil
    }

    private static func autoScaledValue(
        _ value: Double,
        inputUnit: String?,
        explicitOutputUnit: String? = nil,
        family forcedFamily: MeasurementFamilyKind? = nil,
        showsUnit: Bool
    ) -> String? {
        let family = family(for: inputUnit) ?? forcedFamily.map(family(_:))
        guard let family else {
            return nil
        }
        let normalized = normalizedUnitToken(inputUnit)
        let sourceMultiplier = normalized.flatMap { family.aliases[$0] } ?? family.outputs[0].multiplierToBase
        let baseValue = value * sourceMultiplier
        let magnitude = abs(baseValue)
        let preferredScale: MeasurementScale
        if let explicitOutputUnit,
           let explicitNormalized = normalizedUnitToken(explicitOutputUnit),
           let explicitMultiplier = family.aliases[explicitNormalized] {
            preferredScale = family.outputs.first(where: { $0.multiplierToBase == explicitMultiplier }) ?? MeasurementScale(
                label: explicitOutputUnit,
                multiplierToBase: explicitMultiplier
            )
        } else if magnitude == 0 {
            preferredScale = family.outputs.first(where: { $0.multiplierToBase == sourceMultiplier }) ?? family.outputs[0]
        } else {
            preferredScale = family.outputs.last(where: { magnitude >= $0.multiplierToBase }) ?? family.outputs[0]
        }
        let scaledValue = baseValue / preferredScale.multiplierToBase
        let rounded = preferredScale.multiplierToBase == sourceMultiplier
            ? scaledValue
            : (scaledValue * 100).rounded() / 100
        let number = trimmedNumber(rounded)
        return showsUnit ? "\(number) \(preferredScale.label)" : number
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

    /// Renders raw bytes as B/KB/MB/GB/TB/PB (1024-based) to two decimals.
    static func bytes(_ value: Double, showsUnit: Bool) -> String {
        binaryScaled(value, units: ["B", "KB", "MB", "GB", "TB", "PB"], showsUnit: showsUnit)
    }

    /// Renders raw bytes-per-second as B/s..PB/s (1024-based) to two decimals.
    static func dataRate(_ value: Double, showsUnit: Bool) -> String {
        binaryScaled(value, units: ["B/s", "KB/s", "MB/s", "GB/s", "TB/s", "PB/s"], showsUnit: showsUnit)
    }

    /// Auto-scales a magnitude across 1024-based units, keeping the first unit
    /// exact and rounding scaled magnitudes to two decimals.
    private static func binaryScaled(_ value: Double, units: [String], showsUnit: Bool) -> String {
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

    /// Auto-scales a magnitude across decimal-factor units (for example watts to
    /// W/kW/MW), rounding scaled magnitudes to two decimals.
    ///
    /// - Parameters:
    ///   - value: The raw value in the smallest unit.
    ///   - units: The ordered unit labels, smallest first.
    ///   - factor: The step between adjacent units (for example `1000`).
    ///   - showsUnit: Whether to append the chosen unit label.
    /// - Returns: The scaled value with an optional unit suffix.
    static func scaled(_ value: Double, units: [String], factor: Double, showsUnit: Bool) -> String {
        var magnitude = abs(value)
        var index = 0
        while magnitude >= factor, index < units.count - 1 {
            magnitude /= factor
            index += 1
        }
        let signed = value < 0 ? -magnitude : magnitude
        let number = index == 0 ? trimmedNumber(signed) : trimmedNumber((signed * 100).rounded() / 100)
        return showsUnit ? "\(number) \(units[index])" : number
    }

    /// Renders seconds as a compact human duration (for example `1h 2m`).
    static func duration(_ value: Double, unit: String? = nil) -> String {
        let secondsPerUnit: Double
        switch normalizedUnitToken(unit) {
        case "ms":
            secondsPerUnit = 0.001
        case "min":
            secondsPerUnit = 60
        case "h":
            secondsPerUnit = 3_600
        default:
            secondsPerUnit = 1
        }
        let total = Int((abs(value) * secondsPerUnit).rounded())
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

/// Resolves shared averaging families for compatible numeric entities.
///
/// A family is stored symmetrically on every participating entity's display
/// configuration and always includes the entity itself. Rendering uses the
/// current numeric readings of every compatible available member; unavailable
/// or non-numeric members simply drop out of the live average instead of
/// blanking the whole value.
public enum PerchHAEntityAveraging {
    /// The family ids stored for an entity, normalized to always include the
    /// entity itself when averaging is active.
    public static func familyIDs(for entityID: EntityID, configuration: MenuBarItemConfiguration) -> [EntityID] {
        var seen: Set<EntityID> = [entityID]
        var ordered: [EntityID] = [entityID]
        for id in configuration.averageEntityIDs where !seen.contains(id) {
            seen.insert(id)
            ordered.append(id)
        }
        return ordered.count > 1 ? ordered : [entityID]
    }

    /// Whether two entities are eligible to share one average family.
    public static func areCompatible(_ source: DiscoveredEntity, _ target: DiscoveredEntity) -> Bool {
        guard source.id != target.id,
              let sourceUnit = normalizedUnit(source.unit),
              sourceUnit == normalizedUnit(target.unit)
        else {
            return false
        }
        return isPotentiallyNumeric(source) && isPotentiallyNumeric(target)
    }

    /// The entity value to render after applying the shared average family, or
    /// the base entity unchanged when no active family contributes a numeric
    /// average right now.
    public static func averagedEntity(
        base: DiscoveredEntity,
        configuration: MenuBarItemConfiguration,
        availableEntities: [DiscoveredEntity]
    ) -> DiscoveredEntity {
        let family = familyMembers(
            for: base,
            configuration: configuration,
            availableEntities: availableEntities
        )
        guard family.count > 1 else {
            return base
        }
        let numericMembers = family.compactMap { numericState($0.state) }
        guard !numericMembers.isEmpty else {
            return base
        }
        let average = numericMembers.reduce(0, +) / Double(numericMembers.count)
        return DiscoveredEntity(
            id: base.id,
            name: base.name,
            state: String(average),
            unit: base.unit,
            areaID: base.areaID,
            deviceID: base.deviceID,
            deviceName: base.deviceName,
            deviceManufacturer: base.deviceManufacturer,
            deviceModel: base.deviceModel,
            deviceDomain: base.deviceDomain,
            currentPosition: base.currentPosition
        )
    }

    /// The concrete compatible members currently in an entity's family.
    public static func familyMembers(
        for base: DiscoveredEntity,
        configuration: MenuBarItemConfiguration,
        availableEntities: [DiscoveredEntity]
    ) -> [DiscoveredEntity] {
        let ids = familyIDs(for: base.id, configuration: configuration)
        guard ids.count > 1 else {
            return [base]
        }
        let entitiesByID = Dictionary(uniqueKeysWithValues: availableEntities.map { ($0.id, $0) })
        var seen: Set<EntityID> = []
        var resolved: [DiscoveredEntity] = []
        for id in ids {
            let entity = entitiesByID[id] ?? (id == base.id ? base : nil)
            guard let entity else {
                continue
            }
            guard entity.id == base.id || areCompatible(base, entity) else {
                continue
            }
            guard !seen.contains(entity.id) else {
                continue
            }
            seen.insert(entity.id)
            resolved.append(entity)
        }
        return resolved.count > 1 ? resolved : [base]
    }

    private static func isPotentiallyNumeric(_ entity: DiscoveredEntity) -> Bool {
        if numericState(entity.state) != nil {
            return true
        }
        return normalizedUnit(entity.unit) != nil
    }

    private static func numericState(_ state: String) -> Double? {
        Double(state.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private static func normalizedUnit(_ unit: String?) -> String? {
        let trimmed = unit?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let trimmed, !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }
}

public struct EntityValueFormatter: Sendable {
    public let localeIdentifier: String
    public let maximumFractionDigits: Int
    /// The explicitly selected unit, or `nil` to use the detected default.
    public let displayUnit: ValueUnit?
    /// The explicit target symbol within the chosen family, or `nil` for auto.
    public let displayUnitSymbol: String?
    public let showsUnit: Bool
    /// The optional lower bound for percentage/icon normalization.
    public let minValue: Double?
    /// The optional upper bound for percentage/icon normalization.
    public let maxValue: Double?

    public init(
        locale: Locale = .current,
        maximumFractionDigits: Int = 2,
        displayUnit: ValueUnit? = nil,
        displayUnitSymbol: String? = nil,
        showsUnit: Bool = true,
        minValue: Double? = nil,
        maxValue: Double? = nil
    ) {
        self.localeIdentifier = locale.identifier
        self.maximumFractionDigits = max(0, maximumFractionDigits)
        self.displayUnit = displayUnit
        self.displayUnitSymbol = displayUnitSymbol
        self.showsUnit = showsUnit
        self.minValue = minValue
        self.maxValue = maxValue
    }

    public func format(_ entity: DiscoveredEntity, isStale: Bool = false) -> FormattedEntityValue {
        let normalizedState = entity.state.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if normalizedState == "unavailable" {
            return FormattedEntityValue(text: "Unavailable", status: .unavailable)
        }
        if normalizedState == "unknown" {
            return FormattedEntityValue(text: "Unknown", status: .unknown)
        }

        let trimmedState = entity.state.trimmingCharacters(in: .whitespacesAndNewlines)
        let numeric = Decimal(string: trimmedState, locale: Locale(identifier: "en_US_POSIX"))
            .map { NSDecimalNumber(decimal: $0).doubleValue }
        let unit = EntityDisplayDefaults.effectiveUnit(displayUnit, entity: entity)
        let icon = unit.icon(rawNumericValue: numeric, minValue: minValue, maxValue: maxValue)
        let value = valueText(
            unit: unit,
            unitSymbol: displayUnitSymbol,
            numeric: numeric,
            trimmedState: trimmedState,
            haUnit: entity.unit
        )
        let text = icon?.accessibleText ?? value
        if isStale {
            return FormattedEntityValue(text: "Stale: \(text)", status: .stale, iconSymbolName: icon?.symbolName)
        }
        return FormattedEntityValue(text: text, status: .available, iconSymbolName: icon?.symbolName)
    }

    private func valueText(unit: ValueUnit, unitSymbol: String?, numeric: Double?, trimmedState: String, haUnit: String?) -> String {
        let resolvedUnit = haUnit?.trimmingCharacters(in: .whitespacesAndNewlines)
        return unit.display(
            rawNumericValue: numeric,
            rawState: trimmedState,
            haUnit: resolvedUnit,
            explicitUnitSymbol: unitSymbol,
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
            maximumFractionDigits: defaultMaximumFractionDigits(for: entity),
            thresholds: defaultThresholds(for: entity),
            coverControlMode: .both,
            displayUnit: nil
        )
    }

    /// The default fraction digits for an entity's rendered numeric value.
    ///
    /// The current product default is one decimal place across numeric entities;
    /// users can always override this per entity.
    public static func defaultMaximumFractionDigits(for entity: DiscoveredEntity) -> Int {
        1
    }

    /// The default threshold palette for an entity, when one is known.
    ///
    /// Temperature entities start with a cool-to-hot scale. Other metrics keep
    /// an empty threshold set until we have a clear semantic default.
    public static func defaultThresholds(
        for entity: DiscoveredEntity,
        selectedUnit: ValueUnit? = nil
    ) -> ValueThresholds {
        switch effectiveUnit(selectedUnit, entity: entity) {
        case .celsius:
            return ValueThresholds(
                steps: [
                    ThresholdStep(value: 18, color: comfortCoolColor),
                    ThresholdStep(value: 21, color: ValueThresholds.okColor),
                    ThresholdStep(value: 25, color: ValueThresholds.warningColor),
                    ThresholdStep(value: 28, color: ValueThresholds.criticalColor)
                ],
                baseColor: comfortColdColor
            )
        case .fahrenheit:
            return ValueThresholds(
                steps: [
                    ThresholdStep(value: 64, color: comfortCoolColor),
                    ThresholdStep(value: 70, color: ValueThresholds.okColor),
                    ThresholdStep(value: 77, color: ValueThresholds.warningColor),
                    ThresholdStep(value: 82, color: ValueThresholds.criticalColor)
                ],
                baseColor: comfortColdColor
            )
        case .percent where isHumidityLike(entity):
            return ValueThresholds(
                steps: [
                    ThresholdStep(value: 35, color: comfortCoolColor),
                    ThresholdStep(value: 40, color: ValueThresholds.okColor),
                    ThresholdStep(value: 60, color: ValueThresholds.warningColor),
                    ThresholdStep(value: 70, color: ValueThresholds.criticalColor)
                ],
                baseColor: ValueThresholds.warningColor
            )
        case .power:
            return ValueThresholds(
                steps: [
                    ThresholdStep(value: 150, color: comfortCoolColor),
                    ThresholdStep(value: 500, color: ValueThresholds.warningColor),
                    ThresholdStep(value: 1_200, color: ValueThresholds.criticalColor)
                ],
                baseColor: ValueThresholds.okColor
            )
        default:
            if isPM25Like(entity) {
                return ValueThresholds(
                    steps: [
                        ThresholdStep(value: 12, color: comfortCoolColor),
                        ThresholdStep(value: 35, color: ValueThresholds.warningColor),
                        ThresholdStep(value: 55, color: ValueThresholds.criticalColor)
                    ],
                    baseColor: ValueThresholds.okColor
                )
            }
            if isCO2Like(entity) {
                return ValueThresholds(
                    steps: [
                        ThresholdStep(value: 800, color: comfortCoolColor),
                        ThresholdStep(value: 1_000, color: ValueThresholds.warningColor),
                        ThresholdStep(value: 1_400, color: ValueThresholds.criticalColor)
                    ],
                    baseColor: ValueThresholds.okColor
                )
            }
            if isBatteryLike(entity) || isFilterPercentLike(entity) {
                return ValueThresholds(
                    steps: [
                        ThresholdStep(value: 20, color: ValueThresholds.warningColor),
                        ThresholdStep(value: 35, color: comfortCoolColor),
                        ThresholdStep(value: 60, color: ValueThresholds.okColor)
                    ],
                    baseColor: ValueThresholds.criticalColor
                )
            }
            if isRSSILike(entity) {
                return ValueThresholds(
                    steps: [
                        ThresholdStep(value: -80, color: ValueThresholds.warningColor),
                        ThresholdStep(value: -67, color: ValueThresholds.okColor)
                    ],
                    baseColor: ValueThresholds.criticalColor
                )
            }
            return ValueThresholds()
        }
    }

    /// Whether a threshold set carries any explicit styling information.
    public static func hasThresholds(_ thresholds: ValueThresholds) -> Bool {
        thresholds.baseColor != nil || thresholds.steps.isEmpty == false
    }

    /// The thresholds an entity should currently use, falling back to known
    /// defaults when no explicit custom thresholds were stored yet.
    public static func effectiveThresholds(
        for entity: DiscoveredEntity,
        configuration: MenuBarItemConfiguration
    ) -> ValueThresholds {
        let defaults = defaultThresholds(for: entity, selectedUnit: configuration.displayUnit)
        guard hasThresholds(defaults) else {
            return configuration.thresholds
        }
        if configuration.thresholds.steps.isEmpty, defaults.steps.isEmpty == false {
            return ValueThresholds(
                steps: defaults.steps,
                baseColor: configuration.thresholds.baseColor ?? defaults.baseColor
            )
        }
        if hasThresholds(configuration.thresholds) {
            return configuration.thresholds
        }
        return defaults
    }

    /// Repairs a stored item configuration using the entity's current metadata.
    ///
    /// Legacy configs may have persisted `.number` as an explicit display unit
    /// before the app learned to auto-detect better units, and they may carry
    /// an empty threshold payload even though the entity now has a known default
    /// threshold palette. This helper rewrites those stale fields into the
    /// effective configuration the app should actually use today.
    ///
    /// - Parameters:
    ///   - entity: The live entity metadata.
    ///   - configuration: The stored item configuration.
    /// - Returns: A normalized configuration value.
    public static func normalizedConfiguration(
        for entity: DiscoveredEntity,
        configuration: MenuBarItemConfiguration
    ) -> MenuBarItemConfiguration {
        var normalized = configuration
        let detectedUnit = detectedUnit(for: entity)
        if normalized.displayUnit == .number,
           normalized.displayUnitSymbol == nil,
           detectedUnit != .number,
           normalized.minValue == nil,
           normalized.maxValue == nil,
           normalized.absoluteTotal == nil,
           normalized.totalEntityID == nil {
            normalized = normalized.settingDisplayUnit(nil)
        }
        let effectiveThresholds = effectiveThresholds(for: entity, configuration: normalized)
        if normalized.thresholds != effectiveThresholds {
            normalized = normalized.settingThresholds(effectiveThresholds)
        }
        if shouldRepairLegacyMaximumFractionDigits(normalized, entity: entity) {
            normalized = normalized.updating(
                maximumFractionDigits: defaultMaximumFractionDigits(for: entity)
            )
        }
        return normalized
    }

    private static func shouldRepairLegacyMaximumFractionDigits(
        _ configuration: MenuBarItemConfiguration,
        entity: DiscoveredEntity
    ) -> Bool {
        guard configuration.maximumFractionDigits == 0 else {
            return false
        }
        guard defaultMaximumFractionDigits(for: entity) != 0 else {
            return false
        }
        let defaultConfiguration = Self.configuration(for: entity)
        return configuration.style == defaultConfiguration.style
            && configuration.appearance == defaultConfiguration.appearance
            && configuration.showsLabel == defaultConfiguration.showsLabel
            && configuration.showsUnit == defaultConfiguration.showsUnit
            && configuration.absoluteTotal == defaultConfiguration.absoluteTotal
            && configuration.totalEntityID == defaultConfiguration.totalEntityID
            && configuration.averageEntityIDs == defaultConfiguration.averageEntityIDs
            && configuration.thresholds == defaultConfiguration.thresholds
            && configuration.defaultHistoryRange == defaultConfiguration.defaultHistoryRange
            && configuration.coverControlMode == defaultConfiguration.coverControlMode
            && configuration.displayUnit == defaultConfiguration.displayUnit
            && configuration.displayUnitSymbol == defaultConfiguration.displayUnitSymbol
            && configuration.minValue == defaultConfiguration.minValue
            && configuration.maxValue == defaultConfiguration.maxValue
            && configuration.showsEntityIcon == defaultConfiguration.showsEntityIcon
            && configuration.customIconName == defaultConfiguration.customIconName
    }

    /// The concrete display unit detected from an entity's HA unit and state.
    ///
    /// - Parameters:
    ///   - haUnit: The reported Home Assistant unit, if any.
    ///   - state: The current state string (unused today, reserved for future
    ///     value-shape detection).
    /// - Returns: `.percent` for `%`, the matching temperature scale, `.bytes`
    ///   for byte units, concrete families for illuminance/power/energy/mass/
    ///   duration, and `.number` otherwise.
    public static func detectedUnit(haUnit: String?, state: String = "") -> ValueUnit {
        let trimmed = haUnit?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let trimmed, !trimmed.isEmpty else {
            return .number
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
        let normalized = ValueUnit.normalizedUnitToken(trimmed) ?? trimmed
        if isByteUnit(normalized) {
            return .bytes
        }
        if isByteRateUnit(normalized) {
            return .dataRate
        }
        if ValueUnit.isPowerLikeUnit(normalized) {
            return .power
        }
        if ValueUnit.isEnergyLikeUnit(normalized) {
            return .energy
        }
        if ValueUnit.isMassLikeUnit(normalized) {
            return .mass
        }
        switch normalized.lowercased() {
        case "lx":
            return .illuminance
        case "s", "sec", "secs", "second", "seconds", "ms", "min", "h":
            return .duration
        default:
            break
        }
        return .number
    }

    /// Domain-aware detected unit for a discovered entity.
    public static func detectedUnit(for entity: DiscoveredEntity) -> ValueUnit {
        detectedUnit(haUnit: entity.unit, state: entity.state)
    }

    /// Resolves the unit to render with: the explicit selection, or the detected
    /// default when none is set.
    ///
    /// - Parameters:
    ///   - selected: The explicitly chosen unit, or `nil`.
    ///   - haUnit: The reported Home Assistant unit, if any.
    ///   - state: The current state string.
    /// - Returns: A concrete `ValueUnit`.
    public static func effectiveUnit(_ selected: ValueUnit?, haUnit: String?, state: String = "") -> ValueUnit {
        selected ?? detectedUnit(haUnit: haUnit, state: state)
    }

    /// Resolves the unit to render with for a concrete entity.
    public static func effectiveUnit(_ selected: ValueUnit?, entity: DiscoveredEntity) -> ValueUnit {
        selected ?? detectedUnit(for: entity)
    }

    private static func isByteUnit(_ normalized: String) -> Bool {
        let byteUnits: Set<String> = [
            "B", "KB", "MB", "GB", "TB", "PB",
            "EB", "KiB", "MiB", "GiB", "TiB", "PiB", "EiB",
            "BYTE", "BYTES"
        ]
        return byteUnits.contains(normalized)
    }

    private static func isByteRateUnit(_ normalized: String) -> Bool {
        let byteRateUnits: Set<String> = [
            "B/s", "KB/s", "MB/s", "GB/s", "TB/s", "PB/s", "EB/s",
            "KiB/s", "MiB/s", "GiB/s", "TiB/s", "PiB/s", "EiB/s"
        ]
        return byteRateUnits.contains(normalized)
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

    private static func isHumidityLike(_ entity: DiscoveredEntity) -> Bool {
        let name = entity.name.lowercased()
        let id = entity.id.rawValue.lowercased()
        return entity.unit?.trimmingCharacters(in: .whitespacesAndNewlines) == "%"
            && (name.contains("humidity") || name.contains("luftfeuchtigkeit") || id.contains("humidity"))
    }

    private static func isPM25Like(_ entity: DiscoveredEntity) -> Bool {
        let name = entity.name.lowercased()
        let id = entity.id.rawValue.lowercased()
        let unit = entity.unit?.lowercased() ?? ""
        return name.contains("pm2.5")
            || name.contains("pm25")
            || id.contains("pm2_5")
            || id.contains("pm25")
            || unit.contains("ug/m")
            || unit.contains("µg/m")
    }

    private static func isCO2Like(_ entity: DiscoveredEntity) -> Bool {
        let name = entity.name.lowercased()
        let id = entity.id.rawValue.lowercased()
        let unit = entity.unit?.lowercased() ?? ""
        return name.contains("co2") || id.contains("co2") || unit == "ppm"
    }

    private static func isFilterPercentLike(_ entity: DiscoveredEntity) -> Bool {
        let name = entity.name.lowercased()
        let id = entity.id.rawValue.lowercased()
        return entity.unit?.trimmingCharacters(in: .whitespacesAndNewlines) == "%"
            && (name.contains("filter") || id.contains("filter"))
    }

    private static func isRSSILike(_ entity: DiscoveredEntity) -> Bool {
        let name = entity.name.lowercased()
        let id = entity.id.rawValue.lowercased()
        let unit = entity.unit?.lowercased() ?? ""
        return name.contains("rssi") || id.contains("rssi") || unit == "dbm"
    }

    private static let comfortColdColor = PerchHAAccentColor(red: 0.19, green: 0.49, blue: 0.96, alpha: 1)
    private static let comfortCoolColor = PerchHAAccentColor(red: 0.12, green: 0.72, blue: 0.83, alpha: 1)
}
