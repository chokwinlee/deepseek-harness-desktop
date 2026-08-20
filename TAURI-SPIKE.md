# macOS Tauri release — DSH Desktop

A Tauri v2 shell that boots the `@deepseek-ai/dsh` harness and shows its
Web UI in the system WebView (WKWebView), instead of bundling Chromium like Electron.

## Architecture

`src-tauri/src/main.rs`:
1. resolves the bundled Node sidecar (`Contents/MacOS/node`) and the dsh entry
   (`Contents/Resources/_up_/node_modules/@deepseek-ai/dsh/lib/bin.js`)
2. spawns `node --expose-internals <dsh> web --host 127.0.0.1 --port 0`
3. parses the `dsh web: http://127.0.0.1:PORT` readiness line
4. loads that URL in a `WebviewUrl::External` window (1440x900)
5. on exit: SIGTERM then SIGKILL the harness child

## Rebuilding

```bash
scripts/build-tauri.sh arm64
# or, on an Intel runner:
scripts/build-tauri.sh x86_64
```

Local and tagged builds use an ad-hoc identity by default. When a Developer ID
Application certificate plus `APPLE_ID`, `APPLE_PASSWORD`, and `APPLE_TEAM_ID`
are configured, Tauri signs, notarizes, and staples the bundle. Node receives the
JIT entitlements in `build/entitlements.mac.plist` while retaining Hardened Runtime.

## Shrinking the payload

Run `scripts/prune-runtime.mjs` on the prod tree before `tauri build` to drop
runtime-unneeded files (.d.ts/.ts types, sourcemaps, tests, docs, changelogs, @types):

```bash
cd node_modules
node ../scripts/prune-runtime.mjs . --platform darwin --arch arm64
```

The generic pass removes runtime-unneeded source, maps, tests, and docs. The macOS
pass also removes Windows `node-pty` binaries and the unused Sharp Wasm fallback,
while retaining the selected native architecture. Do NOT delete
`doc`/`docs` dirs (e.g. `yaml/dist/doc` is required at runtime). Provider SDKs
(anthropic/mistral/google/aws) are eagerly imported by `@earendil-works/pi-ai/providers/all`
and cannot be removed.

## Gotchas found during the spike

- **Node needs JIT entitlements**: signing the official Node binary with Hardened
  Runtime but without V8's JIT entitlements causes a startup crash. Keep Hardened
  Runtime and apply `allow-jit` plus `allow-unsigned-executable-memory`.
- **Resources land under `Contents/Resources/_up_`** when declared as a glob in
  `bundle.resources`; resolve both `Resources/node_modules` and
  `Resources/_up_/node_modules`.
- **`exe_dir()` already strips the filename**: parent math must account for that
  (Contents = exe.parent(), not exe.parent().parent()).
- The packaged `node_modules` is the FULL npm prod tree (342M). Electron's
  electron-builder prunes per-package `files` (210M); a Tauri port should prune
  similarly (e.g. npm `--omit=dev` + package `files` semantics) to shrink further.

## Published artifact comparison (v0.1.1 to v0.1.2)

| Architecture | Artifact | v0.1.1 Electron | v0.1.2 Tauri | Reduction |
| --- | --- | ---: | ---: | ---: |
| arm64 | DMG | 147.8 MB | 86.3 MB | 41.6% |
| arm64 | ZIP | 155.0 MB | 78.7 MB | 49.2% |
| x64 | DMG | 152.6 MB | 88.8 MB | 41.8% |
| x64 | ZIP | 159.9 MB | 81.0 MB | 49.3% |

These decimal MB figures come from the assets published on the GitHub v0.1.1 and
v0.1.2 releases. Both v0.1.2 macOS downloads stay below 90 MB. The remaining
payload is primarily the Node sidecar and Harness runtime.
## Platform decision (macOS = Tauri, Windows = Electron)

Tauri owns macOS; Electron keeps Windows. Rationale:
- macOS gets Tauri's size/memory wins and the system WebView;
- Windows keeps the battle-tested Electron path (no WebView2 runtime dependency,
  no new platform risk); both shells are thin wrappers over the same `dsh web` core;
- CI builds macOS via `scripts/build-tauri.sh` and Windows via the existing electron-builder flow.

One-click macOS build: `scripts/build-tauri.sh [arm64|x86_64]`
- prod-only `npm ci --omit=dev` -> prune -> Node 22 sidecar download -> `tauri build`
- verifies the Node download checksum and builds the requested Rust target
- signs Node with Hardened Runtime and the required JIT entitlements
- outputs `release/DSH Desktop.app` + dmg/zip
- restores dev deps on exit (trap); first run needs the rust toolchain (auto-bootstrapped)

Smoke test: `scripts/verify-tauri.sh` exercises native PTY/Sharp modules, launches
the packaged app, checks the HTTP UI, requests graceful shutdown, and asserts that
the Harness child did not survive.
