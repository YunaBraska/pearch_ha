import SwiftUI
import PerchHACore

/// The PerchHA design system: an adaptive, iStat-Menus-inspired palette and the
/// reusable card surface used to group rooms.
///
/// Colors are resolved per `ColorScheme` so the panel reads cleanly in both
/// light and dark appearances. The accent is a Home Assistant blue; the semantic
/// trio (`ok`/`warn`/`critical`) drives gauges, pills, and the timeline.
public enum PerchHATheme {
    /// The user-selected accent color, defaulting to the Home Assistant blue
    /// (≈ `#03A9F4`).
    ///
    /// The accent is a process-wide source of truth read by both the panel and
    /// the settings window so a change is reflected everywhere immediately. It is
    /// only mutated on the main thread (via ``apply(accentColor:)``) and only read
    /// from main-thread SwiftUI/AppKit render passes, so no cross-thread
    /// coordination is required.
    public static var accent: Color {
        Color(
            .sRGB,
            red: accentColor.red,
            green: accentColor.green,
            blue: accentColor.blue,
            opacity: accentColor.alpha
        )
    }

    nonisolated(unsafe) private static var accentColor: PerchHAAccentColor = .homeAssistantBlue

    /// Applies the persisted accent color so the panel and settings reflect it.
    ///
    /// - Parameter accentColor: The accent color to use process-wide.
    @MainActor
    public static func apply(accentColor: PerchHAAccentColor) {
        Self.accentColor = accentColor
    }

    /// A healthy/normal severity color.
    public static let ok = Color(red: 0x2E / 255, green: 0xCC / 255, blue: 0x71 / 255)

    /// A warning severity color.
    public static let warn = Color(red: 0xF5 / 255, green: 0xA6 / 255, blue: 0x23 / 255)

    /// A critical severity color.
    public static let critical = Color(red: 0xE7 / 255, green: 0x4C / 255, blue: 0x3C / 255)

    /// The color for a threshold severity.
    ///
    /// - Parameter severity: The resolved value severity.
    /// - Returns: The accent for normal, warn for warning, critical for critical.
    public static func color(for severity: ValueSeverity) -> Color {
        switch severity {
        case .normal:
            accent
        case .warning:
            warn
        case .critical:
            critical
        }
    }

    /// A stable muted color for an unmapped non-numeric state slot.
    ///
    /// - Parameter slot: A palette slot in `0..<HistoryStateColorKind.paletteSlotCount`.
    /// - Returns: A muted, distinguishable color.
    public static func paletteColor(slot: Int) -> Color {
        let palette: [Color] = [
            Color(red: 0x8E / 255, green: 0x9A / 255, blue: 0xAF / 255),
            Color(red: 0xB3 / 255, green: 0x88 / 255, blue: 0xC9 / 255),
            Color(red: 0x6F / 255, green: 0xB1 / 255, blue: 0xC4 / 255),
            Color(red: 0xC9 / 255, green: 0xA2 / 255, blue: 0x6F / 255),
            Color(red: 0x9F / 255, green: 0xB0 / 255, blue: 0x6F / 255)
        ]
        guard !palette.isEmpty else {
            return Color.secondary
        }
        return palette[((slot % palette.count) + palette.count) % palette.count]
    }

    /// The fill color for a classified non-numeric state.
    ///
    /// - Parameter kind: The semantic color bucket.
    /// - Returns: The accent for active, a muted gray for inactive, a stable muted
    ///   palette color otherwise.
    public static func color(for kind: HistoryStateColorKind) -> Color {
        switch kind {
        case .active:
            accent
        case .inactive:
            Color.secondary.opacity(0.55)
        case let .palette(slot):
            paletteColor(slot: slot)
        }
    }

    /// The elevated card fill for the current appearance.
    public static func cardFill(_ scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color(red: 0.16, green: 0.17, blue: 0.19)
            : Color.white
    }

    /// The hairline card border for the current appearance.
    public static func cardBorder(_ scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color.white.opacity(0.10)
            : Color.black.opacity(0.08)
    }

    /// The soft card shadow opacity (light only; dark cards rely on the border).
    public static func cardShadow(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.clear : Color.black.opacity(0.06)
    }

    /// The appearance-aware palette for the menu-bar dashboard popover.
    ///
    /// The dashboard is designed to look intentional in **both** appearances: a
    /// graphite/dark-blue instrument panel in dark mode, and a clean light
    /// *translucent graphite* surface (not pure white) with dark, readable text in
    /// light mode. The same visual hierarchy, accents, and semantic trio carry
    /// across both; the light tokens are designed rather than mechanically
    /// inverted. Tokens are resolved against the supplied ``ColorScheme`` so the
    /// popover follows the resolved theme (system/light/dark). The Settings window
    /// keeps the separate adaptive palette above and never uses these.
    ///
    /// A ``DashboardPalette`` value-type carries the resolved colors; the
    /// ``palette(_:)`` factory builds it for an appearance. Views read tokens from
    /// the palette so a single `@Environment(\.colorScheme)` read fans out to all
    /// dashboard surfaces.
    public struct DashboardPalette: Equatable, Sendable {
        /// The deepest surface — the popover root behind everything.
        public let surfaceRoot: Color
        /// The standard module/panel surface that sits on the root.
        public let surfacePanel: Color
        /// A slightly lighter elevated panel surface (header strip, detail card).
        public let surfacePanelElevated: Color
        /// The fill of a compact inline control at rest (status capsule, switch).
        public let surfaceControl: Color
        /// The fill of a compact inline control when active/on.
        public let surfaceControlActive: Color
        /// A very-low-opacity hairline stroke for the outer surface only.
        public let borderSubtle: Color
        /// An almost-invisible separator between rows/modules.
        public let separatorSubtle: Color
        /// Near-white (dark) / dark-graphite (light) primary text.
        public let textPrimary: Color
        /// Blue-gray secondary text for labels and captions.
        public let textSecondary: Color
        /// The faintest tertiary text for units and disabled states.
        public let textTertiary: Color
        /// The secondary chart/series accent (violet/pink), shared by both schemes.
        public let chartSecondaryColor: Color
        /// The muted chart color used when no trend tint is appropriate.
        public let chartMuted: Color
        /// The track behind a micro meter / bar / ring.
        public let meterTrack: Color
        /// The soft drop-shadow color for the outer surface.
        public let shadowSoft: Color

        /// The calm blue/violet primary accent (the resolved Home Assistant blue).
        public var accentPrimary: Color { PerchHATheme.accent }
        /// The secondary accent (violet/pink), shared by both appearances.
        public var accentSecondary: Color { chartSecondaryColor }
        /// The success color (green), aligned with ``PerchHATheme/ok``.
        public var success: Color { PerchHATheme.ok }
        /// The warning color (amber), aligned with ``PerchHATheme/warn``.
        public var warning: Color { PerchHATheme.warn }
        /// The danger color (red), aligned with ``PerchHATheme/critical``.
        public var danger: Color { PerchHATheme.critical }
        /// The primary chart stroke (the accent blue).
        public var chartPrimary: Color { PerchHATheme.accent }
        /// The secondary chart stroke (the violet/pink secondary accent).
        public var chartSecondary: Color { chartSecondaryColor }

        // MARK: Compatibility aliases

        /// Compatibility alias for ``surfaceRoot``.
        public var popoverBackground: Color { surfaceRoot }
        /// Compatibility alias for ``surfaceRoot``.
        public var appBackground: Color { surfaceRoot }
        /// Compatibility alias for ``surfacePanel``.
        public var cardBackground: Color { surfacePanel }
        /// Compatibility alias for ``surfacePanelElevated``.
        public var cardBackgroundElevated: Color { surfacePanelElevated }
        /// Compatibility alias for ``borderSubtle``.
        public var borderEmphatic: Color { borderSubtle }
        /// Compatibility alias for ``separatorSubtle``.
        public var separator: Color { separatorSubtle }
        /// Compatibility alias for ``meterTrack``.
        public var chartTrack: Color { meterTrack }
        /// Compatibility alias for ``warning``.
        public var accentWarning: Color { warning }
        /// Compatibility alias for ``success``.
        public var accentSuccess: Color { success }
        /// Compatibility alias for ``danger``.
        public var accentDanger: Color { danger }

        /// The semantic color for a connection state, used by the status pill and
        /// the header status dot.
        ///
        /// - Parameter state: The current connection state.
        /// - Returns: Success for connected, warning while connecting/reconnecting,
        ///   danger for failed, and the muted secondary text color when
        ///   disconnected.
        public func connectionColor(_ state: ConnectionState) -> Color {
            switch state {
            case .connected:
                success
            case .connecting, .reconnecting:
                warning
            case .failed:
                danger
            case .disconnected:
                textSecondary
            }
        }

        /// The semantic color for a value severity, resolved against this palette.
        ///
        /// - Parameter severity: The value severity.
        /// - Returns: The primary accent for normal, warning for warning, danger
        ///   for critical.
        public func severityColor(_ severity: ValueSeverity) -> Color {
            switch severity {
            case .normal:
                accentPrimary
            case .warning:
                warning
            case .critical:
                danger
            }
        }
    }

    public enum Dashboard {
        /// A violet/pink secondary-series accent, shared by both appearances.
        public static let accentSecondary = Color(red: 0.71, green: 0.55, blue: 0.93)

        /// The warning accent (amber), aligned with ``PerchHATheme/warn``.
        public static let accentWarning = PerchHATheme.warn

        /// The success accent (green), aligned with ``PerchHATheme/ok``.
        public static let accentSuccess = PerchHATheme.ok

        /// The danger accent (red), aligned with ``PerchHATheme/critical``.
        public static let accentDanger = PerchHATheme.critical

        /// The primary accent (the calm Home Assistant blue, resolved live).
        public static var accentPrimary: Color { PerchHATheme.accent }

        /// The outer corner radius of the dashboard panel surface.
        public static let panelCornerRadius: CGFloat = 20

        /// Builds the resolved dashboard palette for an appearance.
        ///
        /// - Parameter scheme: The resolved color scheme.
        /// - Returns: A ``DashboardPalette`` with designed light or dark tokens.
        public static func palette(_ scheme: ColorScheme) -> DashboardPalette {
            scheme == .dark ? darkPalette : lightPalette
        }

        /// The dark instrument-panel palette: deep graphite/navy root, a slightly
        /// lighter panel, near-white primary text, blue-gray secondary, calm
        /// blue/violet accents, and almost-invisible strokes/separators.
        public static let darkPalette = DashboardPalette(
            surfaceRoot: Color(red: 0.055, green: 0.063, blue: 0.082),
            surfacePanel: Color(red: 0.086, green: 0.098, blue: 0.122),
            surfacePanelElevated: Color(red: 0.122, green: 0.137, blue: 0.165),
            surfaceControl: Color.white.opacity(0.07),
            surfaceControlActive: PerchHATheme.accent.opacity(0.22),
            borderSubtle: Color.white.opacity(0.07),
            separatorSubtle: Color.white.opacity(0.05),
            textPrimary: Color(red: 0.93, green: 0.95, blue: 0.97),
            textSecondary: Color(red: 0.60, green: 0.65, blue: 0.74),
            textTertiary: Color(red: 0.42, green: 0.47, blue: 0.55),
            chartSecondaryColor: accentSecondary,
            chartMuted: Color.white.opacity(0.22),
            meterTrack: Color.white.opacity(0.10),
            shadowSoft: Color.black.opacity(0.55)
        )

        /// The light palette: a soft translucent light-graphite root (not pure
        /// white), a slightly elevated off-white panel, dark-graphite text, and the
        /// same calm hierarchy and accents as the dark palette — designed, not
        /// mechanically inverted.
        public static let lightPalette = DashboardPalette(
            surfaceRoot: Color(red: 0.90, green: 0.91, blue: 0.94),
            surfacePanel: Color(red: 0.965, green: 0.970, blue: 0.985),
            surfacePanelElevated: Color.white,
            surfaceControl: Color.black.opacity(0.05),
            surfaceControlActive: PerchHATheme.accent.opacity(0.16),
            borderSubtle: Color.black.opacity(0.07),
            separatorSubtle: Color.black.opacity(0.06),
            textPrimary: Color(red: 0.11, green: 0.13, blue: 0.18),
            textSecondary: Color(red: 0.34, green: 0.38, blue: 0.45),
            textTertiary: Color(red: 0.54, green: 0.58, blue: 0.65),
            chartSecondaryColor: accentSecondary,
            chartMuted: Color.black.opacity(0.22),
            meterTrack: Color.black.opacity(0.08),
            shadowSoft: Color.black.opacity(0.18)
        )
    }

    /// The subtle fill of an inset capsule control (search field, footer bar).
    ///
    /// - Parameter scheme: The current appearance.
    /// - Returns: A faint, appearance-aware fill that reads as recessed.
    public static func insetControlFill(_ scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color.white.opacity(0.07)
            : Color.black.opacity(0.05)
    }

    /// The hairline stroke of an inset capsule control.
    ///
    /// - Parameter scheme: The current appearance.
    /// - Returns: A faint, appearance-aware border for inset controls.
    public static func insetControlStroke(_ scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color.white.opacity(0.08)
            : Color.black.opacity(0.07)
    }
}

private struct DashboardPaletteKey: EnvironmentKey {
    static let defaultValue = PerchHATheme.Dashboard.darkPalette
}

private struct DashboardRowDensityKey: EnvironmentKey {
    static let defaultValue = PerchHADashboardRowDensity.defaultDensity
}

public extension EnvironmentValues {
    /// The resolved dashboard palette for the current appearance.
    ///
    /// The panel root resolves this once from `@Environment(\.colorScheme)` and
    /// injects it; dashboard surfaces read it instead of resolving the scheme
    /// themselves, so the whole popover shares one designed light/dark palette.
    var dashboardPalette: PerchHATheme.DashboardPalette {
        get { self[DashboardPaletteKey.self] }
        set { self[DashboardPaletteKey.self] = newValue }
    }

    /// The dashboard telemetry-row density.
    ///
    /// Injected once by the panel root from the user's display preferences;
    /// ``TelemetryRow`` reads it to tighten or relax its vertical metrics so the
    /// whole dashboard shares one density.
    var dashboardRowDensity: PerchHADashboardRowDensity {
        get { self[DashboardRowDensityKey.self] }
        set { self[DashboardRowDensityKey.self] = newValue }
    }
}

/// A bespoke, borderless icon (or icon+label) button tinted to the theme accent.
///
/// Replaces stock bordered push buttons in the panel footer, the cover controls,
/// and the settings reorder/affordance controls. The control keeps its caller's
/// action, `help`, and accessibility labels; this style only changes the look:
/// a rounded hover/press chip, accent tint on hover and press, secondary tint at
/// rest, and a dimmed look while disabled. It adds no animation timer.
public struct PerchHAIconButtonStyle: ButtonStyle {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovering = false
    private let prominentOnHover: Bool

    /// Creates the style.
    ///
    /// - Parameter prominentOnHover: When `true`, the hover/press chip fills with
    ///   the accent and the glyph turns white (used for the primary footer
    ///   affordance); otherwise the glyph tints to the accent over a faint chip.
    public init(prominentOnHover: Bool = false) {
        self.prominentOnHover = prominentOnHover
    }

    public func makeBody(configuration: Configuration) -> some View {
        let active = (isHovering || configuration.isPressed) && isEnabled
        let foreground: Color = {
            if !isEnabled {
                return Color.secondary.opacity(0.5)
            }
            if active {
                return prominentOnHover ? Color.white : PerchHATheme.accent
            }
            return Color.secondary
        }()
        let chip: Color = {
            guard active else {
                return .clear
            }
            return prominentOnHover
                ? PerchHATheme.accent
                : PerchHATheme.accent.opacity(0.16)
        }()
        return configuration.label
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(foreground)
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous).fill(chip)
            )
            .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            .opacity(configuration.isPressed && isEnabled ? 0.85 : 1)
            .onHover { hovering in
                isHovering = hovering
            }
    }
}

/// A bespoke, borderless circular icon button used for the panel's cover
/// open/stop/close controls and similar single-glyph actions.
///
/// At rest the glyph is secondary over a faint circular well; on hover/press the
/// well tints to the accent and the glyph turns accent. The caller keeps its
/// action, `help`, and accessibility labels. No animation timer is used.
public struct PerchHACircularIconButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovering = false
    private let diameter: CGFloat

    public init(diameter: CGFloat = 24) {
        self.diameter = diameter
    }

    public func makeBody(configuration: Configuration) -> some View {
        let active = (isHovering || configuration.isPressed) && isEnabled
        let foreground: Color = {
            if !isEnabled {
                return Color.secondary.opacity(0.5)
            }
            return active ? PerchHATheme.accent : Color.secondary
        }()
        return configuration.label
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(foreground)
            .frame(width: diameter, height: diameter)
            .background(
                Circle().fill(active ? PerchHATheme.accent.opacity(0.16) : Color.primary.opacity(0.05))
            )
            .contentShape(Circle())
            .opacity(configuration.isPressed && isEnabled ? 0.85 : 1)
            .onHover { hovering in
                isHovering = hovering
            }
    }
}

/// A bespoke circular icon label with a hover/disabled-aware accent chip, drawn
/// as the *label* of a native borderless `Button` so the control keeps its
/// native AppKit backing (keyboard focus, responder behavior, accessibility)
/// while still presenting the bespoke circular look. Used for the panel's cover
/// open/stop/close controls.
public struct PerchHACircularIconLabel: View {
    @State private var isHovering = false
    private let icon: String
    private let disabled: Bool
    private let diameter: CGFloat

    public init(icon: String, disabled: Bool, diameter: CGFloat = 24) {
        self.icon = icon
        self.disabled = disabled
        self.diameter = diameter
    }

    public var body: some View {
        let active = isHovering && !disabled
        let foreground: Color = disabled
            ? Color.secondary.opacity(0.5)
            : (active ? PerchHATheme.accent : Color.secondary)
        return Image(systemName: icon)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(foreground)
            .frame(width: diameter, height: diameter)
            .background(
                Circle().fill(active ? PerchHATheme.accent.opacity(0.16) : Color.primary.opacity(0.05))
            )
            .contentShape(Circle())
            .onHover { hovering in
                isHovering = hovering
            }
    }
}

/// A bespoke inset capsule wrapper that hosts an existing control (typically the
/// native search field) behind a subtle fill, a hairline stroke, and an inset
/// leading glyph — eliminating the stock square text-field bezel while keeping
/// the wrapped control's behavior and accessibility intact.
public struct PerchHACapsuleField<Content: View>: View {
    @Environment(\.colorScheme) private var colorScheme
    private let systemImage: String
    private let content: Content

    /// Creates the capsule field.
    ///
    /// - Parameters:
    ///   - systemImage: The inset leading SF Symbol (e.g. `magnifyingglass`).
    ///   - content: The wrapped input control.
    public init(systemImage: String, @ViewBuilder content: () -> Content) {
        self.systemImage = systemImage
        self.content = content()
    }

    public var body: some View {
        let shape = Capsule(style: .continuous)
        HStack(spacing: 6) {
            Image(systemName: systemImage)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            content
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(PerchHATheme.insetControlFill(colorScheme), in: shape)
        .overlay(shape.strokeBorder(PerchHATheme.insetControlStroke(colorScheme), lineWidth: 1))
        .clipShape(shape)
    }
}

public extension View {
    /// Applies the bespoke compact look shared by the settings pickers and
    /// steppers: a borderless menu/stepper tinted to the accent at a small
    /// control size. Behavior, keyboard handling, and accessibility are
    /// unchanged.
    func perchHACompactControl() -> some View {
        self
            .controlSize(.small)
            .tint(PerchHATheme.accent)
    }
}

/// A reusable, adaptive elevated card surface that groups room rows.
///
/// Light: a near-white card with a hairline border and a very soft shadow.
/// Dark: a slightly elevated dark card with a hairline border (no shadow).
public struct PerchHACard<Content: View>: View {
    @Environment(\.colorScheme) private var colorScheme
    private let cornerRadius: CGFloat
    private let content: Content

    public init(cornerRadius: CGFloat = 10, @ViewBuilder content: () -> Content) {
        self.cornerRadius = cornerRadius
        self.content = content()
    }

    public var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        content
            .background(PerchHATheme.cardFill(colorScheme), in: shape)
            .overlay(shape.strokeBorder(PerchHATheme.cardBorder(colorScheme), lineWidth: 1))
            .clipShape(shape)
            .shadow(color: PerchHATheme.cardShadow(colorScheme), radius: 3, x: 0, y: 1)
    }
}
