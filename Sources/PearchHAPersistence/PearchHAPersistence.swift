import Foundation
import PearchHACore
import PearchHASupport
import Security

public struct ConfigLocation: Equatable, Sendable {
    public let applicationSupportDirectoryName: String
    public let fileName: String

    public init(applicationSupportDirectoryName: String = "PearchHA", fileName: String = "config.json") {
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

public struct PearchHAConfiguration: Equatable, Codable, Sendable {
    public static let currentSchemaVersion = 1

    public let schemaVersion: Int
    public let selectedEntityIDs: [EntityID]
    public let menuBarEntityIDs: [EntityID]
    public let menuBarItemConfigurations: [MenuBarItemConfiguration]
    public let customActions: [EntityCustomAction]
    public let connectionProfile: PearchHAConnectionProfile?
    public let roomOrder: [RoomID]
    public let entityOrder: [EntityID]
    public let isEntitySelectionExplicit: Bool
    public let menuBarAppearance: PearchHAMenuBarAppearance
    public let stableMenuBarWidth: Bool
    public let themeMode: PearchHAThemeMode
    public let menuBarRefreshInterval: PearchHAMenuBarRefreshInterval
    public let dataSyncInterval: PearchHAMenuBarRefreshInterval
    public let historyDetailRefreshInterval: PearchHAMenuBarRefreshInterval
    public let liveUpdatesEnabled: Bool
    public let accentColor: PearchHAAccentColor
    public let dashboardRowDensity: PearchHADashboardRowDensity
    public let dashboardDefaultHistoryRange: HistoryRange
    public let dashboardShowsFooterTimestamp: Bool
    public let dashboardHiddenModuleIDs: [String]
    public let dashboardSummaryMetricEntityIDs: [EntityID]
    public let dashboardRoomRowLimit: Int

    public init(
        schemaVersion: Int = Self.currentSchemaVersion,
        selectedEntityIDs: [EntityID] = [],
        menuBarEntityIDs: [EntityID] = [],
        menuBarItemConfigurations: [MenuBarItemConfiguration] = [],
        customActions: [EntityCustomAction] = [],
        connectionProfile: PearchHAConnectionProfile? = nil,
        roomOrder: [RoomID] = [],
        entityOrder: [EntityID] = [],
        isEntitySelectionExplicit: Bool = false,
        menuBarAppearance: PearchHAMenuBarAppearance = .defaultAppearance,
        stableMenuBarWidth: Bool = false,
        themeMode: PearchHAThemeMode = .defaultMode,
        menuBarRefreshInterval: PearchHAMenuBarRefreshInterval = .defaultInterval,
        dataSyncInterval: PearchHAMenuBarRefreshInterval = .fiveSeconds,
        historyDetailRefreshInterval: PearchHAMenuBarRefreshInterval = .thirtySeconds,
        liveUpdatesEnabled: Bool = false,
        accentColor: PearchHAAccentColor = .homeAssistantBlue,
        dashboardRowDensity: PearchHADashboardRowDensity = .defaultDensity,
        dashboardDefaultHistoryRange: HistoryRange = .day,
        dashboardShowsFooterTimestamp: Bool = true,
        dashboardHiddenModuleIDs: [String] = [],
        dashboardSummaryMetricEntityIDs: [EntityID] = [],
        dashboardRoomRowLimit: Int = PearchHADisplayPreferences.defaultDashboardRoomRowLimit
    ) {
        self.schemaVersion = schemaVersion
        self.selectedEntityIDs = selectedEntityIDs
        self.menuBarEntityIDs = menuBarEntityIDs
        self.menuBarItemConfigurations = menuBarItemConfigurations
        self.customActions = customActions
        self.connectionProfile = connectionProfile
        self.roomOrder = roomOrder
        self.entityOrder = entityOrder
        self.isEntitySelectionExplicit = isEntitySelectionExplicit
        self.menuBarAppearance = menuBarAppearance
        self.stableMenuBarWidth = stableMenuBarWidth
        self.themeMode = themeMode
        self.menuBarRefreshInterval = menuBarRefreshInterval
        self.dataSyncInterval = dataSyncInterval
        self.historyDetailRefreshInterval = historyDetailRefreshInterval
        self.liveUpdatesEnabled = liveUpdatesEnabled
        self.accentColor = accentColor
        self.dashboardRowDensity = dashboardRowDensity
        self.dashboardDefaultHistoryRange = dashboardDefaultHistoryRange
        self.dashboardShowsFooterTimestamp = dashboardShowsFooterTimestamp
        self.dashboardHiddenModuleIDs = dashboardHiddenModuleIDs
        self.dashboardSummaryMetricEntityIDs = PearchHADisplayPreferences.cappedSummaryMetricEntityIDs(dashboardSummaryMetricEntityIDs)
        self.dashboardRoomRowLimit = dashboardRoomRowLimit
    }

    public static var empty: PearchHAConfiguration {
        PearchHAConfiguration(isEntitySelectionExplicit: true)
    }

    /// Returns a copy replacing only the given selection/menu-bar/action/
    /// connection fields, carrying every other field — including all display
    /// preferences — unchanged.
    ///
    /// Rebuilding a configuration by listing fields at the call site silently
    /// reset every omitted field to its default: connecting once wiped the
    /// user's persisted appearance, theme, and accent. All partial updates go
    /// through this copy instead.
    ///
    /// - Parameters mirror the stored fields; `nil` keeps the current value
    ///   (`connectionProfile` uses a double optional so it can be cleared).
    /// - Returns: The updated configuration value.
    public func replacing(
        selectedEntityIDs: [EntityID]? = nil,
        menuBarEntityIDs: [EntityID]? = nil,
        menuBarItemConfigurations: [MenuBarItemConfiguration]? = nil,
        customActions: [EntityCustomAction]? = nil,
        connectionProfile: PearchHAConnectionProfile?? = nil,
        roomOrder: [RoomID]? = nil,
        entityOrder: [EntityID]? = nil,
        isEntitySelectionExplicit: Bool? = nil
    ) -> PearchHAConfiguration {
        PearchHAConfiguration(
            schemaVersion: schemaVersion,
            selectedEntityIDs: selectedEntityIDs ?? self.selectedEntityIDs,
            menuBarEntityIDs: menuBarEntityIDs ?? self.menuBarEntityIDs,
            menuBarItemConfigurations: menuBarItemConfigurations ?? self.menuBarItemConfigurations,
            customActions: customActions ?? self.customActions,
            connectionProfile: connectionProfile ?? self.connectionProfile,
            roomOrder: roomOrder ?? self.roomOrder,
            entityOrder: entityOrder ?? self.entityOrder,
            isEntitySelectionExplicit: isEntitySelectionExplicit ?? self.isEntitySelectionExplicit,
            menuBarAppearance: menuBarAppearance,
            stableMenuBarWidth: stableMenuBarWidth,
            themeMode: themeMode,
            menuBarRefreshInterval: menuBarRefreshInterval,
            dataSyncInterval: dataSyncInterval,
            historyDetailRefreshInterval: historyDetailRefreshInterval,
            accentColor: accentColor,
            dashboardRowDensity: dashboardRowDensity,
            dashboardDefaultHistoryRange: dashboardDefaultHistoryRange,
            dashboardShowsFooterTimestamp: dashboardShowsFooterTimestamp,
            dashboardHiddenModuleIDs: dashboardHiddenModuleIDs,
            dashboardSummaryMetricEntityIDs: dashboardSummaryMetricEntityIDs,
            dashboardRoomRowLimit: dashboardRoomRowLimit
        )
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
        case connectionProfile
        case roomOrder
        case entityOrder
        case isEntitySelectionExplicit
        case menuBarAppearance
        case stableMenuBarWidth
        case themeMode
        case menuBarRefreshInterval
        case dataSyncInterval
        case historyDetailRefreshInterval
        case liveUpdatesEnabled
        case accentColor
        case dashboardRowDensity
        case dashboardDefaultHistoryRange
        case dashboardShowsFooterTimestamp
        case dashboardHiddenModuleIDs
        case dashboardSummaryMetricEntityIDs
        case dashboardRoomRowLimit
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
        connectionProfile = try container.decodeIfPresent(PearchHAConnectionProfile.self, forKey: .connectionProfile)
        roomOrder = try container.decodeIfPresent([RoomID].self, forKey: .roomOrder) ?? []
        entityOrder = try container.decodeIfPresent([EntityID].self, forKey: .entityOrder) ?? []
        isEntitySelectionExplicit = try container.decodeIfPresent(Bool.self, forKey: .isEntitySelectionExplicit) ?? false
        menuBarAppearance = try container.decodeIfPresent(PearchHAMenuBarAppearance.self, forKey: .menuBarAppearance) ?? .defaultAppearance
        stableMenuBarWidth = try container.decodeIfPresent(Bool.self, forKey: .stableMenuBarWidth) ?? false
        themeMode = try container.decodeIfPresent(PearchHAThemeMode.self, forKey: .themeMode) ?? .defaultMode
        menuBarRefreshInterval = try container.decodeIfPresent(PearchHAMenuBarRefreshInterval.self, forKey: .menuBarRefreshInterval) ?? .defaultInterval
        dataSyncInterval = try container.decodeIfPresent(PearchHAMenuBarRefreshInterval.self, forKey: .dataSyncInterval) ?? .fiveSeconds
        historyDetailRefreshInterval = try container.decodeIfPresent(PearchHAMenuBarRefreshInterval.self, forKey: .historyDetailRefreshInterval) ?? .thirtySeconds
        liveUpdatesEnabled = try container.decodeIfPresent(Bool.self, forKey: .liveUpdatesEnabled) ?? false
        accentColor = try container.decodeIfPresent(PearchHAAccentColor.self, forKey: .accentColor) ?? .homeAssistantBlue
        dashboardRowDensity = try container.decodeIfPresent(PearchHADashboardRowDensity.self, forKey: .dashboardRowDensity) ?? .defaultDensity
        dashboardDefaultHistoryRange = try container.decodeIfPresent(HistoryRange.self, forKey: .dashboardDefaultHistoryRange) ?? .day
        dashboardShowsFooterTimestamp = try container.decodeIfPresent(Bool.self, forKey: .dashboardShowsFooterTimestamp) ?? true
        dashboardHiddenModuleIDs = try container.decodeIfPresent([String].self, forKey: .dashboardHiddenModuleIDs) ?? []
        dashboardSummaryMetricEntityIDs = PearchHADisplayPreferences.cappedSummaryMetricEntityIDs(
            try container.decodeIfPresent([EntityID].self, forKey: .dashboardSummaryMetricEntityIDs) ?? []
        )
        dashboardRoomRowLimit = try container.decodeIfPresent(Int.self, forKey: .dashboardRoomRowLimit)
            ?? PearchHADisplayPreferences.defaultDashboardRoomRowLimit
    }

    /// The display preferences embedded in this configuration.
    ///
    /// Surfaces the flat persisted appearance/dashboard fields as the bundled
    /// ``PearchHADisplayPreferences`` value the UI and app shell exchange.
    public var displayPreferences: PearchHADisplayPreferences {
        PearchHADisplayPreferences(
            menuBarAppearance: menuBarAppearance,
            stableMenuBarWidth: stableMenuBarWidth,
            themeMode: themeMode,
            menuBarRefreshInterval: menuBarRefreshInterval,
            dataSyncInterval: dataSyncInterval,
            historyDetailRefreshInterval: historyDetailRefreshInterval,
            liveUpdatesEnabled: liveUpdatesEnabled,
            accentColor: accentColor,
            dashboardRowDensity: dashboardRowDensity,
            defaultHistoryRange: dashboardDefaultHistoryRange,
            showsFooterTimestamp: dashboardShowsFooterTimestamp,
            hiddenModuleIDs: Set(dashboardHiddenModuleIDs),
            summaryMetricEntityIDs: dashboardSummaryMetricEntityIDs,
            dashboardRoomRowLimit: dashboardRoomRowLimit
        )
    }

    /// Returns a copy of this configuration with its display-preference fields
    /// replaced by the supplied bundle, leaving selection/menu-bar/connection
    /// state untouched.
    public func applying(displayPreferences: PearchHADisplayPreferences) -> PearchHAConfiguration {
        PearchHAConfiguration(
            schemaVersion: schemaVersion,
            selectedEntityIDs: selectedEntityIDs,
            menuBarEntityIDs: menuBarEntityIDs,
            menuBarItemConfigurations: menuBarItemConfigurations,
            customActions: customActions,
            connectionProfile: connectionProfile,
            roomOrder: roomOrder,
            entityOrder: entityOrder,
            isEntitySelectionExplicit: isEntitySelectionExplicit,
            menuBarAppearance: displayPreferences.menuBarAppearance,
            stableMenuBarWidth: displayPreferences.stableMenuBarWidth,
            themeMode: displayPreferences.themeMode,
            menuBarRefreshInterval: displayPreferences.menuBarRefreshInterval,
            dataSyncInterval: displayPreferences.dataSyncInterval,
            historyDetailRefreshInterval: displayPreferences.historyDetailRefreshInterval,
            liveUpdatesEnabled: displayPreferences.liveUpdatesEnabled,
            accentColor: displayPreferences.accentColor,
            dashboardRowDensity: displayPreferences.dashboardRowDensity,
            dashboardDefaultHistoryRange: displayPreferences.defaultHistoryRange,
            dashboardShowsFooterTimestamp: displayPreferences.showsFooterTimestamp,
            dashboardHiddenModuleIDs: Array(displayPreferences.hiddenModuleIDs).sorted(),
            dashboardSummaryMetricEntityIDs: displayPreferences.summaryMetricEntityIDs,
            dashboardRoomRowLimit: displayPreferences.dashboardRoomRowLimit
        )
    }
}

/// A single Home Assistant address in an ordered connection profile.
///
/// Each address carries an optional human label (for example `Home` or `VPN`;
/// may be empty) and a URL string. Both values are trimmed on construction.
public struct PearchHAConnectionAddress: Equatable, Codable, Sendable {
    public let label: String
    public let urlString: String

    /// Creates a connection address.
    ///
    /// - Parameters:
    ///   - label: An optional display label. Trimmed; may be empty.
    ///   - urlString: The Home Assistant URL. Trimmed.
    public init(label: String = "", urlString: String) {
        self.label = label.trimmingCharacters(in: .whitespacesAndNewlines)
        self.urlString = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// An ordered list of Home Assistant addresses to try in sequence.
///
/// The first address is the primary; any following addresses are alternatives
/// (internal, external, VPN, and so on) that the client falls back to in order
/// when an earlier one is unreachable. Strings are trimmed and blank addresses
/// are dropped on construction.
///
public struct PearchHAConnectionProfile: Equatable, Codable, Sendable {
    public let addresses: [PearchHAConnectionAddress]

    /// Whether the user trusts self-signed TLS certificates for the profile's
    /// HTTPS hosts. Defaults to `true` (scoped to the profile's own hosts,
    /// never all hosts); older stored profiles without the field decode as
    /// `true` so existing self-signed setups keep working.
    public let allowsSelfSignedCertificates: Bool

    /// Creates a profile from an ordered list of addresses.
    ///
    /// - Parameters:
    ///   - addresses: The ordered addresses. Entries with an empty URL string
    ///     are dropped.
    ///   - allowsSelfSignedCertificates: The user's self-signed certificate
    ///     preference for the profile's HTTPS hosts. Defaults to `true`.
    public init(addresses: [PearchHAConnectionAddress], allowsSelfSignedCertificates: Bool = true) {
        self.addresses = addresses.filter { !$0.urlString.isEmpty }
        self.allowsSelfSignedCertificates = allowsSelfSignedCertificates
    }

    /// Creates a profile from a primary URL and an optional single fallback.
    ///
    /// Retained for back-compatibility with call sites and stored data that used
    /// the primary/fallback shape. An empty fallback produces no extra address.
    ///
    /// - Parameters:
    ///   - urlString: The primary Home Assistant URL. Trimmed.
    ///   - fallbackURLString: An optional fallback URL. Trimmed; empty is ignored.
    public init(urlString: String, fallbackURLString: String = "") {
        let primary = PearchHAConnectionAddress(urlString: urlString)
        let fallback = PearchHAConnectionAddress(urlString: fallbackURLString)
        self.init(addresses: [primary, fallback])
    }

    /// The primary URL string (the first address), or `""` when empty.
    public var urlString: String {
        addresses.first?.urlString ?? ""
    }

    /// The first alternative URL string (the second address), or `""` when none.
    public var fallbackURLString: String {
        addresses.count > 1 ? addresses[1].urlString : ""
    }

    private enum CodingKeys: String, CodingKey {
        case addresses
        case allowsSelfSignedCertificates
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let allowsSelfSignedCertificates = try container.decodeIfPresent(Bool.self, forKey: .allowsSelfSignedCertificates) ?? true
        let decodedAddresses = try container.decodeIfPresent([PearchHAConnectionAddress].self, forKey: .addresses) ?? []
        self.init(addresses: decodedAddresses, allowsSelfSignedCertificates: allowsSelfSignedCertificates)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(addresses, forKey: .addresses)
        try container.encode(allowsSelfSignedCertificates, forKey: .allowsSelfSignedCertificates)
    }
}

public protocol ConfigStore: Sendable {
    func describe() -> PearchHAModule
    func load() throws -> PearchHAConfiguration
    @discardableResult func save(_ configuration: PearchHAConfiguration) throws -> PearchHAConfiguration
}

public struct JSONConfigStore: ConfigStore {
    public let fileURL: URL

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    public init(location: ConfigLocation = ConfigLocation(), fileManager: FileManager = .default) throws {
        fileURL = try location.fileURL(fileManager: fileManager)
    }

    public func describe() -> PearchHAModule {
        PearchHAPersistence.module
    }

    public func load() throws -> PearchHAConfiguration {
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
            let configuration = try JSONDecoder().decode(PearchHAConfiguration.self, from: data)
            guard configuration.schemaVersion == PearchHAConfiguration.currentSchemaVersion else {
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
    public func save(_ configuration: PearchHAConfiguration) throws -> PearchHAConfiguration {
        guard configuration.schemaVersion == PearchHAConfiguration.currentSchemaVersion else {
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

    public func describe() -> PearchHAModule {
        PearchHAPersistence.module
    }
}

public enum PearchHASecret: String, Codable, CaseIterable, Sendable {
    case accessToken = "access_token"
    case refreshToken = "refresh_token"
    case oauthClientID = "oauth_client_id"
    case customActionProtectedValues = "custom_action_protected_values"
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
    @discardableResult func save(_ value: String, for secret: PearchHASecret) throws -> SecretWriteResult
    func read(_ secret: PearchHASecret) throws -> String
    @discardableResult func delete(_ secret: PearchHASecret) throws -> SecretDeleteResult
}

public struct PearchHAAuthSession: Equatable, Sendable {
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

public struct PearchHAAuthSessionWriteResult: Equatable, Sendable {
    public let accessToken: SecretWriteResult
    public let refreshToken: SecretWriteResult

    public init(accessToken: SecretWriteResult, refreshToken: SecretWriteResult) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
    }
}

public struct PearchHAAuthSessionClearResult: Equatable, Sendable {
    public let accessToken: SecretDeleteResult
    public let refreshToken: SecretDeleteResult

    public init(accessToken: SecretDeleteResult, refreshToken: SecretDeleteResult) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
    }
}

public struct PearchHAAuthSessionStore: Sendable {
    private let secretStore: any SecretStore

    public init(secretStore: any SecretStore = KeychainSecretStore()) {
        self.secretStore = secretStore
    }

    @discardableResult
    public func save(_ session: PearchHAAuthSession) throws -> PearchHAAuthSessionWriteResult {
        let previousValues = try snapshots(for: [.accessToken, .refreshToken, .oauthClientID])
        do {
            let accessTokenResult = try secretStore.save(session.accessToken, for: .accessToken)
            let refreshTokenResult = try secretStore.save(session.refreshToken, for: .refreshToken)
            if let clientID = session.clientID {
                _ = try secretStore.save(clientID, for: .oauthClientID)
            } else {
                _ = try secretStore.delete(.oauthClientID)
            }
            return PearchHAAuthSessionWriteResult(accessToken: accessTokenResult, refreshToken: refreshTokenResult)
        } catch {
            restore(previousValues)
            throw error
        }
    }

    public func load() throws -> PearchHAAuthSession {
        let clientID: String?
        do {
            clientID = try secretStore.read(.oauthClientID)
        } catch SecretStoreError.notFound(_) {
            clientID = nil
        } catch {
            throw error
        }
        return try PearchHAAuthSession(
            accessToken: secretStore.read(.accessToken),
            refreshToken: secretStore.read(.refreshToken),
            clientID: clientID
        )
    }

    public func loadAccessToken() throws -> String {
        try secretStore.read(.accessToken)
    }

    @discardableResult
    public func saveAccessToken(_ accessToken: String) throws -> SecretWriteResult {
        let previousValues = try snapshots(for: [.accessToken, .refreshToken, .oauthClientID])
        do {
            let accessTokenResult = try secretStore.save(accessToken.trimmingCharacters(in: .whitespacesAndNewlines), for: .accessToken)
            _ = try secretStore.delete(.refreshToken)
            _ = try secretStore.delete(.oauthClientID)
            return accessTokenResult
        } catch {
            restore(previousValues)
            throw error
        }
    }

    @discardableResult
    public func replaceAccessToken(_ accessToken: String) throws -> SecretWriteResult {
        try secretStore.save(accessToken.trimmingCharacters(in: .whitespacesAndNewlines), for: .accessToken)
    }

    @discardableResult
    public func clear() throws -> PearchHAAuthSessionClearResult {
        let previousValues = try snapshots(for: [.accessToken, .refreshToken, .oauthClientID])
        do {
            let accessTokenResult = try secretStore.delete(.accessToken)
            let refreshTokenResult = try secretStore.delete(.refreshToken)
            _ = try secretStore.delete(.oauthClientID)
            return PearchHAAuthSessionClearResult(accessToken: accessTokenResult, refreshToken: refreshTokenResult)
        } catch {
            restore(previousValues)
            throw error
        }
    }

    private func snapshots(for secrets: [PearchHASecret]) throws -> [PearchHASecret: PearchHASecretSnapshot] {
        var values: [PearchHASecret: PearchHASecretSnapshot] = [:]
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

    private func restore(_ snapshots: [PearchHASecret: PearchHASecretSnapshot]) {
        // Best-effort rollback: a single secret that cannot be rewritten (for
        // example a slot whose write is the failure being rolled back) must not
        // abort restoration of the remaining secrets.
        for secret in snapshots.keys.sorted(by: { $0.rawValue < $1.rawValue }) {
            guard let snapshot = snapshots[secret] else {
                continue
            }
            try? restore(snapshot, for: secret)
        }
    }

    private func restore(_ snapshot: PearchHASecretSnapshot, for secret: PearchHASecret) throws {
        switch snapshot {
        case let .present(value):
            _ = try secretStore.save(value, for: secret)
        case .missing:
            _ = try secretStore.delete(secret)
        }
    }
}

private enum PearchHASecretSnapshot: Equatable, Sendable {
    case present(String)
    case missing
}

public struct KeychainProtectedActionValueStore: ProtectedActionValueStore, Sendable {
    private let secretStore: any SecretStore

    public init(secretStore: any SecretStore = KeychainSecretStore()) {
        self.secretStore = secretStore
    }

    public func save(_ value: String, for reference: ProtectedActionValueReference) throws {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else {
            throw SecretStoreError.emptySecret(.customActionProtectedValues)
        }

        var manifest = try loadManifest()
        manifest[reference.rawValue] = normalized
        try saveManifest(manifest)
    }

    public func load(_ reference: ProtectedActionValueReference) throws -> String {
        let manifest = try loadManifest()
        guard let value = manifest[reference.rawValue] else {
            throw ProtectedActionValueStoreError.missingValue(reference)
        }
        return value
    }

    public func delete(_ reference: ProtectedActionValueReference) throws {
        var manifest = try loadManifest()
        guard manifest.removeValue(forKey: reference.rawValue) != nil else {
            return
        }
        if manifest.isEmpty {
            _ = try secretStore.delete(.customActionProtectedValues)
            return
        }
        try saveManifest(manifest)
    }

    private func loadManifest() throws -> [String: String] {
        do {
            let data = Data(try secretStore.read(.customActionProtectedValues).utf8)
            return try JSONDecoder().decode([String: String].self, from: data)
        } catch SecretStoreError.notFound(_) {
            return [:]
        } catch is DecodingError {
            throw ProtectedActionValueStoreError.invalidStoredValues
        } catch let error as ProtectedActionValueStoreError {
            throw error
        } catch {
            throw error
        }
    }

    private func saveManifest(_ manifest: [String: String]) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(manifest)
        guard let text = String(data: data, encoding: .utf8) else {
            throw ProtectedActionValueStoreError.invalidStoredValues
        }
        _ = try secretStore.save(text, for: .customActionProtectedValues)
    }
}

public struct KeychainSecretStore: SecretStore {
    public let service: String

    public init(service: String = "dev.pearchha.PearchHA") {
        self.service = service
    }

    @discardableResult
    public func save(_ value: String, for secret: PearchHASecret) throws -> SecretWriteResult {
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

    public func read(_ secret: PearchHASecret) throws -> String {
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
    public func delete(_ secret: PearchHASecret) throws -> SecretDeleteResult {
        let status = SecItemDelete(query(for: secret) as CFDictionary)
        if status == errSecItemNotFound {
            return .notFound
        }
        guard status == errSecSuccess else {
            throw SecretStoreError.operationFailed(operation: "delete", secret: secret, status: status)
        }
        return .deleted
    }

    private func query(for secret: PearchHASecret) -> [CFString: Any] {
        [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: secret.rawValue
        ]
    }
}

public enum SecretStoreError: Error, Equatable, CustomStringConvertible, Sendable {
    case emptySecret(PearchHASecret)
    case invalidData(PearchHASecret)
    case notFound(PearchHASecret)
    case operationFailed(operation: String, secret: PearchHASecret, status: OSStatus)

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

public enum PearchHAPersistence {
    public static let module = PearchHAModule(
        name: "PearchHAPersistence",
        responsibility: "Config persistence and Keychain-backed secrets."
    )
}
