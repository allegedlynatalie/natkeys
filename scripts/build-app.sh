#!/bin/bash
# Builds build/Natkeys.app from the Swift package (no Xcode needed).
set -euo pipefail
cd "$(dirname "$0")/.."

CONFIG="${CONFIG:-release}"
APP="build/Natkeys.app"

echo "▸ Compiling ($CONFIG)…"
swift build -c "$CONFIG" --product Natkeys
BIN_DIR="$(swift build -c "$CONFIG" --show-bin-path)"

if [ ! -f Resources/AppIcon.icns ]; then
    echo "▸ Drawing app icon…"
    ICON_TOOL="$(mktemp -d)/make-icon"
    swiftc -O scripts/make-icon.swift -o "$ICON_TOOL"
    "$ICON_TOOL" Resources/AppIcon.iconset
    iconutil -c icns Resources/AppIcon.iconset -o Resources/AppIcon.icns
    rm -rf Resources/AppIcon.iconset
fi

echo "▸ Assembling $APP…"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/Natkeys" "$APP/Contents/MacOS/Natkeys"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
# Stamp each build with its own build number (yymmdd.HHMM), shown in Settings → General → Version,
# so it's easy to tell which build is installed.
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $(date +%y%m%d.%H%M)" "$APP/Contents/Info.plist"

# Sign with a stable local identity if you've made one (keeps the Accessibility
# permission across rebuilds); otherwise sign ad hoc.
IDENTITY="${NATKEYS_SIGN_IDENTITY:-}"
# (No -v: a self-made certificate is "not trusted", which is fine for signing your own app.)
if [ -z "$IDENTITY" ] && security find-identity -p codesigning 2>/dev/null | grep -q "\"Natkeys Local\""; then
    IDENTITY="Natkeys Local"
fi
echo "▸ Signing (${IDENTITY:-ad hoc})…"
codesign --force --deep --sign "${IDENTITY:--}" "$APP"

echo "✓ Built $APP"
