/// Deterministic token-bucket rate limiter.
public struct TokenBucketRateLimiter: Sendable {
    public let capacity: Double
    public let refillPerSecond: Double
    private var availableTokens: Double
    private var lastRefill: PerchInstant

    public init(capacity: Double, refillPerSecond: Double, now: PerchInstant) {
        precondition(capacity > 0, "capacity must be positive")
        precondition(refillPerSecond > 0, "refillPerSecond must be positive")
        self.capacity = capacity
        self.refillPerSecond = refillPerSecond
        availableTokens = capacity
        lastRefill = now
    }

    public mutating func tryAcquire(tokens: Double = 1, at now: PerchInstant) -> Bool {
        precondition(tokens > 0, "tokens must be positive")
        refill(at: now)
        guard availableTokens >= tokens else {
            return false
        }
        availableTokens -= tokens
        return true
    }

    public mutating func available(at now: PerchInstant) -> Double {
        refill(at: now)
        return availableTokens
    }

    public mutating func nextAvailability(for tokens: Double = 1, at now: PerchInstant) -> RateLimitAvailability {
        precondition(tokens > 0, "tokens must be positive")
        guard tokens <= capacity else {
            return .impossible(capacity: capacity, requested: tokens)
        }
        refill(at: now)
        guard availableTokens < tokens else {
            return .available(now)
        }
        let missing = tokens - availableTokens
        let seconds = missing / refillPerSecond
        return .available(now.advanced(by: PerchDuration(nanoseconds: Int64(seconds * 1_000_000_000))))
    }

    private mutating func refill(at now: PerchInstant) {
        guard now > lastRefill else {
            return
        }
        let elapsed = Double(lastRefill.duration(to: now).nanoseconds) / 1_000_000_000
        availableTokens = min(capacity, availableTokens + elapsed * refillPerSecond)
        lastRefill = now
    }
}

public enum RateLimitAvailability: Equatable, Sendable {
    case available(PerchInstant)
    case impossible(capacity: Double, requested: Double)
}
