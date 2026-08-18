import SwiftUI

struct RemoteSessionView: View {
    let host: RemoteHost

    @Environment(\.scenePhase) private var scenePhase
    @State private var reloadID = UUID()
    @State private var browserState = RemoteBrowserState()

    var body: some View {
        ZStack {
            RemoteBrowserView(baseURL: host.baseURL, reloadID: reloadID, state: $browserState)
                .ignoresSafeArea(.container, edges: .bottom)

            if let errorMessage = browserState.errorMessage {
                ContentUnavailableView {
                    Label("电脑已离线", systemImage: "wifi.slash")
                } description: {
                    Text(errorMessage)
                } actions: {
                    Button("重新连接") {
                        reloadID = UUID()
                    }
                    .buttonStyle(.borderedProminent)
                }
                .background(.background)
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            if browserState.isLoading {
                ProgressView(value: browserState.progress)
                    .progressViewStyle(.linear)
            }
        }
        .navigationTitle(host.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    reloadID = UUID()
                } label: {
                    Label("重新载入", systemImage: "arrow.clockwise")
                }
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active, browserState.errorMessage != nil {
                reloadID = UUID()
            }
        }
    }
}
