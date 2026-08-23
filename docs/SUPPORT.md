# DSH Remote Support / 支持

[English](#english) · [简体中文](#简体中文)

DSH Remote is an independent open-source project. It is not an official
DeepSeek AI or Tailscale product.

## English

### Install or update the Android beta

Android testers must use the direct
[`v0.4.0-beta.1` pre-release](https://github.com/chokwinlee/deepseek-harness-desktop/releases/tag/v0.4.0-beta.1).
GitHub's `/releases/latest` route points to the latest stable release and may
not contain an Android APK.

Install both the Desktop build and
`DSH-Remote-Android-v0.4.0-beta.1.apk` from that same pre-release. Android 8.0
or later is required. Before installing, compare the APK's SHA-256 with its
entry in the release's `SHA256SUMS.txt`. A future GitHub beta signed by the same
project key can update this install directly; do not uninstall first if you
want to retain saved computers.

Full instructions: [Android beta guide](../android/README.md).

### Before reporting a connection issue

1. Confirm that the matching DSH Desktop beta is running, Harness has finished
   starting, and **Mobile Remote** is enabled.
2. Confirm that the phone's date and time are automatic. A large clock mismatch
   can break HTTPS certificate validation.
3. For same Wi-Fi, confirm both devices are still on the same trusted private
   network. Disable and re-enable the LAN endpoint, then scan its new QR code.
   Do not reuse a previous screenshot of the QR code.
4. Do not manually enter a local HTTP address. The Desktop-generated QR code
   contains the required random access credential.
5. On Android 17 or later, allow **Local network / Nearby devices** before a
   direct same-Wi-Fi connection. Camera access is also required if you scan
   rather than import a pairing code.
6. For Tailscale, confirm both devices are connected to the same Tailnet, the
   phone can resolve the computer's Tailnet name, and Desktop shows its private
   HTTPS endpoint as ready. Use Tailscale Serve, not Funnel.
7. If possible, turn off Wi-Fi and test with cellular data plus Tailscale. This
   distinguishes a working remote path from accidental LAN access.
8. In DSH Remote, pull down on the task list to retry. If credentials were
   regenerated, remove the saved computer and scan the current QR code.

Use same-Wi-Fi mode only on a network you trust because its authenticated HTTP
transport is not encrypted. Use Tailscale HTTPS on shared or untrusted networks.
The [Chinese Tailscale guide](./TAILSCALE_REMOTE_SETUP.zh-CN.md) includes a
step-by-step setup.

### Separate connection failures from app failures

- Open the offline Demo. If the same visual or interaction problem occurs
  there, report it as an app UI issue rather than a network issue.
- If Demo works but a saved computer does not, record whether the failing path
  is same Wi-Fi, Tailscale, or custom HTTPS.
- Notifications are local and best effort while the app process observes the
  computer. Android Doze, process death, and manufacturer background controls
  can stop them; this alone does not mean the active foreground connection is
  broken.

### Report a reproducible problem

Open a [GitHub bug report](https://github.com/chokwinlee/deepseek-harness-desktop/issues/new?template=bug-report.yml)
and include:

- DSH Remote version shown in **About and privacy**;
- phone platform, manufacturer/model, and OS version;
- computer operating system, DSH Desktop version, and displayed Harness version;
- connection type: Demo, trusted same Wi-Fi, Tailscale, or custom HTTPS;
- exact steps, expected result, actual result, and approximate failure time;
- visible error text and a redacted screenshot or short recording;
- whether Demo reproduces it and whether reconnecting or rescanning changes it.

If available, include only the shortest relevant, redacted `adb logcat` or
Desktop error excerpt. Never upload API keys, QR codes, bearer tokens, pairing
credentials, Tailnet names, private IP addresses, private paths, source code,
confidential prompts, or full unreviewed logs.

Copyable details block:

```text
Remote version:
Phone and OS:
Desktop OS and version:
Harness version:
Connection type:
Approximate failure time and time zone:
Steps to reproduce:
Expected result:
Actual result:
Visible error:
Does Demo reproduce it:
Does reconnecting or rescanning change it:
```

Privacy details are in the [DSH Remote privacy policy](./PRIVACY.md).

## 简体中文

DSH Remote 是独立开源项目，不是 DeepSeek AI 或 Tailscale 官方产品。

### 安装或升级 Android 内测版

Android 测试者必须打开 [`v0.4.0-beta.1` 预发布专属页面](https://github.com/chokwinlee/deepseek-harness-desktop/releases/tag/v0.4.0-beta.1)。GitHub 的 `/releases/latest` 指向最新稳定版，不一定包含 Android APK。

请从同一个预发布页面安装 Desktop 内测版与 `DSH-Remote-Android-v0.4.0-beta.1.apk`，Android 要求 8.0 或更高版本。安装前，把 APK 的 SHA-256 与 Release 中 `SHA256SUMS.txt` 的对应记录进行比较。未来使用同一项目密钥签名的 GitHub 内测版可以直接覆盖升级；希望保留已保存电脑时不要先卸载。

完整步骤见 [Android 中文内测指南](../android/README.zh-CN.md)。

### 报告连接问题前

1. 确认配套的 DSH Desktop 内测版正在运行，Harness 已经完成启动，并且“手机 Remote”已经开启。
2. 确认手机日期和时间使用自动设置。时钟相差过大会导致 HTTPS 证书校验失败。
3. 使用同一 Wi-Fi 时，确认两台设备仍在同一个受信任私有网络。关闭并重新开启局域网入口，然后扫描新二维码，不要继续使用以前保存的二维码截图。
4. 不要手动输入本地 HTTP 地址。Desktop 生成的二维码包含必需的随机访问凭据。
5. Android 17 或更高版本直连同一 Wi-Fi 前，需要允许“本地网络”或“附近的设备”。选择扫码时还需要相机权限。
6. 使用 Tailscale 时，确认两台设备连接同一个 Tailnet，手机能够解析电脑的 Tailnet 名称，并且 Desktop 显示私有 HTTPS 入口已经就绪。使用 Tailscale Serve，不要使用 Funnel。
7. 条件允许时，关闭 Wi-Fi，只保留蜂窝网络和 Tailscale 后再测试。这可以区分真正可用的跨网络路径与意外走局域网的情况。
8. 在 DSH Remote 任务列表下拉重试。如果凭据已经重新生成，请移除已保存电脑并扫描当前二维码。

同一 Wi-Fi 模式采用带认证但未加密的 HTTP，只能用于受信任网络；共享或不受信任网络请使用 Tailscale HTTPS。分步配置见 [Tailscale 中文教程](./TAILSCALE_REMOTE_SETUP.zh-CN.md)。

### 区分连接故障与 App 故障

- 打开离线 Demo。如果同样的界面或交互问题能在 Demo 复现，请按 App UI 问题报告，不要按网络问题报告。
- Demo 正常而已保存电脑失败时，请记录问题发生在同一 Wi-Fi、Tailscale 还是自管 HTTPS。
- 通知只在 App 进程仍观察电脑时提供本地尽力提醒。Android Doze、进程被杀与厂商后台控制都可能中断通知，这本身不代表前台连接已经失效。

### 提交可复现问题

创建 [GitHub Bug Report](https://github.com/chokwinlee/deepseek-harness-desktop/issues/new?template=bug-report.yml)，并提供：

- “关于与隐私”页面显示的 DSH Remote 版本；
- 手机平台、厂商、型号与系统版本；
- 电脑操作系统、DSH Desktop 版本和界面显示的 Harness 版本；
- 连接类型，包括 Demo、同一受信任 Wi-Fi、Tailscale 或自管 HTTPS；
- 具体步骤、预期结果、实际结果与故障大致发生时间；
- 可见错误文字，以及已经遮盖敏感信息的截图或短录屏；
- Demo 能否复现，重新连接或重新扫码后是否变化。

可以附上最短且已经脱敏的 `adb logcat` 或 Desktop 错误片段。不要上传 API Key、二维码、bearer token、配对凭据、Tailnet 名称、私有 IP、私有路径、源码、机密提示词或未经检查的完整日志。

可复制的信息模板：

```text
Remote 版本：
手机与系统：
Desktop 系统与版本：
Harness 版本：
连接类型：
故障时间与时区：
复现步骤：
预期结果：
实际结果：
可见错误：
Demo 是否复现：
重连或重新扫码后是否变化：
```

隐私边界见 [DSH Remote 隐私政策](./PRIVACY.md#简体中文)。
