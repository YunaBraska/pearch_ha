import Foundation
import PerchHASupport

/// The category of a recorded diagnostic event.
///
/// Only the kinds PerchHA actually emits at real state transitions are
/// represented. Each kind carries a calm, secret-free icon and label suitable
/// for the Diagnostics surface.
public enum PerchHADiagnosticEventKind: String, Equatable, Sendable, CaseIterable {
    /// A connection or authentication attempt failed.
    case connectionFailed
    /// A reconnect/refresh attempt began while values were already known.
    case reconnecting
    /// The connection returned to a healthy connected state after a failure or
    /// reconnect.
    case recovered
    /// A background periodic refresh failed and the model backed off.
    case refreshFailed
    /// The live WebSocket update stream ended and the model is reconnecting it
    /// in the background with backoff.
    case liveUpdatesInterrupted

    /// An SF Symbol name suitable for the Diagnostics list.
    public var systemImage: String {
        switch self {
        case .connectionFailed: "exclamationmark.triangle.fill"
        case .reconnecting: "arrow.triangle.2.circlepath"
        case .recovered: "checkmark.circle.fill"
        case .refreshFailed: "arrow.clockwise.circle"
        case .liveUpdatesInterrupted: "dot.radiowaves.left.and.right"
        }
    }
}

/// A single, deduplicated diagnostic event recorded by the panel model.
///
/// Consecutive identical events (same ``kind`` and ``message``) are collapsed
/// into one record whose ``count`` is incremented and ``lastSeen`` advanced, so
/// a flapping connection does not flood the log. The ``message`` is always the
/// sanitized failure/transition description; it never carries a token or secret.
public struct PerchHADiagnosticEvent: Equatable, Identifiable, Sendable {
    public let id: UUID
    public let kind: PerchHADiagnosticEventKind
    public let message: String
    public let firstSeen: PerchInstant
    public let lastSeen: PerchInstant
    public let count: Int

    public init(
        id: UUID = UUID(),
        kind: PerchHADiagnosticEventKind,
        message: String,
        firstSeen: PerchInstant,
        lastSeen: PerchInstant,
        count: Int = 1
    ) {
        self.id = id
        self.kind = kind
        self.message = message
        self.firstSeen = firstSeen
        self.lastSeen = lastSeen
        self.count = max(1, count)
    }

    /// Whether this event collapses with another (same kind and message).
    func collapses(withKind kind: PerchHADiagnosticEventKind, message: String) -> Bool {
        self.kind == kind && self.message == message
    }
}

/// A bounded, deduplicating ring buffer of diagnostic events.
///
/// Events are stored newest-last internally. Recording an event identical (by
/// kind + message) to the most recent one bumps that record's ``count`` and
/// advances its ``lastSeen`` instead of appending a duplicate. When the buffer
/// exceeds ``capacity`` the oldest event is evicted. The structure is a plain
/// value type so its behavior is fully testable in isolation and cheap to copy
/// into a snapshot.
public struct PerchHADiagnosticLog: Equatable, Sendable {
    /// The default maximum number of distinct events retained.
    public static let defaultCapacity = 50

    public let capacity: Int
    private var events: [PerchHADiagnosticEvent]

    public init(capacity: Int = PerchHADiagnosticLog.defaultCapacity, events: [PerchHADiagnosticEvent] = []) {
        self.capacity = max(1, capacity)
        self.events = Array(events.suffix(self.capacity))
    }

    /// The recorded events in oldest-first order.
    public var oldestFirst: [PerchHADiagnosticEvent] {
        events
    }

    /// The recorded events in newest-first order, for direct display.
    public var newestFirst: [PerchHADiagnosticEvent] {
        events.reversed()
    }

    /// Whether the log holds no events.
    public var isEmpty: Bool {
        events.isEmpty
    }

    /// The number of distinct (post-dedup) events retained.
    public var count: Int {
        events.count
    }

    /// Records an event, deduplicating against the most recent one.
    ///
    /// - Parameters:
    ///   - kind: The event category.
    ///   - message: The sanitized, secret-free message. Must never contain a
    ///     token or credential.
    ///   - now: The current instant from the model's injected clock.
    public mutating func record(kind: PerchHADiagnosticEventKind, message: String, now: PerchInstant) {
        if let last = events.last, last.collapses(withKind: kind, message: message) {
            events[events.count - 1] = PerchHADiagnosticEvent(
                id: last.id,
                kind: last.kind,
                message: last.message,
                firstSeen: last.firstSeen,
                lastSeen: now,
                count: last.count + 1
            )
            return
        }
        events.append(
            PerchHADiagnosticEvent(kind: kind, message: message, firstSeen: now, lastSeen: now)
        )
        if events.count > capacity {
            events.removeFirst(events.count - capacity)
        }
    }

    /// Empties the buffer.
    public mutating func clear() {
        events.removeAll(keepingCapacity: true)
    }
}

/// The current retry/backoff posture exposed to the Diagnostics view.
///
/// Derived purely from the live connection state and the periodic-refresh
/// backoff streak; it never carries a secret.
public enum PerchHARetryBackoffState: Equatable, Sendable {
    /// Connected and healthy; no retry pending.
    case connected
    /// Connecting for the first time (no prior session).
    case connecting
    /// Reconnecting after a drop, on the given attempt number.
    case reconnecting(attempt: Int)
    /// Backing off after one or more failed periodic refreshes, with the next
    /// retry delay in whole seconds.
    case backingOff(failureStreak: Int, nextRetrySeconds: Int)
    /// Disconnected with no retry scheduled.
    case disconnected

    /// A calm, human-readable, secret-free summary line.
    public var summary: String {
        switch self {
        case .connected:
            "Connected"
        case .connecting:
            "Connecting"
        case let .reconnecting(attempt):
            "Reconnecting, attempt \(attempt)"
        case let .backingOff(failureStreak, nextRetrySeconds):
            failureStreak == 1
                ? "Backing off, next retry in \(nextRetrySeconds) s"
                : "Backing off (\(failureStreak) failures), next retry in \(nextRetrySeconds) s"
        case .disconnected:
            "Disconnected"
        }
    }
}
