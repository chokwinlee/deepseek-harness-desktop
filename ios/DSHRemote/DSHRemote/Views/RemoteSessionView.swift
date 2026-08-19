import SwiftUI

struct RemoteSessionView: View {
    @StateObject private var viewModel: RemoteHostViewModel

    init(host: RemoteHost) {
        let client = LiveHarnessRemoteClient(
            baseURL: host.baseURL,
            displayName: host.name,
            accessToken: host.accessToken
        )
        _viewModel = StateObject(wrappedValue: RemoteHostViewModel(client: client))
    }

    init(demoClient: DemoHarnessRemoteClient = DemoHarnessRemoteClient()) {
        _viewModel = StateObject(wrappedValue: RemoteHostViewModel(client: demoClient))
    }

    var body: some View {
        List {
            connectionSection

            if viewModel.isLoading && viewModel.sessions.isEmpty {
                Section {
                    HStack(spacing: 12) {
                        ProgressView()
                        Text("正在读取电脑上的任务…")
                            .foregroundStyle(.secondary)
                    }
                }
            } else if viewModel.sessions.isEmpty && viewModel.errorMessage == nil {
                Section {
                    ContentUnavailableView(
                        "还没有任务",
                        systemImage: "bubble.left.and.text.bubble.right",
                        description: Text("先在 Harness Desktop 中创建任务，再回到这里刷新。")
                    )
                }
            } else {
                Section("最近任务") {
                    ForEach(viewModel.sessions) { session in
                        NavigationLink {
                            RemoteConversationView(client: viewModel.client, session: session)
                        } label: {
                            RemoteSessionRow(session: session)
                        }
                    }
                }
            }

            if let error = viewModel.errorMessage {
                Section {
                    ConnectionErrorCard(message: error) {
                        Task { await viewModel.refresh() }
                    }
                }
            }
        }
        .listSectionSpacing(18)
        .navigationTitle(viewModel.client.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await viewModel.refresh() }
        .task { await viewModel.monitor() }
    }

    private var connectionSection: some View {
        Section {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: viewModel.client.isDemo ? "sparkles" : "checkmark.shield.fill")
                    .font(.title2)
                    .foregroundStyle(viewModel.client.isDemo ? .purple : .green)
                    .frame(width: 44, height: 44)
                    .background(
                        (viewModel.client.isDemo ? Color.purple : Color.green).opacity(0.12),
                        in: RoundedRectangle(cornerRadius: 13)
                    )

                VStack(alignment: .leading, spacing: 5) {
                    Text(viewModel.client.isDemo ? "内置演示模式" : "已连接到你的电脑")
                        .font(.headline)
                    Text(connectionDetail)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 4)
        }
    }

    private var connectionDetail: String {
        if viewModel.client.isDemo {
            return "不连接网络、不调用模型，供功能体验与 App Review 使用。"
        }
        if let description = viewModel.description {
            return "Harness \(description.version) · \(description.attachedSessions) 个活跃会话"
        }
        return "任务执行、代码和模型凭据都留在电脑上。"
    }
}

private struct RemoteSessionRow: View {
    let session: RemoteSessionSummary

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(session.running ? Color.blue.opacity(0.14) : Color(.secondarySystemBackground))
                Image(systemName: session.running ? "waveform" : "checkmark")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(session.running ? .blue : .secondary)
            }
            .frame(width: 42, height: 42)

            VStack(alignment: .leading, spacing: 4) {
                Text(session.title)
                    .font(.body.weight(.semibold))
                    .lineLimit(2)
                HStack(spacing: 6) {
                    Text(session.running ? "执行中" : relativeUpdate)
                    if let project = session.projectName {
                        Text("·")
                        Text(project)
                            .lineLimit(1)
                    }
                }
                .font(.caption)
                .foregroundStyle(session.running ? .blue : .secondary)
            }
        }
        .padding(.vertical, 3)
    }

    private var relativeUpdate: String {
        let seconds = max(0, Date().timeIntervalSince(session.updatedAt))
        if seconds < 60 { return "刚刚" }
        if seconds < 3_600 { return "\(Int(seconds / 60)) 分钟前" }
        if seconds < 86_400 { return "\(Int(seconds / 3_600)) 小时前" }
        if seconds < 604_800 { return "\(Int(seconds / 86_400)) 天前" }
        return session.updatedAt.formatted(date: .abbreviated, time: .omitted)
    }
}

private struct ConnectionErrorCard: View {
    let message: String
    let retry: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("暂时无法连接", systemImage: "wifi.exclamationmark")
                .font(.headline)
                .foregroundStyle(.red)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Button("重新连接", action: retry)
                .buttonStyle(.bordered)
        }
        .padding(.vertical, 4)
    }
}
