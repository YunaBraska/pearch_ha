import AppKit
import FakeHA
import Foundation
import PearchHAClient
import PearchHACore
import PearchHAUI
import SwiftUI
import XCTest

@MainActor
final class EntityControlsTests: XCTestCase {
    private func entity(_ domain: String, state: String = "on", attributes: [String: ActionValue] = [:]) -> DiscoveredEntity {
        DiscoveredEntity(id: EntityID("\(domain).office"), name: "Office \(domain)", state: state,
                         unit: nil, areaID: "office", deviceID: nil, controlAttributes: attributes)
    }

    private func connectedModel(_ entities: [DiscoveredEntity], server: FakeHAWebSocketServer) async -> PearchHAPanelModel {
        let rooms = [Room(id: "office", name: "Office", entities: entities)]
        let model = PearchHAPanelModel(connector: { _ in .success(rooms: rooms) }, actionRunner: { form, action in
            let input = HAConnectionInput(endpoint: HAEndpoint(primaryURL: server.baseURL, fallbackURL: nil), token: form.trimmedToken)
            switch await HomeAssistantClient().callService(input, call: action) {
            case .success: return .success
            case let .failure(failure): return .failed(failure.description)
            }
        })
        model.updateConnectionForm(urlString: server.baseURL.absoluteString, token: "fake-token")
        await model.connect()
        model.setPanelActive(true)
        return model
    }

    func testControlsDispatchAdvertisedServicePayloadsThroughWebSocket() async throws {
        let server = try FakeHAWebSocketServer()
        server.start()
        defer { server.stop() }
        let climate = entity("climate", state: "off", attributes: [
            "supported_features": 441, "temperature": 22, "min_temp": 16, "max_temp": 30, "target_temp_step": 1,
            "hvac_modes": .array(["cool", "heat", "off"]), "fan_modes": .array(["Auto", "Low"]),
            "preset_modes": .array(["eco"]), "swing_modes": .array([])
        ])
        let entities = [climate,
            entity("number", state: "10", attributes: ["min": 0, "max": 100, "step": 0.5]),
            entity("select", state: "a", attributes: ["options": .array(["a", "b"])]),
            entity("light", attributes: ["supported_features": 4, "supported_color_modes": .array(["color_temp", "xy"]),
                                         "min_color_temp_kelvin": 2000, "max_color_temp_kelvin": 6500, "effect_list": .array(["rainbow"])]),
            entity("fan", attributes: ["supported_features": 63, "preset_modes": .array(["auto", "sleep"])]),
            entity("scene", state: "unknown"), entity("button", state: "unknown"), entity("automation"),
            entity("media_player", attributes: ["supported_features": 384445, "source_list": .array(["HDMI"]), "sound_mode_list": .array(["Movie"])]),
            entity("update", attributes: ["supported_features": 1, "in_progress": false, "skipped_version": "2.0"]),
            entity("notify", state: "unknown")
        ]
        let model = await connectedModel(entities, server: server)
        let cases: [(String, String, ActionValue?, [String: ActionValue])] = [
            ("climate", "set_temperature.temperature", 23, ["temperature": 23]),
            ("climate", "set_hvac_mode.hvac_mode", "cool", ["hvac_mode": "cool"]),
            ("climate", "set_fan_mode.fan_mode", "Low", ["fan_mode": "Low"]),
            ("climate", "set_preset_mode.preset_mode", "eco", ["preset_mode": "eco"]),
            ("climate", "turn_on", nil, [:]),
            ("number", "set_value.value", 12.5, ["value": 12.5]),
            ("select", "select_option.option", "b", ["option": "b"]),
            ("light", "turn_on.brightness_pct", 50, ["brightness_pct": 50]),
            ("light", "turn_on.color_temp_kelvin", 3000, ["color_temp_kelvin": 3000]),
            ("light", "turn_on.rgb_color", .array([255, 30, 0]), ["rgb_color": .array([255, 30, 0])]),
            ("light", "turn_on.effect", "rainbow", ["effect": "rainbow"]),
            ("fan", "turn_off", nil, [:]),
            ("fan", "set_percentage.percentage", 60, ["percentage": 60]),
            ("fan", "set_preset_mode.preset_mode", "sleep", ["preset_mode": "sleep"]),
            ("fan", "oscillate.oscillating", true, ["oscillating": true]),
            ("fan", "set_direction.direction", "reverse", ["direction": "reverse"]),
            ("scene", "turn_on", nil, [:]), ("button", "press", nil, [:]),
            ("automation", "turn_off", nil, ["stop_actions": false]),
            ("automation", "trigger", nil, ["skip_condition": false]),
            ("media_player", "media_play", nil, [:]), ("media_player", "media_pause", nil, [:]),
            ("media_player", "media_stop", nil, [:]), ("media_player", "media_next_track", nil, [:]),
            ("media_player", "media_previous_track", nil, [:]), ("media_player", "volume_up", nil, [:]),
            ("media_player", "volume_down", nil, [:]),
            ("media_player", "volume_set.volume_level", 0.4, ["volume_level": 0.4]),
            ("media_player", "volume_mute.is_volume_muted", true, ["is_volume_muted": true]),
            ("media_player", "select_source.source", "HDMI", ["source": "HDMI"]),
            ("media_player", "select_sound_mode.sound_mode", "Movie", ["sound_mode": "Movie"]),
            ("media_player", "shuffle_set.shuffle", false, ["shuffle": false]),
            ("media_player", "repeat_set.repeat", "all", ["repeat": "all"]),
            ("update", "install", nil, [:]), ("update", "skip", nil, [:]),
            ("update", "clear_skipped", nil, [:]),
            ("notify", "send_message.message", "Dinner is ready", ["message": "Dinner is ready"])
        ]
        for (domain, controlID, value, data) in cases {
            let id = EntityID("\(domain).office")
            let success = await model.setEntityControlValue(id, controlID: controlID, value: value, confirmed: true)
            XCTAssertTrue(success, "\(domain).\(controlID): \(model.snapshot.controlActionState)")
            let entries = await server.journal.snapshot().filter { $0.path == "/api/websocket/call_service" }
            let body = try XCTUnwrap(entries.last?.bodyText?.data(using: .utf8))
            let request = try JSONDecoder().decode([String: ActionValue].self, from: body)
            XCTAssertEqual(request["domain"], .string(domain))
            XCTAssertEqual(request["service"], .string(String(controlID.split(separator: ".")[0])))
            XCTAssertEqual(request["target"], .object(["entity_id": .string(id.rawValue)]))
            XCTAssertEqual(request["service_data"], .object(data))
        }
        let calls = await server.journal.snapshot().filter { $0.path == "/api/websocket/call_service" }
        XCTAssertEqual(calls.count, cases.count)
        XCTAssertEqual(model.snapshot.availableRooms.first?.entities.first?.controlAttributes?["temperature"], 22,
                       "A successful command must not invent a reported target temperature")
    }

    func testUnsupportedCapabilitiesAndInvalidValuesNeverDispatch() async throws {
        let server = try FakeHAWebSocketServer()
        server.start()
        defer { server.stop() }
        let entities = [
            entity("climate", attributes: ["supported_features": 33, "min_temp": 16, "max_temp": 30, "target_temp_step": 1, "swing_modes": .array([])]),
            entity("number", attributes: ["min": -1, "max": 1, "step": 0.5]),
            entity("select", attributes: ["options": .array(["a", "b"])]),
            entity("light", attributes: ["supported_color_modes": .array(["rgb"])]),
            entity("notify", state: "unknown"), entity("button", state: "unknown"), entity("scene", state: "unavailable"),
            entity("update", attributes: ["supported_features": 1, "in_progress": 50])
        ]
        let model = await connectedModel(entities, server: server)
        let invalid: [(String, String, ActionValue?)] = [
            ("climate", "set_temperature.temperature", 15), ("climate", "set_temperature.temperature", 30.5),
            ("climate", "set_temperature.temperature", 22.5), ("climate", "set_temperature.temperature", .number(.infinity)),
            ("climate", "set_temperature.temperature", "22"), ("climate", "set_swing_mode.swing_mode", "on"),
            ("number", "set_value.value", 0.25), ("number", "set_value.value", .number(.nan)),
            ("select", "select_option.option", "c"), ("select", "select_option.option", nil),
            ("light", "turn_on.rgb_color", .array([256, 0, 0])), ("light", "turn_on.rgb_color", .array([1, 2])),
            ("light", "turn_on.rgb_color", .array([0.5, 1, 2])), ("light", "turn_on.effect", "rainbow"),
            ("notify", "send_message.message", " \n"), ("notify", "send_message.message", 123),
            ("button", "press", nil), ("scene", "turn_on", nil), ("update", "install", nil)
        ]
        for (domain, controlID, value) in invalid {
            let accepted = await model.setEntityControlValue(EntityID("\(domain).office"), controlID: controlID, value: value)
            XCTAssertFalse(accepted, "\(domain).\(controlID)")
        }
        let calls = await server.journal.snapshot().filter { $0.path == "/api/websocket/call_service" }
        XCTAssertTrue(calls.isEmpty)
        for domain in ["sensor", "binary_sensor", "event", "device_tracker", "person", "sun", "weather", "zone", "conversation"] {
            XCTAssertTrue(PearchHAEntityControlField.controls(for: entity(domain)).isEmpty, domain)
        }
        for attributes: [String: ActionValue] in [["min": 2, "max": 1], ["min": 0], ["min": 0, "max": 1, "step": 0]] {
            XCTAssertTrue(PearchHAEntityControlField.controls(for: entity("number", attributes: attributes)).isEmpty)
        }
        XCTAssertTrue(PearchHAEntityControlField.controls(for: entity("select", attributes: ["options": .array([])])).isEmpty)
        XCTAssertTrue(PearchHAEntityControlField.controls(for: entity("light", attributes: ["supported_color_modes": .array(["onoff"])] )).isEmpty)
    }

    func testRangeTemperaturePreservesOtherEndpointAndHonorsBounds() throws {
        let fields = PearchHAEntityControlField.controls(for: entity("climate", attributes: [
            "supported_features": 518, "min_temp": 5, "max_temp": 30, "target_temp_step": 0.5,
            "target_temp_low": 18, "target_temp_high": 24, "min_humidity": 30, "max_humidity": 70,
            "swing_horizontal_modes": .array(["off", "on"])
        ]))
        let low = try XCTUnwrap(fields.first { $0.id == "set_temperature.target_temp_low" })
        let high = try XCTUnwrap(fields.first { $0.id == "set_temperature.target_temp_high" })
        XCTAssertEqual(low.actionSpec(value: 19.5)?.serviceData, ["target_temp_low": 19.5, "target_temp_high": 24])
        XCTAssertEqual(high.actionSpec(value: 25)?.serviceData, ["target_temp_low": 18, "target_temp_high": 25])
        XCTAssertNil(low.actionSpec(value: 25))
        XCTAssertNil(high.actionSpec(value: 17))
        XCTAssertTrue(fields.contains { $0.id == "set_humidity.humidity" })
        XCTAssertTrue(fields.contains { $0.id == "set_swing_horizontal_mode.swing_horizontal_mode" })
        XCTAssertTrue(PearchHAEntityControlField.controls(for: entity("climate", attributes: [
            "supported_features": 2, "min_temp": 5, "max_temp": 30, "target_temp_low": 3, "target_temp_high": 24
        ])).isEmpty)
    }

    func testLiveCapabilityChangesInvalidateAnOpenControl() async throws {
        let server = try FakeHAWebSocketServer()
        server.start()
        defer { server.stop() }
        let model = await connectedModel([entity("select", state: "a", attributes: ["options": .array(["a", "b"])])], server: server)
        XCTAssertTrue(model.applyLiveState(EntityState(id: "select.office", name: "Office select", state: "a", unit: nil,
                                                      controlAttributes: ["options": .array(["a"])])))
        let stale = await model.setEntityControlValue("select.office", controlID: "select_option.option", value: "b")
        XCTAssertFalse(stale)
        let accepted = await model.setEntityControlValue("select.office", controlID: "select_option.option", value: "a")
        XCTAssertTrue(accepted)
        let calls = await server.journal.snapshot().filter { $0.path == "/api/websocket/call_service" }
        XCTAssertEqual(calls.count, 1)
    }

    func testFailurePreservesReportedValuesAndAllowsRetry() async throws {
        let entities = [entity("number", state: "10", attributes: ["min": 0, "max": 100, "step": 1])]
        let rooms = [Room(id: "office", name: "Office", entities: entities)]
        let model = PearchHAPanelModel(connector: { _ in .success(rooms: rooms) }, actionRunner: { _, _ in .failed("Permission denied") })
        model.updateConnectionForm(urlString: "http://127.0.0.1:8123", token: "fake-token")
        await model.connect()
        for _ in 0..<2 {
            let success = await model.setEntityControlValue("number.office", controlID: "set_value.value", value: 20)
            XCTAssertFalse(success)
            XCTAssertEqual(model.snapshot.availableRooms.first?.entities.first?.state, "10")
            XCTAssertEqual(model.snapshot.controlActionState.failureMessage(for: "number.office"), "Permission denied")
        }
    }

    func testCancellationCannotFinishOrClearANewerControl() async {
        let gate = SuspendedControlRunner()
        let rooms = [Room(id: "office", name: "Office", entities: [entity("scene", state: "unknown")])]
        let model = PearchHAPanelModel(connector: { _ in .success(rooms: rooms) }, actionRunner: { _, _ in await gate.run() })
        model.updateConnectionForm(urlString: "http://127.0.0.1:8123", token: "fake-token")
        await model.connect()
        let first = Task { await model.setEntityControlValue("scene.office", controlID: "turn_on") }
        await gate.waitForCalls(1)
        XCTAssertFalse(model.startEntityControlValue("scene.office", controlID: "turn_on"))
        model.cancelInFlightAction()
        XCTAssertEqual(model.snapshot.controlActionState, .idle)
        let second = Task { await model.setEntityControlValue("scene.office", controlID: "turn_on") }
        await gate.waitForCalls(2)
        await gate.releaseNext()
        let firstResult = await first.value
        XCTAssertFalse(firstResult)
        XCTAssertEqual(model.snapshot.controlActionState, .running(entityID: "scene.office"))
        await gate.releaseNext()
        let secondResult = await second.value
        XCTAssertTrue(secondResult)
        XCTAssertEqual(model.snapshot.controlActionState, .idle)
    }

    func testCancellationBeforeExecutionDoesNotSendACommand() async {
        let rooms = [Room(id: "office", name: "Office", entities: [entity("scene", state: "unknown")])]
        let model = PearchHAPanelModel(connector: { _ in .success(rooms: rooms) }, actionRunner: { _, _ in
            XCTFail("Cancelled pending controls must not reach the action runner")
            return .success
        })
        model.updateConnectionForm(urlString: "http://127.0.0.1:8123", token: "fake-token")
        await model.connect()
        let task = Task { await model.setEntityControlValue("scene.office", controlID: "turn_on") }
        task.cancel()
        let result = await task.value
        XCTAssertFalse(result)
        XCTAssertEqual(model.snapshot.controlActionState, .idle)
    }

    func testTaskCancellationClearsBusyState() async {
        let gate = SuspendedControlRunner()
        let rooms = [Room(id: "office", name: "Office", entities: [entity("scene", state: "unknown")])]
        let model = PearchHAPanelModel(connector: { _ in .success(rooms: rooms) }, actionRunner: { _, _ in await gate.run() })
        model.updateConnectionForm(urlString: "http://127.0.0.1:8123", token: "fake-token")
        await model.connect()
        let task = Task { await model.setEntityControlValue("scene.office", controlID: "turn_on") }
        await gate.waitForCalls(1)
        task.cancel()
        await gate.releaseNext()
        let result = await task.value
        XCTAssertFalse(result)
        XCTAssertEqual(model.snapshot.controlActionState, .idle)
    }

    func testRefreshFailureReportsCommandSentWithoutInventingState() async {
        let rooms = [Room(id: "office", name: "Office", entities: [entity("number", state: "10", attributes: ["min": 0, "max": 100])])]
        let connection = ControlRefreshSequence(rooms: rooms)
        let model = PearchHAPanelModel(connector: { _ in await connection.next() }, actionRunner: { _, _ in .success })
        model.updateConnectionForm(urlString: "http://127.0.0.1:8123", token: "fake-token")
        await model.connect()
        let result = await model.setEntityControlValue("number.office", controlID: "set_value.value", value: 20)
        XCTAssertTrue(result, "The command was accepted even though refreshing its state failed")
        XCTAssertEqual(model.snapshot.availableRooms.first?.entities.first?.state, "10")
        XCTAssertEqual(model.snapshot.controlActionState.failureMessage(for: "number.office"), "Command sent. State refresh failed; values may be stale.")
    }

    func testEditorRendersNativeControlsInBothAppearances() async throws {
        let server = try FakeHAWebSocketServer()
        server.start()
        defer { server.stop() }
        let model = await connectedModel([entity("climate", state: "off", attributes: [
            "supported_features": 441, "temperature": 22, "current_temperature": 21.5,
            "min_temp": 16, "max_temp": 30, "target_temp_step": 1,
            "hvac_modes": .array(["auto", "cool", "dry", "fan_only", "heat", "off"]),
            "fan_modes": .array(["Auto", "Low", "Medium", "High"]), "fan_mode": "Low", "preset_modes": .array(["eco"])
        ])], server: server)
        for (name, scheme) in [("light", ColorScheme.light), ("dark", ColorScheme.dark)] {
            let view = NSHostingView(rootView: PearchHAEntityControlEditor(model: model, entityID: "climate.office").environment(\.colorScheme, scheme).background(Color(nsColor: .windowBackgroundColor)))
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 320, height: 460), styleMask: [.titled], backing: .buffered, defer: false)
            window.appearance = NSAppearance(named: name == "dark" ? .darkAqua : .aqua)
            window.contentView = view
            window.orderFront(nil)
            try await Task.sleep(for: .milliseconds(100))
            defer { window.orderOut(nil) }
            view.layoutSubtreeIfNeeded()
            XCTAssertGreaterThan(view.fittingSize.height, 200)
            if let directory = ProcessInfo.processInfo.environment["PEARCHHA_CONTROL_SNAPSHOT_DIR"] {
                let url = URL(fileURLWithPath: directory)
                try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
                let bitmap = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
                view.cacheDisplay(in: view.bounds, to: bitmap)
                let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
                try png.write(to: url.appendingPathComponent("climate-\(name).png"))
            }
        }
    }
}

private actor SuspendedControlRunner {
    private var callCount = 0
    private var pending: [CheckedContinuation<PearchHAActionResult, Never>] = []
    private var waiters: [(Int, CheckedContinuation<Void, Never>)] = []

    func run() async -> PearchHAActionResult {
        await withCheckedContinuation { continuation in
            pending.append(continuation)
            callCount += 1
            let ready = waiters.filter { $0.0 <= callCount }
            waiters.removeAll { $0.0 <= callCount }
            ready.forEach { $0.1.resume() }
        }
    }

    func waitForCalls(_ count: Int) async {
        guard callCount < count else { return }
        await withCheckedContinuation { waiters.append((count, $0)) }
    }

    func releaseNext() {
        pending.removeFirst().resume(returning: .success)
    }
}

private actor ControlRefreshSequence {
    private var first = true
    let rooms: [Room]
    init(rooms: [Room]) { self.rooms = rooms }
    func next() -> PearchHAConnectionAttemptResult {
        if first {
            first = false
            return .success(rooms: rooms)
        }
        return .failure(.unreachable(host: "localhost"))
    }
}
