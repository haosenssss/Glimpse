#!/usr/bin/env bash
# Builds Glimpse and installs it to /Applications, replacing (and restarting) any running copy.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TARGET="/Applications/Glimpse.app"
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"

"$ROOT/scripts/build-app.sh"

osascript -e 'tell application id "com.haosen.glimpse" to quit' >/dev/null 2>&1 || true
pkill -x Glimpse >/dev/null 2>&1 || true

rm -rf "$TARGET"
cp -R "$ROOT/build/Glimpse.app" "$TARGET"
# Make Finder/Launchpad pick up a changed icon right away.
touch "$TARGET"
"$LSREGISTER" -f "$TARGET" >/dev/null 2>&1 || true

open "$TARGET"
echo "Installed $TARGET"
