import AppKit

/// Watches the user's Trash without Full Disk Access: listing ~/.Trash is blocked by TCC,
/// but stat() on the folder still works and APFS reports entries + 2 as its link count.
final class TrashMonitor {
    let url: URL
    private(set) var isFull = false
    var onChange: (() -> Void)?
    private var timer: Timer?
    private var lastStamp = ""

    init() {
        url = (try? FileManager.default.url(for: .trashDirectory, in: .userDomainMask, appropriateFor: nil, create: false))
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".Trash")
        refresh()
        // A stat() every few seconds is negligible; directory watching needs an fd TCC may refuse.
        timer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in self?.refresh() }
        timer?.tolerance = 2
    }

    func refresh() {
        var st = stat()
        guard stat(url.path, &st) == 0 else { return }
        let stamp = "\(st.st_nlink)-\(st.st_mtimespec.tv_sec)"
        guard stamp != lastStamp else { return }
        lastStamp = stamp

        let full: Bool
        if let names = try? FileManager.default.contentsOfDirectory(atPath: url.path) {
            full = names.contains { $0 != ".DS_Store" }
        } else {
            let dsStore = FileManager.default.fileExists(atPath: url.appendingPathComponent(".DS_Store").path) ? 1 : 0
            full = Int(st.st_nlink) - 2 - dsStore > 0
        }
        if full != isFull {
            isFull = full
            onChange?()
        }
    }

    func open() { NSWorkspace.shared.open(url) }

    /// Asks Finder to empty the Trash after confirming. macOS asks once for permission to control
    /// Finder; nothing is requested until the user actually chooses Empty Trash.
    func empty() {
        let alert = NSAlert()
        alert.messageText = "Are you sure you want to permanently erase the items in the Trash?"
        alert.informativeText = "You can’t undo this action."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Empty Trash")
        alert.addButton(withTitle: "Cancel")
        NSApp.activate()
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", "tell application \"Finder\" to empty trash"]
        process.standardError = FileHandle.nullDevice
        process.terminationHandler = { [weak self] p in
            DispatchQueue.main.async {
                if p.terminationStatus != 0 { NSSound.beep() }
                self?.lastStamp = ""
                self?.refresh()
            }
        }
        try? process.run()
    }

    func trash(_ urls: [URL]) {
        for u in urls { try? FileManager.default.trashItem(at: u, resultingItemURL: nil) }
        lastStamp = ""
        refresh()
    }
}

/// Our own Trash artwork, drawn in code: a glass-and-wire bin, with paper when full.
enum TrashArt {
    private static var cache: [Bool: CGImage] = [:]

    static func image(full: Bool) -> CGImage? {
        if let hit = cache[full] { return hit }
        let image = draw(full: full, size: 512)
        cache[full] = image
        return image
    }

    private static func draw(full: Bool, size: Int) -> CGImage? {
        let s = CGFloat(size)
        guard let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: size * 4,
                                  space: Bitmap.colorSpace, bitmapInfo: Bitmap.bitmapInfo) else { return nil }
        let cx = s / 2, topY = s * 0.80, botY = s * 0.06
        let topW = s * 0.66, botW = s * 0.50, rimH = s * 0.11, baseH = s * 0.08
        let space = Bitmap.colorSpace

        func gradient(_ stops: [(CGFloat, CGFloat)]) -> CGGradient {
            let colors = stops.map { CGColor(gray: $0.0, alpha: $0.1) } as CFArray
            return CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.genericGrayGamma2_2), colors: colors, locations: nil)!
        }

        // Body.
        let body = CGMutablePath()
        body.move(to: CGPoint(x: cx - topW / 2, y: topY))
        body.addLine(to: CGPoint(x: cx - botW / 2, y: botY + baseH / 2))
        body.addCurve(to: CGPoint(x: cx + botW / 2, y: botY + baseH / 2),
                      control1: CGPoint(x: cx - botW / 2, y: botY - baseH / 3), control2: CGPoint(x: cx + botW / 2, y: botY - baseH / 3))
        body.addLine(to: CGPoint(x: cx + topW / 2, y: topY))
        body.closeSubpath()
        ctx.saveGState()
        ctx.addPath(body); ctx.clip()
        ctx.drawLinearGradient(gradient([(0.35, 0.85), (0.80, 0.80), (0.97, 0.75), (0.70, 0.80), (0.30, 0.88)]),
                               start: CGPoint(x: cx - topW / 2, y: 0), end: CGPoint(x: cx + topW / 2, y: 0), options: [])
        // Wire ribs following the taper, and hoops.
        ctx.setLineWidth(s * 0.009)
        for i in 1..<14 {
            let t = CGFloat(i) / 14
            ctx.move(to: CGPoint(x: cx - topW / 2 + topW * t, y: topY))
            ctx.addLine(to: CGPoint(x: cx - botW / 2 + botW * t, y: botY))
            ctx.setStrokeColor(CGColor(gray: i % 2 == 0 ? 1 : 0.15, alpha: i % 2 == 0 ? 0.45 : 0.25))
            ctx.strokePath()
        }
        for i in 1..<5 {
            let t = CGFloat(i) / 5
            let y = botY + (topY - botY) * t, w = botW + (topW - botW) * t
            ctx.addEllipse(in: CGRect(x: cx - w / 2, y: y - rimH * 0.35, width: w, height: rimH * 0.7))
            ctx.setStrokeColor(CGColor(gray: 1, alpha: 0.28)); ctx.strokePath()
        }
        ctx.restoreGState()

        // Opening.
        let opening = CGRect(x: cx - topW / 2, y: topY - rimH / 2, width: topW, height: rimH)
        ctx.saveGState()
        ctx.addEllipse(in: opening); ctx.clip()
        ctx.drawLinearGradient(gradient([(0.08, 0.95), (0.30, 0.9)]), start: CGPoint(x: 0, y: opening.maxY),
                               end: CGPoint(x: 0, y: opening.minY), options: [])
        ctx.restoreGState()

        if full {
            let papers: [(CGFloat, CGFloat, CGFloat, CGFloat)] = [(-0.16, 0.05, 0.20, 0.97), (0.05, 0.09, 0.24, 0.93), (0.17, 0.03, 0.17, 0.99)]
            for (dx, dy, r, g) in papers {
                let rect = CGRect(x: cx + s * dx - s * r / 2, y: topY - s * 0.02 + s * dy - s * r * 0.35, width: s * r, height: s * r * 0.8)
                let blob = CGMutablePath()
                let pts = 9
                for k in 0..<pts {
                    let a = CGFloat(k) / CGFloat(pts) * 2 * .pi
                    let wobble: CGFloat = k % 2 == 0 ? 1 : 0.78
                    let p = CGPoint(x: rect.midX + cos(a) * rect.width / 2 * wobble, y: rect.midY + sin(a) * rect.height / 2 * wobble)
                    k == 0 ? blob.move(to: p) : blob.addLine(to: p)
                }
                blob.closeSubpath()
                ctx.saveGState()
                ctx.addPath(blob); ctx.clip()
                ctx.drawLinearGradient(gradient([(1, 1), (g * 0.82, 1)]), start: CGPoint(x: 0, y: rect.maxY),
                                       end: CGPoint(x: 0, y: rect.minY), options: [])
                ctx.restoreGState()
                ctx.addPath(blob); ctx.setStrokeColor(CGColor(gray: 0.55, alpha: 0.8)); ctx.setLineWidth(s * 0.004); ctx.strokePath()
            }
        }

        // Rim.
        ctx.addEllipse(in: opening)
        ctx.setLineWidth(s * 0.028)
        ctx.setStrokeColor(CGColor(colorSpace: space, components: [0.86, 0.88, 0.92, 1])!)
        ctx.strokePath()
        ctx.addEllipse(in: opening.insetBy(dx: s * 0.012, dy: s * 0.006))
        ctx.setLineWidth(s * 0.006)
        ctx.setStrokeColor(CGColor(gray: 1, alpha: 0.9))
        ctx.strokePath()
        return ctx.makeImage()
    }
}
