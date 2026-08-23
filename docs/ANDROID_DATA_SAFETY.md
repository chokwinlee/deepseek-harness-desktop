# Android Data Safety working notes / Android 数据安全工作记录

[English](#english) · [简体中文](#简体中文)

These notes describe the `v0.4.0-beta.1` Android source and its GitHub APK. The
app is not yet distributed through Google Play. These notes prepare a future
Play Data Safety form; they are not final Play Console answers and do not change
the GitHub beta installation steps.

## English

### Project-operated collection

The project operates no account, relay, analytics, advertising, crash-reporting,
push, telemetry, or model gateway service for DSH Remote. The current source
does not transmit app data to the project maintainer. The Android app does use
Google ML Kit for on-device QR scanning; that SDK separately sends Google the
diagnostic and usage metrics described below.

### User-directed transfers

When the user explicitly connects a computer, the app exchanges the following
data directly with that user-owned or user-managed computer:

- computer address and pairing credential;
- project and session metadata;
- prompts, queue actions, approvals, and structured-question answers;
- selected images and requested message attachments;
- model selection, Goal/Plan, Activity, and subagent state.

Harness on the computer may send prompts and context to the model provider the
user configured there. That transfer is controlled by Desktop and the selected
provider, not by a DSH Remote service.

### On-device storage

- Saved computer names, addresses, and LAN bearer credentials are encrypted as
  one AES-256-GCM payload with a non-exportable Android Keystore key.
- Selected images are bounded, decoded, re-oriented, resized, and re-encoded;
  temporary attachment files remain in the app cache.
- System backup and device transfer exclude DSH Remote app data.
- Users can remove one computer or remove all saved computers from the app.

### Permissions

- `INTERNET`: connect directly to the selected computer.
- `ACCESS_LOCAL_NETWORK`: Android 17 runtime permission used only when the user
  connects directly to a computer on the local network.
- `CAMERA`: scan a Desktop pairing QR code. Camera frames and decoded QR
  contents are processed on-device and are not saved or uploaded.
- `POST_NOTIFICATIONS`: show optional local task updates while the app process
  is observing the computer.
- System Photo Picker: user-selected media access without broad photo-library
  permission.

### Google ML Kit QR scanning

The current app depends on bundled `com.google.mlkit:barcode-scanning:17.3.0`
and limits detection to QR codes. It does not enable ML Kit auto-zoom. Google
states that ML Kit processes feature inputs and outputs on-device and does not
send them to Google servers. Therefore, QR camera images and decoded pairing
contents are not sent to Google by ML Kit.

Google separately documents collection of the following SDK metrics for
diagnostics and usage analytics:

- device manufacturer/model, OS version/build, and available ML accelerators;
- package name and app version;
- a per-installation identifier not intended to identify a user or physical
  device uniquely;
- performance metrics, API configuration such as image format/resolution,
  input/output size, feature version, event type, and error codes.

Google states that these metrics are encrypted in transit with HTTPS and are
not transferred to third parties. See the official [ML Kit terms](https://developers.google.com/ml-kit/terms)
and [Android data-disclosure guide](https://developers.google.com/ml-kit/android-data-disclosure).
The app's public disclosure is in [`PRIVACY.md`](./PRIVACY.md#android-qr-scanner-and-google-ml-kit).

### Submission check

Before Play submission, inspect the final dependency graph and signed AAB,
recheck Google's documentation for the exact ML Kit version, publish the
privacy-policy URL, and answer the Play Console form against the then-current
definitions of "collected", "shared", optional processing, and ephemeral
processing. Do not claim that the Android build has no SDK metrics.

## 简体中文

本文记录 `v0.4.0-beta.1` Android 源码与 GitHub APK 的数据边界。App 当前尚未通过 Google Play 分发。本文用于准备未来的 Play Data Safety 表单，不是最终 Play Console 答案，也不改变 GitHub 内测版安装步骤。

### 项目方运营的数据收集

项目方不为 DSH Remote 运营账号、relay、分析、广告、崩溃上报、推送、遥测或模型网关服务，当前源码不会把 App 数据发送给项目维护者。Android App 使用 Google ML Kit 在设备端扫描二维码，该 SDK 会另外向 Google 发送下文所述的诊断与使用指标。

### 用户主动发起的传输

用户明确连接自己拥有或管理的电脑后，App 会与该电脑直接交换：

- 电脑地址与配对凭据；
- 项目和会话元数据；
- 提示词、队列操作、审批决定与结构化问题答案；
- 用户选择的图片与请求的消息附件；
- 模型选择、Goal、Plan、轨迹和子代理状态。

电脑上的 Harness 可能把提示词和上下文发送给用户配置的模型服务商。该传输由 Desktop 和用户选择的服务商控制，不经过 DSH Remote 服务。

### 设备端存储

- 已保存的电脑名称、地址和局域网 bearer 凭据作为一个整体，使用不可导出的 Android Keystore 密钥进行 AES-256-GCM 加密。
- 用户选择的图片会经过字节限制、解码、方向校正、缩放与重新编码，临时附件文件留在 App cache。
- 系统备份与设备迁移不包含 DSH Remote App 数据。
- 用户可以删除一台电脑，也可以在 App 中删除全部已保存电脑。

### 权限

- `INTERNET`　直接连接用户选择的电脑。
- `ACCESS_LOCAL_NETWORK`　Android 17 运行时权限，只在用户直接连接局域网电脑时使用。
- `CAMERA`　扫描 Desktop 配对二维码，画面与二维码解码内容只在设备端处理，不保存、不上传。
- `POST_NOTIFICATIONS`　在 App 进程仍观察电脑时显示可选的本地任务提醒。
- 系统照片选择器　只访问用户明确选择的媒体，不需要整个照片库权限。

### Google ML Kit 二维码扫描

当前 App 依赖内置的 `com.google.mlkit:barcode-scanning:17.3.0`，并且只检测二维码，没有启用 ML Kit 自动缩放。Google 说明 ML Kit 在设备端处理功能输入与输出，不会把它们发送到 Google 服务器，因此二维码相机图像与解码后的配对内容不会被 ML Kit 发送给 Google。

Google 另外说明，SDK 会收集以下指标用于诊断与使用情况分析：

- 设备厂商、型号、操作系统版本与 build，以及可用的机器学习加速器；
- 包名和 App 版本；
- 不用于唯一识别用户或实体设备的每次安装标识符；
- 性能指标、图像格式和分辨率等 API 配置、输入输出大小、功能版本、事件类型和错误代码。

Google 说明这些指标通过 HTTPS 加密传输，不会转移给第三方。详见官方 [ML Kit 条款](https://developers.google.com/ml-kit/terms?hl=zh-CN)与 [Android 数据披露指南](https://developers.google.com/ml-kit/android-data-disclosure?hl=zh-CN)。App 的公开披露见 [`PRIVACY.md`](./PRIVACY.md#android-二维码扫描与-google-ml-kit)。

### 提交前核对

提交 Google Play 前，必须检查最终依赖图和签名 AAB，针对实际 ML Kit 版本重新核对 Google 文档，发布隐私政策 URL，并按照当时 Play Console 对 collected、shared、可选处理和临时处理的定义填写表单。不能声称 Android 构建完全不发送 SDK 指标。
