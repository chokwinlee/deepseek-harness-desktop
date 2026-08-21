import SwiftUI
import UIKit

struct AboutRemoteView: View {
    @EnvironmentObject private var hostStore: RemoteHostStore
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var confirmsDeletion = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                RemoteSheetHeader(
                    title: "关于 DSH Remote",
                    subtitle: "隐私、连接方式与项目信息"
                )

                ScrollView {
                    VStack(alignment: .leading, spacing: RemoteTheme.sectionSpacing) {
                        aboutHero
                        privacySection
                        connectionSection
                        projectSection

                        if !hostStore.hosts.isEmpty {
                            dataSection
                        }
                    }
                    .padding(.horizontal, RemoteTheme.pagePadding)
                    .padding(.top, 20)
                    .padding(.bottom, 34)
                }
            }
            .background(RemoteTheme.canvas.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $confirmsDeletion) {
                RemoteDestructiveConfirmationSheet(
                    icon: "trash",
                    title: "删除所有电脑？",
                    message: "这会移除本机保存的名称、地址和局域网配对凭据，不会改动电脑上的任务。",
                    confirmTitle: "确认删除"
                ) {
                    hostStore.removeAll()
                    confirmsDeletion = false
                }
                .remoteDestructiveConfirmationPresentation(for: dynamicTypeSize)
            }
        }
    }

    private var aboutHero: some View {
        HStack(spacing: 15) {
            ZStack {
                RoundedRectangle(cornerRadius: 19)
                    .fill(RemoteTheme.accent.opacity(0.11))
                RoundedRectangle(cornerRadius: 19)
                    .stroke(RemoteTheme.accent.opacity(0.16), lineWidth: 1)
                Image(systemName: "iphone.and.arrow.forward")
                    .font(.system(size: 29, weight: .semibold))
                    .foregroundStyle(RemoteTheme.accent)
            }
            .frame(width: 66, height: 66)

            VStack(alignment: .leading, spacing: 4) {
                Text("DSH Remote")
                    .font(.title2.weight(.bold))
                Text("开源、独立的 Harness 手机控制端")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text("连接你的电脑，不经过项目方中继")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(15)
        .remoteSurface(cornerRadius: 16)
    }

    private var privacySection: some View {
        VStack(alignment: .leading, spacing: 9) {
            RemoteSectionHeader(title: "隐私")
            VStack(spacing: 0) {
                AboutInfoRow(
                    icon: "iphone",
                    title: "连接信息留在手机",
                    detail: "电脑地址和局域网配对凭据只保存在这台 iPhone"
                )
                divider
                AboutInfoRow(
                    icon: "arrow.left.arrow.right",
                    title: "任务直达电脑",
                    detail: "代码、提示词与任务内容不经过本项目的服务器"
                )
                divider
                AboutInfoRow(
                    icon: "server.rack",
                    title: "模型由电脑调用",
                    detail: "密钥和提供商设置仍由 DSH Desktop 管理"
                )
                divider
                Link(destination: privacyURL) {
                    AboutActionRow(icon: "hand.raised", title: "查看完整隐私政策")
                }
                .buttonStyle(.plain)
            }
            .remoteSurface(cornerRadius: 14)
        }
    }

    private var connectionSection: some View {
        VStack(alignment: .leading, spacing: 9) {
            RemoteSectionHeader(title: "连接与通知")
            VStack(spacing: 0) {
                AboutInfoRow(
                    icon: "point.3.connected.trianglepath.dotted",
                    title: "跨网络使用 Tailscale",
                    detail: "同一 Wi-Fi 可扫码配对；不要在酒店或咖啡店网络使用局域网 HTTP，也不要开启公开 Funnel"
                )
                divider
                Button {
                    UIApplication.shared.open(URL(string: UIApplication.openSettingsURLString)!)
                } label: {
                    AboutActionRow(icon: "bell", title: "打开系统通知设置")
                }
                .buttonStyle(.plain)
            }
            .remoteSurface(cornerRadius: 14)
        }
    }

    private var projectSection: some View {
        VStack(alignment: .leading, spacing: 9) {
            RemoteSectionHeader(title: "独立开源项目")
            VStack(spacing: 0) {
                Text("DSH Remote 并非 DeepSeek AI 或 Tailscale 的官方产品，也不受其背书。相关商标归各自权利人所有。")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineSpacing(3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                divider
                Link(destination: issuesURL) {
                    AboutActionRow(icon: "exclamationmark.bubble", title: "获取支持或报告问题")
                }
                .buttonStyle(.plain)
                divider
                Link(destination: sourceURL) {
                    AboutActionRow(icon: "chevron.left.forwardslash.chevron.right", title: "查看源代码与许可证")
                }
                .buttonStyle(.plain)
            }
            .remoteSurface(cornerRadius: 14)
        }
    }

    private var dataSection: some View {
        VStack(alignment: .leading, spacing: 9) {
            RemoteSectionHeader(title: "这台 iPhone 上的数据")
            Button {
                confirmsDeletion = true
            } label: {
                HStack(spacing: 11) {
                    Image(systemName: "trash")
                    VStack(alignment: .leading, spacing: 2) {
                        Text("删除所有已保存的电脑")
                            .font(.subheadline.weight(.semibold))
                        Text("不会改动电脑上的项目、会话或任务")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
            }
            .buttonStyle(RemoteActionButtonStyle(kind: .danger))
        }
    }

    private var divider: some View {
        Rectangle()
            .fill(RemoteTheme.hairline)
            .frame(height: 0.5)
            .padding(.leading, 50)
    }

    private var privacyURL: URL {
        URL(string: "https://github.com/chokwinlee/deepseek-harness-desktop/blob/main/docs/PRIVACY.md")!
    }

    private var issuesURL: URL {
        URL(string: "https://github.com/chokwinlee/deepseek-harness-desktop/issues")!
    }

    private var sourceURL: URL {
        URL(string: "https://github.com/chokwinlee/deepseek-harness-desktop")!
    }
}

private struct AboutInfoRow: View {
    let icon: String
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 11) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(RemoteTheme.accent)
                .frame(width: 24, height: 24)
                .background(RemoteTheme.accent.opacity(0.09), in: RoundedRectangle(cornerRadius: 7))
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineSpacing(2)
            }
            Spacer(minLength: 4)
        }
        .padding(13)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct AboutActionRow: View {
    let icon: String
    let title: String

    var body: some View {
        HStack(spacing: 11) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 24)
            Text(title)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.primary)
            Spacer(minLength: 8)
            Image(systemName: "arrow.up.right")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 13)
        .frame(minHeight: 48)
        .contentShape(Rectangle())
    }
}
