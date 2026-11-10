#!/bin/bash
# Builds build/Natkeys.app from the Swift package (no Xcode needed).
#
#   UNIVERSAL=1   build one app for both Apple silicon and Intel Macs (used for releases)
#   VERSION=1.2.0 set the version shown in Finder and Settings (default: Info.plist's)
#   NATKEYS_SIGN_IDENTITY="…"  sign with this certificate instead of the automatic choice
set -euo pipefail
cd "$(dirname "$0")/.."

CONFIG="${CONFIG:-release}"
APP="build/Natkeys.app"
MIN_MACOS="14.0"

if [ "${UNIVERSAL:-0}" = "1" ]; then
    SLICES=()
    for ARCH in arm64 x86_64; do
        echo "▸ Compiling ($CONFIG, $ARCH)…"
        swift build -c "$CONFIG" --product Natkeys --triple "$ARCH-apple-macosx$MIN_MACOS"
        SLICES+=("$(swift build -c "$CONFIG" --triple "$ARCH-apple-macosx$MIN_MACOS" --show-bin-path)/Natkeys")
    done
    BINARY="build/Natkeys-universal"
    mkdir -p build
    lipo -create "${SLICES[@]}" -output "$BINARY"
else
    echo "▸ Compiling ($CONFIG)…"
    swift build -c "$CONFIG" --product Natkeys
    BINARY="$(swift build -c "$CONFIG" --show-bin-path)/Natkeys"
fi

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
cp "$BINARY" "$APP/Contents/MacOS/Natkeys"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
# Stamp each build with its own build number (yymmdd.HHMM), shown in Settings → General → Version,
# so it's easy to tell which build is installed.
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $(date +%y%m%d.%H%M)" "$APP/Contents/Info.plist"
if [ -n "${VERSION:-}" ]; then
    /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$APP/Contents/Info.plist"
fi

# Which certificate signs the app:
#   1. NATKEYS_SIGN_IDENTITY, if set
#   2. an Apple "Developer ID Application" certificate, if you have one (needed for notarizing)
#   3. the self-made "Natkeys Local" certificate (keeps the Accessibility permission across
#      rebuilds and updates)
#   4. otherwise ad hoc
# (No -v: a self-made certificate is "not trusted", which is fine for signing your own app.)
IDENTITY="${NATKEYS_SIGN_IDENTITY:-}"
IDENTITIES="$(security find-identity -p codesigning 2>/dev/null || true)"
if [ -z "$IDENTITY" ]; then
    IDENTITY="$(echo "$IDENTITIES" | sed -n 's/.*"\(Developer ID Application: [^"]*\)".*/\1/p' | head -1)"
fi
if [ -z "$IDENTITY" ] && echo "$IDENTITIES" | grep -q "\"Natkeys Local\""; then
    IDENTITY="Natkeys Local"
fi
SIGN_FLAGS=(--force --deep)
if [[ "$IDENTITY" == "Developer ID Application:"* ]]; then
    # Notarization requires the hardened runtime and a secure timestamp.
    SIGN_FLAGS+=(--options runtime --timestamp)
fi
echo "▸ Signing (${IDENTITY:-ad hoc})…"
codesign "${SIGN_FLAGS[@]}" --sign "${IDENTITY:--}" "$APP"

echo "✓ Built $APP"
