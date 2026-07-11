import Foundation

package enum PearchHAEntityNaming {
    package static func preferredName(
        between first: String?,
        and second: String?,
        entityID: EntityID
    ) -> String? {
        let first = trimmed(first)
        let second = trimmed(second)
        switch (first, second) {
        case let (first?, second?):
            let firstLowered = first.lowercased()
            let secondLowered = second.lowercased()
            if firstLowered == secondLowered {
                return first
            }
            if genericNames(for: entityID).contains(firstLowered), !genericNames(for: entityID).contains(secondLowered) {
                return second
            }
            if genericNames(for: entityID).contains(secondLowered), !genericNames(for: entityID).contains(firstLowered) {
                return first
            }
            if isLessSpecific(first, than: second) {
                return second
            }
            if isLessSpecific(second, than: first) {
                return first
            }
            return first.count >= second.count ? first : second
        case let (first?, nil):
            return first
        case let (nil, second?):
            return second
        case (nil, nil):
            return nil
        }
    }

    package static func preferredUnit(between first: String?, and second: String?) -> String? {
        trimmed(first) ?? trimmed(second)
    }

    private static func trimmed(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return nil
        }
        return value
    }

    private static func isLessSpecific(_ candidate: String, than existing: String) -> Bool {
        let candidateTokens = normalizedTokens(candidate)
        let existingTokens = normalizedTokens(existing)
        guard !candidateTokens.isEmpty, !existingTokens.isEmpty else {
            return false
        }
        guard candidateTokens.count <= existingTokens.count else {
            return false
        }
        let existingTokenSet = Set(existingTokens)
        if Set(candidateTokens).isSubset(of: existingTokenSet) {
            return candidateTokens.count < existingTokens.count || candidate.count < existing.count
        }
        return false
    }

    private static func normalizedTokens(_ raw: String) -> [String] {
        raw
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .split { !$0.isLetter && !$0.isNumber }
            .map(String.init)
    }

    private static func genericNames(for entityID: EntityID) -> Set<String> {
        [
            entityID.rawValue.lowercased(),
            entityID.domain.lowercased(),
            entityID.domain.replacingOccurrences(of: "_", with: " ").lowercased(),
            "sensor",
            "select",
            "switch",
            "binary sensor",
            "number"
        ]
    }
}
