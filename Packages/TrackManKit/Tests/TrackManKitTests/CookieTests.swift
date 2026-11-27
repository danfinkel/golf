import XCTest
@testable import TrackManKit

final class CookieTests: XCTestCase {
    private func cookie(_ name: String, _ value: String, domain: String = "portal.trackmangolf.com", expires: Date? = nil) -> HTTPCookie {
        var properties: [HTTPCookiePropertyKey: Any] = [.domain: domain, .path: "/", .name: name, .value: value, .secure: "TRUE"]
        if let expires { properties[.expires] = expires }
        return HTTPCookie(properties: properties)!
    }

    func testCookieDomainCoversPortalAndLogin() {
        XCTAssertEqual(TrackManConfig.portal.cookieDomain, "trackmangolf.com")
    }

    func testStoredCookieRoundTripsSessionCookie() throws {
        let original = cookie("portal-session", "abc")
        let stored = StoredCookie(original)
        let data = try JSONEncoder().encode([stored])
        let decoded = try JSONDecoder().decode([StoredCookie].self, from: data)
        let restored = try XCTUnwrap(decoded.first?.cookie)
        XCTAssertEqual(restored.name, "portal-session")
        XCTAssertEqual(restored.value, "abc")
        XCTAssertEqual(restored.domain, "portal.trackmangolf.com")
        XCTAssertTrue(restored.isSecure)
        XCTAssertTrue(restored.isSessionOnly)
    }

    func testRelevantKeepsLiveTrackManCookiesOnly() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let cookies = [
            cookie("portal", "1"),
            cookie("idsrv", "2", domain: ".login.trackmangolf.com", expires: now.addingTimeInterval(3600)),
            cookie("old", "3", expires: now.addingTimeInterval(-1)),
            cookie("other", "4", domain: "example.com"),
            cookie("lookalike", "5", domain: "nottrackmangolf.com"),
        ]
        let kept = PortalCookies.relevant(cookies, domain: "trackmangolf.com", now: now).map(\.name)
        XCTAssertEqual(kept, ["portal", "idsrv"])
    }

    func testMergeReplacesSameCookie() {
        let base = [StoredCookie(cookie("portal", "old")), StoredCookie(cookie("keep", "k"))]
        let newer = [StoredCookie(cookie("portal", "new", domain: ".portal.trackmangolf.com"))]
        let merged = PortalCookies.merge(base, with: newer)
        XCTAssertEqual(merged.map(\.name).sorted(), ["keep", "portal"])
        XCTAssertEqual(merged.first { $0.name == "portal" }?.value, "new")
    }

    func testRefreshHandsBackRenewedCookies() async throws {
        let json = #"{"accessToken":"fresh","expires":2000000,"isAuthenticated":true}"#
        let transport = StubTransport(withHeaders: [(200, json, ["Set-Cookie": "portal-session=renewed; Path=/; Secure; HttpOnly"])])
        let received = Box()
        let start = [cookie("portal-session", "abc")]
        let client = PortalSessionClient(
            transport: transport,
            cookies: { start },
            onCookies: { cookies in received.set(cookies) },
            now: { Date(timeIntervalSince1970: 1_000_000) }
        )

        let tokens = try await client.refresh()

        XCTAssertEqual(tokens.accessToken, "fresh")
        XCTAssertEqual(received.value.map(\.value), ["renewed"])
        XCTAssertEqual(received.value.first?.domain, "portal.trackmangolf.com")
    }

    func testRefreshWithoutSetCookieReportsNothing() async throws {
        let json = #"{"accessToken":"fresh","expires":2000000,"isAuthenticated":true}"#
        let received = Box()
        let start = [cookie("portal-session", "abc")]
        let client = PortalSessionClient(
            transport: StubTransport([(200, json)]),
            cookies: { start },
            onCookies: { cookies in received.set(cookies) },
            now: { Date(timeIntervalSince1970: 1_000_000) }
        )
        _ = try await client.refresh()
        XCTAssertTrue(received.value.isEmpty)
    }

    func testInMemoryCookieStore() throws {
        let store = InMemoryCookieStore()
        try store.save([StoredCookie(cookie("a", "1"))])
        XCTAssertEqual(try store.load().count, 1)
        try store.clear()
        XCTAssertTrue(try store.load().isEmpty)
    }
}

private final class Box: @unchecked Sendable {
    private let lock = NSLock()
    private var cookies: [HTTPCookie] = []
    func set(_ new: [HTTPCookie]) { lock.withLock { cookies = new } }
    var value: [HTTPCookie] { lock.withLock { cookies } }
}
