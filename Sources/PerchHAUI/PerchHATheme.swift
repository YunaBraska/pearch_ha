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

    /// The fixed dark palette for the menu-bar dashboard popover.
    ///
    /// Unlike the rest of ``PerchHATheme``, these values do **not** adapt to the
    /// system appearance: the dashboard renders dark in both light and dark mode
    /// (a deliberate, iStat-Menus-class "instrument panel" look). The numbers are
    /// graphite/blue-leaning so the calm Home Assistant ``accent`` blue and the
    /// semantic trio read cleanly against them. The Settings window keeps the
    /// adaptive palette above and never uses these.
    public enum Dashboard {
        /// The opaque base fill of the panel, behind the translucent material.
        ///
        /// A deep graphite-blue. Painted edge-to-edge so the popover never shows a
        /// transparent seam and the material has something dark to sample.
        public static let panelBackground = Color(red: 0.071, green: 0.078, blue: 0.094)

        /// The room/metric card fill — a hair lighter than the panel.
        public static let cardBackground = Color(red: 0.110, green: 0.122, blue: 0.145)

        /// An elevated card fill for the header summary strip and hovered surfaces.
        public static let cardBackgroundElevated = Color(red: 0.145, green: 0.161, blue: 0.188)

        /// The hairline border drawn around cards and the panel (white ≈ 0.08).
        public static let borderSubtle = Color.white.opacity(0.08)

        /// A slightly stronger hairline for the outer panel edge (white ≈ 0.10).
        public static let borderEmphatic = Color.white.opacity(0.10)

        /// The near-white primary text color for values and titles.
        public static let textPrimary = Color(red: 0.93, green: 0.95, blue: 0.97)

        /// The muted blue-gray secondary text color for labels and captions.
        public static let textSecondary = Color(red: 0.62, green: 0.66, blue: 0.73)

        /// The faint tertiary text color for de-emphasized hints.
        public static let textTertiary = Color(red: 0.44, green: 0.48, blue: 0.55)

        /// The primary accent (the calm Home Assistant blue, resolved live).
        public static var accentPrimary: Color { PerchHATheme.accent }

        /// A violet/pink secondary-series accent for secondary data.
        public static let accentSecondary = Color(red: 0.71, green: 0.55, blue: 0.93)

        /// The warning accent (amber), aligned with ``PerchHATheme/warn``.
        public static let accentWarning = PerchHATheme.warn

        /// The success accent (green), aligned with ``PerchHATheme/ok``.
        public static let accentSuccess = PerchHATheme.ok

        /// The danger accent (red), aligned with ``PerchHATheme/critical``.
        public static let accentDanger = PerchHATheme.critical

        /// The muted gray-blue track behind gauges and bars.
        public static let trackColor = Color.white.opacity(0.10)

        /// The outer corner radius of the dashboard panel surface.
        public static let panelCornerRadius: CGFloat = 20

        /// The semantic color for a connection state, used by the status pill and
        /// the header status dot.
        ///
        /// - Parameter state: The current connection state.
        /// - Returns: Success for connected, warning while connecting/reconnecting,
        ///   danger for failed, and the muted secondary text color when
        ///   disconnected.
        public static func connectionColor(_ state: ConnectionState) -> Color {
            switch state {
            case .connected:
                accentSuccess
            case .connecting, .reconnecting:
                accentWarning
            case .failed:
                accentDanger
            case .disconnected:
                textSecondary
            }
        }
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
