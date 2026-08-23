# DSH Remote 的 Tailscale 跨网络设置

Tailscale 只用于离开家庭或办公室网络后的跨网络连接。如果手机与电脑处于同一个受信任 Wi-Fi，请优先使用 Desktop 的“同一 Wi-Fi”配对，不需要安装或登录 Tailscale。

DSH Remote 使用用户自己的 Tailnet，不经过项目方中继。代码、模型调用、API Key 和 Shell 始终留在电脑上。

## 开始前

准备一台运行 DSH Desktop 的 Mac，以及一台 iPhone 或 Android 手机。两台设备需要使用同一个 Tailscale 账号，或至少加入同一个允许互访的 Tailnet。

Desktop 会自动配置 Tailscale Serve、Harness 的受信任地址和配对二维码。不要手动复制 `tailscale serve` 命令，也不要使用 Tailscale Funnel。

## 五步完成设置

### 1. 在 Mac 安装并登录 Tailscale

从 [Tailscale 官方下载页](https://tailscale.com/download/mac) 安装 Mac 客户端，然后完成 VPN 配置并登录。Tailscale 官方建议大多数 Mac 用户使用 Standalone 版本。

安装完成后，确认 Tailscale 显示为已连接。

### 2. 在手机登录同一个 Tailnet

从 [iPhone 官方下载页](https://tailscale.com/download/ios) 或 [Android 官方下载页](https://tailscale.com/download/android) 安装 Tailscale，允许系统添加 VPN 配置，再使用与 Mac 相同的账号登录。

在 Tailscale 的设备列表中确认 Mac 和手机都在线。

### 3. 按 Desktop 提示完成 MagicDNS 与 HTTPS

打开 DSH Desktop 的“设置 → 通用 → 手机 Remote → 管理连接”，查看“跨网络连接”卡片。

Desktop 会按实际状态提示下一步：

- 未安装：先安装 Mac 版 Tailscale；
- 未连接：打开 Tailscale 并登录；
- MagicDNS 未开启：进入 [Tailnet DNS 设置](https://login.tailscale.com/admin/dns) 开启；
- HTTPS 未开启：点击 Desktop 的“设置 HTTPS”，按 Tailscale 页面完成授权；
- 准备完成：可以开启跨网络连接。

启用 Tailnet HTTPS 会为设备申请公开 CA 证书，设备名和 Tailnet DNS 名称会出现在公开证书日志中。它不会让设备公开可访问，但设备名不应包含敏感信息。

### 4. 在 Desktop 开启跨网络连接

点击“开启跨网络”。Desktop 会提示 Harness 需要重启，因为跨网络地址必须加入精确的受信任 Host。

确认后，Desktop 会自动：

1. 重启 Harness；
2. 将当前随机 loopback 端口映射到 Tailnet HTTPS `8443`；
3. 验证 Tailscale Serve 指向正确的 Harness；
4. 生成仅含 Tailnet HTTPS 地址的二维码。

完成后，在 DSH Remote 扫描该二维码。

### 5. 用蜂窝网络做真实验收

扫码成功后，关闭手机 Wi-Fi，只保留蜂窝网络和 Tailscale：

1. 打开 DSH Remote；
2. 进入电脑和任意会话；
3. 刷新项目列表；
4. 发送一条测试消息；
5. 确认流式回复或任务状态正常更新。

仍连接同一个 Wi-Fi 只能证明局域网路径可用，不能证明 Tailscale 跨网络配置成功。

## 安全说明

- 只使用 Tailscale Serve。不要使用 Funnel；Funnel 会把服务暴露到公网。
- Tailscale 地址没有 DSH 项目方凭据；设备准入由你的 Tailnet 与访问策略控制。
- 如果 Tailnet 包含其他成员，应使用 Tailscale Grants 限制谁可以访问这台电脑的 TCP `8443`。
- DSH Desktop 退出或关闭跨网络 Remote 后，会停止它管理的 Serve 入口。
- DSH Remote 不保存 Tailscale 登录凭据。

## 常见问题

### Desktop 显示 Tailscale 未安装

安装 Mac 客户端后完全退出并重新打开 DSH Desktop，再进入连接管理器刷新状态。

### Desktop 显示 Tailscale 未连接

打开 Tailscale，确认状态为 Connected，并检查 Mac 与手机是否属于同一个 Tailnet。

### Desktop 提示 MagicDNS 或 HTTPS 未开启

进入 Tailnet DNS 设置完成对应授权。新 Tailnet 通常默认启用 MagicDNS，但 HTTPS 仍需要单独确认。

### `8443` 已被占用

DSH Desktop 不会覆盖其他 Serve 配置。先检查现有 Tailscale Serve 用途，确认可以关闭后再释放 `8443`。

### Wi-Fi 可用，蜂窝网络不可用

依次确认：

1. 手机的 Tailscale VPN 仍处于开启状态；
2. Mac 在线且没有休眠；
3. 两台设备在同一个 Tailnet；
4. Tailnet Grants 或 ACL 没有阻止 TCP `8443`；
5. Desktop 的跨网络连接仍显示为已开启。

## 官方参考

- [安装 Tailscale on macOS](https://tailscale.com/docs/install/mac)
- [安装 Tailscale on iOS](https://tailscale.com/docs/install/ios)
- [安装 Tailscale on Android](https://tailscale.com/download/android)
- [MagicDNS](https://tailscale.com/docs/features/magicdns)
- [启用 HTTPS](https://tailscale.com/docs/how-to/set-up-https-certificates)
- [Tailscale Serve](https://tailscale.com/docs/features/tailscale-serve)
- [Tailscale Grants](https://tailscale.com/docs/features/access-control/grants)
