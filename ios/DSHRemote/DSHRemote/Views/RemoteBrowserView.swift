import SwiftUI
import UIKit
import WebKit

struct RemoteBrowserState: Equatable {
    var isLoading = true
    var progress = 0.0
    var errorMessage: String?
    var sessionTitle: String?
    var isMobileAdaptationReady = false
    var isSettingsPresented = false
}

enum RemoteBrowserAction: String {
    case toggleSidebar
    case newSession
    case closeSettings
    case reload
}

struct RemoteBrowserCommand: Equatable {
    let id = UUID()
    let action: RemoteBrowserAction
}

struct RemoteBrowserView: UIViewRepresentable {
    let baseURL: URL
    let reloadID: UUID
    let command: RemoteBrowserCommand?
    @Binding var state: RemoteBrowserState

    func makeCoordinator() -> Coordinator {
        Coordinator(baseURL: baseURL, state: $state, reloadID: reloadID)
    }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        configuration.allowsInlineMediaPlayback = true
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        configuration.userContentController.add(context.coordinator, name: Coordinator.stateMessageName)
        configuration.userContentController.add(context.coordinator, name: Coordinator.notificationMessageName)
        configuration.userContentController.add(context.coordinator, name: Coordinator.activityMessageName)

        if let scriptURL = Bundle.main.url(forResource: "RemoteMobileAdaptation", withExtension: "js"),
           let script = try? String(contentsOf: scriptURL, encoding: .utf8) {
            configuration.userContentController.addUserScript(
                WKUserScript(source: script, injectionTime: .atDocumentEnd, forMainFrameOnly: true)
            )
        } else {
            assertionFailure("RemoteMobileAdaptation.js is missing from the app bundle")
        }

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
        if let command, context.coordinator.lastCommandID != command.id {
            context.coordinator.lastCommandID = command.id
            webView.evaluateJavaScript(
                "window.__dshRemoteMobile?.command('\(command.action.rawValue)')"
            )
        }
    }

    static func dismantleUIView(_ webView: WKWebView, coordinator: Coordinator) {
        coordinator.stopObserving()
        webView.stopLoading()
        webView.navigationDelegate = nil
        webView.configuration.userContentController.removeScriptMessageHandler(forName: Coordinator.stateMessageName)
        webView.configuration.userContentController.removeScriptMessageHandler(forName: Coordinator.notificationMessageName)
        webView.configuration.userContentController.removeScriptMessageHandler(forName: Coordinator.activityMessageName)
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        static let stateMessageName = "dshRemoteState"
        static let notificationMessageName = "dshRemoteNotification"
        static let activityMessageName = "dshRemoteActivity"

        private let baseURL: URL
        var state: Binding<RemoteBrowserState>
        var reloadID: UUID
        var lastCommandID: UUID?
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

        func userContentController(
            _ userContentController: WKUserContentController,
            didReceive message: WKScriptMessage
        ) {
            guard let payload = message.body as? [String: Any] else {
                return
            }

            if message.name == Self.notificationMessageName {
                if let event = RemoteNotificationEvent(payload: payload) {
                    RemoteNotificationManager.shared.deliver(event)
                }
                return
            }

            if message.name == Self.activityMessageName {
                RemoteNotificationManager.shared.setMonitoringActive(payload["active"] as? Bool ?? false)
                return
            }

            guard message.name == Self.stateMessageName else { return }

            Task { @MainActor in
                if let title = payload["title"] as? String, !title.isEmpty {
                    self.state.wrappedValue.sessionTitle = title
                } else {
                    self.state.wrappedValue.sessionTitle = nil
                }
                self.state.wrappedValue.isMobileAdaptationReady = payload["ready"] as? Bool ?? false
                self.state.wrappedValue.isSettingsPresented = payload["settings"] as? Bool ?? false
            }
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
