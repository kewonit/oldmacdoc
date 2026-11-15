import AppKit

/// How each shelf style looks, from measurements of the original Dock (see
/// research_notes/Original glass dock fidelity). Clear Glass is the 10.5–10.7 shelf, Frosted the
/// 10.8 shelf, and Smoke our own dark variant built on the 10.8 shelf. Lengths are multiples of the
/// resting icon size `s` (measured at s = 64 px). All art is drawn in code.
struct ShelfLook {
    enum Era { case leopard, mountainLion }

    let style: ShelfStyle
    var era: Era { style == .clear ? .leopard : .mountainLion }

    // MARK: Geometry (× s)

    /// Back edge of the floor above the bottom of the screen.
    var floorHeight: CGFloat { era == .leopard ? 0.81 : 0.78 }
    /// Where icons stand, above the bottom of the screen. Icons never cover the front line.
    var iconBase: CGFloat { era == .leopard ? 0.36 : 0.30 }
    /// How far the back edge runs past the outer tiles.
    var backPad: CGFloat { era == .leopard ? 0.10 : 2.0 / 64 }

    /// Mountain Lion's opaque front face (3 px at s = 64); Leopard has none.
    func lipHeight(_ s: CGFloat) -> CGFloat { era == .leopard ? 0 : max(2, (3.0 / 64 * s).rounded()) }
    /// The bright front line: 3 px on Leopard, 1 px of white above the lip later.
    func lineHeight(_ s: CGFloat) -> CGFloat { era == .leopard ? max(2, (3.0 / 64 * s).rounded()) : 1 }

    // MARK: Reflections and shadows

    var reflectionOpacity: Float {
        switch style {
        case .clear: 0.45
        case .frosted: 0.31
        case .smoke: 0.3
        }
    }
    /// Leopard's reflections fade toward the front; later shelves keep them even.
    var reflectionFrontAlpha: CGFloat { era == .leopard ? 0.5 : 0.9 }
    var shadowOpacity: Float { style == .smoke ? 0.45 : 0.3 }

    // MARK: Blur

    var blur: NSVisualEffectView.Material? {
        switch style {
        case .clear: nil // Leopard's glass didn't blur what's behind it
        case .frosted: .popover
        case .smoke: .hudWindow
        }
    }
    var blurAppearance: NSAppearance.Name { style == .smoke ? .darkAqua : .aqua }

    // MARK: Floor paint

    private static func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat) -> CGColor {
        CGColor(srgbRed: r / 255, green: g / 255, blue: b / 255, alpha: a)
    }

    /// Colour stops for the shelf (lip, front line and floor), in points from the bottom of the screen
    /// up to `top`. Two stops at the same height make a hard edge.
    func stops(top: CGFloat, size s: CGFloat) -> [(y: CGFloat, color: CGColor)] {
        let rgb = Self.rgb
        let lip = lipHeight(s), line = lineHeight(s)
        var stops: [(CGFloat, CGColor)]
        switch style {
        case .clear:
            // Leopard, measured over black and painted at ~0.85 opacity (paint = measurement / 0.85):
            // a bright front line, a thin dark seam, the near band, then a lighter band behind a step
            // 20 px (at s = 64) in front of the back edge.
            let seam = max(1, (1.5 / 64 * s).rounded()), step = top - (20.0 / 64 * s).rounded()
            stops = [(0, rgb(163, 163, 168, 0.95)), (line, rgb(242, 242, 247, 0.95)),
                     (line, rgb(70, 70, 78, 0.9)), (line + seam, rgb(70, 70, 78, 0.9)),
                     (line + seam, rgb(160, 160, 166, 0.85)), (step, rgb(139, 139, 145, 0.85)),
                     (step, rgb(179, 179, 185, 0.85)), (top, rgb(137, 135, 141, 0.85))]
        case .frosted:
            // Mountain Lion: an opaque grey lip, one white line, then a smooth cool floor over the blur.
            stops = [(0, rgb(137, 143, 149, 1)), (lip, rgb(137, 143, 149, 1)),
                     (lip, rgb(250, 252, 255, 1)), (lip + line, rgb(250, 252, 255, 1)),
                     (lip + line, rgb(193, 202, 210, 0.72)), (top, rgb(114, 130, 143, 0.72))]
        case .smoke:
            stops = [(0, rgb(52, 54, 58, 1)), (lip, rgb(52, 54, 58, 1)),
                     (lip, rgb(200, 204, 210, 0.9)), (lip + line, rgb(200, 204, 210, 0.9)),
                     (lip + line, rgb(74, 78, 84, 0.78)), (top, rgb(26, 28, 32, 0.78))]
        }
        return stops.map { (min(max($0.0, 0), top), $0.1) }
    }

    /// Height of the indicator's centre above the bottom of the screen.
    func indicatorY(_ s: CGFloat) -> CGFloat { era == .leopard ? (0.14 * s).rounded() : lipHeight(s) / 2 }
}

/// Running-app indicators, drawn in code at a fixed size per icon size (they don't magnify).
enum IndicatorArt {
    private static var cache: [String: (CGImage, CGSize)] = [:]

    static func image(era: ShelfLook.Era, size s: CGFloat, scale: CGFloat) -> (image: CGImage, size: CGSize)? {
        let key = "\(era)-\(s)-\(scale)"
        if let hit = cache[key] { return hit }
        let made = era == .leopard ? blob(s, scale) : bar(s, scale)
        if let made { cache[key] = made }
        return made
    }

    private static func context(_ size: CGSize, _ scale: CGFloat) -> CGContext? {
        let w = Int((size.width * scale).rounded()), h = Int((size.height * scale).rounded())
        let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                            space: Bitmap.colorSpace, bitmapInfo: Bitmap.bitmapInfo)
        ctx?.scaleBy(x: scale, y: scale)
        return ctx
    }

    private static func color(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat) -> CGColor {
        CGColor(srgbRed: r / 255, green: g / 255, blue: b / 255, alpha: a)
    }

    /// Leopard: a blue-white light lying on the floor (core ~0.13 s wide, glow ~0.3 s).
    private static func blob(_ s: CGFloat, _ scale: CGFloat) -> (CGImage, CGSize)? {
        let size = CGSize(width: max(10, (0.34 * s).rounded()), height: max(6, (0.18 * s).rounded()))
        guard let ctx = context(size, scale) else { return nil }
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        func ellipse(width: CGFloat, height: CGFloat, colors: [CGColor], locations: [CGFloat]) {
            guard let g = CGGradient(colorsSpace: Bitmap.colorSpace, colors: colors as CFArray, locations: locations) else { return }
            ctx.saveGState()
            ctx.translateBy(x: center.x, y: center.y)
            ctx.scaleBy(x: 1, y: height / width)
            ctx.drawRadialGradient(g, startCenter: .zero, startRadius: 0, endCenter: .zero, endRadius: width / 2, options: [])
            ctx.restoreGState()
        }
        ellipse(width: size.width, height: size.height,
                colors: [color(130, 180, 225, 0.6), color(130, 180, 225, 0.25), color(130, 180, 225, 0)], locations: [0, 0.5, 1])
        let core = max(4, 0.13 * s)
        ellipse(width: core * 1.5, height: core * 0.95,
                colors: [color(250, 253, 255, 1), color(225, 240, 255, 0.95), color(160, 205, 245, 0)], locations: [0, 0.45, 1])
        guard let image = ctx.makeImage() else { return nil }
        return (image, size)
    }

    /// Mountain Lion: a short white bar on the lip with a soft blue halo.
    private static func bar(_ s: CGFloat, _ scale: CGFloat) -> (CGImage, CGSize)? {
        let barSize = CGSize(width: max(8, (0.19 * s).rounded()), height: max(2, (3.0 / 64 * s).rounded()))
        let halo = max(3, (0.09 * s).rounded())
        let size = CGSize(width: barSize.width + halo * 2, height: barSize.height + halo * 1.4)
        guard let ctx = context(size, scale) else { return nil }
        let rect = CGRect(x: halo, y: (size.height - barSize.height) / 2, width: barSize.width, height: barSize.height)
        let path = CGPath(roundedRect: rect, cornerWidth: barSize.height / 2, cornerHeight: barSize.height / 2, transform: nil)
        // Shadow blur is in device pixels, so scale it; two passes give the halo its strength.
        ctx.setShadow(offset: .zero, blur: halo * scale, color: color(145, 179, 202, 1))
        ctx.setFillColor(color(250, 252, 255, 1))
        for _ in 0..<2 {
            ctx.addPath(path)
            ctx.fillPath()
        }
        guard let image = ctx.makeImage() else { return nil }
        return (image, size)
    }
}
