import SwiftUI
import TrackManKit
import WebKit

/// Shows TrackMan's own login page. When TrackMan redirects back to the web
/// portal's callback URL, the navigation is cancelled and the code is handed
/// to the app instead.
struct LoginWebView: UIViewRepresentable {
    let request: AuthorizationRequest
    let onCode: (String) -> Void
    let onError: (Error) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        // A fresh, non-persistent store so each sign-in starts clean and no
        // TrackMan cookies linger after sign-out.
        configuration.websiteDataStore = .nonPersistent()
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        webView.load(URLRequest(url: request.url))
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {}

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        private let parent: LoginWebView
        private var finished = false

        init(_ parent: LoginWebView) { self.parent = parent }

        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            guard let url = navigationAction.request.url, parent.request.isCallback(url) else {
                decisionHandler(.allow)
                return
            }
            decisionHandler(.cancel)
            guard !finished else { return }
            finished = true
            do {
                parent.onCode(try parent.request.code(fromCallback: url))
            } catch {
                parent.onError(error)
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
            // Cancelling the callback navigation reports a benign error; ignore it.
            let nsError = error as NSError
            if finished || (nsError.domain == "WebKitErrorDomain" && nsError.code == 102) { return }
            if nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled { return }
            parent.onError(error)
        }
    }
}
