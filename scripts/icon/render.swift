// Renders OldMacDoc's app icon into Resources/Assets.xcassets/AppIcon.appiconset: a close-up of the
// Clear Glass (Leopard) shelf, drawn with the dock's own art (ShelfArt), on graphite. No Apple
// artwork is used.
//
// Run with `make icon`, which compiles this file together with the shelf drawing code:
//   Sources/App/{ShelfArt,ShelfLook}.swift, Sources/Core/{DockLayout,Bitmap,Support}.swift
import AppKit

let canvas = 1024
// Apple's macOS icon grid: an 824 px rounded square, centred, with room for its shadow.
let body = CGRect(x: 100, y: 100, width: 824, height: 824)
let corner: CGFloat = 185
let space = Bitmap.colorSpace

func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: r / 255, green: g / 255, blue: b / 255, alpha: a)
}

func gradient(_ colors: [CGColor], _ locations: [CGFloat]? = nil) -> CGGradient {
    CGGradient(colorsSpace: space, colors: colors as CFArray, locations: locations)!
}

func context(_ side: Int) -> CGContext {
    let ctx = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side * 4,
                        space: space, bitmapInfo: Bitmap.bitmapInfo)!
    ctx.interpolationQuality = .high
    return ctx
}

/// The right end of the Clear Glass shelf, close up: the two-tone floor with its dark seam and bright
/// front line, its slanted end and the striped separator, on graphite lit from behind the glass.
func drawShelf(in ctx: CGContext) {
    ctx.drawLinearGradient(gradient([rgb(8, 9, 12), rgb(30, 33, 39), rgb(14, 15, 19)], [0, 0.62, 1]),
                           start: CGPoint(x: 0, y: body.maxY), end: CGPoint(x: 0, y: body.minY),
                           options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
    let horizon = CGPoint(x: body.midX - 100, y: body.minY + body.height * 0.5)
    ctx.saveGState()
    ctx.translateBy(x: horizon.x, y: horizon.y)
    ctx.scaleBy(x: 1, y: 0.42)
    ctx.drawRadialGradient(gradient([rgb(120, 132, 160, 0.55), rgb(70, 78, 98, 0.22), rgb(40, 44, 54, 0)], [0, 0.45, 1]),
                           startCenter: .zero, startRadius: 0, endCenter: .zero, endRadius: body.width * 0.62, options: [])
    ctx.restoreGState()

    let look = ShelfLook(style: .clear)
    let s: CGFloat = 525                     // the icon size this shelf is drawn for
    let top = (look.floorHeight * s).rounded()
    let front = look.lipHeight(s) + look.lineHeight(s)
    let backWidth: CGFloat = 822
    let backLeft = body.midX - backWidth / 2 - 330
    let base = body.minY + 122
    let shelf = ShelfGeometry(lip: 0, top: top, backLeft: backLeft, backRight: backLeft + backWidth)

    ctx.saveGState()
    ctx.translateBy(x: 0, y: base)
    // A soft glow on the "ground" under the front edge, where the glass catches the light.
    ctx.saveGState()
    ctx.translateBy(x: (shelf.frontLeft + shelf.frontRight) / 2, y: -6)
    ctx.scaleBy(x: 1, y: 0.06)
    ctx.drawRadialGradient(gradient([CGColor(gray: 1, alpha: 0.28), CGColor(gray: 1, alpha: 0)]),
                           startCenter: .zero, startRadius: 0, endCenter: .zero,
                           endRadius: (shelf.frontRight - shelf.frontLeft) * 0.55, options: [])
    ctx.restoreGState()
    // The floor, then a faint diagonal sheen across the glass.
    ShelfArt.drawFloor(shelf, look: look, size: s, in: ctx)
    ctx.saveGState()
    ctx.addPath(shelf.outline())
    ctx.clip()
    ctx.drawLinearGradient(gradient([CGColor(gray: 1, alpha: 0), CGColor(gray: 1, alpha: 0.16), CGColor(gray: 1, alpha: 0)], [0.25, 0.5, 0.75]),
                           start: CGPoint(x: shelf.frontLeft, y: 0), end: CGPoint(x: shelf.frontRight, y: top), options: [])
    ctx.restoreGState()
    // The separator, where the apps end and the Trash's place begins.
    if let zebra = ShelfArt.zebra(size: s, top: top, front: front, scale: 1) {
        let x = backLeft + backWidth * 0.74
        ctx.draw(zebra.image, in: CGRect(x: (x - zebra.size.width / 2).rounded(), y: top - zebra.size.height,
                                         width: zebra.size.width, height: zebra.size.height))
    }
    ctx.restoreGState()
}

func render() -> CGImage {
    let ctx = context(canvas)
    let shape = CGPath(roundedRect: body, cornerWidth: corner, cornerHeight: corner, transform: nil)
    // A soft shadow under the square, as macOS icons have.
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: CGColor(gray: 0, alpha: 0.4))
    ctx.addPath(shape)
    ctx.setFillColor(CGColor(gray: 0.05, alpha: 1))
    ctx.fillPath()
    ctx.restoreGState()

    ctx.saveGState()
    ctx.addPath(shape)
    ctx.clip()
    drawShelf(in: ctx)
    ctx.restoreGState()

    // A hairline rim, so the square holds its edge on dark backgrounds.
    ctx.addPath(shape)
    ctx.setStrokeColor(CGColor(gray: 1, alpha: 0.14))
    ctx.setLineWidth(2)
    ctx.strokePath()
    return ctx.makeImage()!
}

func resized(_ image: CGImage, to side: Int) -> CGImage {
    let ctx = context(side)
    ctx.draw(image, in: CGRect(x: 0, y: 0, width: side, height: side))
    return ctx.makeImage()!
}

func writePNG(_ image: CGImage, to url: URL) throws {
    guard let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else {
        throw CocoaError(.fileWriteUnknown)
    }
    try data.write(to: url)
}

@main
enum RenderIcon {
    static func main() throws {
        let root = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "Resources/Assets.xcassets")
        let set = root.appendingPathComponent("AppIcon.appiconset")
        try FileManager.default.createDirectory(at: set, withIntermediateDirectories: true)
        let master = render()
        var images: [[String: String]] = []
        for points in [16, 32, 128, 256, 512] {
            for scale in [1, 2] {
                let name = scale == 1 ? "icon_\(points)x\(points).png" : "icon_\(points)x\(points)@2x.png"
                try writePNG(points * scale == canvas ? master : resized(master, to: points * scale), to: set.appendingPathComponent(name))
                images.append(["size": "\(points)x\(points)", "idiom": "mac", "filename": name, "scale": "\(scale)x"])
            }
        }
        let info = ["version": 1, "author": "xcode"] as [String: Any]
        try JSONSerialization.data(withJSONObject: ["images": images, "info": info], options: [.prettyPrinted, .sortedKeys])
            .write(to: set.appendingPathComponent("Contents.json"))
        try JSONSerialization.data(withJSONObject: ["info": info], options: [.prettyPrinted, .sortedKeys])
            .write(to: root.appendingPathComponent("Contents.json"))
        print("Wrote \(set.path)")
    }
}
