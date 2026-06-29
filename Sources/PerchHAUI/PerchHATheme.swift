import SwiftUI
import PerchHACore

/// The PerchHA design system: an adaptive, iStat-Menus-inspired palette and the
/// reusable card surface used to group rooms.
///
/// Colors are resolved per `ColorScheme` so the panel reads cleanly in both
/// light and dark appearances. The accent is a Home Assistant blue; the semantic
/// trio (`ok`/`warn`/`critical`) drives gauges, pills, and the timeline.
public enum PerchHATheme {
    /// The Home Assistant accent blue (≈ `#03A9F4`).
    public static let accent = Color(red: 0x03 / 255, green: 0xA9 / 255, blue: 0xF4 / 255)

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
