import AppKit
import ApplicationServices

/// The Accessibility permission. With it, the dock's menus show each app's windows and its own
/// items, as the original Dock's did; without it they show everything else.
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

    /// Posted (distributed) whenever any app's Accessibility permission changes.
    static let changedNotification = Notification.Name("com.apple.accessibility.api")
}

// MARK: - Small Accessibility helpers

private func ax(_ element: AXUIElement, _ attribute: String) -> AnyObject? {
    var value: AnyObject?
    return AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success ? value : nil
}

private func axChildren(_ element: AXUIElement) -> [AXUIElement] {
    ax(element, kAXChildrenAttribute) as? [AXUIElement] ?? []
}

private func axRole(_ element: AXUIElement) -> String { ax(element, kAXRoleAttribute) as? String ?? "" }

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
/// on it. Opening Apple's menu puts it on screen for a frame or two where Apple's Dock waits, so each
/// app's menu is read once and remembered until the app quits or opens; choosing one of its rows opens
/// it once more (see reports/Original Dock right click menus.md).
final class AppleDockMenus {
    let strings: DockStrings
    private struct Entry {
        var pid: pid_t
        var snapshot: AppleMenuSnapshot
    }
    private var cache: [String: Entry] = [:]
    private var observers: [NSObjectProtocol] = []

    init(strings: DockStrings) {
        self.strings = strings
        let nc = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
            observers.append(nc.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
                if let id = app.bundleIdentifier { self?.cache[id] = nil }
                if let path = app.bundleURL?.path { self?.cache[path] = nil }
            })
        }
    }

    deinit { observers.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0) } }

    private static func key(_ item: DockModel.Item) -> String { item.bundleID ?? item.url.path }

    /// What Apple's menu offers for `item`: remembered, or read now (about 50 ms). `fresh` reads it again
    /// (to ask Apple's Dock whether an app that's slow to answer has really stopped responding).
    func snapshot(for item: DockModel.Item, pid: pid_t?, windowTitles: Set<String>, fresh: Bool = false) -> AppleMenuSnapshot? {
        guard AccessibilityAccess.isTrusted else { return nil }
        let remembered = cache[Self.key(item)].flatMap { $0.pid == (pid ?? 0) ? $0.snapshot : nil }
        if !fresh, let remembered { return remembered }
        // A slow app's menu takes Apple's Dock a moment longer: it waits on the app before saying it isn't responding.
        guard let tile = tile(for: item), let nodes = readMenu(of: tile, wait: fresh ? 2.5 : 0.25) else { return remembered }
        let snapshot = AppleMenuMirror.parse(nodes, windowTitles: windowTitles, isRunning: pid != nil, strings: strings)
        // While it isn't responding Apple's menu leaves out the app's own items: that isn't kept, so they're
        // back as soon as it recovers.
        guard !snapshot.notResponding else { return snapshot }
        cache[Self.key(item)] = Entry(pid: pid ?? 0, snapshot: snapshot)
        return snapshot
    }

    /// Chooses an item of Apple's menu for `item`. Updates what's remembered where the result is known
    /// (Open at Login, Assign To), so the next menu shows it without reading Apple's again.
    @discardableResult
    func press(_ path: AppleMenuPath, for item: DockModel.Item) -> Bool {
        guard AccessibilityAccess.isTrusted, let tile = tile(for: item) else { return false }
        AXUIElementPerformAction(tile, "AXShowMenu" as CFString)
        guard let menu = waitForMenu(of: tile) else { return false }
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
        remember(path, for: item)
        return true
    }

    /// App Exposé for `item`, as Apple's Show All Windows does.
    func showAllWindows(for item: DockModel.Item) {
        guard AccessibilityAccess.isTrusted, let tile = tile(for: item) else { return }
        AXUIElementPerformAction(tile, "AXShowExpose" as CFString)
    }

    private func remember(_ path: AppleMenuPath, for item: DockModel.Item) {
        guard var entry = cache[Self.key(item)] else { return }
        if path == entry.snapshot.openAtLoginPath, let on = entry.snapshot.openAtLogin {
            entry.snapshot.openAtLogin = !on
        } else if let chosen = entry.snapshot.assignTo.firstIndex(where: { $0.command == .apple(path) }) {
            for i in entry.snapshot.assignTo.indices where entry.snapshot.assignTo[i].kind == .item {
                entry.snapshot.assignTo[i].mark = i == chosen ? .check : .none
            }
        }
        cache[Self.key(item)] = entry
    }

    // MARK: Apple's Dock

    private func dockElement() -> AXUIElement? {
        guard let dock = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first else { return nil }
        let element = AXUIElementCreateApplication(dock.processIdentifier)
        AXUIElementSetMessagingTimeout(element, 0.3)
        return element
    }

    /// Apple's tile for `item`: by bundle identifier, then by location, then by name.
    private func tile(for item: DockModel.Item) -> AXUIElement? {
        guard let dock = dockElement(), let list = axChildren(dock).first(where: { axRole($0) == kAXListRole }) else { return nil }
        let tiles = axChildren(list).filter { (ax($0, kAXSubroleAttribute) as? String) == "AXApplicationDockItem" }
        let wanted = item.url.resolvingSymlinksInPath().standardizedFileURL.path
        var byName: AXUIElement?
        for tile in tiles {
            let url = (ax(tile, kAXURLAttribute) as? URL) ?? (ax(tile, kAXURLAttribute) as? NSURL).map { $0 as URL }
            if let url {
                if let id = item.bundleID, Bundle(url: url)?.bundleIdentifier == id { return tile }
                if url.resolvingSymlinksInPath().standardizedFileURL.path == wanted { return tile }
            }
            if byName == nil, (ax(tile, kAXTitleAttribute) as? String) == item.name { byName = tile }
        }
        return byName
    }

    private func waitForMenu(of tile: AXUIElement, wait: TimeInterval = 0.25) -> AXUIElement? {
        let deadline = Date().addingTimeInterval(wait)
        while Date() < deadline {
            if let menu = axChildren(tile).first(where: { axRole($0) == kAXMenuRole }) { return menu }
            usleep(2000)
        }
        return nil
    }

    private func readMenu(of tile: AXUIElement, wait: TimeInterval) -> [AppleMenuNode]? {
        AXUIElementPerformAction(tile, "AXShowMenu" as CFString)
        guard let menu = waitForMenu(of: tile, wait: wait) else { return nil }
        let nodes = Self.nodes(axChildren(menu), depth: 0)
        AXUIElementPerformAction(menu, kAXCancelAction as CFString)
        return nodes
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
