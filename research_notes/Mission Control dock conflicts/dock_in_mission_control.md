# Apple's Dock during Mission Control and related modes (macOS 15 / 26 / 27) and how third-party docks avoid "two docks"

Scope note: researched 2026-10-31/11-01. "Local observation" means `strings`/`nm` analysis or a read-only `CGWindowListCopyWindowInfo` dump on the research machine, which runs **macOS 27.0.1 (BuildVersion 26A434)**. Nothing on that machine was changed: no Dock prefs were written and Mission Control was not triggered. That machine's current `com.apple.dock` already holds OldMacDonal's parking values: `autohide = 1; "autohide-delay" = 100000; "no-bouncing" = 1; tilesize = 58` (no `orientation` key, so the Dock is at the bottom). Binary-string findings show that code paths and names exist. They do not prove runtime behavior, so they are marked inferred where that matters.

## Q1. Does Apple's Dock appear in Mission Control, App Exposé, Show Desktop, Launchpad/Apps and Space switches with autohide on? Do any com.apple.dock keys change this?

### Takeaway
Yes. With "Automatically hide and show the Dock" on, and even with a huge `autohide-delay`, Apple's Dock is revealed in Mission Control on macOS 15 (confirmed 15.6.1) and macOS 27, and in App Exposé (confirmed by 2026 user reports, and by DockDoor Pro's docs for macOS 27). No documented or hidden `com.apple.dock` key turns this off. The Dock's own code has an explicit "In expose mode; did NOT hide" path. On macOS 27, Mission Control and App Exposé are run by WindowManager.app, which has a dedicated `MissionControlDockHoist` / `DockRevealComponent` that brings the Dock on screen.

### Cited Findings
- **macOS Sequoia 15.6.1:** with Docky's "Hide System Dock" enabled (autohide on, long delay), "In Mission Control View: The system dock is present when accessing Mission Control View… the system dock overlaps the Docky dock." The same issue reports that in a full-screen app, moving the pointer to the Dock edge "always reveals the system dock". — [Docky issue #18 (2026-06-27)](https://github.com/josejuanqm/docky/issues/18)
- The Docky maintainer on the same issue: "Unfortunately some scenarios are impossible to overcome, such as mission control, and expose", and later: "I was able to repro, seems dock is not respecting the delay in these scenarios. we might need a different approach to 'hidding' the dock overall… making it super small and moving to a different edge might be the right solution after all." The maintainer first thought the problem was Sequoia-only ("cannot reproduce on Tahoe"). A commenter then reported it "on macOS Tahoe too" and said moving the Dock to a side edge (`orientation left/right`) fixed it. That thread mixes the full-screen-edge reveal with the Mission Control reveal, so the Tahoe report is most clearly about the full-screen edge. — [Docky issue #18](https://github.com/josejuanqm/docky/issues/18)
- **App Exposé:** "when I activate App Exposé using the trackpad gesture (swipe down with three fingers), the native macOS Dock appears again at the bottom of the screen" despite Hide System Dock. Maintainer: "Unfortunately unless SIP-unlocked this is not possible." The OS version is not stated (filed 2026-09-06). — [Docky issue #78](https://github.com/josejuanqm/docky/issues/78)
- **macOS 27:** "When i normally enter into mission control, i always just see the macos dock… the macos dock takes priority over docky dock". Filed 2026-10-05. This matches OldMacDonal's symptom. — [Docky issue #90](https://github.com/josejuanqm/docky/issues/90)
- DockDoor Pro's docs: "macOS may still show the native Dock in OS-controlled areas such as Mission Control". On versions before macOS 27, "macOS may still show its own Dock in Mission Control and App Exposé" with no workaround. A "Hide Native Dock in Mission Control" option exists only "on macOS 27 and later". — [DockDoor Pro llms.txt](https://pro.dockdoor.net/llms.txt); [DockDoor Pro features](https://pro.dockdoor.net/features/)
- DockDoor Pro's own-dock option is described as "Bring the hidden dock on screen while Mission Control is open, like the native dock." It is extended to "App Exposé on macOS 27 and later". This implies the native Dock reveals in Mission Control on all versions and in App Exposé at least on 27. — [DockDoor Pro features](https://pro.dockdoor.net/features/); the "like the native dock" wording comes from strings in the DockDoor Pro 1.7.3 binary ([DMG](https://downloads.dockdoor.net/v/1.7.3/DockDoorPro.dmg), local observation)
- **Apple's Mac User Guide for macOS 27 ("Golden Gate"), Desktop & Dock:** the only Dock-hiding setting is "Automatically hide and show the Dock". There is no setting to show or hide the Dock in Mission Control. The Mission Control section lists only: rearrange Spaces, switch to a Space with the app's windows, Group windows by application, Displays have separate Spaces, Drag windows to top of screen to enter Mission Control, Shortcuts, Hot Corners. — [Apple: Change Desktop & Dock settings (macOS 27)](https://support.apple.com/guide/mac-help/change-desktop-dock-settings-mchlp1119/27.0/mac/27.0)
- Per the same guide, "Displays have separate Spaces" controls whether the Dock can appear on every display (on) or only the main display (off). — [Apple: Desktop & Dock settings (macOS 27)](https://support.apple.com/guide/mac-help/change-desktop-dock-settings-mchlp1119/27.0/mac/27.0)
- **Triggers (macOS 27 guide):**

  | Mode | Triggers |
  |---|---|
  | Mission Control | Mission Control key or Control-Up Arrow; 3-finger swipe up; Magic Mouse 2-finger double-tap; dragging a window to the top of the screen |
  | App Exposé | Control-Down Arrow; 3/4-finger swipe down if enabled |
  | Show Desktop | Command-Mission Control or trackpad spread |

  — [Apple: Use Mission Control on Mac](https://support.apple.com/guide/mac-help/use-mission-control-mh35798/mac)
- **Local observation, Dock binary on macOS 27.0.1** (`/System/Library/CoreServices/Dock.app/Contents/MacOS/Dock`). The visibility-decision log strings are: "In expose mode; did NOT hide", "Override to show: %{public}@", "No Overrides for showing the dock.", "In Suppressed UI Mode: %d", "Space Forces Hidden: %d %{public}@", "Autohide Pref Value: %d", "Forcing full-screen hidden mode". Other symbols include `forceDockHiddenWithReason:` / `removeForceDockHiddenWithReason:`, `ForceHideDockAssertion` (owned by `WallpaperAgentDesktopPictureManager`, i.e. internal, for login transitions), and "Didn't hide Dock windows for login transition because autohide is enabled".
- **Local observation, every hyphenated defaults-style key in the macOS 27 Dock binary.** Relevant ones: `autohide-delay`, `autohide-time-modifier`, `autohide-immutable`, `no-bouncing`, `show-recents`, `static-only`, `static-apps`, `static-others`, `expose-group-apps`, `expose-sticky-time`, `mcx-expose-disabled`, `mission-control-transition`, `mission-control-preview-windows`, `mission-control-fsspace`, `live-wallpaper-in-mission-control`, `live-wallpaper-in-app-expose`, `live-wallpaper-in-show-desktop`, `hidden-is-suppressed`, `dock-visibility`, `spring-to-expose`, `workspaces-edge-delay`, `wvous-*-corner`, `appswitcher-all-displays`.
  - No key resembling "show/hide Dock in Mission Control" exists. `orientation` and `tilesize` are read via other code paths and are not in this hyphen list.
  - `dock-visibility` appears among log-reason strings ("press outside Dock", "spacechange", "display/space/fullscreen lifecycle"), so it is most likely a log category, not a pref.
  - `hidden-is-suppressed` sits among debug/feature prefs (`spring-to-expose`, `hilite-windows-in-expose`, `fps-missioncontrol`).
- **Local observation, Dock binary on macOS 27** contains "Failed to show all windows via Window Manager: %@", "Failed to show app expose via Window Manager: %@", "Failed to show desktop via Window Manager: %@", "Failed to end expose via Window Manager: %@" and `wmExposeCoordinator`. On 27, the Dock sends Mission Control, App Exposé and Show Desktop to the WindowManager process.
- **Local observation, WindowManager binary on macOS 27** (`/System/Library/CoreServices/WindowManager.app/Contents/MacOS/WindowManager`, module `WindowManagerAgent`). Classes and properties: `MissionControlDockHoist`, `DockRevealComponent`, `dockRevealProgress`, `minimumDockRevealAmount`, `lastSentMinimumDockRevealAmount`, `dockMinimumReveal`, `hoistsDock`, `dockElevationCallbackID`, `DockController`, `ExposeShieldWindow`, `toggleDockShowDesktop`, "Skip toggleDockShowDesktop, a modal reveal assertion is being held". Animation keys: `dock-layering-fullscreen-mc-entry`, `dock-layering-fullscreen-mc-discrete-return`, `dock-layering-spaces-bar-zoom`, `dock-layering-spaces-bar-interactive-zoom`.
- **macOS 26 Tahoe removed Launchpad;** the "Apps" app replaces it and takes its Dock slot. — [Macworld: macOS Tahoe Apps replaces Launchpad](https://www.macworld.com/article/2830963/macos-tahoe-apps-replaces-launchpad.html)
- One macOS 26.4.1 user says Docky's automatic system-Dock hiding "stopped working". The maker said Dock restoration will move to a separate helper. — [Product Hunt: Docky](https://www.producthunt.com/p/docky-the-dock-rebuit-for-focus)

### Inferences
- On 27, Mission Control and App Exposé reveal the Dock through a show-override in the Dock's visibility state machine ("Override to show"), driven by WindowManager's `minimumDockRevealAmount` / `MissionControlDockHoist`. That override skips the autohide pref and `autohide-delay` entirely. This is why `autohide-delay=100000` has no effect there.
- The only non-override branches that can keep the Dock hidden are "In Suppressed UI Mode" (a process presentation/UI mode such as `NSApplicationPresentationHideDock` / `SetSystemUIMode`) and "Space Forces Hidden" (full-screen spaces). That is exactly the lever DockDoor Pro uses on macOS 27 (see Q2/Q3).
- `mcx-expose-disabled` is an MCX/managed-pref switch. Judging by the name and the "Expose.disabled =" diagnostic string, it disables Mission Control/Exposé entirely. That defeats the purpose and was not tested.
- `expose-group-apps`, `show-recents`, `static-only` and `tilesize` change what the Dock shows or how large it is in Mission Control, not whether it shows. A smaller `tilesize` and `static-only=1` (only running apps) reduce how much of Apple's Dock is visible in Mission Control.
- Because the macOS 27 Dock routes Show Desktop through WindowManager and WindowManager has `toggleDockShowDesktop`, the Dock's behavior in Show Desktop is probably also decided by WindowManager. Whether it reveals there is not verified.

### Gaps
- No primary source found for whether the autohidden Dock reveals during **Show Desktop (F11 / spread)**, during **Space switches** (Ctrl-Left/Right or a swipe), in **Launchpad (macOS 15)**, or in the **macOS 26 Apps** view. Recommend a 2-minute manual test on 15, 26 and 27 for each trigger.
- No Apple statement documents the Mission Control reveal behavior. All evidence is user reports, third-party docs and binary strings.
- On macOS 15/26, the Dock also hosts Exposé (`WVExpose`, `ExposeEventController` classes still exist in the 27 binary). Whether Mission Control was already in WindowManager on 26 was not verified. Only the 27 binaries were available.
- The semantics of `hidden-is-suppressed` and `dock-visibility` were not tested. Writing unknown keys and restarting the Dock on the research machine was out of scope.

## Q2. How do third-party docks and dock-hiding tools handle Mission Control? Do any hide their own dock or hide/occlude Apple's?

### Takeaway
Nearly every replacement parks Apple's Dock the same way OldMacDonal does (autohide plus a huge delay and a Dock restart), and all of them admit Apple's Dock still appears in Mission Control and Exposé. DockDoor Pro (closed source, v1.7.3) is the only product found that suppresses Apple's Dock in Mission Control and App Exposé, and only on macOS 27+. It does this with a bundled helper, `DockShield.app`, that uses SkyLight front-process SPI plus `SetSystemUIMode` (inferred from binary imports). Docky's maintainer instead hides Docky in Exposé and says SIP-on suppression of Apple's Dock is impossible. yabai shows how to detect Mission Control entry and exit.

### Cited Findings
- **Docky (josejuanqm/docky, HEAD cb7a6a6, 2026-10-27):**
  - `SystemDockVisibilityService` "Hides the macOS Dock by writing to com.apple.dock preferences": `autohide=true`, `autohide-delay=1000.0`, `autohide-time-modifier=0.0`, `no-bouncing=true`, `launchanim=false`. It also manages `orientation`, snapshots the prior values, and restarts the Dock via `NSRunningApplication.forceTerminate()`. — [SystemDockVisibilityService.swift](https://github.com/josejuanqm/docky/blob/main/Docky/Services/SystemDockVisibilityService.swift)
  - A separate `DockyDockWatchdog` helper restores the snapshot and runs `/usr/bin/killall Dock` if Docky dies. — [DockyDockWatchdog/main.swift](https://github.com/josejuanqm/docky/blob/main/DockyDockWatchdog/main.swift)
- Docky's main dock window hard-overrides its level to `.mainMenu` (24, above `kCGDockWindowLevel` 20): `override var level: NSWindow.Level { get { .mainMenu } set {} }`. Collection behavior for all-spaces mode is `[.canJoinAllSpaces, .stationary, .ignoresCycle]` plus `.fullScreenAuxiliary`. — [MainWindow.swift](https://github.com/josejuanqm/docky/blob/main/Docky/Views/MainWindow/MainWindow.swift); [DockyPreferences.swift](https://github.com/josejuanqm/docky/blob/main/Docky/Services/DockyPreferences.swift)
- Docky's maintainer: "Docky should hide when expose is enabled." He declined a "make the system Dock tiny" option because it "removes the ability to 'show windows from specific apps' on expose too… as well as people can use docky as a separate dock aside from the system one." — [Docky issue #78](https://github.com/josejuanqm/docky/issues/78)
- Docky has a DEBUG-only, not-wired-in `SkyLightSpaceReservationProbe`. Phase 2 calls `CGSSetWindowAlpha(CGSMainConnectionID(), dockWindowID, 0.0)` on Dock-owned windows "to keep its reservation while erasing its pixels". No result is recorded and it is not shipped. — [SkyLightSpaceReservationProbe.swift](https://github.com/josejuanqm/docky/blob/main/Docky/Private/SkyLightSpaceReservationProbe.swift)
- Docky triggers App Exposé via the private `CoreDockSendNotification("com.apple.expose.front.awake")` loaded by `dlsym` from HIServices. Posting the same name via `DistributedNotificationCenter` "is a no-op". — [CGSPrivate.swift](https://github.com/josejuanqm/docky/blob/main/Docky/Private/CGSPrivate.swift); [WorkspaceService.swift](https://github.com/josejuanqm/docky/blob/main/Docky/Services/WorkspaceService.swift)
- **DockDoor Pro (pro.dockdoor.net, Homebrew cask `dockdoor-pro` 1.7.3)** has these settings: "Hide Native Dock" ("changes Dock preferences and restarts the Dock process"), "Native Dock position — Pin the system Dock to another edge while it is hidden", "Restore native Dock on quit", "Hide Native Dock in Mission Control — Keep the macOS Dock out of Mission Control and App Exposé, on macOS 27 and later", and "Show in Mission Control — Bring the auto-hidden Dock on screen while Mission Control is open, and App Exposé on macOS 27 and later". Minimum OS is macOS 14.6. — [DockDoor Pro features](https://pro.dockdoor.net/features/); [llms.txt](https://pro.dockdoor.net/llms.txt); [Homebrew cask JSON](https://formulae.brew.sh/api/cask/dockdoor-pro.json)
- **DockDoor Pro 1.7.3 internals** (local observation of strings and imports in the shipped [DMG](https://downloads.dockdoor.net/v/1.7.3/DockDoorPro.dmg)):
  - The main app has classes `NativeDockMissionControlHider`, `NativeDockExposeProbe` (with strings `com.apple.WindowManager`, `appexpose.display`), `NativeDockSwipeTap` and `ExposeStateSignal`, plus the pref key `general.hideNativeDockInMissionControl` and the log "native Dock may be revealed".
  - Its imports include `SLSRegisterConnectionNotifyProc`, `SLPSSetFrontProcessWithOptions` and `SLPSPostEventRecordTo`, and it references `/Library/Preferences/com.apple.dock.plist` and `/usr/bin/killall`.
  - It bundles `Contents/Helpers/DockShield.app`: bundle ID `com.ejbills.DockDoorPro.DockShield`, display name "DockDoor Pro Shield", `LSUIElement=true`, built with the macOS 27 SDK and Xcode 27A266a. Its description string is "Hides the native Dock during Mission Control".
  - DockShield imports `SetSystemUIMode`, `GetProcessForPID`, `GetProcessPID` and `CGWindowListCopyWindowInfo` (reading layer, alpha, bounds, owner PID and window number). It `dlopen`s SkyLight for `SLPSGetFrontProcess`, `SLPSSetFrontProcessWithOptions`, `SLPSAddToPermittedFrontPSNList` and `SLPSRemoveFromPermittedFrontPSNList`.
  - DockShield's other symbols: `FrontHold`, `previousFront`, `topWindowAtBegin`, `engage`, `keepAlive`, `onParentSilent`, `getppid`, `read`. Log tags: "[DockShield] helper started/exited/write failed/swipe tap unavailable".
- **DockDoor (free, open source, ejbills/DockDoor HEAD 2026-10-26)** is a previews and window-switcher add-on, not a dock replacement. It has no Mission Control suppression code. Its only Mission Control-related advice is that Dock Locking works best with "Displays have separate Spaces" enabled. — [DockDoor repo](https://github.com/ejbills/DockDoor)
- **ActiveDock 2:** the changelog lists "buttons and menu item to disable and enable (restore) Apple Dock" and an option to hide ActiveDock when an app goes full screen. — [Softpedia ActiveDock changelog](https://mac.softpedia.com/progChangelog/ActiveDock-Changelog-142787.html)
- ActiveDock's docs (updated 2026-08-02) give the recovery command `defaults delete com.apple.dock autohide-delay && killall Dock`, which implies ActiveDock also parks the Dock via `autohide-delay`. The docs say nothing about Mission Control or Exposé. — [ActiveDock documentation](https://noteifyapp.com/2020/06/18/activedock-documentation/)
- **uBar:** no official FAQ was retrievable. Softpedia says uBar can coexist with the Dock without hiding it. — [Softpedia uBar](https://mac.softpedia.com/get/System-Utilities/uBar.shtml)
- **yabai (koekeishiya/yabai, HEAD dd84572, 2026-06-14)** detects Mission Control two ways:
  - an `AXObserver` on the Dock PID for `AXExposeShowAllWindows`, `AXExposeShowFrontWindows`, `AXExposeShowDesktop` and `AXExposeExit`, mapped to modes show-all-windows, show-front-windows and show-desktop — [src/mission_control.c](https://github.com/koekeishiya/yabai/blob/master/src/mission_control.c)
  - `SLSRegisterConnectionNotifyProc(g_connection, handler, 1204, NULL)`, where event 1204 means `MISSION_CONTROL_ENTER` — [src/yabai.c](https://github.com/koekeishiya/yabai/blob/master/src/yabai.c)
- yabai's exit check polls `CGWindowListCopyWindowInfo` every 0.1 s for an unnamed Dock-owned window at layer 18; when it disappears, yabai posts `MISSION_CONTROL_EXIT`. The Dock-restart re-observe path names Monterey through Tahoe only, not 27. — [src/event_loop.c](https://github.com/koekeishiya/yabai/blob/master/src/event_loop.c)
- yabai's README says advanced features need SIP partially disabled "to inject a scripting addition into Dock.app". — [yabai README](https://github.com/koekeishiya/yabai/blob/master/README.md)
- **Local observation, macOS 27.0.1 window list at rest:**

  | Window | Owner | Layer | Size | On screen |
  |---|---|---|---|---|
  | `Dock` | Dock | 20 | full display (1512x982 on the built-in panel) | yes |
  | `ExposeShieldWindow` (one per display) | WindowManager | 19 | full display | no, until Exposé |
  | `Spaces Bar` | WindowManager | 14 | — | yes |
  | `Wallpaper` | WindowManager | -2147483624 | — | yes |

  Levels: `kCGDockWindowLevel`=20, `kCGUtilityWindowLevel`=19, `kCGMainMenuWindowLevel`=24, `kCGStatusWindowLevel`=25, `kCGPopUpMenuWindowLevel`=101.
- **A user analysis in Docky #47:** Dock.app "is started by `com.apple.Dock.agent`, a SIP-protected launch agent. `launchctl bootout`/`unload` returns 'Operation not permitted while System Integrity Protection is engaged', and `killall Dock` just triggers a respawn. So the only available strategies are autohide with an effectively infinite reveal delay, or parking the Dock on an unused edge." This is a user's claim, not Apple's. — [Docky issue #47](https://github.com/josejuanqm/docky/issues/47)
- **LegacyDock, "Dock Gone":** no search results found for either product name.

### Inferences
- **How DockDoor Pro's macOS 27 trick most likely works.** This is inferred from imports and strings and was not run.
  1. The main app detects Mission Control or App Exposé starting. Signals: the SkyLight 1204 notify proc, a trackpad-swipe `CGEventTap` (`NativeDockSwipeTap`), and an AX probe of the `com.apple.WindowManager` process for the `appexpose.display` element (`NativeDockExposeProbe`).
  2. It tells the long-lived `DockShield` child (over a stdin pipe, with parent-death detection) to "engage".
  3. DockShield records the current front process and top window, adds itself to the permitted-front list, makes itself the SkyLight front process with `SLPSSetFrontProcessWithOptions`, and calls `SetSystemUIMode` with a Dock-hidden mode. That hits the Dock's "In Suppressed UI Mode" branch, which wins over the Mission Control show-override.
  4. On exit it restores the previous front process.

  A separate helper is used so the main dock app never becomes active and its own presentation options are not disturbed. The macOS-27-only gating suggests the WindowManager-driven Mission Control on 27 respects the suppressed UI mode where the older Dock-hosted Exposé did not.
- The "Docky hides itself in Exposé" behavior probably comes from WindowServer handling at Exposé time, not from explicit code: no Exposé observer was found in Docky's source. OldMacDonal should not count on it and should hide its panel explicitly.
- yabai's exit heuristic (a layer-18 window owned by Dock) probably does not match macOS 27, where the Exposé shield is WindowManager's `ExposeShieldWindow` at layer 19. On 27, poll for an on-screen `ExposeShieldWindow` owned by WindowManager instead, and verify whether the `AXExpose*` notifications now come from the Dock or from WindowManager. Both binaries contain those strings.
- Because Apple's `Dock` window sits at layer 20 and the shield at 19, an OldMacDonal `NSPanel` at `kCGDockWindowLevel` competes with Apple's Dock in the same layer. Within a layer, the most recently ordered window wins. This explains "both docks visible" and possible z-fighting.

### Gaps
- DockDoor Pro is closed source. The exact `SetSystemUIMode` mode, the timing (engage before or after the zoom animation starts) and how App Exposé's target app is preserved could not be confirmed without running it.
- No official uBar or ActiveDock statement about Mission Control was found. No info was found on "LegacyDock", "Dock Gone" or HiddenBar-style Dock hiders (HiddenBar hides menu-bar items, not the Dock).
- AeroSpace, Hammerspoon and alt-tab-macos were not inspected within the budget.

## Q3. Is there a supported or common way to fully hide Apple's Dock on macOS 14–27 without SIP changes? What are the risks?

### Takeaway
There is no supported way. Apple offers only "Automatically hide and show the Dock", and the Dock process cannot be stopped because launchd respawns it. Common hacks (huge `autohide-delay`, `autohide-time-modifier 0`, a tiny tile size, a different edge or display) hide it in normal use but not in Mission Control or Exposé on 15, 26 or 27. On macOS 27, a SIP-on but private-SPI approach exists (DockDoor Pro's DockShield). Otherwise the practical options are: (a) hide your own dock while Mission Control or Exposé is open, or (b) park Apple's Dock on an edge where its Mission Control reveal does not collide with yours, and shrink it.

### Cited Findings
- Apple's macOS 27 Desktop & Dock settings expose only "Automatically hide and show the Dock". The position choices are Left, Bottom and Right. — [Apple: Desktop & Dock settings (macOS 27)](https://support.apple.com/guide/mac-help/change-desktop-dock-settings-mchlp1119/27.0/mac/27.0)
- The long-delay method (`autohide-delay 1000`, `autohide-time-modifier 0`) is used by Docky, and by implication ActiveDock. It fails in Mission Control, in Exposé and at the full-screen edge. — [Docky SystemDockVisibilityService.swift](https://github.com/josejuanqm/docky/blob/main/Docky/Services/SystemDockVisibilityService.swift); [Docky #18](https://github.com/josejuanqm/docky/issues/18); [Docky #78](https://github.com/josejuanqm/docky/issues/78); [ActiveDock docs](https://noteifyapp.com/2020/06/18/activedock-documentation/)
- **Multi-display leak:** in a vertically stacked display arrangement, a Dock hidden below the upper monitor's bottom edge shows up as a strip on the lower monitor. Workarounds that worked for a user:
  - turn off "Displays have separate Spaces" (needs a log out and back in)
  - `defaults write com.apple.dock orientation left; killall Dock`, since vertical edges have no neighbor
  - autohide with a 1000 s delay and `autohide-time-modifier 0`

  The same user suggests picking the parking edge from the `NSScreen` frames so the Dock never sits on an edge shared with another display. — [Docky issue #47](https://github.com/josejuanqm/docky/issues/47)
- **Tiny-Dock workaround:** shrinking the native Dock makes it barely visible in Exposé ("you can see it if you look for it"). Docky's maintainer rejected it as a default because of the lost Exposé functionality. — [Docky issue #78](https://github.com/josejuanqm/docky/issues/78)
- **The Dock is not killable:** a user reports it is launched by the SIP-protected `com.apple.Dock.agent`, and `killall Dock` respawns it. — [Docky issue #47](https://github.com/josejuanqm/docky/issues/47)
- **SIP-off route:** yabai's scripting addition injects into Dock.app and requires SIP to be partially disabled, which is not viable for a Developer ID consumer app. — [yabai README](https://github.com/koekeishiya/yabai/blob/master/README.md)
- **Presentation options:**
  - `NSApplication.PresentationOptions.hideDock`: "The dock is entirely hidden and disabled." — [Apple Developer: hideDock](https://developer.apple.com/documentation/appkit/nsapplication/presentationoptions-swift.struct/hidedock)
  - `presentationOptions`: "The presentation options that should be in effect for the system when this app is active." An invalid combination raises `NSInvalidArgumentException`. — [Apple Developer: presentationOptions](https://developer.apple.com/documentation/appkit/nsapplication/presentationoptions-swift.property)
- **macOS 27 private-SPI route:** DockDoor Pro's DockShield helper (`SetSystemUIMode` plus SkyLight `SLPS*FrontProcess*`) is advertised as keeping the Dock out of Mission Control and App Exposé, macOS 27 and later only. — [DockDoor Pro features](https://pro.dockdoor.net/features/); binary analysis of the [DockDoor Pro 1.7.3 DMG](https://downloads.dockdoor.net/v/1.7.3/DockDoorPro.dmg) (local observation)
- **Window-alpha route:** Docky contains an experimental, unshipped attempt to set the Dock's windows to alpha 0 with `CGSSetWindowAlpha` from Docky's own connection. Its outcome is undocumented. — [SkyLightSpaceReservationProbe.swift](https://github.com/josejuanqm/docky/blob/main/Docky/Private/SkyLightSpaceReservationProbe.swift)

### Inferences
- **Recommended path for OldMacDonal, in order of risk:**
  1. **Baseline (all versions, public APIs plus Accessibility).**
     - Detect Mission Control, App Exposé and Show Desktop entry and exit:
       - an `AXObserver` on the Dock PID (and on 27 also the WindowManager PID) for `AXExposeShowAllWindows`, `AXExposeShowFrontWindows`, `AXExposeShowDesktop` and `AXExposeExit`, the same as yabai
       - optionally the SkyLight 1204 notify proc for an earlier signal
       - a poll for the WindowManager `ExposeShieldWindow` being on screen (27) or the layer-18 Dock window (15/26), as an exit fallback
     - On entry, fade out or `orderOut` OldMacDonal's panel so only Apple's Dock shows. This is what Docky intends and what DockDoor Pro does when "Show in Mission Control" is off.
     - Low risk; the result is "one dock" during Mission Control, but it is Apple's.
  2. **Reduce Apple's Dock while parked.** Also write a small `tilesize` (for example 16) and, optionally, `static-only=1`, and snapshot and restore them like Docky does. Apple's Mission Control Dock then becomes a small strip.
     - Or park it on a left or right edge chosen from the display arrangement, so its Mission Control reveal does not cover OldMacDonal's bottom dock.
     - Cost: the user's own Dock size and contents change while OldMacDonal runs, and a crash needs the restore watchdog, as Docky does.
  3. **macOS 27+ only, private SPI.** Use a DockShield-style `LSUIElement` helper that, during Mission Control or Exposé, briefly takes SkyLight front-process status and applies `SetSystemUIMode` (or `presentationOptions = [.hideDock]`) so the Dock's suppressed-UI branch hides it.
     - Risks:
       - uses private SkyLight SPI (`SLPSSetFrontProcessWithOptions`, permitted-front list) that can break in point releases
       - changes the front app, which can redirect App Exposé's target or keyboard focus and confuse Spaces' "switch to app" behavior
       - must restore the previous front process on exit, including on crash (DockShield has parent-death detection for this)
       - not App Store-safe, although fine for Developer ID
- Writing `com.apple.dock` and restarting the Dock is what everyone does. The known risks: Dock restarts flash the screen and rebuild Spaces and wallpaper state, and if the app dies without restoring, the user is left with a Dock that never appears. Use a snapshot plus a watchdog, as Docky does.
- `NSApp.presentationOptions = [.hideDock]` in OldMacDonal itself would only apply while OldMacDonal is the active app. A dock app is normally non-activating, so that does not help by itself. This is probably why DockDoor Pro uses a separate helper that becomes front only during Mission Control.

### Gaps
- No confirmation that `SetSystemUIMode` or `.hideDock` suppression is respected in Mission Control on macOS 15 or 26. DockDoor Pro's 27-only gating suggests it is not, but this is unverified.
- No source confirms the minimum `tilesize` the Dock accepts via `defaults`. The UI slider minimum (believed to be 16) was not verified.
- No source on whether `CGSSetWindowAlpha` from a third-party connection on Dock-owned windows succeeds. It is likely denied because only the owner or universal connection can change window alpha, but this is not verified.
- The `SystemUIMode` constant values were not verified: the local macOS 27 SDK headers no longer contain `MacApplication.h` declarations for `kUIMode*`.

## Q4. What does the Dock look like in Mission Control on macOS 26/27 (position, slide-in, timing) so OldMacDonal can match or cover it?

### Takeaway
On macOS 27, Apple's Dock stays in its configured position and edge. It is "hoisted" above the Mission Control shield (the Dock window is at layer 20; WindowManager's `ExposeShieldWindow` is at layer 19) and revealed progressively by WindowManager (`dockRevealProgress` / `minimumDockRevealAmount`). That points to a slide-in from its edge tied to the Mission Control transition and trackpad gesture progress. Exact timing and curves are not documented anywhere found.

### Cited Findings
- **Local observation (macOS 27.0.1):** the Dock's single window is named `Dock`, at layer 20 (`kCGDockWindowLevel`), and covers the whole display (1512x982 on the built-in panel). WindowManager's per-display `ExposeShieldWindow` is at layer 19 and sized to the display. The Spaces Bar is at layer 14 (1512x128 on the built-in panel, 2560x96 on an external display).
- **Local observation:** WindowManager has `DockRevealComponent`, `dockRevealProgress`, `revealProgress`, `minimumDockRevealAmount`, `lastSentMinimumDockRevealAmount`, `dockMinimumReveal`, `MissionControlDockHoist`, `hoistsDock`, `dockCurrentInset`, `dockMaximumInset`, `dockOrientation`, `dockDisplayID`, `dockWindowIdentifiers`, `adjustToAvoidDockHotzones`, and animation keys `dock-layering-fullscreen-mc-entry`, `dock-layering-fullscreen-mc-discrete-return`, `dock-layering-spaces-bar-zoom`, `dock-layering-spaces-bar-interactive-zoom`. The Dock has the pref keys `mission-control-transition` and `expose-sticky-time`.
- DockDoor Pro offers matching behavior for its own dock: "Bring the hidden dock on screen while Mission Control is open, like the native dock." — [DockDoor Pro features](https://pro.dockdoor.net/features/) and binary strings (local observation)
- A user on macOS 15.6.1 reports that the system Dock "overlaps the Docky dock" in Mission Control, so it appears in its normal bottom position. — [Docky issue #18](https://github.com/josejuanqm/docky/issues/18)
- In App Exposé, the native Dock "appears again at the bottom of the screen". — [Docky issue #78](https://github.com/josejuanqm/docky/issues/78)

### Inferences
- **Matching:** with Apple's Dock at the bottom, OldMacDonal's dock at the bottom, and the same size, Apple's Dock slides up into the same band during Mission Control. Either fade OldMacDonal out over about the transition length, or keep OldMacDonal on screen and accept that Apple's Dock (ordered last at layer 20) draws over it.
- **Covering is fragile:** WindowManager re-elevates the Dock during Mission Control (`dockElevationCallbackID`, "hoist"). Raising OldMacDonal's panel above layer 20 (as Docky does with `.mainMenu`, layer 24) could cover Apple's Dock visually. But Apple's Dock would still take clicks in its area unless OldMacDonal's panel accepts mouse events there, and the Mission Control Spaces Bar and window-drag targets could also be covered.
- **Measuring timing:** on a test Mac, record the transition with a screen recording at 60 fps, or sample the Dock's AX element. The Dock's `AXList` child frame (`kAXPositionAttribute` / `kAXSizeAttribute`) can be sampled at about 120 Hz while pressing F3. The Dock's CG window frame is useless for this on 27 because it is always full-screen size.

### Gaps
- No source gives the Mission Control Dock reveal duration, easing, or whether it is interactive with the 3-finger swipe on macOS 26 versus 27. Measure empirically.
- Not verified whether the Dock appears on every display or only the active one in Mission Control when "Displays have separate Spaces" is on.
- No macOS 26 binaries or observations were available, so the 26 versus 27 architecture difference (Dock-hosted versus WindowManager-hosted Mission Control) is unconfirmed.
