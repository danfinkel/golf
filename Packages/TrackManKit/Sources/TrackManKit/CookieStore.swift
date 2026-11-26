import Foundation

/// A TrackMan cookie as saved in the Keychain. `HTTPCookie` is not Codable.
///
/// The portal and login cookies may be session cookies (no expiry date),
/// which the web view forgets when iOS ends the app. Saving them here and
/// putting them back at launch keeps the TrackMan session alive across
/// restarts, so the token can still be renewed without a password.
public struct StoredCookie: Codable, Equatable, Sendable {
    public var name: String
    public var value: String
    public var domain: String
    public var path: String
    public var expires: Date?
    public var secure: Bool
    public var httpOnly: Bool
    public var sameSite: String?

    public init(_ cookie: HTTPCookie) {
        name = cookie.name
        value = cookie.value
        domain = cookie.domain
        path = cookie.path
        expires = cookie.expiresDate
        secure = cookie.isSecure
        httpOnly = cookie.isHTTPOnly
        sameSite = cookie.sameSitePolicy?.rawValue
    }

    public var cookie: HTTPCookie? {
        var properties: [HTTPCookiePropertyKey: Any] = [
            .name: name,
            .value: value,
            .domain: domain,
            .path: path,
        ]
        if let expires { properties[.expires] = expires }
        if secure { properties[.secure] = "TRUE" }
        if httpOnly { properties[HTTPCookiePropertyKey("HttpOnly")] = "TRUE" }
        if let sameSite { properties[.sameSitePolicy] = sameSite }
        return HTTPCookie(properties: properties)
    }

    /// Cookies match when a newer one would replace the older in a browser.
    func sameSlot(as other: StoredCookie) -> Bool {
        name == other.name && path == other.path
            && domain.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
            == other.domain.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
    }
}

public enum PortalCookies {
    /// The cookies worth keeping: those for TrackMan's domains (portal and
    /// login), minus any that have expired.
    public static func relevant(_ cookies: [HTTPCookie], domain: String, now: Date = Date()) -> [HTTPCookie] {
        let suffix = domain.lowercased()
        return cookies.filter { cookie in
            let host = cookie.domain.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
            let onDomain = host == suffix || host.hasSuffix("." + suffix)
            let live = cookie.expiresDate.map { $0 > now } ?? true
            return onDomain && live
        }
    }

    /// `base` with `newer` laid over it; a newer cookie replaces a saved one
    /// with the same name, domain and path.
    public static func merge(_ base: [StoredCookie], with newer: [StoredCookie]) -> [StoredCookie] {
        var result = base.filter { old in !newer.contains { $0.sameSlot(as: old) } }
        result.append(contentsOf: newer)
        return result
    }
}

public protocol CookieStore: Sendable {
    func load() throws -> [StoredCookie]
    func save(_ cookies: [StoredCookie]) throws
    func clear() throws
}

public struct KeychainCookieStore: CookieStore {
    private let item: KeychainItem

    public init(service: String = "GolfDash.TrackMan", account: String = "portal-cookies") {
        item = KeychainItem(service: service, account: account)
    }

    public func load() throws -> [StoredCookie] {
        guard let data = try item.load() else { return [] }
        return try JSONDecoder().decode([StoredCookie].self, from: data)
    }

    public func save(_ cookies: [StoredCookie]) throws {
        try item.save(JSONEncoder().encode(cookies))
    }

    public func clear() throws {
        try item.clear()
    }
}

/// For tests and SwiftUI previews.
public final class InMemoryCookieStore: CookieStore, @unchecked Sendable {
    private let lock = NSLock()
    private var cookies: [StoredCookie]

    public init(_ cookies: [StoredCookie] = []) { self.cookies = cookies }

    public func load() throws -> [StoredCookie] { lock.withLock { cookies } }
    public func save(_ cookies: [StoredCookie]) throws { lock.withLock { self.cookies = cookies } }
    public func clear() throws { lock.withLock { cookies = [] } }
}
