public enum PerchHACommandLineParseError: Error, Equatable, Sendable {
    case unknownOption(String)
    case invalidArgument(String)
    case missingValue(String)
}

public enum PerchHACommandLineNonOptionBehavior: Sendable {
    case unknownOption
    case invalidArgument
}

public struct PerchHACommandLineOptions: Equatable, Sendable {
    public let flags: Set<String>
    private let valuesByOption: [String: [String]]

    public init(
        arguments: [String],
        valueOptions: Set<String>,
        flagOptions: Set<String>,
        nonOptionBehavior: PerchHACommandLineNonOptionBehavior = .unknownOption
    ) throws {
        var parsedFlags = Set<String>()
        var parsedValues: [String: [String]] = [:]
        var index = 0

        while index < arguments.count {
            let argument = arguments[index]
            if valueOptions.contains(argument) {
                let valueIndex = index + 1
                guard valueIndex < arguments.count else {
                    throw PerchHACommandLineParseError.missingValue(argument)
                }
                let value = arguments[valueIndex]
                if value.hasPrefix("--") {
                    throw PerchHACommandLineParseError.missingValue(argument)
                }
                parsedValues[argument, default: []].append(value)
                index += 2
                continue
            }
            if flagOptions.contains(argument) {
                parsedFlags.insert(argument)
                index += 1
                continue
            }
            if argument.hasPrefix("--") {
                throw PerchHACommandLineParseError.unknownOption(argument)
            }
            switch nonOptionBehavior {
            case .unknownOption:
                throw PerchHACommandLineParseError.unknownOption(argument)
            case .invalidArgument:
                throw PerchHACommandLineParseError.invalidArgument(argument)
            }
        }

        flags = parsedFlags
        valuesByOption = parsedValues
    }

    public func has(_ option: String) -> Bool {
        flags.contains(option)
    }

    public func value(for option: String) -> String? {
        valuesByOption[option]?.last
    }

    public func values(for option: String) -> [String] {
        valuesByOption[option] ?? []
    }
}
