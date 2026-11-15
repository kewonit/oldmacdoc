#!/bin/bash
# Captures the website screenshots from the running app: your own dock, as the app shows it, on a
# transparent background (the dock's window on its own, so no wallpaper or other windows are in the
# shots). Needs a Debug build running (make run) and cwebp (brew install webp).
#
# Nothing is launched, quit, moved or clicked. The dock is driven through its Debug commands, and
# your settings are put back afterwards.
#
# Usage: scripts/website/capture.sh [output folder, default website/assets]
# Options, as environment variables (points, on the main display):
#   HERO_X    where the pointer rests for the hero shot (default: the middle of the display)
#   FINISH_ICONS  how many icons the icon-finish close-ups show, from the middle of the dock (default 8)
#   KEEP      a folder to keep the uncropped captures in, for checking the crops
set -euo pipefail
cd "$(dirname "$0")/../.."

OUT=${1:-website/assets}
SUPPORT="$HOME/Library/Application Support/OldMacDoc"
TOOLS=build/website-tools
WORK=$(mktemp -d)
pgrep -qf "Debug/OldMacDoc.app/Contents/MacOS/OldMacDoc" || { echo "Run a Debug build first: make run"; exit 1; }
command -v cwebp >/dev/null || { echo "Needs cwebp: brew install webp"; exit 1; }
mkdir -p "$OUT" "$TOOLS"
for tool in send dockwindow images; do swiftc -O -o "$TOOLS/$tool" "scripts/website/$tool.swift"; done
send() { "$TOOLS/send" "$@"; }

# Main display width in points.
W=$(osascript -l JavaScript -e 'ObjC.import("AppKit"); Math.round($.NSScreen.screens.objectAtIndex(0).frame.size.width)')
HERO_X=${HERO_X:-$((W / 2))}

# The settings the Debug commands change, to put back afterwards (defaults when there's no file).
setting() { plutil -extract "$1" raw -o - "$SUPPORT/settings.json" 2>/dev/null || echo "$2"; }
STYLE=$(setting shelfStyle clear); FINISH=$(setting finish full); SIZE=$(setting iconSize 56)
[ -f "$SUPPORT/settings.json" ] && cp "$SUPPORT/settings.json" "$WORK/settings.json"
restore() {
    send style "$STYLE"; send finish "$FINISH"; send size "$SIZE"
    # Let go, and bring the dock up: in auto-hide it then slides away by itself, as usual.
    send pointer; send hold off; send reveal
    sleep 1.5 # the app saves settings after a short pause; put the file back after that
    if [ -f "$WORK/settings.json" ]; then cp "$WORK/settings.json" "$SUPPORT/settings.json"; else rm -f "$SUPPORT/settings.json"; fi
    if [ -n "${KEEP:-}" ]; then mkdir -p "$KEEP" && cp "$WORK"/*.png "$KEEP"/ 2>/dev/null || true; fi
    rm -rf "$WORK"
}
trap restore EXIT

DOCK=$("$TOOLS/dockwindow")
send hold on
send reveal
send finish full
sleep 2.5
shoot() { screencapture -x -o -l"$DOCK" "$WORK/$1.png"; } # the dock window alone, with its transparency

# Turns a cropped capture into a WebP with transparency, at most 2400 px across.
webp() {
    local src="$WORK/$1.crop.png"
    [ "$(sips -g pixelWidth "$src" | awk '/pixelWidth/{print $2}')" -gt 2400 ] && sips --resampleWidth 2400 "$src" >/dev/null
    cwebp -quiet -q 90 -alpha_q 100 -m 6 -sharp_yuv "$src" -o "$OUT/$2.webp"
    echo "$OUT/$2.webp: $(sips -g pixelWidth -g pixelHeight "$src" | awk '/pixel/{printf "%s ", $2}')"
}

# Hero: the dock magnified under the pointer, with the app's name above it.
send pointer "$HERO_X"; sleep 1.2
shoot hero
send pointer; send hold on; sleep 1

# The three shelves at rest.
for style in clear frosted smoke; do
    send style $style; sleep 2.5
    shoot "shelf-$style"
done
send style clear; sleep 1.5

# The icon finish, off and full.
send finish off; sleep 3; shoot finish-off
send finish full; sleep 3; shoot finish-full

# Crop to the dock (the shelves together, so they line up), then convert.
"$TOOLS/images" crop 8 - - "$WORK/hero.png" >/dev/null
"$TOOLS/images" crop 8 - - "$WORK"/shelf-{clear,frosted,smoke}.png >/dev/null
# The close-ups keep whole icons: found along a row through them, above the shelf (Clear Glass icons
# stand 0.36 × the icon size up; the row is 0.8 × the size above that, in Retina pixels).
ROW=$(awk -v s="$SIZE" 'BEGIN { printf "%d", (int(0.36 * s + 0.5) + 0.8 * s) * 2 }')
read -r FX FW < <("$TOOLS/images" icons "$WORK/finish-full.png" "$ROW" "${FINISH_ICONS:-8}")
"$TOOLS/images" crop 8 "$FX" "$FW" "$WORK"/finish-{off,full}.png >/dev/null
# Link preview, 1200 × 630: services don't all show transparency, so the dock sits on the site's black.
"$TOOLS/images" card "$WORK/hero.crop.png" "$WORK/og.png" 1200 630 0 0 0
sips -s format jpeg -s formatOptions 85 "$WORK/og.png" --out "$OUT/og.jpg" >/dev/null
webp hero hero
for style in clear frosted smoke; do webp "shelf-$style" "shelf-$style"; done
webp finish-off finish-off
webp finish-full finish-full
echo "Screenshots written to $OUT"
