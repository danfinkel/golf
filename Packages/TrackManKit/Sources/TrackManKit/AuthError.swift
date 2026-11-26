import Foundation

public enum AuthError: Error, Equatable, LocalizedError {
    case notSignedIn
    case reauthenticationRequired
    case provider(String)

    public var errorDescription: String? {
        switch self {
        case .notSignedIn:
            return "Not signed in to TrackMan."
        case .reauthenticationRequired:
            return "Your TrackMan session has ended. Please sign in again."
        case .provider(let message):
            return "TrackMan sign-in failed: \(message)"
        }
    }
}
