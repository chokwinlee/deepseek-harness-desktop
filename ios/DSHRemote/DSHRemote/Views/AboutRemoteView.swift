import SwiftUI
import UIKit

struct AboutRemoteView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var hostStore: RemoteHostStore
    @State private var confirmsDeletion = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(spacing: 12) {
                        Image(systemName: "iphone.and.arrow.forward")
                            .font(.system(size: 38, weight: .semibold))
                            .foregroundStyle(.indigo)
                            .frame(width: 72, height: 72)
                            .background(Color.indigo.opacity(0.12), in: RoundedRectangle(cornerRadius: 20))
                        Text("Harness Remote")
                            .font(.title2.weight(.bold))
                        Text("开源、独立的 Harness 手机控制端")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                }

                Section("隐私") {
                    Label("电脑地址与局域网配对凭据只保存在这台 iPhone", systemImage: "iphone")
                    Label("任务内容直接发送到你的电脑", systemImage: "arrow.left.arrow.right")
                    Label("模型请求由电脑上的提供商设置处理", systemImage: "server.rack")
                    Text("本项目维护者不运营中继服务，也不会收到你的代码、提示词、模型密钥或 Tailscale 登录信息。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Link(
                        "查看完整隐私政策",
                        destination: URL(string: "https://github.com/chokwinlee/deepseek-harness-desktop/blob/main/docs/PRIVACY.md")!
                    )
                }

                Section("连接与通知") {
                    Text("跨网络推荐使用你自己的 Tailscale。受信任的家庭或办公 Wi-Fi 可扫码使用局域网入口；酒店、咖啡店等网络不要使用局域网 HTTP。也不要使用公开 Funnel。")
                        .font(.subheadline)
                    Button("打开系统通知设置") {
                        UIApplication.shared.open(URL(string: UIApplication.openSettingsURLString)!)
                    }
                }

                Section("独立项目声明") {
                    Text("Harness Remote 是独立开源项目，并非 DeepSeek AI 或 Tailscale 的官方产品，也不受其背书。相关商标归各自权利人所有。")
                        .font(.subheadline)
                    Link(
                        "获取支持或报告问题",
                        destination: URL(string: "https://github.com/chokwinlee/deepseek-harness-desktop/issues")!
                    )
                    Link(
                        "查看开源代码与许可证",
                        destination: URL(string: "https://github.com/chokwinlee/deepseek-harness-desktop")!
                    )
                }

                if !hostStore.hosts.isEmpty {
                    Section {
                        Button("删除本机保存的所有电脑", role: .destructive) {
                            confirmsDeletion = true
                        }
                    } footer: {
                        Text("删除手机上保存的名称、地址和局域网配对凭据，不会改动电脑上的任务。")
                    }
                }
            }
            .navigationTitle("关于与隐私")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
            .confirmationDialog(
                "删除所有已保存的电脑？",
                isPresented: $confirmsDeletion,
                titleVisibility: .visible
            ) {
                Button("删除", role: .destructive) { hostStore.removeAll() }
                Button("取消", role: .cancel) {}
            }
        }
    }
}
