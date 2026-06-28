import Foundation
import PerchHACore
import PerchHASupport
import Security

public struct ConfigLocation: Equatable, Sendable {
    public let applicationSupportDirectoryName: String
    public let fileName: String

    public init(applicationSupportDirectoryName: String = "PerchHA", fileName: String = "config.json") {
        self.applicationSupportDirectoryName = applicationSupportDirectoryName
        self.fileName = fileName
    }

    public func fileURL(fileManager: FileManager = .default) throws -> URL {
        guard let applicationSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            throw ConfigStoreError.missingApplicationSupportDirectory
        }
        return applicationSupport
            .appendingPathComponent(applicationSupportDirectoryName, isDirectory: true)
            .appendingPathComponent(fileName, isDirectory: false)
    }
}

public struct PerchHAConfiguration: Equatable, Codable, Sendable {
    public static let currentSchemaVersion = 1

    public let schemaVersion: Int
    public let selectedEntityIDs: [EntityID]
    public let menuBarEntityIDs: [EntityID]
    public let menuBarItemConfigurations: [MenuBarItemConfiguration]
    public let customActions: [EntityCustomAction]
    public let roomOrder: [RoomID]
    public let entityOrder: [EntityID]
    public let isEntitySelectionExplicit: Bool

    public init(
        schemaVersion: Int = Self.currentSchemaVersion,
        selectedEntityIDs: [EntityID] = [],
        menuBarEntityIDs: [EntityID] = [],
        menuBarItemConfigurations: [MenuBarItemConfiguration] = [],
        customActions: [EntityCustomAction] = [],
        roomOrder: [RoomID] = [],
        entityOrder: [EntityID] = [],
        isEntitySelectionExplicit: Bool = false
    ) {
        self.schemaVersion = schemaVersion
        self.selectedEntityIDs = selectedEntityIDs
        self.menuBarEntityIDs = menuBarEntityIDs
        self.menuBarItemConfigurations = menuBarItemConfigurations
        self.customActions = customActions
        self.roomOrder = roomOrder
        self.entityOrder = entityOrder
        self.isEntitySelectionExplicit = isEntitySelectionExplicit
    }

    public static var empty: PerchHAConfiguration {
        PerchHAConfiguration()
    }

    public var selectionConfiguration: EntitySelectionConfiguration {
        EntitySelectionConfiguration(
            selectedEntityIDs: selectedEntityIDs,
            roomOrder: roomOrder,
            entityOrder: entityOrder,
            isExplicit: isEntitySelectionExplicit
        )
    }

    public var menuBarDisplayConfiguration: MenuBarDisplayConfiguration {
        MenuBarDisplayConfiguration(
            promotedEntityIDs: menuBarEntityIDs,
            itemConfigurations: menuBarItemConfigurations
        )
    }

    public var customActionConfiguration: CustomActionConfiguration {
        CustomActionConfiguration(actions: customActions)
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case selectedEntityIDs
        case menuBarEntityIDs
        case menuBarItemConfigurations
        case customActions
        case roomOrder
        case entityOrder
        case isEntitySelectionExplicit
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        selectedEntityIDs = try container.decodeIfPresent([EntityID].self, forKey: .selectedEntityIDs) ?? []
        menuBarEntityIDs = try container.decodeIfPresent([EntityID].self, forKey: .menuBarEntityIDs) ?? []
        menuBarItemConfigurations = try container.decodeIfPresent([MenuBarItemConfiguration].self, forKey: .menuBarItemConfigurations) ?? []
        let decodedCustomActions = try container.decodeIfPresent([EntityCustomAction].self, forKey: .customActions) ?? []
        if let failure = CustomActionConfiguration(actions: decodedCustomActions).validationFailure() {
            throw DecodingError.dataCorruptedError(
                forKey: .customActions,
                in: container,
                debugDescription: failure.description
            )
        }
        customActions = decodedCustomActions
        roomOrder = try container.decodeIfPresent([RoomID].self, forKey: .roomOrder) ?? []
        entityOrder = try container.decodeIfPresent([EntityID].self, forKey: .entityOrder) ?? []
        isEntitySelectionExplicit = try container.decodeIfPresent(Bool.self, forKey: .isEntitySelectionExplicit) ?? false
    }
}

public protocol ConfigStore: Sendable {
    func describe() -> PerchHAModule
    func load() throws -> PerchHAConfiguration
    @discardableResult func save(_ configuration: PerchHAConfiguration) throws -> PerchHAConfiguration
}

public struct JSONConfigStore: ConfigStore {
    public let fileURL: URL

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    public init(location: ConfigLocation = ConfigLocation(), fileManager: FileManager = .default) throws {
        fileURL = try location.fileURL(fileManager: fileManager)
    }

    public func describe() -> PerchHAModule {
        PerchHAPersistence.module
    }

    public func load() throws -> PerchHAConfiguration {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return .empty
        }

        let data: Data
        do {
            data = try Data(contentsOf: fileURL)
        } catch {
            throw ConfigStoreError.readFailed(fileURL, message: String(describing: error))
        }

        do {
            let configuration = try JSONDecoder().decode(PerchHAConfiguration.self, from: data)
            guard configuration.schemaVersion == PerchHAConfiguration.currentSchemaVersion else {
                throw ConfigStoreError.unsupportedSchemaVersion(configuration.schemaVersion)
            }
            return configuration
        } catch let error as ConfigStoreError {
            throw error
        } catch {
            throw ConfigStoreError.malformedConfig(fileURL, message: String(describing: error))
        }
    }

    @discardableResult
    public func save(_ configuration: PerchHAConfiguration) throws -> PerchHAConfiguration {
        guard configuration.schemaVersion == PerchHAConfiguration.currentSchemaVersion else {
            throw ConfigStoreError.unsupportedSchemaVersion(configuration.schemaVersion)
        }
        if let failure = configuration.customActionConfiguration.validationFailure() {
            throw ConfigStoreError.invalidConfiguration(message: failure.description)
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let data: Data
        do {
            data = try encoder.encode(configuration)
        } catch {
            throw ConfigStoreError.writeFailed(fileURL, message: String(describing: error))
        }

        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try data.write(to: fileURL, options: [.atomic])
            return configuration
        } catch {
            throw ConfigStoreError.writeFailed(fileURL, message: String(describing: error))
        }
    }
}

public enum ConfigStoreError: Error, Equatable, CustomStringConvertible, Sendable {
    case missingApplicationSupportDirectory
    case malformedConfig(URL, message: String)
    case readFailed(URL, message: String)
    case unsupportedSchemaVersion(Int)
    case invalidConfiguration(message: String)
    case writeFailed(URL, message: String)

    public var description: String {
        switch self {
        case .missingApplicationSupportDirectory:
            "Application Support directory is unavailable"
        case let .malformedConfig(url, message):
            "Config file is malformed at \(url.path): \(message)"
        case let .readFailed(url, message):
            "Config file could not be read at \(url.path): \(message)"
        case let .unsupportedSchemaVersion(version):
            "Config schema version \(version) is unsupported"
        case let .invalidConfiguration(message):
            "Config file is invalid: \(message)"
        case let .writeFailed(url, message):
            "Config file could not be written at \(url.path): \(message)"
        }
    }
}

public struct PlannedConfigStore {
    public init() {}

    public func describe() -> PerchHAModule {
        PerchHAPersistence.module
    }
}

public enum PerchHASecret: String, Codable, CaseIterable, Sendable {
    case accessToken = "access_token"
    case refreshToken = "refresh_token"
    case oauthClientID = "oauth_client_id"
    case selfSignedHostAllowance = "self_signed_host_allowance"
}

public enum SecretWriteResult: Equatable, Sendable {
    case created
    case updated
}

public enum SecretDeleteResult: Equatable, Sendable {
    case deleted
    case notFound
}

public protocol SecretStore: Sendable {
    @discardableResult func save(_ value: String, for secret: PerchHASecret) throws -> SecretWriteResult
    func read(_ secret: PerchHASecret) throws -> String
    @discardableResult func delete(_ secret: PerchHASecret) throws -> SecretDeleteResult
}

public struct PerchHAAuthSession: Equatable, Sendable {
    public let accessToken: String
    public let refreshToken: String
    public let clientID: String?

    public init(accessToken: String, refreshToken: String, clientID: String? = nil) throws {
        let normalizedAccessToken = accessToken.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedRefreshToken = refreshToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedAccessToken.isEmpty else {
            throw SecretStoreError.emptySecret(.accessToken)
        }
        guard !normalizedRefreshToken.isEmpty else {
            throw SecretStoreError.emptySecret(.refreshToken)
        }
        let normalizedClientID = clientID?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let normalizedClientID, normalizedClientID.isEmpty {
            throw SecretStoreError.emptySecret(.oauthClientID)
        }
        self.accessToken = normalizedAccessToken
        self.refreshToken = normalizedRefreshToken
        self.clientID = normalizedClientID
    }
}

public struct PerchHAAuthSessionWriteResult: Equatable, Sendable {
    public let accessToken: SecretWriteResult
    public let refreshToken: SecretWriteResult

    public init(accessToken: SecretWriteResult, refreshToken: SecretWriteResult) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
    }
}

public struct PerchHAAuthSessionClearResult: Equatable, Sendable {
    public let accessToken: SecretDeleteResult
    public let refreshToken: SecretDeleteResult

    public init(accessToken: SecretDeleteResult, refreshToken: SecretDeleteResult) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
    }
}

public struct PerchHAAuthSessionStore: Sendable {
    private let secretStore: any SecretStore

    public init(secretStore: any SecretStore = KeychainSecretStore()) {
        self.secretStore = secretStore
    }

    @discardableResult
    public func save(_ session: PerchHAAuthSession) throws -> PerchHAAuthSessionWriteResult {
        let previousValues = try snapshots(for: [.accessToken, .refreshToken, .oauthClientID])
        do {
            let accessTokenResult = try secretStore.save(session.accessToken, for: .accessToken)
            let refreshTokenResult = try secretStore.save(session.refreshToken, for: .refreshToken)
            if let clientID = session.clientID {
                _ = try secretStore.save(clientID, for: .oauthClientID)
            } else {
                _ = try secretStore.delete(.oauthClientID)
            }
            return PerchHAAuthSessionWriteResult(accessToken: accessTokenResult, refreshToken: refreshTokenResult)
        } catch {
            try restore(previousValues)
            throw error
        }
    }

    public func load() throws -> PerchHAAuthSession {
        let clientID: String?
        do {
            clientID = try secretStore.read(.oauthClientID)
        } catch SecretStoreError.notFound(_) {
            clientID = nil
        } catch {
            throw error
        }
        return try PerchHAAuthSession(
            accessToken: secretStore.read(.accessToken),
            refreshToken: secretStore.read(.refreshToken),
            clientID: clientID
        )
    }

    @discardableResult
    public func replaceAccessToken(_ accessToken: String) throws -> SecretWriteResult {
        try secretStore.save(accessToken.trimmingCharacters(in: .whitespacesAndNewlines), for: .accessToken)
    }

    @discardableResult
    public func clear() throws -> PerchHAAuthSessionClearResult {
        let previousValues = try snapshots(for: [.accessToken, .refreshToken, .oauthClientID])
        do {
            let accessTokenResult = try secretStore.delete(.accessToken)
            let refreshTokenResult = try secretStore.delete(.refreshToken)
            _ = try secretStore.delete(.oauthClientID)
            return PerchHAAuthSessionClearResult(accessToken: accessTokenResult, refreshToken: refreshTokenResult)
        } catch {
            try restore(previousValues)
            throw error
        }
    }

    private func snapshots(for secrets: [PerchHASecret]) throws -> [PerchHASecret: PerchHASecretSnapshot] {
        var values: [PerchHASecret: PerchHASecretSnapshot] = [:]
        for secret in secrets {
            do {
                values[secret] = .present(try secretStore.read(secret))
            } catch SecretStoreError.notFound(_) {
                values[secret] = .missing
            } catch {
                throw error
            }
        }
        return values
    }

    private func restore(_ snapshots: [PerchHASecret: PerchHASecretSnapshot]) throws {
        for secret in snapshots.keys.sorted(by: { $0.rawValue < $1.rawValue }) {
            guard let snapshot = snapshots[secret] else {
                continue
            }
            try restore(snapshot, for: secret)
        }
    }

    private func restore(_ snapshot: PerchHASecretSnapshot, for secret: PerchHASecret) throws {
        switch snapshot {
        case let .present(value):
            _ = try secretStore.save(value, for: secret)
        case .missing:
            _ = try secretStore.delete(secret)
        }
    }
}

private enum PerchHASecretSnapshot: Equatable, Sendable {
    case present(String)
    case missing
}

public struct KeychainSecretStore: SecretStore {
    public let service: String

    public init(service: String = "dev.perchha.PerchHA") {
        self.service = service
    }

    @discardableResult
    public func save(_ value: String, for secret: PerchHASecret) throws -> SecretWriteResult {
        guard !value.isEmpty else {
            throw SecretStoreError.emptySecret(secret)
        }

        let data = Data(value.utf8)
        let updateStatus = SecItemUpdate(
            query(for: secret) as CFDictionary,
            [kSecValueData: data] as CFDictionary
        )
        if updateStatus == errSecSuccess {
            return .updated
        }
        guard updateStatus == errSecItemNotFound else {
            throw SecretStoreError.operationFailed(operation: "update", secret: secret, status: updateStatus)
        }

        var addQuery = query(for: secret)
        addQuery[kSecValueData] = data
        addQuery[kSecAttrAccessible] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw SecretStoreError.operationFailed(operation: "add", secret: secret, status: addStatus)
        }
        return .created
    }

    public func read(_ secret: PerchHASecret) throws -> String {
        var readQuery = query(for: secret)
        readQuery[kSecReturnData] = kCFBooleanTrue
        readQuery[kSecMatchLimit] = kSecMatchLimitOne

        var result: CFTypeRef?
        let status = SecItemCopyMatching(readQuery as CFDictionary, &result)
        if status == errSecItemNotFound {
            throw SecretStoreError.notFound(secret)
        }
        guard status == errSecSuccess else {
            throw SecretStoreError.operationFailed(operation: "read", secret: secret, status: status)
        }
        guard let data = result as? Data, let value = String(data: data, encoding: .utf8) else {
            throw SecretStoreError.invalidData(secret)
        }
        return value
    }

    @discardableResult
    public func delete(_ secret: PerchHASecret) throws -> SecretDeleteResult {
        let status = SecItemDelete(query(for: secret) as CFDictionary)
        if status == errSecItemNotFound {
            return .notFound
        }
        guard status == errSecSuccess else {
            throw SecretStoreError.operationFailed(operation: "delete", secret: secret, status: status)
        }
        return .deleted
    }

    private func query(for secret: PerchHASecret) -> [CFString: Any] {
        [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: secret.rawValue
        ]
    }
}

public enum SecretStoreError: Error, Equatable, CustomStringConvertible, Sendable {
    case emptySecret(PerchHASecret)
    case invalidData(PerchHASecret)
    case notFound(PerchHASecret)
    case operationFailed(operation: String, secret: PerchHASecret, status: OSStatus)

    public var description: String {
        switch self {
        case let .emptySecret(secret):
            "Secret \(secret.rawValue) cannot be empty"
        case let .invalidData(secret):
            "Secret \(secret.rawValue) contains invalid data"
        case let .notFound(secret):
            "Secret \(secret.rawValue) was not found"
        case let .operationFailed(operation, secret, status):
            "Keychain \(operation) failed for \(secret.rawValue) with status \(status)"
        }
    }
}

public enum PerchHAPersistence {
    public static let module = PerchHAModule(
        name: "PerchHAPersistence",
        responsibility: "Config persistence and Keychain-backed secrets."
    )
}
