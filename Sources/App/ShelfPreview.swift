import AppKit
import CoreImage

/// A small dock drawn with the dock's own art: icons standing on a shelf, their reflections in the
/// glass, contact shadows and lights under open apps, over a backdrop. The settings panel shows each
/// shelf this way, with the user's own icons on their wallpaper.
enum ShelfPreview {
    struct Item {
        var image: CGImage
        var lit = false
    }

    /// Draws `items` standing on `style`'s shelf along the bottom of `rect` (CoreGraphics coordinates,
    /// y up), centred, the shelf ending just past the outer icons with its slanted ends. Frosted and
    /// Smoke show `backdrop`, blurred, through the glass, as the dock does.
    static func draw(in ctx: CGContext, rect: CGRect, style: ShelfStyle, iconSize s: CGFloat, items: [Item],
                     backdrop: CGImage?, scale: CGFloat) {
        let look = ShelfLook(style: style)
        let gap = max(1, (s * 0.06).rounded())
        let widths = items.map { _ in s }
        let row = widths.reduce(0, +) + gap * CGFloat(max(items.count - 1, 0))
        let base = rect.minY
        let standY = base + (look.iconBase * s).rounded()
        let top = (look.floorHeight * s).rounded()
        let lip = look.lipHeight(s), front = base + lip + look.lineHeight(s)
        var x = rect.midX - row / 2
        let frames = widths.map { w -> CGRect in
            defer { x += w + gap }
            return CGRect(x: x, y: standY, width: w, height: w)
        }
        let pad = gap / 2 + look.backPad * s
        let shelf = ShelfGeometry(lip: lip, top: top, backLeft: rect.midX - row / 2 - pad, backRight: rect.midX + row / 2 + pad)
        let reach = shelf.overhang

        ctx.saveGState()
        ctx.clip(to: rect)

        // The glass: Frosted and Smoke blur what's behind them and tint it, under the floor's colours.
        ctx.saveGState()
        ctx.translateBy(x: 0, y: base)
        if look.blur != nil {
            ctx.saveGState()
            ctx.addPath(shelf.outline())
            ctx.clip()
            if let backdrop, let blurred = blurred(backdrop, radius: 8 * scale) {
                ctx.draw(blurred, in: CGRect(x: rect.minX, y: 0, width: rect.width, height: rect.height))
            }
            ctx.setFillColor(style == .smoke ? CGColor(gray: 0.08, alpha: 0.55) : CGColor(gray: 0.97, alpha: 0.55))
            ctx.fill(CGRect(x: rect.minX - reach, y: 0, width: rect.width + reach * 2, height: top))
            ctx.restoreGState()
        }
        ShelfArt.drawFloor(shelf, look: look, size: s, in: ctx)
        ctx.restoreGState()

        // Contact shadows.
        for f in frames {
            let shadow = CGRect(x: f.midX - f.width * 0.48, y: standY - f.width * 0.08, width: f.width * 0.96, height: f.width * 0.16)
            guard let g = CGGradient(colorsSpace: Bitmap.colorSpace,
                                     colors: [CGColor(gray: 0, alpha: CGFloat(look.shadowOpacity)), CGColor(gray: 0, alpha: 0)] as CFArray,
                                     locations: [0, 1]) else { continue }
            ctx.saveGState()
            ctx.translateBy(x: shadow.midX, y: shadow.midY)
            ctx.scaleBy(x: 1, y: shadow.height / shadow.width)
            ctx.drawRadialGradient(g, startCenter: .zero, startRadius: 0, endCenter: .zero, endRadius: shadow.width / 2, options: [])
            ctx.restoreGState()
        }

        // Reflections: each icon mirrored at its base, fading toward the front, ending at the front line.
        ctx.saveGState()
        ctx.clip(to: CGRect(x: rect.minX, y: front, width: rect.width, height: max(0, standY - front)))
        ctx.beginTransparencyLayer(auxiliaryInfo: nil)
        for (item, f) in zip(items, frames) {
            ctx.saveGState()
            ctx.translateBy(x: 0, y: standY * 2)
            ctx.scaleBy(x: 1, y: -1)
            ctx.draw(item.image, in: f)
            ctx.restoreGState()
        }
        let opacity = CGFloat(look.reflectionOpacity)
        if let fade = CGGradient(colorsSpace: Bitmap.colorSpace,
                                 colors: [CGColor(gray: 0, alpha: opacity), CGColor(gray: 0, alpha: opacity * look.reflectionFrontAlpha)] as CFArray,
                                 locations: [0, 1]) {
            ctx.setBlendMode(.destinationIn)
            ctx.drawLinearGradient(fade, start: CGPoint(x: 0, y: standY), end: CGPoint(x: 0, y: standY - s * 0.35),
                                   options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
        }
        ctx.endTransparencyLayer()
        ctx.restoreGState()

        ctx.interpolationQuality = .high
        for (item, f) in zip(items, frames) { ctx.draw(item.image, in: f) }

        // Lights under open apps.
        if let light = IndicatorArt.image(era: look.era, size: s, scale: scale) {
            for (item, f) in zip(items, frames) where item.lit {
                let y = base + look.indicatorY(s)
                ctx.draw(light.image, in: CGRect(x: f.midX - light.size.width / 2, y: y - light.size.height / 2,
                                                 width: light.size.width, height: light.size.height))
            }
        }
        ctx.restoreGState()
    }

    /// The settings panel's picture of `style`: `items` on that shelf over the bottom middle of the
    /// user's wallpaper, `size` points at `scale`.
    static func thumbnail(_ style: ShelfStyle, size: CGSize, scale: CGFloat, items: [Item], wallpaper: CGImage?) -> CGImage? {
        let w = Int((size.width * scale).rounded()), h = Int((size.height * scale).rounded())
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                  space: Bitmap.colorSpace, bitmapInfo: Bitmap.bitmapInfo) else { return nil }
        ctx.scaleBy(x: scale, y: scale)
        let rect = CGRect(origin: .zero, size: size)
        let backdrop = wallpaper.flatMap { dockStrip(of: $0, aspect: size.width / size.height) } ?? plainDesktop
        ctx.interpolationQuality = .high
        if let backdrop { ctx.draw(backdrop, in: rect) }
        draw(in: ctx, rect: rect, style: style, iconSize: (size.height * 0.45).rounded(), items: items, backdrop: backdrop, scale: scale)
        return ctx.makeImage()
    }

    /// The bottom middle of a wallpaper, where the dock sits: a strip about a third of its width.
    static func dockStrip(of image: CGImage, aspect: CGFloat) -> CGImage? {
        let w = CGFloat(image.width), h = CGFloat(image.height)
        let cropWidth = min(w, w * 0.34), cropHeight = min(h, cropWidth / aspect)
        return image.cropping(to: CGRect(x: ((w - cropWidth) / 2).rounded(), y: (h - cropHeight).rounded(),
                                         width: cropWidth.rounded(), height: cropHeight.rounded()))
    }

    /// A quiet desktop for when the wallpaper can't be read (a live wallpaper, say).
    private static let plainDesktop: CGImage? = {
        let size = 64
        guard let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: size * 4,
                                  space: Bitmap.colorSpace, bitmapInfo: Bitmap.bitmapInfo),
              let g = CGGradient(colorsSpace: Bitmap.colorSpace,
                                 colors: [CGColor(srgbRed: 0.33, green: 0.38, blue: 0.47, alpha: 1),
                                          CGColor(srgbRed: 0.16, green: 0.19, blue: 0.25, alpha: 1)] as CFArray,
                                 locations: [0, 1]) else { return nil }
        ctx.drawLinearGradient(g, start: CGPoint(x: 0, y: size), end: CGPoint(x: 0, y: 0), options: [])
        return ctx.makeImage()
    }()

    private static let ciContext = CIContext(options: [.cacheIntermediates: false])

    private static func blurred(_ image: CGImage, radius: CGFloat) -> CGImage? {
        let input = CIImage(cgImage: image).clampedToExtent()
        let output = input.applyingGaussianBlur(sigma: radius).cropped(to: CIImage(cgImage: image).extent)
        return ciContext.createCGImage(output, from: output.extent)
    }
}
