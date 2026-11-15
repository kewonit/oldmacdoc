# Releasing

A release is a universal app signed with the Developer ID, notarized and stapled; a notarized DMG; and a Sparkle update (zip plus appcast, with the release notes) on GitHub Releases. Installed copies check the appcast at `https://github.com/kewonit/oldmacdoc/releases/latest/download/appcast.xml` once a day.

## One-time setup

1. **Notarization:** store a notarytool profile for team 55W3P96VL4. It asks for an app-specific password from appleid.apple.com.
   ```sh
   xcrun notarytool store-credentials oldmacdoc-notary --apple-id <your Apple ID> --team-id 55W3P96VL4
   ```
2. **Update signing key:** its private half is in your login keychain (account `com.kewonit.oldmacdoc`), and its public half is `SUPublicEDKey` in `project.yml`. Every update must be signed with it, or installed copies refuse it, so keep a backup somewhere safe:
   ```sh
   build/spm/artifacts/sparkle/Sparkle/bin/generate_keys --account com.kewonit.oldmacdoc -x oldmacdoc-sparkle-key.txt
   ```
   `scripts/release.sh` stops if the keychain's key doesn't match `SUPublicEDKey`.

## Each release

1. Write the release notes under `## <version>` in `CHANGELOG.md`. They become the update's notes and the GitHub release's.
2. Run `PUBLISH=1 scripts/release.sh <version>`. It:
   - builds a universal archive, numbered from the version (1.2.3 is build 10203), so builds always go up;
   - signs it with the Developer ID, notarizes and staples the app and the DMG;
   - makes the Sparkle zip and an appcast holding only this version, with the notes embedded and no deltas;
   - uploads `OldMacDoc-<version>.dmg`, `OldMacDoc.dmg` (the website's download link), the zip and `appcast.xml` as a **draft** release `v<version>`.
3. Check the draft, then publish it: `gh release edit v<version> --draft=false`. The appcast and the zip go live together.
4. Check:
   - `curl -sI https://github.com/kewonit/oldmacdoc/releases/latest/download/appcast.xml` finds it.
   - The website's Download button gets the DMG, which opens with no warnings.
   - An installed older version offers the update and installs it. Apple's Dock comes back for a moment while it restarts, then is parked again.

## Testing an update before publishing

Build two lower versions from the release commit, serve an appcast locally, and point the older one at it. Sparkle accepts a plain `http://127.0.0.1` feed because updates are signed:

```sh
BIN=build/spm/artifacts/sparkle/Sparkle/bin; T=build/update-test
for vb in "0.9.0 90" "0.9.1 91"; do set -- $vb
  xcodebuild -project OldMacDoc.xcodeproj -scheme OldMacDoc -configuration Release -clonedSourcePackagesDirPath build/spm \
    -archivePath $T/$1/OldMacDoc.xcarchive MARKETING_VERSION=$1 CURRENT_PROJECT_VERSION=$2 -quiet archive
  xcodebuild -exportArchive -archivePath $T/$1/OldMacDoc.xcarchive -exportPath $T/$1 -exportOptionsPlist scripts/ExportOptions.plist -quiet
done
mkdir -p $T/feed && ditto -c -k --sequesterRsrc --keepParent $T/0.9.1/OldMacDoc.app $T/feed/OldMacDoc-0.9.1.zip
printf -- '- Test update\n' > $T/feed/OldMacDoc-0.9.1.md
$BIN/generate_appcast --account com.kewonit.oldmacdoc --download-url-prefix http://127.0.0.1:8765/ --embed-release-notes --maximum-deltas 0 $T/feed
python3 -m http.server 8765 --bind 127.0.0.1 --directory $T/feed &
ditto $T/0.9.0/OldMacDoc.app /Applications/OldMacDoc.app
defaults write com.kewonit.oldmacdoc SUFeedURL http://127.0.0.1:8765/appcast.xml
defaults delete com.kewonit.oldmacdoc SULastCheckTime 2>/dev/null; open /Applications/OldMacDoc.app
```

Install and relaunch, then check that About shows 0.9.1 (91) and that Apple's Dock is parked again (`defaults read com.apple.dock autohide-delay` is 100000). Afterwards remove the override: `defaults delete com.kewonit.oldmacdoc SUFeedURL`.
