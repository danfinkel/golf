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
    /// True when TrackMan ended the session on its own (not a sign-out), so
    /// the welcome screen reopens the login sheet. The saved TrackMan login
    /// usually lets that sheet finish without the password.
    @Published private(set) var sessionEnded = false

    let config: TrackManConfig
    let tokens: TokenProvider
    let api: TrackManAPI
    private let cookieStore: CookieStore

    init(
        config: TrackManConfig = .portal,
        store: TokenStore = KeychainTokenStore(),
        cookieStore: CookieStore = KeychainCookieStore()
    ) {
        self.config = config
        self.cookieStore = cookieStore
        let refresher = PortalSessionClient(
            config: config,
            cookies: { await AppSession.portalCookies(saved: cookieStore) },
            onCookies: { renewed in await AppSession.remember(renewed, in: cookieStore, config: config) }
        )
        self.tokens = TokenProvider(refresher: refresher, store: store)
        self.api = TrackManAPI(client: GraphQLClient(config: config, tokens: tokens))
    }

    /// The web view's cookies, plus any saved TrackMan cookies the web view
    /// lost (session cookies do not outlive the app).
    static func portalCookies(saved store: CookieStore) async -> [HTTPCookie] {
        let live = await WKWebsiteDataStore.default().httpCookieStore.allCookies()
        let liveStored = live.map(StoredCookie.init)
        let saved = (try? store.load()) ?? []
        return PortalCookies.merge(saved, with: liveStored).compactMap(\.cookie)
    }

    /// Saves cookies the portal set and puts them in the web view too.
    static func remember(_ cookies: [HTTPCookie], in store: CookieStore, config: TrackManConfig) async {
        let relevant = PortalCookies.relevant(cookies, domain: config.cookieDomain)
        guard !relevant.isEmpty else { return }
        let merged = PortalCookies.merge((try? store.load()) ?? [], with: relevant.map(StoredCookie.init))
        try? store.save(merged)
        let webStore = WKWebsiteDataStore.default().httpCookieStore
        for cookie in relevant {
            await webStore.setCookie(cookie)
        }
    }

    func restore() async {
        guard state == .loading else { return }
        await restoreSavedCookies()
        let current = await tokens.current
        apply(current)
    }

    /// Called by the login sheet once the portal has handed over a token.
    func completeSignIn(with newTokens: TokenSet) async throws {
        try await tokens.signIn(with: newTokens)
        await saveWebCookies()
        sessionEnded = false
        apply(newTokens)
    }

    /// Forgets the token, the saved cookies and the web view's TrackMan
    /// data, so the next sign-in asks for credentials again.
    func signOut() async {
        await tokens.signOut()
        try? cookieStore.clear()
        let store = WKWebsiteDataStore.default()
        let records = await store.dataRecords(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes())
        let trackman = records.filter { $0.displayName.lowercased().contains("trackman") }
        await store.removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), for: trackman)
        sessionEnded = false
        apply(nil)
    }

    /// Any call that finds the session ended routes back to sign-in. The
    /// TrackMan login cookies are kept, so signing back in is usually one
    /// tap with no password.
    func handle(_ error: Error) async {
        if let auth = error as? AuthError, auth == .reauthenticationRequired || auth == .notSignedIn {
            await tokens.signOut()
            sessionEnded = true
            apply(nil)
        }
    }

    /// Puts saved cookies back into the web view after a restart, where
    /// session cookies are gone.
    private func restoreSavedCookies() async {
        let saved = (try? cookieStore.load()) ?? []
        let cookies = PortalCookies.relevant(saved.compactMap(\.cookie), domain: config.cookieDomain)
        guard !cookies.isEmpty else { return }
        let webStore = WKWebsiteDataStore.default().httpCookieStore
        let live = Set(await webStore.allCookies().map { "\($0.name)|\($0.domain)|\($0.path)" })
        for cookie in cookies where !live.contains("\(cookie.name)|\(cookie.domain)|\(cookie.path)") {
            await webStore.setCookie(cookie)
        }
    }

    /// Snapshots TrackMan's cookies from the web view after a sign-in.
    private func saveWebCookies() async {
        let live = await WKWebsiteDataStore.default().httpCookieStore.allCookies()
        let relevant = PortalCookies.relevant(live, domain: config.cookieDomain)
        guard !relevant.isEmpty else { return }
        try? cookieStore.save(relevant.map(StoredCookie.init))
    }

    private func apply(_ tokens: TokenSet?) {
        displayName = tokens?.claims?.displayName
        state = tokens == nil ? .signedOut : .signedIn
    }
}
