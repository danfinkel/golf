import Foundation

public enum AuthError: Error, Equatable, LocalizedError {
    case notSignedIn
    case reauthenticationRequired
    case stateMismatch
    case missingCode
    case provider(String)
    case tokenEndpoint(status: Int, body: String)

    public var errorDescription: String? {
        switch self {
        case .notSignedIn:
            return "Not signed in to TrackMan."
        case .reauthenticationRequired:
            return "Your TrackMan session has ended. Please sign in again."
        case .stateMismatch:
            return "The sign-in response did not match this request. Please try again."
        case .missingCode:
            return "TrackMan did not return an authorization code."
        case .provider(let message):
            return "TrackMan sign-in failed: \(message)"
        case .tokenEndpoint(let status, _):
            return "TrackMan token request failed (HTTP \(status))."
        }
    }
}
