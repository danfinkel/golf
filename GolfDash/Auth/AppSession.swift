import Foundation
import SwiftUI
import TrackManKit
import WebKit

/// App-wide sign-in state plus the API client built on it.
@MainActor
final class AppSession: ObservableObject {
    enum State: Equatable { case loading, signedOut, signedIn }

    @Published private(set) var state: State = .loading
    @Published private(set) var displayName: String?

    let config: TrackManConfig
    let tokens: TokenProvider
    let api: TrackManAPI

    init(config: TrackManConfig = .portal, store: TokenStore = KeychainTokenStore()) {
        self.config = config
        let refresher = PortalSessionClient(config: config, cookies: { await AppSession.portalCookies() })
        self.tokens = TokenProvider(refresher: refresher, store: store)
        self.api = TrackManAPI(client: GraphQLClient(config: config, tokens: tokens))
    }

    /// The login web view's cookies, which hold the TrackMan portal session.
    static func portalCookies() async -> [HTTPCookie] {
        await WKWebsiteDataStore.default().httpCookieStore.allCookies()
    }

    func restore() async {
        guard state == .loading else { return }
        let current = await tokens.current
        apply(current)
    }

    /// Called by the login sheet once the portal has handed over a token.
    func completeSignIn(with newTokens: TokenSet) async throws {
        try await tokens.signIn(with: newTokens)
        apply(newTokens)
    }

    /// Forgets the token and the portal session, so the next sign-in asks
    /// for credentials again.
    func signOut() async {
        await tokens.signOut()
        let store = WKWebsiteDataStore.default()
        let records = await store.dataRecords(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes())
        let trackman = records.filter { $0.displayName.lowercased().contains("trackman") }
        await store.removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), for: trackman)
        apply(nil)
    }

    /// Any call that finds the session ended routes back to sign-in.
    func handle(_ error: Error) async {
        if let auth = error as? AuthError, auth == .reauthenticationRequired || auth == .notSignedIn {
            await signOut()
        }
    }

    private func apply(_ tokens: TokenSet?) {
        displayName = tokens?.claims?.displayName
        state = tokens == nil ? .signedOut : .signedIn
    }
}
