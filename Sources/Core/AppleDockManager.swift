import CoreGraphics
import Foundation
import Darwin

/// Abstraction over a preferences domain so the logic can be tested without touching the real Dock.
protocol DockPreferenceStore: AnyObject {
    var domain: String { get }
    func value(forKey key: String) -> Any?
    func set(_ value: AnyObject?, forKey key: String)
    func synchronize()
}

final class SystemDockPreferences: DockPreferenceStore {
    let domain: String
    init(domain: String = "com.apple.dock") { self.domain = domain }
    func value(forKey key: String) -> Any? { CFPreferencesCopyAppValue(key as CFString, domain as CFString) }
    func set(_ value: AnyObject?, forKey key: String) { CFPreferencesSetAppValue(key as CFString, value, domain as CFString) }
    func synchronize() { CFPreferencesAppSynchronize(domain as CFString) }
}

/// The user's own Dock settings, saved before we touch them. `nil` means "key was not set".
struct DockBackup: Codable, Equatable {
    /// 1: autohide and delay only. 2: also `no-bouncing`. 3: also the Dock's edge, size and magnification.
    var version: Int?
    var autohide: Bool?
    var autohideDelay: Double?
    var noBouncing: Bool?
    var orientation: String?
    var tileSize: Double?
    var magnification: Bool?
    /// The process that parked the Dock with this backup. Not one of the user's settings, so it's left
    /// out of `==`. A watchdog only restores a backup its own process owns: one left over from an
    /// earlier run (an app that quit and opened again within a second) must never touch the backup
    /// of the copy running now.
    var owner: Int32?

    static func == (a: DockBackup, b: DockBackup) -> Bool {
        a.version == b.version && a.autohide == b.autohide && a.autohideDelay == b.autohideDelay
            && a.noBouncing == b.noBouncing && a.orientation == b.orientation && a.tileSize == b.tileSize
            && a.magnification == b.magnification
    }

    static let currentVersion = 3
    /// Whether this backup recorded `no-bouncing` (older backups didn't change it, so mustn't restore it).
    var managesBouncing: Bool { (version ?? 1) >= 2 }
    /// Whether this backup recorded the Dock's edge, size and magnification (the same goes for those).
    var managesPlacement: Bool { (version ?? 1) >= 3 }
}

/// Parks Apple's Dock and puts it back exactly as it was. Parked means: auto-hide on, a reveal
/// delay of ~28 hours, and no bouncing. Without `no-bouncing`, an app asking for attention (a
/// terminal when you switch away from it, for example) makes the hidden Dock push its bouncing
/// icon up from the bottom edge, next to ours; that was verified on macOS 27.
///
/// With a `sideEdge`, parked also means waiting on that side edge at the smallest size without
/// magnification. macOS shows its Dock in Mission Control and App Exposé whatever its settings;
/// on a side edge it shows there as a thin strip, clear of ours at the bottom.
///
/// Safety net, in order:
/// 1. `restore()` on normal quit and on SIGTERM/SIGINT/SIGHUP.
/// 2. A detached watchdog that restores from the backup file if this process dies for any
///    reason (crash, force quit, kill -9). It reads the file at restore time, so it always
///    restores the latest backup.
/// 3. The backup file survives a crash, so the next launch never overwrites the originals.
///
/// Only one dock is ever visible: the app parks Apple's Dock before showing its own, re-parks it
/// immediately when the Dock reports a preference change, and restores it only after closing its own.
final class AppleDockManager {
    /// How long the pointer must rest on the screen edge before Apple's Dock shows: about 28 hours,
    /// so it never appears next to ours (1000 s would let it pop up after ~17 minutes on the edge).
    static let parkedDelay: Double = 100_000
    /// Any delay this long was set by us (including by older builds), never by the user.
    static let ownDelayThreshold: Double = 1000

    /// The smallest size the Dock allows.
    static let parkedTileSize: Double = 16

    /// "left" or "right" to park Apple's Dock on that edge, or nil to leave its edge alone. Changing
    /// it takes effect at the next `hide()` or `reassertIfNeeded()`.
    var sideEdge: String?

    /// The sides ("left", "right") of the main display with no other display against them, where
    /// Apple's Dock can wait: against another display it could come up there.
    static func freeSideEdges(main: CGRect, others: [CGRect]) -> Set<String> {
        func beside(_ f: CGRect) -> Bool { f.maxY > main.minY && f.minY < main.maxY }
        var free: Set<String> = []
        if !others.contains(where: { $0.minX == main.maxX && beside($0) }) { free.insert("right") }
        if !others.contains(where: { $0.maxX == main.minX && beside($0) }) { free.insert("left") }
        return free
    }

    /// The edge for Apple's Dock: `preferred` when it's free, else the other side when that is, else
    /// nil (leave its edge alone).
    static func sideEdge(preferring preferred: String, free: Set<String>) -> String? {
        if free.contains(preferred) { return preferred }
        return ["right", "left"].first(where: free.contains)
    }

    private let prefs: DockPreferenceStore
    let backupURL: URL
    private let useWatchdog: Bool
    private let restartDock: () -> Void
    private(set) var watchdogPID: pid_t = 0

    init(prefs: DockPreferenceStore = SystemDockPreferences(),
         backupURL: URL = Paths.appleDockBackup,
         useWatchdog: Bool = true,
         restartDock: @escaping () -> Void = AppleDockManager.relaunchDock) {
        self.prefs = prefs
        self.backupURL = backupURL
        self.useWatchdog = useWatchdog
        self.restartDock = restartDock
    }

    deinit { stopWatchdog() }

    var isParked: Bool { FileManager.default.fileExists(atPath: backupURL.path) }
    var backup: DockBackup? { JSONFile.load(DockBackup.self, from: backupURL) }

    private var currentAutohide: Bool? { (prefs.value(forKey: "autohide") as? NSNumber)?.boolValue }
    private var currentDelay: Double? { (prefs.value(forKey: "autohide-delay") as? NSNumber)?.doubleValue }
    private var currentNoBouncing: Bool? { (prefs.value(forKey: "no-bouncing") as? NSNumber)?.boolValue }
    private var currentOrientation: String? { prefs.value(forKey: "orientation") as? String }
    private var currentTileSize: Double? { (prefs.value(forKey: "tilesize") as? NSNumber)?.doubleValue }
    private var currentMagnification: Bool? { (prefs.value(forKey: "magnification") as? NSNumber)?.boolValue }
    private var isApplied: Bool {
        let placed = sideEdge.map { edge in
            currentOrientation == edge && currentTileSize == Self.parkedTileSize && currentMagnification == false
        } ?? true
        return currentAutohide == true && currentDelay == Self.parkedDelay && currentNoBouncing == true && placed
    }

    /// The Dock is on a side edge at the smallest size without magnification: how we park it.
    private var looksSideParked: Bool {
        (currentOrientation == "left" || currentOrientation == "right")
            && currentTileSize == Self.parkedTileSize && currentMagnification == false
    }

    /// Reads the live settings. A delay we set ourselves (left over from a lost backup) counts as unset.
    func readCurrent() -> DockBackup {
        var b = DockBackup(version: DockBackup.currentVersion, autohide: currentAutohide, autohideDelay: currentDelay,
                           noBouncing: currentNoBouncing, orientation: currentOrientation, tileSize: currentTileSize,
                           magnification: currentMagnification)
        if let delay = currentDelay, delay >= Self.ownDelayThreshold {
            // Left parked by a lost session: those values were ours, not the user's.
            b.autohide = nil
            b.autohideDelay = nil
            b.noBouncing = nil
            if looksSideParked {
                b.orientation = nil
                b.tileSize = nil
                b.magnification = nil
            }
        }
        return b
    }

    /// Whether the user has Apple's Dock hide automatically, for our own dock's first launch. While
    /// parked, the backup holds their real values; otherwise the live settings do (a delay we set,
    /// left over from a lost session, already counts as unset). Unset means Apple's default: off.
    var usersAutohide: Bool { (backup ?? readCurrent()).autohide ?? false }

    func hide() {
        let me = Int32(getpid())
        if !isParked {
            var fresh = readCurrent()
            fresh.owner = me
            try? JSONFile.save(fresh, to: backupURL)
        } else if var old = backup {
            if !old.managesPlacement {
                // A backup from an older version never changed these, so the live values are the user's.
                if !old.managesBouncing { old.noBouncing = currentNoBouncing }
                old.orientation = currentOrientation
                old.tileSize = currentTileSize
                old.magnification = currentMagnification
                old.version = DockBackup.currentVersion
            }
            // Left by a copy that crashed: this one takes it over, so that copy's watchdog leaves it be.
            old.owner = me
            try? JSONFile.save(old, to: backupURL)
        }
        if !isApplied { park() }
        if useWatchdog, watchdogPID == 0 { startWatchdog() }
    }

    func restore() {
        stopWatchdog()
        guard isParked else { return }
        // An unreadable backup restores Apple's defaults rather than leaving the Dock parked.
        let b = backup ?? DockBackup()
        prefs.set(b.autohide.map { NSNumber(value: $0) }, forKey: "autohide")
        prefs.set(b.autohideDelay.map { NSNumber(value: $0) }, forKey: "autohide-delay")
        if b.managesBouncing || backup == nil {
            prefs.set(b.noBouncing.map { NSNumber(value: $0) }, forKey: "no-bouncing")
        }
        // Without a readable backup, only undo a side parking that is plainly ours.
        if b.managesPlacement || (backup == nil && looksSideParked) {
            prefs.set(b.orientation.map { $0 as NSString }, forKey: "orientation")
            prefs.set(b.tileSize.map { NSNumber(value: $0) }, forKey: "tilesize")
            prefs.set(b.magnification.map { NSNumber(value: $0) }, forKey: "magnification")
        }
        prefs.synchronize()
        try? FileManager.default.removeItem(at: backupURL)
        restartDock()
    }

    enum ReassertResult: Equatable {
        case unchanged
        /// Parked again. `autohideTurnedOff` is true when auto-hide itself was switched off
        /// (Option-Command-D or System Settings), which the app treats as a toggle of its own dock.
        case reparked(autohideTurnedOff: Bool)
    }

    /// Something un-parked the Dock while we run (Option-Command-D, System Settings, `defaults`): park it again.
    /// The backup is left alone, so quitting still restores the Dock exactly as it was before launch.
    @discardableResult
    func reassertIfNeeded() -> ReassertResult {
        guard isParked else { return .unchanged }
        prefs.synchronize()
        guard !isApplied else { return .unchanged }
        let turnedOff = currentAutohide != true
        park()
        return .reparked(autohideTurnedOff: turnedOff)
    }

    private func park() {
        prefs.set(NSNumber(value: true), forKey: "autohide")
        prefs.set(NSNumber(value: Self.parkedDelay), forKey: "autohide-delay")
        prefs.set(NSNumber(value: true), forKey: "no-bouncing")
        if let sideEdge {
            prefs.set(sideEdge as NSString, forKey: "orientation")
            prefs.set(NSNumber(value: Self.parkedTileSize), forKey: "tilesize")
            prefs.set(NSNumber(value: false), forKey: "magnification")
        }
        prefs.synchronize()
        restartDock()
    }

    static func relaunchDock() {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
        process.arguments = ["Dock"]
        process.standardError = FileHandle.nullDevice
        try? process.run()
        process.waitUntilExit()
    }

    // MARK: Watchdog

    /// Run as `sh -c script name <pid> <backup.json> <domain>`. Waits for <pid> to exit, then restores
    /// from the backup if it still exists (a clean quit deletes it first) and <pid> owns it (a newer
    /// copy may already have parked the Dock with a backup of its own). Missing or unreadable values
    /// delete the key, which gives Apple's default. Whether a key is there is read from `plutil`'s exit
    /// status, never its output: some macOS versions (15, at least) print the error to standard output.
    static let watchdogScript = """
    while /bin/kill -0 "$1" 2>/dev/null; do /bin/sleep 1; done
    [ -f "$2" ] || exit 0
    if owner=$(/usr/bin/plutil -extract owner raw -o - "$2" 2>/dev/null); then
      [ "$owner" = "$1" ] || exit 0
    fi
    if v=$(/usr/bin/plutil -extract autohide raw -o - "$2" 2>/dev/null); then
      /usr/bin/defaults write "$3" autohide -bool "$v"
    else
      /usr/bin/defaults delete "$3" autohide 2>/dev/null
    fi
    if v=$(/usr/bin/plutil -extract autohideDelay raw -o - "$2" 2>/dev/null); then
      /usr/bin/defaults write "$3" autohide-delay -float "$v"
    else
      /usr/bin/defaults delete "$3" autohide-delay 2>/dev/null
    fi
    ver=$(/usr/bin/plutil -extract version raw -o - "$2" 2>/dev/null)
    if [ "${ver:-1}" -ge 2 ] 2>/dev/null; then
      if v=$(/usr/bin/plutil -extract noBouncing raw -o - "$2" 2>/dev/null); then
        /usr/bin/defaults write "$3" no-bouncing -bool "$v"
      else
        /usr/bin/defaults delete "$3" no-bouncing 2>/dev/null
      fi
    fi
    if [ "${ver:-1}" -ge 3 ] 2>/dev/null; then
      if v=$(/usr/bin/plutil -extract orientation raw -o - "$2" 2>/dev/null); then
        /usr/bin/defaults write "$3" orientation -string "$v"
      else
        /usr/bin/defaults delete "$3" orientation 2>/dev/null
      fi
      if v=$(/usr/bin/plutil -extract tileSize raw -o - "$2" 2>/dev/null); then
        /usr/bin/defaults write "$3" tilesize -float "$v"
      else
        /usr/bin/defaults delete "$3" tilesize 2>/dev/null
      fi
      if v=$(/usr/bin/plutil -extract magnification raw -o - "$2" 2>/dev/null); then
        /usr/bin/defaults write "$3" magnification -bool "$v"
      else
        /usr/bin/defaults delete "$3" magnification 2>/dev/null
      fi
    fi
    /bin/rm -f "$2"
    [ "$3" = com.apple.dock ] && /usr/bin/killall Dock
    exit 0
    """

    /// Spawns the watchdog in its own session so it outlives this process and its process group.
    /// It gets /dev/null for stdio and inherits no other file descriptors.
    ///
    /// Its signals are reset to their defaults. The app ignores SIGTERM, SIGINT and SIGHUP (it handles
    /// them on a dispatch source), and an ignored signal stays ignored across exec: without the reset,
    /// the SIGTERM `stopWatchdog()` sends on quit did nothing, and a watchdog outlived every quit.
    @discardableResult
    static func spawnWatchdog(watching pid: pid_t, backupURL: URL, domain: String) -> pid_t {
        var attr: posix_spawnattr_t?
        posix_spawnattr_init(&attr)
        defer { posix_spawnattr_destroy(&attr) }
        var defaults = sigset_t()
        sigemptyset(&defaults)
        for sig in [SIGTERM, SIGINT, SIGHUP] { sigaddset(&defaults, sig) }
        posix_spawnattr_setsigdefault(&attr, &defaults)
        var unblocked = sigset_t()
        sigemptyset(&unblocked)
        posix_spawnattr_setsigmask(&attr, &unblocked)
        posix_spawnattr_setflags(&attr, Int16(POSIX_SPAWN_SETSIGDEF | POSIX_SPAWN_SETSIGMASK
            | 0x0400 /* POSIX_SPAWN_SETSID */ | 0x4000 /* POSIX_SPAWN_CLOEXEC_DEFAULT */))
        var files: posix_spawn_file_actions_t?
        posix_spawn_file_actions_init(&files)
        defer { posix_spawn_file_actions_destroy(&files) }
        posix_spawn_file_actions_addopen(&files, 0, "/dev/null", O_RDONLY, 0)
        posix_spawn_file_actions_addopen(&files, 1, "/dev/null", O_WRONLY, 0)
        posix_spawn_file_actions_addopen(&files, 2, "/dev/null", O_WRONLY, 0)

        let args = ["/bin/sh", "-c", watchdogScript, "oldmacdoc-dock-watchdog", String(pid), backupURL.path, domain]
        var cArgs: [UnsafeMutablePointer<CChar>?] = args.map { strdup($0) } + [nil]
        defer { cArgs.forEach { free($0) } }

        var child: pid_t = 0
        return posix_spawn(&child, "/bin/sh", &files, &attr, &cArgs, environ) == 0 ? child : 0
    }

    private func startWatchdog() {
        watchdogPID = Self.spawnWatchdog(watching: getpid(), backupURL: backupURL, domain: prefs.domain)
    }

    private func stopWatchdog() {
        guard watchdogPID > 0 else { return }
        let pid = watchdogPID
        watchdogPID = 0
        kill(pid, SIGTERM)
        DispatchQueue.global(qos: .utility).async { var status: Int32 = 0; waitpid(pid, &status, 0) }
    }
}
