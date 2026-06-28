public struct PerchHAModule: Equatable, Sendable {
    public let name: String
    public let responsibility: String

    public init(name: String, responsibility: String) {
        self.name = name
        self.responsibility = responsibility
    }
}

public enum PerchHASupport {
    public static let module = PerchHAModule(
        name: "PerchHASupport",
        responsibility: "Shared support primitives for scheduling, rate limits, logging, and clocks."
    )
}
