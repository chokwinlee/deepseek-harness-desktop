#!/usr/bin/env bash
# Smoke-test the packaged Tauri app, native runtime, and graceful process cleanup.
# Usage: scripts/verify-tauri.sh [path-to-app]
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"
APP="${1:-release/DeepSeek Harness Desktop.app}"
NODE="$APP/Contents/MacOS/node"
APP_BINARY="$(find "$APP/Contents/MacOS" -maxdepth 1 -type f -perm -111 ! -name node -print -quit)"
[ -x "$APP_BINARY" ] || { echo "app binary not found under $APP/Contents/MacOS" >&2; exit 1; }
[ -x "$NODE" ] || { echo "Node sidecar not found: $NODE" >&2; exit 1; }

for candidate in \
  "$APP/Contents/Resources/node_modules" \
  "$APP/Contents/Resources/_up_/node_modules"; do
  if [ -d "$candidate" ]; then
    MODULES="$candidate"
    break
  fi
done
[ -n "${MODULES:-}" ] || { echo "bundled node_modules not found" >&2; exit 1; }

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

echo "✅ verify-tauri passed (HTTP + native modules + child cleanup)"
