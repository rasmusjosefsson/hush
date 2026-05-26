#!/usr/bin/env bash
set -euo pipefail

# Quick build → quit → install → relaunch.
# Fastest way to test changes in the production app.

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

echo "[1/4] Building app…"
"$ROOT_DIR/scripts/dist/build_app_bundle.sh"

echo "[2/4] Quitting Hush…"
osascript -e 'quit app "Hush"' 2>/dev/null || true
sleep 1
pkill -f "/Applications/Hush.app" 2>/dev/null || true
sleep 0.5

echo "[3/4] Installing to /Applications…"
rm -rf /Applications/Hush.app
cp -R "$ROOT_DIR/dist/Hush.app" /Applications/

echo "[4/4] Launching…"
open /Applications/Hush.app

echo "Done."
