import AppKit

/// Apps' Dock badges (the red count on Mail, Messages, …). Each app sets its own through its Dock tile;
/// macOS keeps it in LaunchServices as the app's "StatusLabel", which any app can read without
/// permission. Private calls, looked up at runtime: if they're missing, there are simply no badges.
final class BadgeMonitor {
    /// Bundle identifier (or path) → label, for running apps that have one. An empty label is a plain dot.
    private(set) var labels: [String: String] = [:]
    var onChange: (() -> Void)?
    /// The apps to check: the running apps on the dock, by key, with their process ids. Only those are
    /// looked at, so a check never lists the system's processes (each one's details cost a trip to
    /// LaunchServices).
    var wanted: () -> [String: pid_t] = { [:] }

    private typealias CreateASN = @convention(c) (CFAllocator?, pid_t) -> Unmanaged<CFTypeRef>?
    private typealias CopyItem = @convention(c) (Int32, CFTypeRef, CFString) -> Unmanaged<CFTypeRef>?
    private let createASN: CreateASN?
    private let copyItem: CopyItem?
    private var timer: Timer?

    init() {
        let ls = dlopen("/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/LaunchServices", RTLD_LAZY)
        createASN = dlsym(ls, "_LSASNCreateWithPid").map { unsafeBitCast($0, to: CreateASN.self) }
        copyItem = dlsym(ls, "_LSCopyApplicationInformationItem").map { unsafeBitCast($0, to: CopyItem.self) }
    }

    static func key(bundleID: String?, path: String?) -> String { bundleID ?? path ?? "" }

    /// Checks once a second (a handful of quick local lookups), reporting only changes.
    func start() {
        guard createASN != nil, copyItem != nil, timer == nil else { return }
        poll()
        let t = Timer(timeInterval: 1, repeats: true) { [weak self] _ in self?.poll() }
        t.tolerance = 0.3
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    func poll() {
        guard let createASN, let copyItem else { return }
        var next: [String: String] = [:]
        let wanted = wanted()
        guard !wanted.isEmpty else {
            if !labels.isEmpty { labels = [:]; onChange?() }
            return
        }
        for (key, pid) in wanted {
            guard let asn = createASN(nil, pid)?.takeRetainedValue(),
                  let info = copyItem(-2, asn, "StatusLabel" as CFString)?.takeRetainedValue() as? [String: Any],
                  let label = info["label"] as? String else { continue }
            next[key] = label
        }
        if next != labels {
            labels = next
            onChange?()
        }
    }
}

/// The badge itself, drawn in code: Leopard's glossy red oval with a white rim and white bold text.
enum BadgeArt {
    private static var cache: [String: CGImage] = [:]

    /// The badge for `label` at `height` pixels; it widens for longer labels (an empty label is a dot).
    static func image(_ label: String, height: Int) -> CGImage? {
        let text = String(label.prefix(6))
        let key = "\(text)-\(height)"
        if let hit = cache[key] { return hit }
        let h = CGFloat(height)
        let font = NSFont(name: "Helvetica-Bold", size: h * 0.56) ?? .boldSystemFont(ofSize: h * 0.56)
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.white]
        let textSize = (text as NSString).size(withAttributes: attrs)
        let shadow = max(1, h * 0.08)
        let body = CGSize(width: text.isEmpty ? h * 0.55 : max(h, textSize.width + h * 0.62), height: text.isEmpty ? h * 0.55 : h)
        let size = CGSize(width: ceil(body.width + 2 * shadow), height: ceil(h + 2 * shadow))
        guard let ctx = CGContext(data: nil, width: Int(size.width), height: Int(size.height), bitsPerComponent: 8,
                                  bytesPerRow: 0, space: Bitmap.colorSpace, bitmapInfo: Bitmap.bitmapInfo) else { return nil }
        let rect = CGRect(x: (size.width - body.width) / 2, y: (size.height - body.height) / 2 + shadow * 0.3,
                          width: body.width, height: body.height)
        let oval = CGPath(roundedRect: rect, cornerWidth: body.height / 2, cornerHeight: body.height / 2, transform: nil)
        // A soft shadow under the whole badge.
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -shadow * 0.5), blur: shadow * 1.5, color: CGColor(gray: 0, alpha: 0.55))
        ctx.addPath(oval)
        ctx.setFillColor(CGColor(gray: 1, alpha: 1))
        ctx.fillPath()
        ctx.restoreGState()
        // White rim, then the red body inside it.
        let rim = max(1, h * 0.075)
        let inner = rect.insetBy(dx: rim, dy: rim)
        let innerPath = CGPath(roundedRect: inner, cornerWidth: inner.height / 2, cornerHeight: inner.height / 2, transform: nil)
        ctx.saveGState()
        ctx.addPath(innerPath)
        ctx.clip()
        let red = [CGColor(srgbRed: 0.98, green: 0.30, blue: 0.24, alpha: 1), CGColor(srgbRed: 0.80, green: 0.05, blue: 0.04, alpha: 1)] as CFArray
        if let g = CGGradient(colorsSpace: Bitmap.colorSpace, colors: red, locations: [0, 1]) {
            ctx.drawLinearGradient(g, start: CGPoint(x: 0, y: inner.maxY), end: CGPoint(x: 0, y: inner.minY), options: [])
        }
        // Leopard's gloss: a lighter band over the top half.
        let gloss = CGRect(x: inner.minX + inner.height * 0.12, y: inner.midY, width: inner.width - inner.height * 0.24,
                           height: inner.height * 0.48)
        ctx.addPath(CGPath(roundedRect: gloss, cornerWidth: gloss.height / 2, cornerHeight: gloss.height / 2, transform: nil))
        ctx.setFillColor(CGColor(gray: 1, alpha: 0.22))
        ctx.fillPath()
        ctx.restoreGState()
        if !text.isEmpty {
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
            (text as NSString).draw(at: CGPoint(x: rect.midX - textSize.width / 2, y: rect.midY - textSize.height / 2 + h * 0.02),
                                    withAttributes: attrs)
            NSGraphicsContext.restoreGraphicsState()
        }
        let image = ctx.makeImage()
        // Counts come and go: keep only the recent ones.
        if cache.count >= 64 { cache.removeAll() }
        cache[key] = image
        return image
    }
}
