# Original 3D glass Dock (10.5–10.9): visual spec for procedural recreation

Scope: the bottom-position 3D shelf Dock in Mac OS X 10.5 Leopard through OS X 10.9 Mavericks. The 2D side Dock is out of scope. No Apple image files were copied or redistributed. Apple's resources are described only by name and size, as community docs and code list them. Screen measurements come from public, low-resolution Wikipedia screenshots, measured pixel by pixel in a scratch folder and not kept.

**Tags:** **[S]** = sourced (URL given), **[M]** = measured by me from a public screenshot (method below), **[I]** = inferred or recalled, not verified. The reference icon size is **s = 64 px** (1x points). Both measured screenshots show roughly 64 px tiles.

## 0. Sources and measurement method

- **dockify** (Alex Zielenski) README covers the theme file names, sizes and plist keys: https://github.com/alexzielenski/dockify/blob/master/README.md
- **dockify_library** source re-creates the pre-10.10 3D floor on 10.10+ Dock internals: https://github.com/alexzielenski/dockify_library. The files used here:
  - `Dockify/theme/DKFloorLayer.m`: 3D floor = trapezoid via rect→quad transform; 3D floor height = 0.63 × 2D floor height
  - `Dockify/helpers/math.c`: `offsetForHeight()` = how far the front corners stick out
  - `Dockify/DKTheme.m`: scurve and indicator size buckets
  - `Dockify/theme/DKTile.m`: in 3D mode, tiles are pushed down by 0.1 × tile height
  - `Dockify/theme/DKindicatorLayer.m`: the indicator is a bitmap anchored at y = 0, with bottom gravity
  - `Dockify/dump/Tile.h`: class-dump; the Dock fades indicators in and out with `indicatorBlendFrom/To/Dur`
- **Measured screenshots** (non-free and low-res, used only for measurement):
  - **M-ML:** https://en.wikipedia.org/wiki/File:OS_X_3D_Dock.png. 708×84, native 1x, a Dock window capture with transparent margins. Uploaded 2012-08-24, and the Calendar icon reads "AUG 24", so this is **10.8 Mountain Lion**. The description says 10.8/10.9.
  - **M-Leo:** https://en.wikipedia.org/wiki/File:Leopard_Desktop.png. 800×500, a 0.625× downscale of 1280×800. The menu bar is 13 px, about 22 × 0.6. Native values below are scaled back by ÷0.625, so expect about ±2 px error.
  - **M-SL / M-ML2 / M-Mav:** `File:Snow_Leopard_Desktop.png`, `File:OS_X_Mountain_Lion_Screenshot.jpg` and `File:OS_X_Mavericks_Desktop.png`. All are 400×250 (0.3125×) and usable only for colour, tint and presence checks.
- **Siracusa's Mavericks review** (Ars Technica, a full-text copy): https://gist.github.com/cmenscher/7108234
- **ASCII.jp, ML vs Mavericks Dock:** https://weekly.ascii.jp/elem/000/002/620/2620042/
- **MacRumors, ML indicator lights:** https://forums.macrumors.com/threads/dock-indicator-lights.1412619/ and https://forums.macrumors.com/threads/no-indicator-lights-in-mountain-lion.1420384. Mavericks "too far down": https://forums.macrumors.com/threads/dock-indicator-lights-too-far-down.1860976
- **Macworld, Leopard indicator files:** https://www.macworld.com/article/189380/105dockactive.html
- **CSS Dock recreation (2011)**, for label values: https://github.com/michaelhue/cssdock (`source/dock.css`)
- **Dock size ranges:** https://docs.applivery.com/en/device-management/apple/macos/policies/dock-configuration.md
- **Not reachable this session:** Ars Technica directly (Siracusa's 10.5 review) and web.archive.org, both blocked for fetching. Nothing here quotes the 10.5 review.

---

## Version mapping verdict

| OldMacDonal style | Proposed | Verdict |
|---|---|---|
| Clear Glass | 10.5 / 10.6 / 10.7 | **Confirmed.** Leopard and Snow Leopard share the same shelf, zebra separator and blue blob indicator [M-Leo, M-SL]. One forum post says the indicators of 10.5–10.7 changed in 10.8 [S: MacRumors]. Lion is treated as identical [I]. |
| Frosted | 10.8 Mountain Lion | **Confirmed.** 10.8 replaced the shelf with a smooth, lighter, cool-grey frosted floor [M-ML]. It also switched to a 1 px white front line over a 3 px grey front lip, a thin groove separator, and a small white bar indicator on the front lip [M-ML]. ASCII calls the 10.8 texture "opaque, smoked-glass-like" (不透明なスモークガラス風) [S: ASCII]. |
| Smoke | 10.9 Mavericks | **Mostly wrong as a "darker" look.** Siracusa: "the Dock looks the same (in its default position, anyway). Move the Dock to the side to reveal its new smoked glass appearance" [S: gist]. Mavericks' "smoked glass" is the **side** Dock. ASCII says the bottom texture became **more see-through**, "like the iOS 7 Dock" [S]. Measured: 10.9 has the same geometry, front lip and bar indicator as 10.8, with a floor tinted more strongly by the wallpaper [M-Mav]. |

**Recommendation:**
- **Frosted** = 10.8: a more opaque frosted floor with little wallpaper tint.
- **10.9** = the same art with more translucency: blur plus about 50% wallpaper show-through.
- A darker **Smoke** shelf is not a historical bottom-shelf look. Ship it as an original variant, or base it loosely on the 10.9 side-Dock smoked glass, which is out of scope.

---

## 1. Shelf (floor)

### Geometry. Same construction in all versions; small differences noted.

- **Construction [S: DKFloorLayer.m]:** a flat rectangular texture is mapped with a rect→quad homography into an isosceles trapezoid. The back (top) corners sit at x = 0 and x = w. The front (bottom) corners sit at −o and w + o.
- **Front-corner overhang [S: math.c]:** `o = 12 + ceil((h − 17) × 0.5)`, where h is the floor height. It depends on h only, not on dock width, so the end slant is constant. There is no true shared vanishing point across dock widths [I, matches both measurements].
- **Measured end slant:**
  - Leopard: +25 px per side over 52 px (0.48 px/px, about 26° from vertical) [M-Leo].
  - 10.8: +25 px per side over 46 px (0.54, about 28°) [M-ML].
  - The Dockify formula gives 27–30 px.
- **Total height, back edge to screen bottom:**

  | | Leopard [M-Leo] | 10.8 [M-ML] |
  |---|---|---|
  | Total | 52 px = 0.81 s | 50 px = 0.78 s |
  | Breakdown | — | 46 px floor + 1 px front line + 3 px lip |

  - Dockify's 3D floor height is 0.63 × the 10.10 2D floor [S].
  - Scale it linearly with icon size, with a minimum of about 17 px (Dockify's `minHeight`) [I].
- **No tilt angle exists.** It is a 2D trapezoid, not a rotated plane. To use Core Animation, set a homography `CATransform3D` on the floor layer, the way Dockify's `CATransform3DrectToQuad` does. Do not use `rotate + m34`.
- **Back edge versus the outermost tiles:**
  - Leopard: back edge ≈ outer tile edge + 6–8 px (about 0.1 s). That is about 16 px beyond the icon art [M-Leo].
  - 10.8: back edge ≈ outer tile edge + 0–4 px [M-ML].
  - The front edge then adds o on each side.
- **Back width vs front width:**
  - 10.8 example: 556 → 606 px (front about 9% wider).
  - Leopard example: 1040 → 1090 px (about 5% wider).
  - The absolute difference is 2o, about 50 px [M].
- **Corners:**
  - The back corners are slightly rounded, r ≈ 3 px [M-ML]. Leopard's are similar, but the measurement is at 0.625× [M-Leo].
  - The 10.8 front-lip bottom corners have r ≈ 2 px.
  - The slanted sides are plain anti-aliased edges with no highlight stroke in either version [M].

### Colour and gradient

**Leopard / Snow Leopard [M-Leo, over a near-black wallpaper]**

- **Rear band:** the back edge to about 40% of depth (about 20 px at s = 64). Luminance runs 117 → 153, RGB ≈ (116,115,120) → (152,152,157). It is neutral grey, with B about +4.
- **Step:** a fairly hard edge (about 1–2 px) down to luminance about 119. It sits about 20 px from the back edge, just behind the icon art bottoms. Its position drifts 2–6 px across the width, so part of it may be reflection [M].
- **Front band:** about 42% to 94% of depth, luminance 119 → 137.
- **Dark line:** about 1.5 px at luminance about 119, just behind the front line.
- **Front line:** about 3 px of the bottom, a bright gradient with luminance about 155 → 225–235. This matches `frontline.png` at 790×3 [S: dockify README].
- **No front lip** shows below the front line.
- **Transparency:** low. On Snow Leopard's purple wallpaper the floor picks up only a faint purple tint [M-SL]. Model it as neutral grey at about 0.85 opacity, or as white at α 0.45–0.6 [I].
- **Blur:** none [I].

**10.8 Mountain Lion [M-ML]**

- **Gradient:** smooth and monotonic, with no step.
  - Back: RGB (114,130,143), luminance 133.
  - Middle (row +16): luminance 145.
  - Row +26: luminance 170.
  - Row +36: luminance 189.
  - Front: RGB (193,202,210), luminance 203.
  - The hue is cool blue-grey.
- **Wallpaper:** over a dark navy wallpaper the floor reads as neutral (124,128,131) → (184,185,189) [M-ML2].
- **Transmission:** about 0.3–0.5 of the blurred wallpaper [M-ML2, estimated].
- **Front line:** 1 px pure white, 250–255.
- **Front lip:** 3 px, opaque, RGB ≈ (137,143,149), flat.

**10.9 Mavericks [M-Mav]**

- Same structure as 10.8.
- Over the blue wave wallpaper: back (119,147,171), front (210,224,236). The lip is RGB ≈ (157,168,176).
- **Transmission:** about 0.5–0.6 [estimated]. It is more see-through than 10.8, consistent with ASCII [S].

### Resource files (Apple; described, not copied) [S: dockify README and DKTheme.m]

| File | Size (px) | Role |
|---|---|---|
| scurve-sm | 900×128 | Floor texture |
| scurve-m | 1280×128 | Floor texture |
| scurve-l | 1280×98 | Floor texture |
| scurve-xl | 1280×86 | Floor texture |
| frontline.png | 790×3 | Front-edge strip |
| separator.png | 64×128 | Separator, an upright image |
| indicator_small / medium / large | No size published | Running indicators (3D) |
| `indicator_*_simple` | No size published | Running indicators (2D) [S: Macworld] |

- **Floor texture selection:** Dockify picks by floor size [S]:
  - Width ≤ 1090 → sm.
  - Height ≤ 86 and width > 1090 → xl.
  - Height ≤ 98 and width > 1090 → l.
  - Otherwise → m.
- The whole texture is stretched into the trapezoid. Nothing is 9-sliced in 3D [S: DKFloorLayer.m].
- The front line is stretched horizontally across the front edge [I].
- `@2x` versions are double size [S].

## 2. Where icons stand; icon shadow

- **Icon base (bottom of the tile canvas):** the base is measured from the reflection axis.

  | | Leopard [M-Leo] | 10.8 [M-ML] |
  |---|---|---|
  | Base above screen bottom | 23 px = 0.36 s | 19 px = 0.30 s |
  | Back edge above base | 29 px = 0.45 s | 31 px = 0.48 s |
  | Base in the floor depth | ~59% from back, ~20 px behind the front line | ~67% from back, 15 px behind the front line |

- About half of each icon overlaps the floor.
- **Icons never overlap the front line.** Their reflections reach it and are clipped there [M].
- Dockify pushes 3D tiles down 10% of the tile height, relative to the 10.10 2D layout [S: DKTile.m].
- **Icon shadow:** 10.8 shows a soft darkening about 4–6 px tall under icon art. It starts about −60 luminance and fades to 0 [M-ML]. Leopard shows about −15 to −20 luminance over 2–3 px [M-Leo].
  - This may be part of the icon art.
  - The Dock does generate a per-tile "shadows and reflection" (`generateShadowsAndReflection` in the 10.10 class-dump) [S: dockify dump].
  - Recommendation: a contact shadow of black at α 0.25–0.35, blur 3 px, offset −2 px, clipped to the floor [I].

## 3. Reflections

- **Mirror:** a 1:1 vertical mirror about the tile base, with no squash. The mirror pairs are symmetric, e.g. Safari's ring and blue face are reflected at equal distances [M-Leo, M-ML].
- **Extent:** the mirror runs from the base to the front line, where it is clipped. That is about 15 px at s = 64 in 10.8 and about 23 px in Leopard.
- **Opacity:**
  - 10.8: about **0.30**, measured from iTunes' blue: ΔR and ΔB both give 0.30–0.31. Little fade before the front line [M-ML].
  - Dockify's theme default `reflectionOpacity` is **31.5** (percent) [S: README].
  - Leopard reads stronger, about 0.35–0.5 just under the base, fading toward the front. The blend looks partly additive or screen-like [M-Leo].
- **Windows and desktop reflections:** Leopard also reflected windows and the desktop (per the brief). In M-Leo a star 9.5 px above the back edge shows up about 7 px into the floor, so the mirror is squashed about 0.7× [M]. Noted only.

## 4. Running indicator

**10.5–10.7: blue-white glowing blob on the floor surface [M-Leo; S: Macworld "the blueish blobs below running programs"]**

- **Position:** centred under the icon. The blob centre is about 9 px above the screen bottom, about 6 px behind the front line, and about 14 px in front of the icon base. It sits in the reflection zone.
- **Core:** a flattened ellipse about 8 × 5 px (about 0.13 s wide). Peak RGB ≈ (191–227, 236–254, 255): near-white with a cyan-blue cast.
- **Inner glow:** about 14 × 6 px.
- **Outer halo:** about 16–20 × 10 px, colour ≈ (130,180,225), at about 0.5 over the floor.
- **Sizes:** three fixed bitmaps (small / medium / large), not continuously scaled [S: Macworld].
  - Dockify's buckets: icon ≤ 44 → small, ≤ 72 → medium, ≤ 100 → large, otherwise xl [S: DKTheme.m].
  - Recommendation: draw procedurally and scale the core width at 0.12–0.14 s, with a glow radius of about 0.08 s [I].
- **Animation:** fades in and out (`indicatorBlend*` ivars) [S: Tile.h dump].

**10.8 and 10.9: small white bar on the front lip [M-ML, M-ML2, M-Mav; S: MacRumors "at the edge of the screen", "hard to see", 10.9 "too far down"]**

- **Bar:** 10 px solid plus 1 px anti-aliasing on each side, for 12 px total (about 0.17 s). It is 3 px tall and fills the lip's height.
  - Row values top to bottom: about 240, 255, about 213.
- **Halo:** pale blue, (145,179,202), extending about 6 px left and right on the lip. A faint blue wash (+10–20 B) rises about 5 px up into the floor.
- ASCII says the indicator changed "from round to bar" [S]. The 10.8 screenshot already shows a bar, so treat that claim as unreliable for 10.8→10.9 [M].

## 5. Separator

**10.5–10.7: "zebra crossing" [M-Leo; M-SL confirms]**

- **Bars:** 8 white bars stacked from back to front. They are upright, centred on one vertical axis with no perspective lean, even about 300 px (native) off-centre. This is an upright image, `separator.png` at 64×128 [S].
- **Positions and sizes** (native px at s ≈ 64, measured from the back edge):

  | Bar | Start | Height | Width |
  |---|---|---|---|
  | 1 | 2.4 | 1.6 | 10 |
  | 2 | 5.6 | 1.6 | — |
  | 3 | 8.8 | 1.6 | 13 |
  | 4 | 12.0 | 3.2 | — |
  | 5 | 16.8 | 3.2 | 16 |
  | 6 | 23.2 | 3.2 | 17 |
  | 7 | 29.6 | 4.8 | 19 |
  | 8 | 39.2 | 4.8 | 22 |

  - The last bar ends at about 43 px, about 6 px before the front line.
  - Gap ≈ bar height (1.6 → 4.8). Both grow geometrically, about ×1.25 per bar.
  - Width grows about 0.16 s → 0.34 s.
- **Colour:** white at α ≈ 0.35 over the floor (+30 to +45 luminance).

**10.8 and 10.9: thin groove line [M-ML, M-Mav]**

- **Line:** 1 px dark (floor −25 to −35 luminance, e.g. 106–110 on a 135–140 floor), with a 1 px light companion on the outer side (+15 to +30).
- **Span:** from about 4 px below the back edge to about 5 px behind the front line.
- **Perspective:** it follows the floor's homography. At 190 px right of centre it leans outward about 0.4 px per px. Generate it as the image of a vertical texture line under the same rect→quad transform.

## 6. Hover labels

There is no primary measurement; all values below are from a 2011 CSS recreation [S: cssdock `dock.css`] or inferred.

- **Font:** Lucida Grande, the system font through 10.9 [I, well known]. 14 px, regular, white, with text shadow 1 px 1 px 1 px rgba(0,0,0,0.9) [S: cssdock].
- **Lozenge:** rgba(0,0,0,0.6), border-radius 12 px (pill-like at about 24 px height), padding 5 px 12 px [S: cssdock].
- **Placement:** the recreation puts the label 34 px above the item's top. Recommendation: about 8–12 px above the top of the icon art. Use the magnified size when magnification is on [I].
- **Arrow:** the recreation adds a 6 px downward arrow. Apple's bottom 3D Dock is recalled as having **no arrow**, an unverified recollection: the arrow belonged to the side Dock [I, unverified].
- **Version changes:** none known for 10.5–10.9. 10.10 switched to Helvetica Neue and a light label [I].

## 7. Trash, as a description for drawing your own

**Leopard [M-Leo crop, described]**

- **Body:** a cylindrical wastebasket, slightly tapered toward the base. It is dark grey, fine wire mesh with diamond or hex perforation.
- **Shading:** a vertical cylindrical highlight that is lighter left of centre and darker at the sides.
- **Rim:** a thick, polished chrome rolled rim seen slightly from above, as an ellipse. The darker interior and back mesh show through the opening.
- **Base:** a thin chrome band.
- **Full state:** crumpled white paper is visible through the mesh and pokes above the rim.

**10.8 and 10.9:** the same concept, but lighter silver perforated metal with clearly separated round holes and a brighter rim [M-ML].

## 8. Sizes and ends

- **Size ranges:** `tilesize` and `largesize` are 16–128. Maximum magnification is 128 px [S: Applivery].
- **Default size:**
  - Leopard's default `tilesize` is **not verified**. Modern macOS defaults to 48. MDM payload docs say 64 [S: Applivery].
  - Apple's Leopard and 10.8 screenshots both show about 64 px tiles [M].
- **Tile pitch:** about 65 px at s = 64, i.e. about 1 px between tiles [M-ML].
- **Ends:** slanted trapezoid sides (see §1), not caps. The ends are plain floor material.
  - Leopard's floor runs into the slanted edge with the same band structure.
  - 10.8's lip continues under the full front width.

---

## Compact numeric spec (s = icon size; "px" = 1x points at s = 64)

| Set | Value | Version | Source |
|---|---|---|---|
| Floor construction | Rect texture → trapezoid homography (not rotate+m34) | all | S DKFloorLayer.m |
| Floor total height (back edge → screen bottom) | 0.81 s (52 px) | 10.5–10.7 | M-Leo |
| Floor total height | 0.78 s (50 = 46 floor + 1 line + 3 lip) | 10.8–10.9 | M-ML |
| Floor minimum height | ~17 px | all | S math.c (minHeight) / I |
| Front-corner overhang per side | o = 12 + ceil((h − 17)/2) → 25–30 px | all | S math.c; M 25 px |
| End slant from vertical | ~26° (Leo) / ~28° (10.8), constant vs width | all | M |
| Back edge beyond outer tile edge | +0.1 s (Leo) / +0–4 px (10.8) | per ver. | M |
| Back-corner radius | ~3 px | all | M-ML |
| Lip bottom-corner radius | ~2 px | 10.8–10.9 | M-ML |
| Floor colour (over black), Leo | rear 0–40% depth: lum 117→153 (RGB 116,115,120→152,152,157); step; front: lum 119→137 | 10.5–10.7 | M-Leo |
| Floor opacity / blur, Leo | ~0.85 neutral grey, no blur | 10.5–10.7 | I (from M-SL tint) |
| Dark line behind front line | ~1.5 px, lum ~119 | 10.5–10.7 | M-Leo |
| Front line | ~3 px bright gradient lum 155→230, no lip | 10.5–10.7 | M-Leo; S frontline.png 790×3 |
| Floor colour, 10.8 | back (114,130,143) → front (193,202,210), smooth | 10.8 | M-ML |
| Floor transmission + blur | ~0.3–0.5 (10.8), ~0.5–0.6 (10.9) | 10.8 / 10.9 | M-ML2 / M-Mav (est.) |
| Front line | 1 px white 250–255 | 10.8–10.9 | M-ML |
| Front lip | 3 px opaque (137,143,149) [10.9: (157,168,176)] | 10.8 / 10.9 | M |
| Icon base above screen bottom | 0.36 s (Leo) / 0.30 s (10.8) | per ver. | M |
| Back edge above icon base | 0.45 s (Leo) / 0.48 s (10.8) | per ver. | M |
| Icons over front line | never; reflections clipped at it | all | M |
| Contact shadow | black α~0.3, blur ~3 px, offset −2 px | all | I (M hints) |
| Reflection | 1:1 mirror at tile base, no squash, clipped at front line | all | M |
| Reflection opacity | 0.30–0.315 (10.8); ~0.35–0.5 fading (Leo) | per ver. | M-ML; S dockify 31.5; M-Leo |
| Indicator (Leo) | blue-white blob on floor: core ~8×5 px (0.13 s), glow ~16–20×10 px (130,180,225) α~0.5; centre 9 px above bottom, ~6 px behind front line | 10.5–10.7 | M-Leo; S Macworld |
| Indicator sizes | 3 fixed bitmaps; buckets ≤44 / ≤72 / ≤100 / > | 10.5–10.7 | S Macworld; S DKTheme.m |
| Indicator (10.8/9) | white bar 10(+2 AA)×3 px on lip (0.17 s), halo (145,179,202) ±6 px | 10.8–10.9 | M-ML, M-Mav; S MacRumors |
| Indicator animation | fade in/out | all | S Tile.h dump |
| Separator (Leo) | 8 upright white bars α~0.35; width 0.16 s→0.34 s; bar = gap = 1.6→4.8 px (×~1.25/bar); span 2→43 px from back edge | 10.5–10.7 | M-Leo; S separator.png 64×128 |
| Separator (10.8/9) | 1 px dark (−30 lum) + 1 px light (+20) groove, perspective-correct, 4 px below back edge → 5 px behind front line | 10.8–10.9 | M-ML |
| Label font | Lucida Grande 14 px regular, white, shadow 1/1/1 black 0.9 | 10.5–10.9 | S cssdock; I |
| Label lozenge | black α0.6, radius 12, padding 5×12, no arrow (bottom Dock) | 10.5–10.9 | S cssdock; I (arrow) |
| Label gap above icon | ~8–12 px above (magnified) icon top | 10.5–10.9 | I |
| Tile pitch | ~s + 1 px | all | M-ML |
| Icon size range / max magnification | 16–128 / 128 | all | S Applivery |
| Default tilesize (Leopard) | unverified; screenshots ~64, modern default 48 | 10.5 | M; S Applivery |
