import SwiftUI
import UIKit
import VisionKit

struct AddHostView: View {
    private enum Field: Hashable {
        case name, address
    }

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var hostStore: RemoteHostStore
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    let autoStartsScanner: Bool

    @State private var name = ""
    @State private var address = ""
    @State private var showsScanner = false
    @State private var showsTailscaleGuide = false
    @State private var showsCrossNetworkEntry = false
    @State private var hasImportedConnection = false
    @State private var isChecking = false
    @State private var errorMessage: String?
    @State private var verificationTask: Task<Void, Never>?
    @State private var verificationGeneration = 0
    @State private var didAutoStartScanner = false
    @State private var scannerAvailabilityRevision = 0
    @FocusState private var focusedField: Field?

    init(autoStartsScanner: Bool = false) {
        self.autoStartsScanner = autoStartsScanner
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                RemoteSheetHeader(
                    title: "添加电脑",
                    subtitle: connectionSubtitle,
                    closeLabel: "取消",
                    onClose: cancelAndDismiss
                )

                ScrollView {
                    VStack(alignment: .leading, spacing: RemoteTheme.sectionSpacing) {
                        localPairingSection

                        if hasImportedConnection {
                            importedConnectionSection
                        } else {
                            crossNetworkSection
                        }

                        if let errorMessage {
                            VStack(alignment: .leading, spacing: 10) {
                                RemoteInlineNotice(
                                    title: "连接失败",
                                    message: errorMessage,
                                    icon: "exclamationmark.triangle.fill",
                                    tone: .danger
                                )
                                .accessibilityAddTraits(.isStaticText)

                                if importedIsSameWiFi {
                                    Button(action: openAppSettings) {
                                        Label("检查 iPhone 网络权限", systemImage: "gear")
                                    }
                                    .buttonStyle(RemoteActionButtonStyle(
                                        kind: .secondary,
                                        fillsWidth: false,
                                        compact: true
                                    ))
                                }
                            }
                        }

                        securityNote
                    }
                    .padding(.horizontal, RemoteTheme.pagePadding)
                    .padding(.top, 20)
                    .padding(.bottom, 28)
                }
                .scrollDismissesKeyboard(.interactively)
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    if hasConnectionInput {
                        connectDock
                    }
                }
            }
            .background(RemoteTheme.canvas.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            .interactiveDismissDisabled(isChecking)
            .sheet(isPresented: $showsScanner) {
                RemoteScannerSheet { value in
                    UISelectionFeedbackGenerator().selectionChanged()
                    showsScanner = false
                    address = value
                    hasImportedConnection = true
                    showsCrossNetworkEntry = false
                    errorMessage = nil
                    focusedField = nil
                    connect(addressOverride: value)
                }
                .presentationBackground(.black)
            }
            .sheet(isPresented: $showsTailscaleGuide) {
                TailscaleSetupGuideView()
                    .presentationDetents([.large])
                    .presentationDragIndicator(.hidden)
                    .presentationBackground(RemoteTheme.canvas)
            }
            .onAppear {
                if let connection = hostStore.consumePendingImportedConnection() {
                    let importedAddress = connection.importedURL.absoluteString
                    address = importedAddress
                    hasImportedConnection = true
                    connect(addressOverride: importedAddress)
                } else if autoStartsScanner, scannerIsAvailable, !didAutoStartScanner {
                    didAutoStartScanner = true
                    showsScanner = true
                }
            }
            .onDisappear {
                verificationGeneration += 1
                verificationTask?.cancel()
                verificationTask = nil
            }
            .onChange(of: errorMessage) { _, message in
                guard let message, !message.isEmpty else { return }
                UIAccessibility.post(
                    notification: .announcement,
                    argument: remoteLocalizedFormat("连接失败，%@", message)
                )
            }
            .onChange(of: scenePhase) { _, phase in
                guard phase == .active else { return }
                scannerAvailabilityRevision += 1
                if autoStartsScanner,
                   scannerIsAvailable,
                   !didAutoStartScanner,
                   !hasImportedConnection,
                   !showsScanner {
                    didAutoStartScanner = true
                    showsScanner = true
                }
            }
        }
    }

    private var localPairingSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            RemoteSectionHeader(title: "同一 Wi-Fi", detail: "推荐")

            if scannerIsAvailable {
                Button {
                    focusedField = nil
                    showsScanner = true
                } label: {
                    connectionGuideContent(
                        title: hasImportedConnection ? "重新扫描二维码" : "扫描 Desktop 二维码",
                        detail: "在 Mac 打开手机 Remote，点“连接 iPhone”，再选择“开始本地配对”。",
                        showsDisclosure: true
                    )
                }
                .buttonStyle(RemotePressableRowButtonStyle(cornerRadius: 16))
                .remoteSurface(cornerRadius: 16, elevated: !hasImportedConnection)
                .accessibilityHint("打开相机扫描，iPhone 不需要安装 Tailscale")
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    connectionGuideContent(
                        title: "这台设备无法使用相机扫码",
                        detail: "同一 Wi-Fi 配对必须扫描 Desktop 二维码。你仍可以在下方配置跨网络 HTTPS。",
                        showsDisclosure: false
                    )
                    .remoteSurface(cornerRadius: 16)

                    if DataScannerViewController.isSupported {
                        HStack(spacing: 8) {
                            Button(action: retryScannerAvailability) {
                                Label("重新检查", systemImage: "arrow.clockwise")
                            }
                            .buttonStyle(RemoteActionButtonStyle(
                                kind: .secondary,
                                fillsWidth: false,
                                compact: true
                            ))

                            Button(action: openAppSettings) {
                                Label("检查相机权限", systemImage: "gear")
                            }
                            .buttonStyle(RemoteActionButtonStyle(
                                kind: .secondary,
                                fillsWidth: false,
                                compact: true
                            ))
                        }
                    }
                }
            }

            if !hasImportedConnection || importedIsSameWiFi {
                Label("iPhone 无需安装或登录 Tailscale", systemImage: "checkmark.circle.fill")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(RemoteTheme.success)
                    .padding(.horizontal, 2)
                    .accessibilityElement(children: .combine)
            }
        }
    }

    private var importedConnectionSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            RemoteSectionHeader(title: "配对结果")

            RemoteInlineNotice(
                title: isChecking ? "正在验证电脑" : "二维码已读取",
                message: isChecking
                    ? "正在确认这是可用的 DSH Desktop，并保存此连接。"
                    : "自动验证没有完成。你可以重新扫描，或在修复网络后重新验证。",
                icon: isChecking ? "arrow.trianglehead.2.clockwise.rotate.90" : "qrcode.viewfinder",
                tone: isChecking ? .info : .warning
            )
            .accessibilityAddTraits(.isStaticText)

            importedEndpointSummary
        }
    }

    private var importedEndpointSummary: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: importedIsSameWiFi ? "wifi" : "network")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(RemoteTheme.accent)
                .frame(width: 38, height: 38)
                .background(
                    RemoteTheme.accent.opacity(0.10),
                    in: RoundedRectangle(cornerRadius: 11)
                )
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text(importedHost?.transportLabel ?? remoteLocalized("Remote 连接"))
                    .font(.subheadline.weight(.semibold))
                Text(importedHost?.address ?? "等待验证")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 6)
            if isChecking {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityHidden(true)
            } else {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(RemoteTheme.warning)
                    .accessibilityHidden(true)
            }
        }
        .padding(13)
        .remoteSurface(cornerRadius: 14)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            remoteLocalizedFormat("已读取 %@ 连接", importedHost?.transportLabel ?? "Remote")
        )
        .accessibilityValue(importedHost?.address ?? "等待验证")
    }

    private var crossNetworkSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            RemoteSectionHeader(title: "不在同一 Wi-Fi？", detail: "可选")

            Button {
                focusedField = nil
                withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) {
                    showsCrossNetworkEntry.toggle()
                }
            } label: {
                crossNetworkGuideContent
            }
            .buttonStyle(RemotePressableRowButtonStyle(cornerRadius: 14))
            .remoteSurface(cornerRadius: 14)
            .accessibilityLabel(showsCrossNetworkEntry ? "收起跨网络连接" : "配置跨网络连接")
            .accessibilityHint("使用 Tailscale 或你自己管理的 HTTPS 地址")

            if showsCrossNetworkEntry {
                VStack(alignment: .leading, spacing: 10) {
                    RemoteInlineNotice(
                        title: "跨网络方式",
                        message: "在 Desktop 按指南开启跨网络连接，再用 Remote 扫描二维码。Desktop 会自动配置 Tailscale Serve，不需要终端命令。",
                        icon: "point.3.connected.trianglepath.dotted",
                        tone: .info
                    )
                    Button {
                        focusedField = nil
                        showsTailscaleGuide = true
                    } label: {
                        Label("查看 3 分钟 Tailscale 教程", systemImage: "book.pages")
                    }
                    .buttonStyle(RemoteActionButtonStyle(kind: .secondary))
                    .accessibilityHint("查看 Mac、iPhone、MagicDNS、HTTPS 和蜂窝网络验收步骤")
                    nameField
                    addressField
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    private var crossNetworkGuideContent: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        crossNetworkIcon
                        Spacer(minLength: 8)
                        crossNetworkDisclosure
                    }
                    crossNetworkCopy
                }
            } else {
                HStack(alignment: .center, spacing: 13) {
                    crossNetworkIcon
                    crossNetworkCopy
                    Spacer(minLength: 4)
                    crossNetworkDisclosure
                }
            }
        }
        .padding(14)
        .frame(minHeight: 68)
        .contentShape(Rectangle())
    }

    private var crossNetworkIcon: some View {
        Image(systemName: "network")
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(.secondary)
            .frame(width: 40, height: 40)
            .background(RemoteTheme.raisedSurface, in: RoundedRectangle(cornerRadius: 11))
            .accessibilityHidden(true)
    }

    private var crossNetworkCopy: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Tailscale 或自有 HTTPS")
                .font(.subheadline.weight(.semibold))
            Text("离开家庭或办公室网络时使用")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var crossNetworkDisclosure: some View {
        Image(systemName: "chevron.down")
            .font(.caption.weight(.bold))
            .foregroundStyle(.tertiary)
            .rotationEffect(.degrees(showsCrossNetworkEntry ? 180 : 0))
            .accessibilityHidden(true)
    }

    private func connectionGuideContent(
        title: String,
        detail: String,
        showsDisclosure: Bool
    ) -> some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        connectionGuideIcon
                        Spacer(minLength: 8)
                        if showsDisclosure { connectionGuideDisclosure }
                    }
                    connectionGuideCopy(title: title, detail: detail)
                }
            } else {
                HStack(alignment: .center, spacing: 13) {
                    connectionGuideIcon
                    connectionGuideCopy(title: title, detail: detail)
                    Spacer(minLength: 4)
                    if showsDisclosure { connectionGuideDisclosure }
                }
            }
        }
        .padding(14)
        .frame(minHeight: 72)
        .contentShape(Rectangle())
    }

    private var connectionGuideIcon: some View {
        Image(systemName: "qrcode.viewfinder")
            .font(.system(size: 19, weight: .semibold))
            .foregroundStyle(RemoteTheme.accent)
            .frame(width: 42, height: 42)
            .background(RemoteTheme.accent.opacity(0.10), in: RoundedRectangle(cornerRadius: 12))
            .accessibilityHidden(true)
    }

    private var connectionGuideDisclosure: some View {
        Image(systemName: "arrow.right")
            .font(.caption.weight(.bold))
            .foregroundStyle(.tertiary)
            .accessibilityHidden(true)
    }

    private func connectionGuideCopy(title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(remoteLocalized(title))
                .font(.body.weight(.semibold))
            Text(remoteLocalized(detail))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineSpacing(2)
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private var nameField: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text("显示名称")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("可选")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            TextField("例如 MacBook Pro", text: $name)
                .submitLabel(.next)
                .focused($focusedField, equals: .name)
                .onSubmit { focusedField = .address }
                .remoteFieldSurface(focused: focusedField == .name)
        }
    }

    private var addressField: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("HTTPS 地址")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            TextField("https://电脑地址", text: $address)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(.URL)
                .textContentType(.URL)
                .submitLabel(.go)
                .focused($focusedField, equals: .address)
                .onSubmit {
                    if canConnect { connect() }
                }
                .remoteFieldSurface(
                    focused: focusedField == .address,
                    invalid: errorMessage != nil
                )

            Text("只接受 HTTPS。Tailscale Serve 地址通常以 .ts.net 结尾；同一 Wi-Fi 的 HTTP 地址不能手动输入。")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .padding(.horizontal, 2)
        }
    }

    private var securityNote: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "lock.shield")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(RemoteTheme.success)
                .frame(width: 22)
            Text(hasImportedConnection && importedIsSameWiFi
                 ? "局域网配对凭据只保存在这台 iPhone。仅在你信任的家庭或办公 Wi-Fi 使用；公共网络请改用 Tailscale HTTPS。"
                 : "连接信息只保存在这台 iPhone；App 不保存 DeepSeek API Key、项目文件或 Tailscale 登录凭据。")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineSpacing(2)
        }
        .padding(.horizontal, 2)
    }

    private var connectDock: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(RemoteTheme.hairline)
                .frame(height: 0.5)
            Button {
                connect()
            } label: {
                HStack(spacing: 8) {
                    if isChecking {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Image(systemName: "arrow.trianglehead.2.clockwise.rotate.90")
                    }
                    Text(isChecking ? "正在验证电脑…" : (hasImportedConnection ? "重新验证" : "验证并保存"))
                }
            }
            .buttonStyle(RemoteActionButtonStyle(kind: .primary))
            .disabled(!canConnect)
            .padding(.horizontal, RemoteTheme.pagePadding)
            .padding(.top, 12)
            .padding(.bottom, 8)
        }
        .background(RemoteTheme.canvas)
    }

    private var scannerIsAvailable: Bool {
        _ = scannerAvailabilityRevision
        return DataScannerViewController.isSupported && DataScannerViewController.isAvailable
    }

    private func retryScannerAvailability() {
        scannerAvailabilityRevision += 1
        if scannerIsAvailable {
            showsScanner = true
        }
    }

    private var connectionSubtitle: String {
        if (isChecking || errorMessage != nil), importedHost != nil {
            let transport = remoteLocalized(importedIsSameWiFi ? "同一 Wi-Fi 配对" : "跨网络连接")
            return isChecking
                ? remoteLocalizedFormat("正在验证%@", transport)
                : remoteLocalizedFormat("%@尚未完成", transport)
        }
        guard hasImportedConnection else { return remoteLocalized("同一 Wi-Fi 扫码，无需 Tailscale") }
        return remoteLocalized(
            importedIsSameWiFi ? "同一 Wi-Fi 配对尚未完成" : "跨网络连接尚未完成"
        )
    }

    private func openAppSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    private var hasConnectionInput: Bool {
        !address.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var canConnect: Bool {
        !isChecking && hasConnectionInput
    }

    private var importedHost: RemoteHost? {
        guard let connection = try? RemoteEndpointValidator.connection(from: address) else { return nil }
        return RemoteHost(
            name: name,
            baseURL: connection.baseURL,
            accessToken: connection.accessToken
        )
    }

    private var importedIsSameWiFi: Bool {
        guard let importedHost else { return false }
        if case .sameWiFi = importedHost.transport { return true }
        return false
    }

    private func connect(addressOverride: String? = nil) {
        errorMessage = nil
        focusedField = nil

        let connection: RemoteConnectionDescriptor
        do {
            connection = try RemoteEndpointValidator.connection(from: addressOverride ?? address)
        } catch {
            errorMessage = error.localizedDescription
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            return
        }

        isChecking = true
        verificationTask?.cancel()
        verificationGeneration += 1
        let generation = verificationGeneration
        verificationTask = Task { @MainActor in
            do {
                try await RemoteConnectionVerifier.verify(connection)
                try Task.checkCancellation()
                guard generation == verificationGeneration else { return }
                hostStore.add(name: name, connection: connection)
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                isChecking = false
                verificationTask = nil
                dismiss()
                Task {
                    await RemoteNotificationManager.shared.requestAuthorizationIfNeeded()
                }
            } catch is CancellationError {
                guard generation == verificationGeneration else { return }
                isChecking = false
                verificationTask = nil
            } catch {
                guard generation == verificationGeneration, !Task.isCancelled else {
                    if generation != verificationGeneration { return }
                    isChecking = false
                    verificationTask = nil
                    return
                }
                errorMessage = connectionMessage(for: error, connection: connection)
                isChecking = false
                verificationTask = nil
                UINotificationFeedbackGenerator().notificationOccurred(.error)
            }
        }
    }

    private func cancelAndDismiss() {
        verificationGeneration += 1
        verificationTask?.cancel()
        verificationTask = nil
        isChecking = false
        dismiss()
    }

    private func connectionMessage(
        for error: Error,
        connection: RemoteConnectionDescriptor
    ) -> String {
        let localConnection = isSameWiFiConnection(connection)

        if let urlError = error as? URLError {
            switch urlError.code {
            case .cannotFindHost, .dnsLookupFailed:
                return remoteLocalized(localConnection
                    ? "找不到电脑。请确认 iPhone 和 Mac 仍在同一 Wi-Fi，并在 Desktop 重新显示局域网二维码。"
                    : "找不到电脑。请确认手机已连接 Tailnet，或检查 HTTPS 域名。")
            case .cannotConnectToHost, .timedOut, .networkConnectionLost:
                return remoteLocalized(localConnection
                    ? "无法连接电脑。请确认 Desktop 正在运行、“同一 Wi-Fi”入口仍已开启；网络变化后请重新扫码。"
                    : "无法连接电脑。请确认 Desktop 正在运行，且 Tailscale Serve 或 HTTPS 入口已开启。")
            case .notConnectedToInternet:
                return remoteLocalized(localConnection
                    ? "无法访问本地网络。请确认 Wi-Fi 已连接，并在 iPhone 设置中允许 DSH Remote 访问本地网络。"
                    : "当前没有可用网络，请联网后重试。")
            case .secureConnectionFailed, .serverCertificateUntrusted:
                return remoteLocalized("HTTPS 证书无效。请检查 Tailscale Serve 或你自己的 HTTPS 配置。")
            default:
                break
            }
        }
        return error.localizedDescription
    }

    private func isSameWiFiConnection(_ connection: RemoteConnectionDescriptor) -> Bool {
        let host = RemoteHost(
            name: "",
            baseURL: connection.baseURL,
            accessToken: connection.accessToken
        )
        if case .sameWiFi = host.transport { return true }
        return false
    }
}

struct TailscaleSetupGuideView: View {
    private struct GuideLink: Identifiable {
        let id: String
        let title: String
        let url: URL
    }

    private struct GuideStep: Identifiable {
        let id: Int
        let title: String
        let detail: String
        let links: [GuideLink]
    }

    private let steps: [GuideStep] = [
        GuideStep(
            id: 1,
            title: "在 Mac 安装并登录",
            detail: "安装 Tailscale，并用你的账号登录。Standalone 版本最适合普通 Mac 用户。",
            links: [GuideLink(
                id: "mac",
                title: "下载 Mac 版",
                url: URL(string: "https://tailscale.com/download/mac")!
            )]
        ),
        GuideStep(
            id: 2,
            title: "在 iPhone 登录同一账号",
            detail: "安装 Tailscale，允许 VPN 配置，并确认 Mac 与 iPhone 出现在同一个 Tailnet。",
            links: [GuideLink(
                id: "ios",
                title: "下载 iPhone 版",
                url: URL(string: "https://tailscale.com/download/ios")!
            )]
        ),
        GuideStep(
            id: 3,
            title: "完成 DNS 与 HTTPS 授权",
            detail: "回到 Desktop 查看检测结果；若提示缺少 MagicDNS 或 HTTPS，按按钮进入 Tailnet DNS 设置。启用证书会把设备 DNS 名称写入公开证书日志。",
            links: [GuideLink(
                id: "dns",
                title: "打开 Tailnet DNS 设置",
                url: URL(string: "https://login.tailscale.com/admin/dns")!
            )]
        ),
        GuideStep(
            id: 4,
            title: "在 Desktop 开启跨网络连接",
            detail: "Desktop 会自动配置 Tailscale Serve、Harness 地址和二维码，不需要复制或运行终端命令。",
            links: [GuideLink(
                id: "serve",
                title: "查看 Tailscale Serve 说明",
                url: URL(string: "https://tailscale.com/docs/features/tailscale-serve")!
            )]
        ),
        GuideStep(
            id: 5,
            title: "用蜂窝网络验收",
            detail: "在 Remote 扫描跨网络二维码，然后关闭 iPhone Wi-Fi，只保留蜂窝网络和 Tailscale，再打开会话并发送一条消息。",
            links: []
        ),
    ]

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                RemoteSheetHeader(
                    title: "Tailscale 设置",
                    subtitle: "约 3 分钟 · 同一 Wi-Fi 不需要 Tailscale"
                )

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 14) {
                        RemoteInlineNotice(
                            title: "Desktop 会自动完成 Serve",
                            message: "你只需要让 Mac 和 iPhone 加入同一个 Tailnet，并按 Desktop 提示完成 DNS 与 HTTPS 授权。",
                            icon: "wand.and.stars",
                            tone: .info
                        )

                        ForEach(steps) { step in
                            guideStep(step)
                        }

                        RemoteInlineNotice(
                            title: "不要使用 Funnel",
                            message: "DSH Remote 只使用 Tailnet 内可访问的 Tailscale Serve。Funnel 会把入口暴露到公网。",
                            icon: "exclamationmark.shield.fill",
                            tone: .warning
                        )

                        Text("DSH Remote 是独立开源项目，并非 Tailscale 官方产品。连接、账号与设备权限由你的 Tailnet 管理。")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.horizontal, 2)
                    }
                    .padding(.horizontal, RemoteTheme.pagePadding)
                    .padding(.top, 16)
                    .padding(.bottom, 32)
                }
            }
            .background(RemoteTheme.canvas.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
        }
    }

    private func guideStep(_ step: GuideStep) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(step.id)")
                .font(.caption.weight(.bold))
                .foregroundStyle(RemoteTheme.accent)
                .frame(width: 30, height: 30)
                .background(RemoteTheme.accent.opacity(0.10), in: RoundedRectangle(cornerRadius: 9))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 5) {
                Text(remoteLocalized(step.title))
                    .font(.body.weight(.semibold))
                Text(remoteLocalized(step.detail))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)

                if !step.links.isEmpty {
                    HStack(spacing: 8) {
                        ForEach(step.links) { link in
                            Link(destination: link.url) {
                                Label(remoteLocalized(link.title), systemImage: "arrow.up.right")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(RemoteTheme.accent)
                                    .padding(.horizontal, 10)
                                    .frame(minHeight: 34)
                                    .background(RemoteTheme.accent.opacity(0.09), in: RoundedRectangle(cornerRadius: 9))
                            }
                            .buttonStyle(RemotePressableRowButtonStyle(cornerRadius: 9))
                        }
                    }
                    .padding(.top, 3)
                }
            }
        }
        .padding(14)
        .remoteSurface(cornerRadius: 14)
        .accessibilityElement(children: .contain)
    }
}

private struct RemoteScannerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var cameraErrorMessage: String?
    @State private var validationMessage: String?
    @State private var scannerAttempt = 0

    let onResult: (String) -> Void

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let scannerFailure = cameraErrorMessage {
                VStack(spacing: 12) {
                    RemoteEmptyState(
                        icon: "camera.fill",
                        title: "无法启动相机",
                        message: "相机暂时不可用。可以重新尝试；如果已拒绝相机权限，请前往系统设置重新允许。",
                        action: { cameraErrorMessage = nil }
                    ) {
                        Label("重新尝试", systemImage: "arrow.clockwise")
                    }

                    Button(action: openAppSettings) {
                        Label("打开系统设置", systemImage: "gear")
                    }
                    .buttonStyle(RemoteActionButtonStyle(
                        kind: .secondary,
                        fillsWidth: false,
                        compact: true
                    ))
                }
                .foregroundStyle(.white)
                .accessibilityHint(scannerFailure)
            } else {
                QRCodeScannerView(
                    onResult: validateScanResult,
                    onError: { cameraErrorMessage = $0 }
                )
                .id(scannerAttempt)
                .ignoresSafeArea()

                scanReticle
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("扫描电脑二维码")
                        .font(.headline)
                        .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)
                    Text("对准 DSH Desktop 显示的二维码")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.68))
                        .lineLimit(dynamicTypeSize.isAccessibilitySize ? 3 : 1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
                .layoutPriority(1)
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .frame(width: 44, height: 44)
                        .background(.black.opacity(0.45), in: RoundedRectangle(cornerRadius: 13))
                }
                .buttonStyle(RemoteToolbarButtonStyle(tint: .white))
                .accessibilityLabel("取消扫描")
                .fixedSize()
                .layoutPriority(2)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(
                LinearGradient(colors: [.black.opacity(0.72), .clear], startPoint: .top, endPoint: .bottom)
            )
        }
    }

    private var scanReticle: some View {
        VStack(spacing: 18) {
            Spacer()
            RoundedRectangle(cornerRadius: 24)
                .stroke(RemoteTheme.accent, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .frame(width: 246, height: 246)
                .shadow(color: RemoteTheme.accent.opacity(0.45), radius: 12)
                .allowsHitTesting(false)

            if let validationMessage {
                VStack(spacing: 8) {
                    Text(remoteLocalized(validationMessage))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)

                    Button {
                        self.validationMessage = nil
                        scannerAttempt += 1
                    } label: {
                        Label("继续扫描", systemImage: "qrcode.viewfinder")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 14)
                            .frame(minHeight: 44)
                    }
                    .buttonStyle(RemotePressableRowButtonStyle(cornerRadius: 12))
                    .background(.white.opacity(0.14), in: RoundedRectangle(cornerRadius: 12))
                    .accessibilityHint("重新启动二维码识别")
                }
                .padding(14)
                .background(.black.opacity(0.72), in: RoundedRectangle(cornerRadius: 16))
                .padding(.horizontal, 24)
            } else {
                Text("扫码后自动验证并保存")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .frame(minHeight: 44)
                    .background(.black.opacity(0.5), in: Capsule())
                    .allowsHitTesting(false)
            }
            Spacer()
        }
    }

    private func validateScanResult(_ value: String) {
        DispatchQueue.main.async {
            do {
                _ = try RemoteEndpointValidator.connection(from: value)
                validationMessage = nil
                onResult(value)
            } catch {
                validationMessage = remoteLocalized("这不是 DSH Desktop 配对码，请扫描 Desktop 显示的二维码。")
                UINotificationFeedbackGenerator().notificationOccurred(.error)
                UIAccessibility.post(
                    notification: .announcement,
                    argument: validationMessage
                )
            }
        }
    }

    private func openAppSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}
