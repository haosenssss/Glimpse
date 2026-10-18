#!/usr/bin/env bash
# Builds a distributable build/Glimpse-<version>.zip.
#
# Release builds are signed ad-hoc on purpose: a personal "Apple Development"
# certificate would embed its holder's name and team ID in the public download,
# and it isn't accepted by Gatekeeper on other Macs anyway.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$ROOT/Resources/Info.plist")"
ZIP="$ROOT/build/Glimpse-$VERSION.zip"

GLIMPSE_SIGN_IDENTITY="-" "$ROOT/scripts/build-app.sh"

if codesign -dvv "$ROOT/build/Glimpse.app" 2>&1 | grep -q "^Authority="; then
    echo "error: release build carries a signing identity" >&2
    exit 1
fi

rm -f "$ZIP"
ditto -c -k --keepParent "$ROOT/build/Glimpse.app" "$ZIP"
echo "Packaged $ZIP"
shasum -a 256 "$ZIP"
