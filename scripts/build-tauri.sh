#!/usr/bin/env bash
# Build the signed macOS Tauri artifact for DeepSeek Harness Desktop.
# Usage: scripts/build-tauri.sh [arm64|x86_64]
# Outputs: release/DeepSeek Harness Desktop.app, release/*.dmg, release/*.zip
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

ARCH="${1:-$(uname -m)}"
case "$ARCH" in
  arm64)
    TRIPLE="aarch64-apple-darwin"
    NODE_ARCH="arm64"
    ARTIFACT_ARCH="arm64"
    ;;
  x86_64)
    TRIPLE="x86_64-apple-darwin"
    NODE_ARCH="x64"
    ARTIFACT_ARCH="x64"
    ;;
  *)
    echo "unsupported arch: $ARCH" >&2
    exit 1
    ;;
esac
NODE_VERSION="22.22.0"
TAURI_CLI="$REPO_ROOT/.tauri-cli/node_modules/.bin/tauri"
BUILD_TEMP="$(mktemp -d /tmp/deepseek-harness-tauri.XXXXXX)"

[ -d /opt/homebrew/bin ] && export PATH="/opt/homebrew/bin:$PATH"

export RUSTUP_HOME="${RUSTUP_HOME:-$REPO_ROOT/.rustup}"
export CARGO_HOME="${CARGO_HOME:-$REPO_ROOT/.cargo}"
export PATH="$CARGO_HOME/bin:$PATH"

restore_dev_dependencies() {
  echo ">> restoring development dependencies"
  npm ci --no-audit --no-fund >/dev/null 2>&1 || \
    echo '!! run "npm ci" manually to restore development dependencies' >&2
}

cleanup() {
  restore_dev_dependencies
  find "$BUILD_TEMP" -depth -delete 2>/dev/null || true
}
trap cleanup EXIT

if [ ! -x "$CARGO_HOME/bin/cargo" ]; then
  case "$(uname -m)" in
    arm64) RUSTUP_HOST="aarch64-apple-darwin" ;;
    x86_64) RUSTUP_HOST="x86_64-apple-darwin" ;;
    *) echo "unsupported build host: $(uname -m)" >&2; exit 1 ;;
  esac
  echo ">> bootstrapping Rust toolchain for $RUSTUP_HOST"
  curl --fail --silent --show-error \
    "https://static.rust-lang.org/rustup/dist/${RUSTUP_HOST}/rustup-init" \
    --output "$BUILD_TEMP/rustup-init"
  chmod +x "$BUILD_TEMP/rustup-init"
  "$BUILD_TEMP/rustup-init" -y --profile minimal --default-toolchain stable --no-modify-path >/dev/null
fi
rustup target add "$TRIPLE" >/dev/null

if [ ! -x "$TAURI_CLI" ]; then
  echo ">> installing pinned Tauri CLI"
  (cd .tauri-cli && npm ci --no-audit --no-fund >/dev/null)
fi

echo ">> installing production dependencies"
npm ci --omit=dev --no-audit --no-fund

echo ">> pruning runtime for darwin/$NODE_ARCH"
(cd node_modules && node "$REPO_ROOT/scripts/prune-runtime.mjs" . --platform darwin --arch "$NODE_ARCH")

SIDECAR="src-tauri/binaries/node-${TRIPLE}"
if [ ! -x "$SIDECAR" ] || [ "$("$SIDECAR" --version 2>/dev/null || true)" != "v${NODE_VERSION}" ]; then
  echo ">> downloading and verifying Node $NODE_VERSION for darwin/$NODE_ARCH"
  NODE_ARCHIVE="node-v${NODE_VERSION}-darwin-${NODE_ARCH}.tar.gz"
  curl --fail --silent --show-error --location \
    "https://nodejs.org/dist/v${NODE_VERSION}/${NODE_ARCHIVE}" \
    --output "$BUILD_TEMP/$NODE_ARCHIVE"
  curl --fail --silent --show-error --location \
    "https://nodejs.org/dist/v${NODE_VERSION}/SHASUMS256.txt" \
    --output "$BUILD_TEMP/SHASUMS256.txt"
  (
    cd "$BUILD_TEMP"
    grep " ${NODE_ARCHIVE}$" SHASUMS256.txt > SHASUMS256.selected
    shasum -a 256 -c SHASUMS256.selected
    tar -xzf "$NODE_ARCHIVE"
  )
  mkdir -p src-tauri/binaries
  cp "$BUILD_TEMP/node-v${NODE_VERSION}-darwin-${NODE_ARCH}/bin/node" "$SIDECAR"
  chmod +x "$SIDECAR"
fi

export APPLE_SIGNING_IDENTITY="${APPLE_SIGNING_IDENTITY:--}"
if [[ "$APPLE_SIGNING_IDENTITY" == "Developer ID Application:"* ]]; then
  : "${APPLE_ID:?APPLE_ID is required for notarization}"
  : "${APPLE_PASSWORD:?APPLE_PASSWORD is required for notarization}"
  : "${APPLE_TEAM_ID:?APPLE_TEAM_ID is required for notarization}"
else
  # Tauri enables notarization when these variables merely exist, even if the
  # GitHub secrets expanded to empty strings. Keep the ad-hoc path truly local.
  unset APPLE_ID APPLE_PASSWORD APPLE_TEAM_ID
fi

echo ">> signing bundled native dependencies with $APPLE_SIGNING_IDENTITY"
NATIVE_SIGNATURES=0
while IFS= read -r -d '' native_file; do
  case "$(file -b "$native_file")" in
    Mach-O*)
      if [[ "$APPLE_SIGNING_IDENTITY" == "Developer ID Application:"* ]]; then
        codesign --force --timestamp --options runtime \
          --sign "$APPLE_SIGNING_IDENTITY" "$native_file"
      else
        codesign --force --options runtime --sign - "$native_file"
      fi
      NATIVE_SIGNATURES=$((NATIVE_SIGNATURES + 1))
      ;;
  esac
done < <(find node_modules -type f \( -name '*.node' -o -name '*.dylib' -o -perm -111 \) -print0)
echo "   signed $NATIVE_SIGNATURES native files"

# Tauri validates every externalBin path from build.rs, including when Cargo is
# only building the dsh launcher itself. Seed the two launcher paths with the
# same-architecture Node sidecar to break that bootstrap cycle; the real CLI
# binary replaces both placeholders immediately after Cargo finishes.
for CLI_SIDECAR_NAME in dsh pnpm; do
  cp "$SIDECAR" "src-tauri/binaries/${CLI_SIDECAR_NAME}-${TRIPLE}"
  chmod +x "src-tauri/binaries/${CLI_SIDECAR_NAME}-${TRIPLE}"
done

echo ">> building bundled dsh command launcher"
(
  cd src-tauri
  cargo build --release --target "$TRIPLE" --bin dsh
)
CLI_BINARY="src-tauri/target/${TRIPLE}/release/dsh"
mkdir -p src-tauri/binaries
install -m 755 "$CLI_BINARY" "src-tauri/binaries/dsh-${TRIPLE}"
install -m 755 "$CLI_BINARY" "src-tauri/binaries/pnpm-${TRIPLE}"

VERSION="$(node -e 'console.log(require("./src-tauri/tauri.conf.json").version)')"
echo ">> building Tauri $VERSION for $TRIPLE"
(
  cd src-tauri
  "$TAURI_CLI" build --ci --target "$TRIPLE" --bundles app
)

BUNDLE_ROOT="src-tauri/target/${TRIPLE}/release/bundle"
APP="$BUNDLE_ROOT/macos/DeepSeek Harness Desktop.app"
[ -d "$APP" ] || { echo "Tauri app not found: $APP" >&2; exit 1; }

codesign --verify --deep --strict --verbose=4 "$APP"

# Tauri's styled DMG helper drives Finder and can time out on headless Intel
# GitHub runners. Build the same drag-to-Applications layout with hdiutil only.
DMG_STAGE="$BUILD_TEMP/dmg-root"
TAURI_DMG="$BUNDLE_ROOT/dmg/DeepSeek-Harness-Desktop-${VERSION}-${ARTIFACT_ARCH}.dmg"
mkdir -p "$DMG_STAGE" "$BUNDLE_ROOT/dmg"
ditto "$APP" "$DMG_STAGE/DeepSeek Harness Desktop.app"
ln -s /Applications "$DMG_STAGE/Applications"
hdiutil create \
  -volname "DeepSeek Harness Desktop" \
  -srcfolder "$DMG_STAGE" \
  -fs HFS+ \
  -format UDZO \
  -ov "$TAURI_DMG" >/dev/null
hdiutil imageinfo "$TAURI_DMG" >/dev/null

echo ">> collecting release artifacts"
mkdir -p release
find "release/DeepSeek Harness Desktop.app" -depth -delete 2>/dev/null || true
cp -R "$APP" "release/DeepSeek Harness Desktop.app"
cp "$TAURI_DMG" "release/DeepSeek-Harness-Desktop-${VERSION}-mac-${ARTIFACT_ARCH}.dmg"
ditto -c -k --sequesterRsrc --keepParent \
  "release/DeepSeek Harness Desktop.app" \
  "release/DeepSeek-Harness-Desktop-${VERSION}-mac-${ARTIFACT_ARCH}.zip"

echo "✅ built: release/DeepSeek Harness Desktop.app ($TRIPLE)"
echo "   dmg: release/DeepSeek-Harness-Desktop-${VERSION}-mac-${ARTIFACT_ARCH}.dmg"
echo "   zip: release/DeepSeek-Harness-Desktop-${VERSION}-mac-${ARTIFACT_ARCH}.zip"
