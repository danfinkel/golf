import XCTest
@testable import TrackManKit

final class AuthTests: XCTestCase {
    func testPKCEMatchesRFC7636Vector() {
        let pkce = PKCE(verifier: "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk")
        XCTAssertEqual(pkce.challenge, "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM")
    }

    func testGeneratedVerifierIsURLSafe() {
        let verifier = PKCE.generate().verifier
        XCTAssertGreaterThanOrEqual(verifier.count, 43)
        XCTAssertNil(verifier.rangeOfCharacter(from: CharacterSet(charactersIn: "+/=")))
    }

    func testAuthorizeURLCarriesPortalClientAndPKCE() throws {
        let request = AuthorizationRequest(config: .portal, pkce: PKCE(verifier: "v"), state: "abc", nonce: "n")
        let items = URLComponents(url: request.url, resolvingAgainstBaseURL: false)!.queryItems!
        func value(_ name: String) -> String? { items.first { $0.name == name }?.value }

        XCTAssertEqual(request.url.host, "login.trackmangolf.com")
        XCTAssertEqual(request.url.path, "/connect/authorize")
        XCTAssertEqual(value("client_id"), TrackManConfig.portal.clientID)
        XCTAssertEqual(value("redirect_uri"), "https://portal.trackmangolf.com/account/callback")
        XCTAssertEqual(value("response_type"), "code")
        XCTAssertEqual(value("code_challenge_method"), "S256")
        XCTAssertEqual(value("code_challenge"), PKCE.challenge(for: "v"))
        XCTAssertEqual(value("state"), "abc")
        XCTAssertTrue(value("scope")!.contains("offline_access"))
    }

    func testCallbackDetectionAndCodeExtraction() throws {
        let request = AuthorizationRequest(config: .portal, state: "abc")
        let callback = URL(string: "https://portal.trackmangolf.com/account/callback?code=XYZ&state=abc&iss=x")!
        XCTAssertTrue(request.isCallback(callback))
        XCTAssertFalse(request.isCallback(URL(string: "https://login.trackmangolf.com/Account/Login")!))
        XCTAssertEqual(try request.code(fromCallback: callback), "XYZ")
    }

    func testCallbackRejectsWrongStateAndProviderErrors() {
        let request = AuthorizationRequest(config: .portal, state: "abc")
        XCTAssertThrowsError(try request.code(fromCallback: URL(string: "https://portal.trackmangolf.com/account/callback?code=X&state=evil")!)) {
            XCTAssertEqual($0 as? AuthError, .stateMismatch)
        }
        XCTAssertThrowsError(try request.code(fromCallback: URL(string: "https://portal.trackmangolf.com/account/callback?error=access_denied&state=abc")!)) {
            XCTAssertEqual($0 as? AuthError, .provider("access_denied"))
        }
    }

    func testCodeExchangePostsPKCEFormAndParsesTokens() async throws {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let transport = StubTransport([(200, #"{"access_token":"AT","refresh_token":"RT","expires_in":604800,"token_type":"Bearer"}"#)])
        let client = OAuthClient(config: .portal, transport: transport, now: { now })
        let request = AuthorizationRequest(config: .portal, pkce: PKCE(verifier: "verifier-123"), state: "s")

        let tokens = try await client.exchange(code: "CODE", request: request)

        XCTAssertEqual(tokens, TokenSet(accessToken: "AT", refreshToken: "RT", expiresAt: now.addingTimeInterval(604800)))
        let sent = transport.recorded[0]
        XCTAssertEqual(sent.url?.absoluteString, "https://login.trackmangolf.com/connect/token")
        XCTAssertEqual(sent.httpMethod, "POST")
        let fields = formFields(sent)
        XCTAssertEqual(fields["grant_type"], "authorization_code")
        XCTAssertEqual(fields["code"], "CODE")
        XCTAssertEqual(fields["code_verifier"], "verifier-123")
        XCTAssertEqual(fields["client_id"], TrackManConfig.portal.clientID)
        XCTAssertEqual(fields["redirect_uri"], "https://portal.trackmangolf.com/account/callback")
    }

    func testRefreshKeepsOldRefreshTokenWhenNotRotated() async throws {
        let now = Date(timeIntervalSince1970: 0)
        let transport = StubTransport([(200, #"{"access_token":"AT2","expires_in":100}"#)])
        let client = OAuthClient(transport: transport, now: { now })
        let tokens = try await client.refresh(TokenSet(accessToken: "AT1", refreshToken: "RT1", expiresAt: now))
        XCTAssertEqual(tokens.accessToken, "AT2")
        XCTAssertEqual(tokens.refreshToken, "RT1")
        XCTAssertEqual(formFields(transport.recorded[0])["grant_type"], "refresh_token")
    }

    func testProviderRefreshesExpiredTokenAndPersistsIt() async throws {
        let now = Date(timeIntervalSince1970: 10_000)
        let store = InMemoryTokenStore(TokenSet(accessToken: "old", refreshToken: "RT", expiresAt: now.addingTimeInterval(-1)))
        let transport = StubTransport([(200, #"{"access_token":"new","refresh_token":"RT2","expires_in":3600}"#)])
        let provider = TokenProvider(client: OAuthClient(transport: transport, now: { now }), store: store, now: { now })

        let token = try await provider.validAccessToken()

        XCTAssertEqual(token, "new")
        XCTAssertEqual(try store.load()?.refreshToken, "RT2")
        let again = try await provider.validAccessToken()
        XCTAssertEqual(again, "new")
        XCTAssertEqual(transport.recorded.count, 1)
    }

    func testRevokedRefreshTokenSignsOut() async throws {
        let now = Date(timeIntervalSince1970: 10_000)
        let store = InMemoryTokenStore(TokenSet(accessToken: "old", refreshToken: "RT", expiresAt: now))
        let transport = StubTransport([(400, #"{"error":"invalid_grant"}"#)])
        let provider = TokenProvider(client: OAuthClient(transport: transport, now: { now }), store: store, now: { now })

        do {
            _ = try await provider.validAccessToken()
            XCTFail("expected reauthentication")
        } catch {
            XCTAssertEqual(error as? AuthError, .reauthenticationRequired)
        }
        let signedIn = await provider.isSignedIn
        XCTAssertFalse(signedIn)
        XCTAssertNil(try store.load())
    }

    func testClaimsDecodeDisplayName() {
        let tokens = TokenSet(accessToken: fakeJWT(#"{"given_name":"Dan","name":"Dan F","email":"d@example.com"}"#), refreshToken: nil, expiresAt: .distantFuture)
        XCTAssertEqual(tokens.claims?.displayName, "Dan")
    }
}
