import Foundation
import PerchHASupport

public struct EntityID: Hashable, Codable, Sendable, ExpressibleByStringLiteral {
    public let rawValue: String

    public init(_ rawValue: String) {
        self.rawValue = rawValue
    }

    public init(stringLiteral value: StringLiteralType) {
        self.init(value)
    }

    public init(from decoder: Decoder) throws {
        rawValue = try decoder.singleValueContainer().decode(String.self)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    public var domain: String {
        rawValue.split(separator: ".", maxSplits: 1).first.map(String.init) ?? rawValue
    }
}

public enum ConnectionState: Equatable, Sendable {
    case disconnected
    case connecting
    case connected
    case reconnecting(attempt: Int)
    case failed(ConnectionFailure)
}

public enum ConnectionFailure: Equatable, Sendable {
    case authentication
    case unreachable(host: String)
    case tlsRejected(host: String)
    case unsupportedCommand(String)
    case protocolError(String)
}

public struct EntityState: Equatable, Codable, Sendable {
    public let id: EntityID
    public let name: String
    public let state: String
    public let unit: String?
    public let currentPosition: Int?

    public init(id: EntityID, name: String, state: String, unit: String?, currentPosition: Int? = nil) {
        self.id = id
        self.name = name
        self.state = state
        self.unit = unit
        self.currentPosition = currentPosition
    }
}

public struct HistorySample: Equatable, Codable, Sendable {
    public let timestamp: Date
    public let state: String
    public let numericValue: Double?

    public init(timestamp: Date, state: String, numericValue: Double?) {
        self.timestamp = timestamp
        self.state = state
        self.numericValue = numericValue
    }
}

public struct HistorySeries: Equatable, Codable, Sendable {
    public let entityID: EntityID
    public let range: HistoryRange
    public let samples: [HistorySample]

    public init(entityID: EntityID, range: HistoryRange, samples: [HistorySample]) {
        self.entityID = entityID
        self.range = range
        self.samples = samples
    }
}

/// A single numeric history reading paired with the moment it was recorded.
///
/// Used by interactive readouts (for example a chart crosshair) that need both
/// the value and its timestamp for the sample nearest a cursor position.
public struct PerchHAHistoryCursorSample: Equatable, Sendable {
    public let timestamp: Date
    public let value: Double

    public init(timestamp: Date, value: Double) {
        self.timestamp = timestamp
        self.value = value
    }
}

/// Pure selection of the history sample nearest a normalized horizontal cursor
/// position, mirroring the time-based layout used to draw the sparkline.
public enum PerchHAHistoryCursor {
    /// The numeric samples of a series, sorted chronologically and stripped of
    /// non-numeric readings.
    ///
    /// Ordering is stable: ties on timestamp keep their original sample order.
    ///
    /// - Parameter series: The history series to project.
    /// - Returns: The chronological numeric samples, possibly empty.
    public static func numericSamples(of series: HistorySeries) -> [PerchHAHistoryCursorSample] {
        series.samples.enumerated()
            .compactMap { index, sample -> (Int, PerchHAHistoryCursorSample)? in
                guard let value = sample.numericValue else {
                    return nil
                }
                return (index, PerchHAHistoryCursorSample(timestamp: sample.timestamp, value: value))
            }
            .sorted { lhs, rhs in
                if lhs.1.timestamp == rhs.1.timestamp {
                    return lhs.0 < rhs.0
                }
                return lhs.1.timestamp < rhs.1.timestamp
            }
            .map(\.1)
    }

    /// The numeric sample nearest a normalized horizontal position.
    ///
    /// The normalized position is clamped to `0...1`. Samples are laid out along
    /// the x-axis by timestamp (matching the sparkline geometry); when every
    /// sample shares one timestamp they fall back to an even index spacing. The
    /// nearest sample by absolute distance is returned, preferring the earlier
    /// sample on ties.
    ///
    /// - Parameters:
    ///   - series: The history series to search.
    ///   - normalizedX: The cursor position in `0...1` (`0` is the first sample,
    ///     `1` is the last).
    /// - Returns: The nearest numeric sample, or `nil` when the series carries no
    ///   numeric samples.
    public static func nearestSample(in series: HistorySeries, atNormalizedX normalizedX: Double) -> PerchHAHistoryCursorSample? {
        let samples = numericSamples(of: series)
        return nearestSample(in: samples, atNormalizedX: normalizedX)
    }

    /// The numeric sample nearest a normalized horizontal position.
    ///
    /// - Parameters:
    ///   - samples: Chronological numeric samples (as produced by
    ///     ``numericSamples(of:)``).
    ///   - normalizedX: The cursor position in `0...1`.
    /// - Returns: The nearest sample, or `nil` when `samples` is empty.
    public static func nearestSample(in samples: [PerchHAHistoryCursorSample], atNormalizedX normalizedX: Double) -> PerchHAHistoryCursorSample? {
        guard let first = samples.first else {
            return nil
        }
        guard samples.count > 1 else {
            return first
        }
        let clampedX = min(max(normalizedX, 0), 1)
        let times = samples.map { $0.timestamp.timeIntervalSince1970 }
        guard let firstTime = times.first, let lastTime = times.last else {
            return first
        }
        let timeSpan = lastTime - firstTime
        let lastIndex = Double(samples.count - 1)
        var bestIndex = 0
        var bestDistance = Double.greatestFiniteMagnitude
        for (index, time) in times.enumerated() {
            let sampleX = timeSpan > 0
                ? (time - firstTime) / timeSpan
                : Double(index) / lastIndex
            let distance = abs(sampleX - clampedX)
            if distance < bestDistance {
                bestDistance = distance
                bestIndex = index
            }
        }
        return samples[bestIndex]
    }
}

public struct AreaID: Hashable, Codable, Sendable, ExpressibleByStringLiteral {
    public let rawValue: String

    public init(_ rawValue: String) {
        self.rawValue = rawValue
    }

    public init(stringLiteral value: StringLiteralType) {
        self.init(value)
    }

    public init(from decoder: Decoder) throws {
        rawValue = try decoder.singleValueContainer().decode(String.self)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

public struct DeviceID: Hashable, Codable, Sendable, ExpressibleByStringLiteral {
    public let rawValue: String

    public init(_ rawValue: String) {
        self.rawValue = rawValue
    }

    public init(stringLiteral value: StringLiteralType) {
        self.init(value)
    }

    public init(from decoder: Decoder) throws {
        rawValue = try decoder.singleValueContainer().decode(String.self)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

public struct RoomID: Hashable, Codable, Sendable, ExpressibleByStringLiteral {
    public let rawValue: String

    public init(_ rawValue: String) {
        self.rawValue = rawValue
    }

    public init(stringLiteral value: StringLiteralType) {
        self.init(value)
    }

    public init(from decoder: Decoder) throws {
        rawValue = try decoder.singleValueContainer().decode(String.self)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

public struct ProtectedActionValueReference: Hashable, Codable, Sendable, ExpressibleByStringLiteral {
    public let rawValue: String

    public init(_ rawValue: String) {
        self.rawValue = rawValue
    }

    public init(stringLiteral value: StringLiteralType) {
        self.init(value)
    }

    public init(from decoder: Decoder) throws {
        rawValue = try decoder.singleValueContainer().decode(String.self)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

public protocol ProtectedActionValueStore: Sendable {
    func save(_ value: String, for reference: ProtectedActionValueReference) throws
    func load(_ reference: ProtectedActionValueReference) throws -> String
    func delete(_ reference: ProtectedActionValueReference) throws
}

public enum ProtectedActionValueStoreError: Error, Equatable, CustomStringConvertible, Sendable {
    case invalidStoredValues
    case missingValue(ProtectedActionValueReference)
    case unavailable

    public var description: String {
        switch self {
        case .invalidStoredValues:
            "protected custom action values are invalid"
        case let .missingValue(reference):
            "protected custom action value \(reference.rawValue) is missing"
        case .unavailable:
            "protected custom action values are unavailable"
        }
    }
}

public enum ActionValue: Equatable, Sendable, Codable, ExpressibleByStringLiteral, ExpressibleByIntegerLiteral, ExpressibleByFloatLiteral, ExpressibleByBooleanLiteral {
    case string(String)
    case protectedString(ProtectedActionValueReference)
    case number(Double)
    case bool(Bool)
    case object([String: ActionValue])
    case array([ActionValue])
    case null

    public init(stringLiteral value: String) {
        self = .string(value)
    }

    public init(integerLiteral value: Int) {
        self = .number(Double(value))
    }

    public init(floatLiteral value: Double) {
        self = .number(value)
    }

    public init(booleanLiteral value: Bool) {
        self = .bool(value)
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode(ProtectedActionValueEnvelope.self),
                  value.kind == ProtectedActionValueEnvelope.protectedStringKind {
            self = .protectedString(value.reference)
        } else if let value = try? container.decode([String: ActionValue].self) {
            self = .object(value)
        } else {
            self = .array(try container.decode([ActionValue].self))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case let .string(value):
            try container.encode(value)
        case let .protectedString(reference):
            try container.encode(
                ProtectedActionValueEnvelope(
                    kind: ProtectedActionValueEnvelope.protectedStringKind,
                    reference: reference
                )
            )
        case let .number(value):
            try container.encode(value)
        case let .bool(value):
            try container.encode(value)
        case let .object(value):
            try container.encode(value)
        case let .array(value):
            try container.encode(value)
        case .null:
            try container.encodeNil()
        }
    }

    public var protectedValueReference: ProtectedActionValueReference? {
        guard case let .protectedString(reference) = self else {
            return nil
        }
        return reference
    }

    public func resolvedProtectedValues(
        using resolver: (ProtectedActionValueReference) throws -> String
    ) throws -> ActionValue {
        switch self {
        case let .protectedString(reference):
            return .string(try resolver(reference))
        case let .object(values):
            return .object(
                Dictionary(
                    uniqueKeysWithValues: try values.map { key, value in
                        (key, try value.resolvedProtectedValues(using: resolver))
                    }
                )
            )
        case let .array(values):
            return .array(try values.map { try $0.resolvedProtectedValues(using: resolver) })
        case .string, .number, .bool, .null:
            return self
        }
    }

    public var protectedValueReferences: Set<ProtectedActionValueReference> {
        switch self {
        case let .protectedString(reference):
            [reference]
        case let .object(values):
            values.values.reduce(into: Set<ProtectedActionValueReference>()) { result, value in
                result.formUnion(value.protectedValueReferences)
            }
        case let .array(values):
            values.reduce(into: Set<ProtectedActionValueReference>()) { result, value in
                result.formUnion(value.protectedValueReferences)
            }
        case .string, .number, .bool, .null:
            []
        }
    }
}

private struct ProtectedActionValueEnvelope: Codable {
    static let protectedStringKind = "protected_string"

    let kind: String
    let reference: ProtectedActionValueReference

    private enum CodingKeys: String, CodingKey {
        case kind = "$perchha"
        case reference
    }
}

public struct ActionSpec: Equatable, Sendable, Codable {
    public let domain: String
    public let service: String
    public let targetEntityID: EntityID?
    public let serviceData: [String: ActionValue]

    public init(domain: String, service: String, targetEntityID: EntityID?, serviceData: [String: ActionValue] = [:]) {
        self.domain = domain
        self.service = service
        self.targetEntityID = targetEntityID
        self.serviceData = serviceData
    }

    public func resolvedProtectedValues(
        using resolver: (ProtectedActionValueReference) throws -> String
    ) throws -> ActionSpec {
        ActionSpec(
            domain: domain,
            service: service,
            targetEntityID: targetEntityID,
            serviceData: Dictionary(
                uniqueKeysWithValues: try serviceData.map { key, value in
                    (key, try value.resolvedProtectedValues(using: resolver))
                }
            )
        )
    }

    public var protectedValueReferences: Set<ProtectedActionValueReference> {
        serviceData.values.reduce(into: Set<ProtectedActionValueReference>()) { result, value in
            result.formUnion(value.protectedValueReferences)
        }
    }

    public static func isSensitiveServiceDataKey(_ key: String) -> Bool {
        let terms = Set([
            "apikey",
            "auth",
            "authorization",
            "bearer",
            "code",
            "credential",
            "credentials",
            "pass",
            "passcode",
            "password",
            "pin",
            "secret",
            "token"
        ])
        let segments = key
            .lowercased()
            .split { character in
                !character.isLetter && !character.isNumber
            }
            .map(String.init)
        if segments.contains(where: terms.contains) {
            return true
        }
        return terms.contains(segments.joined())
    }
}

public struct HAServiceMetadata: Equatable, Sendable {
    public let domain: String
    public let service: String
    public let name: String?
    public let description: String?
    public let fields: [HAServiceFieldMetadata]

    public init(
        domain: String,
        service: String,
        name: String?,
        description: String?,
        fields: [HAServiceFieldMetadata] = []
    ) {
        self.domain = domain
        self.service = service
        self.name = name
        self.description = description
        self.fields = fields
    }
}

public struct HAServiceFieldMetadata: Equatable, Sendable {
    public let key: String
    public let name: String?
    public let description: String?
    public let required: Bool
    public let example: ActionValue?
    public let selector: ActionValue?

    public init(
        key: String,
        name: String?,
        description: String?,
        required: Bool,
        example: ActionValue?,
        selector: ActionValue?
    ) {
        self.key = key
        self.name = name
        self.description = description
        self.required = required
        self.example = example
        self.selector = selector
    }
}

public enum CustomActionValidationFailure: Equatable, Sendable, CustomStringConvertible {
    case incompleteAction(id: String)
    case duplicateActionID(String)
    case sensitiveServiceDataKey(actionID: String, keyPath: String)

    public var description: String {
        switch self {
        case let .incompleteAction(id):
            "custom action \(id) is incomplete"
        case let .duplicateActionID(id):
            "custom action ID \(id) is duplicated"
        case let .sensitiveServiceDataKey(actionID, keyPath):
            "custom action \(actionID) uses protected service data key \(keyPath)"
        }
    }
}

public struct CustomActionID: Hashable, Codable, Sendable, ExpressibleByStringLiteral {
    public let rawValue: String

    public init(_ rawValue: String) {
        self.rawValue = rawValue
    }

    public init(stringLiteral value: StringLiteralType) {
        self.init(value)
    }

    public init(from decoder: Decoder) throws {
        rawValue = try decoder.singleValueContainer().decode(String.self)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

public struct EntityCustomAction: Equatable, Codable, Sendable {
    public let id: CustomActionID
    public let entityID: EntityID
    public let title: String
    public let action: ActionSpec
    public let requiresConfirmation: Bool

    public init(
        id: CustomActionID,
        entityID: EntityID,
        title: String,
        action: ActionSpec,
        requiresConfirmation: Bool = false
    ) {
        self.id = id
        self.entityID = entityID
        self.title = title
        self.action = action
        self.requiresConfirmation = requiresConfirmation
    }

    public var isRunnable: Bool {
        validationFailure() == nil
    }

    public func validationFailure() -> CustomActionValidationFailure? {
        let displayID = id.rawValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "<blank>"
            : id.rawValue
        guard !id.rawValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !entityID.rawValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !action.domain.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !action.service.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            return .incompleteAction(id: displayID)
        }
        if let keyPath = action.sensitiveServiceDataKeyPath() {
            return .sensitiveServiceDataKey(actionID: displayID, keyPath: keyPath)
        }
        return nil
    }
}

public struct CustomActionConfiguration: Equatable, Codable, Sendable {
    public let actions: [EntityCustomAction]

    public init(actions: [EntityCustomAction] = []) {
        self.actions = actions
    }

    public func actions(for entityID: EntityID) -> [EntityCustomAction] {
        actions.filter { $0.entityID == entityID }
    }

    public func action(id: CustomActionID) -> EntityCustomAction? {
        actions.first { $0.id == id }
    }

    public func validationFailure() -> CustomActionValidationFailure? {
        var seenIDs = Set<CustomActionID>()
        for action in actions {
            if let failure = action.validationFailure() {
                return failure
            }
            guard seenIDs.insert(action.id).inserted else {
                return .duplicateActionID(action.id.rawValue)
            }
        }
        return nil
    }

    public var protectedValueReferences: Set<ProtectedActionValueReference> {
        actions.reduce(into: Set<ProtectedActionValueReference>()) { result, action in
            result.formUnion(action.action.protectedValueReferences)
        }
    }

    public func upserting(_ action: EntityCustomAction) -> CustomActionConfiguration {
        var next = actions
        if let index = next.firstIndex(where: { $0.id == action.id }) {
            next[index] = action
            return CustomActionConfiguration(actions: next)
        }
        next.append(action)
        return CustomActionConfiguration(actions: next)
    }

    public func removing(_ id: CustomActionID) -> CustomActionConfiguration {
        CustomActionConfiguration(actions: actions.filter { $0.id != id })
    }
}

private extension ActionSpec {
    func sensitiveServiceDataKeyPath() -> String? {
        Self.sensitiveServiceDataKeyPath(in: serviceData, prefix: "serviceData")
    }

    static func sensitiveServiceDataKeyPath(in values: [String: ActionValue], prefix: String) -> String? {
        for key in values.keys.sorted() {
            let keyPath = "\(prefix).\(key)"
            if isSensitiveServiceDataKey(key),
               let value = values[key],
               !value.isProtectedSensitiveLeaf {
                return keyPath
            }
            if let value = values[key],
               let nestedPath = sensitiveServiceDataKeyPath(in: value, prefix: keyPath) {
                return nestedPath
            }
        }
        return nil
    }

    static func sensitiveServiceDataKeyPath(in value: ActionValue, prefix: String) -> String? {
        switch value {
        case let .object(values):
            sensitiveServiceDataKeyPath(in: values, prefix: prefix)
        case let .array(values):
            values
                .enumerated()
                .compactMap { index, value in
                    sensitiveServiceDataKeyPath(in: value, prefix: "\(prefix)[\(index)]")
                }
                .first
        case .string, .protectedString, .number, .bool, .null:
            nil
        }
    }
}

private extension ActionValue {
    var isProtectedSensitiveLeaf: Bool {
        if case .protectedString = self {
            return true
        }
        return false
    }
}

public struct Area: Equatable, Codable, Sendable {
    public let id: AreaID
    public let name: String

    public init(id: AreaID, name: String) {
        self.id = id
        self.name = name
    }
}

public struct Device: Equatable, Codable, Sendable {
    public let id: DeviceID
    public let name: String?
    public let areaID: AreaID?

    public init(id: DeviceID, name: String?, areaID: AreaID?) {
        self.id = id
        self.name = name
        self.areaID = areaID
    }
}

public struct EntityRegistryEntry: Equatable, Codable, Sendable {
    public let id: EntityID
    public let name: String?
    public let areaID: AreaID?
    public let deviceID: DeviceID?

    public init(id: EntityID, name: String?, areaID: AreaID?, deviceID: DeviceID?) {
        self.id = id
        self.name = name
        self.areaID = areaID
        self.deviceID = deviceID
    }
}

public struct DiscoverySnapshot: Equatable, Codable, Sendable {
    public let areas: [Area]
    public let devices: [Device]
    public let entities: [EntityRegistryEntry]
    public let states: [EntityState]

    public init(areas: [Area], devices: [Device], entities: [EntityRegistryEntry], states: [EntityState]) {
        self.areas = areas
        self.devices = devices
        self.entities = entities
        self.states = states
    }
}

public struct DiscoveredEntity: Equatable, Codable, Sendable {
    public let id: EntityID
    public let name: String
    public let state: String
    public let unit: String?
    public let areaID: AreaID?
    public let deviceID: DeviceID?
    public let currentPosition: Int?

    public init(id: EntityID, name: String, state: String, unit: String?, areaID: AreaID?, deviceID: DeviceID?, currentPosition: Int? = nil) {
        self.id = id
        self.name = name
        self.state = state
        self.unit = unit
        self.areaID = areaID
        self.deviceID = deviceID
        self.currentPosition = currentPosition
    }
}

public struct Room: Equatable, Codable, Sendable {
    public let id: RoomID
    public let name: String
    public let entities: [DiscoveredEntity]

    public init(id: RoomID, name: String, entities: [DiscoveredEntity]) {
        self.id = id
        self.name = name
        self.entities = entities
    }
}

/// Pure, case-insensitive filtering of rooms by a free-text query.
///
/// Mirrors the panel search behavior: a room is kept when its name matches the
/// query or it has any matching entity. When the room name matches, all of its
/// entities are kept; otherwise only matching entities remain. An empty or
/// whitespace-only query returns the input unchanged.
public enum PerchHARoomSearch {
    /// Filters rooms (and their entities) by a query.
    ///
    /// - Parameters:
    ///   - rooms: The rooms to filter.
    ///   - query: The search text. Trimmed and matched case-insensitively.
    /// - Returns: The filtered rooms, preserving input order. Rooms with no
    ///   surviving entities are dropped.
    public static func filter(_ rooms: [Room], query: String) -> [Room] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !needle.isEmpty else {
            return rooms
        }
        return rooms.compactMap { room -> Room? in
            let roomMatches = room.name.lowercased().contains(needle)
            if roomMatches {
                return room
            }
            let matchingEntities = room.entities.filter { $0.name.lowercased().contains(needle) }
            guard !matchingEntities.isEmpty else {
                return nil
            }
            return Room(id: room.id, name: room.name, entities: matchingEntities)
        }
    }
}

public struct RoomResolver: Sendable {
    public static let unassignedRoomID = RoomID("unassigned")
    public static let unassignedRoomName = "Unassigned"

    public init() {}

    public func resolve(snapshot: DiscoverySnapshot) -> [Room] {
        let areasByID = firstAreasByID(snapshot.areas)
        let devicesByID = firstDevicesByID(snapshot.devices)
        let registryByID = firstEntityRegistryEntriesByID(snapshot.entities)

        var groupedEntities: [RoomID: [DiscoveredEntity]] = [:]
        var roomNames: [RoomID: String] = [:]
        var discoveredRoomOrder: [RoomID] = []
        for area in snapshot.areas {
            let roomID = RoomID(area.id.rawValue)
            guard roomNames[roomID] == nil else {
                continue
            }
            roomNames[roomID] = area.name
            discoveredRoomOrder.append(roomID)
        }

        for state in snapshot.states {
            let registryEntry = registryByID[state.id]
            let resolvedAreaID = registryEntry?.areaID ?? registryEntry?.deviceID.flatMap { devicesByID[$0]?.areaID }
            let roomID = resolvedAreaID.map { RoomID($0.rawValue) } ?? Self.unassignedRoomID
            if let areaID = resolvedAreaID, roomNames[roomID] == nil {
                roomNames[roomID] = areasByID[areaID]?.name ?? areaID.rawValue
                discoveredRoomOrder.append(roomID)
            }

            let entity = DiscoveredEntity(
                id: state.id,
                name: nonEmpty(registryEntry?.name) ?? state.name,
                state: state.state,
                unit: state.unit,
                areaID: resolvedAreaID,
                deviceID: registryEntry?.deviceID,
                currentPosition: state.currentPosition
            )
            groupedEntities[roomID, default: []].append(entity)
        }

        if groupedEntities[Self.unassignedRoomID]?.isEmpty == false {
            roomNames[Self.unassignedRoomID] = Self.unassignedRoomName
            discoveredRoomOrder.append(Self.unassignedRoomID)
        }

        var emitted: Set<RoomID> = []
        return discoveredRoomOrder.compactMap { roomID in
            guard emitted.insert(roomID).inserted, let entities = groupedEntities[roomID], !entities.isEmpty else {
                return nil
            }
            return Room(
                id: roomID,
                name: roomNames[roomID] ?? roomID.rawValue,
                entities: entities
            )
        }
    }

    private func firstAreasByID(_ areas: [Area]) -> [AreaID: Area] {
        var result: [AreaID: Area] = [:]
        for area in areas where result[area.id] == nil {
            result[area.id] = area
        }
        return result
    }

    private func firstDevicesByID(_ devices: [Device]) -> [DeviceID: Device] {
        var result: [DeviceID: Device] = [:]
        for device in devices where result[device.id] == nil {
            result[device.id] = device
        }
        return result
    }

    private func firstEntityRegistryEntriesByID(_ entries: [EntityRegistryEntry]) -> [EntityID: EntityRegistryEntry] {
        var result: [EntityID: EntityRegistryEntry] = [:]
        for entry in entries where result[entry.id] == nil {
            result[entry.id] = entry
        }
        return result
    }

    private func nonEmpty(_ value: String?) -> String? {
        guard let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        return value
    }
}

public enum PerchHACore {
    public static let module = PerchHAModule(
        name: "PerchHACore",
        responsibility: "Pure domain state and behavior for PerchHA."
    )
}
