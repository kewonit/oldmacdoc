import Foundation

/// One row of Apple's own Dock menu, as Accessibility reports it.
struct AppleMenuNode: Equatable {
    var title: String
    /// The mark Accessibility reports: "✓", "◆", "•", "-", or nil.
    var mark: String?
    var isEnabled = true
    /// Shown only while Option is held, in place of the row before it (Hide Others, Force Quit).
    var isOptionAlternate = false
    var children: [AppleMenuNode] = []

    /// NSMenu separators come through as disabled rows with no title.
    var isSeparator: Bool { title.isEmpty && !isEnabled && children.isEmpty }
}

/// What OldMacDoc takes from Apple's menu for an app. Everything OldMacDoc can do itself (Keep in
/// Dock, Show in Finder, Hide, Quit) is left out: Keep in Dock in particular is about Apple's own pins.
/// When a remembered copy of an app's menu in Apple's Dock is worth reading again. Each read flickers at
/// the screen's edge, so it's read again only once it may have changed: the app has been used since
/// (recent files, items that depend on what it's doing), or it's been a while (Music's controls).
enum AppleMenuFreshness {
    static let maxAge: TimeInterval = 600

    /// - Parameters:
    ///   - readAt: when it was read (seconds since the reference date), or nil if it never was. If the clock has
    ///     since been set back before it, it's read again.
    ///   - usedSince: the app has been in front, and left, since it was read.
    static func needsRead(readAt: TimeInterval?, usedSince: Bool, now: TimeInterval) -> Bool {
        guard let readAt, now >= readAt else { return true }
        return usedSince || now - readAt >= maxAge
    }
}

struct AppleMenuSnapshot: Equatable {
    var notResponding = false
    /// The app's own items, then its recent documents or folders, as groups of rows that replay Apple's.
    var groups: [[DockMenuItem]] = []
    var openAtLogin: Bool?
    var openAtLoginPath: AppleMenuPath?
    /// The Assign To title and its choices.
    var assignTo: [DockMenuItem] = []
    var canShowAllWindows = false
}

enum AppleMenuMirror {
    /// - Parameter windowTitles: the app's windows as it reports them now. The group of Apple's rows
    ///   that lists them is left out (OldMacDoc lists windows live from the app instead).
    /// - Parameter isRunning: only a running app's menu starts with its windows (one that isn't lists recent documents).
    static func parse(_ top: [AppleMenuNode], windowTitles: Set<String>, isRunning: Bool = true, strings: DockStrings) -> AppleMenuSnapshot {
        var snapshot = AppleMenuSnapshot()

        // Rows between separators, keeping each row's place in Apple's menu.
        var groups: [[(index: Int, node: AppleMenuNode)]] = [[]]
        for (i, node) in top.enumerated() {
            if node.isSeparator {
                if !(groups.last?.isEmpty ?? true) { groups.append([]) }
            } else {
                groups[groups.count - 1].append((i, node))
            }
        }
        groups.removeAll { $0.isEmpty }

        let optionsGroup = groups.firstIndex { g in g.contains { $0.node.title == strings[.options] && !$0.node.children.isEmpty } }
        // The rows OldMacDoc does itself end the part it takes: Options when there is one, else (Finder with a
        // single desktop has none) the group with Show All Windows, Hide, Quit or Open.
        let own: Set<String> = [strings[.showAllWindows], strings[.hide], strings[.show], strings[.hideOthers], strings[.quit],
                                strings[.forceQuit], strings[.open], strings[.relaunch]]
        let end = optionsGroup ?? groups.firstIndex { g in g.contains { own.contains($0.node.title) } } ?? groups.count
        let before = Array(groups[..<end])
        var middle = before

        if let first = middle.first, first.count == 1, !first[0].node.isEnabled,
           first[0].node.title == strings[.applicationNotResponding] {
            snapshot.notResponding = true
            middle.removeFirst()
        }
        if isRunning, let first = middle.first, looksLikeWindows(first.map(\.node), windowTitles: windowTitles) {
            middle.removeFirst()
        }
        // Apple's Keep in Dock and Remove from Dock are about Apple's own pins (the Apps tile puts Remove
        // from Dock at the top level): never offered.
        let applesPins: Set<String> = [strings[.keepInDock], strings[.removeFromDock]]
        snapshot.groups = middle.map { group in
            var rows: [DockMenuItem] = []
            for (i, node) in group where !applesPins.contains(node.title) {
                if node.isOptionAlternate, !rows.isEmpty {
                    rows[rows.count - 1].optionTitle = node.title
                    rows[rows.count - 1].optionCommand = .apple(AppleMenuPath(indexes: [i], titles: [node.title]))
                } else {
                    rows.append(item(node, path: AppleMenuPath(indexes: [i], titles: [node.title])))
                }
            }
            return rows
        }.filter { !$0.isEmpty }

        if let g = optionsGroup, let options = groups[g].first(where: { $0.node.title == strings[.options] }) {
            var inAssign = false
            for (j, child) in options.node.children.enumerated() {
                let path = AppleMenuPath(indexes: [options.index, j], titles: [options.node.title, child.title])
                if child.isSeparator { continue }
                if child.title == strings[.openAtLogin] {
                    snapshot.openAtLogin = child.mark == "✓"
                    snapshot.openAtLoginPath = path
                } else if child.title == strings[.assignTo] {
                    inAssign = true
                    snapshot.assignTo.append(.header(child.title))
                } else if inAssign {
                    snapshot.assignTo.append(item(child, path: path))
                }
            }
        }
        snapshot.canShowAllWindows = groups[end...].contains { $0.contains { $0.node.title == strings[.showAllWindows] } }
        return snapshot
    }

    /// Assign To as Apple's Dock words it, for when its menu hasn't been read: choosing a row replays Apple's
    /// row of the same name in Options.
    static func standardAssignTo(strings: DockStrings) -> [DockMenuItem] {
        [.header(strings[.assignTo])] + [DockStrings.Key.allDesktops, .thisDesktop, .none].map { key in
            .item(strings[key], .apple(AppleMenuPath(indexes: [0, 0], titles: [strings[.options], strings[key]])))
        }
    }

    /// Open at Login in Apple's Options, found by name when chosen.
    static func openAtLoginPath(strings: DockStrings) -> AppleMenuPath {
        AppleMenuPath(indexes: [0, 1], titles: [strings[.options], strings[.openAtLogin]])
    }

    /// Apple lists a running app's windows first. A group is that list if it marks the main window (✓) or a
    /// minimized one (◆), or names one of the app's windows (those on other desktops aren't always named).
    static func looksLikeWindows(_ nodes: [AppleMenuNode], windowTitles: Set<String>) -> Bool {
        nodes.contains { $0.mark == "◆" || $0.mark == "✓" || windowTitles.contains($0.title) }
    }

    private static func item(_ node: AppleMenuNode, path: AppleMenuPath) -> DockMenuItem {
        let mark: DockMenuItem.Mark = node.mark == "✓" ? .check : (node.mark == "◆" ? .diamond : .none)
        var row = DockMenuItem.item(node.title, .apple(path), mark: mark, enabled: node.isEnabled)
        if !node.children.isEmpty {
            row.submenu = node.children.enumerated().map { j, child in
                child.isSeparator ? .separator
                    : item(child, path: AppleMenuPath(indexes: path.indexes + [j], titles: path.titles + [child.title]))
            }
            row.command = .none
        }
        return row
    }
}
