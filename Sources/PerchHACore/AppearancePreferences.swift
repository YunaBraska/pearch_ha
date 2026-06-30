import Foundation

/// How each live menu-bar status item presents its promoted value.
///
/// The default, ``iconAndText``, preserves the historic behavior of showing the
/// gauge/icon image alongside the formatted value. ``iconOnly`` suppresses the
/// value title so only the glyph remains, and ``textOnly`` drops the image so
/// only the value text is shown. The choice is global (it applies to every menu
/// bar item), persisted, and back-compat decoded to ``iconAndText``.
public enum PerchHAMenuBarAppearance: String, CaseIterable, Codable, Equatable, Sendable {
    case iconAndText
    case iconOnly
    case textOnly

    /// The default appearance used when no preference has been persisted.
    public static let defaultAppearance = PerchHAMenuBarAppearance.iconAndText

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
public enum PerchHAThemeMode: String, CaseIterable, Codable, Equatable, Sendable {
    case system
    case light
    case dark

    /// The default theme mode used when no preference has been persisted.
    public static let defaultMode = PerchHAThemeMode.system

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
public struct PerchHAAccentColor: Equatable, Codable, Sendable {
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
        self.red = PerchHAAccentColor.clamp(red)
        self.green = PerchHAAccentColor.clamp(green)
        self.blue = PerchHAAccentColor.clamp(blue)
        self.alpha = PerchHAAccentColor.clamp(alpha)
    }

    private static func clamp(_ value: Double) -> Double {
        min(1, max(0, value))
    }

    /// The Home Assistant accent blue (≈ `#03A9F4`); the default accent.
    public static let homeAssistantBlue = PerchHAAccentColor(
        red: 0x03 / 255,
        green: 0xA9 / 255,
        blue: 0xF4 / 255
    )

    /// The built-in swatches offered in the accent picker, including the default.
    public static let swatches: [PerchHASwatch] = [
        PerchHASwatch(id: "ha-blue", name: "Home Assistant", color: .homeAssistantBlue),
        PerchHASwatch(id: "indigo", name: "Indigo", color: PerchHAAccentColor(red: 0x5E / 255, green: 0x5C / 255, blue: 0xE6 / 255)),
        PerchHASwatch(id: "teal", name: "Teal", color: PerchHAAccentColor(red: 0x0F / 255, green: 0xB5 / 255, blue: 0xA8 / 255)),
        PerchHASwatch(id: "green", name: "Green", color: PerchHAAccentColor(red: 0x2E / 255, green: 0xCC / 255, blue: 0x71 / 255)),
        PerchHASwatch(id: "orange", name: "Orange", color: PerchHAAccentColor(red: 0xF5 / 255, green: 0xA6 / 255, blue: 0x23 / 255)),
        PerchHASwatch(id: "pink", name: "Pink", color: PerchHAAccentColor(red: 0xE7 / 255, green: 0x4C / 255, blue: 0x9C / 255)),
        PerchHASwatch(id: "graphite", name: "Graphite", color: PerchHAAccentColor(red: 0x8E / 255, green: 0x9A / 255, blue: 0xAF / 255))
    ]

    /// A named accent swatch presented in the settings picker.
    public struct PerchHASwatch: Equatable, Sendable, Identifiable {
        /// A stable identifier used as the picker tag.
        public let id: String
        /// A human-readable swatch name.
        public let name: String
        /// The accent color this swatch applies.
        public let color: PerchHAAccentColor

        public init(id: String, name: String, color: PerchHAAccentColor) {
            self.id = id
            self.name = name
            self.color = color
        }
    }

    /// The id of the built-in swatch matching this color, or `nil` for a custom
    /// color that is not one of the named swatches.
    public var matchingSwatchID: String? {
        PerchHAAccentColor.swatches.first { $0.color == self }?.id
    }
}

/// The vertical density of dashboard telemetry rows.
///
/// ``comfortable`` is the historic, roomier row height; ``compact`` tightens the
/// row so more values fit on screen at once. The choice is persisted and applied
/// to every ``TelemetryRow`` in the dashboard.
public enum PerchHADashboardRowDensity: String, CaseIterable, Codable, Equatable, Sendable {
    case comfortable
    case compact

    /// The shipped default density.
    public static let defaultDensity: PerchHADashboardRowDensity = .comfortable

    /// The user-facing control label.
    public var displayName: String {
        switch self {
        case .comfortable: "Comfortable"
        case .compact: "Compact"
        }
    }
}

/// The bundle of user display preferences surfaced in the settings window.
///
/// Carried as a single value so the Settings UI and the app shell exchange the
/// whole set in one place. The ``Self/defaults`` value restores the shipped
/// defaults for the "reset display preferences" affordance.
public struct PerchHADisplayPreferences: Equatable, Sendable {
    /// How each menu-bar item presents its value (icon and/or text).
    public let menuBarAppearance: PerchHAMenuBarAppearance
    /// Whether the menu-bar value uses a fixed monospaced-digit width.
    public let stableMenuBarWidth: Bool
    /// The application appearance override (system/light/dark).
    public let themeMode: PerchHAThemeMode
    /// The accent color applied across the panel and settings.
    public let accentColor: PerchHAAccentColor
    /// The vertical density of dashboard telemetry rows.
    public let dashboardRowDensity: PerchHADashboardRowDensity
    /// The default inline/detail history range used when an entity has no
    /// per-entity override. Capped at a week in the UI.
    public let defaultHistoryRange: HistoryRange
    /// Whether the dashboard footer shows the "updated" timestamp caption.
    public let showsFooterTimestamp: Bool
    /// The room/module identifiers the user has hidden from the dashboard. An
    /// empty set means every available module is shown.
    public let hiddenModuleIDs: Set<String>

    public init(
        menuBarAppearance: PerchHAMenuBarAppearance = .defaultAppearance,
        stableMenuBarWidth: Bool = false,
        themeMode: PerchHAThemeMode = .defaultMode,
        accentColor: PerchHAAccentColor = .homeAssistantBlue,
        dashboardRowDensity: PerchHADashboardRowDensity = .defaultDensity,
        defaultHistoryRange: HistoryRange = .day,
        showsFooterTimestamp: Bool = true,
        hiddenModuleIDs: Set<String> = []
    ) {
        self.menuBarAppearance = menuBarAppearance
        self.stableMenuBarWidth = stableMenuBarWidth
        self.themeMode = themeMode
        self.accentColor = accentColor
        self.dashboardRowDensity = dashboardRowDensity
        self.defaultHistoryRange = defaultHistoryRange
        self.showsFooterTimestamp = showsFooterTimestamp
        self.hiddenModuleIDs = hiddenModuleIDs
    }

    /// The shipped default display preferences.
    public static let defaults = PerchHADisplayPreferences()

    /// Returns a copy with the menu-bar appearance replaced.
    public func with(menuBarAppearance: PerchHAMenuBarAppearance) -> PerchHADisplayPreferences {
        copy(menuBarAppearance: menuBarAppearance)
    }

    /// Returns a copy with the stable-width flag replaced.
    public func with(stableMenuBarWidth: Bool) -> PerchHADisplayPreferences {
        copy(stableMenuBarWidth: stableMenuBarWidth)
    }

    /// Returns a copy with the theme mode replaced.
    public func with(themeMode: PerchHAThemeMode) -> PerchHADisplayPreferences {
        copy(themeMode: themeMode)
    }

    /// Returns a copy with the accent color replaced.
    public func with(accentColor: PerchHAAccentColor) -> PerchHADisplayPreferences {
        copy(accentColor: accentColor)
    }

    /// Returns a copy with the dashboard row density replaced.
    public func with(dashboardRowDensity: PerchHADashboardRowDensity) -> PerchHADisplayPreferences {
        copy(dashboardRowDensity: dashboardRowDensity)
    }

    /// Returns a copy with the default history range replaced.
    public func with(defaultHistoryRange: HistoryRange) -> PerchHADisplayPreferences {
        copy(defaultHistoryRange: defaultHistoryRange)
    }

    /// Returns a copy with the footer-timestamp flag replaced.
    public func with(showsFooterTimestamp: Bool) -> PerchHADisplayPreferences {
        copy(showsFooterTimestamp: showsFooterTimestamp)
    }

    /// Returns a copy with the hidden-module set replaced.
    public func with(hiddenModuleIDs: Set<String>) -> PerchHADisplayPreferences {
        copy(hiddenModuleIDs: hiddenModuleIDs)
    }

    private func copy(
        menuBarAppearance: PerchHAMenuBarAppearance? = nil,
        stableMenuBarWidth: Bool? = nil,
        themeMode: PerchHAThemeMode? = nil,
        accentColor: PerchHAAccentColor? = nil,
        dashboardRowDensity: PerchHADashboardRowDensity? = nil,
        defaultHistoryRange: HistoryRange? = nil,
        showsFooterTimestamp: Bool? = nil,
        hiddenModuleIDs: Set<String>? = nil
    ) -> PerchHADisplayPreferences {
        PerchHADisplayPreferences(
            menuBarAppearance: menuBarAppearance ?? self.menuBarAppearance,
            stableMenuBarWidth: stableMenuBarWidth ?? self.stableMenuBarWidth,
            themeMode: themeMode ?? self.themeMode,
            accentColor: accentColor ?? self.accentColor,
            dashboardRowDensity: dashboardRowDensity ?? self.dashboardRowDensity,
            defaultHistoryRange: defaultHistoryRange ?? self.defaultHistoryRange,
            showsFooterTimestamp: showsFooterTimestamp ?? self.showsFooterTimestamp,
            hiddenModuleIDs: hiddenModuleIDs ?? self.hiddenModuleIDs
        )
    }
}
