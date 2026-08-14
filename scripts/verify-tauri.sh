#!/usr/bin/env bash
# Smoke-test the packaged Tauri app: launch, wait for harness readiness, curl the UI.
# Usage: scripts/verify-tauri.sh [path-to-app]
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"
APP="${1:-release/DeepSeek Harness Desktop.app}"
[ -x "$APP/Contents/MacOS/dsh-tauri-spike" ] || { echo "app binary not found: $APP" >&2; exit 1; }

SPIKE_HOME="$REPO_ROOT/.verify-tauri-home"
rm -rf "$SPIKE_HOME" && mkdir -p "$SPIKE_HOME"
export SPIKE_HOME

LOG="$REPO_ROOT/.verify-tauri.log"
: > "$LOG"
"$APP/Contents/MacOS/dsh-tauri-spike" >"$LOG" 2>&1 &
APP_PID=$!
disown $APP_PID 2>/dev/null || true
trap 'kill "$APP_PID" 2>/dev/null || true' EXIT

URL=""
for i in $(seq 1 120); do
  URL="$(grep -oE "http://127.0.0.1:[0-9]+" "$LOG" | head -1 || true)"
  [ -n "$URL" ] && break
  kill -0 $APP_PID 2>/dev/null || { echo "app exited early:" >&2; tail -20 "$LOG" >&2; exit 1; }
  sleep 1
done
[ -n "$URL" ] || { echo "timeout waiting for harness readiness" >&2; tail -30 "$LOG" >&2; kill $APP_PID 2>/dev/null || true; exit 1; }

echo "harness ready at $URL"
CODE="$(curl -s --max-time 10 -o /dev/null -w "%{http_code}" "$URL/")"
echo "GET $URL/ -> $CODE"
[ "$CODE" = "200" ] || { echo "UI check failed" >&2; kill $APP_PID 2>/dev/null || true; exit 1; }

kill -9 $APP_PID 2>/dev/null || true
sleep 2
echo "✅ verify-tauri passed"