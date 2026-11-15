# Testing

## Unit tests

`make test` runs the XCTest suite in `Tests/`. It covers plate detection, the retro finish, magnification and shelf geometry, and parking and restoring Apple's Dock, including a run of the real crash watchdog against a throwaway preferences domain. CI runs it on every push and pull request.

## Driving the running app

Debug builds listen for commands so the dock can be driven without moving the real pointer:

```swift
DistributedNotificationCenter.default().postNotificationName(
    .init("com.kewonit.oldmacdoc.debug"), object: "pointer 760", userInfo: nil, deliverImmediately: true)
```

Commands: `pointer <x>` (hover at x, holds until `pointer` with no value), `hold on|off` (ignore the real mouse and rest the dock), `press <x>` (show the pressed state), `poof <x>`, `menu <x>` (open that icon's menu for 2 s), `keep <bundle-id> on|off`, `reveal`, `hide`, `style clear|frosted|smoke`, `finish off|subtle|full`, `size <points>`, `stats` (append frame pacing since the last `stats` to `oldmacdoc-stats.txt` in the user's temporary folder, `$(getconf DARWIN_USER_TEMP_DIR)`), `panel` / `panel off` (the settings panel), `about`, `appearance light|dark` (this app only; no value goes back to the system's). These aren't compiled into Release builds.

Pair the commands with `screencapture -l <window id>` to capture the dock window on its own.

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
- **Known limits:**
  - While a monitor is connected or disconnected, macOS can show its Dock for a moment as it rearranges the displays.
  - In full-screen apps neither dock appears: Apple's is parked, and ours stays off full-screen Spaces. Adding ours there needs full-screen detection tested on a real full-screen app.
- **Quit and reopen:** quitting and opening again within a second (as an update's relaunch does) keeps Apple's Dock parked, with exactly one watchdog. Before the fix, a leftover watchdog restored Apple's Dock while the new copy ran.
  - In Mission Control and App Exposé macOS still shows its own Dock, as a strip on the side edge it's parked on. Hiding it completely would need private SkyLight tricks that take over the front process, so it isn't done.
  - Ours staying on screen and coming up in Mission Control (`.stationary`, with Apple's Dock on a side edge) is covered by unit tests for the parking only; check it by hand with F3 and App Exposé, in both auto-hide modes.
  - Show Desktop wasn't exercised on macOS 27: its launch arguments no longer work, and the trigger needs a real key or gesture.
- **Research:** the notes behind these choices are in `reports/` and `research_notes/`.
