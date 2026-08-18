# DSH Remote for iOS

这是 DeepSeek Harness Desktop 的实验性 iPhone 控制端。它不连接本项目维护者提供的服务器，而是通过用户自己的 Tailscale Tailnet 访问电脑上的 Harness。

## 当前进度

已经完成的客户端能力：

- 原生 SwiftUI 主机列表与配对流程；
- 扫描 `dshremote://connect?url=...` 二维码或手动输入 `.ts.net` 地址；
- 连接前的 HTTPS、域名和可达性检查；
- 本地保存多台电脑；
- 使用同源受限的 `WKWebView` 复用官方 Harness UI；
- 断线提示、重新连接和前后台恢复；
- 非 Harness 链接转交系统浏览器。

Desktop 端尚需实现“一键开启 Remote”：查询本机 Tailscale DNS 名、用 `--trusted-host` 重启 Harness、启动受监督的 `tailscale serve`，并显示配对二维码。在该功能接通前，这个 iOS 工程是可编译的客户端骨架，不应表述为已经完成端到端 Remote。

## 运行要求

- Xcode 16 或更高版本；
- iOS 17 或更高版本；
- iPhone 与电脑均安装 Tailscale，并登录同一个 Tailnet；
- 电脑端已按 [`docs/IOS_REMOTE_PLAN.zh-CN.md`](../../docs/IOS_REMOTE_PLAN.zh-CN.md) 暴露专用的 Tailnet HTTPS 地址。

在 Xcode 中打开 `DSHRemote.xcodeproj`，选择开发团队和 iPhone 后运行。工程没有第三方 iOS 依赖。

## 安全边界

- Release 构建只接受 HTTPS `.ts.net` 地址；Debug 构建额外允许 loopback，方便本机开发。
- App 只保存电脑名称和 Remote URL，不保存 DeepSeek API Key、仓库或 Tailscale 登录凭据。
- 二维码不是访问令牌；真正的网络准入由用户自己的 Tailnet 和访问控制策略决定。
- 不要使用 Tailscale Funnel。Funnel 会把服务暴露到公网，不属于这个产品方案。
