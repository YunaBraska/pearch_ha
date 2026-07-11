import Foundation
import PearchHACore

enum PearchHAActionValuePathEditor {
    static func set(
        _ value: ActionValue,
        at path: [PearchHACustomActionServiceDataPathComponent],
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
        guard set(value, at: remainingPath, in: &existing) else {
            return false
        }
        serviceData[trimmedKey] = existing
        return true
    }

    static func set(
        _ value: ActionValue,
        at path: [PearchHACustomActionServiceDataPathComponent],
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
                  set(value, at: remainingPath, in: &child)
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
            guard set(value, at: remainingPath, in: &nextValues[index]) else {
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

    static func renameKey(
        parentPath: [PearchHACustomActionServiceDataPathComponent],
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
        return update(at: parentPath, in: &serviceData) { parent in
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

    static func remove(
        at path: [PearchHACustomActionServiceDataPathComponent],
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
        return update(at: [.key(trimmedKey)], in: &serviceData) { parent in
            remove(at: remainingPath, in: &parent)
        }
    }

    static func remove(
        at path: [PearchHACustomActionServiceDataPathComponent],
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
                  remove(at: remainingPath, in: &child)
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
            guard remove(at: remainingPath, in: &nextValues[index]) else {
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

    static func appendArrayValue(
        _ value: ActionValue,
        at path: [PearchHACustomActionServiceDataPathComponent],
        in serviceData: inout [String: ActionValue]
    ) -> Bool {
        update(at: path, in: &serviceData) { parent in
            guard case let .array(values) = parent else {
                return false
            }
            parent = .array(values + [value])
            return true
        }
    }

    static func moveArrayValue(
        at path: [PearchHACustomActionServiceDataPathComponent],
        direction: SelectionMoveDirection,
        in serviceData: inout [String: ActionValue]
    ) -> Bool {
        guard let last = path.last,
              case let .index(index) = last
        else {
            return false
        }
        let parentPath = Array(path.dropLast())
        return update(at: parentPath, in: &serviceData) { parent in
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

    static func value(
        at path: [PearchHACustomActionServiceDataPathComponent],
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

    static func update(
        at path: [PearchHACustomActionServiceDataPathComponent],
        in serviceData: inout [String: ActionValue],
        mutation: (inout ActionValue) -> Bool
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
            updated = mutation(&value)
        } else {
            updated = Self.update(at: remainingPath, in: &value, mutation: mutation)
        }
        guard updated else {
            return false
        }
        serviceData[trimmedKey] = value
        return true
    }

    static func update(
        at path: [PearchHACustomActionServiceDataPathComponent],
        in parent: inout ActionValue,
        mutation: (inout ActionValue) -> Bool
    ) -> Bool {
        guard let first = path.first else {
            return mutation(&parent)
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
                ? mutation(&child)
                : Self.update(at: remainingPath, in: &child, mutation: mutation)
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
                ? mutation(&nextValues[index])
                : Self.update(at: remainingPath, in: &nextValues[index], mutation: mutation)
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
}
