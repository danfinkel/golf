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
    @State private var showSplash = true

    var body: some View {
        ZStack {
            Group {
                switch session.state {
                case .loading:
                    Theme.ground.ignoresSafeArea()
                case .signedOut:
                    WelcomeView()
                case .signedIn:
                    DashboardView()
                }
            }
            if showSplash {
                SplashView()
                    .transition(.opacity)
                    .zIndex(1)
            }
        }
        .task { await session.restore() }
        .task {
            // Show the splash for one second on every launch, while the
            // session restores underneath.
            try? await Task.sleep(for: .seconds(1))
            withAnimation(.easeOut(duration: 0.35)) { showSplash = false }
        }
    }
}

/// The launch screen: icon, wordmark and tagline on fairway green.
struct SplashView: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.14, green: 0.40, blue: 0.25), Color(red: 0.06, green: 0.20, blue: 0.13)],
                startPoint: .top, endPoint: .bottom
            )
            .ignoresSafeArea()
            VStack(spacing: 18) {
                BallFlightMark()
                    .frame(width: 112, height: 112)
                    .shadow(color: .black.opacity(0.3), radius: 14, y: 8)
                Text("Trading Strokes")
                    .font(Theme.display())
                    .foregroundStyle(.white)
                Text("Know where your strokes go.")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Theme.flag)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
