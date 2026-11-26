import SwiftUI
import TrackManKit

struct WelcomeView: View {
    @EnvironmentObject private var session: AppSession
    @State private var request: AuthorizationRequest?
    @State private var isExchanging = false
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
                request = AuthorizationRequest(config: session.config)
            } label: {
                if isExchanging {
                    ProgressView().frame(maxWidth: .infinity)
                } else {
                    Text("Sign in with TrackMan").frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(isExchanging)
        }
        .padding(24)
        .sheet(item: $request) { request in
            NavigationStack {
                LoginWebView(
                    request: request,
                    onCode: { code in finish(code: code, request: request) },
                    onError: { error in
                        self.request = nil
                        errorMessage = error.localizedDescription
                    }
                )
                .ignoresSafeArea(edges: .bottom)
                .navigationTitle("TrackMan")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { self.request = nil }
                    }
                }
            }
        }
    }

    @MainActor
    private func finish(code: String, request: AuthorizationRequest) {
        self.request = nil
        isExchanging = true
        Task { @MainActor in
            defer { isExchanging = false }
            do {
                try await session.completeSignIn(code: code, request: request)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}
