<div align="center">
  <img src="build/icon.png" width="96" height="96" alt="DSH Desktop icon">
  <h1>DSH Desktop</h1>
  <p><strong>A compact, self-contained DeepSeek Harness desktop host with native iPhone and Android Remote companions.</strong></p>
  <p>
    <a href="#download">Download</a>
    · <a href="#highlights">Highlights</a>
    · <a href="#iphone-remote-source-preview">iPhone Remote</a>
    · <a href="#android-remote-github-beta">Android Remote</a>
    · <a href="#development">Development</a>
    · <a href="CONTRIBUTING.md">Contributing</a>
  </p>
  <p>
    <strong>English</strong>
    · <a href="README.zh-CN.md">简体中文</a>
  </p>
  <p>
    <a href="https://github.com/chokwinlee/deepseek-harness-desktop/actions/workflows/ci.yml"><img src="https://github.com/chokwinlee/deepseek-harness-desktop/actions/workflows/ci.yml/badge.svg" alt="CI status"></a>
    <a href="https://github.com/chokwinlee/deepseek-harness-desktop/releases/latest"><img src="https://img.shields.io/github/v/release/chokwinlee/deepseek-harness-desktop" alt="Latest stable release"></a>
    <a href="LICENSE"><img src="https://img.shields.io/github/license/chokwinlee/deepseek-harness-desktop" alt="MIT License"></a>
  </p>
</div>

![DSH Desktop](docs/images/readme-hero-en.png)

*macOS downloads under 90 MB, with the complete Harness rc.8 runtime included.*

DSH Desktop runs the official [DeepSeek Harness](https://github.com/deepseek-ai/deepseek-harness) Web UI and runtime in a desktop window. The repository also contains DSH Remote native companions for continuing the computer's projects, sessions, and running tasks from iPhone and Android. This build is aligned with `@deepseek-ai/dsh@0.1.0-rc.8` and shows that bundled Harness version in the sidebar. The desktop app manages the local Harness process automatically, so users do not need to install Node.js or start `dsh web` themselves.

> [!IMPORTANT]
> This is an independent community project, not an official DeepSeek AI product. DeepSeek Harness is a developer preview and may introduce breaking changes.

## Highlights

- **Multimodal sessions** — paste or attach images and send them through the normal Harness conversation flow when the selected provider and model declare image input support. Image messages remain visible in session history.
- **Usage at a glance on macOS** — see today and seven-day token totals, estimated cost, active task count, and aggregate running throughput without leaving the current session.
- **Compact macOS package** — stays under 90 MB while bundling the complete Harness runtime, using Tauri and the system WKWebView instead of shipping Chromium.
- **Visible runtime alignment** — the sidebar identifies both the Desktop release and its bundled Harness version, such as `DSH Desktop v0.4.0-beta.1 · Harness rc.8`.
- **Ready to run** — includes everything needed to start Harness, with no separate Node.js installation or terminal command. The app starts and stops the local runtime automatically.
- **Native mobile Remote** — the SwiftUI iPhone client and Kotlin/Compose Android client pair on trusted Wi-Fi or the user's own Tailscale network, then browse projects, create sessions, steer tasks, handle approvals, send images, and follow subagents without moving execution off the computer.

Cost figures are estimates derived from local token logs and available public model prices. Unmatched models stay visibly unpriced rather than being counted as free.

## Multimodal and usage insights

![Multimodal session and usage insights](docs/images/readme-features-en.png)

*A real Harness rc.8 image-input session with live token and cost insights, using `google/gemini-2.5-flash-lite` through OpenRouter.*

The compact title-bar summary stays visible while you work. Open it for input, output, cache, cost, and live-throughput details. Usage is calculated locally from Harness session history, with estimated costs based on available public model prices.

## iPhone Remote (source preview)

> [!NOTE]
> DSH Remote is currently an **iOS source preview**. The first external TestFlight build has been submitted for Beta App Review, but no public link is available until Apple approves it. GitHub Releases do not contain an installable iOS app.

<p align="center">
  <img src="docs/images/remote-home-en.png" width="30%" alt="DSH Remote same-Wi-Fi pairing in English">
  <img src="docs/images/remote-projects-en.png" width="30%" alt="DSH Remote projects and running sessions in English">
  <img src="docs/images/remote-conversation-en.png" width="30%" alt="DSH Remote approval handling in English">
</p>
<p align="center"><sub>Same-Wi-Fi pairing · Projects and running sessions · Approval handling</sub></p>

DSH Remote is a native SwiftUI companion for a DSH Desktop computer you own or manage. It does not run an agent, repository, terminal, or model provider on the phone. Work continues on the computer; the iPhone is a narrow control surface.

The iOS source preview follows the device's app-language setting and includes complete English and Simplified Chinese product copy, including setup, errors, notifications, approvals, models, Activity, and subagent flows.

- **Same Wi-Fi (recommended):** Desktop exposes an opt-in, authenticated LAN endpoint on a trusted private network. No Tailscale account is required.
- **Away from the local network:** both devices join the user's own tailnet, and Desktop configures a private Tailscale Serve HTTPS entry. Do not use Funnel.
- **No project-operated relay:** code, prompts, model credentials, tool execution, and session history remain on the user's computer.

### Install before TestFlight

Developers can install the source preview on their own iPhone with Xcode:

1. Install Xcode 16 or later on a Mac and sign in under **Xcode → Settings → Accounts**.
2. Clone this repository and open `ios/DSHRemote/DSHRemote.xcodeproj`.
3. Select the `DSHRemote` target, choose your Team under **Signing & Capabilities**, and use a unique bundle identifier if automatic signing requests one.
4. Connect an iPhone running iOS 17 or later, select it as the run destination, and choose **Product → Run**.

A free Apple Account can use an Xcode Personal Team for personal on-device testing, but the app must be re-provisioned periodically. If you do not use Xcode, wait for the TestFlight link; downloading an unsigned or unrelated IPA from GitHub will not work.

### Pair and use Remote

1. Install and open the latest DSH Desktop build.
2. In Desktop, open **Settings → General → Mobile Remote → Connect phone**.
3. On the same trusted Wi-Fi, start local pairing and scan the QR code in DSH Remote.
4. For cellular or other remote networks, open the built-in Tailscale setup guide on Desktop or iPhone, enable anywhere access, and scan the HTTPS QR code.
5. Open a project, create or continue a session, and keep all execution on the computer.

See the [iOS source-preview guide](ios/DSHRemote/README.md), [Chinese Tailscale setup guide](docs/TAILSCALE_REMOTE_SETUP.zh-CN.md), [privacy policy](docs/PRIVACY.md), [support notes](docs/SUPPORT.md), and [App Review notes](docs/APP_REVIEW_NOTES.md).

## Android Remote (GitHub beta)

> [!IMPORTANT]
> [`v0.4.0-beta.1`](https://github.com/chokwinlee/deepseek-harness-desktop/releases/tag/v0.4.0-beta.1) is an installable **GitHub pre-release for testing**. It requires Android 8.0 or later and the matching DSH Desktop build from that same release. It is not yet available on Google Play.

<p align="center">
  <img src="docs/images/android-remote-home-en.png" width="42%" alt="DSH Remote Android onboarding in English">
  <img src="docs/images/android-remote-conversation-en.png" width="42%" alt="DSH Remote Android approval and conversation controls in English">
</p>
<p align="center"><sub>Local-first pairing and offline Demo · Conversation, queue, and approval control</sub></p>

Android uses the same local-first Remote v1 contract, QR format, Desktop LAN proxy, and Tailscale HTTPS flow as iOS. It includes encrypted multi-computer storage, projects and sessions, full conversation and Activity views, queue and steer controls, approvals and structured questions, images and references, models, Goal/Plan, nested subagents, local notifications, offline Demo, English, Simplified Chinese, dark appearance, and TalkBack semantics.

To test it:

1. Open the [`v0.4.0-beta.1` pre-release](https://github.com/chokwinlee/deepseek-harness-desktop/releases/tag/v0.4.0-beta.1) and install its Desktop package on the computer.
2. Download `DSH-Remote-Android-v0.4.0-beta.1.apk` on an Android 8.0+ device. If asked, temporarily allow **Install unknown apps** for the browser or file manager that opened it.
3. Compare the APK's SHA-256 with its entry in `SHA256SUMS.txt` from the same release.
4. Open the offline Demo, or in Desktop choose **Settings → General → Mobile Remote → Connect phone** and scan its QR code.

Use direct same-Wi-Fi mode only on a trusted private network: it is authenticated but not encrypted. Use private Tailscale Serve HTTPS for cellular, remote, or untrusted networks, and never use Funnel. Camera and notification permissions are optional. QR images stay on-device, while the bundled Google ML Kit scanner sends Google the diagnostic and usage metrics described in the [privacy policy](docs/PRIVACY.md#android-qr-scanner-and-google-ml-kit).

The computer must remain online with Desktop and Harness running. Local notifications are best effort, and physical-device coverage is still expanding during this beta. See the complete [Android beta install and test guide](android/README.md), [Simplified Chinese guide](android/README.zh-CN.md), [support guide](docs/SUPPORT.md), and [platform-neutral Remote contract](docs/REMOTE_PROTOCOL_V1.md).

## Download

Stable Desktop installers remain on the [latest stable GitHub Release](https://github.com/chokwinlee/deepseek-harness-desktop/releases/latest). GitHub's `/releases/latest` route does not select pre-releases, so Android testers must use the direct [`v0.4.0-beta.1` page](https://github.com/chokwinlee/deepseek-harness-desktop/releases/tag/v0.4.0-beta.1) and install the matching beta Desktop build from that page.

| Current GitHub beta | Architecture | File |
| --- | --- | --- |
| macOS | Apple Silicon | `DSH-Desktop-0.4.0-beta.1-mac-arm64.dmg` |
| macOS | Intel | `DSH-Desktop-0.4.0-beta.1-mac-x64.dmg` |
| Windows 10/11 | x64 installer | `DSH-Desktop-0.4.0-beta.1-win-x64.exe` |
| Windows 10/11 | x64 portable | `DSH-Desktop-0.4.0-beta.1-win-x64.zip` |
| Android 8.0+ | universal APK | `DSH-Remote-Android-v0.4.0-beta.1.apk` |

The pre-release also includes macOS ZIP archives and `SHA256SUMS.txt` for integrity verification. Installable iOS builds continue through TestFlight rather than GitHub assets.

## Desktop quick start

1. Install and open DSH Desktop.
2. Open **Settings → Models** and configure a provider and API key.
3. Add or select a workspace.
4. Start a Harness session.
5. Paste or attach an image when the selected model supports image input.

Configuration, workspaces, and sessions live in the same `DSH_HOME` used by the official CLI (`~/.dsh` by default).

## Plugins and recovery

On macOS, open **Settings → Plugins → Install & manage**. The installer accepts an npm package, `github:owner/repo`, a public GitHub HTTPS URL, or a full command such as:

```bash
dsh plugin --profile web add github:owner/repo
```

Desktop parses supported install commands without running pasted text through a shell, then checks that Harness restarts successfully. If startup fails, it restores the previous plugin configuration. Third-party plugins run code on the local machine, so review their source and publisher before installation.

## Architecture

```text
 iPhone Remote ── authenticated same-Wi-Fi / Tailnet HTTPS ──┐
Android Remote ── authenticated same-Wi-Fi / Tailnet HTTPS ──┤
                                                             ↓
Desktop shell ─────────────→ loopback-only dsh web → official Harness UI/runtime
       └─────────────────── shared DSH_HOME for settings, sessions, and plugins
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

Open `ios/DSHRemote/DSHRemote.xcodeproj` in Xcode to build the iOS source preview. The iOS app has no third-party package dependency and requires iOS 17 or later.

Build the Android beta source with JDK 17 and Android SDK 37:

```bash
cd android
./gradlew testDebugUnitTest compileDebugAndroidTestKotlin lintDebug validateDebugScreenshotTest assembleDebug assembleRelease bundleRelease
```

## Project

- Read [CONTRIBUTING.md](CONTRIBUTING.md) before opening a pull request.
- Report vulnerabilities through the process in [SECURITY.md](SECURITY.md).
- Product and UI decisions follow [PRODUCT.md](PRODUCT.md).
- The desktop host is MIT licensed. Harness and bundled dependencies retain their own licenses; see [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
