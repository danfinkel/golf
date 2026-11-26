import Foundation

/// Hands out a valid access token, refreshing it silently when it is about to
/// expire. Concurrent callers share one refresh.
public actor TokenProvider {
    private let client: OAuthClient
    private let store: TokenStore
    private let now: @Sendable () -> Date
    private var tokens: TokenSet?
    private var refreshTask: Task<TokenSet, Error>?

    public init(client: OAuthClient, store: TokenStore, now: @escaping @Sendable () -> Date = { Date() }) {
        self.client = client
        self.store = store
        self.now = now
        self.tokens = try? store.load()
    }

    public var isSignedIn: Bool { tokens != nil }
    public var current: TokenSet? { tokens }

    public func signIn(with newTokens: TokenSet) throws {
        tokens = newTokens
        try store.save(newTokens)
    }

    public func signOut() {
        tokens = nil
        refreshTask?.cancel()
        refreshTask = nil
        try? store.clear()
    }

    public func validAccessToken(forceRefresh: Bool = false) async throws -> String {
        guard let current = tokens else { throw AuthError.notSignedIn }
        if !forceRefresh, !current.isExpired(at: now()) {
            return current.accessToken
        }
        return try await refreshed(from: current).accessToken
    }

    private func refreshed(from current: TokenSet) async throws -> TokenSet {
        if let inFlight = refreshTask {
            return try await inFlight.value
        }
        let client = self.client
        let task = Task { try await client.refresh(current) }
        refreshTask = task
        defer { refreshTask = nil }
        do {
            let fresh = try await task.value
            tokens = fresh
            try? store.save(fresh)
            return fresh
        } catch AuthError.reauthenticationRequired {
            tokens = nil
            try? store.clear()
            throw AuthError.reauthenticationRequired
        }
    }
}
