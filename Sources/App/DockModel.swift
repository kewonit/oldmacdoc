import AppKit

/// Pinned apps (persisted) plus running apps, in dock order.
final class DockModel {
    struct Item: Equatable {
        var id: String
        var url: URL
        var bundleID: String?
        var name: String
        /// In the pinned part of the dock (it may be leaving once it quits; see `keepsInDock`).
        var isPinned: Bool
        var isRunning: Bool
        /// "Keep in Dock" state. A running app that is unchecked or dragged off stays in place until it quits.
        var keepsInDock: Bool
    }

    struct Pin: Codable, Equatable {
        var path: String
        var bundleID: String?
        /// Remove this pin once the app is no longer running.
        var removeOnQuit: Bool?
        var id: String { bundleID ?? path }
    }

    static let finderID = "com.apple.finder"
    static let finderPath = "/System/Library/CoreServices/Finder.app"

    private(set) var pins: [Pin]
    private(set) var items: [Item] = []
    var onChange: (() -> Void)?

    private let storeURL: URL
    private var observers: [NSObjectProtocol] = []

    init(storeURL: URL = Paths.dockFile) {
        self.storeURL = storeURL
        pins = JSONFile.load([Pin].self, from: storeURL) ?? Self.importAppleDockPins()
        normalizeFinder()
        save()
        let nc = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification,
                     NSWorkspace.didActivateApplicationNotification] {
            observers.append(nc.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in self?.rebuild() })
        }
        rebuild()
    }

    deinit { observers.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0) } }

    func rebuild() {
        let me = ProcessInfo.processInfo.processIdentifier
        let running = NSWorkspace.shared.runningApplications.filter {
            $0.activationPolicy == .regular && $0.processIdentifier != me && $0.bundleURL != nil
        }
        let runningIDs = Set(running.compactMap(\.bundleIdentifier))
        let runningPaths = Set(running.compactMap { $0.bundleURL?.standardizedFileURL.path })

        // Pins waiting for their app to quit leave once it has.
        let leaving = pins.filter { pin in
            pin.removeOnQuit == true && !(pin.bundleID.map(runningIDs.contains) ?? false) && !runningPaths.contains(pin.path)
        }
        if !leaving.isEmpty {
            pins.removeAll { pin in leaving.contains { $0.id == pin.id } }
            save()
        }

        var result: [Item] = []
        var seen = Set<String>()
        for pin in pins {
            guard let url = resolve(pin), seen.insert(pin.id).inserted else { continue }
            let isRunning = (pin.bundleID.map(runningIDs.contains) ?? false) || runningPaths.contains(url.standardizedFileURL.path)
            result.append(Item(id: pin.id, url: url, bundleID: pin.bundleID, name: Self.displayName(url),
                               isPinned: true, isRunning: isRunning, keepsInDock: pin.removeOnQuit != true))
        }
        for app in running {
            guard let url = app.bundleURL else { continue }
            let id = app.bundleIdentifier ?? url.path
            guard seen.insert(id).inserted else { continue }
            result.append(Item(id: id, url: url, bundleID: app.bundleIdentifier,
                               name: app.localizedName ?? Self.displayName(url), isPinned: false, isRunning: true,
                               keepsInDock: false))
        }
        if result != items {
            items = result
            onChange?()
        }
    }

    func item(_ id: String) -> Item? { items.first { $0.id == id } }

    func runningApplication(for item: Item) -> NSRunningApplication? {
        NSWorkspace.shared.runningApplications.first {
            (item.bundleID != nil && $0.bundleIdentifier == item.bundleID) || $0.bundleURL?.path == item.url.path
        }
    }

    func canRemove(_ id: String) -> Bool { id != Self.finderID }
    func canMove(_ id: String) -> Bool { id != Self.finderID }

    // MARK: Editing

    /// "Keep in Dock". Unpinning a running app keeps it in place until it quits, like the original Dock.
    func setPinned(_ id: String, _ pinned: Bool) {
        if pinned {
            if let i = pins.firstIndex(where: { $0.id == id }) {
                pins[i].removeOnQuit = nil
            } else if let item = item(id) {
                pins.append(Pin(path: item.url.path, bundleID: item.bundleID))
            } else {
                return
            }
        } else {
            guard canRemove(id), let i = pins.firstIndex(where: { $0.id == id }) else { return }
            if item(id)?.isRunning == true { pins[i].removeOnQuit = true } else { pins.remove(at: i) }
        }
        save(); rebuild()
    }

    /// Pins `id` at `index` of the visible order (clamped to the pinned section, after Finder).
    func place(_ id: String, at index: Int) {
        guard let item = item(id) else { return }
        move(Pin(path: item.url.path, bundleID: item.bundleID), to: index)
    }

    func insert(appURL: URL, at index: Int) {
        move(Pin(path: appURL.path, bundleID: Bundle(url: appURL)?.bundleIdentifier), to: index)
    }

    private func move(_ pin: Pin, to index: Int) {
        var kept = pins.first { $0.id == pin.id } ?? pin
        kept.removeOnQuit = nil // placing an icon keeps it
        var visible = items.filter(\.isPinned).map(\.id).filter { $0 != pin.id }
        // Pins whose app is missing right now keep their place at the end.
        let missing = pins.filter { p in p.id != pin.id && !visible.contains(p.id) }
        visible.insert(pin.id, at: max(pin.id == Self.finderID ? 0 : 1, min(index, visible.count)))
        pins = visible.compactMap { id in id == pin.id ? kept : pins.first { $0.id == id } } + missing
        normalizeFinder()
        save(); rebuild()
    }

    // MARK: Helpers

    private func resolve(_ pin: Pin) -> URL? {
        if FileManager.default.fileExists(atPath: pin.path) { return URL(fileURLWithPath: pin.path) }
        if let id = pin.bundleID { return NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) }
        return nil
    }

    private func normalizeFinder() {
        pins.removeAll { $0.id == Self.finderID }
        pins.insert(Pin(path: Self.finderPath, bundleID: Self.finderID), at: 0)
    }

    private func save() { try? JSONFile.save(pins, to: storeURL) }

    static func displayName(_ url: URL) -> String {
        let name = FileManager.default.displayName(atPath: url.path)
        return name.hasSuffix(".app") ? String(name.dropLast(4)) : name
    }

    /// First run: copy the apps already kept in Apple's Dock.
    static func importAppleDockPins() -> [Pin] {
        let tiles = CFPreferencesCopyAppValue("persistent-apps" as CFString, "com.apple.dock" as CFString) as? [[String: Any]] ?? []
        let pins: [Pin] = tiles.compactMap { tile in
            guard let data = tile["tile-data"] as? [String: Any],
                  let file = data["file-data"] as? [String: Any],
                  let string = file["_CFURLString"] as? String else { return nil }
            let url = string.hasPrefix("file://") ? URL(string: string) : URL(fileURLWithPath: string)
            guard let url, url.pathExtension == "app" else { return nil }
            return Pin(path: url.path, bundleID: data["bundle-identifier"] as? String ?? Bundle(url: url)?.bundleIdentifier)
        }
        if !pins.isEmpty { return pins }
        return ["/Applications/Safari.app", "/System/Applications/Mail.app", "/System/Applications/Calendar.app",
                "/System/Applications/Notes.app", "/System/Applications/Music.app", "/System/Applications/System Settings.app"]
            .filter { FileManager.default.fileExists(atPath: $0) }
            .map { Pin(path: $0, bundleID: Bundle(path: $0)?.bundleIdentifier) }
    }
}
