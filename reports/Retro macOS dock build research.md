# Hide the Dock, unjail icons, ship safely

You can build a native macOS 14+ Swift dock replacement almost entirely on public APIs, outside the sandbox, and v1 needs no privacy (TCC) prompts. The open-source Docky (GPLv3, last commit Oct 27 2026) ships every core piece on current macOS, so treat it as a working reference, but because of the GPL, read it for ideas only and don't copy its code into this MIT-licensed project. To hide Apple's Dock, snapshot six `com.apple.dock` keys, overwrite them through CFPreferences and restart the Dock. A PID-keyed state file plus a watchdog helper make sure a crash never leaves the user with no Dock. macOS 26 adds the gray squircle plate only to icons that ship inside app bundles, so the fix is to load each app's legacy `.icns` and restyle it in memory. Two caveats apply: apps rebuilt with Xcode 26.1+ may no longer contain free-form art, and no source documents a plate-detection algorithm, so the thresholds below need tuning on real machines. The dock itself is a borderless `.nonactivatingPanel` NSPanel in an `.accessory` app, and that same choice is what makes cooperative activation work on macOS 14+. Only one v1 feature needs a permission: the Trash full/empty indicator, which needs Full Disk Access. Updates are settled: Sparkle 2.10.1 plus a notarized, stapled Developer ID DMG.

## A snapshot, a restart and a watchdog hide the Dock safely

Apple's Dock can't be removed. You hide it by giving it a reveal delay so long it never shows. Docky writes **`autohide=true`, `autohide-delay=1000.0`, `autohide-time-modifier=0.0`, `no-bouncing=true`, `launchanim=false`** with `CFPreferencesSetAppValue(key, value, "com.apple.dock")` followed by `CFPreferencesAppSynchronize`. It saves those keys plus `orientation` beforehand, and it doesn't shell out to `defaults` ([Docky SystemDockVisibilityService](https://github.com/josejuanqm/docky/blob/cb7a6a64483b5cef82b308b6a0958d0df839a779/Docky/Services/SystemDockVisibilityService.swift)). **The new values only take effect after a Dock restart.** Do that with `forceTerminate()` on every `com.apple.dock` instance, or with `/usr/bin/killall Dock` from a helper ([Docky watchdog](https://github.com/josejuanqm/docky/blob/cb7a6a64483b5cef82b308b6a0958d0df839a779/DockyDockWatchdog/main.swift)). The Dock is delayed rather than removed, so a long hover at the edge can still bring it up ([MacRumors](https://forums.macrumors.com/threads/hide-dock.1569696)). The saved `orientation` lets you park the hidden Dock on a different edge so its reveal zone doesn't collide with yours.

The snapshot has two rules. First, record keys that were unset with a sentinel value, so that restoring deletes them (`CFPreferencesSetAppValue(key, nil, domain)`) instead of writing a guessed default. Second, never take a new snapshot while the Dock is already hidden. Crash recovery works in two layers. The first is an atomically written plist in Application Support holding `active`, `ownerPID`, `sessionID` and `snapshot`. On the next launch, if the plist says `active` but the owner PID is dead, the app restores the snapshot ([Docky SystemDockVisibilityService](https://github.com/josejuanqm/docky/blob/cb7a6a64483b5cef82b308b6a0958d0df839a779/Docky/Services/SystemDockVisibilityService.swift)). The second is a **tiny watchdog app embedded in `Contents/Library/LoginItems/`**. The main app launches it with `openApplication(at:configuration:)`, setting `activates = false` and passing the plist path, PID, session and bundle ID as arguments. Every 0.5 s it checks whether the owner is alive with `kill(pid, 0) == 0 || errno == EPERM`. When the owner dies it restores the snapshot, runs `killall Dock` and deletes the state file. A clean quit deletes the file first, so the watchdog exits without doing anything ([Docky watchdog](https://github.com/josejuanqm/docky/blob/cb7a6a64483b5cef82b308b6a0958d0df839a779/DockyDockWatchdog/main.swift)). Also restore in `applicationWillTerminate` and on `NSWorkspace.willPowerOffNotification`. DockDoor uses a private alternative, `CoreDockSetAutoHideEnabled`, but it only toggles autohide and can't set the delay ([DockDoor PrivateApis](https://github.com/ejbills/DockDoor/blob/3044142c907b9cdd49917628847a04970450a8e6/DockDoor/Utilities/PrivateApis.swift)). Avoid it. One caveat: Apple documents neither `no-bouncing` nor `launchanim`, and has published no Dock-key changelog for 26/27. The evidence that the approach works on Tahoe and 27 is Docky's current, shipping code.

## macOS 26 jails only bundle-shipped icons, so render the legacy art yourself

Tahoe "automatically shrinks the freely shaped icons of older apps" and, when pixels stick out past the shape, "places the gray shape behind them." The pre-Tahoe icon usually still sits as an `.icns` in `Contents/Resources`, while the Tahoe icon lives in `Assets.car`. **User-assigned custom icons are not jailed** ([heise](https://heise.de/-11075561); [9to5Mac](https://9to5mac.com/2025/08/08/macos-tahoe-fix-gray-box-icons/)). Two caveats limit what you can recover. Apple called the separate-icons-for-old-and-new-macOS technique "by design" broken, and Xcode 26.1 no longer supports it ([Michael Tsai](https://mjtsai.com/blog/2025/08/08/separate-icons-for-macos-tahoe-vs-earlier/)). That means **recently rebuilt apps may ship only squircle art in their `.icns` too**. And the plate itself changed to "a new lighter gray" in 26.1 ([Michael Tsai quoting Dan Moren](https://mjtsai.com/blog/2025/11/11/tahoes-terrible-icons/)), so never hard-code its color.

The loader:

1. Open `Bundle(url:)` and read `CFBundleIconFile`, appending `.icns` when the name has no extension.
2. Load it with `NSImage(contentsOf:)` and take the widest representation (1024 px when present).
3. If that fails, fall back to the largest `*.icns` in `Resources`, then to `NSWorkspace.shared.icon(forFile:)`.

On 26+ the `icon(forFile:)` result should be assumed to be the plated composite, but this is untested. There is no public API that reads the layers inside `Assets.car`. Don't write icons into other apps' bundles with `setIcon`: app updates reset them and you'd be modifying third-party bundles ([heise](https://heise.de/-11075561)).

No source documents how to detect the plate, so the following is engineering guidance to tune on real 26.x/27 machines. Render both candidates into a 1024² RGBA8 premultiplied `CGContext`, then run two tests:

- **Test A** asks whether the legacy art fits a continuous-corner squircle mask. If more than ~3% of the pixels inside the mask are transparent, or more than ~0.5% of the pixels outside it are opaque, the art doesn't conform. That predicts jailing, so prefer the legacy art.
- **Test B** confirms the plate on the system icon. Sample ~32 points just inside the squircle edge. If they are opaque and low-chroma (`max−min < 10`) with low variance, while the legacy art is transparent at the same points, it's a plate.

One Developer Forums user claims that **edge alpha ≤252** triggers the wrap on 26.4.1. That would explain why anti-aliased legacy icons get caught, but it is one person's experiment ([Apple Developer Forums](https://origin-devforums.apple.com/forums/profile/Wenkai26/replies)).

After choosing the art:

- **Trim** to the bounding box of pixels with α > 8.
- **Normalize size** by `sqrt(opaque area)`, not bounding box, so round and wide icons feel the same size. Clamp the scale to [0.85, 1.15].
- **Cache** the result by bundle ID + `CFBundleVersion`.

For the retro finish, create one app-wide `CIContext` (thread-safe) and build new `CIFilter`s on each call, since filters aren't thread-safe:

1. Apply `CIColorControls` (saturation ~1.15, contrast ~1.06).
2. Add a `CILinearGradient` gloss, white at 40% alpha fading to 0 over the top half, composited with `CISourceAtopCompositing` so the gloss stays inside the icon's silhouette.
3. Optionally add a bevel: `CIHeightFieldFromMask` → `CIShadedMaterial`.
4. Render once per icon, off the main thread, at 2× the maximum magnified size. Never run Core Image per frame.

These Core Image parameters weren't checked against Apple's docs.

## A non-activating accessory panel hosts a tilted-floor shelf

Docky subclasses `NSPanel` because "that's the only way" `.nonactivatingPanel` takes effect and stops dock clicks from activating the app. It returns `canBecomeKey = false` (true only while a text field is focused) and `canBecomeMain = false`, and sets `backgroundColor = .clear` and `isOpaque = false` ([Docky MainWindow](https://github.com/josejuanqm/docky/blob/cb7a6a64483b5cef82b308b6a0958d0df839a779/Docky/Views/MainWindow/MainWindow.swift)). Run the app with `.accessory` activation policy, or set `LSUIElement` ([Docky AppDelegate](https://github.com/josejuanqm/docky/blob/cb7a6a64483b5cef82b308b6a0958d0df839a779/Docky/AppDelegate.swift)). Also set `hidesOnDeactivate = false`, because panels default to hiding when their app isn't active, and an `.accessory` app almost never is.

For collection behavior, use **`[.canJoinAllSpaces, .stationary, .ignoresCycle]`** and add `.fullScreenAuxiliary` only if the dock should appear over full-screen apps ([Docky DockyPreferences](https://github.com/josejuanqm/docky/blob/cb7a6a64483b5cef82b308b6a0958d0df839a779/Docky/Services/DockyPreferences.swift); [Apple](https://developer.apple.com/documentation/appkit/nswindow/collectionbehavior-swift.struct)). For the window level, Docky pins `.mainMenu` (24). Apple's own Dock uses `CGWindowLevelForKey(.dockWindow)` (20, per the SDK's `CGWindowLevel.h`), which keeps the dock below menus and pop-ups. That is the better choice.

To detect full screen, read `CGWindowListCopyWindowInfo` and look for layer-0 windows from other apps whose flipped bounds equal `screen.frame`. Re-check on `activeSpaceDidChangeNotification`, with delayed re-checks because the notification fires during the exit animation ([Docky MainWindow](https://github.com/josejuanqm/docky/blob/cb7a6a64483b5cef82b308b6a0958d0df839a779/Docky/Views/MainWindow/MainWindow.swift)).

For auto-hide reveal, Docky installs global and local `.mouseMoved` monitors with a 2-pt trigger, only while the dock is hidden. Apple restricts only *key* events to Accessibility-trusted apps ([Apple](https://developer.apple.com/documentation/appkit/nsevent/addglobalmonitorforevents(matching:handler:))). Nothing confirms this still holds on 26/27, so keep a fallback ready: a 2-pt transparent edge panel with an `.activeAlways` tracking area.

No source documents Apple's magnification curve or any open-source 3D shelf, so the rendering below is standard Core Animation and needs on-device tuning:

- **Perspective:** put the perspective on the container.
- **Floor:** tilt only the glass floor (a `CAGradientLayer` hinged at its front edge). Keep the icons as a flat, upright row in front of it, which avoids `CATransformLayer`'s contents, mask and opacity pitfalls.
- **Reflections:** use a sibling layer per icon with the same contents, flipped, masked by a fading gradient, at ~0.35 opacity.
- **Magnification:** use a raised-cosine falloff, the same family of curve as the [shadcn macOS Dock](https://www.shadcn.io/components/dock/mac-os-dock). Bottom-anchor the icons so they grow upward. Re-center the row around the pointer. Ease `maxScale` in and out over ~120 ms with `NSView.displayLink(target:selector:)` (macOS 14+).

```swift
var p = CATransform3DIdentity; p.m34 = -1/500; container.sublayerTransform = p
shelf.anchorPoint = CGPoint(x: 0.5, y: 0); shelf.transform = CATransform3DMakeRotation(.pi * 0.38, 1, 0, 0)
reflection.contents = icon.contents; reflection.transform = CATransform3DMakeScale(1, -1, 1); reflection.mask = fade
func scale(_ d: CGFloat, max m: CGFloat = 1.8, range r: CGFloat) -> CGFloat {
    d >= r ? 1 : 1 + (m - 1) * 0.5 * (1 + cos(.pi * d / r)) }
// every mouse move: CATransaction.begin(); setDisableActions(true); layout; commit()
```

For speed:

- Bake shadows into the cached bitmap or set a `shadowPath`. Shadows shaped by alpha cost an offscreen pass per layer, every frame.
- Rasterize only the static shelf, never the scaling icons.
- Host everything in one layer-backed `NSView`.

## Staying `.accessory` makes activation work; Trash state is the only permission

**Running apps.** Track apps with `runningApplications.filter { $0.activationPolicy == .regular && $0.bundleIdentifier != myID }`. Observe didLaunch, didTerminate, didHide, didUnhide and didActivate, and refresh again later, because some apps start as `.accessory` or `.prohibited` and only become `.regular` once their first window appears ([Docky WorkspaceService](https://github.com/josejuanqm/docky/blob/cb7a6a64483b5cef82b308b6a0958d0df839a779/Docky/Services/WorkspaceService.swift)).

**Activation.** Since macOS 14, activation is cooperative, "a request instead of a command," and NSWorkspace handles it automatically when it opens apps ([Apple](https://developer.apple.com/documentation/appkit/passing-control-from-one-app-to-another-with-cooperative-activation)). `ignoringOtherApps` no longer has any effect. **The system exempts `.accessory` apps.** A `.regular` app that isn't frontmost has its activation calls fail silently: every tile click broke while Docky switched to `.regular` to show Settings (issue #35). The fix is `activate(from: NSWorkspace.shared.frontmostApplication ?? .current, options:)`, falling back to `activate(options:)` ([Docky AppActivation](https://github.com/josejuanqm/docky/blob/cb7a6a64483b5cef82b308b6a0958d0df839a779/Docky/Services/AppActivation.swift)). The click flow ([Docky WorkspaceService](https://github.com/josejuanqm/docky/blob/cb7a6a64483b5cef82b308b6a0958d0df839a779/Docky/Services/WorkspaceService.swift)):

- **Not running:** `urlForApplication(withBundleIdentifier:)`, then `openApplication(at:configuration:)` with `activates = true`.
- **Running:** `unhide()`, then `activate(from:options: [.activateAllWindows])`.
- **Running with no windows:** call `openApplication` again, which relies on Launch Services' reopen behavior. Test this; it isn't confirmed.

Restoring minimized windows needs Accessibility. Quit with `terminate()`, use `activateFileViewerSelecting([url])` for Show in Finder, and use `SMAppService.mainApp.register()` for launch at login, checking `.status` first ([Docky LaunchAtLoginService](https://github.com/josejuanqm/docky/blob/cb7a6a64483b5cef82b308b6a0958d0df839a779/Docky/Services/LaunchAtLoginService.swift)). If the status stays `.requiresApproval`, send the user to `SMAppService.openSystemSettingsLoginItems()`.

**Trash.** Without Full Disk Access, listing `~/.Trash` fails with "Operation not permitted," even under `sudo` ([Apple Developer Forums](https://developer.apple.com/forums/thread/122716)). **Docky's TrashService treats a failed read as "empty," which is the bug to avoid.** Check whether the read throws, and show an unknown state instead of empty ([Docky TrashService](https://github.com/josejuanqm/docky/blob/cb7a6a64483b5cef82b308b6a0958d0df839a779/Docky/Services/TrashService.swift)). Moving files to the Trash with `FileManager.trashItem` needs no Full Disk Access ([Docky MainWindowView](https://github.com/josejuanqm/docky/blob/cb7a6a64483b5cef82b308b6a0958d0df839a779/Docky/Views/MainWindow/MainWindowView.swift)). The icons come from `NSImage.trashEmptyName` and `NSImage.trashFullName` ([Docky TrashTileView](https://github.com/josejuanqm/docky/blob/cb7a6a64483b5cef82b308b6a0958d0df839a779/Docky/Views/Tiles/TrashTileView.swift)). Emptying the Trash means sending Finder an Apple Event, which needs the Automation permission and the `apple-events` entitlement. One thing is untested: whether a `DispatchSource` watcher on `.Trash` works without Full Disk Access.

| Feature | API | Permission |
|---|---|---|
| Hide/restore the Dock | CFPreferences + Dock restart | None |
| Panel, auto-hide reveal | NSPanel, `.mouseMoved` monitor | None (test on 26/27) |
| List, launch, activate, quit apps | NSWorkspace / NSRunningApplication | None |
| Restore minimized windows, focus a specific window | AXUIElement | Accessibility |
| Drop files on the Trash | `FileManager.trashItem` | None |
| Trash full/empty indicator, empty Trash | Read `~/.Trash` / Finder Apple Events | Full Disk Access / Automation |
| Launch at login | `SMAppService.mainApp` | User approval only |

## Sparkle 2.10.1 finishes the release

**Updates.** Sparkle **2.10.1** (Oct 25) requires macOS 12+. Version 2.10.0 removed CocoaPods support and fixed delta updates on **macOS 27** ([Sparkle releases](https://github.com/sparkle-project/Sparkle/releases)). Setup ([Sparkle docs](https://sparkle-project.org/documentation/)):

1. Add Sparkle through SPM and create one `SPUStandardUpdaterController`. Because the app is `LSUIElement`, wire `checkForUpdates` into the dock's context menu.
2. In Info.plist, set `SUFeedURL` and `SUPublicEDKey`, and always increase `CFBundleVersion`. Optionally add `SURequireSignedFeed` and `SUVerifyUpdateBeforeExtraction`.
3. Run `generate_keys` once. It keeps the private key in the login Keychain; export a backup with `-x`.
4. Run `generate_appcast` over a folder that persists between releases. It builds the delta updates and picks up a same-named `.md` file (2.9+) as release notes.
5. Export through **Developer ID** so Sparkle's helper tools get signed. Non-sandboxed apps can drop Sparkle's XPC services.

**Release pipeline.** Run this after stapling, so the signature and length in the appcast match the final DMG bytes. Sparkle recommends a notarized, Developer ID-signed DMG with an `/Applications` symlink ([Sparkle docs](https://sparkle-project.org/documentation/)). The flags below are standard but weren't re-checked against Apple's docs; confirm the Xcode 27 `ExportOptions.plist` key names.

```bash
xcodebuild -scheme RetroDock -configuration Release -destination 'generic/platform=macOS' \
  -archivePath build/RD.xcarchive ARCHS="arm64 x86_64" ONLY_ACTIVE_ARCH=NO ENABLE_HARDENED_RUNTIME=YES archive
xcodebuild -exportArchive -archivePath build/RD.xcarchive -exportOptionsPlist ExportOptions.plist -exportPath build/export  # method=developer-id
codesign --verify --deep --strict --verbose=2 build/export/RetroDock.app
hdiutil create -volname RetroDock -srcfolder build/dmg -format UDZO build/RetroDock-$V.dmg   # dmg/ = app + Applications symlink
codesign --sign "Developer ID Application: NAME ($TEAM)" --timestamp build/RetroDock-$V.dmg
xcrun notarytool submit build/RetroDock-$V.dmg --keychain-profile AC_NOTARY --wait && xcrun stapler staple build/RetroDock-$V.dmg
cp build/RetroDock-$V.dmg updates/ && generate_appcast --download-url-prefix "https://github.com/USER/REPO/releases/download/$V/" updates/
gh release create "$V" build/RetroDock-$V.dmg
```

## Conclusion

The most important architectural decision is to stay `.accessory`. That one setting keeps the dock from stealing focus, exempts it from cooperative-activation refusals and keeps it out of the Dock and app switcher. Any temporary switch to `.regular`, for example to show a Settings window, must route activation through `activate(from:)`. The second lesson is that removing the plate is a shrinking advantage. Every third-party app rebuilt with Xcode 26.1+ loses recoverable free-form art, so the Aqua finish has to look good on squircle art. The product's differentiator should be the finish and the shelf, not plate removal alone.

Before committing to the design, check three things on a real 26.x and 27 machine:

- what `icon(forFile:)` returns for jailed apps, and for Dark or Tinted icon styles;
- whether global `.mouseMoved` monitors still fire without Accessibility;
- whether `openApplication` on an already-running app reliably triggers its reopen behavior.
