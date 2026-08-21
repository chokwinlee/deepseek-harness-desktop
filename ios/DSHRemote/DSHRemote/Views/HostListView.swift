import SwiftUI

struct HostListView: View {
    @EnvironmentObject private var hostStore: RemoteHostStore
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Binding var showsAddHost: Bool
    @Binding var addHostStartsWithScanner: Bool
    @State private var showsAbout = false
    @State private var pendingRemoval: RemoteHost?

    var body: some View {
        Group {
            if hostStore.hosts.isEmpty {
                EmptyConnectionView {
                    addHostStartsWithScanner = true
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
            .remoteDestructiveConfirmationPresentation(for: dynamicTypeSize)
        }
    }

    private var homeHeader: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 5) {
                    Text("DSH Remote")
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
                        Text("DSH Remote")
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
        .background(RemoteTheme.canvas)
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
                    addHostStartsWithScanner = false
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
                        .buttonStyle(RemotePressableRowButtonStyle(cornerRadius: 12))

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
        withAnimation(reduceMotion ? nil : .spring(response: 0.28, dampingFraction: 1)) {
            hostStore.remove(at: IndexSet(integer: index))
        }
    }
}

private struct EmptyConnectionView: View {
    let addHost: () -> Void
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 10) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 20)
                            .fill(RemoteTheme.accent.opacity(0.10))
                        Image(systemName: "laptopcomputer.and.iphone")
                            .font(.system(size: dynamicTypeSize.isAccessibilitySize ? 28 : 33, weight: .medium))
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(RemoteTheme.accent)
                    }
                    .frame(width: 70, height: 70)
                    .accessibilityHidden(true)

                    Text("先连接同一 Wi-Fi 的电脑")
                        .font(.title.weight(.bold))
                        .fixedSize(horizontal: false, vertical: true)

                    Text("iPhone 和 Mac 在同一个受信任 Wi-Fi 时，直接扫描 Desktop 二维码即可，不需要安装或登录 Tailscale。")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)
                }

                localPairingSteps
                    .padding(.top, 22)

                Button(action: addHost) {
                    Label("开始同一 Wi-Fi 配对", systemImage: "qrcode.viewfinder")
                }
                .buttonStyle(RemoteActionButtonStyle(kind: .primary))
                .accessibilityHint("打开连接页面并扫描 DSH Desktop 二维码")
                .padding(.top, 18)

                crossNetworkNote
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
                .buttonStyle(RemotePressableRowButtonStyle(cornerRadius: 14))
                .remoteSurface(cornerRadius: 14)
                .padding(.top, 28)
            }
            .frame(maxWidth: 390)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, RemoteTheme.pagePadding)
            .padding(.top, dynamicTypeSize.isAccessibilitySize ? 14 : 28)
            .padding(.bottom, 34)
        }
    }

    private var localPairingSteps: some View {
        VStack(alignment: .leading, spacing: 12) {
            pairingStep(
                number: 1,
                title: "在 Mac 打开本地 Remote",
                detail: "DSH Desktop → 设置 → 通用 → 手机 Remote → 连接 iPhone → 开始本地配对"
            )
            pairingStep(
                number: 2,
                title: "用 iPhone 扫描二维码",
                detail: "扫码后 App 会自动验证电脑并保存连接"
            )
        }
        .padding(14)
        .remoteSurface(cornerRadius: 16)
    }

    private func pairingStep(number: Int, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 11) {
            Text("\(number)")
                .font(.caption.weight(.bold))
                .foregroundStyle(RemoteTheme.accent)
                .frame(width: 25, height: 25)
                .background(RemoteTheme.accent.opacity(0.11), in: Circle())
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var crossNetworkNote: some View {
        HStack(alignment: .top, spacing: 11) {
            Image(systemName: "network")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 28, height: 28)
                .background(RemoteTheme.raisedSurface, in: RoundedRectangle(cornerRadius: 8))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text("需要跨网络连接？")
                    .font(.subheadline.weight(.semibold))
                Text("Tailscale 或自有 HTTPS 是离开同一 Wi-Fi 后的可选方式，可在下一页配置。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 2)
        .accessibilityElement(children: .combine)
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
                    }
                    .padding(.leading, 50)
                    RemoteStatusPill(text: host.transportLabel, color: transportColor)
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
