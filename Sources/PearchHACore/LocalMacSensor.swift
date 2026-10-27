import Foundation

public enum EntitySource: Sendable {
    case homeAssistant
    case thisMac
}

/// Local identifiers cannot collide with Home Assistant's domain.object_id syntax.
/// The namespace survives config export without storing machine identifiers.
public enum LocalMacSensor: String, CaseIterable, Sendable {
    case cpuUsage = "cpu_usage"
    case memoryUsage = "memory_usage"
    case batteryLevel = "battery_level"
    case batteryCharging = "battery_charging"
    case thermalState = "thermal_state"

    public static let roomID = RoomID("local-mac:")
    public var entityID: EntityID { EntityID("local-mac:" + rawValue) }

    public init?(entityID: EntityID) {
        guard entityID.source == .thisMac else { return nil }
        self.init(rawValue: String(entityID.rawValue.dropFirst("local-mac:".count)))
    }

    public var symbol: String {
        switch self {
        case .cpuUsage: "cpu"
        case .memoryUsage: "memorychip"
        case .batteryLevel: "battery.100percent"
        case .batteryCharging: "bolt.batteryblock"
        case .thermalState: "thermometer.medium"
        }
    }

    public var explanation: String {
        switch self {
        case .cpuUsage: LocalMacText.cpuDescription.localized()
        case .memoryUsage: LocalMacText.memoryDescription.localized()
        case .thermalState: LocalMacText.thermalDescription.localized()
        case .batteryLevel, .batteryCharging: LocalMacText.localDescription.localized()
        }
    }

    public func entity(state: String) -> DiscoveredEntity {
        let title: LocalMacText
        let unit: String?
        switch self {
        case .cpuUsage: title = .cpuUsage; unit = "%"
        case .memoryUsage: title = .memoryUsage; unit = "%"
        case .batteryLevel: title = .batteryLevel; unit = "%"
        case .batteryCharging: title = .batteryCharging; unit = nil
        case .thermalState: title = .thermalState; unit = nil
        }
        return DiscoveredEntity(id: entityID, name: title.localized(), state: state, unit: unit,
                                areaID: nil, deviceID: nil, deviceName: LocalMacText.thisMac.localized())
    }

    public func formattedState(_ state: String, locale: Locale) -> String? {
        let key: LocalMacText?
        switch (self, state) {
        case (_, "unavailable"): key = .unavailable
        case (_, "unknown"): key = .unknown
        case (.batteryCharging, "on"): key = .charging
        case (.batteryCharging, "off"): key = .notCharging
        case (.thermalState, "nominal"): key = .nominal
        case (.thermalState, "fair"): key = .fair
        case (.thermalState, "serious"): key = .serious
        case (.thermalState, "critical"): key = .critical
        default: key = nil
        }
        return key?.localized(locale: locale)
    }
}

/// Copy for the local source. Raw readings and persisted IDs stay language-neutral.
public enum LocalMacText: String, CaseIterable, Sendable {
    case thisMac, cpuUsage, memoryUsage, batteryLevel, batteryCharging, thermalState
    case charging, notCharging, nominal, fair, serious, critical, unavailable, unknown
    case source, readOnly, localDescription, cpuDescription, memoryDescription, thermalDescription
    case historyUnavailable

    /// The direct-distribution packager embeds the same resources as Xcode.
    public static var resourceBundleURL: URL { Bundle.module.bundleURL }

    private static let preferredLanguage = Bundle.preferredLocalizations(from: ["en", "de"], forPreferences: Locale.preferredLanguages).first ?? "en"
    private static let translations: [String: [LocalMacText: String]] = Dictionary(uniqueKeysWithValues: ["en", "de"].map { language in
        let bundle = Bundle.module.path(forResource: language, ofType: "lproj").flatMap(Bundle.init(path:)) ?? .module
        return (language, Dictionary(uniqueKeysWithValues: allCases.map {
            ($0, bundle.localizedString(forKey: $0.rawValue, value: nil, table: "LocalMac"))
        }))
    })

    public func localized(locale: Locale? = nil) -> String {
        let language = locale?.language.languageCode?.identifier ?? Self.preferredLanguage
        return Self.translations[language]?[self] ?? Self.translations["en"]?[self] ?? rawValue
    }
}
