import SwiftUI

struct HostListView: View {
    @EnvironmentObject private var hostStore: RemoteHostStore
    @Binding var showsAddHost: Bool
    @State private var showsAbout = false

    var body: some View {
        Group {
            if hostStore.hosts.isEmpty {
                EmptyConnectionView {
                    showsAddHost = true
                }
            } else {
                savedHosts
            }
        }
        .navigationTitle("Harness Remote")
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button {
                    showsAbout = true
                } label: {
                    Label("关于与隐私", systemImage: "info.circle")
                }

                if !hostStore.hosts.isEmpty {
                    Button {
                        showsAddHost = true
                    } label: {
                        Label("添加电脑", systemImage: "plus")
                    }
                }
            }
        }
        .sheet(isPresented: $showsAbout) {
            AboutRemoteView()
                .environmentObject(hostStore)
        }
    }

    private var savedHosts: some View {
        List {
            Section("电脑") {
                ForEach(hostStore.hosts) { host in
                    NavigationLink(value: host) {
                        HostRow(host: host)
                    }
                }
                .onDelete(perform: hostStore.remove)
            }
        }
        .listStyle(.insetGrouped)
    }
}

private struct EmptyConnectionView: View {
    let addHost: () -> Void
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                Image(systemName: "laptopcomputer.and.iphone")
                    .font(.system(size: 34, weight: .medium))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.primary)
                    .frame(width: 68, height: 68)
                    .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 18))
                    .padding(.bottom, 22)

                Text("连接你的电脑")
                    .font(.title2.weight(.bold))

                Text("在 Harness Desktop 中开启手机 Remote，然后扫码或输入地址。")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.top, 8)

                Button(action: addHost) {
                    Label("连接电脑", systemImage: "qrcode.viewfinder")
                        .font(.headline)
                        .foregroundStyle(Color(uiColor: .systemBackground))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .tint(.primary)
                .padding(.top, 28)

                Text("支持 Tailscale 和受信任的同一 Wi-Fi")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.top, 12)

                Group {
                    if dynamicTypeSize.isAccessibilitySize {
                        VStack(spacing: 6) {
                            experiencePrompt
                            experienceLink
                        }
                    } else {
                        HStack(spacing: 4) {
                            experiencePrompt
                            experienceLink
                        }
                    }
                }
                .font(.footnote)
                .padding(.top, 34)
            }
            .frame(maxWidth: 380)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 28)
            .padding(.top, 62)
            .padding(.bottom, 32)
        }
        .background(Color(uiColor: .systemBackground))
    }

    private var experiencePrompt: some View {
        Text("还没有可连接的电脑？")
            .foregroundStyle(.secondary)
    }

    private var experienceLink: some View {
        NavigationLink {
            RemoteSessionView()
        } label: {
            HStack(spacing: 3) {
                Text("先体验一下")
                Image(systemName: "arrow.right")
                    .font(.caption2.weight(.semibold))
            }
        }
    }
}

private struct HostRow: View {
    let host: RemoteHost

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "desktopcomputer")
                .font(.body.weight(.medium))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.tint)
                .frame(width: 36, height: 36)
                .background(Color.accentColor.opacity(0.10), in: RoundedRectangle(cornerRadius: 10))

            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(host.name)
                        .font(.headline)
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    Text(host.transportLabel)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Color(uiColor: .quaternarySystemFill), in: Capsule())
                }

                Text(host.address)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
        .padding(.vertical, 5)
        .accessibilityElement(children: .combine)
    }
}
