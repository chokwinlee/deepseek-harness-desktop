<div align="center">
  <img src="build/icon.png" width="96" height="96" alt="DeepSeek Harness Desktop icon">
  <h1>DeepSeek Harness Desktop</h1>
  <p><strong>A compact, self-contained desktop host for the official DeepSeek Harness experience.</strong></p>
  <p>
    <a href="https://github.com/chokwinlee/deepseek-harness-desktop/releases/latest">Download</a>
    · <a href="#highlights">Highlights</a>
    · <a href="#development">Development</a>
    · <a href="CONTRIBUTING.md">Contributing</a>
  </p>
  <p>
    <strong>English</strong>
    · <a href="README.zh-CN.md">简体中文</a>
  </p>
  <p>
    <a href="https://github.com/chokwinlee/deepseek-harness-desktop/actions/workflows/ci.yml"><img src="https://github.com/chokwinlee/deepseek-harness-desktop/actions/workflows/ci.yml/badge.svg" alt="CI status"></a>
    <a href="https://github.com/chokwinlee/deepseek-harness-desktop/releases/latest"><img src="https://img.shields.io/github/v/release/chokwinlee/deepseek-harness-desktop" alt="Latest release"></a>
    <a href="LICENSE"><img src="https://img.shields.io/github/license/chokwinlee/deepseek-harness-desktop" alt="MIT License"></a>
  </p>
</div>

DeepSeek Harness Desktop runs the official [DeepSeek Harness](https://github.com/deepseek-ai/deepseek-harness) Web UI and runtime in a desktop window. It manages the local Harness process automatically, so users do not need to install Node.js or start `dsh web` themselves.

> [!IMPORTANT]
> This is an independent community project, not an official DeepSeek AI product. DeepSeek Harness is a developer preview and may introduce breaking changes.

## Highlights

- **Ready to run** — bundles a pinned Node.js sidecar, the official Harness runtime, native modules, and release-time runtime checks.
- **Native desktop integration** — uses Tauri and the system WKWebView on macOS, Electron on Windows, and binds Harness only to a random `127.0.0.1` port.
- **Usage at a glance on macOS** — shows today and seven-day token totals, estimated cost, active task count, and aggregate running throughput in the title bar.
- **Quiet UI polish** — the macOS title bar follows the active Harness theme, while both builds add default-on smooth streaming with a General Settings toggle.
- **Safer plugin workflow on macOS** — installs with bundled tools, verifies the restarted runtime, and rolls back to the last healthy profile after a failed change.
- **CLI-compatible** — shares `~/.dsh` with the official CLI and accepts documented install commands without executing pasted text through a shell.

Cost figures are estimates derived from local token logs and available public model prices. Unmatched models stay visibly unpriced rather than being counted as free.

## Download

Installers are published on the [latest GitHub Release](https://github.com/chokwinlee/deepseek-harness-desktop/releases/latest).

| Platform | Architecture | File |
| --- | --- | --- |
| macOS | Apple Silicon | `mac-arm64.dmg` |
| macOS | Intel | `mac-x64.dmg` |
| Windows 10/11 | x64 installer | `win-x64.exe` |
| Windows 10/11 | x64 portable | `win-x64.zip` |

Releases also include ZIP archives and `SHA256SUMS.txt`. macOS builds are hardened and ad-hoc signed unless Developer ID credentials are configured; Windows builds are currently unsigned. Your operating system may therefore show a security confirmation—verify that the download came from this repository before continuing.

## Quick start

1. Install and open DeepSeek Harness Desktop.
2. Open **Settings → Models** and configure a provider and API key.
3. Add or select a workspace.
4. Start a Harness session.

Configuration, workspaces, and sessions live in the same `DSH_HOME` used by the official CLI (`~/.dsh` by default).

## Plugins and recovery

On macOS, open **Settings → Plugins → Install & manage**. The installer accepts an npm package, `github:owner/repo`, a public GitHub HTTPS URL, or a full command such as:

```bash
dsh plugin --profile web add github:owner/repo
```

The command is parsed narrowly and never shell-executed. Desktop uses its bundled DSH and pnpm, restarts only the supervised Harness process, verifies the new profile for five seconds, and restores the previous plugin transaction files if startup fails. Third-party plugins run code on the local machine; inspect their source and publisher before installation.

## Architecture

```text
Desktop shell → loopback-only dsh web → official Harness UI/runtime
       └────── shared DSH_HOME for settings, sessions, and plugins
```

The project does not fork or reimplement the Harness agent runtime. The shell owns desktop packaging, process lifecycle, navigation boundaries, recovery, native integration, and release verification.

## Development

Node.js 22.19 or newer is required.

```bash
git clone https://github.com/chokwinlee/deepseek-harness-desktop.git
cd deepseek-harness-desktop
npm ci
npm test
npm start
```

Build the macOS Tauri release with `npm run build:mac`; build the Windows Electron release with `npm run dist`. Packaging changes should also pass the real packaged-runtime checks in [the release workflow](.github/workflows/release.yml).

## Project

- Read [CONTRIBUTING.md](CONTRIBUTING.md) before opening a pull request.
- Report vulnerabilities through the process in [SECURITY.md](SECURITY.md).
- Product and UI decisions follow [PRODUCT.md](PRODUCT.md).
- The desktop host is MIT licensed. Harness and bundled dependencies retain their own licenses; see [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
