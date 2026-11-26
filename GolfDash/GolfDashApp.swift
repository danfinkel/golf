import SwiftData
import SwiftUI

@main
struct GolfDashApp: App {
    @StateObject private var session = AppSession()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(session)
        }
        .modelContainer(for: [StoredRound.self, StoredActivity.self])
    }
}

struct RootView: View {
    @EnvironmentObject private var session: AppSession

    var body: some View {
        Group {
            switch session.state {
            case .loading:
                ProgressView()
            case .signedOut:
                WelcomeView()
            case .signedIn:
                DashboardView()
            }
        }
        .task { await session.restore() }
    }
}
