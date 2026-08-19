import SwiftUI
import VisionKit

struct AddHostView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var hostStore: RemoteHostStore

    @State private var name = ""
    @State private var address = ""
    @State private var showsScanner = false
    @State private var isChecking = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("例如 MacBook Pro", text: $name)

                    HStack {
                        TextField("https://电脑地址", text: $address)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .keyboardType(.URL)

                        if DataScannerViewController.isSupported,
                           DataScannerViewController.isAvailable {
                            Button {
                                showsScanner = true
                            } label: {
                                Image(systemName: "qrcode.viewfinder")
                                    .font(.title3)
                            }
                            .accessibilityLabel("扫描二维码")
                        }
                    }
                } header: {
                    Text("电脑")
                } footer: {
                    Text("推荐扫描 Desktop 生成的二维码。Tailscale 适合跨网络；同一 Wi-Fi 模式必须通过二维码导入配对凭据。")
                }

                if let errorMessage {
                    Section {
                        Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                    }
                }

                Section {
                    Button {
                        connect()
                    } label: {
                        HStack {
                            Spacer()
                            if isChecking {
                                ProgressView()
                                    .padding(.trailing, 6)
                            }
                            Text(isChecking ? "正在连接…" : "连接")
                            Spacer()
                        }
                    }
                    .disabled(isChecking || address.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .navigationTitle("添加电脑")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
            }
            .sheet(isPresented: $showsScanner) {
                QRCodeScannerView { value in
                    showsScanner = false
                    address = value
                    errorMessage = nil
                }
            }
            .onAppear {
                if let connection = hostStore.consumePendingImportedConnection() {
                    address = connection.importedURL.absoluteString
                }
            }
        }
    }

    private func connect() {
        errorMessage = nil

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
