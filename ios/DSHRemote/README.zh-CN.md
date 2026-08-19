# DSH Remote for iOS

这是 DeepSeek Harness Desktop 的实验性 iPhone 控制端。它不连接本项目维护者提供的服务器，而是通过用户自己的 Tailscale Tailnet 访问电脑上的 Harness。

## 当前进度

已经完成的 MVP 能力：

- 原生 SwiftUI 主机列表与配对流程；
- 扫描 `dshremote://connect?url=...` 二维码或手动输入 `.ts.net` 地址；
- 连接前的 HTTPS、域名和可达性检查；
- 本地保存多台电脑；
- 使用同源受限的 `WKWebView` 复用 Harness 会话运行时，并提供手机优先的会话抽屉、单列消息流、底部输入区、详情底部面板和全屏设置页；
- 断线提示、重新连接和前后台恢复；
- 非 Harness 链接转交系统浏览器。
- macOS Desktop 设置中的一键开启/关闭 Remote；
- 精确的 `--trusted-host`、受监督的前台 `tailscale serve` 与退出清理；
- 本地二维码和 `dshremote://` 深链配对，不经过项目方服务器。

macOS + iOS 已完成真实 Tailnet HTTPS 连接验证；模拟器也已完成手机布局、Prompt、工具调用和流式响应验证。蜂窝网络、完整审批交互和 Windows Host 仍需按方案中的验收门槛逐项验证，因此当前仍标记为实验性 MVP。

## 运行要求

- Xcode 16 或更高版本；
- iOS 17 或更高版本；
- iPhone 与电脑均安装 Tailscale，并登录同一个 Tailnet；
- 在 Desktop 的“设置 → 通用 → 手机 Remote”中开启 Remote；首次使用需按提示授权 Tailnet HTTPS。

在 Xcode 中打开 `DSHRemote.xcodeproj`，选择开发团队和 iPhone 后运行。Desktop 会显示二维码；也可以在 iOS App 中手动输入 Desktop 显示的 `.ts.net:8443` 地址。工程没有第三方 iOS 依赖。

## 安全边界

- Release 构建只接受 HTTPS `.ts.net` 地址；Debug 构建额外允许 loopback，方便本机开发。
- App 只保存电脑名称和 Remote URL，不保存 DeepSeek API Key、仓库或 Tailscale 登录凭据。
- 二维码不是访问令牌；真正的网络准入由用户自己的 Tailnet 和访问控制策略决定。
- 不要使用 Tailscale Funnel。Funnel 会把服务暴露到公网，不属于这个产品方案。
