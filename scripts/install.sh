#!/bin/bash
# Builds Natkeys, installs it to /Applications, and launches it.
set -euo pipefail
cd "$(dirname "$0")/.."

./scripts/build-app.sh

DEST="/Applications/Natkeys.app"
if pgrep -xq Natkeys; then
    echo "▸ Quitting the running copy…"
    osascript -e 'tell application id "io.github.allegedlynatalie.natkeys" to quit' >/dev/null 2>&1 || pkill -x Natkeys || true
    sleep 1
fi

echo "▸ Installing to $DEST…"
rm -rf "$DEST"
cp -R build/Natkeys.app "$DEST"

# Make macOS notice the app (and its right-click "Services" entries) right away.
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$DEST"
/System/Library/CoreServices/pbs -update

open "$DEST"
echo "✓ Natkeys is running. Press Option+Space."
