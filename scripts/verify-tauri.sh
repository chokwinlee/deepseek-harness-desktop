#!/usr/bin/env bash
# Smoke-test the packaged Tauri app, native runtime, and graceful process cleanup.
# Usage: scripts/verify-tauri.sh [path-to-app]
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"
APP="${1:-release/DSH Desktop.app}"
NODE="$APP/Contents/MacOS/node"
DSH_CLI="$APP/Contents/MacOS/dsh"
PNPM_CLI="$APP/Contents/MacOS/pnpm"
APP_BINARY="$(find "$APP/Contents/MacOS" -maxdepth 1 -type f -perm -111 ! -name node ! -name dsh ! -name pnpm -print -quit)"
[ -x "$APP_BINARY" ] || { echo "app binary not found under $APP/Contents/MacOS" >&2; exit 1; }
[ -x "$NODE" ] || { echo "Node sidecar not found: $NODE" >&2; exit 1; }
[ -x "$DSH_CLI" ] || { echo "DSH command launcher not found: $DSH_CLI" >&2; exit 1; }
[ -x "$PNPM_CLI" ] || { echo "pnpm command launcher not found: $PNPM_CLI" >&2; exit 1; }

for candidate in \
  "$APP/Contents/Resources/node_modules" \
  "$APP/Contents/Resources/_up_/node_modules"; do
  if [ -d "$candidate" ]; then
    MODULES="$candidate"
    break
  fi
done
[ -n "${MODULES:-}" ] || { echo "bundled node_modules not found" >&2; exit 1; }
PNPM_SCRIPT="$MODULES/pnpm/bin/pnpm.mjs"
[ -f "$PNPM_SCRIPT" ] || { echo "bundled pnpm not found: $PNPM_SCRIPT" >&2; exit 1; }
DESKTOP_SETTINGS_PATCH="$MODULES/dsh-desktop-settings-plugin/desktop.patch.yml"
DESKTOP_SETTINGS_CLIENT="$MODULES/dsh-desktop-settings-plugin/lib/client.js"
[ -f "$DESKTOP_SETTINGS_PATCH" ] || { echo "Desktop Settings patch not found: $DESKTOP_SETTINGS_PATCH" >&2; exit 1; }
[ -f "$DESKTOP_SETTINGS_CLIENT" ] || { echo "Desktop Settings client not found: $DESKTOP_SETTINGS_CLIENT" >&2; exit 1; }

echo ">> verifying bundled PTY and image native modules"
NODE_PATH="$MODULES" "$NODE" <<'NODE'
const pty = require('node-pty')
const sharp = require('sharp')

const terminal = pty.spawn('/bin/sh', ['-c', 'printf tauri-pty-ok'], {
  cols: 80,
  rows: 24,
  cwd: process.cwd(),
  env: process.env,
})
let output = ''
const timeout = setTimeout(() => {
  terminal.kill()
  throw new Error('bundled node-pty smoke timed out')
}, 10_000)
terminal.onData(chunk => { output += chunk })
terminal.onExit(async ({ exitCode }) => {
  clearTimeout(timeout)
  if (exitCode !== 0 || !output.includes('tauri-pty-ok')) {
    throw new Error(`bundled node-pty smoke failed: code=${exitCode} output=${output}`)
  }
  const metadata = await sharp({
    create: { width: 1, height: 1, channels: 4, background: '#000000' },
  }).png().metadata()
  if (metadata.width !== 1 || metadata.height !== 1) {
    throw new Error('bundled sharp smoke failed')
  }
  console.log('native runtime smoke passed')
})
NODE

PNPM_VERSION="$("$NODE" "$PNPM_SCRIPT" --version)"
[ -n "$PNPM_VERSION" ] || { echo "bundled pnpm did not report a version" >&2; exit 1; }
echo "bundled pnpm smoke passed ($PNPM_VERSION)"

PNPM_CLI_VERSION="$("$PNPM_CLI" --version)"
[ "$PNPM_CLI_VERSION" = "$PNPM_VERSION" ] || { echo "bundled pnpm launcher version mismatch" >&2; exit 1; }
echo "bundled pnpm command smoke passed ($PNPM_CLI_VERSION)"

DSH_VERSION="$("$DSH_CLI" --version)"
[ -n "$DSH_VERSION" ] || { echo "bundled dsh launcher did not report a version" >&2; exit 1; }
echo "bundled dsh command smoke passed ($DSH_VERSION)"

CLI_TEST_HOME="$REPO_ROOT/.verify-tauri-cli-home"
find "$CLI_TEST_HOME" -depth -delete 2>/dev/null || true
mkdir -p "$CLI_TEST_HOME"
DSH_HOME="$CLI_TEST_HOME/.dsh" "$DSH_CLI" plugin --profile web add \
  "link:$REPO_ROOT/test/fixtures/sample-plugin" >/dev/null
node -e '
  const manifest = require(process.argv[1])
  if (manifest.dependencies?.["dsh-desktop-fixture-plugin"] === undefined) process.exit(1)
  if (!manifest.dsh?.profile?.bundles?.includes("dsh-desktop-fixture-plugin")) process.exit(1)
' "$CLI_TEST_HOME/.dsh/profiles/web/package.json"
DSH_HOME="$CLI_TEST_HOME/.dsh" CI=true "$DSH_CLI" plugin --profile web remove \
  "dsh-desktop-fixture-plugin" >/dev/null
node -e '
  const manifest = require(process.argv[1])
  if (manifest.dependencies?.["dsh-desktop-fixture-plugin"] !== undefined) process.exit(1)
  if (manifest.dsh?.profile?.bundles?.includes("dsh-desktop-fixture-plugin")) process.exit(1)
' "$CLI_TEST_HOME/.dsh/profiles/web/package.json"
find "$CLI_TEST_HOME" -depth -delete
echo "bundled dsh plugin add/remove smoke passed"

SPIKE_HOME="$REPO_ROOT/.verify-tauri-home"
find "$SPIKE_HOME" -depth -delete 2>/dev/null || true
mkdir -p "$SPIKE_HOME"
export SPIKE_HOME

LOG="$REPO_ROOT/.verify-tauri.log"
: > "$LOG"
APP_PID=""
CHILD_PID=""

cleanup() {
  if [ -n "$APP_PID" ] && kill -0 "$APP_PID" 2>/dev/null; then
    kill "$APP_PID" 2>/dev/null || true
    sleep 1
    kill -9 "$APP_PID" 2>/dev/null || true
  fi
  if [ -n "$CHILD_PID" ] && kill -0 "$CHILD_PID" 2>/dev/null; then
    kill "$CHILD_PID" 2>/dev/null || true
  fi
}
trap cleanup EXIT

"$APP_BINARY" >"$LOG" 2>&1 &
APP_PID=$!

URL=""
for _ in $(seq 1 120); do
  URL="$(grep -oE 'http://127\.0\.0\.1:[0-9]+' "$LOG" | head -1 || true)"
  CHILD_PID="$(sed -nE 's/.*harness spawned \(pid ([0-9]+)\).*/\1/p' "$LOG" | head -1 || true)"
  [ -n "$URL" ] && break
  kill -0 "$APP_PID" 2>/dev/null || { echo "app exited early:" >&2; tail -20 "$LOG" >&2; exit 1; }
  sleep 1
done
[ -n "$URL" ] || { echo "timeout waiting for harness readiness" >&2; tail -30 "$LOG" >&2; exit 1; }
[ -n "$CHILD_PID" ] || { echo "harness child pid was not logged" >&2; exit 1; }

echo "harness ready at $URL"
CODE="$(curl --silent --max-time 10 --output /dev/null --write-out '%{http_code}' "$URL/")"
echo "GET $URL/ -> $CODE"
[ "$CODE" = "200" ] || { echo "UI check failed" >&2; exit 1; }
BOOT_HTML="$(curl --fail --silent --max-time 10 "$URL/")"
[[ "$BOOT_HTML" == *"dsh-desktop-settings-plugin"* ]] || { echo "Desktop Settings plugin missing from Web boot manifest" >&2; exit 1; }
DESKTOP_CLIENT="$(curl --fail --silent --max-time 10 "$URL/plugins/dsh-desktop-settings-plugin/client.js")"
[[ "$DESKTOP_CLIENT" == *"settings.plugins.tab"* ]] || { echo "Desktop Settings client bundle is invalid" >&2; exit 1; }
echo "native Settings plugin smoke passed"

echo ">> requesting graceful Tauri shutdown"
kill "$APP_PID"
for _ in $(seq 1 100); do
  kill -0 "$APP_PID" 2>/dev/null || break
  sleep 0.1
done
if kill -0 "$APP_PID" 2>/dev/null; then
  echo "Tauri app did not exit after SIGTERM" >&2
  exit 1
fi
wait "$APP_PID" || true
APP_PID=""

for _ in $(seq 1 50); do
  kill -0 "$CHILD_PID" 2>/dev/null || break
  sleep 0.1
done
if kill -0 "$CHILD_PID" 2>/dev/null; then
  echo "Harness child survived Tauri shutdown: $CHILD_PID" >&2
  exit 1
fi
CHILD_PID=""

echo "✅ verify-tauri passed (HTTP + native modules + pnpm + child cleanup)"
