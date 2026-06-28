import Foundation
import PerchHASupport

public struct HAMirrorRequest: Equatable, Sendable {
    public let method: String
    public let url: URL
    public let headers: [String: String]

    public init(method: String, url: URL, headers: [String: String]) {
        self.method = method
        self.url = url
        self.headers = headers
    }
}

public struct HAMirrorResponse: Equatable, Sendable {
    public let statusCode: Int
    public let headers: [String: String]
    public let body: Data

    public init(statusCode: Int, headers: [String: String], body: Data) {
        self.statusCode = statusCode
        self.headers = headers
        self.body = body
    }
}

public protocol HAMirrorTransport: Sendable {
    func send(_ request: HAMirrorRequest) async throws -> HAMirrorResponse
}

public struct URLSessionHAMirrorTransport: HAMirrorTransport {
    public init() {}

    public func send(_ request: HAMirrorRequest) async throws -> HAMirrorResponse {
        var urlRequest = URLRequest(url: request.url)
        urlRequest.httpMethod = request.method
        request.headers.forEach { key, value in
            urlRequest.setValue(value, forHTTPHeaderField: key)
        }

        let (data, response) = try await URLSession.shared.data(for: urlRequest)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw HAMirrorCaptureError.nonHTTPResponse
        }

        var headers: [String: String] = [:]
        for (key, value) in httpResponse.allHeaderFields {
            guard let key = key as? String else {
                continue
            }
            headers[key] = String(describing: value)
        }

        return HAMirrorResponse(statusCode: httpResponse.statusCode, headers: headers, body: data)
    }
}

public struct HAMirrorCapturedEndpoint: Codable, Equatable, Sendable {
    public let method: String
    public let path: String
    public let statusCode: Int
    public let headers: [String: String]
    public let bodyText: String

    public init(method: String, path: String, statusCode: Int, headers: [String: String], bodyText: String) {
        self.method = method
        self.path = path
        self.statusCode = statusCode
        self.headers = headers
        self.bodyText = bodyText
    }
}

public struct HAMirrorWebSocketEvidence: Codable, Equatable, Sendable {
    public let entityRegistryDisplayList: HAMirrorWebSocketCommandEvidence
    public let subscribeEntities: HAMirrorWebSocketCommandEvidence

    public init(entityRegistryDisplayList: HAMirrorWebSocketCommandEvidence, subscribeEntities: HAMirrorWebSocketCommandEvidence) {
        self.entityRegistryDisplayList = entityRegistryDisplayList
        self.subscribeEntities = subscribeEntities
    }
}

public struct HAMirrorWebSocketCommandEvidence: Codable, Equatable, Sendable {
    public let command: String
    public let available: Bool
    public let errorCode: String?
    public let errorMessage: String?
    public let eventKeys: [String]

    public init(command: String, available: Bool, errorCode: String?, errorMessage: String?, eventKeys: [String] = []) {
        self.command = command
        self.available = available
        self.errorCode = errorCode
        self.errorMessage = errorMessage
        self.eventKeys = eventKeys
    }
}

public struct HAMirrorFixtureSet: Codable, Equatable, Sendable {
    public let api: HAMirrorCapturedEndpoint
    public let states: HAMirrorCapturedEndpoint
    public let webSocket: HAMirrorWebSocketEvidence?

    public init(api: HAMirrorCapturedEndpoint, states: HAMirrorCapturedEndpoint, webSocket: HAMirrorWebSocketEvidence? = nil) {
        self.api = api
        self.states = states
        self.webSocket = webSocket
    }
}

public enum HAMirrorFixtureOutputPolicy {
    public static func requiresIgnoredDirectoryVerification(_ directoryURL: URL) -> Bool {
        let components = URL(fileURLWithPath: directoryURL.path, isDirectory: true)
            .standardizedFileURL
            .pathComponents
            .map { $0.lowercased() }
        for (first, second) in zip(components, components.dropFirst()) where first == "fixtures" && second == "private" {
            return true
        }
        return false
    }
}

public struct HAMirrorCaptureService: Sendable {
    private let transport: any HAMirrorTransport
    private let redactor: Redactor
    private let webSocketReceiveTimeoutNanoseconds: UInt64

    public init(
        transport: any HAMirrorTransport = URLSessionHAMirrorTransport(),
        redactor: Redactor = Redactor(),
        webSocketReceiveTimeoutNanoseconds: UInt64 = 5_000_000_000
    ) {
        self.transport = transport
        self.redactor = redactor
        self.webSocketReceiveTimeoutNanoseconds = webSocketReceiveTimeoutNanoseconds
    }

    public func capture(environment: HAMirrorEnvironment, includeWebSocketEvidence: Bool = false) async throws -> HAMirrorFixtureSet {
        guard let token = environment.token, !token.isEmpty else {
            throw HAMirrorCaptureError.missingToken
        }

        let api = try await captureEndpointSelectingBaseURL(path: "/api/", environment: environment, token: token)
        let states = try await captureEndpoint(path: "/api/states", baseURL: api.baseURL, token: token)
        let webSocket = includeWebSocketEvidence
            ? try await captureOptimizedWebSocketEvidence(
                baseURL: api.baseURL,
                token: token
            )
            : nil
        return HAMirrorFixtureSet(api: api.endpoint, states: states, webSocket: webSocket)
    }

    public func captureOptimizedWebSocketEvidence(
        environment: HAMirrorEnvironment,
        captureSubscribeEventKeys: Bool = false
    ) async throws -> HAMirrorWebSocketEvidence {
        guard let token = environment.token, !token.isEmpty else {
            throw HAMirrorCaptureError.missingToken
        }

        let api = try await captureEndpointSelectingBaseURL(path: "/api/", environment: environment, token: token)
        let task = try await authenticateWebSocket(baseURL: api.baseURL, token: token)
        defer {
            task.cancel(with: .goingAway, reason: nil)
        }
        return try await captureOptimizedWebSocketEvidence(
            task: task,
            captureSubscribeEventKeys: captureSubscribeEventKeys
        )
    }

    private func captureOptimizedWebSocketEvidence(
        baseURL: URL,
        token: String,
        captureSubscribeEventKeys: Bool = false
    ) async throws -> HAMirrorWebSocketEvidence {
        let task = try await authenticateWebSocket(baseURL: baseURL, token: token)
        defer {
            task.cancel(with: .goingAway, reason: nil)
        }
        return try await captureOptimizedWebSocketEvidence(
            task: task,
            captureSubscribeEventKeys: captureSubscribeEventKeys
        )
    }

    private func captureOptimizedWebSocketEvidence(
        task: URLSessionWebSocketTask,
        captureSubscribeEventKeys: Bool
    ) async throws -> HAMirrorWebSocketEvidence {
        let entityRegistryDisplayList = try await sendEvidenceCommand(
            task: task,
            id: 1,
            command: "config/entity_registry/list_for_display",
            captureEventKeys: false
        )
        let subscribeEntities = try await sendEvidenceCommand(
            task: task,
            id: 2,
            command: "subscribe_entities",
            captureEventKeys: captureSubscribeEventKeys
        )
        return HAMirrorWebSocketEvidence(
            entityRegistryDisplayList: entityRegistryDisplayList,
            subscribeEntities: subscribeEntities
        )
    }

    private func captureEndpointSelectingBaseURL(
        path: String,
        environment: HAMirrorEnvironment,
        token: String
    ) async throws -> (baseURL: URL, endpoint: HAMirrorCapturedEndpoint) {
        do {
            let endpoint = try await captureEndpoint(path: path, baseURL: environment.primaryURL, token: token)
            return (environment.primaryURL, endpoint)
        } catch {
            guard let fallbackURL = environment.fallbackURL else {
                throw error
            }
            let primaryFailure = sanitizedFailureDescription(error)
            do {
                let endpoint = try await captureEndpoint(path: path, baseURL: fallbackURL, token: token)
                return (fallbackURL, endpoint)
            } catch {
                throw HAMirrorCaptureError.primaryAndFallbackFailed(
                    path: path,
                    primaryFailure: primaryFailure,
                    fallbackFailure: sanitizedFailureDescription(error)
                )
            }
        }
    }

    private func captureEndpoint(path: String, baseURL: URL, token: String) async throws -> HAMirrorCapturedEndpoint {
        let url = try baseURL.homeAssistantURL(path: path)
        let request = HAMirrorRequest(
            method: "GET",
            url: url,
            headers: [
                "Authorization": "Bearer \(token)",
                "Content-Type": "application/json"
            ]
        )
        let response: HAMirrorResponse
        do {
            response = try await transport.send(request)
        } catch let error as HAMirrorCaptureError {
            throw error
        } catch {
            throw HAMirrorCaptureError.transportFailure(path: path, message: sanitizedTransportMessage(error))
        }
        guard (200..<300).contains(response.statusCode) else {
            throw HAMirrorCaptureError.unexpectedStatus(path: path, statusCode: response.statusCode)
        }
        var sanitizer = HAMirrorFixtureSanitizer(redactor: redactor)
        return HAMirrorCapturedEndpoint(
            method: request.method,
            path: path,
            statusCode: response.statusCode,
            headers: redactor.redact(headers: response.headers),
            bodyText: try sanitizer.sanitize(path: path, body: response.body)
        )
    }

    private func authenticateWebSocket(baseURL: URL, token: String) async throws -> URLSessionWebSocketTask {
        let url = try baseURL.homeAssistantWebSocketURL(path: "/api/websocket")
        let task = URLSession.shared.webSocketTask(with: url)
        task.resume()

        let required: [String: Any]
        do {
            required = try await receiveWebSocketObject(task: task)
        } catch let error as HAMirrorCaptureError {
            task.cancel(with: .goingAway, reason: nil)
            throw error
        } catch {
            task.cancel(with: .goingAway, reason: nil)
            throw HAMirrorCaptureError.transportFailure(path: "/api/websocket", message: sanitizedTransportMessage(error))
        }
        guard required["type"] as? String == "auth_required" else {
            task.cancel(with: .protocolError, reason: nil)
            throw HAMirrorCaptureError.webSocketProtocol("expected auth_required")
        }

        do {
            try await sendWebSocketObject(task: task, object: ["type": "auth", "access_token": token])
        } catch let error as HAMirrorCaptureError {
            task.cancel(with: .goingAway, reason: nil)
            throw error
        } catch {
            task.cancel(with: .goingAway, reason: nil)
            throw HAMirrorCaptureError.transportFailure(path: "/api/websocket", message: sanitizedTransportMessage(error))
        }
        let response: [String: Any]
        do {
            response = try await receiveWebSocketObject(task: task)
        } catch let error as HAMirrorCaptureError {
            task.cancel(with: .goingAway, reason: nil)
            throw error
        } catch {
            task.cancel(with: .goingAway, reason: nil)
            throw HAMirrorCaptureError.transportFailure(path: "/api/websocket", message: sanitizedTransportMessage(error))
        }
        if response["type"] as? String == "auth_ok" {
            return task
        }
        task.cancel(with: .goingAway, reason: nil)
        if response["type"] as? String == "auth_invalid" {
            throw HAMirrorCaptureError.webSocketAuthentication
        }
        throw HAMirrorCaptureError.webSocketProtocol("expected auth_ok")
    }

    private func sendEvidenceCommand(
        task: URLSessionWebSocketTask,
        id: Int,
        command: String,
        captureEventKeys: Bool
    ) async throws -> HAMirrorWebSocketCommandEvidence {
        try await sendWebSocketObject(task: task, object: ["id": id, "type": command])
        let response = try await receiveWebSocketObject(task: task)
        guard response["type"] as? String == "result", response["id"] as? Int == id else {
            throw HAMirrorCaptureError.webSocketProtocol("expected result for \(command)")
        }

        if response["success"] as? Bool == true {
            let eventKeys = captureEventKeys ? try await receiveEventKeys(task: task, id: id) : []
            return HAMirrorWebSocketCommandEvidence(
                command: command,
                available: true,
                errorCode: nil,
                errorMessage: nil,
                eventKeys: eventKeys
            )
        }

        let error = response["error"] as? [String: Any]
        return HAMirrorWebSocketCommandEvidence(
            command: command,
            available: false,
            errorCode: error?["code"] as? String,
            errorMessage: (error?["message"] as? String).map { redactor.redact(message: $0) },
            eventKeys: []
        )
    }

    private func receiveEventKeys(task: URLSessionWebSocketTask, id: Int) async throws -> [String] {
        let event = try await receiveWebSocketObject(task: task)
        guard event["type"] as? String == "event", event["id"] as? Int == id else {
            return []
        }
        guard let eventBody = event["event"] as? [String: Any] else {
            return []
        }
        return eventBody.keys.sorted()
    }

    private func sendWebSocketObject(task: URLSessionWebSocketTask, object: [String: Any]) async throws {
        let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        guard let text = String(data: data, encoding: .utf8) else {
            throw HAMirrorCaptureError.webSocketProtocol("could not encode command")
        }
        try await task.send(.string(text))
    }

    private func sanitizedFailureDescription(_ error: Error) -> String {
        if let captureError = error as? HAMirrorCaptureError {
            return captureError.description
        }
        return String(describing: error)
    }

    private func sanitizedTransportMessage(_ error: Error) -> String {
        if let urlError = error as? URLError {
            return urlError.localizedDescription
        }
        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain {
            return nsError.localizedDescription
        }
        return (error as any CustomStringConvertible).description
    }

    private func receiveWebSocketObject(task: URLSessionWebSocketTask) async throws -> [String: Any] {
        let message = try await receiveWebSocketMessage(task: task)
        let data: Data
        switch message {
        case let .string(text):
            data = Data(text.utf8)
        case let .data(raw):
            data = raw
        @unknown default:
            throw HAMirrorCaptureError.webSocketProtocol("unknown WebSocket message")
        }
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw HAMirrorCaptureError.webSocketProtocol("non-object WebSocket payload")
        }
        return object
    }

    private func receiveWebSocketMessage(task: URLSessionWebSocketTask) async throws -> URLSessionWebSocketTask.Message {
        try await withThrowingTaskGroup(of: WebSocketReceiveResult.self) { group in
            let timeout = webSocketReceiveTimeoutNanoseconds
            group.addTask {
                .message(try await task.receive())
            }
            group.addTask {
                try await Task.sleep(nanoseconds: timeout)
                return .timeout
            }
            guard let result = try await group.next() else {
                group.cancelAll()
                throw HAMirrorCaptureError.webSocketProtocol("WebSocket receive ended without a result")
            }
            group.cancelAll()
            switch result {
            case let .message(message):
                return message
            case .timeout:
                task.cancel(with: .goingAway, reason: nil)
                throw HAMirrorCaptureError.webSocketTimeout
            }
        }
    }
}

private enum WebSocketReceiveResult {
    case message(URLSessionWebSocketTask.Message)
    case timeout
}

public struct HAMirrorFixtureSanitizer: Sendable {
    private let redactor: Redactor
    private var aliases: [String: String] = [:]

    public init(redactor: Redactor = Redactor()) {
        self.redactor = redactor
    }

    public mutating func sanitize(path: String, body: Data) throws -> String {
        guard let text = String(data: body, encoding: .utf8) else {
            throw HAMirrorFixtureSanitizationError.invalidUTF8(path)
        }
        return try sanitize(path: path, bodyText: text)
    }

    public mutating func sanitize(path: String, bodyText: String) throws -> String {
        guard let data = bodyText.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data)
        else {
            throw HAMirrorFixtureSanitizationError.invalidJSON(path)
        }

        let result = sanitize(value: json, key: nil, inAttributes: false, entityAlias: nil)
        if result.changed {
            let output = try JSONSerialization.data(withJSONObject: result.value, options: [.sortedKeys])
            return String(data: output, encoding: .utf8) ?? ""
        }

        return redactor.redact(message: bodyText)
    }

    private mutating func sanitize(
        value: Any,
        key: String?,
        inAttributes: Bool,
        entityAlias: String?
    ) -> (value: Any, changed: Bool) {
        let normalizedKey = key?.lowercased()

        if normalizedKey == "entity_id" {
            if let entityID = value as? String {
                let alias = alias(forEntityID: entityID)
                return (alias, alias != entityID)
            }
            if let entityIDs = value as? [String] {
                let sanitized = entityIDs.map { alias(forEntityID: $0) }
                return (sanitized, sanitized != entityIDs)
            }
        }

        if let normalizedKey, redactor.sensitiveKeys.contains(normalizedKey) {
            return (redactor.replacement, true)
        }

        if let normalizedKey, Self.privateTextKeys.contains(normalizedKey) {
            return (redactor.replacement, !isRedacted(value))
        }

        if let normalizedKey, Self.locationNumberKeys.contains(normalizedKey) {
            if let number = value as? NSNumber, number.doubleValue == 0 {
                return (value, false)
            }
            return (0, true)
        }

        if let normalizedKey, Self.timestampKeys.contains(normalizedKey) {
            let replacement = "2026-01-01T00:00:00+00:00"
            return (replacement, (value as? String) != replacement)
        }

        if inAttributes,
           let normalizedKey,
           normalizedKey != "attributes",
           !Self.safeAttributeKeys.contains(normalizedKey) {
            return (redactor.replacement, !isRedacted(value))
        }

        if let dictionary = value as? [String: Any] {
            let rawEntityID = dictionary["entity_id"] as? String
            let currentEntityAlias = rawEntityID.map { alias(forEntityID: $0) } ?? entityAlias
            var sanitized: [String: Any] = [:]
            var changed = false

            for (childKey, childValue) in dictionary {
                let childInAttributes = inAttributes || childKey.lowercased() == "attributes"
                let result = sanitize(
                    value: childValue,
                    key: childKey,
                    inAttributes: childInAttributes,
                    entityAlias: currentEntityAlias
                )
                sanitized[childKey] = result.value
                changed = changed || result.changed
            }

            return (sanitized, changed)
        }

        if let array = value as? [Any] {
            var changed = false
            let sanitized = array.map { element in
                let result = sanitize(value: element, key: key, inAttributes: inAttributes, entityAlias: entityAlias)
                changed = changed || result.changed
                return result.value
            }
            return (sanitized, changed)
        }
        return (value, false)
    }

    private mutating func alias(forEntityID entityID: String) -> String {
        let parts = entityID.split(separator: ".", maxSplits: 1).map(String.init)
        guard parts.count == 2 else {
            return redactor.replacement
        }

        let domain = parts[0]
        let objectID = parts[1]
        if objectID.hasPrefix("entity_") && objectID.dropFirst("entity_".count).allSatisfy(\.isNumber) {
            return entityID
        }

        if let alias = aliases[entityID] {
            return alias
        }

        let alias = "\(domain).entity_\(String(format: "%03d", aliases.count + 1))"
        aliases[entityID] = alias
        return alias
    }

    private func isRedacted(_ value: Any) -> Bool {
        (value as? String) == redactor.replacement
    }

    private static let privateTextKeys: Set<String> = [
        "address",
        "description",
        "device_id",
        "email",
        "friendly_name",
        "location_name",
        "phone",
        "title",
        "unique_id",
        "user_id",
        "username"
    ]

    private static let locationNumberKeys: Set<String> = [
        "gps_accuracy",
        "latitude",
        "longitude"
    ]

    private static let timestampKeys: Set<String> = [
        "last_changed",
        "last_updated",
        "last_reported"
    ]

    private static let safeAttributeKeys: Set<String> = [
        "battery_level",
        "current_position",
        "device_class",
        "icon",
        "state_class",
        "supported_features",
        "unit_of_measurement"
    ]
}

public enum HAMirrorFixtureSanitizationError: Error, Equatable, CustomStringConvertible {
    case invalidUTF8(String)
    case invalidJSON(String)

    public var description: String {
        switch self {
        case let .invalidUTF8(path):
            "fixture body for \(path) is not UTF-8"
        case let .invalidJSON(path):
            "fixture body for \(path) is not JSON"
        }
    }
}

public struct HAMirrorFixtureWriter: Sendable {
    private let encoder: JSONEncoder

    public init() {
        encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    }

    public func write(_ fixtureSet: HAMirrorFixtureSet, to directory: URL) throws -> [URL] {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        var files: [(URL, Data)] = [
            (directory.appendingPathComponent("api.json"), try encoder.encode(fixtureSet.api)),
            (directory.appendingPathComponent("states.json"), try encoder.encode(fixtureSet.states)),
            (directory.appendingPathComponent("manifest.json"), try encoder.encode(fixtureSet))
        ]
        if let webSocket = fixtureSet.webSocket {
            files.append((directory.appendingPathComponent("websocket.json"), try encoder.encode(webSocket)))
        } else {
            let staleWebSocket = directory.appendingPathComponent("websocket.json")
            if FileManager.default.fileExists(atPath: staleWebSocket.path) {
                try FileManager.default.removeItem(at: staleWebSocket)
            }
        }

        for (url, data) in files {
            try data.write(to: url, options: Data.WritingOptions.atomic)
        }

        return files.map { $0.0 }.sorted { $0.path < $1.path }
    }
}

public struct HAMirrorFixtureVerifier: Sendable {
    private let redactor: Redactor

    public init(redactor: Redactor = Redactor()) {
        self.redactor = redactor
    }

    public func verify(directory: URL) throws -> HAMirrorFixtureSet {
        let required = ["api.json", "states.json", "manifest.json"]
        let missing = required.filter { name in
            !FileManager.default.fileExists(atPath: directory.appendingPathComponent(name).path)
        }
        guard missing.isEmpty else {
            throw HAMirrorFixtureVerificationError.missingFiles(missing)
        }

        let api = try decode(HAMirrorCapturedEndpoint.self, name: "api.json", directory: directory)
        let states = try decode(HAMirrorCapturedEndpoint.self, name: "states.json", directory: directory)
        let manifest = try decode(HAMirrorFixtureSet.self, name: "manifest.json", directory: directory)
        try validateRawManifestShape(directory: directory)

        guard manifest.api == api, manifest.states == states else {
            throw HAMirrorFixtureVerificationError.manifestMismatch
        }

        try validate(endpoint: api, file: "api.json", expectedPath: "/api/")
        try validate(endpoint: states, file: "states.json", expectedPath: "/api/states")
        let webSocketURL = directory.appendingPathComponent("websocket.json")
        let hasWebSocketFile = FileManager.default.fileExists(atPath: webSocketURL.path)
        if let manifestWebSocket = manifest.webSocket {
            guard hasWebSocketFile else {
                throw HAMirrorFixtureVerificationError.missingFiles(["websocket.json"])
            }
            try validateRawWebSocketEvidenceFile(webSocketURL)
            let webSocket = try decode(HAMirrorWebSocketEvidence.self, name: "websocket.json", directory: directory)
            guard manifestWebSocket == webSocket else {
                throw HAMirrorFixtureVerificationError.manifestMismatch
            }
            try validate(webSocket: webSocket)
        } else if hasWebSocketFile {
            throw HAMirrorFixtureVerificationError.invalidWebSocketEvidence(reason: "websocket.json exists but manifest has no webSocket evidence")
        }
        return manifest
    }

    private func decode<T: Decodable>(_ type: T.Type, name: String, directory: URL) throws -> T {
        do {
            let data = try Data(contentsOf: directory.appendingPathComponent(name))
            return try JSONDecoder().decode(type, from: data)
        } catch {
            throw HAMirrorFixtureVerificationError.malformedFile(name)
        }
    }

    private func validate(endpoint: HAMirrorCapturedEndpoint, file: String, expectedPath: String) throws {
        guard endpoint.method == "GET" else {
            throw HAMirrorFixtureVerificationError.invalidEndpoint(file: file, reason: "method must be GET")
        }
        guard endpoint.path == expectedPath else {
            throw HAMirrorFixtureVerificationError.invalidEndpoint(file: file, reason: "path must be \(expectedPath)")
        }
        guard (200..<300).contains(endpoint.statusCode) else {
            throw HAMirrorFixtureVerificationError.invalidEndpoint(file: file, reason: "status must be 2xx")
        }
        guard redactor.redact(headers: endpoint.headers) == endpoint.headers else {
            throw HAMirrorFixtureVerificationError.leakedHeader(path: endpoint.path)
        }

        var sanitizer = HAMirrorFixtureSanitizer(redactor: redactor)
        let sanitized: String
        do {
            sanitized = try sanitizer.sanitize(path: endpoint.path, bodyText: endpoint.bodyText)
        } catch {
            throw HAMirrorFixtureVerificationError.invalidEndpoint(file: file, reason: "\(error)")
        }
        guard sanitized == endpoint.bodyText else {
            throw HAMirrorFixtureVerificationError.unsanitizedBody(path: endpoint.path)
        }
    }

    private func validateRawManifestShape(directory: URL) throws {
        let data: Data
        do {
            data = try Data(contentsOf: directory.appendingPathComponent("manifest.json"))
        } catch {
            throw HAMirrorFixtureVerificationError.malformedFile("manifest.json")
        }
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw HAMirrorFixtureVerificationError.malformedFile("manifest.json")
        }
        let keys = Set(object.keys)
        let allowed: Set<String> = ["api", "states", "webSocket"]
        guard keys.isSubset(of: allowed), keys.contains("api"), keys.contains("states") else {
            throw HAMirrorFixtureVerificationError.invalidWebSocketEvidence(reason: "manifest contains unexpected fields")
        }
        if let webSocket = object["webSocket"] {
            guard !(webSocket is NSNull) else {
                return
            }
            try validateRawWebSocketEvidenceObject(webSocket, source: "manifest.webSocket")
        }
    }

    private func validateRawWebSocketEvidenceFile(_ url: URL) throws {
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw HAMirrorFixtureVerificationError.malformedFile("websocket.json")
        }
        guard let object = try? JSONSerialization.jsonObject(with: data) else {
            throw HAMirrorFixtureVerificationError.malformedFile("websocket.json")
        }
        try validateRawWebSocketEvidenceObject(object, source: "websocket.json")
    }

    private func validateRawWebSocketEvidenceObject(_ object: Any, source: String) throws {
        guard let dictionary = object as? [String: Any] else {
            throw HAMirrorFixtureVerificationError.invalidWebSocketEvidence(reason: "\(source) must be an object")
        }
        let keys = Set(dictionary.keys)
        let expected: Set<String> = ["entityRegistryDisplayList", "subscribeEntities"]
        guard keys == expected else {
            throw HAMirrorFixtureVerificationError.invalidWebSocketEvidence(reason: "\(source) contains unexpected fields")
        }
        try validateRawWebSocketCommandEvidence(dictionary["entityRegistryDisplayList"], source: "\(source).entityRegistryDisplayList")
        try validateRawWebSocketCommandEvidence(dictionary["subscribeEntities"], source: "\(source).subscribeEntities")
    }

    private func validateRawWebSocketCommandEvidence(_ object: Any?, source: String) throws {
        guard let dictionary = object as? [String: Any] else {
            throw HAMirrorFixtureVerificationError.invalidWebSocketEvidence(reason: "\(source) must be an object")
        }
        let keys = Set(dictionary.keys)
        let allowed: Set<String> = ["command", "available", "errorCode", "errorMessage", "eventKeys"]
        guard keys.isSubset(of: allowed),
              keys.contains("command"),
              keys.contains("available"),
              keys.contains("eventKeys")
        else {
            throw HAMirrorFixtureVerificationError.invalidWebSocketEvidence(reason: "\(source) contains unexpected fields")
        }
        guard dictionary["command"] is String,
              dictionary["available"] is Bool,
              let eventKeys = dictionary["eventKeys"] as? [Any],
              eventKeys.allSatisfy({ $0 is String })
        else {
            throw HAMirrorFixtureVerificationError.invalidWebSocketEvidence(reason: "\(source) has invalid field types")
        }
        for optionalKey in ["errorCode", "errorMessage"] {
            guard let value = dictionary[optionalKey], !(value is NSNull) else {
                continue
            }
            guard value is String else {
                throw HAMirrorFixtureVerificationError.invalidWebSocketEvidence(reason: "\(source).\(optionalKey) must be a string or null")
            }
        }
    }

    private func validate(webSocket: HAMirrorWebSocketEvidence) throws {
        let commands = [
            webSocket.entityRegistryDisplayList,
            webSocket.subscribeEntities
        ]
        for command in commands {
            guard command.command == "config/entity_registry/list_for_display" || command.command == "subscribe_entities" else {
                throw HAMirrorFixtureVerificationError.invalidWebSocketEvidence(reason: "unexpected command \(command.command)")
            }
            if let errorMessage = command.errorMessage,
               redactor.redact(message: errorMessage) != errorMessage {
                throw HAMirrorFixtureVerificationError.invalidWebSocketEvidence(reason: "unredacted error message for \(command.command)")
            }
        }
    }
}

public enum HAMirrorFixtureVerificationError: Error, Equatable, CustomStringConvertible {
    case missingFiles([String])
    case malformedFile(String)
    case manifestMismatch
    case invalidEndpoint(file: String, reason: String)
    case invalidWebSocketEvidence(reason: String)
    case leakedHeader(path: String)
    case unsanitizedBody(path: String)

    public var description: String {
        switch self {
        case let .missingFiles(files):
            "missing fixture files: \(files.joined(separator: ", "))"
        case let .malformedFile(file):
            "malformed fixture file: \(file)"
        case .manifestMismatch:
            "manifest does not match endpoint fixture files"
        case let .invalidEndpoint(file, reason):
            "invalid fixture endpoint in \(file): \(reason)"
        case let .invalidWebSocketEvidence(reason):
            "invalid WebSocket fixture evidence: \(reason)"
        case let .leakedHeader(path):
            "fixture headers for \(path) contain unredacted secrets"
        case let .unsanitizedBody(path):
            "fixture body for \(path) is not sanitized"
        }
    }
}

public enum HAMirrorCaptureError: Error, Equatable, CustomStringConvertible {
    case missingToken
    case nonHTTPResponse
    case invalidPath(String)
    case transportFailure(path: String, message: String)
    case unexpectedStatus(path: String, statusCode: Int)
    case primaryAndFallbackFailed(path: String, primaryFailure: String, fallbackFailure: String)
    case webSocketAuthentication
    case webSocketProtocol(String)
    case webSocketTimeout

    public var description: String {
        switch self {
        case .missingToken:
            "missing token in environment file"
        case .nonHTTPResponse:
            "Home Assistant returned a non-HTTP response"
        case let .invalidPath(path):
            "invalid Home Assistant path: \(path)"
        case let .transportFailure(path, message):
            "Home Assistant request for \(path) failed: \(message)"
        case let .unexpectedStatus(path, statusCode):
            "Home Assistant returned HTTP \(statusCode) for \(path)"
        case let .primaryAndFallbackFailed(path, primaryFailure, fallbackFailure):
            "Home Assistant request for \(path) failed on both primary and fallback: primary=\(primaryFailure); fallback=\(fallbackFailure)"
        case .webSocketAuthentication:
            "Home Assistant rejected the WebSocket token"
        case let .webSocketProtocol(message):
            "Home Assistant WebSocket protocol error: \(message)"
        case .webSocketTimeout:
            "Home Assistant WebSocket did not respond before the timeout"
        }
    }
}

private extension URL {
    func homeAssistantURL(path: String) throws -> URL {
        guard path.hasPrefix("/") else {
            throw HAMirrorCaptureError.invalidPath(path)
        }
        var components = URLComponents(url: self, resolvingAgainstBaseURL: false)
        components?.path = appendingHomeAssistantPath(path)
        guard let url = components?.url else {
            throw HAMirrorCaptureError.invalidPath(path)
        }
        return url
    }

    func homeAssistantWebSocketURL(path: String) throws -> URL {
        guard path.hasPrefix("/") else {
            throw HAMirrorCaptureError.invalidPath(path)
        }
        var components = URLComponents(url: self, resolvingAgainstBaseURL: false)
        switch components?.scheme?.lowercased() {
        case "http":
            components?.scheme = "ws"
        case "https":
            components?.scheme = "wss"
        default:
            throw HAMirrorCaptureError.invalidPath(path)
        }
        components?.path = appendingHomeAssistantPath(path)
        guard let url = components?.url else {
            throw HAMirrorCaptureError.invalidPath(path)
        }
        return url
    }

    private func appendingHomeAssistantPath(_ path: String) -> String {
        let basePath = self.path
        let normalizedBase = basePath == "/" ? "" : basePath.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let prefix = normalizedBase.isEmpty ? "" : "/\(normalizedBase)"
        return "\(prefix)\(path)"
    }
}
