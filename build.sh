#!/bin/sh
# Build AntigravityHub.app — a macOS menu bar manager for Google Antigravity.
#
#   ./build.sh              compile + assemble ./build/AntigravityHub.app
#   ./build.sh --install    also copy to ~/Applications and launch it
#   ./build.sh --run        build then launch straight from ./build
#
# Requires the Xcode command line tools (xcrun swiftc). No other deps.

set -eu

ROOT="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="$ROOT/build"
APP="$BUILD_DIR/AntigravityHub.app"
BIN="AntigravityHub"
SWIFTC="${SWIFTC:-$(command -v swiftc || echo /usr/bin/swiftc)}"
TARGET_OS="${TARGET_OS:-14.0}"
ARCH="$(uname -m)"

echo "==> Compiling ($ARCH-apple-macos$TARGET_OS)"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

# -parse-as-library is required for @main to work under a bare swiftc build.
# -swift-version 5 keeps the code compiling cleanly without Swift 6 strict
# concurrency churn; flip to 6 once the store is properly actor-isolated.
# -disable-sandbox: SwiftUI's @State/@StateObject are external macros served by
# swift-plugin-server, which the compiler wraps in sandbox-exec. That wrapper
# fails with "sandbox_apply: Operation not permitted" inside restricted shells
# and CI, taking macro expansion down with it. The plugin is a local Xcode
# binary, so running it unsandboxed is fine.
mkdir -p /tmp/clang-cache

"$SWIFTC" \
	-O \
	-module-cache-path /tmp/clang-cache \
	-swift-version 5 \
	-parse-as-library \
	-disable-sandbox \
	-target "$ARCH-apple-macos$TARGET_OS" \
	-framework SwiftUI \
	-framework AppKit \
	-framework ServiceManagement \
	"$ROOT"/Sources/*.swift \
	-o "$APP/Contents/MacOS/$BIN"

echo "==> Assembling bundle"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
if [ -f "$ROOT/Resources/AppIcon.icns" ]; then
	cp "$ROOT/Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
fi
printf 'APPL????' > "$APP/Contents/PkgInfo"

IDENTITY="${IDENTITY:-$(security find-identity -p codesigning -v 2>/dev/null | awk -F'"' '/Developer ID Application/ {print $2; exit}')}"
if [ -n "$IDENTITY" ]; then
	echo "==> Signing (Developer ID: $IDENTITY)"
	codesign --force --options runtime --timestamp --sign "$IDENTITY" "$APP" >/dev/null 2>&1 \
		&& echo "    signed with Developer ID ($IDENTITY)" \
		|| echo "    signing failed"
else
	echo "==> Signing (ad-hoc)"
	codesign --force --sign - "$APP" >/dev/null 2>&1 \
		&& echo "    signed (ad-hoc)" \
		|| echo "    skipped (codesign unavailable)"
fi

echo "==> Built $APP"

case "${1:-}" in
	--install)
		DEST="$HOME/Applications/AntigravityHub.app"
		mkdir -p "$HOME/Applications"
		rm -rf "$DEST"
		cp -R "$APP" "$DEST"
		echo "==> Installed $DEST"
		open "$DEST"
		;;
	--run)
		open "$APP"
		;;
	*)
		echo "    Run with: open \"$APP\""
		;;
esac
