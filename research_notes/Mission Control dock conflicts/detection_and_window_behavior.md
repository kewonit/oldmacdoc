# Detecting Mission Control / App Exposé / Show Desktop / Space switches, and NSWindow behaviour during them (macOS 14–27)

Evidence base and conventions used below:
- **Source code** was read from shallow clones at these commits. Links are permalinks.
  - yabai `dd84572` (2026-06-14)
  - AltTab `c500294` (2026-10-23)
  - DockDoor `3044142` (2026-10-26)
  - Hammerspoon `23e387e` (2026-07-08)
  - AeroSpace `587fc26` (2026-10-31)
  - docky `cb7a6a6` (2026-10-27)
- **"Local experiment"** means something measured on this research machine:
  - macOS **27.0.1, build 26A434**, on 2026-10-31.
  - Displays: a MacBook panel (1512×982 pt) plus an external display (2560×1080).
  - Stage Manager was off. The system Dock appears to be auto-hidden.
  - The test process ran from a terminal that already had Accessibility and Screen Recording access (`AXIsProcessTrusted()` and `CGPreflightScreenCaptureAccess()` both returned true).
  - Mission Control, App Exposé and Show Desktop were opened and closed in code with the Dock's private `CoreDockSendNotification("com.apple.expose.awake" / "com.apple.expose.front.awake" / "com.apple.showdesktop.awake")`, not with a trackpad gesture or F3.
  - The window list was sampled every 8 ms. Screenshots were taken with `screencapture`.
  - Experiment source: a local experiment folder (not included in the repository) and `mcexp2.swift`. Logs: `mcexp.log` and `mcexp2.log` in the same folder. The scratchpad is temporary, so the key raw numbers are copied below.
- **(inferred)** marks my own reasoning rather than a sourced or measured fact.

## Q1. Signals that need no special permission: distributed or Darwin notifications, `NSWorkspace.activeSpaceDidChangeNotification`, `CGWindowListCopyWindowInfo` heuristics and their cost, and `kCGWindowName` redaction

### Takeaway
No public notification announces Mission Control, App Exposé or Show Desktop.
- `com.apple.expose.awake` and its siblings are *commands sent to* the Dock through a private function. They are not broadcasts you can listen for.
- `activeSpaceDidChangeNotification` does not fire for Mission Control or Exposé.

The reliable permission-free signal is the window list. On macOS 27, and per AltTab on releases since macOS 13, the gesture overlays are owned by the **`WindowManager`** process:
- **Level 19** `ExposeShieldWindow`, sized to the screen: Mission Control and App Exposé.
- **Level 14** `Spaces Bar`: only in Mission Control.
- **Level 18** `ShowDesktopOverlay`: Show Desktop.

All three are in the window list about 18–37 ms after the trigger. One read costs about 0.2–0.5 ms when idle. Window names need Screen Recording, so the heuristic should key on owner, level and bounds.

### Cited Findings
**`com.apple.*.awake` are Dock commands, not broadcasts**
- These strings go to the Dock through the private `CoreDockSendNotification()`:
  - `com.apple.expose.awake` toggles Mission Control.
  - `com.apple.expose.front.awake` toggles App Exposé.
  - `com.apple.showdesktop.awake` toggles Show Desktop.
  - Sources: Hammerspoon `hs.spaces.toggleMissionControl/AppExpose/ShowDesktop` — [spaces.lua L244–272](https://github.com/Hammerspoon/hammerspoon/blob/23e387e2805a9890066366e0ac96c71b27f0cfd5/extensions/spaces/spaces.lua#L244-L272); [libspaces.m L246](https://github.com/Hammerspoon/hammerspoon/blob/23e387e2805a9890066366e0ac96c71b27f0cfd5/extensions/spaces/libspaces.m#L246); yabai `space_manager_toggle_mission_control` — [space_manager.c L247–257](https://github.com/koekeishiya/yabai/blob/dd845723416f5fe92af49fad5ebab00369e07edd/src/space_manager.c#L247-L257); a gist listing the CoreDock message names — [gist (search snippet)](https://gist.github.com/unixzii/7091dda6aea958c6da669e436365df65).
- docky's source says the Dock invokes this function from its own menus, and that posting the same name through `DistributedNotificationCenter` "does not route through the Dock and is a no-op". The symbol is loaded with `dlsym`. — [docky CGSPrivate.swift L188–194](https://github.com/josejuanqm/docky/blob/cb7a6a64483b5cef82b308b6a0958d0df839a779/Docky/Private/CGSPrivate.swift#L188-L194)
- Local experiment: `CoreDockSendNotification` silently did nothing when called from a bare command-line process. It worked once `NSApplication.shared` had been created, which gives the process a WindowServer connection. — Local experiment (`toggle.swift`)

**No notification fired (local experiment, macOS 27.0.1)**
Across Mission Control enter/exit, App Exposé enter/exit and Show Desktop enter/exit, none of the following arrived:
- `NSWorkspace.activeSpaceDidChangeNotification`
- any distributed notification, whether observed by name (`com.apple.expose.awake`, `com.apple.expose.front.awake`, `com.apple.showdesktop.awake`, `com.apple.dock.prefchanged` and others) or with a `nil` name
- any Darwin `notify_register_dispatch` callback for those names

The `nil`-name observer did not even receive a distributed notification the process posted itself. That suggests `nil`-name observation is not delivered at all (inferred from one test). — Local experiment, `mcexp.log`

**What Apple documents for `activeSpaceDidChangeNotification`**
- It is "a notification that the workspace posts when a Spaces change occurs".
- It has no `userInfo`.
- You must register on `NSWorkspace.shared.notificationCenter`.
- Source: [Apple docs](https://developer.apple.com/documentation/appkit/nsworkspace/activespacedidchangenotification)

**WindowManager surfaces (AltTab)**
AltTab's `MissionControlOverlay` reads which gesture is up from WindowManager surfaces, recognised "by OWNER, LEVEL and SIZE rather than by name":
- `exposeShieldLevel = 19`, `showDesktopOverlayLevel = 18`, `spacesBarLevel = 14`.
- A shield plus the Spaces bar means Mission Control. A shield alone means App Exposé. Level 18 without a shield means Show Desktop.
- The shield only counts if it is "at least as large as one of the screens".
- Sources: [MissionControlOverlay.swift](https://github.com/lwouis/alt-tab-macos/blob/c500294bdb01186011a5c64a412b04cef9931bef/src/macos/api-wrappers/MissionControlOverlay.swift); [MissionControlOverlaySpecs.md](https://github.com/lwouis/alt-tab-macos/blob/c500294bdb01186011a5c64a412b04cef9931bef/src/macos/api-wrappers/MissionControlOverlaySpecs.md)

**Stage Manager false positive (AltTab)**
- With Stage Manager on macOS 27, one 66×82 `App Icon Window` per stage can sit at level 19, off-screen. Counting it made AltTab think App Exposé was always up.
- With Stage Manager on, Show Desktop draws no `ShowDesktopOverlay`. It removes an event shield instead.
- Sources: [MissionControlOverlay.swift comments](https://github.com/lwouis/alt-tab-macos/blob/c500294bdb01186011a5c64a412b04cef9931bef/src/macos/api-wrappers/MissionControlOverlay.swift); [AltTab issue #6076](https://github.com/lwouis/alt-tab-macos/issues/6076). The issue was reported on macOS 27.0 (26A428) and fixed in AltTab 11.8.0, October 2026.

**Surfaces measured locally on macOS 27.0.1** (one per display; names visible here only because Screen Recording was granted). Source: local experiment, `mcexp.log` and `mcexp2.log`.

| Gesture | Surfaces in `CGWindowListCopyWindowInfo([.optionOnScreenOnly])` |
|---|---|
| Mission Control | `WindowManager` L19 `'ExposeShieldWindow'` 1512×982 and 2560×1080 (screen-sized). `WindowManager` L14 `'Spaces Bar'` 1512×128 and 2560×96. `Dock` L20 `'Dock'` 1512×982. Later, `WindowManager` L0/L2 `'Window Highlight Overlay'`. |
| App Exposé | `WindowManager` L19 `'ExposeShieldWindow'` (screen-sized), with no Spaces Bar. `WindowManager` L0 `'Label Window - …'` and `'Material Label Window'`. |
| Show Desktop | `WindowManager` L18 `'ShowDesktopOverlay'` (screen-sized). |
| At rest | No L14, L18 or L19 `WindowManager` windows, even with `.optionAll`. `WindowManager` owns the wallpaper (level −2147483624, `'Wallpaper'`). The Dock has one L20 `'Dock'` window, off-screen at rest on this machine. |

**Timing, measured from the `CoreDockSendNotification` call** (local experiment, two runs):
- **Mission Control enter**
  - SkyLight connection event 811 (window created) arrived at **6.0 ms**.
  - The overlay windows were present and on-screen at **20.8 ms**, checked with an `.optionAll` read triggered by 811. The 8 ms poller saw them at 29–37 ms.
  - The `Dock` L20 window came on-screen at about 45 ms.
- **Mission Control exit**
  - The L19 shield was removed only after the exit animation, at **321–325 ms**.
  - The Spaces Bar went at about 337–450 ms and the Dock L20 window at about 450–597 ms.
- **App Exposé enter**
  - Event 811 at 6.2 ms. The shield was present at 18.4 ms (811-triggered read) or 23.9 ms (poll).
  - On exit the shield was removed at about 320–334 ms.
- **Show Desktop enter**
  - L18 overlay present at 18.1 ms (poll) or 9.7 ms (811-triggered read).
  - On exit it was removed at about 313–324 ms.

**Cost of reading the window list**
- Local experiment, macOS 27.0.1, 131 windows total, 23 on screen:
  - `.optionOnScreenOnly`: p50 **0.216 ms**, p95 **0.538 ms** (200 reads).
  - `.optionAll`: p50 **0.713 ms**, p95 **1.03 ms**.
  - While the Mission Control animation was running, one `.optionAll` read took **7.8–9.6 ms**.
- AltTab measured the read "at 0.245ms p50 and 0.43ms p95", and says it "reached 22–41ms before focus in macOS 27 QA". It also measured that the overlay window "is created a beat before it is on screen (17ms, measured)", and uses a 150 ms settle delay to coalesce the burst. — [AltTab MissionControl.swift](https://github.com/lwouis/alt-tab-macos/blob/c500294bdb01186011a5c64a412b04cef9931bef/src/macos/api-wrappers/MissionControl.swift)

**`kCGWindowName` and Screen Recording**
- AltTab's source: `kCGWindowName` "would name them outright (`ExposeShieldWindow`, `Spaces Bar`, `ShowDesktopOverlay`) but it is gated on Screen Recording". Owner name, level and bounds "are not gated". — [MissionControlOverlay.swift](https://github.com/lwouis/alt-tab-macos/blob/c500294bdb01186011a5c64a412b04cef9931bef/src/macos/api-wrappers/MissionControlOverlay.swift)
- On macOS 10.15, Apple DTS (Quinn) said access to `kCGWindowName` "seems to be gated by the Screen Recording user data protection". — [Apple Developer Forums 126860 (via search snippet)](https://developer.apple.com/forums/thread/126860)
- A third-party crate claims that on macOS 12.3+ the name is redacted to an *empty string* rather than omitted. Not verified. — [car-desktop docs](https://docs.rs/crate/car-desktop/latest/source/src/macos/windows.rs)
- Apple's `kCGWindowName` reference documents no permission gating: "few applications set the Quartz window name". — [Apple docs](https://developer.apple.com/documentation/coregraphics/kcgwindowname)

**`kCGWindowOwnerName` may also be gated — conflicting reports**
- One developer reports that on **macOS 26** without Screen Recording, `kCGWindowOwnerName` is **nil** for other apps' windows. On a **macOS 27 beta 4 (26A5388g)** it was populated without permission.
- Apple DTS replied that which keys are populated without permission "is undocumented and may change at any time". DTS recommends `CGPreflightScreenCaptureAccess()` for the permission check, and `SCShareableContent` for enumerating windows.
- Source: [Apple Developer Forums 839069](https://developer.apple.com/forums/thread/839069)
- This conflicts with AltTab's statement that owner names are not gated. See the inference below.

**How yabai detected Mission Control exit on older macOS**
- yabai's legacy exit check polled `CGWindowListCopyWindowInfo` every 100 ms for a `Dock`-owned window with **no name** at **layer 18**.
- yabai registers this path (event 1204, then polling) only on releases older than Monterey. On Monterey through Tahoe it uses AX instead.
- Sources: [event_loop.c L1485–1526](https://github.com/koekeishiya/yabai/blob/dd845723416f5fe92af49fad5ebab00369e07edd/src/event_loop.c#L1485-L1526); [yabai.c L311–327](https://github.com/koekeishiya/yabai/blob/dd845723416f5fe92af49fad5ebab00369e07edd/src/yabai.c#L311-L327)

### Inferences
**Darwin and distributed notifications**
- (inferred) Neither carries Mission Control state on macOS 27. None of the projects examined (yabai, AltTab, Hammerspoon, DockDoor, AeroSpace, docky) subscribes to any for this purpose. If one existed, AltTab would not have had to build an overlay classifier.

**Match the `WindowManager` process by PID, not by owner name** (inferred)
- Forum 839069 suggests owner names can be nil without Screen Recording on macOS 26. Compare `kCGWindowOwnerPID` against the PID of the `WindowManager` process, found through `NSRunningApplication`.
  - Its bundle identifier is not confirmed in these sources. `com.apple.WindowManager` is likely and should be verified on device.
- Fall back to matching the owner name if the PID is unavailable.
- Use level plus screen-sized bounds as the main test, never `kCGWindowName`.

**What the timings mean for detection** (inferred, from the local timings)
- **Entry** is detectable within about 1–2 frames of the trigger by reading the window list.
- **Exit** shows up in the window list only about 320 ms later, when the exit animation ends. A dock that waits for the shield to go would reappear late. Use the exit signals in Q3 (own-window occlusion or order-in events at about 20–40 ms) for prompt reappearance.

**Polling cost** (inferred)
- Polling `.optionOnScreenOnly` at 60 Hz costs about 13–30 ms of CPU per second on the calling thread at idle (about 1–3 % of one core). It can spike during gesture animations. WindowServer-side cost was not measured.
- Event-driven reads, as in Q2's ranking, are preferable.

**Exit races** (inferred)
- The trigger in these tests was programmatic. Gesture-driven entry (trackpad swipe) may create the overlays progressively while the finger moves. AltTab notes that the overlay "cannot go stale" and is "what recovers when an exit notification is missed".

### Gaps
- Not checked on macOS 14, 15 or 26 directly: whether the L19, L14 and L18 overlays there are also owned by `WindowManager`.
  - AltTab's comment implies separate-process overlays exist on versions after macOS 12 ("including macOS 12, where the overlay belongs to no separate process and this never fires").
  - yabai's sub-Monterey heuristic used a Dock-owned L18 window.
  - **Must be measured on 14, 15 and 26** before relying on it there.
- `kCGWindowName` redaction was not measured, because the test process had Screen Recording. Whether names come back as nil or as an empty string on 15, 26 and 27 is not confirmed from a primary source.
- Gesture-driven (trackpad or F3) timings were not measured. Only programmatic `CoreDockSendNotification` triggers were used.
- No list of Darwin `notify(3)` names posted by the Dock or WindowManager was found. Names cannot be enumerated without private tooling.

## Q2. With Accessibility: `AXObserver` on the Dock for `AXExposeShowAllWindows`, `AXExposeShowFrontWindows`, `AXExposeShowDesktop` and `AXExposeExit`

### Takeaway
The exact strings are `"AXExposeShowAllWindows"`, `"AXExposeShowFrontWindows"`, `"AXExposeShowDesktop"` and `"AXExposeExit"`, registered on the Dock's application element with `AXObserverAddNotification`.

They worked from macOS 12 through 26 (yabai uses them for Monterey to Tahoe), and per AltTab they arrive "as the gesture starts". On **macOS 27** they are **silently dead**: the subscription returns success and nothing is ever posted. AltTab measured this on 27.0 (26A428) and this research measured it on 27.0.1 (26A434). An AltTab user log from 27.2 beta is ambiguous. Do not rely on them alone for macOS 27.

### Cited Findings
- **yabai** declares the four strings and adds them with `AXObserverAddNotification` on `AXUIElementCreateApplication(dockPid)`. It attaches the run-loop source to the main run loop, and re-subscribes when the Dock restarts (`NSApplicationDockDidRestartNotification`).
  - It calls `mission_control_observe()` only `if (workspace_is_macos_monterey() || … ventura || sonoma || sequoia || tahoe)`.
  - On older releases it instead uses `SLSRegisterConnectionNotifyProc(…, 1204, …)`, then polls for exit.
  - Sources: [mission_control.c L52–106](https://github.com/koekeishiya/yabai/blob/dd845723416f5fe92af49fad5ebab00369e07edd/src/mission_control.c#L52-L106); [yabai.c L311–327](https://github.com/koekeishiya/yabai/blob/dd845723416f5fe92af49fad5ebab00369e07edd/src/yabai.c#L311-L327); [event_loop.c L1545–1557](https://github.com/koekeishiya/yabai/blob/dd845723416f5fe92af49fad5ebab00369e07edd/src/event_loop.c#L1545-L1557)
- **yabai's event handling:**
  - `AXExposeShowAllWindows` sets mode `show-all-windows` (Mission Control).
  - `AXExposeShowFrontWindows` sets `show-front-windows` (App Exposé).
  - `AXExposeShowDesktop` sets `show-desktop`.
  - `AXExposeExit` sets inactive.
  - The `mission_control_enter` and `mission_control_exit` signals are emitted with `YABAI_MISSION_CONTROL_MODE`.
  - Sources: [event_loop.c L1452–1543](https://github.com/koekeishiya/yabai/blob/dd845723416f5fe92af49fad5ebab00369e07edd/src/event_loop.c#L1452-L1543); [mission_control.c L29–44](https://github.com/koekeishiya/yabai/blob/dd845723416f5fe92af49fad5ebab00369e07edd/src/mission_control.c#L29-L44)
- **AltTab** subscribes to the same four strings (its enum `MissionControlState` uses them as raw values). It runs its observer source on a dedicated `missionControlThread` run loop in `.commonModes`. — [DockEvents.swift](https://github.com/lwouis/alt-tab-macos/blob/c500294bdb01186011a5c64a412b04cef9931bef/src/events/DockEvents.swift); [ApplicationServices.HIServices.framework.swift L21–24](https://github.com/lwouis/alt-tab-macos/blob/c500294bdb01186011a5c64a412b04cef9931bef/src/macos/api-wrappers/ApplicationServices.HIServices.framework.swift#L21-L24)
- **AltTab on macOS 27** (source comment, quoted): the Dock's `AXExpose*` notifications "up to macOS 26 arrive as the gesture starts. On 27 the Dock accepts the subscription and posts none of the four, ever. Measured 2026-09-16 on 26A428, together with the two routes yabai uses (the WindowServer's connection notification 1204, and the Dock's unnamed layer-18 window), which are dead the same way. Nothing errors and the subscription still reports success". — [MissionControl.swift L5–19](https://github.com/lwouis/alt-tab-macos/blob/c500294bdb01186011a5c64a412b04cef9931bef/src/macos/api-wrappers/MissionControl.swift)
- **Local experiment, macOS 27.0.1 (26A434):**
  - `AXObserverAddNotification` returned `0` (`kAXErrorSuccess`) for all four.
  - **No** AX callback arrived during Mission Control, App Exposé or Show Desktop, across two runs.
  - SkyLight connection event **1204** was also never delivered, although events 811, 815, 816, 1325 and 1326 were.
  - Source: local experiment, `mcexp.log` and `mcexp2.log`
- **Conflicting data point:** an AltTab user on **macOS 27.2 beta (26B5091g)** with Stage Manager posted logs showing `AXExposeShowFrontWindows` and `AXExposeExit` after a Space change. — [AltTab issue #6076](https://github.com/lwouis/alt-tab-macos/issues/6076)
  - (inferred) This is ambiguous. AltTab's state enum raw values are those same strings, and its overlay path logs `missionControl observed <rawValue>`. The log lines may come from the window-list classifier, not from the Dock.
- **Hammerspoon** (`hs.spaces`) does not observe `AXExpose*`. It finds the Dock's Mission Control accessibility group (`AXIdentifier == "mc"`), which only exists while Mission Control is on screen. It polls for that group for up to 2 s after toggling Mission Control itself.
  - Its docs say these elements "only exist when the Mission Control display is visible".
  - Sources: [spaces.lua L83–118](https://github.com/Hammerspoon/hammerspoon/blob/23e387e2805a9890066366e0ac96c71b27f0cfd5/extensions/spaces/spaces.lua#L83-L118); [spaces.lua L175](https://github.com/Hammerspoon/hammerspoon/blob/23e387e2805a9890066366e0ac96c71b27f0cfd5/extensions/spaces/spaces.lua#L175)
- **DockDoor** at `3044142` contains no `AXExpose` or Mission Control detection code. It only observes `NSWorkspace.activeSpaceDidChangeNotification`. — [WindowManipulationObservers.swift L107](https://github.com/ejbills/DockDoor/blob/3044142c907b9cdd49917628847a04970450a8e6/DockDoor/Utilities/Window%20Management/WindowManipulationObservers.swift#L107)

### Inferences
- (inferred) **Latency on macOS 12–26.** yabai and AltTab treat the AX notification as arriving at gesture start. Delivery is a mach message to the observer's run loop, so expect low single-digit milliseconds after the Dock posts. This was not measured here, because the notifications don't fire on 27.
- (inferred) **Strategy.** On macOS 14–26, use AX as the primary signal *if* the app already has Accessibility. Always run the window-list classifier as well, because:
  - it is the only signal on 27;
  - it recovers from missed `AXExposeExit` events;
  - a subscription that silently never fires is undetectable without it.
- (inferred) **Permission.** `AXObserverCreate` and `AXObserverAddNotification` against another process require the app to be trusted for Accessibility (`AXIsProcessTrusted()`). This is standard behaviour, not re-verified in this research.

### Gaps
- No primary source for AX latency on macOS 14, 15 or 26.
- Not confirmed whether AX `AXExpose*` returns in macOS 27.1 or 27.2, or behaves differently with Stage Manager on.
- Not tested: whether a real trackpad or F3 trigger (rather than `CoreDockSendNotification`) produces AX notifications on 27.

## Q3. `NSWindow.CollectionBehavior` and window levels during Mission Control, App Exposé, Show Desktop and Space switches

### Takeaway
On macOS 27.0.1, **`.stationary` alone decides whether a window stays visible during Mission Control and App Exposé. Window level does not.**
- **`.stationary`** windows stay full-size, in place and drawn above the Mission Control shield and thumbnails, at every level tested (0, 3, 20, 24, 25, 101, 1000).
- **`.transient`** windows are hidden, and so is any non-normal-level window without an explicit behaviour (transient is the default for those). This includes level 1000 (`.screenSaver`). No level keeps a transient window above Mission Control.
- **`.managed`** windows become thumbnails in Mission Control and are hidden in App Exposé unless they belong to the front app.
- **`.auxiliary`** behaved like transient.
- **Show Desktop** hid none of the 16 test windows.

### Cited Findings
**Apple's definitions**
- `.stationary`: "Mission Control doesn't affect the window, so it stays visible and stationary, like the desktop window." — [Apple docs](https://developer.apple.com/documentation/appkit/nswindow/collectionbehavior-swift.struct/stationary)
- `.transient`: "The window floats in Spaces and hides in Mission Control. This is the default behavior if windowLevel isn't equal to normal." — [Apple docs](https://developer.apple.com/documentation/appkit/nswindow/collectionbehavior-swift.struct/transient)
- `.managed`: "The window participates in Mission Control and Spaces. This is the default behavior if windowLevel is equal to normal." — [Apple docs](https://developer.apple.com/documentation/appkit/nswindow/collectionbehavior-swift.struct/managed)
- `.canJoinAllSpaces`: "The window can appear in all spaces. The menu bar behaves this way." — [Apple docs](https://developer.apple.com/documentation/appkit/nswindow/collectionbehavior-swift.struct/canjoinallspaces)
- `.fullScreenAuxiliary`: "The window displays on the same space as the full screen window." — [Apple docs](https://developer.apple.com/documentation/appkit/nswindow/collectionbehavior-swift.struct/fullscreenauxiliary)
- `.fullScreenNone`: "The window doesn't support full-screen mode." — [Apple docs](https://developer.apple.com/documentation/appkit/nswindow/collectionbehavior-swift.struct/fullscreennone)
- `.auxiliary` (macOS 13+): "auxiliary for both Stage Manager and full screen". `.primary`, `.auxiliary` and `.canJoinAllApplications` are mutually exclusive. `.canJoinAllApplications` (macOS 13+) is meant "for floating windows and system overlays". — [auxiliary](https://developer.apple.com/documentation/appkit/nswindow/collectionbehavior-swift.struct/auxiliary); [canJoinAllApplications](https://developer.apple.com/documentation/appkit/nswindow/collectionbehavior-swift.struct/canjoinallapplications)

**Local experiment, macOS 27.0.1: 16 borderless non-activating `NSPanel`s on the primary display**
AppKit reported back exactly the requested `collectionBehavior` raw values, so it did not normalise them. Results come from screenshots taken about 1.3 s into each mode, plus window-list membership and `NSWindow.didChangeOcclusionStateNotification`. Source: local experiment; screenshots `r2_1_missioncontrol_d1.png` and `r2_2_appexpose_d1.png` in the scratchpad probe folder.

| # | Level | collectionBehavior | Mission Control | App Exposé | Show Desktop |
|---|---|---|---|---|---|
| 0 | 0 | `[]` (managed by default) | **Scaled thumbnail** in the window grid | Hidden (not the front app) | Stayed on-screen in window list |
| 1 | 0 | `.canJoinAllSpaces, .stationary` | **Visible, full size, unmoved, drawn above thumbnails** | Visible | Stayed |
| 2 | 3 | `[]` (transient by default) | Hidden | Hidden | Stayed |
| 3 | 3 | `.canJoinAllSpaces, .managed` | **Thumbnail** | Hidden | Stayed |
| 4 | 3 | `.canJoinAllSpaces, .stationary` | Visible above | Visible | Stayed |
| 5 | 20 (`kCGDockWindowLevel`) | `.canJoinAllSpaces, .transient` | Hidden | Hidden | Stayed |
| 6 | 20 | `.canJoinAllSpaces, .stationary` | Visible above | Visible | Stayed |
| 7 | 24 (`.mainMenu`) | `.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary` (docky's dock window) | Visible above | Visible | Stayed |
| 8 | 25 (`.statusBar`) | `.canJoinAllSpaces` | Hidden | Hidden | Stayed |
| 9 | 25 | `.canJoinAllSpaces, .stationary` | Visible above | Visible | Stayed |
| 10 | 101 (`.popUpMenu`) | `.canJoinAllSpaces, .transient` | Hidden | Hidden | Stayed |
| 11 | 101 | `.canJoinAllSpaces, .stationary` | Visible above | Visible | Stayed |
| 12 | 1000 (`.screenSaver`) | `.canJoinAllSpaces, .stationary` | Visible above | Visible | Stayed |
| 13 | 1000 | `.canJoinAllSpaces, .transient` | **Hidden** | Hidden | Stayed |
| 14 | 20 | `.canJoinAllSpaces, .auxiliary` | Hidden | Hidden | Stayed |
| 15 | 20 | `.canJoinAllSpaces, .stationary, .fullScreenNone` | Visible above | Visible | Stayed |

**When hidden windows actually leave and return** (local experiment, `mcexp.log` and `mcexp2.log`)
- The system orders hidden windows **out** when the *entry* animation finishes: **310–338 ms** after the trigger. At that moment each such window gets `didChangeOcclusionState` with `occlusionState` not containing `.visible`, and `isOnActiveSpace` stays true.
- It orders them back **in** at the *start* of the exit: **15–42 ms** after the toggle-off. Occlusion goes back to `.visible`, and SkyLight 815 (ordered in) events fire.
- Brief occlusion flapping was seen on the managed windows during the App Exposé exit animation.

**Other local observations**
- During Mission Control the **system Dock window** (`Dock`, L20) comes on-screen even though it is auto-hidden at rest. The system Dock stays visible in Mission Control. — Local experiment; run-1 Mission Control screenshot
- Window levels on macOS 27.0.1 via `CGWindowLevelForKey`:

| Key | Level |
|---|---|
| base | −2147483648 |
| minimum | −2147483643 |
| desktop | −2147483623 |
| desktopIcon | −2147483603 |
| backstopMenu | −20 |
| normal | 0 |
| floating / tornOffMenu | 3 |
| modalPanel | 8 |
| utility | 19 |
| dock | 20 |
| mainMenu | 24 |
| status | 25 |
| popUpMenu | 101 |
| overlay | 102 |
| help | 200 |
| dragging | 500 |
| screenSaver | 1000 |
| assistiveTechHigh | 1500 |
| cursor | 2147483630 |
| maximum | 2147483631 |

  The Mission Control overlays sit at 14 (Spaces Bar), 18 (Show Desktop) and 19 (shield). The shield shares level 19 with `kCGUtilityWindowLevel`. — Local experiment, `probe.swift`

**Full-screen Spaces (Apple DTS, tested on macOS 26)**
- `.floating` (3) and `.statusBar` (25) "both sit below full-screen content". A panel at `.screenSaver` with `[.canJoinAllSpaces, .canJoinAllApplications, .fullScreenAuxiliary, .stationary]` stayed on top over full-screen apps and on every Space, so re-ordering it on `activeSpaceDidChangeNotification` was unnecessary. Mission Control is not discussed. — [Apple Developer Forums 826308](https://origin-devforums.apple.com/forums/thread/826308)

**What existing dock-like apps use**
- **docky** (a third-party dock): level `.mainMenu` (24) with `[.canJoinAllSpaces, .stationary, .ignoresCycle]` plus `.fullScreenAuxiliary`. For "Active Space" mode it uses `[.moveToActiveSpace, .stationary, .ignoresCycle]`. — [DockyPreferences.swift L471–483](https://github.com/josejuanqm/docky/blob/cb7a6a64483b5cef82b308b6a0958d0df839a779/Docky/Services/DockyPreferences.swift#L471-L483); [MainWindow.swift L236](https://github.com/josejuanqm/docky/blob/cb7a6a64483b5cef82b308b6a0958d0df839a779/Docky/Views/MainWindow/MainWindow.swift#L236)
- **DockDoor**'s hover previews: `.statusBar` or `.floating` with `[.canJoinAllSpaces, .transient, .fullScreenAuxiliary]`, so they are hidden in Mission Control. Its gesture HUD uses `.popUpMenu` with `[.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle, .transient]`. That last one sets both stationary and transient, and its effective behaviour is untested. — [SharedPreviewWindowCoordinator.swift L94–99](https://github.com/ejbills/DockDoor/blob/3044142c907b9cdd49917628847a04970450a8e6/DockDoor/Views/Hover%20Window/Shared%20Components/SharedPreviewWindowCoordinator.swift#L94-L99); [WindowGestureHUD.swift L149](https://github.com/ejbills/DockDoor/blob/3044142c907b9cdd49917628847a04970450a8e6/DockDoor/Utilities/Window%20Gestures/WindowGestureHUD.swift#L149)

### Inferences
**Two ways for the dock app to vanish in Mission Control** (inferred)
- **(a) Zero code:** drop `.stationary` and use `.transient` with `.canJoinAllSpaces` and `.fullScreenAuxiliary`. The system hides the window, but only at the end of the roughly 300 ms entry animation, and shows it again at about 20–40 ms into the exit. Exactly what the window looks like during the zoom animation was not captured.
- **(b) Full control:** keep `.stationary` so the system never touches the window, detect the modes yourself (Q1, Q2, Q5), and fade or `orderOut` within one frame.
- `.stationary` is also what the system Dock-like behaviour needs if the dock should *stay* visible over Mission Control like Apple's Dock.

**An own-window sentinel is a no-permission, public-API signal** (inferred)
- Use a tiny `.transient` + `.canJoinAllSpaces` window at a non-normal level, observed with `NSWindow.didChangeOcclusionStateNotification`.
  - Its **exit** edge comes about 20–40 ms after exit starts, much earlier than the window-list shield removal at about 320 ms.
  - Its **entry** edge is late (about 310–340 ms), so pair it with the window-list check for entry.
- Caveats:
  - It does not fire for Show Desktop.
  - Occlusion also changes when the screen locks, the display sleeps or another window covers it, so confirm with a window-list read.
  - Whether a fully transparent (alpha 0) or 1×1 window still gets occlusion updates was **not tested**.

**Ordering of stationary windows** (inferred)
- Stationary windows drew above the Mission Control shield (level 19) even at level 0. That suggests Mission Control lifts stationary windows into its presentation rather than ordering them purely by level.

### Gaps
**Space-switch animation was not tested**, because it needs multiple Spaces and synthetic key events. Unanswered:
- whether `.canJoinAllSpaces` windows (with or without `.stationary`) stay fixed or slide during the Space-switch animation;
- whether `.transient` windows flicker.

AltTab notes that "Space switches emit storms of transient animation/snapshot windows" ([WindowServerEvents.swift](https://github.com/lwouis/alt-tab-macos/blob/c500294bdb01186011a5c64a412b04cef9931bef/src/events/WindowServerEvents.swift)), but says nothing about third-party window motion.

**Not covered by the matrix:**
- Behaviour on macOS 14, 15 and 26. Apple's documented semantics are unchanged since 10.6, but empirical confirmation is needed.
- Behaviour with Stage Manager on.
- `.fullScreenAuxiliary` windows while a full-screen Space is active during Mission Control.
- Level 102 (overlay), 1500 and other levels above 1000. Untested, but a transient level-1000 window was already hidden, so level is unlikely to matter (inferred).
- What the Show Desktop column means visually: all 16 windows stayed in the on-screen window list, but in run 1 they were on the external display and the screenshot only captured the primary display.

## Q4. How yabai, AeroSpace, AltTab, DockDoor, Hammerspoon, Raycast and BetterTouchTool detect Mission Control and Space changes

### Takeaway
- **yabai:** AX `AXExpose*` on Monterey through Tahoe; SkyLight event 1204 plus a Dock L18 window poll before Monterey.
- **AltTab:**
  - `AXExpose*`;
  - SkyLight notify procs (811, 804, 815, 816, 1325, 1326) that trigger a window-list classifier of WindowManager overlays (the only route on 27);
  - SkyLight 1329 and 1401 for Space changes.
- **Hammerspoon:** an `NSWorkspaceActiveSpaceDidChangeNotification` watcher, plus probing the Dock's AX `"mc"` group.
- **AeroSpace** and **DockDoor:** only `NSWorkspace.activeSpaceDidChangeNotification`, with no Mission Control detection.
- **Raycast** and **BetterTouchTool:** closed source; nothing found.

### Cited Findings
**yabai**
- Registers `SLSRegisterConnectionNotifyProc` for 1327 (space created) and 1328 (space destroyed) on Ventura through Tahoe, 808 (window focused), 1202 (cmd-tab), and 804 on Sequoia and Tahoe. 1204 (Mission Control enter) is used only before Monterey. — [yabai.c L311–334](https://github.com/koekeishiya/yabai/blob/dd845723416f5fe92af49fad5ebab00369e07edd/src/yabai.c#L311-L334); [mission_control.c L7–26](https://github.com/koekeishiya/yabai/blob/dd845723416f5fe92af49fad5ebab00369e07edd/src/mission_control.c#L7-L26)
- Observes these notifications:
  - `NSWorkspaceActiveSpaceDidChangeNotification`
  - `"NSWorkspaceActiveDisplayDidChangeNotification"` (a string literal)
  - distributed `"AppleInterfaceMenuBarHidingChangedNotification"` and `"com.apple.dock.prefchanged"`
  - local `"NSApplicationDockDidRestartNotification"`
  - Source: [workspace.m L157–195](https://github.com/koekeishiya/yabai/blob/dd845723416f5fe92af49fad5ebab00369e07edd/src/workspace.m#L157-L195)
- Classifies Spaces with `SLSSpaceGetType`: 0 = user, 4 = full-screen, 2 = system. — [space.c L88–100](https://github.com/koekeishiya/yabai/blob/dd845723416f5fe92af49fad5ebab00369e07edd/src/space.c#L88-L100)
- Blocks space operations while Mission Control is active (`SPACE_OP_ERROR_IN_MISSION_CONTROL`). After a `show` or `show-all-windows` exit it calls `window_manager_correct_for_mission_control_changes`, because windows dragged between Spaces in Mission Control must be re-synced. — [event_loop.c L1528–1543](https://github.com/koekeishiya/yabai/blob/dd845723416f5fe92af49fad5ebab00369e07edd/src/event_loop.c#L1528-L1543)

**AltTab**
- `WindowServerEvents` registers SkyLight notify procs on the shared AppKit connection. — [WsEventRouting.swift L9–21](https://github.com/lwouis/alt-tab-macos/blob/c500294bdb01186011a5c64a412b04cef9931bef/src/windowserver/WsEventRouting.swift#L9-L21)

| Event | Meaning |
|---|---|
| 811 | created |
| 804 | destroyed |
| 806 | moved |
| 807 | resized |
| 815 | ordered in |
| 816 | ordered out |
| 808 | focused |
| 1325 | window added to Space |
| 1326 | window removed from Space |
| 1329 | current Space changed |
| 1401 | active Space changed |

- Measured on macOS 26.5: connection-wide notifications arrive "only once the connection has opted at least one window in" through `SLSRequestNotificationsForWindows`. That call *replaces* the opted-in list rather than adding to it. — [WindowServerEvents.swift L9–20](https://github.com/lwouis/alt-tab-macos/blob/c500294bdb01186011a5c64a412b04cef9931bef/src/events/WindowServerEvents.swift)
- Every 815 and 816 event for a window it doesn't own calls `MissionControl.surfacesChanged()`, which schedules a coalesced window-list "look" (150 ms settle). Its `state()` prefers the observed overlay over the AX announcement. — [WindowServerEvents.swift L150–180](https://github.com/lwouis/alt-tab-macos/blob/c500294bdb01186011a5c64a412b04cef9931bef/src/events/WindowServerEvents.swift); [MissionControl.swift](https://github.com/lwouis/alt-tab-macos/blob/c500294bdb01186011a5c64a412b04cef9931bef/src/macos/api-wrappers/MissionControl.swift)
- Space changes: AltTab debounces "the 1329/1401 Space-change burst into one settled handler (replaces SpacesEvents)", and mutes window create/destroy briefly around a transition. — [WindowServerEvents.swift L30–37](https://github.com/lwouis/alt-tab-macos/blob/c500294bdb01186011a5c64a412b04cef9931bef/src/events/WindowServerEvents.swift)

**Hammerspoon**
- `hs.spaces.watcher` uses `NSWorkspaceActiveSpaceDidChangeNotification`. — [libspaces_watcher.m L117–123](https://github.com/Hammerspoon/hammerspoon/blob/23e387e2805a9890066366e0ac96c71b27f0cfd5/extensions/spaces/libspaces_watcher.m#L117-L123)
- Reads Spaces through `SLSCopyManagedDisplaySpaces`. — [libspaces.m L56](https://github.com/Hammerspoon/hammerspoon/blob/23e387e2805a9890066366e0ac96c71b27f0cfd5/extensions/spaces/libspaces.m#L56)
- Detects Mission Control as "visible" only by finding the Dock AX child with `AXIdentifier == "mc"`. — [spaces.lua L83–96](https://github.com/Hammerspoon/hammerspoon/blob/23e387e2805a9890066366e0ac96c71b27f0cfd5/extensions/spaces/spaces.lua#L83-L96)

**AeroSpace**
- Subscribes to `NSWorkspace.activeSpaceDidChangeNotification`. — [GlobalObserver.swift L53](https://github.com/nikitabobko/AeroSpace/blob/587fc26a7f212a819eabecf0ae219b11468e2195/Sources/AppBundle/GlobalObserver.swift#L53)
- Has no Mission Control detection. Its guide only notes Mission Control display quirks and suggests `defaults write com.apple.dock expose-group-apps -bool true`. — [guide.adoc L478–486](https://github.com/nikitabobko/AeroSpace/blob/587fc26a7f212a819eabecf0ae219b11468e2195/docs/guide.adoc#L478-L486)

**DockDoor**
- Uses `NSWorkspace.activeSpaceDidChangeNotification` only. — [WindowManipulationObservers.swift L107](https://github.com/ejbills/DockDoor/blob/3044142c907b9cdd49917628847a04970450a8e6/DockDoor/Utilities/Window%20Management/WindowManipulationObservers.swift#L107)

**docky**
- Uses `NSWorkspace.activeSpaceDidChangeNotification` together with `CGSGetActiveSpace` and `CGSCopyManagedDisplaySpaces` for space-based profile triggers. — [CGSPrivate.swift L17–30](https://github.com/josejuanqm/docky/blob/cb7a6a64483b5cef82b308b6a0958d0df839a779/Docky/Private/CGSPrivate.swift#L17-L30); [MainWindow.swift L527](https://github.com/josejuanqm/docky/blob/cb7a6a64483b5cef82b308b6a0958d0df839a779/Docky/Views/MainWindow/MainWindow.swift#L527)
- No Mission Control detection was found in its Swift sources.

**SkyLight events seen in the local experiment** (local experiment, `mcexp.log`)
- During Mission Control and App Exposé entry, delivered events were 811 (at about 6 ms), 1325 and 1326 (about 15–24 ms), 815 and 816. Event 1204 never arrived.
- SkyLight 1327 and 1328 events also appeared, but they coincided with `screencapture` runs, not with Mission Control. Do not treat them as Mission Control signals.

### Inferences
- (inferred) **macOS 27 consensus.** The most actively maintained project (AltTab, October 2026) has concluded that the window-list overlay classifier is the only working Mission Control signal on macOS 27. yabai's last commit (June 2026) only gates macOS versions up to Tahoe, so its Mission Control signals probably do not fire on 27.
- (inferred) **Space changes.** The fastest permission-free option is SkyLight 1329 and 1401 (private, but it needs no TCC permission). The public option is `NSWorkspace.activeSpaceDidChangeNotification`.

### Gaps
- **Raycast** and **BetterTouchTool** are closed source. No public documentation of how they detect Mission Control was found.
- `yabai` issue search failed (the GitHub search API refused it), so yabai bug reports for macOS 27 were not reviewed.
- Latency of `activeSpaceDidChangeNotification` relative to the Space-switch animation (before, during or after) was not measured.

## Q5. Detecting full-screen Spaces

### Takeaway
There is no public API that says "the current Space is a full-screen Space". Options:
- **Private (most reliable):** `SLSCopyManagedDisplaySpaces` / `CGSCopyManagedDisplaySpaces` gives each display's `"Current Space"` and per-Space `"type"`. Type 4 means full-screen, 0 means user desktop. yabai uses `SLSSpaceGetType(cid, sid) == 4`. A read costs about 0.18 ms.
- **Public heuristics:**
  - `NSApp.currentSystemPresentationOptions`, which reflects the active app's presentation options;
  - a layer-0 window from another process covering the whole screen frame (docky's approach).

### Cited Findings
- yabai: `space_is_fullscreen(sid)` is `SLSSpaceGetType(g_connection, sid) == 4`, user Spaces are `== 0` and system Spaces are `== 2`. — [space.c L88–100](https://github.com/koekeishiya/yabai/blob/dd845723416f5fe92af49fad5ebab00369e07edd/src/space.c#L88-L100)
- Local experiment, macOS 27.0.1: `SLSCopyManagedDisplaySpaces(SLSMainConnectionID())` still works. — Local experiment, `spaces.swift`
  - Each display dictionary has the keys `"Current Space"`, `"Display Identifier"` and `"Spaces"`.
  - Each Space has `"ManagedSpaceID"` and `"type"`. Here: display 1 Spaces `[4 (type 0), 16 (type 0)]` with current 4; display 2 Space `[140]`.
  - `SLSGetActiveSpace` returned 140.
  - Average cost was **0.175 ms** per call.
- docky documents `CGSCopyManagedDisplaySpaces` as returning "the ordered list of spaces per managed display … `{id64, uuid, type, …}`". — [CGSPrivate.swift L24–30](https://github.com/josejuanqm/docky/blob/cb7a6a64483b5cef82b308b6a0958d0df839a779/Docky/Private/CGSPrivate.swift#L24-L30)
- docky's public-API full-screen check: `CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements])`, keeping only layer-0 windows not owned by itself, then comparing bounds (converted from top-left CG coordinates to bottom-left NSScreen coordinates) with the target screen's frame. It re-checks about 0.85 s later to cover the full-screen exit animation ("can run up to ~750 ms"). — [MainWindow.swift L1176–1215](https://github.com/josejuanqm/docky/blob/cb7a6a64483b5cef82b308b6a0958d0df839a779/Docky/Views/MainWindow/MainWindow.swift#L1176-L1215)
- `NSApplication.currentSystemPresentationOptions` "contains the presentation options that have been put into effect by the currently active app". It is KVO-observable, but KVO "notifications aren't sent when … [the new active app] has the same set of presentation options as the previously active app". — [Apple docs](https://developer.apple.com/documentation/appkit/nsapplication/currentsystempresentationoptions)
  - Local experiment: raw value 0 with no full-screen app frontmost.
- Apple DTS: `.fullScreenAuxiliary` plus `.canJoinAllApplications` and level `.screenSaver` are needed to appear over other apps' full-screen windows. `.floating` and `.statusBar` "sit below full-screen content". — [Apple Developer Forums 826308](https://origin-devforums.apple.com/forums/thread/826308)

### Inferences
- (inferred) Combine the signals: on `activeSpaceDidChangeNotification` (or SkyLight 1329/1401), read `SLSCopyManagedDisplaySpaces` and check the current Space's `type == 4` for each display. Fall back to the docky-style window-bounds heuristic if the private symbol is missing. `currentSystemPresentationOptions` only describes the *active* app, so it misses a full-screen Space on a display that isn't focused.
- (inferred) Full-screen state is per display when "Displays have separate Spaces" is on. Evaluate it per display, using the `"Display Identifier"` UUID matched to an `NSScreen`.

### Gaps
- Not confirmed: whether `currentSystemPresentationOptions` reliably contains `.fullScreen` for native full-screen apps on macOS 14–27. Not tested with a full-screen app.
- Not tested: the `type` value for split-view full-screen Spaces on macOS 27.

## Q6 (objective). Ranked techniques for a non-sandboxed Swift dock that must react within about one frame

### Takeaway
On macOS 27 the only working approach is **SkyLight window-created / ordered-in / ordered-out events (private, no TCC permission)**, followed by an immediate `CGWindowListCopyWindowInfo` classification of WindowManager L19, L14 and L18 overlays. That detects entry about 6–21 ms after the trigger.

For exit, observe the system ordering your own `.transient` sentinel window back in (about 15–42 ms). The overlay itself is only removed after about 320 ms.

AX `AXExpose*` events are a nice-to-have on macOS 14–26 when the app already has Accessibility. Nothing public and push-based exists.

### Cited Findings
| Rank | Technique | Permission | API status | macOS 14–26 | macOS 27 | Entry / exit latency | Sources |
|---|---|---|---|---|---|---|---|
| 1 | SkyLight notify procs 811, 815, 816 (and 804) on your own connection after `SLSRequestNotificationsForWindows(cid, ownWids, n)`. On each event, read `CGWindowListCopyWindowInfo` and classify: `WindowManager` L19 screen-sized + L14 = Mission Control; L19 alone = App Exposé; L18 = Show Desktop | None (private SPI, non-sandboxed) | Private | Event numbers are used by AltTab on 26.5; the overlay owner on 14/15 is unverified | **Works** (AltTab; local experiment) | Entry: 811 at about 6 ms, overlay readable at about 18–21 ms. Exit: shield gone at about 320 ms | [AltTab WindowServerEvents.swift](https://github.com/lwouis/alt-tab-macos/blob/c500294bdb01186011a5c64a412b04cef9931bef/src/events/WindowServerEvents.swift); [MissionControlOverlay.swift](https://github.com/lwouis/alt-tab-macos/blob/c500294bdb01186011a5c64a412b04cef9931bef/src/macos/api-wrappers/MissionControlOverlay.swift); local experiment |
| 2 | Own `.transient` sentinel window plus `NSWindow.didChangeOcclusionStateNotification` (exit edge) | None | **Public** | Not measured | Works (local) | Entry about 310–338 ms (late); exit about 15–42 ms (early) | Local experiment; [Apple `.transient`](https://developer.apple.com/documentation/appkit/nswindow/collectionbehavior-swift.struct/transient) |
| 3 | Poll `CGWindowListCopyWindowInfo(.optionOnScreenOnly)` on a display link and classify as in rank 1 | None (names not needed) | **Public** | Overlay owner on 14/15 unverified | Works | ≤1 frame plus about 18–37 ms after trigger. About 0.2–0.5 ms per read idle, about 8–10 ms (or 22–41 ms per AltTab) under load | Local experiment; [AltTab MissionControl.swift](https://github.com/lwouis/alt-tab-macos/blob/c500294bdb01186011a5c64a412b04cef9931bef/src/macos/api-wrappers/MissionControl.swift) |
| 4 | `AXObserver` on the Dock for `AXExposeShowAllWindows`, `AXExposeShowFrontWindows`, `AXExposeShowDesktop`, `AXExposeExit`; re-subscribe on Dock restart | **Accessibility** | Undocumented AX strings | **Works**: "arrive as the gesture starts" (AltTab); yabai uses them on Monterey–Tahoe | **Dead**: subscribe succeeds, nothing is posted (AltTab 26A428; local 26A434). 27.2 unclear | Gesture start, on 12–26 | [yabai mission_control.c](https://github.com/koekeishiya/yabai/blob/dd845723416f5fe92af49fad5ebab00369e07edd/src/mission_control.c); [AltTab DockEvents.swift](https://github.com/lwouis/alt-tab-macos/blob/c500294bdb01186011a5c64a412b04cef9931bef/src/events/DockEvents.swift) |
| 5 | Hammerspoon-style probe for the Dock AX child `AXIdentifier == "mc"` | Accessibility | Undocumented | Works (Hammerspoon) | Unverified | Polling only | [spaces.lua L83–96](https://github.com/Hammerspoon/hammerspoon/blob/23e387e2805a9890066366e0ac96c71b27f0cfd5/extensions/spaces/spaces.lua#L83-L96) |
| 6 | SkyLight 1204 (Mission Control enter) plus a Dock L18 unnamed-window poll for exit | None (private) | Private | Not used by yabai after Big Sur | **Dead** (AltTab; local) | — | [yabai.c](https://github.com/koekeishiya/yabai/blob/dd845723416f5fe92af49fad5ebab00369e07edd/src/yabai.c#L311-L327); [event_loop.c](https://github.com/koekeishiya/yabai/blob/dd845723416f5fe92af49fad5ebab00369e07edd/src/event_loop.c#L1485-L1526) |
| — | `NSWorkspace.activeSpaceDidChangeNotification` | None | Public | Space changes only | Did **not** fire for Mission Control, App Exposé or Show Desktop (local) | — | [Apple docs](https://developer.apple.com/documentation/appkit/nsworkspace/activespacedidchangenotification); local experiment |
| — | Distributed or Darwin notifications (`com.apple.expose.*.awake` and others) | — | — | These are Dock *commands* through `CoreDockSendNotification` | Nothing observed (local) | — | [Hammerspoon spaces.lua](https://github.com/Hammerspoon/hammerspoon/blob/23e387e2805a9890066366e0ac96c71b27f0cfd5/extensions/spaces/spaces.lua#L244-L272); [docky CGSPrivate.swift](https://github.com/josejuanqm/docky/blob/cb7a6a64483b5cef82b308b6a0958d0df839a779/Docky/Private/CGSPrivate.swift#L188-L194) |

For Space switches: rank SkyLight 1329 and 1401 first (private, no permission, fire during the transition and need debouncing; [AltTab](https://github.com/lwouis/alt-tab-macos/blob/c500294bdb01186011a5c64a412b04cef9931bef/src/windowserver/WsEventRouting.swift#L9-L21)). `NSWorkspace.activeSpaceDidChangeNotification` comes second (public; used by yabai, Hammerspoon, AeroSpace, DockDoor and docky).

### Inferences
**Code pattern** (inferred, assembled from the cited AltTab and yabai code and the local experiment; Swift, non-sandboxed):

```swift
// --- private SkyLight entry points (dlsym; no TCC permission needed) ---
typealias NotifyProc = @convention(c) (UInt32, UnsafeMutableRawPointer?, Int, UnsafeMutableRawPointer?, Int32) -> Void
let sky = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_NOW)
let SLSMainConnectionID = unsafeBitCast(dlsym(sky, "SLSMainConnectionID"), to: (@convention(c) () -> Int32).self)
let SLSRegisterConnectionNotifyProc = unsafeBitCast(dlsym(sky, "SLSRegisterConnectionNotifyProc"),
    to: (@convention(c) (Int32, NotifyProc, UInt32, UnsafeMutableRawPointer?) -> CGError).self)
let SLSRequestNotificationsForWindows = unsafeBitCast(dlsym(sky, "SLSRequestNotificationsForWindows"),
    to: (@convention(c) (Int32, UnsafeMutablePointer<UInt32>, Int32) -> CGError).self)

enum Gesture { case none, missionControl, appExpose, showDesktop }

func classify() -> Gesture {               // ~0.2–0.5 ms idle
    let wmPIDs = Set(NSWorkspace.shared.runningApplications
        .filter { $0.localizedName == "WindowManager" || $0.bundleIdentifier == "com.apple.WindowManager" } // verify id
        .map(\.processIdentifier))
    let sizes = NSScreen.screens.map(\.frame.size)
    var shield = false, bar = false, desk = false
    for w in (CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []) {
        let pid = (w[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value ?? 0
        let owner = w[kCGWindowOwnerName as String] as? String
        guard wmPIDs.contains(pid) || owner == "WindowManager" else { continue }
        let layer = w[kCGWindowLayer as String] as? Int ?? .min
        let b = (w[kCGWindowBounds as String] as? NSDictionary).flatMap { CGRect(dictionaryRepresentation: $0 as CFDictionary) } ?? .zero
        switch layer {
        case 19: shield = shield || sizes.contains { b.width >= $0.width && b.height >= $0.height } // ignore Stage Manager 66×82 icons
        case 14: bar = true
        case 18: desk = true
        default: break
        }
    }
    return shield ? (bar ? .missionControl : .appExpose) : (desk ? .showDesktop : .none)
}

// Register once, after the dock window exists (connection-wide events need ≥1 opted-in window; the list REPLACES)
var wids: [UInt32] = [UInt32(dockWindow.windowNumber), UInt32(sentinel.windowNumber)]
let cid = SLSMainConnectionID()
_ = SLSRequestNotificationsForWindows(cid, &wids, Int32(wids.count))
let proc: NotifyProc = { event, _, _, _, _ in
    DispatchQueue.main.async { GestureMonitor.shared.surfacesChanged(event) }  // 811/815/816/804 → classify()
}
for e: UInt32 in [811, 804, 815, 816, 1329, 1401] { _ = SLSRegisterConnectionNotifyProc(cid, proc, e, nil) }

// Public-API sentinel for the fast EXIT edge (and fallback ENTRY edge)
let sentinel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 2, height: 2), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
sentinel.level = .floating
sentinel.collectionBehavior = [.canJoinAllSpaces, .transient, .ignoresCycle]
sentinel.ignoresMouseEvents = true
sentinel.orderFrontRegardless()
NotificationCenter.default.addObserver(forName: NSWindow.didChangeOcclusionStateNotification, object: sentinel, queue: .main) { _ in
    GestureMonitor.shared.sentinelVisible(sentinel.occlusionState.contains(.visible)) // re-confirm with classify()
}
// Dock window itself: keep `.stationary` (system never hides/moves it) and fade it yourself on .missionControl/.appExpose.
```

**Tuning notes** (inferred)
- Keep the dock window `[.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]` so the system never hides, moves or thumbnails it. Then the app's own detector fully decides visibility.
- After any 811 or 815 event, re-classify on the next one or two display-link ticks as well. The shield can be created about 17 ms before it is on-screen (AltTab), so the first read may miss it.
- While a gesture is believed active, re-check every frame or every 100 ms (AltTab uses 0.1 s `maxAge`; yabai polls at 100 ms). This covers missed exit events.
- If the app has Accessibility and runs on macOS ≤ 26, also subscribe to `AXExpose*` for the earliest entry and exit. Treat them as hints and reconcile with `classify()`.
- Keep a version gate and a self-test: if AX subscriptions succeed but no event arrives while `classify()` sees an overlay, ignore AX for the rest of the session.

### Gaps
- Not confirmed on macOS 14, 15 or 26: whether the WindowManager L19, L14 and L18 overlays exist there. If they don't, rank 1 and rank 3 need an alternative classifier on those versions; AX (rank 4) does cover them.
- Whether `SLSRequestNotificationsForWindows` with only the app's own windows is enough to receive other processes' 811, 815 and 816 events on macOS 14 and 15. It was enough on macOS 27.0.1 in the local experiment, and AltTab reports it is required on 26.5.
- No data on how App Store review or notarization treat SkyLight `dlsym` use. The app is non-sandboxed and distributed outside the App Store, so this is likely irrelevant (inferred).
