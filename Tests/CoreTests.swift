import CoreImage
import XCTest

/// Draws a synthetic 1024 icon: a rounded-square body with a circle of artwork in the middle.
private func makeIcon(body: (CGFloat, CGFloat, CGFloat), art: (CGFloat, CGFloat, CGFloat), artSide: CGFloat = 0.5,
                      artTouchesEdges: Bool = false) -> Bitmap {
    let size = 1024
    let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: size * 4,
                        space: Bitmap.colorSpace, bitmapInfo: Bitmap.bitmapInfo)!
    let bodyRect = CGRect(x: 100, y: 100, width: 824, height: 824)
    ctx.addPath(CGPath(roundedRect: bodyRect, cornerWidth: 185, cornerHeight: 185, transform: nil))
    ctx.setFillColor(CGColor(srgbRed: body.0, green: body.1, blue: body.2, alpha: 1))
    ctx.fillPath()
    let side = artTouchesEdges ? bodyRect.width : bodyRect.width * artSide
    let artRect = CGRect(x: 512 - side / 2, y: 512 - side / 2, width: side, height: side)
    ctx.setFillColor(CGColor(srgbRed: art.0, green: art.1, blue: art.2, alpha: 1))
    if artTouchesEdges { ctx.fill(CGRect(x: bodyRect.minX, y: 480, width: bodyRect.width, height: 64)) } else { ctx.fillEllipse(in: artRect) }
    return Bitmap(cgImage: ctx.makeImage()!, size: size)!
}

final class PlateDetectorTests: XCTestCase {
    func testLiftsGrayPlate() throws {
        let icon = makeIcon(body: (0.86, 0.86, 0.86), art: (0.9, 0.1, 0.1))
        let lifted = try XCTUnwrap(PlateDetector.lift(icon))
        XCTAssertEqual(lifted.alpha(300, 512), 0, "plate area should be cut away")
        XCTAssertEqual(lifted.alpha(150, 150), 0, "corners should be transparent")
        let centre = lifted.color(512, 512)
        XCTAssertGreaterThan(centre.w, 0.99)
        XCTAssertGreaterThan(centre.x, 0.85)
        XCTAssertLessThan(centre.y, 0.15)
    }

    func testLeavesColouredBackgroundAlone() {
        let icon = makeIcon(body: (0.1, 0.4, 0.95), art: (1, 1, 1))
        XCTAssertNil(PlateDetector.lift(icon), "a deliberate blue background is not a gray plate")
    }

    func testNotConfidentWhenArtworkTouchesEdges() {
        let icon = makeIcon(body: (0.86, 0.86, 0.86), art: (0.2, 0.2, 0.9), artTouchesEdges: true)
        XCTAssertNil(PlateDetector.lift(icon))
    }

    func testFullBleedIconIsUntouched() {
        // A normal full-squircle icon with a gradient-free white body and big artwork.
        let icon = makeIcon(body: (1, 1, 1), art: (0.2, 0.6, 0.2), artSide: 0.5)
        XCTAssertNil(PlateDetector.lift(icon), "pure white backgrounds are excluded by the luminance band")
    }
}

final class NormalizerAndFinishTests: XCTestCase {
    func testBitmapKeepsAspectRatio() throws {
        let ctx = CGContext(data: nil, width: 400, height: 100, bitsPerComponent: 8, bytesPerRow: 1600,
                            space: Bitmap.colorSpace, bitmapInfo: Bitmap.bitmapInfo)!
        ctx.setFillColor(CGColor(srgbRed: 0, green: 0, blue: 1, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: 400, height: 100))
        let bmp = try XCTUnwrap(Bitmap(cgImage: ctx.makeImage()!, size: 400))
        let b = try XCTUnwrap(bmp.opaqueBounds(threshold: 128))
        XCTAssertEqual(b.width, 400)
        XCTAssertEqual(b.height, 100, accuracy: 1)
    }

    func testSoftShadowDoesNotLiftIcon() throws {
        var icon = Bitmap(width: 1024, height: 1024)
        for y in 100..<800 { for x in 100..<900 { icon.set(x, y, rgb: SIMD3(1, 0, 0), alpha: 1) } }
        for y in 800..<900 { for x in 100..<900 { icon.set(x, y, rgb: SIMD3(0, 0, 0), alpha: 0.12) } } // faint shadow below
        let out = try XCTUnwrap(IconNormalizer.normalize(icon, outputSize: 512))
        XCTAssertEqual(out.contentRect.minY, 512 * IconNormalizer.bottomMargin, accuracy: 1, "solid art stands on the bottom")
        XCTAssertEqual(out.contentRect.width, 512 * IconNormalizer.targetFill, accuracy: 1.5)
    }

    func testNormalizesSizeAndStandsOnBottom() throws {
        var small = Bitmap(width: 1024, height: 1024)
        for y in 10..<210 { for x in 10..<210 { small.set(x, y, rgb: SIMD3(1, 0, 0), alpha: 1) } }
        let out = try XCTUnwrap(IconNormalizer.normalize(small, outputSize: 512))
        XCTAssertEqual(out.contentRect.width, 512 * IconNormalizer.targetFill, accuracy: 1.5)
        XCTAssertEqual(out.contentRect.midX, 256, accuracy: 1)
        XCTAssertEqual(out.contentRect.minY, 512 * IconNormalizer.bottomMargin, accuracy: 1)
    }

    func testFinishKeepsSizeAndTransparency() throws {
        let icon = makeIcon(body: (0.2, 0.5, 0.9), art: (1, 1, 1))
        let sized = try XCTUnwrap(IconNormalizer.normalize(icon, outputSize: 512))
        let tuning = try XCTUnwrap(RetroFinish.tuning(level: .full))
        let finished = try XCTUnwrap(RetroFinish.apply(sized.image, contentRect: sized.contentRect, tuning: tuning, context: CIContext()))
        XCTAssertEqual(finished.width, 512)
        let bmp = try XCTUnwrap(Bitmap(cgImage: finished, size: 512))
        XCTAssertEqual(bmp.alpha(2, 510), 0, "finish must not spill outside the icon")
        XCTAssertGreaterThan(bmp.alpha(256, 200), 250)
        XCTAssertNil(RetroFinish.tuning(level: .off))
    }
}

final class LayoutTests: XCTestCase {
    private func row(pointer: CGFloat?, gap: Int? = nil) -> RowLayout {
        RowLayout.make(count: 9, baseSize: 48, spacing: 6, gapBefore: gap, gap: 20, centerX: 500,
                       pointerX: pointer, maxScale: 128.0 / 48, effectWidth: 144)
    }

    func testRestingRowIsCentred() {
        let r = row(pointer: nil, gap: 8)
        XCTAssertEqual((r.slots.first!.minX - 3 + r.slots.last!.maxX + 3) / 2, 500, accuracy: 0.01)
        XCTAssertTrue(r.slots.allSatisfy { $0.size == 48 })
    }

    func testIconUnderPointerReachesMagnifiedSizeAndStaysPut() {
        let target = row(pointer: nil).slots[4].center
        let r = row(pointer: target)
        XCTAssertEqual(r.slots[4].size, 128, accuracy: 0.01)
        XCTAssertEqual(r.slots[4].center, target, accuracy: 0.01)
        // Falls off with distance, symmetric, back to rest beyond the effect width.
        XCTAssertGreaterThan(r.slots[3].size, r.slots[2].size)
        XCTAssertGreaterThan(r.slots[2].size, r.slots[1].size)
        XCTAssertEqual(r.slots[3].size, r.slots[5].size, accuracy: 0.01)
        XCTAssertEqual(r.slots[0].size, 48, accuracy: 1)
        // The row grows evenly on both sides.
        let rest = row(pointer: nil)
        XCTAssertEqual(rest.slots[0].center - r.slots[0].center, r.slots[8].center - rest.slots[8].center, accuracy: 0.01)
    }

    func testTilesStayContiguousWhilePointerMoves() {
        for p in stride(from: CGFloat(200), through: 800, by: 7) {
            let r = row(pointer: p)
            for i in 1..<r.slots.count {
                let gapBetween = r.slots[i].minX - r.slots[i - 1].maxX
                XCTAssertGreaterThan(gapBetween, 0, "icons never overlap (pointer \(p))")
            }
            XCTAssertLessThanOrEqual(r.slots.map(\.size).max()!, 128.001)
        }
    }

    func testShelfKeepsConstantOverhangAndRecedes() {
        // dockify's formula: a 52 pt floor sticks out 30 pt at each front corner.
        XCTAssertEqual(ShelfGeometry.overhang(height: 52), 30)
        let narrow = ShelfGeometry(lip: 0, top: 52, backLeft: 400, backRight: 600)
        let wide = ShelfGeometry(lip: 0, top: 52, backLeft: 100, backRight: 1300)
        XCTAssertEqual(narrow.frontLeft, 370)
        XCTAssertEqual(wide.frontRight - wide.backRight, narrow.frontRight - narrow.backRight, "same slant at any width")
        // A line in the middle stays upright; one near the end leans out toward the front.
        XCTAssertEqual(narrow.perspectiveX(500, from: 23, to: 0), 500, accuracy: 0.001)
        XCTAssertGreaterThan(narrow.perspectiveX(590, from: 23, to: 0), 590)
        XCTAssertLessThan(narrow.perspectiveX(590, from: 23, to: 52), 590)
        // A lip pushes the slanted part up; the lip itself is upright.
        let ml = ShelfGeometry(lip: 3, top: 50, backLeft: 400, backRight: 600)
        XCTAssertEqual(ml.edges(at: 0).left, ml.edges(at: 3).left)
        XCTAssertEqual(ml.edges(at: 50).left, 400, accuracy: 0.001)
    }
}

private final class FakePrefs: DockPreferenceStore {
    let domain = "com.kewonit.oldmacdoc.tests.fake"
    var values: [String: Any] = [:]
    func value(forKey key: String) -> Any? { values[key] }
    func set(_ value: AnyObject?, forKey key: String) { values[key] = value }
    func synchronize() {}
}

final class AppleDockManagerTests: XCTestCase {
    private var url: URL!
    override func setUp() {
        url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
    }
    override func tearDown() { try? FileManager.default.removeItem(at: url) }

    func testHideAndRestoreRoundTrip() {
        let prefs = FakePrefs()
        prefs.values["autohide"] = NSNumber(value: false)
        var restarts = 0
        let m = AppleDockManager(prefs: prefs, backupURL: url, useWatchdog: false) { restarts += 1 }
        m.hide()
        XCTAssertTrue(m.isParked)
        XCTAssertEqual((prefs.values["autohide"] as? NSNumber)?.boolValue, true)
        XCTAssertEqual((prefs.values["autohide-delay"] as? NSNumber)?.doubleValue, AppleDockManager.parkedDelay)
        XCTAssertEqual((prefs.values["no-bouncing"] as? NSNumber)?.boolValue, true, "bounces would reveal the hidden Dock")
        m.hide()
        XCTAssertEqual(restarts, 1, "hiding twice must not restart the Dock twice")
        m.restore()
        XCTAssertFalse(m.isParked)
        XCTAssertEqual((prefs.values["autohide"] as? NSNumber)?.boolValue, false)
        XCTAssertNil(prefs.values["autohide-delay"], "a key that was unset must be removed again")
        XCTAssertNil(prefs.values["no-bouncing"])
        XCTAssertEqual(restarts, 2)
    }

    func testCrashRecoveryKeepsOriginalBackup() {
        let prefs = FakePrefs()
        prefs.values["autohide"] = NSNumber(value: false)
        prefs.values["autohide-delay"] = NSNumber(value: 0.5)
        AppleDockManager(prefs: prefs, backupURL: url, useWatchdog: false) {}.hide()
        // "Crash": a new instance starts while the Dock is still parked.
        let second = AppleDockManager(prefs: prefs, backupURL: url, useWatchdog: false) {}
        second.hide()
        XCTAssertEqual(second.backup, DockBackup(version: 3, autohide: false, autohideDelay: 0.5, noBouncing: nil))
        second.restore()
        XCTAssertEqual((prefs.values["autohide-delay"] as? NSNumber)?.doubleValue, 0.5)
    }

    func testLeftoverParkedDelayIsTreatedAsUnset() {
        let prefs = FakePrefs()
        prefs.values["autohide"] = NSNumber(value: true)
        prefs.values["autohide-delay"] = NSNumber(value: AppleDockManager.parkedDelay)
        let m = AppleDockManager(prefs: prefs, backupURL: url, useWatchdog: false) {}
        XCTAssertEqual(m.readCurrent(), DockBackup(version: 3))
    }

    func testCorruptBackupRestoresDefaults() throws {
        let prefs = FakePrefs()
        prefs.values["autohide"] = NSNumber(value: true)
        prefs.values["autohide-delay"] = NSNumber(value: AppleDockManager.parkedDelay)
        try Data("not json".utf8).write(to: url)
        let m = AppleDockManager(prefs: prefs, backupURL: url, useWatchdog: false) {}
        m.restore()
        XCTAssertNil(prefs.values["autohide"])
        XCTAssertNil(prefs.values["autohide-delay"])
        XCTAssertFalse(m.isParked)
    }

    func testReassertReparksAndKeepsOriginalBackup() {
        let prefs = FakePrefs()
        prefs.values["autohide"] = NSNumber(value: true)
        var restarts = 0
        let m = AppleDockManager(prefs: prefs, backupURL: url, useWatchdog: false) { restarts += 1 }
        m.hide()
        XCTAssertEqual(m.reassertIfNeeded(), .unchanged)

        prefs.values["autohide"] = NSNumber(value: false) // Option-Command-D
        XCTAssertEqual(m.reassertIfNeeded(), .reparked(autohideTurnedOff: true))
        XCTAssertEqual((prefs.values["autohide"] as? NSNumber)?.boolValue, true, "parked again")

        prefs.values["autohide-delay"] = NSNumber(value: 0.2) // a silent `defaults write`
        XCTAssertEqual(m.reassertIfNeeded(), .reparked(autohideTurnedOff: false))
        prefs.values["no-bouncing"] = NSNumber(value: false)
        XCTAssertEqual(m.reassertIfNeeded(), .reparked(autohideTurnedOff: false))
        XCTAssertEqual(restarts, 4)

        m.restore()
        XCTAssertEqual((prefs.values["autohide"] as? NSNumber)?.boolValue, true, "original settings come back")
        XCTAssertNil(prefs.values["autohide-delay"])
    }

    func testOlderParkedDelayCountsAsOurs() {
        let prefs = FakePrefs()
        prefs.values["autohide"] = NSNumber(value: true)
        prefs.values["autohide-delay"] = NSNumber(value: 1000) // left by an older build
        let m = AppleDockManager(prefs: prefs, backupURL: url, useWatchdog: false) {}
        XCTAssertEqual(m.readCurrent(), DockBackup(version: 3))
    }

    func testUsersOwnBouncingSettingIsRestored() {
        let prefs = FakePrefs()
        prefs.values["no-bouncing"] = NSNumber(value: false)
        let m = AppleDockManager(prefs: prefs, backupURL: url, useWatchdog: false) {}
        m.hide()
        XCTAssertEqual((prefs.values["no-bouncing"] as? NSNumber)?.boolValue, true)
        m.restore()
        XCTAssertEqual((prefs.values["no-bouncing"] as? NSNumber)?.boolValue, false)
    }

    func testOlderBackupIsUpgradedWithoutLosingTheUsersValue() throws {
        // An older build parked the Dock (it never touched no-bouncing); the user had it on.
        let prefs = FakePrefs()
        prefs.values["autohide"] = NSNumber(value: true)
        prefs.values["autohide-delay"] = NSNumber(value: 1000)
        prefs.values["no-bouncing"] = NSNumber(value: true)
        try JSONFile.save(DockBackup(autohide: false, autohideDelay: nil), to: url)
        let m = AppleDockManager(prefs: prefs, backupURL: url, useWatchdog: false) {}
        m.hide()
        XCTAssertEqual(m.backup, DockBackup(version: 3, autohide: false, autohideDelay: nil, noBouncing: true))
        m.restore()
        XCTAssertEqual((prefs.values["autohide"] as? NSNumber)?.boolValue, false)
        XCTAssertEqual((prefs.values["no-bouncing"] as? NSNumber)?.boolValue, true)
    }

    func testSideParkingRoundTrip() {
        let prefs = FakePrefs()
        prefs.values["tilesize"] = NSNumber(value: 48)
        prefs.values["magnification"] = NSNumber(value: true)
        let m = AppleDockManager(prefs: prefs, backupURL: url, useWatchdog: false) {}
        m.sideEdge = "right"
        m.hide()
        XCTAssertEqual(prefs.values["orientation"] as? String, "right")
        XCTAssertEqual((prefs.values["tilesize"] as? NSNumber)?.doubleValue, AppleDockManager.parkedTileSize)
        XCTAssertEqual((prefs.values["magnification"] as? NSNumber)?.boolValue, false)
        m.restore()
        XCTAssertNil(prefs.values["orientation"], "back to the bottom, where it was")
        XCTAssertEqual((prefs.values["tilesize"] as? NSNumber)?.doubleValue, 48)
        XCTAssertEqual((prefs.values["magnification"] as? NSNumber)?.boolValue, true)
    }

    func testWithoutSideEdgeTheDocksPlaceIsLeftAlone() {
        let prefs = FakePrefs()
        prefs.values["orientation"] = "left"
        prefs.values["tilesize"] = NSNumber(value: 64)
        var restarts = 0
        let m = AppleDockManager(prefs: prefs, backupURL: url, useWatchdog: false) { restarts += 1 }
        m.hide()
        XCTAssertEqual(prefs.values["orientation"] as? String, "left")
        XCTAssertEqual((prefs.values["tilesize"] as? NSNumber)?.doubleValue, 64)
        XCTAssertEqual(m.reassertIfNeeded(), .unchanged)
        m.restore()
        XCTAssertEqual(prefs.values["orientation"] as? String, "left")
        XCTAssertEqual(restarts, 2)
    }

    func testMovedDockIsParkedOnItsEdgeAgain() {
        let prefs = FakePrefs()
        let m = AppleDockManager(prefs: prefs, backupURL: url, useWatchdog: false) {}
        m.sideEdge = "right"
        m.hide()
        prefs.values["orientation"] = "bottom" // System Settings → Position on screen
        XCTAssertEqual(m.reassertIfNeeded(), .reparked(autohideTurnedOff: false))
        XCTAssertEqual(prefs.values["orientation"] as? String, "right")
        // A display arrives on the right: the edge moves.
        m.sideEdge = "left"
        XCTAssertEqual(m.reassertIfNeeded(), .reparked(autohideTurnedOff: false))
        XCTAssertEqual(prefs.values["orientation"] as? String, "left")
        m.restore()
        XCTAssertNil(prefs.values["orientation"])
    }

    func testVersionTwoBackupIsUpgradedWithTheUsersPlacement() throws {
        // Parked by a build that never moved the Dock: its edge and size are still the user's.
        let prefs = FakePrefs()
        prefs.values["autohide"] = NSNumber(value: true)
        prefs.values["autohide-delay"] = NSNumber(value: AppleDockManager.parkedDelay)
        prefs.values["no-bouncing"] = NSNumber(value: true)
        prefs.values["tilesize"] = NSNumber(value: 40)
        try JSONFile.save(DockBackup(version: 2, autohide: false), to: url)
        let m = AppleDockManager(prefs: prefs, backupURL: url, useWatchdog: false) {}
        m.sideEdge = "right"
        m.hide()
        XCTAssertEqual(m.backup, DockBackup(version: 3, autohide: false, tileSize: 40))
        XCTAssertEqual(prefs.values["orientation"] as? String, "right")
        m.restore()
        XCTAssertEqual((prefs.values["tilesize"] as? NSNumber)?.doubleValue, 40)
        XCTAssertNil(prefs.values["orientation"])
        XCTAssertNil(prefs.values["no-bouncing"], "version 2 recorded no-bouncing as unset")
    }

    func testLeftoverSideParkingIsTreatedAsUnset() {
        let prefs = FakePrefs()
        prefs.values["autohide-delay"] = NSNumber(value: AppleDockManager.parkedDelay)
        prefs.values["orientation"] = "right"
        prefs.values["tilesize"] = NSNumber(value: AppleDockManager.parkedTileSize)
        prefs.values["magnification"] = NSNumber(value: false)
        let m = AppleDockManager(prefs: prefs, backupURL: url, useWatchdog: false) {}
        XCTAssertEqual(m.readCurrent(), DockBackup(version: 3))
    }

    /// Runs the real watchdog script against a throwaway preferences domain.
    func testWatchdogRestoresAfterOwnerDies() throws {
        let domain = "com.kewonit.oldmacdoc.tests.dock-\(UUID().uuidString.prefix(8))"
        let prefs = SystemDockPreferences(domain: domain)
        func park() {
            prefs.set(NSNumber(value: true), forKey: "autohide")
            prefs.set(NSNumber(value: AppleDockManager.parkedDelay), forKey: "autohide-delay")
            prefs.set(NSNumber(value: true), forKey: "no-bouncing")
            prefs.set("right" as NSString, forKey: "orientation")
            prefs.set(NSNumber(value: AppleDockManager.parkedTileSize), forKey: "tilesize")
            prefs.set(NSNumber(value: false), forKey: "magnification")
            prefs.synchronize()
        }
        park()
        defer {
            for key in ["autohide", "autohide-delay", "no-bouncing", "orientation", "tilesize", "magnification"] {
                prefs.set(nil, forKey: key)
            }
            prefs.synchronize()
        }
        try JSONFile.save(DockBackup(version: 3, autohide: false, autohideDelay: nil, noBouncing: false,
                                     orientation: "left", tileSize: 52, magnification: nil), to: url)

        // A short-lived "owner" process that dies on its own.
        let owner = Process()
        owner.executableURL = URL(fileURLWithPath: "/bin/sleep")
        owner.arguments = ["1"]
        try owner.run()
        let watchdog = AppleDockManager.spawnWatchdog(watching: owner.processIdentifier, backupURL: url, domain: domain)
        XCTAssertGreaterThan(watchdog, 0)
        var status: Int32 = 0
        waitpid(watchdog, &status, 0)

        prefs.synchronize()
        XCTAssertEqual((prefs.value(forKey: "autohide") as? NSNumber)?.boolValue, false)
        XCTAssertNil(prefs.value(forKey: "autohide-delay"), "unset key must be deleted")
        XCTAssertEqual((prefs.value(forKey: "no-bouncing") as? NSNumber)?.boolValue, false)
        XCTAssertEqual(prefs.value(forKey: "orientation") as? String, "left")
        XCTAssertEqual((prefs.value(forKey: "tilesize") as? NSNumber)?.doubleValue, 52)
        XCTAssertNil(prefs.value(forKey: "magnification"), "unset key must be deleted")
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))

        // An older (version 1) backup never changed no-bouncing, so the watchdog leaves it alone.
        park()
        try JSONFile.save(DockBackup(autohide: true, autohideDelay: nil), to: url)
        let owner2 = Process()
        owner2.executableURL = URL(fileURLWithPath: "/bin/sleep")
        owner2.arguments = ["1"]
        try owner2.run()
        let watchdog2 = AppleDockManager.spawnWatchdog(watching: owner2.processIdentifier, backupURL: url, domain: domain)
        waitpid(watchdog2, &status, 0)
        prefs.synchronize()
        XCTAssertEqual((prefs.value(forKey: "no-bouncing") as? NSNumber)?.boolValue, true, "untouched for older backups")
        XCTAssertEqual(prefs.value(forKey: "orientation") as? String, "right", "untouched for older backups")
    }

    /// The app ignores SIGTERM (it handles it on a dispatch source). The watchdog must not inherit
    /// that, or quitting can't stop it and it outlives the app.
    func testWatchdogStopsOnSIGTERMEvenWhenTheAppIgnoresIt() throws {
        let previous = signal(SIGTERM, SIG_IGN)
        defer { signal(SIGTERM, previous) }
        let watchdog = AppleDockManager.spawnWatchdog(watching: getpid(), backupURL: url, domain: "com.kewonit.oldmacdoc.tests.unused")
        XCTAssertGreaterThan(watchdog, 0)
        usleep(200_000) // let the shell start its wait loop
        kill(watchdog, SIGTERM)
        var status: Int32 = 0
        var exited = false
        for _ in 0..<40 where !exited { // up to 2 s
            exited = waitpid(watchdog, &status, WNOHANG) == watchdog
            if !exited { usleep(50_000) }
        }
        if !exited { kill(watchdog, SIGKILL); waitpid(watchdog, &status, 0) }
        XCTAssertTrue(exited, "the watchdog ignored SIGTERM")
    }

    /// A watchdog left from an earlier run (its app quit, and a new copy opened at once) must leave
    /// the new copy's backup and the Dock alone.
    func testWatchdogLeavesABackupOwnedByANewerCopyAlone() throws {
        let domain = "com.kewonit.oldmacdoc.tests.dock-\(UUID().uuidString.prefix(8))"
        let prefs = SystemDockPreferences(domain: domain)
        prefs.set(NSNumber(value: AppleDockManager.parkedDelay), forKey: "autohide-delay")
        prefs.synchronize()
        defer {
            prefs.set(nil, forKey: "autohide-delay")
            prefs.synchronize()
        }
        let previousOwner = Process()
        previousOwner.executableURL = URL(fileURLWithPath: "/bin/sleep")
        previousOwner.arguments = ["0.5"]
        try previousOwner.run()
        // The newer copy (this test process) owns the backup.
        try JSONFile.save(DockBackup(version: 3, autohide: false, owner: getpid()), to: url)
        let watchdog = AppleDockManager.spawnWatchdog(watching: previousOwner.processIdentifier, backupURL: url, domain: domain)
        var status: Int32 = 0
        waitpid(watchdog, &status, 0)
        prefs.synchronize()
        XCTAssertEqual((prefs.value(forKey: "autohide-delay") as? NSNumber)?.doubleValue, AppleDockManager.parkedDelay,
                       "the Dock must stay parked")
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path), "the newer copy's backup must stay")
    }

    func testUsersAutohideComesFromTheirOwnDock() throws {
        let prefs = FakePrefs()
        let m = AppleDockManager(prefs: prefs, backupURL: url, useWatchdog: false) {}
        XCTAssertFalse(m.usersAutohide, "unset is Apple's default: off")
        prefs.values["autohide"] = NSNumber(value: true)
        XCTAssertTrue(m.usersAutohide)
        prefs.values["autohide"] = NSNumber(value: false)
        XCTAssertFalse(m.usersAutohide)
        // Parked, the live value is ours; the backup has theirs.
        m.hide()
        XCTAssertEqual((prefs.values["autohide"] as? NSNumber)?.boolValue, true)
        XCTAssertFalse(m.usersAutohide)
        // A delay left over from a lost session isn't the user's either.
        try FileManager.default.removeItem(at: url)
        prefs.values["autohide-delay"] = NSNumber(value: AppleDockManager.parkedDelay)
        XCTAssertFalse(m.usersAutohide)
    }

    func testHideTakesOverABackupLeftByACrashedCopy() throws {
        let prefs = FakePrefs()
        try JSONFile.save(DockBackup(version: 3, autohide: false, owner: 1), to: url)
        AppleDockManager(prefs: prefs, backupURL: url, useWatchdog: false) {}.hide()
        let saved = try XCTUnwrap(JSONFile.load(DockBackup.self, from: url))
        XCTAssertEqual(saved.owner, getpid())
        XCTAssertEqual(saved.autohide, false, "the user's settings are kept")
    }
}

final class SettingsTests: XCTestCase {
    func testSettingsDecodeWithMissingKeys() throws {
        let s = try JSONDecoder().decode(AppSettings.self, from: Data(#"{"shelfStyle":"smoke"}"#.utf8))
        XCTAssertEqual(s.shelfStyle, .smoke)
        XCTAssertEqual(s.iconSize, AppSettings().iconSize)
    }

    func testLightsForOpenAppsAreOnByDefault() throws {
        XCTAssertTrue(AppSettings().showIndicators)
        let saved = try JSONDecoder().decode(AppSettings.self, from: Data(#"{"finish":"off"}"#.utf8))
        XCTAssertTrue(saved.showIndicators, "a settings file without the key keeps the lights on")
    }

    func testSettingsFromEarlierVersionsStillLoad() throws {
        // `symbolCutout` was removed; files that have it must still load, with everything else kept.
        let old = try JSONDecoder().decode(AppSettings.self, from: Data(#"{"symbolCutout":true,"shelfStyle":"frosted","autoHide":false}"#.utf8))
        XCTAssertEqual(old.shelfStyle, .frosted)
        XCTAssertFalse(old.autoHide)
    }

    func testOutOfRangeSizesAreClamped() throws {
        let tiny = try JSONDecoder().decode(AppSettings.self, from: Data(#"{"iconSize":0,"magnifiedSize":9000}"#.utf8))
        XCTAssertEqual(tiny.iconSize, AppSettings.iconSizeRange.lowerBound)
        XCTAssertEqual(tiny.magnifiedSize, AppSettings.magnifiedSizeRange.upperBound)
        let independent = try JSONDecoder().decode(AppSettings.self, from: Data(#"{"iconSize":90,"magnifiedSize":50}"#.utf8))
        XCTAssertEqual(independent.magnifiedSize, 50, "the magnified size is kept as set, not tied to the icon size")
    }
}

final class SettingsPanelLogicTests: XCTestCase {
    private func settings(size: Double, magnified: Double, on: Bool = true) -> AppSettings {
        var s = AppSettings()
        s.iconSize = size
        s.magnifiedSize = magnified
        s.magnification = on
        return s
    }

    func testSizeRangeEndsAtWhatFits() {
        let unknown = DockSizeControls(settings: settings(size: 56, magnified: 100), largestFitting: nil)
        XCTAssertEqual(unknown.sizeRange, 32...96)
        let fits60 = DockSizeControls(settings: settings(size: 56, magnified: 100), largestFitting: 60)
        XCTAssertEqual(fits60.sizeRange, 32...60)
        let crowded = DockSizeControls(settings: settings(size: 56, magnified: 100), largestFitting: 20)
        XCTAssertEqual(crowded.sizeRange, 16...24, "never narrower than a few points, even on a crowded screen")
    }

    func testSizeAboveWhatFitsShowsAtTheLimit() {
        let c = DockSizeControls(settings: settings(size: 80, magnified: 100), largestFitting: 60)
        XCTAssertEqual(c.size, 60)
        XCTAssertEqual(c.magnification, 100, "magnification doesn't depend on the size")
    }

    func testFarLeftMagnificationIsOff() {
        let s = settings(size: 48, magnified: 96)
        let c = DockSizeControls(settings: s, largestFitting: nil)
        XCTAssertEqual(c.magnification, 96)
        XCTAssertFalse(c.magnificationIsOff)
        let off = DockSizeControls.settingMagnification(DockSizeControls.offPosition, in: s)
        XCTAssertFalse(off.magnification)
        XCTAssertEqual(off.magnifiedSize, 96, "the last magnified size is kept for turning it back on")
        let shown = DockSizeControls(settings: off, largestFitting: nil)
        XCTAssertTrue(shown.magnificationIsOff)
        XCTAssertEqual(shown.magnificationReadout, "Off")
        let on = DockSizeControls.settingMagnification(72.4, in: off)
        XCTAssertTrue(on.magnification)
        XCTAssertEqual(on.magnifiedSize, 72)
    }

    func testTheSlidersAreIndependent() {
        let s = settings(size: 48, magnified: 64)
        // Moving Size leaves Magnification where it was, even past it, and the other way round.
        for size in [32.0, 60, 80, 96] {
            let new = DockSizeControls.settingSize(size, in: s)
            XCTAssertEqual(new.magnifiedSize, 64)
            XCTAssertTrue(new.magnification)
            XCTAssertEqual(DockSizeControls(settings: new, largestFitting: nil).magnification, 64)
        }
        for magnified in [DockSizeControls.offPosition, 50, 100, 128] {
            let new = DockSizeControls.settingMagnification(magnified, in: s)
            XCTAssertEqual(new.iconSize, 48)
            XCTAssertEqual(DockSizeControls(settings: new, largestFitting: nil).size, 48)
        }
        XCTAssertEqual(DockSizeControls.magnificationRange, 47...128, "a fixed range, whatever the size")
    }

    func testPanelOpensUnderItsItemAndStaysOnScreen() {
        let screen = CGRect(x: 0, y: 0, width: 1512, height: 982)
        let visible = CGRect(x: 0, y: 0, width: 1512, height: 949)
        let size = CGSize(width: 310, height: 400)
        let item = CGRect(x: 1200, y: 949, width: 30, height: 33)
        let f = PanelPlacement.frame(size: size, item: item, screen: screen, visible: visible, menuBarHeight: 33)
        XCTAssertEqual(f.maxY, 944, "5 pt under the item")
        XCTAssertEqual(f.minX, 1194, "kept 8 pt inside the screen's right edge")
        let left = PanelPlacement.frame(size: size, item: CGRect(x: 2, y: 949, width: 30, height: 33),
                                        screen: screen, visible: visible, menuBarHeight: 33)
        XCTAssertEqual(left.minX, 8)
        let hidden = PanelPlacement.frame(size: size, item: nil, screen: screen, visible: visible, menuBarHeight: 33)
        XCTAssertEqual(hidden.maxX, 1502, "top right when the item can't be seen")
        XCTAssertEqual(hidden.maxY, 943, "under the menu bar")
    }
}
