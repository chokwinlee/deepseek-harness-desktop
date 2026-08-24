# DSH Remote for iOS

DSH Remote is the native SwiftUI companion for DSH Desktop. It connects directly to a Harness computer owned or managed by the user; the project does not operate a relay, account system, analytics service, or model gateway for the iOS app.

> [!IMPORTANT]
> The external beta has passed Beta App Review. Join the public TestFlight beta at <https://testflight.apple.com/join/7Ew6Yk9V>. The app is not yet published on the App Store, and GitHub Releases do not provide a generic installable IPA.

## What it can do

- Pair with DSH Desktop on the same trusted Wi-Fi using an authenticated QR code.
- Connect away from the local network through the user's own Tailscale Serve HTTPS entry.
- Browse Desktop projects and sessions, create a session, and continue an existing task.
- Prompt, queue, steer, cancel, answer approvals and structured questions, and receive local notifications.
- Send selected or pasted images, insert file and session references, inspect Goal/Plan/trajectory state, and follow continuable subagents.
- Switch among models already configured on the computer without exposing provider credentials on iPhone.

Code, repositories, Shell access, model calls, API keys, and task history remain on the computer.

## Languages

The app follows the language selected for DSH Remote in iOS Settings. English and Simplified Chinese cover the complete product surface, including setup, errors, notifications, approvals, model routing, Activity, images, references, and nested subagents. Project names, file paths, user prompts, and computer-provided model output are preserved as content rather than translated by the app.

## Install with TestFlight

Requirements:

- an iPhone running iOS 17 or later;
- Apple's [TestFlight app](https://apps.apple.com/app/testflight/id899247664);
- a running DSH Desktop release.

Steps:

1. Open the [DSH Remote public invitation](https://testflight.apple.com/join/7Ew6Yk9V).
2. Choose **View in TestFlight**, accept the invitation, and install the beta.
3. Open DSH Remote and pair it with the current DSH Desktop release.

The public group accepts up to 10,000 testers. Each uploaded build remains available for up to 90 days.

## Build from source with Xcode

Requirements:

- macOS with Xcode 16 or later;
- an iPhone running iOS 17 or later;
- an Apple Account signed in under **Xcode → Settings → Accounts**;
- a running DSH Desktop build.

Steps:

1. Clone the repository.
2. Open `ios/DSHRemote/DSHRemote.xcodeproj` in Xcode.
3. Select the `DSHRemote` target and open **Signing & Capabilities**.
4. Choose your Team. If automatic signing reports that the bundle identifier is unavailable, replace `com.chokwinlee.dshremote` with a unique identifier you control.
5. Connect your iPhone, choose it as the run destination, and select **Product → Run**.
6. Follow any Developer Mode or device-trust prompt shown by iOS or Xcode.

A free Xcode Personal Team supports personal on-device testing, but the app must be re-provisioned periodically. TestFlight is the supported installation path for testers who do not build from source.

## Pair on the same Wi-Fi

1. Open DSH Desktop.
2. Go to **Settings → General → Mobile Remote → Connect iPhone**.
3. Choose **Same Wi-Fi** and start local pairing.
4. In DSH Remote, tap **Add computer** and scan the QR code.

The LAN endpoint is opt-in, limited to the Remote API allowlist, and protected by a random credential carried in the QR code. Use it only on a trusted private Wi-Fi.

## Connect from another network

Install Tailscale on the Mac and iPhone, sign in to the same tailnet, then use the built-in setup guide on either Desktop or iPhone. Desktop configures Tailscale Serve automatically; do not use Funnel.

Chinese step-by-step guide: [`../../docs/TAILSCALE_REMOTE_SETUP.zh-CN.md`](../../docs/TAILSCALE_REMOTE_SETUP.zh-CN.md).

## Distribution status

| Channel | Status |
| --- | --- |
| Xcode source build | Available now |
| Public TestFlight | [Available now](https://testflight.apple.com/join/7Ew6Yk9V), up to 10,000 testers |
| App Store | Not submitted yet |

## Privacy and support

- [Privacy policy](../../docs/PRIVACY.md)
- [Support](../../docs/SUPPORT.md)
- [App Review notes](../../docs/APP_REVIEW_NOTES.md)

DSH Remote is an independent community project. It is not an official DeepSeek AI or Tailscale product.
