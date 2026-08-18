import SwiftUI

struct RootView: View {
    @EnvironmentObject private var hostStore: RemoteHostStore
    @State private var showsAddHost = false

    var body: some View {
        NavigationStack {
            HostListView(showsAddHost: $showsAddHost)
                .navigationDestination(for: RemoteHost.self) { host in
                    RemoteSessionView(host: host)
                }
        }
        .sheet(isPresented: $showsAddHost) {
            AddHostView()
                .environmentObject(hostStore)
        }
        .onChange(of: hostStore.pendingImportedURL) { _, importedURL in
            if importedURL != nil {
                showsAddHost = true
            }
        }
    }
}
