public enum PearchHACommandLineParseError: Error, Equatable, Sendable {
    case unknownOption(String)
    case invalidArgument(String)
    case missingValue(String)
}

public enum PearchHACommandLineNonOptionBehavior: Sendable {
    case unknownOption
    case invalidArgument
}

public struct PearchHACommandLineOptions: Equatable, Sendable {
    public let flags: Set<String>
    private let valuesByOption: [String: [String]]

    public init(
        arguments: [String],
        valueOptions: Set<String>,
        flagOptions: Set<String>,
        nonOptionBehavior: PearchHACommandLineNonOptionBehavior = .unknownOption
    ) throws {
        var parsedFlags = Set<String>()
        var parsedValues: [String: [String]] = [:]
        var index = 0

        while index < arguments.count {
            let argument = arguments[index]
            if valueOptions.contains(argument) {
                let valueIndex = index + 1
                guard valueIndex < arguments.count else {
                    throw PearchHACommandLineParseError.missingValue(argument)
                }
                let value = arguments[valueIndex]
                if value.hasPrefix("--") {
                    throw PearchHACommandLineParseError.missingValue(argument)
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
                throw PearchHACommandLineParseError.unknownOption(argument)
            }
            switch nonOptionBehavior {
            case .unknownOption:
                throw PearchHACommandLineParseError.unknownOption(argument)
            case .invalidArgument:
                throw PearchHACommandLineParseError.invalidArgument(argument)
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
