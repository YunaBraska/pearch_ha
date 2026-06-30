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

/// A tiny inline sparkline used in entity rows when history is already cached.
///
/// Numeric series draw a thin line; non-numeric series draw their state-timeline
/// bands. It never fetches: callers must hand it an already-resolved series.
public struct PerchHAInlineSparkline: View {
    private let series: HistorySeries
    private let color: Color

    public init(series: HistorySeries, color: Color) {
        self.series = series
        self.color = color
    }

    public var body: some View {
        if PerchHAHistoryCursor.numericSamples(of: series).count > 1 {
            InlineSparklinePath(series: series)
                .stroke(color, style: StrokeStyle(lineWidth: 1, lineCap: .round, lineJoin: .round))
                .accessibilityHidden(true)
        } else {
            PerchHAHistoryStateTimeline(segments: HistoryStateSegments.segments(of: series), cornerRadius: 1.5)
                .accessibilityHidden(true)
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
