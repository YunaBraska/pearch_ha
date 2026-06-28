#if canImport(XCTest)
import Foundation
import XCTest
import FakeHA

final class FakeHATests: XCTestCase {
    func testFakeHAServesAPIAndStates() async throws {
        let server = try FakeHARESTServer()
        server.start()
        defer {
            server.stop()
        }

        let api = try await get(path: "/api/", baseURL: server.baseURL)
        XCTAssertEqual(api.status, 200)
        XCTAssertEqual(api.body, #"{"message":"API running."}"#)

        let states = try await get(path: "/api/states", baseURL: server.baseURL)
        XCTAssertEqual(states.status, 200)
        XCTAssertEqual(states.body, #"[]"#)
    }

    func testFakeHARESTServerSupportsPathPrefixes() async throws {
        let server = try FakeHARESTServer(pathPrefix: "/ha")
        server.start()
        defer {
            server.stop()
        }

        let states = try await get(path: "/api/states", baseURL: server.baseURL)

        XCTAssertEqual(states.status, 200)
        XCTAssertEqual(states.body, #"[]"#)
        let journal = await server.journal.snapshot()
        XCTAssertEqual(journal.last?.path, "/ha/api/states")
    }

    func testFakeHARejectsMissingBearerTokenAndJournalsRedactedHeaders() async throws {
        let server = try FakeHARESTServer()
        server.start()
        defer {
            server.stop()
        }

        let url = server.baseURL.appendingPathComponent("api/states")
        let (_, response) = try await URLSession.shared.data(from: url)
        let http = try XCTUnwrap(response as? HTTPURLResponse)

        XCTAssertEqual(http.statusCode, 401)

        let journal = await server.journal.snapshot()
        XCTAssertEqual(journal.last?.path, "/api/states")
    }

    func testFakeHAJournalsRedactedAuthorizationHeader() async throws {
        let server = try FakeHARESTServer()
        server.start()
        defer {
            server.stop()
        }

        _ = try await get(path: "/api/states", baseURL: server.baseURL)
        for _ in 0..<100 {
            if await !server.journal.snapshot().isEmpty {
                break
            }
            await Task.yield()
        }

        let journal = await server.journal.snapshot()
        XCTAssertEqual(journal.last?.headers["authorization"], "<redacted>")
    }

    func testFakeHALoadsFixturesFromMirrorFiles() throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("fakeha-fixtures-\(UUID().uuidString)", isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: directory)
        }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try #"{"bodyText":"{\"message\":\"API running.\"}"}"#.write(
            to: directory.appendingPathComponent("api.json"),
            atomically: true,
            encoding: .utf8
        )
        try #"{"bodyText":"[{\"entity_id\":\"sensor.one\"}]"}"#.write(
            to: directory.appendingPathComponent("states.json"),
            atomically: true,
            encoding: .utf8
        )

        let fixtures = try FakeHAFixtures.load(from: directory)

        XCTAssertEqual(fixtures.apiBody, #"{"message":"API running."}"#)
        XCTAssertEqual(fixtures.statesBody, #"[{"entity_id":"sensor.one"}]"#)
        XCTAssertEqual(fixtures.entityRegistryDisplayBody, #"{"entities":[{"ei":"sensor.one"}]}"#)
        XCTAssertEqual(fixtures.entityRegistryBody, #"[{"entity_id":"sensor.one"}]"#)
    }

    func testFakeHALoadsMirrorFixturesAndSynthesizesDisplayRegistryResults() async throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("fakeha-fixtures-\(UUID().uuidString)", isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: directory)
        }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try #"{"bodyText":"{\"message\":\"API running.\"}"}"#.write(
            to: directory.appendingPathComponent("api.json"),
            atomically: true,
            encoding: .utf8
        )
        try #"{"bodyText":"[{\"entity_id\":\"sensor.one\",\"attributes\":{\"friendly_name\":\"Kitchen sensor\"}}]"}"#.write(
            to: directory.appendingPathComponent("states.json"),
            atomically: true,
            encoding: .utf8
        )

        let fixtures = try FakeHAFixtures.load(from: directory)
        let server = try FakeHAWebSocketServer(fixtures: fixtures)
        server.start()
        defer {
            server.stop()
        }

        let task = URLSession.shared.webSocketTask(with: try webSocketURL(baseURL: server.baseURL))
        task.resume()
        defer {
            task.cancel(with: .goingAway, reason: nil)
        }

        XCTAssertEqual(try await receiveString(task), #"{"type":"auth_required","ha_version":"fake-ha"}"#)
        try await task.send(.string(#"{"type":"auth","access_token":"fake-token"}"#))
        XCTAssertEqual(try await receiveString(task), #"{"type":"auth_ok","ha_version":"fake-ha"}"#)
        try await task.send(.string(#"{"id":7,"type":"config/entity_registry/list_for_display"}"#))

        let result = try await receiveString(task)

        XCTAssertTrue(result.contains(#""id":7"#))
        XCTAssertTrue(result.contains(#""success":true"#))
        XCTAssertTrue(result.contains(#""ei":"sensor.one""#))
        XCTAssertTrue(result.contains(#""en":"Kitchen sensor""#))
    }

    func testFakeHAMirroredWebSocketModePreservesPerCommandAvailabilityCodes() {
        let mode = FakeHAWebSocketMode.mirrored(
            commandAvailability: [
                FakeHAWebSocketCommandAvailability(
                    command: "config/entity_registry/list_for_display",
                    available: false,
                    errorCode: "unsupported_command"
                ),
                FakeHAWebSocketCommandAvailability(
                    command: "subscribe_entities",
                    available: false,
                    errorCode: "unknown_command"
                )
            ]
        )

        XCTAssertEqual(mode.unavailableCommandCode(for: "config/entity_registry/list_for_display"), .unsupportedCommand)
        XCTAssertEqual(mode.unavailableCommandCode(for: "subscribe_entities"), .unknownCommand)
        XCTAssertNil(mode.unavailableCommandCode(for: "get_states"))
    }

    func testFakeHAWebSocketAuthHandshake() {
        let auth = FakeHAWebSocketAuth()

        XCTAssertEqual(auth.authRequiredMessage, #"{"type":"auth_required","ha_version":"fake-ha"}"#)
        XCTAssertEqual(
            auth.authenticate(clientMessage: #"{"type":"auth","access_token":"fake-token"}"#),
            #"{"type":"auth_ok","ha_version":"fake-ha"}"#
        )
        XCTAssertEqual(
            auth.authenticate(clientMessage: #"{"type":"auth","access_token":"wrong"}"#),
            #"{"type":"auth_invalid","message":"Invalid access token"}"#
        )
    }

    func testFakeHAWebSocketServerAuthenticatesAndReturnsStates() async throws {
        let fixtures = FakeHAFixtures(
            apiBody: #"{"message":"API running."}"#,
            statesBody: #"[{"entity_id":"sensor.office_temperature","state":"21.4","attributes":{"friendly_name":"Office temperature","unit_of_measurement":"°C"}}]"#
        )
        let server = try FakeHAWebSocketServer(fixtures: fixtures)
        server.start()
        defer {
            server.stop()
        }

        let task = URLSession.shared.webSocketTask(with: try webSocketURL(baseURL: server.baseURL))
        task.resume()
        defer {
            task.cancel(with: .goingAway, reason: nil)
        }

        XCTAssertEqual(try await receiveString(task), #"{"type":"auth_required","ha_version":"fake-ha"}"#)
        try await task.send(.string(#"{"type":"auth","access_token":"fake-token"}"#))
        XCTAssertEqual(try await receiveString(task), #"{"type":"auth_ok","ha_version":"fake-ha"}"#)
        try await task.send(.string(#"{"id":1,"type":"get_states"}"#))

        let result = try await receiveString(task)
        XCTAssertTrue(result.contains(#""type":"result""#))
        XCTAssertTrue(result.contains(#""success":true"#))
        XCTAssertTrue(result.contains("sensor.office_temperature"))
    }

    func testFakeHAWebSocketServerRejectsUnknownCommandExplicitly() async throws {
        let server = try FakeHAWebSocketServer()
        server.start()
        defer {
            server.stop()
        }

        let task = URLSession.shared.webSocketTask(with: try webSocketURL(baseURL: server.baseURL))
        task.resume()
        defer {
            task.cancel(with: .goingAway, reason: nil)
        }

        XCTAssertEqual(try await receiveString(task), #"{"type":"auth_required","ha_version":"fake-ha"}"#)
        try await task.send(.string(#"{"type":"auth","access_token":"fake-token"}"#))
        XCTAssertEqual(try await receiveString(task), #"{"type":"auth_ok","ha_version":"fake-ha"}"#)
        try await task.send(.string(#"{"id":9,"type":"unknown_command"}"#))

        let result = try await receiveString(task)

        XCTAssertTrue(result.contains(#""id":9"#))
        XCTAssertTrue(result.contains(#""success":false"#))
        XCTAssertTrue(result.contains(#""code":"unknown_command""#))
    }

    func testFakeHAWebSocketServerReturnsRecorderStatistics() async throws {
        let fixtures = FakeHAFixtures(
            apiBody: #"{"message":"API running."}"#,
            statesBody: #"[]"#,
            recorderStatisticsBody: #"{"sensor.office_temperature":[{"start":1782554400000,"end":1782558000000,"mean":21.4}]}"#
        )
        let server = try FakeHAWebSocketServer(fixtures: fixtures)
        server.start()
        defer {
            server.stop()
        }

        let task = URLSession.shared.webSocketTask(with: try webSocketURL(baseURL: server.baseURL))
        task.resume()
        defer {
            task.cancel(with: .goingAway, reason: nil)
        }

        XCTAssertEqual(try await receiveString(task), #"{"type":"auth_required","ha_version":"fake-ha"}"#)
        try await task.send(.string(#"{"type":"auth","access_token":"fake-token"}"#))
        XCTAssertEqual(try await receiveString(task), #"{"type":"auth_ok","ha_version":"fake-ha"}"#)
        try await task.send(
            .string(
                #"{"id":3,"type":"recorder/statistics_during_period","statistic_ids":["sensor.office_temperature"],"period":"hour","start_time":"2026-06-20T12:00:00Z","end_time":"2026-06-27T12:00:00Z","types":["mean","state"]}"#
            )
        )

        let result = try await receiveString(task)

        XCTAssertTrue(result.contains(#""id":3"#))
        XCTAssertTrue(result.contains(#""success":true"#))
        XCTAssertTrue(result.contains(#""sensor.office_temperature""#))
        XCTAssertTrue(result.contains(#""mean":21.4"#))
    }

    func testFakeHAWebSocketServerReturnsServiceMetadata() async throws {
        let fixtures = FakeHAFixtures(
            apiBody: #"{"message":"API running."}"#,
            statesBody: #"[]"#,
            servicesBody: #"{"script":{"turn_on":{"name":"Turn on","fields":{"entity_id":{"required":true}}}}}"#
        )
        let server = try FakeHAWebSocketServer(fixtures: fixtures)
        server.start()
        defer {
            server.stop()
        }

        let task = URLSession.shared.webSocketTask(with: try webSocketURL(baseURL: server.baseURL))
        task.resume()
        defer {
            task.cancel(with: .goingAway, reason: nil)
        }

        XCTAssertEqual(try await receiveString(task), #"{"type":"auth_required","ha_version":"fake-ha"}"#)
        try await task.send(.string(#"{"type":"auth","access_token":"fake-token"}"#))
        XCTAssertEqual(try await receiveString(task), #"{"type":"auth_ok","ha_version":"fake-ha"}"#)
        try await task.send(.string(#"{"id":4,"type":"get_services"}"#))

        let result = try await receiveString(task)

        XCTAssertTrue(result.contains(#""id":4"#))
        XCTAssertTrue(result.contains(#""success":true"#))
        XCTAssertTrue(result.contains(#""script""#))
        XCTAssertTrue(result.contains(#""turn_on""#))
        XCTAssertTrue(result.contains(#""entity_id""#))
    }

    func testFakeHAWebSocketServerSupportsPathPrefixes() async throws {
        let server = try FakeHAWebSocketServer(pathPrefix: "/ha")
        server.start()
        defer {
            server.stop()
        }

        let task = URLSession.shared.webSocketTask(with: try webSocketURL(baseURL: server.baseURL))
        task.resume()
        defer {
            task.cancel(with: .goingAway, reason: nil)
        }

        XCTAssertEqual(try await receiveString(task), #"{"type":"auth_required","ha_version":"fake-ha"}"#)
        try await task.send(.string(#"{"type":"auth","access_token":"fake-token"}"#))
        XCTAssertEqual(try await receiveString(task), #"{"type":"auth_ok","ha_version":"fake-ha"}"#)
        let journal = await server.journal.snapshot()
        XCTAssertEqual(journal.last?.path, "/ha/api/websocket")
    }

    func testFakeHAWebSocketServerRejectsInvalidToken() async throws {
        let server = try FakeHAWebSocketServer()
        server.start()
        defer {
            server.stop()
        }

        let task = URLSession.shared.webSocketTask(with: try webSocketURL(baseURL: server.baseURL))
        task.resume()
        defer {
            task.cancel(with: .goingAway, reason: nil)
        }

        _ = try await receiveString(task)
        try await task.send(.string(#"{"type":"auth","access_token":"wrong"}"#))
        XCTAssertEqual(try await receiveString(task), #"{"type":"auth_invalid","message":"Invalid access token"}"#)
    }

    func testFakeHAServersStartOnDistinctPortsUnderBurstCreation() throws {
        var restServers: [FakeHARESTServer] = []
        var webSocketServers: [FakeHAWebSocketServer] = []
        defer {
            restServers.forEach { $0.stop() }
            webSocketServers.forEach { $0.stop() }
        }

        for _ in 0..<12 {
            let rest = try FakeHARESTServer()
            rest.start()
            restServers.append(rest)

            let webSocket = try FakeHAWebSocketServer()
            webSocket.start()
            webSocketServers.append(webSocket)
        }

        let restPorts = Set(restServers.compactMap { $0.baseURL.port })
        let webSocketPorts = Set(webSocketServers.compactMap { $0.baseURL.port })
        XCTAssertEqual(restPorts.count, restServers.count)
        XCTAssertEqual(webSocketPorts.count, webSocketServers.count)
        XCTAssertTrue(restPorts.isDisjoint(with: webSocketPorts))
    }

    func testFakeHAConsumesCoalescedWebSocketBytes() throws {
        let fixtures = FakeHAFixtures(
            apiBody: #"{"message":"API running."}"#,
            statesBody: #"[{"entity_id":"sensor.office_temperature","state":"21.4","attributes":{"friendly_name":"Office temperature","unit_of_measurement":"°C"}}]"#
        )
        let server = try FakeHAWebSocketServer(fixtures: fixtures)
        server.start()
        defer {
            server.stop()
        }

        let probe = FakeHARawWebSocketProbe()
        let coalescedAuth = try probe.authenticateWithCoalescedUpgrade(baseURL: server.baseURL)
        XCTAssertNotNil(coalescedAuth.range(of: Data(#""type":"auth_ok""#.utf8)))

        let coalescedCommands = try probe.authenticateThenSendCoalescedCommands(baseURL: server.baseURL)
        XCTAssertNotNil(coalescedCommands.range(of: Data(#""id":1"#.utf8)))
        XCTAssertNotNil(coalescedCommands.range(of: Data(#""id":2"#.utf8)))
    }

    private func get(path: String, baseURL: URL) async throws -> (status: Int, body: String) {
        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)
        components?.path = appendingPath(path, to: baseURL.path)
        let url = try XCTUnwrap(components?.url)
        var request = URLRequest(url: url)
        request.setValue("Bearer fake-token", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        let http = try XCTUnwrap(response as? HTTPURLResponse)
        return (http.statusCode, String(data: data, encoding: .utf8) ?? "")
    }

    private func webSocketURL(baseURL: URL) throws -> URL {
        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)
        components?.scheme = "ws"
        components?.path = appendingPath("/api/websocket", to: baseURL.path)
        return try XCTUnwrap(components?.url)
    }

    private func appendingPath(_ path: String, to basePath: String) -> String {
        let normalizedBase = basePath == "/" ? "" : basePath.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let prefix = normalizedBase.isEmpty ? "" : "/\(normalizedBase)"
        return "\(prefix)\(path)"
    }

    private func receiveString(_ task: URLSessionWebSocketTask) async throws -> String {
        switch try await task.receive() {
        case let .string(text):
            return text
        case let .data(data):
            return String(data: data, encoding: .utf8) ?? ""
        @unknown default:
            return ""
        }
    }
}
#endif
