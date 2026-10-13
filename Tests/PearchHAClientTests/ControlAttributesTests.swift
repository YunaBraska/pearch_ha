import FakeHA
import Foundation
import PearchHAClient
import PearchHACore
import XCTest

final class ControlAttributesTests: XCTestCase {
    private let original = #"{"entity_id":"climate.office","state":"off","attributes":{"friendly_name":"Office AC","supported_features":441,"temperature":22,"min_temp":16,"max_temp":30,"target_temp_step":1,"hvac_modes":["cool","off"],"fan_modes":["Low","High"],"swing_modes":[],"unrelated_metadata":{"ignored":true}}}"#

    private func input(_ server: FakeHAWebSocketServer) -> HAConnectionInput {
        HAConnectionInput(endpoint: HAEndpoint(primaryURL: server.baseURL, fallbackURL: nil), token: "fake-token")
    }

    func testRESTAndWebSocketDiscoveryPreserveOnlyControlAttributes() async throws {
        let server = try FakeHAWebSocketServer(fixtures: FakeHAFixtures(apiBody: "{}", statesBody: "[\(original)]"))
        server.start()
        defer { server.stop() }
        let client = HomeAssistantClient()
        let rest = await client.states(input(server))
        let websocket = await client.webSocketStates(input(server))
        guard case let .success(states) = rest, case let .success(wsStates) = websocket else {
            return XCTFail("Expected REST and WebSocket states: \(rest), \(websocket)")
        }
        XCTAssertEqual(states, wsStates)
        let state = try XCTUnwrap(states.first)
        XCTAssertEqual(state.controlAttributes?["supported_features"], 441)
        XCTAssertEqual(state.controlAttributes?["temperature"], 22)
        XCTAssertEqual(state.controlAttributes?["hvac_modes"], .array(["cool", "off"]))
        XCTAssertEqual(state.controlAttributes?["swing_modes"], .array([]))
        XCTAssertNil(state.controlAttributes?["unrelated_metadata"])
        XCTAssertNil(state.controlAttributes?["friendly_name"])
    }

    func testCompactChangeMergesAttributesAndPreservesExplicitNull() async throws {
        let server = try FakeHAWebSocketServer(fixtures: FakeHAFixtures(
            apiBody: "{}", statesBody: "[\(original)]",
            stateChangedEventBody: #"{"entity_id":"climate.office","attributes":{"temperature":null,"fan_modes":["Auto"]}}"#
        ), mode: .partialSubscribeEntitiesChange)
        server.start()
        defer { server.stop() }
        guard case let .success(state) = await HomeAssistantClient().nextStateChangedEvent(input(server)) else {
            return XCTFail("Expected compact attribute change")
        }
        XCTAssertEqual(state.state, "off")
        XCTAssertEqual(state.name, "Office AC")
        XCTAssertEqual(state.controlAttributes?["temperature"], .null)
        XCTAssertEqual(state.controlAttributes?["fan_modes"], .array(["Auto"]))
        XCTAssertEqual(state.controlAttributes?["min_temp"], 16)
        XCTAssertEqual(state.controlAttributes?["supported_features"], 441)
    }

    func testCompactRemovalDeletesOnlyNamedAttributes() async throws {
        let server = try FakeHAWebSocketServer(fixtures: FakeHAFixtures(
            apiBody: "{}", statesBody: "[\(original)]", stateChangedEventBody: original,
            removedAttributeNames: ["temperature", "fan_modes", "swing_modes"]
        ), mode: .attributeRemovalSubscribeEntitiesChange)
        server.start()
        defer { server.stop() }
        guard case let .success(state) = await HomeAssistantClient().nextStateChangedEvent(input(server)) else {
            return XCTFail("Expected compact attribute removal")
        }
        XCTAssertEqual(state.name, "Office AC")
        XCTAssertEqual(state.controlAttributes?["supported_features"], 441)
        XCTAssertEqual(state.controlAttributes?["min_temp"], 16)
        XCTAssertNil(state.controlAttributes?["temperature"])
        XCTAssertNil(state.controlAttributes?["fan_modes"])
        XCTAssertNil(state.controlAttributes?["swing_modes"])
    }

    func testFullEventsReplaceCapabilitiesInsteadOfMergingStaleFields() async throws {
        for mode: FakeHAWebSocketMode in [.normal, .unsupportedCommands(["subscribe_entities"])] {
            let server = try FakeHAWebSocketServer(fixtures: FakeHAFixtures(
                apiBody: "{}", statesBody: "[\(original)]",
                stateChangedEventBody: #"{"entity_id":"climate.office","state":"cool","attributes":{"friendly_name":"Office AC","supported_features":1,"temperature":23}}"#
            ), mode: mode)
            server.start()
            defer { server.stop() }
            guard case let .success(state) = await HomeAssistantClient().nextStateChangedEvent(input(server)) else {
                return XCTFail("Expected full state change")
            }
            XCTAssertEqual(state.state, "cool")
            XCTAssertEqual(state.controlAttributes, ["supported_features": 1, "temperature": 23])
        }
    }
}
