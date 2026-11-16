import AppKit

/// The user's login items (Open at Login), read from LaunchServices' list, which the Dock's own Open at Login
/// changes. The list's header is gone from the SDK but its calls are still there, so they're looked up at
/// runtime; without them the menu falls back to what Apple's Dock menu said. Only ever read, never written.
enum LoginItems {
    private typealias Create = @convention(c) (CFAllocator?, CFString, CFTypeRef?) -> Unmanaged<AnyObject>?
    private typealias Snapshot = @convention(c) (AnyObject, UnsafeMutablePointer<UInt32>?) -> Unmanaged<CFArray>?
    private typealias Resolve = @convention(c) (AnyObject, UInt32, UnsafeMutablePointer<Unmanaged<CFError>?>?) -> Unmanaged<CFURL>?

    private static let calls: (create: Create, snapshot: Snapshot, resolve: Resolve, list: CFString)? = {
        let cs = dlopen("/System/Library/Frameworks/CoreServices.framework/CoreServices", RTLD_LAZY)
        guard let create = dlsym(cs, "LSSharedFileListCreate"), let snapshot = dlsym(cs, "LSSharedFileListCopySnapshot"),
              let resolve = dlsym(cs, "LSSharedFileListItemCopyResolvedURL"),
              let list = dlsym(cs, "kLSSharedFileListSessionLoginItems") else { return nil }
        return (unsafeBitCast(create, to: Create.self), unsafeBitCast(snapshot, to: Snapshot.self),
                unsafeBitCast(resolve, to: Resolve.self), list.assumingMemoryBound(to: CFString.self).pointee)
    }()

    /// Read at most once a second, so opening menus one after another reads the list once.
    private static var cached: (at: TimeInterval, urls: [URL])?

    /// The login items' locations, or nil if the list can't be read.
    static func urls() -> [URL]? {
        let now = ProcessInfo.processInfo.systemUptime
        if let cached, now - cached.at < 1 { return cached.urls }
        guard let calls, let list = calls.create(nil, calls.list, nil)?.takeRetainedValue(),
              let items = calls.snapshot(list, nil)?.takeRetainedValue() as? [AnyObject] else { return nil }
        let urls = items.compactMap { calls.resolve($0, 0, nil)?.takeRetainedValue() as URL? }
        cached = (now, urls)
        return urls
    }

    /// Whether the app at `appURL` opens at login, or nil when that can't be told.
    static func contains(_ appURL: URL, bundleID: String?) -> Bool? {
        urls().map { LoginItemMatch.matches($0, appURL: appURL, bundleID: bundleID) }
    }
}

/// Which desktop each app is assigned to, from macOS's own records (no permission needed).
enum DesktopAssignments {
    static func read(bundleID: String) -> (assignment: DesktopAssignment, desktops: Int) {
        let domain = "com.apple.spaces" as CFString
        CFPreferencesAppSynchronize(domain)
        let bindings = CFPreferencesCopyAppValue("app-bindings" as CFString, domain) as? [String: Any] ?? [:]
        let config = CFPreferencesCopyAppValue("SpacesDisplayConfiguration" as CFString, domain) as? [String: Any]
        return DesktopAssignment.parse(bindings: bindings, config: config, bundleID: bundleID)
    }
}
