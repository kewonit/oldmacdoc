import AppKit

/// A folder's tile. As a stack (Leopard's look), its first few items piled up with a slight twist, the
/// first on top; empty, or displayed as a folder, the folder's own icon.
enum StackArt {
    static let pixels = 256

    static func image(folder: URL, entries: [StackEntry], display: StackDisplay) -> CGImage? {
        let shown = display == .stack ? Array(entries.prefix(3)) : []
        guard !shown.isEmpty else {
            return IconEngine.cgImage(NSWorkspace.shared.icon(forFile: folder.path), size: pixels)
        }
        let side = CGFloat(pixels)
        guard let ctx = CGContext(data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: Bitmap.colorSpace, bitmapInfo: Bitmap.bitmapInfo) else { return nil }
        // Bottom of the pile first: each a little smaller, turned a few degrees, nudged up.
        let turns: [CGFloat] = [0, -7, 6]
        let nudges: [CGPoint] = [.zero, CGPoint(x: -6, y: 10), CGPoint(x: 7, y: 18)]
        for (i, entry) in shown.enumerated().reversed() {
            let icon = NSWorkspace.shared.icon(forFile: entry.url.path)
            guard let image = IconEngine.cgImage(icon, size: pixels) else { continue }
            let size = side * (0.98 - CGFloat(i) * 0.05)
            ctx.saveGState()
            ctx.translateBy(x: side / 2 + nudges[i].x, y: side / 2 + nudges[i].y - side * 0.04)
            ctx.rotate(by: turns[i] * .pi / 180)
            ctx.setShadow(offset: CGSize(width: 0, height: -3), blur: 8, color: CGColor(gray: 0, alpha: 0.35))
            ctx.draw(image, in: CGRect(x: -size / 2, y: -size / 2, width: size, height: size))
            ctx.restoreGState()
        }
        return ctx.makeImage()
    }

    /// The round arrow at the top of a Fan (Open in Finder), drawn in code.
    static func finderArrow(size: Int) -> CGImage? {
        let s = CGFloat(size)
        guard let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: Bitmap.colorSpace, bitmapInfo: Bitmap.bitmapInfo) else { return nil }
        let circle = CGRect(x: s * 0.08, y: s * 0.08, width: s * 0.84, height: s * 0.84)
        ctx.setShadow(offset: CGSize(width: 0, height: -s * 0.02), blur: s * 0.05, color: CGColor(gray: 0, alpha: 0.5))
        ctx.addEllipse(in: circle)
        let colors = [CGColor(gray: 0.45, alpha: 0.95), CGColor(gray: 0.15, alpha: 0.95)] as CFArray
        ctx.saveGState()
        ctx.clip()
        if let g = CGGradient(colorsSpace: Bitmap.colorSpace, colors: colors, locations: [0, 1]) {
            ctx.drawLinearGradient(g, start: CGPoint(x: 0, y: circle.maxY), end: CGPoint(x: 0, y: circle.minY), options: [])
        }
        ctx.restoreGState()
        ctx.setShadow(offset: .zero, blur: 0, color: nil)
        ctx.setStrokeColor(CGColor(gray: 1, alpha: 0.85))
        ctx.setLineWidth(s * 0.035)
        ctx.strokeEllipse(in: circle.insetBy(dx: s * 0.02, dy: s * 0.02))
        // The arrow, pointing up and right.
        ctx.setFillColor(CGColor(gray: 1, alpha: 1))
        ctx.translateBy(x: s / 2, y: s / 2)
        ctx.rotate(by: -.pi / 4) // clockwise: pointing up and to the right
        let w = s * 0.11, l = s * 0.42, head = s * 0.2
        ctx.fill(CGRect(x: -w / 2, y: -l / 2, width: w, height: l - head * 0.6))
        ctx.beginPath()
        ctx.move(to: CGPoint(x: -head * 0.75, y: l / 2 - head))
        ctx.addLine(to: CGPoint(x: head * 0.75, y: l / 2 - head))
        ctx.addLine(to: CGPoint(x: 0, y: l / 2 + head * 0.15))
        ctx.closePath()
        ctx.fillPath()
        return ctx.makeImage()
    }
}
