# Testing

## Unit tests

`make test` runs the XCTest suite in `Tests/`. It covers plate detection, the retro finish, magnification and shelf geometry, and parking and restoring Apple's Dock, including a run of the real crash watchdog against a throwaway preferences domain. CI runs it on every push and pull request.

## Driving the running app

Debug builds listen for commands so the dock can be driven without moving the real pointer:

```swift
DistributedNotificationCenter.default().postNotificationName(
    .init("com.kewonit.oldmacdoc.debug"), object: "pointer 760", userInfo: nil, deliverImmediately: true)
```

Commands: `pointer <x>` (hover at x, holds until `pointer` with no value), `hold on|off` (ignore the real mouse and rest the dock; it lets go by itself after a minute, and while it holds, real clicks pass through the dock, so always end with `hold off`), `press <x>` (show the pressed state), `poof <x>`, `menu <x>` (open that icon's menu for 2 s), `menu <tile-id> [press|sticky]` (open a tile's menu, `::separator` for the separator; `press` as if the button were still down), `menu-move <x> <y>` / `menu-release <x> <y>` (screen points, as a held button would), `menu-key down|up|left|right|return|esc|<letter>`, `menu-option on|off`, `menu-choose <title>/<title>` and `menu-choose-dry …` (choose, or only highlight, a row through submenus), `menu-close`, `click <tile-id>` (a plain click), `stack <folder name> [fan|grid|list]`, `stack-open <item name>`, `stack-close`, `add-stack <path>`, `drop <x> <path>|<path>` (as dropping files on the dock at x), `dump` (write the dock's menu, stack and window state to `oldmacdoc-dump.json` in the user's temporary folder, including `appleMenuOpens`, how many times Apple's menu has been opened), `apple-items on|off` (the App items in menus setting), `apple-read` (read every app's menu from Apple's Dock now, as is done while the screen is off; the dump's `appleMenuResults` says how each went and `appleMenusRemembered` which are remembered), `autohide on|off` (Hide automatically), `keep <bundle-id> on|off`, `reveal`, `hide`, `style clear|frosted|smoke`, `finish off|subtle|full`, `add-desktop left|right` (where Mission Control's + goes, which moves Apple's parked Dock to the other edge), `size <points>`, `stats` (append frame pacing since the last `stats` to `oldmacdoc-stats.txt` in the user's temporary folder, `$(getconf DARWIN_USER_TEMP_DIR)`), `panel` / `panel off` (the settings panel), `about`, `appearance light|dark` (this app only; no value goes back to the system's), `clearance sweep` (look at every window again, as turning hiding off does) and `clearance dump` (write the windows being watched, the dock's band and what was done to each to `oldmacdoc-clearance.json` in the user's temporary folder). These aren't compiled into Release builds.

Pair the commands with `screencapture -l <window id>` to capture the dock window on its own.

With `OLDMACDOC_TRACE` set in its environment, a Debug build writes every window event it sees and what it did about it (keeping windows clear of the dock) to standard error.

A Debug build is a new binary to macOS each time, so it usually isn't allowed Accessibility and windows aren't touched. To test that part without allowing each build, compile `Sources/Core/DockClearance.swift`, `Sources/App/AX.swift` and `Sources/App/DockClearanceController.swift` with `-D DEBUG` and a small `main.swift` (an `AccessibilityAccess` with `isTrusted`, a `DockClearanceController` with `wanted = true`, and `NSApplication.shared.run()`), and run it from a terminal that is allowed Accessibility. Save the frames of the windows that are open first and put them back afterwards: it shortens every maximised window on the current Space.

## Notes from testing on macOS 27.0.1

- **Apple's Dock:** verified on a real Mac through:
  - a clean quit (SIGTERM) and a `kill -9` crash: the watchdog restored the exact original keys;
  - a real ⌥⌘D press: re-parked faster than a 10 ms sampler could see, with no flash of Apple's Dock, and quitting still restored the original settings;
  - a 4-second rest on the bottom edge, and a drag held on the edge: only one dock was visible each time;
  - launch order: Apple's Dock is parked about 80 ms before ours appears.

  A unit test runs the real watchdog script against a throwaway preferences domain.
- **Real pointer, no permissions:** synthetic mouse events confirmed that hover magnification, labels, the context menu, drag-to-reorder (including dragging back to the starting point) and auto-hide reveal and hide all work. Global mouse-moved monitoring needs no Accessibility permission on macOS 27.
- **Rendering:**
  - Every frame is drawn from a display link, so motion is even however often pointer events arrive. All geometry for a frame (icons, floor, its outline, reflections, separator and the blur behind the glass) is applied in one transaction with implicit animations off, so nothing can drift apart or flicker.
  - Magnification eases in and out over about 0.09 s, and tracking inside the dock is direct. Reorders slide from where the icons were drawn (FLIP); arrivals grow in and departures shrink away.
  - The blur mask is a stretchable image redrawn only when the shelf's height or slant changes.
- **Cost:** 0.0% CPU at idle (the display link pauses once everything settles), about 4–6% (Debug build) while the pointer sweeps the dock at 120 Hz, and a physical footprint of about 85 MB with roughly 30 icons cached at 512 px.
  - Count WindowServer too. While the dock animates at 120 Hz, WindowServer used about 45% of a core on a 14-inch MacBook Pro on macOS 27 (about 22% during auto-hide slides). That is the same as a 10 pt square animating in a tiny window at 120 Hz (46%; 27% at 60 Hz), so it's the price of compositing at that rate, not of what the dock draws. Hiding every layer group didn't change it, and neither did removing the per-frame shape masks.
  - Frame pacing (`stats`): auto-hide slides run at a steady 120 fps; while hovering, frames follow the pointer, about 4 ms after it moves (8 ms at the 95th percentile).
  - A cold re-render of 21 icons after a finish change took about 4.5 CPU-seconds in a Debug build, once per finish level. Changing the shelf renders nothing.
- **Full screen:** the panel is not marked `.fullScreenAuxiliary`, so the system keeps it off full-screen Spaces. A window-bounds check can't tell full screen from a zoomed window on notched displays, so the app doesn't use one.
- **Plate detection:** on this Mac, 23 of 25 third-party apps ship a legacy `.icns`, which is used first. Designed light squircles (Slack, Chrome, VS Code, Figma) look just like a light plate in colour, so detection is deliberately conservative. Plate removal shouldn't be advertised until it has been checked against real plated apps.
- **Both docks:** a real app requesting attention no longer brings up Apple's Dock while it's parked. Without `no-bouncing`, the bouncing icon was verified to appear. A slower `autohide-time-modifier` did not prevent it, so it isn't used.
- **Mission Control:** in both modes, only one dock shows. It was checked at 80, 180 and 400 ms into Mission Control and just after exit. With the pointer on the bottom edge during Mission Control in auto-hide mode, ours stayed down. Research and measurements are in `reports/Mission Control dock conflicts.md`.
- **Windows and the dock, with hiding off** (TextEdit, Chrome, Slack, WhatsApp, Claude and a terminal, through the controller run from a terminal):
  - Window > Zoom, Fill, Left, Right, Bottom, Bottom Left and Bottom Right end at the dock's top (bottom 921 on a 982 pt display with the resting icons 61 pt up); Top is left alone. Zoom again and Fill again put the window back where it was. Filled windows that were already open were shortened as soon as it started. The dock growing moved shortened windows up with it, four times in a row with no app left alone; shrinking left them. Changes made while Mission Control was up waited for it to close. With hiding on, Fill was left alone.
  - Fill and tiling animate the frame in about 40 steps over 0.3 s, and WindowManager sets the tiled frame again if it's changed within about 0.6 s of the start (changed 0.45 s after the menu command, or 0.585 s after the animation's first frame: put back; 0.6 s or more after the command: kept). AppKit's Zoom has no animation and no such hold.
  - Pressing the green button through Accessibility (`kAXZoomButtonAttribute`) enters full screen, as a click does. On this display (with a notch) that window's frame is exactly a filled window's (0, 33, 1512 × 949) and `AXFullScreen` is true; a filled window's is false.
  - Not checked in a real app: a double-click on the title bar and dragging a window to an edge to tile it (they need the real pointer; they run the same Fill and tile commands as the menu), resizing a window by hand into the dock (the rule is unit-tested), and "Tiled windows have margins" (off on the test Mac; unit-tested with an 8 pt gap).
- **Known limits:**
  - While a monitor is connected or disconnected, macOS can show its Dock for a moment as it rearranges the displays.
  - With hiding off, a maximised window fills the screen and then steps up above the dock: there's no way to make room before macOS sizes it.
  - In full-screen apps neither dock appears: Apple's is parked, and ours stays off full-screen Spaces. Adding ours there needs full-screen detection tested on a real full-screen app.
- **Quit and reopen:** quitting and opening again within a second (as an update's relaunch does) keeps Apple's Dock parked, with exactly one watchdog. Before the fix, a leftover watchdog restored Apple's Dock while the new copy ran.
  - In Mission Control and App Exposé macOS still shows its own Dock, as a strip on the side edge it's parked on. Hiding it completely would need private SkyLight tricks that take over the front process, so it isn't done.
  - Ours staying on screen and coming up in Mission Control (`.stationary`, with Apple's Dock on a side edge) is covered by unit tests for the parking only; check it by hand with F3 and App Exposé, in both auto-hide modes.
  - Show Desktop wasn't exercised on macOS 27: its launch arguments no longer work, and the trigger needs a real key or gesture.
- **App items in menus (1.2.5),** on a real Mac with a build signed to keep Accessibility:
  - Right-clicking apps, a not-running app, the Trash and the separator never opened Apple's menu (`appleMenuOpens` stayed 0), with nothing remembered and after a full read.
  - Display asleep (`pmset displaysleepnow`): all 19 apps read, about 50 ms each. Woken 2 s in: the reads that opened Apple's menu were all before the wake, and the next one was skipped. Woken and slept again mid-read: the reading started over and finished. Started while the screen could be seen: nothing read.
  - The screen saver posted `com.apple.screenIsLocked` as it started (the Mac locked), but no stop or unlock notice when it was ended by killing it: why the state is asked of macOS each time.
  - App items in menus off: no items and nothing read while asleep. Apple's Dock parked on the left: read the same. Hiding off, all three shelves and keyboard navigation: menus unchanged. Without Accessibility: menus without app items, nothing read.
  - A paused app (`kill -STOP`): the menu opened at once and kept the keyboard; Application Not Responding and Force Quit appeared in place about 3 s later. Open at Login pressed twice in a row: both took effect.
  - Not checked: VoiceOver, and a Mac locked for real (rather than the display asleep) while reading.
- **Research:** the notes behind these choices are in `reports/` and `research_notes/`.
