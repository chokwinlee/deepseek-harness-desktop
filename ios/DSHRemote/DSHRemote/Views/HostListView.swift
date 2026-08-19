import SwiftUI

struct HostListView: View {
    @EnvironmentObject private var hostStore: RemoteHostStore
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Binding var showsAddHost: Bool
    @State private var showsAbout = false
    @State private var pendingRemoval: RemoteHost?

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
        .background(RemoteTheme.canvas.ignoresSafeArea())
        .safeAreaInset(edge: .top, spacing: 0) {
            homeHeader
        }
        .remoteNavigationChromeHidden()
        .sheet(isPresented: $showsAbout) {
            AboutRemoteView()
                .environmentObject(hostStore)
                .presentationBackground(RemoteTheme.canvas)
        }
        .sheet(item: $pendingRemoval) { host in
            RemoteDestructiveConfirmationSheet(
                icon: "desktopcomputer",
                title: "移除“\(host.name)”？",
                message: "这只会删除这台 iPhone 保存的连接信息，不会改动电脑上的项目、会话或任务。",
                confirmTitle: "移除电脑"
            ) {
                remove(host)
                pendingRemoval = nil
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.hidden)
            .presentationBackground(RemoteTheme.canvas)
        }
    }

    private var homeHeader: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Harness Remote")
                        .font(.title2.weight(.bold))
                    HStack(alignment: .center, spacing: 8) {
                        Text(hostStore.hosts.isEmpty ? "从手机继续电脑上的 Harness" : "你的电脑")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Spacer(minLength: 4)
                        homeActions
                    }
                }
            } else {
                HStack(alignment: .center, spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Harness Remote")
                            .font(.title2.weight(.bold))
                        Text(hostStore.hosts.isEmpty ? "从手机继续电脑上的 Harness" : "你的电脑")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 8)
                    homeActions
                }
            }
        }
        .padding(.horizontal, RemoteTheme.pagePadding)
        .padding(.top, 8)
        .padding(.bottom, 12)
        .background(RemoteTheme.canvas.opacity(0.98))
        .dynamicTypeSize(...DynamicTypeSize.accessibility2)
    }

    private var homeActions: some View {
        HStack(spacing: 8) {
            Button {
                showsAbout = true
            } label: {
                Image(systemName: "info")
            }
            .buttonStyle(RemoteIconButtonStyle())
            .accessibilityLabel("关于与隐私")

            if !hostStore.hosts.isEmpty {
                Button {
                    showsAddHost = true
                } label: {
                    Image(systemName: "plus")
                }
                .buttonStyle(RemoteIconButtonStyle(tint: RemoteTheme.accent, emphasized: true))
                .accessibilityLabel("添加电脑")
            }
        }
    }

    private var savedHosts: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 10) {
                RemoteSectionHeader(title: "电脑", detail: "\(hostStore.hosts.count) 台")
                    .padding(.bottom, 2)

                ForEach(hostStore.hosts) { host in
                    HStack(spacing: 0) {
                        NavigationLink(value: host) {
                            HostRow(host: host)
                        }
                        .buttonStyle(.plain)

                        Menu {
                            Button("删除电脑", systemImage: "trash", role: .destructive) {
                                pendingRemoval = host
                            }
                        } label: {
                            Image(systemName: "ellipsis")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(.tertiary)
                                .frame(width: 44, height: 52)
                                .contentShape(Rectangle())
                        }
                        .accessibilityLabel("管理 \(host.name)")
                    }
                    .padding(.horizontal, 4)
                    .remoteSurface(cornerRadius: 14)
                    .contextMenu {
                        Button("删除电脑", systemImage: "trash", role: .destructive) {
                            pendingRemoval = host
                        }
                    }
                }

                Text("长按电脑也可以移除连接。删除只影响这台 iPhone。")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 2)
                    .padding(.top, 4)
            }
            .padding(.horizontal, RemoteTheme.pagePadding)
            .padding(.top, 8)
            .padding(.bottom, 28)
        }
    }

    private func remove(_ host: RemoteHost) {
        guard let index = hostStore.hosts.firstIndex(where: { $0.id == host.id }) else { return }
        withAnimation(.easeOut(duration: 0.18)) {
            hostStore.remove(at: IndexSet(integer: index))
        }
    }
}

private struct EmptyConnectionView: View {
    let addHost: () -> Void
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                ZStack {
                    RoundedRectangle(cornerRadius: 24)
                        .fill(RemoteTheme.raisedSurface)
                    RoundedRectangle(cornerRadius: 24)
                        .stroke(RemoteTheme.hairline, lineWidth: 1)
                    Image(systemName: "laptopcomputer.and.iphone")
                        .font(.system(size: 37, weight: .medium))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(RemoteTheme.accent)
                }
                .frame(
                    width: dynamicTypeSize.isAccessibilitySize ? 66 : 82,
                    height: dynamicTypeSize.isAccessibilitySize ? 66 : 82
                )
                .padding(.bottom, dynamicTypeSize.isAccessibilitySize ? 16 : 24)

                Text("连接你的电脑")
                    .font(.title.weight(.bold))

                Text(onboardingMessage)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
                    .padding(.top, 9)

                Button(action: addHost) {
                    Label("连接电脑", systemImage: "qrcode.viewfinder")
                }
                .buttonStyle(RemoteActionButtonStyle(kind: .primary))
                .padding(.top, 28)

                Group {
                    if dynamicTypeSize.isAccessibilitySize {
                        VStack(spacing: 8) {
                            connectionCapability(icon: "network", text: "同一 Wi-Fi")
                            connectionCapability(icon: "point.3.connected.trianglepath.dotted", text: "Tailscale")
                        }
                    } else {
                        HStack(spacing: 8) {
                            connectionCapability(icon: "network", text: "同一 Wi-Fi")
                            connectionCapability(icon: "point.3.connected.trianglepath.dotted", text: "Tailscale")
                        }
                    }
                }
                .padding(.top, 14)

                NavigationLink {
                    RemoteSessionView()
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(RemoteTheme.thinking)
                            .frame(width: 38, height: 38)
                            .background(RemoteTheme.thinking.opacity(0.10), in: RoundedRectangle(cornerRadius: 11))

                        VStack(alignment: .leading, spacing: 3) {
                            Text("还没有电脑？先体验一下")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.primary)
                            Text("离线查看项目、对话、轨迹与确认流程")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                        Spacer(minLength: 8)
                        Image(systemName: "arrow.right")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.tertiary)
                    }
                    .padding(13)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .remoteSurface(cornerRadius: 14)
                .padding(.top, 32)
            }
            .frame(maxWidth: 390)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 24)
            .padding(.top, dynamicTypeSize.isAccessibilitySize ? 18 : 40)
            .padding(.bottom, 34)
        }
    }

    private func connectionCapability(icon: String, text: String) -> some View {
        Label(text, systemImage: icon)
            .font(.caption.weight(.medium))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 10)
            .frame(minHeight: 30)
            .background(RemoteTheme.raisedSurface, in: Capsule())
    }

    private var onboardingMessage: String {
        dynamicTypeSize.isAccessibilitySize
            ? "在 Harness Desktop 开启手机 Remote。扫码后即可查看项目、会话和运行状态。"
            : "在 Harness Desktop 开启手机 Remote，\n扫码后即可查看项目、会话和运行状态。"
    }
}

private struct HostRow: View {
    let host: RemoteHost
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 12) {
                        hostGlyph
                        Text(host.name)
                            .font(.body.weight(.semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(2)
                        Spacer(minLength: 6)
                        disclosure
                    }
                    HStack(alignment: .center, spacing: 8) {
                        Text(host.address)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .truncationMode(.middle)
                        Spacer(minLength: 4)
                        RemoteStatusPill(text: host.transportLabel, color: transportColor)
                    }
                    .padding(.leading, 50)
                }
            } else {
                HStack(spacing: 12) {
                    hostGlyph
                    VStack(alignment: .leading, spacing: 5) {
                        HStack(alignment: .firstTextBaseline, spacing: 7) {
                            Text(host.name)
                                .font(.body.weight(.semibold))
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                            RemoteStatusPill(text: host.transportLabel, color: transportColor)
                        }
                        Text(host.address)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    Spacer(minLength: 6)
                    disclosure
                }
            }
        }
        .padding(.leading, 10)
        .padding(.vertical, 10)
        .frame(minHeight: 68)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(host.name)
        .accessibilityValue("\(host.transportLabel)，\(host.address)")
        .accessibilityHint("打开电脑上的项目与会话")
    }

    private var hostGlyph: some View {
        Image(systemName: hostIcon)
            .font(.system(size: 17, weight: .medium))
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(RemoteTheme.accent)
            .frame(width: 38, height: 38)
            .background(RemoteTheme.accent.opacity(0.10), in: RoundedRectangle(cornerRadius: 11))
    }

    private var disclosure: some View {
        Image(systemName: "chevron.right")
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(.tertiary)
    }

    private var hostIcon: String {
        switch host.transport {
        case .loopback: "desktopcomputer"
        case .sameWiFi, .unpairedLocalNetwork: "wifi"
        case .tailscale: "point.3.connected.trianglepath.dotted"
        case .https, .custom: "network"
        }
    }

    private var transportColor: Color {
        switch host.transport {
        case .loopback: RemoteTheme.warning
        case .sameWiFi: RemoteTheme.success
        case .unpairedLocalNetwork: RemoteTheme.danger
        case .tailscale, .https, .custom: RemoteTheme.accent
        }
    }
}
