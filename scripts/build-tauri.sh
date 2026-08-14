#!/usr/bin/env bash
# Build the macOS Tauri artifact for DeepSeek Harness Desktop from this repo.
# Usage: scripts/build-tauri.sh [arm64|x86_64]
# Outputs: release/DeepSeek Harness Desktop.app, release/*.dmg, release/*.zip
# Platform decision: Tauri owns macOS; Electron owns Windows (see TAURI-SPIKE.md).
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

ARCH="${1:-$(uname -m)}"
case "$ARCH" in
  arm64) TRIPLE="aarch64-apple-darwin" ;;
  x86_64) TRIPLE="x86_64-apple-darwin" ;;
  *) echo "unsupported arch: $ARCH" >&2; exit 1 ;;
esac
NODE_VERSION="22.22.0"

# homebrew node/npm on dev machines (no-op in CI runners where node is on PATH)
[ -d /opt/homebrew/bin ] && export PATH="/opt/homebrew/bin:$PATH"

# rust toolchain (workspace-local by default)
export RUSTUP_HOME="${RUSTUP_HOME:-$REPO_ROOT/.rustup}"
export CARGO_HOME="${CARGO_HOME:-$REPO_ROOT/.cargo}"
export PATH="$CARGO_HOME/bin:$PATH"
if [ ! -x "$CARGO_HOME/bin/cargo" ]; then
  echo ">> bootstrapping rust toolchain (one-time)"
  curl -sSf https://static.rust-lang.org/rustup/dist/aarch64-apple-darwin/rustup-init -o /tmp/rustup-init
  chmod +x /tmp/rustup-init
  /tmp/rustup-init -y --profile minimal --default-toolchain stable --no-modify-path >/dev/null
fi

# production-only node_modules (the full tree contains electron/typescript dev deps)
echo ">> npm ci --omit=dev"
rm -rf node_modules
npm ci --omit=dev --no-audit --no-fund
restore_dev() { echo ">> restoring dev deps: npm ci"; npm ci --no-audit --no-fund >/dev/null 2>&1 || echo "!! run \"npm ci\" manually to restore dev deps" >&2; }
trap restore_dev EXIT

# prune runtime-unneeded files (.d.ts/.ts/maps/tests/...)
echo ">> pruning node_modules"
( cd node_modules && node "$REPO_ROOT/scripts/prune-runtime.mjs" . )

# node sidecar (official build, same version as engines requirement)
SIDECAR="src-tauri/binaries/node-${TRIPLE}"
if [ ! -x "$SIDECAR" ]; then
  echo ">> downloading Node $NODE_VERSION sidecar for $ARCH"
  mkdir -p src-tauri/binaries /tmp/node-dl
  curl -sSfL -o /tmp/node-dl/node.tar.gz "https://nodejs.org/dist/v${NODE_VERSION}/node-v${NODE_VERSION}-darwin-${ARCH}.tar.gz"
  tar -xzf /tmp/node-dl/node.tar.gz -C /tmp/node-dl
  cp "/tmp/node-dl/node-v${NODE_VERSION}-darwin-${ARCH}/bin/node" "$SIDECAR"
  chmod +x "$SIDECAR"
fi

# tauri-cli in an isolated dir (never pollutes node_modules)
if [ ! -x .tauri-cli/node_modules/.bin/tauri ]; then
  echo ">> installing tauri-cli"
  mkdir -p .tauri-cli
  ( cd .tauri-cli
    [ -f package.json ] || printf '{"name":"tauri-cli-host","private":true,"version":"1.0.0"}\n' > package.json
    npm i @tauri-apps/cli@^2 --no-audit --no-fund --cache "$PWD/.npm-cache" >/dev/null
  )
fi

VERSION="$(node -e "console.log(require(\"./src-tauri/tauri.conf.json\").version)")"

# build the .app
echo ">> tauri build (this takes a few minutes on first run)"
( cd src-tauri && "$REPO_ROOT/.tauri-cli/node_modules/.bin/tauri" build --bundles app )
APP="src-tauri/target/release/bundle/macos/DeepSeek Harness Desktop.app"

# post-build fix: node sidecar must NOT be hardened-runtime signed (V8 crashes)
echo ">> re-signing node sidecar without hardened runtime"
codesign --force --sign - "$APP/Contents/MacOS/node"
codesign --force --sign - --options runtime "$APP"
codesign --verify --deep --strict "$APP"

# artifacts
echo ">> packaging dmg + zip"
mkdir -p release
rm -rf "release/DeepSeek Harness Desktop.app"
cp -R "$APP" "release/DeepSeek Harness Desktop.app"
hdiutil create -volname "DeepSeek Harness Desktop" -srcfolder "release/DeepSeek Harness Desktop.app" -ov -format UDZO -fs HFS+ "release/DeepSeek-Harness-Desktop-${VERSION}-mac-${ARCH}.dmg" >/dev/null
ditto -c -k --sequesterRsrc --keepParent "release/DeepSeek Harness Desktop.app" "release/DeepSeek-Harness-Desktop-${VERSION}-mac-${ARCH}.zip"

echo "✅ built: release/DeepSeek Harness Desktop.app (macOS $ARCH)"
echo "   dmg: release/DeepSeek-Harness-Desktop-${VERSION}-mac-${ARCH}.dmg"
echo "   zip: release/DeepSeek-Harness-Desktop-${VERSION}-mac-${ARCH}.zip"