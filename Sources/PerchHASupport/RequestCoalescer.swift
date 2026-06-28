/// Coalesces concurrent requests for the same key into one in-flight task.
public actor RequestCoalescer<Key: Hashable & Sendable, Value: Sendable> {
    private var inFlight: [Key: Task<Value, Error>] = [:]
    private var coalescedWaiters = 0

    public init() {}

    public func value(
        for key: Key,
        start operation: @Sendable @escaping () async throws -> Value
    ) async throws -> Value {
        if let existing = inFlight[key] {
            coalescedWaiters += 1
            do {
                let value = try await existing.value
                coalescedWaiters -= 1
                return value
            } catch {
                coalescedWaiters -= 1
                throw error
            }
        }

        let task = Task {
            try await operation()
        }
        inFlight[key] = task

        do {
            let value = try await task.value
            inFlight[key] = nil
            return value
        } catch {
            inFlight[key] = nil
            throw error
        }
    }

    public func activeRequestCount() -> Int {
        inFlight.count
    }

    public func coalescedWaiterCount() -> Int {
        coalescedWaiters
    }
}
