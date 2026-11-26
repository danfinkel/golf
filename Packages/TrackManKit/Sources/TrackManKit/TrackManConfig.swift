import Foundation

/// Endpoints and OAuth client settings for TrackMan.
///
/// TrackMan has no public developer API. These values mirror what the
/// TrackMan web portal (portal.trackmangolf.com) uses, observed in Nov 2026.
/// If TrackMan changes them, this is the only file that needs updating.
public struct TrackManConfig: Sendable, Equatable {
    public var issuer: URL
    public var clientID: String
    public var redirectURI: URL
    public var scopes: [String]
    public var graphQLURL: URL
    /// Sent as Origin/Referer on API calls, matching the web portal.
    public var webOrigin: String

    public init(issuer: URL, clientID: String, redirectURI: URL, scopes: [String], graphQLURL: URL, webOrigin: String) {
        self.issuer = issuer
        self.clientID = clientID
        self.redirectURI = redirectURI
        self.scopes = scopes
        self.graphQLURL = graphQLURL
        self.webOrigin = webOrigin
    }

    public static let portal = TrackManConfig(
        issuer: URL(string: "https://login.trackmangolf.com")!,
        clientID: "golf-portal.2dad6810-ef7c-4a0d-9c0a-0eaae2fb9e98",
        redirectURI: URL(string: "https://portal.trackmangolf.com/account/callback")!,
        scopes: [
            "openid",
            "profile",
            "email",
            "offline_access",
            "https://auth.trackman.com/dr/cloud",
            "https://auth.trackman.com/authorization",
            "https://auth.trackman.com/proamevent",
        ],
        graphQLURL: URL(string: "https://api.trackmangolf.com/graphql")!,
        webOrigin: "https://portal.trackmangolf.com"
    )

    public var authorizeEndpoint: URL { issuer.appendingPathComponent("connect/authorize") }
    public var tokenEndpoint: URL { issuer.appendingPathComponent("connect/token") }
}
