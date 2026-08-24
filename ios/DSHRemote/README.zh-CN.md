# DSH Remote for iOS

这是 DSH Desktop 的独立开源 iPhone 控制端。它不连接本项目维护者提供的服务器，而是直接访问用户自己的电脑。iPhone 和 Mac 在同一个受信任 Wi-Fi 时，优先使用 Desktop 自带的认证局域网入口，不需要安装或登录 Tailscale；离开同一 Wi-Fi 后，再选择 Tailscale Tailnet 或自行管理的 HTTPS。

> [!IMPORTANT]
> 外部构建已经通过 Beta App Review，可通过[公开 TestFlight 链接](https://testflight.apple.com/join/7Ew6Yk9V)安装。App 尚未正式上架 App Store，GitHub Release 也不提供通用可安装 IPA。

## 当前进度

当前能力：

- 原生 SwiftUI 电脑、任务、对话、工具摘要和输入界面；
- 扫描 Desktop 的同一 Wi-Fi 配对二维码，或在跨网络场景扫描/手动输入 HTTPS 地址；二维码使用 `harnessremote://connect?url=...`（兼容 `dshremote://`）；
- 通过 `host.describe` 验证目标确实是 Harness，而不是只检查网页状态码；
- 本地保存多台电脑；
- 原生调用 `session.list`、`session.create`、`session.history`、`session.prompt` 与 `session.cancel`，可从项目列表选择归属并新建会话；
- 读取 rc.8 持久图片附件，在用户消息、模型消息和工具结果中原位展示，失败可重试；
- 从系统照片选择器或剪贴板添加图片，在手机端去除元数据、按 Host 限制压缩和预检后随提示词发送；
- 使用 `@` 搜索并插入当前项目文件或已有会话引用，文件路径与会话 mention 由电脑端权威解析；
- 浏览主会话派出的多层子代理，读取历史，并对可继续的子代理补充消息或停止运行；
- 只读展示当前 Goal、Plan 模式及对应的对话与轨迹事件；
- 任务执行中补充指令、停止任务、处理审批和结构化问题；
- WebSocket 事件流与定时刷新共同恢复运行状态、消息、完成通知和待确认提醒；
- 无网络、无模型调用的内置体验模式；
- macOS Desktop 设置中的一键开启/关闭 Remote；
- 精确的 `--trusted-host`、受监督的前台 `tailscale serve` 与退出清理；
- 受监督的局域网 Remote 代理，只开放原生客户端所需 API，使用高强度随机 bearer 凭据；正常重启和关闭再开启会继续信任已配对 iPhone，用户可在二维码页明确“重置配对”并撤销旧凭据；
- 本地二维码和 `harnessremote://` 深链配对，不经过项目方服务器。

原来的桌面网页 `WKWebView` 包装层已从 iOS target 移除。App 可从电脑已配置的模型中切换会话路由，但不暴露模型提供方/API Key 配置、插件安装、任意目录选择或原始终端；代码和模型调用继续在电脑上执行。

## 语言

App 会跟随 iOS 设置中为 DSH Remote 选择的语言。英文和简体中文已覆盖完整产品界面，包括设置、错误、通知、审批、模型路由、轨迹、图片、引用和多层子代理。项目名、文件路径、用户提示词以及电脑返回的模型内容属于用户内容，App 会保留原文，不自行翻译。

## 运行要求

- Xcode 16 或更高版本；
- iOS 17 或更高版本；
- 同一 Wi-Fi 时，手机不必安装 Tailscale，但必须在 Desktop 中单独开启“同一 Wi-Fi”并扫码；
- 跨网络时，推荐 iPhone 与电脑均安装 Tailscale 并登录同一个 Tailnet，或使用你自己管理的 HTTPS；
- 在 Desktop 的“设置 → 通用 → 手机 Remote”中选择需要的连接方式。同一 Wi-Fi 配对不要求配置 Tailnet HTTPS。

## 通过 TestFlight 安装

要求：

- iOS 17 或更高版本的 iPhone；
- Apple 的 [TestFlight App](https://apps.apple.com/app/testflight/id899247664)；
- 正在运行的当前 DSH Desktop 正式版。

步骤：

1. 打开 [DSH Remote 公开邀请链接](https://testflight.apple.com/join/7Ew6Yk9V)。
2. 选择“在 TestFlight 中查看”，接受邀请并安装内测版。
3. 打开 DSH Remote，与当前 DSH Desktop 正式版完成配对。

公开组最多接受 10,000 名测试者。每个上传构建最长可测试 90 天。

## 使用 Xcode 从源码安装

1. 在 **Xcode → Settings → Accounts** 登录 Apple Account。
2. 用 Xcode 打开 `ios/DSHRemote/DSHRemote.xcodeproj`。
3. 选择 `DSHRemote` target，在 **Signing & Capabilities** 选择自己的 Team。
4. 如果自动签名提示 Bundle Identifier 不可用，把 `com.chokwinlee.dshremote` 改成自己控制的唯一标识。
5. 连接 iPhone，选择它作为运行设备，然后执行 **Product → Run**。
6. 按 Xcode 或 iOS 提示完成 Developer Mode 与设备信任。

免费 Xcode Personal Team 可用于个人真机测试，但需要定期重新签名。不从源码构建的测试者应使用 TestFlight 安装。

在 Xcode 中打开 `DSHRemote.xcodeproj`，选择开发团队和 iPhone 后运行。首次本地配对时，在 Desktop 打开“设置 → 通用 → 手机 Remote → 连接 iPhone → 开始本地配对”，再在 iOS App 扫描二维码。扫码后 App 会立即验证电脑并保存连接，不需要再点一次确认；验证失败时会返回添加页显示原因，可重新扫码或重试。局域网 HTTP 地址不能手输，必须扫码导入访问凭据。

跨网络时，可扫描 Desktop 的 Tailscale 二维码，或在添加页展开“Tailscale 或自有 HTTPS”后手动输入你管理的 HTTPS 地址。Desktop 和 iOS Remote 都内置状态感知的设置教程，完整步骤见 [`docs/TAILSCALE_REMOTE_SETUP.zh-CN.md`](../../docs/TAILSCALE_REMOTE_SETUP.zh-CN.md)。工程没有第三方 iOS 依赖。未连接电脑时可直接进入内置体验，离线查看项目、对话、轨迹与确认流程。

## 安全边界

- 公网地址必须使用 HTTPS；局域网 HTTP 只接受私有地址，并且必须带 Desktop 二维码生成的访问凭据。
- Harness 始终只监听 `127.0.0.1`；局域网代理只允许 Remote 使用的固定 API 路径，拒绝未认证和其他路径。
- 局域网代理以流式方式转发图片提示词，并设置 136 MiB 线格式上限；该上限覆盖 rc.8 默认 100 MiB 图片总量的 base64 开销，但不会开放任意上传接口。
- App 保存电脑名称、Remote URL，以及局域网配对所需的随机访问凭据；不保存 DeepSeek API Key、仓库或 Tailscale 登录凭据。
- Desktop 将局域网配对凭据原子写入 `$DSH_HOME/desktop-secrets/lan-remote-token`；Unix 目录与文件权限分别收紧为 `0700`、`0600`。凭据不会写入日志或发送给项目维护者。
- 局域网 HTTP 不提供链路加密，只应在你信任的家庭/办公 Wi-Fi 使用；酒店、咖啡店等不受信任网络应使用 Tailscale HTTPS。
- Tailscale 二维码不带项目方令牌；其设备准入由用户自己的 Tailnet 和访问控制策略决定。
- 不要使用 Tailscale Funnel。Funnel 会把服务暴露到公网，不属于这个产品方案。
- 这是独立项目，并非 DeepSeek AI 或 Tailscale 官方产品。隐私、支持与审核说明见 `docs/PRIVACY.md`、`docs/SUPPORT.md` 和 `docs/APP_REVIEW_NOTES.md`。
