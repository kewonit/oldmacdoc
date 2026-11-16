import Foundation

enum StackSort: String, Codable, CaseIterable {
    case name, dateAdded, dateModified, dateCreated, kind
}

/// How a folder's tile looks: its newest items piled up (Leopard's stack), or the folder's own icon.
enum StackDisplay: String, Codable, CaseIterable {
    case stack, folder
}

/// How a folder opens: Fan when its items fit, otherwise Grid (Automatic), or always one of them.
enum StackView: String, Codable, CaseIterable {
    case automatic, fan, grid, list
}

/// A folder kept in the dock, between the apps and the Trash.
struct StackPin: Codable, Equatable, Identifiable {
    var id: String
    var path: String
    var display: StackDisplay = .stack
    var view: StackView = .automatic
    /// Leopard sorted Downloads by date added and everything else by name.
    var sort: StackSort = .name

    init(id: String = "stack:" + UUID().uuidString, path: String, display: StackDisplay = .stack,
         view: StackView = .automatic, sort: StackSort? = nil) {
        self.id = id
        self.path = path
        self.display = display
        self.view = view
        self.sort = sort ?? (URL(fileURLWithPath: path).lastPathComponent == "Downloads" ? .dateAdded : .name)
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        path = try c.decode(String.self, forKey: .path)
        display = c.value(.display, or: .stack)
        view = c.value(.view, or: .automatic)
        sort = c.value(.sort, or: .name)
    }

    var url: URL { URL(fileURLWithPath: path, isDirectory: true) }
    var name: String { FileManager.default.displayName(atPath: path) }
}

/// The folders in the dock, in order, kept in their own file so the apps' `dock.json` never changes.
final class StackStore {
    private(set) var pins: [StackPin]
    private let url: URL

    init(url: URL = Paths.stacksFile, firstRun: () -> [StackPin] = { [] }) {
        self.url = url
        if FileManager.default.fileExists(atPath: url.path) {
            // One damaged entry doesn't lose the others.
            pins = (JSONFile.load([Lenient<StackPin>].self, from: url) ?? []).compactMap(\.value)
        } else {
            pins = firstRun()
            save()
        }
    }

    func pin(_ id: String) -> StackPin? { pins.first { $0.id == id } }

    /// Adds `folder` at `index` among the folders (or moves it there if it's already in), and returns its id.
    @discardableResult
    func add(folder: URL, at index: Int) -> String {
        let path = folder.standardizedFileURL.path
        let pin = pins.first { $0.path == path } ?? StackPin(path: path)
        pins.removeAll { $0.id == pin.id }
        pins.insert(pin, at: max(0, min(index, pins.count)))
        save()
        return pin.id
    }

    func move(_ id: String, to index: Int) {
        guard let pin = pin(id) else { return }
        pins.removeAll { $0.id == id }
        pins.insert(pin, at: max(0, min(index, pins.count)))
        save()
    }

    func remove(_ id: String) {
        pins.removeAll { $0.id == id }
        save()
    }

    func update(_ id: String, _ change: (inout StackPin) -> Void) {
        guard let i = pins.firstIndex(where: { $0.id == id }) else { return }
        change(&pins[i])
        save()
    }

    private func save() { try? JSONFile.save(pins, to: url) }

    /// First run: the folders kept in Apple's Dock (its "persistent-others").
    static func appleDockFolders(_ tiles: [[String: Any]]) -> [StackPin] {
        tiles.compactMap { tile in
            guard let data = tile["tile-data"] as? [String: Any],
                  let file = data["file-data"] as? [String: Any],
                  let string = file["_CFURLString"] as? String else { return nil }
            let url = string.hasPrefix("file://") ? URL(string: string) : URL(fileURLWithPath: string)
            guard let url else { return nil }
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue,
                  url.pathExtension != "app" else { return nil }
            // Apple's showas: 1 fan, 2 grid, 3 list, 0 automatic; displayas: 0 stack, 1 folder; arrangement:
            // 1 name, 2 date added, 3 date modified, 4 date created, 5 kind.
            let view: StackView = [1: .fan, 2: .grid, 3: .list][data["showas"] as? Int ?? 0] ?? .automatic
            let display: StackDisplay = (data["displayas"] as? Int) == 1 ? .folder : .stack
            let sort: StackSort? = [1: .name, 2: .dateAdded, 3: .dateModified, 4: .dateCreated, 5: .kind][data["arrangement"] as? Int ?? 0]
            return StackPin(path: url.standardizedFileURL.path, display: display, view: view, sort: sort)
        }
    }
}

/// Decodes to nil instead of failing, so one bad element doesn't fail the whole array.
struct Lenient<T: Codable>: Codable {
    let value: T?
    init(from decoder: Decoder) throws { value = try? T(from: decoder) }
    func encode(to encoder: Encoder) throws { try value?.encode(to: encoder) }
}

extension Paths {
    static var stacksFile: URL { appSupport.appendingPathComponent("stacks.json") }
}

// MARK: - A folder's contents

/// One item in a stack: a file or folder in the stacked folder.
struct StackEntry: Equatable {
    var url: URL
    var name: String
    var isFolder: Bool
    /// Packages (apps, bundles) open rather than navigate.
    var isPackage: Bool
    var added: Date?
    var modified: Date?
    var created: Date?
    var kind: String

    static let keys: [URLResourceKey] = [.localizedNameKey, .isDirectoryKey, .isPackageKey, .addedToDirectoryDateKey,
                                         .contentModificationDateKey, .creationDateKey, .localizedTypeDescriptionKey,
                                         .isHiddenKey]

    init(url: URL, name: String, isFolder: Bool, isPackage: Bool = false, added: Date? = nil, modified: Date? = nil,
         created: Date? = nil, kind: String = "") {
        self.url = url
        self.name = name
        self.isFolder = isFolder
        self.isPackage = isPackage
        self.added = added
        self.modified = modified
        self.created = created
        self.kind = kind
    }

    /// The visible items of `folder` (no hidden files), unsorted. Empty if it can't be read.
    static func contents(of folder: URL) -> [StackEntry] {
        let urls = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: keys,
                                                                  options: [.skipsHiddenFiles])) ?? []
        return urls.compactMap { url in
            guard let v = try? url.resourceValues(forKeys: Set(keys)), v.isHidden != true else { return nil }
            let dir = v.isDirectory ?? false, pkg = v.isPackage ?? false
            return StackEntry(url: url, name: v.localizedName ?? url.lastPathComponent, isFolder: dir && !pkg,
                              isPackage: pkg, added: v.addedToDirectoryDate, modified: v.contentModificationDate,
                              created: v.creationDate, kind: v.localizedTypeDescription ?? "")
        }
    }

    /// Sorted as the Dock sorts stacks: dates newest first, names and kinds A to Z (Finder's order).
    static func sorted(_ entries: [StackEntry], by sort: StackSort) -> [StackEntry] {
        func byName(_ a: StackEntry, _ b: StackEntry) -> Bool { a.name.localizedStandardCompare(b.name) == .orderedAscending }
        func newest(_ a: Date?, _ b: Date?, _ x: StackEntry, _ y: StackEntry) -> Bool {
            let l = a ?? .distantPast, r = b ?? .distantPast
            return l == r ? byName(x, y) : l > r
        }
        switch sort {
        case .name: return entries.sorted(by: byName)
        case .dateAdded: return entries.sorted { newest($0.added, $1.added, $0, $1) }
        case .dateModified: return entries.sorted { newest($0.modified, $1.modified, $0, $1) }
        case .dateCreated: return entries.sorted { newest($0.created, $1.created, $0, $1) }
        case .kind:
            return entries.sorted { a, b in
                let c = a.kind.localizedStandardCompare(b.kind)
                return c == .orderedSame ? byName(a, b) : c == .orderedAscending
            }
        }
    }
}

/// Putting files into a folder in the dock, as dropping them on its tile does.
enum StackFiling {
    /// Moves each file into `folder` on the same disk, or copies it from another disk (or always, with
    /// `copy`). Nothing is ever replaced: a name already in the folder is skipped. A folder never goes into
    /// itself, and a file already in the folder stays put. Returns, for each file, whether it went in.
    static func file(_ urls: [URL], into folder: URL, copy: Bool, fileManager fm: FileManager = .default) -> [URL: Bool] {
        let target = folder.standardizedFileURL
        let targetVolume = volume(of: target)
        var result: [URL: Bool] = [:]
        for url in urls {
            let source = url.standardizedFileURL
            let destination = target.appendingPathComponent(source.lastPathComponent)
            if source == target || target.path.hasPrefix(source.path + "/")
                || source.deletingLastPathComponent().standardizedFileURL == target
                || fm.fileExists(atPath: destination.path) {
                result[url] = false
                continue
            }
            do {
                if copy || targetVolume == nil || volume(of: source) != targetVolume {
                    try fm.copyItem(at: source, to: destination)
                } else {
                    try fm.moveItem(at: source, to: destination)
                }
                result[url] = true
            } catch {
                result[url] = false
            }
        }
        return result
    }

    private static func volume(of url: URL) -> String? {
        ((try? url.resourceValues(forKeys: [.volumeIdentifierKey]).volumeIdentifier) as? NSObject).map { "\($0)" }
    }
}
