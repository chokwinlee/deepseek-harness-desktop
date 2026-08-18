import SwiftUI
import UIKit
import WebKit

struct RemoteBrowserState: Equatable {
    var isLoading = true
    var progress = 0.0
    var errorMessage: String?
}

struct RemoteBrowserView: UIViewRepresentable {
    let baseURL: URL
    let reloadID: UUID
    @Binding var state: RemoteBrowserState

    func makeCoordinator() -> Coordinator {
        Coordinator(baseURL: baseURL, state: $state, reloadID: reloadID)
    }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        configuration.allowsInlineMediaPlayback = true
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true
        webView.scrollView.keyboardDismissMode = .interactive
        context.coordinator.observe(webView)
        webView.load(URLRequest(url: baseURL, cachePolicy: .reloadRevalidatingCacheData))
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        context.coordinator.state = $state
        if context.coordinator.reloadID != reloadID {
            context.coordinator.reloadID = reloadID
            webView.reload()
        }
    }

    static func dismantleUIView(_ webView: WKWebView, coordinator: Coordinator) {
        coordinator.stopObserving()
        webView.stopLoading()
        webView.navigationDelegate = nil
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        private let baseURL: URL
        var state: Binding<RemoteBrowserState>
        var reloadID: UUID
        private var progressObservation: NSKeyValueObservation?

        init(baseURL: URL, state: Binding<RemoteBrowserState>, reloadID: UUID) {
            self.baseURL = baseURL
            self.state = state
            self.reloadID = reloadID
        }

        func observe(_ webView: WKWebView) {
            progressObservation = webView.observe(\.estimatedProgress, options: [.new]) { [weak self] webView, _ in
                Task { @MainActor in
                    guard let self else { return }
                    self.state.wrappedValue.progress = webView.estimatedProgress
                }
            }
        }

        func stopObserving() {
            progressObservation?.invalidate()
            progressObservation = nil
        }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            state.wrappedValue.isLoading = true
            state.wrappedValue.errorMessage = nil
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            state.wrappedValue.isLoading = false
            state.wrappedValue.progress = 1
        }

        func webView(
            _ webView: WKWebView,
            didFailProvisionalNavigation navigation: WKNavigation!,
            withError error: Error
        ) {
            show(error)
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            show(error)
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
            guard let destination = navigationAction.request.url else {
                decisionHandler(.cancel)
                return
            }

            if isAllowed(destination) {
                decisionHandler(.allow)
                return
            }

            if destination.scheme == "https" || destination.scheme == "http" {
                UIApplication.shared.open(destination)
            }
            decisionHandler(.cancel)
        }

        private func isAllowed(_ destination: URL) -> Bool {
            if destination.scheme == "about" || destination.scheme == "blob" {
                return true
            }
            guard let destinationComponents = URLComponents(url: destination, resolvingAgainstBaseURL: false),
                  let baseComponents = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
                return false
            }
            return destinationComponents.scheme == baseComponents.scheme
                && destinationComponents.host == baseComponents.host
                && destinationComponents.port == baseComponents.port
        }

        private func show(_ error: Error) {
            let message: String
            if let urlError = error as? URLError,
               [.cannotFindHost, .cannotConnectToHost, .timedOut, .networkConnectionLost].contains(urlError.code) {
                message = "与电脑的连接已断开。请确认 Tailscale 和 Desktop 正在运行。"
            } else {
                message = error.localizedDescription
            }
            state.wrappedValue.isLoading = false
            state.wrappedValue.errorMessage = message
        }
    }
}
