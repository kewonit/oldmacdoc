#!/bin/bash
# Builds OldMacDoc's disk image around a signed app, checks what went into it, then signs, notarizes
# and staples it. scripts/release.sh calls it; it can also rebuild the DMG of an existing release.
#
# Usage: scripts/dmg/build.sh <OldMacDoc.app> <out.dmg> [notary profile]
#        scripts/dmg/build.sh --prepare     only make sure dmgbuild is ready (release.sh checks early)
#
# dmgbuild lays out the window (settings.py, over background.png from `make dmg-background`) by
# writing it straight into the image, without scripting Finder. It lives in its own Python
# environment under build/, installed by hash from requirements.txt, and is set up again whenever
# that file changes or the environment stops running (a moved folder, a replaced Python).
set -euo pipefail
cd "$(dirname "$0")/../.."

VENV=build/dmgbuild-venv
REQUIREMENTS=scripts/dmg/requirements.txt
DMGBUILD=$VENV/bin/dmgbuild

prepare() {
  local want
  want=$(shasum -a 256 "$REQUIREMENTS" | cut -d' ' -f1)
  if [ "$(cat "$VENV/.requirements.sha256" 2>/dev/null)" = "$want" ] && "$DMGBUILD" --help >/dev/null 2>&1; then
    return
  fi
  echo "Setting up dmgbuild…"
  rm -rf "$VENV"
  python3 -m venv "$VENV"
  "$VENV/bin/pip" install -q --disable-pip-version-check --require-hashes --only-binary=:all: --no-deps \
    -r "$REQUIREMENTS"
  "$DMGBUILD" --help >/dev/null
  echo "$want" > "$VENV/.requirements.sha256"
}

if [ "${1:-}" = --prepare ]; then
  prepare
  exit
fi

USAGE="usage: scripts/dmg/build.sh <OldMacDoc.app> <out.dmg> [notary profile]"
APP=${1:?$USAGE}
OUT=${2:?$USAGE}
PROFILE=${3:-oldmacdoc-notary}
NAME=$(basename "$APP")
prepare

rm -f "$OUT"
"$DMGBUILD" --detach-retries 30 -s scripts/dmg/settings.py -D app="$APP" OldMacDoc "$OUT" >/dev/null

# Check what went in before anything is signed: dmgbuild doesn't notice when copying the app fails,
# and an empty image would notarize just fine.
MNT=$(mktemp -d)
trap 'hdiutil detach -quiet "$MNT" 2>/dev/null; rmdir "$MNT" 2>/dev/null' EXIT
hdiutil attach -quiet -nobrowse -noautoopen -readonly -mountpoint "$MNT" "$OUT"
fail() { echo "The disk image is wrong: $1" >&2; exit 1; }
build() { /usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$1/Contents/Info.plist"; }
codesign --verify --deep --strict "$MNT/$NAME" || fail "$NAME inside doesn't pass a strict signature check."
[ "$(build "$MNT/$NAME")" = "$(build "$APP")" ] || fail "$NAME inside isn't the build it was made from."
[ "$(readlink "$MNT/Applications")" = /Applications ] || fail "the Applications shortcut is missing."
if xattr -p com.apple.FinderInfo "$MNT/$NAME" >/dev/null 2>&1; then
  fail "$NAME carries Finder information, which breaks its signature."
fi
hdiutil detach -quiet "$MNT"
rmdir "$MNT"
trap - EXIT

codesign --sign "Developer ID Application" --timestamp "$OUT"
xcrun notarytool submit "$OUT" --keychain-profile "$PROFILE" --wait
xcrun stapler staple "$OUT"
spctl -a -vvv -t install "$OUT"
