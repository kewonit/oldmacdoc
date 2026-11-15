import AppKit

/// Shelf art drawn once into small bitmaps, so a frame of magnification or sliding only moves and
/// stretches layers. Shape masks with a new path every frame make WindowServer rasterize them on
/// the CPU for every frame (measured: about a quarter of a core while hovering), so nothing here
/// changes shape per frame.
enum ShelfArt {
    /// How much of a reflection is kept, as a share of the icon's height. Only the part between the
    /// icon's base and the front line ever shows (under a third of a resting icon, less when magnified).
    static let reflectionDepth: CGFloat = 0.4

    private static var floors: [String: Floor] = [:]
    private static var zebras: [String: CGImage] = [:]

    struct Floor {
        let image: CGImage
        /// Where the stretchable middle column sits, in the layer's unit coordinates (`contentsCenter`).
        let center: CGRect
    }

    private static func context(width: CGFloat, height: CGFloat, scale: CGFloat) -> CGContext? {
        let w = Int((width * scale).rounded(.up)), h = Int((height * scale).rounded(.up))
        guard w > 0, h > 0 else { return nil }
        let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                            space: Bitmap.colorSpace, bitmapInfo: Bitmap.bitmapInfo)
        ctx?.scaleBy(x: scale, y: scale)
        return ctx
    }

    /// The whole shelf (lip, front line and glass floor) as a narrow image whose single middle column
    /// stretches to any width. The ends have a fixed slant (the overhang depends only on the height),
    /// so they are drawn once at their real size and never distort as the dock widens.
    static func floor(look: ShelfLook, size s: CGFloat, top: CGFloat, scale: CGFloat) -> Floor? {
        let key = "\(look.style.rawValue)-\(s)-\(top)-\(scale)"
        if let hit = floors[key] { return hit }
        let lip = look.lipHeight(s)
        let overhang = ShelfGeometry.overhang(height: top - lip)
        let cap = overhang + 4 // the slanted end plus its rounded back corner
        let width = cap * 2 + 2
        guard let ctx = context(width: width, height: top, scale: scale) else { return nil }
        drawFloor(ShelfGeometry(lip: lip, top: top, backLeft: overhang, backRight: width - overhang), look: look, size: s, in: ctx)
        guard let image = ctx.makeImage() else { return nil }
        let floor = Floor(image: image, center: CGRect(x: cap / width, y: 0, width: 2 / width, height: 1))
        floors[key] = floor
        return floor
    }

    /// Paints a shelf (lip, front line and glass floor) in `shape`, with its bottom at y = 0 of `ctx`.
    /// Each band between two colour stops is its own gradient, so equal heights give hard edges.
    static func drawFloor(_ shape: ShelfGeometry, look: ShelfLook, size s: CGFloat, in ctx: CGContext) {
        ctx.saveGState()
        ctx.addPath(shape.outline())
        ctx.clip()
        let stops = look.stops(top: shape.top, size: s)
        let width = shape.frontRight - shape.frontLeft
        for (a, b) in zip(stops, stops.dropFirst()) where b.y > a.y {
            guard let g = CGGradient(colorsSpace: Bitmap.colorSpace, colors: [a.color, b.color] as CFArray, locations: [0, 1])
            else { continue }
            ctx.saveGState()
            ctx.clip(to: CGRect(x: shape.frontLeft, y: a.y, width: width, height: b.y - a.y))
            ctx.drawLinearGradient(g, start: CGPoint(x: 0, y: a.y), end: CGPoint(x: 0, y: b.y),
                                   options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
            ctx.restoreGState()
        }
        ctx.restoreGState()
    }

    /// An icon's reflection: the bottom of the icon mirrored, with the fade toward the front and the
    /// shelf's reflection opacity baked in (no mask, no group opacity). The image's top row is the
    /// icon's base. It's drawn at 256 px wide, enough for the largest magnified icon at 2x.
    static func reflection(of icon: CGImage, look: ShelfLook) -> CGImage? {
        let w: CGFloat = 256, h = (w * reflectionDepth).rounded()
        guard let ctx = context(width: w, height: h, scale: 1) else { return nil }
        ctx.interpolationQuality = .high
        ctx.saveGState()
        ctx.translateBy(x: 0, y: h)
        ctx.scaleBy(x: 1, y: -1)
        ctx.draw(icon, in: CGRect(x: 0, y: 0, width: w, height: w))
        ctx.restoreGState()
        // Full strength at the base, fading to `reflectionFrontAlpha` a third of the icon away.
        let opacity = CGFloat(look.reflectionOpacity)
        let colors = [CGColor(gray: 0, alpha: opacity), CGColor(gray: 0, alpha: opacity * look.reflectionFrontAlpha)] as CFArray
        if let fade = CGGradient(colorsSpace: Bitmap.colorSpace, colors: colors, locations: [0, 1]) {
            ctx.setBlendMode(.destinationIn)
            ctx.drawLinearGradient(fade, start: CGPoint(x: 0, y: h), end: CGPoint(x: 0, y: h - w * 0.35),
                                   options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
        }
        return ctx.makeImage()
    }

    /// Leopard's "zebra crossing" separator: eight upright white bars, as the original's separator
    /// image (no perspective lean, see the visual spec). Bars and gaps are equal and grow from about
    /// 1.6 to 4.8 px (at s = 64) toward the viewer, from 2 to 43 px in front of the back edge, while
    /// the bars widen from 0.16 s to 0.34 s. The image's top is the floor's back edge.
    static func zebra(size s: CGFloat, top: CGFloat, front: CGFloat, scale: CGFloat) -> (image: CGImage, size: CGSize)? {
        let key = "\(s)-\(top)-\(front)-\(scale)"
        let width = (s * 0.34).rounded(.up) + 2, height = (43.0 / 64 * s).rounded(.up) + 1
        if let hit = zebras[key] { return (hit, CGSize(width: width, height: height)) }
        guard let ctx = context(width: width, height: height, scale: scale) else { return nil }
        let growth = pow(3, 1.0 / 7)
        let weights = (0..<8).map { pow(growth, CGFloat($0)) }
        let back = 2.0 / 64 * s, near = 43.0 / 64 * s
        let unit = (near - back) / (2 * weights.reduce(0, +))
        ctx.setFillColor(CGColor(gray: 1, alpha: 0.35))
        var y = back // distance in front of the back edge
        for weight in weights {
            let thickness = weight * unit
            let depth = (y + thickness / 2) / max(top - front, 1)
            let w = s * (0.16 + 0.18 * depth)
            ctx.fill(CGRect(x: (width - w) / 2, y: height - y - thickness, width: w, height: thickness))
            y += thickness * 2
        }
        guard let image = ctx.makeImage() else { return nil }
        zebras[key] = image
        return (image, CGSize(width: width, height: height))
    }
}
