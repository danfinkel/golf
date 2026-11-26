import SwiftUI
import TrackManKit

struct WelcomeView: View {
    @EnvironmentObject private var session: AppSession
    @State private var showLogin = false
    @State private var isSaving = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            BallFlightMark()
                .frame(width: 120, height: 120)
                .shadow(color: .black.opacity(0.18), radius: 10, y: 6)
            Text("Trading Strokes")
                .font(Theme.display())
                .foregroundStyle(Theme.ink)
            Text(session.sessionEnded
                 ? "Your TrackMan session ended. Sign in again to pick up where you left off."
                 : "Sign in with your TrackMan account to see your drive distance and practice volume.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Spacer()
            if let errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }
            Button {
                errorMessage = nil
                showLogin = true
            } label: {
                if isSaving {
                    ProgressView().frame(maxWidth: .infinity)
                } else {
                    Text("Sign in with TrackMan").frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(isSaving)
            Text("Tip: on the TrackMan login page, tap the key above the keyboard to fill your password from the Passwords app.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(24)
        .background(Theme.ground.ignoresSafeArea())
        .task {
            // TrackMan ended the session: reopen the login sheet right away.
            // The saved login usually finishes it with no typing.
            if session.sessionEnded { showLogin = true }
        }
        .sheet(isPresented: $showLogin) {
            NavigationStack {
                LoginWebView(
                    config: session.config,
                    onTokens: { tokens in finish(with: tokens) },
                    onError: { error in
                        showLogin = false
                        errorMessage = error.localizedDescription
                    }
                )
                .ignoresSafeArea(edges: .bottom)
                .navigationTitle("TrackMan")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { showLogin = false }
                    }
                }
            }
        }
    }

    @MainActor
    private func finish(with tokens: TokenSet) {
        showLogin = false
        isSaving = true
        Task { @MainActor in
            defer { isSaving = false }
            do {
                try await session.completeSignIn(with: tokens)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}
