import Foundation

/// What an app's Info.plist says about how it shows up while it runs.
enum AppBundleInfo {
    /// Whether the app gets a place in the Dock while it runs. Agents (`LSUIElement`) and
    /// background-only apps don't. Launchpad (Apps on macOS 26 and later) and Mission Control are
    /// agents: they open something and quit at once, so Apple's Dock never bounces them.
    static func showsInDock(_ info: [String: Any]?) -> Bool {
        !(flag(info?["LSUIElement"]) || flag(info?["LSBackgroundOnly"]))
    }

    /// Info.plist switches come as booleans, numbers or strings ("1", "YES", "true").
    static func flag(_ value: Any?) -> Bool {
        switch value {
        case let number as NSNumber: return number.boolValue
        case let string as String:
            return ["1", "yes", "true"].contains(string.trimmingCharacters(in: .whitespaces).lowercased())
        default: return false
        }
    }
}
