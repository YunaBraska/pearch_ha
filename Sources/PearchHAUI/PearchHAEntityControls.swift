import Foundation
import PearchHACore

/// A capability-derived editor and its validated Home Assistant action.
/// Construct fields from an entity; rederive them before execution to reject stale capabilities.
public struct PearchHAEntityControlField: Equatable, Sendable, Identifiable {
    public enum Input: Equatable, Sendable {
        case action
        case choice(options: [String], current: String?)
        case number(current: Double?, range: ClosedRange<Double>, step: Double?, unit: String?)
        case boolean(current: Bool?)
        case color(current: [Double]?)
        case text

        var reportsValue: Bool {
            switch self {
            case .action, .text: false
            case .choice, .number, .boolean, .color: true
            }
        }

        var reportedValue: ActionValue? {
            switch self {
            case let .choice(_, current): current.map(ActionValue.string)
            case let .number(current, _, _, _): current.map(ActionValue.number)
            case let .boolean(current): current.map(ActionValue.bool)
            case let .color(current): current.map { .array($0.map(ActionValue.number)) }
            case .action, .text: nil
            }
        }
    }

    public let id: String
    public let title: String
    public let input: Input
    public let requiresConfirmation: Bool
    private let action: ActionSpec
    private let parameter: String?

    /// Position and intensity controls use a slider with optional precise entry.
    var prefersSlider: Bool {
        switch (action.domain, action.service, parameter) {
        case ("cover", "set_cover_position", "position"),
             ("light", "turn_on", "brightness_pct"),
             ("fan", "set_percentage", "percentage"),
             ("media_player", "volume_set", "volume_level"):
            return true
        default:
            return false
        }
    }

    /// The cover position editor uses the existing cover command path.
    static func coverPosition(_ control: PearchHACoverControl) -> Self {
        Self(id: "position", title: "Position", input: .number(current: control.position.map(Double.init), range: 0...100, step: 1, unit: "%"),
             requiresConfirmation: false, action: control.actionSpec(command: .setPosition(control.position ?? 0)), parameter: "position")
    }

    /// Returns an action only when the input matches the advertised options, bounds and step.
    /// Action buttons take no value. Message text must contain non-whitespace characters.
    public func actionSpec(value: ActionValue? = nil) -> ActionSpec? {
        switch input {
        case .action:
            guard value == nil else { return nil }
        case let .choice(options, _):
            guard case let .string(option) = value, options.contains(option) else { return nil }
        case let .number(_, range, step, _):
            guard case let .number(number) = value, number.isFinite, range.contains(number) else { return nil }
            if let step {
                let steps = (number - range.lowerBound) / step
                guard steps.isFinite, abs(steps - steps.rounded()) < 0.000001 else { return nil }
            }
        case .boolean:
            guard case .bool = value else { return nil }
        case .color:
            guard case let .array(components) = value, components.count == 3,
                  components.allSatisfy({ component in
                      guard case let .number(number) = component else { return false }
                      return number.isFinite && (0...255).contains(number) && number.rounded() == number
                  }) else { return nil }
        case .text:
            guard case let .string(text) = value, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        }
        var data = action.serviceData
        if let parameter, let value { data[parameter] = value }
        return ActionSpec(domain: action.domain, service: action.service, targetEntityID: action.targetEntityID, serviceData: data)
    }

    /// Describes the same capabilities used by the editors and direct controls.
    /// Current readings are excluded so normal state updates do not invalidate settings rows.
    static func controlHelp(for entity: DiscoveredEntity) -> String? {
        guard entity.state != "unavailable" else { return nil }
        var descriptions: [String] = []
        if PearchHAEntityControl(entity: entity) != nil {
            descriptions.append("On / Off")
        }
        if let cover = PearchHACoverControl(entity: entity) {
            descriptions.append("Open / Stop / Close")
            if cover.position != nil { descriptions.append("Position: 0 - 100 %") }
        }
        descriptions += controls(for: entity).map { field in
            switch field.input {
            case let .choice(options, _):
                return "\(field.title): \(options.joined(separator: ", "))"
            case let .number(_, range, step, unit):
                let bounds = "\(range.lowerBound.formatted(.number.grouping(.never))) - \(range.upperBound.formatted(.number.grouping(.never)))"
                return "\(field.title): \(bounds)\(unit.map { " " + $0 } ?? "")\(step.map { ", step " + $0.formatted(.number.grouping(.never)) } ?? "")"
            case .boolean:
                return "\(field.title): On / Off"
            case .action, .color, .text:
                return field.title
            }
        }
        guard !descriptions.isEmpty else { return nil }
        return (["Controllable (\(entity.id.domain))"] + descriptions).joined(separator: "\n")
    }

    /// Builds only controls supported by the entity's current capabilities.
    /// Unavailable entities expose none. Stateless buttons, scenes and notify entities may be unknown.
    public static func controls(for entity: DiscoveredEntity) -> [Self] {
        guard entity.state != "unavailable" else { return [] }
        let attributes = entity.controlAttributes ?? [:]
        let rawFeatures = attributes["supported_features"]?.controlNumber ?? 0
        let features = rawFeatures >= 0 && rawFeatures < Double(Int.max) && rawFeatures.rounded() == rawFeatures ? Int(rawFeatures) : 0
        func supports(_ flag: Int) -> Bool { features & flag == flag }
        func number(_ key: String) -> Double? { attributes[key]?.controlNumber }
        func string(_ key: String) -> String? { attributes[key]?.controlString }
        func strings(_ key: String) -> [String] { attributes[key]?.controlStrings ?? [] }
        var fields: [Self] = []
        func add(_ title: String, _ service: String, _ parameter: String? = nil, _ input: Input = .action,
                 confirm: Bool = false, data: [String: ActionValue] = [:]) {
            fields.append(Self(id: service + (parameter.map { "." + $0 } ?? ""), title: title, input: input,
                               requiresConfirmation: confirm,
                               action: ActionSpec(domain: entity.id.domain, service: service, targetEntityID: entity.id, serviceData: data),
                               parameter: parameter))
        }
        func choice(_ title: String, _ service: String, _ parameter: String, options: [String], current: String?) {
            let options = options.reduce(into: [String]()) { result, option in
                if !option.isEmpty && !result.contains(option) { result.append(option) }
            }
            guard !options.isEmpty else { return }
            add(title, service, parameter, .choice(options: options, current: current))
        }
        func numeric(_ title: String, _ service: String, _ parameter: String, current: Double?,
                     min: Double?, max: Double?, step: Double?, unit: String? = nil,
                     data: [String: ActionValue] = [:]) {
            guard let min, let max, min.isFinite, max.isFinite, min <= max,
                  step.map({ $0.isFinite && $0 > 0 }) ?? true else { return }
            add(title, service, parameter, .number(current: current, range: min...max, step: step, unit: unit), data: data)
        }
        func power(on: Int, off: Int) {
            if supports(on), entity.state == "off" { add("Turn on", "turn_on") }
            if supports(off), entity.state != "off", entity.state != "unknown" { add("Turn off", "turn_off") }
        }
        switch entity.id.domain {
        case "climate":
            choice("Mode", "set_hvac_mode", "hvac_mode", options: strings("hvac_modes"), current: entity.state)
            let unit = entity.unit ?? string("temperature_unit")
            let step = number("target_temp_step") ?? number("precision")
            if supports(1) {
                numeric("Temperature", "set_temperature", "temperature", current: number("temperature"),
                        min: number("min_temp"), max: number("max_temp"), step: step, unit: unit)
            }
            if supports(2), let low = number("target_temp_low"), let high = number("target_temp_high"),
               let minimum = number("min_temp"), let maximum = number("max_temp"),
               minimum <= low, low <= high, high <= maximum {
                numeric("Minimum temperature", "set_temperature", "target_temp_low", current: low,
                        min: minimum, max: high, step: step, unit: unit, data: ["target_temp_high": .number(high)])
                numeric("Maximum temperature", "set_temperature", "target_temp_high", current: high,
                        min: low, max: maximum, step: step, unit: unit, data: ["target_temp_low": .number(low)])
            }
            if supports(4) {
                numeric("Humidity", "set_humidity", "humidity", current: number("humidity"),
                        min: number("min_humidity"), max: number("max_humidity"), step: number("target_humidity_step") ?? 1, unit: "%")
            }
            for (flag, title, key) in [(8, "Fan", "fan"), (16, "Preset", "preset"), (32, "Swing", "swing"), (512, "Horizontal swing", "swing_horizontal")] where supports(flag) {
                choice(title, "set_\(key)_mode", "\(key)_mode", options: strings("\(key)_modes"), current: string("\(key)_mode"))
            }
            power(on: 256, off: 128)
        case "number":
            numeric("Value", "set_value", "value", current: Double(entity.state), min: number("min"), max: number("max"), step: number("step"), unit: entity.unit)
        case "select":
            choice("Option", "select_option", "option", options: strings("options"), current: entity.state)
        case "light":
            let modes = strings("supported_color_modes")
            if modes.contains(where: { ["brightness", "color_temp", "hs", "xy", "rgb", "rgbw", "rgbww", "white"].contains($0) }) {
                // Home Assistant clears brightness when a light turns off.
                let brightness = entity.state == "off" ? 0 : number("brightness").map { ($0 / 255 * 100).rounded() }
                numeric("Brightness", "turn_on", "brightness_pct", current: brightness, min: 0, max: 100, step: 1, unit: "%")
            }
            if modes.contains("color_temp") {
                numeric("Color temperature", "turn_on", "color_temp_kelvin", current: number("color_temp_kelvin"), min: number("min_color_temp_kelvin"), max: number("max_color_temp_kelvin"), step: 1, unit: "K")
            }
            if modes.contains(where: { ["hs", "xy", "rgb", "rgbw", "rgbww"].contains($0) }) {
                let rgb: [Double]?
                if case let .array(values) = attributes["rgb_color"] { rgb = values.compactMap(\.controlNumber) } else { rgb = nil }
                add("Color", "turn_on", "rgb_color", .color(current: rgb?.count == 3 ? rgb : nil))
            }
            if supports(4) { choice("Effect", "turn_on", "effect", options: strings("effect_list"), current: string("effect")) }
        case "fan":
            power(on: 32, off: 16)
            if supports(1) {
                numeric("Speed", "set_percentage", "percentage", current: number("percentage"), min: 0, max: 100, step: 1, unit: "%")
            }
            if supports(8) { choice("Preset", "set_preset_mode", "preset_mode", options: strings("preset_modes"), current: string("preset_mode")) }
            if supports(2) { add("Oscillation", "oscillate", "oscillating", .boolean(current: attributes["oscillating"]?.controlBool)) }
            if supports(4) { choice("Direction", "set_direction", "direction", options: ["forward", "reverse"], current: string("direction")) }
        case "scene":
            add("Activate", "turn_on")
        case "button":
            add("Press", "press", confirm: true)
        case "automation":
            if entity.state == "on" { add("Disable", "turn_off", confirm: true, data: ["stop_actions": false]) }
            if entity.state == "off" { add("Enable", "turn_on") }
            add("Run actions", "trigger", confirm: true, data: ["skip_condition": false])
        case "media_player":
            power(on: 128, off: 256)
            for (flag, title, service) in [(16384, "Play", "media_play"), (1, "Pause", "media_pause"), (4096, "Stop", "media_stop"), (16, "Previous", "media_previous_track"), (32, "Next", "media_next_track")] where supports(flag) {
                add(title, service)
            }
            if supports(1024) {
                add("Volume down", "volume_down")
                add("Volume up", "volume_up")
            }
            if supports(4) { numeric("Volume", "volume_set", "volume_level", current: number("volume_level"), min: 0, max: 1, step: 0.01) }
            if supports(8) { add("Mute", "volume_mute", "is_volume_muted", .boolean(current: attributes["is_volume_muted"]?.controlBool)) }
            if supports(2048) { choice("Source", "select_source", "source", options: strings("source_list"), current: string("source")) }
            if supports(65536) { choice("Sound mode", "select_sound_mode", "sound_mode", options: strings("sound_mode_list"), current: string("sound_mode")) }
            if supports(32768) { add("Shuffle", "shuffle_set", "shuffle", .boolean(current: attributes["shuffle"]?.controlBool)) }
            if supports(262144) { choice("Repeat", "repeat_set", "repeat", options: ["off", "all", "one"], current: string("repeat")) }
        case "update":
            let updating = attributes["in_progress"]?.controlBool == true || number("in_progress") != nil
            if !updating {
                if entity.state == "on" {
                    if supports(1) { add("Install update", "install", confirm: true) }
                    add("Skip version", "skip", confirm: true)
                }
                if let skipped = string("skipped_version"), !skipped.isEmpty { add("Clear skipped version", "clear_skipped", confirm: true) }
            }
        case "notify":
            add("Message", "send_message", "message", .text)
        default:
            break
        }
        return fields
    }
}

extension ActionValue {
    var controlNumber: Double? {
        guard case let .number(value) = self, value.isFinite else { return nil }
        return value
    }
    var controlString: String? {
        guard case let .string(value) = self else { return nil }
        return value
    }
    var controlStrings: [String]? {
        guard case let .array(values) = self else { return nil }
        return values.compactMap(\.controlString)
    }
    var controlBool: Bool? {
        guard case let .bool(value) = self else { return nil }
        return value
    }
}
