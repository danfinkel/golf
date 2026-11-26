import Foundation

/// TrackMan endpoints.
///
/// TrackMan has no public developer API. The web portal signs in on its own
/// server (it holds the OAuth client secret) and hands the browser a bearer
/// token from `/api/account/me`, keyed by the portal's session cookie. The app
/// signs in on that portal page and reads the same endpoint (observed Nov 2026).
/// If TrackMan changes any of this, this is the only file to update.
public struct TrackManConfig: Sendable, Equatable {
    public var portalURL: URL
    public var sessionPath: String
    public var graphQLURL: URL

    public init(portalURL: URL, sessionPath: String, graphQLURL: URL) {
        self.portalURL = portalURL
        self.sessionPath = sessionPath
        self.graphQLURL = graphQLURL
    }

    public static let portal = TrackManConfig(
        portalURL: URL(string: "https://portal.trackmangolf.com/")!,
        sessionPath: "/api/account/me",
        graphQLURL: URL(string: "https://api.trackmangolf.com/graphql")!
    )

    public var sessionURL: URL { URL(string: sessionPath, relativeTo: portalURL)!.absoluteURL }
    public var portalHost: String { portalURL.host ?? "portal.trackmangolf.com" }
    /// Sent as Origin/Referer on API calls, matching the web portal.
    public var webOrigin: String { "https://\(portalHost)" }

    /// True once the login web view is back on the portal (signed in), rather
    /// than on the TrackMan login pages.
    public func isPortalPage(_ url: URL?) -> Bool {
        guard let url, url.host?.lowercased() == portalHost.lowercased() else { return false }
        return !url.path.lowercased().hasPrefix("/account/")
    }
}
