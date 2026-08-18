import SwiftUI

struct HostListView: View {
    @EnvironmentObject private var hostStore: RemoteHostStore
    @Binding var showsAddHost: Bool

    var body: some View {
        Group {
            if hostStore.hosts.isEmpty {
                ContentUnavailableView {
                    Label("连接你的电脑", systemImage: "laptopcomputer.and.iphone")
                } description: {
                    Text("先在 DeepSeek Harness Desktop 中开启 Remote，然后扫描电脑上的二维码。")
                } actions: {
                    Button("添加电脑") {
                        showsAddHost = true
                    }
                    .buttonStyle(.borderedProminent)
                }
            } else {
                List {
                    Section("我的电脑") {
                        ForEach(hostStore.hosts) { host in
                            NavigationLink(value: host) {
                                HostRow(host: host)
                            }
                        }
                        .onDelete(perform: hostStore.remove)
                    }

                    Section {
                        Label("连接由你自己的 Tailscale 网络保护；任务、代码和密钥不会经过本项目的服务器。", systemImage: "lock.shield")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .navigationTitle("DSH Remote")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showsAddHost = true
                } label: {
                    Label("添加电脑", systemImage: "plus")
                }
            }
        }
    }
}

private struct HostRow: View {
    let host: RemoteHost

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "desktopcomputer")
                .font(.title3)
                .foregroundStyle(.tint)
                .frame(width: 36, height: 36)
                .background(.tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))

            VStack(alignment: .leading, spacing: 3) {
                Text(host.name)
                    .font(.body.weight(.medium))
                Text(host.address)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 4)
    }
}
