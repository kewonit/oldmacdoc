# Original Dock right-click menus: visuals across versions, and drawing a pointer menu in AppKit

Method note for the report writer: the Ars Technica reviews and Apple's old HIG pages were read through the Wayback Machine, because arstechnica.com and lists.apple.com block or 502 direct fetches. Every pixel measurement below is my own. I downloaded each screenshot, converted it with `sips` and sampled pixels. I label these "measured (estimate)". JPEG artefacts mean ±1–2 px, and when an image is scaled I give ratios normalised to a 19 px menu row. "Local" sources are files on this machine, which runs macOS 27.0.1 (build 26A434) with Xcode's macOS SDK.

## Q1. What did Dock tile menus look like in 10.5 Leopard, 10.6 Snow Leopard, 10.7 Lion and 10.8 Mountain Lion (and just before/after)?

### Takeaway
From 10.0 through at least 10.12, Dock menus were drawn by the Dock, not by a standard NSMenu. Each one was a rounded-rect menu with a triangular pointer about 26×13 px. The pointer was centred on the icon. The menu was not centred: its left edge sat near the icon's left edge, so the pointer was about 23–28 px in from the menu's left side. Leopard (10.5) used the light standard pop-up-menu look plus the pointer. Snow Leopard (10.6) introduced a Dock-only dark translucent "charcoal" menu with white text, a thin translucent light border and a blue gradient highlight. Lion and Mountain Lion are not light: Apple's own Mavericks-era HIG screenshot shows the same dark bordered menu, so 10.7–10.9 almost certainly kept the Snow Leopard style.

### Cited Findings

**Pre-Leopard (10.0–10.4): the pointer predates Leopard**
- In 2002 a developer wrote that "Most contextual menus... are just rectangles but if you control-click on the Dock, it's 'pointy'", and asked how to replicate it. — [cocoa-dev, Aug 2002](https://lists.apple.com/archives/cocoa-dev/2002/Aug/msg01008.html) (read via [Wayback](https://web.archive.org/web/2020/https://lists.apple.com/archives/cocoa-dev/2002/Aug/msg01008.html))
- In 2004 the pointer was described as "the arrow point that points to the dock and is attached to the standard rectangular pop-up menu that is _not_ present in regular contextual menus." — [cocoa-dev, Apr 2004](https://lists.apple.com/archives/cocoa-dev/2004/Apr/msg00221.html)

**10.5 Leopard (2007): light standard menu plus pointer**
- Siracusa: "Leopard's menus also have a subtle change: rounded corners. Only the lower corners are rounded in drop-down menus, while all four corners are rounded in pop-up menus." His pop-up example is the Dock's Trash menu, captioned "Pop-up menu (graphite)". — [Siracusa, Leopard review p.4](https://web.archive.org/web/2012/http://arstechnica.com/apple/reviews/2007/10/mac-os-x-10-5.ars/4); [screenshot dock-trash-menu.jpg](https://web.archive.org/web/20120723092644im_/http://origin.arstechnica.com/reviews/os/mac-os-x-10-5.media/dock-trash-menu.jpg)
- Siracusa: "The new menu highlight color is a deep, rich blue or an appropriately slatey gray, both with the obligatory gradients." — [Leopard review p.4](https://web.archive.org/web/2012/http://arstechnica.com/apple/reviews/2007/10/mac-os-x-10-5.ars/4)
- In Nov 2007 (Leopard era), Peter Ammon answered on cocoa-dev: "No, there is no way to get a Dock-menu appearance" for `[NSMenu popUpContextMenu:...]`. Another poster claimed the Dock no longer had the look. David Alger corrected him: "Control-click any application in the Dock and you get a popup menu with a little triangle pointing back towards the application you clicked on." — [cocoa-dev msg00992](https://lists.apple.com/archives/Cocoa-dev/2007/Nov/msg00992.html), [msg01018](https://lists.apple.com/archives/Cocoa-dev/2007/Nov/msg01018.html)
- Measured (estimate) from the Leopard Trash screenshot (184×194, assumed 1:1):
  - Body is light: the composite is about rgb(218,218,218) over a near-black desktop rgb(8,7,13). That equals roughly 85% white, or a slightly off-white at higher opacity; the two can't be separated.
  - Corner radius is about 3–4 px.
  - Top padding is about 4 px.
  - Rows are 19 px: the highlight runs from y=33 to y=51.
  - The graphite highlight is a vertical gradient from about rgb(102,107,113) to rgb(92,97,103). It runs edge to edge with no inset, and the highlighted text is white.
  - "Empty Trash" is disabled, drawn in gray text.
  - Pointer:
    - Filled in the menu colour with no distinct stroke.
    - Base about 26–27 px, height about 13 px, apex about 90°.
    - Apex at x≈55, the Trash icon's centre (≈56).
    - Menu left edge at x≈31–32, so the pointer axis is about 23 px from the left edge.
    - Menu width is about 127 px.
    - About 7 px between the pointer tip and the top of the Trash artwork.
  - Source: [dock-trash-menu.jpg](https://web.archive.org/web/20120723092644im_/http://origin.arstechnica.com/reviews/os/mac-os-x-10-5.media/dock-trash-menu.jpg)

**10.6 Snow Leopard (2009): the Dock-only dark "HUD" menu**
- Siracusa: "any and all pop-up menus on the Dock—and only on the Dock—have a unique look in Snow Leopard, complete with a custom selection appearance (which, for a change, does a passable job of matching the system-wide selection appearance setting)." — [Siracusa, Snow Leopard review p.4](https://web.archive.org/web/2010/http://arstechnica.com/apple/reviews/2009/08/mac-os-x-10-6.ars/4)
- Siracusa: "these menus may bring to mind Apple's Hi-Tech appearance theme from the bad-old days of Copland... Note the translucent edges which accentuate the rounded corners. The gradient on the selection highlight is also admirably restrained." He adds that the look "does clash a bit with the default 'slanty, shiny shelf' appearance of the Dock". The caption reads "New Dock menu appearance. Mmmm… arbitrary." — [SL review p.4](https://web.archive.org/web/2010/http://arstechnica.com/apple/reviews/2009/08/mac-os-x-10-6.ars/4); [screenshot dock-menus-1.jpg](https://web.archive.org/web/20101206061843im_/http://static.arstechnica.com/20090828/dock-menus-1.jpg)
- Siracusa on window lists: the caption reads "Minimized window denoted by a diamond". Windows minimised into the app icon are recovered by right-clicking the icon. — [SL review p.17](https://web.archive.org/web/2010/http://arstechnica.com/apple/reviews/2009/08/mac-os-x-10-6.ars/17); [screenshot](https://web.archive.org/web/20101207040133im_/http://static.arstechnica.com/20090828/dock-minimized-windows-menu.jpg)
- Siracusa, same review: "Clicking and holding on a running application's Dock icon now triggers Exposé, but only for the windows belonging to that application." — [SL review p.17](https://web.archive.org/web/2010/http://arstechnica.com/apple/reviews/2009/08/mac-os-x-10-6.ars/17)
- Siracusa also shows a System Preferences Dock menu that lists preference panes, with the same dark style and pointer. — [SL review p.21](https://web.archive.org/web/2010/http://arstechnica.com/apple/reviews/2009/08/mac-os-x-10-6.ars/21); [screenshot](https://web.archive.org/web/20101207042404im_/http://static.arstechnica.com/20090828/system-preferences-dock-menu.jpg)
- Pre-release history: build 10A402 (July 2009) changed Dock contextual menus to "what some users are calling a 'heads-up display' theme of white text on a charcoal background." — [MacRumors, 10 Jul 2009](https://www.macrumors.com/2009/07/10/os-x-snow-leopard-10a402-brings-visual-tweaks-and-other-enhancements/). A search snippet of AppleInsider's report says earlier builds used the same look as Finder contextual menus. I could not open the page (HTTP 403). — [AppleInsider discussion](https://forums.appleinsider.com/discussion/100379)
- Wikipedia: Snow Leopard Dock menus have "a new look... with a semi-transparent charcoal background and white text." — [Wikipedia: Dock (macOS)](https://en.wikipedia.org/wiki/Dock_(macOS))
- Reception, from search snippets only (pages not opened):
  - Macworld called it white text on a translucent black background. — [Macworld SL review](https://www.macworld.com/article/3162444/mac-os-x-10-6-snow-leopard-review-2.html)
  - A MacRumors thread complained that Dock menus were black and translucent while other menus stayed white. — [MacRumors thread](https://forums.macrumors.com/threads/sl-right-click-inconsistencies-dock-vs-elsewhere.775215)
  - The O'Reilly Missing Manual notes some found it too translucent and points to TinkerTool to reduce it. — [O'Reilly ch.4](https://www.oreilly.com/library/view/mac-os-x/9781449377243/ch04.html)
- Measured (estimate) from dock-menus-1.jpg (636×310, about 52 px Dock icons, assumed 1:1):
  - **Fill:** about rgb(24,24,24) at about 0.80–0.81 alpha. I solved this from two wallpaper/body pairs: (155,93,158)→(49,37,47) and (101,36,118)→(40,28,42). All three channels agree within about 2 levels.
  - **Border:**
    - About 1.5–2 px, roughly white at 30% alpha. Examples: the top edge reads (173,139,173) over wallpaper (136,90,137), and the bottom edge reads (110,64,113) over (46,0,50).
    - Below it, a 1 px darker inner line.
    - The border continues along both edges of the pointer.
  - **Corners:** radius about 6 px.
  - **Rows:** 19 px (the highlighted "Options" row runs from y=134 to y=152). Cap height is about 10 px, consistent with 14 pt Lucida Grande.
  - **Highlight:** vertical blue gradient from about rgb(115,127,240) at the top to about rgb(67,84,250) at the bottom. It runs edge to edge (touching the border, no inset) and the text stays white.
  - **Separators:** 1 px line, about white at 20% ((88,76,86) over body (46,34,48)). The separator item is about 12–13 px tall.
  - **Glyphs:**
    - White ✓ for the frontmost window.
    - ◆ for a minimised window.
    - 16 px window proxy icons before window titles.
    - White ▶ submenu triangles at the right.
  - **Submenu:** same material, no pointer. It opens to the right, roughly level with the parent row.
  - **Pointer:**
    - Base about 26–28 px, height about 13–14 px, apex about 90°.
    - Axis at x≈235, the Safari icon's centre (about x=210–262).
    - Menu left edge at x≈207, so the axis is about 28 px in from the left.
    - Menu width is about 152 px.
    - About 8–10 px between the tip (y≈223) and the top of the Safari artwork.
  - Source: [dock-menus-1.jpg](https://web.archive.org/web/20101206061843im_/http://static.arstechnica.com/20090828/dock-menus-1.jpg)

**10.7 Lion and 10.8 Mountain Lion**
- Siracusa's Lion and Mountain Lion reviews do not discuss Dock menus. I searched all 19 Lion pages and 22 Mountain Lion pages through Wayback.
  - Lion changed the system-wide highlight: "The total removal of blue highlights from several controls... the additional green in the blue highlights that still do exist makes those controls appear more saccharine." — [Lion review p.3](https://web.archive.org/web/2012/http://arstechnica.com/apple/reviews/2011/07/mac-os-x-10-7.ars/3)
  - Mountain Lion changed the Dock shelf to frosted glass with "thin rectangular lights" as running indicators. — [Mountain Lion review p.3](https://web.archive.org/web/2013/http://arstechnica.com/apple/2012/07/os-x-10-8/3/); [Wikipedia](https://en.wikipedia.org/wiki/Dock_(macOS))
- Apple's HIG (2011 revision, "Last updated: 2011-07-26", the week of Lion's launch) shows a dark Dock menu with a pointer in its "TextEdit Edit menu, the Mail Dock menu, and a Finder contextual menu" figure. The Dock pictured is the Leopard/Snow Leopard glass shelf, so this is probably a reused Snow Leopard screenshot. — [Apple HIG 2011, Menus](https://web.archive.org/web/20110926103021/http://developer.apple.com/library/mac/documentation/UserExperience/Conceptual/AppleHIGuidelines/Menus/Menus.html); [figure mn_threemenutypes.jpg](https://web.archive.org/web/20110926103021im_/http://developer.apple.com/library/mac/documentation/UserExperience/Conceptual/AppleHIGuidelines/art/mn_threemenutypes.jpg)
- Apple's HIG (revision "Updated: 2013-10-22", Mavericks launch day) shows the iTunes Dock menu with this look:
  - Dark body with white text and a light rim.
  - Pointer aimed at the iTunes icon.
  - Mavericks-era icons (iBooks, Maps), with the frosted shelf and light-bar indicator.
  - Source: [Apple HIG 2013, Menus](https://web.archive.org/web/20131212010816/https://developer.apple.com/library/mac/documentation/userexperience/conceptual/applehiguidelines/Menus/Menus.html); [figure mn_itunesdockmenu_2x.png](https://web.archive.org/web/20131212010816im_/https://developer.apple.com/library/mac/documentation/userexperience/conceptual/applehiguidelines/art/mn_itunesdockmenu_2x.png)
- Measured (estimate) from that 2013 figure (310×426; it looks like a 2x capture scaled to about 70%, since the row pitch is about 26.5 image px):
  - Body composite over the white page is a uniform rgb(65,65,65).
  - The rim is about 2 px light ((209–236) over white), with a darker inner line (56) and a soft outer shadow edge.
  - The pointer is about 36×19 image px, about 26×13.5 px once normalised to 19 px rows.
  - The pointer axis is at the iTunes icon's centre, about 26 px (normalised) from the menu's left edge.
  - Disabled items (Play/Next/Previous) are gray.
- Apple's HIG text from the same era says: "To reveal a Dock menu, users Control-click or press and hold an app's Dock icon." It also mentions "the minimal Dock menu that is displayed when users press and hold the Dock icon". — [Apple HIG 2011](https://web.archive.org/web/20110926103021/http://developer.apple.com/library/mac/documentation/UserExperience/Conceptual/AppleHIGuidelines/Menus/Menus.html)

**10.10 Yosemite and 10.12 Sierra: the pointer survives with flat, vibrant menus**
- The Yosemite-era OS X HIG says: "Note that the Dock and Dock menus use the current appearance that the user specifies in General preferences." It shows "Light menu bar and Dock appearance" and "Dark menu bar and Dock appearance" iTunes Dock menus, both with a pointer. — [OS X HIG, Dock Menus (Apr 2016 capture)](https://web.archive.org/web/20160410090049/https://developer.apple.com/library/mac/documentation/UserExperience/Conceptual/OSXHIGuidelines/OtherMenus.html); [light figure](https://web.archive.org/web/20160410090049im_/https://developer.apple.com/library/mac/documentation/UserExperience/Conceptual/OSXHIGuidelines/Art/dock_menu_light_2x.png); [dark figure](https://web.archive.org/web/20160410090049im_/https://developer.apple.com/library/mac/documentation/UserExperience/Conceptual/OSXHIGuidelines/Art/dock_menu_dark_2x.png)
- Measured (estimate) from the Yosemite figures (406×604, @2x):
  - Corner radius is about 8–9 px @2x, about 4–4.5 pt.
  - The pointer is about 44×24 px @2x, about 22×12 pt.
  - The pointer axis is about 25 pt from the menu's left edge.
  - Composites over the white page: light body (240,240,240) with separators (223); dark body (121,121,121) with separators (156).
- The macOS HIG "Dock Menus" page (June 2018 capture) shows a Sierra-wallpaper screenshot of the Messages Dock menu, still with a pointer. The same image file was still there in a Jan 2022 capture. — [macOS HIG Dock Menus 2018](https://web.archive.org/web/20180618155436/https://developer.apple.com/design/human-interface-guidelines/macos/menus/dock-menus/); [image dockMenus.png](https://web.archive.org/web/20180618155436im_/https://developer.apple.com/design/human-interface-guidelines/macos/images/dockMenus.png); [Jan 2022 capture](https://web.archive.org/web/20220128180555/https://developer.apple.com/design/human-interface-guidelines/macos/menus/dock-menus/)
- Measured (estimate) from the Sierra image (768×250, about 1x, 18–19 px row pitch):
  - Corner radius is about 4–5 px.
  - The pointer is about 22–24 px wide and 11–12 px tall.
  - The axis is at x≈378, the Messages icon's centre.
  - The menu's left edge is at x≈352, so the axis is about 26 px in.
  - The tip is about 11 px above the Dock's top edge.
  - Body composite over the warm wallpaper is about (210,192,189): a light vibrant material tinted by the background.

### Inferences
- **Fonts.** Lucida Grande at the standard menu size (about 14 pt) through 10.9, Helvetica Neue in 10.10, San Francisco from 10.11. This is based on glyph shapes in the screenshots, the 10 px cap height in Snow Leopard, and the known system-font changes; no source states it for Dock menus.
- **Lion and Mountain Lion were dark, not light.** Snow Leopard is dark (verified) and the Mavericks figure is dark (verified). Snow Leopard's estimated fill composited over white gives about 68, which nearly matches the 2013 figure's 65 over white, so the material looks unchanged from 10.6 to 10.9. OldMacDoc's "Frosted" (Mountain Lion) shelf should pair with the dark bordered menu, not a light one.
- **Pointer geometry is stable.** 10.5–10.9 measure about 26×13 px with a right-angle apex (sides near 45°). 10.10–10.12 are slightly smaller, about 22–24×11–12. A spec of base 26, height 13 for 10.5–10.9, and base 22, height 11 for 10.10+, is within the measurement error.
- **Placement rule.** In all six screenshots (Leopard Trash, SL Safari, SL System Preferences, Mavericks iTunes, Yosemite iTunes, Sierra Messages), the pointer is centred on the icon and the menu's left edge sits within a few px of the icon's left edge. The axis is about 23–28 px from the menu's left edge, which is about half the pointer base plus the corner radius plus a few px. This matches MAAttachedWindow's "TopRight" placement with a rounded corner beside the arrow. Presumably the menu flipped to extend leftward near the screen's right edge, but no screenshot shows that.
- **Highlight follows the system.** Siracusa confirms this for 10.6; the Leopard graphite screenshot confirms it for 10.5. Lion's "greener" blue probably applied from 10.7.
- **Translucency of the rim.** The rim is translucent white, not a solid colour. Over a white page it reads nearly white, and over the Snow Leopard purple wallpaper it reads lavender. To get Siracusa's "translucent edges", render it as white at about 25–35% over the backdrop.

### Gaps
- I found no Lion or Mountain Lion screenshot of a Dock menu. Dark for 10.7–10.8 is inferred from bracketing evidence (10.6 and 10.9), not observed.
- **Opening and closing animation.** No source says whether 10.5–10.9 Dock menus appeared instantly or faded, or whether the chosen item blinked. Siracusa says Snow Leopard generally "everything fades", but not specifically for Dock menus. Treat it as unknown; NSMenu's default (instant open, quick fade on close) is a reasonable stand-in.
- **Left or right Dock.** I found no screenshot or text describing the pointer for a side-positioned Dock. By symmetry it would point left or right at the icon centre, with the menu's top near the icon's top, but that is unverified.
- **Clamping.** I found no evidence of how the pointer behaves when the menu is clamped at a screen edge (whether it slides along the edge or the menu flips).
- The shadow's radius and offset can't be measured reliably from these JPEGs. There is a soft dark shadow, strongest below and beside the menu.
- The Leopard body colour can't be separated into fill and opacity because the backdrop was black.

## Q2. When did the pointer disappear, and what do Dock menus look like on macOS 14 Sonoma through macOS 27?

### Takeaway
The pointer is verified through 10.12 Sierra, from Apple's own HIG screenshot. On current macOS (verified on this machine, macOS 27.0.1), the Dock no longer draws its own menus. They are ordinary AppKit NSMenus shown by the Dock's DockHelper XPC process relative to the icon's rect. There is no callout, and the menu uses the system menu material and appearance: Big Sur's spacing and rounded highlights, and Liquid Glass from macOS 26. I could not pin down the exact release that dropped the pointer (somewhere from 10.13 to 11.0). Big Sur is the most likely, but that is unverified.

### Cited Findings
- On the installed macOS 27.0.1, `Dock.app/Contents/XPCServices/DockHelper.xpc` links AppKit. Its strings include `popupWithMenu:direction:rect:dark:orientation:fromKeyboard:accessibilityContainer:withReply:` and the private `_popUpMenuRelativeToRect:inView:preferredEdge:`, plus `NSMenuDelegate`, `menuWillOpen:`, `NSMenuItemDiamond` and `NSMenuItemBullet`. So the Dock hands DockHelper a menu, a direction or orientation, the icon rect and a dark flag, and DockHelper pops a real NSMenu. — [Local: DockHelper.xpc](file:///System/Library/CoreServices/Dock.app/Contents/XPCServices/DockHelper.xpc/Contents/MacOS/DockHelper)
- The Dock binary itself has `_menuPopupDelay` and `_menuPopupInterval` strings, which look like internal press-and-hold timing keys. The default values are unknown. — [Local: Dock binary](file:///System/Library/CoreServices/Dock.app/Contents/MacOS/Dock)
- The Dock's resources contain no menu-pointer artwork. The only callout art is the Stacks grid pointer: `ecsb_arrow_bottom.png` and `ecsb_arrow_top.png` at 59×52 px @1x including shadow, with `ecsb_arrow_bottom_mask@2x.png` at 86×42 px, about a 43×21 pt triangle with a right-angle apex. There is also `pileArrow*.png` for fan stacks. — [Local: Dock.app Resources](file:///System/Library/CoreServices/Dock.app/Contents/Resources/)
- `Dock.app/Contents/Resources/DockMenus.plist` defines Dock menu structures by kind: process, dock, docklet, file, fileapp, folder, directory, directorylist, trash, volume, url, minwindow, finder-running, finder-quit, smartfolder, spacer, screensharingstack, continuity. The directory menu uses section headers such as "SORT_BY", "DISPLAY_AS" and "SHOW_AS", plus separators. — [Local: DockMenus.plist](file:///System/Library/CoreServices/Dock.app/Contents/Resources/DockMenus.plist)
- The current Apple HIG Dock menus page shows only a stylised illustration and says "people can secondary click an app's or game's icon in the Dock to reveal a Dock menu". It gives no visual spec. — [Apple HIG: Dock menus](https://developer.apple.com/design/human-interface-guidelines/dock-menus)
- Big Sur menu changes:
  - "Menu items are more spaced out vertically too." — [MacStories Big Sur review](https://www.macstories.net/stories/macos-big-sur-the-macstories-review/5)
  - "Highlighted elements — like a menu item that you're hovering overtop" now have rounded corners. — [Pixel Envy](https://pxlnv.com/blog/big-sur-design-observations/)
  - Six Colors (search snippet) notes menus with curved edges and "additional space between each menu item". — [Six Colors](https://sixcolors.com/post/2020/11/macos-big-sur-review-third-age-of-mac/)
- Wikipedia's Dock timeline:
  - Yosemite: vibrancy and a dark-mode option.
  - Big Sur: all four corners of the Dock rounded.
  - macOS 26 Tahoe: "the vibrancy effect used since OS X Yosemite was changed to a glass-like texture".
  - macOS 27 "Golden Gate": "redesigned icons and an adjustable blur". The 27 entry cites MacRumors.
  - Source: [Wikipedia: Dock (macOS)](https://en.wikipedia.org/wiki/Dock_(macOS))
- AppKit (macOS 14+) added `NSMenu.presentationStyle` (`.regular`, `.palette`), `selectionMode` and `selectedItems`. The header documents `menu(_:willHighlight:)` behaviour changes in macOS 14.0 and 26.4. — [Local: AppKit NSMenu.h, macOS SDK](file:///Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk/System/Library/Frameworks/AppKit.framework/Headers/NSMenu.h); [Apple docs: NSMenu](https://developer.apple.com/documentation/appkit/nsmenu)
- Keyboard access to the real Dock today: "Press Fn-Control-F3 to move to the Dock. Then use the Left Arrow and Right Arrow keys to move from icon to icon. Press Return to open an item." Menus open with "Control-click an item to display its shortcut menu". — [Apple Support: Use the Dock on Mac](https://support.apple.com/guide/mac-help/use-the-dock-mh35859/mac)
- An AppleVis thread (search snippet only, HTTP 403 on fetch) says VoiceOver users open Dock item menus with VO-Shift-M or Up Arrow, unreliably in Big Sur. — [AppleVis](https://www.applevis.com/forum/macos-mac-apps/removing-things-my-dock-big-sur-1123)

### Inferences
- The pointer disappeared when Apple moved Dock menu presentation to standard NSMenu, which has no public or private callout drawing. NSMenu's own `_popUpMenuRelativeToRect:inView:preferredEdge:` is what DockHelper calls. The `dark:` parameter shows that the Dock still forces the menu's appearance to match the Dock rather than the app.
- On macOS 14–27 a Dock menu therefore looks exactly like any context menu:
  - System menu material (vibrant through macOS 15, Liquid Glass on 26+).
  - Rounded inset highlight in the accent colour.
  - San Francisco text at the standard menu size.
  - No border stroke beyond the system's, and no pointer.
  - Placed just above the icon (beside it for a side Dock), with `NSMenuItemDiamond` and `NSMenuItemBullet` state images still used for minimised windows.
- The "dark" flag suggests that on Tahoe and later the Dock menu follows Dock darkness rather than the app's appearance. That matches the 2016 HIG statement that Dock menus "use the current appearance".

### Gaps
- **Exact removal release (10.13, 10.14, 10.15 or 11.0).** No source I could open states it. Search results didn't surface a High Sierra, Mojave or Catalina Dock menu screenshot or text, and the Ars Big Sur review's pages (read through Wayback) don't mention Dock menus. My best guess is Big Sur (11.0), which is when menus were redesigned, but this is unverified.
- No sourced corner radius, padding or row height for macOS 26 or 27 menus. Measure them from a live screenshot on this machine if needed.
- The DockHelper and NSMenu evidence is from binary strings, not documentation. It shows the mechanism exists, not every code path. For example, a Stack grid still draws its own pointer.

## Q3. How can a third-party AppKit app (OldMacDoc, macOS 14+) draw a Dock-style menu with a pointer, and what are the keyboard and accessibility trade-offs?

### Takeaway
There is no public way to give an NSMenu a callout or a custom background. Apple engineers said so in 2007 and nothing in the macOS 26.4 SDK changes it. That leaves three routes:
- **Custom borderless panel.** A non-activating borderless NSPanel that draws its own rows and pointer (the MAAttachedWindow, INPopoverController and SFBPopovers pattern). It gives full visual fidelity, but you must rebuild menu tracking, keyboard handling, type-select, submenus and the accessibility (AX) menu semantics.
- **NSMenu plus a companion "tail" window (hack).** It keeps all native behaviour but can only approximate the join, and it fights the system's menu material.
- **NSPopover.** Free arrow and edge-flipping, but the system arrow and material can't look like 10.5 or 10.6, and the content is not a menu.

For three retro shelves the custom panel is the only route that reproduces the look. OldMacDoc already uses the needed window plumbing.

### Cited Findings

**Native NSMenu limits and what's available**
- 2007, Apple-era answer: "No, there is no way to get a Dock-menu appearance". Rainer Brockerhoff, after discussing MAAttachedWindow with Matt Gemmell: "we concluded it's too much work (in the short term) to emulate all the little NSMenu details... icons, scrolling, submenus, and whatnot." A custom MDEF (Carbon menu definition) was floated as an alternative. — [cocoa-dev msg00992](https://lists.apple.com/archives/Cocoa-dev/2007/Nov/msg00992.html), [msg01032](https://lists.apple.com/archives/cocoa-dev/2007/Nov/msg01032.html)
- `NSMenuItem.view`, from the header documentation:
  - "A menu item with a view does not draw its title, state, font, or other standard drawing attributes, and assigns drawing responsibility entirely to the view. Keyboard equivalents and type-select continue to use the key equivalent and title as normal."
  - "A view in a menu item will receive mouse and keyboard events normally. During non-sticky menu tracking (manipulating menus with the mouse button held down), a view in a menu item will receive mouseDragged: events."
  - "because menu tracking occurs in the NSEventTrackingRunLoopMode, you must add the timer to the run loop in that mode."
  - "do not attempt to move or otherwise modify the window."
  - "Menu item views are not supported in the Dock menu." This refers to the real Dock's `applicationDockMenu`, not menus an app pops itself.
  - `isHighlighted` tells a view when to draw its highlight.
  - Sources: [Local: NSMenuItem.h](file:///Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk/System/Library/Frameworks/AppKit.framework/Headers/NSMenuItem.h); [Apple docs: NSMenuItem.view](https://developer.apple.com/documentation/appkit/nsmenuitem/view)
- Positioning APIs:
  - `popUpMenuPositioningItem:atLocation:inView:` (10.6+).
  - `NSMenu.size`, readonly, 10.6+. It lets you know the frame before showing.
  - `minimumWidth`.
  - `userInterfaceLayoutDirection`.
  - `NSMenuDelegate.confinementRectForMenu:onScreen:`, which constrains where the system may place or clamp the menu.
  - `menuWillOpen:` and `menuDidClose:`.
  - Sources: [Local: NSMenu.h](file:///Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk/System/Library/Frameworks/AppKit.framework/Headers/NSMenu.h); [Apple docs: NSMenuDelegate](https://developer.apple.com/documentation/appkit/nsmenudelegate)
- OldMacDoc today:
  - It pops a plain NSMenu centred over the tile, 8 pt above it: `menu.popUp(positioning: nil, at: NSPoint(x: t.frame.midX - size.width / 2, y: t.frame.maxY + 8 + size.height), in: self)`. — [Local: DockView.swift:1274](file:///Users/kew/Github/oldmacdonal/Sources/App/DockView.swift)
  - The app is `.accessory` with LSUIElement set. — [Local: main.swift](file:///Users/kew/Github/oldmacdonal/Sources/App/main.swift)
  - It already uses borderless `.nonactivatingPanel` panels at `.popUpMenu` level with `canBecomeKey` true for Settings. — [Local: SettingsPanel.swift](file:///Users/kew/Github/oldmacdonal/Sources/App/SettingsPanel.swift)

**Custom-window building blocks (AppKit, verified in SDK headers)**
- `NSWindowStyleMaskNonactivatingPanel`: "Specifies that a panel that does not activate the owning application." `NSPanel.becomesKeyOnlyIfNeeded` and `NSWindow.canBecomeKeyWindow` can be overridden. — [Local: NSWindow.h](file:///Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk/System/Library/Frameworks/AppKit.framework/Headers/NSWindow.h); [Apple docs: nonactivatingPanel](https://developer.apple.com/documentation/appkit/nswindow/stylemask-swift.struct/nonactivatingpanel)
- `-[NSWindow trackEventsMatchingMask:timeout:mode:handler:]` (10.10+) runs a local tracking loop. It is the tool for "press on the icon, drag into the menu, release on an item". — [Local: NSWindow.h line 786](file:///Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk/System/Library/Frameworks/AppKit.framework/Headers/NSWindow.h); [Apple docs](https://developer.apple.com/documentation/appkit/nswindow/trackevents(matching:timeout:mode:handler:))
- Accessibility:
  - AppKit exposes `NSAccessibilityMenuRole`, `NSAccessibilityMenuItemRole` and `NSAccessibilityMenuButtonRole`. — [Local: NSAccessibilityConstants.h](file:///Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk/System/Library/Frameworks/AppKit.framework/Headers/NSAccessibilityConstants.h)
  - There is no AppKit constant for menu-open or menu-close notifications. HIServices defines `kAXMenuOpenedNotification` ("AXMenuOpened", value is "the opened menu UIElement"), `kAXMenuClosedNotification` and `kAXMenuItemSelectedNotification`. — [Local: AXNotificationConstants.h](file:///Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk/System/Library/Frameworks/ApplicationServices.framework/Frameworks/HIServices.framework/Headers/AXNotificationConstants.h); [Apple docs: kAXMenuOpenedNotification](https://developer.apple.com/documentation/applicationservices/kaxmenuopenednotification)

**NSPopover**
- Popovers are anchored with `showRelativeToRect:ofView:preferredEdge:`. AppKit "will place the anchor towards the preferredEdge... unless such a placement would cause the popover not to fit". It then tries the opposite edge, then the remaining sides, then centres on screen, "causing it to (at least temporarily) lose its anchor".
- Other properties:
  - `behavior`: transient, semitransient or applicationDefined.
  - `animates`, which Apple calls "a hint".
  - `positioningRect`.
  - `hasFullSizeContent` (macOS 14+).
- The Lion-era `NSPopoverAppearanceHUD` ("The popover will draw with a HUD appearance") was deprecated after 10.10.
- Sources: [Local: NSPopover.h](file:///Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk/System/Library/Frameworks/AppKit.framework/Headers/NSPopover.h); [Apple docs: NSPopover](https://developer.apple.com/documentation/appkit/nspopover)
- A Stack Overflow answer reports that the NSPopover arrow cannot be removed and that you must "code your own floating window" instead. I saw this only through a search summary; stackoverflow.com blocks fetches. — [Stack Overflow 68744895](https://stackoverflow.com/questions/68744895/swift-ui-macos-menubar-nspopover-no-arrow)

**Open-source callout implementations (macOS)**
- **MAAttachedWindow** (Matt Gemmell, 2007), a borderless NSWindow subclass that draws a bordered rounded rect with an arrow aimed at a point.
  - Properties: `borderColor`, `borderWidth`, `viewMargin`, `arrowBaseWidth`, `arrowHeight`, `hasArrow`, `cornerRadius`, `drawsRoundCornerBesideArrow`.
  - 12 positions such as `MAPositionTopRight`, plus automatic placement that "prefers to position itself horizontally centered below the specified point".
  - Defaults are HUD-like: background `colorWithCalibratedWhite:0.1 alpha:0.75`, white border, `borderWidth` 2, `arrowBaseWidth` 20, `arrowHeight` 16, `cornerRadius` 8. It is non-opaque with a shadow and overrides `canBecomeKeyWindow`.
  - Source: [GitHub mirror lowell/MAAttachedWindow](https://github.com/lowell/MAAttachedWindow); [original post](http://mattgemmell.com/2007/10/03/maattachedwindow-nswindow-subclass). A 2011 cocoa-dev reply recommends it for "a panel with a side 'arrow' such as the list seen when right-click on a dock item". — [cocoa-dev 2011](https://lists.apple.com/archives/cocoa-dev/2011/Mar/msg00765.html)
- **INPopoverController** (BSD-2), a pre-NSPopover popover. It offers "Customizable color, border color, border width, arrow size, and corner radius", automatic arrow direction "depending on screen space", appear and disappear animation, and close-on-key-loss or app-resign behaviours. Drawing lives in `INPopoverWindowFrame.m`. — [GitHub indragiek/INPopoverController](https://github.com/indragiek/INPopoverController)
- **SFBPopovers** (MIT), which combines MAAttachedWindow and INPopoverController. — [GitHub sbooth/SFBPopovers](https://github.com/sbooth/SFBPopovers)
- **iSapozhnik/Popover** (MIT, Swift), a custom popover with configurable arrow height and width, background and border, aimed at status items. — [GitHub iSapozhnik/Popover](https://github.com/iSapozhnik/Popover)
- **nongio/dock.app**, a proof-of-concept Dock replacement where clients send menus that the dock "can open... on right-click". It is not a callout implementation. — [GitHub nongio/dock.app](https://github.com/nongio/dock.app)
- **Pantheon (elementary) dock** proposed switching context menus to GTK popovers because "The caret pointing to the dock item is another clear signal that the menu applies only to that dock item". The proposal was never decided. — [Launchpad bug 1293356](https://bugs.launchpad.net/pantheon-dock/+bug/1293356)

### Inferences

**Option A: keep NSMenu (status quo).**
- Pros:
  - Free arrow-key navigation, Return, Escape and type-select.
  - Key equivalents, submenus with correct hover intent, and scrolling for tall menus.
  - Option-key alternates (`isAlternate`).
  - Correct VoiceOver menu semantics and press-drag-release tracking (pop it from `mouseDown` and it tracks non-sticky).
  - You can force `menu.appearance = NSAppearance(named: .darkAqua)` for Smoke or Frosted.
- Cons:
  - No pointer or custom material, rim, highlight gradient or Lucida Grande.
  - On macOS 26+ it is Liquid Glass, which clashes with retro shelves.
  - `NSMenuItem.view` can restyle rows (keeping type-select and key equivalents, per the header) but not the menu chrome.
- Cheap fidelity win: copy Apple's placement rather than centring. Put the menu's left edge near the tile's left edge, with `confinementRect` limiting clamping.

**Option B: NSMenu plus a separate borderless "tail" panel.**
- How:
  - Compute the frame from `menu.size` and the point given to `popUp(positioning:at:in:)`.
  - In `menuWillOpen`, order in a tiny `.popUpMenu`+1 panel drawing a triangle under the menu's bottom edge. Remove it in `menuDidClose`.
- Pros:
  - Keeps all native keyboard and VoiceOver behaviour.
- Cons:
  - The tail can't match the system's vibrant or glass material or its shadow.
  - The corner and edge join will show.
  - If the system clamps or shifts the menu, the tail misaligns.
  - The menu window is private, so you can't read its real frame.
- Suitable only as a stopgap; nobody I found documents doing this.

**Option C: custom borderless NSPanel menu (recommended for fidelity).**
- Window: `NSPanel` with `[.borderless, .nonactivatingPanel]`, `isOpaque = false`, `backgroundColor = .clear`, `hasShadow = true`, level `.popUpMenu`, and `canBecomeKey = true`. That lets it take keys without activating the `.accessory` app, as SettingsPanel already does.
- Shape: draw one `NSBezierPath` (rounded rect plus triangle) for fill and stroke. For the Snow Leopard–Mavericks dark style, put a backdrop blur behind it with `NSVisualEffectView`, using `maskImage` to clip the blur to the same path. Leopard used no blur, just a light translucent fill.
- Things to rebuild:
  1. **Tracking.** From the tile's `mouseDown`, start a timer for click-and-hold (about 0.5 s is plausible; the Dock's own `_menuPopupDelay` value is unknown). Show the panel and run `window.trackEvents(matching: [.leftMouseDragged, .leftMouseUp])` so release-over-item fires and release elsewhere dismisses. Right-click or Control-click opens it "sticky".
  2. **Dismissal.** Use a global plus local `NSEvent` monitor for clicks outside, plus app or Space change notifications, plus Escape.
  3. **Keyboard.** Up and Down skip separators and disabled items. Right and Left open and close submenus. Return and Space activate. Escape closes. Add key-equivalent matching, and type-select with a buffer of about 1 s.
  4. **Submenus.** Child panels without a pointer, opened on hover after about 200 ms, with a diagonal "safe triangle" so moving toward the submenu doesn't switch rows.
  5. **Alternates.** Watch `flagsChanged` for Option alternates, e.g. Quit becomes Force Quit.
  6. **Scrolling and flipping.** Scroll when taller than the screen, and flip to extend left when near the right edge (pointer moves to the right corner).
  7. **Accessibility.**
     - The panel's content view gets `accessibilityRole = .menu`.
     - Each row is an `NSAccessibilityElement` with role `.menuItem`, a title, enabled state and a press action.
     - Post focused-element-changed for the highlighted row.
     - Post `NSAccessibility.Notification(rawValue: "AXMenuOpened")` and `"AXMenuClosed"` (the HIServices strings).
     - Whether VoiceOver treats a non-NSMenu window exactly like a system menu is unverified. Test it.
- This is precisely the "too much work... icons, scrolling, submenus" Brockerhoff and Gemmell flagged in 2007. A Dock menu is small, though: one submenu level, tens of items, no icons except window proxies.

**Option D: NSPopover.**
- Pros:
  - System-quality arrow, anchoring and edge-flipping (`preferredEdge` maps neatly to bottom, left or right Docks).
  - Built-in show and close animation.
- Cons:
  - The arrow is the modern system arrow, so it can't be restyled to the 26×13 bordered HUD tail.
  - The background is the system popover material (`hasFullSizeContent` only extends content under it).
  - The HUD appearance has been gone since 10.10.
  - The content is not a menu, so you still rebuild everything in Option C's steps 1–7. Popover keyboard focus in a non-activating accessory app is also untested.
- So NSPopover saves only the shape drawing, which is the easy part.

**Visual spec to feed Option C (from Q1 measurements).**
- Pointer:
  - About 26 px base and 13 px tall (Leopard to Mavericks), right-angle apex.
  - The tip leaves about 7–10 px clear above the icon artwork.
  - The axis sits at the icon centre, about 25 px in from the menu's left edge.
  - The menu's left edge sits at about the icon's left edge.
- Rows and text:
  - Rows 19 px, separators about 12 px with a 1 px line.
  - 4–6 px top and bottom padding.
  - Lucida Grande 14 is not shipped on macOS 14+. Use the closest system font, or bundle a licensed substitute; licensing is unchecked.
- Highlight: edge to edge, no inset; text turns white.
- Clear Glass (Leopard): light about 85–90% white fill, about 4 px radius, system-accent gradient highlight, pointer filled with no separate stroke.
- Frosted (Mountain Lion) and Smoke: dark rgb(24,24,24) at about 0.8 with a backdrop blur, about 6 px radius, about 1.5–2 px white-30% rim continuing around the pointer, blue gradient highlight from about #737FF0 to #4355FA (or the accent colour), separators white at 20%.

### Gaps
- I found no maintained Swift package that implements a full callout menu with keyboard, type-select, submenus and AX roles. The candidates above are popover-window frames only. I also found no macOS third-party dock (uBar, ActiveDock and others not checked in depth) that is documented as copying the pointer menus.
- VoiceOver behaviour for a custom panel posting `AXMenuOpened` and exposing `.menu` and `.menuItem` roles is undocumented by Apple for third-party windows and needs hands-on testing.
- No source gives NSPopover's arrow size, or whether an NSPopover shown from a `.nonactivatingPanel` in an `.accessory` app can take keyboard focus without activating the app.
- I couldn't open the Stack Overflow answers on NSPopover arrows and NSMenu-in-NSPopover (the site blocks fetches), so those points rest on search summaries.

## Q4. Which reference screenshots, teardowns and measurements exist?

### Takeaway
The best primary visual references are Siracusa's Leopard and Snow Leopard screenshots (1:1, measurable) and Apple's own HIG figures for Lion-era, Mavericks, Yosemite (light and dark) and Sierra Dock menus, all on the Wayback Machine. No published teardown gives pixel dimensions. The measurements in Q1 are mine and are estimates.

### Cited Findings
- **Leopard Dock Trash menu**, graphite highlight, pointer (184×194). — [dock-trash-menu.jpg](https://web.archive.org/web/20120723092644im_/http://origin.arstechnica.com/reviews/os/mac-os-x-10-5.media/dock-trash-menu.jpg) from [Siracusa Leopard p.4](https://web.archive.org/web/2012/http://arstechnica.com/apple/reviews/2007/10/mac-os-x-10-5.ars/4)
- **Snow Leopard Safari Dock menu** with the Options submenu open, blue highlight, check and window icons (636×310). — [dock-menus-1.jpg](https://web.archive.org/web/20101206061843im_/http://static.arstechnica.com/20090828/dock-menus-1.jpg) from [Siracusa SL p.4](https://web.archive.org/web/2010/http://arstechnica.com/apple/reviews/2009/08/mac-os-x-10-6.ars/4)
- **Snow Leopard Safari menu** with a diamond for a minimised window (199×287). — [dock-minimized-windows-menu.jpg](https://web.archive.org/web/20101207040133im_/http://static.arstechnica.com/20090828/dock-minimized-windows-menu.jpg)
- **Snow Leopard System Preferences Dock menu** (272×247). — [system-preferences-dock-menu.jpg](https://web.archive.org/web/20101207042404im_/http://static.arstechnica.com/20090828/system-preferences-dock-menu.jpg)
- **Apple HIG 2011**, Mail Dock menu with submenu (SL-style). — [mn_threemenutypes.jpg](https://web.archive.org/web/20110926103021im_/http://developer.apple.com/library/mac/documentation/UserExperience/Conceptual/AppleHIGuidelines/art/mn_threemenutypes.jpg)
- **Apple HIG 2013**, Mavericks iTunes Dock menu, dark with pointer. — [mn_itunesdockmenu_2x.png](https://web.archive.org/web/20131212010816im_/https://developer.apple.com/library/mac/documentation/userexperience/conceptual/applehiguidelines/art/mn_itunesdockmenu_2x.png)
- **OS X HIG (Yosemite)**, light and dark Dock menus with pointer. — [light](https://web.archive.org/web/20160410090049im_/https://developer.apple.com/library/mac/documentation/UserExperience/Conceptual/OSXHIGuidelines/Art/dock_menu_light_2x.png), [dark](https://web.archive.org/web/20160410090049im_/https://developer.apple.com/library/mac/documentation/UserExperience/Conceptual/OSXHIGuidelines/Art/dock_menu_dark_2x.png)
- **macOS HIG (Sierra)**, Messages Dock menu with pointer. — [dockMenus.png](https://web.archive.org/web/20180618155436im_/https://developer.apple.com/design/human-interface-guidelines/macos/images/dockMenus.png)
- **Current Dock's Stacks grid callout art**, the only Apple-authored pointer asset still shipping. — [Local: ecsb_arrow_bottom@2x.png](file:///System/Library/CoreServices/Dock.app/Contents/Resources/ecsb_arrow_bottom@2x.png)

### Inferences
- The Snow Leopard image is the single best reference for OldMacDoc's dark shelves, and the Leopard Trash image for Clear Glass. Both are native resolution, so the pointer, row and radius numbers transfer directly as points.
- Because the Mavericks HIG figure matches Snow Leopard when composited over white, it is a usable second reference for the Mountain Lion ("Frosted") era.

### Gaps
- I found no Siracusa text on Dock menus for Lion, Mountain Lion or Mavericks, and no 512pixels or TidBITS teardown with measurements. I did not search 512pixels' screenshot library exhaustively.
- I found no reference screenshot of a side-Dock (left or right) menu for any version.
