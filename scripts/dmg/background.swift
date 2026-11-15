// Renders the window of OldMacDoc's disk image (scripts/dmg/background.png and background@2x.png):
// the app and the Applications folder standing on the Clear Glass shelf, the striped separator
// between them as in the real Dock, a dotted arrow from one to the other, and a line of the song.
// Finder draws the two icons and their names on top; this draws everything else. No Apple artwork.
//
// Run with `make dmg-background`, which compiles this file together with the shelf drawing code:
//   Sources/App/{ShelfArt,ShelfLook}.swift, Sources/Core/{DockLayout,Bitmap,Support}.swift
// The window size and icon positions must match scripts/dmg/settings.py.
import AppKit

/// The window's content, in points from its top left, as Finder lays it out (settings.py). The picture
/// runs 20 pt below the 420 pt Finder shows under a 32 pt title bar, for macOS 14 and 15's 28 pt one.
enum Layout {
    static let size = CGSize(width: 640, height: 440)
    static let icon: CGFloat = 128
    static let iconY: CGFloat = 236 // the icons' centres
    static let appX: CGFloat = 180
    static let applicationsX: CGFloat = 460
}

let space = Bitmap.colorSpace

func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: r / 255, green: g / 255, blue: b / 255, alpha: a)
}

func gradient(_ colors: [CGColor], _ locations: [CGFloat]) -> CGGradient {
    CGGradient(colorsSpace: space, colors: colors as CFArray, locations: locations)!
}

/// A soft elliptical glow centred at `center`, `radius` wide and `squash` as tall.
func glow(_ ctx: CGContext, at center: CGPoint, radius: CGFloat, squash: CGFloat, colors: [CGColor], locations: [CGFloat]) {
    ctx.saveGState()
    ctx.translateBy(x: center.x, y: center.y)
    ctx.scaleBy(x: 1, y: squash)
    ctx.drawRadialGradient(gradient(colors, locations), startCenter: .zero, startRadius: 0,
                           endCenter: .zero, endRadius: radius, options: [])
    ctx.restoreGState()
}

/// Text centred across the window, its top `top` points from the window's top.
func text(_ ctx: CGContext, _ string: String, top: CGFloat, font: NSFont, color: NSColor, kern: CGFloat = 0) {
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
    let line = NSAttributedString(string: string, attributes: [.font: font, .foregroundColor: color, .kern: kern])
    let size = line.size()
    line.draw(at: CGPoint(x: ((Layout.size.width - size.width) / 2).rounded(), y: Layout.size.height - top - size.height))
    NSGraphicsContext.restoreGraphicsState()
}

/// The arrow from the app to Applications, as one drawn shape: a stroke that swells from a fine point
/// along a cubic curve (`start`, `c1`, `c2`, `tip`) into a swept-back head, fading in toward the
/// tip, on a soft shadow so it sits in the scene rather than on it.
func arrow(_ ctx: CGContext, start: CGPoint, c1: CGPoint, c2: CGPoint, tip: CGPoint) {
    func point(_ t: CGFloat) -> CGPoint {
        let u = 1 - t
        let a = u * u * u, b = 3 * u * u * t, c = 3 * u * t * t, d = t * t * t
        return CGPoint(x: a * start.x + b * c1.x + c * c2.x + d * tip.x, y: a * start.y + b * c1.y + c * c2.y + d * tip.y)
    }
    func unit(_ v: CGPoint) -> CGPoint { let l = max(hypot(v.x, v.y), 0.0001); return CGPoint(x: v.x / l, y: v.y / l) }

    // The shaft stops where the head begins: find that point by walking back along the curve.
    let headLength: CGFloat = 17, headHalfWidth: CGFloat = 8.5, sweep: CGFloat = 4.5
    var end: CGFloat = 1
    while end > 0, hypot(point(end).x - tip.x, point(end).y - tip.y) < headLength { end -= 0.002 }
    let base = point(end)
    let along = unit(CGPoint(x: tip.x - base.x, y: tip.y - base.y))
    let across = CGPoint(x: -along.y, y: along.x)

    // Both edges of the shaft, its width easing from a hairline to full just before the head.
    let steps = 64
    var left: [CGPoint] = [], right: [CGPoint] = []
    for i in 0...steps {
        let t = end * CGFloat(i) / CGFloat(steps)
        let p = point(t)
        let q = point(min(t + 0.001, 1)), o = point(max(t - 0.001, 0))
        let d = unit(CGPoint(x: q.x - o.x, y: q.y - o.y))
        let n = CGPoint(x: -d.y, y: d.x)
        let f = CGFloat(i) / CGFloat(steps)
        let half = (0.6 + 2.4 * (1 - pow(1 - f, 2))) // 1.2 pt wide at the start, 6 pt at the head
        left.append(CGPoint(x: p.x + n.x * half, y: p.y + n.y * half))
        right.append(CGPoint(x: p.x - n.x * half, y: p.y - n.y * half))
    }
    let shape = CGMutablePath()
    shape.addLines(between: left)
    shape.addLine(to: CGPoint(x: base.x + across.x * headHalfWidth - along.x * sweep,
                              y: base.y + across.y * headHalfWidth - along.y * sweep))
    shape.addLine(to: tip)
    shape.addLine(to: CGPoint(x: base.x - across.x * headHalfWidth - along.x * sweep,
                              y: base.y - across.y * headHalfWidth - along.y * sweep))
    for p in right.reversed() { shape.addLine(to: p) } // (addLines would start a new outline)
    shape.closeSubpath()
    // A round end at the fine start.
    shape.addEllipse(in: CGRect(x: start.x - 0.6, y: start.y - 0.6, width: 1.2, height: 1.2))

    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -1.5), blur: 5, color: CGColor(gray: 0, alpha: 0.45))
    ctx.beginTransparencyLayer(auxiliaryInfo: nil)
    ctx.addPath(shape)
    ctx.clip()
    ctx.drawLinearGradient(gradient([CGColor(gray: 1, alpha: 0.28), CGColor(gray: 1, alpha: 0.92)], [0, 0.75]),
                           start: start, end: tip, options: [.drawsAfterEndLocation])
    ctx.endTransparencyLayer()
    ctx.restoreGState()
}

func render(scale: CGFloat) -> CGImage {
    let W = Layout.size.width, H = Layout.size.height
    let ctx = CGContext(data: nil, width: Int(W * scale), height: Int(H * scale), bitsPerComponent: 8,
                        bytesPerRow: Int(W * scale) * 4, space: space, bitmapInfo: Bitmap.bitmapInfo)!
    ctx.interpolationQuality = .high
    ctx.scaleBy(x: scale, y: scale)
    func y(_ top: CGFloat) -> CGFloat { H - top } // window coordinates (from the top) to CoreGraphics'

    // Graphite, lit from behind the glass, as in the app icon.
    ctx.drawLinearGradient(gradient([rgb(16, 17, 21), rgb(36, 39, 46), rgb(13, 14, 17)], [0, 0.6, 1]),
                           start: CGPoint(x: 0, y: H), end: .zero, options: [])
    glow(ctx, at: CGPoint(x: W / 2, y: y(Layout.iconY)), radius: W * 0.62, squash: 0.42,
         colors: [rgb(120, 132, 160, 0.5), rgb(70, 78, 98, 0.2), rgb(40, 44, 54, 0)], locations: [0, 0.45, 1])

    // The shelf, sized like the Dock's for two 128 pt icons, the icons standing where Finder puts them.
    let look = ShelfLook(style: .clear)
    let s = Layout.icon
    let top = (look.floorHeight * s).rounded()
    let front = look.lipHeight(s) + look.lineHeight(s)
    let standY = y(Layout.iconY + s / 2)
    let base = standY - (look.iconBase * s).rounded()
    let pad = max(1, (s * 0.06).rounded()) / 2 + look.backPad * s
    let shelf = ShelfGeometry(lip: look.lipHeight(s), top: top,
                              backLeft: Layout.appX - s / 2 - pad, backRight: Layout.applicationsX + s / 2 + pad)
    ctx.saveGState()
    ctx.translateBy(x: 0, y: base)
    // The glass catching the light on the "ground" under its front edge.
    glow(ctx, at: CGPoint(x: W / 2, y: -3), radius: (shelf.frontRight - shelf.frontLeft) * 0.55, squash: 0.06,
         colors: [CGColor(gray: 1, alpha: 0.24), CGColor(gray: 1, alpha: 0)], locations: [0, 1])
    ShelfArt.drawFloor(shelf, look: look, size: s, in: ctx)
    // The separator: the app on the apps' side, Applications where folders and the Trash go.
    if let zebra = ShelfArt.zebra(size: s, top: top, front: front, scale: scale) {
        ctx.draw(zebra.image, in: CGRect(x: (W / 2 - zebra.size.width / 2).rounded(), y: top - zebra.size.height,
                                         width: zebra.size.width, height: zebra.size.height))
    }
    ctx.restoreGState()

    // From just off the app's top corner, up over the separator and down onto the folder.
    arrow(ctx, start: CGPoint(x: Layout.appX + 70, y: y(Layout.iconY - 40)),
          c1: CGPoint(x: Layout.appX + 100, y: y(Layout.iconY - 96)),
          c2: CGPoint(x: Layout.applicationsX - 104, y: y(Layout.iconY - 104)),
          tip: CGPoint(x: Layout.applicationsX - 72, y: y(Layout.iconY - 46)))

    text(ctx, "Drag OldMacDoc to Applications", top: 46,
         font: .systemFont(ofSize: 22, weight: .semibold), color: NSColor(white: 1, alpha: 0.94), kern: -0.3)
    text(ctx, "♪  and on his Mac he had a Dock, E-I-E-I-O", top: 82,
         font: .systemFont(ofSize: 14, weight: .regular), color: NSColor(white: 1, alpha: 0.55))
    return ctx.makeImage()!
}

func writePNG(_ image: CGImage, to path: String) throws {
    let rep = NSBitmapImageRep(cgImage: image)
    rep.size = Layout.size // 72 dpi at 1x, 144 at 2x, so Finder shows both at the window's size
    guard let data = rep.representation(using: .png, properties: [:]) else { throw CocoaError(.fileWriteUnknown) }
    try data.write(to: URL(fileURLWithPath: path))
}

@main
enum RenderBackground {
    static func main() throws {
        let folder = CommandLine.arguments.dropFirst().first ?? "scripts/dmg"
        try writePNG(render(scale: 1), to: "\(folder)/background.png")
        try writePNG(render(scale: 2), to: "\(folder)/background@2x.png")
        print("Wrote \(folder)/background.png and background@2x.png")
    }
}
