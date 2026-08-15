<div align="center">
  <img src="build/icon.png" width="112" height="112" alt="DeepSeek Harness Desktop 图标">
  <h1>DeepSeek Harness Desktop</h1>
  <p><strong>macOS 下载包不到 90 MB，完整内置 Harness 运行环境。</strong></p>
  <p>一个小巧的 DeepSeek Harness 非官方桌面端，支持 macOS 和 Windows。</p>
  <p>
    <a href="https://github.com/chokwinlee/deepseek-harness-desktop/releases/latest">下载</a>
    · <a href="#安装">安装</a>
    · <a href="#macos-为什么更小">macOS 为什么更小</a>
    · <a href="CONTRIBUTING.md">参与贡献</a>
  </p>
  <p>
    <a href="README.md">English</a>
    · <strong>简体中文</strong>
  </p>
  <p>
    <a href="https://github.com/chokwinlee/deepseek-harness-desktop/actions/workflows/ci.yml"><img src="https://github.com/chokwinlee/deepseek-harness-desktop/actions/workflows/ci.yml/badge.svg" alt="CI 状态"></a>
    <a href="https://github.com/chokwinlee/deepseek-harness-desktop/releases/latest"><img src="https://img.shields.io/github/v/release/chokwinlee/deepseek-harness-desktop" alt="最新版本"></a>
    <a href="LICENSE"><img src="https://img.shields.io/github/license/chokwinlee/deepseek-harness-desktop" alt="MIT 许可证"></a>
  </p>
</div>

![DeepSeek Harness Desktop：macOS 下载包不到 90 MB，内置完整 Harness 运行环境](docs/images/readme-hero-zh-CN.png)

DeepSeek Harness Desktop 把官方 [DeepSeek Harness](https://github.com/deepseek-ai/deepseek-harness) Web UI 和运行环境放进原生桌面窗口，并负责自动启动和关闭 Harness。用户无需额外安装 Node.js，也不用在终端执行命令。

macOS 版采用 Tauri 和系统自带的 WKWebView，无需随应用附带另一套浏览器内核。v0.1.2 公开发布的 Apple Silicon DMG 为 86.3 MB，Intel DMG 为 88.8 MB。两者都比本项目上一版 Electron DMG 小约 42%，同时保留完整的 Node sidecar 和 Harness 运行环境。

本项目没有分叉、修改或重新实现 Harness agent 运行时。仓库只负责 macOS Tauri 宿主、Windows Electron 宿主、打包配置、运行时验证和自动发布。

桌面宿主会跳过上游仅供内部测试的提示，再进入 Web UI。模型 API Key 设置仍然保留，因为它属于正常的功能配置。

> [!IMPORTANT]
> 这是一个独立的社区项目，与 DeepSeek AI 没有隶属或背书关系。DeepSeek Harness 目前仍处于开发者预览阶段，后续版本可能包含不兼容改动。

## macOS 为什么更小

小体积是这个项目最明确的优势之一。Tauri 让 macOS 应用直接复用系统已有的 WKWebView，无需打包 Chromium。发布脚本还会移除运行时用不到的 source map、类型声明、测试、文档和其他平台的原生二进制文件。

下面的数据来自 GitHub 已公开的 Release 资产，使用十进制 MB。表格对比相同架构、相同文件类型的两个连续版本。

| macOS 安装包 | v0.1.1 Electron | v0.1.2 Tauri | 减少 |
| --- | ---: | ---: | ---: |
| Apple Silicon DMG | 147.8 MB | **86.3 MB** | **41.6%** |
| Intel DMG | 152.6 MB | **88.8 MB** | **41.8%** |

ZIP 下载包的变化同样明显。Apple Silicon 版本减小 49.2%，Intel 版本减小 49.3%。原始文件和校验值可以在 [v0.1.1](https://github.com/chokwinlee/deepseek-harness-desktop/releases/tag/v0.1.1) 与 [v0.1.2](https://github.com/chokwinlee/deepseek-harness-desktop/releases/tag/v0.1.2) Release 中直接核对。

更小的下载包依然可以独立运行。安装包内含固定版本的 Node sidecar、官方 Harness 运行时、原生 PTY 和图像模块，并提供自动进程管理。CI 还会检查包体积，DMG 上限为 130 MB，ZIP 上限为 140 MB，防止后续版本在无人察觉时重新变大。

## 下载

安装包可以从 [最新 GitHub Release](https://github.com/chokwinlee/deepseek-harness-desktop/releases/latest) 获取。

| 平台 | 架构 | 推荐文件 |
| --- | --- | --- |
| macOS | Apple Silicon | `mac-arm64.dmg` |
| macOS | Intel | `mac-x64.dmg` |
| Windows 10/11 | x64 | `win-x64.exe` |
| Windows 10/11 | x64 便携版 | `win-x64.zip` |

每个版本也会提供 ZIP 压缩包和用于完整性验证的 `SHA256SUMS.txt`。

## 安装

### macOS

1. 根据 Mac 架构下载对应的 DMG。
2. 打开 DMG，把 **DeepSeek Harness Desktop** 拖进 **Applications**。
3. 从 Applications 启动应用。

macOS 发行版默认启用 Hardened Runtime 并使用 ad-hoc 签名。配置 Developer ID 和公证凭据后，同一套发布流程也会完成正式签名、公证和 stapling。

### Windows

下载并运行 x64 安装程序，也可以解压便携版 ZIP。当前 Windows 构建没有代码签名，SmartScreen 可能显示警告。继续安装前，请确认文件来自本仓库。

## 开始使用

1. 打开 **Settings → Models**。
2. 添加模型服务商和 API Key。
3. 添加或选择工作区。
4. 新建 Harness 会话。

桌面端会与官方 CLI 共用 `~/.dsh` 中的配置和会话数据。

## 工作方式

```text
DeepSeek Harness Desktop
├── 启动安装包内的 `dsh web` 运行时
├── 在 127.0.0.1 上选择一个随机端口
├── 通过 Harness API 确认固定版本的上游欢迎提示
├── macOS 使用 Tauri + WKWebView，Windows 使用 Electron
├── 桌面窗口只加载对应的本机回环地址
└── 应用退出时终止 Harness 子进程
```

桌面窗口只能访问本机 Harness 地址。外部 HTTP、HTTPS 和邮件链接会交给系统浏览器或邮件应用打开。macOS Tauri 宿主会把 Harness 放进单独的进程组，退出应用时一并停止运行时及其后代进程。

## 检查更新

桌面壳会在启动几秒后检查 GitHub Releases 是否有新版本。没有新版本时不显示任何更新界面；发现更新后，才会在 Harness 侧栏的 **Settings** 上方增加一个紧凑入口：

- **没有更新** —— 不显示桌面更新入口。
- **发现新版本** —— 入口显示新版本号和蓝色下载标记；打开后显示发布日期和发布说明，提供「下载更新」（在浏览器中打开发布页）和「忽略此版本」（隐藏该版本的入口）两个选项。
- **检查失败** —— 不在 Harness 侧栏增加错误提示；应用保持打开时仍会按计划再次检查。

版本入口会跟随 Harness 侧栏的展开与收起布局、当前语言、亮色或深色主题、键盘焦点及减少动画偏好。更新界面的层级低于 Harness 模态框，不会覆盖 Settings 等产品流程。

应用保持打开期间每 6 小时自动再检查一次。这是社区项目、构建为 ad-hoc 签名，因此更新需要从发布页手动下载安装，而不是在应用内直接替换。

## 开发

开发环境需要 Node.js 22.19 或更高版本。

```bash
git clone https://github.com/chokwinlee/deepseek-harness-desktop.git
cd deepseek-harness-desktop
npm ci
npm test
npm start
```

为当前平台构建未安装的应用。

```bash
npm run pack
npm run verify:packaged
```

运行 `npm run build:mac` 可以为当前架构构建 macOS Tauri 发行包，运行 `npm run dist` 可以构建 Windows Electron 发行包。应用目前固定使用 `@deepseek-ai/dsh@0.1.0-rc.6`。升级依赖后，需要对打包运行时执行冒烟测试，并在发布前真实启动一次桌面应用。

Developer ID 签名是可选项。如需启用，请配置以下 GitHub Actions secrets。

`APPLE_CERTIFICATE`、`APPLE_CERTIFICATE_PASSWORD`、`KEYCHAIN_PASSWORD`、`APPLE_ID`、`APPLE_PASSWORD` 和 `APPLE_TEAM_ID`。

缺少这些凭据时，发行版会使用 ad-hoc 签名，与早期未签名发行版的行为保持一致。

## 发布验证

每个带标签的版本都会在 GitHub 托管的 macOS Intel、macOS Apple Silicon 和 Windows x64 runner 上完成构建。流水线会执行以下检查。

1. 根据 `package-lock.json` 安装依赖。
2. 运行测试套件。
3. 在 macOS 构建 Tauri 产物，在 Windows 构建 Electron 产物。
4. 验证打包后的原生 PTY 和图像模块。
5. 启动打包运行时，检查真实 HTTP UI 和干净退出。
6. 检查各平台安装包的体积预算。
7. 验证 macOS 代码签名，并在凭据存在时检查公证。
8. 随 Release 发布 SHA-256 校验值。

## 参与贡献

欢迎提交可以复现的问题报告和范围明确的改进。提交 Pull Request 前请先阅读 [CONTRIBUTING.md](CONTRIBUTING.md)。安全问题请按照 [SECURITY.md](SECURITY.md) 中的方式反馈，不要创建公开 Issue。

## 许可证

桌面宿主采用 [MIT License](LICENSE)。DeepSeek Harness 和安装包内的第三方软件继续使用各自的许可证，详情见 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)。
