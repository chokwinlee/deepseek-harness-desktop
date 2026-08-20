<div align="center">
  <img src="build/icon.png" width="96" height="96" alt="DSH Desktop 图标">
  <h1>DSH Desktop</h1>
  <p><strong>官方 DeepSeek Harness 体验的轻量、自包含桌面宿主。</strong></p>
  <p>
    <a href="https://github.com/chokwinlee/deepseek-harness-desktop/releases/latest">下载</a>
    · <a href="#核心能力">核心能力</a>
    · <a href="#开发">开发</a>
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

![DSH Desktop](docs/images/readme-hero-zh-CN.png)

*Harness rc.8 的真实图片输入会话，同时展开 Token 与费用统计，模型通过 OpenRouter 使用 `google/gemini-2.5-flash-lite`。*

DSH Desktop 把官方 [DeepSeek Harness](https://github.com/deepseek-ai/deepseek-harness) Web UI 和运行时放进桌面窗口。当前构建使用 `@deepseek-ai/dsh@0.1.0-rc.8`，侧边栏会同时显示桌面版与内置 Harness 版本。应用会自动管理本机 Harness 进程，用户无需另外安装 Node.js，也不用手动启动 `dsh web`。

> [!IMPORTANT]
> 这是独立社区项目，与 DeepSeek AI 官方产品无关。DeepSeek Harness 仍处于开发者预览阶段，后续版本可能包含不兼容改动。

## 核心能力

- **多模态会话**　所选服务商与模型声明支持图片输入后，可以直接粘贴或附加图片，并沿用 Harness 的标准会话流程。图片消息会保留在会话历史中。
- **macOS 用量统计**　无需离开当前会话，即可查看今日与近七天 Token、估算费用、运行任务数和合计吞吐率。
- **内置版本明确**　侧边栏同时标明桌面版与内置 Harness 版本，例如 `DSH Desktop v0.2.1 · Harness rc.8`。
- **开箱即用**　应用内置固定版本的 Node.js sidecar、官方 Harness 运行时、原生模块和发行检查。Harness 只绑定到随机的 `127.0.0.1` 端口。

费用来自本地 Token 记录和可用的公开模型价格，只作为估算。无法匹配价格的模型会明确显示为未定价，不会被当作免费。

## 用量统计

标题栏会持续显示精简摘要。展开后可以查看输入、输出、缓存、费用和实时吞吐率。用量记录来自本地 Harness 会话日志，价格信息可能从公开模型目录获取。

## 下载

安装包发布在[最新 GitHub Release](https://github.com/chokwinlee/deepseek-harness-desktop/releases/latest)。

| 平台 | 架构 | 文件 |
| --- | --- | --- |
| macOS | Apple Silicon | `mac-arm64.dmg` |
| macOS | Intel | `mac-x64.dmg` |
| Windows 10/11 | x64 安装版 | `win-x64.exe` |
| Windows 10/11 | x64 便携版 | `win-x64.zip` |

Release 同时提供 ZIP 和 `SHA256SUMS.txt`。macOS 构建会启用 Hardened Runtime；没有配置 Developer ID 时使用 ad-hoc 签名。Windows 构建目前没有代码签名，因此系统可能显示安全确认。继续前请确认文件来自本仓库。

## 快速开始

1. 安装并打开 DSH Desktop。
2. 进入 **设置 → 模型**，配置模型服务商和 API Key。
3. 添加或选择工作区。
4. 新建 Harness 会话。
5. 所选模型支持图片输入时，粘贴或附加一张图片。

配置、工作区和会话与官方 CLI 使用相同的 `DSH_HOME`，默认位于 `~/.dsh`。

## 插件与恢复

在 macOS 打开 **设置 → 插件 → 安装与管理**。安装器接受 npm 包、`github:owner/repo`、公开 GitHub HTTPS 地址，也可以直接粘贴下面的完整命令。

```bash
dsh plugin --profile web add github:owner/repo
```

桌面端只解析受支持的命令结构，不会执行粘贴的 shell 文本。它使用内置 DSH 和 pnpm，只重启受监护的 Harness 进程，并验证新 profile 是否能稳定运行五秒；启动失败时会恢复变更前的插件事务文件。第三方插件会在本机运行代码，安装前请检查来源与发布者。

## 架构

```text
桌面宿主 → 仅回环地址的 dsh web → 官方 Harness UI / 运行时
    └──── 共用 DSH_HOME，保存设置、会话和插件
```

本项目不分叉或重新实现 Harness agent 运行时，只负责桌面打包、进程生命周期、导航边界、故障恢复、原生集成和发行验证。

## 开发

开发环境需要 Node.js 22.19 或更高版本。

```bash
git clone https://github.com/chokwinlee/deepseek-harness-desktop.git
cd deepseek-harness-desktop
npm ci
npm test
npm start
```

运行 `npm run build:mac` 构建 macOS Tauri 发行包，运行 `npm run dist` 构建 Windows Electron 发行包。涉及打包的变更还应通过[发行工作流](.github/workflows/release.yml)中的真实运行时检查。

## 项目

- 提交 Pull Request 前请阅读 [CONTRIBUTING.md](CONTRIBUTING.md)。
- 安全问题请按照 [SECURITY.md](SECURITY.md) 私下报告。
- 产品与界面决策遵循 [PRODUCT.md](PRODUCT.md)。
- 桌面宿主采用 MIT 许可证；Harness 与内置依赖保留各自许可证，详见 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)。
