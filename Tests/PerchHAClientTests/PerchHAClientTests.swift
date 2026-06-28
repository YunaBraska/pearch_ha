#if canImport(XCTest)
import Foundation
import FakeHA
import XCTest
import PerchHACore
import PerchHAClient

final class PerchHAClientTests: XCTestCase {
    func testConnectionInputKeepsURLs() throws {
        let primary = try XCTUnwrap(URL(string: "http://homeassistant.local:8123"))
        let fallback = try XCTUnwrap(URL(string: "https://example.ui.nabu.casa"))
        let input = HAConnectionInput(
            endpoint: HAEndpoint(primaryURL: primary, fallbackURL: fallback),
            token: "redacted"
        )

        XCTAssertEqual(input.endpoint.primaryURL, primary)
        XCTAssertEqual(input.endpoint.fallbackURL, fallback)
        XCTAssertEqual(input.serverTrustPolicy, .default)
    }

    func testServerTrustPolicyIsHostScopedAndSecureSchemeOnly() throws {
        let policy = HAServerTrustPolicy(
            allowedSelfSignedCertificateHosts: [" HOMEASSISTANT.local ", "fallback.example", ""]
        )

        XCTAssertTrue(
            policy.allowsSelfSignedCertificate(
                for: try XCTUnwrap(URL(string: "https://homeassistant.local:8123/api/"))
            )
        )
        XCTAssertTrue(
            policy.allowsSelfSignedCertificate(
                for: try XCTUnwrap(URL(string: "wss://fallback.example/api/websocket"))
            )
        )
        XCTAssertFalse(
            policy.allowsSelfSignedCertificate(
                for: try XCTUnwrap(URL(string: "http://homeassistant.local:8123/api/"))
            )
        )
        XCTAssertFalse(
            policy.allowsSelfSignedCertificate(
                for: try XCTUnwrap(URL(string: "https://other.local:8123/api/"))
            )
        )
    }

    func testPlannedClientIdentifiesModule() {
        XCTAssertEqual(PlannedHAClient().describe().name, "PerchHAClient")
    }

    func testOAuthAuthorizationURLUsesOfficialAuthorizeEndpointAndEncodesNativeRedirect() throws {
        let client = HomeAssistantClient()
        let request = HAOAuthAuthorizationRequest(
            baseURL: try XCTUnwrap(URL(string: "http://homeassistant.local:8123")),
            clientID: "https://perchha.dev/app",
            redirectURI: "perchha://auth",
            state: "state value"
        )

        let result = client.authorizationURL(for: request)

        XCTAssertEqual(
            result,
            .success(try XCTUnwrap(URL(string: "http://homeassistant.local:8123/auth/authorize?client_id=https%3A%2F%2Fperchha.dev%2Fapp&redirect_uri=perchha%3A%2F%2Fauth&state=state+value")))
        )
    }

    func testOAuthAuthorizationURLAllowsOmittedOptionalState() throws {
        let client = HomeAssistantClient()
        let request = HAOAuthAuthorizationRequest(
            baseURL: try XCTUnwrap(URL(string: "http://homeassistant.local:8123")),
            clientID: "https://perchha.dev/app",
            redirectURI: "perchha://auth"
        )

        let result = client.authorizationURL(for: request)

        XCTAssertEqual(
            result,
            .success(try XCTUnwrap(URL(string: "http://homeassistant.local:8123/auth/authorize?client_id=https%3A%2F%2Fperchha.dev%2Fapp&redirect_uri=perchha%3A%2F%2Fauth")))
        )
    }

    func testOAuthAuthorizationURLRejectsInvalidInputBeforeOpeningBrowser() throws {
        let client = HomeAssistantClient()
        let invalidBaseURLRequest = HAOAuthAuthorizationRequest(
            baseURL: try XCTUnwrap(URL(string: "file:///tmp/homeassistant")),
            clientID: "https://perchha.dev/app",
            redirectURI: "perchha://auth",
            state: "state"
        )
        let invalidRedirectURIRequest = HAOAuthAuthorizationRequest(
            baseURL: try XCTUnwrap(URL(string: "https://homeassistant.local")),
            clientID: "https://perchha.dev/app",
            redirectURI: "callback",
            state: "state"
        )

        XCTAssertEqual(client.authorizationURL(for: invalidBaseURLRequest), .failure(.invalidURL(path: "/auth/authorize")))
        XCTAssertEqual(
            client.authorizationURL(for: invalidRedirectURIRequest),
            .failure(.invalidPayload(path: "/auth/authorize", reason: "redirect_uri is invalid"))
        )
    }

    func testOAuthClientWebsiteAcceptsDeclaredNativeRedirectInFirstTenKB() async throws {
        let transport = RecordingHARESTTransport(
            responses: [
                .success(HARESTResponse(
                    statusCode: 200,
                    headers: ["Content-Type": "text/html"],
                    body: Data(#"<html><head><link rel="redirect_uri" href="perchha://auth"></head></html>"#.utf8)
                ))
            ]
        )
        let client = HomeAssistantClient(transport: transport)

        let result = await client.verifyOAuthClientWebsite(
            clientID: "https://perchha.dev/app",
            redirectURI: "perchha://auth"
        )

        XCTAssertEqual(
            result,
            .success(
                HAOAuthClientWebsiteCheck(
                    clientID: "https://perchha.dev/app",
                    redirectURI: "perchha://auth",
                    websiteFetched: true,
                    redirectURIDeclared: true
                )
            )
        )
        let request = try await XCTUnwrap(transport.requests.first)
        XCTAssertEqual(request.method, "GET")
        XCTAssertEqual(request.url.absoluteString, "https://perchha.dev/app")
        XCTAssertEqual(request.headers["Accept"], "text/html,application/xhtml+xml")
        XCTAssertNil(request.body)
    }

    func testOAuthClientWebsiteAcceptsRedirectDeclarationWithAttributesInEitherOrder() async {
        let transport = RecordingHARESTTransport(
            responses: [
                .success(HARESTResponse(
                    statusCode: 200,
                    headers: [:],
                    body: Data(#"<link href='perchha://auth' rel='author redirect_uri'>"#.utf8)
                ))
            ]
        )

        let result = await HomeAssistantClient(transport: transport).verifyOAuthClientWebsite(
            clientID: "https://perchha.dev/app",
            redirectURI: "perchha://auth"
        )

        XCTAssertEqual(
            result,
            .success(
                HAOAuthClientWebsiteCheck(
                    clientID: "https://perchha.dev/app",
                    redirectURI: "perchha://auth",
                    websiteFetched: true,
                    redirectURIDeclared: true
                )
            )
        )
    }

    func testOAuthClientWebsiteRejectsMissingNativeRedirectDeclaration() async {
        let transport = RecordingHARESTTransport(
            responses: [
                .success(HARESTResponse(
                    statusCode: 200,
                    headers: ["Content-Type": "text/html"],
                    body: Data(#"<html><head></head><body>No redirect here.</body></html>"#.utf8)
                ))
            ]
        )
        let client = HomeAssistantClient(transport: transport)

        let result = await client.verifyOAuthClientWebsite(
            clientID: "https://perchha.dev/app",
            redirectURI: "perchha://auth"
        )

        XCTAssertEqual(
            result,
            .failure(.invalidPayload(path: "https://perchha.dev/app", reason: "redirect_uri link is required in first 10000 bytes"))
        )
    }

    func testOAuthClientWebsiteRejectsNativeRedirectDeclarationAfterFirstTenKB() async {
        let padding = String(repeating: "x", count: 10_001)
        let transport = RecordingHARESTTransport(
            responses: [
                .success(HARESTResponse(
                    statusCode: 200,
                    headers: ["Content-Type": "text/html"],
                    body: Data("\(padding)<link rel=\"redirect_uri\" href=\"perchha://auth\">".utf8)
                ))
            ]
        )
        let client = HomeAssistantClient(transport: transport)

        let result = await client.verifyOAuthClientWebsite(
            clientID: "https://perchha.dev/app",
            redirectURI: "perchha://auth"
        )

        XCTAssertEqual(
            result,
            .failure(.invalidPayload(path: "https://perchha.dev/app", reason: "redirect_uri link is required in first 10000 bytes"))
        )
    }

    func testOAuthClientWebsiteSkipsNetworkForSameOriginRedirect() async {
        let transport = RecordingHARESTTransport(responses: [])
        let client = HomeAssistantClient(transport: transport)

        let result = await client.verifyOAuthClientWebsite(
            clientID: "https://perchha.dev/app",
            redirectURI: "https://perchha.dev/oauth/callback"
        )

        XCTAssertEqual(
            result,
            .success(
                HAOAuthClientWebsiteCheck(
                    clientID: "https://perchha.dev/app",
                    redirectURI: "https://perchha.dev/oauth/callback",
                    websiteFetched: false,
                    redirectURIDeclared: false
                )
            )
        )
        XCTAssertEqual(await transport.requests, [])
    }

    func testOAuthClientWebsiteSkipsNetworkForExplicitDefaultHTTPSPort() async {
        let transport = RecordingHARESTTransport(responses: [])
        let client = HomeAssistantClient(transport: transport)

        let result = await client.verifyOAuthClientWebsite(
            clientID: "https://perchha.dev/app",
            redirectURI: "https://perchha.dev:443/auth"
        )

        XCTAssertEqual(
            result,
            .success(
                HAOAuthClientWebsiteCheck(
                    clientID: "https://perchha.dev/app",
                    redirectURI: "https://perchha.dev:443/auth",
                    websiteFetched: false,
                    redirectURIDeclared: false
                )
            )
        )
        XCTAssertEqual(await transport.requests, [])
    }

    func testOAuthClientWebsiteSkipsNetworkForExplicitDefaultHTTPPort() async {
        let transport = RecordingHARESTTransport(responses: [])
        let client = HomeAssistantClient(transport: transport)

        let result = await client.verifyOAuthClientWebsite(
            clientID: "http://perchha.dev/app",
            redirectURI: "http://perchha.dev:80/auth"
        )

        XCTAssertEqual(
            result,
            .success(
                HAOAuthClientWebsiteCheck(
                    clientID: "http://perchha.dev/app",
                    redirectURI: "http://perchha.dev:80/auth",
                    websiteFetched: false,
                    redirectURIDeclared: false
                )
            )
        )
        XCTAssertEqual(await transport.requests, [])
    }

    func testOAuthClientWebsiteRejectsInvalidInputsBeforeNetwork() async {
        let transport = RecordingHARESTTransport(responses: [])
        let client = HomeAssistantClient(transport: transport)

        let invalidClient = await client.verifyOAuthClientWebsite(
            clientID: "perchha://app",
            redirectURI: "perchha://auth"
        )
        let invalidRedirect = await client.verifyOAuthClientWebsite(
            clientID: "https://perchha.dev/app",
            redirectURI: "auth"
        )

        XCTAssertEqual(
            invalidClient,
            .failure(.invalidPayload(path: "/auth/client_id", reason: "client_id must be an application website URL"))
        )
        XCTAssertEqual(
            invalidRedirect,
            .failure(.invalidPayload(path: "/auth/client_id", reason: "redirect_uri is invalid"))
        )
        XCTAssertEqual(await transport.requests, [])
    }

    func testOAuthCodeExchangePostsFormAndRequiresRefreshToken() async throws {
        let transport = RecordingHARESTTransport(
            responses: [
                .success(HARESTResponse(
                    statusCode: 200,
                    headers: [:],
                    body: Data(#"{"access_token":"access-token","refresh_token":"refresh-token","expires_in":1800,"token_type":"Bearer"}"#.utf8)
                ))
            ]
        )
        let client = HomeAssistantClient(transport: transport)
        let baseURL = try XCTUnwrap(URL(string: "https://homeassistant.local"))

        let result = await client.exchangeAuthorizationCode(
            baseURL: baseURL,
            code: "code value",
            clientID: "https://perchha.dev/app"
        )

        XCTAssertEqual(
            result,
            .success(HAOAuthToken(accessToken: "access-token", refreshToken: "refresh-token", expiresInSeconds: 1800, tokenType: "Bearer"))
        )
        let request = try await XCTUnwrap(transport.requests.first)
        XCTAssertEqual(request.method, "POST")
        XCTAssertEqual(request.url.path, "/auth/token")
        XCTAssertEqual(request.headers["Accept"], "application/json")
        XCTAssertEqual(request.headers["Content-Type"], "application/x-www-form-urlencoded")
        XCTAssertEqual(
            String(data: try XCTUnwrap(request.body), encoding: .utf8),
            "grant_type=authorization_code&code=code+value&client_id=https%3A%2F%2Fperchha.dev%2Fapp"
        )
        XCTAssertEqual(request.serverTrustPolicy, .default)
    }

    func testOAuthTokenRequestsCarrySelfSignedCertificatePolicy() async throws {
        let transport = RecordingHARESTTransport(
            responses: [
                .success(HARESTResponse(
                    statusCode: 200,
                    headers: [:],
                    body: Data(#"{"access_token":"access-token","refresh_token":"refresh-token","expires_in":1800,"token_type":"Bearer"}"#.utf8)
                )),
                .success(HARESTResponse(
                    statusCode: 200,
                    headers: [:],
                    body: Data(#"{"access_token":"rotated-access","expires_in":1800,"token_type":"Bearer"}"#.utf8)
                ))
            ]
        )
        let policy = HAServerTrustPolicy(allowedSelfSignedCertificateHosts: ["homeassistant.local"])
        let client = HomeAssistantClient(transport: transport)
        let baseURL = try XCTUnwrap(URL(string: "https://homeassistant.local"))

        let exchange = await client.exchangeAuthorizationCode(
            baseURL: baseURL,
            code: "code",
            clientID: "https://perchha.dev/app",
            serverTrustPolicy: policy
        )
        let refresh = await client.refreshAccessToken(
            baseURL: baseURL,
            refreshToken: "refresh-token",
            clientID: "https://perchha.dev/app",
            serverTrustPolicy: policy
        )

        XCTAssertEqual(
            exchange,
            .success(HAOAuthToken(accessToken: "access-token", refreshToken: "refresh-token", expiresInSeconds: 1800, tokenType: "Bearer"))
        )
        XCTAssertEqual(
            refresh,
            .success(HAOAuthToken(accessToken: "rotated-access", refreshToken: nil, expiresInSeconds: 1800, tokenType: "Bearer"))
        )
        let requests = await transport.requests
        XCTAssertEqual(requests.map(\.serverTrustPolicy), [policy, policy])
    }

    func testOAuthCodeExchangeRejectsTokenPayloadWithoutRefreshToken() async throws {
        let transport = RecordingHARESTTransport(
            responses: [
                .success(HARESTResponse(
                    statusCode: 200,
                    headers: [:],
                    body: Data(#"{"access_token":"access-token","expires_in":1800,"token_type":"Bearer"}"#.utf8)
                ))
            ]
        )
        let client = HomeAssistantClient(transport: transport)

        let result = await client.exchangeAuthorizationCode(
            baseURL: try XCTUnwrap(URL(string: "https://homeassistant.local")),
            code: "code",
            clientID: "https://perchha.dev/app"
        )

        XCTAssertEqual(result, .failure(.invalidPayload(path: "/auth/token", reason: "refresh_token is required")))
    }

    func testOAuthCodeExchangeRejectsWhitespaceRefreshToken() async throws {
        let transport = RecordingHARESTTransport(
            responses: [
                .success(HARESTResponse(
                    statusCode: 200,
                    headers: [:],
                    body: Data(#"{"access_token":"access-token","refresh_token":"   ","expires_in":1800,"token_type":"Bearer"}"#.utf8)
                ))
            ]
        )
        let client = HomeAssistantClient(transport: transport)

        let result = await client.exchangeAuthorizationCode(
            baseURL: try XCTUnwrap(URL(string: "https://homeassistant.local")),
            code: "code",
            clientID: "https://perchha.dev/app"
        )

        XCTAssertEqual(result, .failure(.invalidPayload(path: "/auth/token", reason: "refresh_token is required")))
    }

    func testOAuthCodeExchangeRejectsNonBearerTokenType() async throws {
        let transport = RecordingHARESTTransport(
            responses: [
                .success(HARESTResponse(
                    statusCode: 200,
                    headers: [:],
                    body: Data(#"{"access_token":"access-token","refresh_token":"refresh-token","expires_in":1800,"token_type":"Basic"}"#.utf8)
                ))
            ]
        )
        let client = HomeAssistantClient(transport: transport)

        let result = await client.exchangeAuthorizationCode(
            baseURL: try XCTUnwrap(URL(string: "https://homeassistant.local")),
            code: "code",
            clientID: "https://perchha.dev/app"
        )

        XCTAssertEqual(result, .failure(.invalidPayload(path: "/auth/token", reason: "token_type must be Bearer")))
    }

    func testOAuthCodeExchangeRejectsEmptyAccessToken() async throws {
        let transport = RecordingHARESTTransport(
            responses: [
                .success(HARESTResponse(
                    statusCode: 200,
                    headers: [:],
                    body: Data(#"{"access_token":"","refresh_token":"refresh-token","expires_in":1800,"token_type":"Bearer"}"#.utf8)
                ))
            ]
        )
        let client = HomeAssistantClient(transport: transport)

        let result = await client.exchangeAuthorizationCode(
            baseURL: try XCTUnwrap(URL(string: "https://homeassistant.local")),
            code: "code",
            clientID: "https://perchha.dev/app"
        )

        XCTAssertEqual(result, .failure(.invalidPayload(path: "/auth/token", reason: "access_token is required")))
    }

    func testOAuthCodeExchangeRejectsWhitespaceAccessToken() async throws {
        let transport = RecordingHARESTTransport(
            responses: [
                .success(HARESTResponse(
                    statusCode: 200,
                    headers: [:],
                    body: Data(#"{"access_token":"   ","refresh_token":"refresh-token","expires_in":1800,"token_type":"Bearer"}"#.utf8)
                ))
            ]
        )
        let client = HomeAssistantClient(transport: transport)

        let result = await client.exchangeAuthorizationCode(
            baseURL: try XCTUnwrap(URL(string: "https://homeassistant.local")),
            code: "code",
            clientID: "https://perchha.dev/app"
        )

        XCTAssertEqual(result, .failure(.invalidPayload(path: "/auth/token", reason: "access_token is required")))
    }

    func testOAuthCodeExchangeRejectsNonPositiveExpiry() async throws {
        let transport = RecordingHARESTTransport(
            responses: [
                .success(HARESTResponse(
                    statusCode: 200,
                    headers: [:],
                    body: Data(#"{"access_token":"access-token","refresh_token":"refresh-token","expires_in":0,"token_type":"Bearer"}"#.utf8)
                ))
            ]
        )
        let client = HomeAssistantClient(transport: transport)

        let result = await client.exchangeAuthorizationCode(
            baseURL: try XCTUnwrap(URL(string: "https://homeassistant.local")),
            code: "code",
            clientID: "https://perchha.dev/app"
        )

        XCTAssertEqual(result, .failure(.invalidPayload(path: "/auth/token", reason: "expires_in must be positive")))
    }

    func testOAuthRefreshPostsRefreshGrantAndKeepsStoredRefreshTokenExternal() async throws {
        let transport = RecordingHARESTTransport(
            responses: [
                .success(HARESTResponse(
                    statusCode: 200,
                    headers: [:],
                    body: Data(#"{"access_token":"rotated-access-token","expires_in":1800,"token_type":"Bearer"}"#.utf8)
                ))
            ]
        )
        let client = HomeAssistantClient(transport: transport)

        let result = await client.refreshAccessToken(
            baseURL: try XCTUnwrap(URL(string: "https://homeassistant.local")),
            refreshToken: "refresh token",
            clientID: "https://perchha.dev/app"
        )

        XCTAssertEqual(
            result,
            .success(HAOAuthToken(accessToken: "rotated-access-token", refreshToken: nil, expiresInSeconds: 1800, tokenType: "Bearer"))
        )
        let request = try await XCTUnwrap(transport.requests.first)
        XCTAssertEqual(
            String(data: try XCTUnwrap(request.body), encoding: .utf8),
            "grant_type=refresh_token&refresh_token=refresh+token&client_id=https%3A%2F%2Fperchha.dev%2Fapp"
        )
    }

    func testOAuthRefreshInvalidRequestIsNotAuthenticationAndTransportErrorsAreRedacted() async throws {
        let invalidRequestTransport = RecordingHARESTTransport(
            responses: [
                .success(HARESTResponse(statusCode: 400, headers: [:], body: Data(#"{"error":"invalid_grant"}"#.utf8)))
            ]
        )
        let leakingTransport = RecordingHARESTTransport(
            responses: [
                .transportError("refresh_token=refresh-secret code=secret-code")
            ]
        )
        let baseURL = try XCTUnwrap(URL(string: "https://homeassistant.local"))

        XCTAssertEqual(
            await HomeAssistantClient(transport: invalidRequestTransport).refreshAccessToken(
                baseURL: baseURL,
                refreshToken: "refresh-secret",
                clientID: "https://perchha.dev/app"
            ),
            .failure(.invalidPayload(path: "/auth/token", reason: "HTTP 400 invalid request"))
        )
        XCTAssertEqual(
            await HomeAssistantClient(transport: leakingTransport).refreshAccessToken(
                baseURL: baseURL,
                refreshToken: "refresh-secret",
                clientID: "https://perchha.dev/app"
            ),
            .failure(.transport("refresh_token=<redacted> code=<redacted>"))
        )
    }

    func testOAuthTokenEndpointInactiveUserMapsToAuthentication() async throws {
        let transport = RecordingHARESTTransport(
            responses: [
                .success(HARESTResponse(statusCode: 403, headers: [:], body: Data()))
            ]
        )
        let client = HomeAssistantClient(transport: transport)

        let result = await client.refreshAccessToken(
            baseURL: try XCTUnwrap(URL(string: "https://homeassistant.local")),
            refreshToken: "refresh-secret",
            clientID: "https://perchha.dev/app"
        )

        XCTAssertEqual(result, .failure(.authentication))
    }

    func testOAuthRevokePostsRevokeActionAndAcceptsEmptyBody() async throws {
        let transport = RecordingHARESTTransport(
            responses: [
                .success(HARESTResponse(statusCode: 200, headers: [:], body: Data()))
            ]
        )
        let client = HomeAssistantClient(transport: transport)

        let result = await client.revokeRefreshToken(
            baseURL: try XCTUnwrap(URL(string: "https://homeassistant.local")),
            refreshToken: "refresh-token"
        )

        XCTAssertEqual(result, .success(.revoked))
        let request = try await XCTUnwrap(transport.requests.first)
        XCTAssertEqual(request.url.path, "/auth/token")
        XCTAssertEqual(String(data: try XCTUnwrap(request.body), encoding: .utf8), "token=refresh-token&action=revoke")
    }

    func testRESTSmokeUsesTrailingSlashAndBearerToken() async throws {
        let transport = RecordingHARESTTransport(
            responses: [
                .success(HARESTResponse(statusCode: 200, headers: [:], body: Data(#"{"message":"API running."}"#.utf8)))
            ]
        )
        let client = HomeAssistantClient(transport: transport)
        let input = try connectionInput()

        let result = await client.checkRESTConnection(input)

        XCTAssertEqual(result, .success(HARESTCheck(message: "API running.")))
        let requests = await transport.requests
        XCTAssertEqual(requests.map { $0.url.path }, ["/api/"])
        XCTAssertEqual(requests.first?.headers["Authorization"], "Bearer secret-token")
        XCTAssertEqual(requests.first?.headers["Accept"], "application/json")
    }

    func testRESTSmokePreservesBasePathPrefix() async throws {
        let transport = RecordingHARESTTransport(
            responses: [
                .success(HARESTResponse(statusCode: 200, headers: [:], body: Data(#"{"message":"API running."}"#.utf8)))
            ]
        )
        let client = HomeAssistantClient(transport: transport)
        let input = HAConnectionInput(
            endpoint: HAEndpoint(
                primaryURL: try XCTUnwrap(URL(string: "https://example.ui.nabu.casa/ha")),
                fallbackURL: nil
            ),
            token: "secret-token"
        )

        let result = await client.checkRESTConnection(input)

        XCTAssertEqual(result, .success(HARESTCheck(message: "API running.")))
        let requests = await transport.requests
        XCTAssertEqual(requests.map { $0.url.path }, ["/ha/api/"])
    }

    func testRESTRequestCarriesSelfSignedCertificatePolicy() async throws {
        let transport = RecordingHARESTTransport(
            responses: [
                .success(HARESTResponse(statusCode: 200, headers: [:], body: Data(#"{"message":"API running."}"#.utf8)))
            ]
        )
        let policy = HAServerTrustPolicy(allowedSelfSignedCertificateHosts: ["homeassistant.local"])
        let client = HomeAssistantClient(transport: transport)
        let input = HAConnectionInput(
            endpoint: HAEndpoint(
                primaryURL: try XCTUnwrap(URL(string: "https://homeassistant.local:8123")),
                fallbackURL: nil
            ),
            token: "secret-token",
            serverTrustPolicy: policy
        )

        let result = await client.checkRESTConnection(input)

        XCTAssertEqual(result, .success(HARESTCheck(message: "API running.")))
        let requests = await transport.requests
        XCTAssertEqual(requests.first?.serverTrustPolicy, policy)
    }

    func testStatesMapsFriendlyNameUnitAndMissingAttributes() async throws {
        let body = """
        [
          {
            "entity_id": "sensor.office_temperature",
            "state": "21.4",
            "attributes": {
              "friendly_name": "Office temperature",
              "unit_of_measurement": "°C"
            }
          },
          {
            "entity_id": "binary_sensor.window",
            "state": "off",
            "attributes": {}
          },
          {
            "entity_id": "cover.office_blinds",
            "state": "open",
            "attributes": {
              "friendly_name": "Office blinds",
              "current_position": "42"
            }
          }
        ]
        """
        let transport = RecordingHARESTTransport(
            responses: [
                .success(HARESTResponse(statusCode: 200, headers: [:], body: Data(body.utf8)))
            ]
        )
        let client = HomeAssistantClient(transport: transport)

        let result = await client.states(try connectionInput())

        XCTAssertEqual(
            result,
            .success([
                EntityState(id: "sensor.office_temperature", name: "Office temperature", state: "21.4", unit: "°C"),
                EntityState(id: "binary_sensor.window", name: "binary_sensor.window", state: "off", unit: nil),
                EntityState(id: "cover.office_blinds", name: "Office blinds", state: "open", unit: nil, currentPosition: 42)
            ])
        )
        let requests = await transport.requests
        XCTAssertEqual(requests.map { $0.url.path }, ["/api/states"])
    }

    func testAuthenticationFailureIsTypedAndDoesNotLeakToken() async throws {
        let transport = RecordingHARESTTransport(
            responses: [
                .success(HARESTResponse(statusCode: 401, headers: [:], body: Data(#"{"message":"bad secret-token"}"#.utf8)))
            ]
        )
        let client = HomeAssistantClient(transport: transport)

        let result = await client.checkRESTConnection(try connectionInput())

        XCTAssertEqual(result, .failure(.authentication))
        if case let .failure(error) = result {
            XCTAssertFalse(error.description.contains("secret-token"))
        }
    }

    func testClientFailureMapsToCoreConnectionFailure() {
        XCTAssertEqual(HAClientFailure.authentication.connectionFailure, .authentication)
        XCTAssertEqual(HAClientFailure.unreachable(host: "homeassistant.local").connectionFailure, .unreachable(host: "homeassistant.local"))
        XCTAssertEqual(HAClientFailure.tlsRejected(host: "homeassistant.local").connectionFailure, .tlsRejected(host: "homeassistant.local"))
        XCTAssertEqual(
            HAClientFailure.httpStatus(path: "/api/", statusCode: 500).connectionFailure,
            .protocolError("HTTP 500 for /api/")
        )
    }

    func testConnectionFallsBackWhenPrimaryIsUnreachable() async throws {
        let transport = RecordingHARESTTransport(
            responses: [
                .urlError(URLError(.cannotConnectToHost)),
                .success(HARESTResponse(statusCode: 200, headers: [:], body: Data(#"{"message":"API running."}"#.utf8)))
            ]
        )
        let client = HomeAssistantClient(transport: transport)
        let input = HAConnectionInput(
            endpoint: HAEndpoint(
                primaryURL: try XCTUnwrap(URL(string: "http://primary.local:8123")),
                fallbackURL: try XCTUnwrap(URL(string: "https://fallback.example"))
            ),
            token: "secret-token"
        )

        let result = await client.checkRESTConnection(input)

        XCTAssertEqual(result, .success(HARESTCheck(message: "API running.")))
        let requests = await transport.requests
        XCTAssertEqual(requests.map { $0.url.host }, ["primary.local", "fallback.example"])
    }

    func testConnectionFallsBackWhenPrimaryTransportFails() async throws {
        let transport = RecordingHARESTTransport(
            responses: [
                .transportError("socket closed before response"),
                .success(HARESTResponse(statusCode: 200, headers: [:], body: Data(#"{"message":"API running."}"#.utf8)))
            ]
        )
        let client = HomeAssistantClient(transport: transport)
        let input = HAConnectionInput(
            endpoint: HAEndpoint(
                primaryURL: try XCTUnwrap(URL(string: "http://primary.local:8123")),
                fallbackURL: try XCTUnwrap(URL(string: "https://fallback.example"))
            ),
            token: "secret-token"
        )

        let result = await client.checkRESTConnection(input)

        XCTAssertEqual(result, .success(HARESTCheck(message: "API running.")))
        let requests = await transport.requests
        XCTAssertEqual(requests.map { $0.url.host }, ["primary.local", "fallback.example"])
    }

    func testInvalidStatesPayloadIsTyped() async throws {
        let transport = RecordingHARESTTransport(
            responses: [
                .success(HARESTResponse(statusCode: 200, headers: [:], body: Data(#"[{"state":"21.4"}]"#.utf8)))
            ]
        )
        let client = HomeAssistantClient(transport: transport)

        let result = await client.states(try connectionInput())

        if case let .failure(error) = result {
            XCTAssertTrue(error.description.contains("/api/states"))
        } else {
            XCTFail("invalid states payload unexpectedly succeeded")
        }
    }

    func test_t_connection_errors() async throws {
        let authTransport = RecordingHARESTTransport(
            responses: [
                .success(HARESTResponse(statusCode: 401, headers: [:], body: Data()))
            ]
        )
        let unreachableTransport = RecordingHARESTTransport(
            responses: [
                .urlError(URLError(.cannotConnectToHost))
            ]
        )
        let tlsTransport = RecordingHARESTTransport(
            responses: [
                .urlError(URLError(.serverCertificateUntrusted))
            ]
        )
        let input = try connectionInput()

        XCTAssertEqual(await HomeAssistantClient(transport: authTransport).checkRESTConnection(input), .failure(.authentication))
        XCTAssertEqual(
            await HomeAssistantClient(transport: unreachableTransport).checkRESTConnection(input),
            .failure(.unreachable(host: "homeassistant.local"))
        )
        XCTAssertEqual(
            await HomeAssistantClient(transport: tlsTransport).checkRESTConnection(input),
            .failure(.tlsRejected(host: "homeassistant.local"))
        )
    }

    func testClientFetchesStatesFromFakeHA() async throws {
        let fixtures = FakeHAFixtures(
            apiBody: #"{"message":"API running."}"#,
            statesBody: #"[{"entity_id":"sensor.office_temperature","state":"21.4","attributes":{"friendly_name":"Office temperature","unit_of_measurement":"°C"}}]"#
        )
        let server = try FakeHARESTServer(fixtures: fixtures)
        server.start()
        defer {
            server.stop()
        }
        let input = HAConnectionInput(
            endpoint: HAEndpoint(primaryURL: server.baseURL, fallbackURL: nil),
            token: "fake-token"
        )
        let client = HomeAssistantClient()

        XCTAssertEqual(await client.checkRESTConnection(input), .success(HARESTCheck(message: "API running.")))
        XCTAssertEqual(
            await client.states(input),
            .success([
                EntityState(id: "sensor.office_temperature", name: "Office temperature", state: "21.4", unit: "°C")
            ])
        )
    }

    func testSelfSignedRESTRequiresExplicitHostAllowance() async throws {
        let identity = try FakeHASelfSignedIdentity()
        let server = try FakeHARESTServer(
            fixtures: FakeHAFixtures(
                apiBody: #"{"message":"API running."}"#,
                statesBody: #"[]"#
            ),
            tlsIdentity: identity.identity
        )
        server.start()
        defer {
            server.stop()
        }
        let client = HomeAssistantClient()
        let strictInput = HAConnectionInput(
            endpoint: HAEndpoint(primaryURL: server.baseURL, fallbackURL: nil),
            token: "fake-token"
        )
        let allowedInput = HAConnectionInput(
            endpoint: HAEndpoint(primaryURL: server.baseURL, fallbackURL: nil),
            token: "fake-token",
            serverTrustPolicy: HAServerTrustPolicy(allowedSelfSignedCertificateHosts: ["127.0.0.1"])
        )

        XCTAssertEqual(await client.checkRESTConnection(strictInput), .failure(.tlsRejected(host: "127.0.0.1")))
        XCTAssertEqual(await client.checkRESTConnection(allowedInput), .success(HARESTCheck(message: "API running.")))
    }

    func testSelfSignedAllowanceRejectsCASignedSingleLeafCertificate() async throws {
        let identity = try FakeHASelfSignedIdentity.caSignedLeaf()
        let server = try FakeHARESTServer(
            fixtures: FakeHAFixtures(
                apiBody: #"{"message":"API running."}"#,
                statesBody: #"[]"#
            ),
            tlsIdentity: identity.identity
        )
        server.start()
        defer {
            server.stop()
        }
        let input = HAConnectionInput(
            endpoint: HAEndpoint(primaryURL: server.baseURL, fallbackURL: nil),
            token: "fake-token",
            serverTrustPolicy: HAServerTrustPolicy(allowedSelfSignedCertificateHosts: ["127.0.0.1"])
        )

        XCTAssertEqual(await HomeAssistantClient().checkRESTConnection(input), .failure(.tlsRejected(host: "127.0.0.1")))
    }

    func testSelfSignedWebSocketRequiresExplicitHostAllowance() async throws {
        let identity = try FakeHASelfSignedIdentity()
        let server = try FakeHAWebSocketServer(tlsIdentity: identity.identity)
        server.start()
        defer {
            server.stop()
        }
        let client = HomeAssistantClient()
        let strictInput = HAConnectionInput(
            endpoint: HAEndpoint(primaryURL: server.baseURL, fallbackURL: nil),
            token: "fake-token"
        )
        let allowedInput = HAConnectionInput(
            endpoint: HAEndpoint(primaryURL: server.baseURL, fallbackURL: nil),
            token: "fake-token",
            serverTrustPolicy: HAServerTrustPolicy(allowedSelfSignedCertificateHosts: ["127.0.0.1"])
        )

        XCTAssertEqual(await client.checkWebSocketConnection(strictInput), .failure(.tlsRejected(host: "127.0.0.1")))
        XCTAssertEqual(await client.checkWebSocketConnection(allowedInput), .success(HAWebSocketCheck(haVersion: "fake-ha")))
    }

    func testSelfSignedWebSocketAllowanceRejectsCASignedSingleLeafCertificate() async throws {
        let identity = try FakeHASelfSignedIdentity.caSignedLeaf()
        let server = try FakeHAWebSocketServer(tlsIdentity: identity.identity)
        server.start()
        defer {
            server.stop()
        }
        let input = HAConnectionInput(
            endpoint: HAEndpoint(primaryURL: server.baseURL, fallbackURL: nil),
            token: "fake-token",
            serverTrustPolicy: HAServerTrustPolicy(allowedSelfSignedCertificateHosts: ["127.0.0.1"])
        )

        XCTAssertEqual(await HomeAssistantClient().checkWebSocketConnection(input), .failure(.tlsRejected(host: "127.0.0.1")))
    }

    func test_t_rest_history_provider_maps_and_sorts_samples() async throws {
        let historyBody = """
        [
          [
            {"entity_id":"sensor.office_temperature","state":"22.0","last_changed":"2026-06-27T11:00:00+00:00"},
            {"state":"21.4","last_changed":"2026-06-27T10:30:00+00:00"},
            {"state":"unknown","last_changed":"2026-06-27T11:30:00+00:00"},
            {"entity_id":"sensor.office_temperature","state":"23.0","last_updated":"2026-06-27T11:45:00+00:00"}
          ],
          [
            {"entity_id":"sensor.other","state":"1","last_changed":"2026-06-27T10:00:00+00:00"}
          ]
        ]
        """
        let transport = RecordingHARESTTransport(
            responses: [
                .success(HARESTResponse(statusCode: 200, headers: [:], body: Data(historyBody.utf8)))
            ]
        )
        let client = HomeAssistantClient(transport: transport)
        let end = try historyDate("2026-06-27T12:00:00+00:00")

        let result = await client.history(
            try connectionInput(),
            entityID: "sensor.office_temperature",
            range: .hour,
            end: end
        )

        XCTAssertEqual(
            result,
            .success(
                HistorySeries(
                    entityID: "sensor.office_temperature",
                    range: .hour,
                    samples: [
                        HistorySample(timestamp: try historyDate("2026-06-27T10:30:00+00:00"), state: "21.4", numericValue: 21.4),
                        HistorySample(timestamp: try historyDate("2026-06-27T11:00:00+00:00"), state: "22.0", numericValue: 22.0),
                        HistorySample(timestamp: try historyDate("2026-06-27T11:30:00+00:00"), state: "unknown", numericValue: nil),
                        HistorySample(timestamp: try historyDate("2026-06-27T11:45:00+00:00"), state: "23.0", numericValue: 23.0)
                    ]
                )
            )
        )
        let request = try XCTUnwrap(await transport.requests.first)
        XCTAssertTrue(request.url.path.hasPrefix("/api/history/period/"))
        let items = Dictionary(
            uniqueKeysWithValues: (URLComponents(url: request.url, resolvingAgainstBaseURL: false)?.queryItems ?? [])
                .compactMap { item in item.value.map { (item.name, $0) } }
        )
        XCTAssertEqual(items["filter_entity_id"], "sensor.office_temperature")
        XCTAssertEqual(items["end_time"], "2026-06-27T12:00:00Z")
        XCTAssertEqual(items["minimal_response"], "true")
        XCTAssertEqual(items["no_attributes"], "true")
    }

    func testRESTHistoryAcceptsMinimalResponseRowsWithoutEntityID() async throws {
        let historyBody = """
        [
          [
            {"entity_id":"sensor.office_temperature","state":"22.0","last_changed":"2026-06-27T11:00:00+00:00"},
            {"state":"21.4","last_changed":"2026-06-27T10:30:00+00:00"},
            {"entity_id":"sensor.office_temperature","state":"unknown","last_updated":"2026-06-27T11:30:00+00:00"}
          ]
        ]
        """
        let transport = RecordingHARESTTransport(
            responses: [
                .success(HARESTResponse(statusCode: 200, headers: [:], body: Data(historyBody.utf8)))
            ]
        )
        let client = HomeAssistantClient(transport: transport)
        let end = try historyDate("2026-06-27T12:00:00+00:00")

        let result = await client.history(
            try connectionInput(),
            entityID: "sensor.office_temperature",
            range: .hour,
            end: end
        )

        XCTAssertEqual(
            result,
            .success(
                HistorySeries(
                    entityID: "sensor.office_temperature",
                    range: .hour,
                    samples: [
                        HistorySample(timestamp: try historyDate("2026-06-27T10:30:00+00:00"), state: "21.4", numericValue: 21.4),
                        HistorySample(timestamp: try historyDate("2026-06-27T11:00:00+00:00"), state: "22.0", numericValue: 22.0),
                        HistorySample(timestamp: try historyDate("2026-06-27T11:30:00+00:00"), state: "unknown", numericValue: nil)
                    ]
                )
            )
        )
        let request = try XCTUnwrap(await transport.requests.first)
        XCTAssertTrue(request.url.path.hasPrefix("/api/history/period/"))
        let items = Dictionary(
            uniqueKeysWithValues: (URLComponents(url: request.url, resolvingAgainstBaseURL: false)?.queryItems ?? [])
                .compactMap { item in item.value.map { (item.name, $0) } }
        )
        XCTAssertEqual(items["filter_entity_id"], "sensor.office_temperature")
        XCTAssertEqual(items["end_time"], "2026-06-27T12:00:00Z")
        XCTAssertEqual(items["minimal_response"], "true")
        XCTAssertEqual(items["no_attributes"], "true")
    }

    func testRESTHistoryPreservesBasePathPrefixAgainstFakeHA() async throws {
        let fixtures = FakeHAFixtures(
            apiBody: #"{"message":"API running."}"#,
            statesBody: #"[]"#,
            historyBody: """
            [[{"entity_id":"sensor.office_temperature","state":"22.0","last_changed":"2026-06-27T11:00:00+00:00"}]]
            """
        )
        let server = try FakeHARESTServer(fixtures: fixtures, pathPrefix: "/ha")
        server.start()
        defer {
            server.stop()
        }
        let input = HAConnectionInput(
            endpoint: HAEndpoint(primaryURL: server.baseURL, fallbackURL: nil),
            token: "fake-token"
        )
        let client = HomeAssistantClient()

        let result = await client.history(
            input,
            entityID: "sensor.office_temperature",
            range: .day,
            end: try historyDate("2026-06-27T12:00:00+00:00")
        )

        XCTAssertEqual(
            result,
            .success(
                HistorySeries(
                    entityID: "sensor.office_temperature",
                    range: .day,
                    samples: [
                        HistorySample(timestamp: try historyDate("2026-06-27T11:00:00+00:00"), state: "22.0", numericValue: 22.0)
                    ]
                )
            )
        )
        let journal = await server.journal.snapshot()
        XCTAssertTrue(journal.contains { $0.path.hasPrefix("/ha/api/history/period/") })
        XCTAssertTrue(journal.contains { $0.path.contains("filter_entity_id=sensor.office_temperature") })
    }

    func testRESTHistoryReturnsEmptySeriesForNoSamples() async throws {
        let transport = RecordingHARESTTransport(
            responses: [
                .success(HARESTResponse(statusCode: 200, headers: [:], body: Data(#"[]"#.utf8)))
            ]
        )
        let client = HomeAssistantClient(transport: transport)

        let result = await client.history(
            try connectionInput(),
            entityID: "sensor.office_temperature",
            range: .day,
            end: try historyDate("2026-06-27T12:00:00+00:00")
        )

        XCTAssertEqual(
            result,
            .success(HistorySeries(entityID: "sensor.office_temperature", range: .day, samples: []))
        )
    }

    func testRESTHistoryRejectsMalformedPayload() async throws {
        let transport = RecordingHARESTTransport(
            responses: [
                .success(
                    HARESTResponse(
                        statusCode: 200,
                        headers: [:],
                        body: Data(#"[[{"entity_id":"sensor.office_temperature","state":"22.0"}]]"#.utf8)
                    )
                )
            ]
        )
        let client = HomeAssistantClient(transport: transport)

        let result = await client.history(
            try connectionInput(),
            entityID: "sensor.office_temperature",
            range: .hour,
            end: try historyDate("2026-06-27T12:00:00+00:00")
        )

        if case let .failure(error) = result {
            XCTAssertTrue(error.description.contains("/api/history/period"))
        } else {
            XCTFail("malformed history payload unexpectedly succeeded")
        }
    }

    func test_t_history_week_routes_to_recorder_statistics() async throws {
        let fixtures = FakeHAFixtures(
            apiBody: #"{"message":"API running."}"#,
            statesBody: #"[]"#,
            recorderStatisticsBody: """
            {
              "sensor.office_temperature": [
                {"start":1782558000000,"end":1782561600000,"mean":22.0},
                {"start":1782554400000,"end":1782558000000,"state":21.4},
                {"start":1782561600000,"end":1782565200000,"mean":null,"state":null}
              ],
              "sensor.other": [
                {"start":1782554400000,"end":1782558000000,"mean":1.0}
              ]
            }
            """
        )
        let server = try FakeHAWebSocketServer(fixtures: fixtures)
        server.start()
        defer {
            server.stop()
        }
        let client = HomeAssistantClient()
        let input = HAConnectionInput(
            endpoint: HAEndpoint(primaryURL: server.baseURL, fallbackURL: nil),
            token: "fake-token"
        )

        let result = await client.history(
            input,
            entityID: "sensor.office_temperature",
            range: .week,
            end: try historyDate("2026-06-27T12:00:00+00:00")
        )

        XCTAssertEqual(
            result,
            .success(
                HistorySeries(
                    entityID: "sensor.office_temperature",
                    range: .week,
                    samples: [
                        HistorySample(timestamp: try historyDate("2026-06-27T10:00:00+00:00"), state: "21.4", numericValue: 21.4),
                        HistorySample(timestamp: try historyDate("2026-06-27T11:00:00+00:00"), state: "22.0", numericValue: 22.0)
                    ]
                )
            )
        )
        try await waitForJournalPath(server: server, path: "/api/websocket/recorder/statistics_during_period")
        let journal = await server.journal.snapshot()
        let command = try XCTUnwrap(journal.first { $0.path == "/api/websocket/recorder/statistics_during_period" })
        XCTAssertTrue(command.bodyText?.contains(#""period":"hour""#) ?? false)
        XCTAssertTrue(command.bodyText?.contains(#""statistic_ids":["sensor.office_temperature"]"#) ?? false)
        XCTAssertTrue(command.bodyText?.contains(#""start_time":"2026-06-20T12:00:00Z""#) ?? false)
        XCTAssertTrue(command.bodyText?.contains(#""end_time":"2026-06-27T12:00:00Z""#) ?? false)
        XCTAssertFalse(journal.contains { $0.path.hasPrefix("/api/history/period/") })
    }

    func testHistoryMonthRoutesToRecorderStatisticsWithDailyPeriod() async throws {
        let fixtures = FakeHAFixtures(
            apiBody: #"{"message":"API running."}"#,
            statesBody: #"[]"#,
            recorderStatisticsBody: """
            {
              "sensor.office_energy": [
                {"start":1780272000000,"end":1780358400000,"state":41.0}
              ]
            }
            """
        )
        let server = try FakeHAWebSocketServer(fixtures: fixtures)
        server.start()
        defer {
            server.stop()
        }
        let client = HomeAssistantClient()
        let input = HAConnectionInput(
            endpoint: HAEndpoint(primaryURL: server.baseURL, fallbackURL: nil),
            token: "fake-token"
        )

        let result = await client.history(
            input,
            entityID: "sensor.office_energy",
            range: .month,
            end: try historyDate("2026-06-27T12:00:00+00:00")
        )

        XCTAssertEqual(
            result,
            .success(
                HistorySeries(
                    entityID: "sensor.office_energy",
                    range: .month,
                    samples: [
                        HistorySample(timestamp: try historyDate("2026-06-01T00:00:00+00:00"), state: "41.0", numericValue: 41.0)
                    ]
                )
            )
        )
        try await waitForJournalPath(server: server, path: "/api/websocket/recorder/statistics_during_period")
        let command = try XCTUnwrap(await server.journal.snapshot().first { $0.path == "/api/websocket/recorder/statistics_during_period" })
        XCTAssertTrue(command.bodyText?.contains(#""period":"day""#) ?? false)
        XCTAssertTrue(command.bodyText?.contains(#""start_time":"2026-05-28T12:00:00Z""#) ?? false)
    }

    func testHistoryRecorderStatisticsPreservesBasePathPrefixAgainstFakeHA() async throws {
        let fixtures = FakeHAFixtures(
            apiBody: #"{"message":"API running."}"#,
            statesBody: #"[]"#,
            recorderStatisticsBody: """
            {
              "sensor.office_temperature": [
                {"start":1782554400000,"end":1782558000000,"mean":21.4}
              ]
            }
            """
        )
        let server = try FakeHAWebSocketServer(fixtures: fixtures, pathPrefix: "/ha")
        server.start()
        defer {
            server.stop()
        }
        let client = HomeAssistantClient()
        let input = HAConnectionInput(
            endpoint: HAEndpoint(primaryURL: server.baseURL, fallbackURL: nil),
            token: "fake-token"
        )

        let result = await client.history(
            input,
            entityID: "sensor.office_temperature",
            range: .week,
            end: try historyDate("2026-06-27T12:00:00+00:00")
        )

        XCTAssertEqual(
            result,
            .success(
                HistorySeries(
                    entityID: "sensor.office_temperature",
                    range: .week,
                    samples: [
                        HistorySample(timestamp: try historyDate("2026-06-27T10:00:00+00:00"), state: "21.4", numericValue: 21.4)
                    ]
                )
            )
        )
        let journal = await server.journal.snapshot()
        XCTAssertEqual(journal.first?.path, "/ha/api/websocket")
        XCTAssertTrue(journal.contains { $0.path == "/api/websocket/recorder/statistics_during_period" })
    }

    func testHistoryFallsBackToRESTWhenRecorderStatisticsIsUnknown() async throws {
        let fixtures = FakeHAFixtures(
            apiBody: #"{"message":"API running."}"#,
            statesBody: #"[]"#,
            historyBody: """
            [[{"entity_id":"sensor.office_temperature","state":"22.0","last_changed":"2026-06-27T11:00:00+00:00"}]]
            """
        )
        let server = try FakeHAWebSocketServer(
            fixtures: fixtures,
            mode: .unavailableCommands(["recorder/statistics_during_period"], code: .unknownCommand)
        )
        server.start()
        defer {
            server.stop()
        }
        let client = HomeAssistantClient()
        let input = HAConnectionInput(
            endpoint: HAEndpoint(primaryURL: server.baseURL, fallbackURL: nil),
            token: "fake-token"
        )

        let result = await client.history(
            input,
            entityID: "sensor.office_temperature",
            range: .week,
            end: try historyDate("2026-06-27T12:00:00+00:00")
        )

        XCTAssertEqual(
            result,
            .success(
                HistorySeries(
                    entityID: "sensor.office_temperature",
                    range: .week,
                    samples: [
                        HistorySample(timestamp: try historyDate("2026-06-27T11:00:00+00:00"), state: "22.0", numericValue: 22.0)
                    ]
                )
            )
        )
        try await waitForJournalPath(server: server, path: "/api/websocket/recorder/statistics_during_period")
        let journal = await server.journal.snapshot()
        XCTAssertTrue(journal.contains { $0.path.hasPrefix("/api/history/period/") })
    }

    func testHistoryRecorderStatisticsFallbackPreservesBasePathPrefixAgainstFakeHA() async throws {
        let fixtures = FakeHAFixtures(
            apiBody: #"{"message":"API running."}"#,
            statesBody: #"[]"#,
            historyBody: """
            [[{"entity_id":"sensor.office_temperature","state":"22.5","last_changed":"2026-06-27T11:30:00+00:00"}]]
            """
        )
        let server = try FakeHAWebSocketServer(
            fixtures: fixtures,
            mode: .unavailableCommands(["recorder/statistics_during_period"], code: .unknownCommand),
            pathPrefix: "/ha"
        )
        server.start()
        defer {
            server.stop()
        }
        let client = HomeAssistantClient()
        let input = HAConnectionInput(
            endpoint: HAEndpoint(primaryURL: server.baseURL, fallbackURL: nil),
            token: "fake-token"
        )

        let result = await client.history(
            input,
            entityID: "sensor.office_temperature",
            range: .week,
            end: try historyDate("2026-06-27T12:00:00+00:00")
        )

        XCTAssertEqual(
            result,
            .success(
                HistorySeries(
                    entityID: "sensor.office_temperature",
                    range: .week,
                    samples: [
                        HistorySample(timestamp: try historyDate("2026-06-27T11:30:00+00:00"), state: "22.5", numericValue: 22.5)
                    ]
                )
            )
        )
        let journal = await server.journal.snapshot()
        XCTAssertEqual(journal.first?.path, "/ha/api/websocket")
        XCTAssertTrue(journal.contains { $0.path.hasPrefix("/ha/api/history/period/") })
        XCTAssertTrue(journal.contains { $0.path.contains("filter_entity_id=sensor.office_temperature") })
    }

    func testHistoryFallsBackToRESTWhenRecorderStatisticsIsLegacyUnsupported() async throws {
        let fixtures = FakeHAFixtures(
            apiBody: #"{"message":"API running."}"#,
            statesBody: #"[]"#,
            historyBody: """
            [[{"entity_id":"sensor.office_temperature","state":"21.0","last_changed":"2026-06-27T10:00:00+00:00"}]]
            """
        )
        let server = try FakeHAWebSocketServer(
            fixtures: fixtures,
            mode: .unsupportedCommands(["recorder/statistics_during_period"])
        )
        server.start()
        defer {
            server.stop()
        }
        let client = HomeAssistantClient()
        let input = HAConnectionInput(
            endpoint: HAEndpoint(primaryURL: server.baseURL, fallbackURL: nil),
            token: "fake-token"
        )

        let result = await client.history(
            input,
            entityID: "sensor.office_temperature",
            range: .month,
            end: try historyDate("2026-06-27T12:00:00+00:00")
        )

        XCTAssertEqual(
            result,
            .success(
                HistorySeries(
                    entityID: "sensor.office_temperature",
                    range: .month,
                    samples: [
                        HistorySample(timestamp: try historyDate("2026-06-27T10:00:00+00:00"), state: "21.0", numericValue: 21.0)
                    ]
                )
            )
        )
        try await waitForJournalPath(server: server, path: "/api/websocket/recorder/statistics_during_period")
        let journal = await server.journal.snapshot()
        XCTAssertTrue(journal.contains { $0.path.hasPrefix("/api/history/period/") })
    }

    func testHistoryFallsBackToRESTWhenRecorderStatisticsTransportIsUnreachable() async throws {
        let fixtures = FakeHAFixtures(
            apiBody: #"{"message":"API running."}"#,
            statesBody: #"[]"#,
            historyBody: """
            [[{"entity_id":"sensor.office_temperature","state":"20.5","last_changed":"2026-06-27T09:00:00+00:00"}]]
            """
        )
        let fallbackServer = try FakeHAWebSocketServer(
            fixtures: fixtures,
            mode: .unavailableCommands(["recorder/statistics_during_period"], code: .unknownCommand)
        )
        fallbackServer.start()
        defer {
            fallbackServer.stop()
        }
        let client = HomeAssistantClient()
        let input = HAConnectionInput(
            endpoint: HAEndpoint(
                primaryURL: try XCTUnwrap(URL(string: "http://127.0.0.1:1")),
                fallbackURL: fallbackServer.baseURL
            ),
            token: "fake-token"
        )

        let result = await client.history(
            input,
            entityID: "sensor.office_temperature",
            range: .week,
            end: try historyDate("2026-06-27T12:00:00+00:00")
        )

        XCTAssertEqual(
            result,
            .success(
                HistorySeries(
                    entityID: "sensor.office_temperature",
                    range: .week,
                    samples: [
                        HistorySample(timestamp: try historyDate("2026-06-27T09:00:00+00:00"), state: "20.5", numericValue: 20.5)
                    ]
                )
            )
        )
        try await waitForJournalPath(server: fallbackServer, path: "/api/websocket/recorder/statistics_during_period")
        let journal = await fallbackServer.journal.snapshot()
        XCTAssertEqual(journal.first?.path, "/api/websocket")
        XCTAssertTrue(journal.contains { $0.path.hasPrefix("/api/history/period/") })
        XCTAssertTrue(journal.contains { $0.path.contains("filter_entity_id=sensor.office_temperature") })
    }

    func testHistoryFallsBackToRESTWhenRecorderStatisticsCommandTransportBreaks() async throws {
        let fixtures = FakeHAFixtures(
            apiBody: #"{"message":"API running."}"#,
            statesBody: #"[]"#,
            historyBody: """
            [[{"entity_id":"sensor.office_temperature","state":"20.75","last_changed":"2026-06-27T09:30:00+00:00"}]]
            """,
            recorderStatisticsBody: """
            {"sensor.office_temperature":[{"start":1782460800000,"mean":99.0}]}
            """
        )
        let server = try FakeHAWebSocketServer(
            fixtures: fixtures,
            mode: .disconnectOnCommands(["recorder/statistics_during_period"])
        )
        server.start()
        defer {
            server.stop()
        }
        let client = HomeAssistantClient()
        let input = HAConnectionInput(
            endpoint: HAEndpoint(primaryURL: server.baseURL, fallbackURL: nil),
            token: "fake-token"
        )

        let result = await client.history(
            input,
            entityID: "sensor.office_temperature",
            range: .week,
            end: try historyDate("2026-06-27T12:00:00+00:00")
        )

        XCTAssertEqual(
            result,
            .success(
                HistorySeries(
                    entityID: "sensor.office_temperature",
                    range: .week,
                    samples: [
                        HistorySample(timestamp: try historyDate("2026-06-27T09:30:00+00:00"), state: "20.75", numericValue: 20.75)
                    ]
                )
            )
        )
        try await waitForJournalPath(server: server, path: "/api/websocket/recorder/statistics_during_period")
        let journal = await server.journal.snapshot()
        XCTAssertTrue(journal.contains { $0.path.hasPrefix("/api/history/period/") })
        XCTAssertTrue(journal.contains { $0.path.contains("filter_entity_id=sensor.office_temperature") })
    }

    func testHistoryRecorderStatisticsRejectsMalformedPayload() async throws {
        let fixtures = FakeHAFixtures(
            apiBody: #"{"message":"API running."}"#,
            statesBody: #"[]"#,
            recorderStatisticsBody: """
            {"sensor.office_temperature":[{"start":"bad","mean":22.0}]}
            """
        )
        let server = try FakeHAWebSocketServer(fixtures: fixtures)
        server.start()
        defer {
            server.stop()
        }
        let client = HomeAssistantClient()
        let input = HAConnectionInput(
            endpoint: HAEndpoint(primaryURL: server.baseURL, fallbackURL: nil),
            token: "fake-token"
        )

        let result = await client.history(
            input,
            entityID: "sensor.office_temperature",
            range: .week,
            end: try historyDate("2026-06-27T12:00:00+00:00")
        )

        if case let .failure(error) = result {
            XCTAssertTrue(error.description.contains("/api/websocket"))
        } else {
            XCTFail("malformed recorder statistics payload unexpectedly succeeded")
        }
    }

    func testWebSocketAuthSucceedsAgainstFakeHA() async throws {
        let server = try FakeHAWebSocketServer()
        server.start()
        defer {
            server.stop()
        }
        let client = HomeAssistantClient()
        let input = HAConnectionInput(
            endpoint: HAEndpoint(primaryURL: server.baseURL, fallbackURL: nil),
            token: "fake-token"
        )

        XCTAssertEqual(await client.checkWebSocketConnection(input), .success(HAWebSocketCheck(haVersion: "fake-ha")))
    }

    func testWebSocketDiscoveryPreservesBasePathPrefix() async throws {
        let fixtures = FakeHAFixtures(
            apiBody: #"{"message":"API running."}"#,
            statesBody: #"[{"entity_id":"sensor.office_temperature","state":"21.4","attributes":{"friendly_name":"Office temperature","unit_of_measurement":"°C"}}]"#,
            areaRegistryBody: #"[{"area_id":"office","name":"Office"}]"#,
            deviceRegistryBody: #"[]"#,
            entityRegistryBody: #"[{"entity_id":"sensor.office_temperature","name":"Office temperature","area_id":"office"}]"#
        )
        let server = try FakeHAWebSocketServer(fixtures: fixtures, pathPrefix: "/ha")
        server.start()
        defer {
            server.stop()
        }
        let client = HomeAssistantClient()
        let input = HAConnectionInput(
            endpoint: HAEndpoint(primaryURL: server.baseURL, fallbackURL: nil),
            token: "fake-token"
        )

        let result = await client.discovery(input)

        XCTAssertEqual(
            result,
            .success(
                DiscoverySnapshot(
                    areas: [Area(id: "office", name: "Office")],
                    devices: [],
                    entities: [EntityRegistryEntry(id: "sensor.office_temperature", name: "Office temperature", areaID: "office", deviceID: nil)],
                    states: [EntityState(id: "sensor.office_temperature", name: "Office temperature", state: "21.4", unit: "°C")]
                )
            )
        )
        let journal = await server.journal.snapshot()
        XCTAssertEqual(journal.first?.path, "/ha/api/websocket")
    }

    func testWebSocketAuthFailureIsTyped() async throws {
        let server = try FakeHAWebSocketServer()
        server.start()
        defer {
            server.stop()
        }
        let client = HomeAssistantClient()
        let input = HAConnectionInput(
            endpoint: HAEndpoint(primaryURL: server.baseURL, fallbackURL: nil),
            token: "wrong-token"
        )

        XCTAssertEqual(await client.checkWebSocketConnection(input), .failure(.authentication))
    }

    func testWebSocketStatesMapsFakeHAStates() async throws {
        let fixtures = FakeHAFixtures(
            apiBody: #"{"message":"API running."}"#,
            statesBody: #"[{"entity_id":"sensor.office_temperature","state":"21.4","attributes":{"friendly_name":"Office temperature","unit_of_measurement":"°C"}}]"#
        )
        let server = try FakeHAWebSocketServer(fixtures: fixtures)
        server.start()
        defer {
            server.stop()
        }
        let client = HomeAssistantClient()
        let input = HAConnectionInput(
            endpoint: HAEndpoint(primaryURL: server.baseURL, fallbackURL: nil),
            token: "fake-token"
        )

        XCTAssertEqual(
            await client.webSocketStates(input),
            .success([
                EntityState(id: "sensor.office_temperature", name: "Office temperature", state: "21.4", unit: "°C")
            ])
        )
    }

    func testWebSocketWrongResultIDIsProtocolErrorAndDoesNotFallback() async throws {
        let primary = try FakeHAWebSocketServer(mode: .wrongResultID)
        let fallback = try FakeHAWebSocketServer()
        primary.start()
        fallback.start()
        defer {
            primary.stop()
            fallback.stop()
        }
        let client = HomeAssistantClient()
        let input = HAConnectionInput(
            endpoint: HAEndpoint(primaryURL: primary.baseURL, fallbackURL: fallback.baseURL),
            token: "fake-token"
        )

        let result = await client.webSocketStates(input)

        XCTAssertEqual(result, .failure(.webSocketProtocol("expected result id 1, received 2")))
        try await waitForJournalCount(server: primary, count: 1)
        XCTAssertTrue(await fallback.journal.snapshot().isEmpty)
    }

    func testWebSocketCommandFailureIsTyped() async throws {
        let server = try FakeHAWebSocketServer(mode: .commandFailure)
        server.start()
        defer {
            server.stop()
        }
        let client = HomeAssistantClient()
        let input = HAConnectionInput(
            endpoint: HAEndpoint(primaryURL: server.baseURL, fallbackURL: nil),
            token: "fake-token"
        )

        XCTAssertEqual(
            await client.webSocketStates(input),
            .failure(.webSocketCommand(id: 1, code: "failed", message: "Planned command failure"))
        )
    }

    func testStateChangedEventMapsNewState() async throws {
        let fixtures = FakeHAFixtures(
            apiBody: #"{"message":"API running."}"#,
            statesBody: #"[]"#,
            stateChangedEventBody: #"{"entity_id":"sensor.office_temperature","state":"22.0","attributes":{"friendly_name":"Office temperature","unit_of_measurement":"°C"}}"#
        )
        let server = try FakeHAWebSocketServer(fixtures: fixtures)
        server.start()
        defer {
            server.stop()
        }
        let client = HomeAssistantClient()
        let input = HAConnectionInput(
            endpoint: HAEndpoint(primaryURL: server.baseURL, fallbackURL: nil),
            token: "fake-token"
        )

        XCTAssertEqual(
            await client.nextStateChangedEvent(input),
            .success(EntityState(id: "sensor.office_temperature", name: "Office temperature", state: "22.0", unit: "°C"))
        )
        try await waitForJournalPath(server: server, path: "/api/websocket/subscribe_entities")
        let paths = await server.journal.snapshot().map(\.path)
        XCTAssertFalse(paths.contains("/api/websocket/subscribe_events"))
    }

    func test_t_reconnect_after_restart_resubscribes_live_state() async throws {
        let fixtures = FakeHAFixtures(
            apiBody: #"{"message":"API running."}"#,
            statesBody: #"[]"#,
            stateChangedEventBody: #"{"entity_id":"sensor.office_temperature","state":"22.0","attributes":{"friendly_name":"Office temperature","unit_of_measurement":"°C"}}"#
        )
        let server = try FakeHAWebSocketServer(fixtures: fixtures, mode: .disconnectOnceAfterSubscribeEntitiesResult)
        server.start()
        defer {
            server.stop()
        }
        let client = HomeAssistantClient()
        let input = HAConnectionInput(
            endpoint: HAEndpoint(primaryURL: server.baseURL, fallbackURL: nil),
            token: "fake-token"
        )

        XCTAssertEqual(
            await client.nextStateChangedEvent(input),
            .success(EntityState(id: "sensor.office_temperature", name: "Office temperature", state: "22.0", unit: "°C"))
        )
        try await waitForJournalCount(server: server, count: 4)
        let paths = await server.journal.snapshot().map(\.path)
        XCTAssertEqual(paths.filter { $0 == "/api/websocket" }.count, 2)
        XCTAssertEqual(paths.filter { $0 == "/api/websocket/subscribe_entities" }.count, 2)
        XCTAssertFalse(paths.contains("/api/websocket/subscribe_events"))
    }

    func test_t_live_updates_fall_back_to_subscribe_events_when_subscribe_entities_is_unknown() async throws {
        let fixtures = FakeHAFixtures(
            apiBody: #"{"message":"API running."}"#,
            statesBody: #"[]"#,
            stateChangedEventBody: #"{"entity_id":"sensor.office_temperature","state":"22.0","attributes":{"friendly_name":"Office temperature","unit_of_measurement":"°C"}}"#
        )
        let server = try FakeHAWebSocketServer(fixtures: fixtures, mode: .unavailableCommands(["subscribe_entities"], code: .unknownCommand))
        server.start()
        defer {
            server.stop()
        }
        let client = HomeAssistantClient()
        let input = HAConnectionInput(
            endpoint: HAEndpoint(primaryURL: server.baseURL, fallbackURL: nil),
            token: "fake-token"
        )

        XCTAssertEqual(
            await client.nextStateChangedEvent(input),
            .success(EntityState(id: "sensor.office_temperature", name: "Office temperature", state: "22.0", unit: "°C"))
        )
        try await waitForJournalPath(server: server, path: "/api/websocket/subscribe_events")
        let paths = await server.journal.snapshot().map(\.path)
        XCTAssertTrue(paths.contains("/api/websocket/subscribe_entities"))
        XCTAssertTrue(paths.contains("/api/websocket/subscribe_events"))
    }

    func test_t_live_updates_fall_back_to_subscribe_events_when_subscribe_entities_is_legacy_unsupported() async throws {
        let fixtures = FakeHAFixtures(
            apiBody: #"{"message":"API running."}"#,
            statesBody: #"[]"#,
            stateChangedEventBody: #"{"entity_id":"sensor.office_temperature","state":"22.0","attributes":{"friendly_name":"Office temperature","unit_of_measurement":"°C"}}"#
        )
        let server = try FakeHAWebSocketServer(fixtures: fixtures, mode: .unsupportedCommands(["subscribe_entities"]))
        server.start()
        defer {
            server.stop()
        }
        let client = HomeAssistantClient()
        let input = HAConnectionInput(
            endpoint: HAEndpoint(primaryURL: server.baseURL, fallbackURL: nil),
            token: "fake-token"
        )

        XCTAssertEqual(
            await client.nextStateChangedEvent(input),
            .success(EntityState(id: "sensor.office_temperature", name: "Office temperature", state: "22.0", unit: "°C"))
        )
        try await waitForJournalPath(server: server, path: "/api/websocket/subscribe_events")
        let paths = await server.journal.snapshot().map(\.path)
        XCTAssertTrue(paths.contains("/api/websocket/subscribe_entities"))
        XCTAssertTrue(paths.contains("/api/websocket/subscribe_events"))
    }

    func test_t_live_updates_merge_partial_subscribe_entities_change() async throws {
        let fixtures = FakeHAFixtures(
            apiBody: #"{"message":"API running."}"#,
            statesBody: """
            [
              {"entity_id":"cover.office_blinds","state":"open","attributes":{"friendly_name":"Office blinds","current_position":40}}
            ]
            """,
            stateChangedEventBody: #"{"entity_id":"cover.office_blinds","state":"open","attributes":{"friendly_name":"Office blinds","current_position":76}}"#
        )
        let server = try FakeHAWebSocketServer(fixtures: fixtures, mode: .partialSubscribeEntitiesChange)
        server.start()
        defer {
            server.stop()
        }
        let client = HomeAssistantClient()
        let input = HAConnectionInput(
            endpoint: HAEndpoint(primaryURL: server.baseURL, fallbackURL: nil),
            token: "fake-token"
        )

        XCTAssertEqual(
            await client.nextStateChangedEvent(input),
            .success(EntityState(id: "cover.office_blinds", name: "Office blinds", state: "open", unit: nil, currentPosition: 76))
        )
        try await waitForJournalPath(server: server, path: "/api/websocket/subscribe_entities")
        let paths = await server.journal.snapshot().map(\.path)
        XCTAssertFalse(paths.contains("/api/websocket/subscribe_events"))
    }

    func test_t_live_updates_merge_subscribe_entities_attribute_removals() async throws {
        let fixtures = FakeHAFixtures(
            apiBody: #"{"message":"API running."}"#,
            statesBody: """
            [
              {"entity_id":"sensor.office_temperature","state":"21.4","attributes":{"friendly_name":"Office temperature","unit_of_measurement":"°C"}}
            ]
            """,
            stateChangedEventBody: #"{"entity_id":"sensor.office_temperature","state":"22.0","attributes":{"friendly_name":"Office temperature","unit_of_measurement":"°C"}}"#
        )
        let server = try FakeHAWebSocketServer(fixtures: fixtures, mode: .attributeRemovalSubscribeEntitiesChange)
        server.start()
        defer {
            server.stop()
        }
        let client = HomeAssistantClient()
        let input = HAConnectionInput(
            endpoint: HAEndpoint(primaryURL: server.baseURL, fallbackURL: nil),
            token: "fake-token"
        )

        XCTAssertEqual(
            await client.nextStateChangedEvent(input),
            .success(EntityState(id: "sensor.office_temperature", name: "sensor.office_temperature", state: "21.4", unit: nil))
        )
        try await waitForJournalPath(server: server, path: "/api/websocket/subscribe_entities")
        let paths = await server.journal.snapshot().map(\.path)
        XCTAssertFalse(paths.contains("/api/websocket/subscribe_events"))
    }

    func test_t_live_updates_clear_current_position_when_subscribe_entities_removes_it() async throws {
        let fixtures = FakeHAFixtures(
            apiBody: #"{"message":"API running."}"#,
            statesBody: """
            [
              {"entity_id":"cover.office_blinds","state":"open","attributes":{"friendly_name":"Office blinds","current_position":41}}
            ]
            """,
            stateChangedEventBody: #"{"entity_id":"cover.office_blinds","state":"open","attributes":{"friendly_name":"Office blinds","current_position":41}}"#
        )
        let server = try FakeHAWebSocketServer(fixtures: fixtures, mode: .attributeRemovalSubscribeEntitiesChange)
        server.start()
        defer {
            server.stop()
        }
        let client = HomeAssistantClient()
        let input = HAConnectionInput(
            endpoint: HAEndpoint(primaryURL: server.baseURL, fallbackURL: nil),
            token: "fake-token"
        )

        XCTAssertEqual(
            await client.nextStateChangedEvent(input),
            .success(EntityState(id: "cover.office_blinds", name: "cover.office_blinds", state: "open", unit: nil))
        )
        try await waitForJournalPath(server: server, path: "/api/websocket/subscribe_entities")
        let paths = await server.journal.snapshot().map(\.path)
        XCTAssertFalse(paths.contains("/api/websocket/subscribe_events"))
    }

    func test_t_live_updates_ignore_subscribe_entities_entity_removal_until_next_state() async throws {
        let fixtures = FakeHAFixtures(
            apiBody: #"{"message":"API running."}"#,
            statesBody: """
            [
              {"entity_id":"sensor.office_temperature","state":"21.4","attributes":{"friendly_name":"Office temperature","unit_of_measurement":"°C"}}
            ]
            """,
            stateChangedEventBody: #"{"entity_id":"sensor.office_temperature","state":"22.0","attributes":{"friendly_name":"Office temperature","unit_of_measurement":"°C"}}"#
        )
        let server = try FakeHAWebSocketServer(fixtures: fixtures, mode: .entityRemovalThenSubscribeEntitiesAddition)
        server.start()
        defer {
            server.stop()
        }
        let client = HomeAssistantClient()
        let input = HAConnectionInput(
            endpoint: HAEndpoint(primaryURL: server.baseURL, fallbackURL: nil),
            token: "fake-token"
        )

        XCTAssertEqual(
            await client.nextStateChangedEvent(input),
            .success(EntityState(id: "sensor.office_temperature", name: "Office temperature", state: "22.0", unit: "°C"))
        )
        try await waitForJournalPath(server: server, path: "/api/websocket/subscribe_entities")
        let paths = await server.journal.snapshot().map(\.path)
        XCTAssertFalse(paths.contains("/api/websocket/subscribe_events"))
    }

    func test_t_live_updates_wait_past_many_subscribe_entities_removals() async throws {
        let fixtures = FakeHAFixtures(
            apiBody: #"{"message":"API running."}"#,
            statesBody: """
            [
              {"entity_id":"sensor.office_temperature","state":"21.4","attributes":{"friendly_name":"Office temperature","unit_of_measurement":"°C"}}
            ]
            """,
            stateChangedEventBody: #"{"entity_id":"sensor.office_temperature","state":"22.0","attributes":{"friendly_name":"Office temperature","unit_of_measurement":"°C"}}"#
        )
        let server = try FakeHAWebSocketServer(fixtures: fixtures, mode: .manyEntityRemovalsThenSubscribeEntitiesAddition(count: 17))
        server.start()
        defer {
            server.stop()
        }
        let client = HomeAssistantClient()
        let input = HAConnectionInput(
            endpoint: HAEndpoint(primaryURL: server.baseURL, fallbackURL: nil),
            token: "fake-token"
        )

        XCTAssertEqual(
            await client.nextStateChangedEvent(input),
            .success(EntityState(id: "sensor.office_temperature", name: "Office temperature", state: "22.0", unit: "°C"))
        )
        try await waitForJournalPath(server: server, path: "/api/websocket/subscribe_entities")
        let paths = await server.journal.snapshot().map(\.path)
        XCTAssertFalse(paths.contains("/api/websocket/subscribe_events"))
    }

    func test_t_live_updates_do_not_merge_partial_change_after_entity_removal() async throws {
        let fixtures = FakeHAFixtures(
            apiBody: #"{"message":"API running."}"#,
            statesBody: """
            [
              {"entity_id":"sensor.office_temperature","state":"21.4","attributes":{"friendly_name":"Old temperature","unit_of_measurement":"old"}}
            ]
            """,
            stateChangedEventBody: #"{"entity_id":"sensor.office_temperature","state":"22.0","attributes":{"friendly_name":"Office temperature","unit_of_measurement":"°C"}}"#
        )
        let server = try FakeHAWebSocketServer(fixtures: fixtures, mode: .entityRemovalThenPartialSubscribeEntitiesChangeThenAddition)
        server.start()
        defer {
            server.stop()
        }
        let client = HomeAssistantClient()
        let input = HAConnectionInput(
            endpoint: HAEndpoint(primaryURL: server.baseURL, fallbackURL: nil),
            token: "fake-token"
        )

        XCTAssertEqual(
            await client.nextStateChangedEvent(input),
            .success(EntityState(id: "sensor.office_temperature", name: "Office temperature", state: "22.0", unit: "°C"))
        )
        try await waitForJournalPath(server: server, path: "/api/websocket/subscribe_entities")
        let paths = await server.journal.snapshot().map(\.path)
        XCTAssertFalse(paths.contains("/api/websocket/subscribe_events"))
    }

    func testCallServiceJournalsExactCustomSensorActionPayload() async throws {
        let server = try FakeHAWebSocketServer()
        server.start()
        defer {
            server.stop()
        }
        let client = HomeAssistantClient()
        let input = HAConnectionInput(
            endpoint: HAEndpoint(primaryURL: server.baseURL, fallbackURL: nil),
            token: "fake-token"
        )
        let call = HAServiceCall(
            domain: "script",
            service: "turn_on",
            targetEntityID: "sensor.office_temperature",
            serviceData: [
                "mode": "boost",
                "duration": 15,
                "confirmed": true,
                "code": "1234",
                "pin": "9999",
                "secret": "hidden"
            ]
        )

        XCTAssertEqual(await client.callService(input, call: call), .success(HAServiceCallResult(contextID: "fake-context")))
        try await waitForJournalCount(server: server, count: 2)

        let serviceEntry = await server.journal.snapshot().last
        XCTAssertEqual(serviceEntry?.method, "WS")
        XCTAssertEqual(serviceEntry?.path, "/api/websocket/call_service")
        XCTAssertTrue(serviceEntry?.bodyText?.contains(#""type":"call_service""#) ?? false)
        XCTAssertTrue(serviceEntry?.bodyText?.contains(#""domain":"script""#) ?? false)
        XCTAssertTrue(serviceEntry?.bodyText?.contains(#""service":"turn_on""#) ?? false)
        XCTAssertTrue(serviceEntry?.bodyText?.contains(#""entity_id":"sensor.office_temperature""#) ?? false)
        XCTAssertTrue(serviceEntry?.bodyText?.contains(#""mode":"boost""#) ?? false)
        XCTAssertTrue(serviceEntry?.bodyText?.contains(#""duration":15"#) ?? false)
        XCTAssertTrue(serviceEntry?.bodyText?.contains(#""confirmed":true"#) ?? false)
        XCTAssertTrue(serviceEntry?.bodyText?.contains(#""code":"<redacted>""#) ?? false)
        XCTAssertTrue(serviceEntry?.bodyText?.contains(#""pin":"<redacted>""#) ?? false)
        XCTAssertTrue(serviceEntry?.bodyText?.contains(#""secret":"<redacted>""#) ?? false)
        XCTAssertFalse(serviceEntry?.bodyText?.contains("1234") ?? true)
        XCTAssertFalse(serviceEntry?.bodyText?.contains("9999") ?? true)
        XCTAssertFalse(serviceEntry?.bodyText?.contains("hidden") ?? true)
    }

    func test_t_custom_action_service_metadata_fetches_get_services() async throws {
        let fixtures = FakeHAFixtures(
            apiBody: #"{"message":"API running."}"#,
            statesBody: #"[]"#,
            servicesBody: """
            {
              "script": {
                "turn_on": {
                  "name": "Turn on",
                  "description": "Runs a script.",
                  "fields": {
                    "entity_id": {
                      "name": "Entity",
                      "description": "Script entity",
                      "required": true,
                      "example": "script.air_cleaner_boost",
                      "selector": {
                        "entity": {
                          "domain": "script"
                        }
                      }
                    },
                    "duration": {
                      "required": false,
                      "example": 15,
                      "selector": {
                        "number": {
                          "min": 1,
                          "max": 60
                        }
                      }
                    }
                  }
                }
              }
            }
            """
        )
        let server = try FakeHAWebSocketServer(fixtures: fixtures)
        server.start()
        defer {
            server.stop()
        }
        let client = HomeAssistantClient()
        let input = HAConnectionInput(
            endpoint: HAEndpoint(primaryURL: server.baseURL, fallbackURL: nil),
            token: "fake-token"
        )

        XCTAssertEqual(
            await client.services(input),
            .success([
                HAServiceMetadata(
                    domain: "script",
                    service: "turn_on",
                    name: "Turn on",
                    description: "Runs a script.",
                    fields: [
                        HAServiceFieldMetadata(
                            key: "duration",
                            name: nil,
                            description: nil,
                            required: false,
                            example: 15,
                            selector: .object([
                                "number": .object([
                                    "max": 60,
                                    "min": 1
                                ])
                            ])
                        ),
                        HAServiceFieldMetadata(
                            key: "entity_id",
                            name: "Entity",
                            description: "Script entity",
                            required: true,
                            example: "script.air_cleaner_boost",
                            selector: .object([
                                "entity": .object([
                                    "domain": "script"
                                ])
                            ])
                        )
                    ]
                )
            ])
        )
        try await waitForJournalPath(server: server, path: "/api/websocket/get_services")
    }

    func test_t_live_updates_panel_and_bar() async throws {
        let fixtures = FakeHAFixtures(
            apiBody: #"{"message":"API running."}"#,
            statesBody: #"[]"#,
            stateChangedEventBody: #"{"entity_id":"sensor.office_temperature","state":"22.0","attributes":{"friendly_name":"Office temperature","unit_of_measurement":"°C"}}"#
        )
        let server = try FakeHAWebSocketServer(fixtures: fixtures)
        server.start()
        defer {
            server.stop()
        }
        let client = HomeAssistantClient()
        let input = HAConnectionInput(
            endpoint: HAEndpoint(primaryURL: server.baseURL, fallbackURL: nil),
            token: "fake-token"
        )

        XCTAssertEqual(
            await client.nextStateChangedEvent(input),
            .success(EntityState(id: "sensor.office_temperature", name: "Office temperature", state: "22.0", unit: "°C"))
        )
    }

    func test_t_call_service_journaled() async throws {
        let server = try FakeHAWebSocketServer()
        server.start()
        defer {
            server.stop()
        }
        let client = HomeAssistantClient()
        let input = HAConnectionInput(
            endpoint: HAEndpoint(primaryURL: server.baseURL, fallbackURL: nil),
            token: "fake-token"
        )

        XCTAssertEqual(
            await client.callService(
                input,
                call: HAServiceCall(domain: "switch", service: "turn_on", targetEntityID: "switch.office_lamp")
            ),
            .success(HAServiceCallResult(contextID: "fake-context"))
        )
        try await waitForJournalCount(server: server, count: 2)
        XCTAssertTrue(await server.journal.snapshot().contains { $0.path == "/api/websocket/call_service" })
    }

    func test_t_websocket_auth_and_get_states() async throws {
        let fixtures = FakeHAFixtures(
            apiBody: #"{"message":"API running."}"#,
            statesBody: #"[{"entity_id":"sensor.office_temperature","state":"21.4","attributes":{"friendly_name":"Office temperature","unit_of_measurement":"°C"}}]"#
        )
        let server = try FakeHAWebSocketServer(fixtures: fixtures)
        server.start()
        defer {
            server.stop()
        }
        let client = HomeAssistantClient()
        let input = HAConnectionInput(
            endpoint: HAEndpoint(primaryURL: server.baseURL, fallbackURL: nil),
            token: "fake-token"
        )

        XCTAssertEqual(await client.checkWebSocketConnection(input), .success(HAWebSocketCheck(haVersion: "fake-ha")))
        XCTAssertEqual(
            await client.webSocketStates(input),
            .success([
                EntityState(id: "sensor.office_temperature", name: "Office temperature", state: "21.4", unit: "°C")
            ])
        )
    }

    func test_t_rest_client_contract() async throws {
        let fixtures = FakeHAFixtures(
            apiBody: #"{"message":"API running."}"#,
            statesBody: #"[{"entity_id":"sensor.office_temperature","state":"21.4","attributes":{"friendly_name":"Office temperature","unit_of_measurement":"°C"}}]"#
        )
        let server = try FakeHARESTServer(fixtures: fixtures)
        server.start()
        defer {
            server.stop()
        }
        let client = HomeAssistantClient()
        let input = HAConnectionInput(
            endpoint: HAEndpoint(primaryURL: server.baseURL, fallbackURL: nil),
            token: "fake-token"
        )

        XCTAssertEqual(await client.checkRESTConnection(input), .success(HARESTCheck(message: "API running.")))
        XCTAssertEqual(
            await client.states(input),
            .success([
                EntityState(id: "sensor.office_temperature", name: "Office temperature", state: "21.4", unit: "°C")
            ])
        )
        XCTAssertEqual(
            await client.checkRESTConnection(
                HAConnectionInput(endpoint: input.endpoint, token: "wrong-token")
            ),
            .failure(.authentication)
        )
    }

    func test_t_discovery_grouping() async throws {
        let fixtures = FakeHAFixtures(
            apiBody: #"{"message":"API running."}"#,
            statesBody: """
            [
              {"entity_id":"sensor.kitchen_temperature","state":"21.4","attributes":{"friendly_name":"Kitchen temperature","unit_of_measurement":"°C"}},
              {"entity_id":"sensor.kitchen_humidity","state":"44","attributes":{"friendly_name":"Kitchen humidity","unit_of_measurement":"%"}},
              {"entity_id":"binary_sensor.kitchen_window","state":"off","attributes":{"friendly_name":"Kitchen window"}},
              {"entity_id":"light.kitchen_counter","state":"on","attributes":{"friendly_name":"Kitchen counter"}},
              {"entity_id":"sensor.living_temperature","state":"22.0","attributes":{"friendly_name":"Living temperature","unit_of_measurement":"°C"}},
              {"entity_id":"switch.living_lamp","state":"off","attributes":{"friendly_name":"Living lamp"}},
              {"entity_id":"media_player.living_speaker","state":"idle","attributes":{"friendly_name":"Living speaker"}},
              {"entity_id":"sensor.office_co2","state":"650","attributes":{"friendly_name":"Office CO2","unit_of_measurement":"ppm"}},
              {"entity_id":"binary_sensor.office_motion","state":"on","attributes":{"friendly_name":"Office motion"}},
              {"entity_id":"cover.office_blinds","state":"open","attributes":{"friendly_name":"Office blinds"}},
              {"entity_id":"sensor.loose_battery","state":"87","attributes":{"friendly_name":"Loose battery","unit_of_measurement":"%"}},
              {"entity_id":"sensor.registry_missing","state":"1","attributes":{"friendly_name":"Registry missing"}}
            ]
            """,
            areaRegistryBody: """
            [
              {"area_id":"kitchen","name":"Kitchen"},
              {"area_id":"living_room","name":"Living Room"},
              {"area_id":"office","name":"Office"}
            ]
            """,
            deviceRegistryBody: """
            [
              {"id":"kitchen_bridge","name":"Kitchen bridge","area_id":"kitchen"},
              {"id":"living_hub","name":"Living hub","area_id":"living_room"},
              {"id":"office_air","name":"Office air","area_id":"office"}
            ]
            """,
            entityRegistryBody: """
            [
              {"entity_id":"sensor.kitchen_temperature","name":"Kitchen temperature","area_id":"kitchen","device_id":"living_hub"},
              {"entity_id":"sensor.kitchen_humidity","name":"Kitchen humidity","device_id":"kitchen_bridge"},
              {"entity_id":"binary_sensor.kitchen_window","name":"Kitchen window","area_id":"kitchen"},
              {"entity_id":"light.kitchen_counter","name":"Kitchen counter","area_id":"kitchen"},
              {"entity_id":"sensor.living_temperature","name":"Living temperature","device_id":"living_hub"},
              {"entity_id":"switch.living_lamp","name":"Living lamp","area_id":"living_room"},
              {"entity_id":"media_player.living_speaker","name":"Living speaker","area_id":"living_room"},
              {"entity_id":"sensor.office_co2","name":"Office CO2","device_id":"office_air"},
              {"entity_id":"binary_sensor.office_motion","name":"Office motion","area_id":"office"},
              {"entity_id":"cover.office_blinds","name":"Office blinds","area_id":"office"},
              {"entity_id":"sensor.loose_battery","name":"Loose battery"}
            ]
            """
        )
        let server = try FakeHAWebSocketServer(fixtures: fixtures)
        server.start()
        defer {
            server.stop()
        }
        let client = HomeAssistantClient()
        let input = HAConnectionInput(
            endpoint: HAEndpoint(primaryURL: server.baseURL, fallbackURL: nil),
            token: "fake-token"
        )

        let result = await client.discovery(input)

        guard case let .success(snapshot) = result else {
            XCTFail("discovery unexpectedly failed: \(result)")
            return
        }
        let rooms = RoomResolver().resolve(snapshot: snapshot)
        XCTAssertEqual(snapshot.states.count, 12)
        XCTAssertEqual(rooms.map(\.name), ["Kitchen", "Living Room", "Office", "Unassigned"])
        XCTAssertEqual(
            rooms.first { $0.name == "Kitchen" }?.entities.map(\.id),
            ["sensor.kitchen_temperature", "sensor.kitchen_humidity", "binary_sensor.kitchen_window", "light.kitchen_counter"]
        )
        XCTAssertEqual(
            rooms.first { $0.name == "Living Room" }?.entities.map(\.id),
            ["sensor.living_temperature", "switch.living_lamp", "media_player.living_speaker"]
        )
        XCTAssertEqual(
            rooms.first { $0.name == "Office" }?.entities.map(\.id),
            ["sensor.office_co2", "binary_sensor.office_motion", "cover.office_blinds"]
        )
        XCTAssertEqual(
            rooms.first { $0.name == "Unassigned" }?.entities.map(\.id),
            ["sensor.loose_battery", "sensor.registry_missing"]
        )
    }

    func test_t_discovery_uses_entity_registry_display_list_when_supported() async throws {
        let fixtures = FakeHAFixtures(
            apiBody: #"{"message":"API running."}"#,
            statesBody: """
            [
              {"entity_id":"sensor.office_temperature","state":"21.4","attributes":{"friendly_name":"State name","unit_of_measurement":"°C"}}
            ]
            """,
            areaRegistryBody: #"[{"area_id":"office","name":"Office"}]"#,
            deviceRegistryBody: #"[]"#,
            entityRegistryDisplayBody: """
            {
              "entities": [
                {"ei":"sensor.office_temperature","en":"Display name","ai":"office"}
              ]
            }
            """,
            entityRegistryBody: """
            [
              {"entity_id":"sensor.office_temperature","name":"Full registry name","area_id":"office"}
            ]
            """
        )
        let server = try FakeHAWebSocketServer(fixtures: fixtures)
        server.start()
        defer {
            server.stop()
        }
        let client = HomeAssistantClient()
        let input = HAConnectionInput(
            endpoint: HAEndpoint(primaryURL: server.baseURL, fallbackURL: nil),
            token: "fake-token"
        )

        let result = await client.discovery(input)

        XCTAssertEqual(
            result,
            .success(
                DiscoverySnapshot(
                    areas: [Area(id: "office", name: "Office")],
                    devices: [],
                    entities: [EntityRegistryEntry(id: "sensor.office_temperature", name: "Display name", areaID: "office", deviceID: nil)],
                    states: [EntityState(id: "sensor.office_temperature", name: "State name", state: "21.4", unit: "°C")]
                )
            )
        )
        try await waitForJournalPath(server: server, path: "/api/websocket/config/entity_registry/list_for_display")
        let paths = await server.journal.snapshot().map(\.path)
        XCTAssertFalse(paths.contains("/api/websocket/config/entity_registry/list"))
    }

    func test_t_discovery_falls_back_to_full_entity_registry_when_display_list_is_unknown() async throws {
        let fixtures = FakeHAFixtures(
            apiBody: #"{"message":"API running."}"#,
            statesBody: """
            [
              {"entity_id":"sensor.office_temperature","state":"21.4","attributes":{"friendly_name":"State name","unit_of_measurement":"°C"}}
            ]
            """,
            areaRegistryBody: #"[{"area_id":"office","name":"Office"}]"#,
            deviceRegistryBody: #"[]"#,
            entityRegistryBody: """
            [
              {"entity_id":"sensor.office_temperature","name":"Full registry name","area_id":"office"}
            ]
            """
        )
        let server = try FakeHAWebSocketServer(fixtures: fixtures)
        server.start()
        defer {
            server.stop()
        }
        let client = HomeAssistantClient()
        let input = HAConnectionInput(
            endpoint: HAEndpoint(primaryURL: server.baseURL, fallbackURL: nil),
            token: "fake-token"
        )

        let result = await client.discovery(input)

        XCTAssertEqual(
            result,
            .success(
                DiscoverySnapshot(
                    areas: [Area(id: "office", name: "Office")],
                    devices: [],
                    entities: [EntityRegistryEntry(id: "sensor.office_temperature", name: "Full registry name", areaID: "office", deviceID: nil)],
                    states: [EntityState(id: "sensor.office_temperature", name: "State name", state: "21.4", unit: "°C")]
                )
            )
        )
        try await waitForJournalPath(server: server, path: "/api/websocket/config/entity_registry/list")
    }

    func test_t_discovery_falls_back_to_states_when_registry_commands_are_unknown() async throws {
        let fixtures = FakeHAFixtures(
            apiBody: #"{"message":"API running."}"#,
            statesBody: """
            [
              {"entity_id":"sensor.office_temperature","state":"21.4","attributes":{"friendly_name":"Office temperature","unit_of_measurement":"°C"}}
            ]
            """
        )
        let server = try FakeHAWebSocketServer(
            fixtures: fixtures,
            mode: .unavailableCommands([
                "config/area_registry/list",
                "config/device_registry/list",
                "config/entity_registry/list_for_display",
                "config/entity_registry/list"
            ], code: .unknownCommand)
        )
        server.start()
        defer {
            server.stop()
        }
        let client = HomeAssistantClient()
        let input = HAConnectionInput(
            endpoint: HAEndpoint(primaryURL: server.baseURL, fallbackURL: nil),
            token: "fake-token"
        )

        let result = await client.discovery(input)

        guard case let .success(snapshot) = result else {
            XCTFail("discovery unexpectedly failed: \(result)")
            return
        }
        XCTAssertEqual(snapshot.areas, [])
        XCTAssertEqual(snapshot.devices, [])
        XCTAssertEqual(snapshot.entities, [])
        XCTAssertEqual(snapshot.states, [
            EntityState(id: "sensor.office_temperature", name: "Office temperature", state: "21.4", unit: "°C")
        ])
        XCTAssertEqual(
            RoomResolver().resolve(snapshot: snapshot),
            [
                Room(
                    id: "unassigned",
                    name: "Unassigned",
                    entities: [
                        DiscoveredEntity(
                            id: "sensor.office_temperature",
                            name: "Office temperature",
                            state: "21.4",
                            unit: "°C",
                            areaID: nil,
                            deviceID: nil
                        )
                    ]
                )
            ]
        )
    }

    func testEnvironmentParsesLocalEnvFileShape() throws {
        let environment = try HAMirrorEnvironment.parse(
            """
            url=http://homeassistant.local:8123
            url2=https://example.ui.nabu.casa
            token='secret-token'
            user=owner
            password="secret-password"
            PERCHHA_OAUTH_CLIENT_ID=https://perchha.dev/app
            PERCHHA_OAUTH_REDIRECT_URI=perchha://auth
            """
        )

        XCTAssertEqual(environment.primaryURL.absoluteString, "http://homeassistant.local:8123")
        XCTAssertEqual(environment.fallbackURL?.absoluteString, "https://example.ui.nabu.casa")
        XCTAssertEqual(environment.token, "secret-token")
        XCTAssertEqual(environment.user, "owner")
        XCTAssertEqual(environment.password, "secret-password")
        XCTAssertEqual(environment.oauthClientID, "https://perchha.dev/app")
        XCTAssertEqual(environment.oauthRedirectURI, "perchha://auth")
    }

    func testEnvironmentAcceptsBareHostURLAsHTTP() throws {
        let environment = try HAMirrorEnvironment.parse(
            """
            url=homeassistant.local:8123
            url2=backup.local:8123/ha
            token=secret-token
            """
        )

        XCTAssertEqual(environment.primaryURL.absoluteString, "http://homeassistant.local:8123")
        XCTAssertEqual(environment.fallbackURL?.absoluteString, "http://backup.local:8123/ha")
    }

    func testMirrorEnvironmentFromEnvironmentLoadsExplicitEnvironmentFileAndOverridesExportedValues() throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("perchha-client-test-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: directory)
        }
        let fileURL = directory.appendingPathComponent("mirror.env", isDirectory: false)
        try """
        url=http://file.homeassistant.local:8123
        url2=https://file.ui.nabu.casa
        token=file-token
        user=file-user
        password=file-password
        PERCHHA_OAUTH_CLIENT_ID=https://file.perchha.dev/app
        PERCHHA_OAUTH_REDIRECT_URI=perchha-file://auth
        """.write(to: fileURL, atomically: true, encoding: .utf8)

        let environment = try HAMirrorEnvironment.fromEnvironment([
            HAMirrorEnvironment.environmentFileEnvironmentKey: fileURL.path,
            HAMirrorEnvironment.tokenEnvironmentKey: "exported-token",
            HAMirrorEnvironment.oauthClientIDEnvironmentKey: "https://exported.perchha.dev/app",
            HAMirrorEnvironment.oauthRedirectURIEnvironmentKey: "perchha-exported://auth"
        ])

        XCTAssertEqual(environment.primaryURL.absoluteString, "http://file.homeassistant.local:8123")
        XCTAssertEqual(environment.fallbackURL?.absoluteString, "https://file.ui.nabu.casa")
        XCTAssertEqual(environment.token, "exported-token")
        XCTAssertEqual(environment.user, "file-user")
        XCTAssertEqual(environment.password, "file-password")
        XCTAssertEqual(environment.oauthClientID, "https://exported.perchha.dev/app")
        XCTAssertEqual(environment.oauthRedirectURI, "perchha-exported://auth")
    }

    func testMirrorEnvironmentFromEnvironmentOverridesMalformedExplicitEnvironmentFileWhenURLIsExported() throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("perchha-client-test-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: directory)
        }
        let fileURL = directory.appendingPathComponent("mirror.env", isDirectory: false)
        try """
        PERCHHA_OAUTH_CLIENT_ID
        """.write(to: fileURL, atomically: true, encoding: .utf8)

        let environment = try HAMirrorEnvironment.fromEnvironment([
            HAMirrorEnvironment.environmentFileEnvironmentKey: fileURL.path,
            HAMirrorEnvironment.primaryURLEnvironmentKey: "homeassistant.local:8123",
            HAMirrorEnvironment.tokenEnvironmentKey: "exported-token"
        ])

        XCTAssertEqual(environment.primaryURL.absoluteString, "http://homeassistant.local:8123")
        XCTAssertNil(environment.fallbackURL)
        XCTAssertEqual(environment.token, "exported-token")
    }

    func testMirrorEnvironmentFromEnvironmentRejectsMissingExplicitEnvironmentFileWithoutExportedURL() {
        XCTAssertThrowsError(
            try HAMirrorEnvironment.fromEnvironment([
                HAMirrorEnvironment.environmentFileEnvironmentKey: "/tmp/perchha-client-tests/missing.env"
            ])
        ) { error in
            XCTAssertEqual(
                error as? HAMirrorEnvironmentError,
                .missingFile("/tmp/perchha-client-tests/missing.env")
            )
        }
    }

    func testMirrorEnvironmentReadinessReportsMissingTokenWithoutCredentialValues() throws {
        let environment = try HAMirrorEnvironment.parse(
            """
            url=http://homeassistant.local:8123
            user=owner@example.invalid
            password=secret-password
            """
        )

        let report = environment.readinessReport

        XCTAssertFalse(report.canCaptureMirror)
        XCTAssertFalse(report.canCheckOAuthClientWebsite)
        XCTAssertEqual(
            report.issues,
            [
                .missingCaptureToken,
                .usernamePasswordNotCaptureCredentials
            ]
        )
        XCTAssertEqual(
            report.nextSteps(envPath: ".env.local"),
            [
                "Set token= in .env.local or export PERCHHA_HA_TOKEN to a Home Assistant bearer access token before mirror capture. A long-lived access token works, or use the native OAuth sign-in flow and copy the resulting access token.",
                "user/password alone cannot authenticate the REST or WebSocket APIs. Keep them only for browser sign-in or manual work; mirror capture still needs token= in .env.local or PERCHHA_HA_TOKEN in the process environment.",
                "If you want native OAuth sign-in instead of a long-lived token, set both PERCHHA_OAUTH_CLIENT_ID and PERCHHA_OAUTH_REDIRECT_URI in .env.local, or export both values, then run hamirror oauth-check --env .env.local."
            ]
        )
        let issueText = report.issues.map(\.description).joined(separator: "\n")
        XCTAssertFalse(issueText.contains("owner@example.invalid"))
        XCTAssertFalse(issueText.contains("secret-password"))
    }

    func testMirrorEnvironmentReadinessReportsCaptureAndOAuthReadiness() throws {
        let environment = try HAMirrorEnvironment.parse(
            """
            url=http://homeassistant.local:8123
            url2=https://example.ui.nabu.casa
            token=secret-token
            PERCHHA_OAUTH_CLIENT_ID=https://perchha.dev/app
            PERCHHA_OAUTH_REDIRECT_URI=perchha://auth
            """
        )

        let report = environment.readinessReport

        XCTAssertTrue(report.hasFallbackURL)
        XCTAssertTrue(report.hasToken)
        XCTAssertTrue(report.hasOAuthClientID)
        XCTAssertTrue(report.hasOAuthRedirectURI)
        XCTAssertTrue(report.canCaptureMirror)
        XCTAssertTrue(report.canCheckOAuthClientWebsite)
        XCTAssertEqual(report.issues, [])
        XCTAssertEqual(
            report.suggestedCommands(envPath: ".env.local"),
            [
                "swift run hamirror capture --env .env.local --output Fixtures/private/m8-real --websocket --write",
                "swift run hamirror oauth-check --env .env.local"
            ]
        )
    }

    func testMirrorEnvironmentReadinessReportsOAuthReadyWhileCaptureBlocked() throws {
        let environment = try HAMirrorEnvironment.parse(
            """
            url=http://homeassistant.local:8123
            PERCHHA_OAUTH_CLIENT_ID=https://perchha.dev/app
            PERCHHA_OAUTH_REDIRECT_URI=perchha://auth
            """
        )

        let report = environment.readinessReport

        XCTAssertFalse(report.canCaptureMirror)
        XCTAssertTrue(report.canCheckOAuthClientWebsite)
        XCTAssertEqual(report.issues, [.missingCaptureToken])
        XCTAssertEqual(
            report.nextSteps(envPath: ".env.local"),
            [
                "Set token= in .env.local or export PERCHHA_HA_TOKEN to a Home Assistant bearer access token before mirror capture. A long-lived access token works, or use the native OAuth sign-in flow and copy the resulting access token."
            ]
        )
        XCTAssertEqual(
            report.suggestedCommands(envPath: ".env.local"),
            [
                "swift run hamirror oauth-check --env .env.local"
            ]
        )
    }

    func testMirrorEnvironmentSuggestedCommandsShellQuoteEnvPath() throws {
        let environment = try HAMirrorEnvironment.parse(
            """
            url=http://homeassistant.local:8123
            token=secret-token
            PERCHHA_OAUTH_CLIENT_ID=https://perchha.dev/app
            PERCHHA_OAUTH_REDIRECT_URI=perchha://auth
            """
        )

        XCTAssertEqual(
            environment.readinessReport.suggestedCommands(envPath: "/tmp/My Project/owner's env.local"),
            [
                "swift run hamirror capture --env '/tmp/My Project/owner'\"'\"'s env.local' --output Fixtures/private/m8-real --websocket --write",
                "swift run hamirror oauth-check --env '/tmp/My Project/owner'\"'\"'s env.local'"
            ]
        )
    }

    func testMirrorEnvironmentReadinessDiagnosticIsScriptableAndRedacted() throws {
        let environment = try HAMirrorEnvironment.parse(
            """
            url=http://homeassistant.local:8123
            url2=https://example.ui.nabu.casa
            user=owner@example.invalid
            password=secret-password
            PERCHHA_OAUTH_CLIENT_ID=https://perchha.dev/app
            """
        )

        let diagnostic = environment.readinessReport.diagnostic(envPath: ".env.local")
        let data = try JSONEncoder().encode(diagnostic)
        let decoded = try JSONDecoder().decode(HAMirrorEnvironmentReadinessDiagnostic.self, from: data)
        let text = String(decoding: data, as: UTF8.self)

        XCTAssertEqual(decoded.envPath, ".env.local")
        XCTAssertEqual(decoded.url, .present)
        XCTAssertEqual(decoded.url2, .present)
        XCTAssertEqual(decoded.token, .missing)
        XCTAssertEqual(decoded.user, .present)
        XCTAssertEqual(decoded.password, .present)
        XCTAssertEqual(decoded.oauthClientID, .present)
        XCTAssertEqual(decoded.oauthRedirectURI, .missing)
        XCTAssertEqual(decoded.capture, .blocked)
        XCTAssertEqual(decoded.oauthCheck, .blocked)
        XCTAssertEqual(
            decoded.issues.map(\.code),
            [
                .missingCaptureToken,
                .usernamePasswordNotCaptureCredentials,
                .incompleteOAuthClientWebsiteConfiguration
            ]
        )
        XCTAssertEqual(
            decoded.nextSteps,
            [
                "Set token= in .env.local or export PERCHHA_HA_TOKEN to a Home Assistant bearer access token before mirror capture. A long-lived access token works, or use the native OAuth sign-in flow and copy the resulting access token.",
                "user/password alone cannot authenticate the REST or WebSocket APIs. Keep them only for browser sign-in or manual work; mirror capture still needs token= in .env.local or PERCHHA_HA_TOKEN in the process environment.",
                "Set both PERCHHA_OAUTH_CLIENT_ID and PERCHHA_OAUTH_REDIRECT_URI in .env.local, or export both values, then rerun hamirror oauth-check --env .env.local."
            ]
        )
        XCTAssertEqual(decoded.suggestedCommands, [])
        XCTAssertFalse(text.contains("owner@example.invalid"))
        XCTAssertFalse(text.contains("secret-password"))
        XCTAssertFalse(text.contains("https://perchha.dev/app"))
    }

    func testMirrorEnvironmentReadinessReportsIncompleteOAuthConfiguration() throws {
        let environment = try HAMirrorEnvironment.parse(
            """
            url=http://homeassistant.local:8123
            token=secret-token
            PERCHHA_OAUTH_CLIENT_ID=https://perchha.dev/app
            """
        )

        let report = environment.readinessReport

        XCTAssertTrue(report.canCaptureMirror)
        XCTAssertFalse(report.canCheckOAuthClientWebsite)
        XCTAssertEqual(report.issues, [.incompleteOAuthClientWebsiteConfiguration])
        XCTAssertEqual(
            report.nextSteps(envPath: ".env.local"),
            [
                "Set both PERCHHA_OAUTH_CLIENT_ID and PERCHHA_OAUTH_REDIRECT_URI in .env.local, or export both values, then rerun hamirror oauth-check --env .env.local."
            ]
        )
        XCTAssertEqual(
            report.suggestedCommands(envPath: ".env.local"),
            [
                "swift run hamirror capture --env .env.local --output Fixtures/private/m8-real --websocket --write"
            ]
        )
    }

    func testMirrorEnvironmentOAuthCheckBlockingMessagesOnlyReportOAuthReadiness() throws {
        let environment = try HAMirrorEnvironment.parse(
            """
            url=http://homeassistant.local:8123
            user=owner@example.invalid
            password=secret-password
            """
        )

        XCTAssertEqual(
            environment.readinessReport.oauthCheckBlockingMessages(envPath: ".env.local"),
            [
                "OAuth client website check requires PERCHHA_OAUTH_CLIENT_ID and PERCHHA_OAUTH_REDIRECT_URI",
                "If you want native OAuth sign-in instead of a long-lived token, set both PERCHHA_OAUTH_CLIENT_ID and PERCHHA_OAUTH_REDIRECT_URI in .env.local, or export both values, then run hamirror oauth-check --env .env.local."
            ]
        )
    }

    func testMirrorEnvironmentOAuthCheckBlockingMessagesExplainIncompleteOAuthConfiguration() throws {
        let environment = try HAMirrorEnvironment.parse(
            """
            url=http://homeassistant.local:8123
            PERCHHA_OAUTH_CLIENT_ID=https://perchha.dev/app
            """
        )

        XCTAssertEqual(
            environment.readinessReport.oauthCheckBlockingMessages(envPath: ".env.local"),
            [
                "OAuth client website check requires PERCHHA_OAUTH_CLIENT_ID and PERCHHA_OAUTH_REDIRECT_URI",
                "Set both PERCHHA_OAUTH_CLIENT_ID and PERCHHA_OAUTH_REDIRECT_URI in .env.local, or export both values, then rerun hamirror oauth-check --env .env.local."
            ]
        )
    }

    func testMirrorEnvironmentReadinessNextStepsShellQuoteEnvPathCommands() throws {
        let environment = try HAMirrorEnvironment.parse(
            """
            url=http://homeassistant.local:8123
            PERCHHA_OAUTH_CLIENT_ID=https://perchha.dev/app
            """
        )

        XCTAssertEqual(
            environment.readinessReport.nextSteps(envPath: "/tmp/My Project/owner's env.local"),
            [
                "Set token= in /tmp/My Project/owner's env.local or export PERCHHA_HA_TOKEN to a Home Assistant bearer access token before mirror capture. A long-lived access token works, or use the native OAuth sign-in flow and copy the resulting access token.",
                "Set both PERCHHA_OAUTH_CLIENT_ID and PERCHHA_OAUTH_REDIRECT_URI in /tmp/My Project/owner's env.local, or export both values, then rerun hamirror oauth-check --env '/tmp/My Project/owner'\"'\"'s env.local'."
            ]
        )
    }

    func testOAuthClientWebsiteEnvironmentParsesOAuthOnlyEnvFile() throws {
        let environment = try HAOAuthClientWebsiteEnvironment.parse(
            """
            PERCHHA_OAUTH_CLIENT_ID=https://perchha.dev/app
            PERCHHA_OAUTH_REDIRECT_URI=perchha://auth
            """
        )

        XCTAssertEqual(environment.clientID, "https://perchha.dev/app")
        XCTAssertEqual(environment.redirectURI, "perchha://auth")
    }

    func testOAuthClientWebsiteEnvironmentFromEnvironmentLoadsExplicitEnvironmentFile() throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("perchha-client-test-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: directory)
        }
        let fileURL = directory.appendingPathComponent("oauth.env", isDirectory: false)
        try """
        PERCHHA_OAUTH_CLIENT_ID=https://file.perchha.dev/app
        PERCHHA_OAUTH_REDIRECT_URI=perchha-file://auth
        """.write(to: fileURL, atomically: true, encoding: .utf8)

        let environment = try HAOAuthClientWebsiteEnvironment.fromEnvironment([
            HAMirrorEnvironment.environmentFileEnvironmentKey: fileURL.path
        ])

        XCTAssertEqual(environment.clientID, "https://file.perchha.dev/app")
        XCTAssertEqual(environment.redirectURI, "perchha-file://auth")
    }

    func testOAuthClientWebsiteEnvironmentFromEnvironmentOverridesMissingExplicitEnvironmentFile() throws {
        let environment = try HAOAuthClientWebsiteEnvironment.fromEnvironment([
            HAMirrorEnvironment.environmentFileEnvironmentKey: "/tmp/perchha-client-tests/missing-oauth.env",
            HAMirrorEnvironment.oauthClientIDEnvironmentKey: "https://exported.perchha.dev/app",
            HAMirrorEnvironment.oauthRedirectURIEnvironmentKey: "perchha-exported://auth"
        ])

        XCTAssertEqual(environment.clientID, "https://exported.perchha.dev/app")
        XCTAssertEqual(environment.redirectURI, "perchha-exported://auth")
    }

    func testOAuthClientWebsiteEnvironmentRejectsMissingOAuthKeys() {
        XCTAssertThrowsError(
            try HAOAuthClientWebsiteEnvironment.parse(
                """
                PERCHHA_OAUTH_REDIRECT_URI=perchha://auth
                """
            )
        ) { error in
            XCTAssertEqual(error as? HAMirrorEnvironmentError, .missingOAuthClientID)
        }
        XCTAssertThrowsError(
            try HAOAuthClientWebsiteEnvironment.parse(
                """
                PERCHHA_OAUTH_CLIENT_ID=https://perchha.dev/app
                """
            )
        ) { error in
            XCTAssertEqual(error as? HAMirrorEnvironmentError, .missingOAuthRedirectURI)
        }
    }

    func testEnvironmentRejectsHostlessURL() {
        XCTAssertThrowsError(
            try HAMirrorEnvironment.parse(
                """
                url=file:///tmp/home-assistant
                token=secret-token
                """
            )
        ) { error in
            XCTAssertEqual(error as? HAMirrorEnvironmentError, .invalidURL("file:///tmp/home-assistant"))
        }
    }

    func testMirrorCapturePreservesTrailingSlashAPIPath() async throws {
        let transport = RecordingMirrorTransport()
        let service = HAMirrorCaptureService(transport: transport)
        let environment = HAMirrorEnvironment(
            primaryURL: try XCTUnwrap(URL(string: "http://127.0.0.1:8123")),
            fallbackURL: nil,
            token: "secret-token",
            user: nil,
            password: nil
        )

        _ = try await service.capture(environment: environment)

        let requests = await transport.requests
        XCTAssertEqual(requests.map { $0.url.path }, ["/api/", "/api/states"])
    }

    func testMirrorCapturePreservesBasePathPrefix() async throws {
        let transport = RecordingMirrorTransport()
        let service = HAMirrorCaptureService(transport: transport)
        let environment = HAMirrorEnvironment(
            primaryURL: try XCTUnwrap(URL(string: "http://127.0.0.1:8123/ha")),
            fallbackURL: nil,
            token: "secret-token",
            user: nil,
            password: nil
        )

        _ = try await service.capture(environment: environment)

        let requests = await transport.requests
        XCTAssertEqual(requests.map { $0.url.path }, ["/ha/api/", "/ha/api/states"])
    }

    func test_t_mirror_redaction() async throws {
        let transport = RecordingMirrorTransport(
            apiBody: #"{"message":"API running.","token":"secret"}"#,
            statesBody: #"[{"entity_id":"sensor.one","state":"1","attributes":{"token":"secret"}}]"#
        )
        let service = HAMirrorCaptureService(transport: transport)
        let environment = HAMirrorEnvironment(
            primaryURL: try XCTUnwrap(URL(string: "http://127.0.0.1:8123")),
            fallbackURL: nil,
            token: "secret-token",
            user: nil,
            password: nil
        )

        let fixtures = try await service.capture(environment: environment)

        XCTAssertFalse(fixtures.api.bodyText.contains("secret"))
        XCTAssertFalse(fixtures.states.bodyText.contains("secret"))

        let requests = await transport.requests
        XCTAssertEqual(requests.first?.headers["Authorization"], "Bearer secret-token")
    }

    func testMirrorCaptureRecordsOptimizedWebSocketEvidence() async throws {
        let fixtures = FakeHAFixtures(
            apiBody: #"{"message":"API running."}"#,
            statesBody: #"[]"#,
            stateChangedEventBody: #"{"entity_id":"sensor.office_temperature","state":"22.0","attributes":{"friendly_name":"Office temperature","unit_of_measurement":"°C"}}"#,
            entityRegistryDisplayBody: """
            {
              "entities": [
                {"ei":"sensor.office_temperature","en":"Office temperature","ai":"office"}
              ]
            }
            """
        )
        let server = try FakeHAWebSocketServer(fixtures: fixtures)
        server.start()
        defer {
            server.stop()
        }
        let environment = HAMirrorEnvironment(
            primaryURL: server.baseURL,
            fallbackURL: nil,
            token: "fake-token",
            user: nil,
            password: nil
        )

        let evidence = try await HAMirrorCaptureService().captureOptimizedWebSocketEvidence(
            environment: environment,
            captureSubscribeEventKeys: true
        )

        XCTAssertEqual(
            evidence.entityRegistryDisplayList,
            HAMirrorWebSocketCommandEvidence(
                command: "config/entity_registry/list_for_display",
                available: true,
                errorCode: nil,
                errorMessage: nil
            )
        )
        XCTAssertEqual(evidence.subscribeEntities.command, "subscribe_entities")
        XCTAssertTrue(evidence.subscribeEntities.available)
        XCTAssertEqual(evidence.subscribeEntities.eventKeys, ["a"])
    }

    func testMirrorWebSocketEvidenceCaptureTimesOutWhenServerStopsResponding() async throws {
        let server = try FakeHAWebSocketServer(mode: .silentAfterAuth)
        server.start()
        defer {
            server.stop()
        }
        let service = HAMirrorCaptureService(webSocketReceiveTimeoutNanoseconds: 50_000_000)
        let environment = HAMirrorEnvironment(
            primaryURL: server.baseURL,
            fallbackURL: nil,
            token: "fake-token",
            user: nil,
            password: nil
        )

        do {
            _ = try await service.captureOptimizedWebSocketEvidence(environment: environment)
            XCTFail("capture unexpectedly succeeded against a silent WebSocket")
        } catch let error as HAMirrorCaptureError {
            XCTAssertEqual(error, .webSocketTimeout)
        }
    }

    func testMirrorCaptureSanitizesPrivateStatePayload() async throws {
        let transport = RecordingMirrorTransport(
            statesBody: """
            [{
              "entity_id": "sensor.kitchen_temperature",
              "state": "21.4",
              "attributes": {
                "friendly_name": "Kitchen temperature",
                "unit_of_measurement": "°C",
                "device_class": "temperature",
                "latitude": 52.52,
                "longitude": 13.405,
                "postcode": 10115,
                "elevation": 44.5,
                "distance": [1, 2, 3],
                "note": "door beside bedroom"
              },
              "last_changed": "2026-06-27T09:00:00+00:00",
              "last_updated": "2026-06-27T09:01:00+00:00"
            }]
            """
        )
        let service = HAMirrorCaptureService(transport: transport)
        let environment = HAMirrorEnvironment(
            primaryURL: try XCTUnwrap(URL(string: "http://127.0.0.1:8123")),
            fallbackURL: nil,
            token: "secret-token",
            user: nil,
            password: nil
        )

        let fixtures = try await service.capture(environment: environment)

        XCTAssertTrue(fixtures.states.bodyText.contains("sensor.entity_001"))
        XCTAssertTrue(fixtures.states.bodyText.contains("unit_of_measurement"))
        XCTAssertTrue(fixtures.states.bodyText.contains("device_class"))
        XCTAssertFalse(fixtures.states.bodyText.contains("kitchen"))
        XCTAssertFalse(fixtures.states.bodyText.contains("Kitchen"))
        XCTAssertFalse(fixtures.states.bodyText.contains("52.52"))
        XCTAssertFalse(fixtures.states.bodyText.contains("13.405"))
        XCTAssertFalse(fixtures.states.bodyText.contains("10115"))
        XCTAssertFalse(fixtures.states.bodyText.contains("44.5"))
        XCTAssertFalse(fixtures.states.bodyText.contains("[1,2,3]"))
        XCTAssertFalse(fixtures.states.bodyText.contains("bedroom"))
        XCTAssertFalse(fixtures.states.bodyText.contains("2026-06-27T09"))
    }

    func testMirrorCaptureRejectsUnexpectedStatusWithoutCapturingBody() async throws {
        let transport = RecordingMirrorTransport(
            apiStatusCode: 401,
            apiBody: #"{"message":"Unauthorized","token":"secret"}"#
        )
        let service = HAMirrorCaptureService(transport: transport)
        let environment = HAMirrorEnvironment(
            primaryURL: try XCTUnwrap(URL(string: "http://127.0.0.1:8123")),
            fallbackURL: nil,
            token: "secret-token",
            user: nil,
            password: nil
        )

        do {
            _ = try await service.capture(environment: environment)
            XCTFail("capture unexpectedly accepted an unauthorized response")
        } catch let error as HAMirrorCaptureError {
            XCTAssertEqual(error, .unexpectedStatus(path: "/api/", statusCode: 401))
            XCTAssertFalse(error.description.contains("secret"))
        }

        let requests = await transport.requests
        XCTAssertEqual(requests.map { $0.url.path }, ["/api/"])
    }

    func testMirrorCaptureFallsBackToConfiguredFallbackURLOnPrimaryTransportFailure() async throws {
        let transport = RecordingMirrorTransport { request in
            if request.url.host == "primary.local" {
                throw RecordingMirrorTransportError(message: "connection refused")
            }
            return HAMirrorResponse(
                statusCode: 200,
                headers: ["Authorization": "Bearer should-redact"],
                body: Data((request.url.path == "/api/" ? #"{"message":"API running."}"# : #"[]"#).utf8)
            )
        }
        let service = HAMirrorCaptureService(transport: transport)
        let environment = HAMirrorEnvironment(
            primaryURL: try XCTUnwrap(URL(string: "http://primary.local:8123")),
            fallbackURL: try XCTUnwrap(URL(string: "https://fallback.example")),
            token: "secret-token",
            user: nil,
            password: nil
        )

        let fixtures = try await service.capture(environment: environment)

        XCTAssertEqual(fixtures.api.statusCode, 200)
        let requests = await transport.requests
        XCTAssertEqual(
            requests.map { ($0.url.host ?? "", $0.url.path) },
            [
                ("primary.local", "/api/"),
                ("fallback.example", "/api/"),
                ("fallback.example", "/api/states")
            ]
        )
    }

    func testMirrorCaptureReportsSanitizedPrimaryAndFallbackFailures() async throws {
        let transport = RecordingMirrorTransport { request in
            if request.url.host == "primary.local" {
                throw RecordingMirrorTransportError(message: "connection refused")
            }
            return HAMirrorResponse(
                statusCode: 401,
                headers: ["Authorization": "Bearer should-redact"],
                body: Data(#"{"message":"Unauthorized","token":"secret"}"#.utf8)
            )
        }
        let service = HAMirrorCaptureService(transport: transport)
        let environment = HAMirrorEnvironment(
            primaryURL: try XCTUnwrap(URL(string: "http://primary.local:8123")),
            fallbackURL: try XCTUnwrap(URL(string: "https://fallback.example")),
            token: "secret-token",
            user: nil,
            password: nil
        )

        do {
            _ = try await service.capture(environment: environment)
            XCTFail("capture unexpectedly succeeded when both base URLs failed")
        } catch let error as HAMirrorCaptureError {
            XCTAssertEqual(
                error,
                .primaryAndFallbackFailed(
                    path: "/api/",
                    primaryFailure: "Home Assistant request for /api/ failed: connection refused",
                    fallbackFailure: "Home Assistant returned HTTP 401 for /api/"
                )
            )
            XCTAssertFalse(error.description.contains("fallback.example"))
            XCTAssertFalse(error.description.contains("primary.local"))
            XCTAssertFalse(error.description.contains("secret"))
        }
    }

    func testFixtureWriterWritesManifestAndEndpoints() throws {
        let fixtureSet = HAMirrorFixtureSet(
            api: HAMirrorCapturedEndpoint(method: "GET", path: "/api/", statusCode: 200, headers: [:], bodyText: "{}"),
            states: HAMirrorCapturedEndpoint(method: "GET", path: "/api/states", statusCode: 200, headers: [:], bodyText: "[]")
        )
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("perchha-client-test-\(UUID().uuidString)", isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: directory)
        }

        let written = try HAMirrorFixtureWriter().write(fixtureSet, to: directory)

        XCTAssertEqual(written.map { $0.lastPathComponent }, ["api.json", "manifest.json", "states.json"])
        XCTAssertTrue(FileManager.default.fileExists(atPath: directory.appendingPathComponent("api.json").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: directory.appendingPathComponent("states.json").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: directory.appendingPathComponent("manifest.json").path))
    }

    func testFixtureWriterWritesWebSocketEvidenceWhenPresent() throws {
        let fixtureSet = HAMirrorFixtureSet(
            api: HAMirrorCapturedEndpoint(method: "GET", path: "/api/", statusCode: 200, headers: [:], bodyText: "{}"),
            states: HAMirrorCapturedEndpoint(method: "GET", path: "/api/states", statusCode: 200, headers: [:], bodyText: "[]"),
            webSocket: HAMirrorWebSocketEvidence(
                entityRegistryDisplayList: HAMirrorWebSocketCommandEvidence(
                    command: "config/entity_registry/list_for_display",
                    available: true,
                    errorCode: nil,
                    errorMessage: nil
                ),
                subscribeEntities: HAMirrorWebSocketCommandEvidence(
                    command: "subscribe_entities",
                    available: true,
                    errorCode: nil,
                    errorMessage: nil,
                    eventKeys: ["a"]
                )
            )
        )
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("perchha-client-test-\(UUID().uuidString)", isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: directory)
        }

        let written = try HAMirrorFixtureWriter().write(fixtureSet, to: directory)

        XCTAssertEqual(written.map { $0.lastPathComponent }, ["api.json", "manifest.json", "states.json", "websocket.json"])
        XCTAssertTrue(FileManager.default.fileExists(atPath: directory.appendingPathComponent("websocket.json").path))
    }

    func testFixtureWriterRemovesStaleWebSocketEvidenceWhenWritingRestOnlyFixtures() throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("perchha-client-test-\(UUID().uuidString)", isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: directory)
        }
        let writer = HAMirrorFixtureWriter()
        let withWebSocket = HAMirrorFixtureSet(
            api: HAMirrorCapturedEndpoint(method: "GET", path: "/api/", statusCode: 200, headers: [:], bodyText: "{}"),
            states: HAMirrorCapturedEndpoint(method: "GET", path: "/api/states", statusCode: 200, headers: [:], bodyText: "[]"),
            webSocket: HAMirrorWebSocketEvidence(
                entityRegistryDisplayList: HAMirrorWebSocketCommandEvidence(
                    command: "config/entity_registry/list_for_display",
                    available: true,
                    errorCode: nil,
                    errorMessage: nil
                ),
                subscribeEntities: HAMirrorWebSocketCommandEvidence(
                    command: "subscribe_entities",
                    available: true,
                    errorCode: nil,
                    errorMessage: nil
                )
            )
        )
        let restOnly = HAMirrorFixtureSet(
            api: withWebSocket.api,
            states: withWebSocket.states
        )

        _ = try writer.write(withWebSocket, to: directory)
        XCTAssertTrue(FileManager.default.fileExists(atPath: directory.appendingPathComponent("websocket.json").path))

        _ = try writer.write(restOnly, to: directory)

        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.appendingPathComponent("websocket.json").path))
    }

    func testMirrorFixtureOutputPolicyRequiresIgnoredVerificationForPrivateFixtureDirectory() {
        XCTAssertTrue(
            HAMirrorFixtureOutputPolicy.requiresIgnoredDirectoryVerification(
                URL(fileURLWithPath: "Fixtures/private/m8-real", isDirectory: true)
            )
        )
        XCTAssertTrue(
            HAMirrorFixtureOutputPolicy.requiresIgnoredDirectoryVerification(
                URL(fileURLWithPath: "/tmp/Repo/Fixtures/private/m8-real", isDirectory: true)
            )
        )
        XCTAssertFalse(
            HAMirrorFixtureOutputPolicy.requiresIgnoredDirectoryVerification(
                URL(fileURLWithPath: "Fixtures/public/m2-minimal", isDirectory: true)
            )
        )
    }

    func testFixtureVerifierAcceptsCompleteSanitizedFixtureSet() throws {
        let fixtureSet = HAMirrorFixtureSet(
            api: HAMirrorCapturedEndpoint(method: "GET", path: "/api/", statusCode: 200, headers: [:], bodyText: #"{"message":"API running."}"#),
            states: HAMirrorCapturedEndpoint(
                method: "GET",
                path: "/api/states",
                statusCode: 200,
                headers: [:],
                bodyText: #"[{"attributes":{"friendly_name":"<redacted>","unit_of_measurement":"°C"},"entity_id":"sensor.entity_001","last_changed":"2026-01-01T00:00:00+00:00","state":"21.4"}]"#
            )
        )
        let directory = try writeFixtureSet(fixtureSet)
        defer {
            try? FileManager.default.removeItem(at: directory)
        }

        XCTAssertEqual(try HAMirrorFixtureVerifier().verify(directory: directory), fixtureSet)
    }

    func testFixtureVerifierAcceptsWebSocketEvidence() throws {
        let fixtureSet = HAMirrorFixtureSet(
            api: HAMirrorCapturedEndpoint(method: "GET", path: "/api/", statusCode: 200, headers: [:], bodyText: #"{"message":"API running."}"#),
            states: HAMirrorCapturedEndpoint(method: "GET", path: "/api/states", statusCode: 200, headers: [:], bodyText: "[]"),
            webSocket: HAMirrorWebSocketEvidence(
                entityRegistryDisplayList: HAMirrorWebSocketCommandEvidence(
                    command: "config/entity_registry/list_for_display",
                    available: true,
                    errorCode: nil,
                    errorMessage: nil
                ),
                subscribeEntities: HAMirrorWebSocketCommandEvidence(
                    command: "subscribe_entities",
                    available: true,
                    errorCode: nil,
                    errorMessage: nil,
                    eventKeys: ["a"]
                )
            )
        )
        let directory = try writeFixtureSet(fixtureSet)
        defer {
            try? FileManager.default.removeItem(at: directory)
        }

        XCTAssertEqual(try HAMirrorFixtureVerifier().verify(directory: directory), fixtureSet)
    }

    func testFixtureVerifierRejectsWebSocketFileWithoutManifestEvidence() throws {
        let fixtureSet = HAMirrorFixtureSet(
            api: HAMirrorCapturedEndpoint(method: "GET", path: "/api/", statusCode: 200, headers: [:], bodyText: #"{"message":"API running."}"#),
            states: HAMirrorCapturedEndpoint(method: "GET", path: "/api/states", statusCode: 200, headers: [:], bodyText: "[]")
        )
        let directory = try writeFixtureSet(fixtureSet)
        defer {
            try? FileManager.default.removeItem(at: directory)
        }
        try #"{"private_payload":{"entity_id":"sensor.office_temperature"}}"#
            .write(to: directory.appendingPathComponent("websocket.json"), atomically: true, encoding: .utf8)

        XCTAssertThrowsError(try HAMirrorFixtureVerifier().verify(directory: directory)) { error in
            guard case .invalidWebSocketEvidence = error as? HAMirrorFixtureVerificationError else {
                XCTFail("unexpected error: \(error)")
                return
            }
        }
    }

    func testFixtureVerifierRejectsUnknownWebSocketEvidenceFields() throws {
        let fixtureSet = HAMirrorFixtureSet(
            api: HAMirrorCapturedEndpoint(method: "GET", path: "/api/", statusCode: 200, headers: [:], bodyText: #"{"message":"API running."}"#),
            states: HAMirrorCapturedEndpoint(method: "GET", path: "/api/states", statusCode: 200, headers: [:], bodyText: "[]"),
            webSocket: HAMirrorWebSocketEvidence(
                entityRegistryDisplayList: HAMirrorWebSocketCommandEvidence(
                    command: "config/entity_registry/list_for_display",
                    available: true,
                    errorCode: nil,
                    errorMessage: nil
                ),
                subscribeEntities: HAMirrorWebSocketCommandEvidence(
                    command: "subscribe_entities",
                    available: true,
                    errorCode: nil,
                    errorMessage: nil
                )
            )
        )
        let directory = try writeFixtureSet(fixtureSet)
        defer {
            try? FileManager.default.removeItem(at: directory)
        }
        let privateWebSocket = """
        {
          "entityRegistryDisplayList": {
            "command": "config/entity_registry/list_for_display",
            "available": true,
            "eventKeys": [],
            "result": {"entity_id": "sensor.office_temperature"}
          },
          "subscribeEntities": {
            "command": "subscribe_entities",
            "available": true,
            "eventKeys": []
          }
        }
        """
        try privateWebSocket.write(to: directory.appendingPathComponent("websocket.json"), atomically: true, encoding: .utf8)

        XCTAssertThrowsError(try HAMirrorFixtureVerifier().verify(directory: directory)) { error in
            guard case .invalidWebSocketEvidence = error as? HAMirrorFixtureVerificationError else {
                XCTFail("unexpected error: \(error)")
                return
            }
        }
    }

    func testFixtureVerifierRejectsManifestMismatch() throws {
        let fixtureSet = HAMirrorFixtureSet(
            api: HAMirrorCapturedEndpoint(method: "GET", path: "/api/", statusCode: 200, headers: [:], bodyText: #"{"message":"API running."}"#),
            states: HAMirrorCapturedEndpoint(method: "GET", path: "/api/states", statusCode: 200, headers: [:], bodyText: "[]")
        )
        let directory = try writeFixtureSet(fixtureSet)
        defer {
            try? FileManager.default.removeItem(at: directory)
        }
        let mismatchedManifest = HAMirrorFixtureSet(
            api: HAMirrorCapturedEndpoint(method: "GET", path: "/api/", statusCode: 200, headers: [:], bodyText: #"{"message":"changed"}"#),
            states: fixtureSet.states
        )
        let data = try JSONEncoder().encode(mismatchedManifest)
        try data.write(to: directory.appendingPathComponent("manifest.json"))

        XCTAssertThrowsError(try HAMirrorFixtureVerifier().verify(directory: directory)) { error in
            XCTAssertEqual(error as? HAMirrorFixtureVerificationError, .manifestMismatch)
        }
    }

    func testFixtureVerifierRejectsUnsanitizedBody() throws {
        let fixtureSet = HAMirrorFixtureSet(
            api: HAMirrorCapturedEndpoint(method: "GET", path: "/api/", statusCode: 200, headers: [:], bodyText: #"{"message":"API running."}"#),
            states: HAMirrorCapturedEndpoint(
                method: "GET",
                path: "/api/states",
                statusCode: 200,
                headers: [:],
                bodyText: #"[{"entity_id":"sensor.kitchen_temperature","attributes":{"friendly_name":"Kitchen temperature"},"state":"21.4"}]"#
            )
        )
        let directory = try writeFixtureSet(fixtureSet)
        defer {
            try? FileManager.default.removeItem(at: directory)
        }

        XCTAssertThrowsError(try HAMirrorFixtureVerifier().verify(directory: directory)) { error in
            XCTAssertEqual(error as? HAMirrorFixtureVerificationError, .unsanitizedBody(path: "/api/states"))
        }
    }

    func testFixtureVerifierRejectsMalformedFixtureJSON() throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("perchha-client-test-\(UUID().uuidString)", isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: directory)
        }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try "{".write(to: directory.appendingPathComponent("api.json"), atomically: true, encoding: .utf8)
        try "[]".write(to: directory.appendingPathComponent("states.json"), atomically: true, encoding: .utf8)
        try "{}".write(to: directory.appendingPathComponent("manifest.json"), atomically: true, encoding: .utf8)

        XCTAssertThrowsError(try HAMirrorFixtureVerifier().verify(directory: directory)) { error in
            XCTAssertEqual(error as? HAMirrorFixtureVerificationError, .malformedFile("api.json"))
        }
    }
}

private func connectionInput() throws -> HAConnectionInput {
    HAConnectionInput(
        endpoint: HAEndpoint(
            primaryURL: try XCTUnwrap(URL(string: "http://homeassistant.local:8123")),
            fallbackURL: nil
        ),
        token: "secret-token"
    )
}

actor RecordingHARESTTransport: HARESTTransport {
    private(set) var requests: [HARESTRequest] = []
    private var responses: [RecordingHARESTTransportResponse]

    init(responses: [RecordingHARESTTransportResponse]) {
        self.responses = responses
    }

    func send(_ request: HARESTRequest) async throws -> HARESTResponse {
        requests.append(request)
        guard !responses.isEmpty else {
            throw URLError(.cannotConnectToHost)
        }
        switch responses.removeFirst() {
        case let .success(response):
            return response
        case let .urlError(error):
            throw error
        case let .transportError(message):
            throw RecordingHARESTTransportError(message: message)
        }
    }
}

enum RecordingHARESTTransportResponse: Sendable {
    case success(HARESTResponse)
    case urlError(URLError)
    case transportError(String)
}

struct RecordingHARESTTransportError: Error, CustomStringConvertible, Sendable {
    let message: String

    var description: String {
        message
    }
}

private func writeFixtureSet(_ fixtureSet: HAMirrorFixtureSet) throws -> URL {
    let directory = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("perchha-client-test-\(UUID().uuidString)", isDirectory: true)
    _ = try HAMirrorFixtureWriter().write(fixtureSet, to: directory)
    return directory
}

private func historyDate(_ value: String) throws -> Date {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime]
    return try XCTUnwrap(formatter.date(from: value))
}

actor RecordingMirrorTransport: HAMirrorTransport {
    private(set) var requests: [HAMirrorRequest] = []
    private let apiStatusCode: Int
    private let statesStatusCode: Int
    private let apiBody: String
    private let statesBody: String
    private let handler: (@Sendable (HAMirrorRequest) throws -> HAMirrorResponse)?

    init(
        apiStatusCode: Int = 200,
        statesStatusCode: Int = 200,
        apiBody: String = #"{"message":"API running."}"#,
        statesBody: String = #"[]"#,
        handler: (@Sendable (HAMirrorRequest) throws -> HAMirrorResponse)? = nil
    ) {
        self.apiStatusCode = apiStatusCode
        self.statesStatusCode = statesStatusCode
        self.apiBody = apiBody
        self.statesBody = statesBody
        self.handler = handler
    }

    func send(_ request: HAMirrorRequest) async throws -> HAMirrorResponse {
        requests.append(request)
        if let handler {
            return try handler(request)
        }
        let isAPI = request.url.path == "/api/"
        let body = isAPI ? apiBody : statesBody
        return HAMirrorResponse(
            statusCode: isAPI ? apiStatusCode : statesStatusCode,
            headers: ["Authorization": "Bearer should-redact"],
            body: Data(body.utf8)
        )
    }

}

private func waitForJournalCount(server: FakeHAWebSocketServer, count: Int) async throws {
    for _ in 0..<100 {
        if await server.journal.snapshot().count >= count {
            return
        }
        await Task.yield()
    }
    throw ClientTestFailure("FakeHA WebSocket journal did not reach \(count)")
}

private func waitForJournalPath(server: FakeHAWebSocketServer, path: String) async throws {
    for _ in 0..<100 {
        if await server.journal.snapshot().contains(where: { $0.path == path }) {
            return
        }
        await Task.yield()
    }
    throw ClientTestFailure("FakeHA WebSocket journal did not contain \(path)")
}

struct ClientTestFailure: Error, CustomStringConvertible {
    let description: String

    init(_ description: String) {
        self.description = description
    }
}
#endif
