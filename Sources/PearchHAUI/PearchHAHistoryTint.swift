import SwiftUI
import PearchHACore

enum PearchHAHistoryTint {
    static func numericAccent(
        for entity: DiscoveredEntity,
        configuration: MenuBarItemConfiguration
    ) -> PearchHAAccentColor? {
        guard let value = Double(entity.state.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            return nil
        }
        return numericAccent(for: value, entity: entity, configuration: configuration)
    }

    static func numericAccent(
        for value: Double,
        entity: DiscoveredEntity,
        configuration: MenuBarItemConfiguration
    ) -> PearchHAAccentColor? {
        let thresholds = EntityDisplayDefaults.effectiveThresholds(for: entity, configuration: configuration)
        guard EntityDisplayDefaults.hasThresholds(thresholds) else {
            return nil
        }
        return thresholds.color(for: value)
    }

    static func stateAccent(
        for state: String,
        entity: DiscoveredEntity,
        configuration: MenuBarItemConfiguration
    ) -> PearchHAAccentColor? {
        let thresholds = EntityDisplayDefaults.effectiveStateThresholds(for: entity, configuration: configuration)
        guard EntityDisplayDefaults.hasStateThresholds(thresholds) else {
            return nil
        }
        return thresholds.color(for: state)
    }
}
