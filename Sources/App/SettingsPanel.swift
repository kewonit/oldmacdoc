import AppKit
import Combine
import ServiceManagement
import SwiftUI

/// The window under the menu bar icon, like Control Center's: it takes keyboard focus without making
/// OldMacDoc the active app (the app in front keeps its menus), and closes on Esc, ⌘W or a click
/// anywhere else. ⌘Q quits OldMacDoc from it.
final class SettingsPanel: NSPanel {
    var onDismiss: (() -> Void)?

    init() {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        isFloatingPanel = true
        level = .popUpMenu // after isFloatingPanel, which resets the level; above the dock
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isMovable = false
        isReleasedWhenClosed = false
        animationBehavior = .utilityWindow
        title = AppInfo.name // what VoiceOver calls the panel
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    override func cancelOperation(_ sender: Any?) { onDismiss?() }

    override func resignKey() {
        super.resignKey()
        onDismiss?()
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command {
            switch event.charactersIgnoringModifiers {
            case "w": onDismiss?(); return true
            case "q": NSApp.terminate(nil); return true
            default: break
            }
        }
        return super.performKeyEquivalent(with: event)
    }
}

/// Reports changes to its content's size, so the panel can follow them (an update row appearing, say).
private final class SizeReportingHostingView<Content: View>: NSHostingView<Content> {
    var onSizeChange: (() -> Void)?

    override func invalidateIntrinsicContentSize() {
        super.invalidateIntrinsicContentSize()
        onSizeChange?()
    }
}

/// The menu bar icon and the settings panel under it.
///
/// On macOS 27 and later the icon opens the panel through the status item's expanded-interface
/// session, so it takes part in menu bar tracking like a menu; earlier, clicking the icon toggles it.
/// While the panel is open the dock stays up, even in auto-hide, so every change can be seen.
@MainActor
final class SettingsPanelController: NSObject {
    /// The largest icon size that fits on screen now.
    var largestFitting: () -> Double? = { nil }
    /// The first few apps on the dock, for the pictures of each shelf.
    var previewIcons: () -> [ShelfPreview.Item] = { [] }
    /// Keep the dock up (true) or let it hide again (false).
    var holdDock: (Bool) -> Void = { _ in }
    /// Magnify the dock at the middle of the shelf while the Magnification slider is being dragged.
    var demoMagnification: (Bool) -> Void = { _ in }
    var showAbout: () -> Void = {}

    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let panel = SettingsPanel()
    private let model = SettingsPanelModel()
    private let store: SettingsStore
    private let updater: UpdaterController
    private var hosting: SizeReportingHostingView<SettingsView>!
    private var monitors: [Any] = []
    private var observers: [(NotificationCenter, NSObjectProtocol)] = []
    private var bag = Set<AnyCancellable>()
    private(set) var isOpen = false

    init(store: SettingsStore, updater: UpdaterController) {
        self.store = store
        self.updater = updater
        super.init()

        let actions = SettingsActions(
            about: { [weak self] in
                self?.close()
                self?.showAbout()
            },
            checkForUpdates: { [weak self] in
                self?.close()
                self?.updater.checkForUpdates()
            },
            quit: { NSApp.terminate(nil) },
            openLoginItems: { [weak self] in
                self?.close()
                SMAppService.openSystemSettingsLoginItems()
            },
            magnifying: { [weak self] in self?.demoMagnification($0) },
            openAccessibility: { [weak self] in
                self?.close()
                AccessibilityAccess.ask()
                AccessibilityAccess.openSettings()
            })
        hosting = SizeReportingHostingView(rootView: SettingsView(store: store, model: model, updater: updater, actions: actions))
        hosting.onSizeChange = { [weak self] in
            // After SwiftUI's layout pass, not inside it.
            DispatchQueue.main.async { if self?.isOpen == true { self?.placePanel() } }
        }
        panel.contentView = makeBackground()
        panel.onDismiss = { [weak self] in self?.close() }

        if let button = item.button {
            button.image = Self.icon(badged: false)
            button.toolTip = AppInfo.name
            button.setAccessibilityLabel(AppInfo.name)
        }
        if usesExpandedInterface {
            #if compiler(>=6.4)
            if #available(macOS 27, *) { item.expandedInterfaceDelegate = self }
            #endif
        } else if let button = item.button {
            button.target = self
            button.action = #selector(toggle)
            button.sendAction(on: [.leftMouseDown, .rightMouseDown])
        }

        // A dot on the icon while an update found in the background waits to be looked at.
        updater.$needsAttention.removeDuplicates().sink { [weak self] waiting in
            guard let button = self?.item.button else { return }
            button.image = Self.icon(badged: waiting)
            let label = waiting ? "\(AppInfo.name), update available" : AppInfo.name
            button.toolTip = label
            button.setAccessibilityLabel(label)
        }.store(in: &bag)
        updater.willShowAlert = { [weak self] in self?.close() }
    }

    /// Opens the panel, for when the app is opened again from Finder or Spotlight (there's no Dock icon
    /// to click). If the menu bar is too full to show the icon, it opens at the top right of the screen.
    func open() {
        present()
    }

    /// Closes the panel and lets the dock hide again. Safe to call at any time.
    func close() {
        guard isOpen else { return }
        isOpen = false
        removeMonitors()
        demoMagnification(false)
        holdDock(false)
        store.flush()
        panel.orderOut(nil)
        item.button?.highlight(false)
        #if compiler(>=6.4)
        if #available(macOS 27, *), let session = item.expandedInterfaceSession { session.cancel() }
        #endif
    }

    @objc private func toggle() {
        if isOpen { close() } else { present() }
    }

    private func present() {
        guard !isOpen else { return }
        isOpen = true
        model.refresh(largestFitting: largestFitting(), icons: previewIcons(), screen: screen)
        placePanel()
        panel.makeKeyAndOrderFront(nil)
        holdDock(true)
        installMonitors()
        // The button drops its highlight when the mouse goes up; keep it lit while the panel is open.
        if !usesExpandedInterface {
            DispatchQueue.main.async { [weak self] in self?.item.button?.highlight(self?.isOpen ?? false) }
        }
    }

    // MARK: Where the panel goes

    private var usesExpandedInterface: Bool {
        #if compiler(>=6.4)
        if #available(macOS 27, *) {
            #if DEBUG
            // `defaults write com.kewonit.oldmacdoc OldMacDocLegacyStatusItem -bool YES` tries the macOS 14–26 path.
            if UserDefaults.standard.bool(forKey: "OldMacDocLegacyStatusItem") { return false }
            #endif
            return true
        }
        #endif
        return false
    }

    private var itemIsVisible: Bool {
        guard item.isVisible, let window = item.button?.window else { return false }
        return window.occlusionState.contains(.visible)
    }

    private var itemFrame: CGRect? {
        guard itemIsVisible, let button = item.button, let window = button.window else { return nil }
        return window.convertToScreen(button.convert(button.bounds, to: nil))
    }

    /// Nil for a moment when no display is attached (the lid closes with none other, or while the
    /// displays are rearranged); the panel stays where it is until one is back.
    private var screen: NSScreen? {
        if itemIsVisible, let screen = item.button?.window?.screen { return screen }
        let pointer = NSEvent.mouseLocation
        return NSScreen.screens.first { $0.frame.contains(pointer) } ?? NSScreen.main ?? NSScreen.screens.first
    }

    private func placePanel() {
        guard let screen = self.screen else { return }
        let menuBar = max(NSStatusBar.system.thickness, screen.frame.maxY - screen.visibleFrame.maxY)
        let frame = PanelPlacement.frame(size: hosting.fittingSize, item: itemFrame, screen: screen.frame,
                                         visible: screen.visibleFrame, menuBarHeight: menuBar)
        if panel.frame != frame { panel.setFrame(frame, display: true) }
        panel.invalidateShadow()
    }

    /// Liquid Glass on macOS 26 and later; the menu material before that.
    private func makeBackground() -> NSView {
        #if compiler(>=6.2)
        if #available(macOS 26, *) {
            let radius: CGFloat = 18
            let glass = NSGlassEffectView()
            glass.cornerRadius = radius
            glass.contentView = hosting
            glass.autoresizingMask = [.width, .height]
            // The glass draws a faint shadow of its own into the window's square corners, and the window
            // shadow follows whatever isn't fully clear, so it came out square behind the round glass.
            // Clipping to the glass's shape leaves the corners clear and the window shadow round.
            let clip = NSView()
            clip.wantsLayer = true
            clip.layer?.cornerRadius = radius
            clip.layer?.cornerCurve = .continuous
            clip.layer?.masksToBounds = true
            glass.frame = clip.bounds
            clip.addSubview(glass)
            return clip
        }
        #endif
        let effect = NSVisualEffectView()
        effect.material = .menu
        effect.blendingMode = .behindWindow
        effect.state = .active
        effect.maskImage = Self.roundedMask(radius: 12)
        hosting.frame = effect.bounds
        hosting.autoresizingMask = [.width, .height]
        effect.addSubview(hosting)
        return effect
    }

    private static func roundedMask(radius: CGFloat) -> NSImage {
        let side = radius * 2 + 1
        let image = NSImage(size: NSSize(width: side, height: side), flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
            return true
        }
        image.capInsets = NSEdgeInsets(top: radius, left: radius, bottom: radius, right: radius)
        image.resizingMode = .stretch
        return image
    }

    // MARK: Closing on clicks elsewhere

    private func installMonitors() {
        let mouseDown: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        // Clicks in other apps, on the desktop or in the menu bar.
        if let m = NSEvent.addGlobalMonitorForEvents(matching: mouseDown, handler: { [weak self] _ in
            MainActor.assumeIsolated { self?.close() }
        }) { monitors.append(m) }
        // Clicks on our own dock, which never takes keyboard focus, so the panel doesn't lose it. The
        // click still goes through. Clicks in the menu bar are the icon's own business (it toggles);
        // the icon's window isn't always `item.button.window` during a menu bar session.
        if let m = NSEvent.addLocalMonitorForEvents(matching: mouseDown, handler: { [weak self] event in
            MainActor.assumeIsolated {
                guard let self, let window = event.window, window !== self.panel, window.level < .statusBar else { return }
                self.close()
            }
            return event
        }) { monitors.append(m) }
        let ws = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.activeSpaceDidChangeNotification, NSWorkspace.willSleepNotification,
                     NSWorkspace.sessionDidResignActiveNotification] {
            observe(ws, name)
        }
        observe(.default, NSApplication.didChangeScreenParametersNotification)
    }

    private func observe(_ center: NotificationCenter, _ name: Notification.Name) {
        let token = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.close() }
        }
        observers.append((center, token))
    }

    private func removeMonitors() {
        monitors.forEach(NSEvent.removeMonitor)
        monitors.removeAll()
        observers.forEach { $0.0.removeObserver($0.1) }
        observers.removeAll()
    }

    // MARK: Menu bar icon

    /// The dock symbol, with a small dot in its corner while an update waits. A template image, so the
    /// menu bar tints it.
    private static func icon(badged: Bool) -> NSImage {
        let symbol = NSImage(systemSymbolName: "dock.rectangle", accessibilityDescription: AppInfo.name) ?? NSImage()
        guard badged else {
            symbol.isTemplate = true
            return symbol
        }
        let size = symbol.size
        let image = NSImage(size: size, flipped: false) { rect in
            symbol.draw(in: rect)
            let d = (size.height * 0.42).rounded()
            let dot = NSRect(x: rect.maxX - d, y: rect.maxY - d, width: d, height: d)
            // A clear ring sets the dot apart from the symbol under it.
            NSGraphicsContext.current?.compositingOperation = .clear
            NSBezierPath(ovalIn: dot.insetBy(dx: -1.5, dy: -1.5)).fill()
            NSGraphicsContext.current?.compositingOperation = .sourceOver
            NSColor.black.setFill()
            NSBezierPath(ovalIn: dot).fill()
            return true
        }
        image.isTemplate = true
        return image
    }
}

#if compiler(>=6.4)
@available(macOS 27, *)
extension SettingsPanelController: NSStatusItemExpandedInterfaceDelegate {
    // AppKit calls these on the main thread.
    nonisolated func statusItem(_ statusItem: NSStatusItem, didBegin session: NSStatusItemExpandedInterfaceSession) {
        MainActor.assumeIsolated {
            // Already open (from Finder or Spotlight, without a session): this click means close.
            if isOpen { close() } else { present() }
        }
    }

    nonisolated func statusItemDidEndExpandedInterfaceSession(_ statusItem: NSStatusItem, animated: Bool) {
        MainActor.assumeIsolated { close() }
    }
}
#endif
