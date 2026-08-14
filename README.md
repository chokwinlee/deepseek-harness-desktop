<div align="center">
  <img src="build/icon.png" width="112" height="112" alt="DeepSeek Harness Desktop icon">
  <h1>DeepSeek Harness Desktop</h1>
  <p>An unofficial desktop host for DeepSeek Harness on macOS and Windows.</p>
  <p>
    <a href="https://github.com/chokwinlee/deepseek-harness-desktop/releases/latest">Download</a>
    · <a href="#installation">Installation</a>
    · <a href="CONTRIBUTING.md">Contributing</a>
  </p>
  <p>
    <a href="https://github.com/chokwinlee/deepseek-harness-desktop/actions/workflows/ci.yml"><img src="https://github.com/chokwinlee/deepseek-harness-desktop/actions/workflows/ci.yml/badge.svg" alt="CI status"></a>
    <a href="https://github.com/chokwinlee/deepseek-harness-desktop/releases/latest"><img src="https://img.shields.io/github/v/release/chokwinlee/deepseek-harness-desktop" alt="Latest release"></a>
    <a href="LICENSE"><img src="https://img.shields.io/github/license/chokwinlee/deepseek-harness-desktop" alt="MIT License"></a>
  </p>
</div>

DeepSeek Harness Desktop packages the official [DeepSeek Harness](https://github.com/deepseek-ai/deepseek-harness) Web UI and runtime in a native desktop window. It starts and stops Harness automatically, so no separate Node.js installation or terminal command is required.

The Harness agent runtime is not forked, modified, or reimplemented here. This repository contains only the Electron host, packaging configuration, runtime verification, and release automation.

The desktop host skips the upstream internal-testing announcement before loading the Web UI. The model API key step remains available because it is functional setup, not a promotional notice.

> [!IMPORTANT]
> This is an independent community project. It is not affiliated with or endorsed by DeepSeek AI. DeepSeek Harness is currently a developer preview and may introduce breaking changes.

## Download

Installers are available on the [latest GitHub Release](https://github.com/chokwinlee/deepseek-harness-desktop/releases/latest).

| Platform | Architecture | Recommended file |
| --- | --- | --- |
| macOS | Apple Silicon | `mac-arm64.dmg` |
| macOS | Intel | `mac-x64.dmg` |
| Windows 10/11 | x64 | `win-x64.exe` |
| Windows 10/11 | x64 portable | `win-x64.zip` |

Each release also includes ZIP archives and a `SHA256SUMS.txt` file for integrity verification.

## Installation

### macOS

1. Download the DMG for your Mac.
2. Drag **DeepSeek Harness Desktop** to **Applications** before opening it.
3. Launch the app from Applications.

The current macOS builds use an ad-hoc signature but are not notarized with an Apple Developer ID. If Gatekeeper blocks the first launch, right-click the app and choose **Open**, or allow it under **System Settings → Privacy & Security**. Download builds only from this repository's Releases page.

### Windows

Download and run the x64 installer, or extract the portable ZIP. Windows SmartScreen may warn about the current unsigned build; confirm that the file came from this repository before continuing.

## Getting started

1. Open **Settings → Models**.
2. Add your model provider and API key.
3. Add or select a workspace.
4. Start a new Harness session.

The desktop app uses the same `~/.dsh` configuration and session data as the official CLI.

## How it works

```text
DeepSeek Harness Desktop
├── launches the packaged `dsh web` runtime
├── binds it to a random port on 127.0.0.1
├── acknowledges the pinned upstream welcome notice through the Harness API
├── loads that exact loopback origin in a sandboxed Electron window
└── terminates the child process when the desktop app exits
```

The renderer has Node.js integration disabled and context isolation enabled. Navigation is restricted to the local Harness origin, external links open in the system browser, and renderer permission requests are denied by default. Startup logs redact common credential patterns before they are displayed in an error report.

## Development

Node.js 22.19 or newer is required.

```bash
git clone https://github.com/chokwinlee/deepseek-harness-desktop.git
cd deepseek-harness-desktop
npm ci
npm test
npm start
```

Build an unpacked application for the current platform:

```bash
npm run pack
npm run verify:packaged
```

Build distributable installers with `npm run dist`. The application currently pins `@deepseek-ai/dsh@0.1.0-rc.6`; dependency upgrades require a packaged-runtime smoke test and a real desktop launch before release.

## Release verification

Every tagged release is built on GitHub-hosted macOS Intel, macOS Apple Silicon, and Windows x64 runners. The workflow:

1. installs dependencies from `package-lock.json`;
2. runs the test suite;
3. builds the platform installer and archive;
4. verifies the complete packaged DeepSeek dependency set;
5. starts the packaged runtime and waits for a successful HTTP response;
6. enforces platform-specific installer size budgets;
7. verifies macOS bundle signatures; and
8. publishes SHA-256 checksums with the release assets.

## Contributing

Bug reports and focused improvements are welcome. Read [CONTRIBUTING.md](CONTRIBUTING.md) before opening a pull request. For security issues, follow [SECURITY.md](SECURITY.md) instead of opening a public issue.

## License

The desktop host is licensed under the [MIT License](LICENSE). DeepSeek Harness and bundled third-party software retain their respective licenses; see [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
