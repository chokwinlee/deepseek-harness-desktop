# DSH Remote App Review Notes

## Product summary

DSH Remote is a native SwiftUI companion that controls an AI coding Harness running on a computer owned or managed by the user. The iOS app does not download or execute code, expose a terminal, install plugins, edit model credentials, or purchase digital services. Work executes on the user's computer.

The app is an independent open-source project and is not affiliated with DeepSeek AI or Tailscale. The name, icon, About screen, and store copy must preserve that distinction.

## Review without external hardware or accounts

No login or review credentials are required.

1. Launch the app.
2. On the no-computer screen, tap **先体验一下** below the connect button.
3. Open **登录流程上线检查** (`Login flow release check`).
4. Inspect the native conversation and tool-summary cards.
5. Answer the visible confirmation question.
6. Send a prompt; the demo simulates running and completion without network access or an LLM.
7. The `@` picker and subagent catalog/history use offline demo data. The image draft can be exercised with any image explicitly chosen in the system picker or pasted from the clipboard; the demo still makes no network or model call and requests no broad photo-library access.

The offline experience is presented as an explicit secondary action when no computer has been saved and contains no hidden gestures.

## Live connection

Live mode connects directly to the user's Harness computer through Tailscale Serve, an authenticated same-Wi-Fi endpoint, or another HTTPS endpoint the user controls. The same-Wi-Fi endpoint is the recommended first pairing path, is opt-in, is restricted to the Remote API allowlist, and is protected by a high-entropy random bearer credential carried in the pairing QR code. It uses local HTTP and is labeled for trusted private Wi-Fi only. Tailscale is presented only as an optional cross-network or untrusted-network path and is not required by the app. The maintainer operates no relay. No Tailscale account is created or purchased in the app.

## Data and privacy

- The maintainer receives no prompts, code, credentials, diagnostics, analytics, or account data from the iOS app.
- Saved computer names, URLs, and LAN pairing credentials use `UserDefaults` only for app functionality; the privacy manifest declares reason `CA92.1`.
- Camera access occurs only after the user chooses QR scanning.
- Image access occurs only after the user chooses the system photo picker or explicitly pastes an image. Selected images are processed in memory and sent directly to the user's computer; the app has no photo library, relay, or maintainer-operated upload service.
- Local notifications report task completion or an interaction waiting while monitoring is active.
- Prompts can be sent by the user's computer to the model provider configured on that computer. App Store privacy answers and review notes must disclose this user-directed flow without claiming that no third party ever processes content.

## Store submission checklist

- Host the privacy policy and support page at stable public HTTPS URLs before submission.
- Use those URLs in App Store Connect and verify they open without authentication.
- Complete the App Privacy questionnaire consistently with the shipped binary and this policy.
- Use the Developer Tools category and explain the companion relationship in Review Notes.
- Attach a short review video only if Apple requests help reproducing a live-computer connection; the built-in demo should remain sufficient for core review.
- Verify the final archive contains `PrivacyInfo.xcprivacy`, the independent 1024×1024 icon, camera/local-network purpose strings, and no `WKWebView` remote UI.
- Confirm all repository licenses and attribution notices are current before the first public binary.
