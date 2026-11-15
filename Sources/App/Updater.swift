import AppKit
import Combine
import Sparkle

/// Automatic updates with Sparkle 2, from the appcast on GitHub Releases (`SUFeedURL`), checked once
/// a day (`SUEnableAutomaticChecks`, so there is no permission prompt).
///
/// OldMacDoc has no Dock icon and is never the active app, so Sparkle's own alert for an update found
/// in the background would open behind other windows. It uses Sparkle's "gentle reminders" instead:
/// the alert only shows when it can take focus (right after launch); otherwise the menu bar icon gets
/// a dot and the settings panel offers the update, which brings up the alert when chosen.
@MainActor
final class UpdaterController: NSObject, ObservableObject {
    /// The version waiting to be installed, until its update session ends (shown in the panel).
    @Published private(set) var availableVersion: String?
    /// A scheduled check found an update the user hasn't looked at yet (the dot on the menu bar icon).
    @Published private(set) var needsAttention = false
    /// Whether a check can start now (not while one is running).
    @Published private(set) var canCheck = false

    /// Called before Sparkle shows an alert, so the settings panel can get out of its way.
    var willShowAlert: (() -> Void)?

    private var controller: SPUStandardUpdaterController?
    private var subscription: AnyCancellable?

    /// Whether this copy updates itself: it needs the signing key's public half in Info.plist, and
    /// Debug builds only do when asked to (a release would replace the build being worked on), with
    /// `defaults write com.kewonit.oldmacdoc OldMacDocDebugUpdates -bool YES`.
    var isConfigured: Bool { controller != nil }

    override init() {
        super.init()
        guard let key = Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String, !key.isEmpty else { return }
        #if DEBUG
        guard UserDefaults.standard.bool(forKey: "OldMacDocDebugUpdates") else { return }
        #endif
        let controller = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: nil, userDriverDelegate: self)
        self.controller = controller
        subscription = controller.updater.publisher(for: \.canCheckForUpdates)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.canCheck = $0 }
    }

    /// Starts checking. Called at the end of launch, once this is known to be the only copy running.
    func start() {
        controller?.startUpdater()
    }

    /// Checks now, or brings back the alert for an update already found.
    func checkForUpdates() {
        controller?.checkForUpdates(nil)
    }
}

extension UpdaterController: SPUStandardUserDriverDelegate {
    nonisolated var supportsGentleScheduledUpdateReminders: Bool { true }

    /// Sparkle shows a scheduled update itself only when it can take focus (just after launch).
    nonisolated func standardUserDriverShouldHandleShowingScheduledUpdate(_ update: SUAppcastItem,
                                                                       andInImmediateFocus immediateFocus: Bool) -> Bool {
        immediateFocus
    }

    nonisolated func standardUserDriverWillHandleShowingUpdate(_ handleShowingUpdate: Bool, forUpdate update: SUAppcastItem,
                                                               state: SPUUserUpdateState) {
        let version = update.displayVersionString
        let userInitiated = state.userInitiated
        MainActor.assumeIsolated {
            availableVersion = version
            if !handleShowingUpdate && !userInitiated { needsAttention = true }
        }
    }

    nonisolated func standardUserDriverDidReceiveUserAttention(forUpdate update: SUAppcastItem) {
        MainActor.assumeIsolated { needsAttention = false }
    }

    nonisolated func standardUserDriverWillFinishUpdateSession() {
        MainActor.assumeIsolated {
            needsAttention = false
            availableVersion = nil
        }
    }

    nonisolated func standardUserDriverWillShowModalAlert() {
        MainActor.assumeIsolated { willShowAlert?() }
    }
}
