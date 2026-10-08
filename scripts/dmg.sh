#!/bin/sh
# Wrap AntigravityHub.app into a drag-to-Applications DMG with e-paper background.
#
#   ./scripts/dmg.sh                package ./build/AntigravityHub.app or ./dist/AntigravityHub.app
#   ./scripts/dmg.sh --app PATH     use an app at PATH
#
# Output: ./dist/AntigravityHub-<version>.dmg

set -eu

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DIST="$ROOT/dist"
DEST_APP="$DIST/AntigravityHub.app"
BACKGROUND="$ROOT/Resources/dmg/background.png"
VOLUME_NAME="Antigravity Hub"

# ----- Find the .app ---------------------------------------------------

if [ "${1:-}" = "--app" ] && [ -n "${2:-}" ]; then
    DEST_APP="$2"
    shift 2
elif [ ! -d "$DEST_APP" ]; then
    if [ -d "$ROOT/build/AntigravityHub.app" ]; then
        DEST_APP="$ROOT/build/AntigravityHub.app"
    else
        echo "==> Building app first..."
        "$ROOT/build.sh"
        DEST_APP="$ROOT/build/AntigravityHub.app"
    fi
fi

if [ ! -f "$BACKGROUND" ]; then
    echo "❌ Background image missing at $BACKGROUND" >&2
    exit 1
fi

VERSION="$(plutil -extract CFBundleShortVersionString raw -o - "$DEST_APP/Contents/Info.plist" 2>/dev/null \
    || defaults read "$DEST_APP/Contents/Info.plist" CFBundleShortVersionString 2>/dev/null \
    || echo "0.2.0")"
DMG_PATH="$DIST/AntigravityHub-$VERSION.dmg"
DMG_TEMP="$(mktemp -t antigravityhub-dmg-tmp).dmg"
STAGING="$(mktemp -d -t antigravityhub-stage)"
MOUNT_DIR="$(mktemp -d -t antigravityhub-mount)"

cleanup() {
    hdiutil detach "$MOUNT_DIR" -force -quiet 2>/dev/null || true
    rm -rf "$STAGING" "$MOUNT_DIR" "$DMG_TEMP"
}
trap cleanup EXIT

mkdir -p "$DIST"
rm -f "$DMG_TEMP" "$DMG_PATH"

# ----- Stage contents into temporary directory -------------------------

echo "==> Staging contents into temporary bundle"
cp -R "$DEST_APP" "$STAGING/Antigravity Hub.app"
ln -s /Applications "$STAGING/Applications"
mkdir -p "$STAGING/.background"
cp "$BACKGROUND" "$STAGING/.background/background.png"

# ----- Create read-write temporary DMG ---------------------------------

echo "==> Creating read-write disk image"
hdiutil create \
    -srcfolder "$STAGING" \
    -volname "$VOLUME_NAME" \
    -fs HFS+ \
    -format UDRW \
    -ov \
    "$DMG_TEMP" >/dev/null

hdiutil detach "/Volumes/$VOLUME_NAME" -force -quiet 2>/dev/null || true
ATTACH_OUT="$(hdiutil attach -readwrite -noverify -noautoopen "$DMG_TEMP")"
DEVICE="$(echo "$ATTACH_OUT" | awk 'NR==1{print $1}')"
MOUNT_DIR="/Volumes/$VOLUME_NAME"

# ----- Configure Finder layout -----------------------------------------

echo "==> Configuring Finder window layout & e-paper background"
osascript <<APPLESCRIPT || true
tell application "Finder"
    tell disk "$VOLUME_NAME"
        open
        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        set pathbar visible of container window to false
        set the bounds of container window to {160, 110, 800, 560} -- 640 x 450 (content 640 x 420)
        set theViewOptions to icon view options of container window
        set arrangement of theViewOptions to not arranged
        set icon size of theViewOptions to 96
        set background picture of theViewOptions to file ".background:background.png"
        set position of item "Antigravity Hub.app" of container window to {160, 180}
        set position of item "Applications" of container window to {480, 180}
        update without registering applications
        delay 1
        close
    end tell
end tell
APPLESCRIPT

sync
sleep 2

# ----- Detach and compress ----------------------------------------------

echo "==> Finalizing and compressing DMG"
hdiutil detach "$DEVICE" -quiet 2>/dev/null || hdiutil detach "$MOUNT_DIR" -force -quiet 2>/dev/null || true
rm -rf "$MOUNT_DIR"

hdiutil convert "$DMG_TEMP" -format UDZO -imagekey zlib-level=9 -o "$DMG_PATH" >/dev/null
rm -f "$DMG_TEMP"

# ----- Code sign DMG if identity is available ---------------------------

IDENTITY="${IDENTITY:-$(security find-identity -p codesigning -v 2>/dev/null \
    | awk -F'"' '/Developer ID Application/ {print $2; exit}')}"
if [ -n "$IDENTITY" ]; then
    echo "==> Signing DMG with Developer ID ($IDENTITY)"
    codesign --force --sign "$IDENTITY" --timestamp "$DMG_PATH"
else
    echo "==> Developer ID identity not found in keychain, skipping DMG signing"
fi

echo "==> Done. DMG built at: $DMG_PATH"
echo "    Size: $(du -h "$DMG_PATH" | cut -f1)"
echo "    Verify with: hdiutil mount \"$DMG_PATH\""

# ----- Sparkle Appcast Generation ---------------------------------------
KEY_FILE="${SPARKLE_KEY_FILE:-$HOME/.antigravity-hub-keys/sparkle_ed25519_priv.key}"
if [ -f "$KEY_FILE" ] && [ -x "$ROOT/scripts/sparkle/generate_appcast" ]; then
    echo "==> Generating Sparkle appcast.xml"
    DOWNLOAD_PREFIX="${DOWNLOAD_PREFIX:-https://github.com/XideaDev/Antigravity-Hub/releases/download/v$VERSION/}"
    "$ROOT/scripts/sparkle/generate_appcast" \
        --ed-key-file "$KEY_FILE" \
        --download-url-prefix "$DOWNLOAD_PREFIX" \
        -o "$ROOT/appcast.xml" \
        "$DIST"
    echo "==> Sparkle appcast updated at: $ROOT/appcast.xml"
fi
