import XCTest
@testable import TrackManKit

final class AuthTests: XCTestCase {
    private let sessionCookie = HTTPCookie(properties: [
        .domain: "portal.trackmangolf.com",
        .path: "/",
        .name: "portal-session",
        .value: "abc123",
        .secure: "TRUE",
    ])!

    private let otherCookie = HTTPCookie(properties: [
        .domain: "example.com",
        .path: "/",
        .name: "other",
        .value: "nope",
    ])!

    private func accountJSON(token: String = "AT", expires: Double = 2_000_000, authenticated: Bool = true) -> String {
        #"{"accessToken":"\#(token)","expires":\#(expires),"isAuthenticated":\#(authenticated),"name":"","refreshToken":"ignored"}"#
    }

    func testPortalPageDetection() {
        let config = TrackManConfig.portal
        XCTAssertTrue(config.isPortalPage(URL(string: "https://portal.trackmangolf.com/player")))
        XCTAssertTrue(config.isPortalPage(URL(string: "https://portal.trackmangolf.com/")))
        XCTAssertFalse(config.isPortalPage(URL(string: "https://portal.trackmangolf.com/account/callback?code=x")))
        XCTAssertFalse(config.isPortalPage(URL(string: "https://login.trackmangolf.com/Account/Login")))
        XCTAssertFalse(config.isPortalPage(nil))
        XCTAssertEqual(config.sessionURL.absoluteString, "https://portal.trackmangolf.com/api/account/me")
    }

    func testPortalAccountParsesIntoTokenSet() {
        let account = PortalAccount.parse(accountJSON(token: "AT", expires: 1_796_315_557))
        XCTAssertEqual(account?.tokenSet(), TokenSet(accessToken: "AT", expiresAt: Date(timeIntervalSince1970: 1_796_315_557)))
    }

    func testSignedOutAccountHasNoTokens() {
        XCTAssertNil(PortalAccount.parse(accountJSON(authenticated: false))?.tokenSet())
        XCTAssertNil(PortalAccount.parse(#"{"isAuthenticated":false}"#)?.tokenSet())
        XCTAssertNil(PortalAccount.parse("<html>login</html>"))
    }

    func testExpiryFallsBackToJWTClaim() {
        let jwt = fakeJWT(#"{"exp":1800000000}"#)
        let account = PortalAccount(accessToken: jwt, expires: nil, isAuthenticated: true)
        XCTAssertEqual(account.tokenSet()?.expiresAt, Date(timeIntervalSince1970: 1_800_000_000))
    }

    func testSessionClientSendsOnlyPortalCookies() async throws {
        let transport = StubTransport([(200, accountJSON(token: "fresh", expires: 2_000_000))])
        let cookies = [sessionCookie, otherCookie]
        let client = PortalSessionClient(transport: transport, cookies: { cookies }, now: { Date(timeIntervalSince1970: 1_000_000) })

        let tokens = try await client.refresh()

        XCTAssertEqual(tokens.accessToken, "fresh")
        let sent = transport.recorded[0]
        XCTAssertEqual(sent.url?.absoluteString, "https://portal.trackmangolf.com/api/account/me")
        XCTAssertEqual(sent.value(forHTTPHeaderField: "Cookie"), "portal-session=abc123")
    }

    func testSessionClientRequiresReauthWhenSignedOutOrExpired() async {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let cases: [(Int, String)] = [
            (200, accountJSON(authenticated: false)),
            (200, "<html>TrackMan login</html>"),
            (401, ""),
            (200, accountJSON(expires: 999_999)),
        ]
        for response in cases {
            let cookies = [sessionCookie]
            let client = PortalSessionClient(transport: StubTransport([response]), cookies: { cookies }, now: { now })
            do {
                _ = try await client.refresh()
                XCTFail("expected reauthentication for \(response)")
            } catch {
                XCTAssertEqual(error as? AuthError, .reauthenticationRequired)
            }
        }
    }

    func testSessionClientWithoutCookiesRequiresReauth() async {
        let transport = StubTransport([])
        let client = PortalSessionClient(transport: transport, cookies: { [] })
        do {
            _ = try await client.refresh()
            XCTFail("expected reauthentication")
        } catch {
            XCTAssertEqual(error as? AuthError, .reauthenticationRequired)
        }
        XCTAssertTrue(transport.recorded.isEmpty)
    }

    func testProviderRenewsExpiredTokenAndPersistsIt() async throws {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let store = InMemoryTokenStore(TokenSet(accessToken: "old", expiresAt: now.addingTimeInterval(-1)))
        let transport = StubTransport([(200, accountJSON(token: "new", expires: 2_000_000))])
        let cookies = [sessionCookie]
        let refresher = PortalSessionClient(transport: transport, cookies: { cookies }, now: { now })
        let provider = TokenProvider(refresher: refresher, store: store, now: { now })

        let token = try await provider.validAccessToken()
        XCTAssertEqual(token, "new")
        XCTAssertEqual(try store.load()?.accessToken, "new")

        let again = try await provider.validAccessToken()
        XCTAssertEqual(again, "new")
        XCTAssertEqual(transport.recorded.count, 1)
    }

    func testEndedSessionSignsOut() async throws {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let store = InMemoryTokenStore(TokenSet(accessToken: "old", expiresAt: now))
        let refresher = PortalSessionClient(transport: StubTransport([]), cookies: { [] }, now: { now })
        let provider = TokenProvider(refresher: refresher, store: store, now: { now })

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
        let tokens = TokenSet(accessToken: fakeJWT(#"{"given_name":"Dan","name":"Dan F","email":"d@example.com"}"#), expiresAt: .distantFuture)
        XCTAssertEqual(tokens.claims?.displayName, "Dan")
        let noName = TokenSet(accessToken: fakeJWT(#"{"given_name":"","email":"d@example.com"}"#), expiresAt: .distantFuture)
        XCTAssertEqual(noName.claims?.displayName, "d@example.com")
    }
}
