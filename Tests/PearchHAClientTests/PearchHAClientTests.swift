#if canImport(XCTest)
import Foundation
import FakeHA
import XCTest
import PearchHACore
import PearchHAClient
import PearchHATestSupport

func requestPercentEncodedPath(_ url: URL) -> String {
    URLComponents(url: url, resolvingAgainstBaseURL: false)?.percentEncodedPath ?? url.path
}

func replacingHost(in url: URL, with host: String) throws -> URL {
    var components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
    components.host = host
    return try XCTUnwrap(components.url)
}

final class PearchHAClientTests: XCTestCase {
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

    func testServerTrustPolicyTrustsAllSecureHostsWhenTrustsAllHostsIsSet() throws {
        let policy = HAServerTrustPolicy(trustsAllHosts: true)

        XCTAssertTrue(
            policy.allowsSelfSignedCertificate(
                for: try XCTUnwrap(URL(string: "https://anything.example:8123/api/"))
            )
        )
        XCTAssertTrue(
            policy.allowsSelfSignedCertificate(
                for: try XCTUnwrap(URL(string: "wss://unknown.local/api/websocket"))
            )
        )
        XCTAssertTrue(policy.allowsSelfSignedCertificate(forHost: "unlisted.host"))
        XCTAssertFalse(
            policy.allowsSelfSignedCertificate(
                for: try XCTUnwrap(URL(string: "http://anything.example:8123/api/"))
            )
        )
        XCTAssertFalse(policy.allowsSelfSignedCertificate(forHost: nil))
    }

    func testServerTrustPolicyTrustsAllHostsIsOffByDefault() {
        XCTAssertFalse(HAServerTrustPolicy.default.trustsAllHosts)
        XCTAssertFalse(HAServerTrustPolicy(allowedSelfSignedCertificateHosts: ["a.local"]).trustsAllHosts)
    }

    func testPlannedClientIdentifiesModule() {
        XCTAssertEqual(PlannedHAClient().describe().name, "PearchHAClient")
    }

    func testOAuthAuthorizationURLUsesOfficialAuthorizeEndpointAndEncodesNativeRedirect() throws {
        let client = HomeAssistantClient()
        let request = HAOAuthAuthorizationRequest(
            baseURL: try XCTUnwrap(URL(string: "http://homeassistant.local:8123")),
            clientID: "https://pearchha.dev/app",
            redirectURI: "pearchha://auth",
            state: "state value"
        )

        let result = client.authorizationURL(for: request)

        XCTAssertEqual(
            result,
            .success(try XCTUnwrap(URL(string: "http://homeassistant.local:8123/auth/authorize?client_id=https%3A%2F%2Fpearchha.dev%2Fapp&redirect_uri=pearchha%3A%2F%2Fauth&state=state+value")))
        )
    }

    func testOAuthAuthorizationURLAllowsOmittedOptionalState() throws {
        let client = HomeAssistantClient()
        let request = HAOAuthAuthorizationRequest(
            baseURL: try XCTUnwrap(URL(string: "http://homeassistant.local:8123")),
            clientID: "https://pearchha.dev/app",
            redirectURI: "pearchha://auth"
        )

        let result = client.authorizationURL(for: request)

        XCTAssertEqual(
            result,
            .success(try XCTUnwrap(URL(string: "http://homeassistant.local:8123/auth/authorize?client_id=https%3A%2F%2Fpearchha.dev%2Fapp&redirect_uri=pearchha%3A%2F%2Fauth")))
        )
    }

    func testOAuthAuthorizationURLRejectsInvalidInputBeforeOpeningBrowser() throws {
        let client = HomeAssistantClient()
        let invalidBaseURLRequest = HAOAuthAuthorizationRequest(
            baseURL: try XCTUnwrap(URL(string: "file:///tmp/homeassistant")),
            clientID: "https://pearchha.dev/app",
            redirectURI: "pearchha://auth",
            state: "state"
        )
        let invalidRedirectURIRequest = HAOAuthAuthorizationRequest(
            baseURL: try XCTUnwrap(URL(string: "https://homeassistant.local")),
            clientID: "https://pearchha.dev/app",
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
                    body: Data(#"<html><head><link rel="redirect_uri" href="pearchha://auth"></head></html>"#.utf8)
                ))
            ]
        )
        let client = HomeAssistantClient(transport: transport)

        let result = await client.verifyOAuthClientWebsite(
            clientID: "https://pearchha.dev/app",
            redirectURI: "pearchha://auth"
        )

        XCTAssertEqual(
            result,
            .success(
                HAOAuthClientWebsiteCheck(
                    clientID: "https://pearchha.dev/app",
                    redirectURI: "pearchha://auth",
                    websiteFetched: true,
                    redirectURIDeclared: true
                )
            )
        )
        let firstRequest = await transport.requests.first
        let request = try XCTUnwrap(firstRequest)
        XCTAssertEqual(request.method, "GET")
        XCTAssertEqual(request.url.absoluteString, "https://pearchha.dev/app")
        XCTAssertEqual(request.headers["Accept"], "text/html,application/xhtml+xml")
        XCTAssertNil(request.body)
    }

    func testOAuthClientWebsiteAcceptsRedirectDeclarationWithAttributesInEitherOrder() async {
        let transport = RecordingHARESTTransport(
            responses: [
                .success(HARESTResponse(
                    statusCode: 200,
                    headers: [:],
                    body: Data(#"<link href='pearchha://auth' rel='author redirect_uri'>"#.utf8)
                ))
            ]
        )

        let result = await HomeAssistantClient(transport: transport).verifyOAuthClientWebsite(
            clientID: "https://pearchha.dev/app",
            redirectURI: "pearchha://auth"
        )

        XCTAssertEqual(
            result,
            .success(
                HAOAuthClientWebsiteCheck(
                    clientID: "https://pearchha.dev/app",
                    redirectURI: "pearchha://auth",
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
            clientID: "https://pearchha.dev/app",
            redirectURI: "pearchha://auth"
        )

        XCTAssertEqual(
            result,
            .failure(.invalidPayload(path: "https://pearchha.dev/app", reason: "redirect_uri link is required in first 10000 bytes"))
        )
    }

    func testOAuthClientWebsiteRejectsNativeRedirectDeclarationAfterFirstTenKB() async {
        let padding = String(repeating: "x", count: 10_001)
        let transport = RecordingHARESTTransport(
            responses: [
                .success(HARESTResponse(
                    statusCode: 200,
                    headers: ["Content-Type": "text/html"],
                    body: Data("\(padding)<link rel=\"redirect_uri\" href=\"pearchha://auth\">".utf8)
                ))
            ]
        )
        let client = HomeAssistantClient(transport: transport)

        let result = await client.verifyOAuthClientWebsite(
            clientID: "https://pearchha.dev/app",
            redirectURI: "pearchha://auth"
        )

        XCTAssertEqual(
            result,
            .failure(.invalidPayload(path: "https://pearchha.dev/app", reason: "redirect_uri link is required in first 10000 bytes"))
        )
    }

    func testOAuthClientWebsiteSkipsNetworkForSameOriginRedirect() async {
        let transport = RecordingHARESTTransport(responses: [])
        let client = HomeAssistantClient(transport: transport)

        let result = await client.verifyOAuthClientWebsite(
            clientID: "https://pearchha.dev/app",
            redirectURI: "https://pearchha.dev/oauth/callback"
        )

        XCTAssertEqual(
            result,
            .success(
                HAOAuthClientWebsiteCheck(
                    clientID: "https://pearchha.dev/app",
                    redirectURI: "https://pearchha.dev/oauth/callback",
                    websiteFetched: false,
                    redirectURIDeclared: false
                )
            )
        )
        await assertEqualAsync(await transport.requests, [])
    }

    func testOAuthClientWebsiteSkipsNetworkForExplicitDefaultHTTPSPort() async {
        let transport = RecordingHARESTTransport(responses: [])
        let client = HomeAssistantClient(transport: transport)

        let result = await client.verifyOAuthClientWebsite(
            clientID: "https://pearchha.dev/app",
            redirectURI: "https://pearchha.dev:443/auth"
        )

        XCTAssertEqual(
            result,
            .success(
                HAOAuthClientWebsiteCheck(
                    clientID: "https://pearchha.dev/app",
                    redirectURI: "https://pearchha.dev:443/auth",
                    websiteFetched: false,
                    redirectURIDeclared: false
                )
            )
        )
        await assertEqualAsync(await transport.requests, [])
    }

    func testOAuthClientWebsiteSkipsNetworkForExplicitDefaultHTTPPort() async {
        let transport = RecordingHARESTTransport(responses: [])
        let client = HomeAssistantClient(transport: transport)

        let result = await client.verifyOAuthClientWebsite(
            clientID: "http://pearchha.dev/app",
            redirectURI: "http://pearchha.dev:80/auth"
        )

        XCTAssertEqual(
            result,
            .success(
                HAOAuthClientWebsiteCheck(
                    clientID: "http://pearchha.dev/app",
                    redirectURI: "http://pearchha.dev:80/auth",
                    websiteFetched: false,
                    redirectURIDeclared: false
                )
            )
        )
        await assertEqualAsync(await transport.requests, [])
    }

    func testOAuthClientWebsiteRejectsInvalidInputsBeforeNetwork() async {
        let transport = RecordingHARESTTransport(responses: [])
        let client = HomeAssistantClient(transport: transport)

        let invalidClient = await client.verifyOAuthClientWebsite(
            clientID: "pearchha://app",
            redirectURI: "pearchha://auth"
        )
        let invalidRedirect = await client.verifyOAuthClientWebsite(
            clientID: "https://pearchha.dev/app",
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
        await assertEqualAsync(await transport.requests, [])
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
            clientID: "https://pearchha.dev/app"
        )

        XCTAssertEqual(
            result,
            .success(HAOAuthToken(accessToken: "access-token", refreshToken: "refresh-token", expiresInSeconds: 1800, tokenType: "Bearer"))
        )
        let firstRequest = await transport.requests.first
        let request = try XCTUnwrap(firstRequest)
        XCTAssertEqual(request.method, "POST")
        XCTAssertEqual(request.url.path, "/auth/token")
        XCTAssertEqual(request.headers["Accept"], "application/json")
        XCTAssertEqual(request.headers["Content-Type"], "application/x-www-form-urlencoded")
        XCTAssertEqual(
            String(data: try XCTUnwrap(request.body), encoding: .utf8),
            "grant_type=authorization_code&code=code+value&client_id=https%3A%2F%2Fpearchha.dev%2Fapp"
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
            clientID: "https://pearchha.dev/app",
            serverTrustPolicy: policy
        )
        let refresh = await client.refreshAccessToken(
            baseURL: baseURL,
            refreshToken: "refresh-token",
            clientID: "https://pearchha.dev/app",
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
            clientID: "https://pearchha.dev/app"
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
            clientID: "https://pearchha.dev/app"
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
            clientID: "https://pearchha.dev/app"
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
            clientID: "https://pearchha.dev/app"
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
            clientID: "https://pearchha.dev/app"
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
            clientID: "https://pearchha.dev/app"
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
            clientID: "https://pearchha.dev/app"
        )

        XCTAssertEqual(
            result,
            .success(HAOAuthToken(accessToken: "rotated-access-token", refreshToken: nil, expiresInSeconds: 1800, tokenType: "Bearer"))
        )
        let firstRequest = await transport.requests.first
        let request = try XCTUnwrap(firstRequest)
        XCTAssertEqual(
            String(data: try XCTUnwrap(request.body), encoding: .utf8),
            "grant_type=refresh_token&refresh_token=refresh+token&client_id=https%3A%2F%2Fpearchha.dev%2Fapp"
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

        await assertEqualAsync(
            await HomeAssistantClient(transport: invalidRequestTransport).refreshAccessToken(
                baseURL: baseURL,
                refreshToken: "refresh-secret",
                clientID: "https://pearchha.dev/app"
            ),
            .failure(.invalidPayload(path: "/auth/token", reason: "HTTP 400 invalid request"))
        )
        await assertEqualAsync(
            await HomeAssistantClient(transport: leakingTransport).refreshAccessToken(
                baseURL: baseURL,
                refreshToken: "refresh-secret",
                clientID: "https://pearchha.dev/app"
            ),
            .failure(.transport("refresh_token=<redacted> code=<redacted>"))
        )
    }

    func testOAuthCodeExchangeReportsHTTPStatusFailure() async throws {
        let transport = RecordingHARESTTransport(
            responses: [
                .success(HARESTResponse(statusCode: 418, headers: [:], body: Data()))
            ]
        )

        let result = await HomeAssistantClient(transport: transport).exchangeAuthorizationCode(
            baseURL: try XCTUnwrap(URL(string: "https://homeassistant.local")),
            code: "code",
            clientID: "https://pearchha.dev/app"
        )

        XCTAssertEqual(result, .failure(.httpStatus(path: "/auth/token", statusCode: 418)))
    }

    func testOAuthCodeExchangeMapsNonHTTPResponseToInvalidResponse() async throws {
        let transport = RecordingHARESTTransport(
            responses: [
                .nonHTTPResponse
            ]
        )

        let result = await HomeAssistantClient(transport: transport).exchangeAuthorizationCode(
            baseURL: try XCTUnwrap(URL(string: "https://homeassistant.local")),
            code: "code",
            clientID: "https://pearchha.dev/app"
        )

        XCTAssertEqual(result, .failure(.invalidResponse(path: "/auth/token")))
    }

    func testOAuthCodeExchangeMapsTransportURLFailure() async throws {
        let transport = RecordingHARESTTransport(
            responses: [
                .urlError(URLError(.timedOut))
            ]
        )

        let result = await HomeAssistantClient(transport: transport).exchangeAuthorizationCode(
            baseURL: try XCTUnwrap(URL(string: "https://homeassistant.local")),
            code: "code",
            clientID: "https://pearchha.dev/app"
        )

        XCTAssertEqual(result, .failure(.unreachable(host: "homeassistant.local")))
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
            clientID: "https://pearchha.dev/app"
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
        let firstRequest = await transport.requests.first
        let request = try XCTUnwrap(firstRequest)
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
        XCTAssertEqual(requests.map { requestPercentEncodedPath($0.url) }, ["/api/"])
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
        XCTAssertEqual(requests.map { requestPercentEncodedPath($0.url) }, ["/ha/api/"])
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

    func testRESTConnectionReportsHTTPStatusFailure() async throws {
        let transport = RecordingHARESTTransport(
            responses: [
                .success(HARESTResponse(statusCode: 503, headers: [:], body: Data(#"{"message":"offline"}"#.utf8)))
            ]
        )

        let result = await HomeAssistantClient(transport: transport).checkRESTConnection(try connectionInput())

        XCTAssertEqual(result, .failure(.httpStatus(path: "/api/", statusCode: 503)))
    }

    func testRESTConnectionMapsNonHTTPResponseToInvalidResponse() async throws {
        let transport = RecordingHARESTTransport(
            responses: [
                .nonHTTPResponse
            ]
        )

        let result = await HomeAssistantClient(transport: transport).checkRESTConnection(try connectionInput())

        XCTAssertEqual(result, .failure(.invalidResponse(path: "/api/")))
    }

    func testClientFailureMapsToCoreConnectionFailure() {
        XCTAssertEqual(HAClientFailure.authentication.connectionFailure, .authentication)
        XCTAssertEqual(HAClientFailure.unreachable(host: "homeassistant.local").connectionFailure, .unreachable(host: "homeassistant.local"))
        XCTAssertEqual(HAClientFailure.tlsRejected(host: "homeassistant.local").connectionFailure, .tlsRejected(host: "homeassistant.local"))
        XCTAssertEqual(
            HAClientFailure.httpStatus(path: "/api/", statusCode: 500).connectionFailure,
            .protocolError("HTTP 500 for /api/")
        )
        XCTAssertEqual(
            HAClientFailure.invalidURL(path: "/bad path").connectionFailure,
            .protocolError("invalid URL path: /bad path")
        )
        XCTAssertEqual(
            HAClientFailure.invalidResponse(path: "/api/").connectionFailure,
            .protocolError("non-HTTP response for /api/")
        )
        XCTAssertEqual(
            HAClientFailure.invalidPayload(path: "/api/states", reason: "broken").connectionFailure,
            .protocolError("invalid payload for /api/states: broken")
        )
        XCTAssertEqual(
            HAClientFailure.webSocketProtocol("oops").connectionFailure,
            .protocolError("WebSocket protocol error: oops")
        )
        XCTAssertEqual(
            HAClientFailure.webSocketCommand(id: 9, code: "unknown_command", message: "nope").connectionFailure,
            .protocolError("WebSocket command 9 failed: unknown_command - nope")
        )
        XCTAssertEqual(
            HAClientFailure.transport("socket closed").connectionFailure,
            .protocolError("socket closed")
        )
    }

    func testClientFailureDescriptionsStaySpecific() {
        XCTAssertEqual(HAClientFailure.authentication.description, "Home Assistant rejected the access token")
        XCTAssertEqual(
            HAClientFailure.unreachable(host: "ha.local").description,
            "Home Assistant is unreachable at ha.local"
        )
        XCTAssertEqual(
            HAClientFailure.tlsRejected(host: "ha.local").description,
            "Home Assistant TLS certificate was rejected for ha.local"
        )
        XCTAssertEqual(
            HAClientFailure.invalidURL(path: "/broken").description,
            "invalid Home Assistant URL path: /broken"
        )
        XCTAssertEqual(
            HAClientFailure.invalidResponse(path: "/api/").description,
            "Home Assistant returned a non-HTTP response for /api/"
        )
        XCTAssertEqual(
            HAClientFailure.invalidPayload(path: "/api/states", reason: "missing state").description,
            "Home Assistant returned invalid payload for /api/states: missing state"
        )
        XCTAssertEqual(
            HAClientFailure.httpStatus(path: "/api/", statusCode: 503).description,
            "Home Assistant returned HTTP 503 for /api/"
        )
        XCTAssertEqual(
            HAClientFailure.webSocketProtocol("bad ack").description,
            "Home Assistant WebSocket protocol error: bad ack"
        )
        XCTAssertEqual(
            HAClientFailure.webSocketCommand(id: nil, code: "unknown_command", message: "unsupported").description,
            "Home Assistant WebSocket command ? failed: unknown_command - unsupported"
        )
        XCTAssertEqual(
            HAClientFailure.transport("connection reset").description,
            "Home Assistant transport failed: connection reset"
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

    func testConnectionTriesAddressesInOrderAndSucceedsOnThird() async throws {
        let transport = RecordingHARESTTransport(
            responses: [
                .urlError(URLError(.cannotConnectToHost)),
                .transportError("socket closed before response"),
                .success(HARESTResponse(statusCode: 200, headers: [:], body: Data(#"{"message":"API running."}"#.utf8)))
            ]
        )
        let client = HomeAssistantClient(transport: transport)
        let input = HAConnectionInput(
            endpoint: HAEndpoint(urls: [
                try XCTUnwrap(URL(string: "http://first.local:8123")),
                try XCTUnwrap(URL(string: "http://second.local:8123")),
                try XCTUnwrap(URL(string: "https://third.example"))
            ]),
            token: "secret-token"
        )

        let result = await client.checkRESTConnection(input)

        XCTAssertEqual(result, .success(HARESTCheck(message: "API running.")))
        let requests = await transport.requests
        XCTAssertEqual(requests.map { $0.url.host }, ["first.local", "second.local", "third.example"])
    }

    func testConnectionStopsAtNonRetryableAuthFailureWithoutTryingLaterAddresses() async throws {
        let transport = RecordingHARESTTransport(
            responses: [
                .urlError(URLError(.cannotConnectToHost)),
                .success(HARESTResponse(statusCode: 401, headers: [:], body: Data())),
                .success(HARESTResponse(statusCode: 200, headers: [:], body: Data(#"{"message":"API running."}"#.utf8)))
            ]
        )
        let client = HomeAssistantClient(transport: transport)
        let input = HAConnectionInput(
            endpoint: HAEndpoint(urls: [
                try XCTUnwrap(URL(string: "http://first.local:8123")),
                try XCTUnwrap(URL(string: "http://second.local:8123")),
                try XCTUnwrap(URL(string: "https://third.example"))
            ]),
            token: "secret-token"
        )

        let result = await client.checkRESTConnection(input)

        XCTAssertEqual(result, .failure(.authentication))
        let requests = await transport.requests
        XCTAssertEqual(requests.map { $0.url.host }, ["first.local", "second.local"])
    }

    func testConnectionReportsSanitizedFailureWhenAllAddressesFail() async throws {
        let transport = RecordingHARESTTransport(
            responses: [
                .urlError(URLError(.cannotConnectToHost)),
                .urlError(URLError(.cannotConnectToHost))
            ]
        )
        let client = HomeAssistantClient(transport: transport)
        let input = HAConnectionInput(
            endpoint: HAEndpoint(urls: [
                try XCTUnwrap(URL(string: "http://first.local:8123")),
                try XCTUnwrap(URL(string: "https://second.example"))
            ]),
            token: "super-secret-token"
        )

        let result = await client.checkRESTConnection(input)

        XCTAssertEqual(result, .failure(.unreachable(host: "second.example")))
        if case let .failure(failure) = result {
            XCTAssertFalse(failure.description.contains("super-secret-token"))
        } else {
            XCTFail("expected a failure when every address is unreachable")
        }
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

        await assertEqualAsync(await HomeAssistantClient(transport: authTransport).checkRESTConnection(input), .failure(.authentication))
        await assertEqualAsync(
            await HomeAssistantClient(transport: unreachableTransport).checkRESTConnection(input),
            .failure(.unreachable(host: "homeassistant.local"))
        )
        await assertEqualAsync(
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

        await assertEqualAsync(await client.checkRESTConnection(input), .success(HARESTCheck(message: "API running.")))
        await assertEqualAsync(
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
        let localhostURL = try replacingHost(in: server.baseURL, with: "localhost")
        let strictInput = HAConnectionInput(
            endpoint: HAEndpoint(primaryURL: localhostURL, fallbackURL: nil),
            token: "fake-token"
        )
        let allowedInput = HAConnectionInput(
            endpoint: HAEndpoint(primaryURL: localhostURL, fallbackURL: nil),
            token: "fake-token",
            serverTrustPolicy: HAServerTrustPolicy(allowedSelfSignedCertificateHosts: ["localhost"])
        )

        await assertEqualAsync(await client.checkRESTConnection(strictInput), .failure(.tlsRejected(host: "localhost")))

        let allowedResult = await client.checkRESTConnection(allowedInput)
        switch allowedResult {
        case .success(HARESTCheck(message: "API running.")):
            break
        case .failure(.tlsRejected(host: "localhost")):
            break
        default:
            XCTFail("expected explicit TLS outcome for allow-listed host, got \(allowedResult)")
        }
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

        await assertEqualAsync(await HomeAssistantClient().checkRESTConnection(input), .failure(.tlsRejected(host: "127.0.0.1")))
    }

    func testSelfSignedRESTAllows127001HostAllowance() async throws {
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
        let input = HAConnectionInput(
            endpoint: HAEndpoint(primaryURL: server.baseURL, fallbackURL: nil),
            token: "fake-token",
            serverTrustPolicy: HAServerTrustPolicy(allowedSelfSignedCertificateHosts: ["127.0.0.1"])
        )

        await assertEqualAsync(await HomeAssistantClient().checkRESTConnection(input), .success(HARESTCheck(message: "API running.")))
    }

    func testSelfSignedWebSocketRequiresExplicitHostAllowance() async throws {
        let identity = try FakeHASelfSignedIdentity()
        let server = try FakeHAWebSocketServer(tlsIdentity: identity.identity)
        server.start()
        defer {
            server.stop()
        }
        let client = HomeAssistantClient()
        let localhostURL = try replacingHost(in: server.baseURL, with: "localhost")
        let strictInput = HAConnectionInput(
            endpoint: HAEndpoint(primaryURL: localhostURL, fallbackURL: nil),
            token: "fake-token"
        )
        let allowedInput = HAConnectionInput(
            endpoint: HAEndpoint(primaryURL: localhostURL, fallbackURL: nil),
            token: "fake-token",
            serverTrustPolicy: HAServerTrustPolicy(allowedSelfSignedCertificateHosts: ["localhost"])
        )

        await assertEqualAsync(await client.checkWebSocketConnection(strictInput), .failure(.tlsRejected(host: "localhost")))

        let allowedResult = await client.checkWebSocketConnection(allowedInput)
        switch allowedResult {
        case .success(HAWebSocketCheck(haVersion: "fake-ha")):
            break
        case .failure(.tlsRejected(host: "localhost")):
            break
        default:
            XCTFail("expected explicit TLS outcome for allow-listed host, got \(allowedResult)")
        }
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

        await assertEqualAsync(await HomeAssistantClient().checkWebSocketConnection(input), .failure(.tlsRejected(host: "127.0.0.1")))
    }

    func testSelfSignedWebSocketAllows127001HostAllowance() async throws {
        let identity = try FakeHASelfSignedIdentity()
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

        await assertEqualAsync(await HomeAssistantClient().checkWebSocketConnection(input), .success(HAWebSocketCheck(haVersion: "fake-ha")))
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
        let firstRequest = await transport.requests.first
        let request = try XCTUnwrap(firstRequest)
        XCTAssertTrue(request.url.path.hasPrefix("/api/history/period/"))
        let items = Dictionary(
            uniqueKeysWithValues: (URLComponents(url: request.url, resolvingAgainstBaseURL: false)?.queryItems ?? [])
                .compactMap { item in item.value.map { (item.name, $0) } }
        )
        XCTAssertEqual(items["filter_entity_id"], "sensor.office_temperature")
        XCTAssertEqual(items["end_time"], "2026-06-27T12:00:00Z")
        XCTAssertEqual(items["include_start_time_state"], "true")
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
        let firstRequest = await transport.requests.first
        let request = try XCTUnwrap(firstRequest)
        XCTAssertTrue(request.url.path.hasPrefix("/api/history/period/"))
        let items = Dictionary(
            uniqueKeysWithValues: (URLComponents(url: request.url, resolvingAgainstBaseURL: false)?.queryItems ?? [])
                .compactMap { item in item.value.map { (item.name, $0) } }
        )
        XCTAssertEqual(items["filter_entity_id"], "sensor.office_temperature")
        XCTAssertEqual(items["end_time"], "2026-06-27T12:00:00Z")
        XCTAssertEqual(items["include_start_time_state"], "true")
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

    func test_t_bulk_history_returns_multiple_series_in_one_request() async throws {
        // HA returns one array per requested entity; under minimal_response only the
        // first row of each group carries entity_id.
        let historyBody = """
        [
          [
            {"entity_id":"sensor.a","state":"1.0","last_changed":"2026-06-27T10:00:00+00:00"},
            {"state":"2.0","last_changed":"2026-06-27T11:00:00+00:00"}
          ],
          [
            {"entity_id":"sensor.b","state":"5.0","last_changed":"2026-06-27T10:30:00+00:00"}
          ]
        ]
        """
        let transport = RecordingHARESTTransport(
            responses: [
                .success(HARESTResponse(statusCode: 200, headers: [:], body: Data(historyBody.utf8)))
            ]
        )
        let client = HomeAssistantClient(transport: transport)

        let result = await client.historyBatch(
            try connectionInput(),
            entityIDs: ["sensor.a", "sensor.b"],
            range: .hour,
            end: try historyDate("2026-06-27T12:00:00+00:00")
        )

        guard case let .success(series) = result else {
            XCTFail("bulk history unexpectedly failed: \(result)")
            return
        }
        XCTAssertEqual(
            series["sensor.a"],
            HistorySeries(
                entityID: "sensor.a",
                range: .hour,
                samples: [
                    HistorySample(timestamp: try historyDate("2026-06-27T10:00:00+00:00"), state: "1.0", numericValue: 1.0),
                    HistorySample(timestamp: try historyDate("2026-06-27T11:00:00+00:00"), state: "2.0", numericValue: 2.0)
                ]
            )
        )
        XCTAssertEqual(
            series["sensor.b"],
            HistorySeries(
                entityID: "sensor.b",
                range: .hour,
                samples: [
                    HistorySample(timestamp: try historyDate("2026-06-27T10:30:00+00:00"), state: "5.0", numericValue: 5.0)
                ]
            )
        )
        let requests = await transport.requests
        XCTAssertEqual(requests.count, 1, "two entities fetched in a single bulk request")
        let request = try XCTUnwrap(requests.first)
        let items = Dictionary(
            uniqueKeysWithValues: (URLComponents(url: request.url, resolvingAgainstBaseURL: false)?.queryItems ?? [])
                .compactMap { item in item.value.map { (item.name, $0) } }
        )
        XCTAssertEqual(items["filter_entity_id"], "sensor.a,sensor.b")
        XCTAssertEqual(items["include_start_time_state"], "true")
        XCTAssertEqual(items["minimal_response"], "true")
        XCTAssertEqual(items["no_attributes"], "true")
    }

    func test_t_bulk_history_splits_sets_larger_than_cap_into_batches() async throws {
        // 3 ids with a cap of 2 → two sequential requests (2 ids, then 1).
        func body(for ids: [String]) -> String {
            let groups = ids.map { id in
                #"[{"entity_id":"\#(id)","state":"1.0","last_changed":"2026-06-27T10:00:00+00:00"}]"#
            }
            return "[\(groups.joined(separator: ","))]"
        }
        let transport = RecordingHARESTTransport(
            responses: [
                .success(HARESTResponse(statusCode: 200, headers: [:], body: Data(body(for: ["sensor.a", "sensor.b"]).utf8))),
                .success(HARESTResponse(statusCode: 200, headers: [:], body: Data(body(for: ["sensor.c"]).utf8)))
            ]
        )
        let client = HomeAssistantClient(transport: transport)

        let result = await client.historyBatch(
            try connectionInput(),
            entityIDs: ["sensor.a", "sensor.b", "sensor.c"],
            range: .hour,
            end: try historyDate("2026-06-27T12:00:00+00:00"),
            batchSize: 2
        )

        guard case let .success(series) = result else {
            XCTFail("bulk history unexpectedly failed: \(result)")
            return
        }
        XCTAssertEqual(Set(series.keys), ["sensor.a", "sensor.b", "sensor.c"])
        let requests = await transport.requests
        XCTAssertEqual(requests.count, 2, "a >cap set splits into sequential batches")
        let filters = requests.map { request in
            (URLComponents(url: request.url, resolvingAgainstBaseURL: false)?.queryItems ?? [])
                .first { $0.name == "filter_entity_id" }?.value
        }
        XCTAssertEqual(filters, ["sensor.a,sensor.b", "sensor.c"])
    }

    func test_t_bulk_history_returns_empty_without_transport_when_entity_list_is_empty() async throws {
        let transport = RecordingHARESTTransport(
            responses: [
                .transportError("transport should stay idle")
            ]
        )
        let client = HomeAssistantClient(transport: transport)

        let result = await client.historyBatch(
            try connectionInput(),
            entityIDs: [],
            range: .hour,
            end: try historyDate("2026-06-27T12:00:00+00:00")
        )

        XCTAssertEqual(result, .success([:]))
        let requests = await transport.requests
        XCTAssertTrue(requests.isEmpty)
    }

    func test_t_bulk_history_deduplicates_entity_ids_and_treats_zero_batch_size_as_one() async throws {
        func body(for id: String) -> String {
            #"[ [{"entity_id":"\#(id)","state":"1.0","last_changed":"2026-06-27T10:00:00+00:00"}] ]"#
        }
        let transport = RecordingHARESTTransport(
            responses: [
                .success(HARESTResponse(statusCode: 200, headers: [:], body: Data(body(for: "sensor.a").utf8))),
                .success(HARESTResponse(statusCode: 200, headers: [:], body: Data(body(for: "sensor.b").utf8)))
            ]
        )
        let client = HomeAssistantClient(transport: transport)

        let result = await client.historyBatch(
            try connectionInput(),
            entityIDs: ["sensor.a", "sensor.a", "sensor.b"],
            range: .hour,
            end: try historyDate("2026-06-27T12:00:00+00:00"),
            batchSize: 0
        )

        guard case let .success(series) = result else {
            XCTFail("bulk history unexpectedly failed: \(result)")
            return
        }
        XCTAssertEqual(Set(series.keys), ["sensor.a", "sensor.b"])
        let requests = await transport.requests
        XCTAssertEqual(requests.count, 2)
        let filters = requests.map { request in
            (URLComponents(url: request.url, resolvingAgainstBaseURL: false)?.queryItems ?? [])
                .first { $0.name == "filter_entity_id" }?.value
        }
        XCTAssertEqual(filters, ["sensor.a", "sensor.b"])
    }

    func test_t_bulk_history_partial_or_empty_entity_yields_no_series_without_failing() async throws {
        // sensor.a returns rows; sensor.b is absent entirely; an empty group is
        // ignored. The batch still succeeds for the entities that came back.
        let historyBody = """
        [
          [
            {"entity_id":"sensor.a","state":"1.0","last_changed":"2026-06-27T10:00:00+00:00"}
          ],
          []
        ]
        """
        let transport = RecordingHARESTTransport(
            responses: [
                .success(HARESTResponse(statusCode: 200, headers: [:], body: Data(historyBody.utf8)))
            ]
        )
        let client = HomeAssistantClient(transport: transport)

        let result = await client.historyBatch(
            try connectionInput(),
            entityIDs: ["sensor.a", "sensor.b"],
            range: .hour,
            end: try historyDate("2026-06-27T12:00:00+00:00")
        )

        guard case let .success(series) = result else {
            XCTFail("bulk history unexpectedly failed: \(result)")
            return
        }
        XCTAssertNotNil(series["sensor.a"])
        XCTAssertNil(series["sensor.b"], "an entity with no rows is simply absent")
    }

    func test_t_bulk_history_falls_back_to_next_url_on_unreachable_primary() async throws {
        let transport = RecordingHARESTTransport(
            responses: [
                .urlError(URLError(.cannotConnectToHost)),
                .success(HARESTResponse(
                    statusCode: 200,
                    headers: [:],
                    body: Data(#"[[{"entity_id":"sensor.a","state":"1.0","last_changed":"2026-06-27T10:00:00+00:00"}]]"#.utf8)
                ))
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

        let result = await client.historyBatch(
            input,
            entityIDs: ["sensor.a"],
            range: .hour,
            end: try historyDate("2026-06-27T12:00:00+00:00")
        )

        guard case let .success(series) = result else {
            XCTFail("bulk history unexpectedly failed: \(result)")
            return
        }
        XCTAssertNotNil(series["sensor.a"])
        let requests = await transport.requests
        XCTAssertEqual(requests.map { $0.url.host }, ["primary.local", "fallback.example"])
    }

    func test_t_bulk_history_returns_partial_success_when_later_batch_transport_fails() async throws {
        let firstBatch = #"[ [{"entity_id":"sensor.a","state":"1.0","last_changed":"2026-06-27T10:00:00+00:00"}] ]"#
        let transport = RecordingHARESTTransport(
            responses: [
                .success(HARESTResponse(statusCode: 200, headers: [:], body: Data(firstBatch.utf8))),
                .transportError("secret-token connection dropped")
            ]
        )
        let client = HomeAssistantClient(transport: transport)
        let input = HAConnectionInput(
            endpoint: HAEndpoint(primaryURL: try XCTUnwrap(URL(string: "http://primary.local:8123")), fallbackURL: nil),
            token: "secret-token"
        )

        let result = await client.historyBatch(
            input,
            entityIDs: ["sensor.a", "sensor.b"],
            range: .hour,
            end: try historyDate("2026-06-27T12:00:00+00:00"),
            batchSize: 1
        )

        guard case let .success(series) = result else {
            XCTFail("bulk history unexpectedly failed: \(result)")
            return
        }
        XCTAssertEqual(Set(series.keys), ["sensor.a"])
        let requests = await transport.requests
        XCTAssertEqual(requests.count, 2)
    }

    func test_t_bulk_history_surfaces_authentication_when_later_batch_rejects_token() async throws {
        let firstBatch = #"[ [{"entity_id":"sensor.a","state":"1.0","last_changed":"2026-06-27T10:00:00+00:00"}] ]"#
        let transport = RecordingHARESTTransport(
            responses: [
                .success(HARESTResponse(statusCode: 200, headers: [:], body: Data(firstBatch.utf8))),
                .success(HARESTResponse(statusCode: 401, headers: [:], body: Data()))
            ]
        )
        let client = HomeAssistantClient(transport: transport)

        let result = await client.historyBatch(
            try connectionInput(),
            entityIDs: ["sensor.a", "sensor.b"],
            range: .hour,
            end: try historyDate("2026-06-27T12:00:00+00:00"),
            batchSize: 1
        )

        XCTAssertEqual(result, .failure(.authentication))
        let requests = await transport.requests
        XCTAssertEqual(requests.count, 2)
    }

    func test_t_bulk_history_never_leaks_token_on_failure() async throws {
        let transport = RecordingHARESTTransport(
            responses: [
                .transportError("connection died super-secret-token leaked")
            ]
        )
        let client = HomeAssistantClient(transport: transport)
        let input = HAConnectionInput(
            endpoint: HAEndpoint(primaryURL: try XCTUnwrap(URL(string: "http://primary.local:8123")), fallbackURL: nil),
            token: "super-secret-token"
        )

        let result = await client.historyBatch(
            input,
            entityIDs: ["sensor.a"],
            range: .hour,
            end: try historyDate("2026-06-27T12:00:00+00:00")
        )

        // A fully failed batch surfaces an explicit failure whose text never
        // contains the token; the Authorization header is the only place the
        // token appears.
        guard case let .failure(failure) = result else {
            XCTFail("a fully failed bulk history must fail explicitly, got \(result)")
            return
        }
        XCTAssertFalse(failure.description.contains("super-secret-token"), "failure text must never leak the token")
        let requests = await transport.requests
        XCTAssertEqual(requests.first?.headers["Authorization"], "Bearer super-secret-token")
    }

    func test_t_bulk_history_week_routes_to_recorder_statistics_in_one_command() async throws {
        let fixtures = FakeHAFixtures(
            apiBody: #"{"message":"API running."}"#,
            statesBody: #"[]"#,
            recorderStatisticsBody: """
            {
              "sensor.office_temperature": [
                {"start":1782554400000,"end":1782558000000,"state":21.4}
              ],
              "sensor.office_humidity": [
                {"start":1782554400000,"end":1782558000000,"mean":47.0}
              ]
            }
            """
        )
        let server = try FakeHAWebSocketServer(fixtures: fixtures)
        server.start()
        defer {
            server.stop()
        }
        try await waitForRESTServerReady(baseURL: server.baseURL)
        let client = HomeAssistantClient()
        let input = HAConnectionInput(
            endpoint: HAEndpoint(primaryURL: server.baseURL, fallbackURL: nil),
            token: "fake-token"
        )

        // The bulk sync must fetch week/month history from the SAME source as
        // the hover load (recorder statistics) — mixing raw REST states into
        // the same cache key made week previews oscillate between two shapes.
        let result = await client.historyBatch(
            input,
            entityIDs: ["sensor.office_temperature", "sensor.office_humidity"],
            range: .week,
            end: try historyDate("2026-06-27T12:00:00+00:00")
        )

        guard case let .success(series) = result else {
            XCTFail("bulk statistics history unexpectedly failed: \(result)")
            return
        }
        XCTAssertEqual(
            series["sensor.office_temperature"]?.samples,
            [HistorySample(timestamp: try historyDate("2026-06-27T10:00:00+00:00"), state: "21.4", numericValue: 21.4)]
        )
        XCTAssertEqual(
            series["sensor.office_humidity"]?.samples,
            [HistorySample(timestamp: try historyDate("2026-06-27T10:00:00+00:00"), state: "47.0", numericValue: 47.0)]
        )
        try await waitForJournalPath(server: server, path: "/api/websocket/recorder/statistics_during_period")
        let journal = await server.journal.snapshot()
        let command = try XCTUnwrap(journal.first { $0.path == "/api/websocket/recorder/statistics_during_period" })
        XCTAssertTrue(
            command.bodyText?.contains(#""statistic_ids":["sensor.office_temperature","sensor.office_humidity"]"#) ?? false,
            "both entities travel in one statistics command"
        )
        XCTAssertFalse(journal.contains { $0.path.hasPrefix("/api/history/period/") })
    }

    func test_t_bulk_history_week_skips_entities_without_recorder_samples() async throws {
        let fixtures = FakeHAFixtures(
            apiBody: #"{"message":"API running."}"#,
            statesBody: #"[]"#,
            recorderStatisticsBody: """
            {
              "sensor.office_temperature": [],
              "sensor.office_humidity": [
                {"start":1782554400000,"end":1782558000000,"mean":47.0}
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

        let result = await client.historyBatch(
            input,
            entityIDs: ["sensor.office_temperature", "sensor.office_humidity"],
            range: .week,
            end: try historyDate("2026-06-27T12:00:00+00:00")
        )

        guard case let .success(series) = result else {
            XCTFail("bulk statistics history unexpectedly failed: \(result)")
            return
        }
        XCTAssertNil(series["sensor.office_temperature"])
        XCTAssertEqual(
            series["sensor.office_humidity"]?.samples,
            [HistorySample(timestamp: try historyDate("2026-06-27T10:00:00+00:00"), state: "47.0", numericValue: 47.0)]
        )
    }

    func test_t_bulk_history_week_falls_back_to_rest_when_recorder_statistics_is_unknown() async throws {
        let fixtures = FakeHAFixtures(
            apiBody: #"{"message":"API running."}"#,
            statesBody: #"[]"#,
            historyBody: """
            [
              [
                {"entity_id":"sensor.office_temperature","state":"21.4","last_changed":"2026-06-25T10:00:00+00:00"}
              ]
            ]
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

        let result = await client.historyBatch(
            input,
            entityIDs: ["sensor.office_temperature"],
            range: .week,
            end: try historyDate("2026-06-27T12:00:00+00:00")
        )

        guard case let .success(series) = result else {
            XCTFail("bulk history fallback unexpectedly failed: \(result)")
            return
        }
        XCTAssertNotNil(series["sensor.office_temperature"], "an HA without recorder statistics still serves bulk history via REST")
        let journal = await server.journal.snapshot()
        XCTAssertTrue(journal.contains { $0.path.hasPrefix("/api/history/period/") })
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

    func test_t_history_week_falls_back_to_rest_when_recorder_statistics_returns_no_samples() async throws {
        let fixtures = FakeHAFixtures(
            apiBody: #"{"message":"API running."}"#,
            statesBody: #"[]"#,
            historyBody: """
            [
              [
                {"entity_id":"sensor.office_temperature","state":"21.4","last_changed":"2026-06-25T10:00:00+00:00"}
              ]
            ]
            """,
            recorderStatisticsBody: """
            {
              "sensor.office_temperature": []
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
                        HistorySample(timestamp: try historyDate("2026-06-25T10:00:00+00:00"), state: "21.4", numericValue: 21.4)
                    ]
                )
            )
        )
        let journal = await server.journal.snapshot()
        XCTAssertTrue(journal.contains { $0.path == "/api/websocket/recorder/statistics_during_period" })
        XCTAssertTrue(journal.contains { $0.path.hasPrefix("/api/history/period/") })
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
        let journalSnapshot = await server.journal.snapshot()
        let command = try XCTUnwrap(journalSnapshot.first { $0.path == "/api/websocket/recorder/statistics_during_period" })
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
        try await waitForRESTServerReady(baseURL: server.baseURL)
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
        XCTAssertTrue(journal.contains { $0.path == "/ha/api/websocket" })
        XCTAssertTrue(journal.contains { $0.path.hasPrefix("/ha/api/history/period/") })
        XCTAssertTrue(journal.contains { $0.path.contains("filter_entity_id=sensor.office_temperature") })
    }

    func testHistoryFallsBackToRESTWhenRecorderStatisticsIsOlderHAUnsupported() async throws {
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

    func test_t_bulk_history_week_rejects_malformed_recorder_statistics_payload() async throws {
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

        let result = await client.historyBatch(
            input,
            entityIDs: ["sensor.office_temperature"],
            range: .week,
            end: try historyDate("2026-06-27T12:00:00+00:00")
        )

        if case let .failure(error) = result {
            XCTAssertTrue(error.description.contains("/api/websocket"))
        } else {
            XCTFail("malformed bulk recorder statistics payload unexpectedly succeeded")
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

        await assertEqualAsync(await client.checkWebSocketConnection(input), .success(HAWebSocketCheck(haVersion: "fake-ha")))
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

    func testWebSocketDiscoveryPreservesDeviceModelAndDomainFromRegistry() async throws {
        let fixtures = FakeHAFixtures(
            apiBody: #"{"message":"API running."}"#,
            statesBody: #"[{"entity_id":"sensor.office_temperature","state":"21.4","attributes":{"friendly_name":"Office temperature","unit_of_measurement":"°C"}}]"#,
            areaRegistryBody: #"[{"area_id":"office","name":"Office"}]"#,
            deviceRegistryBody: """
            [
              {
                "id":"office_air",
                "name":"Office air",
                "manufacturer":"AirGradient",
                "model":"Airthings Wave Plus",
                "identifiers":[["bluetooth","office-air"]],
                "area_id":"office"
              }
            ]
            """,
            entityRegistryBody: #"[{"entity_id":"sensor.office_temperature","name":"Office temperature","device_id":"office_air"}]"#
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
                    devices: [Device(id: "office_air", name: "Office air", manufacturer: "AirGradient", model: "Airthings Wave Plus", domain: "bluetooth", areaID: "office")],
                    entities: [EntityRegistryEntry(id: "sensor.office_temperature", name: "Office temperature", areaID: nil, deviceID: "office_air")],
                    states: [EntityState(id: "sensor.office_temperature", name: "Office temperature", state: "21.4", unit: "°C")]
                )
            )
        )
    }

    func testWebSocketDiscoveryToleratesNonStringDeviceIdentifierMembers() async throws {
        let fixtures = FakeHAFixtures(
            apiBody: #"{"message":"API running."}"#,
            statesBody: #"[{"entity_id":"sensor.office_temperature","state":"21.4","attributes":{"friendly_name":"Office temperature","unit_of_measurement":"°C"}}]"#,
            areaRegistryBody: #"[{"area_id":"office","name":"Office"}]"#,
            deviceRegistryBody: """
            [
              {
                "id":"office_air",
                "name":"Office air",
                "manufacturer":"AirGradient",
                "model":"Airthings Wave Plus",
                "identifiers":[["bluetooth",118003]],
                "area_id":"office"
              }
            ]
            """,
            entityRegistryBody: #"[{"entity_id":"sensor.office_temperature","name":"Office temperature","device_id":"office_air"}]"#
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
                    devices: [Device(id: "office_air", name: "Office air", manufacturer: "AirGradient", model: "Airthings Wave Plus", domain: "bluetooth", areaID: "office")],
                    entities: [EntityRegistryEntry(id: "sensor.office_temperature", name: "Office temperature", areaID: nil, deviceID: "office_air")],
                    states: [EntityState(id: "sensor.office_temperature", name: "Office temperature", state: "21.4", unit: "°C")]
                )
            )
        )
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

        await assertEqualAsync(await client.checkWebSocketConnection(input), .failure(.authentication))
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

        await assertEqualAsync(
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
        await assertTrueAsync(await fallback.journal.snapshot().isEmpty)
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

        await assertEqualAsync(
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

        await assertEqualAsync(
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

        await assertEqualAsync(
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

        await assertEqualAsync(
            await client.nextStateChangedEvent(input),
            .success(EntityState(id: "sensor.office_temperature", name: "Office temperature", state: "22.0", unit: "°C"))
        )
        try await waitForJournalPath(server: server, path: "/api/websocket/subscribe_events")
        let paths = await server.journal.snapshot().map(\.path)
        XCTAssertTrue(paths.contains("/api/websocket/subscribe_entities"))
        XCTAssertTrue(paths.contains("/api/websocket/subscribe_events"))
    }

    func test_t_live_updates_fall_back_to_subscribe_events_when_subscribe_entities_is_older_ha_unsupported() async throws {
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

        await assertEqualAsync(
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

        await assertEqualAsync(
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

        await assertEqualAsync(
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

        await assertEqualAsync(
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

        await assertEqualAsync(
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

        await assertEqualAsync(
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
        try await waitForRESTServerReady(baseURL: server.baseURL)
        let client = HomeAssistantClient()
        let input = HAConnectionInput(
            endpoint: HAEndpoint(primaryURL: server.baseURL, fallbackURL: nil),
            token: "fake-token"
        )

        await assertEqualAsync(
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

        await assertEqualAsync(await client.callService(input, call: call), .success(HAServiceCallResult(contextID: "fake-context")))
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

        await assertEqualAsync(
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

        await assertEqualAsync(
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

        await assertEqualAsync(
            await client.callService(
                input,
                call: HAServiceCall(domain: "switch", service: "turn_on", targetEntityID: "switch.office_lamp")
            ),
            .success(HAServiceCallResult(contextID: "fake-context"))
        )
        try await waitForJournalCount(server: server, count: 2)
        await assertTrueAsync(await server.journal.snapshot().contains { $0.path == "/api/websocket/call_service" })
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

        await assertEqualAsync(await client.checkWebSocketConnection(input), .success(HAWebSocketCheck(haVersion: "fake-ha")))
        await assertEqualAsync(
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

        await assertEqualAsync(await client.checkRESTConnection(input), .success(HARESTCheck(message: "API running.")))
        await assertEqualAsync(
            await client.states(input),
            .success([
                EntityState(id: "sensor.office_temperature", name: "Office temperature", state: "21.4", unit: "°C")
            ])
        )
        await assertEqualAsync(
            await client.checkRESTConnection(
                HAConnectionInput(endpoint: input.endpoint, token: "wrong-token")
            ),
            .failure(.authentication)
        )
    }

    func test_t_discovery_surfaces_registry_command_failure_explicitly() async throws {
        let fixtures = FakeHAFixtures(
            apiBody: #"{"message":"API running."}"#,
            statesBody: #"[]"#,
            areaRegistryBody: #"[]"#,
            deviceRegistryBody: #"[]"#,
            entityRegistryBody: #"[]"#
        )
        let server = try FakeHAWebSocketServer(fixtures: fixtures, mode: .commandFailure)
        server.start()
        defer {
            server.stop()
        }
        let client = HomeAssistantClient()
        let input = HAConnectionInput(
            endpoint: HAEndpoint(primaryURL: server.baseURL, fallbackURL: nil),
            token: "fake-token"
        )

        await assertEqualAsync(
            await client.discovery(input),
            .failure(.webSocketCommand(id: 1, code: "failed", message: "Planned command failure"))
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
            PEARCHHA_OAUTH_CLIENT_ID=https://pearchha.dev/app
            PEARCHHA_OAUTH_REDIRECT_URI=pearchha://auth
            """
        )

        XCTAssertEqual(environment.primaryURL.absoluteString, "http://homeassistant.local:8123")
        XCTAssertEqual(environment.fallbackURL?.absoluteString, "https://example.ui.nabu.casa")
        XCTAssertEqual(environment.token, "secret-token")
        XCTAssertEqual(environment.user, "owner")
        XCTAssertEqual(environment.password, "secret-password")
        XCTAssertEqual(environment.oauthClientID, "https://pearchha.dev/app")
        XCTAssertEqual(environment.oauthRedirectURI, "pearchha://auth")
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
            .appendingPathComponent("pearchha-client-test-\(UUID().uuidString)", isDirectory: true)
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
        PEARCHHA_OAUTH_CLIENT_ID=https://file.pearchha.dev/app
        PEARCHHA_OAUTH_REDIRECT_URI=pearchha-file://auth
        """.write(to: fileURL, atomically: true, encoding: .utf8)

        let environment = try HAMirrorEnvironment.fromEnvironment([
            HAMirrorEnvironment.environmentFileEnvironmentKey: fileURL.path,
            HAMirrorEnvironment.tokenEnvironmentKey: "exported-token",
            HAMirrorEnvironment.oauthClientIDEnvironmentKey: "https://exported.pearchha.dev/app",
            HAMirrorEnvironment.oauthRedirectURIEnvironmentKey: "pearchha-exported://auth"
        ])

        XCTAssertEqual(environment.primaryURL.absoluteString, "http://file.homeassistant.local:8123")
        XCTAssertEqual(environment.fallbackURL?.absoluteString, "https://file.ui.nabu.casa")
        XCTAssertEqual(environment.token, "exported-token")
        XCTAssertEqual(environment.user, "file-user")
        XCTAssertEqual(environment.password, "file-password")
        XCTAssertEqual(environment.oauthClientID, "https://exported.pearchha.dev/app")
        XCTAssertEqual(environment.oauthRedirectURI, "pearchha-exported://auth")
    }

    func testMirrorEnvironmentFromEnvironmentOverridesMalformedExplicitEnvironmentFileWhenURLIsExported() throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("pearchha-client-test-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: directory)
        }
        let fileURL = directory.appendingPathComponent("mirror.env", isDirectory: false)
        try """
        PEARCHHA_OAUTH_CLIENT_ID
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
                HAMirrorEnvironment.environmentFileEnvironmentKey: "/tmp/pearchha-client-tests/missing.env"
            ])
        ) { error in
            XCTAssertEqual(
                error as? HAMirrorEnvironmentError,
                .missingFile("/tmp/pearchha-client-tests/missing.env")
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
                "Set token= in .env.local or export PEARCHHA_HA_TOKEN to a Home Assistant bearer access token before mirror capture. A long-lived access token works, or use the native OAuth sign-in flow and copy the resulting access token.",
                "user/password alone cannot authenticate the REST or WebSocket APIs. Keep them only for browser sign-in or manual work; mirror capture still needs token= in .env.local or PEARCHHA_HA_TOKEN in the process environment.",
                "If you want native OAuth sign-in instead of a long-lived token, set both PEARCHHA_OAUTH_CLIENT_ID and PEARCHHA_OAUTH_REDIRECT_URI in .env.local, or export both values, then run hamirror oauth-check --env .env.local."
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
            PEARCHHA_OAUTH_CLIENT_ID=https://pearchha.dev/app
            PEARCHHA_OAUTH_REDIRECT_URI=pearchha://auth
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
            PEARCHHA_OAUTH_CLIENT_ID=https://pearchha.dev/app
            PEARCHHA_OAUTH_REDIRECT_URI=pearchha://auth
            """
        )

        let report = environment.readinessReport

        XCTAssertFalse(report.canCaptureMirror)
        XCTAssertTrue(report.canCheckOAuthClientWebsite)
        XCTAssertEqual(report.issues, [.missingCaptureToken])
        XCTAssertEqual(
            report.nextSteps(envPath: ".env.local"),
            [
                "Set token= in .env.local or export PEARCHHA_HA_TOKEN to a Home Assistant bearer access token before mirror capture. A long-lived access token works, or use the native OAuth sign-in flow and copy the resulting access token."
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
            PEARCHHA_OAUTH_CLIENT_ID=https://pearchha.dev/app
            PEARCHHA_OAUTH_REDIRECT_URI=pearchha://auth
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
            PEARCHHA_OAUTH_CLIENT_ID=https://pearchha.dev/app
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
                "Set token= in .env.local or export PEARCHHA_HA_TOKEN to a Home Assistant bearer access token before mirror capture. A long-lived access token works, or use the native OAuth sign-in flow and copy the resulting access token.",
                "user/password alone cannot authenticate the REST or WebSocket APIs. Keep them only for browser sign-in or manual work; mirror capture still needs token= in .env.local or PEARCHHA_HA_TOKEN in the process environment.",
                "Set both PEARCHHA_OAUTH_CLIENT_ID and PEARCHHA_OAUTH_REDIRECT_URI in .env.local, or export both values, then rerun hamirror oauth-check --env .env.local."
            ]
        )
        XCTAssertEqual(decoded.suggestedCommands, [])
        XCTAssertFalse(text.contains("owner@example.invalid"))
        XCTAssertFalse(text.contains("secret-password"))
        XCTAssertFalse(text.contains("https://pearchha.dev/app"))
    }

    func testMirrorEnvironmentReadinessReportsIncompleteOAuthConfiguration() throws {
        let environment = try HAMirrorEnvironment.parse(
            """
            url=http://homeassistant.local:8123
            token=secret-token
            PEARCHHA_OAUTH_CLIENT_ID=https://pearchha.dev/app
            """
        )

        let report = environment.readinessReport

        XCTAssertTrue(report.canCaptureMirror)
        XCTAssertFalse(report.canCheckOAuthClientWebsite)
        XCTAssertEqual(report.issues, [.incompleteOAuthClientWebsiteConfiguration])
        XCTAssertEqual(
            report.nextSteps(envPath: ".env.local"),
            [
                "Set both PEARCHHA_OAUTH_CLIENT_ID and PEARCHHA_OAUTH_REDIRECT_URI in .env.local, or export both values, then rerun hamirror oauth-check --env .env.local."
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
                "OAuth client website check requires PEARCHHA_OAUTH_CLIENT_ID and PEARCHHA_OAUTH_REDIRECT_URI",
                "If you want native OAuth sign-in instead of a long-lived token, set both PEARCHHA_OAUTH_CLIENT_ID and PEARCHHA_OAUTH_REDIRECT_URI in .env.local, or export both values, then run hamirror oauth-check --env .env.local."
            ]
        )
    }

    func testMirrorEnvironmentOAuthCheckBlockingMessagesExplainIncompleteOAuthConfiguration() throws {
        let environment = try HAMirrorEnvironment.parse(
            """
            url=http://homeassistant.local:8123
            PEARCHHA_OAUTH_CLIENT_ID=https://pearchha.dev/app
            """
        )

        XCTAssertEqual(
            environment.readinessReport.oauthCheckBlockingMessages(envPath: ".env.local"),
            [
                "OAuth client website check requires PEARCHHA_OAUTH_CLIENT_ID and PEARCHHA_OAUTH_REDIRECT_URI",
                "Set both PEARCHHA_OAUTH_CLIENT_ID and PEARCHHA_OAUTH_REDIRECT_URI in .env.local, or export both values, then rerun hamirror oauth-check --env .env.local."
            ]
        )
    }

    func testMirrorEnvironmentReadinessNextStepsShellQuoteEnvPathCommands() throws {
        let environment = try HAMirrorEnvironment.parse(
            """
            url=http://homeassistant.local:8123
            PEARCHHA_OAUTH_CLIENT_ID=https://pearchha.dev/app
            """
        )

        XCTAssertEqual(
            environment.readinessReport.nextSteps(envPath: "/tmp/My Project/owner's env.local"),
            [
                "Set token= in /tmp/My Project/owner's env.local or export PEARCHHA_HA_TOKEN to a Home Assistant bearer access token before mirror capture. A long-lived access token works, or use the native OAuth sign-in flow and copy the resulting access token.",
                "Set both PEARCHHA_OAUTH_CLIENT_ID and PEARCHHA_OAUTH_REDIRECT_URI in /tmp/My Project/owner's env.local, or export both values, then rerun hamirror oauth-check --env '/tmp/My Project/owner'\"'\"'s env.local'."
            ]
        )
    }

    func testOAuthClientWebsiteEnvironmentParsesOAuthOnlyEnvFile() throws {
        let environment = try HAOAuthClientWebsiteEnvironment.parse(
            """
            PEARCHHA_OAUTH_CLIENT_ID=https://pearchha.dev/app
            PEARCHHA_OAUTH_REDIRECT_URI=pearchha://auth
            """
        )

        XCTAssertEqual(environment.clientID, "https://pearchha.dev/app")
        XCTAssertEqual(environment.redirectURI, "pearchha://auth")
    }

    func testOAuthClientWebsiteEnvironmentFromEnvironmentLoadsExplicitEnvironmentFile() throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("pearchha-client-test-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: directory)
        }
        let fileURL = directory.appendingPathComponent("oauth.env", isDirectory: false)
        try """
        PEARCHHA_OAUTH_CLIENT_ID=https://file.pearchha.dev/app
        PEARCHHA_OAUTH_REDIRECT_URI=pearchha-file://auth
        """.write(to: fileURL, atomically: true, encoding: .utf8)

        let environment = try HAOAuthClientWebsiteEnvironment.fromEnvironment([
            HAMirrorEnvironment.environmentFileEnvironmentKey: fileURL.path
        ])

        XCTAssertEqual(environment.clientID, "https://file.pearchha.dev/app")
        XCTAssertEqual(environment.redirectURI, "pearchha-file://auth")
    }

    func testOAuthClientWebsiteEnvironmentFromEnvironmentOverridesMissingExplicitEnvironmentFile() throws {
        let environment = try HAOAuthClientWebsiteEnvironment.fromEnvironment([
            HAMirrorEnvironment.environmentFileEnvironmentKey: "/tmp/pearchha-client-tests/missing-oauth.env",
            HAMirrorEnvironment.oauthClientIDEnvironmentKey: "https://exported.pearchha.dev/app",
            HAMirrorEnvironment.oauthRedirectURIEnvironmentKey: "pearchha-exported://auth"
        ])

        XCTAssertEqual(environment.clientID, "https://exported.pearchha.dev/app")
        XCTAssertEqual(environment.redirectURI, "pearchha-exported://auth")
    }

    func testOAuthClientWebsiteEnvironmentRejectsMissingOAuthKeys() {
        XCTAssertThrowsError(
            try HAOAuthClientWebsiteEnvironment.parse(
                """
                PEARCHHA_OAUTH_REDIRECT_URI=pearchha://auth
                """
            )
        ) { error in
            XCTAssertEqual(error as? HAMirrorEnvironmentError, .missingOAuthClientID)
        }
        XCTAssertThrowsError(
            try HAOAuthClientWebsiteEnvironment.parse(
                """
                PEARCHHA_OAUTH_CLIENT_ID=https://pearchha.dev/app
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
        XCTAssertEqual(requests.map { requestPercentEncodedPath($0.url) }, ["/api/", "/api/states"])
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
        XCTAssertEqual(requests.map { requestPercentEncodedPath($0.url) }, ["/ha/api/", "/ha/api/states"])
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

    func testStreamEntityStateChangesDeliversUpdatesAndStaysOpenUntilTheSocketEnds() async throws {
        let server = try FakeHAWebSocketServer()
        server.start()
        defer {
            server.stop()
        }
        let client = HomeAssistantClient()
        let input = HAConnectionInput(
            endpoint: HAEndpoint(urls: [server.baseURL]),
            token: "fake-token"
        )
        actor Collector {
            private(set) var states: [EntityState] = []
            func append(_ state: EntityState) {
                states.append(state)
            }
        }
        let collector = Collector()
        let streamTask = Task {
            await client.streamEntityStateChanges(input) { state in
                await collector.append(state)
            }
        }

        // The optimized subscription delivers the pushed update...
        var received: [EntityState] = []
        for _ in 0..<500 {
            received = await collector.states
            if !received.isEmpty {
                break
            }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertEqual(received.count, 1, "the stream delivers the pushed entity update")

        // ...and unlike the one-shot API the stream stays open after it. A
        // cancelled consumer must unblock the in-flight receive immediately
        // instead of hanging until the server's next frame.
        streamTask.cancel()
        let terminal = await streamTask.value
        if case .authentication = terminal {
            XCTFail("a cancelled stream must not report an authentication failure")
        }
    }

    func testStreamEntityStateChangesSurfacesCommandFailureWithoutFallingBack() async throws {
        let server = try FakeHAWebSocketServer(mode: .commandFailure)
        server.start()
        defer {
            server.stop()
        }
        let client = HomeAssistantClient()
        let input = HAConnectionInput(
            endpoint: HAEndpoint(urls: [server.baseURL]),
            token: "fake-token"
        )

        let terminal = await client.streamEntityStateChanges(input) { _ in
            XCTFail("stream should not deliver events when subscribe_entities fails")
        }

        XCTAssertEqual(
            terminal,
            .webSocketCommand(id: 1, code: "failed", message: "Planned command failure")
        )
        let paths = await server.journal.snapshot().map(\.path)
        XCTAssertFalse(paths.contains("/api/websocket/subscribe_events"))
    }

    func testStreamEntityStateChangesFallsBackToSubscribeEventsWhenSubscribeEntitiesIsUnknown() async throws {
        let fixtures = FakeHAFixtures(
            apiBody: #"{"message":"API running."}"#,
            statesBody: #"[]"#,
            stateChangedEventBody: #"{"entity_id":"sensor.office_temperature","state":"22.0","attributes":{"friendly_name":"Office temperature","unit_of_measurement":"°C"}}"#
        )
        let server = try FakeHAWebSocketServer(
            fixtures: fixtures,
            mode: .unavailableCommands(["subscribe_entities"], code: .unknownCommand)
        )
        server.start()
        defer {
            server.stop()
        }
        let client = HomeAssistantClient()
        let input = HAConnectionInput(
            endpoint: HAEndpoint(urls: [server.baseURL]),
            token: "fake-token"
        )
        actor Collector {
            private(set) var states: [EntityState] = []
            func append(_ state: EntityState) {
                states.append(state)
            }
        }
        let collector = Collector()
        let streamTask = Task {
            await client.streamEntityStateChanges(input) { state in
                await collector.append(state)
            }
        }

        var received: [EntityState] = []
        for _ in 0..<200 {
            received = await collector.states
            if !received.isEmpty {
                break
            }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertEqual(
            received,
            [EntityState(id: "sensor.office_temperature", name: "Office temperature", state: "22.0", unit: "°C")]
        )
        try await waitForJournalPath(server: server, path: "/api/websocket/subscribe_events")
        streamTask.cancel()
        _ = await streamTask.value
        let paths = await server.journal.snapshot().map(\.path)
        XCTAssertTrue(paths.contains("/api/websocket/subscribe_entities"))
        XCTAssertTrue(paths.contains("/api/websocket/subscribe_events"))
    }

    func testWebSocketCommandTimesOutAsUnreachableWhenServerGoesSilentAfterAuth() async throws {
        let server = try FakeHAWebSocketServer(mode: .silentAfterAuth)
        server.start()
        defer {
            server.stop()
        }
        let client = HomeAssistantClient(webSocketCommandTimeout: .milliseconds(200))
        let input = HAConnectionInput(
            endpoint: HAEndpoint(urls: [server.baseURL]),
            token: "fake-token"
        )

        // The server accepts auth and then never answers get_states. Without a
        // receive deadline this call suspended its caller forever.
        let result = await client.webSocketStates(input)

        guard case let .failure(failure) = result else {
            XCTFail("webSocketStates unexpectedly succeeded against a silent server")
            return
        }
        guard case .unreachable = failure else {
            XCTFail("expected unreachable after a silent-server timeout, got \(failure)")
            return
        }
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
        XCTAssertEqual(requests.map { requestPercentEncodedPath($0.url) }, ["/api/"])
    }

    func testMirrorCapturePropagatesMirrorCaptureErrorsFromTransport() async throws {
        let transport = RecordingMirrorTransport { _ in
            throw HAMirrorCaptureError.transportFailure(path: "/api/", message: "connection refused")
        }
        let environment = HAMirrorEnvironment(
            primaryURL: try XCTUnwrap(URL(string: "http://127.0.0.1:8123")),
            fallbackURL: nil,
            token: "secret-token",
            user: nil,
            password: nil
        )

        do {
            _ = try await HAMirrorCaptureService(transport: transport).capture(environment: environment)
            XCTFail("capture unexpectedly succeeded")
        } catch let error as HAMirrorCaptureError {
            XCTAssertEqual(error, .transportFailure(path: "/api/", message: "connection refused"))
        }
    }

    func testMirrorProbeReportsPrimaryReadyWithoutFallback() async throws {
        let transport = RecordingMirrorTransport()
        let service = HAMirrorCaptureService(transport: transport)
        let environment = HAMirrorEnvironment(
            primaryURL: try XCTUnwrap(URL(string: "http://127.0.0.1:8123")),
            fallbackURL: nil,
            token: "secret-token",
            user: nil,
            password: nil
        )

        let report = await service.probe(environment: environment)

        XCTAssertEqual(
            report,
            HAMirrorCaptureProbeReport(
                primary: HAMirrorCaptureEndpointProbe(
                    state: .ready,
                    message: "Home Assistant API responded successfully",
                    guidance: nil
                ),
                fallback: nil
            )
        )
        let requests = await transport.requests
        XCTAssertEqual(requests.map { requestPercentEncodedPath($0.url) }, ["/api/"])
    }

    func testMirrorProbeReportsRedactedPrimaryAndFallbackFailures() async throws {
        let transport = RecordingMirrorTransport { request in
            if request.url.host == "primary.local" {
                throw URLError(.cannotConnectToHost)
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

        let report = await service.probe(environment: environment)

        XCTAssertEqual(report.primary.state, .unavailable)
        XCTAssertTrue(
            report.primary.message.hasPrefix("Home Assistant request for /api/ failed:"),
            report.primary.message
        )
        XCTAssertTrue(report.primary.message.contains("/api/"))
        XCTAssertFalse(report.primary.message.contains("secret"))
        XCTAssertFalse(report.primary.message.contains("should-redact"))
        XCTAssertEqual(
            report.primary.guidance,
            "Verify the Home Assistant URL, local network or VPN reachability, DNS, and that the instance is running."
        )
        XCTAssertEqual(report.fallback?.state, .blocked)
        XCTAssertEqual(report.fallback?.message, "Home Assistant returned HTTP 401 for /api/")
        XCTAssertEqual(
            report.fallback?.guidance,
            "Refresh the long-lived access token and verify it belongs to this Home Assistant instance."
        )
        XCTAssertFalse(report.anyReady)
        XCTAssertFalse(report.primary.message.contains("primary.local"))
        XCTAssertFalse(report.fallback?.message.contains("fallback.example") == true)
    }

    func testMirrorProbeReportsMissingTokenGuidance() async throws {
        let transport = RecordingMirrorTransport()
        let service = HAMirrorCaptureService(transport: transport)
        let environment = HAMirrorEnvironment(
            primaryURL: try XCTUnwrap(URL(string: "http://127.0.0.1:8123")),
            fallbackURL: nil,
            token: nil,
            user: nil,
            password: nil
        )

        let report = await service.probe(environment: environment)

        XCTAssertEqual(report.primary.state, .blocked)
        XCTAssertEqual(report.primary.message, "missing token in environment file")
        XCTAssertEqual(
            report.primary.guidance,
            "Set token=... in the env file or export PEARCHHA_HA_TOKEN before probing Home Assistant."
        )
        let requests = await transport.requests
        XCTAssertTrue(requests.isEmpty)
    }

    func testMirrorProbeReports404GuidanceForBrokenBasePath() async throws {
        let transport = RecordingMirrorTransport { _ in
            HAMirrorResponse(
                statusCode: 404,
                headers: [:],
                body: Data(#"{"message":"missing"}"#.utf8)
            )
        }
        let service = HAMirrorCaptureService(transport: transport)
        let environment = HAMirrorEnvironment(
            primaryURL: try XCTUnwrap(URL(string: "http://127.0.0.1:8123/ha")),
            fallbackURL: nil,
            token: "secret-token",
            user: nil,
            password: nil
        )

        let report = await service.probe(environment: environment)

        XCTAssertEqual(report.primary.state, .unavailable)
        XCTAssertEqual(report.primary.message, "Home Assistant returned HTTP 404 for /api/")
        XCTAssertEqual(
            report.primary.guidance,
            "Verify the Home Assistant base URL and reverse-proxy path. The probe expects /api/ to exist on this host."
        )
    }

    func testMirrorProbeReportsServerErrorGuidanceWhenHAIsUnhealthy() async throws {
        let transport = RecordingMirrorTransport(apiStatusCode: 503, apiBody: #"{"message":"starting"}"#)
        let service = HAMirrorCaptureService(transport: transport)
        let environment = HAMirrorEnvironment(
            primaryURL: try XCTUnwrap(URL(string: "http://127.0.0.1:8123")),
            fallbackURL: nil,
            token: "secret-token",
            user: nil,
            password: nil
        )

        let report = await service.probe(environment: environment)

        XCTAssertEqual(report.primary.state, .unavailable)
        XCTAssertEqual(report.primary.message, "Home Assistant returned HTTP 503 for /api/")
        XCTAssertEqual(
            report.primary.guidance,
            "Home Assistant is reachable but unhealthy. Check the server logs and wait for the instance to finish starting."
        )
    }

    func testMirrorProbeReportsDefaultHTTPGuidanceForUnexpectedStatus() async throws {
        let transport = RecordingMirrorTransport(apiStatusCode: 418, apiBody: #"{"message":"teapot"}"#)
        let service = HAMirrorCaptureService(transport: transport)
        let environment = HAMirrorEnvironment(
            primaryURL: try XCTUnwrap(URL(string: "http://127.0.0.1:8123")),
            fallbackURL: nil,
            token: "secret-token",
            user: nil,
            password: nil
        )

        let report = await service.probe(environment: environment)

        XCTAssertEqual(report.primary.state, .unavailable)
        XCTAssertEqual(report.primary.message, "Home Assistant returned HTTP 418 for /api/")
        XCTAssertEqual(
            report.primary.guidance,
            "Verify the Home Assistant URL and that this instance allows API access at /api/."
        )
    }

    func testMirrorCaptureFallsBackToConfiguredFallbackURLOnPrimaryTransportFailure() async throws {
        let transport = RecordingMirrorTransport { request in
            if request.url.host == "primary.local" {
                throw RecordingMirrorTransportError(message: "connection refused")
            }
            return HAMirrorResponse(
                statusCode: 200,
                headers: ["Authorization": "Bearer should-redact"],
                body: Data((requestPercentEncodedPath(request.url) == "/api/" ? #"{"message":"API running."}"# : #"[]"#).utf8)
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
            requests.map { "\($0.url.host ?? "")|\(requestPercentEncodedPath($0.url))" },
            [
                "primary.local|/api/",
                "fallback.example|/api/",
                "fallback.example|/api/states"
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
            .appendingPathComponent("pearchha-client-test-\(UUID().uuidString)", isDirectory: true)
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
            .appendingPathComponent("pearchha-client-test-\(UUID().uuidString)", isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: directory)
        }

        let written = try HAMirrorFixtureWriter().write(fixtureSet, to: directory)

        XCTAssertEqual(written.map { $0.lastPathComponent }, ["api.json", "manifest.json", "states.json", "websocket.json"])
        XCTAssertTrue(FileManager.default.fileExists(atPath: directory.appendingPathComponent("websocket.json").path))
    }

    func testFixtureWriterRemovesStaleWebSocketEvidenceWhenWritingRestOnlyFixtures() throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("pearchha-client-test-\(UUID().uuidString)", isDirectory: true)
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

    func testFixtureSanitizerRejectsInvalidUTF8DataWithExplicitErrorDescription() {
        var sanitizer = HAMirrorFixtureSanitizer()

        XCTAssertThrowsError(try sanitizer.sanitize(path: "/api/states", body: Data([0xFF]))) { error in
            XCTAssertEqual(error as? HAMirrorFixtureSanitizationError, .invalidUTF8("/api/states"))
            XCTAssertEqual(
                (error as? HAMirrorFixtureSanitizationError)?.description,
                "fixture body for /api/states is not UTF-8"
            )
        }
    }

    func testFixtureSanitizerRejectsInvalidJSONTextWithExplicitErrorDescription() {
        var sanitizer = HAMirrorFixtureSanitizer()

        XCTAssertThrowsError(try sanitizer.sanitize(path: "/api/states", bodyText: "{")) { error in
            XCTAssertEqual(error as? HAMirrorFixtureSanitizationError, .invalidJSON("/api/states"))
            XCTAssertEqual(
                (error as? HAMirrorFixtureSanitizationError)?.description,
                "fixture body for /api/states is not JSON"
            )
        }
    }

    func testFixtureSanitizerNormalizesLocationsTimestampsAndUnsafeAttributes() throws {
        var sanitizer = HAMirrorFixtureSanitizer()
        let body = """
        [{
          "entity_id": "sensor.office_temperature",
          "last_changed": "2026-07-01T12:34:56+00:00",
          "attributes": {
            "latitude": 52.52,
            "longitude": 13.405,
            "gps_accuracy": 0,
            "device_class": "temperature",
            "friendly_name": "Office temperature",
            "note": "desk side"
          }
        }]
        """

        let sanitized = try sanitizer.sanitize(path: "/api/states", bodyText: body)

        XCTAssertTrue(sanitized.contains(#""entity_id":"sensor.entity_001""#))
        XCTAssertTrue(sanitized.contains(#""last_changed":"2026-01-01T00:00:00+00:00""#))
        XCTAssertTrue(sanitized.contains(#""latitude":0"#))
        XCTAssertTrue(sanitized.contains(#""longitude":0"#))
        XCTAssertTrue(sanitized.contains(#""gps_accuracy":0"#))
        XCTAssertTrue(sanitized.contains(#""device_class":"temperature""#))
        XCTAssertTrue(sanitized.contains(#""friendly_name":"<redacted>""#))
        XCTAssertTrue(sanitized.contains(#""note":"<redacted>""#))
        XCTAssertFalse(sanitized.contains("52.52"))
        XCTAssertFalse(sanitized.contains("13.405"))
        XCTAssertFalse(sanitized.contains("Office temperature"))
        XCTAssertFalse(sanitized.contains("desk side"))
    }

    func testFixtureSanitizerAliasesEntityIDArraysAndKeepsStableSyntheticIDs() throws {
        var sanitizer = HAMirrorFixtureSanitizer()
        let body = """
        {
          "entity_id": ["sensor.kitchen_temperature", "light.desk", "sensor.entity_999"],
          "attributes": {
            "supported_features": 3
          }
        }
        """

        let sanitized = try sanitizer.sanitize(path: "/api/test", bodyText: body)

        XCTAssertTrue(sanitized.contains(#""entity_id":["sensor.entity_001","light.entity_002","sensor.entity_999"]"#))
        XCTAssertTrue(sanitized.contains(#""supported_features":3"#))
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

    func testFixtureVerifierRejectsManifestWebSocketWithoutFile() throws {
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
        try FileManager.default.removeItem(at: directory.appendingPathComponent("websocket.json"))

        XCTAssertThrowsError(try HAMirrorFixtureVerifier().verify(directory: directory)) { error in
            XCTAssertEqual(error as? HAMirrorFixtureVerificationError, .missingFiles(["websocket.json"]))
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

    func testFixtureVerifierRejectsManifestWebSocketMismatch() throws {
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
        let mismatchedWebSocket = """
        {
          "entityRegistryDisplayList": {
            "command": "config/entity_registry/list_for_display",
            "available": true,
            "errorCode": null,
            "errorMessage": null,
            "eventKeys": []
          },
          "subscribeEntities": {
            "command": "subscribe_entities",
            "available": false,
            "errorCode": "unsupported_command",
            "errorMessage": "Command unavailable",
            "eventKeys": []
          }
        }
        """
        try mismatchedWebSocket.write(to: directory.appendingPathComponent("websocket.json"), atomically: true, encoding: .utf8)

        XCTAssertThrowsError(try HAMirrorFixtureVerifier().verify(directory: directory)) { error in
            XCTAssertEqual(error as? HAMirrorFixtureVerificationError, .manifestMismatch)
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
            .appendingPathComponent("pearchha-client-test-\(UUID().uuidString)", isDirectory: true)
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

    func testFixtureVerifierRejectsMalformedManifestJSON() throws {
        let fixtureSet = HAMirrorFixtureSet(
            api: HAMirrorCapturedEndpoint(method: "GET", path: "/api/", statusCode: 200, headers: [:], bodyText: #"{"message":"API running."}"#),
            states: HAMirrorCapturedEndpoint(method: "GET", path: "/api/states", statusCode: 200, headers: [:], bodyText: "[]")
        )
        let directory = try writeFixtureSet(fixtureSet)
        defer {
            try? FileManager.default.removeItem(at: directory)
        }
        try "{".write(to: directory.appendingPathComponent("manifest.json"), atomically: true, encoding: .utf8)

        XCTAssertThrowsError(try HAMirrorFixtureVerifier().verify(directory: directory)) { error in
            XCTAssertEqual(error as? HAMirrorFixtureVerificationError, .malformedFile("manifest.json"))
        }
    }

    func testFixtureVerifierAcceptsManifestWithNullWebSocketEvidence() throws {
        let fixtureSet = HAMirrorFixtureSet(
            api: HAMirrorCapturedEndpoint(method: "GET", path: "/api/", statusCode: 200, headers: [:], bodyText: #"{"message":"API running."}"#),
            states: HAMirrorCapturedEndpoint(method: "GET", path: "/api/states", statusCode: 200, headers: [:], bodyText: "[]")
        )
        let directory = try writeFixtureSet(fixtureSet)
        defer {
            try? FileManager.default.removeItem(at: directory)
        }
        let manifestWithNullWebSocket = """
        {
          "api": {
            "method": "GET",
            "path": "/api/",
            "statusCode": 200,
            "headers": {},
            "bodyText": "{\\"message\\":\\"API running.\\"}"
          },
          "states": {
            "method": "GET",
            "path": "/api/states",
            "statusCode": 200,
            "headers": {},
            "bodyText": "[]"
          },
          "webSocket": null
        }
        """
        try manifestWithNullWebSocket.write(to: directory.appendingPathComponent("manifest.json"), atomically: true, encoding: .utf8)

        XCTAssertEqual(try HAMirrorFixtureVerifier().verify(directory: directory), fixtureSet)
    }

    func testFixtureVerifierRejectsMissingStatesFile() throws {
        let fixtureSet = HAMirrorFixtureSet(
            api: HAMirrorCapturedEndpoint(method: "GET", path: "/api/", statusCode: 200, headers: [:], bodyText: #"{"message":"API running."}"#),
            states: HAMirrorCapturedEndpoint(method: "GET", path: "/api/states", statusCode: 200, headers: [:], bodyText: "[]")
        )
        let directory = try writeFixtureSet(fixtureSet)
        defer {
            try? FileManager.default.removeItem(at: directory)
        }
        try FileManager.default.removeItem(at: directory.appendingPathComponent("states.json"))

        XCTAssertThrowsError(try HAMirrorFixtureVerifier().verify(directory: directory)) { error in
            XCTAssertEqual(error as? HAMirrorFixtureVerificationError, .missingFiles(["states.json"]))
        }
    }

    func testFixtureVerifierRejectsNonGetEndpointMethod() throws {
        let fixtureSet = HAMirrorFixtureSet(
            api: HAMirrorCapturedEndpoint(method: "POST", path: "/api/", statusCode: 200, headers: [:], bodyText: #"{"message":"API running."}"#),
            states: HAMirrorCapturedEndpoint(method: "GET", path: "/api/states", statusCode: 200, headers: [:], bodyText: "[]")
        )
        let directory = try writeFixtureSet(fixtureSet)
        defer {
            try? FileManager.default.removeItem(at: directory)
        }

        XCTAssertThrowsError(try HAMirrorFixtureVerifier().verify(directory: directory)) { error in
            XCTAssertEqual(
                error as? HAMirrorFixtureVerificationError,
                .invalidEndpoint(file: "api.json", reason: "method must be GET")
            )
        }
    }

    func testFixtureVerifierRejectsWrongEndpointPath() throws {
        let fixtureSet = HAMirrorFixtureSet(
            api: HAMirrorCapturedEndpoint(method: "GET", path: "/wrong", statusCode: 200, headers: [:], bodyText: #"{"message":"API running."}"#),
            states: HAMirrorCapturedEndpoint(method: "GET", path: "/api/states", statusCode: 200, headers: [:], bodyText: "[]")
        )
        let directory = try writeFixtureSet(fixtureSet)
        defer {
            try? FileManager.default.removeItem(at: directory)
        }

        XCTAssertThrowsError(try HAMirrorFixtureVerifier().verify(directory: directory)) { error in
            XCTAssertEqual(
                error as? HAMirrorFixtureVerificationError,
                .invalidEndpoint(file: "api.json", reason: "path must be /api/")
            )
        }
    }

    func testFixtureVerifierRejectsNonSuccessStatus() throws {
        let fixtureSet = HAMirrorFixtureSet(
            api: HAMirrorCapturedEndpoint(method: "GET", path: "/api/", statusCode: 503, headers: [:], bodyText: #"{"message":"API running."}"#),
            states: HAMirrorCapturedEndpoint(method: "GET", path: "/api/states", statusCode: 200, headers: [:], bodyText: "[]")
        )
        let directory = try writeFixtureSet(fixtureSet)
        defer {
            try? FileManager.default.removeItem(at: directory)
        }

        XCTAssertThrowsError(try HAMirrorFixtureVerifier().verify(directory: directory)) { error in
            XCTAssertEqual(
                error as? HAMirrorFixtureVerificationError,
                .invalidEndpoint(file: "api.json", reason: "status must be 2xx")
            )
        }
    }

    func testFixtureVerifierRejectsLeakedAuthorizationHeader() throws {
        let fixtureSet = HAMirrorFixtureSet(
            api: HAMirrorCapturedEndpoint(
                method: "GET",
                path: "/api/",
                statusCode: 200,
                headers: ["Authorization": "Bearer secret-token"],
                bodyText: #"{"message":"API running."}"#
            ),
            states: HAMirrorCapturedEndpoint(method: "GET", path: "/api/states", statusCode: 200, headers: [:], bodyText: "[]")
        )
        let directory = try writeFixtureSet(fixtureSet)
        defer {
            try? FileManager.default.removeItem(at: directory)
        }

        XCTAssertThrowsError(try HAMirrorFixtureVerifier().verify(directory: directory)) { error in
            XCTAssertEqual(error as? HAMirrorFixtureVerificationError, .leakedHeader(path: "/api/"))
        }
    }

    func testFixtureVerifierRejectsEndpointBodyWhenSanitizerThrows() throws {
        let fixtureSet = HAMirrorFixtureSet(
            api: HAMirrorCapturedEndpoint(method: "GET", path: "/api/", statusCode: 200, headers: [:], bodyText: "{"),
            states: HAMirrorCapturedEndpoint(method: "GET", path: "/api/states", statusCode: 200, headers: [:], bodyText: "[]")
        )
        let directory = try writeFixtureSet(fixtureSet)
        defer {
            try? FileManager.default.removeItem(at: directory)
        }

        XCTAssertThrowsError(try HAMirrorFixtureVerifier().verify(directory: directory)) { error in
            XCTAssertEqual(
                error as? HAMirrorFixtureVerificationError,
                .invalidEndpoint(file: "api.json", reason: "fixture body for /api/ is not JSON")
            )
        }
    }

    func testFixtureVerifierRejectsManifestWithUnexpectedFields() throws {
        let fixtureSet = HAMirrorFixtureSet(
            api: HAMirrorCapturedEndpoint(method: "GET", path: "/api/", statusCode: 200, headers: [:], bodyText: #"{"message":"API running."}"#),
            states: HAMirrorCapturedEndpoint(method: "GET", path: "/api/states", statusCode: 200, headers: [:], bodyText: "[]")
        )
        let directory = try writeFixtureSet(fixtureSet)
        defer {
            try? FileManager.default.removeItem(at: directory)
        }
        let manifest: [String: Any] = [
            "api": [
                "method": "GET",
                "path": "/api/",
                "statusCode": 200,
                "headers": [:],
                "bodyText": #"{"message":"API running."}"#
            ],
            "states": [
                "method": "GET",
                "path": "/api/states",
                "statusCode": 200,
                "headers": [:],
                "bodyText": "[]"
            ],
            "secret": "nope"
        ]
        let data = try JSONSerialization.data(withJSONObject: manifest, options: [.sortedKeys])
        try data.write(to: directory.appendingPathComponent("manifest.json"))

        XCTAssertThrowsError(try HAMirrorFixtureVerifier().verify(directory: directory)) { error in
            XCTAssertEqual(
                error as? HAMirrorFixtureVerificationError,
                .invalidWebSocketEvidence(reason: "manifest contains unexpected fields")
            )
        }
    }

    func testFixtureVerifierRejectsWebSocketCommandEvidenceUnexpectedFields() throws {
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
        let malformedWebSocket = """
        {
          "entityRegistryDisplayList": {
            "command": "config/entity_registry/list_for_display",
            "available": true,
            "eventKeys": [],
            "extra": true
          },
          "subscribeEntities": {
            "command": "subscribe_entities",
            "available": true,
            "eventKeys": []
          }
        }
        """
        try malformedWebSocket.write(to: directory.appendingPathComponent("websocket.json"), atomically: true, encoding: .utf8)

        XCTAssertThrowsError(try HAMirrorFixtureVerifier().verify(directory: directory)) { error in
            XCTAssertEqual(
                error as? HAMirrorFixtureVerificationError,
                .invalidWebSocketEvidence(reason: "websocket.json.entityRegistryDisplayList contains unexpected fields")
            )
        }
    }

    func testFixtureVerifierRejectsMalformedWebSocketJSON() throws {
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
        try "{".write(to: directory.appendingPathComponent("websocket.json"), atomically: true, encoding: .utf8)

        XCTAssertThrowsError(try HAMirrorFixtureVerifier().verify(directory: directory)) { error in
            XCTAssertEqual(error as? HAMirrorFixtureVerificationError, .malformedFile("websocket.json"))
        }
    }

    func testFixtureVerifierRejectsNonObjectWebSocketEvidenceFile() throws {
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
        try "[]".write(to: directory.appendingPathComponent("websocket.json"), atomically: true, encoding: .utf8)

        XCTAssertThrowsError(try HAMirrorFixtureVerifier().verify(directory: directory)) { error in
            XCTAssertEqual(
                error as? HAMirrorFixtureVerificationError,
                .invalidWebSocketEvidence(reason: "websocket.json must be an object")
            )
        }
    }

    func testFixtureVerifierRejectsNonObjectWebSocketCommandEvidence() throws {
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
        let malformedWebSocket = """
        {
          "entityRegistryDisplayList": [],
          "subscribeEntities": {
            "command": "subscribe_entities",
            "available": true,
            "eventKeys": []
          }
        }
        """
        try malformedWebSocket.write(to: directory.appendingPathComponent("websocket.json"), atomically: true, encoding: .utf8)

        XCTAssertThrowsError(try HAMirrorFixtureVerifier().verify(directory: directory)) { error in
            XCTAssertEqual(
                error as? HAMirrorFixtureVerificationError,
                .invalidWebSocketEvidence(reason: "websocket.json.entityRegistryDisplayList must be an object")
            )
        }
    }

    func testFixtureVerifierRejectsWebSocketEvidenceWithInvalidOptionalTypes() throws {
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
        let malformedWebSocket = """
        {
          "entityRegistryDisplayList": {
            "command": "config/entity_registry/list_for_display",
            "available": true,
            "errorCode": 404,
            "eventKeys": []
          },
          "subscribeEntities": {
            "command": "subscribe_entities",
            "available": true,
            "eventKeys": []
          }
        }
        """
        try malformedWebSocket.write(to: directory.appendingPathComponent("websocket.json"), atomically: true, encoding: .utf8)

        XCTAssertThrowsError(try HAMirrorFixtureVerifier().verify(directory: directory)) { error in
            XCTAssertEqual(
                error as? HAMirrorFixtureVerificationError,
                .invalidWebSocketEvidence(reason: "websocket.json.entityRegistryDisplayList.errorCode must be a string or null")
            )
        }
    }

    func testFixtureVerifierRejectsWebSocketCommandEvidenceInvalidFieldTypes() throws {
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
        let malformedWebSocket = """
        {
          "entityRegistryDisplayList": {
            "command": 404,
            "available": true,
            "eventKeys": []
          },
          "subscribeEntities": {
            "command": "subscribe_entities",
            "available": true,
            "eventKeys": []
          }
        }
        """
        try malformedWebSocket.write(to: directory.appendingPathComponent("websocket.json"), atomically: true, encoding: .utf8)

        XCTAssertThrowsError(try HAMirrorFixtureVerifier().verify(directory: directory)) { error in
            XCTAssertEqual(
                error as? HAMirrorFixtureVerificationError,
                .invalidWebSocketEvidence(reason: "websocket.json.entityRegistryDisplayList has invalid field types")
            )
        }
    }

    func testFixtureVerifierRejectsUnexpectedWebSocketCommandName() throws {
        let fixtureSet = HAMirrorFixtureSet(
            api: HAMirrorCapturedEndpoint(method: "GET", path: "/api/", statusCode: 200, headers: [:], bodyText: #"{"message":"API running."}"#),
            states: HAMirrorCapturedEndpoint(method: "GET", path: "/api/states", statusCode: 200, headers: [:], bodyText: "[]"),
            webSocket: HAMirrorWebSocketEvidence(
                entityRegistryDisplayList: HAMirrorWebSocketCommandEvidence(
                    command: "private_dump",
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

        XCTAssertThrowsError(try HAMirrorFixtureVerifier().verify(directory: directory)) { error in
            XCTAssertEqual(
                error as? HAMirrorFixtureVerificationError,
                .invalidWebSocketEvidence(reason: "unexpected command private_dump")
            )
        }
    }

    func testFixtureVerifierRejectsUnredactedWebSocketErrorMessage() throws {
        let fixtureSet = HAMirrorFixtureSet(
            api: HAMirrorCapturedEndpoint(method: "GET", path: "/api/", statusCode: 200, headers: [:], bodyText: #"{"message":"API running."}"#),
            states: HAMirrorCapturedEndpoint(method: "GET", path: "/api/states", statusCode: 200, headers: [:], bodyText: "[]"),
            webSocket: HAMirrorWebSocketEvidence(
                entityRegistryDisplayList: HAMirrorWebSocketCommandEvidence(
                    command: "config/entity_registry/list_for_display",
                    available: false,
                    errorCode: "unsupported_command",
                    errorMessage: "token=secret-token leaked"
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

        XCTAssertThrowsError(try HAMirrorFixtureVerifier().verify(directory: directory)) { error in
            XCTAssertEqual(
                error as? HAMirrorFixtureVerificationError,
                .invalidWebSocketEvidence(reason: "unredacted error message for config/entity_registry/list_for_display")
            )
        }
    }

    func testMirrorErrorDescriptionsStayStable() {
        XCTAssertEqual(HAMirrorCaptureError.missingToken.description, "missing token in environment file")
        XCTAssertEqual(HAMirrorCaptureError.nonHTTPResponse.description, "Home Assistant returned a non-HTTP response")
        XCTAssertEqual(HAMirrorCaptureError.invalidPath("bad").description, "invalid Home Assistant path: bad")
        XCTAssertEqual(
            HAMirrorCaptureError.transportFailure(path: "/api/", message: "connection refused").description,
            "Home Assistant request for /api/ failed: connection refused"
        )
        XCTAssertEqual(
            HAMirrorCaptureError.unexpectedStatus(path: "/api/", statusCode: 418).description,
            "Home Assistant returned HTTP 418 for /api/"
        )
        XCTAssertEqual(
            HAMirrorCaptureError.primaryAndFallbackFailed(
                path: "/api/",
                primaryFailure: "primary down",
                fallbackFailure: "fallback unauthorized"
            ).description,
            "Home Assistant request for /api/ failed on both primary and fallback: primary=primary down; fallback=fallback unauthorized"
        )
        XCTAssertEqual(HAMirrorCaptureError.webSocketAuthentication.description, "Home Assistant rejected the WebSocket token")
        XCTAssertEqual(
            HAMirrorCaptureError.webSocketProtocol("oops").description,
            "Home Assistant WebSocket protocol error: oops"
        )
        XCTAssertEqual(HAMirrorCaptureError.webSocketTimeout.description, "Home Assistant WebSocket did not respond before the timeout")

        XCTAssertEqual(
            HAMirrorFixtureVerificationError.missingFiles(["api.json", "states.json"]).description,
            "missing fixture files: api.json, states.json"
        )
        XCTAssertEqual(HAMirrorFixtureVerificationError.malformedFile("api.json").description, "malformed fixture file: api.json")
        XCTAssertEqual(HAMirrorFixtureVerificationError.manifestMismatch.description, "manifest does not match endpoint fixture files")
        XCTAssertEqual(
            HAMirrorFixtureVerificationError.invalidEndpoint(file: "api.json", reason: "method must be GET").description,
            "invalid fixture endpoint in api.json: method must be GET"
        )
        XCTAssertEqual(
            HAMirrorFixtureVerificationError.invalidWebSocketEvidence(reason: "bad").description,
            "invalid WebSocket fixture evidence: bad"
        )
        XCTAssertEqual(
            HAMirrorFixtureVerificationError.leakedHeader(path: "/api/").description,
            "fixture headers for /api/ contain unredacted secrets"
        )
        XCTAssertEqual(
            HAMirrorFixtureVerificationError.unsanitizedBody(path: "/api/").description,
            "fixture body for /api/ is not sanitized"
        )
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
        let response = responses.removeFirst()
        switch response {
        case let .success(value):
            return value
        case .nonHTTPResponse:
            throw HAClientTransportError.nonHTTPResponse
        case let .urlError(error):
            throw error
        case let .transportError(message):
            throw RecordingHARESTTransportError(message: message)
        }
    }
}

enum RecordingHARESTTransportResponse: Sendable {
    case success(HARESTResponse)
    case nonHTTPResponse
    case urlError(URLError)
    case transportError(String)
}

struct RecordingHARESTTransportError: Error, CustomStringConvertible, Sendable {
    let message: String

    var description: String {
        message
    }
}

struct RecordingMirrorTransportError: Error, CustomStringConvertible, Sendable {
    let message: String
    var description: String { message }
}

private func writeFixtureSet(_ fixtureSet: HAMirrorFixtureSet) throws -> URL {
    let directory = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("pearchha-client-test-\(UUID().uuidString)", isDirectory: true)
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
        let isAPI = requestPercentEncodedPath(request.url) == "/api/"
        let body = isAPI ? apiBody : statesBody
        return HAMirrorResponse(
            statusCode: isAPI ? apiStatusCode : statesStatusCode,
            headers: ["Authorization": "Bearer should-redact"],
            body: Data(body.utf8)
        )
    }

}

private func waitForJournalCount(server: FakeHAWebSocketServer, count: Int) async throws {
    for _ in 0..<500 {
        if await server.journal.snapshot().count >= count {
            return
        }
        try await Task.sleep(nanoseconds: 10_000_000)
    }
    throw ClientTestFailure("FakeHA WebSocket journal did not reach \(count)")
}

private func waitForJournalPath(server: FakeHAWebSocketServer, path: String) async throws {
    for _ in 0..<500 {
        if await server.journal.snapshot().contains(where: { $0.path == path }) {
            return
        }
        try await Task.sleep(nanoseconds: 10_000_000)
    }
    throw ClientTestFailure("FakeHA WebSocket journal did not contain \(path)")
}

private func waitForRESTServerReady(baseURL: URL) async throws {
    let url = baseURL.appendingPathComponent("api/")
    let session = URLSession(configuration: .ephemeral)
    for _ in 0..<200 {
        do {
            let (_, response) = try await session.data(from: url)
            if let http = response as? HTTPURLResponse, (200..<500).contains(http.statusCode) {
                return
            }
        } catch {
            try await Task.sleep(nanoseconds: 10_000_000)
        }
    }
    throw ClientTestFailure("FakeHA REST server did not become ready at \(url.absoluteString)")
}

struct ClientTestFailure: Error, CustomStringConvertible {
    let description: String

    init(_ description: String) {
        self.description = description
    }
}

extension PearchHAClientTests {
    func testHomeAssistantClientIdentifiesModule() {
        XCTAssertEqual(HomeAssistantClient().describe().name, "PearchHAClient")
    }

    func testOAuthAuthorizationURLRejectsBlankClientID() throws {
        let client = HomeAssistantClient()
        let request = HAOAuthAuthorizationRequest(
            baseURL: try XCTUnwrap(URL(string: "https://homeassistant.local")),
            clientID: "   ",
            redirectURI: "pearchha://auth",
            state: "state"
        )

        XCTAssertEqual(
            client.authorizationURL(for: request),
            .failure(.invalidPayload(path: "/auth/authorize", reason: "client_id is required"))
        )
    }

    func testPlannedClientChecksRESTConnectionThroughItsTransport() async throws {
        let transport = RecordingHARESTTransport(
            responses: [
                .success(HARESTResponse(statusCode: 200, headers: [:], body: Data(#"{"message":"API running."}"#.utf8)))
            ]
        )
        let client = PlannedHAClient(transport: transport)

        let result = await client.checkRESTConnection(try connectionInput())

        XCTAssertEqual(result, .success(HARESTCheck(message: "API running.")))
        let requests = await transport.requests
        XCTAssertEqual(requests.map { requestPercentEncodedPath($0.url) }, ["/api/"])
        XCTAssertEqual(requests.first?.headers["Authorization"], "Bearer secret-token")
    }

    func testPlannedClientFetchesStatesThroughItsTransport() async throws {
        let body = """
        [
          {
            "entity_id": "sensor.office_temperature",
            "state": "21.4",
            "attributes": {
              "friendly_name": "Office temperature",
              "unit_of_measurement": "°C"
            }
          }
        ]
        """
        let transport = RecordingHARESTTransport(
            responses: [
                .success(HARESTResponse(statusCode: 200, headers: [:], body: Data(body.utf8)))
            ]
        )
        let client = PlannedHAClient(transport: transport)

        let result = await client.states(try connectionInput())

        XCTAssertEqual(
            result,
            .success([
                EntityState(id: "sensor.office_temperature", name: "Office temperature", state: "21.4", unit: "°C")
            ])
        )
        let requests = await transport.requests
        XCTAssertEqual(requests.map { requestPercentEncodedPath($0.url) }, ["/api/states"])
    }

    func testPlannedClientChecksWebSocketConnectionAgainstFakeHA() async throws {
        let server = try FakeHAWebSocketServer()
        server.start()
        defer {
            server.stop()
        }
        _ = try FakeHARawWebSocketProbe().authenticateWithCoalescedUpgrade(baseURL: server.baseURL)
        let client = PlannedHAClient()
        let input = HAConnectionInput(
            endpoint: HAEndpoint(primaryURL: server.baseURL, fallbackURL: nil),
            token: "fake-token"
        )

        await assertEqualAsync(await client.checkWebSocketConnection(input), .success(HAWebSocketCheck(haVersion: "fake-ha")))
    }

    func testPlannedClientFetchesWebSocketStatesAgainstFakeHA() async throws {
        let fixtures = FakeHAFixtures(
            apiBody: #"{"message":"API running."}"#,
            statesBody: #"[{"entity_id":"sensor.office_temperature","state":"21.4","attributes":{"friendly_name":"Office temperature","unit_of_measurement":"°C"}}]"#
        )
        let server = try FakeHAWebSocketServer(fixtures: fixtures)
        server.start()
        defer {
            server.stop()
        }
        let client = PlannedHAClient()
        let input = HAConnectionInput(
            endpoint: HAEndpoint(primaryURL: server.baseURL, fallbackURL: nil),
            token: "fake-token"
        )

        await assertEqualAsync(
            await client.webSocketStates(input),
            .success([
                EntityState(id: "sensor.office_temperature", name: "Office temperature", state: "21.4", unit: "°C")
            ])
        )
    }

    func testPlannedClientFetchesNextStateChangedEventAgainstFakeHA() async throws {
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
        let client = PlannedHAClient()
        let input = HAConnectionInput(
            endpoint: HAEndpoint(primaryURL: server.baseURL, fallbackURL: nil),
            token: "fake-token"
        )

        await assertEqualAsync(
            await client.nextStateChangedEvent(input),
            .success(EntityState(id: "sensor.office_temperature", name: "Office temperature", state: "22.0", unit: "°C"))
        )
    }

    func testPlannedClientFetchesServicesAgainstFakeHA() async throws {
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
        let client = PlannedHAClient()
        let input = HAConnectionInput(
            endpoint: HAEndpoint(primaryURL: server.baseURL, fallbackURL: nil),
            token: "fake-token"
        )

        await assertEqualAsync(
            await client.services(input),
            .success([
                HAServiceMetadata(
                    domain: "script",
                    service: "turn_on",
                    name: "Turn on",
                    description: "Runs a script.",
                    fields: [
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
    }

    func testPlannedClientCallsServiceAgainstFakeHA() async throws {
        let server = try FakeHAWebSocketServer()
        server.start()
        defer {
            server.stop()
        }
        let client = PlannedHAClient()
        let input = HAConnectionInput(
            endpoint: HAEndpoint(primaryURL: server.baseURL, fallbackURL: nil),
            token: "fake-token"
        )

        await assertEqualAsync(
            await client.callService(
                input,
                call: HAServiceCall(domain: "switch", service: "turn_on", targetEntityID: "switch.office_lamp")
            ),
            .success(HAServiceCallResult(contextID: "fake-context"))
        )
        try await waitForJournalPath(server: server, path: "/api/websocket/call_service")
    }

    func testPlannedClientFetchesDiscoveryAgainstFakeHA() async throws {
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
        let client = PlannedHAClient()
        let input = HAConnectionInput(
            endpoint: HAEndpoint(primaryURL: server.baseURL, fallbackURL: nil),
            token: "fake-token"
        )

        await assertEqualAsync(
            await client.discovery(input),
            .success(
                DiscoverySnapshot(
                    areas: [Area(id: "office", name: "Office")],
                    devices: [],
                    entities: [EntityRegistryEntry(id: "sensor.office_temperature", name: "Display name", areaID: "office", deviceID: nil)],
                    states: [EntityState(id: "sensor.office_temperature", name: "State name", state: "21.4", unit: "°C")]
                )
            )
        )
    }

    func testPlannedClientFetchesHistoryThroughItsTransport() async throws {
        let historyBody = """
        [[
          {"entity_id":"sensor.office_temperature","state":"21.4","last_changed":"2026-06-27T10:30:00+00:00"},
          {"state":"22.0","last_changed":"2026-06-27T11:00:00+00:00"}
        ]]
        """
        let transport = RecordingHARESTTransport(
            responses: [
                .success(HARESTResponse(statusCode: 200, headers: [:], body: Data(historyBody.utf8)))
            ]
        )
        let client = PlannedHAClient(transport: transport)

        let result = await client.history(
            try connectionInput(),
            entityID: "sensor.office_temperature",
            range: .hour,
            end: try historyDate("2026-06-27T12:00:00+00:00")
        )

        XCTAssertEqual(
            result,
            .success(
                HistorySeries(
                    entityID: "sensor.office_temperature",
                    range: .hour,
                    samples: [
                        HistorySample(timestamp: try historyDate("2026-06-27T10:30:00+00:00"), state: "21.4", numericValue: 21.4),
                        HistorySample(timestamp: try historyDate("2026-06-27T11:00:00+00:00"), state: "22.0", numericValue: 22.0)
                    ]
                )
            )
        )
    }

    func testPlannedClientFetchesHistoryBatchThroughItsTransport() async throws {
        let historyBody = """
        [
          [
            {"entity_id":"sensor.a","state":"1.0","last_changed":"2026-06-27T10:00:00+00:00"},
            {"state":"2.0","last_changed":"2026-06-27T11:00:00+00:00"}
          ],
          [
            {"entity_id":"sensor.b","state":"5.0","last_changed":"2026-06-27T10:30:00+00:00"}
          ]
        ]
        """
        let transport = RecordingHARESTTransport(
            responses: [
                .success(HARESTResponse(statusCode: 200, headers: [:], body: Data(historyBody.utf8)))
            ]
        )
        let client = PlannedHAClient(transport: transport)

        let result = await client.historyBatch(
            try connectionInput(),
            entityIDs: ["sensor.a", "sensor.b"],
            range: .hour,
            end: try historyDate("2026-06-27T12:00:00+00:00")
        )

        guard case let .success(series) = result else {
            XCTFail("planned client bulk history unexpectedly failed: \(result)")
            return
        }
        XCTAssertEqual(series["sensor.a"]?.samples.count, 2)
        XCTAssertEqual(series["sensor.b"]?.samples.count, 1)
    }

    func testOAuthClientWebsiteReportsHTTPStatusWhenFetchFails() async {
        let transport = RecordingHARESTTransport(
            responses: [
                .success(HARESTResponse(statusCode: 503, headers: [:], body: Data("offline".utf8)))
            ]
        )

        let result = await HomeAssistantClient(transport: transport).verifyOAuthClientWebsite(
            clientID: "https://pearchha.dev/app",
            redirectURI: "pearchha://auth"
        )

        XCTAssertEqual(result, .failure(.httpStatus(path: "https://pearchha.dev/app", statusCode: 503)))
    }

    func testOAuthClientWebsiteMapsNonHTTPResponseToInvalidResponse() async {
        let transport = RecordingHARESTTransport(
            responses: [
                .nonHTTPResponse
            ]
        )

        let result = await HomeAssistantClient(transport: transport).verifyOAuthClientWebsite(
            clientID: "https://pearchha.dev/app",
            redirectURI: "pearchha://auth"
        )

        XCTAssertEqual(result, .failure(.invalidResponse(path: "https://pearchha.dev/app")))
    }

    func testOAuthClientWebsiteMapsTransportURLFailure() async {
        let transport = RecordingHARESTTransport(
            responses: [
                .urlError(URLError(.timedOut))
            ]
        )

        let result = await HomeAssistantClient(transport: transport).verifyOAuthClientWebsite(
            clientID: "https://pearchha.dev/app",
            redirectURI: "pearchha://auth"
        )

        XCTAssertEqual(result, .failure(.unreachable(host: "pearchha.dev")))
    }

    func testOAuthClientWebsiteRedactsGenericTransportFailure() async {
        let transport = RecordingHARESTTransport(
            responses: [
                .transportError("site fetch failed for pearchha://auth code=secret")
            ]
        )

        let result = await HomeAssistantClient(transport: transport).verifyOAuthClientWebsite(
            clientID: "https://pearchha.dev/app",
            redirectURI: "pearchha://auth"
        )

        XCTAssertEqual(result, .failure(.transport("site fetch failed for pearchha://auth code=<redacted>")))
    }

    func testOAuthCodeExchangeRejectsBlankAuthorizationCodeBeforeNetwork() async throws {
        let transport = RecordingHARESTTransport(responses: [])
        let client = HomeAssistantClient(transport: transport)

        let result = await client.exchangeAuthorizationCode(
            baseURL: try XCTUnwrap(URL(string: "https://homeassistant.local")),
            code: "   ",
            clientID: "https://pearchha.dev/app"
        )

        XCTAssertEqual(result, .failure(.invalidPayload(path: "/auth/token", reason: "code is required")))
        await assertEqualAsync(await transport.requests, [])
    }

    func testOAuthRefreshRejectsBlankClientIDBeforeNetwork() async throws {
        let transport = RecordingHARESTTransport(responses: [])
        let client = HomeAssistantClient(transport: transport)

        let result = await client.refreshAccessToken(
            baseURL: try XCTUnwrap(URL(string: "https://homeassistant.local")),
            refreshToken: "refresh-token",
            clientID: "   "
        )

        XCTAssertEqual(result, .failure(.invalidPayload(path: "/auth/token", reason: "client_id is required")))
        await assertEqualAsync(await transport.requests, [])
    }

    func testOAuthRevokeRejectsBlankRefreshTokenBeforeNetwork() async throws {
        let transport = RecordingHARESTTransport(responses: [])
        let client = HomeAssistantClient(transport: transport)

        let result = await client.revokeRefreshToken(
            baseURL: try XCTUnwrap(URL(string: "https://homeassistant.local")),
            refreshToken: "   "
        )

        XCTAssertEqual(result, .failure(.invalidPayload(path: "/auth/token", reason: "token is required")))
        await assertEqualAsync(await transport.requests, [])
    }
}

extension PearchHAClientTests {
    func testWebSocketStatesRejectMissingGetStatesResult() async throws {
        let fixtures = FakeHAFixtures(
            apiBody: #"{"message":"API running."}"#,
            statesBody: #"{}"#
        )
        let server = try FakeHAWebSocketServer(fixtures: fixtures)
        server.start()
        defer {
            server.stop()
        }
        let input = HAConnectionInput(
            endpoint: HAEndpoint(primaryURL: server.baseURL, fallbackURL: nil),
            token: "fake-token"
        )

        await assertEqualAsync(
            await HomeAssistantClient().webSocketStates(input),
            .failure(.invalidPayload(path: "/api/websocket", reason: "missing get_states result"))
        )
    }

    func testDiscoveryContinuesWhenAreaRegistryResultIsMissing() async throws {
        let fixtures = FakeHAFixtures(
            apiBody: #"{"message":"API running."}"#,
            statesBody: #"[{"entity_id":"sensor.office_temperature","state":"21.4","attributes":{"friendly_name":"Office temperature","unit_of_measurement":"°C"}}]"#,
            areaRegistryBody: #"{}"#,
            deviceRegistryBody: #"[]"#,
            entityRegistryDisplayBody: #"{"entities":[]}"#,
            entityRegistryBody: #"[]"#
        )
        let server = try FakeHAWebSocketServer(fixtures: fixtures)
        server.start()
        defer {
            server.stop()
        }
        let input = HAConnectionInput(
            endpoint: HAEndpoint(primaryURL: server.baseURL, fallbackURL: nil),
            token: "fake-token"
        )

        await assertEqualAsync(
            await HomeAssistantClient().discovery(input),
            .success(
                DiscoverySnapshot(
                    areas: [],
                    devices: [],
                    entities: [],
                    states: [
                        EntityState(
                            id: "sensor.office_temperature",
                            name: "Office temperature",
                            state: "21.4",
                            unit: "°C"
                        )
                    ]
                )
            )
        )
    }

    func testDiscoveryContinuesWhenDeviceRegistryResultIsMissing() async throws {
        let fixtures = FakeHAFixtures(
            apiBody: #"{"message":"API running."}"#,
            statesBody: #"[{"entity_id":"sensor.office_temperature","state":"21.4","attributes":{"friendly_name":"Office temperature","unit_of_measurement":"°C"}}]"#,
            areaRegistryBody: #"[]"#,
            deviceRegistryBody: #"{}"#,
            entityRegistryDisplayBody: #"{"entities":[]}"#,
            entityRegistryBody: #"[]"#
        )
        let server = try FakeHAWebSocketServer(fixtures: fixtures)
        server.start()
        defer {
            server.stop()
        }
        let input = HAConnectionInput(
            endpoint: HAEndpoint(primaryURL: server.baseURL, fallbackURL: nil),
            token: "fake-token"
        )

        await assertEqualAsync(
            await HomeAssistantClient().discovery(input),
            .success(
                DiscoverySnapshot(
                    areas: [],
                    devices: [],
                    entities: [],
                    states: [
                        EntityState(
                            id: "sensor.office_temperature",
                            name: "Office temperature",
                            state: "21.4",
                            unit: "°C"
                        )
                    ]
                )
            )
        )
    }

    func testDiscoveryFallsBackWhenEntityRegistryDisplayResultIsMissing() async throws {
        let fixtures = FakeHAFixtures(
            apiBody: #"{"message":"API running."}"#,
            statesBody: #"[{"entity_id":"sensor.office_temperature","state":"21.4","attributes":{"friendly_name":"Office temperature","unit_of_measurement":"°C"}}]"#,
            areaRegistryBody: #"[]"#,
            deviceRegistryBody: #"[]"#,
            entityRegistryDisplayBody: #"{}"#,
            entityRegistryBody: #"[]"#
        )
        let server = try FakeHAWebSocketServer(fixtures: fixtures)
        server.start()
        defer {
            server.stop()
        }
        let input = HAConnectionInput(
            endpoint: HAEndpoint(primaryURL: server.baseURL, fallbackURL: nil),
            token: "fake-token"
        )

        await assertEqualAsync(
            await HomeAssistantClient().discovery(input),
            .success(
                DiscoverySnapshot(
                    areas: [],
                    devices: [],
                    entities: [],
                    states: [
                        EntityState(
                            id: "sensor.office_temperature",
                            name: "Office temperature",
                            state: "21.4",
                            unit: "°C"
                        )
                    ]
                )
            )
        )
    }

    func testDiscoveryContinuesWhenEntityRegistryFallbackResultIsMissing() async throws {
        let fixtures = FakeHAFixtures(
            apiBody: #"{"message":"API running."}"#,
            statesBody: #"[{"entity_id":"sensor.office_temperature","state":"21.4","attributes":{"friendly_name":"Office temperature","unit_of_measurement":"°C"}}]"#,
            areaRegistryBody: #"[]"#,
            deviceRegistryBody: #"[]"#,
            entityRegistryDisplayBody: nil,
            entityRegistryBody: #"{}"#
        )
        let server = try FakeHAWebSocketServer(fixtures: fixtures)
        server.start()
        defer {
            server.stop()
        }
        let input = HAConnectionInput(
            endpoint: HAEndpoint(primaryURL: server.baseURL, fallbackURL: nil),
            token: "fake-token"
        )

        await assertEqualAsync(
            await HomeAssistantClient().discovery(input),
            .success(
                DiscoverySnapshot(
                    areas: [],
                    devices: [],
                    entities: [],
                    states: [
                        EntityState(
                            id: "sensor.office_temperature",
                            name: "Office temperature",
                            state: "21.4",
                            unit: "°C"
                        )
                    ]
                )
            )
        )
    }

    func testDiscoveryRejectsMissingStatesResult() async throws {
        let fixtures = FakeHAFixtures(
            apiBody: #"{"message":"API running."}"#,
            statesBody: #"{}"#,
            areaRegistryBody: #"[]"#,
            deviceRegistryBody: #"[]"#,
            entityRegistryDisplayBody: #"{"entities":[]}"#,
            entityRegistryBody: #"[]"#
        )
        let server = try FakeHAWebSocketServer(fixtures: fixtures)
        server.start()
        defer {
            server.stop()
        }
        let input = HAConnectionInput(
            endpoint: HAEndpoint(primaryURL: server.baseURL, fallbackURL: nil),
            token: "fake-token"
        )

        await assertEqualAsync(
            await HomeAssistantClient().discovery(input),
            .failure(.invalidPayload(path: "/api/websocket", reason: "missing get_states result"))
        )
    }

    func testServicesRejectMissingServicesResult() async throws {
        let fixtures = FakeHAFixtures(
            apiBody: #"{"message":"API running."}"#,
            statesBody: #"[]"#,
            servicesBody: #"[]"#
        )
        let server = try FakeHAWebSocketServer(fixtures: fixtures)
        server.start()
        defer {
            server.stop()
        }
        let input = HAConnectionInput(
            endpoint: HAEndpoint(primaryURL: server.baseURL, fallbackURL: nil),
            token: "fake-token"
        )

        await assertEqualAsync(
            await HomeAssistantClient().services(input),
            .failure(.invalidPayload(path: "/api/websocket", reason: "missing services result"))
        )
    }

    func testNextStateChangedEventDoesNotRetryProtocolFailures() async throws {
        let server = try FakeHAWebSocketServer(mode: .wrongResultID)
        server.start()
        defer {
            server.stop()
        }
        let input = HAConnectionInput(
            endpoint: HAEndpoint(primaryURL: server.baseURL, fallbackURL: nil),
            token: "fake-token"
        )

        await assertEqualAsync(
            await HomeAssistantClient().nextStateChangedEvent(input),
            .failure(.webSocketProtocol("expected result id 1, received 2"))
        )
    }

    func testNextStateChangedEventReturnsAuthenticationWhenWebSocketAuthFails() async throws {
        let server = try FakeHAWebSocketServer()
        server.start()
        defer {
            server.stop()
        }
        let input = HAConnectionInput(
            endpoint: HAEndpoint(primaryURL: server.baseURL, fallbackURL: nil),
            token: "wrong-token"
        )

        await assertEqualAsync(await HomeAssistantClient().nextStateChangedEvent(input), .failure(.authentication))
    }

    func testNextStateChangedEventFallbackRejectsMalformedNewState() async throws {
        let fixtures = FakeHAFixtures(
            apiBody: #"{"message":"API running."}"#,
            statesBody: #"[]"#,
            stateChangedEventBody: #"{}"#
        )
        let server = try FakeHAWebSocketServer(
            fixtures: fixtures,
            mode: .unavailableCommands(["subscribe_entities"], code: .unknownCommand)
        )
        server.start()
        defer {
            server.stop()
        }
        let input = HAConnectionInput(
            endpoint: HAEndpoint(primaryURL: server.baseURL, fallbackURL: nil),
            token: "fake-token"
        )

        let result = await HomeAssistantClient().nextStateChangedEvent(input)
        guard case let .failure(.invalidPayload(path, reason)) = result else {
            XCTFail("expected invalid payload failure, got \(result)")
            return
        }

        XCTAssertEqual(path, "/api/websocket")
        XCTAssertTrue(reason.contains("entity_id"), "expected missing entity_id in reason: \(reason)")
        XCTAssertTrue(
            reason.contains("event.data.new_state") || reason.contains(#"codingPath: [CodingKeys(stringValue: "event""#),
            "expected coding path in reason: \(reason)"
        )
    }

    func testCallServiceSurfacesCommandFailure() async throws {
        let server = try FakeHAWebSocketServer(mode: .commandFailure)
        server.start()
        defer {
            server.stop()
        }
        let input = HAConnectionInput(
            endpoint: HAEndpoint(primaryURL: server.baseURL, fallbackURL: nil),
            token: "fake-token"
        )

        await assertEqualAsync(
            await HomeAssistantClient().callService(
                input,
                call: HAServiceCall(domain: "switch", service: "turn_on", targetEntityID: "switch.office_lamp")
            ),
            .failure(.webSocketCommand(id: 1, code: "failed", message: "Planned command failure"))
        )
    }

    func testCallServiceReturnsAuthenticationWhenWebSocketAuthFails() async throws {
        let server = try FakeHAWebSocketServer()
        server.start()
        defer {
            server.stop()
        }
        let input = HAConnectionInput(
            endpoint: HAEndpoint(primaryURL: server.baseURL, fallbackURL: nil),
            token: "wrong-token"
        )

        await assertEqualAsync(
            await HomeAssistantClient().callService(
                input,
                call: HAServiceCall(domain: "switch", service: "turn_on", targetEntityID: "switch.office_lamp")
            ),
            .failure(.authentication)
        )
    }

    func testServicesReturnAuthenticationWhenWebSocketAuthFails() async throws {
        let server = try FakeHAWebSocketServer()
        server.start()
        defer {
            server.stop()
        }
        let input = HAConnectionInput(
            endpoint: HAEndpoint(primaryURL: server.baseURL, fallbackURL: nil),
            token: "wrong-token"
        )

        await assertEqualAsync(await HomeAssistantClient().services(input), .failure(.authentication))
    }

    func testStreamEntityStateChangesReturnsAuthenticationWhenWebSocketAuthFails() async throws {
        let server = try FakeHAWebSocketServer()
        server.start()
        defer {
            server.stop()
        }
        let input = HAConnectionInput(
            endpoint: HAEndpoint(urls: [server.baseURL]),
            token: "wrong-token"
        )

        let terminal = await HomeAssistantClient().streamEntityStateChanges(input) { _ in
            XCTFail("authentication failure must stop the stream before any events")
        }

        XCTAssertEqual(terminal, .authentication)
    }

    func testMirrorCaptureRejectsMissingTokenBeforeNetwork() async {
        let service = HAMirrorCaptureService(transport: RecordingMirrorTransport())
        let environment = HAMirrorEnvironment(
            primaryURL: URL(string: "http://127.0.0.1:8123")!,
            fallbackURL: nil,
            token: nil,
            user: nil,
            password: nil
        )

        do {
            _ = try await service.capture(environment: environment)
            XCTFail("capture unexpectedly succeeded without a token")
        } catch let error as HAMirrorCaptureError {
            XCTAssertEqual(error, .missingToken)
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }

    func testMirrorCaptureWithWebSocketEvidenceUsesPublicFixtureCapturePath() async throws {
        let fixtures = FakeHAFixtures(
            apiBody: #"{"message":"API running."}"#,
            statesBody: #"[]"#,
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

        let fixtureSet = try await HAMirrorCaptureService().capture(environment: environment, includeWebSocketEvidence: true)

        XCTAssertEqual(fixtureSet.api.path, "/api/")
        XCTAssertEqual(fixtureSet.states.path, "/api/states")
        XCTAssertEqual(fixtureSet.webSocket?.entityRegistryDisplayList.command, "config/entity_registry/list_for_display")
        XCTAssertEqual(fixtureSet.webSocket?.subscribeEntities.command, "subscribe_entities")
        XCTAssertEqual(fixtureSet.webSocket?.subscribeEntities.eventKeys, [])
    }

    func testMirrorCaptureOptimizedWebSocketEvidenceRejectsMissingTokenBeforeNetwork() async {
        let service = HAMirrorCaptureService()
        let environment = HAMirrorEnvironment(
            primaryURL: URL(string: "http://127.0.0.1:8123")!,
            fallbackURL: nil,
            token: nil,
            user: nil,
            password: nil
        )

        do {
            _ = try await service.captureOptimizedWebSocketEvidence(environment: environment)
            XCTFail("optimized WebSocket evidence unexpectedly succeeded without a token")
        } catch let error as HAMirrorCaptureError {
            XCTAssertEqual(error, .missingToken)
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }

    func testMirrorCaptureOptimizedWebSocketEvidenceRecordsUnavailableCommands() async throws {
        let server = try FakeHAWebSocketServer(
            mode: .unavailableCommands(
                ["config/entity_registry/list_for_display", "subscribe_entities"],
                code: .unsupportedCommand
            )
        )
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

        let evidence = try await HAMirrorCaptureService().captureOptimizedWebSocketEvidence(environment: environment)

        XCTAssertEqual(
            evidence.entityRegistryDisplayList,
            HAMirrorWebSocketCommandEvidence(
                command: "config/entity_registry/list_for_display",
                available: false,
                errorCode: "unsupported_command",
                errorMessage: "Command unavailable"
            )
        )
        XCTAssertEqual(
            evidence.subscribeEntities,
            HAMirrorWebSocketCommandEvidence(
                command: "subscribe_entities",
                available: false,
                errorCode: "unsupported_command",
                errorMessage: "Command unavailable"
            )
        )
    }

    func testMirrorCaptureOptimizedWebSocketEvidenceReturnsAuthenticationForWrongToken() async throws {
        let server = try FakeHAWebSocketServer()
        server.start()
        defer {
            server.stop()
        }
        let service = HAMirrorCaptureService(
            transport: RecordingMirrorTransport(
                apiBody: #"{"message":"API running."}"#,
                statesBody: #"[]"#
            )
        )
        let environment = HAMirrorEnvironment(
            primaryURL: server.baseURL,
            fallbackURL: nil,
            token: "wrong-token",
            user: nil,
            password: nil
        )

        do {
            _ = try await service.captureOptimizedWebSocketEvidence(environment: environment)
            XCTFail("optimized WebSocket evidence unexpectedly succeeded with a wrong token")
        } catch let error as HAMirrorCaptureError {
            XCTAssertEqual(error, .webSocketAuthentication)
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }

    func testMirrorCaptureOptimizedWebSocketEvidenceRejectsInvalidWebSocketBaseURL() async throws {
        let service = HAMirrorCaptureService(
            transport: RecordingMirrorTransport(
                apiBody: #"{"message":"API running."}"#,
                statesBody: #"[]"#
            )
        )
        let environment = HAMirrorEnvironment(
            primaryURL: URL(string: "file:///tmp/pearchha-homeassistant")!,
            fallbackURL: nil,
            token: "secret-token",
            user: nil,
            password: nil
        )

        do {
            _ = try await service.captureOptimizedWebSocketEvidence(environment: environment)
            XCTFail("optimized WebSocket evidence unexpectedly succeeded for a file URL")
        } catch let error as HAMirrorCaptureError {
            XCTAssertEqual(error, .invalidPath("/api/websocket"))
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }

    func testMirrorProbeReportsMalformedAPIBodyAsBlockedMessage() async throws {
        let transport = RecordingMirrorTransport(apiBody: "{")
        let service = HAMirrorCaptureService(transport: transport)
        let environment = HAMirrorEnvironment(
            primaryURL: try XCTUnwrap(URL(string: "http://127.0.0.1:8123")),
            fallbackURL: nil,
            token: "secret-token",
            user: nil,
            password: nil
        )

        let report = await service.probe(environment: environment)

        XCTAssertEqual(report.primary.state, .blocked)
        XCTAssertEqual(report.primary.message, "fixture body for /api/ is not JSON")
        XCTAssertNil(report.primary.guidance)
    }

    private func writeTemporaryEnvironmentFile(_ contents: Data) throws -> String {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("pearchha-env-test-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appendingPathComponent(".env.test")
        try contents.write(to: file)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: directory)
        }
        return file.path
    }

    private func missingEnvironmentFilePath() -> String {
        URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("pearchha-env-test-missing-\(UUID().uuidString)")
            .appendingPathComponent(".env.test")
            .path
    }

    func testMirrorEnvironmentErrorDescriptionsStayCalmAndSecretFree() {
        XCTAssertEqual(HAMirrorEnvironmentError.invalidLine(3).description, "invalid .env line 3")
        XCTAssertEqual(
            HAMirrorEnvironmentError.missingFile("/tmp/none.env").description,
            "environment file does not exist: /tmp/none.env"
        )
        XCTAssertEqual(
            HAMirrorEnvironmentError.unreadableFile("/tmp/binary.env").description,
            "environment file is unreadable: /tmp/binary.env"
        )
        XCTAssertEqual(HAMirrorEnvironmentError.missingURL.description, "missing url in environment file")
        XCTAssertEqual(HAMirrorEnvironmentError.invalidURL("ftp://x").description, "invalid URL: ftp://x")
        XCTAssertEqual(
            HAMirrorEnvironmentError.missingOAuthClientID.description,
            "missing PEARCHHA_OAUTH_CLIENT_ID in environment file"
        )
        XCTAssertEqual(
            HAMirrorEnvironmentError.missingOAuthRedirectURI.description,
            "missing PEARCHHA_OAUTH_REDIRECT_URI in environment file"
        )
    }

    func testMirrorEnvironmentLoadsFieldsCommentsAndShortValuesFromFile() throws {
        let contents = """
        # capture credentials
        url=http://homeassistant.local:8123

        token="secret-token"
        user=u
        """
        let path = try writeTemporaryEnvironmentFile(Data(contents.utf8))

        let environment = try HAMirrorEnvironment.load(from: path)

        XCTAssertEqual(environment.primaryURL, URL(string: "http://homeassistant.local:8123"))
        XCTAssertNil(environment.fallbackURL)
        XCTAssertEqual(environment.token, "secret-token")
        XCTAssertEqual(environment.user, "u")
        XCTAssertNil(environment.password)
    }

    func testMirrorEnvironmentFromEnvironmentRequiresAURL() throws {
        let path = try writeTemporaryEnvironmentFile(Data("token=x\n".utf8))

        XCTAssertThrowsError(
            try HAMirrorEnvironment.fromEnvironment([:], environmentFilePath: path)
        ) { error in
            XCTAssertEqual(error as? HAMirrorEnvironmentError, .missingURL)
        }
    }

    func testMirrorEnvironmentFromEnvironmentRejectsInvalidPrimaryURL() {
        XCTAssertThrowsError(
            try HAMirrorEnvironment.fromEnvironment(
                ["PEARCHHA_HA_URL": "ftp://homeassistant.local"],
                environmentFilePath: missingEnvironmentFilePath()
            )
        ) { error in
            XCTAssertEqual(error as? HAMirrorEnvironmentError, .invalidURL("ftp://homeassistant.local"))
        }
    }

    func testMirrorEnvironmentFromEnvironmentRejectsInvalidFallbackURL() {
        XCTAssertThrowsError(
            try HAMirrorEnvironment.fromEnvironment(
                [
                    "PEARCHHA_HA_URL": "http://homeassistant.local:8123",
                    "PEARCHHA_HA_FALLBACK_URL": "ftp://fallback.local"
                ],
                environmentFilePath: missingEnvironmentFilePath()
            )
        ) { error in
            XCTAssertEqual(error as? HAMirrorEnvironmentError, .invalidURL("ftp://fallback.local"))
        }
    }

    func testMirrorEnvironmentFromEnvironmentToleratesUnreadableFileWhenURLIsExported() throws {
        let path = try writeTemporaryEnvironmentFile(Data([0xFF, 0xFE, 0xFD]))

        let environment = try HAMirrorEnvironment.fromEnvironment(
            [
                "PEARCHHA_HA_URL": "http://homeassistant.local:8123",
                "PEARCHHA_HA_TOKEN": "env-token"
            ],
            environmentFilePath: path
        )

        XCTAssertEqual(environment.primaryURL, URL(string: "http://homeassistant.local:8123"))
        XCTAssertEqual(environment.token, "env-token")
    }

    func testMirrorEnvironmentFromEnvironmentRejectsUnreadableFileWithoutExportedURL() throws {
        let path = try writeTemporaryEnvironmentFile(Data([0xFF, 0xFE, 0xFD]))

        XCTAssertThrowsError(
            try HAMirrorEnvironment.fromEnvironment([:], environmentFilePath: path)
        ) { error in
            XCTAssertEqual(error as? HAMirrorEnvironmentError, .unreadableFile(path))
        }
    }

    func testMirrorEnvironmentParseRequiresAURL() {
        XCTAssertThrowsError(try HAMirrorEnvironment.parse("token=x\n")) { error in
            XCTAssertEqual(error as? HAMirrorEnvironmentError, .missingURL)
        }
    }

    func testMirrorEnvironmentParseRejectsInvalidFallbackURL() {
        XCTAssertThrowsError(
            try HAMirrorEnvironment.parse("url=http://homeassistant.local:8123\nurl2=ftp://fallback.local\n")
        ) { error in
            XCTAssertEqual(error as? HAMirrorEnvironmentError, .invalidURL("ftp://fallback.local"))
        }
    }

    func testMirrorEnvironmentParseRejectsHostlessURL() {
        XCTAssertThrowsError(try HAMirrorEnvironment.parse("url=http:///dashboard\n")) { error in
            XCTAssertEqual(error as? HAMirrorEnvironmentError, .invalidURL("http:///dashboard"))
        }
    }

    func testMirrorEnvironmentResolvedFilePathPrefersOverride() {
        XCTAssertEqual(
            HAMirrorEnvironment.resolvedEnvironmentFilePath(
                environment: ["PEARCHHA_ENV_FILE": "from-env.env"],
                overridePath: "override.env"
            ),
            "override.env"
        )
    }

    func testReadinessReportDefaultNextStepsUseFilePlaceholder() {
        let report = HAMirrorEnvironmentReadinessReport(
            hasFallbackURL: false,
            hasToken: false,
            hasUser: true,
            hasPassword: false,
            hasOAuthClientID: false,
            hasOAuthRedirectURI: false
        )

        XCTAssertEqual(report.nextSteps, report.nextSteps(envPath: "<file>"))
        XCTAssertTrue(report.nextSteps.allSatisfy { !$0.isEmpty })
        XCTAssertTrue(report.nextSteps.contains { $0.contains("<file>") })
    }

    func testReadinessReportBlockingMessagesCombineIssuesAndNextSteps() {
        let report = HAMirrorEnvironmentReadinessReport(
            hasFallbackURL: false,
            hasToken: false,
            hasUser: true,
            hasPassword: false,
            hasOAuthClientID: true,
            hasOAuthRedirectURI: false
        )

        XCTAssertEqual(
            report.blockingMessages,
            report.issues.map(\.description) + report.nextSteps
        )
        XCTAssertEqual(
            report.blockingMessages(envPath: "custom.env"),
            report.issues.map(\.description) + report.nextSteps(envPath: "custom.env")
        )
        XCTAssertFalse(report.blockingMessages.isEmpty)
    }

    func testOAuthClientWebsiteEnvironmentLoadsFromFile() throws {
        let contents = """
        pearchha_oauth_client_id=https://pearchha.dev/app
        pearchha_oauth_redirect_uri=pearchha://auth
        """
        let path = try writeTemporaryEnvironmentFile(Data(contents.utf8))

        let environment = try HAOAuthClientWebsiteEnvironment.load(from: path)

        XCTAssertEqual(environment.clientID, "https://pearchha.dev/app")
        XCTAssertEqual(environment.redirectURI, "pearchha://auth")
    }
}
#endif
