import Foundation
import SwiftUI
import TrackManKit

/// App-wide sign-in state plus the API client built on it.
@MainActor
final class AppSession: ObservableObject {
    enum State: Equatable { case loading, signedOut, signedIn }

    @Published private(set) var state: State = .loading
    @Published private(set) var displayName: String?

    let config: TrackManConfig
    let oauth: OAuthClient
    let tokens: TokenProvider
    let api: TrackManAPI

    init(config: TrackManConfig = .portal, store: TokenStore = KeychainTokenStore()) {
        self.config = config
        self.oauth = OAuthClient(config: config)
        self.tokens = TokenProvider(client: oauth, store: store)
        self.api = TrackManAPI(client: GraphQLClient(config: config, tokens: tokens))
    }

    func restore() async {
        guard state == .loading else { return }
        let current = await tokens.current
        apply(current)
    }

    /// Called by the login sheet once it has captured the authorization code.
    func completeSignIn(code: String, request: AuthorizationRequest) async throws {
        let newTokens = try await oauth.exchange(code: code, request: request)
        try await tokens.signIn(with: newTokens)
        apply(newTokens)
    }

    func signOut() async {
        await tokens.signOut()
        apply(nil)
    }

    /// Any call that finds the session revoked routes back to sign-in.
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
