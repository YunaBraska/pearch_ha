import Foundation

/// Deterministic jitter generator for scheduling and retry behavior.
public struct JitteredScheduler: Sendable {
    public let base: PearchDuration
    public let fraction: Double
    private var generator: SeededGenerator

    public init(base: PearchDuration, fraction: Double, seed: UInt64) {
        precondition(fraction >= 0 && fraction <= 1, "fraction must be within 0...1")
        self.base = base
        self.fraction = fraction
        generator = SeededGenerator(seed: seed)
    }

    public mutating func nextDelay() -> PearchDuration {
        let span = Double(base.nanoseconds) * fraction
        let offset = Int64((generator.nextUnit() * 2 - 1) * span)
        return PearchDuration(nanoseconds: base.nanoseconds + offset)
    }
}

/// Exponential backoff with deterministic full jitter.
public struct ExponentialBackoff: Sendable {
    public let base: PearchDuration
    public let cap: PearchDuration
    public let multiplier: Double
    private var generator: SeededGenerator

    public init(base: PearchDuration, cap: PearchDuration, multiplier: Double = 2, seed: UInt64) {
        precondition(base.nanoseconds > 0, "base must be positive")
        precondition(cap >= base, "cap must be at least base")
        precondition(multiplier >= 1, "multiplier must be at least 1")
        self.base = base
        self.cap = cap
        self.multiplier = multiplier
        generator = SeededGenerator(seed: seed)
    }

    public mutating func delay(forAttempt attempt: Int) -> PearchDuration {
        precondition(attempt >= 1, "attempt must be at least 1")
        let exponent = pow(multiplier, Double(attempt - 1))
        let raw = min(Double(cap.nanoseconds), Double(base.nanoseconds) * exponent)
        return PearchDuration(nanoseconds: Int64(generator.nextUnit() * raw))
    }
}

struct SeededGenerator: Sendable {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed == 0 ? 0x9E37_79B9_7F4A_7C15 : seed
    }

    mutating func nextUnit() -> Double {
        state = state &* 6_364_136_223_846_793_005 &+ 1
        let value = state >> 11
        return Double(value) / Double(UInt64.max >> 11)
    }
}
