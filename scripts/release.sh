#!/bin/bash
# Builds a release: a universal app signed with the Developer ID, notarized and stapled; a notarized
# DMG; and a Sparkle update (zip + appcast with the release notes) for automatic updates. With
# PUBLISH=1 it uploads them as a draft GitHub release, to check and then publish. See docs/RELEASING.md.
#
# Usage: scripts/release.sh <version>          e.g. scripts/release.sh 1.0.0
#   PUBLISH=1        create the draft GitHub release v<version>
#   NOTARY_PROFILE   notarytool keychain profile (default oldmacdoc-notary)
#
# The release notes are the "## <version>" section of CHANGELOG.md.
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION=${1:?usage: scripts/release.sh <version>}
[[ $VERSION =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "The version must look like 1.2.3."; exit 1; }
IFS=. read -r MAJOR MINOR PATCH <<< "$VERSION"
(( MINOR < 100 && PATCH < 100 )) || { echo "Minor and patch versions must be below 100."; exit 1; }
# Sparkle orders updates by build number, so it comes from the version and only ever grows
# (1.0.0 is 10000, 1.2.3 is 10203).
BUILD=$((MAJOR * 10000 + MINOR * 100 + PATCH))

APP=OldMacDoc
REPO=https://github.com/kewonit/oldmacdoc
PROFILE=${NOTARY_PROFILE:-oldmacdoc-notary}
SPM=build/spm
BIN=$SPM/artifacts/sparkle/Sparkle/bin
OUT=build/release/$VERSION
FEED=$OUT/feed # this release's update alone: the appcast only needs the newest version

NOTES=$(awk -v v="$VERSION" 'index($0, "## " v) == 1 { on = 1; next } /^## / { if (on) exit } on' CHANGELOG.md)
[ -n "${NOTES//[$'\n ']/}" ] || { echo "CHANGELOG.md has no '## $VERSION' section."; exit 1; }

# Everything that can fail fast, before the long build.
xcrun notarytool history --keychain-profile "$PROFILE" >/dev/null 2>&1 \
  || { echo "No notarytool profile '$PROFILE'. Create it first (docs/RELEASING.md)."; exit 1; }
xcodegen generate --quiet
[ -x "$BIN/generate_keys" ] || xcodebuild -resolvePackageDependencies -project $APP.xcodeproj -clonedSourcePackagesDirPath $SPM -quiet
scripts/dmg/build.sh --prepare # dmgbuild, for the DMG at the end
KEY=$(sed -nE 's/^ *SUPublicEDKey: "(.*)"$/\1/p' project.yml)
[ -n "$KEY" ] && [ "$("$BIN/generate_keys" --account com.kewonit.oldmacdoc -p)" = "$KEY" ] \
  || { echo "The update signing key in your keychain doesn't match SUPublicEDKey in project.yml."; exit 1; }

rm -rf "$OUT"
mkdir -p "$FEED"
echo "Building $APP $VERSION ($BUILD)…"
xcodebuild -project $APP.xcodeproj -scheme $APP -configuration Release -clonedSourcePackagesDirPath $SPM \
  -archivePath "$OUT/$APP.xcarchive" ARCHS="arm64 x86_64" ONLY_ACTIVE_ARCH=NO \
  MARKETING_VERSION="$VERSION" CURRENT_PROJECT_VERSION="$BUILD" -quiet archive
xcodebuild -exportArchive -archivePath "$OUT/$APP.xcarchive" -exportPath "$OUT/export" \
  -exportOptionsPlist scripts/ExportOptions.plist -quiet
APP_PATH="$OUT/export/$APP.app"
lipo -archs "$APP_PATH/Contents/MacOS/$APP"
codesign --verify --deep --strict "$APP_PATH"

echo "Notarizing the app…"
ditto -c -k --keepParent "$APP_PATH" "$OUT/notarize.zip"
xcrun notarytool submit "$OUT/notarize.zip" --keychain-profile "$PROFILE" --wait
xcrun stapler staple "$APP_PATH"
rm "$OUT/notarize.zip"

echo "Building and notarizing the DMG…"
scripts/dmg/build.sh "$APP_PATH" "$OUT/$APP-$VERSION.dmg" "$PROFILE"
# The same DMG under a name that never changes, for …/releases/latest/download/OldMacDoc.dmg.
cp "$OUT/$APP-$VERSION.dmg" "$OUT/$APP.dmg"

echo "Making the update and appcast…"
ditto -c -k --sequesterRsrc --keepParent "$APP_PATH" "$FEED/$APP-$VERSION.zip"
printf '%s\n' "$NOTES" > "$FEED/$APP-$VERSION.md"
"$BIN/generate_appcast" --account com.kewonit.oldmacdoc \
  --download-url-prefix "$REPO/releases/download/v$VERSION/" \
  --embed-release-notes --maximum-deltas 0 --full-release-notes-url "$REPO/blob/main/CHANGELOG.md" "$FEED"

echo "Done: $OUT/$APP-$VERSION.dmg, $FEED/$APP-$VERSION.zip, $FEED/appcast.xml"
if [ "${PUBLISH:-0}" = 1 ]; then
  gh release create "v$VERSION" --draft --title "$APP $VERSION" --notes "$NOTES" \
    "$OUT/$APP-$VERSION.dmg" "$OUT/$APP.dmg" "$FEED/$APP-$VERSION.zip" "$FEED/appcast.xml"
  echo "Draft release v$VERSION created. Check it, then: gh release edit v$VERSION --draft=false"
fi
