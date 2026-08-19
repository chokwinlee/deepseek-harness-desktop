import SwiftUI
import VisionKit

struct AddHostView: View {
    private enum Field: Hashable {
        case name, address
    }

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var hostStore: RemoteHostStore

    @State private var name = ""
    @State private var address = ""
    @State private var showsScanner = false
    @State private var isChecking = false
    @State private var errorMessage: String?
    @FocusState private var focusedField: Field?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                RemoteSheetHeader(
                    title: "连接电脑",
                    subtitle: "扫码最快，也可以输入安全的 HTTPS 地址",
                    closeLabel: "取消"
                )

                ScrollView {
                    VStack(alignment: .leading, spacing: RemoteTheme.sectionSpacing) {
                        connectionGuide

                        VStack(alignment: .leading, spacing: 10) {
                            RemoteSectionHeader(title: "电脑信息")
                            nameField
                            addressField
                        }

                        if let errorMessage {
                            RemoteInlineNotice(
                                title: "连接失败",
                                message: errorMessage,
                                icon: "exclamationmark.triangle.fill",
                                tone: .danger
                            )
                            .accessibilityAddTraits(.isStaticText)
                        }

                        securityNote
                    }
                    .padding(.horizontal, RemoteTheme.pagePadding)
                    .padding(.top, 20)
                    .padding(.bottom, 28)
                }
                .scrollDismissesKeyboard(.interactively)
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    connectDock
                }
            }
            .background(RemoteTheme.canvas.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $showsScanner) {
                RemoteScannerSheet { value in
                    showsScanner = false
                    address = value
                    errorMessage = nil
                    focusedField = .name
                }
                .presentationBackground(.black)
            }
            .onAppear {
                if let connection = hostStore.consumePendingImportedConnection() {
                    address = connection.importedURL.absoluteString
                }
            }
        }
    }

    @ViewBuilder
    private var connectionGuide: some View {
        if scannerIsAvailable {
            Button {
                focusedField = nil
                showsScanner = true
            } label: {
                connectionGuideContent(
                    title: "推荐扫描 Desktop 二维码",
                    detail: "自动带入 Tailscale 地址，或同一 Wi-Fi 所需的配对凭据。",
                    showsDisclosure: true
                )
            }
            .buttonStyle(.plain)
            .remoteSurface(cornerRadius: 14)
            .accessibilityHint("打开相机扫描")
        } else {
            connectionGuideContent(
                title: "从 Desktop 复制 Remote 地址",
                detail: "这台设备暂时不能扫码，你仍可以在下方粘贴 HTTPS 地址。",
                showsDisclosure: false
            )
            .remoteSurface(cornerRadius: 14)
        }
    }

    private func connectionGuideContent(
        title: String,
        detail: String,
        showsDisclosure: Bool
    ) -> some View {
        HStack(alignment: .center, spacing: 13) {
            Image(systemName: "qrcode.viewfinder")
                .font(.system(size: 19, weight: .semibold))
                .foregroundStyle(RemoteTheme.accent)
                .frame(width: 42, height: 42)
                .background(RemoteTheme.accent.opacity(0.10), in: RoundedRectangle(cornerRadius: 12))

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.body.weight(.semibold))
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineSpacing(2)
            }
            Spacer(minLength: 4)
            if showsDisclosure {
                Image(systemName: "arrow.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(14)
        .frame(minHeight: 72)
        .contentShape(Rectangle())
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
            Text("Remote 地址")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            HStack(spacing: 4) {
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

                if scannerIsAvailable {
                    Rectangle()
                        .fill(RemoteTheme.hairline)
                        .frame(width: 0.5, height: 24)

                    Button {
                        focusedField = nil
                        showsScanner = true
                    } label: {
                        Image(systemName: "qrcode.viewfinder")
                            .font(.system(size: 18, weight: .medium))
                            .foregroundStyle(RemoteTheme.accent)
                            .frame(width: 44, height: 44)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("扫描二维码")
                }
            }
            .remoteFieldSurface(
                focused: focusedField == .address,
                invalid: errorMessage != nil
            )

            Text("手动输入仅接受 HTTPS；局域网连接必须扫码完成配对。")
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
            Text("连接信息只保存在这台 iPhone；首次连接后可允许任务完成和等待确认提醒。")
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
                    Text(isChecking ? "正在验证电脑…" : "连接并保存")
                }
            }
            .buttonStyle(RemoteActionButtonStyle(kind: .primary))
            .disabled(!canConnect)
            .padding(.horizontal, RemoteTheme.pagePadding)
            .padding(.top, 12)
            .padding(.bottom, 8)
        }
        .background(RemoteTheme.canvas.opacity(0.98))
    }

    private var scannerIsAvailable: Bool {
        DataScannerViewController.isSupported && DataScannerViewController.isAvailable
    }

    private var canConnect: Bool {
        !isChecking && !address.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func connect() {
        errorMessage = nil
        focusedField = nil

        let connection: RemoteConnectionDescriptor
        do {
            connection = try RemoteEndpointValidator.connection(from: address)
        } catch {
            errorMessage = error.localizedDescription
            return
        }

        isChecking = true
        Task {
            do {
                try await RemoteConnectionVerifier.verify(connection)
                hostStore.add(name: name, connection: connection)
                await RemoteNotificationManager.shared.requestAuthorizationIfNeeded()
                dismiss()
            } catch {
                errorMessage = connectionMessage(for: error)
                isChecking = false
            }
        }
    }

    private func connectionMessage(for error: Error) -> String {
        if let urlError = error as? URLError {
            switch urlError.code {
            case .cannotFindHost, .dnsLookupFailed:
                return "找不到电脑。使用 Tailscale 时，请确认手机已连接 Tailnet 且 MagicDNS 可用。"
            case .cannotConnectToHost, .timedOut, .networkConnectionLost:
                return "无法连接电脑。请确认 Desktop 正在运行且 Remote 已开启。"
            case .secureConnectionFailed, .serverCertificateUntrusted:
                return "HTTPS 证书无效。请检查 Tailscale Serve 或你自己的 HTTPS 配置。"
            default:
                break
            }
        }
        return error.localizedDescription
    }
}

private struct RemoteScannerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var errorMessage: String?

    let onResult: (String) -> Void

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let scannerFailure = errorMessage {
                RemoteEmptyState(
                    icon: "camera.fill",
                    title: "无法启动相机",
                    message: "相机暂时不可用。可以重新尝试，或关闭扫码后手动输入 Remote 地址。",
                    action: { errorMessage = nil }
                ) {
                    Label("重新尝试", systemImage: "arrow.clockwise")
                }
                .foregroundStyle(.white)
                .accessibilityHint(scannerFailure)
            } else {
                QRCodeScannerView(
                    onResult: onResult,
                    onError: { errorMessage = $0 }
                )
                .ignoresSafeArea()

                scanReticle
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("扫描电脑二维码")
                        .font(.headline)
                    Text("对准 Harness Desktop 显示的二维码")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.68))
                }
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .frame(width: 44, height: 44)
                        .background(.black.opacity(0.45), in: RoundedRectangle(cornerRadius: 13))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("取消扫描")
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
            Text("二维码会自动验证后保存")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .frame(minHeight: 44)
                .background(.black.opacity(0.5), in: Capsule())
            Spacer()
        }
        .allowsHitTesting(false)
    }
}
