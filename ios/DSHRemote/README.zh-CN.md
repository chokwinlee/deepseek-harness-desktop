# Harness Remote for iOS

这是 Harness Desktop 的独立开源 iPhone 控制端。它不连接本项目维护者提供的服务器，而是直接访问用户自己的电脑。跨网络推荐使用 Tailscale Tailnet；在同一个受信任 Wi-Fi 中，也可使用 Desktop 自带的认证局域网入口。

## 当前进度

当前能力：

- 原生 SwiftUI 电脑、任务、对话、工具摘要和输入界面；
- 扫描 `harnessremote://connect?url=...`（兼容 `dshremote://`）二维码或手动输入 HTTPS 地址；
- 通过 `host.describe` 验证目标确实是 Harness，而不是只检查网页状态码；
- 本地保存多台电脑；
- 原生调用 `session.list`、`session.history`、`session.prompt` 与 `session.cancel`；
- 任务执行中补充指令、停止任务、处理审批和结构化问题；
- WebSocket 事件流与定时刷新共同恢复运行状态、消息、完成通知和待确认提醒；
- 无网络、无模型调用的内置审核演示模式；
- macOS Desktop 设置中的一键开启/关闭 Remote；
- 精确的 `--trusted-host`、受监督的前台 `tailscale serve` 与退出清理；
- 受监督的局域网 Remote 代理，只开放原生客户端所需 API，使用随机 256-bit bearer 凭据；
- 本地二维码和 `harnessremote://` 深链配对，不经过项目方服务器。

原来的桌面网页 `WKWebView` 包装层已从 iOS target 移除。App 可从电脑已配置的模型中切换会话路由，但不暴露模型提供方/API Key 配置、插件安装、任意目录选择或原始终端；代码和模型调用继续在电脑上执行。

## 运行要求

- Xcode 16 或更高版本；
- iOS 17 或更高版本；
- 跨网络时，推荐 iPhone 与电脑均安装 Tailscale 并登录同一个 Tailnet；
- 同一 Wi-Fi 时，手机不必安装 Tailscale，但必须在 Desktop 中单独开启“同一 Wi-Fi”并扫码；
- 在 Desktop 的“设置 → 通用 → 手机 Remote”中开启 Remote；首次使用需按提示授权 Tailnet HTTPS。

在 Xcode 中打开 `DSHRemote.xcodeproj`，选择开发团队和 iPhone 后运行。Desktop 会分别显示 Tailscale 和局域网二维码；也可以在 iOS App 中手动输入由你管理的 HTTPS 地址。局域网 HTTP 地址不能手输，必须扫码导入访问凭据。工程没有第三方 iOS 依赖。未连接电脑时可直接进入“审核演示”体验完整原生流程。

## 安全边界

- 公网地址必须使用 HTTPS；局域网 HTTP 只接受私有地址，并且必须带 Desktop 二维码生成的访问凭据。
- Harness 始终只监听 `127.0.0.1`；局域网代理只允许 Remote 使用的固定 API 路径，拒绝未认证和其他路径。
- App 保存电脑名称、Remote URL，以及局域网配对所需的随机访问凭据；不保存 DeepSeek API Key、仓库或 Tailscale 登录凭据。
- 局域网 HTTP 不提供链路加密，只应在你信任的家庭/办公 Wi-Fi 使用；酒店、咖啡店等不受信任网络应使用 Tailscale HTTPS。
- Tailscale 二维码不带项目方令牌；其设备准入由用户自己的 Tailnet 和访问控制策略决定。
- 不要使用 Tailscale Funnel。Funnel 会把服务暴露到公网，不属于这个产品方案。
- 这是独立项目，并非 DeepSeek AI 或 Tailscale 官方产品。隐私、支持与审核说明见 `docs/PRIVACY.md`、`docs/SUPPORT.md` 和 `docs/APP_REVIEW_NOTES.md`。
