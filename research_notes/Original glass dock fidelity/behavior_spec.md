# Original glass Dock (10.5 Leopard – 10.9 Mavericks): behaviour & animation spec

Tags: **[S]** = sourced (URL given), **[S-mimic]** = taken from an open-source dock built to copy OS X (Plank, which came from Docky), not from Apple, **[I]** = inferred (from memory of the real Dock, from the maths, or from later macOS). Apple never published timing constants for the Dock. The magnification maths is the only part Apple documented, in its Dock patent.

Key sources:
- P = US Patent 7,434,177 B1, "User interface for providing consolidation and access" (Jobs, Ording, Lindsay). This is the Dock patent. https://patents.google.com/patent/US7434177B1/en
- PT = Plank `DockTheme.vala` https://github.com/ricotz/plank/blob/master/lib/Drawing/DockTheme.vala
- PP = Plank `PositionManager.vala` https://github.com/ricotz/plank/blob/master/lib/PositionManager.vala
- MD = macos-defaults.com (only tested on Mojave and later): https://macos-defaults.com/dock/autohide-time-modifier.html , https://macos-defaults.com/dock/autohide-delay.html

---

## 1. Magnification

### Falloff: a sine displacement field, not a raised cosine [S: P]
The patent says it scales "any tile that lies even partially within W pixels to either side of the cursor". It does not sample a scale curve at each icon's centre. It moves each tile's edges:

```
S  = ((H - h) / 2) / sin(π · (h/2) / (2W))        // Eq.1  H = largesize, h = tilesize, W = effect width (px)
d' = S · sin(π/2 · clamp(d, -W, W) / W)           // Eq.2/3, d = signed distance of a tile EDGE from the cursor
scale = 1 + (d2' - d1') / (d2 - d1)               // Eq.4, applied to width AND height
```
- How I read it [I, but it is the only reading consistent with Eq.4 and the "shift by S" text]: d' is a displacement. A new edge position is `d + d'`.
- Tiles fully outside ±W "will be shifted away from the cursor position by the scale amount S, resulting in the userbar's width increasing by up to 2S" [S: P].
- Each tile is "scaled equally in both width and height from the lower left hand corner" [S: P]. In other words, icons grow up from the shelf line.
- Consequences [I, they follow from the maths]:
  - `f(0) = 0`, so the point under the pointer never moves. You get pointer anchoring for free and need no separate correction step.
  - A tile centred on the pointer comes out exactly H. Off-centre tiles never reach H. With the pointer on the boundary between two tiles, both are 125 px at h=48, H=128, W=3h.
  - The local scale is `1 + S·π/(2W)·cos(πd/2W)`. That is a quarter-wave cosine on each side, not `(1+cos)/2`. It has a slight kink where it reaches 1 at ±W.
  - Growth is symmetric about the pointer (±S), not about the dock's centre. Near an end, that end moves less.
- **W is not published.** The patent only says W "can be chosen to be a multiple of the default tile width" [S: P]. The table below shows the results; my calibration guess is **W ≈ 3 × tilesize** [I]:

| W | S (px) | total growth 2S | sizes: centre, ±1, ±2, ±3 (h=48, H=128) |
|---|---|---|---|
| 2h | 104 | 209 | 128, 105, 56, 48 |
| 2.5h | 129 | 259 | 128, 113, 73, 48 |
| **3h** | 155 | 309 | **128, 117, 88, 53** |
| your raised cosine, r=3.2 | – | – | ≈128, 110, 73, 49 |

  So the original bump is broader and flatter on top than yours: about 2 large neighbours and a slight 3rd on each side.

### Sizes [S]
- Default tile 64×64, range 16–128. Upper limit on magnification about 128, user-adjustable. Magnified size is never below tile size [S: P].
- Defaults: `largesize` 128, `tilesize` 64 [S: https://mosen.github.io/profiledocs/payloads/mac/dock.html]. Modern macos-defaults lists `tilesize` 48 [S: https://macos-defaults.com/dock/tilesize.html (via mirror)]. The out-of-box plist varied by Mac model [I]. Use 48 for a typical "stock" look and 64 for the built-in default.
- Magnification is off out of the box (`magnification` = false) [I].

### Row and shelf growth
- The bar width increases by up to 2S [S: P]. The glass floor is drawn under the span from the first to the last icon, so it widens and narrows live with the bump [I]. Plank does the same: the window does not resize, but the background rect is recomputed from the zoomed first and last items [S: PP].
- The dock is not re-centred while magnified. Each end moves outward by however far its outermost icon was pushed [I, from P].

### Enter / leave
- Tracking is instant while the pointer is inside. Each mouseMoved recomputes everything, with no smoothing lag [I].
- Magnification "can be canceled when the cursor leaves the content region" [S: P].
- In 10.5–10.9 the bump grows in when the pointer enters and settles back when it leaves, over a short ramp of about **0.15–0.2 s, ease-out** [I]. Plank does the same with a 0→1 `zoom_in_progress` that multiplies `(zoom − 1)` [S: PP]. Animate one global amount `t` and use `H_eff = h + (H − h)·t`. Do not animate per-icon sizes.
- Holding Ctrl+Shift while over the Dock toggles magnification temporarily [S, title only: https://discmaster.textfiles.com/file/11593/db.tidbits.com.tar/db.tidbits.com/article/2445.html].

## 2. Auto-hide
- `autohide-delay` (delay before showing) defaults to **0.2 s** [S: MD]. A forum user recalls 0.24 s [S: https://spy.macrumors.com/threads/delaying-dock-autohide.2003990/]. It is likely the same in 10.5–10.9 [I].
- `autohide-time-modifier` defaults to 0.5. MD says "By default, the Dock opening and closing animations take 0.5 seconds" [S: MD]. **Change your 0.22 s slide to about 0.5 s.** Setting it to 0 removes the animation [S: MD].
- Easing is ease-in-out. The whole dock (shelf, icons and indicators) slides fully past the screen edge [I]. The patent says it "will animate (e.g., slide) downwards, offscreen" when the cursor leaves [S: P].
- The reveal fires when the pointer hits the outermost pixel row of the screen edge, held for the delay. The trigger zone is limited to the dock's resting horizontal extent [I, moderate confidence]. The dock re-hides as soon as the pointer leaves the dock's bounds plus a small margin, with no delay [I].
- The dock stays shown while one of its menus is open or during a drag that is over it [I].

## 3. Launch bounce vs attention bounce
- Apple published no constants. The closest documented OS X copy is Plank: `LaunchBounceTime` 600 ms, `LaunchBounceHeight` 0.625 × icon, `UrgentBounceTime` 600 ms, `UrgentBounceHeight` 1.67 × icon (5/3), `ClickTime` 300 ms [S-mimic: PT].
- Changes for you [I]:
  - Raise the height from 0.42 to **about 0.6 × the current (magnified) icon size**.
  - Keep 0.6 s per hop.
  - Use a ballistic parabola: decelerate on the way up, accelerate on the way down (y = 4h·t(1−t)).
  - **No squash or stretch** in 10.5–10.9. The icon stays rigid, and its reflection moves with it.
  - The bounce repeats until the app finishes launching (checks in with the Dock), then finishes the current hop and lands. Never stop in mid-air.
  - The indicator light appears when the launch starts. The `launchanim` = false key disables the bounce (well known, not fetched).
- Attention bounce (`requestUserAttention`):
  - Critical requests bounce until the app is activated or the request is cancelled.
  - "Informational: The dock icon will bounce for one second. The request, though, remains active until either the app becomes active or the request is canceled." [S: https://developer.apple.com/documentation/appkit/nsapplication/requestuserattentiontype/informationalrequest]
  - Adobe's AIR docs describe informational as bouncing once and critical as bouncing until the app comes to the front [S: https://www.few.vu.nl/~eliens/assets/flex3/langref/flash/desktop/DockIcon.html].
  - Calling it on an already-active app has no effect. Activating the app cancels the request [S: https://developer.apple.com/documentation/appkit/nsapplication/requestuserattention(_:)].
  - The attention hop is much taller than the launch hop, about 1.5–1.7 × icon [S-mimic: PT / I], with continuous hops at roughly the same cadence.
  - With auto-hide on, the bouncing icon pokes up from the screen edge without revealing the dock [I].

## 4. Poof
- The art is `Dock.app/Contents/Resources/poof.png`: **5 frames, each 128×128**, transparent [S: https://forums.macrumors.com/threads/the-animation-when-you-drag-off-the-dock.118582/ ; https://www.theregister.com/2009/05/29/mac_secrets_cloud_poof/]. The Dock uses its own poof code, not `NSShowAnimationEffect` [S: The Register].
- **Replace your scale+fade with a flipbook** [I]:
  - On mouse-up the icon vanishes instantly.
  - Play the 5 frames centred on the drop point, not the old slot.
  - Total about **0.25–0.35 s** (≈ 60 ms per frame).
  - Draw it at about the dragged icon's size; the native size is 128.
  - Play the poof sound, a short cloud "pfft".
- Trigger: once the dragged icon leaves the dock's bounds, which is roughly a tile above the shelf, there is no hold time [I]. While outside:
  - The cursor becomes `NSCursor.disappearingItem` [S: https://developer.apple.com/documentation/appkit/nscursor/disappearingitem, "for example, when dragging an item from the dock"].
  - The gap closes. It reopens if you drag back in [I].
- The **"Remove" label and the farther drag distance are from later macOS** [S, modern: https://support.apple.com/guide/mac-help/use-the-dock-on-mac-mh35859/mac]. Do not use them for the glass era [I].
- What can and cannot be poofed [I]:
  - A running app dragged out does not poof. It is un-kept and slides back until the app quits.
  - Finder and Trash cannot be removed; they slide back.

## 5. Drag-to-reorder
- Neighbours slide apart to open a slot at the insertion point and close the old slot, with ease-out over about **0.2–0.3 s** [I]. Plank uses `ItemMoveTime` 450 ms for move, add and remove [S-mimic: PT]. Treat 450 as an upper bound.
- The dragged icon follows the pointer at the size it had when picked up (magnified, if magnification is on). It is opaque, with no reflection. Magnification keeps running around the gap during the drag [I].
- Rules [I, standard Dock behaviour]:
  - **Finder is always first (left or top). Trash is always last.** Neither can be moved or removed.
  - Apps live left of the divider. Documents, folders, stacks and minimised windows live right of it, and items cannot cross.
  - Dragging a file over an app icon highlights the app if it accepts that file, with no gap. Over the documents side, a gap opens.

## 6. Clicking
- Pressed state [I]: the icon darkens instantly on mouse-down, with about a **35–40 % black overlay** (≈ 0.6–0.65 brightness). It clears on mouse-up or when the pointer leaves the icon.
- Clicking a running app [I, standard AppKit]:
  - It activates the app and unhides it if hidden.
  - It sends the reopen Apple Event (`kAEReopenApplication` → `applicationShouldHandleReopen:hasVisibleWindows:`), so a windowless app opens a new window.
  - Clicking a non-running kept app launches it and starts the bounce.
- Modifiers [S: https://support.apple.com/guide/mac-help/use-the-dock-on-mac-mh35859/mac]:
  - Cmd-click: show in Finder.
  - Option-click the current app: hide it and switch to the previous app.
  - Option-Cmd-click an app: switch to it and hide all others.
  - Control-click: shortcut menu.
- Click-and-hold [I]: in 10.5 it opens the menu after about 0.5 s. From 10.6 Snow Leopard it opens App Exposé for that app.

## 7. Hover labels
- "A fade in time of zero milliseconds"; zero ms for fading in and out between tiles. Only one label shows at a time. When the cursor leaves the bar, "the last label presented persists for a short period, e.g., 250 milliseconds, then fades out" [S: P].
- **There is no hover delay.** The label switches instantly from icon to icon [S: P].
- The label sits a few px above the top of the icon's current magnified size and stays centred on it, so it moves as the bump moves [I]. Style: a dark translucent rounded pill with white text, the glass-era look [I].

## 8. Running indicators
- 10.5–10.9: a blue-white glowing "light" on the glass floor under the icon. TidBITS found it hard to see on the shelf [S: https://tidbits.com/2007/10/26/six-things-i-hate-about-leopard/].
- The light appears when the launch starts, with a quick fade of about 0.15 s [I]. On quit it disappears; if the app is not kept, the icon then slides out and the neighbours close up (same timing as §5) [I].
- In 10.7 Lion the lights became a checkbox (`show-process-indicators`). Users reported it **off by default on clean installs** [S, anecdotal: https://www.mactrast.com/2011/10/mac-tip-dock-open-application-indicator-lights-in-mac-os-x-lion/ ; https://gist.github.com/jinkim/1265305].
- **Hidden apps still show the light.** `showhidden` = true makes hidden apps' icons translucent; it is off by default [I].

## 9. Other things that make it feel right
- Icons grow from the bottom edge [S: P].
- The shelf width follows the bump live (§1).
- Reflections in the floor are scaled and bounced together with the icon [I].
- `no-glass` = YES gives the 2D look, for reference [S: https://krypted.com/tag/no-glass].
- Minimise effects, noted only [I]:
  - Genie is the default; `mineffect` scale and suck are alternatives.
  - Shift+minimise/restore plays the genie in slow motion.
  - The minimised window becomes a thumbnail tile to the right of the divider.
- Divider [I]: drag it to resize the tile size live; Option-drag snaps to standard sizes; right-click gives the magnification and position menu.
- Badges (red count ovals) scale with the icon [I].
- Siracusa's Ars reviews were not retrieved within the search budget. They contain no published constants as far as I know [I].
