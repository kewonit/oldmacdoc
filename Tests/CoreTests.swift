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

    func testFreeSideEdgesAreTheSidesWithNoDisplayBesideThem() {
        let main = CGRect(x: 0, y: 0, width: 1512, height: 982)
        XCTAssertEqual(AppleDockManager.freeSideEdges(main: main, others: []), ["left", "right"])
        let right = CGRect(x: 1512, y: -200, width: 2560, height: 1440)
        XCTAssertEqual(AppleDockManager.freeSideEdges(main: main, others: [right]), ["left"])
        let left = CGRect(x: -1920, y: 0, width: 1920, height: 1080)
        XCTAssertEqual(AppleDockManager.freeSideEdges(main: main, others: [left]), ["right"])
        XCTAssertEqual(AppleDockManager.freeSideEdges(main: main, others: [left, right]), [])
        // Above, or only touching at a corner, it isn't beside the main display.
        let above = CGRect(x: 0, y: 982, width: 2560, height: 1440)
        let cornerRight = CGRect(x: 1512, y: 982, width: 1920, height: 1080)
        XCTAssertEqual(AppleDockManager.freeSideEdges(main: main, others: [above, cornerRight]), ["left", "right"])
    }

    func testSideEdgeIsThePreferredOneWhenFree() {
        XCTAssertEqual(AppleDockManager.sideEdge(preferring: "right", free: ["left", "right"]), "right")
        XCTAssertEqual(AppleDockManager.sideEdge(preferring: "left", free: ["left", "right"]), "left")
        XCTAssertEqual(AppleDockManager.sideEdge(preferring: "left", free: ["right"]), "right", "the other side when blocked")
        XCTAssertEqual(AppleDockManager.sideEdge(preferring: "right", free: ["left"]), "left", "the other side when blocked")
        XCTAssertNil(AppleDockManager.sideEdge(preferring: "right", free: []))
    }

    func testAddDesktopSideParksAppleDockOnTheOtherEdge() {
        XCTAssertEqual(AddDesktopSide.left.dockEdge, "right")
        XCTAssertEqual(AddDesktopSide.right.dockEdge, "left")
        // The default is how it always was: Apple's Dock on the right on a single display.
        let free = AppleDockManager.freeSideEdges(main: CGRect(x: 0, y: 0, width: 1512, height: 982), others: [])
        XCTAssertEqual(AppleDockManager.sideEdge(preferring: AppSettings().addDesktopSide.dockEdge, free: free), "right")
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

    func testItemsFromApplesDockAreOnByDefaultAndForOlderFiles() throws {
        XCTAssertTrue(AppSettings().appleMenuItems)
        XCTAssertTrue(try JSONDecoder().decode(AppSettings.self, from: Data(#"{"finish":"off"}"#.utf8)).appleMenuItems)
        XCTAssertFalse(try JSONDecoder().decode(AppSettings.self, from: Data(#"{"appleMenuItems":false}"#.utf8)).appleMenuItems)
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
        XCTAssertEqual(old.addDesktopSide, .left, "files from before the choice keep the + where it was")
    }

    func testAddDesktopSideIsSaved() throws {
        var s = AppSettings()
        s.addDesktopSide = .right
        let back = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(s))
        XCTAssertEqual(back.addDesktopSide, .right)
        let damaged = try JSONDecoder().decode(AppSettings.self, from: Data(#"{"addDesktopSide":"top"}"#.utf8))
        XCTAssertEqual(damaged.addDesktopSide, .left)
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

final class AppBundleInfoTests: XCTestCase {
    func testAgentsAndBackgroundAppsStayOutOfTheDock() {
        XCTAssertFalse(AppBundleInfo.showsInDock(["LSUIElement": true]), "Apps.app (Launchpad) uses a boolean")
        XCTAssertFalse(AppBundleInfo.showsInDock(["LSUIElement": NSNumber(value: 1)]), "Mission Control uses 1")
        XCTAssertFalse(AppBundleInfo.showsInDock(["LSUIElement": "YES"]))
        XCTAssertFalse(AppBundleInfo.showsInDock(["LSUIElement": " true "]))
        XCTAssertFalse(AppBundleInfo.showsInDock(["LSUIElement": "1"]))
        XCTAssertFalse(AppBundleInfo.showsInDock(["LSBackgroundOnly": true]))
    }

    func testOrdinaryAppsShowInTheDock() {
        XCTAssertTrue(AppBundleInfo.showsInDock(nil), "no Info.plist")
        XCTAssertTrue(AppBundleInfo.showsInDock([:]))
        XCTAssertTrue(AppBundleInfo.showsInDock(["CFBundleIdentifier": "com.apple.Safari"]))
        XCTAssertTrue(AppBundleInfo.showsInDock(["LSUIElement": false, "LSBackgroundOnly": NSNumber(value: 0)]))
        XCTAssertTrue(AppBundleInfo.showsInDock(["LSUIElement": "0"]))
        XCTAssertTrue(AppBundleInfo.showsInDock(["LSUIElement": "NO"]))
    }

    func testSystemLaunchersAreAgents() throws {
        // On this Mac's own launchers, where present: they open something and quit at once.
        for path in ["/System/Applications/Apps.app", "/System/Applications/Mission Control.app",
                     "/System/Applications/Launchpad.app"] where FileManager.default.fileExists(atPath: path) {
            XCTAssertFalse(AppBundleInfo.showsInDock(Bundle(path: path)?.infoDictionary), path)
        }
        if let safari = Bundle(path: "/Applications/Safari.app") {
            XCTAssertTrue(AppBundleInfo.showsInDock(safari.infoDictionary))
        }
    }
}

// MARK: - Dock menus

private func titles(_ items: [DockMenuItem]) -> [String] {
    items.map { $0.kind == .separator ? "---" : $0.title }
}

private func options(_ items: [DockMenuItem]) -> [DockMenuItem] {
    items.first { $0.title == "Options" }?.submenu ?? []
}

final class DockMenuTests: XCTestCase {
    let s = DockStrings.english

    func testRunningAppFollowsTheOriginalOrder() {
        var state = AppMenuState(isRunning: true, keepsInDock: true)
        state.windows = [MenuWindow(title: "Inbox", isMain: true), MenuWindow(title: "Draft", isMinimized: true)]
        state.appleGroups = [[.item("New Window", .apple(AppleMenuPath(indexes: [3], titles: ["New Window"])))]]
        state.openAtLogin = false
        state.canShowAllWindows = true
        let menu = DockMenuBuilder.app(state, strings: s)
        XCTAssertEqual(titles(menu), ["Inbox", "Draft", "---", "New Window", "---", "Options", "---",
                                      "Show All Windows", "Hide", "Quit"])
        XCTAssertEqual(menu[0].mark, .check)
        XCTAssertEqual(menu[1].mark, .diamond)
        XCTAssertEqual(menu[0].command, .focusWindow(0))
        XCTAssertEqual(titles(options(menu)), ["Keep in Dock", "Open at Login", "Show in Finder", "---", "Icon"])
        XCTAssertEqual(options(menu)[0].mark, .check)
        let hide = menu.first { $0.title == "Hide" }!, quit = menu.first { $0.title == "Quit" }!
        XCTAssertEqual(hide.resolved(option: true).title, "Hide Others")
        XCTAssertEqual(hide.resolved(option: true).command, .hideOthers)
        XCTAssertEqual(quit.resolved(option: true).command, .forceQuit)
        XCTAssertFalse(menu.contains { $0.command == .open }, "a running app has no Open")
    }

    func testAppThatIsNotRunning() {
        var state = AppMenuState(isRunning: false, keepsInDock: true)
        state.appleGroups = [[.item("Report.numbers", .apple(AppleMenuPath(indexes: [0], titles: ["Report.numbers"])))]]
        let menu = DockMenuBuilder.app(state, strings: s)
        XCTAssertEqual(titles(menu), ["Report.numbers", "---", "Options", "---", "Open"])
        XCTAssertEqual(titles(options(menu)), ["Remove from Dock", "Show in Finder", "---", "Icon"],
                       "unknown Open at Login is left out")
    }

    func testHiddenAndHungApps() {
        let hidden = DockMenuBuilder.app(AppMenuState(isRunning: true, isHidden: true), strings: s)
        XCTAssertTrue(hidden.contains { $0.title == "Show" && $0.command == .unhide })
        let hung = DockMenuBuilder.app(AppMenuState(isRunning: true, notResponding: true), strings: s)
        XCTAssertEqual(hung.first?.kind, .header)
        XCTAssertEqual(hung.first?.title, "Application Not Responding")
        XCTAssertEqual(hung.last?.title, "Force Quit")
        XCTAssertEqual(hung.last?.command, .forceQuit)
    }

    func testFinderHasNoQuitAndOffersRelaunchWithOption() {
        let menu = DockMenuBuilder.app(AppMenuState(isRunning: true, isFinder: true), strings: s)
        XCTAssertFalse(menu.contains { $0.command == .quit })
        XCTAssertEqual(Array(titles(visibleRows(menu, option: false)).suffix(2)), ["---", "Hide"])
        XCTAssertEqual(visibleRows(menu, option: true).last?.title, "Relaunch")
        XCTAssertTrue(menu.contains { $0.command == .newFinderWindow }, "Finder's own items without Accessibility")
        XCTAssertEqual(titles(options(menu)), ["Icon"], "Finder can't be removed or opened at login")
    }

    func testAssignToBlockSitsInOptions() {
        var state = AppMenuState(isRunning: true)
        state.assignTo = [.header("Assign To"), .item("All Desktops", .none), .item("None", .none, mark: .check)]
        XCTAssertEqual(titles(options(DockMenuBuilder.app(state, strings: s))),
                       ["Keep in Dock", "Show in Finder", "---", "Assign To", "All Desktops", "None", "---", "Icon"])
    }

    func testTrashSeparatorAndStackMenus() {
        XCTAssertEqual(titles(DockMenuBuilder.trash(isFull: false, strings: s)), ["Open", "---", "Empty Trash"])
        XCTAssertFalse(DockMenuBuilder.trash(isFull: false, strings: s)[2].isEnabled)
        XCTAssertEqual(titles(DockMenuBuilder.separator(autoHide: true, magnification: false, strings: s)),
                       ["Turn Hiding Off", "Turn Magnification On", "---", "Dock Settings…"])
        let stack = DockMenuBuilder.stack(name: "Downloads", sort: .dateAdded, display: .stack, view: .automatic, strings: s)
        XCTAssertEqual(titles(stack), ["Sort by", "Display as", "View content as", "---", "Options", "---", "Open “Downloads”"])
        XCTAssertEqual(stack[0].submenu?.first { $0.mark == .check }?.title, "Date Added")
        XCTAssertEqual(stack[2].submenu?.first { $0.mark == .check }?.title, "Automatic")
    }

    func testVisibleRowsNeverDoubleOrEndOnSeparators() {
        var relaunch = DockMenuItem.item("Relaunch", .relaunch)
        relaunch.optionOnly = true
        let items: [DockMenuItem] = [.separator, .item("A", .none), .separator, .separator, relaunch, .separator]
        XCTAssertEqual(titles(visibleRows(items, option: false)), ["A"])
        XCTAssertEqual(titles(visibleRows(items, option: true)), ["A", "---", "Relaunch"])
    }

    func testSystemStringsMatchApplesDock() {
        // On a Mac in English these are the Dock's own words.
        let system = DockStrings.system()
        if Locale.preferredLanguages.first?.hasPrefix("en") == true {
            XCTAssertEqual(system[.keepInDock], "Keep in Dock")
            XCTAssertEqual(system[.showAs], "View content as")
        }
        XCTAssertEqual(DockStrings.system(dockPath: "/nonexistent")[.quit], "Quit")
    }
}

final class AppleMenuMirrorTests: XCTestCase {
    private func node(_ t: String, _ mark: String? = nil, enabled: Bool = true, alt: Bool = false,
                      _ children: [AppleMenuNode] = []) -> AppleMenuNode {
        AppleMenuNode(title: t, mark: mark, isEnabled: enabled, isOptionAlternate: alt, children: children)
    }
    private var sep: AppleMenuNode { AppleMenuNode(title: "", isEnabled: false) }

    /// Safari's menu as read from Apple's Dock on macOS 27.0.1.
    private var safari: [AppleMenuNode] {
        [node("Inbox", "✓"), sep, node("New Window"), node("New Private Window"), sep,
         node("Options", nil, [node("Keep in Dock", "✓"), node("Open at Login"), node("Show in Finder"), sep,
                               node("Assign To"), node("All Desktops"), node("This Desktop"), node("None", "✓")]),
         sep, node("Show All Windows"), node("Hide"), node("Hide Others", alt: true), node("Quit"), node("Force Quit", alt: true)]
    }

    func testTakesTheAppsOwnItemsAndLeavesOutItsWindows() {
        let snap = AppleMenuMirror.parse(safari, windowTitles: ["Inbox"], strings: .english)
        XCTAssertEqual(snap.groups.map { $0.map(\.title) }, [["New Window", "New Private Window"]])
        XCTAssertEqual(snap.groups[0][0].command, .apple(AppleMenuPath(indexes: [2], titles: ["New Window"])))
        XCTAssertEqual(snap.openAtLogin, false)
        XCTAssertEqual(snap.openAtLoginPath, AppleMenuPath(indexes: [5, 1], titles: ["Options", "Open at Login"]))
        XCTAssertEqual(snap.assignTo.map(\.title), ["Assign To", "All Desktops", "This Desktop", "None"])
        XCTAssertEqual(snap.assignTo.first?.kind, .header)
        XCTAssertEqual(snap.assignTo.last?.mark, .check)
        XCTAssertEqual(snap.assignTo[1].command, .apple(AppleMenuPath(indexes: [5, 5], titles: ["Options", "All Desktops"])))
        XCTAssertTrue(snap.canShowAllWindows)
        XCTAssertFalse(snap.notResponding)
    }

    func testNeverTakesApplesKeepInDock() {
        let snap = AppleMenuMirror.parse(safari, windowTitles: ["Inbox"], strings: .english)
        let all = snap.groups.flatMap { $0 } + snap.assignTo
        XCTAssertFalse(all.contains { $0.title == "Keep in Dock" || $0.title == "Remove from Dock" })
    }

    func testTheAppsTilesTopLevelRemoveFromDockIsLeftOut() {
        // Apple's menu for the Apps tile (Launchpad) on macOS 27.
        let menu = [node("Remove from Dock"), sep, node("Show Apps"), sep, node("Options", nil, [node("Open at Login")]), sep, node("Open")]
        let snap = AppleMenuMirror.parse(menu, windowTitles: [], strings: .english)
        XCTAssertEqual(snap.groups.map { $0.map(\.title) }, [["Show Apps"]])
    }

    func testWithoutOptionsHideAndShowAllWindowsAreStillLeftOut() {
        // Finder with one desktop: no Assign To, so Apple's menu has no Options submenu.
        let menu = [node("Documents", "✓"), sep, node("New Finder Window"), node("Find…"), sep,
                    node("Show All Windows"), node("Hide"), node("Hide Others", alt: true)]
        let snap = AppleMenuMirror.parse(menu, windowTitles: [], strings: .english)
        XCTAssertEqual(snap.groups.map { $0.map(\.title) }, [["New Finder Window", "Find…"]])
        XCTAssertTrue(snap.canShowAllWindows)
    }

    func testWindowsOnAnotherDesktopAreStillRecognisedByTheirMark() {
        // The app reports no windows here (they're on another desktop), but Apple marks the main one.
        let menu = [node("Elsewhere", "✓"), node("Also elsewhere"), sep, node("New Window"), sep, node("Options", nil, [node("Keep in Dock")])]
        XCTAssertEqual(AppleMenuMirror.parse(menu, windowTitles: [], strings: .english).groups.map { $0.map(\.title) }, [["New Window"]])
        // An app that isn't running has no windows: its first rows are recent documents, whatever their marks.
        let recents = [node("Budget.numbers", "✓"), sep, node("Options", nil, [node("Remove from Dock")]), sep, node("Open")]
        XCTAssertEqual(AppleMenuMirror.parse(recents, windowTitles: [], isRunning: false, strings: .english).groups.map { $0.map(\.title) },
                       [["Budget.numbers"]])
    }

    func testWithoutWindowsTheFirstGroupIsTheApps() {
        let menu = [node("New Window"), sep, node("Options", nil, [node("Keep in Dock")]), sep, node("Hide"), node("Quit")]
        let snap = AppleMenuMirror.parse(menu, windowTitles: [], strings: .english)
        XCTAssertEqual(snap.groups.map { $0.map(\.title) }, [["New Window"]])
        XCTAssertNil(snap.openAtLogin)
        XCTAssertFalse(snap.canShowAllWindows)
    }

    func testMinimizedWindowsMarkTheWindowGroup() {
        let menu = [node("Elsewhere", "◆"), sep, node("Play"), sep, node("Options", nil, [node("Keep in Dock")])]
        XCTAssertEqual(AppleMenuMirror.parse(menu, windowTitles: [], strings: .english).groups.map { $0.map(\.title) }, [["Play"]])
    }

    func testNotRespondingAndOptionAlternatesInTheAppsItems() {
        let menu = [node("Application Not Responding", enabled: false), sep, node("Inbox"), sep,
                    node("Pause"), node("Stop", alt: true), sep, node("Options", nil, [node("Keep in Dock")])]
        let snap = AppleMenuMirror.parse(menu, windowTitles: ["Inbox"], strings: .english)
        XCTAssertTrue(snap.notResponding)
        XCTAssertEqual(snap.groups.map { $0.map(\.title) }, [["Pause"]])
        XCTAssertEqual(snap.groups[0][0].optionTitle, "Stop")
    }

    func testRecentDocumentsOfAnAppThatIsNotRunning() {
        let menu = [node("Budget.numbers"), node("Trip.numbers"), sep,
                    node("Options", nil, [node("Remove from Dock"), node("Open at Login", "✓"), node("Show in Finder")]), sep, node("Open")]
        let snap = AppleMenuMirror.parse(menu, windowTitles: [], strings: .english)
        XCTAssertEqual(snap.groups.map { $0.map(\.title) }, [["Budget.numbers", "Trip.numbers"]])
        XCTAssertEqual(snap.openAtLogin, true)
    }
}

final class CalloutGeometryTests: XCTestCase {
    let screen = CGRect(x: 0, y: 0, width: 1512, height: 982)

    func testPointerIsOnTheIconAndTheMenuStartsNearItsLeftEdge() {
        let p = Callout.place(size: CGSize(width: 200, height: 150), anchorX: 700, anchorTop: 80, screen: screen, top: 950, cornerRadius: 6)
        XCTAssertEqual(p.pointerX, 700)
        XCTAssertEqual(p.body.minX, 700 - Callout.axisInset)
        XCTAssertEqual(p.body.minY, 80 + Callout.gap + Callout.pointerHeight)
        XCTAssertEqual(p.frame.minY, 80 + Callout.gap)
        XCTAssertFalse(p.isClipped)
    }

    func testAtTheScreensEdgesTheMenuMovesButThePointerStaysOnTheIcon() {
        let right = Callout.place(size: CGSize(width: 200, height: 150), anchorX: 1490, anchorTop: 80, screen: screen, top: 950, cornerRadius: 6)
        XCTAssertEqual(right.body.maxX, screen.maxX - Callout.margin)
        XCTAssertEqual(right.pointerX, right.body.maxX - 6 - Callout.pointerWidth / 2, "as far over as the corner allows")
        let left = Callout.place(size: CGSize(width: 200, height: 150), anchorX: 20, anchorTop: 80, screen: screen, top: 950, cornerRadius: 6)
        XCTAssertEqual(left.body.minX, Callout.margin)
        XCTAssertEqual(left.pointerX, Callout.margin + 6 + Callout.pointerWidth / 2, "as near the icon as the corner allows")
    }

    func testTallMenusAreClippedBelowTheMenuBar() {
        let p = Callout.place(size: CGSize(width: 200, height: 2000), anchorX: 700, anchorTop: 80, screen: screen, top: 950, cornerRadius: 6)
        XCTAssertTrue(p.isClipped)
        XCTAssertEqual(p.body.maxY, 950 - Callout.margin)
    }

    func testCenteredGridsAndSecondScreens() {
        let other = CGRect(x: -1920, y: 0, width: 1920, height: 1080)
        let p = Callout.place(size: CGSize(width: 400, height: 300), anchorX: -1000, anchorTop: 80, screen: other, top: 1050,
                              cornerRadius: 6, alignment: .centered)
        XCTAssertEqual(p.body.midX, -1000)
        XCTAssertEqual(p.pointerX, -1000)
    }

    func testSubmenusOpenRightOrFlipLeft() {
        let parent = CGRect(x: 600, y: 100, width: 200, height: 200)
        let row = CGRect(x: 600, y: 250, width: 200, height: 19)
        let r = Callout.submenu(size: CGSize(width: 150, height: 100), row: row, parent: parent, screen: screen, top: 950, inset: 4)
        XCTAssertEqual(r.frame.minX, parent.maxX - 2)
        XCTAssertEqual(r.frame.maxY, row.maxY + 4)
        let edge = CGRect(x: 1300, y: 100, width: 200, height: 200)
        let l = Callout.submenu(size: CGSize(width: 150, height: 100), row: row, parent: edge, screen: screen, top: 950, inset: 4)
        XCTAssertEqual(l.frame.maxX, edge.minX + 2)
    }

    func testOutlineContainsBodyAndPointerTip() {
        let path = Callout.path(size: CGSize(width: 200, height: 113), pointerX: 40, cornerRadius: 6)
        XCTAssertTrue(path.contains(CGPoint(x: 100, y: 60)))
        XCTAssertTrue(path.contains(CGPoint(x: 40, y: 2)), "near the pointer's tip")
        XCTAssertFalse(path.contains(CGPoint(x: 100, y: 5)), "beside the pointer, below the body")
    }
}

final class MenuTrackingTests: XCTestCase {
    func testReleaseRule() {
        XCTAssertEqual(MenuTracking.release(enteredMenu: true, overItem: true, overMenu: true), .choose)
        XCTAssertEqual(MenuTracking.release(enteredMenu: false, overItem: false, overMenu: false), .stayOpen, "quick right-click")
        XCTAssertEqual(MenuTracking.release(enteredMenu: true, overItem: false, overMenu: true), .stayOpen, "on a separator")
        XCTAssertEqual(MenuTracking.release(enteredMenu: true, overItem: false, overMenu: false), .close)
    }

    func testArrowKeysSkipWhatCantBeChosenAndWrap() {
        let sel = [false, true, false, true, true]
        XCTAssertEqual(MenuTracking.next(from: nil, step: 1, selectable: sel), 1)
        XCTAssertEqual(MenuTracking.next(from: 1, step: 1, selectable: sel), 3)
        XCTAssertEqual(MenuTracking.next(from: 4, step: 1, selectable: sel), 1)
        XCTAssertEqual(MenuTracking.next(from: nil, step: -1, selectable: sel), 4)
        XCTAssertNil(MenuTracking.next(from: nil, step: 1, selectable: [false, false]))
    }

    func testTypeSelect() {
        let t = ["Show All Windows", "Hide", "Hide Others", "Quit", "Show in Finder"]
        let sel = [true, true, true, true, true]
        XCTAssertEqual(MenuTracking.typeSelect("q", titles: t, selectable: sel, from: nil), 3)
        XCTAssertEqual(MenuTracking.typeSelect("s", titles: t, selectable: sel, from: nil), 0)
        XCTAssertEqual(MenuTracking.typeSelect("s", titles: t, selectable: sel, from: 0), 4, "the same letter again moves on")
        XCTAssertEqual(MenuTracking.typeSelect("hide o", titles: t, selectable: sel, from: 1), 2)
        XCTAssertNil(MenuTracking.typeSelect("z", titles: t, selectable: sel, from: nil))
    }
}

final class StackTests: XCTestCase {
    private var dir: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("stacks-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: dir) }

    func testStoreAddsMovesAndKeepsItsOwnFile() {
        let file = dir.appendingPathComponent("stacks.json")
        let store = StackStore(url: file)
        let a = store.add(folder: dir.appendingPathComponent("A"), at: 0)
        let b = store.add(folder: dir.appendingPathComponent("B"), at: 5)
        XCTAssertEqual(store.pins.map(\.id), [a, b])
        XCTAssertEqual(store.add(folder: dir.appendingPathComponent("B"), at: 0), b, "the same folder again moves it")
        XCTAssertEqual(store.pins.map(\.id), [b, a])
        store.update(a) { $0.view = .grid }
        let reloaded = StackStore(url: file)
        XCTAssertEqual(reloaded.pins, store.pins)
        XCTAssertEqual(reloaded.pin(a)?.view, .grid)
        reloaded.remove(b)
        XCTAssertEqual(StackStore(url: file).pins.map(\.id), [a])
    }

    func testDamagedEntriesAndMissingKeysDontLoseTheRest() throws {
        let file = dir.appendingPathComponent("stacks.json")
        try Data(#"[{"id":"stack:1","path":"/tmp/x","view":"sideways"},{"bogus":true},{"id":"stack:2","path":"/tmp/y"}]"#.utf8).write(to: file)
        let store = StackStore(url: file)
        XCTAssertEqual(store.pins.map(\.id), ["stack:1", "stack:2"])
        XCTAssertEqual(store.pins[0].view, .automatic)
        XCTAssertEqual(store.pins[1].display, .stack)
    }

    func testDownloadsSortsByDateAddedAndFirstRunImportsApplesFolders() throws {
        XCTAssertEqual(StackPin(path: "/Users/x/Downloads").sort, .dateAdded)
        XCTAssertEqual(StackPin(path: "/Users/x/Documents").sort, .name)
        let folder = dir.appendingPathComponent("Docs")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let tiles: [[String: Any]] = [
            ["tile-data": ["file-data": ["_CFURLString": folder.absoluteString], "showas": 2, "displayas": 1, "arrangement": 3]],
            ["tile-data": ["file-data": ["_CFURLString": "/nonexistent/folder"]]],
        ]
        let pins = StackStore.appleDockFolders(tiles)
        XCTAssertEqual(pins.count, 1)
        XCTAssertEqual(pins[0].view, .grid)
        XCTAssertEqual(pins[0].display, .folder)
        XCTAssertEqual(pins[0].sort, .dateModified)
    }

    func testContentsSkipHiddenFilesAndSortLikeTheDock() throws {
        let fm = FileManager.default
        for name in ["b.txt", "A.txt", "c10.txt", "c9.txt", ".hidden"] {
            fm.createFile(atPath: dir.appendingPathComponent(name).path, contents: Data())
        }
        try fm.createDirectory(at: dir.appendingPathComponent("Sub"), withIntermediateDirectories: true)
        let entries = StackEntry.contents(of: dir)
        XCTAssertEqual(entries.count, 5)
        XCTAssertEqual(StackEntry.sorted(entries, by: .name).map(\.name), ["A.txt", "b.txt", "c9.txt", "c10.txt", "Sub"])
        XCTAssertTrue(entries.first { $0.name == "Sub" }!.isFolder)
        var older = StackEntry(url: dir, name: "old", isFolder: false, added: Date(timeIntervalSince1970: 1))
        let newer = StackEntry(url: dir, name: "new", isFolder: false, added: Date(timeIntervalSince1970: 2))
        XCTAssertEqual(StackEntry.sorted([older, newer], by: .dateAdded).map(\.name), ["new", "old"])
        older.added = nil
        XCTAssertEqual(StackEntry.sorted([older, newer], by: .dateAdded).first?.name, "new")
    }

    func testFanRisesAndBendsRight() {
        let slots = StackLayout.fan(count: 8)
        XCTAssertEqual(slots.count, 8)
        XCTAssertEqual(slots[0].center, CGPoint(x: 0, y: StackLayout.fanStart))
        for (a, b) in zip(slots, slots.dropFirst()) {
            XCTAssertGreaterThan(b.center.y, a.center.y)
            XCTAssertGreaterThanOrEqual(b.center.x, a.center.x)
            XCTAssertLessThanOrEqual(b.rotation, a.rotation)
        }
        XCTAssertEqual(StackLayout.fanCapacity(height: 10_000), StackLayout.fanMaximum)
        XCTAssertEqual(StackLayout.fanCapacity(height: 0), 1)
    }

    func testAutomaticChoosesFanOnlyWhenItFits() {
        XCTAssertEqual(StackLayout.resolve(.automatic, count: 5, fanCapacity: 10), .fan)
        XCTAssertEqual(StackLayout.resolve(.automatic, count: 10, fanCapacity: 10), .grid, "one row is Open in Finder")
        XCTAssertEqual(StackLayout.resolve(.list, count: 500, fanCapacity: 10), .list)
    }

    func testGridIsAboutSquareAndFitsTheScreen() {
        XCTAssertEqual(StackLayout.gridColumns(count: 1, maxWidth: 1500), 1)
        XCTAssertEqual(StackLayout.gridColumns(count: 12, maxWidth: 1500), 5)
        XCTAssertEqual(StackLayout.gridColumns(count: 200, maxWidth: 1500), 8)
        XCTAssertEqual(StackLayout.gridColumns(count: 200, maxWidth: 400), 3)
        let size = StackLayout.gridSize(count: 12, columns: 5)
        XCTAssertEqual(size.width, 5 * StackLayout.gridCell.width + 2 * StackLayout.gridPadding)
    }

    func testDraggedItemsStayInTheirOwnSection() {
        // Finder, two kept apps, one open app, then three folders (the dragged item not counted).
        XCTAssertEqual(DockSections.clamp(0, isStack: false, keptApps: 3, apps: 4, stacks: 3), 1, "never before Finder")
        XCTAssertEqual(DockSections.clamp(6, isStack: false, keptApps: 3, apps: 4, stacks: 3), 3, "not among open apps or folders")
        XCTAssertEqual(DockSections.clamp(1, isStack: true, keptApps: 3, apps: 4, stacks: 2), 4, "folders stay after the apps")
        XCTAssertEqual(DockSections.clamp(9, isStack: true, keptApps: 3, apps: 4, stacks: 2), 6)
    }
}

final class StackFilingTests: XCTestCase {
    func testMovesCopiesAndNeverReplaces() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("filing-\(UUID().uuidString)")
        let folder = root.appendingPathComponent("Folder"), other = root.appendingPathComponent("Other")
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        try fm.createDirectory(at: other, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }
        let a = other.appendingPathComponent("a.txt"), b = other.appendingPathComponent("b.txt")
        let clash = other.appendingPathComponent("same.txt")
        for f in [a, b, clash] { try Data(f.lastPathComponent.utf8).write(to: f) }
        try Data("keep me".utf8).write(to: folder.appendingPathComponent("same.txt"))

        let moved = StackFiling.file([a], into: folder, copy: false)
        XCTAssertEqual(moved[a], true)
        XCTAssertFalse(fm.fileExists(atPath: a.path), "moved on the same disk")
        XCTAssertTrue(fm.fileExists(atPath: folder.appendingPathComponent("a.txt").path))

        let copied = StackFiling.file([b], into: folder, copy: true)
        XCTAssertEqual(copied[b], true)
        XCTAssertTrue(fm.fileExists(atPath: b.path), "Option copies")

        XCTAssertEqual(StackFiling.file([clash], into: folder, copy: false)[clash], false)
        XCTAssertEqual(try String(contentsOf: folder.appendingPathComponent("same.txt"), encoding: .utf8), "keep me", "never replaced")
        XCTAssertTrue(fm.fileExists(atPath: clash.path))

        XCTAssertEqual(StackFiling.file([folder], into: folder.appendingPathComponent("..").appendingPathComponent("Folder"), copy: false)[folder], false,
                       "not into itself")
        let inside = folder.appendingPathComponent("a.txt")
        XCTAssertEqual(StackFiling.file([inside], into: folder, copy: false)[inside], false, "already there")
    }
}


final class LiveMenuStateTests: XCTestCase {
    /// As macOS 27 stores it: a built-in display with three desktops (one current) and one full-screen app,
    /// and a second display with none.
    private let config: [String: Any] = ["Management Data": ["Monitors": [
        ["Current Space": ["uuid": "B"], "Spaces": [["uuid": "A", "type": 0], ["uuid": "B", "type": 0], ["uuid": "C", "type": 0],
                                                     ["uuid": "F", "type": 4]]],
        ["Current Space": [String: Any](), "Spaces": [[String: Any]]()],
    ]]]

    func testDesktopAssignmentFromSpacesRecords() {
        func parse(_ bindings: [String: Any]) -> DesktopAssignment {
            DesktopAssignment.parse(bindings: bindings, config: config, bundleID: "com.example.App").assignment
        }
        XCTAssertEqual(parse([:]), DesktopAssignment.none)
        XCTAssertEqual(parse(["com.example.app": "AllSpaces"]), .all, "bundle ids match without regard to case")
        XCTAssertEqual(parse(["com.example.App": "B"]), .thisDesktop)
        XCTAssertEqual(parse(["com.example.App": "C"]), .otherDesktop)
        XCTAssertEqual(parse(["com.other": "AllSpaces"]), DesktopAssignment.none)
        XCTAssertEqual(DesktopAssignment.parse(bindings: [:], config: config, bundleID: "x").desktops, 3, "full-screen spaces don't count")
        XCTAssertEqual(DesktopAssignment.parse(bindings: [:], config: nil, bundleID: "x").desktops, 0)
    }

    func testAssignToRowsAreTickedFromTheLiveAssignment() {
        let rows: [DockMenuItem] = [.header("Assign To"), .item("All Desktops", .none, mark: .check), .item("This Desktop", .none),
                                    .item("Desktop on Display 2", .none, mark: .check), .item("None", .none)]
        func ticked(_ a: DesktopAssignment) -> [String] {
            AppleMenuMirror.markAssignTo(rows, assignment: a, strings: .english).filter { $0.mark == .check }.map(\.title)
        }
        XCTAssertEqual(ticked(.thisDesktop), ["This Desktop"])
        XCTAssertEqual(ticked(.all), ["All Desktops"])
        XCTAssertEqual(ticked(.none), ["None"])
        XCTAssertEqual(ticked(.otherDesktop), [])
        XCTAssertEqual(AppleMenuMirror.markAssignTo(rows, assignment: .all, strings: .english).first?.kind, .header)
    }

    func testLoginItemsMatchByLocationOrBundleIdentifier() {
        let items = [URL(fileURLWithPath: "/Applications/Mail.app"), URL(fileURLWithPath: "/Users/x/Apps/Notes Copy.app")]
        XCTAssertTrue(LoginItemMatch.matches(items, appURL: URL(fileURLWithPath: "/Applications/Mail.app/"), bundleID: nil))
        XCTAssertTrue(LoginItemMatch.matches(items, appURL: URL(fileURLWithPath: "/System/Applications/Notes.app"), bundleID: "com.apple.Notes",
                                             bundleIDOf: { $0.lastPathComponent == "Notes Copy.app" ? "com.apple.Notes" : nil }))
        XCTAssertFalse(LoginItemMatch.matches(items, appURL: URL(fileURLWithPath: "/Applications/Safari.app"), bundleID: "com.apple.Safari",
                                              bundleIDOf: { _ in nil }))
    }
}
