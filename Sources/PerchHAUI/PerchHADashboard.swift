import SwiftUI
import PerchHACore

// MARK: - Status pill

/// A compact, text-bearing status control for boolean / discrete states.
///
/// The pill always carries its label text (never color alone), tinted to a
/// semantic color over a faint matching well. Active states fill more strongly;
/// inactive/unavailable states stay quiet. The caller supplies the accessibility
/// label so the pill can be hidden from assistive tech when its text is already
/// announced by a parent element.
public struct StatusPill: View {
    private let text: String
    private let systemImage: String?
    private let color: Color
    private let filled: Bool
    private let accessibilityLabel: String?

    /// Creates a status pill.
    ///
    /// - Parameters:
    ///   - text: The visible label (also the default accessibility label).
    ///   - systemImage: An optional leading SF Symbol.
    ///   - color: The semantic tint for the glyph, text, and well.
    ///   - filled: When `true`, the pill fills with the tint and the text turns
    ///     white (active states); otherwise the tint is used as text over a faint
    ///     well.
    ///   - accessibilityLabel: An explicit accessibility label; when `nil` the
    ///     visible `text` is used.
    public init(
        _ text: String,
        systemImage: String? = nil,
        color: Color,
        filled: Bool = false,
        accessibilityLabel: String? = nil
    ) {
        self.text = text
        self.systemImage = systemImage
        self.color = color
        self.filled = filled
        self.accessibilityLabel = accessibilityLabel
    }

    public var body: some View {
        HStack(spacing: 3) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: 8, weight: .bold))
                    .accessibilityHidden(true)
            }
            Text(text)
                .font(.system(size: 10.5, weight: .semibold))
                .textCase(.uppercase)
                .tracking(0.4)
                .lineLimit(1)
                .fixedSize()
        }
        .foregroundStyle(filled ? Color.white : color)
        .padding(.horizontal, 7)
        .padding(.vertical, 2.5)
        .background(
            Capsule(style: .continuous).fill(filled ? color : color.opacity(0.16))
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel ?? text)
    }
}

// MARK: - Compact switch

/// A compact, native on/off switch for telemetry rows.
///
/// It wraps a native SwiftUI `Toggle` in the `switch` style at the mini control
/// size and tints it to the accent, so it stays a real, keyboard-focusable
/// platform switch (preserving the switch accessibility role and first-responder
/// behavior) while reading as a small cockpit control rather than a full-size
/// toggle. While `isRunning` it disables hits and dims slightly.
public struct CompactSwitch: View {
    private let isOn: Bool
    private let isRunning: Bool
    private let onChange: (Bool) -> Void

    /// Creates the switch.
    ///
    /// - Parameters:
    ///   - isOn: The current on/off state.
    ///   - isRunning: Whether a control action is in flight (dims, disables hits).
    ///   - onChange: Called with the requested new value when toggled.
    public init(isOn: Bool, isRunning: Bool, onChange: @escaping (Bool) -> Void) {
        self.isOn = isOn
        self.isRunning = isRunning
        self.onChange = onChange
    }

    public var body: some View {
        Toggle("", isOn: binding)
            .labelsHidden()
            .toggleStyle(.switch)
            .controlSize(.mini)
            .tint(PerchHATheme.accent)
            .disabled(isRunning)
            .opacity(isRunning ? 0.55 : 1)
    }

    private var binding: Binding<Bool> {
        Binding(
            get: { isOn },
            set: { onChange($0) }
        )
    }
}

// MARK: - Summary strip

/// A single compact summary readout: a small uppercase caption above a
/// monospaced-digit hero value, optionally tinted by severity.
public struct SummaryMetric: View {
    @Environment(\.dashboardPalette) private var palette
    private let caption: String
    private let value: String
    private let tint: Color?

    /// Creates the metric.
    ///
    /// - Parameters:
    ///   - caption: The small uppercase label (e.g. `"HUMIDITY"`).
    ///   - value: The monospaced hero value (e.g. `"44%"`).
    ///   - tint: An optional value tint; defaults to primary text.
    public init(caption: String, value: String, tint: Color? = nil) {
        self.caption = caption
        self.value = value
        self.tint = tint
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value)
                .font(.system(size: 16, weight: .semibold).monospacedDigit())
                .foregroundStyle(tint ?? palette.textPrimary)
                .lineLimit(1)
            Text(caption)
                .font(.system(size: 9, weight: .semibold))
                .textCase(.uppercase)
                .tracking(0.5)
                .foregroundStyle(palette.textTertiary)
                .lineLimit(1)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(caption), \(value)")
    }
}

/// The header's horizontal strip of compact summary readouts.
///
/// Renders up to a few ``SummaryMetric`` values separated by faint dividers. It
/// draws nothing when there are no metrics, so the header never shows empty
/// decoration.
public struct SummaryStrip: View {
    @Environment(\.dashboardPalette) private var palette
    private let metrics: [SummaryStripMetric]

    /// Creates the strip.
    ///
    /// - Parameter metrics: The resolved metrics, in display order.
    public init(metrics: [SummaryStripMetric]) {
        self.metrics = metrics
    }

    public var body: some View {
        if metrics.isEmpty {
            EmptyView()
        } else {
            HStack(spacing: 14) {
                ForEach(Array(metrics.enumerated()), id: \.offset) { index, metric in
                    if index > 0 {
                        Rectangle()
                            .fill(palette.separatorSubtle)
                            .frame(width: 1, height: 24)
                    }
                    SummaryMetric(caption: metric.caption, value: metric.value, tint: metric.tint)
                }
                Spacer(minLength: 0)
            }
        }
    }
}

/// A resolved summary-strip metric value. Pure data so the header can be built
/// from a snapshot without SwiftUI.
public struct SummaryStripMetric: Equatable {
    public let caption: String
    public let value: String
    public let tint: Color?

    public init(caption: String, value: String, tint: Color? = nil) {
        self.caption = caption
        self.value = value
        self.tint = tint
    }
}

// MARK: - Header

/// The dashboard header: a tiny connection dot + brand on one line, with a
/// compact summary strip of monospaced readouts below.
///
/// No refresh button and no warning count — values auto-update and diagnostics
/// live in Settings. Settings/quit live only in the footer. The header is part of
/// the single surface: it has padding but no border or card of its own.
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
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Circle()
                    .fill(palette.connectionColor(summary.connectionState))
                    .frame(width: 7, height: 7)
                    .accessibilityHidden(true)
                Text("PearchHA")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(palette.textPrimary)
                Spacer(minLength: 0)
            }
            SummaryStrip(metrics: metrics)
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 12)
    }

    private var metrics: [SummaryStripMetric] {
        var result: [SummaryStripMetric] = [
            SummaryStripMetric(
                caption: "Status",
                value: summary.connectionLabel,
                tint: palette.connectionColor(summary.connectionState)
            )
        ]
        // When the user has chosen explicit summary metrics, render those in
        // order (with muted placeholders for unavailable entities) instead of the
        // auto-derived primary metric and alert count. The status pill above is
        // kept regardless of the selection.
        if !summary.selectedMetrics.isEmpty {
            for metric in summary.selectedMetrics {
                result.append(
                    SummaryStripMetric(
                        caption: metric.name,
                        value: metric.valueText,
                        tint: metric.isAvailable ? nil : palette.textTertiary
                    )
                )
            }
            return result
        }
        if let metric = summary.primaryMetric {
            result.append(
                SummaryStripMetric(
                    caption: metric.name,
                    value: metric.valueText,
                    tint: metric.severity == .normal ? nil : palette.severityColor(metric.severity)
                )
            )
        }
        if let warnings = summary.warningCount, warnings > 0 {
            result.append(
                SummaryStripMetric(
                    caption: "Alerts",
                    value: "\(warnings)",
                    tint: palette.warning
                )
            )
        }
        return result
    }
}

// MARK: - Module block

/// A small uppercase, tracked module label that introduces a group of rows.
///
/// It is *not* a card title bar — it has no border or fill. An optional trailing
/// count sits muted at the end (e.g. how many rows are hidden behind "More").
public struct ModuleHeader: View {
    @Environment(\.dashboardPalette) private var palette
    private let title: String
    private let trailingText: String?

    /// Creates the header.
    ///
    /// - Parameters:
    ///   - title: The label text, rendered uppercased.
    ///   - trailingText: An optional muted trailing caption.
    public init(_ title: String, trailingText: String? = nil) {
        self.title = title
        self.trailingText = trailingText
    }

    public var body: some View {
        HStack(spacing: 6) {
            Text(title)
                .font(.system(size: 10.5, weight: .semibold))
                .textCase(.uppercase)
                .tracking(0.8)
                .foregroundStyle(palette.textSecondary)
                .lineLimit(1)
            Spacer(minLength: 0)
            if let trailingText {
                Text(trailingText)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(palette.textTertiary)
                    .lineLimit(1)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
    }
}

/// A module: a small ``ModuleHeader`` above a vertical run of rows, separated
/// from neighbouring modules by spacing only.
///
/// Crucially this is NOT a bordered/elevated card. It draws no fill, no border,
/// and no rounded box — it is nearly integrated into the single popover surface.
/// The only internal decoration is an almost-invisible hairline between rows.
public struct ModuleBlock<Rows: View>: View {
    @Environment(\.dashboardPalette) private var palette
    private let title: String
    private let trailingText: String?
    private let rows: Rows

    /// Creates the module block.
    ///
    /// - Parameters:
    ///   - title: The module label.
    ///   - trailingText: An optional muted trailing caption on the header.
    ///   - rows: The module's rows.
    public init(
        title: String,
        trailingText: String? = nil,
        @ViewBuilder rows: () -> Rows
    ) {
        self.title = title
        self.trailingText = trailingText
        self.rows = rows()
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ModuleHeader(title, trailingText: trailingText)
                .padding(.horizontal, 16)
                .padding(.bottom, 2)
            VStack(spacing: 0) {
                rows
            }
        }
    }
}

/// An almost-invisible inset separator drawn between telemetry rows. It insets
/// from the leading edge so it aligns under the label, not the icon.
public struct TelemetryRowSeparator: View {
    @Environment(\.dashboardPalette) private var palette

    public init() {}

    public var body: some View {
        Rectangle()
            .fill(palette.separatorSubtle)
            .frame(height: 1)
            .padding(.leading, 44)
    }
}

// MARK: - Telemetry row

/// The fixed-column geometry shared by every telemetry row so the panel reads as
/// an aligned table: the same reserved widths and preview height are used for
/// every row, whether or not its data has landed yet. Reserving the columns is
/// what keeps the cache-fill flicker-free — content lands inside a slot that was
/// already occupying its final footprint.
public enum TelemetryRowMetrics {
    /// The fixed leading icon column width.
    public static let iconWidth: CGFloat = 16
    /// The reserved history-preview column width (micro chart or placeholder).
    public static let previewWidth: CGFloat = 92
    /// The reserved history-preview column height.
    public static let previewHeight: CGFloat = 24
    /// The reserved value/status column minimum width, right-aligned.
    public static let valueMinWidth: CGFloat = 66
    /// The reserved trailing control column width so toggles align across rows.
    public static let controlWidth: CGFloat = 38
}

/// A compact, single-line telemetry row — the cockpit replacement for the old
/// entity row.
///
/// Layout is a fixed-column reserved grid so every row lines up like a table and
/// nothing reflows when cached data arrives:
/// `[icon 16] [label (+ subtitle), flexible] [preview 92×24] [value ≥66] [control 38]`.
/// Each non-flexible column is a reserved fixed (or fixed-min) width that is
/// always present, so a row that has no cached history shows a muted placeholder
/// in the same footprint a chart would occupy. The `preview`, `value`, and
/// `control` slots are supplied by the caller (which decides chart-vs-placeholder
/// and value-vs-dash) so the row stays a thin, reusable renderer that only owns
/// alignment. Accessibility is framed by the caller via the row label.
public struct TelemetryRow<Preview: View, Value: View, Control: View>: View {
    @Environment(\.dashboardPalette) private var palette
    @Environment(\.dashboardRowDensity) private var rowDensity
    private let icon: String
    private let iconActive: Bool
    private let label: String
    private let subtitle: String?
    private let secondLine: AnyView?
    private let preview: Preview
    private let value: Value
    private let control: Control

    /// Creates a telemetry row.
    ///
    /// - Parameters:
    ///   - icon: The leading SF Symbol.
    ///   - iconActive: When `true` the icon takes the accent tint; otherwise muted.
    ///   - label: The single-line entity name.
    ///   - subtitle: An optional tiny muted subtitle (e.g. a unit).
    ///   - secondLine: An optional compact second line (e.g. cover controls).
    ///   - preview: The reserved history-preview column (micro chart or muted
    ///     placeholder); always present so swapping placeholder→chart never
    ///     changes row height or shifts neighbors.
    ///   - value: The reserved right-aligned value/status column (or a muted
    ///     placeholder when the value is not yet known).
    ///   - control: The reserved trailing control column (e.g. a toggle), or an
    ///     empty view when the row exposes no control; the slot stays reserved so
    ///     controls align across rows.
    public init(
        icon: String,
        iconActive: Bool,
        label: String,
        subtitle: String? = nil,
        secondLine: AnyView? = nil,
        @ViewBuilder preview: () -> Preview,
        @ViewBuilder value: () -> Value,
        @ViewBuilder control: () -> Control
    ) {
        self.icon = icon
        self.iconActive = iconActive
        self.label = label
        self.subtitle = subtitle
        self.secondLine = secondLine
        self.preview = preview()
        self.value = value()
        self.control = control()
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 14))
                    .frame(width: TelemetryRowMetrics.iconWidth, alignment: .center)
                    .foregroundStyle(iconActive ? palette.accentPrimary : palette.textTertiary)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 0) {
                    Text(label)
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(palette.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                    if let subtitle {
                        Text(subtitle)
                            .font(.system(size: 10))
                            .foregroundStyle(palette.textTertiary)
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .layoutPriority(1)
                preview
                    .frame(
                        width: TelemetryRowMetrics.previewWidth,
                        height: TelemetryRowMetrics.previewHeight,
                        alignment: .center
                    )
                value
                    .frame(minWidth: TelemetryRowMetrics.valueMinWidth, alignment: .trailing)
                control
                    .frame(width: TelemetryRowMetrics.controlWidth, alignment: .trailing)
            }
            secondLine
        }
        .padding(.horizontal, 16)
        .padding(.vertical, rowDensity == .compact ? 4 : 7)
        .frame(minHeight: rowDensity == .compact ? 30 : 38)
        .contentShape(Rectangle())
    }
}

/// A muted reserved-slot placeholder: a faint baseline dash filling the history
/// preview column when an entity has no cached history yet. It occupies the same
/// footprint as a micro chart so the column never changes geometry when real data
/// lands — calm, not a shimmering skeleton.
public struct TelemetryPreviewPlaceholder: View {
    @Environment(\.dashboardPalette) private var palette

    /// Creates the placeholder.
    public init() {}

    public var body: some View {
        MicroDash(color: palette.meterTrack)
            .frame(width: TelemetryRowMetrics.previewWidth, height: 7)
            .accessibilityHidden(true)
    }
}

// MARK: - Footer

/// The dashboard footer: a quiet anchored bar with a connection dot, a calm
/// "updated" caption, and small settings / quit icon buttons over a subtle top
/// separator.
///
/// No refresh control; values auto-update while the panel is open. Each control
/// keeps its action and accessibility label.
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
        VStack(spacing: 0) {
            Rectangle()
                .fill(palette.separatorSubtle)
                .frame(height: 1)
            HStack(spacing: 6) {
                Circle()
                    .fill(connectionColor)
                    .frame(width: 6, height: 6)
                    .accessibilityHidden(true)
                Text(updatedText)
                    .font(.system(size: 11))
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(1)
                    .accessibilityLabel("Updated \(updatedText)")
                Spacer(minLength: 4)
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
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
        }
    }
}
