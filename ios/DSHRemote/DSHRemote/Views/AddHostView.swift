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
                        .textContentType(.deviceName)

                    HStack {
                        TextField("https://电脑名.tailnet.ts.net:8443", text: $address)
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
                    Text("手机和电脑需要登录同一个 Tailscale 网络。地址由 Desktop 的 Remote 页面生成。")
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
                if let importedURL = hostStore.consumePendingImportedURL() {
                    address = importedURL.absoluteString
                }
            }
        }
    }

    private func connect() {
        errorMessage = nil

        let endpoint: URL
        do {
            endpoint = try RemoteEndpointValidator.normalizedURL(from: address)
        } catch {
            errorMessage = error.localizedDescription
            return
        }

        isChecking = true
        Task {
            do {
                try await RemoteConnectionVerifier.verify(endpoint)
                hostStore.add(name: name, baseURL: endpoint)
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
                return "找不到电脑。请确认手机已连接 Tailscale，并且 MagicDNS 可用。"
            case .cannotConnectToHost, .timedOut, .networkConnectionLost:
                return "无法连接电脑。请确认 Desktop 正在运行且 Remote 已开启。"
            case .secureConnectionFailed, .serverCertificateUntrusted:
                return "HTTPS 证书无效。请重新运行 Tailscale Serve 配置。"
            default:
                break
            }
        }
        return error.localizedDescription
    }
}
