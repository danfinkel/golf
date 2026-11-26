import Foundation

/// The body of `GET portal.trackmangolf.com/api/account/me`. It also carries
/// a refresh token, but that one only works with the portal's client secret,
/// so the app ignores it.
public struct PortalAccount: Decodable, Sendable, Equatable {
    public let accessToken: String?
    /// Unix seconds; equals the JWT's `exp`.
    public let expires: Double?
    public let isAuthenticated: Bool?

    public init(accessToken: String?, expires: Double?, isAuthenticated: Bool?) {
        self.accessToken = accessToken
        self.expires = expires
        self.isAuthenticated = isAuthenticated
    }

    /// A usable token set, or nil when the portal session is signed out.
    public func tokenSet() -> TokenSet? {
        guard isAuthenticated != false, let token = accessToken, !token.isEmpty else { return nil }
        let expiry = expires ?? AccessTokenClaims.decode(jwt: token)?.exp
        guard let expiry else { return nil }
        return TokenSet(accessToken: token, expiresAt: Date(timeIntervalSince1970: expiry))
    }

    /// Parses the endpoint's JSON text, as read from the login web view.
    public static func parse(_ text: String) -> PortalAccount? {
        try? JSONDecoder().decode(PortalAccount.self, from: Data(text.utf8))
    }
}

/// Gets a fresh token when the current one expires.
public protocol TokenRefresher: Sendable {
    func refresh() async throws -> TokenSet
}

/// Re-reads `/api/account/me` with the portal session cookies the login web
/// view stored, so no password is needed until that session ends.
public struct PortalSessionClient: TokenRefresher {
    let config: TrackManConfig
    let transport: HTTPTransport
    let cookies: @Sendable () async -> [HTTPCookie]
    let now: @Sendable () -> Date

    public init(
        config: TrackManConfig = .portal,
        transport: HTTPTransport = URLSession(configuration: .ephemeral),
        cookies: @escaping @Sendable () async -> [HTTPCookie],
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.config = config
        self.transport = transport
        self.cookies = cookies
        self.now = now
    }

    public func refresh() async throws -> TokenSet {
        let host = config.portalHost.lowercased()
        let portalCookies = await cookies().filter { cookie in
            let domain = cookie.domain.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
            return host == domain || host.hasSuffix("." + domain)
        }
        guard !portalCookies.isEmpty else { throw AuthError.reauthenticationRequired }

        var request = URLRequest(url: config.sessionURL)
        request.timeoutInterval = 30
        request.httpShouldHandleCookies = false
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        for (field, value) in HTTPCookie.requestHeaderFields(with: portalCookies) {
            request.setValue(value, forHTTPHeaderField: field)
        }

        let (data, response) = try await transport.send(request)
        // A signed-out session ends on the HTML login page or a 401.
        guard response.statusCode == 200,
              let account = try? JSONDecoder().decode(PortalAccount.self, from: data),
              let tokens = account.tokenSet(),
              !tokens.isExpired(at: now()) else {
            throw AuthError.reauthenticationRequired
        }
        return tokens
    }
}
