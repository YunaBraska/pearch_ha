public struct PearchHAModule: Equatable, Sendable {
    public let name: String
    public let responsibility: String

    public init(name: String, responsibility: String) {
        self.name = name
        self.responsibility = responsibility
    }
}

public enum PearchHASupport {
    public static let module = PearchHAModule(
        name: "PearchHASupport",
        responsibility: "Shared support primitives for command-line parsing, scheduling, rate limits, logging, and clocks."
    )
}
