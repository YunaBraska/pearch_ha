import Foundation

/// A contiguous run of one unchanging state within a history series.
///
/// Produced by ``HistoryStateSegments`` to drive the non-numeric state timeline,
/// where each segment is drawn as a proportional colored band.
public struct HistoryStateSegment: Equatable, Sendable {
    /// The (already trimmed) raw state shared by every sample in the run.
    public let state: String
    /// The timestamp of the first sample in the run.
    public let start: Date
    /// The timestamp that ends the run.
    ///
    /// For every segment but the last this is the start of the following run; for
    /// the final run it is the timestamp of the last sample (so a single trailing
    /// sample has a zero-length, but still renderable, segment).
    public let end: Date

    public init(state: String, start: Date, end: Date) {
        self.state = state
        self.start = start
        self.end = end
    }

    /// The wall-clock duration the state was held, never negative.
    public var duration: TimeInterval {
        max(0, end.timeIntervalSince(start))
    }
}

/// Pure collapse of a ``HistorySeries`` into ordered state segments.
///
/// Mirrors the timeline layout used by the panel's history popover for
/// non-numeric entities (covers, switches, binary sensors). Consecutive samples
/// that share the same state are merged into one segment; the boundary between
/// two segments is the timestamp of the first sample of the later state, so the
/// segments tile the timeline without gaps.
public enum HistoryStateSegments {
    /// Collapses a series into chronological state segments.
    ///
    /// Samples are sorted by timestamp (ties keep their original order). Adjacent
    /// samples with an equal state are merged. The state strings are compared and
    /// stored trimmed of surrounding whitespace; an all-empty/whitespace state is
    /// kept verbatim as the trimmed (possibly empty) value so the timeline can
    /// still classify it.
    ///
    /// - Parameter series: The history series to collapse.
    /// - Returns: Ordered segments covering the series, or an empty array when the
    ///   series carries no samples.
    public static func segments(of series: HistorySeries) -> [HistoryStateSegment] {
        segments(of: series.samples)
    }

    /// Collapses raw samples into chronological state segments.
    ///
    /// - Parameter samples: The samples to collapse.
    /// - Returns: Ordered segments, or an empty array when `samples` is empty.
    public static func segments(of samples: [HistorySample]) -> [HistoryStateSegment] {
        let ordered = samples
            .enumerated()
            .sorted { lhs, rhs in
                if lhs.element.timestamp == rhs.element.timestamp {
                    return lhs.offset < rhs.offset
                }
                return lhs.element.timestamp < rhs.element.timestamp
            }
            .map { (state: $0.element.state.trimmingCharacters(in: .whitespacesAndNewlines), timestamp: $0.element.timestamp) }

        guard let first = ordered.first else {
            return []
        }

        var segments: [HistoryStateSegment] = []
        var runState = first.state
        var runStart = first.timestamp
        var lastTimestamp = first.timestamp

        for sample in ordered.dropFirst() {
            if sample.state == runState {
                lastTimestamp = sample.timestamp
                continue
            }
            segments.append(HistoryStateSegment(state: runState, start: runStart, end: sample.timestamp))
            runState = sample.state
            runStart = sample.timestamp
            lastTimestamp = sample.timestamp
        }
        segments.append(HistoryStateSegment(state: runState, start: runStart, end: lastTimestamp))
        return segments
    }
}

/// Semantic color buckets for a non-numeric state, kept pure so both the UI and
/// its tests agree on the classification.
///
/// Common Home Assistant states map to ``active`` (on, open, home, …) or
/// ``inactive`` (off, closed, away, …). Anything else is hashed to one of a
/// small, stable set of muted palette slots so distinct custom states stay
/// visually distinguishable across redraws.
public enum HistoryStateColorKind: Equatable, Sendable {
    case active
    case inactive
    /// A stable palette slot index in `0..<paletteSlotCount` for an unmapped state.
    case palette(Int)

    /// The number of muted palette slots used for unmapped states.
    public static let paletteSlotCount = 5

    /// Classifies a raw state string.
    ///
    /// - Parameter state: The raw (possibly untrimmed) state value.
    /// - Returns: The semantic color bucket for the state.
    public static func classify(_ state: String) -> HistoryStateColorKind {
        let normalized = state.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if activeStates.contains(normalized) {
            return .active
        }
        if inactiveStates.contains(normalized) {
            return .inactive
        }
        return .palette(stableSlot(for: normalized))
    }

    private static let activeStates: Set<String> = [
        "on", "open", "opening", "home", "active", "playing", "heat", "cool", "unlocked", "detected", "motion"
    ]

    private static let inactiveStates: Set<String> = [
        "off", "closed", "closing", "away", "not_home", "idle", "standby", "paused", "locked", "clear", "no_motion"
    ]

    /// A deterministic, platform-independent slot for an arbitrary state.
    ///
    /// Uses an FNV-1a hash of the normalized bytes so the slot is stable across
    /// processes and architectures (unlike `String.hashValue`).
    private static func stableSlot(for normalized: String) -> Int {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in normalized.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x00000100000001B3
        }
        return Int(hash % UInt64(paletteSlotCount))
    }
}
