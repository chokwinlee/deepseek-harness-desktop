import SwiftUI

struct RootView: View {
    @EnvironmentObject private var hostStore: RemoteHostStore
    @State private var showsAddHost = false

    var body: some View {
        #if DEBUG
        if let scenario = ProcessInfo.processInfo.environment["DSH_REMOTE_SCENARIO"] {
            debugScenario(scenario)
        } else {
            appRoot
        }
        #else
        appRoot
        #endif
    }

    private var appRoot: some View {
        NavigationStack {
            HostListView(showsAddHost: $showsAddHost)
                .navigationDestination(for: RemoteHost.self) { host in
                    RemoteSessionView(host: host)
                }
        }
        .tint(RemoteTheme.accent)
        .sheet(isPresented: $showsAddHost) {
            AddHostView()
                .environmentObject(hostStore)
                .presentationBackground(RemoteTheme.canvas)
        }
        .onChange(of: hostStore.pendingImportedConnection) { _, importedConnection in
            if importedConnection != nil {
                showsAddHost = true
            }
        }
    }

    #if DEBUG
    @ViewBuilder
    private func debugScenario(_ scenario: String) -> some View {
        switch scenario {
        case "projects":
            NavigationStack {
                RemoteSessionView()
            }
            .tint(RemoteTheme.accent)
        case "conversation", "models", "trajectory", "details", "rc8", "rc8-trajectory", "rc8-image-failure", "references", "image-draft", "subagents":
            NavigationStack {
                RemoteConversationView(
                    client: DemoHarnessRemoteClient(),
                    session: RemoteSessionSummary(
                        id: "review-demo-session",
                        title: "登录流程上线检查",
                        updatedAt: Date(),
                        running: false,
                        projectName: "Sample Project",
                        projectPath: "/Users/demo/Sample Project"
                    )
                )
            }
            .tint(RemoteTheme.accent)
        case "live-acceptance":
            if let endpoint = ProcessInfo.processInfo.environment["DSH_REMOTE_LIVE_ENDPOINT"],
               let baseURL = URL(string: endpoint),
               let sessionID = ProcessInfo.processInfo.environment["DSH_REMOTE_LIVE_SESSION_ID"],
               !sessionID.isEmpty {
                let accessToken = ProcessInfo.processInfo.environment["DSH_REMOTE_LIVE_TOKEN"]
                NavigationStack {
                    RemoteConversationView(
                        client: LiveHarnessRemoteClient(
                            baseURL: baseURL,
                            displayName: "v0.3.0 acceptance",
                            accessToken: accessToken?.isEmpty == false ? accessToken : nil
                        ),
                        session: RemoteSessionSummary(
                            id: sessionID,
                            title: "DSH Remote v0.3 验收",
                            updatedAt: Date(),
                            running: false,
                            projectName: "deepseek-harness-desktop",
                            projectPath: "/Users/chokwin/Documents/ChatGPT/deepseek-harness-desktop"
                        )
                    )
                }
                .tint(RemoteTheme.accent)
            } else {
                appRoot
            }
        case "add-host":
            AddHostView()
                .environmentObject(hostStore)
        case "about":
            AboutRemoteView()
                .environmentObject(hostStore)
        default:
            appRoot
        }
    }
    #endif
}
