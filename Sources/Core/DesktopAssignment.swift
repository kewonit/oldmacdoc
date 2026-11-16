import Foundation

/// Which desktop an app is assigned to (the Dock's Options ▸ Assign To), read from macOS's own records in
/// `com.apple.spaces`, so the menu always shows the current choice without opening Apple's Dock menu.
enum DesktopAssignment: Equatable {
    case all, thisDesktop, otherDesktop, none

    /// - Parameters:
    ///   - bindings: `app-bindings`: bundle identifier → "AllSpaces" or a desktop's uuid (no entry: None).
    ///   - config: `SpacesDisplayConfiguration`, which lists each display's desktops and its current one.
    /// - Returns: the app's assignment, and how many desktops there are (full-screen apps' spaces don't count).
    static func parse(bindings: [String: Any], config: [String: Any]?, bundleID: String) -> (assignment: DesktopAssignment, desktops: Int) {
        let monitors = ((config?["Management Data"] as? [String: Any])?["Monitors"] as? [[String: Any]]) ?? []
        let desktops = monitors.reduce(0) { count, monitor in
            count + ((monitor["Spaces"] as? [[String: Any]]) ?? []).filter { ($0["type"] as? Int ?? 0) == 0 }.count
        }
        let current = Set(monitors.compactMap { ($0["Current Space"] as? [String: Any])?["uuid"] as? String })
        let wanted = bundleID.lowercased()
        guard let value = bindings.first(where: { $0.key.lowercased() == wanted })?.value as? String else {
            return (.none, desktops)
        }
        if value == "AllSpaces" { return (.all, desktops) }
        return (current.contains(value) ? .thisDesktop : .otherDesktop, desktops)
    }
}

extension AppleMenuMirror {
    /// Apple's Assign To rows, ticked by the live assignment: All Desktops, This Desktop or None. Any other row
    /// (a desktop on another display) is left unticked, as the assignment can't be matched to it by name.
    static func markAssignTo(_ rows: [DockMenuItem], assignment: DesktopAssignment, strings: DockStrings) -> [DockMenuItem] {
        rows.map { row in
            guard row.kind == .item else { return row }
            var marked = row
            let on: Bool
            switch row.title {
            case strings[.allDesktops]: on = assignment == .all
            case strings[.thisDesktop]: on = assignment == .thisDesktop
            case strings[.none]: on = assignment == .none
            default: on = false
            }
            marked.mark = on ? .check : .none
            return marked
        }
    }
}

/// Whether an app is one of the user's login items (Open at Login), matched by where it is, or by bundle id.
enum LoginItemMatch {
    static func matches(_ urls: [URL], appURL: URL, bundleID: String?, bundleIDOf: (URL) -> String? = { Bundle(url: $0)?.bundleIdentifier }) -> Bool {
        let path = appURL.resolvingSymlinksInPath().standardizedFileURL.path
        if urls.contains(where: { $0.resolvingSymlinksInPath().standardizedFileURL.path == path }) { return true }
        guard let bundleID else { return false }
        return urls.contains { $0.pathExtension == "app" && bundleIDOf($0) == bundleID }
    }
}
