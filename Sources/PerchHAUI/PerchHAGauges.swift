import SwiftUI
import PerchHACore

/// A crisp, adaptive ring gauge drawn with a trimmed circular stroke.
///
/// The track is a faint full circle; the value arc fills clockwise from the top
/// by `fraction`. Severity tints the value arc. Reuse the pure
/// ``PerchHAEntityGauge`` fraction/severity rather than recomputing them.
public struct PerchHARingGauge: View {
    private let fraction: Double
    private let color: Color
    private let lineWidth: CGFloat
    private let trackColor: Color

    public init(fraction: Double, color: Color, lineWidth: CGFloat = 3, trackColor: Color = Color.primary.opacity(0.12)) {
        self.fraction = min(1.0, max(0.0, fraction))
        self.color = color
        self.lineWidth = lineWidth
        self.trackColor = trackColor
    }

    public var body: some View {
        ZStack {
            Circle()
                .stroke(trackColor, lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: CGFloat(fraction))
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .padding(lineWidth / 2)
        .accessibilityHidden(true)
    }
}

/// A crisp, adaptive horizontal bar gauge drawn with rounded capsules.
public struct PerchHABarGauge: View {
    private let fraction: Double
    private let color: Color
    private let trackColor: Color

    public init(fraction: Double, color: Color, trackColor: Color = Color.primary.opacity(0.12)) {
        self.fraction = min(1.0, max(0.0, fraction))
        self.color = color
        self.trackColor = trackColor
    }

    public var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(trackColor)
                Capsule()
                    .fill(color)
                    .frame(width: max(0, proxy.size.width * CGFloat(fraction)))
            }
        }
        .accessibilityHidden(true)
    }
}

/// A crisp, adaptive battery gauge: a rounded body with a nub and an interior
/// fill that grows left-to-right by `fraction`.
public struct PerchHABatteryGauge: View {
    private let fraction: Double
    private let color: Color
    private let trackColor: Color

    public init(fraction: Double, color: Color, trackColor: Color = Color.primary.opacity(0.12)) {
        self.fraction = min(1.0, max(0.0, fraction))
        self.color = color
        self.trackColor = trackColor
    }

    public var body: some View {
        GeometryReader { proxy in
            let nubWidth = max(1.5, proxy.size.width * 0.07)
            let bodyWidth = max(0, proxy.size.width - nubWidth - 1)
            let inset: CGFloat = 1.5
            let fillWidth = max(0, (bodyWidth - inset * 2) * CGFloat(fraction))
            HStack(spacing: 1) {
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                        .strokeBorder(trackColor, lineWidth: 1)
                    RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                        .fill(color)
                        .frame(width: fillWidth)
                        .padding(inset)
                }
                .frame(width: bodyWidth)
                Capsule()
                    .fill(trackColor)
                    .frame(width: nubWidth, height: proxy.size.height * 0.4)
            }
        }
        .accessibilityHidden(true)
    }
}

/// Picks the drawn gauge family for a resolved ``PerchHAEntityGauge``.
///
/// Ring gauges are square; bar/battery gauges fill the available width. The
/// gauge carries no accessibility of its own (the row labels the value).
public struct PerchHAEntityGaugeView: View {
    private let gauge: PerchHAEntityGauge

    public init(gauge: PerchHAEntityGauge) {
        self.gauge = gauge
    }

    public var body: some View {
        let color = PerchHATheme.color(for: gauge.severity)
        switch gauge.style {
        case .ring:
            PerchHARingGauge(fraction: gauge.fraction, color: color)
        case .bar:
            PerchHABarGauge(fraction: gauge.fraction, color: color)
        case .battery:
            PerchHABatteryGauge(fraction: gauge.fraction, color: color)
        }
    }
}

private struct InlineSparklinePath: Shape {
    let series: HistorySeries

    /// The fixed mini-chart sample budget for inline previews. Caps redraw cost
    /// and keeps the tiny sparkline legible.
    private static let inlineSampleBudget = 48

    func path(in rect: CGRect) -> Path {
        let geometry = PerchHAHistorySparklineGeometry(series: series, maxSamples: Self.inlineSampleBudget)
        return Path { path in
            for (index, point) in geometry.points.enumerated() {
                let cgPoint = CGPoint(
                    x: rect.minX + rect.width * CGFloat(point.x),
                    y: rect.minY + rect.height * CGFloat(point.y)
                )
                if index == 0 {
                    path.move(to: cgPoint)
                } else {
                    path.addLine(to: cgPoint)
                }
            }
        }
    }
}

// MARK: - Micro charts

/// A tiny inline trend sparkline for a numeric series, with a faint area fill
/// under the stroke so it reads as a telemetry trace rather than a single hair.
///
/// Inline only: it draws a thin stroke and a translucent fill, no axes, no inner
/// labels. It never fetches; callers hand it an already-resolved numeric series.
/// When the series has fewer than two numeric samples it draws a muted baseline
/// dash instead of a fake trace.
public struct MicroSparkline: View {
    private let series: HistorySeries
    private let color: Color
    private let muted: Color

    /// Creates the sparkline.
    ///
    /// - Parameters:
    ///   - series: The already-resolved numeric history series.
    ///   - color: The stroke and fill tint.
    ///   - muted: The dash color used when there is not enough data.
    public init(series: HistorySeries, color: Color, muted: Color) {
        self.series = series
        self.color = color
        self.muted = muted
    }

    public var body: some View {
        if PerchHAHistoryCursor.numericSamples(of: series).count > 1 {
            ZStack {
                InlineSparklineArea(series: series)
                    .fill(
                        LinearGradient(
                            colors: [color.opacity(0.22), color.opacity(0.0)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                InlineSparklinePath(series: series)
                    .stroke(color, style: StrokeStyle(lineWidth: 1.4, lineCap: .round, lineJoin: .round))
            }
            .accessibilityHidden(true)
        } else {
            MicroDash(color: muted)
        }
    }
}

/// A closed area under the inline sparkline trace, used for the faint gradient
/// fill. Shares the same downsampled geometry as ``InlineSparklinePath``.
private struct InlineSparklineArea: Shape {
    let series: HistorySeries
    private static let inlineSampleBudget = 48

    func path(in rect: CGRect) -> Path {
        let geometry = PerchHAHistorySparklineGeometry(series: series, maxSamples: Self.inlineSampleBudget)
        let points = geometry.points
        guard points.count > 1 else {
            return Path()
        }
        return Path { path in
            for (index, point) in points.enumerated() {
                let cgPoint = CGPoint(
                    x: rect.minX + rect.width * CGFloat(point.x),
                    y: rect.minY + rect.height * CGFloat(point.y)
                )
                if index == 0 {
                    path.move(to: cgPoint)
                } else {
                    path.addLine(to: cgPoint)
                }
            }
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
            path.closeSubpath()
        }
    }
}

/// A short muted baseline dash, drawn when a micro chart has no real history so
/// the row shows a calm placeholder rather than a fabricated dramatic trace.
public struct MicroDash: View {
    private let color: Color

    /// Creates the dash.
    ///
    /// - Parameter color: The muted dash tint.
    public init(color: Color) {
        self.color = color
    }

    public var body: some View {
        GeometryReader { proxy in
            Capsule()
                .fill(color)
                .frame(width: max(8, proxy.size.width * 0.5), height: 1.5)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
        .accessibilityHidden(true)
    }
}

/// A tiny inline count-trace drawn as a row of vertical activity bars (the
/// non-numeric / state-band counterpart of ``MicroSparkline``).
///
/// It renders the series' state-timeline bands as a compact band strip — useful
/// for on/off and discrete-state entities — with no axes or labels. With no
/// segments it draws a muted baseline dash.
public struct MicroActivityBars: View {
    private let series: HistorySeries
    private let muted: Color

    /// Creates the activity-band view.
    ///
    /// - Parameters:
    ///   - series: The already-resolved history series.
    ///   - muted: The dash color used when there are no segments.
    public init(series: HistorySeries, muted: Color) {
        self.series = series
        self.muted = muted
    }

    public var body: some View {
        let segments = HistoryStateSegments.segments(of: series)
        if segments.isEmpty {
            MicroDash(color: muted)
        } else {
            PerchHAHistoryStateTimeline(segments: segments, cornerRadius: 1.5)
                .accessibilityHidden(true)
        }
    }
}

/// A tiny bounded-percentage meter: a short rounded track with a tinted fill
/// growing left-to-right by `fraction`. No labels; the caller draws the value.
public struct MicroMeter: View {
    private let fraction: Double
    private let color: Color
    private let trackColor: Color

    /// Creates the meter.
    ///
    /// - Parameters:
    ///   - fraction: The fill fraction (clamped to `0...1`).
    ///   - color: The fill tint.
    ///   - trackColor: The track tint behind the fill.
    public init(fraction: Double, color: Color, trackColor: Color) {
        self.fraction = min(1.0, max(0.0, fraction))
        self.color = color
        self.trackColor = trackColor
    }

    public var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(trackColor)
                Capsule()
                    .fill(color)
                    .frame(width: max(0, proxy.size.width * CGFloat(fraction)))
            }
        }
        .accessibilityHidden(true)
    }
}
