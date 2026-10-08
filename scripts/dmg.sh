#!/bin/sh
# Wrap a signed AntigravityHub.app into a drag-to-Applications DMG.
#
#   ./scripts/dmg.sh                build + sign the .app first, then package
#   ./scripts/dmg.sh --app PATH     use an already-signed .app at PATH
#
# Output: ./dist/AntigravityHub-<version>.dmg
#
# The DMG layout matches what macOS Finder expects when the user opens it:
# a window 540x340 with the .app on the left, the Applications symlink on
# the right, and an arrow underneath the .app pointing at the symlink.
#
# The background is an e-ink-style image at Resources/dmg/background.png
# that the user can later swap for a brand-coloured variant.

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
    echo "❌ $DEST_APP not found. Run ./scripts/sign.sh first, or pass --app PATH." >&2
    exit 1
fi

if [ ! -f "$BACKGROUND" ]; then
    echo "❌ Background image missing at $BACKGROUND" >&2
    exit 1
fi

VERSION="$(/usr/bin/defaults read "$DEST_APP/Contents/Info.plist" CFBundleShortVersionString 2>/dev/null \
    || echo "0.0.0")"
DMG_PATH="$DIST/AntigravityHub-$VERSION.dmg"

# ----- Stage a temporary read-write bundle -----------------------------

STAGING="$(mktemp -d -t antigravityhub-dmg)"
trap 'rm -rf "$STAGING"' EXIT

cp -R "$DEST_APP" "$STAGING/AntigravityHub.app"
ln -s /Applications "$STAGING/Applications"
mkdir -p "$STAGING/.background"
cp "$BACKGROUND" "$STAGING/.background/background.png"

# ----- Build the DMG ----------------------------------------------------

echo "==> Building DMG"
rm -f "$DMG_PATH"

# - UDRO: read-only UDIF (default since 10.5)
# - fs HFS+: required for the .DS_Store + custom background to work
# - format UDZO: compressed read-only
hdiutil create \
    -volname "$VOLUME_NAME" \
    -srcfolder "$STAGING" \
    -fs HFS+ \
    -fsargs "-c c=64,a=16,e=16" \
    -format UDZO \
    -norecurse \
    "$DMG_PATH"

# ----- Stamp the visual layout -----------------------------------------
# hdiutil attach -> set .DS_Store window geometry -> detach

echo "==> Stamping window layout"
MOUNT="$(mktemp -d -t antigravityhub-mount)"
trap 'rm -rf "$STAGING" "$MOUNT"' EXIT

hdiutil attach -nobrowse -quiet -mountpoint "$MOUNT" "$DMG_PATH"

# Finder writes its window geometry into .DS_Store when the volume opens.
# AppleScript lays out a 540x340 window with the .app at (130, 160) and
# Applications symlink at (380, 160), background image behind both.
osascript <<APPLESCRIPT
tell application "Finder"
    tell disk "$VOLUME_NAME"
        open
        delay 1
        set theBounds to {0, 0, 540, 340}
        set theWindowBounds to bounds of front window
        set bounds of front window to {0, 0, 540, 340}
        set position of item "AntigravityHub.app" to {130, 160}
        set position of item "Applications" to {380, 160}
        set background view options to {2}
        update without registering applications
    end tell
    delay 1
end tell
APPLESCRIPT

# Some Finder versions need a moment to flush .DS_Store before we detach.
sync
sleep 1
hdiutil detach -quiet "$MOUNT"

# ----- Optional: code sign the DMG itself -------------------------------

IDENTITY="$(security find-identity -p codesigning -v 2>/dev/null \
    | awk -F'"' '/Developer ID Application/ {print $2; exit}')"
if [ -n "$IDENTITY" ]; then
    echo "==> Signing DMG"
    codesign --force --sign "$IDENTITY" --timestamp "$DMG_PATH"
fi

echo "==> Done. $DMG_PATH"
echo "    Open with: open \"$DMG_PATH\""
