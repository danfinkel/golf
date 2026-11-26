import Foundation

/// One sign-in attempt: the URL to load in the login sheet plus the secrets
/// needed to validate the callback and redeem the code.
public struct AuthorizationRequest: Sendable, Identifiable {
    public var id: String { state }
    public let url: URL
    public let state: String
    public let pkce: PKCE
    public let redirectURI: URL

    public init(
        config: TrackManConfig,
        pkce: PKCE = .generate(),
        state: String = PKCE.randomURLSafeString(byteCount: 16),
        nonce: String = PKCE.randomURLSafeString(byteCount: 16)
    ) {
        var components = URLComponents(url: config.authorizeEndpoint, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: config.clientID),
            URLQueryItem(name: "redirect_uri", value: config.redirectURI.absoluteString),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: config.scopes.joined(separator: " ")),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "nonce", value: nonce),
            URLQueryItem(name: "code_challenge", value: pkce.challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
        ]
        self.url = components.url!
        self.state = state
        self.pkce = pkce
        self.redirectURI = config.redirectURI
    }

    /// True when a navigation in the login sheet is the redirect back to the
    /// portal, which the app intercepts instead of loading.
    public func isCallback(_ url: URL) -> Bool {
        url.scheme?.lowercased() == redirectURI.scheme?.lowercased()
            && url.host?.lowercased() == redirectURI.host?.lowercased()
            && url.path.lowercased() == redirectURI.path.lowercased()
    }

    /// Extracts the authorization code from the callback URL.
    public func code(fromCallback url: URL) throws -> String {
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        func value(_ name: String) -> String? { items.first { $0.name == name }?.value }

        if let error = value("error") {
            throw AuthError.provider(value("error_description") ?? error)
        }
        guard value("state") == state else { throw AuthError.stateMismatch }
        guard let code = value("code"), !code.isEmpty else { throw AuthError.missingCode }
        return code
    }
}
