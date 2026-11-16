import AppKit
import Combine

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let settings = SettingsStore()
    let appleDock = AppleDockManager()
    let icons = IconEngine()
    let updater = UpdaterController()
    private(set) var model: DockModel!
    private var dock: DockWindowController?
    private var settingsPanel: SettingsPanelController!
    private let about = AboutWindowController()
    private var signalSources: [DispatchSourceSignal] = []
    private var timers: [Timer] = []
    private var dockPrefsObserver: NSObjectProtocol?
    private var screensObserver: NSObjectProtocol?
    private var addDesktopSideSink: AnyCancellable?
    private var isDuplicate = false
    #if DEBUG
    private var debugObservers: [NSObjectProtocol] = []
    #endif

    func applicationDidFinishLaunching(_ notification: Notification) {
        // A second copy must not touch Apple's Dock: the first one owns the backup. A copy that is
        // still on its way out (an update relaunching the app) doesn't count.
        let me = ProcessInfo.processInfo.processIdentifier
        if NSRunningApplication.runningApplications(withBundleIdentifier: Bundle.main.bundleIdentifier ?? "")
            .contains(where: { $0.processIdentifier != me && !$0.isTerminated && kill($0.processIdentifier, 0) == 0 }) {
            isDuplicate = true
            NSApp.terminate(nil)
            return
        }

        installSignalHandlers()
        model = DockModel()
        settingsPanel = SettingsPanelController(store: settings, updater: updater)
        settingsPanel.largestFitting = { [weak self] in self?.dock.map { Double($0.view.largestFittingSize) } }
        settingsPanel.previewIcons = { [weak self] in self?.dock?.view.previewItems(count: 6) ?? [] }
        settingsPanel.holdDock = { [weak self] in self?.dock?.isHeldRevealed = $0 }
        settingsPanel.demoMagnification = { [weak self] in self?.dock?.demoMagnification($0) }
        settingsPanel.showAbout = { [weak self] in self?.about.show() }
        about.checkForUpdates = { [weak self] in self?.updater.checkForUpdates() }
        about.canCheckForUpdates = { [weak self] in self?.updater.isConfigured ?? false }

        // The first launch starts the way the user had Apple's Dock: hiding automatically or not.
        if !settings.existedAtLaunch { settings.settings.autoHide = appleDock.usersAutohide }

        // Park Apple's Dock before ours appears, so the two are never on screen together. On a free side
        // edge, its Mission Control appearance stays clear of ours, so ours can show there too.
        appleDock.sideEdge = wantedSideEdge
        appleDock.hide()
        dock = DockWindowController(model: model, settings: settings, icons: icons)
        dock?.showsInMissionControl = appleDock.sideEdge != nil
        screensObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.placeAppleDock() }
        }
        // Moving Apple's Dock restarts it, so a quick Left, Right, Left in the panel does that once, after
        // the choice settles, and not at all if it ends where it started.
        addDesktopSideSink = settings.$settings.map(\.addDesktopSide).removeDuplicates().dropFirst()
            .debounce(for: .seconds(0.3), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in MainActor.assumeIsolated { self?.placeAppleDock() } }
        // The Dock posts this when its preferences change (Option-Command-D, System Settings), so it can
        // be parked again before it finishes sliding in. The poll catches silent `defaults` writes.
        dockPrefsObserver = DistributedNotificationCenter.default().addObserver(
            forName: .init("com.apple.dock.prefchanged"), object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.reassertAppleDock() }
        }
        schedule(every: 2) { [weak self] in self?.reassertAppleDock() }
        #if DEBUG
        installDebugHooks()
        #endif
        // Last, once this is known to be the only copy running.
        updater.start()
    }

    private func schedule(every interval: TimeInterval, _ block: @escaping () -> Void) {
        let timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { _ in MainActor.assumeIsolated { block() } }
        timer.tolerance = interval * 0.2
        timers.append(timer)
    }

    /// The edge Apple's Dock waits on: the one that puts Mission Control's + where the user chose (the
    /// right by default, which also keeps clear of Stage Manager on the left), or the other side when a
    /// display is against that one. nil when both sides touch a display.
    private var wantedSideEdge: String? {
        AppleDockManager.sideEdge(preferring: settings.settings.addDesktopSide.dockEdge,
                                  free: AppleDockManager.mainDisplayFreeSideEdges)
    }

    /// A display came, went or moved, or the + was moved: Apple's Dock may need another edge.
    private func placeAppleDock() {
        let edge = wantedSideEdge
        guard appleDock.isParked, edge != appleDock.sideEdge else { return }
        appleDock.sideEdge = edge
        appleDock.reassertIfNeeded()
        dock?.showsInMissionControl = edge != nil
    }

    private func reassertAppleDock() {
        guard appleDock.isParked, case .reparked(let autohideTurnedOff) = appleDock.reassertIfNeeded() else { return }
        // "Turn Dock Hiding On/Off" was aimed at the dock on screen, which is ours.
        if autohideTurnedOff { settings.settings.autoHide.toggle() }
    }

    /// Opening the app again (Finder, Spotlight) opens its settings, since there's no Dock icon to click.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        settingsPanel?.open()
        return false
    }

    func applicationWillTerminate(_ notification: Notification) {
        guard !isDuplicate else { return }
        cleanUp()
    }

    /// Closes our dock before Apple's comes back, so the two are never on screen together.
    private func cleanUp() {
        settings.flush()
        dock?.close()
        if appleDock.isParked { appleDock.restore() }
    }

    private func installSignalHandlers() {
        for sig in [SIGTERM, SIGINT, SIGHUP] {
            signal(sig, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: sig, queue: .main)
            source.setEventHandler { [weak self] in
                // Quit the normal way, so everything that listens for it runs (Sparkle installs a
                // downloaded update on quit). If that hasn't finished in a few seconds, put Apple's
                // Dock back and leave anyway.
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                    self?.cleanUp()
                    exit(0)
                }
                NSApp.terminate(nil)
            }
            source.resume()
            signalSources.append(source)
        }
    }

    #if DEBUG
    /// `panel` and `about` open those windows, for screenshots (see docs/TESTING.md; the dock's own
    /// commands are in DockWindowController).
    private func installDebugHooks() {
        let center = DistributedNotificationCenter.default()
        let token = center.addObserver(forName: Notification.Name("com.kewonit.oldmacdoc.debug"), object: nil, queue: .main) { [weak self] n in
            MainActor.assumeIsolated {
                switch n.object as? String {
                case "panel": self?.settingsPanel.open()
                case "panel off": self?.settingsPanel.close()
                case "about": self?.about.show()
                case "appearance light": NSApp.appearance = NSAppearance(named: .aqua)
                case "appearance dark": NSApp.appearance = NSAppearance(named: .darkAqua)
                case "appearance": NSApp.appearance = nil
                default: break
                }
            }
        }
        debugObservers.append(token)
    }
    #endif
}

extension AppleDockManager {
    /// The sides of the main display (the one with the menu bar) with no other display against them.
    @MainActor static var mainDisplayFreeSideEdges: Set<String> {
        guard let main = NSScreen.screens.first?.frame else { return [] }
        return freeSideEdges(main: main, others: NSScreen.screens.dropFirst().map(\.frame))
    }
}
