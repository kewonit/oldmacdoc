import AppKit

/// Tells the dock when macOS is drawing its own Dock, so ours can step aside before both show.
///
/// macOS always draws its Dock in Mission Control and App Exposé, even while it's parked, and
/// nothing can turn that off. macOS 27 posts no notification for these modes either. What can be
/// seen, without any permission, is the window list: Mission Control and App Exposé put a
/// screen-sized WindowManager shield at level 19 on screen within ~20–40 ms of the trigger.
///
/// The Dock's own window is not a usable signal: after the Dock restarts (which parking it does) it
/// keeps a transparent, full-screen window at the Dock level on screen while hidden.
///
/// To notice that quickly without polling, the monitor asks the WindowServer for window events
/// (private SkyLight calls loaded at runtime; no permission needed, the same approach AltTab uses on
/// macOS 27) and reads the window list once per frame at most when they arrive. While macOS's Dock
/// is up it also checks every 50 ms so ours comes back as soon as it has gone. If the private calls
/// are ever unavailable, the dock window's `.transient` behaviour and a check before every reveal
/// still keep the two docks apart.
final class SystemDockMonitor {
    private(set) var isShowingSystemDock = false
    /// Called on the main thread when macOS's Dock appears or goes away.
    var onChange: ((Bool) -> Void)?

    private var exitPoll: Timer?
    private var checkScheduled = false
    private var lastCheck: CFTimeInterval = 0
    private var observers: [NSObjectProtocol] = []
    private var windowManagerPID: pid_t = 0

    /// The monitor that receives WindowServer events (the C callback can't capture context).
    private static weak var current: SystemDockMonitor?

    init(watching window: NSWindow) {
        Self.current = self
        refreshPIDs()
        let ws = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
            observers.append(ws.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                self?.refreshPIDs()
            })
        }
        WindowServerEvents.register(windowNumber: window.windowNumber)
        check()
    }

    func stop() {
        exitPoll?.invalidate()
        exitPoll = nil
        observers.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0) }
        observers.removeAll()
        onChange = nil
        if Self.current === self { Self.current = nil }
    }

    fileprivate static func windowsChanged() {
        DispatchQueue.main.async { current?.scheduleCheck() }
    }

    /// Coalesces bursts of window events into at most one window-list read per frame.
    func scheduleCheck() {
        guard !checkScheduled else { return }
        checkScheduled = true
        let wait = max(0, 1.0 / 60 - (CACurrentMediaTime() - lastCheck))
        DispatchQueue.main.asyncAfter(deadline: .now() + wait) { [weak self] in
            guard let self else { return }
            self.checkScheduled = false
            self.check()
        }
    }

    /// One window-list read (well under a millisecond normally).
    @discardableResult
    func check() -> Bool {
        lastCheck = CACurrentMediaTime()
        let showing = systemDockOnScreen()
        if showing != isShowingSystemDock {
            isShowingSystemDock = showing
            onChange?(showing)
        }
        if showing, exitPoll == nil {
            let timer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in self?.check() }
            timer.tolerance = 0.01
            exitPoll = timer
        } else if !showing {
            exitPoll?.invalidate()
            exitPoll = nil
        }
        return showing
    }

    private func refreshPIDs() {
        windowManagerPID = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.WindowManager").first?.processIdentifier ?? 0
    }

    /// The Mission Control / App Exposé shield: a WindowManager window at level 19 covering a display
    /// (Stage Manager also uses level 19, for small windows, hence the size check).
    private func systemDockOnScreen() -> Bool {
        let screens = NSScreen.screens.map(\.frame.size)
        let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
        for w in windows {
            let pid = (w[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value ?? 0
            let owner = w[kCGWindowOwnerName as String] as? String
            let layer = w[kCGWindowLayer as String] as? Int ?? .min
            if layer == 19, (windowManagerPID != 0 && pid == windowManagerPID) || owner == "WindowManager",
               let dict = w[kCGWindowBounds as String] as? NSDictionary,
               let bounds = CGRect(dictionaryRepresentation: dict as CFDictionary),
               screens.contains(where: { bounds.width >= $0.width && bounds.height >= $0.height }) {
                return true
            }
        }
        return false
    }
}

/// WindowServer window events through private SkyLight entry points, looked up at runtime. Events
/// for windows being created, ordered in and ordered out arrive within a few milliseconds; the
/// connection only receives them after opting at least one of its own windows in.
private enum WindowServerEvents {
    private typealias NotifyProc = @convention(c) (UInt32, UnsafeMutableRawPointer?, Int, UnsafeMutableRawPointer?, Int32) -> Void
    private typealias MainConnection = @convention(c) () -> Int32
    private typealias RegisterProc = @convention(c) (Int32, NotifyProc, UInt32, UnsafeMutableRawPointer?) -> Int32
    private typealias RequestForWindows = @convention(c) (Int32, UnsafeMutablePointer<UInt32>, Int32) -> Int32

    private static var registered = false
    /// Window created (811), ordered (804), ordered in/out (815/816).
    private static let events: [UInt32] = [804, 811, 815, 816]

    static func register(windowNumber: Int) {
        guard let sky = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY),
              let mainSymbol = dlsym(sky, "SLSMainConnectionID"),
              let registerSymbol = dlsym(sky, "SLSRegisterConnectionNotifyProc"),
              let requestSymbol = dlsym(sky, "SLSRequestNotificationsForWindows") else { return }
        let mainConnection = unsafeBitCast(mainSymbol, to: MainConnection.self)
        let requestForWindows = unsafeBitCast(requestSymbol, to: RequestForWindows.self)
        let connection = mainConnection()
        var windows = [UInt32(truncatingIfNeeded: windowNumber)]
        _ = requestForWindows(connection, &windows, Int32(windows.count))
        guard !registered else { return }
        registered = true
        let registerProc = unsafeBitCast(registerSymbol, to: RegisterProc.self)
        let proc: NotifyProc = { _, _, _, _, _ in SystemDockMonitor.windowsChanged() }
        for event in events { _ = registerProc(connection, proc, event, nil) }
    }
}
