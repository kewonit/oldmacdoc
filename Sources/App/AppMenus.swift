import AppKit
import ApplicationServices

/// The Accessibility permission. With it, the dock's menus show each app's windows and its own
/// items, as the original Dock's did, and maximised windows stop above the dock while it doesn't hide
/// (DockClearanceController); without it the menus show everything else.
enum AccessibilityAccess {
    static var isTrusted: Bool { AXIsProcessTrusted() }

    /// Shows the system's request (once per call; macOS remembers a refusal in System Settings).
    static func ask() {
        _ = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
    }

    static func openSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

}

// MARK: - An app's windows

/// An app's windows, read from the app itself (no flash, always current).
enum AppWindows {
    struct Window {
        let element: AXUIElement
        let info: MenuWindow
    }

    /// The app's document windows, front to back, minimized ones included. Nil when the app didn't
    /// answer in time: it isn't responding.
    static func read(pid: pid_t, appName: String) -> [Window]? {
        guard AccessibilityAccess.isTrusted else { return [] }
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.3)
        var value: AnyObject?
        let error = AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &value)
        if error == .cannotComplete { return nil }
        guard error == .success, let windows = value as? [AXUIElement] else { return [] }
        return windows.compactMap { w in
            // A timeout set on the app's element isn't inherited by its windows' elements.
            AXUIElementSetMessagingTimeout(w, 0.3)
            let minimized = ax(w, kAXMinimizedAttribute) as? Bool ?? false
            let subrole = ax(w, kAXSubroleAttribute) as? String
            guard minimized || subrole == kAXStandardWindowSubrole || subrole == kAXDialogSubrole else { return nil }
            let title = ax(w, kAXTitleAttribute) as? String ?? ""
            return Window(element: w, info: MenuWindow(title: title.isEmpty ? appName : title,
                                                      isMain: ax(w, kAXMainAttribute) as? Bool ?? false,
                                                      isMinimized: minimized))
        }
    }

    /// Brings one window forward, out of the Dock if it was minimized, and its app with it.
    static func focus(_ window: AXUIElement, of app: NSRunningApplication) {
        if app.isHidden { app.unhide() }
        AXUIElementSetAttributeValue(window, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
        AXUIElementSetAttributeValue(window, kAXMainAttribute as CFString, kCFBooleanTrue)
        AXUIElementPerformAction(window, kAXRaiseAction as CFString)
        app.activate(options: [])
    }
}

// MARK: - Apple's own Dock menus

/// Reads each app's menu from Apple's Dock, which is still running while parked, and replays a choice
/// on it. Opening Apple's menu puts it on screen for a frame or two, at the middle of the edge where Apple's
/// Dock waits, so it's never opened just to show a menu: each app's is read while the display is asleep or
/// the Mac is locked, and remembered (read again then only once it may have changed, `AppleMenuFreshness`).
/// Choosing one of its rows opens it once more (see reports/Original Dock right click menus.md), and so does
/// asking whether an app that's slow to answer has stopped responding.
///
/// Everything that opens Apple's menu runs in turn on one background queue, so the dock keeps drawing
/// while Apple's Dock answers and two openings never overlap. Results come back on the main thread.
final class AppleDockMenus {
    let strings: DockStrings
    /// Remembered by app and by whether it was running (a running app's menu lists other things).
    private struct Entry {
        var snapshot: AppleMenuSnapshot
        /// When it was read (seconds since the reference date, so it ages while the Mac sleeps too).
        var readAt: TimeInterval
        /// The app has been opened, used or quit since this was read.
        var usedSince = false
    }
    private var cache: [String: Entry] = [:]
    /// When each app was last opened, used or quit, so a read that was under way then doesn't count as current.
    private var touchedAt: [String: TimeInterval] = [:]
    private var observers: [(NotificationCenter, NSObjectProtocol)] = []
    /// Reads under way, by item and kind, with everyone waiting for them.
    private var reading: [String: [(AppleMenuSnapshot?) -> Void]] = [:]
    private let queue = DispatchQueue(label: "com.kewonit.oldmacdoc.apple-dock-menus", qos: .userInitiated)
    private let onScreen = AppleMenuOnScreen()
    /// How many times Apple's menu has been asked to open (each one flickers), for testing.
    var opens: Int { onScreen.opens }
    /// How the last read of each app's menu went, for testing.
    private(set) var results: [String: String] = [:]
    /// The screen going out of sight and back, for testing.
    private(set) var screenEvents: [String] = []

    /// Apple's menu is up, or has only just closed. While it's up it has the keyboard, and when it closes the
    /// keyboard goes back to the app in front, not to the dock's own menu, so that menu shouldn't take losing
    /// it then as a sign to close.
    var hasKeyboard: Bool { onScreen.hasKeyboard }

    /// Apple's tile for the menu being opened: found once, used for the checks that follow.
    private var tileMemo: (key: String, at: TimeInterval, tile: AXUIElement?)?

    init(strings: DockStrings) {
        self.strings = strings
        // A ceiling for every Accessibility call this app makes (elements it doesn't set one on otherwise wait
        // about 6 s for an app that has stopped answering).
        AXUIElementSetMessagingTimeout(AXUIElementCreateSystemWide(), 1.0)
        let nc = NSWorkspace.shared.notificationCenter
        // Opening, using or quitting an app can change its menu (recent files, what it's doing): what's remembered
        // is kept, to show meanwhile, but read again next time the screen can't be seen.
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification,
                     NSWorkspace.didDeactivateApplicationNotification] {
            observers.append((nc, nc.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
                self?.touch(app)
            }))
        }
        // These only prompt a look: whether the screen can be seen is asked of macOS each time
        // (`screenIsHidden`). A sign it's coming back is trusted at once, though, and stops the reading.
        observers.append((nc, nc.addObserver(forName: NSWorkspace.screensDidSleepNotification, object: nil, queue: .main) { [weak self] _ in
            self?.screenMayBeHidden("display asleep")
        }))
        observers.append((nc, nc.addObserver(forName: NSWorkspace.screensDidWakeNotification, object: nil, queue: .main) { [weak self] _ in
            self?.screenShowing("display awake")
        }))
        let dnc = DistributedNotificationCenter.default()
        for name in ["com.apple.screenIsLocked", "com.apple.screensaver.didstart"] {
            observers.append((dnc, dnc.addObserver(forName: .init(name), object: nil, queue: .main) { [weak self] _ in
                self?.screenMayBeHidden(name)
            }))
        }
        for name in ["com.apple.screenIsUnlocked", "com.apple.screensaver.didstop"] {
            observers.append((dnc, dnc.addObserver(forName: .init(name), object: nil, queue: .main) { [weak self] _ in
                self?.screenShowing(name)
            }))
        }
        // Started while nobody can see the screen (an update installed while the Mac is locked).
        screenMayBeHidden("start")
    }

    deinit { observers.forEach { $0.0.removeObserver($0.1) } }

    private static func key(_ item: DockModel.Item) -> String { item.bundleID ?? item.url.path }
    private static func key(_ base: String, running: Bool) -> String { base + (running ? "|running" : "|not running") }
    private static func key(_ item: DockModel.Item, pid: pid_t?) -> String { key(key(item), running: pid != nil) }
    private static var now: TimeInterval { Date().timeIntervalSinceReferenceDate }

    /// `app` was opened, used or quit: what's remembered of its menu may be out of date.
    private func touch(_ app: NSRunningApplication) {
        for base in [app.bundleIdentifier, app.bundleURL?.path].compactMap({ $0 }) {
            for running in [true, false] {
                let key = Self.key(base, running: running)
                touchedAt[key] = Self.now
                cache[key]?.usedSince = true
            }
        }
    }

    /// Remembers what was read for `key`, asked for at `asked`: still out of date if the app was touched since.
    private func store(_ snapshot: AppleMenuSnapshot, for key: String, asked: TimeInterval) {
        cache[key] = Entry(snapshot: snapshot, readAt: Self.now, usedSince: (touchedAt[key] ?? -.infinity) >= asked)
    }

    /// What was last read from Apple's menu for `item`, running (with `pid`) or not, without reading it again.
    func remembered(for item: DockModel.Item, pid: pid_t?) -> AppleMenuSnapshot? {
        cache[Self.key(item, pid: pid)]?.snapshot
    }

    /// Whether what's remembered for `item` is missing or may be out of date.
    func needsRead(for item: DockModel.Item, pid: pid_t?) -> Bool {
        guard AccessibilityAccess.isTrusted else { return false }
        let entry = cache[Self.key(item, pid: pid)]
        return AppleMenuFreshness.needsRead(readAt: entry?.readAt, usedSince: entry?.usedSince ?? false, now: Self.now)
    }

    // MARK: Reading while the screen can't be seen

    /// The dock's apps, with each running one's process: those whose menus are read while the screen can't be
    /// seen. Empty when App items in menus is off.
    var appsToRead: (() -> [(item: DockModel.Item, pid: pid_t?)])?
    private var hiddenWork: DispatchWorkItem?
    private var readingWhileHidden = false
    /// Goes up whenever the screen may be about to show again: reading stops, and a read waiting its turn on
    /// the queue doesn't open Apple's menu.
    private let showings = LockedCounter()

    /// Whether nobody can see the screen now: every display asleep, or the Mac locked (the lock screen is drawn
    /// above Apple's menu). Asked of macOS each time rather than kept from notifications, as one can be missed
    /// (nothing says the screen saver has gone if it's ended unusually). A screen saver that doesn't lock
    /// doesn't count. Safe to call from any thread.
    static func screenIsHidden() -> Bool {
        if (CGSessionCopyCurrentDictionary() as? [String: Any])?["CGSSessionScreenIsLocked"] as? Bool == true { return true }
        var count: UInt32 = 0
        var displays = [CGDirectDisplayID](repeating: 0, count: 32)
        guard CGGetOnlineDisplayList(32, &displays, &count) == .success, count > 0 else { return false }
        return displays.prefix(Int(count)).allSatisfy { CGDisplayIsAsleep($0) != 0 }
    }

    private func note(_ event: String) {
        let at = String(format: "%.2f", ProcessInfo.processInfo.systemUptime)
        screenEvents = Array((screenEvents + ["\(at) \(event)"]).suffix(20))
    }

    private func screenShowing(_ why: String) {
        showings.increment()
        hiddenWork?.cancel()
        note("\(why): stop")
    }

    private func screenMayBeHidden(_ why: String) {
        hiddenWork?.cancel()
        // A moment for the display to go dark or the lock screen to come up completely, then a look.
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            let hidden = Self.screenIsHidden()
            self.note("\(why): hidden \(hidden)")
            if hidden { self.readWhileHidden() }
        }
        hiddenWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1, execute: work)
    }

    /// Reads, one app at a time, every menu that's missing or may be out of date, and stops as soon as the
    /// screen may be seen again. `anyway`: even while it can be (for testing).
    func readWhileHidden(anyway: Bool = false) {
        guard !readingWhileHidden, AccessibilityAccess.isTrusted, let apps = appsToRead?(), !apps.isEmpty else { return }
        // The app in front isn't left before the screen goes, but it's the one most likely to have changed.
        if let front = NSWorkspace.shared.frontmostApplication { touch(front) }
        var left = apps.filter { needsRead(for: $0.item, pid: $0.pid) }.map(\.item.id)
        readingWhileHidden = true
        let showing = showings.value
        func next() {
            guard anyway || (Self.screenIsHidden() && showings.value == showing), !left.isEmpty else {
                readingWhileHidden = false
                // Stopped as the screen began to come back, but it's gone again (woken and slept mid-read): start over.
                if !left.isEmpty, !anyway, Self.screenIsHidden() { screenMayBeHidden("again") }
                return
            }
            // As it is now: it may have opened or quit while the others were read.
            let id = left.removeFirst()
            guard let app = appsToRead?().first(where: { $0.item.id == id }), needsRead(for: app.item, pid: app.pid) else {
                next()
                return
            }
            read(app.item, pid: app.pid, windowTitles: nil, fresh: false, whileHidden: anyway ? nil : showing) { _ in next() }
        }
        next()
    }

    // MARK: Opening Apple's menu

    /// Reads Apple's menu for `item` (about 50 ms) without holding up the main thread, and calls `done` there
    /// with it, or nil when it couldn't be read. `fresh` waits longer, to let Apple's Dock say whether an app
    /// that's slow to answer has really stopped responding. `windowTitles`: the app's windows, asked of it
    /// first if nil (and if it doesn't answer, its menu isn't read: the windows couldn't be told from its own
    /// items). `whileHidden`: only if, when its turn comes, the screen still can't be seen and hasn't shown
    /// signs of coming back since `showings` was this. Asking again while a read is under way waits for it.
    func read(_ item: DockModel.Item, pid: pid_t?, windowTitles: Set<String>?, fresh: Bool, whileHidden: Int? = nil,
              done: @escaping (AppleMenuSnapshot?) -> Void) {
        guard AccessibilityAccess.isTrusted else { done(nil); return }
        let key = Self.key(item, pid: pid)
        let job = "\(key)|\(fresh)|\(whileHidden != nil)"
        if reading[job] != nil { reading[job]?.append(done); return }
        reading[job] = [done]
        let strings = strings
        let onScreen = onScreen
        let showings = showings
        let stillHidden = { whileHidden.map { Self.screenIsHidden() && showings.value == $0 } ?? true }
        let queue = queue
        let asked = Self.now
        queue.async { [weak self] in
            var outcome = "skipped: the screen can be seen"
            var snapshot: AppleMenuSnapshot?
            var titles = windowTitles
            if titles == nil {
                titles = pid.map { AppWindows.read(pid: $0, appName: item.name).map { Set($0.map(\.info.title)) } } ?? []
            }
            if titles == nil {
                outcome = "skipped: the app didn't answer"
            } else if stillHidden() {
                if let tile = Self.findTile(for: item) {
                    // Nobody's waiting on a read while the screen is hidden: Apple's Dock gets a little longer.
                    let wait: TimeInterval = fresh ? 2.5 : whileHidden != nil ? 1 : 0.25
                    let shownAt = ProcessInfo.processInfo.systemUptime
                    if let nodes = Self.readMenu(of: tile, wait: wait, onScreen: onScreen, queue: queue, unless: { !stillHidden() }) {
                        snapshot = AppleMenuMirror.parse(nodes, windowTitles: titles ?? [], isRunning: pid != nil, strings: strings)
                        outcome = (snapshot!.notResponding ? "not responding" : "\(snapshot!.groups.count) groups")
                            + String(format: " (opened after %.2f)", shownAt)
                    } else {
                        outcome = stillHidden() ? "no menu" : "skipped: the screen can be seen"
                    }
                } else {
                    outcome = "no tile"
                }
            }
            DispatchQueue.main.async {
                guard let self else { return }
                self.results[key] = outcome
                // While it isn't responding Apple's menu leaves out the app's own items: that isn't kept, so they're
                // back as soon as it recovers.
                if let snapshot, !snapshot.notResponding { self.store(snapshot, for: key, asked: asked) }
                let waiting = self.reading.removeValue(forKey: job) ?? []
                waiting.forEach { $0(snapshot) }
            }
        }
    }

    /// Chooses an item of Apple's menu for `item`, calling `done` on the main thread with whether it was
    /// chosen. Apple's menu is open anyway to do that, so what's remembered is read again first (no extra
    /// flicker): the app's own items and recent files stay current as you use them.
    func press(_ path: AppleMenuPath, for item: DockModel.Item, pid: pid_t?, windowTitles: Set<String>,
               done: @escaping (Bool) -> Void) {
        guard AccessibilityAccess.isTrusted else { done(false); return }
        let key = Self.key(item, pid: pid)
        let strings = strings
        let onScreen = onScreen
        let asked = Self.now
        let queue = queue
        queue.async { [weak self] in
            var fresh: AppleMenuSnapshot?
            var pressed = false
            if let tile = Self.findTile(for: item) {
                // You chose something: worth waiting longer for a slow app's menu.
                if let menu = Self.openMenu(of: tile, wait: 1.5, onScreen: onScreen, queue: queue) {
                    var snapshot = AppleMenuMirror.parse(Self.nodes(axChildren(menu), depth: 0), windowTitles: windowTitles,
                                                         isRunning: pid != nil, strings: strings)
                    // Read before the press: Open at Login is about to change.
                    if path.titles.last == strings[.openAtLogin], let on = snapshot.openAtLogin { snapshot.openAtLogin = !on }
                    fresh = snapshot
                    pressed = Self.press(path, in: menu)
                    // Pressed, Apple's menu closes by itself; otherwise `press` cancelled it.
                    Self.waitUntilClosed(menu, of: tile)
                    onScreen.closed()
                }
            }
            DispatchQueue.main.async {
                guard let self else { return }
                if let fresh, !fresh.notResponding { self.store(fresh, for: key, asked: asked) }
                LoginItems.invalidate()
                done(pressed)
            }
        }
    }

    /// Whether Apple's Dock has a tile for `item` (found without opening anything).
    func hasTile(for item: DockModel.Item) -> Bool {
        AccessibilityAccess.isTrusted && tile(for: item) != nil
    }

    /// App Exposé for `item`, as Apple's Show All Windows does.
    func showAllWindows(for item: DockModel.Item) {
        guard AccessibilityAccess.isTrusted, let tile = tile(for: item) else { return }
        AXUIElementPerformAction(tile, "AXShowExpose" as CFString)
    }

    // MARK: Apple's Dock

    /// Apple's tile for `item`, remembered for a moment, as opening one menu asks several times.
    private func tile(for item: DockModel.Item) -> AXUIElement? {
        let now = ProcessInfo.processInfo.systemUptime
        if let memo = tileMemo, memo.key == Self.key(item), now - memo.at < 1 { return memo.tile }
        let found = Self.findTile(for: item)
        tileMemo = (Self.key(item), now, found)
        return found
    }

    // What follows touches nothing but `AppleMenuOnScreen`, so it runs on the background queue (the ones that
    // open Apple's menu only there) as well as the main thread.

    private static func dockElement() -> AXUIElement? {
        guard let dock = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first else { return nil }
        let element = AXUIElementCreateApplication(dock.processIdentifier)
        AXUIElementSetMessagingTimeout(element, 0.3)
        return element
    }

    /// Apple's tile for `item`: the one at the same location; else the one with the same bundle identifier
    /// (an app that has moved); else, only among tiles that don't say where they are, the one with its name.
    private static func findTile(for item: DockModel.Item) -> AXUIElement? {
        guard let dock = dockElement(), let list = axChildren(dock).first(where: { axRole($0) == kAXListRole }) else { return nil }
        let tiles = axChildren(list).filter { (ax($0, kAXSubroleAttribute) as? String) == "AXApplicationDockItem" }
        let wanted = item.url.resolvingSymlinksInPath().standardizedFileURL.path
        var byID: AXUIElement?, byName: AXUIElement?
        for tile in tiles {
            let url = (ax(tile, kAXURLAttribute) as? URL) ?? (ax(tile, kAXURLAttribute) as? NSURL).map { $0 as URL }
            if let url {
                if url.resolvingSymlinksInPath().standardizedFileURL.path == wanted { return tile }
                if byID == nil, let id = item.bundleID, Bundle(url: url)?.bundleIdentifier == id { byID = tile }
            } else if byName == nil, (ax(tile, kAXTitleAttribute) as? String) == item.name {
                byName = tile
            }
        }
        return byID ?? byName
    }

    /// Presses the row at `path` in Apple's open `menu`, found by title nearest its old place; closes the
    /// menu if it isn't there.
    private static func press(_ path: AppleMenuPath, in menu: AXUIElement) -> Bool {
        var level = axChildren(menu)
        var target: AXUIElement?
        for (depth, title) in path.titles.enumerated() {
            let want = depth < path.indexes.count ? path.indexes[depth] : 0
            let matches = level.indices.filter { (ax(level[$0], kAXTitleAttribute) as? String) == title }
            guard let i = matches.min(by: { abs($0 - want) < abs($1 - want) }) else { break }
            if depth == path.titles.count - 1 {
                target = level[i]
            } else if let sub = axChildren(level[i]).first(where: { axRole($0) == kAXMenuRole }) {
                level = axChildren(sub)
            } else {
                break
            }
        }
        guard let target, AXUIElementPerformAction(target, kAXPressAction as CFString) == .success else {
            AXUIElementPerformAction(menu, kAXCancelAction as CFString)
            return false
        }
        return true
    }

    private static func shownMenu(of tile: AXUIElement) -> AXUIElement? {
        axChildren(tile).first(where: { axRole($0) == kAXMenuRole })
    }

    /// Opens Apple's menu on `tile` and waits up to `wait` for it, a moment after the last one closed (Apple's
    /// Dock ignores a menu asked for while the last is still closing). Nil if it didn't come, or if `unless` says
    /// not to open it after all; one that comes late is watched for a little longer and closed. Background
    /// queue only: one menu at a time.
    private static func openMenu(of tile: AXUIElement, wait: TimeInterval, onScreen: AppleMenuOnScreen,
                                 queue: DispatchQueue, unless: @escaping () -> Bool = { false }) -> AXUIElement? {
        let gap = AppleMenuOnScreen.gap - onScreen.sinceClosed
        if gap > 0 { usleep(useconds_t(gap * 1_000_000)) }
        guard !unless() else { return nil }
        onScreen.opened()
        AXUIElementPerformAction(tile, "AXShowMenu" as CFString)
        // Waits for it, but stops waiting at once if `unless` turns (the screen is coming back).
        if let menu = poll(for: wait, { shownMenu(of: tile) }, until: unless) {
            guard unless() else { return menu }
            close(menu, of: tile, onScreen: onScreen)
            return nil
        }
        // Too late to use, but it may still come: if it does, close it, so it isn't left at the edge of the screen;
        // and look again a while later, in case Apple's Dock is slower still (just restarted, or busy).
        if let late = poll(for: 1.5, { shownMenu(of: tile) }) {
            close(late, of: tile, onScreen: onScreen)
            return nil
        }
        onScreen.closed()
        for delay in [3.0, 8.0] {
            queue.asyncAfter(deadline: .now() + delay) {
                guard let stray = shownMenu(of: tile) else { return }
                close(stray, of: tile, onScreen: onScreen)
            }
        }
        return nil
    }

    private static func close(_ menu: AXUIElement, of tile: AXUIElement, onScreen: AppleMenuOnScreen) {
        AXUIElementPerformAction(menu, kAXCancelAction as CFString)
        waitUntilClosed(menu, of: tile)
        onScreen.closed()
    }

    /// Reads Apple's menu on `tile` and closes it again.
    private static func readMenu(of tile: AXUIElement, wait: TimeInterval, onScreen: AppleMenuOnScreen, queue: DispatchQueue,
                                 unless: @escaping () -> Bool) -> [AppleMenuNode]? {
        guard let menu = openMenu(of: tile, wait: wait, onScreen: onScreen, queue: queue, unless: unless) else { return nil }
        let nodes = Self.nodes(axChildren(menu), depth: 0)
        close(menu, of: tile, onScreen: onScreen)
        return nodes
    }

    /// Waits (briefly) for Apple's menu on `tile` to have gone.
    private static func waitUntilClosed(_ menu: AXUIElement, of tile: AXUIElement) {
        _ = poll(for: 0.5) { shownMenu(of: tile) == nil ? true : nil }
    }

    /// Asks `check` every 2 ms for up to `seconds`, or until `until` says to stop.
    private static func poll<T>(for seconds: TimeInterval, _ check: () -> T?, until: () -> Bool = { false }) -> T? {
        let deadline = Date().addingTimeInterval(seconds)
        repeat {
            if let found = check() { return found }
            if until() { return nil }
            usleep(2000)
        } while Date() < deadline
        return nil
    }

    private static func nodes(_ items: [AXUIElement], depth: Int) -> [AppleMenuNode] {
        items.map { item in
            let modifiers = ax(item, kAXMenuItemCmdModifiersAttribute) as? Int ?? 0
            var children: [AppleMenuNode] = []
            if depth < 2, let sub = axChildren(item).first(where: { axRole($0) == kAXMenuRole }) {
                children = nodes(axChildren(sub), depth: depth + 1)
            }
            // Option-only rows: the Option modifier and no Command (kAXMenuItemModifierOption | NoCommand).
            return AppleMenuNode(title: ax(item, kAXTitleAttribute) as? String ?? "",
                                 mark: ax(item, kAXMenuItemMarkCharAttribute) as? String,
                                 isEnabled: ax(item, kAXEnabledAttribute) as? Bool ?? true,
                                 isOptionAlternate: modifiers & 2 != 0 && modifiers & 8 != 0,
                                 children: children)
        }
    }
}

/// A count read on one thread and changed on another.
final class LockedCounter {
    private let lock = NSLock()
    private var stored = 0
    var value: Int {
        lock.lock()
        defer { lock.unlock() }
        return stored
    }

    func increment() {
        lock.lock()
        stored += 1
        lock.unlock()
    }
}

/// Whether Apple's menu is on screen, and when it last closed, as the background queue opens and closes it.
/// Read from any thread.
final class AppleMenuOnScreen {
    /// How long after one of Apple's menus closes before another is asked for.
    static let gap: TimeInterval = 0.4
    private let lock = NSLock()
    private var isUp = false
    private var closedAt: TimeInterval = -.infinity

    private func locked<T>(_ body: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }

    private var openCount = 0
    /// How many times it has been asked to open.
    var opens: Int { locked { openCount } }
    func opened() { locked { isUp = true; openCount += 1 } }
    func closed() { locked { isUp = false; closedAt = ProcessInfo.processInfo.systemUptime } }
    var sinceClosed: TimeInterval { locked { ProcessInfo.processInfo.systemUptime - closedAt } }
    /// Up, or closed less than 0.3 s ago (the keyboard takes a moment to come back).
    var hasKeyboard: Bool { locked { isUp || ProcessInfo.processInfo.systemUptime - closedAt < 0.3 } }
}
