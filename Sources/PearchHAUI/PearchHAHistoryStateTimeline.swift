import SwiftUI
import PearchHACore

/// A horizontal timeline of proportional colored bands for a non-numeric history
/// series (covers, switches, binary sensors).
///
/// Each segment is sized by its share of the total span and colored by
/// ``HistoryStateColorKind``. Zero-total spans (a single sample, or all samples
/// at one instant) fall back to equal widths so the timeline still renders. The
/// view is purely visual; callers supply accessibility on the surrounding row or
/// popover.
public struct PearchHAHistoryStateTimeline: View {
    private let segments: [HistoryStateSegment]
    private let cornerRadius: CGFloat
    private let colorForState: (String) -> Color

    public init(
        segments: [HistoryStateSegment],
        cornerRadius: CGFloat = 3,
        colorForState: ((String) -> Color)? = nil
    ) {
        self.segments = segments
        self.cornerRadius = cornerRadius
        self.colorForState = colorForState ?? { state in
            PearchHATheme.color(for: HistoryStateColorKind.classify(state))
        }
    }

    public var body: some View {
        GeometryReader { proxy in
            let widths = Self.segmentWidths(segments, totalWidth: proxy.size.width)
            HStack(spacing: 1) {
                ForEach(Array(segments.enumerated()), id: \.offset) { index, segment in
                    Rectangle()
                        .fill(colorForState(segment.state))
                        .frame(width: max(0, widths[index]))
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        }
    }

    /// Proportional pixel widths for the segments across `totalWidth`.
    ///
    /// Widths are proportional to each segment's duration. When every segment has
    /// zero duration (a single instant) the widths are equal. Exposed for tests.
    ///
    /// - Parameters:
    ///   - segments: The segments to lay out.
    ///   - totalWidth: The available pixel width.
    /// - Returns: One width per segment, summing to at most `totalWidth`.
    static func segmentWidths(_ segments: [HistoryStateSegment], totalWidth: CGFloat) -> [CGFloat] {
        guard !segments.isEmpty, totalWidth > 0 else {
            return segments.map { _ in 0 }
        }
        let spacing = CGFloat(max(0, segments.count - 1))
        let usable = max(0, totalWidth - spacing)
        let durations = segments.map { max(0, $0.duration) }
        let total = durations.reduce(0, +)
        guard total > 0 else {
            let equal = usable / CGFloat(segments.count)
            return segments.map { _ in equal }
        }
        return durations.map { usable * CGFloat($0 / total) }
    }
}

/// The interactive, constant-height state timeline shown in the history popover.
///
/// Shows the current state above a band timeline; a hover cursor reveals the
/// state and duration of the segment under the pointer (reusing the numeric
/// chart's cursor pattern). Height is fixed so hovering never resizes the
/// popover.
struct PearchHAHistoryStateTimelinePopoverBody: View {
    let segments: [HistoryStateSegment]
    let range: HistoryRange
    let entityName: String
    let labelColor: Color
    let valueColor: Color
    let colorForState: (String) -> Color
    let onHoverReadoutChange: (String?) -> Void

    @State private var cursorNormalizedX: Double?

    private static let timelineHeight: CGFloat = 22

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Current")
                    .foregroundStyle(labelColor)
                Spacer()
                Text(currentStateLabel)
                    .foregroundStyle(valueColor)
            }
            .font(.caption)
            timeline
            legend
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(entityName) state timeline, current state \(currentStateLabel)")
        .accessibilityValue(accessibilitySegmentSummary)
    }

    /// The recent state segments spoken by assistive technology, since the
    /// drawn timeline itself is a single ignored element.
    private var accessibilitySegmentSummary: String {
        let recent = segments.suffix(6)
        guard !recent.isEmpty else {
            return "No recorded states"
        }
        let described = recent
            .map { "\(Self.label(for: $0.state)) for \(Self.durationLabel($0.duration))" }
            .joined(separator: ", ")
        let omitted = segments.count - recent.count
        return omitted > 0 ? "\(described), and \(omitted) earlier" : described
    }

    private var timeline: some View {
        GeometryReader { proxy in
            ZStack(alignment: .topLeading) {
                PearchHAHistoryStateTimeline(
                    segments: segments,
                    colorForState: colorForState
                )
                if let normalizedX = cursorNormalizedX {
                    let x = proxy.size.width * CGFloat(min(max(normalizedX, 0), 1))
                    Rectangle()
                        .fill(Color.primary.opacity(0.5))
                        .frame(width: 1)
                        .frame(maxHeight: .infinity)
                        .offset(x: x)
                }
            }
            .contentShape(Rectangle())
            .onContinuousHover { phase in
                switch phase {
                case let .active(location):
                    let width = proxy.size.width
                    let normalizedX = width > 0 ? Double(location.x / width) : nil
                    cursorNormalizedX = normalizedX
                    onHoverReadoutChange(normalizedX.flatMap(readout))
                case .ended:
                    cursorNormalizedX = nil
                    onHoverReadoutChange(nil)
                }
            }
        }
        .frame(height: Self.timelineHeight)
        .onDisappear {
            onHoverReadoutChange(nil)
        }
    }

    private var legend: some View {
        let uniqueStates = orderedUniqueStates
        return FlowingLegend(
            states: uniqueStates,
            labelColor: labelColor,
            colorForState: colorForState
        )
    }

    private var orderedUniqueStates: [String] {
        var seen = Set<String>()
        var result: [String] = []
        for segment in segments where seen.insert(segment.state).inserted {
            result.append(segment.state)
        }
        return result
    }

    private var currentStateLabel: String {
        Self.label(for: segments.last?.state ?? "")
    }

    private func readout(forNormalizedX normalizedX: Double) -> String? {
        guard let segment = segment(atNormalizedX: normalizedX) else {
            return nil
        }
        return Self.readout(state: segment.state, start: segment.start, duration: segment.duration, range: range)
    }

    private func segment(atNormalizedX normalizedX: Double) -> HistoryStateSegment? {
        guard !segments.isEmpty else {
            return nil
        }
        let clamped = min(max(normalizedX, 0), 1)
        let durations = segments.map { max(0, $0.duration) }
        let total = durations.reduce(0, +)
        guard total > 0 else {
            let index = min(segments.count - 1, Int(clamped * Double(segments.count)))
            return segments[index]
        }
        var cumulative = 0.0
        for (index, duration) in durations.enumerated() {
            cumulative += duration / total
            if clamped <= cumulative {
                return segments[index]
            }
        }
        return segments.last
    }

    static func label(for state: String) -> String {
        let trimmed = state.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return "Unknown"
        }
        let spaced = trimmed.replacingOccurrences(of: "_", with: " ")
        return spaced.prefix(1).uppercased() + spaced.dropFirst()
    }

    static func readout(
        state: String,
        start: Date,
        duration: TimeInterval,
        range: HistoryRange? = nil,
        locale: Locale = .current,
        timeZone: TimeZone = .current
    ) -> String {
        let timestamp = PearchHAHistoryHoverFormatting.timestamp(
            start,
            range: range,
            locale: locale,
            timeZone: timeZone
        )
        return "\(label(for: state)) · \(timestamp) · \(durationLabel(duration))"
    }

    static func durationLabel(_ duration: TimeInterval) -> String {
        let seconds = Int(duration.rounded())
        if seconds < 60 {
            return "\(seconds)s"
        }
        let minutes = seconds / 60
        if minutes < 60 {
            return "\(minutes)m"
        }
        let hours = minutes / 60
        if hours < 24 {
            let remaining = minutes % 60
            return remaining == 0 ? "\(hours)h" : "\(hours)h \(remaining)m"
        }
        let days = hours / 24
        let remainingHours = hours % 24
        return remainingHours == 0 ? "\(days)d" : "\(days)d \(remainingHours)h"
    }
}

private struct FlowingLegend: View {
    let states: [String]
    let labelColor: Color
    let colorForState: (String) -> Color

    var body: some View {
        HStack(spacing: 10) {
            ForEach(Array(states.prefix(4).enumerated()), id: \.offset) { _, state in
                HStack(spacing: 4) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(colorForState(state))
                        .frame(width: 8, height: 8)
                    Text(PearchHAHistoryStateTimelinePopoverBody.label(for: state))
                        .font(.caption2)
                        .foregroundStyle(labelColor)
                        .lineLimit(1)
                }
            }
            if states.count > 4 {
                Text("+\(states.count - 4) more")
                    .font(.caption2)
                    .foregroundStyle(labelColor)
                    .lineLimit(1)
                    .accessibilityLabel("\(states.count - 4) more states not shown")
            }
            Spacer(minLength: 0)
        }
    }
}
