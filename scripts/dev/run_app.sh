#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
DERIVED_DATA_DIR="$ROOT_DIR/.build/xcode-dev"
PRODUCT_DIR="$DERIVED_DATA_DIR/Build/Products/Debug"
APP_BIN="$PRODUCT_DIR/Hush"
APP_BUNDLE="$PRODUCT_DIR/Hush-Dev.app"
LOG_FILE="${TMPDIR:-/tmp}/hush-dev.log"

echo "[1/4] Building debug app bundle (xcodebuild)…"
xcodebuild build \
  -scheme Hush \
  -configuration Debug \
  -destination "platform=OS X,arch=arm64" \
  -derivedDataPath "$DERIVED_DATA_DIR" \
  CODE_SIGN_IDENTITY="Apple Development" \
  DEVELOPMENT_TEAM=5P7V25NKVS \
  CODE_SIGNING_REQUIRED=YES \
  CODE_SIGNING_ALLOWED=YES >/dev/null

if [[ ! -x "$APP_BIN" ]]; then
  echo "Build succeeded but app binary not found at: $APP_BIN" >&2
  exit 1
fi

# Link PackageFrameworks so dyld can find them at runtime
PKGFW_DIR="$PRODUCT_DIR/PackageFrameworks"
mkdir -p "$PKGFW_DIR"

echo "[2/4] Wrapping in .app bundle for macOS permissions…"
MACOS_DIR="$APP_BUNDLE/Contents/MacOS"
mkdir -p "$MACOS_DIR"
cp -f "$APP_BIN" "$MACOS_DIR/Hush"

# Copy resource bundle
RESOURCE_BUNDLE="$PRODUCT_DIR/Hush_Hush.bundle"
if [[ -d "$RESOURCE_BUNDLE" ]]; then
  RESOURCES_DIR="$APP_BUNDLE/Contents/Resources"
  mkdir -p "$RESOURCES_DIR"
  rsync -a --delete "$RESOURCE_BUNDLE" "$RESOURCES_DIR/"
fi

# Symlink frameworks into the bundle
BUNDLE_FW_DIR="$APP_BUNDLE/Contents/Frameworks"
mkdir -p "$BUNDLE_FW_DIR"
for fw in "$PRODUCT_DIR"/*.framework; do
  [[ -d "$fw" ]] || continue
  fw_name="$(basename "$fw")"
  if [[ ! -e "$BUNDLE_FW_DIR/$fw_name" ]]; then
    ln -s "$fw" "$BUNDLE_FW_DIR/$fw_name"
  fi
done
BUNDLE_PKGFW_DIR="$MACOS_DIR/../Frameworks/PackageFrameworks"
mkdir -p "$BUNDLE_PKGFW_DIR"
for fw in "$PKGFW_DIR"/*.framework; do
  [[ -d "$fw" ]] || continue
  fw_name="$(basename "$fw")"
  if [[ ! -e "$BUNDLE_PKGFW_DIR/$fw_name" ]]; then
    ln -s "$fw" "$BUNDLE_PKGFW_DIR/$fw_name"
  fi
done

cat > "$APP_BUNDLE/Contents/Info.plist" << 'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key>
    <string>com.hush.dev</string>
    <key>CFBundleName</key>
    <string>Hush Dev</string>
    <key>CFBundleExecutable</key>
    <string>Hush</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>CFBundleShortVersionString</key>
    <string>0.1.0</string>
    <key>NSMicrophoneUsageDescription</key>
    <string>Hush needs microphone access for voice dictation and transcription.</string>
</dict>
</plist>
PLIST

codesign --force --sign "Apple Development" --deep "$APP_BUNDLE" 2>/dev/null || true

echo "[3/4] Stopping existing Hush processes…"
pkill -f "Hush-Dev.app/Contents/MacOS/Hush" || true
pkill -f "$DERIVED_DATA_DIR/Build/Products/Debug/Hush" || true
sleep 1

GIT_COMMIT="$(git -C "$ROOT_DIR" rev-parse --short=12 HEAD 2>/dev/null || echo unknown)"
BUILD_DATE_UTC="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

echo "[4/4] Launching Hush…"
nohup open "$APP_BUNDLE" >"$LOG_FILE" 2>&1 &

sleep 2
PID="$(pgrep -f "Hush-Dev.app/Contents/MacOS/Hush" | head -n 1 || true)"

echo "  pid: ${PID:-unknown}"
echo "  bundle: $APP_BUNDLE"
echo "  commit: $GIT_COMMIT"
echo "  built-at: $BUILD_DATE_UTC"
echo "  log: $LOG_FILE"
