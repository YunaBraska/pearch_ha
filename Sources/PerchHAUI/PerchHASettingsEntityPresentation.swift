import Foundation
import PerchHACore

struct PerchHAConnectionTokenAccessPresentation: Equatable {
    let usesStoredToken: Bool
    let tokenDraft: String

    private var trimmedTokenDraft: String {
        tokenDraft.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var hasTokenDraft: Bool {
        !trimmedTokenDraft.isEmpty
    }

    var showsSavedTokenGuidance: Bool {
        usesStoredToken && !hasTokenDraft
    }

    var fieldPlaceholder: String {
        showsSavedTokenGuidance ? "Paste new token to replace the saved one" : "Access token"
    }

    var editableButtonTitle: String {
        showsSavedTokenGuidance ? "Connect with saved token" : "Connect with token"
    }

    var connectedButtonTitle: String {
        if hasTokenDraft {
            return "Update token and reconnect"
        }
        if usesStoredToken {
            return "Reconnect with saved token"
        }
        return "Update connection"
    }

    var savedTokenGuidance: String? {
        guard showsSavedTokenGuidance else {
            return nil
        }
        return "A token is already stored in the macOS Keychain. Leave this blank to reuse it, or paste a new token to replace it on the next successful connect."
    }

    var tokenCreationGuidance: String {
        "Create one in Home Assistant under your profile → Security → Long-lived access tokens."
    }

    var connectedActionHelp: String {
        if hasTokenDraft {
            return "Reconnect using the token shown here and the addresses above."
        }
        if usesStoredToken {
            return "Reconnect using your saved Keychain token and the addresses above."
        }
        return "Reconnect using the addresses above."
    }
}

struct PerchHAEntityMetadataPresentation: Equatable {
    struct Field: Equatable {
        let label: String
        let value: String
        let usesMonospacedFont: Bool
    }

    let rowCaption: String
    let rowIdentifier: String
    let inspectorFields: [Field]

    init(entity: DiscoveredEntity, roomName: String) {
        let trimmedDeviceName = Self.formattedDeviceDisplayName(for: entity)
        let trimmedManufacturer = Self.nonEmpty(entity.deviceManufacturer)
        let trimmedRawDeviceName = Self.nonEmpty(entity.deviceName)
        let trimmedDeviceDomain = Self.nonEmpty(entity.deviceDomain)
        rowCaption = Self.rowCaption(for: entity)

        let identifierParts = [entity.id.rawValue, entity.deviceID?.rawValue].compactMap { $0 }
        rowIdentifier = identifierParts.joined(separator: " · ")

        var fields: [Field] = [
            Field(label: "Entity name", value: entity.name, usesMonospacedFont: false),
            Field(label: "Entity ID", value: entity.id.rawValue, usesMonospacedFont: true),
            Field(label: "Room", value: roomName, usesMonospacedFont: false)
        ]
        if let areaID = entity.areaID?.rawValue,
           !Self.matchesIgnoringCaseAndPunctuation(areaID, roomName) {
            fields.append(Field(label: "Area ID", value: areaID, usesMonospacedFont: true))
        }
        if let deviceName = trimmedDeviceName {
            fields.append(Field(label: "Device name", value: deviceName, usesMonospacedFont: false))
        }
        if let manufacturer = trimmedManufacturer {
            fields.append(Field(label: "Device manufacturer", value: manufacturer, usesMonospacedFont: false))
        }
        if let deviceModel = Self.nonEmpty(entity.deviceModel) {
            fields.append(Field(label: "Device model", value: deviceModel, usesMonospacedFont: false))
        }
        if let rawDeviceName = trimmedRawDeviceName,
           !Self.matchesIgnoringCaseAndPunctuation(rawDeviceName, trimmedDeviceName),
           !Self.containsIgnoringCaseAndPunctuation(trimmedDeviceName, rawDeviceName) {
            fields.append(Field(label: "Device registry name", value: rawDeviceName, usesMonospacedFont: false))
        }
        if let deviceDomain = trimmedDeviceDomain {
            fields.append(Field(label: "Device domain", value: deviceDomain, usesMonospacedFont: true))
        }
        if let deviceID = entity.deviceID?.rawValue {
            fields.append(Field(label: "Device ID", value: deviceID, usesMonospacedFont: true))
        }
        inspectorFields = fields
    }

    static func rowCaption(for entity: DiscoveredEntity) -> String {
        let rowPrimaryContext = formattedDeviceDisplayName(for: entity) ?? humanizedEntityDomain(entity.id.domain)
        let rowCaptionParts = uniqueNonEmptyValues([rowPrimaryContext, nonEmpty(entity.unit)])
        return rowCaptionParts.joined(separator: " · ")
    }

    private static func nonEmpty(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return nil
        }
        return value
    }

    private static func uniqueNonEmptyValues(_ values: [String?]) -> [String] {
        var result: [String] = []
        var seen: Set<String> = []
        for value in values {
            guard let normalized = nonEmpty(value) else {
                continue
            }
            let key = normalized.lowercased()
            guard seen.insert(key).inserted else {
                continue
            }
            result.append(normalized)
        }
        return result
    }

    private static func humanizedEntityDomain(_ domain: String) -> String {
        domain.replacingOccurrences(of: "_", with: " ").capitalized
    }

    private static func matchesIgnoringCaseAndPunctuation(_ lhs: String?, _ rhs: String?) -> Bool {
        normalizedSearchKey(lhs) == normalizedSearchKey(rhs)
    }

    private static func containsIgnoringCaseAndPunctuation(_ container: String?, _ candidate: String?) -> Bool {
        guard let container = normalizedSearchKey(container),
              let candidate = normalizedSearchKey(candidate) else {
            return false
        }
        return container.contains(candidate)
    }

    private static func normalizedSearchKey(_ value: String?) -> String? {
        guard let value = nonEmpty(value) else {
            return nil
        }
        let filtered = value.lowercased().filter { $0.isLetter || $0.isNumber }
        return filtered.isEmpty ? nil : filtered
    }

    private static func formattedDeviceDisplayName(
        for entity: DiscoveredEntity
    ) -> String? {
        formattedDeviceDisplayName(
            manufacturer: entity.deviceManufacturer,
            name: entity.deviceName,
            model: entity.deviceModel
        )
    }

    private static func formattedDeviceDisplayName(
        manufacturer: String?,
        name: String?,
        model: String?
    ) -> String? {
        let trimmedManufacturer = nonEmpty(manufacturer)
        let trimmedName = nonEmpty(name)
        let trimmedModel = nonEmpty(model)
        let normalizedManufacturer = trimmedManufacturer?.lowercased()
        let nameIncludesManufacturer = normalizedManufacturer.map { trimmedName?.lowercased().contains($0) == true } ?? false
        let modelIncludesManufacturer = normalizedManufacturer.map { trimmedModel?.lowercased().contains($0) == true } ?? false

        if let name = trimmedName, let model = trimmedModel, modelIncludesManufacturer, !nameIncludesManufacturer {
            let normalizedVerboseName = model.lowercased()
            let normalizedCode = name.lowercased()
            if normalizedVerboseName == normalizedCode || normalizedVerboseName.contains("(\(normalizedCode))") {
                return model
            }
            return "\(model) (\(name))"
        }

        var baseName = trimmedName
        if let manufacturer = trimmedManufacturer {
            if let name = baseName {
                if !name.lowercased().hasPrefix(manufacturer.lowercased() + " ")
                    && name.lowercased() != manufacturer.lowercased() {
                    baseName = "\(manufacturer) \(name)"
                }
            } else {
                baseName = manufacturer
            }
        }

        guard let baseName else {
            return trimmedModel
        }
        guard let model = trimmedModel else {
            return baseName
        }

        let normalizedBase = baseName.lowercased()
        let normalizedModel = model.lowercased()
        if normalizedBase == normalizedModel || normalizedBase.contains("(\(normalizedModel))") {
            return baseName
        }
        return "\(baseName) (\(model))"
    }
}

struct PerchHAEntityMetadataLinksPresentation: Equatable {
    let entitiesURL: URL?
    let deviceURL: URL?

    init(baseURL: URL?, entity: DiscoveredEntity) {
        entitiesURL = Self.resolvedURL(baseURL: baseURL, path: "/config/entities")
        if let deviceID = entity.deviceID?.rawValue.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) {
            deviceURL = Self.resolvedURL(baseURL: baseURL, path: "/config/devices/device/\(deviceID)")
        } else {
            deviceURL = nil
        }
    }

    private static func resolvedURL(baseURL: URL?, path: String) -> URL? {
        guard let baseURL, var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            return nil
        }
        components.path = path
        components.query = nil
        components.fragment = nil
        return components.url
    }
}

struct PerchHASettingsEntityPresentation: Equatable {
    let metadata: PerchHAEntityMetadataPresentation
    let hasAverageLinks: Bool
    let canAverage: Bool
}
