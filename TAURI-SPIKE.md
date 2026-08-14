# Tauri spike — DeepSeek Harness Desktop (macOS arm64)

A minimal Tauri v2 shell that boots the `@deepseek-ai/dsh` harness and shows its
Web UI in the system WebView (WKWebView), instead of bundling Chromium like Electron.

## Architecture

`src-tauri/src/main.rs`:
1. resolves the bundled Node sidecar (`Contents/MacOS/node`) and the dsh entry
   (`Contents/Resources/_up_/node_modules/@deepseek-ai/dsh/lib/bin.js`)
2. spawns `node --expose-internals <dsh> web --host 127.0.0.1 --port 0`
3. parses the `dsh web: http://127.0.0.1:PORT` readiness line
4. loads that URL in a `WebviewUrl::External` window (1440x900)
5. on exit: SIGTERM then SIGKILL the harness child

## Rebuilding (this machine)

```bash
export RUSTUP_HOME=/Users/chokwin/Documents/ChatGPT/deepseek-harness-desktop/.rustup
export CARGO_HOME=/Users/chokwin/Documents/ChatGPT/deepseek-harness-desktop/.cargo
export PATH=$CARGO_HOME/bin:/opt/homebrew/bin:$PATH
cd src-tauri
../.tauri-cli/node_modules/.bin/tauri build --bundles app
```

Post-build fix (required, see below): re-sign the bundled Node WITHOUT hardened runtime:

```bash
APP="target/release/bundle/macos/DeepSeek Harness Desktop.app"
codesign --force --sign - "$APP/Contents/MacOS/node"
codesign --force --sign - --options runtime "$APP"
```

DMG (hdiutil needs full disk access in this sandbox):
```bash
hdiutil create -volname "DeepSeek Harness Desktop" -srcfolder "$APP" -ov -format UDZO release/DeepSeek-Harness-Desktop-0.1.0-mac-arm64.dmg
```

## Shrinking the payload

Run `scripts/prune-runtime.mjs` on the prod tree before `tauri build` to drop
runtime-unneeded files (.d.ts/.ts types, sourcemaps, tests, docs, changelogs, @types):

```bash
cd node_modules && node ../scripts/prune-runtime.mjs .
```

Removes ~19000 items / ~73MB of file bytes (disk 342M -> 203M). Do NOT delete
`doc`/`docs` dirs (e.g. `yaml/dist/doc` is required at runtime). Provider SDKs
(anthropic/mistral/google/aws) are eagerly imported by `@earendil-works/pi-ai/providers/all`
and cannot be removed.

## Gotchas found during the spike

- **Node sidecar + hardened runtime = crash**: the official node binary from
  nodejs.org crashes with `Trace/BPT trap` when signed ad-hoc with the `runtime`
  flag (V8 needs `allow-unsigned-executable-memory`). Re-sign it without hardened
  runtime after `tauri build` (see above).
- **Resources land under `Contents/Resources/_up_`** when declared as a glob in
  `bundle.resources`; resolve both `Resources/node_modules` and
  `Resources/_up_/node_modules`.
- **`exe_dir()` already strips the filename**: parent math must account for that
  (Contents = exe.parent(), not exe.parent().parent()).
- The packaged `node_modules` is the FULL npm prod tree (342M). Electron's
  electron-builder prunes per-package `files` (210M); a Tauri port should prune
  similarly (e.g. npm `--omit=dev` + package `files` semantics) to shrink further.

## Artifacts (this run)

```
release/DeepSeek Harness Desktop.app              326M   (after prune)
release/DeepSeek-Harness-Desktop-0.1.0-mac-arm64.dmg  105M
release/DeepSeek-Harness-Desktop-0.1.0-mac-arm64.zip  100M
```

vs Electron: .app 498M / DMG 153M / ZIP 166M.
Breakdown (after prune): shell 10M + node sidecar 106M + node_modules 203M.