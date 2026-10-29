import SwiftUI
import PearchHACore

/// Shared adaptive surfaces and accents for the panel, Settings and details.
/// Cyan provides continuity across appearances; semantic colors still identify
/// health and thresholds, and the saved accent remains user-configurable.
public enum PearchHATheme {
    /// The user-selected accent color, defaulting to the Home Assistant blue
    /// (≈ `#03A9F4`).
    ///
    /// The accent is a process-wide source of truth read by both the panel and
    /// the settings window so a change is reflected everywhere immediately. It is
    /// only mutated on the main thread (via ``apply(accentColor:)``) and only read
    /// from main-thread SwiftUI/AppKit render passes, so no cross-thread
    /// coordination is required.
    public static var accent: Color {
        let accentColor = accentSnapshot.raw
        return Color(
            .sRGB,
            red: accentColor.red,
            green: accentColor.green,
            blue: accentColor.blue,
            opacity: accentColor.alpha
        )
    }

    /// Raw color and its four foreground variants are replaced together by the
    /// appearance owner. Render passes only read this immutable snapshot.
    private struct AccentSnapshot {
        let raw: PearchHAAccentColor
        let light: Color
        let dark: Color
        let increasedLight: Color
        let increasedDark: Color

        init(_ accent: PearchHAAccentColor) {
            raw = accent
            light = readableAccent(accent, for: .light)
            dark = readableAccent(accent, for: .dark)
            increasedLight = readableAccent(accent, for: .light, increasedContrast: true)
            increasedDark = readableAccent(accent, for: .dark, increasedContrast: true)
        }
    }

    nonisolated(unsafe) private static var accentSnapshot = AccentSnapshot(.homeAssistantBlue)

    /// Applies the persisted accent color so the panel and settings reflect it.
    ///
    /// - Parameter accentColor: The accent color to use process-wide.
    @MainActor
    public static func apply(accentColor: PearchHAAccentColor) {
        guard accentSnapshot.raw != accentColor else { return }
        accentSnapshot = AccentSnapshot(accentColor)
    }

    /// Resolves readable foreground ink without changing the saved accent.
    ///
    /// The original hue is blended only as far toward black (light appearance)
    /// or white (dark appearance) as needed. Translucent foregrounds gain opacity
    /// when required. Content surfaces and raw accent selection/hover fills are
    /// included in the calculation. Increased Contrast targets 7:1; if a custom
    /// fill makes that impossible, the strongest achievable contrast is used.
    ///
    /// - Parameters:
    ///   - accent: The unchanged user-selected RGBA color.
    ///   - scheme: The appearance of the content surface.
    ///   - increasedContrast: Whether Increase Contrast is enabled.
    /// - Returns: Foreground ink targeting 4.5:1, or 7:1 with Increase Contrast.
    public static func readableAccent(
        _ accent: PearchHAAccentColor,
        for scheme: ColorScheme,
        increasedContrast: Bool = false
    ) -> Color {
        let surfaces = scheme == .dark ? Dashboard.darkSurfaces : Dashboard.lightSurfaces
        let backgroundColors = [surfaces.root, surfaces.panel, surfaces.elevated]
        let opacities = scheme == .dark ? [0, 0.16, 0.22] : [0, 0.16]
        let backgrounds = backgroundColors.flatMap { background in
            opacities.map { opacity in
                let alpha = accent.alpha * opacity
                return [accent.red * alpha + background.red * (1 - alpha),
                        accent.green * alpha + background.green * (1 - alpha),
                        accent.blue * alpha + background.blue * (1 - alpha)]
            }
        }
        let target = scheme == .dark ? 1.0 : 0.0
        // A small margin keeps conversion to native colors above the threshold.
        let requiredRatio = increasedContrast ? 7.01 : 4.51

        func luminance(_ channels: [Double]) -> Double {
            zip(channels, [0.2126, 0.7152, 0.0722]).reduce(0) { result, channel in
                let linear = channel.0 <= 0.04045 ? channel.0 / 12.92 : pow((channel.0 + 0.055) / 1.055, 2.4)
                return result + linear * channel.1
            }
        }

        func candidate(_ amount: Double) -> PearchHAAccentColor {
            PearchHAAccentColor(red: accent.red + (target - accent.red) * amount,
                               green: accent.green + (target - accent.green) * amount,
                               blue: accent.blue + (target - accent.blue) * amount,
                               alpha: accent.alpha + (1 - accent.alpha) * amount)
        }

        let backgroundLuminances = backgrounds.map(luminance)

        func minimumRatio(_ ink: PearchHAAccentColor) -> Double {
            let inkLuminance = ink.alpha == 1 ? luminance([ink.red, ink.green, ink.blue]) : nil
            // Status capsules use their readable foreground as a 16% chip fill.
            // Unlike raw selection fills, these backgrounds change with the ink.
            let derivedChips = backgroundColors.map { background in
                let alpha = ink.alpha * 0.16
                return [ink.red * alpha + background.red * (1 - alpha),
                        ink.green * alpha + background.green * (1 - alpha),
                        ink.blue * alpha + background.blue * (1 - alpha)]
            }
            return (Array(zip(backgrounds, backgroundLuminances)) + derivedChips.map { ($0, luminance($0)) })
                .reduce(Double.infinity) { minimum, entry in
                let (background, surface) = entry
                let foreground = inkLuminance ?? luminance([ink.red * ink.alpha + background[0] * (1 - ink.alpha),
                                            ink.green * ink.alpha + background[1] * (1 - ink.alpha),
                                            ink.blue * ink.alpha + background[2] * (1 - ink.alpha)])
                return min(minimum, (max(foreground, surface) + 0.05) / (min(foreground, surface) + 0.05))
            }
        }

        guard minimumRatio(accent) < requiredRatio else { return color(for: accent) }
        guard minimumRatio(candidate(1)) >= requiredRatio else { return color(for: candidate(1)) }
        var lower = 0.0
        var upper = 1.0
        for _ in 0..<24 {
            let amount = (lower + upper) / 2
            if minimumRatio(candidate(amount)) >= requiredRatio {
                upper = amount
            } else {
                lower = amount
            }
        }
        return color(for: candidate(upper))
    }

    /// A healthy/normal severity color (the Home Assistant success green,
    /// ≈ `#4CAF50`).
    public static let ok = Color(red: 0x4C / 255, green: 0xAF / 255, blue: 0x50 / 255)

    /// A warning severity color (the Home Assistant accent orange, ≈ `#FF9800`).
    public static let warn = Color(red: 0xFF / 255, green: 0x98 / 255, blue: 0x00 / 255)

    /// A critical severity color (the Home Assistant error red, ≈ `#F44336`).
    public static let critical = Color(red: 0xF4 / 255, green: 0x43 / 255, blue: 0x36 / 255)

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

    /// The concrete render color for a stored RGBA accent value.
    ///
    /// - Parameter accent: The stored color.
    /// - Returns: The SwiftUI color.
    public static func color(for accent: PearchHAAccentColor) -> Color {
        Color(red: accent.red, green: accent.green, blue: accent.blue, opacity: accent.alpha)
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

    /// The grouped content fill shared by cards in the current appearance.
    public static func cardFill(_ scheme: ColorScheme) -> Color {
        Dashboard.palette(scheme).surfacePanel
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

    /// The shared appearance-aware palette for the panel, Settings and details.
    /// Root, grouped content and elevated controls have distinct surfaces in both
    /// appearances. Opaque fills remain legible with Reduce Transparency enabled.
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

        /// The user-selected primary accent (Cyan by default).
        public let accentPrimary: Color
        /// The secondary accent (violet/pink), shared by both appearances.
        public var accentSecondary: Color { chartSecondaryColor }
        /// The success color (green), aligned with ``PearchHATheme/ok``.
        public var success: Color { PearchHATheme.ok }
        /// The warning color (amber), aligned with ``PearchHATheme/warn``.
        public var warning: Color { PearchHATheme.warn }
        /// The danger color (red), aligned with ``PearchHATheme/critical``.
        public var danger: Color { PearchHATheme.critical }
        /// The primary chart stroke (the accent blue).
        public var chartPrimary: Color { accentPrimary }
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
        static let darkSurfaces = (
            root: PearchHAAccentColor(red: 0x13 / 255, green: 0x21 / 255, blue: 0x29 / 255),
            panel: PearchHAAccentColor(red: 0x1B / 255, green: 0x2B / 255, blue: 0x34 / 255),
            elevated: PearchHAAccentColor(red: 0x26 / 255, green: 0x38 / 255, blue: 0x40 / 255)
        )
        static let lightSurfaces = (
            root: PearchHAAccentColor(red: 0xEB / 255, green: 0xF5 / 255, blue: 0xF8 / 255),
            panel: PearchHAAccentColor(red: 0xF7 / 255, green: 0xFB / 255, blue: 0xFC / 255),
            elevated: PearchHAAccentColor(red: 1, green: 1, blue: 1)
        )
        /// A violet/pink secondary-series accent, shared by both appearances.
        public static let accentSecondary = Color(red: 0.71, green: 0.55, blue: 0.93)

        /// The warning accent (amber), aligned with ``PearchHATheme/warn``.
        public static let accentWarning = PearchHATheme.warn

        /// The success accent (green), aligned with ``PearchHATheme/ok``.
        public static let accentSuccess = PearchHATheme.ok

        /// The danger accent (red), aligned with ``PearchHATheme/critical``.
        public static let accentDanger = PearchHATheme.critical

        /// The primary accent (the calm Home Assistant blue, resolved live).
        public static var accentPrimary: Color { PearchHATheme.accent }

        /// The outer corner radius of the dashboard panel surface (the Home
        /// Assistant card radius).
        public static let panelCornerRadius: CGFloat = 12

        /// Builds the resolved dashboard palette for an appearance.
        ///
        /// - Parameter scheme: The resolved color scheme.
        /// - Returns: A ``DashboardPalette`` with designed light or dark tokens.
        public static func palette(_ scheme: ColorScheme, increasedContrast: Bool = false) -> DashboardPalette {
            let surfaces = scheme == .dark ? darkSurfaces : lightSurfaces
            let snapshot = PearchHATheme.accentSnapshot
            let foreground = scheme == .dark
                ? (increasedContrast ? snapshot.increasedDark : snapshot.dark)
                : (increasedContrast ? snapshot.increasedLight : snapshot.light)
            if scheme == .dark {
                return DashboardPalette(
                    surfaceRoot: PearchHATheme.color(for: surfaces.root),
                    surfacePanel: PearchHATheme.color(for: surfaces.panel),
                    surfacePanelElevated: PearchHATheme.color(for: surfaces.elevated),
                    surfaceControl: Color.white.opacity(0.07),
                    surfaceControlActive: PearchHATheme.accent.opacity(0.22),
                    borderSubtle: Color.white.opacity(0.07),
                    separatorSubtle: Color.white.opacity(0.08),
                    textPrimary: Color(red: 0xED / 255, green: 0xF5 / 255, blue: 0xF7 / 255),
                    textSecondary: Color(red: 0xAB / 255, green: 0xBD / 255, blue: 0xC4 / 255),
                    textTertiary: Color(red: 0x97 / 255, green: 0xAC / 255, blue: 0xB5 / 255),
                    chartSecondaryColor: accentSecondary,
                    chartMuted: Color.white.opacity(0.22),
                    meterTrack: Color.white.opacity(0.10),
                    shadowSoft: Color.black.opacity(0.55),
                    accentPrimary: foreground
                )
            }
            return DashboardPalette(
                surfaceRoot: PearchHATheme.color(for: surfaces.root),
                surfacePanel: PearchHATheme.color(for: surfaces.panel),
                surfacePanelElevated: PearchHATheme.color(for: surfaces.elevated),
                surfaceControl: Color.black.opacity(0.05),
                surfaceControlActive: PearchHATheme.accent.opacity(0.16),
                borderSubtle: Color.black.opacity(0.07),
                separatorSubtle: Color.black.opacity(0.07),
                textPrimary: Color(red: 0x1B / 255, green: 0x30 / 255, blue: 0x3A / 255),
                textSecondary: Color(red: 0x50 / 255, green: 0x66 / 255, blue: 0x70 / 255),
                textTertiary: Color(red: 0x5E / 255, green: 0x73 / 255, blue: 0x7C / 255),
                chartSecondaryColor: accentSecondary,
                chartMuted: Color.black.opacity(0.22),
                meterTrack: Color.black.opacity(0.08),
                shadowSoft: Color.black.opacity(0.18),
                accentPrimary: foreground
            )
        }

        /// Cool graphite surfaces with readable blue-gray secondary text.
        public static var darkPalette: DashboardPalette { palette(.dark) }

        /// Pale Cyan surfaces with dark ink and subtly elevated content.
        public static var lightPalette: DashboardPalette { palette(.light) }
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
    static let defaultValue = PearchHATheme.Dashboard.darkPalette
}

private struct DashboardRowDensityKey: EnvironmentKey {
    static let defaultValue = PearchHADashboardRowDensity.defaultDensity
}

public extension EnvironmentValues {
    /// The resolved dashboard palette for the current appearance.
    ///
    /// The panel root resolves this once from `@Environment(\.colorScheme)` and
    /// injects it; dashboard surfaces read it instead of resolving the scheme
    /// themselves, so the whole popover shares one designed light/dark palette.
    var dashboardPalette: PearchHATheme.DashboardPalette {
        get { self[DashboardPaletteKey.self] }
        set { self[DashboardPaletteKey.self] = newValue }
    }

    /// The dashboard telemetry-row density.
    ///
    /// Injected once by the panel root from the user's display preferences;
    /// ``TelemetryRow`` reads it to tighten or relax its vertical metrics so the
    /// whole dashboard shares one density.
    var dashboardRowDensity: PearchHADashboardRowDensity {
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
public struct PearchHAIconButtonStyle: ButtonStyle {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dashboardPalette) private var palette
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
                return prominentOnHover ? (colorScheme == .dark ? Color.black : Color.white) : palette.accentPrimary
            }
            return Color.secondary
        }()
        let chip: Color = {
            guard active else {
                return .clear
            }
            return prominentOnHover
                ? palette.accentPrimary
                : PearchHATheme.accent.opacity(0.16)
        }()
        return configuration.label
            .pearchHAFont(size: 12, weight: .semibold)
            .foregroundStyle(foreground)
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous).fill(chip)
            )
            .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
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
public struct PearchHACircularIconButtonStyle: ButtonStyle {
    @Environment(\.dashboardPalette) private var palette
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
            return active ? palette.accentPrimary : Color.secondary
        }()
        return configuration.label
            .pearchHAFont(size: 11, weight: .semibold)
            .foregroundStyle(foreground)
            .frame(width: diameter, height: diameter)
            .background(
                Circle().fill(active ? PearchHATheme.accent.opacity(0.16) : Color.primary.opacity(0.05))
            )
            .contentShape(Circle())
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
public struct PearchHACircularIconLabel: View {
    @Environment(\.dashboardPalette) private var palette
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
            : (active ? palette.accentPrimary : Color.secondary)
        return Image(systemName: icon)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(foreground)
            .frame(width: diameter, height: diameter)
            .background(
                Circle().fill(active ? PearchHATheme.accent.opacity(0.16) : Color.primary.opacity(0.05))
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
public struct PearchHACapsuleField<Content: View>: View {
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
        .background(PearchHATheme.insetControlFill(colorScheme), in: shape)
        .overlay(shape.strokeBorder(PearchHATheme.insetControlStroke(colorScheme), lineWidth: 1))
        .clipShape(shape)
    }
}

public extension View {
    /// Applies the bespoke compact look shared by the settings pickers and
    /// steppers: a borderless menu/stepper tinted to the accent at a small
    /// control size. Behavior, keyboard handling, and accessibility are
    /// unchanged.
    func pearchHACompactControl() -> some View {
        self
            .controlSize(.small)
    }
}

/// A reusable, adaptive elevated card surface that groups room rows.
///
/// Light: a near-white card with a hairline border and a very soft shadow.
/// Dark: a slightly elevated dark card with a hairline border (no shadow).
public struct PearchHACard<Content: View>: View {
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
            .background(PearchHATheme.cardFill(colorScheme), in: shape)
            .overlay(shape.strokeBorder(PearchHATheme.cardBorder(colorScheme), lineWidth: 1))
            .clipShape(shape)
            .shadow(color: PearchHATheme.cardShadow(colorScheme), radius: 3, x: 0, y: 1)
    }
}

extension PearchHAAccentColor {
    /// Creates a stored RGBA value from a picked SwiftUI color.
    ///
    /// - Parameter color: The picked color.
    /// - Returns: `nil` when the color cannot be resolved into sRGB.
    public init?(_ color: Color) {
        guard let converted = NSColor(color).usingColorSpace(.sRGB) else {
            return nil
        }
        self.init(
            red: converted.redComponent,
            green: converted.greenComponent,
            blue: converted.blueComponent,
            alpha: converted.alphaComponent
        )
    }
}
