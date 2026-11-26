import SwiftUI
import TrackManKit
import WebKit

/// Signs in on the TrackMan web portal exactly as a browser would. Once the
/// web view is back on a portal page, it reads the portal's own
/// `/api/account/me`, which returns the bearer token the portal uses.
///
/// The default (persistent) website data store keeps the portal session
/// cookie, so the app can renew the token later without asking for the
/// password again.
struct LoginWebView: UIViewRepresentable {
    let config: TrackManConfig
    let onTokens: (TokenSet) -> Void
    let onError: (Error) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        webView.load(URLRequest(url: config.portalURL))
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {}

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        private let parent: LoginWebView
        private var finished = false
        private var checking = false

        init(_ parent: LoginWebView) { self.parent = parent }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            guard parent.config.isPortalPage(webView.url) else { return }
            readToken(from: webView)
        }

        private func readToken(from webView: WKWebView) {
            guard !finished, !checking else { return }
            checking = true
            let script = """
            const response = await fetch('\(parent.config.sessionPath)', { credentials: 'include', headers: { 'Accept': 'application/json' } });
            return await response.text();
            """
            Task { @MainActor in
                defer { checking = false }
                do {
                    let result = try await webView.callAsyncJavaScript(script, contentWorld: .page)
                    guard let text = result as? String,
                          let tokens = PortalAccount.parse(text)?.tokenSet() else {
                        return // Not signed in yet; the portal will send the user to login.
                    }
                    guard !finished else { return }
                    finished = true
                    parent.onTokens(tokens)
                } catch {
                    // The page may still be redirecting; a later didFinish retries.
                }
            }
        }

        // Apple and Microsoft sign-in may open a popup; keep it in this view.
        func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
            if navigationAction.targetFrame == nil {
                webView.load(navigationAction.request)
            }
            return nil
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            let nsError = error as NSError
            if finished || (nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled) { return }
            if nsError.domain == "WebKitErrorDomain" && nsError.code == 102 { return }
            parent.onError(error)
        }
    }
}
