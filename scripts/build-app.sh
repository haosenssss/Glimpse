#!/usr/bin/env bash
# Builds Glimpse.app into ./build.
#
# If icon/AppIcon.png or icon/AppIcon.jpg exists (square artwork, 1024px or larger), it is
# fitted into the macOS icon shape and bundled as AppIcon.icns.
#
# Signs with the first "Apple Development" identity (override with
# GLIMPSE_SIGN_IDENTITY). A stable identity matters: macOS ties Accessibility and
# Screen Recording grants to the signature, so ad-hoc builds lose them on every rebuild.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CONFIG="${1:-release}"
APP="$ROOT/build/Glimpse.app"
ARTWORK="$(ls "$ROOT"/icon/AppIcon.{png,jpg,jpeg} 2>/dev/null | head -n 1 || true)"

"$ROOT/scripts/spm.sh" build -c "$CONFIG" --product Glimpse
BIN_DIR="$("$ROOT/scripts/spm.sh" build -c "$CONFIG" --product Glimpse --show-bin-path)"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/Glimpse" "$APP/Contents/MacOS/Glimpse"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"

build_icon() {
    local work="$ROOT/.build/icon"
    local iconset="$work/AppIcon.iconset"
    rm -rf "$work"
    mkdir -p "$iconset"

    "$ROOT/scripts/spm.sh" build -c release --product MakeIcon
    "$("$ROOT/scripts/spm.sh" build -c release --product MakeIcon --show-bin-path)/MakeIcon" "$ARTWORK" "$work/icon-1024.png"

    local size
    for size in 16 32 128 256 512; do
        sips -z "$size" "$size" "$work/icon-1024.png" --out "$iconset/icon_${size}x${size}.png" >/dev/null
        sips -z $((size * 2)) $((size * 2)) "$work/icon-1024.png" --out "$iconset/icon_${size}x${size}@2x.png" >/dev/null
    done
    iconutil -c icns "$iconset" -o "$APP/Contents/Resources/AppIcon.icns"
}

if [[ -n "$ARTWORK" ]]; then
    build_icon
else
    echo "note: no icon/AppIcon.png or .jpg; building without an app icon" >&2
fi

IDENTITY="${GLIMPSE_SIGN_IDENTITY:-$(security find-identity -v -p codesigning | awk -F'"' '/Apple Development/ { print $2; exit }')}"
if [[ -n "$IDENTITY" ]]; then
    codesign --force --sign "$IDENTITY" "$APP"
else
    echo "warning: no Apple Development identity found; signing ad-hoc (permissions reset on each rebuild)" >&2
    codesign --force --sign - "$APP"
fi

codesign --verify --verbose=1 "$APP"
echo "Built $APP"
