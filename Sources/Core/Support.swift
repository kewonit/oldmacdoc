import Foundation

enum AppInfo {
    static let name = "OldMacDoc"
    static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0"
    }
}

enum Paths {
    static let appSupport: URL = ensure(
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(AppInfo.name, isDirectory: true))
    static let caches: URL = ensure(
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(AppInfo.name, isDirectory: true))

    static var iconCache: URL { ensure(caches.appendingPathComponent("Icons", isDirectory: true)) }
    static var customIcons: URL { ensure(appSupport.appendingPathComponent("Custom Icons", isDirectory: true)) }
    static var settingsFile: URL { appSupport.appendingPathComponent("settings.json") }
    static var dockFile: URL { appSupport.appendingPathComponent("dock.json") }
    static var appleDockBackup: URL { appSupport.appendingPathComponent("apple-dock-backup.json") }

    @discardableResult
    static func ensure(_ url: URL) -> URL {
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}

enum JSONFile {
    static func load<T: Decodable>(_ type: T.Type, from url: URL) -> T? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(T.self, from: data)
    }

    static func save<T: Encodable>(_ value: T, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(value).write(to: url, options: .atomic)
    }
}

extension KeyedDecodingContainer {
    /// Decodes a value, falling back to `fallback` when the key is missing or malformed,
    /// so settings files from older versions keep loading.
    func value<T: Decodable>(_ key: Key, or fallback: T) -> T {
        ((try? decodeIfPresent(T.self, forKey: key)) ?? nil) ?? fallback
    }
}

// MARK: - Settings model

enum ShelfStyle: String, Codable, CaseIterable, Identifiable {
    case clear, frosted, smoke
    var id: String { rawValue }
    var title: String {
        switch self {
        case .clear: "Clear Glass"
        case .frosted: "Frosted"
        case .smoke: "Smoke"
        }
    }
}

enum FinishLevel: String, Codable, CaseIterable, Identifiable {
    case off, subtle, full
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
}

enum IconMode: String, Codable {
    case retro, original
}

/// Which side of Mission Control the + for a new desktop sits on. macOS puts it on the side away from
/// Apple's Dock, so the app chooses it by parking Apple's Dock on the other edge.
enum AddDesktopSide: String, Codable, CaseIterable, Identifiable {
    case left, right
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
    /// The edge Apple's Dock waits on to put the + on this side.
    var dockEdge: String { self == .left ? "right" : "left" }
}

struct IconOverride: Codable, Equatable {
    var mode: IconMode = .retro
    /// File name inside `Paths.customIcons`.
    var customImage: String?
}

struct AppSettings: Codable, Equatable {
    var shelfStyle: ShelfStyle = .clear
    var finish: FinishLevel = .full
    var iconSize: Double = 56
    var magnification = true
    var magnifiedSize: Double = 100
    var autoHide = true
    var showIndicators = true
    /// Left keeps Apple's Dock on the right edge, as it always was.
    var addDesktopSide: AddDesktopSide = .left
    var overrides: [String: IconOverride] = [:]
    /// Each app's own menu items and recent files, copied from Apple's Dock (which makes its menu flicker
    /// at the screen's edge once per app). Off, Apple's Dock menus are only opened to carry out a choice.
    var appleMenuItems = true

    /// The sizes the menu offers, in points.
    static let iconSizeRange: ClosedRange<Double> = 32...96
    static let magnifiedSizeRange: ClosedRange<Double> = 48...128

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = AppSettings()
        shelfStyle = c.value(.shelfStyle, or: d.shelfStyle)
        finish = c.value(.finish, or: d.finish)
        iconSize = c.value(.iconSize, or: d.iconSize)
        magnification = c.value(.magnification, or: d.magnification)
        magnifiedSize = c.value(.magnifiedSize, or: d.magnifiedSize)
        autoHide = c.value(.autoHide, or: d.autoHide)
        showIndicators = c.value(.showIndicators, or: d.showIndicators)
        addDesktopSide = c.value(.addDesktopSide, or: d.addDesktopSide)
        overrides = c.value(.overrides, or: d.overrides)
        appleMenuItems = c.value(.appleMenuItems, or: d.appleMenuItems)
        // A hand-edited or damaged file can't push the sizes out of range. They're independent: a
        // magnified size below the icon size simply shows no magnification.
        iconSize = Self.clamp(iconSize, to: Self.iconSizeRange, or: d.iconSize)
        magnifiedSize = Self.clamp(magnifiedSize, to: Self.magnifiedSizeRange, or: d.magnifiedSize)
    }

    private static func clamp(_ value: Double, to range: ClosedRange<Double>, or fallback: Double) -> Double {
        value.isFinite ? min(max(value, range.lowerBound), range.upperBound) : fallback
    }
}
