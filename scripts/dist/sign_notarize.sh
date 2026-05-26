#!/usr/bin/env bash
set -euo pipefail

# Sign Hush.app and optionally produce a DMG.
#
# For local/unsigned builds, the default ad-hoc signing identity ("-") is used.
# For distribution, set SIGN_IDENTITY to your Developer ID certificate and
# provide NOTARYTOOL_PROFILE for notarization.
#
# Prereqs (for notarized distribution only):
# - Developer ID Application certificate installed in Keychain.
# - notarytool credentials stored in Keychain:
#     xcrun notarytool store-credentials "$NOTARYTOOL_PROFILE" --apple-id ... --team-id ... --password ...
#
# Environment variables:
#   APP_NAME              (default: Hush)
#   DIST_DIR              (default: ./dist)
#   SIGN_IDENTITY         (default: - [ad-hoc, local use only])
#   NOTARYTOOL_PROFILE    (required to notarize)
#   SKIP_NOTARIZE         (default: 1) set to 0 to enable notarization
#   CREATE_DMG            (default: 1)
#
# Outputs:
#   dist/Hush.app (signed)
#   dist/Hush.dmg (if CREATE_DMG=1)

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
APP_NAME="${APP_NAME:-Hush}"
DIST_DIR="${DIST_DIR:-$ROOT_DIR/dist}"
APP_PATH="$DIST_DIR/${APP_NAME}.app"

SIGN_IDENTITY="${SIGN_IDENTITY:--}"
NOTARYTOOL_PROFILE="${NOTARYTOOL_PROFILE:-AC_PASSWORD}"
SKIP_NOTARIZE="${SKIP_NOTARIZE:-1}"
CREATE_DMG="${CREATE_DMG:-1}"

if [[ ! -d "$APP_PATH" ]]; then
  echo "Missing app bundle: $APP_PATH" >&2
  echo "Run: $ROOT_DIR/scripts/dist/build_app_bundle.sh" >&2
  exit 1
fi

echo "[1/5] Clearing extended attributes…"
xattr -cr "$APP_PATH" || true

echo "[2/5] Signing helper binaries…"
# Sign helper binaries under Resources (e.g. ffmpeg).
while IFS= read -r -d '' bin; do
  echo "Signing: $(basename "$bin")"
  codesign --force --sign "$SIGN_IDENTITY" --options runtime --timestamp "$bin"
done < <(
  find "$APP_PATH/Contents/Resources" -maxdepth 1 -type f -perm -111 \
    -name "ffmpeg" -print0 2>/dev/null || true
)

ENTITLEMENTS="$ROOT_DIR/scripts/dist/Hush.entitlements"

echo "[3/5] Codesigning app (hardened runtime + entitlements)…"
codesign --force --sign "$SIGN_IDENTITY" --options runtime --timestamp \
  --entitlements "$ENTITLEMENTS" "$APP_PATH"

echo "[4/5] Verifying signature…"
codesign --verify --deep --strict --verbose=2 "$APP_PATH"

if [[ "$SKIP_NOTARIZE" != "1" ]]; then
  ZIP_PATH="$DIST_DIR/${APP_NAME}.app.zip"
  rm -f "$ZIP_PATH"

  echo "[5/5] Notarizing…"
  ditto -c -k --keepParent "$APP_PATH" "$ZIP_PATH"

  # Submit without --wait (crashes with bus error on macOS 15+), then poll.
  SUBMIT_OUT=$(xcrun notarytool submit "$ZIP_PATH" --keychain-profile "$NOTARYTOOL_PROFILE" 2>&1)
  echo "$SUBMIT_OUT"
  SUBMISSION_ID=$(echo "$SUBMIT_OUT" | grep '  id:' | head -1 | awk '{print $2}')
  if [[ -z "$SUBMISSION_ID" ]]; then
    echo "Error: Failed to extract submission ID"
    exit 1
  fi
  echo "Polling notarization status for $SUBMISSION_ID..."
  while true; do
    STATUS=$(xcrun notarytool info "$SUBMISSION_ID" --keychain-profile "$NOTARYTOOL_PROFILE" 2>&1)
    if echo "$STATUS" | grep -q "status: Accepted"; then
      echo "Notarization accepted!"
      break
    elif echo "$STATUS" | grep -q "status: Invalid"; then
      echo "Notarization REJECTED:"
      echo "$STATUS"
      exit 1
    fi
    sleep 15
  done

  echo "Stapling app…"
  xcrun stapler staple "$APP_PATH"
  xcrun stapler validate "$APP_PATH"

  echo "Gatekeeper assess…"
  spctl --assess --type execute --verbose=4 "$APP_PATH" || true
else
  echo "[5/5] Skipping notarization (SKIP_NOTARIZE=1)."
  echo "  To notarize, set SKIP_NOTARIZE=0, SIGN_IDENTITY, and NOTARYTOOL_PROFILE."
fi

if [[ "$CREATE_DMG" == "1" ]]; then
  DMG_PATH="$DIST_DIR/${APP_NAME}.dmg"
  rm -f "$DMG_PATH"

  echo "Creating DMG…"
  # Stage a folder with the app + Applications symlink for drag-to-install experience.
  DMG_STAGING="$DIST_DIR/.dmg-staging"
  DMG_RW="$DIST_DIR/${APP_NAME}-rw.dmg"
  rm -rf "$DMG_STAGING" "$DMG_RW"
  mkdir -p "$DMG_STAGING"
  cp -R "$APP_PATH" "$DMG_STAGING/"
  ln -s /Applications "$DMG_STAGING/Applications"

  # Create a read-write DMG first so we can customize the Finder layout.
  hdiutil create -volname "$APP_NAME" -srcfolder "$DMG_STAGING" -ov -format UDRW "$DMG_RW" >/dev/null
  rm -rf "$DMG_STAGING"

  # Mount and apply Finder layout: app on left, Applications on right.
  # hdiutil output is tab-delimited; mount points may contain spaces.
  ATTACH_OUTPUT="$(hdiutil attach "$DMG_RW" -nobrowse -noverify 2>&1)" || true
  MOUNT_DIR="$(echo "$ATTACH_OUTPUT" | tail -1 | awk -F '\t' 'NF>=3 {print $3}')"
  # Extract the /dev/diskN device so we can always detach, even if mount-point parsing fails.
  ATTACH_DEV="$(echo "$ATTACH_OUTPUT" | head -1 | awk '{print $1}')"
  if [[ -z "$MOUNT_DIR" || ! -d "$MOUNT_DIR" ]]; then
    echo "Warning: Failed to mount DMG for layout customization; skipping."
    # Detach whatever was partially attached so hdiutil convert can access the file.
    [[ -n "$ATTACH_DEV" ]] && hdiutil detach "$ATTACH_DEV" -quiet 2>/dev/null || true
  else
    OSA_OK=0

    if command -v timeout >/dev/null 2>&1; then
      timeout 30 osascript <<APPLESCRIPT && OSA_OK=1 || true
tell application "Finder"
  tell disk "$APP_NAME"
    open
    set current view of container window to icon view
    set toolbar visible of container window to false
    set statusbar visible of container window to false
    set bounds of container window to {120, 120, 900, 560}
    set opts to icon view options of container window
    set icon size of opts to 128
    set text size of opts to 14
    set arrangement of opts to not arranged
    set position of item "${APP_NAME}.app" of container window to {220, 260}
    set position of item "Applications" of container window to {560, 260}
    close
    open
    update without registering applications
    delay 2
    close
  end tell
end tell
APPLESCRIPT
    else
      echo "Notice: 'timeout' not found; running osascript without timeout."
      osascript <<APPLESCRIPT && OSA_OK=1 || true
tell application "Finder"
  tell disk "$APP_NAME"
    open
    set current view of container window to icon view
    set toolbar visible of container window to false
    set statusbar visible of container window to false
    set bounds of container window to {120, 120, 900, 560}
    set opts to icon view options of container window
    set icon size of opts to 128
    set text size of opts to 14
    set arrangement of opts to not arranged
    set position of item "${APP_NAME}.app" of container window to {220, 260}
    set position of item "Applications" of container window to {560, 260}
    close
    open
    update without registering applications
    delay 2
    close
  end tell
end tell
APPLESCRIPT
    fi

    if [[ "$OSA_OK" -eq 0 ]]; then
      echo "Warning: Finder layout customization failed; skipping."
    fi

    sync
    sleep 1
    hdiutil detach "$MOUNT_DIR" -quiet
  fi

  # Convert to compressed read-only DMG.
  hdiutil convert "$DMG_RW" -format UDZO -o "$DMG_PATH" >/dev/null
  rm -f "$DMG_RW"

  # Sign the DMG (ad-hoc is fine for local use).
  echo "Signing DMG…"
  codesign --force --sign "$SIGN_IDENTITY" --timestamp "$DMG_PATH"

  if [[ "$SKIP_NOTARIZE" != "1" ]]; then
    echo "Notarizing DMG…"
    DMG_SUBMIT_OUT=$(xcrun notarytool submit "$DMG_PATH" --keychain-profile "$NOTARYTOOL_PROFILE" 2>&1)
    echo "$DMG_SUBMIT_OUT"
    DMG_SUBMISSION_ID=$(echo "$DMG_SUBMIT_OUT" | grep '  id:' | head -1 | awk '{print $2}')
    if [[ -z "$DMG_SUBMISSION_ID" ]]; then
      echo "Error: Failed to extract DMG submission ID"
      exit 1
    fi
    echo "Polling DMG notarization status for $DMG_SUBMISSION_ID..."
    while true; do
      DMG_STATUS=$(xcrun notarytool info "$DMG_SUBMISSION_ID" --keychain-profile "$NOTARYTOOL_PROFILE" 2>&1)
      if echo "$DMG_STATUS" | grep -q "status: Accepted"; then
        echo "DMG notarization accepted!"
        break
      elif echo "$DMG_STATUS" | grep -q "status: Invalid"; then
        echo "DMG notarization REJECTED:"
        echo "$DMG_STATUS"
        exit 1
      fi
      sleep 15
    done

    echo "Stapling DMG…"
    xcrun stapler staple "$DMG_PATH"
    xcrun stapler validate "$DMG_PATH"
  fi

  echo "DMG created: $DMG_PATH"
fi

echo "Done."
