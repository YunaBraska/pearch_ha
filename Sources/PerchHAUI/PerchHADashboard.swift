import SwiftUI
import PerchHACore

/// An appearance-aware elevated card surface for the dashboard popover.
///
/// Reads the resolved ``PerchHATheme/DashboardPalette`` from the environment so it
/// renders as a graphite instrument-panel card in dark mode and a clean light
/// translucent-graphite card in light mode: a card fill, a subtle hairline
/// border, and no shadow (the border carries the separation).
public struct PerchHADashboardCard<Content: View>: View {
    @Environment(\.dashboardPalette) private var palette
    private let cornerRadius: CGFloat
    private let elevated: Bool
    private let content: Content

    /// Creates the card.
    ///
    /// - Parameters:
    ///   - cornerRadius: The corner radius (defaults to the card radius token).
    ///   - elevated: When `true`, uses the slightly lighter elevated fill (for the
    ///     header summary strip); otherwise the standard card fill.
    ///   - content: The card contents.
    public init(
        cornerRadius: CGFloat = PerchHACornerRadius.card,
        elevated: Bool = false,
        @ViewBuilder content: () -> Content
    ) {
        self.cornerRadius = cornerRadius
        self.elevated = elevated
        self.content = content()
    }

    public var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        let fill = elevated ? palette.cardBackgroundElevated : palette.cardBackground
        content
            .background(fill, in: shape)
            .overlay(shape.strokeBorder(palette.borderSubtle, lineWidth: 1))
            .clipShape(shape)
    }
}

/// A compact, text-bearing status pill for the dashboard.
///
/// The pill always carries its label text (never color alone), tinted to a
/// semantic color over a faint matching well. Used by the header status pill. The
/// caller supplies the accessibility label so the pill can be hidden from
/// assistive tech when its text is already announced by a parent element.
public struct StatusPill: View {
    private let text: String
    private let systemImage: String?
    private let color: Color
    private let accessibilityLabel: String?

    /// Creates a status pill.
    ///
    /// - Parameters:
    ///   - text: The visible label (also the default accessibility label).
    ///   - systemImage: An optional leading SF Symbol.
    ///   - color: The semantic tint for the glyph, text, and well.
    ///   - accessibilityLabel: An explicit accessibility label; when `nil` the
    ///     visible `text` is used.
    public init(
        _ text: String,
        systemImage: String? = nil,
        color: Color,
        accessibilityLabel: String? = nil
    ) {
        self.text = text
        self.systemImage = systemImage
        self.color = color
        self.accessibilityLabel = accessibilityLabel
    }

    public var body: some View {
        HStack(spacing: PerchHASpacing.xs - 1) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: 9, weight: .bold))
                    .accessibilityHidden(true)
            }
            Text(text)
                .font(.system(size: 11, weight: .semibold))
                .lineLimit(1)
                .fixedSize()
        }
        .foregroundStyle(color)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(
            Capsule(style: .continuous).fill(color.opacity(0.16))
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel ?? text)
    }
}

/// A compact summary readout pairing a small ring gauge (or no gauge) with a hero
/// number and a muted caption, for the dashboard header strip.
///
/// Built from ``PerchHADashboardSummary/PrimaryMetric`` real data: when a fraction
/// is present a ring gauge is drawn; otherwise the number stands alone. The whole
/// readout is a single accessibility element labelled with name and value.
public struct SummaryGauge: View {
    @Environment(\.dashboardPalette) private var palette
    private let metric: PerchHADashboardSummary.PrimaryMetric

    /// Creates the summary gauge.
    ///
    /// - Parameter metric: The resolved primary metric.
    public init(metric: PerchHADashboardSummary.PrimaryMetric) {
        self.metric = metric
    }

    public var body: some View {
        let tint = metric.severity == .normal
            ? palette.accentPrimary
            : PerchHATheme.color(for: metric.severity)
        return HStack(spacing: PerchHASpacing.sm - 2) {
            if let fraction = metric.fraction {
                PerchHARingGauge(
                    fraction: fraction,
                    color: tint,
                    lineWidth: 3,
                    trackColor: palette.chartTrack
                )
                .frame(width: 24, height: 24)
            }
            VStack(alignment: .leading, spacing: 0) {
                Text(metric.valueText)
                    .font(.system(size: 15, weight: .semibold).monospacedDigit())
                    .foregroundStyle(metric.severity == .normal ? palette.textPrimary : tint)
                    .lineLimit(1)
                Text(metric.name)
                    .font(.system(size: 10))
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(1)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(metric.name), \(metric.valueText)")
    }
}

/// The dashboard header: a compact brand/title row with a connection status dot,
/// above a summary strip of real-data readouts.
///
/// The summary strip shows only the connection status pill plus an optional
/// primary metric. The unactionable warning count and the manual refresh control
/// have been removed: values auto-update and health/diagnostics live in Settings.
/// It renders fewer readouts when there is not enough real data and never draws
/// empty decoration. Search lives in the Settings window.
public struct DashboardHeader: View {
    @Environment(\.dashboardPalette) private var palette
    private let summary: PerchHADashboardSummary

    /// Creates the header.
    ///
    /// - Parameter summary: The pure summary projection built from the snapshot.
    public init(summary: PerchHADashboardSummary) {
        self.summary = summary
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: PerchHASpacing.sm + 2) {
            titleRow
            summaryStrip
        }
        .padding(.horizontal, PerchHASpacing.md)
        .padding(.top, PerchHASpacing.md)
        .padding(.bottom, PerchHASpacing.sm)
    }

    private var titleRow: some View {
        HStack(spacing: PerchHASpacing.sm - 2) {
            Circle()
                .fill(palette.connectionColor(summary.connectionState))
                .frame(width: 7, height: 7)
                .accessibilityHidden(true)
            Text("PearchHA")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(palette.textPrimary)
            Spacer(minLength: PerchHASpacing.sm)
        }
    }

    private var summaryStrip: some View {
        HStack(spacing: PerchHASpacing.sm) {
            StatusPill(
                summary.connectionLabel,
                systemImage: "circle.fill",
                color: palette.connectionColor(summary.connectionState),
                accessibilityLabel: "Connection \(summary.connectionLabel)"
            )
            if let metric = summary.primaryMetric {
                Divider()
                    .frame(height: 20)
                    .overlay(palette.borderSubtle)
                SummaryGauge(metric: metric)
            }
            Spacer(minLength: 0)
        }
    }
}

/// The dashboard footer: a quiet anchored bar with a connection indicator, a
/// calm "updated" caption, and small settings / quit icon buttons.
///
/// The manual refresh control has been removed; values auto-update while the
/// panel is open. Restrained SF Symbols over the palette; not a toolbar. Each
/// control keeps its action and accessibility label.
public struct DashboardFooter: View {
    @Environment(\.dashboardPalette) private var palette
    private let connectionColor: Color
    private let updatedText: String
    private let settingsDisabled: Bool
    private let onSettings: () -> Void
    private let onQuit: () -> Void

    /// Creates the footer.
    ///
    /// - Parameters:
    ///   - connectionColor: The status indicator color.
    ///   - updatedText: A calm relative "updated" description.
    ///   - settingsDisabled: Whether the settings control is disabled.
    ///   - onSettings: The open-settings action.
    ///   - onQuit: The quit action.
    public init(
        connectionColor: Color,
        updatedText: String,
        settingsDisabled: Bool,
        onSettings: @escaping () -> Void,
        onQuit: @escaping () -> Void
    ) {
        self.connectionColor = connectionColor
        self.updatedText = updatedText
        self.settingsDisabled = settingsDisabled
        self.onSettings = onSettings
        self.onQuit = onQuit
    }

    public var body: some View {
        HStack(spacing: PerchHASpacing.sm - 2) {
            Circle()
                .fill(connectionColor)
                .frame(width: 6, height: 6)
                .accessibilityHidden(true)
            Text(updatedText)
                .font(.system(size: 11))
                .foregroundStyle(palette.textSecondary)
                .lineLimit(1)
                .accessibilityLabel("Updated \(updatedText)")
            Spacer(minLength: PerchHASpacing.xs)
            Button(action: onSettings) {
                Image(systemName: "gearshape")
            }
            .buttonStyle(PerchHAIconButtonStyle())
            .disabled(settingsDisabled)
            .help("Settings")
            .accessibilityLabel("Settings")
            Button(action: onQuit) {
                Image(systemName: "power")
            }
            .buttonStyle(PerchHAIconButtonStyle())
            .help("Quit")
            .accessibilityLabel("Quit")
        }
        .padding(.horizontal, PerchHASpacing.md)
        .padding(.vertical, PerchHASpacing.sm - 1)
    }
}
