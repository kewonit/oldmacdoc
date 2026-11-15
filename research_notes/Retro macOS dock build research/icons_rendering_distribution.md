# Icons, 3D Dock Rendering, and Developer ID Distribution for a Swift Retro Dock (macOS 14–27, as of Oct 2026)

> Research budget note: 16 searches/fetches in total. Apple API reference pages (NSImage, Core Image, CATransform3D, notarytool) were **not** fetched this session. Code that relies on those APIs is in the **Inferences** sections and is labeled as engineering guidance, not sourced fact. Test it before shipping.

## Q1. App icons on macOS 26/27: what the system returns, where the original artwork lives, and how to load it

### Takeaway
On macOS 26 Tahoe, an app's own icon is shrunk and put on a gray squircle ("plate") if it doesn't fit Apple's shape. The legacy `.icns` in `Contents/Resources` (named by `CFBundleIconFile`) often still holds the original free-form artwork. The Tahoe icon lives in `Assets.car` (named by `CFBundleIconName`). User-assigned custom icons are not jailed. So the build plan is: read `CFBundleIconFile` → load the `.icns` with `NSImage(contentsOf:)` → use it when it looks non-squircle, and fall back to `NSWorkspace.shared.icon(forFile:)` otherwise.

### Cited Findings
- heise: "macOS automatically shrinks the freely shaped icons of older apps so that they follow Apple's specifications." Also: "The system detects when pixels protrude and places the gray shape behind them." This can happen even to square icons. — [heise, "Icons in macOS 26: Fighting the 'Squircle' Prison"](https://heise.de/-11075561)
- heise: the old icon is an `.icns` file in `Contents/Resources`, often `AppIcon.icns`, and "the modern icon for Tahoe is in the 'Assets.car' file". — [heise](https://heise.de/-11075561); same point in [9to5Mac fix guide](https://9to5mac.com/2025/08/08/macos-tahoe-fix-gray-box-icons/)
- heise: "Currently, macOS only treats the icon brought along by an app this way, but not custom icons." The user fix is to drag the `.icns` onto the Get Info icon. The Dock updates on the app's next launch. Apple could change this in a later Tahoe update. — [heise](https://heise.de/-11075561)
- mpv commit "osxbundle: add new macOS 26 compatible App icon": adds a precompiled `Assets.car` plus a `CFBundleIconName` key and keeps the existing `CFBundleIconFile`. It says actool generates an Assets.car "compatible with all the new Theme variants of macOS 26". It also notes that no tool can generate a macOS 26 compatible icns (besides the default), because the icns lacks the required padding. — [mpv commit mirror](https://git.quad4.io/Mirrors/mpv/commit/f93df58a8eebf23b7f841bbf34bb2bda9f9cc16b) (seen via search summary; I did not read the full diff)
- Dual-icon apps: giving the `.iconset` (`CFBundleIconFile`) and the `.icon` (`CFBundleIconName`) different names let one app show a pre-Tahoe icon on older macOS and a Tahoe icon on Tahoe. This stopped working in later Xcode betas. Apple said "this is by design", and John Siracusa reported that Xcode 26.1 no longer supports the technique. — [Michael Tsai, Aug 8 2025](https://mjtsai.com/blog/2025/08/08/separate-icons-for-macos-tahoe-vs-earlier/) (search summary)
- Older macOS ignores `CFBundleIconName`/Assets.car and falls back to `CFBundleIconFile`, so both icon systems coexist in a bundle for backward compatibility. — Tauri-app doc in search results ([TabularisDB PR #217](https://github.com/TabularisDB/tabularis/pull/217) or [cmdr commit](https://github.blesdmm.dns-dynamic.net/vdavid/cmdr/commit/cc80d28); I could not tell which one the snippet came from)
- Dan Moren: "Squircle jail remains a thing in macOS 26.1", now with "a new lighter gray background". Michael Schmitt: Tahoe blocks even small flourishes that extend past the shape. Paul Kafasis (Rogue Amoeba): "Perhaps one day, it will again be possible for icons to have shape and personality." Beatrix Willius: an app can still draw into its Dock icon at runtime, but only once it has launched. — [Michael Tsai, "Tahoe's Terrible Icons", Nov 11 2025](https://mjtsai.com/blog/2025/11/11/tahoes-terrible-icons/)
- Unverified detection heuristic: one Apple Developer Forums user (testing on macOS 26.4.1) claims that edge alpha values ≤252 trigger the gray wrap, which would explain why anti-aliased legacy icons get caught. This is a single user's experiment, not an Apple rule. — [Apple Developer Forums user replies](https://origin-devforums.apple.com/forums/profile/Wenkai26/replies) (search summary)
- A third-party icon tool describes the behavior as: icons that do not fit within the squircle "are shrunk and placed above an ugly grey background". — [sabinomaggi/IconLib](https://github.com/sabinomaggi/IconLib) (search summary)
- Commentary describes Tahoe as requiring squircle app icons and wrapping non-conforming ones in a gray box. — [One Foot Tsunami](https://onefoottsunami.com/2025/11/05/tahoes-terrible-icons/), [9to5Mac](https://9to5mac.com/2025/08/08/macos-tahoe-fix-gray-box-icons/)

### Inferences
- **What `NSWorkspace.shared.icon(forFile:)` returns on 26+:** most likely the same system-composited icon Finder and the Dock show, so for non-conforming apps it is the jailed version on the plate. Two findings support this: the jailing happens at the system level, and only bundle-shipped icons are affected. This was not confirmed against Apple documentation. Verify empirically on 26.x and 27.
- **Loader (public API only):**
  ```swift
  func legacyIcon(appURL: URL) -> NSImage? {
      guard let b = Bundle(url: appURL) else { return nil }
      if var name = b.object(forInfoDictionaryKey: "CFBundleIconFile") as? String {
          if (name as NSString).pathExtension.isEmpty { name += ".icns" }   // key often omits extension
          if let u = b.url(forResource: name, withExtension: nil), let img = NSImage(contentsOf: u) { return img }
      }
      // Fallback: AppIcon.icns or any *.icns in Contents/Resources (pick largest file)
      let res = appURL.appendingPathComponent("Contents/Resources")
      let icns = (try? FileManager.default.contentsOfDirectory(at: res, includingPropertiesForKeys: [.fileSizeKey]))?
          .filter { $0.pathExtension == "icns" } ?? []
      return icns.max { (try? $0.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0) ?? 0 <
                        (try? $1.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0) ?? 0 }
          .flatMap(NSImage.init(contentsOf:))
  }
  // Best bitmap: img.representations.max { $0.pixelsWide < $1.pixelsWide } → 1024px (ic10) when present.
  ```
- **The `.icns` may itself be squircle art.** Since Xcode 26.1, the dual-name technique is gone ([Tsai](https://mjtsai.com/blog/2025/08/08/separate-icons-for-macos-tahoe-vs-earlier/)). Apps rebuilt with an Icon Composer `.icon` probably ship an `.icns` derived from the new squircle design. Recent builds of updated apps may therefore have no free-form artwork left to recover. Treat the legacy `.icns` as a candidate and test its shape (Q2) before preferring it.
- **`.icon` (Icon Composer) layers:** the `.icon` source is compiled by actool into `Assets.car` ([mpv commit](https://git.quad4.io/Mirrors/mpv/commit/f93df58a8eebf23b7f841bbf34bb2bda9f9cc16b)). The layered source is not shipped inside the app, and there is no public API to parse `Assets.car` layers. Reading layered icons from third-party apps therefore isn't feasible without private CoreUI APIs, which the constraints exclude. `Bundle(url:)?.image(forResource:)` may resolve names from that bundle's asset catalog, but whether it returns the composed Tahoe icon by `CFBundleIconName` is untested.
- **Don't write custom icons into other apps' bundles** (the Get Info or `NSWorkspace.setIcon` route). It modifies third-party bundles, it is reset by updates (which is why a re-applier tool like Replaicon exists, per [heise](https://heise.de/-11075561)), and it breaks the "all restyling at runtime" constraint. Render from the `.icns` in memory instead.
- **Plate geometry useful for detection (from Apple's Big Sur-era template, not verified this session):** a 1024×1024 canvas with an ~824×824 rounded-rect body (≈100 px inset per side) and a continuous-curvature corner radius of ≈22.4–22.5% of the body width. Detect the plate by sampling rather than hardcoding RGB. Moren reports the plate got lighter in 26.1, so the colors drift between releases.

### Gaps
- **Rogue Amoeba "Free The Icons" (Oct 2026):** search found nothing by that name; it may be too recent to be indexed. Rogue Amoeba's only verified statement is Kafasis's quote above.
- **Raycast extension** that un-jails icons: not found.
- **The mpv change** that reverts jailing (if one exists beyond the Assets.car commit): not found.
- **Exact numbers:** the plate RGB, the shrink factor for jailed artwork, and any macOS 27 changes to jailing were not found in any source.
- **Appearance modes:** whether `icon(forFile:)` returns Dark, Clear, or Tinted variants depending on the user's icon style is unverified. This would confound pixel sampling.

## Q2. Algorithms for plate detection and removal, trimming and normalization, and a Core Image "retro Aqua" finish

### Takeaway
No source documents a plate-detection algorithm. Build it with two tests. First, check whether the legacy `.icns` is non-squircle (transparent pixels inside the standard squircle mask, or opaque pixels outside it). Second, check whether the system icon shows a low-chroma, uniform ring between the squircle edge and a smaller artwork bounding box. Then trim the alpha bounding box, normalize the visual size, and apply a reused `CIContext` pipeline.

### Cited Findings
- The system wraps icons when pixels protrude from the shape. Shape conformance is the trigger. — [heise](https://heise.de/-11075561)
- Edge alpha ≤252 claimed as the trigger (unverified, macOS 26.4.1). — [Apple Developer Forums](https://origin-devforums.apple.com/forums/profile/Wenkai26/replies)
- The plate background became lighter gray in 26.1. — [Michael Tsai quoting Dan Moren](https://mjtsai.com/blog/2025/11/11/tahoes-terrible-icons/)

### Inferences (engineering guidance; Core Image and AppKit behavior not re-verified this session)
- **Normalize everything to a 1024² RGBA8 premultiplied `CGContext`** and read the bytes directly. That is fast: about 4 MB per icon, run once and cached per bundle ID + CFBundleVersion.
- **Test A (legacy art is free-form):** build a squircle mask (inset 100 px, radius ≈ 0.2237 × 824, continuous corners via `NSBezierPath`/`CGPath`).
  - `inside` = fraction of mask pixels with α < 250
  - `outside` = fraction of non-mask pixels with α > 8
  - If `inside > 0.03 || outside > 0.005`, the art doesn't conform. That predicts jailing, so prefer the legacy art.
- **Test B (system icon is jailed):** sample about 32 points on a ring just inside the squircle edge (≈8–24 px inside the inset rect) of the `NSWorkspace` icon. A ring that is opaque and low-chroma (`max(r,g,b) − min(r,g,b) < 10`), with luminance variance below about 4, while the same points in the legacy art are transparent, indicates a plate. Use Test B to confirm Test A and to catch the edge-alpha case.
- **Alpha bounding-box trim:** scan rows and columns for α > 8. Crop with `cgImage.cropping(to:)`. Pad back to a square, centered on the bbox center.
- **Visual-size normalization:** scale so that `sqrt(opaquePixelCount)/1024` hits a target (≈0.80 for free-form art). Area-based is better than bbox-based: a round icon and a wide icon then *feel* the same size. Clamp the scale to [0.85, 1.15]. Apply the same target to squircle icons (≈824² area) so mixed shelves look even.
- **Retro finish (one shared `CIContext`; create it once, never per icon):**
  ```swift
  let ciContext = CIContext(options: [.cacheIntermediates: false])   // reuse app-wide; GPU-backed via Metal
  func aquaize(_ cg: CGImage) -> CGImage? {
      let src = CIImage(cgImage: cg); let e = src.extent
      let punchy = src.applyingFilter("CIColorControls",
          parameters: [kCIInputSaturationKey: 1.15, kCIInputContrastKey: 1.06, kCIInputBrightnessKey: 0.0])
      let gloss = CIFilter(name: "CILinearGradient", parameters: [
          "inputPoint0": CIVector(x: e.midX, y: e.maxY), "inputPoint1": CIVector(x: e.midX, y: e.midY),
          "inputColor0": CIColor(red: 1, green: 1, blue: 1, alpha: 0.40),
          "inputColor1": CIColor(red: 1, green: 1, blue: 1, alpha: 0.0)])!.outputImage!.cropped(to: e)
      // Source-atop keeps gloss only where the icon has alpha (no gloss outside its silhouette)
      let out = gloss.applyingFilter("CISourceAtopCompositing", parameters: [kCIInputBackgroundImageKey: punchy])
      return ciContext.createCGImage(out, from: e)
  }
  ```
  - **Bevel (optional):** make an alpha mask with `CIColorMatrix`, then `CIHeightFieldFromMask` (radius ≈ 6–12 px at 1024), then `CIShadedMaterial` with a small radial-gradient "sphere" shading image (`CIRadialGradient`), then multiply/soft-light over the icon at low opacity. Clip the gloss to an ellipse (`CIRadialGradient` with a stretched transform) for the classic Aqua lozenge highlight.
  - **Performance:** render once per icon at 2× the maximum magnified point size (e.g., 256 px) and cache the `CGImage`. Never run Core Image per frame. Do the processing off the main thread. `CIContext` is thread-safe; `CIFilter` instances are not, so build them per call.

### Gaps
- No source gives the system's exact squircle-conformance test, the mask tolerance, or the plate color values. The thresholds above are starting points to calibrate on real 26.x and 27 machines.

## Q3. Core Animation 3D glass shelf, reflections, shadows, magnification, and performance

### Takeaway
Use a perspective `sublayerTransform` (m34 ≈ −1/500) on a container. Tilt only the glass-floor layer around the X axis (Leopard style). Keep icons upright and facing the viewer. Draw reflections as vertically flipped copies masked by a `CAGradientLayer`, and drive magnification with a raised-cosine or Gaussian falloff inside `CATransaction.setDisableActions(true)`. Sourced material here is thin: the APIs are standard, but this session didn't verify them against docs.

### Cited Findings
- Docky (`josejuanqm/docky`) is an open-source, GPLv3 Swift Dock replacement that can run alongside, mirror, or replace the system Dock. It uses Sparkle. Its rendering technique was not confirmed. — [awesome.ecosyste.ms entry for Docky](https://awesome.ecosyste.ms/projects/github.com%2Fjosejuanqm%2Fdocky), [ossinsight](https://ossinsight.io/analyze/josejuanqm/docky)
- `swiftui-macos-dock-animation` is a simple SwiftUI implementation of the macOS Dock magnification. — [GitHub: HuangRunHua/swiftui-macos-dock-animation](https://github.com/HuangRunHua/swiftui-macos-dock-animation)
- DockDoor is open-source Swift/SwiftUI, focused on window previews rather than a 3D shelf. — [Reddit r/macapps](https://reddit.birdcat.cafe/r/macapps/comments/1hse6ey/dockdoor_the_modern_alternative_to_hyperdock)
- Shadcn's web "macOS Dock" component uses cosine-based magnification. It's React, not Swift, but its math is a reference point. — [shadcn.io macOS Dock](https://www.shadcn.io/components/dock/mac-os-dock)

### Inferences (standard Core Animation; not re-verified against Apple docs this session)
- **Shelf:**
  ```swift
  var p = CATransform3DIdentity; p.m34 = -1.0 / 500          // smaller denominator = stronger perspective
  container.sublayerTransform = p
  shelf.anchorPoint = CGPoint(x: 0.5, y: 0)                   // hinge at the front edge
  shelf.transform = CATransform3DMakeRotation(.pi * 0.38, 1, 0, 0)  // ~68° tilt away from viewer
  // shelf = CAGradientLayer (white α0.55 → α0.15), 1px bright top-edge border layer, plus a darker front lip layer (no transform)
  ```
  Use `CATransformLayer` only if the children need to keep their own 3D positions (e.g., icons standing *on* a rotated plane). For the Leopard look, a flat icon row in front of a tilted floor is simpler and avoids the "`CATransformLayer` doesn't render its own contents, mask, or opacity" pitfalls.
- **Reflections:** for each icon, add a sibling `reflection` layer with the same `contents` and `transform = CATransform3DMakeScale(1, -1, 1)`, positioned directly under the icon's base. Its `mask` is a `CAGradientLayer` (black α0.35 → clear over ~40% height), and its opacity is about 0.35. Keep the frame in sync with magnification in the same transaction. `CAReplicatorLayer` (instanceCount 2, flip `instanceTransform`, `instanceAlphaOffset`) works too, but per-instance gradient fades are harder. Prefer explicit sibling layers.
- **Shadows:** use `layer.shadowOpacity` and `shadowRadius` with no `shadowPath`. Core Animation then uses the contents' alpha, which shapes the shadow to the icon but costs an offscreen pass per layer per frame. To avoid that cost, either:
  - pre-bake the shadow into the cached icon bitmap (`CIGaussianBlur` on the alpha mask, offset, and composite), or
  - set a `shadowPath` (squircle `CGPath` for squircle icons, or a contact-shadow ellipse on the shelf).
- **Magnification:**
  ```swift
  func scale(_ d: CGFloat, maxScale: CGFloat = 1.8, range: CGFloat = 3 * baseSize) -> CGFloat {
      guard d < range else { return 1 }
      return 1 + (maxScale - 1) * 0.5 * (1 + cos(.pi * d / range))   // raised cosine; or exp(-d*d/(2*σ*σ)), σ≈range/2.5
  }
  // d = |iconCenterX(at rest) − mouseX|. Lay out left→right with widths baseSize*scale;
  // re-center the row so total growth is split around the pointer (prevents the row from "walking").
  ```
  - Bottom-anchor the icons (`anchorPoint.y = 0`) so they grow upward off the shelf.
  - Ease the entry and exit by lerping `maxScale` from 1 to its target over about 120 ms with a `CVDisplayLink`/`CADisplayLink` (the latter on macOS 14+ via `NSView.displayLink(target:selector:)`).
- **Performance:**
  - Wrap every mouse-move update in `CATransaction.begin(); setDisableActions(true); … commit()`.
  - Set `contentsScale = window.backingScaleFactor` and `contentsGravity = .resizeAspect`.
  - Supply bitmaps at maximum magnified size × 2 so scaling is downsample-only.
  - Use `shouldRasterize` only on static subtrees (shelf plus lip), with `rasterizationScale = backingScaleFactor`. **Never** rasterize the per-frame-scaling icon layers.
  - Host everything in one layer-backed `NSView` (`wantsLayer = true`, `layerContentsRedrawPolicy = .never`), not dozens of NSViews.
- **Licensing caution:** Docky is GPLv3. Read it for ideas only. Copying its code into this MIT-licensed project would bring GPL obligations with it.

### Gaps
- No source describes Apple's actual Dock magnification curve or confirms any open-source dock's 3D shelf or reflection code. Docky's renderer is unverified.

## Q4. Sparkle 2 for auto-updates

### Takeaway
The current release is Sparkle **2.10.1** (Oct 25; requires macOS 12+, CocoaPods dropped), so it covers macOS 14–27. Add it via SPM, create one `SPUStandardUpdaterController`, and set `SUFeedURL` + `SUPublicEDKey`. Make keys once with `generate_keys`, build the feed with `generate_appcast` over a folder of notarized DMGs, and serve over HTTPS (GitHub Releases or Pages works).

### Cited Findings
- **Latest releases:**
  - 2.10.1 "Golden Gate Bump" (25 Oct): fixes `releaseNotesLink` whitespace handling, premature install from NFC-encoded paths, and custom namespace prefixes. Says "macOS 12.0 or later is required" because Xcode 27 drops older deployment targets.
  - 2.10.0 (13 Sep): raises the minimum to macOS 12, removes CocoaPods, and fixes file-system compression for delta updates on **macOS 27**.

  — [Sparkle GitHub Releases](https://github.com/sparkle-project/Sparkle/releases) (the page doesn't show the year; given the Xcode 27 / macOS 27 references, it's 2026)
- A stale Wikipedia mirror (March 2026 snapshot) lists 2.6.0. This conflicts with the releases page; trust GitHub. — [Wikipedia mirror](https://wiki.krisyotam.com/content/wikipedia_en_all_nopic_2026-03/Sparkle_(software))
- SPM: add `https://github.com/sparkle-project/Sparkle` via File › Add Packages. With SPM, the tools live in the package's `../artifacts/sparkle/Sparkle/bin/` (go up from `checkouts`). — [Sparkle documentation](https://sparkle-project.org/documentation/)
- The updater is `SPUStandardUpdaterController`. A "Check for Updates…" item targets `checkForUpdates:`, and no other calls are needed for automatic checks. SwiftUI and programmatic setup have a separate page. — [Sparkle documentation](https://sparkle-project.org/documentation/)
- Info.plist:
  - `SUFeedURL` (appcast URL) and `SUPublicEDKey` (base64 key from `generate_keys`).
  - `CFBundleVersion` must increase, because Sparkle compares on it.
  - Optional hardening: `SURequireSignedFeed` + `SUVerifyUpdateBeforeExtraction`, and `SUSignedFeedFailureExpirationInterval`.

  — [Sparkle documentation](https://sparkle-project.org/documentation/)
- `./bin/generate_keys` stores the private key in the login Keychain. Export with `-x private-key-file`, import with `-f`, and re-run to print the public key. — [Sparkle documentation](https://sparkle-project.org/documentation/)
- `./bin/generate_appcast /path/to/updates_folder/` takes a persistent folder of dmg/zip/tar.xz/aar archives and writes the appcast plus `*.delta` files. An `.html` (or, since 2.9, `.md`) file with the same name as an archive becomes the release notes. With a signed feed, it also signs the appcast. — [Sparkle documentation](https://sparkle-project.org/documentation/)
- Distribution:
  - Use Archive › Distribute App › **Developer ID** so Sparkle's helper tools get signed. `xcodebuild archive` and `-exportArchive` work for automation.
  - Recommended format: a notarized, Developer ID-signed DMG with an `/Applications` symlink.
  - Library Validation, part of the Hardened Runtime, is required for notarization; ad-hoc signatures can stop Sparkle from loading. Verify with `codesign --deep --verify`.
  - Non-sandboxed apps can drop Sparkle's XPC services.
  - Serve over HTTPS (ATS), and keep signing keys off the hosting machine.

  — [Sparkle documentation](https://sparkle-project.org/documentation/)
- Testing: `defaults delete <bundle-id> SULastCheckTime` forces a check. Sparkle asks for permission on the second launch by default. — [Sparkle documentation](https://sparkle-project.org/documentation/)

### Inferences
- **SwiftUI / agent-app setup (standard Sparkle 2 API; snippet not shown on the fetched page):**
  ```swift
  import Sparkle
  final class Updates { static let shared = Updates()
      let controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
      func check() { controller.checkForUpdates(nil) } }
  // Wire `Updates.shared.check()` into the dock's status-bar or context menu (a dock app is likely LSUIElement).
  ```
- **GitHub hosting:** attach the DMG to a GitHub Release and host `appcast.xml` on GitHub Pages or in the repo. Run `generate_appcast --download-url-prefix "https://github.com/<user>/<repo>/releases/download/vX.Y/" updates/` so the enclosure URLs point at the release assets. The flag exists in Sparkle 2's `generate_appcast -h`; confirm locally. `sign_update <archive>` prints `sparkle:edSignature` and `length` for hand-built feeds.
- Add `SUEnableAutomaticChecks = YES` to skip the second-launch permission prompt (standard key; not on the fetched page).

### Gaps
- The programmatic/SwiftUI page and the `sign_update` docs weren't fetched. The release year (2026) is inferred, not shown.

## Q5. Release scripting: universal archive, Developer ID + hardened runtime, notarize, staple, DMG

### Takeaway
Archive with "Any Mac" (arm64 + x86_64), export with `method = developer-id`, verify the signature, build a DMG with an `/Applications` symlink, sign it, `notarytool submit --wait`, `stapler staple`, then run `generate_appcast` and upload to GitHub Releases. Sparkle's docs confirm the Developer ID export, DMG, and hardened-runtime requirements. The exact command flags below are standard but weren't re-fetched this session.

### Cited Findings
- Use Developer ID distribution via Archive or `xcodebuild archive` / `-exportArchive`. A notarized, Developer ID-signed DMG with an `/Applications` symlink is recommended. Hardened Runtime library validation is required for notarization. Verify with `codesign --deep --verify`. — [Sparkle documentation](https://sparkle-project.org/documentation/)

### Inferences (standard Apple toolchain; flags not re-verified this session)
```bash
set -euo pipefail
APP=RetroDock; TEAM=XXXXXXXXXX; V=$(git describe --tags)
xcodebuild -project $APP.xcodeproj -scheme $APP -configuration Release \
  -destination 'generic/platform=macOS' -archivePath build/$APP.xcarchive \
  ARCHS="arm64 x86_64" ONLY_ACTIVE_ARCH=NO ENABLE_HARDENED_RUNTIME=YES archive
# ExportOptions.plist: method=developer-id, teamID=$TEAM, signingStyle=automatic
xcodebuild -exportArchive -archivePath build/$APP.xcarchive \
  -exportOptionsPlist ExportOptions.plist -exportPath build/export
lipo -archs build/export/$APP.app/Contents/MacOS/$APP          # expect: x86_64 arm64
codesign --verify --deep --strict --verbose=2 build/export/$APP.app
mkdir -p build/dmg && cp -R build/export/$APP.app build/dmg/ && ln -sf /Applications build/dmg/Applications
hdiutil create -volname "$APP" -srcfolder build/dmg -ov -format UDZO build/$APP-$V.dmg   # or: create-dmg (brew) for background/layout
codesign --sign "Developer ID Application: <Name> ($TEAM)" --timestamp build/$APP-$V.dmg
# one-time: xcrun notarytool store-credentials AC_NOTARY --apple-id <id> --team-id $TEAM --password <app-specific-pw>
xcrun notarytool submit build/$APP-$V.dmg --keychain-profile AC_NOTARY --wait
xcrun stapler staple build/$APP-$V.dmg
spctl -a -vv -t open --context context:primary-signature build/$APP-$V.dmg
cp build/$APP-$V.dmg updates/ && ./bin/generate_appcast \
  --download-url-prefix "https://github.com/<user>/<repo>/releases/download/$V/" updates/
gh release create "$V" build/$APP-$V.dmg --notes-file updates/$APP-$V.md
```
- Notarize the DMG, not just the `.app`. Stapling the DMG covers the first launch offline. Sparkle installs from the DMG, so the enclosed app must already be signed with the hardened runtime.
- Recommended safety rail: run `generate_appcast` only after stapling, so the signature and length in the feed match the final bytes.

### Gaps
- Apple's notarytool, stapler, and `ExportOptions.plist` documentation weren't fetched. If needed, confirm Xcode 27 export-method key names (e.g., that `developer-id` is unchanged).
