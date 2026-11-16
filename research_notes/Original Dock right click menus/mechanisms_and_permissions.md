# Mechanisms and permissions for reproducing Apple Dock tile menus in a third-party dock (macOS 14 to 27)

Method note: entries marked **[Local test]** were run on this machine on 2026-11-16, macOS 27.0.1 (build 26A434), with small Swift/ObjC probes compiled in a scratch folder, plus `nm`, `strings` and `codesign` on `/System/Library/CoreServices/Dock.app`, and greps of the macOS 27 SDK. The probe process inherited the terminal's TCC grants (Accessibility: granted, Screen Recording: granted, Full Disk Access: NOT granted), so "works without permission" could only be tested for Full Disk Access, not for Accessibility or Screen Recording. Open-source code was read from fresh clones: AltTab at commit `2a9cbbb` (2026-11-16) and DockDoor at commit `baf6425` (2026-11-10). Nothing that changes user state (login items, Assign To, Exposé) was executed; only read-only calls and one open-then-cancel of a Dock menu.

## Q1. Getting another app's own Dock menu items (applicationDockMenu), directly or by reading Apple's parked Dock via Accessibility

### Takeaway
There is no public or documented way for a third-party process to ask an app for its `applicationDockMenu(_:)` menu. On macOS 27 AppKit answers the Dock over a private WindowServer (CGS/SkyLight) "dock message" channel, not an Apple Event, and the Dock holds private SkyLight entitlements for it. The practical route is Accessibility: `AXShowMenu` on Apple's own Dock tile returns the complete Dock menu (the app's own items, the window list, Options with checkmarks, Show All Windows, Hide, Hide Others, Quit, Force Quit), readable as an AXMenu tree and closable with `AXCancel`. This was verified on 27.0.1 with the Dock auto-hidden. It costs the Accessibility permission.

### Cited Findings
- AppKit on 27.0.1 contains a private class `NSCGSDockNotifications` with class methods `+addGetAppMenuHandler:`, `+addDoMenuCommandHandler:`, `+addSelectWindowHandler:`, `+addDockAliveHandler:`, `+addDockDiedHandler:`, `+addMinimizeEffectDoneHandler:` and others, and a class `NSCGSDockMessageHandlers` (`-addHandlerForMessage:order:block:`, `-handlersForMessageID:`). `NSApplication` has private `-_createDockMenu:`, `-_sendDockMenuCommand:withTag:modifierFlags:` (and an `originatingDisplay:` variant), `-_registerWithDock`, `-_setDockMenuForPersistentState:`. There is also an XPC-based `NSDockConnection` (ivars `_connection` of type `OS_xpc_object`, `_serviceName`, `-sendMessage:synchronous:replyHandler:`). — [Local test: Objective-C runtime dump of AppKit on 27.0.1]
- The Dock binary on 27.0.1 contains the selectors `doMenuCommand:tag:modifiers:display:` and `doMenuCommand:tag:modifiers:display:forExtra:`, and imports `CGSRegisterConnectionNotifyProc`, `SLSTransactionPostNotificationToConnection`, `CGSGetConnectionIDForPSN` and `AESendMessage`. — [Local test: `nm -u` and `strings` on Dock]
- The Dock's code signature carries private entitlements including `com.apple.private.skylight.universal-owner`, `com.apple.private.tcc.allow` = [kTCCServicePostEvent, kTCCServiceAppleEvents, kTCCServiceScreenCapture, kTCCServiceFileProviderDomain, Desktop/Documents/Downloads/NetworkVolumes/RemovableVolumes], `com.apple.private.coreservices.canaccessanysharedfilelist`, `com.apple.private.backgroundtaskmanagement.manage`, `com.apple.private.launchservices.allowedtoforciblyremoveapplicationfromrunninglist`. — [Local test: `codesign -d --entitlements` on Dock.app]
- The macOS 27 SDK's CoreServices, Carbon and ApplicationServices headers contain no `GDMn`, `kAEGetDockMenu` or Dock-menu Apple Event constant. — [Local test: grep of SDK headers]
- A web search found no documentation of a `GDMn` / "get dock menu" Apple Event; the documented model is that an app supplies its Dock menu itself via a `dockMenu` outlet, `applicationDockMenu:`, or an `AppleDockMenu` nib named in Info.plist. — [O'Reilly, Cocoa in a Nutshell, Dock menus](https://www.oreilly.com/library/view/cocoa-in-a/0596004621/ch03s05.html) (from search excerpt); [Apple Developer Forums: Mac app, SwiftUI: Change Dock menu](https://developer.apple.com/forums/thread/749201)
- The known third-party workaround is UI scripting: System Events can open another app's Dock menu through the Dock process, which depends on Accessibility permission and the Dock's UI layout. — [Keyboard Maestro forum: Accessing the Dock Menu of an Application](https://forum.keyboardmaestro.com/t/accessing-the-dock-menu-of-an-application/8995)
- Dock AX tree on 27.0.1: AXApplication (Dock) > AXList > AXDockItem children (24 here) with subrole `AXApplicationDockItem` for apps. Running-app tiles expose actions `AXPress`, `AXShowMenu`, `AXShowExpose`; non-running tiles expose `AXPress`, `AXShowMenu`. Item attributes: AXTitle, AXURL, AXIsApplicationRunning, AXShownMenuUIElement, AXStatusLabel (badge), AXProgressValue, AXPosition, AXSize, AXFrame, AXSelected. — [Local test: AX dump of com.apple.dock]
- With `com.apple.dock autohide = 1` (default delay, so the Dock was hidden), `AXUIElementPerformAction(finderTile, "AXShowMenu")` returned success immediately and the AXMenu was readable via `AXShownMenuUIElement`. Finder's menu had 25 items: the open Finder window, New Finder Window, New Smart Folder, Find…, Go to Folder…, Connect to Server…, 10 recent folders, Options (submenu), Show All Windows, Hide, Hide Others. `AXCancel` on the menu closed it (AXShownMenuUIElement became nil). The tile's AXPosition was unchanged before and after. — [Local test]
- Safari's tile menu via the same route: the open window's title (checked), **New Window, New Private Window** (Safari's own `applicationDockMenu` items), Options submenu, Show All Windows, Hide, Hide Others, Quit, Force Quit. The Options submenu's children were readable without opening the submenu: Keep in Dock (checked), Open at Login, Show in Finder, Assign To (header), All Desktops, This Desktop, None (checked). Checkmark state is read from `AXMenuItemMarkChar`. — [Local test]
- DockDoor reads Apple's Dock through AX (it subscribes to `kAXSelectedChildrenChangedNotification` on the Dock's AXList and reads `kAXSelectedChildrenAttribute` to know which tile is hovered), but its source has no `AXShowMenu` call, so it does not proxy Dock menus. — [DockDoor DockObserver.swift @baf6425](https://github.com/ejbills/DockDoor/blob/baf6425a981b09acb79189ec568e7c189b70a0ce/DockDoor/Utilities/DockObserver.swift)
- Talon's community voice-control scripts find a Dock item by searching `com.apple.dock` children for `AXSubrole == "AXApplicationDockItem"` with a matching name, and perform `AXShowExpose` on it. — [Talon dock module docs](https://wolfmanstout.github.io/wolfmanstout_talon/apps/dock); [talonhub/community dock.py](https://github.com/talonhub/community/blob/main/apps/dock/dock.py)

### Inferences
- The Dock-to-app menu request is almost certainly a WindowServer connection notification (`CGSRegisterConnectionNotifyProc` on the app side, `SLS...PostNotificationToConnection` on the Dock side), with the selected item sent back as a "do menu command" carrying a tag. Sending that request from a third-party process would need reverse engineering of message IDs and the serialized menu format, and probably the Dock-only `universal-owner` entitlement. Treat direct fetching as not feasible (speculative, not tested).
- A workable AX design for OldMacDoc: on right-click, `AXShowMenu` on the matching Apple Dock tile (match by AXURL, not title), read the tree, `AXCancel` at once, then show OldMacDoc's own NSMenu built from it. On a choice, re-open the Dock menu and `AXPress` the item matched by title and position (the window list and recents can change between the read and the press). Everything in the Dock menu (app items, windows, recents, Options state) comes over in one read.
- Apple's Dock draws its menu on screen when `AXShowMenu` runs, so the user may see a brief flash at the parked Dock's edge before `AXCancel`. Whether that is visible with a huge `autohide-delay` was not tested.
- Force Quit appeared in Safari's AX-opened menu without Option held. The AX-opened menu may be the extended variant, or Safari may have been slow to answer; not confirmed.

### Gaps
- Not tested: behavior with OldMacDoc's actual parking (huge `autohide-delay`); whether the Dock slides in or draws the menu off screen. I did not change the user's Dock preferences.
- Not tested: `AXPress` on a Dock menu item while the Dock is parked (to avoid side effects). The KM forum shows that pressing Dock menu items via UI scripting works in general.
- No open-source project was found that fetches `applicationDockMenu` from another app directly.

## Q2. Window lists per app (titles, minimized state) and bringing a specific window forward

### Takeaway
Without any permission, `CGWindowListCopyWindowInfo` still gives owner PID and name, window number, bounds, layer, alpha, on-screen flag and sharing state, but other apps' window titles (`kCGWindowName`) are withheld unless Screen Recording is granted (true since 10.15 and measured by AltTab on macOS 27). Minimized state, titles without Screen Recording, unminimize and raise need Accessibility. Reliable cross-app focus of one window on macOS 14+ uses private SkyLight calls plus AX, as AltTab does, because macOS 14 made app activation advisory.

### Cited Findings
- AltTab (macOS 27 measurements in comments): "WindowServer applies the change at once: other apps' window titles appear or vanish" when Screen Recording is granted or revoked; AltTab detects the grant by checking whether any other app's layer-0 window has a non-empty `kCGWindowName`. It also notes `CGPreflightScreenCaptureAccess` "is frozen per-process", so a grant made mid-session is not seen by that call. — [AltTab SystemPermissions.swift @2a9cbbb](https://github.com/lwouis/alt-tab-macos/blob/2a9cbbb5462fbd0a76bb3f5f50d71b357823d6ab/src/macos/SystemPermissions.swift)
- AltTab lets users skip Screen Recording (issue #5548) and keeps working without it; Accessibility is required. — [AltTab SystemPermissions.swift @2a9cbbb](https://github.com/lwouis/alt-tab-macos/blob/2a9cbbb5462fbd0a76bb3f5f50d71b357823d6ab/src/macos/SystemPermissions.swift)
- Apple's CGWindowListCopyWindowInfo reference does not document which keys are gated; Apple recommends `CGPreflightScreenCaptureAccess()` (no prompt) and `CGRequestScreenCaptureAccess()` (prompts). The same thread reports that on a macOS 27 beta `kCGWindowOwnerName` is filled in for other apps' windows without permission. — [Apple Developer Forums thread 839069](https://developer.apple.com/forums/thread/839069) (from search excerpt)
- Catalina: CGWindowListCopyWindowInfo only returns window names with Screen Recording permission, though some names are present without it. — [Mozilla Bug 1580900](https://bugzilla.mozilla.org/show_bug.cgi?id=1580900); [Apple Developer Forums: window name not available in macOS 10.15](https://developer.apple.com/forums/thread/126860); [Michael Tsai: Detecting Screen Recording Permission on Catalina (2019-11-22)](https://mjtsai.com/blog/2019/11/22/detecting-screen-recording-permission-on-catalina/)
- On 27.0.1 the keys returned per window are: kCGWindowAlpha, kCGWindowBounds, kCGWindowIsOnscreen, kCGWindowLayer, kCGWindowMemoryUsage, kCGWindowName, kCGWindowNumber, kCGWindowOwnerName, kCGWindowOwnerPID, kCGWindowSharingState, kCGWindowStoreType. With `.optionAll`, 73 of 81 layer-0 windows had no `kCGWindowIsOnscreen` (off screen covers minimized windows, hidden apps and other Spaces). This run had Screen Recording, so it shows the full set, not the reduced one. — [Local test]
- AltTab's focus recipe for one window: if minimized, set `kAXMinimizedAttribute` to false via AX; then `_SLPSSetFrontProcessWithOptions(&psn, wid, userGenerated)` (fronts the process and only that window, switching Space if needed); then "makeKeyWindow" via `SLPSPostEventRecordTo` (a synthetic mouse down/up event record); then `kAXRaiseAction`. Its comment: "The public APIs alone don't move key focus across apps (macOS 14 downgraded NSRunningApplication.activate to an advisory 'request')." — [AltTab Window.swift @2a9cbbb](https://github.com/lwouis/alt-tab-macos/blob/2a9cbbb5462fbd0a76bb3f5f50d71b357823d6ab/src/switcher/state/Window.swift); [AltTab SkyLight.framework.swift](https://github.com/lwouis/alt-tab-macos/blob/2a9cbbb5462fbd0a76bb3f5f50d71b357823d6ab/src/macos/api-wrappers/SkyLight.framework.swift)
- AltTab maps AX elements to CGWindowIDs with private `_AXUIElementGetWindow`, builds AX elements for windows AX does not list (e.g. other Spaces) with private `_AXUIElementCreateWithRemoteToken`, and reads Spaces with `CGSCopySpacesForWindows`. — [AltTab AXUIElement.swift](https://github.com/lwouis/alt-tab-macos/blob/2a9cbbb5462fbd0a76bb3f5f50d71b357823d6ab/src/macos/api-wrappers/AXUIElement.swift); [AltTab HIServices wrapper](https://github.com/lwouis/alt-tab-macos/blob/2a9cbbb5462fbd0a76bb3f5f50d71b357823d6ab/src/macos/api-wrappers/ApplicationServices.HIServices.framework.swift)
- macOS 27 SDK: `NSApplicationActivateIgnoringOtherApps` is marked `API_DEPRECATED("ignoringOtherApps is deprecated in macOS 14 and will have no effect.")`; `-activateFromApplication:options:` was added in macOS 14.0. — [Local test: NSRunningApplication.h in macOS 27 SDK]
- DockDoor needs Accessibility and Screen Recording ("which DockDoor needs to find your windows and show their previews"); its source uses `kAXMinimizedAttribute`, `_SLPSSetFrontProcessWithOptions` and `_AXUIElementCreateWithRemoteToken`. — [dockdoor.net](https://dockdoor.net/); [Local test: grep of DockDoor @baf6425](https://github.com/ejbills/DockDoor)
- uBar: "The Accessibility API is used to control windows and applications" (quit apps, close/maximize/minimize windows); Screen Recording lets it read window titles, show newly opened windows and capture previews ("at no time is your screen actually being recorded"); Full Disk Access is optional and only for Trash. — [uBar documentation (mirror of ubarapp.com/documentation)](https://kelaenderkoe.pages.dev/float-https-ubarapp.com/documentation)
- ExtraDock: Accessibility "lets ExtraDock read and control window state" (badges, minimize toggle, window focus/minimize/restore); Screen Recording only for live thumbnails; "Space Awareness can still list visible apps without Accessibility permission." — [ExtraDock permissions](https://extradock.app/docs/permissions.html)
- Screen Recording carries a recurring cost: macOS 15 Sequoia re-prompts monthly ("Allow For One Month"); beta builds prompted weekly. — [MacRumors, 2024-08-15](https://www.macrumors.com/2024/08/15/macos-sequoia-screen-recording-app-permissions/); [9to5Mac, 2024-08-14](https://9to5mac.com/2024/08/14/macos-sequoia-screen-recording-prompt-monthly/)

### Inferences
- Zero-permission tier: OldMacDoc can show a rough per-app window count and on-screen state from CGWindowList, but not titles, and it cannot reliably tell minimized windows from windows on other Spaces.
- The Dock-menu AX route (Q1) returns window titles from the Dock's own AX tree, so the Dock's window list (with the checkmark on the main window) can be shown without Screen Recording. Pressing a window item would make Apple's Dock front or unminimize that window, so no private SkyLight calls are needed. This is inferred, not tested in a no-Screen-Recording state.
- If OldMacDoc does its own window management instead, Accessibility is the one permission worth asking for. Screen Recording adds titles from CGWindowList but brings the monthly re-prompt and a heavy trust cost, and it buys nothing that Accessibility does not already give.

### Gaps
- Could not observe the exact CGWindowList output without Screen Recording on 27.0.1, because the probe inherited a granted state.
- Whether `NSRunningApplication.activate(from:options:)` called from a just-clicked dock panel is enough to front an app on 14+ was not tested.

## Q3. Open at Login for another app

### Takeaway
`SMAppService` only registers the calling app or helpers inside its own bundle. Apple's Dock on 27.0.1 still uses the legacy `LSSharedFileList` session-login-items API, plus BTM calls, but it holds private shared-file-list and BTM entitlements. A third-party process can read the list with the legacy API without a prompt (verified on 27.0.1). Writing through it is untested, and reports conflict on whether it still works. System Events `make login item` needs Automation for System Events, with mixed reports on Sonoma. Pressing Dock > Options > Open at Login over AX gives exact Dock behavior for the cost of Accessibility.

### Cited Findings
- Apple (Quinn): "Open at Login shows a list of login items, per the legacy kLSSharedFileListSessionLoginItems API"; "Allow in the Background … is an allowlist." John Siracusa: `SMAppService.mainApp.register()`/`unregister()` manage the Open at Login section. — [Michael Tsai: Ventura's "Open at Login" vs. "Allow in the Background" (2022-10-27)](https://mjtsai.com/blog/?p=37461)
- SMAppService covers the main app (`mainApp`), helpers in the app's own bundle (`loginItem(identifier:)`), and its own LaunchAgents and daemons; there is no API to register a different app. — [Apple: SMAppService](https://developer.apple.com/documentation/servicemanagement/smappservice); [Apple Developer Forums: Porting existing LoginItem Logic to the new SMAppService](https://developer.apple.com/forums/thread/713830?answerId=726511022)
- The Dock on 27.0.1 imports `LSSharedFileListCreate`, `LSSharedFileListCopySnapshot`, `LSSharedFileListInsertItemBookmark`, `LSSharedFileListItemRemove`, `LSSharedFileListItemCopyBookmarkData`, `LSSharedFileListGetSeedValue`, `BTMDispositionIsLaunchable`, and links `BackgroundTaskManagement.framework`. It is entitled with `com.apple.private.coreservices.canaccessanysharedfilelist` and `com.apple.private.backgroundtaskmanagement.manage`. — [Local test: `nm -u`, `otool -L`, `codesign` on Dock]
- A non-entitled probe calling `LSSharedFileListCreate(NULL, kLSSharedFileListSessionLoginItems, NULL)` and `LSSharedFileListCopySnapshot` on 27.0.1 returned 1 item with a display name. That matches `tell application "System Events" to get the name of every login item` (1 item). No prompt appeared. — [Local test]
- Conflicting: one developer reports the LSSharedFileList login-item API (deprecated since 10.11) is documented as "no longer supported" and had no effect on current macOS, and moved to SMAppService. — [truthatt11/shuttle PR #4](https://github.com/truthatt11/shuttle/pull/4). An El Capitan-era thread said it still worked despite deprecation. — [cocoa-dev: LSSharedFileList API deprecated](https://cocoa-dev.apple.narkive.com/e1eR9bUb/lssharedfilelist-api-deprecated)
- Sandboxed apps cannot use `LSSharedFileListInsertItemURL` (not a limit for OldMacDoc, which is not sandboxed). — [cocoa-dev, 2012-01](https://lists.apple.com/archives/cocoa-dev/2012/Jan/msg00141.html). Adding a login item for all users needs admin rights. — [SpecterOps Apfell docs: persist_loginitem_allusers](https://docs.specterops.io/mythic-agents/apfell-docs/commands/persist_loginitem_allusers)
- System Events can make, list and delete login items via AppleScript (Ventura-era write-up). — [Eclectic Light: How helpers are changing in Ventura (2022-06-21)](https://eclecticlight.co/2022/06/21/how-helpers-are-changing-in-ventura/) (from search excerpt). A Jamf admin reports the osascript method "seems to no longer work" on Sonoma. — [Jamf Community: macOS Sonoma Login Items](https://community.jamf.com/t5/jamf-pro/macos-sonoma-login-items-without-configuration-profile/td-p/303347). Without Automation consent, sending to System Events fails with -1743. — [MacRumors forum: error -1743](https://forums.macrumors.com/threads/avoid-not-authorized-to-send-apple-events-to-system-events-1743-for-keyboard-shortcut-script.2393549)
- Since Ventura, login and background items live in the BTM database at `/private/var/db/com.apple.backgroundtaskmanagement/BackgroundItems-v*.btm` (the version number changes by release). `sudo sfltool dumpbtm` needs root, and the open-source DumpBTM needs Full Disk Access. — [Eclectic Light: Controlling login and background items in Ventura (2023-02-15)](https://eclecticlight.co/2023/02/15/controlling-login-and-background-items-in-ventura/); [r0x4/DumpBTM](https://gh.ali360.cloudns.ch/r0x4/DumpBTM); [Objective-See DumpBTM post](https://patreon.com/posts/77420730)
- Apple's Dock exposes the current state as a checkmark on Options > Open at Login, readable via AX. — [Local test, Q1]

### Inferences
- For the checkmark: read the `kLSSharedFileListSessionLoginItems` snapshot and compare each item's resolved URL with the app's URL. This is deprecated but works on 27.0.1 with no permission.
- For the toggle, in order of fidelity: (a) AX-press Dock > Options > Open at Login (Accessibility; exactly what the Dock does, including BTM bookkeeping); (b) `LSSharedFileListInsertItemURL` / `LSSharedFileListItemRemove` (no permission, but may be a silent no-op without the Dock's entitlement; must be tested on 14, 15, 26, 27); (c) System Events (an extra Automation prompt for a second target app, with unreliable reports); (d) open System Settings > General > Login Items and let the user add it.
- Reading the BTM database directly is out (root or Full Disk Access).

### Gaps
- LSSharedFileList writes were not tested, to avoid changing the user's login items. This is the key open question for a zero-permission toggle.
- Whether a third-party LSSharedFileList insert triggers the "Background Items Added" notification, or lands in Open at Login versus Allow in the Background, is unknown.

## Q4. "Assign To" desktops (All Desktops / This Desktop / None)

### Takeaway
The Dock applies Assign To with private CGS calls (`CGSProcessAssignToSpace`, `CGSProcessAssignToAllSpaces`) and stores it in `com.apple.spaces` `app-bindings` (bundle ID → `AllSpaces` or a Space UUID; no entry means None). It pushes the bindings to WindowServer with `CGSSessionSetCurrentSessionWorkspaceApplicationBindings`. Writing the plist from outside takes effect only after `killall Dock`, which does not fit OldMacDoc's parking, and is reported as unreliable. HIServices exports private `CoreDockSetWorkspacesAppBindings` and `CoreDockCopyWorkspacesAppBindings` (untested). The AX route through Dock > Options works and shows the current state, for the cost of Accessibility.

### Cited Findings
- The Dock on 27.0.1 imports `CGSProcessAssignToAllSpaces`, `CGSProcessAssignToSpace`, `CGSSessionSetCurrentSessionWorkspaceApplicationBindings` and `CGSSessionSetCurrentSessionWorkspacePreferences`, and has the string "Failed to assign ". — [Local test: `nm -u` and `strings` on Dock]
- The macOS 27 SDK's HIServices.tbd exports `_CoreDockCopyWorkspacesAppBindings` and `_CoreDockSetWorkspacesAppBindings`, along with `_CoreDockSendNotification`, `_CoreDockGetWorkspacesCount`, `_CoreDockSetWorkspacesCount` and others. — [Local test: grep of SDK .tbd]
- `app-bindings` in `~/Library/Preferences/com.apple.spaces.plist` maps bundle IDs to `AllSpaces` or a Space UUID. The gist sets it with PlistBuddy, then `killall Dock`; for None it deletes the key. The author is "not 100% sure" killall is needed. A commenter had to relaunch the target app. Another found it had no effect while yabai ran. Changes made in the Dock menu apply at once without restarting anything. Some apps "seem to ignore it." The specific-desktop path is marked untested. — [0xdevalias gist: app-bindings](https://gist.github.com/0xdevalias/8bc497546d5f036cbaeae5d0e389aa35)
- Assign To options appear only with at least two Spaces, and the wording changes when a second display is attached. — [Apple Community: Assigning applications to spaces](https://discussions.apple.com/thread/5494320); [Apple Community: Assign to This Desktop / All Desktops broken for some apps](https://discussions.apple.com/thread/4138506?page=2)
- On this machine `defaults read com.apple.spaces app-bindings` returned an empty dictionary, which matches Safari's AX-read Options showing "None" checked. The preference is readable with no permission. — [Local test]

### Inferences
- Reading the current state needs no permission (read `app-bindings` and match the bundle ID; for "This Desktop", compare the UUID with the current Space UUID in `SpacesDisplayConfiguration`).
- Writing with no permission is possible only through private API (`CoreDockSetWorkspacesAppBindings`, which presumably messages the Dock, then the Dock updates WindowServer). It is unverified and could break on any release. The plist plus `killall Dock` route would undo the parking and flash the Dock, so it is not recommended.
- The AX press on the Dock menu item is the dependable option and matches Apple's behavior exactly.

### Gaps
- `CoreDockSetWorkspacesAppBindings` was not called; its signature (a CFDictionary like the plist is presumed) and its effect without a Dock restart are unverified.

## Q5. "Show All Windows" (App Exposé) for a given app

### Takeaway
Verified on 27.0.1: every running-app tile in Apple's Dock exposes the AX action `AXShowExpose`, which is how Talon triggers App Exposé (needs Accessibility). The zero-permission candidate is the private `CoreDockSendNotification(CFSTR("com.apple.expose.front.awake"), 0)`; the notification string is in the 27.0.1 Dock and the function is exported. It acts on the frontmost app, so activate the target first. It was not executed here.

### Cited Findings
- Running-app Dock tiles list `AXShowExpose` among their actions on 27.0.1 (Finder, Safari). — [Local test]
- Talon's `dock_app_expose(app)` locates the app's Dock item by AX and invokes `AXShowExpose`; its `dock_send_notification` sends Dock notifications such as `com.apple.showdesktop.awake` and `com.apple.launchpad.toggle`. — [Talon dock module docs](https://wolfmanstout.github.io/wolfmanstout_talon/apps/dock)
- The Dock binary on 27.0.1 contains `com.apple.expose.front.awake`, `com.apple.expose.awake`, `AXExposeShowAllWindows`, `showAllWindowsWithTransaction:`, "Failed to show all windows via Window Manager: %@", and imports WindowManager.framework's `AppExposeShownBy.menu`. So in 27 the Dock's Show All Windows goes through the private WindowManager framework. — [Local test: `strings` and `nm` on Dock]
- `_CoreDockSendNotification` is exported by HIServices in the macOS 27 SDK. — [Local test]
- Apple has never offered an official API to invoke Exposé, and older workarounds (synthesized hotkeys read from `com.apple.symbolichotkeys`) were called unofficial and fragile. — [cocoa-dev 2008-03](https://lists.apple.com/archives/cocoa-dev/2008/Mar/msg02178.html); [cocoa-dev 2004-07: Expose API?](https://lists.apple.com/archives/cocoa-dev/2004/Jul/msg00682.html)

### Inferences
- With the Dock parked but running, both `AXShowExpose` and `CoreDockSendNotification` should still work, since the Dock process owns Exposé. Not tested.
- The fallback of posting the user's App Exposé hotkey (Ctrl-Down) via CGEvent would need Accessibility (PostEvent) anyway, so it saves nothing over `AXShowExpose`.

### Gaps
- `open -a "Mission Control" --args 2` was not verified on 14 to 27.
- `CoreDockSendNotification("com.apple.expose.front.awake")` was not executed (it would take over the user's screen). Its reliability on 14 to 27 is unconfirmed by any source found.

## Q6. Hide / Show / Quit / Force Quit / Hide Others

### Takeaway
These all go through public `NSRunningApplication` and `NSWorkspace` calls and need no TCC permission in a non-sandboxed app. The only macOS 14+ caveat is activation (Show or bring to front), which is now advisory.

### Cited Findings
- The macOS 27 SDK declares `-[NSRunningApplication hide]`, `-unhide`, `-terminate`, `-forceTerminate`, `-activateWithOptions:`, `-activateFromApplication:options:` (14.0+), and `-[NSWorkspace hideOtherApplications]`. — [Local test: NSRunningApplication.h and NSWorkspace.h in macOS 27 SDK]; [Apple: NSRunningApplication](https://developer.apple.com/documentation/appkit/nsrunningapplication)
- `ignoringOtherApps` "is deprecated in macOS 14 and will have no effect". — [Local test: NSRunningApplication.h]
- DockDoor calls `forceTerminate()` on other apps. — [DockDoor DockObserver.swift @baf6425](https://github.com/ejbills/DockDoor/blob/baf6425a981b09acb79189ec568e7c189b70a0ce/DockDoor/Utilities/DockObserver.swift). AltTab notes that public activation is only a "request" since 14. — [AltTab Window.swift](https://github.com/lwouis/alt-tab-macos/blob/2a9cbbb5462fbd0a76bb3f5f50d71b357823d6ab/src/switcher/state/Window.swift)
- Apple's Dock instead uses private calls (`_LSKillApplication`, `_LSForceQuitApplication`, `CPSPostHideReq`, `CPSPostShowReq`, `CPSPostHideMostReq`, `_CPSSetFrontProcessWithOptions`). — [Local test: `nm -u` on Dock]

### Inferences
- `NSWorkspace.hideOtherApplications()` hides everything except the caller. For "Hide Others" relative to a target app, iterate `NSWorkspace.shared.runningApplications` (regular activation policy, not the target, not OldMacDoc) and call `hide()` on each, then activate the target.
- `terminate()` asks the app to quit normally (it can refuse or show save dialogs); `forceTerminate()` kills it. Neither prompted for Automation in the docks examined. This is inferred from DockDoor and AltTab shipping them without an Automation entitlement, not from documentation.

### Gaps
- No Apple statement found on whether `terminate()` is exempt from Automation TCC; widely used without prompts, but not documented.

## Q7. Finder-specific items (New Finder Window, Find, Go to Folder, Connect to Server, Empty Trash)

### Takeaway
OldMacDoc already asks for Automation of Finder for Empty Trash. That consent is per sender and target pair, so other Finder Apple Events (for example `make new Finder window`) reuse the same grant with no new prompt. Find has a public zero-permission API: `NSWorkspace.showSearchResults(forQueryString:)`. Every Finder Dock-menu item, including recent folders, is also reachable through the Dock-menu AX route.

### Cited Findings
- `-[NSWorkspace showSearchResultsForQueryString:]` (macOS 10.6+) and `-activateFileViewerSelectingURLs:` (10.6+) are public in the macOS 27 SDK. — [Local test: NSWorkspace.h]
- Finder's Dock menu on 27.0.1 has: New Finder Window, New Smart Folder, Find…, Go to Folder…, Connect to Server…, the recent folders, Options, Show All Windows, Hide, Hide Others (no Quit). — [Local test, Q1]
- Finder's recent folders come from `com.apple.finder` `FXRecentFolders`: 10 entries, matching the 10 recent folders in the Dock menu. They are readable with `defaults read` and no permission. — [Local test]
- Apple Events consent under TCC is granted per target app (kTCCServiceAppleEvents with the target's identity), so one approval for "OldMacDoc → Finder" covers all events to Finder. — [HackTricks: macOS Apple Events](https://book.hacktricks.xyz/macos-hardening/macos-security-and-privilege-escalation/macos-security-protections/macos-tcc/macos-apple-events)
- Apple's Dock bypasses these prompts through `com.apple.private.tcc.allow` including `kTCCServiceAppleEvents`, which third parties cannot get. — [Local test: Dock entitlements]

### Inferences
- New Finder Window: Finder AE `make new Finder window` (reuses the Empty Trash grant). The zero-AE fallback `NSWorkspace.open(homeFolderURL)` may only bring forward an existing window for that folder instead of opening a new one.
- Go to Folder… and Connect to Server…: no public API found. Options are a Finder AE (activate Finder, then the Dock-equivalent action), the AX route, or using `NSWorkspace.open` on an `smb://` or `afp://` URL that the user typed in an OldMacDoc prompt.
- Recent folders for the Finder tile: build from `FXRecentFolders` (bookmark data per entry) with no permission.

### Gaps
- Whether `showSearchResults(forQueryString:)` itself sends an Apple Event that can trigger an Automation prompt from a third-party app was not tested.

## Q8. Recent documents per app

### Takeaway
Per-app recents live in `~/Library/Application Support/com.apple.sharedfilelist/com.apple.LSSharedFileList.ApplicationRecentDocuments/<bundle-id>.sfl3`, and that folder is TCC-protected: listing it failed with "Operation not permitted" without Full Disk Access on 27.0.1. The deprecated LSSharedFileList API with a per-app list name returned items once and nothing in later runs, so it is unreliable for a non-entitled process. The Dock reads them with the private `canaccessanysharedfilelist` entitlement. The zero-permission source that works is the global `kLSSharedFileListRecentDocumentItems` list, which is not per app. Per-app recents for a third party need either Full Disk Access (read the .sfl3 files) or the Dock-menu AX route.

### Cited Findings
- `ls ~/Library/Application Support/com.apple.sharedfilelist/` and the `ApplicationRecentDocuments` subfolder both failed with "Operation not permitted" in a process without Full Disk Access (`~/Library/Safari` was also unreadable, confirming no FDA). — [Local test]
- `LSSharedFileListCreate(NULL, "com.apple.LSSharedFileList.ApplicationRecentDocuments/<bundle-id>", NULL)` returned a list object for every bundle ID tried. The snapshot for `com.apple.dt.Xcode` had 10 items in the first run, then 0 items in 3 later runs (including after spinning the run loop for 1.5 s). Finder, Preview, TextEdit, Safari and VS Code always returned 0. — [Local test]
- The global `kLSSharedFileListRecentDocumentItems` (`com.apple.LSSharedFileList.RecentDocuments`) returned 10 named items, and `kLSSharedFileListRecentApplicationItems` returned 10, with no permission. — [Local test]
- The Dock has `com.apple.private.coreservices.canaccessanysharedfilelist` and contains `DOCKRecentsController`, `DOCKRecentsCache` and `addRecentsToMenu:`. — [Local test: `codesign` and `strings` on Dock]
- The Dock-menu AX route returns the recents the Dock shows (for example Finder's 10 recent folders). — [Local test, Q1]

### Inferences
- Do not ship per-app recents on the LSSharedFileList trick: the one positive result could not be reproduced.
- A cheap partial: for apps whose bundle ID matches the "Open Recent" list, the global RecentDocuments list could be filtered by file type to the app's document types (`LSCopyAllRoleHandlersForContentType`). This approximates but does not equal the Dock's list.
- Full Disk Access is the costliest permission (it reads all user data) for a small feature; the AX route gets the Dock's exact list with Accessibility, which OldMacDoc would already need for the menu proxy.

### Gaps
- The .sfl3 format (an NSKeyedArchiver archive holding bookmark data) was not decoded here, and no citable source on it was gathered in this session.
- It is not known why the per-app LSSharedFileList call returned Xcode's items once.

## Q9. Capability-by-permission matrix and recommendations

### Takeaway
A dock can cover the basic half of Apple's tile menu with zero permissions (Hide/Show/Quit/Force Quit/Hide Others, Show in Finder, Keep in Dock, Finder Find, New Finder Window via the existing Finder grant, read-only Open at Login and Assign To state). Everything that depends on another app's own Dock menu items, titled or minimized window lists, recents, or changing Assign To / Open at Login reliably needs Accessibility. Accessibility alone, used to proxy Apple's still-running Dock menu, gives near-exact parity. Screen Recording, Full Disk Access and System Events Automation add cost without adding coverage.

### Cited Findings
Matrix (OS evidence is 27.0.1 local tests unless a source says otherwise; source links are in Q1 to Q8):

| Capability | Zero-permission method | Works? | Best permissioned method | Permission | What other docks do |
|---|---|---|---|---|---|
| App's own Dock menu items (applicationDockMenu) | None (private CGS dock-message channel, Dock-only entitlement) | No | AXShowMenu on Apple's Dock tile, read, AXCancel, later AXPress | Accessibility | No dock found that proxies them; UI scripting via System Events (KM forum) |
| Window list with titles | CGWindowList: owner, bounds, layer, on-screen; no titles | Partial | Dock-menu AX route, or AX kAXWindows + kAXTitle | Accessibility (titles via CGWindowList need Screen Recording) | AltTab (AX required, SR optional), DockDoor (AX + SR), uBar (AX + SR), ExtraDock (AX + SR) |
| Minimized state | No reliable way | No | AX kAXMinimizedAttribute | Accessibility | AltTab, DockDoor |
| Bring a specific window forward or unminimize | Activate the app only (advisory since 14) | Partial | AXPress the window item in the Dock menu, or AX set minimized=false + `_SLPSSetFrontProcessWithOptions` + AXRaise | Accessibility (+ private API) | AltTab, DockDoor |
| Show All Windows (App Exposé) | `CoreDockSendNotification("com.apple.expose.front.awake")` (private, untested) | Unverified | `AXShowExpose` on the Dock tile | Accessibility | Talon |
| Hide / Show / Quit / Force Quit / Hide Others | NSRunningApplication / NSWorkspace | Yes | n/a | None | DockDoor (`forceTerminate`) |
| Open at Login: read state | LSSharedFileList session login items snapshot (deprecated) | Yes (read) | Read the Dock menu checkmark | None | n/a |
| Open at Login: toggle | `LSSharedFileListInsertItemURL` / `ItemRemove` | Untested; conflicting reports | AXPress Dock > Options > Open at Login; or System Events | Accessibility; or Automation (System Events) | n/a |
| Assign To: read state | `defaults` `com.apple.spaces` `app-bindings` | Yes | Dock menu checkmark | None | n/a |
| Assign To: set | `CoreDockSetWorkspacesAppBindings` (private, untested); plist + `killall Dock` (breaks parking) | Unverified / poor | AXPress Dock > Options > All Desktops / This Desktop / None | Accessibility | n/a |
| Finder: Find… | `NSWorkspace.showSearchResults(forQueryString:)` | Likely (public API) | Finder AE | Automation (Finder), already granted for Empty Trash | n/a |
| Finder: New Finder Window | `NSWorkspace.open(folder)` (may reuse a window) | Partial | Finder AE `make new Finder window` | Automation (Finder), already granted | n/a |
| Finder: recent folders | `com.apple.finder` `FXRecentFolders` | Yes | Dock-menu AX route | None | n/a |
| Per-app recent documents | Global RecentDocuments list only (not per app) | No (per app) | Dock-menu AX route; or read .sfl3 | Accessibility; or Full Disk Access | uBar documentation does not mention recents |
| Empty Trash | n/a | n/a | Finder AE (already shipped) | Automation (Finder) | uBar uses optional FDA for Trash; ExtraDock "Native Trash" needs file access |

Permission costs:
- Accessibility: the user must enable it by hand in System Settings > Privacy & Security > Accessibility (the API can only open the prompt or pane). Apps often have to detect the grant and may need a relaunch; DockDoor 1.40.2 changed its prompt to ask for a restart only after it detects the grant. The grant gives broad UI control, which is a trust cost. — [DockDoor 1.40.2 release notes](https://newreleases.io/project/github/ejbills/DockDoor/release/1.40.2); [AltTab SystemPermissions.swift](https://github.com/lwouis/alt-tab-macos/blob/2a9cbbb5462fbd0a76bb3f5f50d71b357823d6ab/src/macos/SystemPermissions.swift)
- Screen Recording: a monthly re-approval prompt since Sequoia, an alarming name ("Screen & System Audio Recording"), and `CGPreflightScreenCaptureAccess` stays stale within a process. — [MacRumors](https://www.macrumors.com/2024/08/15/macos-sequoia-screen-recording-app-permissions/); [AltTab SystemPermissions.swift](https://github.com/lwouis/alt-tab-macos/blob/2a9cbbb5462fbd0a76bb3f5f50d71b357823d6ab/src/macos/SystemPermissions.swift)
- Automation (Apple Events): one prompt per target app. Finder is already covered; System Events would be a second prompt, and failures show as -1743. — [MacRumors forum -1743](https://forums.macrumors.com/threads/avoid-not-authorized-to-send-apple-events-to-system-events-1743-for-keyboard-shortcut-script.2393549)
- Full Disk Access: the broadest grant; users must add the app by hand; uBar labels it optional and Trash-only. — [uBar documentation](https://kelaenderkoe.pages.dev/float-https-ubarapp.com/documentation)

### Inferences
Recommendations for OldMacDoc:
1. **Tier 0, keep shipping with no permissions:** Hide, Show, Quit, Force Quit (Option), Hide Others (loop over other regular apps), Show in Finder (`activateFileViewerSelecting`), Keep in Dock (OldMacDoc's own data), Finder Find (`showSearchResults`), New Finder Window (Finder AE under the existing Empty Trash grant), Finder recent folders (`FXRecentFolders`), Open at Login and Assign To shown read-only (checkmarks from LSSharedFileList and `app-bindings`), and a window count from CGWindowList.
2. **Tier 1, one opt-in permission (Accessibility), "Use Apple's Dock menu":** because OldMacDoc parks rather than kills the Dock, it can proxy Apple's own menu over AX. That gives the app's own Dock items, the titled window list with main-window checkmark, recents, Options (Open at Login, Assign To, with state), Show All Windows (`AXShowExpose`), all with Apple's exact behavior and no private API. Ask for it only when the user turns on an "Extended menus" setting, and fall back to Tier 0 when it is not granted.
3. **Avoid:** Screen Recording (titles are available through AX instead, and it re-prompts monthly), Full Disk Access (recents through AX instead), System Events Automation (a second prompt with unreliable Sonoma reports), and `killall Dock`-based writes (they undo the parking).
4. **Experiment before deciding** (each could move a feature into Tier 0): a third-party `LSSharedFileListInsertItemURL` / `ItemRemove` on 14, 15, 26 and 27 for Open at Login; private `CoreDockSetWorkspacesAppBindings` for Assign To; private `CoreDockSendNotification("com.apple.expose.front.awake")` after activating the target for Show All Windows. Each private call is a release-by-release risk, but none needs a permission.
5. **Verify the AX proxy under real parking:** run `AXShowMenu` with OldMacDoc's huge `autohide-delay` and check for any visible flash, how fast read-then-cancel is, and whether `AXPress` on items such as Assign To and window items acts at once while the Dock is parked.

### Gaps
- No product documentation was found for ActiveDock, Dockey, HyperDock or MacPilot permissions or menu features; uBar's documentation does not say whether it reproduces apps' own Dock menu items.
- All OS-behavior tests are from 27.0.1 only; nothing was re-run on 14, 15 or 26. Version-specific breakage dates beyond Ventura (login item UI, 2022) and Sequoia (Screen Recording re-prompt, 2024) were not found.
