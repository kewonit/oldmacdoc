import AppKit
import ApplicationServices

/// Keeps maximised and tiled windows clear of the dock while it doesn't hide, as Apple's Dock does; the
/// rules are in DockClearance. It works only while Hide automatically is off and Accessibility is allowed.
///
/// No API lets another app reserve screen space the way Apple's Dock does (see DockClearance), so macOS
/// maximises a window first, and then it steps up above the dock. Windows that were already maximised when
/// hiding is turned off step up too. Turning hiding on leaves windows where they are, as Apple's Dock does;
/// one zoom fills the screen again.
///
/// Every Accessibility call runs on a thread of its own, so an app that has stopped answering can never hold
/// up the dock's animation on the main thread.
final class DockClearanceController {
    /// Hiding is off: windows should keep clear of the dock.
    var wanted = false {
        didSet { if wanted != oldValue { update() } }
    }
    /// The dock's resting top, in points above the bottom of the main display (unmagnified, as Apple's Dock
    /// reserves its unmagnified height).
    var restingTop: CGFloat {
        didSet { if restingTop != oldValue { scheduleGeometry() } }
    }
    /// macOS is showing its own Dock (Mission Control, App Exposé): windows move about there, so nothing is
    /// changed until it has gone.
    var systemDockShowing = false {
        didSet {
            guard systemDockShowing != oldValue else { return }
            let paused = systemDockShowing
            engine.perform { $0.setPaused(paused) }
        }
    }

    private let engine = ClearanceEngine()
    private(set) var isRunning = false
    private var observers: [(NotificationCenter, NSObjectProtocol)] = []
    private var geometryWork: DispatchWorkItem?

    init(restingTop: CGFloat) {
        self.restingTop = restingTop
    }

    /// Accessibility may have been allowed or taken away.
    func refreshTrust() { update() }

    func stop() { wanted = false }

    private func update() {
        let run = wanted && AccessibilityAccess.isTrusted
        guard run != isRunning else { return }
        isRunning = run
        if run { start() } else { halt() }
    }

    private func start() {
        let geometry = geometry()
        let pids = NSWorkspace.shared.runningApplications.filter(Self.isWatched).map(\.processIdentifier)
        let paused = systemDockShowing
        engine.perform { $0.activate(geometry: geometry, pids: pids, paused: paused) }

        let ws = NSWorkspace.shared.notificationCenter
        observe(ws, NSWorkspace.didLaunchApplicationNotification) { [engine] note in
            guard let app = Self.app(note), Self.isWatched(app) else { return }
            let pid = app.processIdentifier
            engine.perform { $0.addApp(pid, sweepAfter: 1) }
        }
        observe(ws, NSWorkspace.didTerminateApplicationNotification) { [engine] note in
            guard let pid = Self.app(note)?.processIdentifier else { return }
            engine.perform { $0.removeApp(pid) }
        }
        // An app coming forward may show windows that weren't on screen: unhidden, or out of Stage Manager. It
        // may also be new to this: one that became a regular app after launching (from a menu bar app, say),
        // or one too busy to answer when it launched.
        observe(ws, NSWorkspace.didActivateApplicationNotification) { [engine] note in
            guard let app = Self.app(note), Self.isWatched(app) else { return }
            let pid = app.processIdentifier
            engine.perform { $0.catchUp(pid) }
        }
        observe(ws, NSWorkspace.activeSpaceDidChangeNotification) { [engine] _ in
            engine.perform { $0.spaceChanged() }
        }
        observe(NotificationCenter.default, NSApplication.didChangeScreenParametersNotification) { [weak self] _ in
            self?.pushGeometry()
        }
    }

    private func halt() {
        observers.forEach { $0.0.removeObserver($0.1) }
        observers.removeAll()
        geometryWork?.cancel()
        geometryWork = nil
        engine.perform { $0.deactivate() }
    }

    private func observe(_ center: NotificationCenter, _ name: Notification.Name, _ action: @escaping (Notification) -> Void) {
        observers.append((center, center.addObserver(forName: name, object: nil, queue: .main, using: action)))
    }

    private static func app(_ note: Notification) -> NSRunningApplication? {
        note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
    }

    /// Apps with windows of their own (not agents or background apps), other than this one.
    private static func isWatched(_ app: NSRunningApplication) -> Bool {
        app.activationPolicy == .regular && app.processIdentifier != getpid() && !app.isTerminated
    }

    // MARK: Geometry

    /// The main display (the dock's) as Accessibility has it, and the dock's band.
    private func geometry() -> DockClearance.Geometry? {
        guard let screen = NSScreen.screens.first, restingTop > 0 else { return nil }
        return DockClearance.geometry(display: screen.frame, visible: screen.visibleFrame, restingTop: restingTop,
                                      primaryMaxY: screen.frame.maxY)
    }

    /// The dock's height changes many times while the Size slider is dragged, and when apps arrive in a
    /// crowded dock: windows follow once it settles.
    private func scheduleGeometry() {
        guard isRunning else { return }
        geometryWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.geometryWork = nil
            self?.pushGeometry()
        }
        geometryWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: work)
    }

    private func pushGeometry() {
        guard isRunning else { return }
        let geometry = geometry()
        engine.perform { $0.setGeometry(geometry) }
    }

    // MARK: Debug

    #if DEBUG
    /// Looks at every window again, as when hiding is turned off.
    func debugSweep() { engine.perform { $0.sweep(nil, force: true) } }

    /// Writes what's being watched and what was done to `url`.
    func debugDump(to url: URL) {
        let running = isRunning, wanted = wanted, trusted = AccessibilityAccess.isTrusted, top = restingTop
        engine.perform { $0.dump(to: url, extra: ["running": running, "wanted": wanted, "trusted": trusted, "restingTop": top]) }
    }
    #endif
}

// MARK: - The Accessibility thread

/// Everything that talks to other apps. It lives on its own thread, and its state is only touched there.
private final class ClearanceEngine {
    /// How long a window's frame must stay still before it's looked at: a zoom or a tile goes through many
    /// frames, and only the last one counts.
    static let settle: TimeInterval = 0.15
    /// After an animated change (Fill and tiling animate for ~0.3 s), nothing is done until this long after it
    /// started: macOS puts a tiled window's frame back if it changes within about 0.6 s of the start (measured
    /// on macOS 27.0.1).
    static let tileHold: TimeInterval = 0.8
    /// A burst of changes longer than this was an animation.
    static let animationBurst: TimeInterval = 0.1
    /// Given its full frame again this soon after being shortened: macOS insisting, not the user. The next try
    /// waits `tileHold` from then, so macOS has let go of it.
    static let putBackWithin: TimeInterval = 0.5
    /// How long nothing is done after a Space switch (as AutoHide.transitionBlackout holds reveals): windows
    /// slide about meanwhile.
    static let spaceBlackout: TimeInterval = 0.4

    private final class App {
        let pid: pid_t
        let element: AXUIElement
        var observer: AXObserver?
        var attempts = 0
        var retry: Timer?
        init(pid: pid_t) {
            self.pid = pid
            element = AXUIElementCreateApplication(pid)
            // A timeout set on the app's element isn't inherited by its windows' elements (see `track`).
            AXUIElementSetMessagingTimeout(element, 0.3)
        }
    }

    private final class Tracked {
        let element: AXUIElement
        let pid: pid_t
        /// The frame it had when it was last looked at.
        var settled: CGRect?
        var record: DockClearance.Record?
        /// It didn't take the frame it was given (a minimum height, say): left alone until its frame changes.
        var stuckAt: CGRect?
        var samples: [DockClearance.Sample] = []
        /// When the current burst of changes started, and when its last change came.
        var burstStart: TimeInterval = 0
        var lastEvent: TimeInterval = 0
        var timer: Timer?
        /// When it was last shortened here, and how many times in a row it was put back straight after.
        var shortenedAt: TimeInterval = -.infinity
        var putBacks = 0
        /// When it was changed here lately, as a last guard against going back and forth with something.
        var changes: [TimeInterval] = []
        init(element: AXUIElement, pid: pid_t) {
            self.element = element
            self.pid = pid
        }
    }

    private let thread = WorkerThread()
    private var active = false
    private var geometry: DockClearance.Geometry?
    private var paused = false
    private var blockedUntil: TimeInterval = 0
    private var apps: [pid_t: App] = [:]
    private var windows: [AXUIElement: Tracked] = [:]
    /// Windows that changed while paused, looked at once it's over.
    private var deferred: Set<AXUIElement> = []
    /// A sweep asked for while paused: nil for none, true to look at every window again.
    private var pendingSweep: Bool?
    private var resumeTimer: Timer?
    /// Apps whose windows keep being put back (a tiling window manager at work): left alone until they quit.
    private var givenUp: Set<pid_t> = []

    func perform(_ work: @escaping (ClearanceEngine) -> Void) {
        thread.perform { [unowned self] in work(self) }
    }

    private var now: TimeInterval { ProcessInfo.processInfo.systemUptime }

    // MARK: Starting and stopping

    func activate(geometry: DockClearance.Geometry?, pids: [pid_t], paused: Bool) {
        guard !active else { return }
        active = true
        self.geometry = geometry
        self.paused = paused
        blockedUntil = 0
        for pid in pids { addApp(pid, sweepAfter: nil) }
        sweep(nil, force: true)
    }

    func deactivate() {
        guard active else { return }
        active = false
        for pid in Array(apps.keys) { removeApp(pid) }
        windows.values.forEach { $0.timer?.invalidate() }
        windows = [:]
        deferred = []
        pendingSweep = nil
        resumeTimer?.invalidate()
        resumeTimer = nil
        givenUp = []
        geometry = nil
    }

    func setGeometry(_ g: DockClearance.Geometry?) {
        guard active, let g else { return }
        let old = geometry
        geometry = g
        guard let old else { return sweep(nil, force: true) }
        if old.display != g.display {
            // Another main display, or it changed size: what was recorded doesn't fit it any more.
            for t in windows.values {
                t.record = nil
                t.stuckAt = nil
            }
            sweep(nil, force: true)
        } else if old.visible != g.visible || g.bandTop < old.bandTop - 0.5 {
            // The menu bar came or went, or the dock grew: windows that end above it move up with it.
            // When the dock shrinks they stay, as with Apple's Dock.
            sweep(nil, force: true)
        }
    }

    func setPaused(_ on: Bool) {
        paused = on
        if !on { resume() }
    }

    func spaceChanged() {
        guard active else { return }
        blockedUntil = now + Self.spaceBlackout
        // Windows on the new Space haven't been seen yet.
        pendingSweep = pendingSweep ?? false
        resumeTimer?.invalidate()
        resumeTimer = after(Self.spaceBlackout + 0.05) { [weak self] in self?.resume() }
    }

    private var isHeld: Bool { paused || now < blockedUntil }

    private func resume() {
        guard active, !isHeld else { return }
        let waiting = deferred
        deferred = []
        for element in waiting {
            if let t = windows[element] { evaluate(t, usePrevious: true) }
        }
        if let force = pendingSweep {
            pendingSweep = nil
            sweep(nil, force: force)
        }
    }

    // MARK: Apps

    func addApp(_ pid: pid_t, sweepAfter delay: TimeInterval?) {
        guard active, apps[pid] == nil else { return }
        let app = App(pid: pid)
        apps[pid] = app
        connect(app, sweepAfter: delay)
    }

    private func connect(_ app: App, sweepAfter delay: TimeInterval?) {
        guard active, apps[app.pid] === app else { return }
        var created: AXObserver?
        guard AXObserverCreate(app.pid, clearanceCallback, &created) == .success, let observer = created else { return }
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        let result = AXObserverAddNotification(observer, app.element, kAXWindowCreatedNotification as CFString, refcon)
        if result == .cannotComplete {
            // Still launching, or busy: try again in a moment, for a few seconds.
            app.attempts += 1
            guard app.attempts <= 5 else { return }
            app.retry = after(0.25 * pow(2, Double(app.attempts - 1))) { [weak self, weak app] in
                guard let self, let app else { return }
                self.connect(app, sweepAfter: 0)
            }
            return
        }
        // On the app, so windows not seen yet are noticed too (each window is also observed, in `track`).
        for name in [kAXFocusedWindowChangedNotification, kAXWindowMovedNotification, kAXWindowResizedNotification] {
            AXObserverAddNotification(observer, app.element, name as CFString, refcon)
        }
        CFRunLoopAddSource(CFRunLoopGetCurrent(), AXObserverGetRunLoopSource(observer), .defaultMode)
        app.observer = observer
        // Windows an app restores as it launches often send no "created".
        if let delay {
            let pid = app.pid
            after(delay) { [weak self] in self?.sweep([pid], force: false) }
        }
    }

    func removeApp(_ pid: pid_t) {
        guard let app = apps.removeValue(forKey: pid) else { return }
        app.retry?.invalidate()
        if let observer = app.observer {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), AXObserverGetRunLoopSource(observer), .defaultMode)
        }
        forget(pid)
        givenUp.remove(pid)
    }

    private func forget(_ pid: pid_t) {
        for (element, t) in windows where t.pid == pid {
            t.timer?.invalidate()
            windows[element] = nil
            deferred.remove(element)
        }
    }

    func catchUp(_ pid: pid_t) {
        guard active, !givenUp.contains(pid) else { return }
        guard let app = apps[pid] else { return addApp(pid, sweepAfter: 0.25) }
        if app.observer == nil {
            // It didn't answer when it launched: try again now that it's in use.
            app.retry?.invalidate()
            app.attempts = 0
            return connect(app, sweepAfter: 0.25)
        }
        after(0.25) { [weak self] in self?.sweep([pid], force: false) }
    }

    // MARK: Windows

    fileprivate func received(_ name: String, _ element: AXUIElement) {
        guard active else { return }
        trace("\(name) \(axFrame(element).map { "\($0)" } ?? "-")")
        switch name {
        case kAXUIElementDestroyedNotification:
            windows.removeValue(forKey: element)?.timer?.invalidate()
            deferred.remove(element)
        case kAXWindowCreatedNotification:
            if let t = track(element) { settleLater(t) }
        case kAXFocusedWindowChangedNotification:
            // A window first seen when it comes forward (one restored at launch, say).
            let window = axRole(element) == kAXWindowRole ? element : axElement(element, kAXFocusedWindowAttribute)
            if let window, windows[window] == nil, let t = track(window) { settleLater(t) }
        case kAXWindowMovedNotification, kAXWindowResizedNotification:
            guard let t = track(element) else { return }
            if let sample = Self.sample(t.element) {
                t.samples.append(sample)
                if t.samples.count > 16 { t.samples.removeFirst(t.samples.count - 16) }
            }
            settleLater(t)
        default:
            break
        }
    }

    /// The window, watched from now on; nil for anything that isn't an app's window.
    private func track(_ element: AXUIElement) -> Tracked? {
        if let t = windows[element] { return t }
        var pid: pid_t = 0
        guard AXUIElementGetPid(element, &pid) == .success, let app = apps[pid], !givenUp.contains(pid) else { return nil }
        AXUIElementSetMessagingTimeout(element, 0.3)
        guard axRole(element) == kAXWindowRole else { return nil }
        if let observer = app.observer {
            let refcon = Unmanaged.passUnretained(self).toOpaque()
            for name in [kAXWindowMovedNotification, kAXWindowResizedNotification, kAXUIElementDestroyedNotification] {
                AXObserverAddNotification(observer, element, name as CFString, refcon)
            }
        }
        let t = Tracked(element: element, pid: pid)
        windows[element] = t
        return t
    }

    /// While the left button is down: where the pointer is and the window's frame, to tell a resize by hand.
    private static func sample(_ element: AXUIElement) -> DockClearance.Sample? {
        guard CGEventSource.buttonState(.combinedSessionState, button: .left), let frame = axFrame(element) else { return nil }
        return DockClearance.Sample(frame: frame, pointer: CGEvent(source: nil)?.location ?? .zero, buttonDown: true)
    }

    private func settleLater(_ t: Tracked) {
        t.lastEvent = now
        guard t.timer == nil else { return }
        t.burstStart = t.lastEvent
        t.timer = after(Self.settle) { [weak self, weak t] in
            guard let t else { return }
            self?.settled(t)
        }
    }

    private func settled(_ t: Tracked) {
        t.timer = nil
        let animated = t.lastEvent - t.burstStart > Self.animationBurst
        let due = animated || isPutBack(t) ? max(t.lastEvent + Self.settle, t.burstStart + Self.tileHold) : t.lastEvent + Self.settle
        let wait = due - now
        if wait > 0.01 {
            t.timer = after(wait) { [weak self, weak t] in
                guard let t else { return }
                self?.settled(t)
            }
            return
        }
        evaluate(t, usePrevious: true)
    }

    /// The current burst began straight after the window was shortened: its own change coming back, and
    /// perhaps macOS giving it its full frame again.
    private func isPutBack(_ t: Tracked) -> Bool {
        t.record != nil && t.burstStart >= t.shortenedAt && t.burstStart - t.shortenedAt < Self.putBackWithin
    }

    /// Looks at every window of `pids` (every app when nil). Without `force`, only windows not seen yet or
    /// changed since, so one left alone (resized by hand into the dock, say) stays that way.
    func sweep(_ pids: [pid_t]?, force: Bool) {
        guard active, geometry != nil else { return }
        if isHeld {
            pendingSweep = force || (pendingSweep ?? false)
            return
        }
        // Windows on other Spaces, hidden or in Stage Manager's strip aren't on screen: they're looked at
        // when they come back.
        let onScreen = Self.onScreenWindows()
        let targets = pids.map { $0.compactMap { apps[$0] } } ?? Array(apps.values)
        for app in targets where app.observer != nil && !givenUp.contains(app.pid) {
            for element in ax(app.element, kAXWindowsAttribute) as? [AXUIElement] ?? [] {
                if let id = axWindowNumber(element), !onScreen.contains(id) { continue }
                guard let t = track(element) else { continue }
                if !force, let settled = t.settled, let frame = axFrame(t.element), DockClearance.same(settled, frame) { continue }
                evaluate(t, usePrevious: !force)
            }
        }
    }

    /// Whether the window is on a full-screen Space. Not every app says it's full screen (games, SDL and Qt
    /// apps), and on a display with a notch its frame is a filled window's.
    private static func isOnFullScreenSpace(_ element: AXUIElement) -> Bool {
        guard let id = axWindowNumber(element) else { return false }
        return FullScreenSpaces.contains(id)
    }

    private static func onScreenWindows() -> Set<CGWindowID> {
        let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        return Set(list.compactMap { ($0[kCGWindowNumber as String] as? NSNumber)?.uint32Value })
    }

    private func evaluate(_ t: Tracked, usePrevious: Bool) {
        guard active, let g = geometry, windows[t.element] === t, !givenUp.contains(t.pid) else { return }
        if isHeld {
            deferred.insert(t.element)
            return
        }
        // Only what happened while it changed: a press near its edge afterwards (a scroll bar, say) isn't a resize.
        let samples = t.samples
        t.samples = []
        guard let frame = axFrame(t.element) else { return }
        let previous = usePrevious ? t.settled : nil
        if let stuck = t.stuckAt {
            if DockClearance.same(stuck, frame) {
                t.settled = frame
                return
            }
            t.stuckAt = nil
        }
        // Most changes are nowhere near the dock: no need to ask the app anything more.
        if t.record == nil, DockClearance.cleared(frame, in: g) == nil {
            t.settled = frame
            return
        }
        let window = DockClearance.Window(frame: frame,
                                          isStandard: ax(t.element, kAXSubroleAttribute) as? String == kAXStandardWindowSubrole,
                                          isMinimized: ax(t.element, kAXMinimizedAttribute) as? Bool ?? false,
                                          isFullScreen: (ax(t.element, "AXFullScreen") as? Bool ?? false) || Self.isOnFullScreenSpace(t.element),
                                          isResizable: axIsSettable(t.element, kAXSizeAttribute))
        // Only a change that just happened can be macOS putting it back; a sweep (the dock grew) isn't one.
        let putBack = usePrevious && isPutBack(t)
        let action = DockClearance.action(window, previous: previous, record: t.record, edgeDrag: DockClearance.isEdgeDrag(samples),
                                          putBack: putBack, in: g)
        trace("\(t.pid) \(frame) from \(previous.map { "\($0)" } ?? "-") \(window) -> \(action)")
        switch action {
        case .leave:
            if let record = t.record, !DockClearance.same(frame, record.set) { t.record = nil }
            t.settled = frame
        case .shrink(let target):
            t.putBacks = putBack ? t.putBacks + 1 : 0
            guard mayChange(t) else { return }
            let result = apply(target, to: t, move: false)
            t.shortenedAt = now
            trace("\(t.pid) took \(result.map { "\($0)" } ?? "-")")
            if let result, result.maxY <= g.bandTop + DockClearance.slack {
                t.record = DockClearance.record(full: frame, previous: t.settled, old: t.record, set: result)
            } else {
                // It keeps a size of its own (a minimum height, or one fitted to its content).
                t.stuckAt = result ?? frame
                t.record = nil
            }
            t.settled = result ?? frame
        case .restore(let before):
            guard mayChange(t) else { return }
            t.settled = apply(before, to: t, move: true) ?? frame
            t.record = nil
        }
    }

    /// False, and the app is left alone from then on, when its window keeps being put back: a tiling window
    /// manager, or the app itself, insisting on its own frame. A put-back now and then is macOS finishing a
    /// tile; three in a row, or many changes in a few seconds, is something that won't give way.
    private func mayChange(_ t: Tracked) -> Bool {
        let time = now
        t.changes = t.changes.filter { time - $0 < 5 } + [time]
        guard t.putBacks >= 3 || t.changes.count > 8 else { return true }
        givenUp.insert(t.pid)
        forget(t.pid)
        return false
    }

    /// Gives the window `frame` and returns the frame it took.
    private func apply(_ frame: CGRect, to t: Tracked, move: Bool) -> CGRect? {
        // With this on (VoiceOver and some tools set it), Chromium, Electron and Firefox animate every change
        // slowly; Rectangle turns it off around its changes too.
        let app = apps[t.pid]?.element
        let enhanced = app.flatMap { ax($0, "AXEnhancedUserInterface") as? Bool } ?? false
        if enhanced, let app { AXUIElementSetAttributeValue(app, "AXEnhancedUserInterface" as CFString, kCFBooleanFalse) }
        defer {
            if enhanced, let app { AXUIElementSetAttributeValue(app, "AXEnhancedUserInterface" as CFString, kCFBooleanTrue) }
        }
        if move {
            // Size first, so the new place isn't refused for running off the screen; then again, in case the
            // old place limited the size.
            axSetSize(t.element, frame.size)
            axSetPosition(t.element, frame.origin)
        }
        axSetSize(t.element, frame.size)
        return axFrame(t.element)
    }

    // MARK: Timers and debugging

    @discardableResult
    private func after(_ delay: TimeInterval, _ block: @escaping () -> Void) -> Timer {
        let timer = Timer(timeInterval: delay, repeats: false) { _ in block() }
        timer.tolerance = min(0.02, delay * 0.1)
        RunLoop.current.add(timer, forMode: .default)
        return timer
    }

    #if DEBUG
    private static let tracing = ProcessInfo.processInfo.environment["OLDMACDOC_TRACE"] != nil

    /// With OLDMACDOC_TRACE set, what's seen and done goes to standard error.
    private func trace(_ message: @autoclosure () -> String) {
        guard Self.tracing else { return }
        FileHandle.standardError.write(Data((String(format: "%.3f ", now) + message() + "\n").utf8))
    }

    func dump(to url: URL, extra: [String: Any]) {
        func text(_ r: CGRect?) -> Any { r.map { "\(Int($0.minX)),\(Int($0.minY)) \(Int($0.width))x\(Int($0.height))" } ?? NSNull() }
        var state = extra
        state["active"] = active
        state["paused"] = paused
        state["apps"] = apps.count
        state["givenUp"] = Array(givenUp)
        if let g = geometry {
            state["display"] = text(g.display)
            state["visible"] = text(g.visible)
            state["bandTop"] = g.bandTop
        }
        state["windows"] = windows.values.map { t -> [String: Any] in
            [
                "pid": t.pid,
                "title": ax(t.element, kAXTitleAttribute) as? String ?? "",
                "frame": text(axFrame(t.element)),
                "settled": text(t.settled),
                "stuckAt": text(t.stuckAt),
                "record": t.record.map { ["before": text($0.before), "full": text($0.full), "set": text($0.set)] } ?? NSNull(),
            ]
        }
        if let data = try? JSONSerialization.data(withJSONObject: state, options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: url)
        }
    }
    #else
    @inline(__always) private func trace(_ message: @autoclosure () -> String) {}
    #endif
}

/// Accessibility notifications, delivered on the engine's thread (a C callback, so it can't capture anything).
private let clearanceCallback: AXObserverCallback = { _, element, notification, refcon in
    guard let refcon else { return }
    Unmanaged<ClearanceEngine>.fromOpaque(refcon).takeUnretainedValue().received(notification as String, element)
}

/// Which Spaces a window is on, through private SkyLight calls looked up at runtime, as SystemDockMonitor's
/// are (yabai and AltTab use the same ones). If they're missing, no window counts as full screen here and
/// `AXFullScreen` is all there is.
private enum FullScreenSpaces {
    private typealias MainConnection = @convention(c) () -> Int32
    private typealias SpacesForWindows = @convention(c) (Int32, Int32, CFArray) -> Unmanaged<CFArray>?
    private typealias SpaceType = @convention(c) (Int32, UInt64) -> Int32

    private static let calls: (connection: Int32, spaces: SpacesForWindows, type: SpaceType)? = {
        guard let sky = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_LAZY),
              let main = dlsym(sky, "SLSMainConnectionID"), let spaces = dlsym(sky, "SLSCopySpacesForWindows"),
              let type = dlsym(sky, "SLSSpaceGetType") else { return nil }
        return (unsafeBitCast(main, to: MainConnection.self)(), unsafeBitCast(spaces, to: SpacesForWindows.self),
                unsafeBitCast(type, to: SpaceType.self))
    }()

    /// Space type 4 is a full-screen app's (checked on macOS 27.0.1: a full-screen TextEdit window, and the
    /// active Space while it showed).
    static func contains(_ window: CGWindowID) -> Bool {
        guard let calls, let list = calls.spaces(calls.connection, 7, [NSNumber(value: window)] as CFArray)?.takeRetainedValue(),
              let spaces = list as? [NSNumber] else { return false }
        return spaces.contains { calls.type(calls.connection, $0.uint64Value) == 4 }
    }
}

/// A thread that runs a run loop forever, for the Accessibility observers and the timers that go with them.
private final class WorkerThread: Thread {
    private var loop: CFRunLoop?
    private let started = DispatchSemaphore(value: 0)

    override init() {
        super.init()
        name = "OldMacDoc window clearance"
        qualityOfService = .userInitiated
        start()
        started.wait()
    }

    override func main() {
        loop = CFRunLoopGetCurrent()
        // A port keeps the run loop running with nothing else in it.
        RunLoop.current.add(NSMachPort(), forMode: .default)
        started.signal()
        // A thread of its own drains no autorelease pool unless it's given one.
        while true { autoreleasepool { _ = RunLoop.current.run(mode: .default, before: .distantFuture) } }
    }

    func perform(_ block: @escaping () -> Void) {
        guard let loop else { return }
        CFRunLoopPerformBlock(loop, CFRunLoopMode.defaultMode.rawValue, block)
        CFRunLoopWakeUp(loop)
    }
}
