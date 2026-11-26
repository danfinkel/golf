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
            Image(systemName: "figure.golf")
                .font(.system(size: 64))
                .foregroundStyle(.tint)
            Text("Golf Dash")
                .font(.largeTitle.bold())
            Text("Sign in with your TrackMan account to see your drive distance and practice volume.")
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
        }
        .padding(24)
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
