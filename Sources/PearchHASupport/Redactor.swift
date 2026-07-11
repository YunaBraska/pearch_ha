/// Redacts secrets before they reach logs, journals, or diagnostics.
public struct Redactor: Sendable {
    public let replacement: String
    public let sensitiveKeys: Set<String>

    public init(
        replacement: String = "<redacted>",
        sensitiveKeys: Set<String> = [
            "authorization",
            "access_token",
            "refresh_token",
            "token",
            "password",
            "secret",
            "code",
            "pin",
            "passcode"
        ]
    ) {
        self.replacement = replacement
        self.sensitiveKeys = Set(sensitiveKeys.map { $0.lowercased() })
    }

    public func redact(headers: [String: String]) -> [String: String] {
        redact(dictionary: headers)
    }

    public func redact(fields: [String: String]) -> [String: String] {
        redact(dictionary: fields)
    }

    public func redact(message: String) -> String {
        var redacted = message
        for key in sensitiveKeys {
            redacted = redactAssignments(named: key, in: redacted)
        }
        return redacted
    }

    private func redact(dictionary: [String: String]) -> [String: String] {
        Dictionary(uniqueKeysWithValues: dictionary.map { key, value in
            sensitiveKeys.contains(key.lowercased()) ? (key, replacement) : (key, value)
        })
    }

    private func redactAssignments(named key: String, in message: String) -> String {
        let patterns = ["\(key)", "\"\(key)\""]
        var result = message
        for pattern in patterns {
            result = redactAssignmentValue(for: key, after: pattern, in: result)
        }
        return result
    }

    private func redactAssignmentValue(for key: String, after marker: String, in message: String) -> String {
        var result = message
        var searchStart = result.startIndex

        while let range = result.range(of: marker, options: [.caseInsensitive], range: searchStart..<result.endIndex) {
            guard isKeyBoundary(before: range.lowerBound, in: result) else {
                searchStart = range.upperBound
                continue
            }

            var separator = range.upperBound
            while separator < result.endIndex && (result[separator] == " " || result[separator] == "\"") {
                separator = result.index(after: separator)
            }
            guard separator < result.endIndex && (result[separator] == "=" || result[separator] == ":") else {
                searchStart = range.upperBound
                continue
            }

            var valueStart = result.index(after: separator)
            while valueStart < result.endIndex && (result[valueStart] == " " || result[valueStart] == "\"") {
                valueStart = result.index(after: valueStart)
            }
            let valueEnd = key.lowercased() == "authorization"
                ? authorizationValueEnd(from: valueStart, in: result)
                : scalarValueEnd(from: valueStart, in: result)

            result.replaceSubrange(valueStart..<valueEnd, with: replacement)
            searchStart = result.index(valueStart, offsetBy: replacement.count, limitedBy: result.endIndex) ?? result.endIndex
        }

        return result
    }

    private func scalarValueEnd(from valueStart: String.Index, in message: String) -> String.Index {
        message[valueStart...].firstIndex { character in
            character == " " || character == "," || character == "\n" || character == "\""
        } ?? message.endIndex
    }

    private func authorizationValueEnd(from valueStart: String.Index, in message: String) -> String.Index {
        let delimiters: Set<Character> = [",", "\n", "\""]
        var index = valueStart
        while index < message.endIndex {
            let character = message[index]
            if delimiters.contains(character) {
                return index
            }
            if character == " " && startsAssignment(after: index, in: message) {
                return index
            }
            index = message.index(after: index)
        }
        return message.endIndex
    }

    private func startsAssignment(after spaceIndex: String.Index, in message: String) -> Bool {
        var index = message.index(after: spaceIndex)
        while index < message.endIndex && message[index] == " " {
            index = message.index(after: index)
        }

        var sawKeyCharacter = false
        while index < message.endIndex {
            let character = message[index]
            if character.isLetter || character.isNumber || character == "_" || character == "-" {
                sawKeyCharacter = true
                index = message.index(after: index)
                continue
            }
            if (character == ":" || character == "=") && sawKeyCharacter {
                return true
            }
            return false
        }

        return false
    }

    private func isKeyBoundary(before index: String.Index, in message: String) -> Bool {
        guard index > message.startIndex else {
            return true
        }
        let previous = message[message.index(before: index)]
        return !(previous.isLetter || previous.isNumber || previous == "_")
    }
}
