import Foundation

/// Finds the plate macOS 26+ puts behind non-conforming icons (a rounded square of
/// near-uniform gray with smaller artwork centred inside) and cuts it away.
/// Returns nil whenever it isn't confident, so callers fall back to the untouched icon.
enum PlateDetector {
    struct Options {
        /// How far an edge sample may be from the plate colour (0...1, per channel).
        var sampleTolerance: Float = 0.06
        /// Flood-fill tolerance for plate pixels.
        var fillTolerance: Float = 0.09
        /// Gray plates must sit in this luminance band. Kept conservative on purpose: on macOS 27,
        /// designed light squircles (Slack, Chrome, VS Code, Figma…) measure ~0.93–0.975, which is
        /// indistinguishable by colour from a light plate, so they must not match.
        var neutralLuminance: ClosedRange<Float> = 0.08...0.96
    }

    static func lift(_ src: Bitmap, options: Options = Options()) -> Bitmap? {
        let w = src.width
        guard let body = src.opaqueBounds(threshold: 128) else { return nil }
        let side = max(body.width, body.height)
        guard abs(body.width - body.height) <= max(2, side / 25), side >= w * 55 / 100 else { return nil }

        // Inner region: inside the rounded corners and the rim highlight.
        let inset = max(2, side * 6 / 100)
        let inner = PixelRect(minX: body.minX + inset, minY: body.minY + inset,
                              maxX: body.maxX - inset, maxY: body.maxY - inset)
        guard inner.width > 24 else { return nil }

        // Sample the middle 60% of each inner edge.
        var top: [SIMD4<Float>] = [], bottom: [SIMD4<Float>] = []
        var sides: [(SIMD4<Float>, Int)] = []
        let lo = inner.width / 5, hi = inner.width * 4 / 5
        for i in stride(from: lo, through: hi, by: 2) {
            top.append(src.color(inner.minX + i, inner.minY))
            bottom.append(src.color(inner.minX + i, inner.maxY))
            sides.append((src.color(inner.minX, inner.minY + i), inner.minY + i))
            sides.append((src.color(inner.maxX, inner.minY + i), inner.minY + i))
        }
        let all = top + bottom + sides.map(\.0)
        guard all.allSatisfy({ $0.w > 0.97 }) else { return nil }

        func mean(_ c: [SIMD4<Float>]) -> SIMD3<Float> { c.reduce(SIMD3<Float>(), { $0 + $1.rgb }) / Float(c.count) }
        let topMean = mean(top), bottomMean = mean(bottom)
        func plate(atY y: Int) -> SIMD3<Float> {
            let t = Float(y - inner.minY) / Float(max(1, inner.height - 1))
            return topMean + (bottomMean - topMean) * t
        }

        // The edge must be uniform (allowing a vertical gradient).
        var good = 0
        for c in top where colorDistance(c.rgb, topMean) < options.sampleTolerance { good += 1 }
        for c in bottom where colorDistance(c.rgb, bottomMean) < options.sampleTolerance { good += 1 }
        for (c, y) in sides where colorDistance(c.rgb, plate(atY: y)) < options.sampleTolerance { good += 1 }
        guard good * 100 >= all.count * 95 else { return nil }

        // A plate is a neutral gray; a deliberately coloured background is part of the design.
        for m in [topMean, bottomMean] {
            guard m.max() - m.min() < 0.05 else { return nil }
            let luma = 0.2126 * m.x + 0.7152 * m.y + 0.0722 * m.z
            guard options.neutralLuminance.contains(luma) else { return nil }
        }

        // Flood-fill the plate from the inner edge.
        var isPlate = [Bool](repeating: false, count: w * src.height)
        var stack: [Int] = []
        stack.reserveCapacity(inner.width * 8)
        @inline(__always) func matches(_ x: Int, _ y: Int) -> Bool {
            let c = src.color(x, y)
            return c.w > 0.02 && colorDistance(c.rgb, plate(atY: y)) < options.fillTolerance
        }
        @inline(__always) func push(_ x: Int, _ y: Int) {
            let i = y * w + x
            if !isPlate[i] && matches(x, y) { isPlate[i] = true; stack.append(i) }
        }
        for x in inner.minX...inner.maxX { push(x, inner.minY); push(x, inner.maxY) }
        for y in inner.minY...inner.maxY { push(inner.minX, y); push(inner.maxX, y) }
        while let i = stack.popLast() {
            let x = i % w, y = i / w
            if x > inner.minX { push(x - 1, y) }
            if x < inner.maxX { push(x + 1, y) }
            if y > inner.minY { push(x, y - 1) }
            if y < inner.maxY { push(x, y + 1) }
        }

        // Semi-transparent pixels in the rounded corners are the body's rim, not artwork.
        let corner = side * 18 / 100
        @inline(__always) func isRim(_ x: Int, _ y: Int) -> Bool {
            guard src.alpha(x, y) < 250 else { return false }
            return (x < inner.minX + corner || x > inner.maxX - corner) && (y < inner.minY + corner || y > inner.maxY - corner)
        }

        // Confidence checks: plenty of plate, real artwork, artwork clear of the edges and centred.
        var plateCount = 0, artCount = 0
        var art = PixelRect(minX: Int.max, minY: Int.max, maxX: -1, maxY: -1)
        for y in inner.minY...inner.maxY {
            for x in inner.minX...inner.maxX {
                if isPlate[y * w + x] { plateCount += 1; continue }
                guard src.alpha(x, y) > 8, !isRim(x, y) else { continue }
                artCount += 1
                art.minX = min(art.minX, x); art.maxX = max(art.maxX, x)
                art.minY = min(art.minY, y); art.maxY = max(art.maxY, y)
            }
        }
        let innerArea = inner.width * inner.height
        guard plateCount * 100 >= innerArea * 20, artCount * 100 >= innerArea * 3, art.maxX >= 0 else { return nil }
        guard art.minX > inner.minX + 1, art.maxX < inner.maxX - 1,
              art.minY > inner.minY + 1, art.maxY < inner.maxY - 1 else { return nil }
        let bodyCX = (body.minX + body.maxX) / 2, bodyCY = (body.minY + body.maxY) / 2
        guard abs((art.minX + art.maxX) / 2 - bodyCX) <= side / 10,
              abs((art.minY + art.maxY) / 2 - bodyCY) <= side / 10 else { return nil }

        // Copy the artwork; un-blend pixels on the boundary so no gray fringe is left.
        var out = Bitmap(width: w, height: src.height)
        for y in art.minY...art.maxY {
            for x in art.minX...art.maxX where !isPlate[y * w + x] && !isRim(x, y) {
                let c = src.color(x, y)
                guard c.w > 0 else { continue }
                var touches = false
                for dy in -1...1 { for dx in -1...1 where isPlate[(y + dy) * w + (x + dx)] { touches = true } }
                if touches {
                    let p = plate(atY: y)
                    let a = min(1, colorDistance(c.rgb, p) / 0.35)
                    guard a > 0.03 else { continue }
                    out.set(x, y, rgb: (c.rgb - (1 - a) * p) / a, alpha: a * c.w)
                } else {
                    out.set(x, y, rgb: c.rgb, alpha: c.w)
                }
            }
        }
        return out
    }
}
