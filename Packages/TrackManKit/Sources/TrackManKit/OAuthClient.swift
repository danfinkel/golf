import Foundation

/// Talks to TrackMan's token endpoint as a public OAuth client (no secret).
public struct OAuthClient: Sendable {
    public let config: TrackManConfig
    let transport: HTTPTransport
    let now: @Sendable () -> Date

    public init(config: TrackManConfig = .portal, transport: HTTPTransport = URLSession.shared, now: @escaping @Sendable () -> Date = { Date() }) {
        self.config = config
        self.transport = transport
        self.now = now
    }

    /// Redeems the authorization code captured from the login sheet.
    public func exchange(code: String, request: AuthorizationRequest) async throws -> TokenSet {
        try await tokenCall([
            "grant_type": "authorization_code",
            "code": code,
            "redirect_uri": request.redirectURI.absoluteString,
            "client_id": config.clientID,
            "code_verifier": request.pkce.verifier,
        ], previous: nil)
    }

    /// Swaps the refresh token for a new access token. TrackMan may rotate the
    /// refresh token; when it does not send one, the old one is kept.
    public func refresh(_ tokens: TokenSet) async throws -> TokenSet {
        guard let refreshToken = tokens.refreshToken else {
            throw AuthError.reauthenticationRequired
        }
        return try await tokenCall([
            "grant_type": "refresh_token",
            "refresh_token": refreshToken,
            "client_id": config.clientID,
        ], previous: tokens)
    }

    func tokenRequest(form: [String: String]) -> URLRequest {
        var request = URLRequest(url: config.tokenEndpoint)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = Data(Self.formEncode(form).utf8)
        request.timeoutInterval = 30
        return request
    }

    static func formEncode(_ form: [String: String]) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return form.keys.sorted().map { key in
            let value = form[key] ?? ""
            let k = key.addingPercentEncoding(withAllowedCharacters: allowed) ?? key
            let v = value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
            return "\(k)=\(v)"
        }.joined(separator: "&")
    }

    private func tokenCall(_ form: [String: String], previous: TokenSet?) async throws -> TokenSet {
        let (data, response) = try await transport.send(tokenRequest(form: form))
        guard response.statusCode == 200 else {
            let oauthError = try? JSONDecoder().decode(TokenErrorResponse.self, from: data)
            if previous != nil, oauthError?.error == "invalid_grant" {
                throw AuthError.reauthenticationRequired
            }
            if let oauthError {
                throw AuthError.provider(oauthError.errorDescription ?? oauthError.error)
            }
            throw AuthError.tokenEndpoint(status: response.statusCode, body: String(decoding: data.prefix(300), as: UTF8.self))
        }
        let body = try JSONDecoder().decode(TokenResponse.self, from: data)
        return TokenSet(
            accessToken: body.accessToken,
            refreshToken: body.refreshToken ?? previous?.refreshToken,
            expiresAt: now().addingTimeInterval(body.expiresIn ?? 3600),
            idToken: body.idToken ?? previous?.idToken
        )
    }
}
