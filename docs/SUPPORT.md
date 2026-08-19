# Harness Remote Support

Harness Remote is an independent open-source project. It is not an official DeepSeek AI or Tailscale product.

## Before reporting a connection issue

1. Confirm Harness Desktop is running and Mobile Remote is enabled.
2. If you use Tailscale, confirm both devices are in the same tailnet and the iPhone can resolve the device name.
3. If you use Same Wi-Fi, confirm both devices are still on the same trusted private network and re-scan the Desktop QR code after disabling/re-enabling that endpoint.
4. Do not manually enter a local HTTP address; the pairing QR code contains the required access credential.
5. Do not use Tailscale Funnel. Harness Remote is intended for a private network or another HTTPS endpoint you protect.
6. In the app, pull down on the task list to retry.

## Get help

Report reproducible problems at <https://github.com/chokwinlee/deepseek-harness-desktop/issues>. Include the iOS version, Desktop version, connection type, and the visible error message. Never include API keys, tailnet credentials, private source code, or confidential prompts.

The built-in Review Demo is available without a computer and can be used to verify the app's interface, notifications, prompt controls, and question flow.
