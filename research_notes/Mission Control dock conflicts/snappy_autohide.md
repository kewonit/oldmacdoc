# Snappy, robust auto-hiding third-party dock on macOS 14–27 (AppKit + Core Animation)

Scope note: about 24 searches and fetches, done 2026-10-31. Every item under "Cited Findings" has a URL. Everything under "Inferences" is my own engineering judgement built on those findings. Treat it as a recommendation, not a sourced fact. Several Apple behaviours I could not confirm from primary sources are listed under "Gaps".

## 1. Timings: Apple defaults, "snappy" user settings, recommended reveal delay, slide duration, easing, hide grace

### Takeaway
Apple's Dock waits 0.2 s before revealing ("autohide-delay") and animates over about 0.5 s ("autohide-time-modifier"). Power users usually set the delay to 0 and the animation to 0.25 or lower. Josejuanqm's Docky, a modern open-source AppKit dock, defaults its slide to 0.22 s. A good default is a short dwell of about 0.1–0.2 s, a slide of about 0.2–0.25 s that eases out on show and eases in on hide, and a hide grace of about 0.2–0.4 s. Expose all three as settings.

### Cited Findings
- `com.apple.dock autohide-delay` default is **0.2** (float, seconds). Quote: "By default, the Dock only opens if the mouse doesn't move for 0.2 seconds". Setting it to 0 makes the Dock appear instantly. Tested on Mojave through Sequoia. — [macos-defaults.com: autohide-delay](https://macos-defaults.com/dock/autohide-delay.html)
- `com.apple.dock autohide-time-modifier` default is **0.5**. Quote: "By default, the Dock opening and closing animations take 0.5 seconds". A value of 2 slows it and 0 removes the animation. One value covers both show and hide. Tested on Mojave through Sequoia. — [macos-defaults.com: autohide-time-modifier](https://macos-defaults.com/dock/autohide-time-modifier.html)
- 0.25 is a commonly shared "faster" value for autohide-time-modifier: `defaults write com.apple.dock autohide-time-modifier -float 0.25 && killall Dock`. It appears in dotfile gists and blog guides. — [gist (midudev)](https://gist.github.com/midudev/aa970a3768665a10e6c8fc5d5c901907), [gist (bretonics)](https://gist.github.com/bretonics/8fc4f729b31f1307f7d9d7712d4eed15/d1ce0438aca55e57fd69fcabe9d404062f5491f5), [jogruber.de blog](https://jogruber.de/blog/how-to-speed-up-the-animations-of-a-hidden-macos-dock), [nix-darwin option](https://mynixos.com/nix-darwin/option/system.defaults.dock.autohide-time-modifier)
- r/MacOS posts circulate `autohide-delay 0` together with `autohide-time-modifier 0.5`, i.e. no delay but the default animation length "for comfort". A commenter argued the built-in delay is deliberate: "so the Dock won't show while the mouse is moving and appears almost immediately once it stops". I saw these only through a Reddit snapshot aggregator, not reddit.com itself. — [r/MacOS snapshot 2026-04-02](https://reddit.sentinel-team.org/posts/1sapqsd/snapshots/2026-04-02T22%3A10%3A08.968062Z), [r/MacOS snapshot 2026-04-15](https://reddit.sentinel-team.org/posts/1sm0qm9/snapshots/2026-04-15T22%3A09%3A06.765165Z)
- I found **no source** recommending a 0.15 time-modifier. The search returned 0 / 0.25 / 0.5 only. — (search result; see Gaps)
- Josejuanqm/docky (open-source AppKit dock, macOS 14+) added `DockyPreferences.autohideAnimationDuration`. Quote: "default `0.22s`, clamped `0...1`". The settings slider runs "`0...1s`, step `0.05`" and `0s` "snaps the window instantly". It replaced an earlier "`base * autohideTimeModifier` heuristic". The PR describes separate "Autohide Delay" and "Fullscreen Reveal Delay" controls and uses one duration for both show and hide. — [docky PR #50](https://github.com/josejuanqm/docky/pull/50)
- Plank (Linux dock) has separate `HideDelay` ("Time (in ms) to wait before hiding the dock.") and `UnhideDelay` ("Time (in ms) to wait before unhiding the dock.") preferences. — [Plank DockPreferences.vala](https://raw.githubusercontent.com/ricotz/plank/master/lib/DockPreferences.vala)
- Plank logic: `hide()` cancels any pending unhide and hides at once if HideDelay is 0, otherwise it arms a one-shot timer. `show()` cancels any pending hide. **Pointer-driven reveals wait for UnhideDelay. Reveals caused by window-overlap recalculation are immediate** (`pointer_update = false`). Window-state recalculation is debounced with `UPDATE_TIMEOUT = 200U` ms. — [Plank HideManager.vala](https://raw.githubusercontent.com/ricotz/plank/master/lib/HideManager.vala)
- The Core Animation / AppKit animator proxy has a default duration of 0.25 s, which NSAnimationContext can change. — [Pearson Core Animation sample PDF](https://ptgmedia.pearsoncmg.com/images/9780321617750/samplepages/0321617754_Sample.pdf)
- Complaints go both ways in other docks and panels. There are bug titles like "Auto hide is too slow" (Plank/Launchpad) and "Autohide Too Fast" (AWN), plus KDE requests for a "configurable delay for reveal of auto-hide panel". Users want reveal *delay* and slide *speed* as separate controls. One Directory Opus thread notes that its "delay" settings "really aren't delays… they are reveal and hide speed settings". — [Launchpad bug 264798](https://bugs.launchpad.net/bugs/264798), [AWN bug 130233](https://bugs.launchpad.net/awn/+bug/130233), [KDE bug 297109](https://bugs.kde.org/show_bug.cgi?id=297109), [KDE bug 267277](https://bugs.kde.org/show_bug.cgi?id=267277), [DOpus forum](https://resource.dopus.com/t/autohide-delay-for-taskbar-toolbars/23451)
- Dockside users report that a shelf next to the Dock still animates with a delay even when the system autohide timer is 0. Users notice when a third-party surface does not match the system Dock settings they chose. — [Dockside feedback](https://dockside.featurebase.app/p/dockside-shelf-animation-still-has-delay-when-autohide-timer-set)

### Inferences
- **Recommended defaults:**
  - Reveal dwell: 0.12–0.2 s. Slide-in: 0.20–0.25 s with ease-out (decelerate, e.g. `CAMediaTimingFunction(controlPoints: 0.2, 0.8, 0.2, 1)` or a critically damped spring of about 0.25 s).
  - Slide-out: 0.18–0.25 s with ease-in (accelerate). Hide grace after the pointer leaves: 0.25–0.4 s.
  - "Snappy" preset: dwell 0–0.05 s plus velocity gating (section 3), slide 0.15–0.2 s, hide grace about 0.15 s.
  - Keep reveal delay, slide duration and hide delay as three separate settings (Plank and Docky both split them).
- Apple's 0.2 s is a *stillness* dwell ("mouse doesn't move"), not a plain timer. Copy that idea: restart the dwell timer on each mouse-moved event at the edge, or reveal immediately if pointer speed is below a threshold.
- Optionally read `com.apple.dock autohide-delay` and `autohide-time-modifier` with `UserDefaults(suiteName: "com.apple.dock")` or `CFPreferencesCopyAppValue`, and default to them, so users with `delay 0` tweaks get the same feel. The Dockside complaint shows users expect this. Docky first scaled from the modifier and later moved to its own setting.
- Make interruptions instant. If the pointer comes back during the hide slide, reverse from the current presentation position with the show curve and no dwell. The user has already shown intent.
- Plank reveals instantly for state-driven (non-pointer) reasons. Copy that: keyboard toggle, drag start and menu open reveal with no dwell.

### Gaps
- The relationship between autohide-time-modifier and actual duration is unclear. macos-defaults calls 0.5 "seconds", while Docky's old code treated the value as a multiplier on a base. I could not find Apple documentation or a frame-timing measurement of the stock Dock's actual slide length or easing curve.
- I found no source showing the stock Dock's *hide* delay after the pointer leaves. My recollection is that it hides almost at once, but this is unverified.
- I could not verify a sourced "0.15" community value. Plank's GSettings default values for HideDelay/UnhideDelay could not be fetched (schema URL 404).

## 2. Implementation: Core Animation in a fixed window vs NSWindow frame animation; display links; avoiding layout

### Takeaway
Animating an NSWindow's frame is known to be sluggish, jagged or main-thread-blocking. Keep the window fixed and slide a layer (transform/position) with Core Animation, starting from the presentation layer so the slide can be interrupted and reversed. Use `NSView.displayLink(target:selector:)` (macOS 14+) only if you need per-frame logic, and never set `isHidden` on the view that owns the link, because a hidden view's link stops.

### Cited Findings
- `NSView.displayLink(target:selector:)` (macOS 14.0+) returns a `CADisplayLink`. Quote: "whose callback will be invoked in-sync with the display the view is on". Quote: "If the view is hidden, or not on any display, the callback will not be invoked." — [Apple: NSView.displayLink(target:selector:)](https://developer.apple.com/documentation/appkit/nsview/displaylink(target:selector:).md)
- Third-party toolkits use the view-attached `CADisplayLink` on macOS 14+ and fall back to CVDisplayLink on macOS 13, guarding the new API with availability checks. — [day-toolkit-appkit frame.rs](https://docs.rs/crate/day-toolkit-appkit/latest/source/src/frame.rs), [Chromium ca_metal_display_link_mac.mm](https://chromium.googlesource.com/chromium/src/+/main/ui/display/mac/ca_metal_display_link_mac.mm)
- Window-frame animation is reported as sluggish and jagged even when view animations inside the same window are smooth. NSViewAnimation, the window `animator` proxy and explicit CAAnimations on the proxy all gave similar results. — [cocoa-dev msg00525](https://lists.apple.com/archives/cocoa-dev/2010/Jul/msg00525.html), [cocoa-dev msg00527](https://lists.apple.com/archives/cocoa-dev/2010/Jul/msg00527.html)
- `setFrame:display:animate:` is "generally smooth" but **blocks the main thread**, and a window can only resize as fast as its contents redraw. — [cocoa-dev msg00526](https://lists.apple.com/archives/cocoa-dev/2010/Jul/msg00526.html), [cocoa-dev msg00530](https://lists.apple.com/archives/cocoa-dev/2010/Jul/msg00530.html)
- Docky's `MainWindow` "reads the preference directly for its slide animation". The PR does not say whether it moves the window frame or a layer. — [docky PR #50](https://github.com/josejuanqm/docky/pull/50)
- Docky had a bug where "A small sliver of the dock can be seen when in fullscreen mode" (#14). A fix PR (#61) was titled "conceal the hidden dock's reveal sliver instead of leaving it painted". A parked or hidden dock that leaves pixels visible is a real, reported failure. — [docky issues list](https://github.com/josejuanqm/docky/issues?q=hide)

### Inferences
- **Recommended architecture:**
  - Window: one borderless, non-activating `NSPanel` per active display. Size it to the fully revealed dock plus shadow and magnification headroom, with `level` around `.statusBar` or `.dock`-equivalent and `collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]`. Do not resize or move it during the slide.
  - Animation: slide a container layer's `transform.translation.y` (or `position.y`) between 0 and +height.
  - Interruption: on interrupt, read `layer.presentation()?.value(forKeyPath:)`, set the model value to the target inside `CATransaction.setDisableActions(true)`, and add a `CABasicAnimation` or `CASpringAnimation` from the presentation value. Scale the duration by the remaining distance so mid-slide reversals keep a constant speed.
  - Compositing: this runs on the render server, vsync-aligned, and does not touch the main thread per frame.
- When fully hidden, also set `alphaValue = 0` on the window or `opacity = 0` on the layer, then `ignoresMouseEvents = true`. Leaving a 1-pt translated edge on screen causes Docky's "sliver" bug. Don't `orderOut` on each hide. Re-ordering windows can flicker and costs a WindowServer round trip. Avoid `isHidden` on the view hosting a display link, since its callback stops.
- **No layout during the slide:** finish icon layout before the slide starts. Avoid Auto Layout, `needsLayout` or `needsDisplay` on the moving hierarchy and keep `layerContentsRedrawPolicy = .never` or `.onSetNeedsDisplay`. Don't animate `NSVisualEffectView` or blur sizes. Translate a precomposed container instead.
- Use a display link (`view.displayLink` on 14+) only to poll `NSEvent.mouseLocation` for hover/dwell logic while near the edge, or for spring physics you compute yourself. Pause it (`isPaused = true`) when the pointer is far from the edge, to save energy.
- Set `preferredFrameRateRange` on the CADisplayLink for ProMotion displays. Most of the benefit comes from staying compositor-driven, not from frame rate.

### Gaps
- I found no modern (2023+) Apple statement or benchmark comparing NSWindow frame animation with layer animation on macOS 14–27. The jank evidence is from 2010 mailing lists and may be partly outdated.
- I found no source for the exact window level and collection behaviour the stock Dock uses.

## 3. Triggers: global monitors vs edge windows, horizontal span, pressure/dwell, dragging, hot corners, stacked displays

### Takeaway
`NSEvent.addGlobalMonitorForEvents` can watch mouse-moved and drag events **without** Accessibility permission (only key events need it). It skips your own app's events, so add a local monitor too. Plank shows a good model: accumulate "pressure" against the edge (threshold 60 px, at most 15 per event, decaying after 1 s) and force the dock visible during drags and menus. With stacked displays, the bottom edge of the upper display is not a real edge. Apple's own Dock jumps only on true bottom edges, and Docky has an open bug for getting this wrong.

### Cited Findings
- Global monitor: "Installs an event monitor that receives copies of events the system posts to other applications". Events "are delivered asynchronously" and you "cannot modify or otherwise prevent the event". Quote: "Key-related events may only be monitored if accessibility is enabled or if your application is trusted for accessibility access". Quote: "your handler will not be called for events that are sent to your own application." Monitorable types include `NSMouseMoved`, `NSLeftMouseDragged`, `NSRightMouseDragged`, `NSOtherMouseDragged`, mouse up/down, `NSScrollWheel` and `NSFlagsChanged`. — [Apple: addGlobalMonitorForEvents](https://developer.apple.com/documentation/appkit/nsevent/addglobalmonitorforevents(matching:handler:).md)
- **Plank pressure reveal** uses XFixes pointer barriers:
  - Constants: `PRESSURE_THRESHOLD = 60.0` (accumulated px) and `PRESSURE_TIMEOUT = 1000U` ms. After the pointer leaves the barrier, a 1000 ms timer resets pressure to zero if the barrier isn't hit again.
  - Each hit adds at most `Math.fmin (15.0, distance)`, where distance is the perpendicular component. Pressure accumulates only when the slide along the edge is less than the perpendicular push (`slide < distance`).
  - Reaching the threshold sets `Hovered = true` and reveals. With PressureReveal on, plain enter events are ignored while the dock is hidden, so pressure alone controls reveal.
  — [Plank HideManager.vala](https://raw.githubusercontent.com/ricotz/plank/master/lib/HideManager.vala)
- Plank sets `Disabled` and **forces the dock visible immediately with no delay** when "a window menu is visible or an internal or external drag is active". Normal hide logic, with HideDelay, resumes once the condition clears. Plank's hover test uses a "cursor region" (`get_cursor_region()`), not the whole edge. — [Plank HideManager.vala](https://raw.githubusercontent.com/ricotz/plank/master/lib/HideManager.vala)
- Apple Dock on multiple displays (Apple Community, user-reported):
  - The Dock moves when you push the pointer against the **bottom edge** of another display. Moving across the seam between two displays only switches the active screen.
  - The Dock "cannot move to a display if the bottom edge of that display fully overlaps with another one". The workaround is to shift one display slightly in Arrange Displays.
  - In a vertically stacked setup (macOS Tahoe 26.1), "The Dock always appears on the very bottom edge of the lower monitor". The suggested trick is to "slightly shift the vertical layout by a few pixels" so the upper display's bottom edge becomes reachable. Quote: "There is no setting to configure the Dock location across screens."
  — [Apple Community thread 256192595](https://discussions.apple.com/thread/256192595), [search-result summary incl. Apple Community 256165313](https://discussions.apple.com/thread/256165313)
- Forum users say the Dock follows the pointer between displays only when "Displays have separate Spaces" is on. — [Apple Community 253716507](https://discussions.apple.com/thread/253716507), [Keyboard Maestro forum](https://forum.keyboardmaestro.com/t/any-way-to-keep-dock-always-on-the-same-monitor-and-still-use-spaces/26444), [Apple Community (KR mirror) 256019856](https://discussions-kr-prz.apple.com/thread/256019856)
- **Docky #47 "Dock appears on screen below"** (open). With a laptop below the main monitor and follow-mouse mode, Docky's hidden strip shows up at the *top* of the lower screen. A commenter explained that a hidden dock parked below the upper display is "on the other screen" ("In a stacked arrangement it isn't off-screen at all"). The proposed fix is to compare every `NSScreen` frame, find the edges that border another display, and never park or hide across them. — [docky issue #47](https://github.com/josejuanqm/docky/issues/47)
- DockDoor (window previews on the native Dock) fixed "windows hanging when users set long hover delays" in v1.3.3, and disabled its "prevent dock hide" option by default because it caused window resizing. — [DockDoor v1.3.3 release notes](https://newreleases.io/project/github/ejbills/DockDoor/release/v1.3.3)
- DockDoor #54 requested a delay before showing the *next* app's preview, because it showed instantly when moving between icons. Users want a long initial delay but instant switching once the UI is engaged. — [DockDoor issue #54](https://github.com/ejbills/DockDoor/issues/54)

### Inferences
- **Trigger source.** Use a global monitor for `.mouseMoved`, `.leftMouseDragged`, `.rightMouseDragged` and `.otherMouseDragged`, plus a local monitor for the same types. This needs no TCC permission.
  - The global monitor is async and misses events sent to your own app. While the pointer is within about 40 pt of the edge, also poll `NSEvent.mouseLocation` from a display link. That gives a reliable pointer position at vsync and catches the "already at edge when monitor starts" case.
  - Avoid a 1-pt transparent "edge tracking window". To get tracking areas it must accept mouse events, which steals clicks on the bottom pixel row of apps beneath it (e.g. scroll bars, resize handles).
- **Horizontal span.** Reveal only when the pointer is at the edge *and* within the dock's horizontal span, padded by about 8–16 pt. This keeps clicks at the bottom of windows elsewhere, and bottom hot corners, from triggering the dock. Plank's "cursor region" works the same way.
- **Pressure on macOS without pointer barriers.**
  - The cursor clamps at a true screen edge, but `NSEvent.deltaY` keeps reporting motion. Accumulate positive downward deltas while `mouseLocation.y <= screen.frame.minY + 1`, using Plank's constants scaled to points: threshold about 40–60 pt, per-event cap about 15, decay or reset after 1 s away from the edge.
  - Count a delta only when |dy| > |dx|, matching Plank's `slide < distance`. Offer modes: dwell (default, 0.12–0.2 s of stillness), pressure (opt-in), instant.
- **Drags.** While any `leftMouseDragged` is active (e.g. a Finder file drag), reveal as soon as the pointer reaches the edge within the span. Skip the dwell or keep it at 0.1 s or less, and never auto-hide while the dock is a drop target. This is Plank's `Disabled` rule.
- **Hot corners.** Exclude about 6–10 pt at each bottom corner of the display from the trigger zone. Never cover the extreme corner pixels with an interactive window, so system hot corners (`com.apple.dock wvous-bl-corner` / `wvous-br-corner`) keep working.
- **Stacked displays.**
  - On `NSApplication.didChangeScreenParametersNotification`, compute for each screen whether its bottom edge (over the dock's horizontal span) is a *true* edge, i.e. no other `NSScreen.frame` touches it from below.
  - Only arm reveal triggers on true edges. On the upper display, use pressure or dwell only on the x-ranges not covered by the lower display.
  - Never park a hidden dock in a way that spills onto the screen below (Docky #47). Use opacity 0 plus a clip to the screen's own frame instead of translating out of bounds.
- **Hysteresis.** The "leave" region should be the dock's visible frame expanded by about 8–20 pt on top and sides, larger than the "enter" region. This stops show/hide flapping at the boundary.

### Gaps
- I did not verify whether the stock macOS Dock reveals only within its horizontal span or anywhere along the bottom edge. I found no Apple doc.
- I did not test or find a source on whether `NSEvent.deltaY` keeps reporting at a clamped edge for global monitors on macOS 14–27. It's a common technique, but unverified here.
- I could not find how the stock Dock handles file drags (exact dwell) or its interaction with bottom hot corners.

## 4. Edge cases: multi-display, notch, Stage Manager, full screen, Mission Control/Exposé/Show Desktop, lock/sleep/wake, fast user switching, Reduce Motion, Option-Command-D, open menus

### Takeaway
The failure modes users report for third-party docks are a hidden dock leaving a visible sliver, the dock hiding or revealing wrongly after Mission Control or Space changes (stale window bounds), the system Dock reappearing in App Exposé, wrong-display placement with stacked monitors, and the system Dock's own autohide left broken after install or uninstall. Design every check to fail toward "visible", rerun state checks after Space and app activation changes, and respect Reduce Motion through the NSWorkspace API.

### Cited Findings
- **Stale bounds after Mission Control** (docky PR #32, fixing #20): "`CGWindowList` bounds go stale after a Mission Control / Space transition". The window you land on is reported at full-screen bounds until it is next interacted with, so the dock wrongly hides. The fix cross-checks the `CGWindowList` fullscreen match against Accessibility-reported frames. Quote: "Fail-safe direction is "leave the dock visible."" A `scheduleFullscreenRecheck()` runs after `didActivateApplicationNotification`. — [docky PR #32](https://github.com/josejuanqm/docky/pull/32)
- Other Docky full-screen and system-Dock issues:
  - #17 "Inconsistent behavior when trying to unhide the dock in fullscreen mode with "Hide in Fullscreen" enabled" (open).
  - #34 "Hide In Fullscreen" did not work on Zen Browser, fixed by PR #48 "hide in fullscreen for single-window apps".
  - PR #51 "hide for full-axis tiled windows flush against Docky's edge".
  - #78 "System Dock appears when using App Exposé despite "Hide System Dock"" (open).
  - #18 system Dock still visible despite "Hide System Dock".
  - #79 windows don't use the full screen area when the system Dock is hidden.
  — [docky issues (hide)](https://github.com/josejuanqm/docky/issues?q=hide)
- Docky has a separate "Fullscreen Reveal Delay" setting next to "Autohide Delay". — [docky PR #50](https://github.com/josejuanqm/docky/pull/50)
- Docky requires macOS 14+, needs Accessibility and Screen Recording permissions, and uses private APIs, so it is not on the Mac App Store. A Product Hunt user reported that **the native Dock's auto-hide stopped working after installing Docky on macOS 26.4.1**. The maintainer suggested turning off the "hide native Dock" toggle and promised a restoration helper. — [docky (ecosyste.ms summary)](https://awesome.ecosyste.ms/projects/github.com%2Fjosejuanqm%2Fdocky), [Product Hunt: Docky](https://www.producthunt.com/p/docky-the-dock-rebuit-for-focus)
- uBar: a MacRumors user said the Dock no longer auto-hid, suspected uBar, and saw it persist after deleting the app (single anecdote, no fix). — [MacRumors thread](https://forums.macrumors.com/threads/m1-mba-dock-will-no-longer-autohide.2332310/)
- The system Dock can't be disabled. It is a SIP-protected launch agent, `killall Dock` respawns it, and a hidden Dock still occupies coordinate space on the display beneath (commenter analysis on Docky #47). — [docky issue #47](https://github.com/josejuanqm/docky/issues/47)
- Reduce Motion: `NSWorkspace.shared.accessibilityDisplayShouldReduceMotion` (macOS 10.12+). Quote: "If this property's value is true, avoid large animations, especially those that simulate the third dimension." Observe `accessibilityDisplayOptionsDidChangeNotification` on `NSWorkspace.shared.notificationCenter`. — [Apple: accessibilityDisplayShouldReduceMotion](https://developer.apple.com/documentation/appkit/nsworkspace/accessibilitydisplayshouldreducemotion.md)
- Display links stop for views that are hidden or "not on any display". Display disconnect or sleep pauses a per-view link. — [Apple: NSView.displayLink](https://developer.apple.com/documentation/appkit/nsview/displaylink(target:selector:).md)
- Multi-display Dock placement depends on "Displays have separate Spaces". There is no Apple setting to pin the Dock to a display, and users turn to tools like DockLock Lite. — [Apple Community 256192595](https://discussions.apple.com/thread/256192595), [BinaryAge forum "Dock moving to Display2"](https://discuss.binaryage.com/t/dock-moving-to-display2/3647)
- ActiveDock's product page lists multiple-monitor support only in its Pro Lifetime tier. I found no ActiveDock autohide documentation. — [ActiveDock page (noteifyapp)](https://noteifyapp.com/activedock)
- `hideDock` presentation options behave inconsistently on multi-monitor Macs (developer forum thread title). Native "Dock does not hide on full screen" reports were "fixed" by `killall Dock`. — [Apple Dev Forums 698725](https://developer.apple.com/forums/thread/698725), [Apple Dev Forums 666789](https://developer.apple.com/forums/thread/666789)

### Inferences
- **State machine with fail-safes.** Model the dock as a state machine `{hidden, revealing, shown, hiding}`, with *inhibitors* that force `shown` and pause hide timers:
  - Inhibitors: context menu open, drag in progress, dock is first responder for a rename/search field, a popover or stack is open, the keyboard-toggle "pinned" state.
  - Inhibitors that force `hidden` or suspended: screen locked, session inactive, true full-screen Space on that display.
  - Track menus by setting a flag in `NSMenuDelegate.menuWillOpen` and clearing it in `menuDidClose`. When the menu closes, recheck the pointer position before arming the hide timer. This avoids hiding under the user's pointer just after a menu selection.
  - Always rerun `recomputeVisibility()` after these events, then again after a short debounce of about 200 ms (Plank's `UPDATE_TIMEOUT`):
    - `NSWorkspace.activeSpaceDidChangeNotification`
    - `didActivateApplicationNotification`
    - `NSApplication.didChangeScreenParametersNotification`
    - `NSWorkspace.screensDidWakeNotification` / `didWakeNotification`
    - `NSWorkspace.sessionDidBecomeActiveNotification` (fast user switching)
    - the distributed notifications `com.apple.screenIsUnlocked` / `com.apple.screenIsLocked`
- **Never-stuck rules:**
  1. Any hide timer is cancelled by any pointer event inside the leave region.
  2. On every display-link tick or monitor event while `shown`, recheck the pointer position. Don't rely only on `mouseExited`, which can be missed across Space switches, sleep and display reconfiguration.
  3. After wake or unlock, or when screens change, snap to the correct end state with no animation, then resume.
  4. Keep a watchdog. If `shown` and the pointer has been outside the leave region for more than 2 s with no inhibitor, force-hide.
  5. Make full-screen detection fail toward visible, as in Docky PR #32.
- **Multi-display:**
  - Separate Spaces on: the dock can follow the pointer to whichever display's *true* bottom edge was triggered. Move the window there while hidden, never mid-slide.
  - Separate Spaces off: the system treats displays as one space. Pin to the main display or a user-chosen display, and still avoid edges shared with another screen (Docky #47).
  - On connect/disconnect, or when `NSScreen.main` or `NSScreen.screens.first` changes, rebuild the per-screen windows and recompute true edges.
- **Notch / menu bar.** Not relevant to a bottom dock, except that `NSScreen.safeAreaInsets` / `auxiliaryTopLeftArea` only affect the top edge. Use `screen.frame` (not `visibleFrame`) for the bottom trigger, because `visibleFrame` changes when the system Dock is shown or hidden.
- **Stage Manager.** Its strip sits at the left edge, so a bottom dock mostly coexists. Window-overlap ("intelligent hide") logic must ignore Stage Manager thumbnails.
- **Full-screen apps.** Hide by default. Reveal only with the fullscreen-specific dwell or pressure (Docky has a separate "Fullscreen Reveal Delay"). `.fullScreenAuxiliary` lets the panel appear over full-screen Spaces.
- **Mission Control / App Exposé / Show Desktop / Launchpad-Apps.** During these, the pointer can hit the bottom edge while the user is choosing a window. Suppress reveals while Mission Control is active, e.g. detect the frontmost-app/Space transition, or treat `activeSpaceDidChange` as a 300–500 ms reveal blackout. Rerun window-overlap checks afterwards because of stale CGWindowList bounds. If you hide the system Dock, expect it to reappear in App Exposé (Docky #78). Document this rather than fight it.
- **Reduce Motion.** When on, replace the slide with a short crossfade (about 0.1–0.15 s opacity) or an instant swap. Keep the dwell, since dwell is about intent, not motion.
- **Option-Command-D.** This system shortcut toggles the *system* Dock's autohide. A third-party dock should offer its own toggle shortcut, possibly the same combo through a registered hotkey (Carbon `RegisterEventHotKey` doesn't need Accessibility). On toggle, reveal or hide instantly (no dwell) and treat it as a pin/unpin until the next toggle.
- **Restore the system Dock.** If the app ever changes `com.apple.dock` defaults (e.g. a long `autohide-delay` to bury the system Dock), save the originals and restore them on quit or uninstall, and offer a "restore system Dock" button. Both the uBar anecdote and the Docky 26.4.1 report show users blame the third-party app when the system Dock's autohide stays broken.

### Gaps
- I found no primary source on how the stock Dock behaves during Mission Control, Show Desktop, Launchpad/Apps, screen lock or fast user switching on macOS 14–27. The inferences above are my own engineering judgement.
- I found no source on whether the stock Dock replaces its slide with a fade under Reduce Motion.
- I found no source on Stage Manager's interaction with bottom auto-hiding panels.
- I did not fetch Apple Support's Dock article confirming Option-Command-D. It is widely known, but it has no URL in these notes.
- The distributed notification names `com.apple.screenIsLocked` / `com.apple.screenIsUnlocked` are undocumented. I did not verify them in this session.

## 5. What well-regarded third-party docks do, and user complaints

### Takeaway
Among the docks examined, only Plank and josejuanqm/docky have readable code or PRs. Plank's HideManager is the best reference for trigger and inhibitor logic. Docky's PR and issue history covers modern macOS failure modes: sliver, stale bounds after Mission Control, App Exposé, stacked displays, broken system-Dock autohide. For uBar and ActiveDock I found only marketing pages and anecdotes, and no technical documentation.

### Cited Findings
- **Plank:** HideMode options none / intelligent / auto / dodge-maximized / window-dodge / dodge-active; separate HideDelay and UnhideDelay in ms; optional PressureReveal; 200 ms debounce on window-state changes; menus and drags force the dock visible; plain enter events are ignored when pressure reveal is on. — [Plank DockPreferences.vala](https://raw.githubusercontent.com/ricotz/plank/master/lib/DockPreferences.vala), [Plank HideManager.vala](https://raw.githubusercontent.com/ricotz/plank/master/lib/HideManager.vala)
- **josejuanqm/docky** (GPLv3, macOS 14+, launched April 2026): slide 0.22 s by default (0–1 s); separate autohide delay and fullscreen reveal delay; known issues listed in section 4 (#14 sliver, #17 fullscreen reveal inconsistency, #20 dock hiding with autohide off, #47 stacked displays, #78 App Exposé). — [docky PR #50](https://github.com/josejuanqm/docky/pull/50), [docky issues](https://github.com/josejuanqm/docky/issues?q=hide), [docky PR #32](https://github.com/josejuanqm/docky/pull/32), [docky issue #47](https://github.com/josejuanqm/docky/issues/47)
- **DockDoor** (window previews over the native Dock): hover-delay hangs fixed in v1.3.3. The "prevent dock hide" option, which keeps the native Dock up while previews show, was off by default because it caused window resizing. Showing the next preview instantly ignored the configured delay (#54, fixed in 1.2). — [DockDoor v1.3.3](https://newreleases.io/project/github/ejbills/DockDoor/release/v1.3.3), [DockDoor #54](https://github.com/ejbills/DockDoor/issues/54)
- **uBar:** only one anecdotal complaint found (the system Dock's autohide stayed broken after removal). — [MacRumors](https://forums.macrumors.com/threads/m1-mba-dock-will-no-longer-autohide.2332310/)
- **ActiveDock:** multi-monitor support only in Pro Lifetime. No autohide specifics found. — [noteifyapp ActiveDock](https://noteifyapp.com/activedock)

### Inferences
- **Plank-style rules worth porting:**
  - Inhibitors (menus, drags) reveal instantly and block hiding.
  - Pointer reveals respect the dwell. State-driven reveals are instant.
  - Debounce window and Space recalculation by about 200 ms.
  - Pressure reveal as an opt-in mode with threshold, per-event cap and decay.
- **Docky lessons worth porting:**
  - Fully conceal a hidden dock (no sliver).
  - Cross-check CGWindowList with AX frames after Space and Mission Control transitions and fail toward visible.
  - Handle stacked displays explicitly.
  - Ship a "restore system Dock" path.
- **DockDoor lesson.** Changing the native Dock's autohide to keep it up caused window resizing (the `visibleFrame` changes). Don't toggle system Dock autohide dynamically.

### Gaps
- I found no technical documentation, changelog or forum thread for uBar's or ActiveDock's reveal delay, slide speed or multi-display autohide behaviour.
- I did not read DockDoor's GitHub issues beyond #54 and the v1.3.3 notes. There may be more autohide-related reports.
- I did not read Docky's actual slide implementation (window frame vs layer). Only PR descriptions were fetched.
