import SwiftUI

struct RemoteSessionView: View {
    let host: RemoteHost

    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var reloadID = UUID()
    @State private var browserState = RemoteBrowserState()
    @State private var browserCommand: RemoteBrowserCommand?

    var body: some View {
        ZStack {
            RemoteBrowserView(
                baseURL: host.baseURL,
                reloadID: reloadID,
                command: browserCommand,
                state: $browserState
            )
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
            RemoteTopBar(
                title: browserState.isSettingsPresented
                    ? "设置"
                    : (browserState.sessionTitle ?? "新对话"),
                hostName: host.name,
                isLoading: browserState.isLoading,
                isReady: browserState.isMobileAdaptationReady,
                showsSessionActions: !browserState.isSettingsPresented,
                progress: browserState.progress,
                onBack: {
                    if browserState.isSettingsPresented {
                        send(.closeSettings)
                    } else {
                        dismiss()
                    }
                },
                onSessions: { send(.toggleSidebar) },
                onNewSession: { send(.newSession) }
            )
        }
        .toolbar(.hidden, for: .navigationBar)
        .onChange(of: scenePhase) { _, phase in
            if phase == .active, browserState.errorMessage != nil {
                reloadID = UUID()
            }
        }
    }

    private func send(_ action: RemoteBrowserAction) {
        browserCommand = RemoteBrowserCommand(action: action)
    }
}

private struct RemoteTopBar: View {
    let title: String
    let hostName: String
    let isLoading: Bool
    let isReady: Bool
    let showsSessionActions: Bool
    let progress: Double
    let onBack: () -> Void
    let onSessions: () -> Void
    let onNewSession: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                toolbarButton("返回", systemImage: "chevron.left", action: onBack)
                if showsSessionActions {
                    toolbarButton("会话", systemImage: "sidebar.left", action: onSessions)
                }

                VStack(spacing: 2) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)

                    HStack(spacing: 5) {
                        Circle()
                            .fill(isReady ? Color.green : Color.orange)
                            .frame(width: 6, height: 6)
                        Text("\(hostName) · \(connectionLabel)")
                            .lineLimit(1)
                    }
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 6)

                if showsSessionActions {
                    toolbarButton("新建会话", systemImage: "square.and.pencil", action: onNewSession)
                } else {
                    Color.clear
                        .frame(width: 44, height: 44)
                }
            }
            .frame(height: 52)
            .padding(.horizontal, 4)

            if isLoading {
                ProgressView(value: progress)
                    .progressViewStyle(.linear)
            } else {
                Divider()
            }
        }
        .background(.bar)
    }

    private var connectionLabel: String {
        if isLoading { return "连接中" }
        return isReady ? "已连接" : "正在载入"
    }

    private func toolbarButton(
        _ title: String,
        systemImage: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.body.weight(.medium))
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .accessibilityLabel(title)
    }
}
