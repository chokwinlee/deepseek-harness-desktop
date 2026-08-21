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
        case "conversation", "models", "trajectory", "details", "rc8", "rc8-trajectory", "rc8-image-failure":
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
