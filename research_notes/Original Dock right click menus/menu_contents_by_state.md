# macOS Dock tile menus: item-by-item contents by tile type, app state and OS version

Notes on method and source tiers (read first):

- **Tier A, primary, current macOS.** I read the shipping Dock's own menu template and string tables on this machine (macOS 27.0.1, build 26A434). They are `/System/Library/CoreServices/Dock.app/Contents/Resources/DockMenus.plist` and `.../en.lproj/DockMenus.strings` + `Localizable.strings`. I also read Finder's dock-menu strings (`Finder.app/.../en.lproj/LocalizableMerged.strings`). Then I opened real Dock menus through the Accessibility API (System Events `AXShowMenu` on each Dock tile, dumping each item's title, mark character and enabled state, then pressing Escape) and recorded the result. Cited below as **[Local plist]**, **[Local strings]**, **[Finder strings]** and **[Live AX dump, macOS 27.0.1]**. One caveat on the AX dump: it lists Option-key *alternate* items (Hide Others, Force Quit) next to their primaries. On screen, only one of each pair is visible at a time.
- **Tier A, primary, historical.** Apple's own Human Interface Guidelines PDFs: 2005-09-08 (Tiger era), 2008-06-09 (Leopard era), 2009-08-20 (Snow Leopard era) and 2012-07-23 (Mountain Lion era). They come from the archive.org `apple-hig` collection and I read them in full text.
- **Tier B, primary-ish.** A `DockMenus.plist` posted as a GitHub gist on 2015-04-18. It contains a `dashboard` section and `SECURE_EMPTY_TRASH`, so it is almost certainly OS X 10.10 Yosemite. Cited as **[2015 plist]**. Its contents are reproduced in the "versions" section.
- **Tier C.** Apple Support pages, TidBITS, MacMost, Lap Cat Software, MacRumors and Apple Community threads, Wikipedia. Where a fact comes only from a search-engine excerpt and not from a page I could open, it is marked *(search excerpt)*.
- Exact-glyph note: current strings use the single Unicode ellipsis "…" (U+2026) and curly quotes “ ” in `Open “%@”`.

---

## Q1. App that is NOT running (pinned in the Dock): which items, in what order?

### Takeaway
On current macOS (verified live on 27.0.1), a pinned, not-running app shows these items in order. First come the app's recent documents, if it has any. Then a separator. Then **Options ▸** with Remove from Dock, Open at Login, Show in Finder, and an Assign To block when more than one desktop exists. Then a separator, then **Open**. Leopard (10.5) used the same items with no Options submenu: Remove from Dock, Open at Login, Show in Finder, Open. Snow Leopard (10.6) moved the first three into **Options ▸**.

### Cited Findings
- **Current template (`fileapp` = app tile not running):** `OPTIONS ▸ { KEEP_IN_DOCK, REMOVE_FROM_DOCK, OPEN_AT_LOGIN, SHOW_IN_FINDER }`, separator, `SHOW_ALL_WINDOWS`, `SHOW_RECENTS`, `OPEN`, `FORCE_QUIT (dynamic=1)` — [Local plist](file:///System/Library/CoreServices/Dock.app/Contents/Resources/DockMenus.plist). Not every template item is shown. The Dock filters them at runtime, as the live dumps below show.
- **Live, Maps (pinned, not running, no recents)** — [Live AX dump, macOS 27.0.1]:
  ```
  Options ▸
      Remove from Dock
      Open at Login
      Show in Finder
      ───────────
      Assign To            (section header)
      All Desktops
      This Desktop
    ✓ None
  ───────────
  Open
  [Force Quit]             (Option-alternate, see Q5)
  ```
- **Live, Numbers (pinned, not running, has recent documents)** — [Live AX dump, macOS 27.0.1]. Nine recent-document names are listed **at the top**, then a separator, then the same Options ▸ / separator / Open / [Force Quit] block as Maps. No "Show Recents" item and no "Show All Windows" item appeared.
- **Snow Leopard (2009 HIG):** "When you click and hold the Dock icon of an application that is not running, a minimal Dock menu appears that allows you to: Open the application; Show the application in the Finder and manage the Remove from Dock and Open at Login options." Control-click on a not-running app shows "the same minimal Dock menu" — [Apple HIG 2009-08-20, "The Dock"](https://archive.org/download/apple-hig/MacOSX_HIG_2009_08_20.pdf).
- **Leopard-era user report (2008):** the right-click options on a not-running System Preferences tile were "Remove From Dock, Open At Login, Show in Finder and Open" — [Yahoo Answers, 2008-10-10](https://answers.yahoo.com/question/index?qid=20081010092039AAwpVua) *(search excerpt; the page no longer loads)*.
- **Snow Leopard moved those items into Options:** Macworld's "11 major new Snow Leopard features" says the items for removing an app, opening it at login and revealing it in the Finder moved into a new **Options** submenu — [Macworld](https://www.macworld.com/article/199787/snow-leopard-changes.html) *(search excerpt; the page now returns HTTP 410)*.
- **10.6 "Mac 101"-style description:** "All application, folder, and file Dock menus have an 'Options' sub-menu." It lists Keep in Dock / Remove from Dock, Open at Login and Show in Finder. "Remove from Dock appears in the Dock Menu of an inactive application that is set to 'Keep in Dock' or on a folder / file" — [Dennis Deschamps blog, Sept 2010, Mac OS X v10.6 Dock](https://dennisdeschampsblogs.blogspot.com/2010/09/mac-os-x-v106-mac-101-dock-dock-expose.html).
- **Lion added "Show Recents" for not-running apps:** "In Lion, when you right-click (Cntrl+click) on an app icon in the dock (an app not running), one of the menu choices is 'Show Recents'." Replies say it "shows recently open documents" and that "an application has to support this feature to show anything" — [Apple Community thread 3258198, 2011](https://discussions.apple.com/thread/3258198).
- **Yosemite-era template (`fileapp`):** `OPTIONS ▸ { REMOVE_FROM_DOCK, OPEN_AT_LOGIN, SHOW_IN_FINDER }`, separator, `SHOW_ALL_WINDOWS`, `SHOW_RECENTS`, `OPEN`. It has no Keep in Dock and no Force Quit — [2015 plist gist](https://gist.github.com/Darkle/2ca4152ec3cbc90b8aa9).
- **Recent documents in Dock menus:** "Apps like Pages, Numbers, and Keynote list recent documents in their Dock menu" — [MacMost, 2025-08-04](https://macmost.com/get-the-most-from-the-mac-dock-with-dock-menus.html).
- **Open at Login shows a checkmark when on:** "choose Options > Open at Login. A check mark appears next to Open at Login" — [TidBITS, 2017-03-06](https://tidbits.com/2017/03/06/macos-hidden-treasures-dominate-the-dock/).

### Inferences
- **Reproducible current menu, not-running pinned app:**
  `[recent document names…]`, `───`, `Options ▸ (Remove from Dock / Open at Login / Show in Finder [/ ─── / Assign To / All Desktops / This Desktop / None])`, `───`, `Open`.
  The recent-documents block and its separator appear only if the app has recents.
- Since 2015 the macOS 27 template has gained `KEEP_IN_DOCK` and `FORCE_QUIT` in `fileapp`. The likely reason is the "recent applications" Dock section, whose not-running, un-pinned tiles need **Keep in Dock**, and a launching or hung app whose tile is still in "file" state. The Dock binary contains the strings "File tile is not acting as process" and "actingAsProcess". This explanation is inferred, not documented.
- In Lion through Yosemite, recents seem to have been reached through a **Show Recents** item that opens App Exposé with recent documents. The macOS 27 live menu instead lists recent documents inline at the top. The `SHOW_RECENTS` template item still exists, so it may appear under conditions I did not trigger.
- **Leopard (10.5) not-running pinned app, best reconstruction:** `Remove from Dock`, `Open at Login`, `Show in Finder`, `───`, `Open`. The separator before Open is inferred from later templates.

### Gaps
- I found no first-hand Leopard screenshot or Apple document that gives the exact Leopard order or separators. The reconstruction rests on the Yahoo excerpt plus the HIG.
- I could not confirm whether recent documents were listed inline in 10.5 or 10.6. They appear inline in macOS 27 and behind "Show Recents" in Lion.
- I could not confirm when "Show Recents" stopped appearing for apps that list recents inline.

---

## Q2. App that IS running: full ordered contents (window list, app items, Options, Show All Windows, Hide/Show, Quit, Force Quit, Not Responding)

### Takeaway
On current macOS a running app's menu is built in this order:
1. `Application Not Responding` (disabled), only when the app is hung, followed by a separator.
2. The Dock's **window list**: ✓ on the main window, ◆ on minimized windows.
3. A separator, then the app's **own dock-menu items** from `applicationDockMenu(_:)`, then a separator.
4. **Options ▸**: ✓Keep in Dock (or Remove from Dock), Open at Login, Show in Finder, then a separator and an Assign To block.
5. A separator, then **Show All Windows**, **Hide** (or **Show** when hidden), and **Quit**.

Holding Option turns Hide into **Hide Others** and Quit into **Force Quit**. Leopard had the same pieces without the Options submenu and without Show All Windows.

### Cited Findings
- **Current template (`process` = running app):**
  ```
  APPLICATION_NOT_RESPONDING [enabled=false]
  ───
  OPTIONS ▸ { KEEP_IN_DOCK, REMOVE_FROM_DOCK, OPEN_AT_LOGIN, SHOW_IN_FINDER }
  ───
  SHOW_ALL_WINDOWS
  SHOW_RECENTS
  HIDE        [dynamic=0]
  HIDE_OTHERS [dynamic=1]
  SHOW
  OPEN
  QUIT        [dynamic=0, dynamic-break]
  FORCE_QUIT  [dynamic=1]
  ```
  The Dock code inserts the window list and the app's own items above this, and the Assign To block inside Options — [Local plist](file:///System/Library/CoreServices/Dock.app/Contents/Resources/DockMenus.plist). The Yosemite template is identical apart from the separate `assignto` section — [2015 plist gist](https://gist.github.com/Darkle/2ca4152ec3cbc90b8aa9).
- **Live, Safari (pinned, running, one window)** — [Live AX dump, macOS 27.0.1]:
  ```
  ✓ <window title>
  ───────────
  New Window                  (Safari's applicationDockMenu items)
  New Private Window
  ───────────
  Options ▸
    ✓ Keep in Dock
      Open at Login
      Show in Finder
      ───────────
      Assign To               (header)
      All Desktops
      This Desktop
    ✓ None
  ───────────
  Show All Windows
  Hide            [Option → Hide Others]
  Quit            [Option → Force Quit]
  ```
- **Live, Google Chrome (running, not pinned):** `✓ <window>`, `───`, Chrome's own items (a list of profiles, `───`, New Window, New Incognito Window), `───`, Options ▸ with **Keep in Dock unchecked** (because the app is not pinned), Open at Login, Show in Finder, `───`, Assign To / All Desktops / This Desktop / ✓None, then `───`, Show All Windows, Hide, [Hide Others], Quit, [Force Quit] — [Live AX dump, macOS 27.0.1]. Ghostty, Notes and Music had the same structure. Music's own block is large, with submenus (Rating ▸ None/★…★★★★★, Repeat ▸ Off/All/One, Shuffle ▸ On/Off/Songs/Albums/Groupings, Pause, Next, Previous). All of it sits between the window-list separator and Options.
- **Window-list marks:** "Dock menus list open windows for that app, including minimized ones (marked with a diamond)" — [MacMost 2025](https://macmost.com/get-the-most-from-the-mac-dock-with-dock-menus.html). Apple's convention for window lists: "A checkmark indicates the active window… A diamond indicates that the window has been minimized into the Dock." "Use a bullet next to a document with unsaved changes… A minimized document with unsaved changes should have a diamond only." — [Apple HIG 2005-09-08, Menus](http://www.multimedialab.be/doc/tech/doc_osx_hi_guidelines.pdf). Live dumps showed ✓ on one window for Safari, Chrome, Ghostty and Finder. Notes' only window had no ✓ — [Live AX dump, macOS 27.0.1].
- **App items position:** "You can customize your application's Dock menu by adding to the default items provided by the Dock. These additional items appear in the Dock menu only when the application is open… Application-specific items appear above the standard Dock menu items." — [Apple HIG 2008-06-09, Dock Menus](https://archive.org/download/apple-hig/MacOSX_HIG_2008_06_09.pdf). The 2005 HIG has identical text — [HIG 2005](http://www.multimedialab.be/doc/tech/doc_osx_hi_guidelines.pdf).
- **API mechanics:** `applicationDockMenu(_:)` "Returns the app's dock menu." "If this method returns a menu, this menu takes precedence over the `dockMenu` in the nib. The target and action for each menu item are passed to the dock. On selection of the menu item the dock messages your application, which should invoke `[NSApp sendAction:selector to:target from:nil]`." The nib alternative is the Info.plist key `AppleDockMenu` — [Apple Developer: applicationDockMenu(_:)](https://developer.apple.com/documentation/appkit/nsapplicationdelegate/applicationdockmenu(_:)).
- **Current HIG:** "people can secondary click an app's or game's icon in the Dock to reveal a Dock menu, which presents both system-provided and custom items. The system-provided Dock menu items can vary depending on whether the app is open." It suggests that "a Dock menu can list all currently or recently open windows" and gives Mail as an example (get new mail, compose) — [Apple HIG: Dock menus](https://developer.apple.com/design/human-interface-guidelines/dock-menus).
- **Leopard-era standard items:** "The menu lists the application's open windows and contains the Show In Finder, Hide, and Quit commands… If the user presses the Option key, Hide changes to Hide Others and Quit changes to Force Quit. If the tile has not been permanently added to the Dock, the command Keep In Dock also appears." — [Apple HIG 2008-06-09](https://archive.org/download/apple-hig/MacOSX_HIG_2008_06_09.pdf). This paragraph is unchanged from the 2005 Tiger-era HIG and does not mention Open at Login, which the Leopard Dock did have (see Q1).
- **Snow Leopard running app (2009 HIG):** press-and-hold gives "a minimal Dock menu" to "Quit the application; Hide or show the application's windows; Show the application in the Finder and manage the Keep in Dock and Open at Login options". "When you Control-click the Dock icon of a running application, a customizable Dock menu appears… this menu displays the same items as the minimal Dock menu… In addition, this menu lists all open windows (including minimized windows) and may contain application-specific items." Custom items appear "only when the application is open and the user Control-clicks the Dock icon." — [Apple HIG 2009-08-20](https://archive.org/download/apple-hig/MacOSX_HIG_2009_08_20.pdf).
- **Keep in Dock vs Remove from Dock in Options:** "choose Options > Remove from Dock if the app is closed or Options > Keep in Dock if it's open" (that is, uncheck it) — [TidBITS 2017](https://tidbits.com/2017/03/06/macos-hidden-treasures-dominate-the-dock/). This matches the live dumps: running Safari showed ✓Keep in Dock and not-running Maps showed Remove from Dock.
- **Show All Windows:** "choose Show All Windows from the contextual menu" — [TidBITS 2017](https://tidbits.com/2017/03/06/macos-hidden-treasures-dominate-the-dock/). "Select 'Show All Windows' to enter App Exposé" — [MacMost 2025](https://macmost.com/get-the-most-from-the-mac-dock-with-dock-menus.html). In Lion, users noted that click-and-hold "just shows a menu list which includes that option inside the menu" — [MacRumors forum, 2011-07-25](https://forums.macrumors.com/threads/lion-osx-show-all-windows-like-snow-leopard.1197752/).
- **Hide ↔ Show, Option alternates:** "Select Hide or Show to control app visibility." "Hold Option to change Quit to Force Quit." "Option also changes Hide to Hide Others" — [MacMost 2025](https://macmost.com/get-the-most-from-the-mac-dock-with-dock-menus.html). Also "open the app's contextual menu and hold Option to turn Quit into Force Quit" and "press Option to turn Hide into Hide Others" — [TidBITS 2017](https://tidbits.com/2017/03/06/macos-hidden-treasures-dominate-the-dock/).
- **Assign To (Lion onward):** the Options submenu gained "a section labeled Assign To which contains three options": All Desktops, This Desktop, None. It appears only when more than one desktop exists — [Cult of Mac, 2011](https://www.cultofmac.com/news/assign-applications-to-mission-control-spaces-in-lion-os-x-tips) and [MacRumors, 2011-07-21](https://macrumors.com/2011/07/21/lion-assigning-apps-to-all-desktops-in-mission-control) *(both search excerpts)*. The 2012 HIG names "Assign to this Desktop" among Dock-menu options — [Apple HIG 2012-07-23](https://archive.org/download/apple-hig/MacOSX_HIG_2012_07_23.pdf). The current strings are `ASSIGN_TO = Assign To`, `ALL_DESKTOPS = All Desktops`, `THIS_DESKTOP = This Desktop`, `DESKTOP_ON = Desktop on Display %@`, `OTHER_DESKTOP = Desktop %@`, `OTHER_DESKTOP_ON = Desktop %@ on Display %@`, `NONE = None` — [Local strings](file:///System/Library/CoreServices/Dock.app/Contents/Resources/en.lproj/DockMenus.strings). The Yosemite template had a separate `assignto` list: `ASSIGN_TO [disabled header]`, `ALL_DESKTOPS`, `THIS_DESKTOP`, `OTHER_DESKTOP`, `NONE` — [2015 plist gist](https://gist.github.com/Darkle/2ca4152ec3cbc90b8aa9).
- **Not responding:** the template's first item is `APPLICATION_NOT_RESPONDING` (disabled) followed by a separator. The English string is "Application Not Responding" — [Local plist](file:///System/Library/CoreServices/Dock.app/Contents/Resources/DockMenus.plist), [Local strings](file:///System/Library/CoreServices/Dock.app/Contents/Resources/en.lproj/DockMenus.strings). Apple: "If an app stops responding, Control-click the app's icon, then choose Force Quit" — [Apple Support: Use the Dock on Mac](https://support.apple.com/guide/mac-help/use-the-dock-mh35859/mac).
- **New in recent macOS strings:** `STOP_RUNNING_IN_BACKGROUND = Stop Running in Background` ([Local strings](file:///System/Library/CoreServices/Dock.app/Contents/Resources/en.lproj/DockMenus.strings)), plus `RUNNING_IN_BACKGROUND = Running in Background` and `NO_AVAILABLE_WINDOWS = No Available Windows` ([Local Localizable.strings](file:///System/Library/CoreServices/Dock.app/Contents/Resources/en.lproj/Localizable.strings)).

### Inferences
- **Reproducible current menu, running app** (bracketed items are conditional):
  ```
  [Application Not Responding]   (disabled; only when hung)
  [───]
  [✓|◆| ] Window 1               (Dock-generated window list)
  [  ] Window 2 …
  ───
  [app items from applicationDockMenu, may include submenus and its own separators]
  ───
  Options ▸
      ✓ Keep in Dock   (unchecked if not pinned; "Remove from Dock" form is used only for not-running tiles)
        Open at Login  (✓ when set)
        Show in Finder
      [─── Assign To / All Desktops / This Desktop or Desktop on Display N / None]   (exactly one has ✓; only with >1 desktop)
  ───
  Show All Windows
  [Show Recents]                 (when the app has recents; see Q1 gaps)
  Hide | Show                    (Show when app is hidden; Option: Hide Others)
  Quit                           (Option: Force Quit; hung app: Force Quit)
  ```
- `dynamic=0` / `dynamic=1` in the template almost certainly marks NSMenuItem primary/Option-alternate pairs, consistent with the TidBITS and MacMost descriptions. `dynamic-break` on QUIT probably separates it from the Hide/Hide Others pair so the two alternate groups don't merge. `dynamic=2`, used for Secure Empty Trash in 2015, matches the Command-key alternate (see Q3).
- `Desktop on Display %@` is used instead of "This Desktop" when "Displays have separate Spaces" is on with multiple displays. This feature arrived with OS X 10.9 Mavericks. `Desktop %@` appears when the app is assigned to a different desktop. Both are inferred from the string keys.
- The ✓ appears to mark the app's main/key window, not "the frontmost app's window". Apps in the background still showed ✓, while Notes showed none, possibly because its window wasn't main.
- **Leopard (10.5), running pinned app, best reconstruction:**
  ```
  ✓ Window A / ◆ Window B …
  ───
  [app items]
  ───
  Remove from Dock   (or "Keep in Dock" if not pinned; see gap)
  Open at Login
  Show in Finder
  ───
  Hide    (Option: Hide Others)
  Quit    (Option: Force Quit)
  ```
  There was no Options submenu, no Show All Windows and no Assign To.

### Gaps
- **Window-list order.** I could not establish whether windows are listed in z-order, creation order or alphabetically, or whether windows on other Spaces or in full screen are included. Strings such as "Not Available in this Split View" hint at special handling.
- **Bullet mark.** I could not confirm whether the Dock window list ever shows the unsaved-changes bullet (•). The HIG rule is for the Window menu.
- **Keep in Dock for running pinned apps in Leopard.** It is unclear whether Leopard showed "Remove from Dock" or "Keep in Dock" here. The Snow Leopard Mac 101-style text implies running pinned apps show Keep in Dock (checked), but nothing I found is Leopard-specific.
- **Show All Windows in 10.6.** The 2009 HIG's minimal-menu list doesn't include it, and Lion users described it as how you now reach App Exposé. I found no 10.6 screenshot or text that settles whether 10.6 had it.
- **Open in a running app's template.** I could not determine when `OPEN` appears in the running-app template. It did not appear for any running app in the live dumps.
- **"Stop Running in Background".** I could not determine which apps or states show this string. It is new in recent macOS and undocumented.

---

## Q3. Special tiles: Finder, Trash, Launchpad/Apps, folders/stacks, documents, URLs, volumes, minimized windows, spacers, agent apps, and the Dock separator menu

### Takeaway
- **Finder** has no Quit. Its menu is the window list, then Finder's own items (New Finder Window, New Smart Folder, Find…, Go to Folder…, Connect to Server…, plus a folder list), then Options ▸ with only Assign To, then Show All Windows, Hide/Show, and, with Option, Relaunch.
- **Trash** is `Open`, separator, `Empty Trash`. Through Yosemite, holding Command made it `Secure Empty Trash`.
- **Dock separator** menu: `Turn Hiding On/Off`, `Turn Magnification On/Off`, `Position on Screen ▸`, `Minimize Using ▸`, separator, `Dock Settings…`. It was `Dock Preferences…` before macOS 13.

### Cited Findings
- **Finder template (`finder-running`):** `APPLICATION_NOT_RESPONDING [disabled]`, `───`, `OPTIONS ▸ {}` (empty in the template; the Dock adds the Assign To block), `───`, `SHOW_ALL_WINDOWS`, `HIDE [dynamic=0]`, `HIDE_OTHERS [dynamic=1]`, `SHOW`, `RELAUNCH`. There is no QUIT and no Keep in Dock, Open at Login or Show in Finder. `finder-quit` (Finder not running) is `OPTIONS ▸ {}`, `───`, `OPEN` — [Local plist](file:///System/Library/CoreServices/Dock.app/Contents/Resources/DockMenus.plist). The 2015 template is identical — [2015 plist gist](https://gist.github.com/Darkle/2ca4152ec3cbc90b8aa9).
- **Live Finder menu** — [Live AX dump, macOS 27.0.1]:
  ```
  ✓ <Finder window title>          (Dock window list)
  ───────────
  New Finder Window                (Finder's own applicationDockMenu)
  New Smart Folder
  Find…
  ───────────
  Go to Folder…
  Connect to Server…
  ───────────
  <folder> <folder> ✓<folder> …    (Finder-supplied list of 9 folder names, one checked)
  ───────────
  Options ▸
      Assign To / All Desktops / This Desktop / ✓None
  ───────────
  Show All Windows
  Hide            [Option → Hide Others]
  ```
  No Quit and no Relaunch appeared in the AX dump, which was taken without Option held.
- **Finder strings:** `N80 = New Finder Window`, `N81 = New Smart Folder`, `N82 = Find…`, `N83 = Go to Folder…`, `N84 = Connect to Server…`. Finder's binary implements `applicationDockMenu:` and has `_staticDockMenu` / `_dockMenu` ivars — [Finder strings](file:///System/Library/CoreServices/Finder.app/Contents/Resources/en.lproj/LocalizableMerged.strings).
- **Relaunch:** "hold Option as you invoke the contextual menu and choose Relaunch." "You can't quit or force quit the Finder" — [TidBITS 2017](https://tidbits.com/2017/03/06/macos-hidden-treasures-dominate-the-dock/). A 2012 description of the Finder Dock menu says it lets you create new folders, run searches, go to directories or servers, and show or hide Finder windows, with open Finder windows at the top — [MacTrast, 2012-05](https://www.mactrast.com/2012/05/mac-tip-right-clicking-in-the-dock/). MacMost lists "New Finder Window, Connect to Server, Go to Folder", jumping to recent folders, New Smart Folder and Find — [MacMost 2025](https://macmost.com/get-the-most-from-the-mac-dock-with-dock-menus.html).
- **Trash template (current):** `OPEN`, `───`, `EMPTY_TRASH [dynamic=0]`. English strings: "Open", "Empty Trash", with no ellipsis — [Local plist](file:///System/Library/CoreServices/Dock.app/Contents/Resources/DockMenus.plist), [Local strings](file:///System/Library/CoreServices/Dock.app/Contents/Resources/en.lproj/DockMenus.strings). Live: `Open`, `───`, `Empty Trash` — [Live AX dump, macOS 27.0.1].
- **Trash template (Yosemite):** `OPEN`, `───`, `EMPTY_TRASH [dynamic=0]`, `SECURE_EMPTY_TRASH [dynamic=2]` — [2015 plist gist](https://gist.github.com/Darkle/2ca4152ec3cbc90b8aa9). Holding Command while right-clicking the Dock Trash changes "Empty Trash" to "Secure Empty Trash" in the Lion era — [MacTrast: Secure Empty Trash in Lion](https://www.mactrast.com/?p=23886) and [How-To Geek](https://www.howtogeek.com/219430/how-to-securely-empty-the-trash-in-os-x/) *(both search excerpts)*. The option is absent from the macOS 27 template. Guides for Big Sur and Ventura show only plain Empty Trash — [MacKeeper](https://mackeeper.com/blog/secure-empty-trash-mac-big-sur) *(search excerpt)*.
- **Dock separator (`dock`) template:** `TURN_HIDING_ON`, `TURN_HIDING_OFF`, `TURN_MAG_ON`, `TURN_MAG_OFF`, `POSITION_ON_SCREEN ▸ {LEFT, BOTTOM, RIGHT}`, `MINIMIZE_USING ▸ {GENIE_EFFECT, SCALE_EFFECT}`, `───`, `DOCK_SETTINGS`. Strings: "Turn Hiding On/Off", "Turn Magnification On/Off", "Position on Screen" (Left/Bottom/Right), "Minimize Using" (Genie Effect/Scale Effect), "Dock Settings…" — [Local plist](file:///System/Library/CoreServices/Dock.app/Contents/Resources/DockMenus.plist). Live: `Turn Hiding Off`, `Turn Magnification Off`, `Position on Screen ▸ Left / ✓Bottom / Right`, `Minimize Using ▸ ✓Genie Effect / Scale Effect`, `───`, `Dock Settings…` — [Live AX dump, macOS 27.0.1]. Yosemite used the same template with `DOCK_PREFS` in place of `DOCK_SETTINGS` — [2015 plist gist](https://gist.github.com/Darkle/2ca4152ec3cbc90b8aa9). The divider menu offers turning hiding and magnification on/off, Dock position and minimize style — [MacTrast 2012](https://www.mactrast.com/2012/05/mac-tip-right-clicking-in-the-dock/). Older wording: "Control-clicking the divider… and choosing Dock Preferences" — [TidBITS 2017](https://tidbits.com/2017/03/06/macos-hidden-treasures-dominate-the-dock/). Apple: "You can Control-click the separator to access other actions from the shortcut menu" — [Apple Support](https://support.apple.com/guide/mac-help/use-the-dock-mh35859/mac).
- **Launchpad / Apps (`docklet`):** `REMOVE_FROM_DOCK`, `───`, `SHOW_NAME` ("Show %@"). Live on macOS 27 the Apps tile reads `Remove from Dock`, `───`, `Show Apps` — [Local plist](file:///System/Library/CoreServices/Dock.app/Contents/Resources/DockMenus.plist), [Live AX dump, macOS 27.0.1]. The 2015 template had the same `docklet`, plus a `dashboard` docklet: More Widgets…, Dashboard Preferences, Remove from Dock, `───`, Show Dashboard — [2015 plist gist](https://gist.github.com/Darkle/2ca4152ec3cbc90b8aa9).
- **Document tile (`file`):** `OPTIONS ▸ {REMOVE_FROM_DOCK, OPEN_AT_LOGIN, SHOW_IN_FINDER}`, `───`, `OPEN_FILENAME` ("Open “%@”") — [Local plist](file:///System/Library/CoreServices/Dock.app/Contents/Resources/DockMenus.plist). TidBITS: documents offer "Remove from Dock, Open at Login, and Show in Finder" — [TidBITS 2017](https://tidbits.com/2017/03/06/macos-hidden-treasures-dominate-the-dock/).
- **Folder/stack tile (`directory`):**
  ```
  Sort by (header): Name / Date Added / Date Modified / Date Created / Kind
  ───
  Display as (header): Folder / Stack
  ───
  View content as (header): Fan / Grid / List / Automatic
  ───
  Options ▸ {Remove from Dock, Show in Finder}
  ───
  Open "<folder>"
  ```
  The other folder variants: `folder` is `───`, `Options ▸ {Remove from Dock, Open at Login, Show in Finder}`, `───`, `Open "%@"`. `smartfolder` has Sort by Name/Date Modified/Date Created/Last Opened, Display as, View content as, then Remove from Dock — [Local plist](file:///System/Library/CoreServices/Dock.app/Contents/Resources/DockMenus.plist). A 10.6 description lists "Sort by, Display as, and View content as" with Fan/Grid/List/Automatic — [Deschamps blog 2010](https://dennisdeschampsblogs.blogspot.com/2010/09/mac-os-x-v106-mac-101-dock-dock-expose.html).
- **Other tiles:**
  - **URL:** `Remove from Dock`, `───`, `Open`.
  - **Volume:** `───`, `Options ▸ {Remove from Dock, Show in Finder}`, `Eject`, `───`, `Open`.
  - **Minimized-window tile (`minwindow`):** `───`, `Open "<window>"`.
  - **Spacer:** `Remove from Dock`.
  - **Handoff/Continuity tile:** `Open`.

  Source for all of the above: [Local plist](file:///System/Library/CoreServices/Dock.app/Contents/Resources/DockMenus.plist). "The contextual menu doesn't offer any options for minimized windows other than opening them" — [TidBITS 2017](https://tidbits.com/2017/03/06/macos-hidden-treasures-dominate-the-dock/).
- **Agent apps:** `LSUIElement` is "A Boolean value indicating whether the app is an agent app that runs in the background and doesn't appear in the Dock" — [Apple Developer: LSUIElement](https://developer.apple.com/documentation/bundleresources/information-property-list/lsuielement).
- **Finder and Trash cannot be removed:** "The Finder and Trash icons cannot be removed" — [Deschamps blog 2010](https://dennisdeschampsblogs.blogspot.com/2010/09/mac-os-x-v106-mac-101-dock-dock-expose.html). Strings also contain `TrashRemoveFromDock = Remove from Dock`, but its use is unknown — [Local Localizable.strings](file:///System/Library/CoreServices/Dock.app/Contents/Resources/en.lproj/Localizable.strings).

### Inferences
- **Reproducible Finder menu, current:** `[window list]`, `───`, `New Finder Window`, `New Smart Folder`, `Find…`, `───`, `Go to Folder…`, `Connect to Server…`, `[─── folder list]`, `───`, `Options ▸ [Assign To block only]`, `───`, `Show All Windows`, `Hide|Show` (Option: `Hide Others`), and with Option `Relaunch`. No Quit.
- The second, Finder-supplied folder list (nine names, one checked, while Finder reported one window) is most likely the tabs of the open Finder window, or recent folders as MacMost puts it. This is unverified.
- Relaunch did not appear in the AX dump even though it is in the template, and TidBITS says to hold Option while opening the menu. It is therefore probably added only when Option is held at open time, rather than being a live NSMenuItem alternate.
- A Launchpad tile on Sonoma/Sequoia would follow the same `docklet` template: `Remove from Dock`, `───`, `Show Launchpad`. This follows from `SHOW_NAME = Show %@` but was not observed.
- Separator menu: only one of each On/Off pair is shown, according to the current state.

### Gaps
- **Leopard Trash and separator menus.** I found no source that confirms them item by item. In particular, I could not confirm whether Leopard's Dock Trash had a Command-key Secure Empty Trash, or the exact Leopard separator-menu wording ("Dock Preferences…" is likely).
- **Launchpad on 14/15.** I did not observe the Launchpad tile menu on Sonoma or Sequoia directly.
- **Finder's dock menu in 10.5–10.8.** The exact items are unverified. MacTrast 2012 describes equivalents of the same commands.

---

## Q4. Exact wording, capitalization and ellipses (current macOS; Leopard/Snow Leopard wording)

### Takeaway
Current English Dock-menu strings, verbatim from the macOS 27.0.1 Dock:
- Options, Keep in Dock, Remove from Dock, Open at Login, Show in Finder
- Assign To, All Desktops, This Desktop, Desktop on Display %@, None
- Show All Windows, Show Recents
- Hide, Hide Others, Show, Quit, Force Quit, Relaunch, Open, Open “%@”
- Application Not Responding
- Empty Trash
- Turn Hiding On, Turn Magnification On, Position on Screen, Minimize Using, Genie Effect, Scale Effect, Dock Settings…

Only "Dock Settings…" and Finder's own Find…, Go to Folder… and Connect to Server… carry an ellipsis. "Empty Trash" has none.

### Cited Findings
- **Full current `en.lproj/DockMenus.strings`** — [Local strings](file:///System/Library/CoreServices/Dock.app/Contents/Resources/en.lproj/DockMenus.strings):
  - All Desktops; Application Not Responding; Assign To; Automatic; Bottom; Date Added; Date Created; Date Modified
  - Desktop on Display %@; Display as; Folder; Stack; Dock Settings…; Eject; Empty Trash; Fan; Force Quit
  - Genie Effect; Grid; Hide; Hide %@; Hide Others; Keep in Dock; Kind; Last Opened; Left; List
  - Minimize Using; Name; None; Open; Open at Login; Open “%@”; Open in Finder; Options
  - Desktop %@; Desktop %@ on Display %@; Position on Screen; Quit; Relaunch; Remove from Dock; Rename Stack; Right; Scale Effect
  - Show; Show All Windows; View content as; Show in Finder; Show %@; Show Recents; Sort by; Stop Running in Background
  - This Desktop; Turn Hiding Off; Turn Hiding On; Turn Magnification Off; Turn Magnification On
- **Leopard/Tiger-era Apple wording:** "Show In Finder", "Hide", "Quit", "Hide Others", "Force Quit", "Keep In Dock" — [Apple HIG 2008-06-09](https://archive.org/download/apple-hig/MacOSX_HIG_2008_06_09.pdf). The HIG uses title case ("Show In Finder", "Keep In Dock"). A 2008 Leopard user wrote "Remove From Dock, Open At Login, Show in Finder and Open" — [Yahoo Answers](https://answers.yahoo.com/question/index?qid=20081010092039AAwpVua) *(search excerpt)*.
- **Snow Leopard-era wording:** "Keep in Dock / Remove from Dock", "Open at Login", "Show in Finder", under "Options" — [Deschamps blog 2010](https://dennisdeschampsblogs.blogspot.com/2010/09/mac-os-x-v106-mac-101-dock-dock-expose.html), [Apple HIG 2009-08-20](https://archive.org/download/apple-hig/MacOSX_HIG_2009_08_20.pdf).
- **Older separator item:** `DOCK_PREFS` (Yosemite) became `DOCK_SETTINGS` = "Dock Settings…" (current) — [2015 plist gist](https://gist.github.com/Darkle/2ca4152ec3cbc90b8aa9), [Local plist](file:///System/Library/CoreServices/Dock.app/Contents/Resources/DockMenus.plist). Older user-facing name: "Dock Preferences" — [TidBITS 2017](https://tidbits.com/2017/03/06/macos-hidden-treasures-dominate-the-dock/).
- **Menu look:** Snow Leopard's Dock menus "have more options and have a new look… with a semi-transparent charcoal background and white text" — [Wikipedia: Dock (macOS)](https://en.wikipedia.org/wiki/Dock_(macOS)) (uncited claim on Wikipedia).
- **Mismatch in a third-party write-up:** TidBITS writes "Options > Show App in Finder" and calls the desktop section a "Desktops header" — [TidBITS 2017](https://tidbits.com/2017/03/06/macos-hidden-treasures-dominate-the-dock/). The Dock's actual strings are "Show in Finder" and "Assign To", so TidBITS appears to paraphrase.

### Inferences
- Apple's HIG title-cases "Show In Finder" and "Keep In Dock". The shipping UI from at least 10.6 onward uses lowercase "in", "at" and "from" ("Show in Finder", "Keep in Dock", "Open at Login", "Remove from Dock"). For a Leopard replica, the lowercase forms are the safer choice. The capitalized forms in the Yahoo excerpt are likely the poster's own typing.
- Dock string `OPEN_FILENAME` is `Open “%@”`, with curly quotes, for documents, folders and minimized windows. Apps use plain `Open`.
- `HIDE_NAME` ("Hide %@") and `SHOW_NAME` ("Show %@") exist. Only `SHOW_NAME` is used in the template (for docklets such as "Show Apps"). App menus use bare "Hide"/"Show".

### Gaps
- **10.5 and 10.7/10.8 string tables.** I could not obtain the actual `DockMenus.strings` from these versions, so their exact wording rests on Apple's HIG and secondary sources.
- **Menu appearance across versions.** I could not confirm when the dark charcoal Dock-menu style (10.6) ended. It is commonly believed to have lasted until 10.10 Yosemite, but this is unverified.

---

## Q5. Behavior details: opening the menu, choosing a window item, modifier keys

### Takeaway
- **Opening the menu.** Right-click and Control-click always open the menu. Click-and-hold opened the menu in 10.5. In 10.6 it triggered Dock Exposé plus a minimal menu without the window list or app items. From Lion onward it opens the normal menu again, which now includes Show All Windows.
- **Modifier keys.** Option swaps Hide→Hide Others and Quit→Force Quit, and turns Finder's Quit slot into Relaunch. Command swapped Empty Trash→Secure Empty Trash up to Yosemite.
- **Choosing a window item.** It activates the app and brings that window forward, un-minimizing it if needed (secondary sources only).

### Cited Findings
- **10.5:** "in 10.5 and earlier… clicking and holding on an item in the Dock would bring up a contextual menu." **10.6:** "Clicking and holding on an application icon in the Snow Leopard Dock invokes Exposé for that application." The hidden default `defaults write com.apple.Dock show-expose-menus -bool no; killall Dock` restores the menu-on-hold behavior. A commenter reports that on 10.6.2 click-and-hold shows Dock Exposé and the standard menu together — [Lap Cat Software, 2009-08-28](https://lapcatsoftware.com/blog/2009/08/28/snow-leopard-hidden-dock-preference/).
- **10.5 HIG:** "When a user presses and holds the mouse button on your application's tile in the Dock, a menu appears" — [Apple HIG 2008-06-09](https://archive.org/download/apple-hig/MacOSX_HIG_2008_06_09.pdf). The Tiger-era HIG adds: "Control-clicking an application icon in the Dock displays a menu… (Users can also press the application icon to get this menu.)" — [Apple HIG 2005](http://www.multimedialab.be/doc/tech/doc_osx_hi_guidelines.pdf).
- **10.6 HIG:** "When you press and hold the Dock icon of a running application, two things happen: Exposé displays all windows currently open in the application (including minimized windows); A minimal Dock menu appears." Control-click gives the full, customizable menu with windows and app items — [Apple HIG 2009-08-20](https://archive.org/download/apple-hig/MacOSX_HIG_2009_08_20.pdf). In 10.6, clicking a Dock icon while Exposé is active "displays a menu of options for an active application" — [Maria Langer, Snow Leopard Visual QuickStart sample, Peachpit](https://ptgmedia.pearsoncmg.com/imprint_downloads/peachpit/peachpit/downloads/snowleopard/0321635396_Sample.pdf).
- **10.7:** click-and-hold "just shows a menu list which includes that option [Show All Windows] inside the menu." "The options that appear when you hold down left mouse button is simply the same options" as right-click — [MacRumors forum, July 2011](https://forums.macrumors.com/threads/lion-osx-show-all-windows-like-snow-leopard.1197752/).
- **10.8-era HIG:** "Users can click and hold (or Control-click) an app's Dock icon to reveal the Dock menu. A Dock menu can contain app commands such as Open, Quit, and Hide, in addition to high-level options such as Show in Finder, Open at Login, and Assign to this Desktop." — [Apple HIG 2012-07-23](https://archive.org/download/apple-hig/MacOSX_HIG_2012_07_23.pdf).
- **Current:** "Access it by clicking and holding, Control-clicking, right-clicking, or force-touching the Dock icon" — [TidBITS 2017](https://tidbits.com/2017/03/06/macos-hidden-treasures-dominate-the-dock/). Apple: "Control-click an item to display its shortcut menu, then choose an action, such as Show Recents" — [Apple Support: Use the Dock on Mac](https://support.apple.com/guide/mac-help/use-the-dock-mh35859/mac).
- **Option alternates:** Hide→Hide Others, Quit→Force Quit — [Apple HIG 2008](https://archive.org/download/apple-hig/MacOSX_HIG_2008_06_09.pdf), [TidBITS 2017](https://tidbits.com/2017/03/06/macos-hidden-treasures-dominate-the-dock/), [MacMost 2025](https://macmost.com/get-the-most-from-the-mac-dock-with-dock-menus.html). "Force Quit is available for every application within the Dock… hold Option while right-clicking" — [MacTrast 2012](https://www.mactrast.com/2012/05/mac-tip-right-clicking-in-the-dock/). Finder gets Relaunch with Option — [TidBITS 2017](https://tidbits.com/2017/03/06/macos-hidden-treasures-dominate-the-dock/).
- **Command alternate (Trash, ≤ Yosemite):** Secure Empty Trash, from `SECURE_EMPTY_TRASH [dynamic=2]` — [2015 plist gist](https://gist.github.com/Darkle/2ca4152ec3cbc90b8aa9); [MacTrast Lion tip](https://www.mactrast.com/?p=23886) *(search excerpt)*.
- **Choosing a minimized window:** a diamond sits next to the minimized window in the Dock menu, and selecting it unminimizes the window — [MacMost](https://macmost.com/get-the-most-from-the-mac-dock-with-dock-menus.html) (the unminimize sentence is a *search excerpt*; the page I opened confirms the diamond).
- **Related click modifiers (not menu items):** "Option-click the current app's icon" hides the current app and switches to the previous one. "Option-Command-click" an icon switches to that app and hides all others. "Command-click the item's icon" shows it in Finder — [Apple Support: Use the Dock on Mac](https://support.apple.com/guide/mac-help/use-the-dock-mh35859/mac).
- **App-item selection mechanics:** the Dock messages the app, which should call `[NSApp sendAction:selector to:target from:nil]` — [Apple Developer: applicationDockMenu(_:)](https://developer.apple.com/documentation/appkit/nsapplicationdelegate/applicationdockmenu(_:)).

### Inferences
- Choosing a window in the Dock's window list most likely activates the app and orders that window front, un-minimizing it if it is minimized. This matches the general Dock rule that clicking an app brings its windows forward — [Apple HIG 2009, "The Dock"](https://archive.org/download/apple-hig/MacOSX_HIG_2009_08_20.pdf). I found no primary statement specific to the window-list item, though.
- Because Hide/Hide Others and Quit/Force Quit are NSMenuItem-style alternates, pressing or releasing Option while the menu is open should flip them live. Finder's Relaunch seems to need Option held when the menu opens.
- **Gaps relevant to OldMacDoc** (a Leopard-styled replica). The current OldMacDoc menu is Open, Show/Hide, Keep in Dock, Show in Finder, Icon ▸, Quit [Option: Force Quit]; Trash is Open, Empty Trash…. Compared with the original Dock, it lacks:
  - The **window list** (✓ main, ◆ minimized) at the top for running apps.
  - The app's **applicationDockMenu items**, placed after the window list and before the system items.
  - **Open at Login** (with ✓).
  - **Remove from Dock** wording for not-running pinned apps. Leopard showed Remove from Dock; 10.6+ toggles a ✓Keep in Dock.
  - **Hide Others** as the Option alternate of Hide.
  - **Application Not Responding** (disabled header), with Force Quit for hung apps.
  - **Recent documents** for apps with recents (Lion+).
  - **Show All Windows** and **Assign To** (Lion+ only, so optional for a Leopard look).
  - **Open is shown only when not running.** In the original Dock, "Open" appears only for not-running apps. Running apps get Hide/Show and Quit instead, with no Open.
  - **Finder's special menu:** New Finder Window, New Smart Folder, Find…, Go to Folder…, Connect to Server…, no Quit, Option → Relaunch.
  - **Dock separator menu.**
  - **Trash wording.** Apple's Dock Trash item is "Empty Trash" with no ellipsis.

### Gaps
- **Primary source for window-item behavior.** I found no Apple primary source describing what choosing a window item does, for example whether it switches Spaces or exits full screen.
- **Live modifier behavior.** I did not test live whether Option flips items while the menu is already open, versus only at open time. Screen-level verification would need a human or screen capture; the AX dump lists alternates without showing which is visible.
- **Force-touch and hold timing.** I could not confirm the release version for force-touch opening or the exact hold delay (Lion-era users mention about 1 second).
