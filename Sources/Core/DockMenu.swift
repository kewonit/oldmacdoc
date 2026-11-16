import Foundation

// MARK: - Menu data

/// Replays one item of Apple's own Dock menu: where it was (indexes from the top, through any
/// submenu) and what it was called there, to check it's still the same item.
struct AppleMenuPath: Equatable, Hashable {
    var indexes: [Int]
    var titles: [String]
}

/// What choosing a menu row does. Plain data, so menus are built and tested without AppKit.
enum DockCommand: Equatable {
    case none
    // Apps
    case open, hide, unhide, hideOthers, quit, forceQuit, relaunch
    case toggleKeepInDock, showInFinder, toggleOpenAtLogin, showAllWindows
    /// A window from the live window list, by its place in that list.
    case focusWindow(Int)
    case apple(AppleMenuPath)
    case iconMode(IconMode), chooseIconImage, resetIcon
    // Finder, when Apple's menu can't be read
    case newFinderWindow, findInFinder
    // Trash
    case openTrash, emptyTrash
    // The separator
    case toggleAutoHide, toggleMagnification, dockSettings
    // Stacks
    case stackSort(StackSort), stackDisplay(StackDisplay), stackView(StackView)
    case removeStack, openStackFolder
    /// A file or folder shown in a List stack.
    case openFile(String)
}

struct DockMenuItem: Equatable {
    enum Kind: Equatable { case item, separator, header }
    enum Mark: Equatable { case none, check, diamond }

    var kind: Kind = .item
    var title = ""
    var mark: Mark = .none
    var isEnabled = true
    var command: DockCommand = .none
    var submenu: [DockMenuItem]?
    /// Shown instead of this row while Option is held (Hide Others, Force Quit).
    var optionTitle: String?
    var optionCommand: DockCommand?
    /// Shown only while Option is held (Finder's Relaunch).
    var optionOnly = false
    /// A file whose icon the row shows (List stacks).
    var iconPath: String?
    /// A folder whose contents become this row's submenu when it opens (List stacks).
    var folderPath: String?

    static func item(_ title: String, _ command: DockCommand, mark: Mark = .none, enabled: Bool = true) -> DockMenuItem {
        DockMenuItem(title: title, mark: mark, isEnabled: enabled, command: command)
    }
    static func header(_ title: String) -> DockMenuItem { DockMenuItem(kind: .header, title: title, isEnabled: false) }
    static let separator = DockMenuItem(kind: .separator, isEnabled: false)
    static func submenu(_ title: String, _ items: [DockMenuItem], enabled: Bool = true) -> DockMenuItem {
        DockMenuItem(title: title, isEnabled: enabled, submenu: items)
    }

    /// The title and command in effect with or without Option held.
    func resolved(option: Bool) -> (title: String, command: DockCommand) {
        if option, let t = optionTitle { return (t, optionCommand ?? command) }
        return (title, command)
    }

    var isSelectable: Bool { kind == .item && isEnabled }
}

/// The rows actually shown with or without Option held: Option-only rows come and go, and
/// separators never double up or end a menu.
func visibleRows(_ items: [DockMenuItem], option: Bool) -> [DockMenuItem] {
    var out: [DockMenuItem] = []
    for item in items where option || !item.optionOnly {
        if item.kind == .separator, out.isEmpty || out.last?.kind == .separator { continue }
        out.append(item)
    }
    while out.last?.kind == .separator { out.removeLast() }
    return out
}

// MARK: - Strings

/// Menu titles. The Dock's own words come from its string table, so they read exactly as Apple's
/// Dock does, in the same language; English is the fallback (and what tests use).
struct DockStrings {
    enum Key: String, CaseIterable {
        case allDesktops = "ALL_DESKTOPS"
        case applicationNotResponding = "APPLICATION_NOT_RESPONDING"
        case assignTo = "ASSIGN_TO"
        case automatic = "AUTOMATIC"
        case dateAdded = "DATE_ADDED"
        case dateCreated = "DATE_CREATED"
        case dateModified = "DATE_MODIFIED"
        case displayAs = "DISPLAY_AS"
        case displayAsFolder = "DISPLAY_AS_FOLDER"
        case displayAsStack = "DISPLAY_AS_STACK"
        case dockSettings = "DOCK_SETTINGS"
        case emptyTrash = "EMPTY_TRASH"
        case fan = "FAN"
        case forceQuit = "FORCE_QUIT"
        case grid = "GRID"
        case hide = "HIDE"
        case hideOthers = "HIDE_OTHERS"
        case keepInDock = "KEEP_IN_DOCK"
        case kind = "KIND"
        case list = "LIST"
        case name = "NAME"
        case none = "NONE"
        case open = "OPEN"
        case openFilename = "OPEN_FILENAME"
        case openAtLogin = "OPEN_AT_LOGIN"
        case openInFinder = "OPEN_IN_FINDER"
        case options = "OPTIONS"
        case quit = "QUIT"
        case relaunch = "RELAUNCH"
        case removeFromDock = "REMOVE_FROM_DOCK"
        case show = "SHOW"
        case showAllWindows = "SHOW_ALL_WINDOWS"
        case showAs = "SHOW_AS"
        case showInFinder = "SHOW_IN_FINDER"
        case sortBy = "SORT_BY"
        case thisDesktop = "THIS_DESKTOP"
        case turnHidingOff = "TURN_HIDING_OFF"
        case turnHidingOn = "TURN_HIDING_ON"
        case turnMagnificationOff = "TURN_MAG_OFF"
        case turnMagnificationOn = "TURN_MAG_ON"
    }

    static let englishTable: [Key: String] = [
        .allDesktops: "All Desktops", .applicationNotResponding: "Application Not Responding", .assignTo: "Assign To",
        .automatic: "Automatic", .dateAdded: "Date Added", .dateCreated: "Date Created", .dateModified: "Date Modified",
        .displayAs: "Display as", .displayAsFolder: "Folder", .displayAsStack: "Stack", .dockSettings: "Dock Settings…",
        .emptyTrash: "Empty Trash", .fan: "Fan", .forceQuit: "Force Quit", .grid: "Grid", .hide: "Hide",
        .hideOthers: "Hide Others", .keepInDock: "Keep in Dock", .kind: "Kind", .list: "List", .name: "Name",
        .none: "None", .open: "Open", .openFilename: "Open “%@”", .openAtLogin: "Open at Login",
        .openInFinder: "Open in Finder", .options: "Options", .quit: "Quit", .relaunch: "Relaunch",
        .removeFromDock: "Remove from Dock", .show: "Show", .showAllWindows: "Show All Windows",
        .showAs: "View content as", .showInFinder: "Show in Finder", .sortBy: "Sort by", .thisDesktop: "This Desktop",
        .turnHidingOff: "Turn Hiding Off", .turnHidingOn: "Turn Hiding On",
        .turnMagnificationOff: "Turn Magnification Off", .turnMagnificationOn: "Turn Magnification On",
    ]

    private let table: [Key: String]

    init(table: [Key: String] = [:]) {
        self.table = table
    }

    subscript(_ key: Key) -> String { table[key] ?? Self.englishTable[key] ?? key.rawValue }

    static let english = DockStrings()

    /// The Dock's own strings in the user's language, where it has them.
    static func system(dockPath: String = "/System/Library/CoreServices/Dock.app") -> DockStrings {
        guard let bundle = Bundle(path: dockPath) else { return .english }
        var table: [Key: String] = [:]
        for key in Key.allCases {
            let value = bundle.localizedString(forKey: key.rawValue, value: nil, table: "DockMenus")
            if value != key.rawValue, !value.isEmpty { table[key] = value }
        }
        return DockStrings(table: table)
    }
}

// MARK: - Building the menus

struct MenuWindow: Equatable {
    var title: String
    var isMain = false
    var isMinimized = false
}

/// Everything an app tile's menu depends on.
struct AppMenuState: Equatable {
    var isRunning = false
    var isFinder = false
    var isHidden = false
    var keepsInDock = true
    var notResponding = false
    /// The app's windows, read live.
    var windows: [MenuWindow] = []
    /// Rows from Apple's own menu for this app: its own items, recent documents or folders, in groups.
    var appleGroups: [[DockMenuItem]] = []
    /// Nil when it can't be known: the row is left out.
    var openAtLogin: Bool?
    var openAtLoginCommand: DockCommand = .toggleOpenAtLogin
    /// Open at Login is changed through Apple's Dock: without a tile there, it's shown but can't be chosen.
    var openAtLoginEnabled = true
    /// Apple's Assign To block (its title, then the choices), when there's more than one desktop.
    var assignTo: [DockMenuItem] = []
    var canShowAllWindows = false
    var iconMode: IconMode = .retro
    var hasIconOverride = false
}

/// The rows of each menu, in the original Dock's order: windows, the app's own items, Options,
/// then Show All Windows, Hide and Quit (see reports/Original Dock right click menus.md).
enum DockMenuBuilder {
    static let iconTitle = "Icon"

    static func app(_ s: AppMenuState, strings: DockStrings) -> [DockMenuItem] {
        var groups: [[DockMenuItem]] = []
        if s.isRunning, s.notResponding { groups.append([.header(strings[.applicationNotResponding])]) }
        if s.isRunning, !s.windows.isEmpty {
            groups.append(s.windows.enumerated().map { i, w in
                .item(w.title.isEmpty ? "Untitled" : w.title, .focusWindow(i),
                      mark: w.isMinimized ? .diamond : (w.isMain ? .check : .none))
            })
        }
        groups += s.appleGroups
        if s.isFinder, s.appleGroups.isEmpty {
            groups.append([.item("New Finder Window", .newFinderWindow), .item("Find…", .findInFinder)])
        }

        var options: [DockMenuItem] = []
        if !s.isFinder {
            if s.isRunning {
                options.append(.item(strings[.keepInDock], .toggleKeepInDock, mark: s.keepsInDock ? .check : .none))
            } else {
                options.append(.item(strings[.removeFromDock], .toggleKeepInDock))
            }
            if let login = s.openAtLogin {
                options.append(.item(strings[.openAtLogin], s.openAtLoginCommand, mark: login ? .check : .none, enabled: s.openAtLoginEnabled))
            }
            options.append(.item(strings[.showInFinder], .showInFinder))
        }
        if !s.assignTo.isEmpty {
            options.append(.separator)
            options += s.assignTo
        }
        options.append(.separator)
        options.append(.submenu(iconTitle, iconMenu(mode: s.iconMode, hasOverride: s.hasIconOverride)))
        groups.append([.submenu(strings[.options], visibleRows(options, option: true))])

        if s.isRunning {
            var tail: [DockMenuItem] = []
            if s.canShowAllWindows { tail.append(.item(strings[.showAllWindows], .showAllWindows)) }
            var hide = s.isHidden ? DockMenuItem.item(strings[.show], .unhide) : .item(strings[.hide], .hide)
            hide.optionTitle = strings[.hideOthers]
            hide.optionCommand = .hideOthers
            tail.append(hide)
            if s.isFinder {
                var relaunch = DockMenuItem.item(strings[.relaunch], .relaunch)
                relaunch.optionOnly = true
                tail.append(relaunch)
            } else if s.notResponding {
                tail.append(.item(strings[.forceQuit], .forceQuit))
            } else {
                var quit = DockMenuItem.item(strings[.quit], .quit)
                quit.optionTitle = strings[.forceQuit]
                quit.optionCommand = .forceQuit
                tail.append(quit)
            }
            groups.append(tail)
        } else {
            groups.append([.item(strings[.open], .open)])
        }
        return joined(groups)
    }

    static func iconMenu(mode: IconMode, hasOverride: Bool) -> [DockMenuItem] {
        [.item("Retro Finish", .iconMode(.retro), mark: mode == .retro ? .check : .none),
         .item("Original", .iconMode(.original), mark: mode == .original ? .check : .none),
         .separator,
         .item("Choose Image…", .chooseIconImage),
         .item("Reset", .resetIcon, enabled: hasOverride)]
    }

    static func trash(isFull: Bool, strings: DockStrings) -> [DockMenuItem] {
        [.item(strings[.open], .openTrash), .separator, .item(strings[.emptyTrash], .emptyTrash, enabled: isFull)]
    }

    /// The menu on the separator: the settings the original offered there that OldMacDoc has.
    static func separator(autoHide: Bool, magnification: Bool, strings: DockStrings) -> [DockMenuItem] {
        [.item(strings[autoHide ? .turnHidingOff : .turnHidingOn], .toggleAutoHide),
         .item(strings[magnification ? .turnMagnificationOff : .turnMagnificationOn], .toggleMagnification),
         .separator,
         .item(strings[.dockSettings], .dockSettings)]
    }

    static func stack(name: String, sort: StackSort, display: StackDisplay, view: StackView,
                      strings: DockStrings) -> [DockMenuItem] {
        let sorts: [(StackSort, DockStrings.Key)] = [(.name, .name), (.dateAdded, .dateAdded), (.dateModified, .dateModified),
                                                     (.dateCreated, .dateCreated), (.kind, .kind)]
        let views: [(StackView, DockStrings.Key)] = [(.fan, .fan), (.grid, .grid), (.list, .list), (.automatic, .automatic)]
        return [
            .submenu(strings[.sortBy], sorts.map { .item(strings[$0.1], .stackSort($0.0), mark: sort == $0.0 ? .check : .none) }),
            .submenu(strings[.displayAs], [
                .item(strings[.displayAsFolder], .stackDisplay(.folder), mark: display == .folder ? .check : .none),
                .item(strings[.displayAsStack], .stackDisplay(.stack), mark: display == .stack ? .check : .none),
            ]),
            .submenu(strings[.showAs], views.map { .item(strings[$0.1], .stackView($0.0), mark: view == $0.0 ? .check : .none) }),
            .separator,
            .submenu(strings[.options], [.item(strings[.removeFromDock], .removeStack), .item(strings[.showInFinder], .showInFinder)]),
            .separator,
            .item(strings[.openFilename].replacingOccurrences(of: "%@", with: name), .openStackFolder),
        ]
    }

    /// Groups joined with one separator between each pair of non-empty groups.
    static func joined(_ groups: [[DockMenuItem]]) -> [DockMenuItem] {
        var out: [DockMenuItem] = []
        for group in groups where !group.isEmpty {
            if !out.isEmpty { out.append(.separator) }
            out += group
        }
        return out
    }
}
