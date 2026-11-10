#!/bin/bash
# Builds the downloadable Natkeys-<version>.dmg to attach to a GitHub Release.
#
#   ./scripts/release.sh 1.0.0
#
# The app runs on Apple silicon and Intel Macs (macOS 14 or later).
#
# Signing: with an Apple "Developer ID Application" certificate in your keychain, the app is
# signed for notarization. If NOTARY_PROFILE names a saved notarytool profile
# (xcrun notarytool store-credentials <name> …), the disk image is also sent to Apple, notarized,
# and stapled, so it opens with no warning. Without a Developer ID, it is signed with
# "Natkeys Local", and people open it the first time with System Settings → Privacy & Security →
# Open Anyway (the README explains this).
#
# Output goes to build/release/: the .dmg, its SHA-256 checksum, and draft release notes.
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${1:-}"
if ! [[ "$VERSION" =~ ^[0-9]+\.[0-9]+(\.[0-9]+)?$ ]]; then
    echo "Usage: ./scripts/release.sh <version>   (for example 1.0.0)" >&2
    exit 1
fi

UNIVERSAL=1 VERSION="$VERSION" ./scripts/build-app.sh

APP="build/Natkeys.app"
OUT="build/release"
DMG="$OUT/Natkeys-$VERSION.dmg"
rm -rf "$OUT"
mkdir -p "$OUT/stage"

echo "▸ Making $DMG…"
ditto "$APP" "$OUT/stage/Natkeys.app"
ln -s /Applications "$OUT/stage/Applications"
hdiutil create -quiet -volname "Natkeys $VERSION" -srcfolder "$OUT/stage" -fs HFS+ -format UDZO -ov "$DMG"
rm -rf "$OUT/stage"

AUTHORITY="$(codesign -dvv "$APP" 2>&1 | sed -n 's/^Authority=//p' | head -1)"
NOTARIZED="no"
if [[ "$AUTHORITY" == "Developer ID Application:"* ]]; then
    codesign --force --timestamp --sign "$AUTHORITY" "$DMG"
    if [ -n "${NOTARY_PROFILE:-}" ]; then
        echo "▸ Notarizing with Apple (this can take a few minutes)…"
        xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
        xcrun stapler staple "$DMG"
        NOTARIZED="yes"
    else
        echo "  (Set NOTARY_PROFILE to notarize. Without it, people still see the Open Anyway step.)"
    fi
fi

echo "▸ Checking the disk image…"
MOUNT="$(mktemp -d)"
hdiutil attach -quiet -nobrowse -readonly -mountpoint "$MOUNT" "$DMG"
ARCHS="$(lipo -archs "$MOUNT/Natkeys.app/Contents/MacOS/Natkeys")"
codesign --verify --strict "$MOUNT/Natkeys.app"
SHOWN_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$MOUNT/Natkeys.app/Contents/Info.plist")"
hdiutil detach -quiet "$MOUNT"
rmdir "$MOUNT" 2>/dev/null || true
[ "$SHOWN_VERSION" = "$VERSION" ] || { echo "Version in the app is $SHOWN_VERSION, expected $VERSION" >&2; exit 1; }

SHA="$(shasum -a 256 "$DMG" | awk '{print $1}')"
echo "$SHA  Natkeys-$VERSION.dmg" > "$DMG.sha256"
SIZE="$(du -h "$DMG" | awk '{print $1}')"

if [ "$NOTARIZED" = "yes" ]; then
    FIRST_OPEN="Open the disk image, drag **Natkeys** into **Applications**, and open it."
else
    FIRST_OPEN="Open the disk image and drag **Natkeys** into **Applications**. The first time you open it, macOS says it can't check Natkeys for malware, because the app isn't notarized by Apple. Click **Done**, then go to **System Settings → Privacy & Security**, scroll down to the message about Natkeys, click **Open Anyway**, and confirm. You only do this once."
fi

cat > "$OUT/release-notes.md" <<EOF
## Install

1. Download **Natkeys-$VERSION.dmg** below.
2. $FIRST_OPEN
3. When asked, allow Natkeys under **Accessibility** so it can read selected text and paste for you.
4. Press **Option+Space** in any app.

Requires macOS 14 Sonoma or later, on Apple silicon or Intel.

SHA-256: \`$SHA\`
EOF

echo
echo "✓ $DMG ($SIZE, $ARCHS, signed by ${AUTHORITY:-ad hoc}, notarized: $NOTARIZED)"
echo "  Release notes draft: $OUT/release-notes.md"
