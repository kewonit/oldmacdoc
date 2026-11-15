import AppKit
import Combine

/// Borderless, never-key panel on every desktop. Clicks pass through except over the shelf.
///
/// macOS always draws its own Dock in Mission Control and App Exposé. While Apple's Dock waits on a
/// side edge, it shows there as a thin strip, and the panel is `.stationary` so ours stays on screen
/// at the bottom, as the real Dock does. Otherwise it's `.transient`, so the system takes it away
/// there and the two docks never overlap. Without `.fullScreenAuxiliary` the system keeps it off
/// full-screen Spaces (a bounds check can't tell full screen from a zoomed window on displays with a notch).
final class DockPanel: NSPanel {
    static let staysInMissionControl: NSWindow.CollectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenNone]
    static let leavesMissionControl: NSWindow.CollectionBehavior = [.canJoinAllSpaces, .transient, .ignoresCycle, .fullScreenNone]

    init() {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        collectionBehavior = Self.leavesMissionControl
        hidesOnDeactivate = false
        isMovable = false
        isFloatingPanel = true
        // After isFloatingPanel, which resets the level to .floating. Same level as Apple's Dock.
        level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.dockWindow)))
        becomesKeyOnlyIfNeeded = true
        ignoresMouseEvents = true
        acceptsMouseMovedEvents = true
        animationBehavior = .none
        isReleasedWhenClosed = false
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

final class DockWindowController {
    let panel = DockPanel()
    let view: DockView
    private let blur = NSVisualEffectView()
    private let settings: SettingsStore
    private let trash: TrashMonitor
    private var monitors: [Any] = []
    private var observers: [(NotificationCenter, NSObjectProtocol)] = []
    private var bag = Set<AnyCancellable>()
    private var lastSettings: AppSettings
    /// Shape the current blur mask was drawn for (height, lip, overhang).
    private var maskShape: [CGFloat] = []

    private var revealed = true
    #if DEBUG
    /// While set, real mouse events are ignored so a simulated pointer sticks.
    private var debugHold = false
    #endif
    private var revealWork: DispatchWorkItem?
    private var hideWork: DispatchWorkItem?
    /// When a mouse event last found the pointer on the bottom edge (system uptime), to tell a push
    /// into the edge from a pointer resting on it.
    private var lastEdgeEvent: TimeInterval = 0
    /// The dock magnifies at the middle of the shelf, whatever the real pointer does (while the
    /// Magnification slider is being dragged).
    private var demoMagnifying = false
    /// Mission Control or App Exposé is open and ours is the dock showing in it.
    private var inMissionControl = false

    /// Whether ours is the dock in Mission Control and App Exposé, coming up there as Apple's would.
    /// Only while Apple's Dock waits on a side edge (see AppleDockManager), where its own appearance
    /// there can't land on ours; otherwise ours steps aside.
    var showsInMissionControl = false {
        didSet {
            guard showsInMissionControl != oldValue else { return }
            panel.collectionBehavior = showsInMissionControl ? DockPanel.staysInMissionControl : DockPanel.leavesMissionControl
            systemDockChanged(systemDock?.isShowingSystemDock ?? false)
        }
    }
    /// While set (the settings panel is open), the dock stays up even in auto-hide, so every change
    /// made in the panel can be seen. Letting go hides it again shortly after, if it hides automatically.
    var isHeldRevealed = false {
        didSet {
            guard isHeldRevealed != oldValue else { return }
            updateStuckCheck()
            if isHeldRevealed {
                hideWork?.cancel()
                hideWork = nil
                if !revealed, !systemDockInTheWay { setRevealed(true) }
            } else if settings.settings.autoHide, !view.isBusy, !pointerIsOverDock() {
                scheduleHide(after: AutoHide.afterHoldDelay)
            }
        }
    }

    /// Reveals are held off briefly around Space switches, when macOS animates its own UI.
    private var revealBlockedUntil = Date.distantPast
    /// While shown in auto-hide mode, a slow check makes sure the dock can never get stuck up
    /// (for example after Mission Control or wake, when no mouse event arrives).
    private var stuckCheck: Timer?
    private var systemDock: SystemDockMonitor?

    init(model: DockModel, settings: SettingsStore, icons: IconEngine) {
        self.settings = settings
        trash = TrashMonitor()
        lastSettings = settings.settings
        view = DockView(model: model, settings: settings, icons: icons, trash: trash)

        let container = NSView()
        container.wantsLayer = true
        blur.blendingMode = .behindWindow
        blur.state = .active
        view.autoresizingMask = [.width, .height]
        container.addSubview(blur)
        container.addSubview(view)
        panel.contentView = container

        model.onChange = { [weak self] in self?.view.reload() }
        trash.onChange = { [weak self] in self?.view.trashChanged() }
        view.onShelfChange = { [weak self] shelf, offset, opacity in self?.updateBlur(shelf, offset: offset, opacity: opacity) }
        view.onPointerActivity = { [weak self] in self?.handleMouse() }

        settings.$settings.dropFirst().receive(on: DispatchQueue.main).sink { [weak self] new in
            self?.settingsChanged(new)
        }.store(in: &bag)

        // Mouse-moved monitors need no permission (only key monitoring does). The global one is how
        // we notice the pointer while the panel lets clicks through.
        let handler: (NSEvent) -> Void = { [weak self] _ in self?.handleMouse(fromEvent: true) }
        if let m = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged, .rightMouseDragged], handler: handler) {
            monitors.append(m)
        }
        if let m = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged, .leftMouseUp], handler: { e in handler(e); return e }) {
            monitors.append(m)
        }
        observe(NotificationCenter.default, NSApplication.didChangeScreenParametersNotification) { [weak self] in
            self?.position()
            self?.reevaluate()
        }
        let ws = NSWorkspace.shared.notificationCenter
        observe(ws, NSWorkspace.activeSpaceDidChangeNotification) { [weak self] in
            self?.revealBlockedUntil = Date().addingTimeInterval(AutoHide.transitionBlackout)
            self?.reevaluate()
        }
        for name in [NSWorkspace.didWakeNotification, NSWorkspace.sessionDidBecomeActiveNotification,
                     NSWorkspace.screensDidWakeNotification] {
            observe(ws, name) { [weak self] in self?.reevaluate() }
        }
        observe(NSWorkspace.shared.notificationCenter, NSWorkspace.accessibilityDisplayOptionsDidChangeNotification) { [weak self] in
            self?.view.layoutTiles()
        }
        #if DEBUG
        installDebugHooks()
        #endif

        applyBlurStyle()
        position()
        panel.orderFrontRegardless()
        let monitor = SystemDockMonitor(watching: panel)
        monitor.onChange = { [weak self] showing in self?.systemDockChanged(showing) }
        systemDock = monitor
        if monitor.isShowingSystemDock { systemDockChanged(true) }
        // Show the dock for a moment at launch so people can find it, then auto-hide.
        if settings.settings.autoHide { scheduleHide(after: 2.5) }
        updateStuckCheck()
    }

    func close() {
        view.tearDown()
        monitors.forEach(NSEvent.removeMonitor)
        monitors.removeAll()
        observers.forEach { $0.0.removeObserver($0.1) }
        observers.removeAll()
        revealWork?.cancel()
        hideWork?.cancel()
        stuckCheck?.invalidate()
        systemDock?.stop()
        systemDock = nil
        panel.orderOut(nil)
    }

    private func observe(_ center: NotificationCenter, _ name: Notification.Name, _ action: @escaping () -> Void) {
        observers.append((center, center.addObserver(forName: name, object: nil, queue: .main) { _ in action() }))
    }

    private var screen: NSScreen? { NSScreen.screens.first }

    /// The window never moves: it sits on the bottom edge of the main display and auto-hide slides
    /// the dock inside it (Core Animation on the display link), which keeps the slide smooth and
    /// lets it reverse mid-way.
    func position() {
        guard let screen else { return }
        // Tall enough for the largest sizes, so resizing the icons never resizes the window.
        let frame = NSRect(x: screen.frame.minX, y: screen.frame.minY, width: screen.frame.width, height: DockView.maximumHeight)
        if panel.frame != frame { panel.setFrame(frame, display: true) }
        view.layoutTiles()
    }

    private func settingsChanged(_ new: AppSettings) {
        let old = lastSettings
        lastSettings = new
        if old.shelfStyle != new.shelfStyle {
            view.applyStyle()
            applyBlurStyle()
        }
        if old.finish != new.finish || old.overrides != new.overrides {
            view.refreshIcons(force: false)
        }
        if old.iconSize != new.iconSize || old.magnifiedSize != new.magnifiedSize || old.magnification != new.magnification {
            view.layoutTiles()
        } else if old.showIndicators != new.showIndicators {
            view.layoutTiles(animated: true)
        }
        if old.autoHide != new.autoHide {
            if new.autoHide { scheduleHide(after: 0.6) } else { setRevealed(true) }
            updateStuckCheck()
        }
    }

    // MARK: Pointer, magnification and auto-hide

    /// `fromEvent` is true when a mouse event (rather than a state change) prompted the call.
    private func handleMouse(fromEvent: Bool = false) {
        #if DEBUG
        if debugHold { return }
        #endif
        if demoMagnifying { return }
        guard let screen else { return }
        let p = NSEvent.mouseLocation

        if !revealed {
            let x = p.x - panel.frame.minX
            // The bottom corners stay free for hot corners.
            let corner = AutoHide.cornerMargin
            let atEdge = p.y <= screen.frame.minY + 2 && p.x >= screen.frame.minX + corner && p.x <= screen.frame.maxX - corner
            if atEdge, x >= view.shelfRect.minX - 40, x <= view.shelfRect.maxX + 40, Date() >= revealBlockedUntil {
                // Pushing on into the edge (the mouse keeps moving with the pointer pinned there) or
                // dragging something to the dock reveals it at once; a pointer that just stops on the
                // edge has to rest there for a moment, so clicks at the bottom of a window don't summon it.
                let now = ProcessInfo.processInfo.systemUptime
                let pushing = fromEvent && now - lastEdgeEvent < AutoHide.pushWindow
                if fromEvent { lastEdgeEvent = now }
                let dragging = NSEvent.pressedMouseButtons & 1 != 0
                if dragging || pushing {
                    revealWork?.cancel()
                    revealWork = nil
                    if !systemDockInTheWay { setRevealed(true) }
                    return
                }
                if revealWork == nil {
                    let work = DispatchWorkItem { [weak self] in
                        self?.revealWork = nil
                        // Never bring ours up next to Apple's (Mission Control draws Apple's Dock).
                        guard let self, !self.systemDockInTheWay else { return }
                        self.setRevealed(true)
                    }
                    revealWork = work
                    DispatchQueue.main.asyncAfter(deadline: .now() + AutoHide.revealDelay, execute: work)
                }
            } else {
                revealWork?.cancel()
                revealWork = nil
                lastEdgeEvent = 0
            }
            return
        }

        let local = NSPoint(x: p.x - panel.frame.minX, y: p.y - panel.frame.minY)
        let inside = view.isInteractive(local) && (showsInMissionControl || !(systemDock?.isShowingSystemDock ?? false))
        if panel.ignoresMouseEvents == inside { panel.ignoresMouseEvents = !inside }
        view.pointerMoved(inside ? local : nil)

        if inside || view.isBusy {
            hideWork?.cancel()
            hideWork = nil
        } else if settings.settings.autoHide, hideWork == nil, !isHeldRevealed {
            scheduleHide(after: AutoHide.hideDelay)
        }
    }

    private func scheduleHide(after delay: TimeInterval) {
        hideWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.hideWork = nil
            #if DEBUG
            // A held dock stays where the debug commands put it, wherever the real pointer is.
            if self.debugHold { return }
            #endif
            // Up for as long as Mission Control is open, or the settings panel; closing them re-checks.
            if self.inMissionControl || self.isHeldRevealed { return }
            let p = NSEvent.mouseLocation
            let local = NSPoint(x: p.x - self.panel.frame.minX, y: p.y - self.panel.frame.minY)
            if self.settings.settings.autoHide, !self.view.isBusy, !self.view.isInteractive(local) {
                self.setRevealed(false)
            }
        }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    /// Magnifies the dock at the middle of the shelf while `on`, so the magnified size can be seen
    /// while the slider is being dragged (the real pointer is up in the settings panel).
    func demoMagnification(_ on: Bool) {
        guard on != demoMagnifying else { return }
        demoMagnifying = on
        if on {
            view.pointerMoved(NSPoint(x: view.shelfRect.midX, y: view.standY + 4))
        } else {
            view.pointerMoved(nil)
            handleMouse()
        }
    }

    private func setRevealed(_ show: Bool) {
        guard show != revealed else { return }
        revealed = show
        revealWork?.cancel()
        revealWork = nil
        lastEdgeEvent = 0
        if !show { panel.ignoresMouseEvents = true }
        view.setShown(show)
        updateStuckCheck()
        // The pointer is already on the edge: start tracking it (and magnifying) straight away.
        if show { handleMouse() }
    }

    /// macOS is drawing its own Dock where ours would be. A fresh read, so a reveal can't race the monitor.
    private var systemDockInTheWay: Bool { !showsInMissionControl && (systemDock?.check() ?? false) }

    /// macOS started or stopped drawing its own Dock (Mission Control, App Exposé, a forced reveal).
    private func systemDockChanged(_ showing: Bool) {
        if showsInMissionControl {
            // Apple's is a strip on the side: ours comes up for as long as Mission Control is open.
            view.setSteppedAside(false)
            inMissionControl = showing
            if showing {
                hideWork?.cancel()
                hideWork = nil
                setRevealed(true)
            } else {
                reevaluate()
            }
            return
        }
        inMissionControl = false
        view.setSteppedAside(showing)
        if showing {
            revealWork?.cancel()
            revealWork = nil
            panel.ignoresMouseEvents = true
        } else {
            reevaluate()
        }
    }

    /// Re-applies the right state after something the mouse monitors can't see (Space switch,
    /// Mission Control, wake, display change).
    private func reevaluate() {
        if !settings.settings.autoHide {
            setRevealed(true)
            return
        }
        if isHeldRevealed {
            if !revealed, !systemDockInTheWay { setRevealed(true) }
            return
        }
        handleMouse()
        if revealed && hideWork == nil && !pointerIsOverDock() && !view.isBusy { scheduleHide(after: AutoHide.hideDelay) }
    }

    private func pointerIsOverDock() -> Bool {
        let p = NSEvent.mouseLocation
        return view.isInteractive(NSPoint(x: p.x - panel.frame.minX, y: p.y - panel.frame.minY))
    }

    private func updateStuckCheck() {
        stuckCheck?.invalidate()
        stuckCheck = nil
        guard revealed, settings.settings.autoHide, !isHeldRevealed else { return }
        let timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            guard let self, self.revealed, self.hideWork == nil, !self.view.isBusy, !self.pointerIsOverDock() else { return }
            self.scheduleHide(after: AutoHide.hideDelay)
        }
        timer.tolerance = 0.5
        stuckCheck = timer
    }

    // MARK: Frosted / Smoke blur behind the glass

    private func applyBlurStyle() {
        let look = ShelfLook(style: settings.settings.shelfStyle)
        blur.isHidden = look.blur == nil
        if let material = look.blur {
            blur.material = material
            blur.appearance = NSAppearance(named: look.blurAppearance)
        }
        maskShape = []
        if let shelf = view.shelfGeometry {
            updateBlur(shelf, offset: max(0, view.reportedOffset), opacity: max(0, view.reportedOpacity))
        }
    }

    /// Keeps the blur exactly behind the shelf. Called inside the dock's frame transaction, so it
    /// moves in the same commit as the floor. The floor's ends have a fixed slant, so the mask is a
    /// small stretchable image (only the middle stretches) that is redrawn only when the shelf's
    /// height or slant changes, never while it widens during magnification.
    private func updateBlur(_ shelf: ShelfGeometry, offset: CGFloat, opacity: Float) {
        guard ShelfLook(style: settings.settings.shelfStyle).blur != nil else { return }
        // Slides and fades with the dock; fully hidden, it's taken out so no sliver stays on the edge.
        blur.isHidden = offset >= shelf.top || opacity <= 0
        if blur.alphaValue != CGFloat(opacity) { blur.alphaValue = CGFloat(opacity) }
        let frame = CGRect(x: shelf.frontLeft, y: -offset, width: shelf.frontRight - shelf.frontLeft, height: shelf.top)
        if blur.frame != frame { blur.frame = frame }
        let shape = [shelf.top, shelf.lip, shelf.overhang]
        guard shape != maskShape else { return }
        maskShape = shape
        blur.maskImage = Self.stretchableMask(top: shelf.top, lip: shelf.lip)
    }

    static func stretchableMask(top: CGFloat, lip: CGFloat) -> NSImage {
        let overhang = ShelfGeometry.overhang(height: top - lip)
        let cap = overhang + 4 // the slanted end plus its rounded back corner
        let width = cap * 2 + 2
        let local = ShelfGeometry(lip: lip, top: top, backLeft: overhang, backRight: width - overhang)
        let image = NSImage(size: CGSize(width: width, height: top), flipped: false) { _ in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            ctx.addPath(local.outline())
            ctx.setFillColor(.black)
            ctx.fillPath()
            return true
        }
        image.capInsets = NSEdgeInsets(top: 0, left: cap, bottom: 0, right: cap)
        image.resizingMode = .stretch
        return image
    }

    // MARK: Debug hooks (Debug builds only)

    #if DEBUG
    /// Drive the dock from outside for testing, e.g.
    /// `DistributedNotificationCenter.default().post(name: .init("com.kewonit.oldmacdoc.debug"), object: "pointer 700")`
    private func installDebugHooks() {
        let center = DistributedNotificationCenter.default()
        let token = center.addObserver(forName: Notification.Name("com.kewonit.oldmacdoc.debug"), object: nil, queue: .main) { [weak self] n in
            guard let self, let command = n.object as? String else { return }
            let parts = command.split(separator: " ").map(String.init)
            let arg = parts.count > 1 ? parts[1] : ""
            switch parts.first {
            case "hold":
                // Ignore the real mouse and rest the dock, e.g. for screenshots; "hold off" lets go.
                self.debugHold = arg != "off"
                if self.debugHold { self.view.pointerMoved(nil) }
            case "reveal": self.setRevealed(true)
            case "hide": self.setRevealed(false)
            case "pointer":
                self.hideWork?.cancel()
                self.debugHold = Double(arg) != nil
                self.view.pointerMoved(Double(arg).map { NSPoint(x: $0, y: self.view.standY + 4) })
            case "press": self.view.debugPress(at: Double(arg).map { CGFloat($0) })
            case "poof": self.view.debugPoof(at: Double(arg).map { CGFloat($0) } ?? 700)
            case "menu": Double(arg).map { self.view.debugMenu(at: CGFloat($0), seconds: 2) }
            case "keep" where parts.count > 2: self.view.model.setPinned(arg, parts[2] == "on")
            case "style": ShelfStyle(rawValue: arg).map { self.settings.settings.shelfStyle = $0 }
            case "finish": FinishLevel(rawValue: arg).map { self.settings.settings.finish = $0 }
            case "size": Double(arg).map { self.settings.settings.iconSize = $0 }
            case "stats":
                // Appends a line to oldmacdoc-stats.txt in the user's temporary folder.
                let url = FileManager.default.temporaryDirectory.appendingPathComponent("oldmacdoc-stats.txt")
                let line = Data((self.view.debugStats() + "\n").utf8)
                if let handle = try? FileHandle(forWritingTo: url) {
                    handle.seekToEndOfFile()
                    handle.write(line)
                    try? handle.close()
                } else {
                    try? line.write(to: url)
                }
            default: break
            }
        }
        observers.append((center, token))
    }
    #endif
}
