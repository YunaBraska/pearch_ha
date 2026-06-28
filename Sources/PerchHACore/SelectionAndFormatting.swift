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

public struct EntityValueFormatter: Sendable {
    public let localeIdentifier: String
    public let maximumFractionDigits: Int

    public init(locale: Locale = .current, maximumFractionDigits: Int = 2) {
        self.localeIdentifier = locale.identifier
        self.maximumFractionDigits = maximumFractionDigits
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
        let value = formattedNumber(trimmedState) ?? trimmedState
        guard let unit, !unit.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return value
        }
        return "\(value) \(unit)"
    }

    private func formattedNumber(_ state: String) -> String? {
        guard let decimal = Decimal(string: state, locale: Locale(identifier: "en_US_POSIX")) else {
            return nil
        }
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: localeIdentifier)
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = maximumFractionDigits
        formatter.roundingMode = .halfUp
        return formatter.string(from: NSDecimalNumber(decimal: decimal))
    }
}
