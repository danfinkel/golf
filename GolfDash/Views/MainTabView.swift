import SwiftData
import SwiftUI

/// The signed-in app: a tab bar along the bottom. More tabs (irons, putting,
/// other apps) slot in here later.
struct MainTabView: View {
    @EnvironmentObject private var session: AppSession
    @Environment(\.modelContext) private var context
    @StateObject private var sync = SyncService()
    @Query private var rounds: [StoredRound]

    var body: some View {
        TabView {
            HomeView(sync: sync)
                .tabItem { Label("Home", systemImage: "house.fill") }
            DriverView(sync: sync)
                .tabItem { Label("Driver", systemImage: "figure.golf") }
        }
        .tint(Theme.pine)
        .task {
            let stale = sync.lastSynced.map { Date().timeIntervalSince($0) > 15 * 60 } ?? true
            if stale || rounds.isEmpty {
                await sync.sync(session: session, context: context)
            }
        }
    }
}
