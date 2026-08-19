import SwiftUI

struct HostListView: View {
    @EnvironmentObject private var hostStore: RemoteHostStore
    @Binding var showsAddHost: Bool
    @State private var showsAbout = false

    var body: some View {
        List {
            Section {
                NavigationLink {
                    RemoteSessionView()
                } label: {
                    DemoModeRow()
                }
            } header: {
                Text("先体验完整流程")
            } footer: {
                Text("演示模式不连接网络、不执行代码，也不会调用模型。")
            }

            if hostStore.hosts.isEmpty {
                Section {
                    VStack(alignment: .leading, spacing: 14) {
                        Label("连接你自己的电脑", systemImage: "laptopcomputer.and.iphone")
                            .font(.headline)
                        Text("在 Harness Desktop 中开启手机 Remote。跨网络使用 Tailscale；同一受信任 Wi-Fi 可直接扫码连接。")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Button("添加电脑") { showsAddHost = true }
                            .buttonStyle(.borderedProminent)
                    }
                    .padding(.vertical, 6)
                }
            } else {
                Section("我的电脑") {
                    ForEach(hostStore.hosts) { host in
                        NavigationLink(value: host) {
                            HostRow(host: host)
                        }
                    }
                    .onDelete(perform: hostStore.remove)
                }
            }

            Section {
                Label {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("本地优先")
                            .font(.subheadline.weight(.semibold))
                        Text("任务、代码和模型凭据留在你的电脑；本项目不提供云端中继。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } icon: {
                    Image(systemName: "lock.shield")
                        .foregroundStyle(.green)
                }
            }
        }
        .listSectionSpacing(20)
        .navigationTitle("Harness Remote")
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button {
                    showsAbout = true
                } label: {
                    Label("关于与隐私", systemImage: "info.circle")
                }
                Button {
                    showsAddHost = true
                } label: {
                    Label("添加电脑", systemImage: "plus")
                }
            }
        }
        .sheet(isPresented: $showsAbout) {
            AboutRemoteView()
                .environmentObject(hostStore)
        }
    }
}

private struct DemoModeRow: View {
    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "sparkles")
                .font(.title2.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: 48, height: 48)
                .background(
                    LinearGradient(
                        colors: [.indigo, .purple],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    in: RoundedRectangle(cornerRadius: 14)
                )
            VStack(alignment: .leading, spacing: 4) {
                Text("审核演示")
                    .font(.headline)
                Text("查看任务、发送补充、处理确认")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 5)
    }
}

private struct HostRow: View {
    let host: RemoteHost

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "desktopcomputer")
                .font(.title3)
                .foregroundStyle(.tint)
                .frame(width: 40, height: 40)
                .background(.tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))

            VStack(alignment: .leading, spacing: 3) {
                Text(host.name)
                    .font(.body.weight(.semibold))
                Text(host.address)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Text(host.transportLabel)
                    .font(.caption2)
                    .foregroundStyle(transportColor)
            }
        }
        .padding(.vertical, 3)
    }

    private var transportColor: Color {
        switch host.transport {
        case .loopback:
            .orange
        case .sameWiFi:
            .green
        case .unpairedLocalNetwork:
            .red
        case .tailscale:
            .blue
        case .https:
            .indigo
        case .custom:
            .secondary
        }
    }
}
