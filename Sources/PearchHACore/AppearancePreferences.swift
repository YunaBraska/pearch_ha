import Foundation

/// How each live menu-bar status item presents its promoted value.
///
/// The default, ``iconAndText``, preserves the historic behavior of showing the
/// gauge/icon image alongside the formatted value. ``iconOnly`` suppresses the
/// value title so only the glyph remains, and ``textOnly`` drops the image so
/// only the value text is shown. The choice is global (it applies to every menu
/// bar item), persisted, and back-compat decoded to ``iconAndText``.
public enum PearchHAMenuBarAppearance: String, CaseIterable, Codable, Equatable, Sendable {
    case iconAndText
    case iconOnly
    case textOnly

    /// The default appearance used when no preference has been persisted.
    public static let defaultAppearance = PearchHAMenuBarAppearance.iconAndText

    /// A short, human-readable label for the settings picker.
    public var displayName: String {
        switch self {
        case .iconAndText:
            "Icon and text"
        case .iconOnly:
            "Icon only"
        case .textOnly:
            "Text only"
        }
    }

    /// Whether the status-item image should be shown for this appearance.
    public var showsImage: Bool {
        switch self {
        case .iconAndText, .iconOnly:
            true
        case .textOnly:
            false
        }
    }

    /// Whether the status-item value title should be shown for this appearance.
    public var showsTitle: Bool {
        switch self {
        case .iconAndText, .textOnly:
            true
        case .iconOnly:
            false
        }
    }
}

/// The user's preferred application appearance, overriding the system setting.
///
/// ``system`` follows the macOS appearance; ``light`` and ``dark`` force the
/// aqua and dark-aqua appearances respectively. Persisted and back-compat
/// decoded to ``system``.
public enum PearchHAThemeMode: String, CaseIterable, Codable, Equatable, Sendable {
    case system
    case light
    case dark

    /// The default theme mode used when no preference has been persisted.
    public static let defaultMode = PearchHAThemeMode.system

    /// A short, human-readable label for the settings picker.
    public var displayName: String {
        switch self {
        case .system:
            "System"
        case .light:
            "Light"
        case .dark:
            "Dark"
        }
    }
}

/// A persisted accent color expressed as sRGB components in `0...1`.
///
/// Stored as four `Double` channels so the value round-trips through JSON
/// without depending on `AppKit`/`SwiftUI` color types in the Core layer. The
/// default, ``homeAssistantBlue``, matches the historic Home Assistant accent.
public struct PearchHAAccentColor: Equatable, Codable, Sendable {
    /// The red channel, clamped to `0...1`.
    public let red: Double
    /// The green channel, clamped to `0...1`.
    public let green: Double
    /// The blue channel, clamped to `0...1`.
    public let blue: Double
    /// The alpha channel, clamped to `0...1`.
    public let alpha: Double

    /// Creates an accent color, clamping every channel into `0...1`.
    ///
    /// - Parameters:
    ///   - red: The red channel.
    ///   - green: The green channel.
    ///   - blue: The blue channel.
    ///   - alpha: The alpha channel (defaults to fully opaque).
    public init(red: Double, green: Double, blue: Double, alpha: Double = 1) {
        self.red = PearchHAAccentColor.clamp(red)
        self.green = PearchHAAccentColor.clamp(green)
        self.blue = PearchHAAccentColor.clamp(blue)
        self.alpha = PearchHAAccentColor.clamp(alpha)
    }

    private static func clamp(_ value: Double) -> Double {
        min(1, max(0, value))
    }

    /// The Home Assistant accent blue (≈ `#03A9F4`); the default accent.
    public static let homeAssistantBlue = PearchHAAccentColor(
        red: 0x03 / 255,
        green: 0xA9 / 255,
        blue: 0xF4 / 255
    )

    /// The built-in swatches offered in the accent picker, including the default.
    public static let swatches: [PearchHASwatch] = [
        PearchHASwatch(id: "ha-blue", name: "Home Assistant", color: .homeAssistantBlue),
        PearchHASwatch(id: "indigo", name: "Indigo", color: PearchHAAccentColor(red: 0x5E / 255, green: 0x5C / 255, blue: 0xE6 / 255)),
        PearchHASwatch(id: "teal", name: "Teal", color: PearchHAAccentColor(red: 0x0F / 255, green: 0xB5 / 255, blue: 0xA8 / 255)),
        PearchHASwatch(id: "green", name: "Green", color: PearchHAAccentColor(red: 0x4C / 255, green: 0xAF / 255, blue: 0x50 / 255)),
        PearchHASwatch(id: "orange", name: "Orange", color: PearchHAAccentColor(red: 0xFF / 255, green: 0x98 / 255, blue: 0x00 / 255)),
        PearchHASwatch(id: "pink", name: "Pink", color: PearchHAAccentColor(red: 0xE7 / 255, green: 0x4C / 255, blue: 0x9C / 255)),
        PearchHASwatch(id: "graphite", name: "Graphite", color: PearchHAAccentColor(red: 0x8E / 255, green: 0x9A / 255, blue: 0xAF / 255))
    ]

    /// A named accent swatch presented in the settings picker.
    public struct PearchHASwatch: Equatable, Sendable, Identifiable {
        /// A stable identifier used as the picker tag.
        public let id: String
        /// A human-readable swatch name.
        public let name: String
        /// The accent color this swatch applies.
        public let color: PearchHAAccentColor

        public init(id: String, name: String, color: PearchHAAccentColor) {
            self.id = id
            self.name = name
            self.color = color
        }
    }

    /// The id of the built-in swatch matching this color, or `nil` for a custom
    /// color that is not one of the named swatches.
    public var matchingSwatchID: String? {
        PearchHAAccentColor.swatches.first { $0.color == self }?.id
    }
}

/// The vertical density of dashboard telemetry rows.
///
/// ``comfortable`` is the historic, roomier row height; ``compact`` tightens the
/// row so more values fit on screen at once. The choice is persisted and applied
/// to every ``TelemetryRow`` in the dashboard.
public enum PearchHADashboardRowDensity: String, CaseIterable, Codable, Equatable, Sendable {
    case comfortable
    case compact

    /// The shipped default density.
    public static let defaultDensity: PearchHADashboardRowDensity = .comfortable

    /// The user-facing control label.
    public var displayName: String {
        switch self {
        case .comfortable: "Comfortable"
        case .compact: "Compact"
        }
    }
}

/// The minimum cadence at which the menu-bar UI is allowed to repaint.
///
/// Live data can continue updating in the background, but the visible menu-bar
/// items only reconcile on this schedule so idle websocket chatter does not keep
/// redrawing the status items.
public enum PearchHAMenuBarRefreshInterval: Int, CaseIterable, Codable, Equatable, Sendable {
    case oneSecond = 1
    case fiveSeconds = 5
    case fifteenSeconds = 15
    case thirtySeconds = 30
    case fortyFiveSeconds = 45
    case sixtySeconds = 60
    case oneHundredTwentySeconds = 120
    case threeHundredSeconds = 300

    public static let defaultInterval: PearchHAMenuBarRefreshInterval = .thirtySeconds

    public var displayName: String {
        switch self {
        case .oneSecond: "1s"
        case .fiveSeconds: "5s"
        case .fifteenSeconds: "15s"
        case .thirtySeconds: "30s"
        case .fortyFiveSeconds: "45s"
        case .sixtySeconds: "60s"
        case .oneHundredTwentySeconds: "120s"
        case .threeHundredSeconds: "300s"
        }
    }

    public var timeInterval: TimeInterval {
        TimeInterval(rawValue)
    }
}

/// The bundle of user display preferences surfaced in the settings window.
///
/// Carried as a single value so the Settings UI and the app shell exchange the
/// whole set in one place. The ``Self/defaults`` value restores the shipped
/// defaults for the "reset display preferences" affordance.
public struct PearchHADisplayPreferences: Equatable, Sendable {
    /// How each menu-bar item presents its value (icon and/or text).
    public let menuBarAppearance: PearchHAMenuBarAppearance
    /// Whether the menu-bar value uses a fixed monospaced-digit width.
    public let stableMenuBarWidth: Bool
    /// The application appearance override (system/light/dark).
    public let themeMode: PearchHAThemeMode
    /// The minimum cadence at which menu-bar items repaint.
    public let menuBarRefreshInterval: PearchHAMenuBarRefreshInterval
    /// The cadence for background cache/data synchronization loops.
    public let dataSyncInterval: PearchHAMenuBarRefreshInterval
    /// The cadence for refreshing an open history detail surface in the background.
    public let historyDetailRefreshInterval: PearchHAMenuBarRefreshInterval
    /// The accent color applied across the panel and settings.
    public let accentColor: PearchHAAccentColor
    /// The vertical density of dashboard telemetry rows.
    public let dashboardRowDensity: PearchHADashboardRowDensity
    /// The default inline/detail history range used when an entity has no
    /// per-entity override.
    public let defaultHistoryRange: HistoryRange
    /// Whether the dashboard footer shows the "updated" timestamp caption.
    public let showsFooterTimestamp: Bool
    /// The room/module identifiers the user has hidden from the dashboard. An
    /// empty set means every available module is shown.
    public let hiddenModuleIDs: Set<String>
    /// The ordered entity identifiers the user has chosen to surface in the
    /// dashboard header summary strip, capped at ``maxSummaryMetricEntityIDs``.
    /// An empty array means "automatic" — the header derives its own metrics.
    public let summaryMetricEntityIDs: [EntityID]
    /// The number of telemetry rows a dashboard module shows before the rest
    /// collapse behind the "x more" affordance. A negative value means no
    /// limit — every row is always shown.
    public let dashboardRoomRowLimit: Int

    /// The maximum number of user-selected summary-strip entities honored. The
    /// header shows at most this many; extra selections are truncated.
    public static let maxSummaryMetricEntityIDs = 3

    /// The shipped default ``dashboardRoomRowLimit``.
    public static let defaultDashboardRoomRowLimit = 6

    public init(
        menuBarAppearance: PearchHAMenuBarAppearance = .defaultAppearance,
        stableMenuBarWidth: Bool = false,
        themeMode: PearchHAThemeMode = .defaultMode,
        menuBarRefreshInterval: PearchHAMenuBarRefreshInterval = .defaultInterval,
        dataSyncInterval: PearchHAMenuBarRefreshInterval = .fiveSeconds,
        historyDetailRefreshInterval: PearchHAMenuBarRefreshInterval = .thirtySeconds,
        accentColor: PearchHAAccentColor = .homeAssistantBlue,
        dashboardRowDensity: PearchHADashboardRowDensity = .defaultDensity,
        defaultHistoryRange: HistoryRange = .day,
        showsFooterTimestamp: Bool = true,
        hiddenModuleIDs: Set<String> = [],
        summaryMetricEntityIDs: [EntityID] = [],
        dashboardRoomRowLimit: Int = PearchHADisplayPreferences.defaultDashboardRoomRowLimit
    ) {
        self.menuBarAppearance = menuBarAppearance
        self.stableMenuBarWidth = stableMenuBarWidth
        self.themeMode = themeMode
        self.menuBarRefreshInterval = menuBarRefreshInterval
        self.dataSyncInterval = dataSyncInterval
        self.historyDetailRefreshInterval = historyDetailRefreshInterval
        self.accentColor = accentColor
        self.dashboardRowDensity = dashboardRowDensity
        self.defaultHistoryRange = defaultHistoryRange
        self.showsFooterTimestamp = showsFooterTimestamp
        self.hiddenModuleIDs = hiddenModuleIDs
        self.summaryMetricEntityIDs = PearchHADisplayPreferences.cappedSummaryMetricEntityIDs(summaryMetricEntityIDs)
        self.dashboardRoomRowLimit = dashboardRoomRowLimit
    }

    /// The effective per-module row cap, or `nil` when ``dashboardRoomRowLimit``
    /// is negative (no limit).
    public var dashboardRoomRowCap: Int? {
        dashboardRoomRowLimit < 0 ? nil : dashboardRoomRowLimit
    }

    /// De-duplicates (keeping first occurrence) and truncates a requested
    /// summary-metric selection to the supported cap, so the stored preference
    /// can never exceed ``maxSummaryMetricEntityIDs`` ordered, distinct entries.
    public static func cappedSummaryMetricEntityIDs(_ requested: [EntityID]) -> [EntityID] {
        var seen = Set<EntityID>()
        var result: [EntityID] = []
        for id in requested where seen.insert(id).inserted {
            result.append(id)
            if result.count == maxSummaryMetricEntityIDs {
                break
            }
        }
        return result
    }

    /// The shipped default display preferences.
    public static let defaults = PearchHADisplayPreferences()

    /// Returns a copy with the menu-bar appearance replaced.
    public func with(menuBarAppearance: PearchHAMenuBarAppearance) -> PearchHADisplayPreferences {
        copy(menuBarAppearance: menuBarAppearance)
    }

    /// Returns a copy with the stable-width flag replaced.
    public func with(stableMenuBarWidth: Bool) -> PearchHADisplayPreferences {
        copy(stableMenuBarWidth: stableMenuBarWidth)
    }

    /// Returns a copy with the theme mode replaced.
    public func with(themeMode: PearchHAThemeMode) -> PearchHADisplayPreferences {
        copy(themeMode: themeMode)
    }

    /// Returns a copy with the menu-bar repaint cadence replaced.
    public func with(menuBarRefreshInterval: PearchHAMenuBarRefreshInterval) -> PearchHADisplayPreferences {
        copy(menuBarRefreshInterval: menuBarRefreshInterval)
    }

    /// Returns a copy with the background data-sync cadence replaced.
    public func with(dataSyncInterval: PearchHAMenuBarRefreshInterval) -> PearchHADisplayPreferences {
        copy(dataSyncInterval: dataSyncInterval)
    }

    /// Returns a copy with the history-detail refresh cadence replaced.
    public func with(historyDetailRefreshInterval: PearchHAMenuBarRefreshInterval) -> PearchHADisplayPreferences {
        copy(historyDetailRefreshInterval: historyDetailRefreshInterval)
    }

    /// Returns a copy with the accent color replaced.
    public func with(accentColor: PearchHAAccentColor) -> PearchHADisplayPreferences {
        copy(accentColor: accentColor)
    }

    /// Returns a copy with the dashboard row density replaced.
    public func with(dashboardRowDensity: PearchHADashboardRowDensity) -> PearchHADisplayPreferences {
        copy(dashboardRowDensity: dashboardRowDensity)
    }

    /// Returns a copy with the default history range replaced.
    public func with(defaultHistoryRange: HistoryRange) -> PearchHADisplayPreferences {
        copy(defaultHistoryRange: defaultHistoryRange)
    }

    /// Returns a copy with the footer-timestamp flag replaced.
    public func with(showsFooterTimestamp: Bool) -> PearchHADisplayPreferences {
        copy(showsFooterTimestamp: showsFooterTimestamp)
    }

    /// Returns a copy with the hidden-module set replaced.
    public func with(hiddenModuleIDs: Set<String>) -> PearchHADisplayPreferences {
        copy(hiddenModuleIDs: hiddenModuleIDs)
    }

    /// Returns a copy with the summary-metric selection replaced. The supplied
    /// list is de-duplicated and capped at ``maxSummaryMetricEntityIDs``.
    public func with(summaryMetricEntityIDs: [EntityID]) -> PearchHADisplayPreferences {
        copy(summaryMetricEntityIDs: PearchHADisplayPreferences.cappedSummaryMetricEntityIDs(summaryMetricEntityIDs))
    }

    /// Returns a copy with the per-module row limit replaced. Negative means
    /// no limit.
    public func with(dashboardRoomRowLimit: Int) -> PearchHADisplayPreferences {
        copy(dashboardRoomRowLimit: dashboardRoomRowLimit)
    }

    private func copy(
        menuBarAppearance: PearchHAMenuBarAppearance? = nil,
        stableMenuBarWidth: Bool? = nil,
        themeMode: PearchHAThemeMode? = nil,
        menuBarRefreshInterval: PearchHAMenuBarRefreshInterval? = nil,
        dataSyncInterval: PearchHAMenuBarRefreshInterval? = nil,
        historyDetailRefreshInterval: PearchHAMenuBarRefreshInterval? = nil,
        accentColor: PearchHAAccentColor? = nil,
        dashboardRowDensity: PearchHADashboardRowDensity? = nil,
        defaultHistoryRange: HistoryRange? = nil,
        showsFooterTimestamp: Bool? = nil,
        hiddenModuleIDs: Set<String>? = nil,
        summaryMetricEntityIDs: [EntityID]? = nil,
        dashboardRoomRowLimit: Int? = nil
    ) -> PearchHADisplayPreferences {
        PearchHADisplayPreferences(
            menuBarAppearance: menuBarAppearance ?? self.menuBarAppearance,
            stableMenuBarWidth: stableMenuBarWidth ?? self.stableMenuBarWidth,
            themeMode: themeMode ?? self.themeMode,
            menuBarRefreshInterval: menuBarRefreshInterval ?? self.menuBarRefreshInterval,
            dataSyncInterval: dataSyncInterval ?? self.dataSyncInterval,
            historyDetailRefreshInterval: historyDetailRefreshInterval ?? self.historyDetailRefreshInterval,
            accentColor: accentColor ?? self.accentColor,
            dashboardRowDensity: dashboardRowDensity ?? self.dashboardRowDensity,
            defaultHistoryRange: defaultHistoryRange ?? self.defaultHistoryRange,
            showsFooterTimestamp: showsFooterTimestamp ?? self.showsFooterTimestamp,
            hiddenModuleIDs: hiddenModuleIDs ?? self.hiddenModuleIDs,
            summaryMetricEntityIDs: summaryMetricEntityIDs ?? self.summaryMetricEntityIDs,
            dashboardRoomRowLimit: dashboardRoomRowLimit ?? self.dashboardRoomRowLimit
        )
    }
}
