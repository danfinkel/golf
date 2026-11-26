import Foundation

public struct TokenSet: Codable, Sendable, Equatable {
    public var accessToken: String
    public var refreshToken: String?
    public var expiresAt: Date
    public var idToken: String?

    public init(accessToken: String, refreshToken: String?, expiresAt: Date, idToken: String? = nil) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.expiresAt = expiresAt
        self.idToken = idToken
    }

    /// Treats a token as expired a little early so a request never races expiry.
    public func isExpired(at now: Date, leeway: TimeInterval = 60) -> Bool {
        now.addingTimeInterval(leeway) >= expiresAt
    }

    public var claims: AccessTokenClaims? { AccessTokenClaims.decode(jwt: accessToken) }
}

/// The few profile claims the app shows. Read without verifying the
/// signature: the token came straight from TrackMan over TLS and is only
/// used for display here; the API does the real verification.
public struct AccessTokenClaims: Decodable, Sendable, Equatable {
    public let name: String?
    public let givenName: String?
    public let email: String?

    enum CodingKeys: String, CodingKey {
        case name
        case givenName = "given_name"
        case email
    }

    public var displayName: String? { givenName ?? name ?? email }

    public static func decode(jwt: String) -> AccessTokenClaims? {
        let parts = jwt.split(separator: ".")
        guard parts.count >= 2 else { return nil }
        var base64 = String(parts[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while base64.count % 4 != 0 { base64 += "=" }
        guard let data = Data(base64Encoded: base64) else { return nil }
        return try? JSONDecoder().decode(AccessTokenClaims.self, from: data)
    }
}

struct TokenResponse: Decodable {
    let accessToken: String
    let refreshToken: String?
    let expiresIn: Double?
    let idToken: String?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresIn = "expires_in"
        case idToken = "id_token"
    }
}

struct TokenErrorResponse: Decodable {
    let error: String
    let errorDescription: String?

    enum CodingKeys: String, CodingKey {
        case error
        case errorDescription = "error_description"
    }
}
