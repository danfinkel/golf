import Foundation

/// Hands out a valid access token, renewing it from the portal session when
/// it is about to expire. Concurrent callers share one renewal.
public actor TokenProvider {
    private let refresher: TokenRefresher
    private let store: TokenStore
    private let now: @Sendable () -> Date
    private var tokens: TokenSet?
    private var refreshTask: Task<TokenSet, Error>?

    public init(refresher: TokenRefresher, store: TokenStore, now: @escaping @Sendable () -> Date = { Date() }) {
        self.refresher = refresher
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
        return try await refreshed().accessToken
    }

    private func refreshed() async throws -> TokenSet {
        if let inFlight = refreshTask {
            return try await inFlight.value
        }
        let refresher = self.refresher
        let task = Task { try await refresher.refresh() }
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
