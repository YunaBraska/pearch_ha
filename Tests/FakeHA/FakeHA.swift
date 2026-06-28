import Foundation
import Darwin
import CryptoKit
import Network
import PerchHASupport

public struct FakeHAFixtures: Equatable, Sendable {
    public let apiBody: String
    public let statesBody: String
    public let historyBody: String
    public let stateChangedEventBody: String
    public let areaRegistryBody: String
    public let deviceRegistryBody: String
    public let entityRegistryDisplayBody: String?
    public let entityRegistryBody: String
    public let recorderStatisticsBody: String
    public let servicesBody: String
    public let bearerToken: String

    public init(
        apiBody: String,
        statesBody: String,
        historyBody: String = "[]",
        stateChangedEventBody: String? = nil,
        areaRegistryBody: String = "[]",
        deviceRegistryBody: String = "[]",
        entityRegistryDisplayBody: String? = nil,
        entityRegistryBody: String = "[]",
        recorderStatisticsBody: String = "{}",
        servicesBody: String = "{}",
        bearerToken: String = "fake-token"
    ) {
        self.apiBody = apiBody
        self.statesBody = statesBody
        self.historyBody = historyBody
        self.stateChangedEventBody = stateChangedEventBody ?? Self.defaultStateChangedEventBody(statesBody: statesBody)
        self.areaRegistryBody = areaRegistryBody
        self.deviceRegistryBody = deviceRegistryBody
        self.entityRegistryDisplayBody = entityRegistryDisplayBody
        self.entityRegistryBody = entityRegistryBody
        self.recorderStatisticsBody = recorderStatisticsBody
        self.servicesBody = servicesBody
        self.bearerToken = bearerToken
    }

    public static let minimal = FakeHAFixtures(
        apiBody: #"{"message":"API running."}"#,
        statesBody: #"[]"#
    )

    public static func load(from directory: URL, bearerToken: String = "fake-token") throws -> FakeHAFixtures {
        let api = try CapturedEndpointFile.load(from: directory.appendingPathComponent("api.json"))
        let states = try CapturedEndpointFile.load(from: directory.appendingPathComponent("states.json"))
        return FakeHAFixtures(apiBody: api.bodyText, statesBody: states.bodyText, bearerToken: bearerToken)
    }

    private static func defaultStateChangedEventBody(statesBody: String) -> String {
        guard
            let data = statesBody.data(using: .utf8),
            let states = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]],
            let first = states.first,
            let eventData = try? JSONSerialization.data(withJSONObject: first, options: [.sortedKeys]),
            let eventText = String(data: eventData, encoding: .utf8)
        else {
            return #"{"entity_id":"sensor.entity_001","state":"0","attributes":{}}"#
        }
        return eventText
    }
}

public struct FakeHAJournalEntry: Equatable, Sendable {
    public let method: String
    public let path: String
    public let headers: [String: String]
    public let bodyText: String?

    public init(method: String, path: String, headers: [String: String], bodyText: String? = nil) {
        self.method = method
        self.path = path
        self.headers = headers
        self.bodyText = bodyText
    }
}

public actor FakeHAJournal {
    private var entries: [FakeHAJournalEntry] = []

    public init() {}

    public func record(_ entry: FakeHAJournalEntry) {
        entries.append(entry)
    }

    public func snapshot() -> [FakeHAJournalEntry] {
        entries
    }
}

public final class FakeHARESTServer: @unchecked Sendable {
    public let baseURL: URL
    public let journal: FakeHAJournal

    private let listener: NWListener
    private let queue: DispatchQueue
    private let fixtures: FakeHAFixtures
    private let redactor: Redactor
    private let pathPrefix: String

    public init(fixtures: FakeHAFixtures = .minimal, pathPrefix: String = "", redactor: Redactor = Redactor()) throws {
        let endpoint = try Self.makeLoopbackListener()
        let port = endpoint.port
        let listener = endpoint.listener
        let normalizedPathPrefix = Self.normalizedPathPrefix(pathPrefix)

        self.listener = listener
        self.fixtures = fixtures
        self.redactor = redactor
        self.pathPrefix = normalizedPathPrefix
        self.journal = FakeHAJournal()
        self.queue = DispatchQueue(label: "dev.perchha.fakeha.rest")
        self.baseURL = URL(string: "http://127.0.0.1:\(port)\(normalizedPathPrefix)")!
    }

    public func start() {
        listener.newConnectionHandler = { [weak self] connection in
            self?.handle(connection: connection)
        }
        listener.start(queue: queue)
    }

    public func stop() {
        listener.cancel()
    }

    private func handle(connection: NWConnection) {
        connection.start(queue: queue)
        receiveHTTPRequest(on: connection) { [weak self] read in
            guard let self else {
                connection.cancel()
                return
            }
            guard let read else {
                connection.cancel()
                return
            }
            let request = read.request
            Task {
                await journal.record(
                    FakeHAJournalEntry(
                        method: request.method,
                        path: request.path,
                        headers: redactor.redact(headers: request.headers)
                    )
                )
            }
            let response = self.response(for: request)
            connection.send(content: response, completion: .contentProcessed { _ in
                connection.cancel()
            })
        }
    }

    private func response(for request: HTTPRequest) -> Data {
        guard let effectivePath = effectivePath(for: request.path) else {
            return httpResponse(status: 404, reason: "Not Found", body: #"{"message":"Not found"}"#)
        }

        guard request.headers["authorization"] == "Bearer \(fixtures.bearerToken)" else {
            return httpResponse(status: 401, reason: "Unauthorized", body: #"{"message":"Unauthorized"}"#)
        }

        guard request.method == "GET" else {
            return httpResponse(status: 405, reason: "Method Not Allowed", body: #"{"message":"Method not allowed"}"#)
        }

        switch effectivePath {
        case let path where path.hasPrefix("/api/history/period/"):
            return httpResponse(status: 200, reason: "OK", body: fixtures.historyBody)
        case "/api/":
            return httpResponse(status: 200, reason: "OK", body: fixtures.apiBody)
        case "/api/states":
            return httpResponse(status: 200, reason: "OK", body: fixtures.statesBody)
        default:
            return httpResponse(status: 404, reason: "Not Found", body: #"{"message":"Not found"}"#)
        }
    }

    private func receiveHTTPRequest(
        on connection: NWConnection,
        buffer: Data = Data(),
        completion: @escaping @Sendable (HTTPRequestRead?) -> Void
    ) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, _, _ in
            guard let self, let data, !data.isEmpty else {
                completion(nil)
                return
            }
            var nextBuffer = buffer
            nextBuffer.append(data)
            if let read = HTTPRequest.read(from: nextBuffer) {
                completion(read)
                return
            }
            receiveHTTPRequest(on: connection, buffer: nextBuffer, completion: completion)
        }
    }

    private func effectivePath(for requestPath: String) -> String? {
        let routePath = String(requestPath.split(separator: "?", maxSplits: 1).first.map(String.init) ?? requestPath)
        guard !pathPrefix.isEmpty else {
            return routePath
        }
        guard routePath == pathPrefix || routePath.hasPrefix("\(pathPrefix)/") else {
            return nil
        }
        let index = routePath.index(routePath.startIndex, offsetBy: pathPrefix.count)
        let suffix = String(routePath[index...])
        return suffix.isEmpty ? "/" : suffix
    }

    private func httpResponse(status: Int, reason: String, body: String) -> Data {
        let bytes = body.data(using: .utf8) ?? Data()
        let header = """
        HTTP/1.1 \(status) \(reason)\r
        Content-Type: application/json\r
        Content-Length: \(bytes.count)\r
        Connection: close\r
        \r

        """
        var data = Data(header.utf8)
        data.append(bytes)
        return data
    }

    private static func makeLoopbackListener(maxAttempts: Int = 16) throws -> (port: UInt16, listener: NWListener) {
        for _ in 0..<maxAttempts {
            let port = try reserveLoopbackPort()
            do {
                return try (port, NWListener(using: .tcp, on: NWEndpoint.Port(rawValue: port)!))
            } catch {
                continue
            }
        }
        throw FakeHAError.portReservationFailed
    }

    private static func reserveLoopbackPort() throws -> UInt16 {
        let descriptor = socket(AF_INET, SOCK_STREAM, 0)
        guard descriptor >= 0 else {
            throw FakeHAError.portReservationFailed
        }
        defer {
            close(descriptor)
        }

        var address = sockaddr_in(
            sin_len: UInt8(MemoryLayout<sockaddr_in>.size),
            sin_family: sa_family_t(AF_INET),
            sin_port: 0,
            sin_addr: in_addr(s_addr: INADDR_LOOPBACK.bigEndian),
            sin_zero: (0, 0, 0, 0, 0, 0, 0, 0)
        )

        let bindResult = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPointer in
                bind(descriptor, sockaddrPointer, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bindResult == 0 else {
            throw FakeHAError.portReservationFailed
        }

        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        let nameResult = withUnsafeMutablePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPointer in
                getsockname(descriptor, sockaddrPointer, &length)
            }
        }
        guard nameResult == 0 else {
            throw FakeHAError.portReservationFailed
        }

        return UInt16(bigEndian: address.sin_port)
    }

    private static func normalizedPathPrefix(_ pathPrefix: String) -> String {
        let trimmed = pathPrefix.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return trimmed.isEmpty ? "" : "/\(trimmed)"
    }
}

public enum FakeHAError: Error, Equatable {
    case missingPort
    case portReservationFailed
    case invalidWebSocketKey
}

public enum FakeHAUnavailableCommandCode: String, Equatable, Sendable {
    case unknownCommand = "unknown_command"
    case unsupportedCommand = "unsupported_command"
}

public enum FakeHAWebSocketMode: Equatable, Sendable {
    case normal
    case wrongResultID
    case commandFailure
    case silentAfterAuth
    case unsupportedCommands(Set<String>)
    case unavailableCommands(Set<String>, code: FakeHAUnavailableCommandCode)
    case partialSubscribeEntitiesChange
    case attributeRemovalSubscribeEntitiesChange
    case entityRemovalThenSubscribeEntitiesAddition
    case manyEntityRemovalsThenSubscribeEntitiesAddition(count: Int)
    case entityRemovalThenPartialSubscribeEntitiesChangeThenAddition
    case disconnectOnceAfterSubscribeEntitiesResult

    func unavailableCommandCode(for type: String) -> FakeHAUnavailableCommandCode? {
        switch self {
        case let .unsupportedCommands(commands):
            commands.contains(type) ? .unsupportedCommand : nil
        case let .unavailableCommands(commands, code):
            commands.contains(type) ? code : nil
        case .normal,
             .wrongResultID,
             .commandFailure,
             .silentAfterAuth,
             .partialSubscribeEntitiesChange,
             .attributeRemovalSubscribeEntitiesChange,
             .entityRemovalThenSubscribeEntitiesAddition,
             .manyEntityRemovalsThenSubscribeEntitiesAddition,
             .entityRemovalThenPartialSubscribeEntitiesChangeThenAddition,
             .disconnectOnceAfterSubscribeEntitiesResult:
            nil
        }
    }
}

public final class FakeHAWebSocketServer: @unchecked Sendable {
    public let baseURL: URL
    public let journal: FakeHAJournal

    private let listener: NWListener
    private let queue: DispatchQueue
    private let fixtures: FakeHAFixtures
    private let redactor: Redactor
    private let mode: FakeHAWebSocketMode
    private let pathPrefix: String
    private var heldConnections: [NWConnection] = []
    private var didDisconnectAfterSubscribeEntitiesResult = false

    public init(
        fixtures: FakeHAFixtures = .minimal,
        mode: FakeHAWebSocketMode = .normal,
        pathPrefix: String = "",
        redactor: Redactor = Redactor()
    ) throws {
        let endpoint = try Self.makeLoopbackListener()
        let port = endpoint.port
        let listener = endpoint.listener
        let normalizedPathPrefix = Self.normalizedPathPrefix(pathPrefix)

        self.listener = listener
        self.fixtures = fixtures
        self.redactor = redactor
        self.mode = mode
        self.pathPrefix = normalizedPathPrefix
        self.journal = FakeHAJournal()
        self.queue = DispatchQueue(label: "dev.perchha.fakeha.websocket")
        self.baseURL = URL(string: "http://127.0.0.1:\(port)\(normalizedPathPrefix)")!
    }

    public func start() {
        listener.newConnectionHandler = { [weak self] connection in
            self?.handle(connection: connection)
        }
        listener.start(queue: queue)
    }

    public func stop() {
        listener.cancel()
        queue.async { [weak self] in
            self?.heldConnections.forEach { $0.cancel() }
            self?.heldConnections.removeAll()
        }
    }

    private func handle(connection: NWConnection) {
        connection.start(queue: queue)
        receiveHTTPRequest(on: connection) { [weak self] request in
            guard let self else {
                connection.cancel()
                return
            }
            guard let read = request else {
                connection.cancel()
                return
            }
            let request = read.request
            Task {
                await journal.record(
                    FakeHAJournalEntry(
                        method: request.method,
                        path: request.path,
                        headers: redactor.redact(headers: request.headers)
                    )
                )
            }
            guard effectivePath(for: request.path) == "/api/websocket",
                  let key = request.headers["sec-websocket-key"],
                  let handshake = Self.handshakeResponse(for: key)
            else {
                let response = restResponse(for: request)
                connection.send(content: response, completion: .contentProcessed { _ in
                    connection.cancel()
                })
                return
            }

            connection.send(content: handshake, completion: .contentProcessed { [weak self] _ in
                self?.sendText(FakeHAWebSocketAuth(bearerToken: self?.fixtures.bearerToken ?? "").authRequiredMessage, to: connection)
                self?.receiveAuth(on: connection, buffer: read.remainder)
            })
        }
    }

    private func receiveAuth(on connection: NWConnection, buffer: Data = Data()) {
        receiveFrame(on: connection, buffer: buffer) { [weak self] result in
            guard let self, let result else {
                connection.cancel()
                return
            }
            let message = result.message
            let auth = FakeHAWebSocketAuth(bearerToken: fixtures.bearerToken)
            let response = auth.authenticate(clientMessage: message)
            guard response.contains("\"auth_ok\"") else {
                sendText(response, to: connection) {
                    connection.cancel()
                }
                return
            }
            if mode == .silentAfterAuth {
                heldConnections.append(connection)
                return
            }
            sendText(response, to: connection)
            receiveCommand(on: connection, buffer: result.remainder)
        }
    }

    private func receiveCommand(on connection: NWConnection, buffer: Data = Data()) {
        receiveFrame(on: connection, buffer: buffer) { [weak self] result in
            guard let self, let result else {
                connection.cancel()
                return
            }
            let message = result.message
            guard let data = message.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let id = object["id"] as? Int,
                  let type = object["type"] as? String
            else {
                sendText(#"{"id":0,"type":"result","success":false,"error":{"code":"invalid_format","message":"Unsupported command"}}"#, to: connection)
                connection.cancel()
                return
            }
            if mode == .commandFailure {
                sendText(#"{"id":\#(id),"type":"result","success":false,"error":{"code":"failed","message":"Planned command failure"}}"#, to: connection)
                return
            }
            if let unavailableCode = mode.unavailableCommandCode(for: type) {
                handleUnavailableCommand(id: id, type: type, code: unavailableCode, rawMessage: message, connection: connection, nextBuffer: result.remainder)
                return
            }
            switch type {
            case "get_states":
                sendText(statesResultMessage(id: id), to: connection)
                receiveCommand(on: connection, buffer: result.remainder)
            case "subscribe_entities":
                handleSubscribeEntities(id: id, rawMessage: message, connection: connection, nextBuffer: result.remainder)
            case "subscribe_events":
                handleSubscribeEvents(id: id, command: object, rawMessage: message, connection: connection, nextBuffer: result.remainder)
            case "call_service":
                handleCallService(id: id, command: object, rawMessage: message, connection: connection, nextBuffer: result.remainder)
            case "get_services":
                handleRegistryList(id: id, type: type, body: fixtures.servicesBody, rawMessage: message, connection: connection, nextBuffer: result.remainder)
            case "config/area_registry/list":
                handleRegistryList(id: id, type: type, body: fixtures.areaRegistryBody, rawMessage: message, connection: connection, nextBuffer: result.remainder)
            case "config/device_registry/list":
                handleRegistryList(id: id, type: type, body: fixtures.deviceRegistryBody, rawMessage: message, connection: connection, nextBuffer: result.remainder)
            case "config/entity_registry/list_for_display":
                guard let body = fixtures.entityRegistryDisplayBody else {
                    handleUnavailableCommand(id: id, type: type, code: .unknownCommand, rawMessage: message, connection: connection, nextBuffer: result.remainder)
                    return
                }
                handleRegistryList(id: id, type: type, body: body, rawMessage: message, connection: connection, nextBuffer: result.remainder)
            case "config/entity_registry/list":
                handleRegistryList(id: id, type: type, body: fixtures.entityRegistryBody, rawMessage: message, connection: connection, nextBuffer: result.remainder)
            case "recorder/statistics_during_period":
                handleRegistryList(id: id, type: type, body: fixtures.recorderStatisticsBody, rawMessage: message, connection: connection, nextBuffer: result.remainder)
            default:
                handleUnavailableCommand(id: id, type: type, code: .unknownCommand, rawMessage: message, connection: connection, nextBuffer: result.remainder)
            }
        }
    }

    private func receiveFrame(on connection: NWConnection, buffer: Data = Data(), completion: @escaping @Sendable (WebSocketMessageRead?) -> Void) {
        if let read = WebSocketFrame.read(from: buffer) {
            guard read.frame.opcode == .text,
                  let message = String(data: read.frame.payload, encoding: .utf8)
            else {
                completion(nil)
                return
            }
            completion(WebSocketMessageRead(message: message, remainder: read.remainder))
            return
        }

        connection.receive(minimumIncompleteLength: 2, maximumLength: 64 * 1024) { data, _, _, _ in
            guard let data, !data.isEmpty else {
                completion(nil)
                return
            }
            var nextBuffer = buffer
            nextBuffer.append(data)
            guard let read = WebSocketFrame.read(from: nextBuffer) else {
                self.receiveFrame(on: connection, buffer: nextBuffer, completion: completion)
                return
            }
            guard read.frame.opcode == .text,
                  let message = String(data: read.frame.payload, encoding: .utf8)
            else {
                completion(nil)
                return
            }
            completion(WebSocketMessageRead(message: message, remainder: read.remainder))
        }
    }

    private func receiveHTTPRequest(
        on connection: NWConnection,
        buffer: Data = Data(),
        completion: @escaping @Sendable (HTTPRequestRead?) -> Void
    ) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, _, _ in
            guard let self, let data, !data.isEmpty else {
                completion(nil)
                return
            }
            var nextBuffer = buffer
            nextBuffer.append(data)
            if let read = HTTPRequest.read(from: nextBuffer) {
                completion(read)
                return
            }
            receiveHTTPRequest(on: connection, buffer: nextBuffer, completion: completion)
        }
    }

    private func effectivePath(for requestPath: String) -> String? {
        guard !pathPrefix.isEmpty else {
            return requestPath
        }
        guard requestPath == pathPrefix || requestPath.hasPrefix("\(pathPrefix)/") else {
            return nil
        }
        let index = requestPath.index(requestPath.startIndex, offsetBy: pathPrefix.count)
        let suffix = String(requestPath[index...])
        return suffix.isEmpty ? "/" : suffix
    }

    private func sendText(_ text: String, to connection: NWConnection, completion: (@Sendable () -> Void)? = nil) {
        connection.send(content: WebSocketFrame.text(text), completion: .contentProcessed { _ in
            completion?()
        })
    }

    private func sendTexts(_ texts: [String], to connection: NWConnection, completion: @escaping @Sendable () -> Void) {
        guard let first = texts.first else {
            completion()
            return
        }
        sendText(first, to: connection) { [weak self] in
            guard let self else {
                connection.cancel()
                return
            }
            sendTexts(Array(texts.dropFirst()), to: connection, completion: completion)
        }
    }

    private func sendUnavailableCommand(id: Int, code: FakeHAUnavailableCommandCode, to connection: NWConnection) {
        sendText(#"{"id":\#(id),"type":"result","success":false,"error":{"code":"\#(code.rawValue)","message":"Command unavailable"}}"#, to: connection)
    }

    private func statesResultMessage(id: Int) -> String {
        let resultID = mode == .wrongResultID ? id + 1 : id
        return #"{"id":\#(resultID),"type":"result","success":true,"result":\#(fixtures.statesBody)}"#
    }

    private func handleSubscribeEntities(id: Int, rawMessage: String, connection: NWConnection, nextBuffer: Data) {
        let disconnectAfterResult: Bool
        if mode == .disconnectOnceAfterSubscribeEntitiesResult && !didDisconnectAfterSubscribeEntitiesResult {
            didDisconnectAfterSubscribeEntitiesResult = true
            disconnectAfterResult = true
        } else {
            disconnectAfterResult = false
        }
        Task {
            await journal.record(
                FakeHAJournalEntry(
                    method: "WS",
                    path: "/api/websocket/subscribe_entities",
                    headers: [:],
                    bodyText: redactor.redact(message: rawMessage)
                )
            )
            sendText(#"{"id":\#(id),"type":"result","success":true,"result":null}"#, to: connection) { [weak self] in
                guard let self else {
                    connection.cancel()
                    return
                }
                guard !disconnectAfterResult else {
                    connection.cancel()
                    return
                }
                sendTexts(subscribeEntitiesEventMessages(id: id), to: connection) { [weak self] in
                    self?.receiveCommand(on: connection, buffer: nextBuffer)
                }
            }
        }
    }

    private func handleSubscribeEvents(id: Int, command: [String: Any], rawMessage: String, connection: NWConnection, nextBuffer: Data) {
        guard command["event_type"] as? String == "state_changed" else {
            sendText(#"{"id":\#(id),"type":"result","success":false,"error":{"code":"unsupported_event","message":"Only state_changed is supported"}}"#, to: connection)
            receiveCommand(on: connection, buffer: nextBuffer)
            return
        }
        Task {
            await journal.record(
                FakeHAJournalEntry(
                    method: "WS",
                    path: "/api/websocket/subscribe_events",
                    headers: [:],
                    bodyText: redactor.redact(message: rawMessage)
                )
            )
            sendText(#"{"id":\#(id),"type":"result","success":true,"result":null}"#, to: connection) { [weak self] in
                guard let self else {
                    connection.cancel()
                    return
                }
                sendText(stateChangedEventMessage(id: id), to: connection)
                receiveCommand(on: connection, buffer: nextBuffer)
            }
        }
    }

    private func handleCallService(id: Int, command: [String: Any], rawMessage: String, connection: NWConnection, nextBuffer: Data) {
        guard command["domain"] as? String != nil, command["service"] as? String != nil else {
            sendText(#"{"id":\#(id),"type":"result","success":false,"error":{"code":"invalid_format","message":"Service call missing domain or service"}}"#, to: connection)
            receiveCommand(on: connection, buffer: nextBuffer)
            return
        }
        Task {
            await journal.record(
                FakeHAJournalEntry(
                    method: "WS",
                    path: "/api/websocket/call_service",
                    headers: [:],
                    bodyText: redactor.redact(message: rawMessage)
                )
            )
            sendText(#"{"id":\#(id),"type":"result","success":true,"result":{"context":{"id":"fake-context"},"response":null}}"#, to: connection)
            receiveCommand(on: connection, buffer: nextBuffer)
        }
    }

    private func handleRegistryList(id: Int, type: String, body: String, rawMessage: String, connection: NWConnection, nextBuffer: Data) {
        Task {
            await journal.record(
                FakeHAJournalEntry(
                    method: "WS",
                    path: "/api/websocket/\(type)",
                    headers: [:],
                    bodyText: redactor.redact(message: rawMessage)
                )
            )
            sendText(#"{"id":\#(id),"type":"result","success":true,"result":\#(body)}"#, to: connection)
            receiveCommand(on: connection, buffer: nextBuffer)
        }
    }

    private func handleUnavailableCommand(id: Int, type: String, code: FakeHAUnavailableCommandCode, rawMessage: String, connection: NWConnection, nextBuffer: Data) {
        Task {
            await journal.record(
                FakeHAJournalEntry(
                    method: "WS",
                    path: "/api/websocket/\(type)",
                    headers: [:],
                    bodyText: redactor.redact(message: rawMessage)
                )
            )
            sendUnavailableCommand(id: id, code: code, to: connection)
            receiveCommand(on: connection, buffer: nextBuffer)
        }
    }

    private func stateChangedEventMessage(id: Int) -> String {
        #"{"id":\#(id),"type":"event","event":{"event_type":"state_changed","data":{"entity_id":"\#(eventEntityID())","old_state":null,"new_state":\#(fixtures.stateChangedEventBody)},"origin":"LOCAL","time_fired":"2026-01-01T00:00:00+00:00","context":{"id":"fake-context"}}}"#
    }

    private func subscribeEntitiesEventMessages(id: Int) -> [String] {
        switch mode {
        case .partialSubscribeEntitiesChange:
            return [
                #"{"id":\#(id),"type":"event","event":{"c":{"\#(eventEntityID())":{"+":\#(subscribeEntitiesStateBody)}}}}"#
            ]
        case .attributeRemovalSubscribeEntitiesChange:
            return [
                #"{"id":\#(id),"type":"event","event":{"c":{"\#(eventEntityID())":{"-":{"a":["friendly_name","unit_of_measurement","current_position"]}}}}}"#
            ]
        case .entityRemovalThenSubscribeEntitiesAddition:
            return [
                #"{"id":\#(id),"type":"event","event":{"r":["\#(eventEntityID())"]}}"#,
                #"{"id":\#(id),"type":"event","event":{"a":{"\#(eventEntityID())":\#(subscribeEntitiesStateBody)}}}"#
            ]
        case let .manyEntityRemovalsThenSubscribeEntitiesAddition(count):
            let removal = #"{"id":\#(id),"type":"event","event":{"r":["\#(eventEntityID())"]}}"#
            let addition = #"{"id":\#(id),"type":"event","event":{"a":{"\#(eventEntityID())":\#(subscribeEntitiesStateBody)}}}"#
            return Array(repeating: removal, count: max(0, count)) + [addition]
        case .entityRemovalThenPartialSubscribeEntitiesChangeThenAddition:
            return [
                #"{"id":\#(id),"type":"event","event":{"r":["\#(eventEntityID())"]}}"#,
                #"{"id":\#(id),"type":"event","event":{"c":{"\#(eventEntityID())":{"+":\#(subscribeEntitiesStateOnlyBody)}}}}"#,
                #"{"id":\#(id),"type":"event","event":{"a":{"\#(eventEntityID())":\#(subscribeEntitiesStateBody)}}}"#
            ]
        case .normal, .wrongResultID, .commandFailure, .silentAfterAuth, .unsupportedCommands, .unavailableCommands:
            return [
                #"{"id":\#(id),"type":"event","event":{"a":{"\#(eventEntityID())":\#(subscribeEntitiesStateBody)}}}"#
            ]
        case .disconnectOnceAfterSubscribeEntitiesResult:
            return [
                #"{"id":\#(id),"type":"event","event":{"a":{"\#(eventEntityID())":\#(subscribeEntitiesStateBody)}}}"#
            ]
        }
    }

    private var subscribeEntitiesStateOnlyBody: String {
        guard
            let data = fixtures.stateChangedEventBody.data(using: .utf8),
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let state = object["state"] as? String,
            let encoded = try? JSONSerialization.data(withJSONObject: ["s": state], options: [.sortedKeys]),
            let text = String(data: encoded, encoding: .utf8)
        else {
            return #"{"s":"0"}"#
        }
        return text
    }

    private var subscribeEntitiesStateBody: String {
        guard
            let data = fixtures.stateChangedEventBody.data(using: .utf8),
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let state = object["state"] as? String
        else {
            return #"{"s":"0","a":{}}"#
        }
        var compact: [String: Any] = ["s": state]
        if let attributes = object["attributes"] as? [String: Any] {
            compact["a"] = attributes
        }
        if let lastChanged = object["last_changed"] as? String {
            compact["lc"] = lastChanged
        }
        if let lastUpdated = object["last_updated"] as? String {
            compact["lu"] = lastUpdated
        }
        if let context = object["context"] as? [String: Any] {
            compact["c"] = context
        }
        guard
            let encoded = try? JSONSerialization.data(withJSONObject: compact, options: [.sortedKeys]),
            let text = String(data: encoded, encoding: .utf8)
        else {
            return #"{"s":"0","a":{}}"#
        }
        return text
    }

    private func eventEntityID() -> String {
        guard
            let data = fixtures.stateChangedEventBody.data(using: .utf8),
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let entityID = object["entity_id"] as? String
        else {
            return "sensor.entity_001"
        }
        return entityID
    }

    private static func handshakeResponse(for key: String) -> Data? {
        let magic = "\(key)258EAFA5-E914-47DA-95CA-C5AB0DC85B11"
        let digest = Insecure.SHA1.hash(data: Data(magic.utf8))
        let accept = Data(digest).base64EncodedString()
        let response = """
        HTTP/1.1 101 Switching Protocols\r
        Upgrade: websocket\r
        Connection: Upgrade\r
        Sec-WebSocket-Accept: \(accept)\r
        \r

        """
        return Data(response.utf8)
    }

    private func httpResponse(status: Int, reason: String, body: String) -> Data {
        let bytes = Data(body.utf8)
        let header = """
        HTTP/1.1 \(status) \(reason)\r
        Content-Type: application/json\r
        Content-Length: \(bytes.count)\r
        Connection: close\r
        \r

        """
        var data = Data(header.utf8)
        data.append(bytes)
        return data
    }

    private func restResponse(for request: HTTPRequest) -> Data {
        guard let effectivePath = effectivePath(for: request.path) else {
            return httpResponse(status: 404, reason: "Not Found", body: #"{"message":"Not found"}"#)
        }

        guard request.headers["authorization"] == "Bearer \(fixtures.bearerToken)" else {
            return httpResponse(status: 401, reason: "Unauthorized", body: #"{"message":"Unauthorized"}"#)
        }

        guard request.method == "GET" else {
            return httpResponse(status: 405, reason: "Method Not Allowed", body: #"{"message":"Method not allowed"}"#)
        }

        switch effectivePath {
        case let path where path.hasPrefix("/api/history/period/"):
            return httpResponse(status: 200, reason: "OK", body: fixtures.historyBody)
        case "/api/":
            return httpResponse(status: 200, reason: "OK", body: fixtures.apiBody)
        case "/api/states":
            return httpResponse(status: 200, reason: "OK", body: fixtures.statesBody)
        default:
            return httpResponse(status: 404, reason: "Not Found", body: #"{"message":"Not found"}"#)
        }
    }

    private static func makeLoopbackListener(maxAttempts: Int = 16) throws -> (port: UInt16, listener: NWListener) {
        for _ in 0..<maxAttempts {
            let port = try reserveLoopbackPort()
            do {
                return try (port, NWListener(using: .tcp, on: NWEndpoint.Port(rawValue: port)!))
            } catch {
                continue
            }
        }
        throw FakeHAError.portReservationFailed
    }

    private static func reserveLoopbackPort() throws -> UInt16 {
        let descriptor = socket(AF_INET, SOCK_STREAM, 0)
        guard descriptor >= 0 else {
            throw FakeHAError.portReservationFailed
        }
        defer {
            close(descriptor)
        }

        var address = sockaddr_in(
            sin_len: UInt8(MemoryLayout<sockaddr_in>.size),
            sin_family: sa_family_t(AF_INET),
            sin_port: 0,
            sin_addr: in_addr(s_addr: INADDR_LOOPBACK.bigEndian),
            sin_zero: (0, 0, 0, 0, 0, 0, 0, 0)
        )

        let bindResult = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPointer in
                bind(descriptor, sockaddrPointer, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bindResult == 0 else {
            throw FakeHAError.portReservationFailed
        }

        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        let nameResult = withUnsafeMutablePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPointer in
                getsockname(descriptor, sockaddrPointer, &length)
            }
        }
        guard nameResult == 0 else {
            throw FakeHAError.portReservationFailed
        }

        return UInt16(bigEndian: address.sin_port)
    }

    private static func normalizedPathPrefix(_ pathPrefix: String) -> String {
        let trimmed = pathPrefix.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return trimmed.isEmpty ? "" : "/\(trimmed)"
    }
}

public struct FakeHAWebSocketAuth: Equatable, Sendable {
    public let bearerToken: String

    public init(bearerToken: String = "fake-token") {
        self.bearerToken = bearerToken
    }

    public var authRequiredMessage: String {
        #"{"type":"auth_required","ha_version":"fake-ha"}"#
    }

    public func authenticate(clientMessage: String) -> String {
        guard
            let data = clientMessage.data(using: .utf8),
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            object["type"] as? String == "auth",
            object["access_token"] as? String == bearerToken
        else {
            return #"{"type":"auth_invalid","message":"Invalid access token"}"#
        }

        return #"{"type":"auth_ok","ha_version":"fake-ha"}"#
    }
}

public struct FakeHARawWebSocketProbe: Sendable {
    public init() {}

    public func authenticateWithCoalescedUpgrade(baseURL: URL, token: String = "fake-token") throws -> Data {
        try withConnectedSocket(baseURL: baseURL) { descriptor in
            var payload = handshakeRequest(baseURL: baseURL)
            payload.append(WebSocketFrame.maskedText(#"{"type":"auth","access_token":"\#(token)"}"#))
            try sendAll(payload, descriptor: descriptor)
            return try receiveUntil(
                descriptor: descriptor,
                contains: [Data(#""type":"auth_ok""#.utf8)]
            )
        }
    }

    public func authenticateThenSendCoalescedCommands(baseURL: URL, token: String = "fake-token") throws -> Data {
        try withConnectedSocket(baseURL: baseURL) { descriptor in
            try sendAll(handshakeRequest(baseURL: baseURL), descriptor: descriptor)
            _ = try receiveUntil(descriptor: descriptor, contains: [Data(#""type":"auth_required""#.utf8)])

            try sendAll(WebSocketFrame.maskedText(#"{"type":"auth","access_token":"\#(token)"}"#), descriptor: descriptor)
            _ = try receiveUntil(descriptor: descriptor, contains: [Data(#""type":"auth_ok""#.utf8)])

            var commands = WebSocketFrame.maskedText(#"{"id":1,"type":"get_states"}"#)
            commands.append(WebSocketFrame.maskedText(#"{"id":2,"type":"get_states"}"#))
            try sendAll(commands, descriptor: descriptor)

            return try receiveUntil(
                descriptor: descriptor,
                contains: [
                    Data(#""id":1"#.utf8),
                    Data(#""id":2"#.utf8)
                ]
            )
        }
    }

    private func withConnectedSocket<T>(baseURL: URL, operation: (Int32) throws -> T) throws -> T {
        guard let port = baseURL.port else {
            throw FakeHARawWebSocketProbeError.missingPort
        }

        for _ in 0..<100 {
            let descriptor = socket(AF_INET, SOCK_STREAM, 0)
            guard descriptor >= 0 else {
                throw FakeHARawWebSocketProbeError.socketFailed
            }

            var timeout = timeval(tv_sec: 2, tv_usec: 0)
            _ = withUnsafePointer(to: &timeout) { pointer in
                setsockopt(descriptor, SOL_SOCKET, SO_RCVTIMEO, pointer, socklen_t(MemoryLayout<timeval>.size))
            }

            var address = sockaddr_in(
                sin_len: UInt8(MemoryLayout<sockaddr_in>.size),
                sin_family: sa_family_t(AF_INET),
                sin_port: UInt16(port).bigEndian,
                sin_addr: in_addr(s_addr: INADDR_LOOPBACK.bigEndian),
                sin_zero: (0, 0, 0, 0, 0, 0, 0, 0)
            )

            let result = withUnsafePointer(to: &address) { pointer in
                pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPointer in
                    connect(descriptor, sockaddrPointer, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
            if result == 0 {
                defer {
                    close(descriptor)
                }
                return try operation(descriptor)
            }

            close(descriptor)
            usleep(10_000)
        }
        throw FakeHARawWebSocketProbeError.connectFailed
    }

    private func handshakeRequest(baseURL: URL) -> Data {
        let host = baseURL.host ?? "127.0.0.1"
        let port = baseURL.port.map { ":\($0)" } ?? ""
        let path = appendingWebSocketPath(to: baseURL.path)
        return Data(
            """
            GET \(path) HTTP/1.1\r
            Host: \(host)\(port)\r
            Upgrade: websocket\r
            Connection: Upgrade\r
            Sec-WebSocket-Key: ZmFrZWhhLXByb2JlLWtleQ==\r
            Sec-WebSocket-Version: 13\r
            \r

            """.utf8
        )
    }

    private func appendingWebSocketPath(to basePath: String) -> String {
        let normalizedBase = basePath == "/" ? "" : basePath.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let prefix = normalizedBase.isEmpty ? "" : "/\(normalizedBase)"
        return "\(prefix)/api/websocket"
    }

    private func sendAll(_ data: Data, descriptor: Int32) throws {
        var bytesSent = 0
        try data.withUnsafeBytes { rawBuffer in
            guard let baseAddress = rawBuffer.baseAddress else {
                return
            }
            while bytesSent < data.count {
                let sent = send(descriptor, baseAddress.advanced(by: bytesSent), data.count - bytesSent, 0)
                guard sent > 0 else {
                    throw FakeHARawWebSocketProbeError.sendFailed
                }
                bytesSent += sent
            }
        }
    }

    private func receiveUntil(descriptor: Int32, contains requiredNeedles: [Data]) throws -> Data {
        var accumulated = Data()
        var buffer = [UInt8](repeating: 0, count: 4_096)
        while true {
            let received = recv(descriptor, &buffer, buffer.count, 0)
            guard received > 0 else {
                throw FakeHARawWebSocketProbeError.receiveTimedOut(accumulated)
            }
            accumulated.append(buffer, count: received)
            if requiredNeedles.allSatisfy({ accumulated.range(of: $0) != nil }) {
                return accumulated
            }
        }
    }
}

public enum FakeHARawWebSocketProbeError: Error, Equatable, Sendable {
    case missingPort
    case socketFailed
    case connectFailed
    case sendFailed
    case receiveTimedOut(Data)
}

private struct WebSocketFrame {
    enum Opcode: UInt8 {
        case text = 0x1
        case close = 0x8
    }

    let opcode: Opcode
    let payload: Data

    static func read(from data: Data) -> WebSocketFrameRead? {
        let bytes = [UInt8](data)
        guard bytes.count >= 2 else {
            return nil
        }
        let opcode = Opcode(rawValue: bytes[0] & 0x0f)
        let isMasked = (bytes[1] & 0x80) != 0
        var length = Int(bytes[1] & 0x7f)
        var index = 2
        if length == 126 {
            guard bytes.count >= 4 else {
                return nil
            }
            length = (Int(bytes[2]) << 8) | Int(bytes[3])
            index = 4
        } else if length == 127 {
            guard bytes.count >= 10 else {
                return nil
            }
            length = bytes[2..<10].reduce(0) { ($0 << 8) | Int($1) }
            index = 10
        }

        var mask: [UInt8] = []
        if isMasked {
            guard bytes.count >= index + 4 else {
                return nil
            }
            mask = Array(bytes[index..<index + 4])
            index += 4
        }

        guard bytes.count >= index + length, let opcode else {
            return nil
        }

        var payload = Array(bytes[index..<index + length])
        if isMasked {
            for payloadIndex in payload.indices {
                payload[payloadIndex] ^= mask[payloadIndex % 4]
            }
        }
        let remainderStart = index + length
        let remainder = remainderStart < data.count ? data.suffix(from: remainderStart) : Data()
        return WebSocketFrameRead(
            frame: WebSocketFrame(opcode: opcode, payload: Data(payload)),
            remainder: Data(remainder)
        )
    }

    static func text(_ text: String) -> Data {
        let payload = [UInt8](text.utf8)
        var frame = Data([0x81])
        if payload.count < 126 {
            frame.append(UInt8(payload.count))
        } else {
            frame.append(126)
            frame.append(UInt8((payload.count >> 8) & 0xff))
            frame.append(UInt8(payload.count & 0xff))
        }
        frame.append(contentsOf: payload)
        return frame
    }

    static func maskedText(_ text: String, mask: [UInt8] = [0x11, 0x22, 0x33, 0x44]) -> Data {
        let payload = [UInt8](text.utf8)
        var frame = Data([0x81])
        if payload.count < 126 {
            frame.append(0x80 | UInt8(payload.count))
        } else {
            frame.append(0x80 | 126)
            frame.append(UInt8((payload.count >> 8) & 0xff))
            frame.append(UInt8(payload.count & 0xff))
        }
        frame.append(contentsOf: mask)
        for index in payload.indices {
            frame.append(payload[index] ^ mask[index % mask.count])
        }
        return frame
    }
}

private struct WebSocketFrameRead {
    let frame: WebSocketFrame
    let remainder: Data
}

private struct WebSocketMessageRead {
    let message: String
    let remainder: Data
}

private struct HTTPRequestRead {
    let request: HTTPRequest
    let remainder: Data
}

private struct HTTPRequest {
    let method: String
    let path: String
    let headers: [String: String]

    static func read(from data: Data) -> HTTPRequestRead? {
        let separator = Data("\r\n\r\n".utf8)
        guard let range = data.range(of: separator) else {
            return nil
        }
        let headerData = data.subdata(in: data.startIndex..<range.lowerBound)
        let remainder = data.suffix(from: range.upperBound)
        guard let text = String(data: headerData, encoding: .utf8) else {
            return nil
        }
        let lines = text.components(separatedBy: "\r\n")
        let requestLine = lines.first?.split(separator: " ") ?? []
        let method = requestLine.indices.contains(0) ? String(requestLine[0]) : ""
        let path = requestLine.indices.contains(1) ? String(requestLine[1]) : ""
        let headers = Dictionary(uniqueKeysWithValues: lines.dropFirst().compactMap { line -> (String, String)? in
            guard let separator = line.firstIndex(of: ":") else {
                return nil
            }
            let key = String(line[..<separator]).trimmingCharacters(in: .whitespaces).lowercased()
            let value = String(line[line.index(after: separator)...]).trimmingCharacters(in: .whitespaces)
            return (key, value)
        })
        return HTTPRequestRead(
            request: HTTPRequest(method: method, path: path, headers: headers),
            remainder: Data(remainder)
        )
    }
}

private struct CapturedEndpointFile: Decodable {
    let bodyText: String

    static func load(from url: URL) throws -> CapturedEndpointFile {
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(CapturedEndpointFile.self, from: data)
    }
}
