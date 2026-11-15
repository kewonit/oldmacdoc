import CoreGraphics
import Foundation

/// Trims padding and scales every icon to the same visual size, standing on the bottom edge.
enum IconNormalizer {
    static let targetFill: CGFloat = 0.88
    static let bottomMargin: CGFloat = 0.02

    struct Output {
        let image: CGImage
        /// Where the solid artwork landed, in CoreGraphics coordinates (origin bottom-left).
        let contentRect: CGRect
    }

    static func normalize(_ bitmap: Bitmap, outputSize: Int) -> Output? {
        // `full` keeps soft baked-in shadows; `solid` (what we size and stand on) ignores them,
        // so icons with drop shadows don't float above the shelf or shrink.
        guard let full = bitmap.opaqueBounds(threshold: 4), let source = bitmap.makeImage(),
              let cropped = source.cropping(to: CGRect(x: full.minX, y: full.minY, width: full.width, height: full.height))
        else { return nil }
        let solid = bitmap.opaqueBounds(threshold: 60) ?? full

        // Sparse shapes (circles, odd outlines) read smaller than squares of the same width.
        var covered = 0
        for y in solid.minY...solid.maxY {
            for x in solid.minX...solid.maxX where bitmap.alpha(x, y) > 127 { covered += 1 }
        }
        let sw = CGFloat(solid.width), sh = CGFloat(solid.height)
        let coverage = CGFloat(covered) / (sw * sh)
        let boost = min(1.08, max(1, pow(0.9 / max(coverage, 0.3), 0.25)))

        let out = CGFloat(outputSize)
        let longest = max(sw, sh)
        let scale = min(targetFill * out / longest * boost, 0.98 * out / longest)
        let target = CGRect(x: ((out - sw * scale) / 2).rounded(), y: (out * bottomMargin).rounded(),
                            width: sw * scale, height: sh * scale)

        // Map the full crop with the same transform. Bitmap rows run top-down, CG runs bottom-up.
        let h = CGFloat(bitmap.height)
        let solidBottom = h - CGFloat(solid.maxY + 1), fullBottom = h - CGFloat(full.maxY + 1)
        let drawRect = CGRect(x: target.minX + CGFloat(full.minX - solid.minX) * scale,
                              y: target.minY + (fullBottom - solidBottom) * scale,
                              width: CGFloat(full.width) * scale, height: CGFloat(full.height) * scale)

        guard let ctx = CGContext(data: nil, width: outputSize, height: outputSize, bitsPerComponent: 8,
                                  bytesPerRow: outputSize * 4, space: Bitmap.colorSpace,
                                  bitmapInfo: Bitmap.bitmapInfo) else { return nil }
        ctx.interpolationQuality = .high
        ctx.draw(cropped, in: drawRect)
        guard let image = ctx.makeImage() else { return nil }
        return Output(image: image, contentRect: target)
    }
}
