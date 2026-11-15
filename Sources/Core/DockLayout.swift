import CoreGraphics
import Foundation

/// Horizontal layout of the icon row, with the Dock's magnification.
///
/// Magnification follows Apple's Dock patent (US 7,434,177): every tile edge at distance `d` from
/// the pointer moves outward by `S · sin(π/2 · clamp(d, −W, W) / W)`. A tile's new width is the
/// distance between its moved edges, so the tile under the pointer grows to exactly the magnified
/// size, the point under the pointer never moves, the row grows evenly on both sides, and the
/// scale falls off as a quarter-wave cosine over the effect width `W`.
struct RowLayout: Equatable {
    struct Slot: Equatable {
        var center: CGFloat
        var size: CGFloat
        var minX: CGFloat { center - size / 2 }
        var maxX: CGFloat { center + size / 2 }
    }

    var slots: [Slot]

    /// - Parameters:
    ///   - baseSize: resting icon size `h`; each tile is `h + spacing` wide with the icon centred in it.
    ///   - gapBefore: index that gets an extra `gap` in front of it (the separator before the Trash).
    ///   - pointerX: pointer position in the same space as `centerX`, or nil when the pointer is away.
    ///   - maxScale: magnified size / resting size (`H / h`).
    ///   - effectWidth: `W`, how far from the pointer magnification reaches.
    ///   - weights: how much of its place each tile takes, 0...1 (default 1). Tiles arriving grow from
    ///     0 and tiles leaving shrink to 0, so their neighbours slide aside and back as on the original.
    static func make(count: Int, baseSize h: CGFloat, spacing: CGFloat, gapBefore: Int?, gap: CGFloat,
                     centerX: CGFloat, pointerX: CGFloat?, maxScale: CGFloat, effectWidth w: CGFloat,
                     weights: [CGFloat]? = nil) -> RowLayout {
        guard count > 0, h > 0 else { return RowLayout(slots: []) }
        let tile = h + spacing
        let widths = (0..<count).map { i in tile * min(max(weights.map { i < $0.count ? $0[i] : 1 } ?? 1, 0), 1) }
        let rowWidth = widths.reduce(0, +) + (gapBefore.map { (1..<count).contains($0) ? gap : 0 } ?? 0)

        // Resting tile edges, row centred on centerX.
        var lefts: [CGFloat] = []
        var x = centerX - rowWidth / 2
        for i in 0..<count {
            if i == gapBefore, i > 0 { x += gap }
            lefts.append(x)
            x += widths[i]
        }

        let width = max(w, tile / 2 + 1)
        guard let p = pointerX, maxScale > 1.001 else {
            return RowLayout(slots: zip(lefts, widths).map { Slot(center: $0 + $1 / 2, size: h * $1 / tile) })
        }

        // S makes a tile centred on the pointer exactly maxScale times larger.
        let s = tile * (maxScale - 1) / 2 / sin(.pi * tile / (4 * width))
        func moved(_ edge: CGFloat) -> CGFloat {
            let d = min(max(edge - p, -width), width)
            return edge + s * sin(.pi / 2 * d / width)
        }
        return RowLayout(slots: zip(lefts, widths).map { left, tileWidth in
            let l = moved(left), r = moved(left + tileWidth)
            return Slot(center: (l + r) / 2, size: h * (r - l) / tile)
        })
    }
}

/// The glass floor as the original Dock drew it: a flat texture mapped into a trapezoid. The back
/// edge runs just past the outer tiles; each front corner sticks out by a fixed overhang (the formula
/// dockify recovered from the 10.5–10.9 Dock), so the ends keep the same slant however wide the dock is.
/// Coordinates are y-up from the bottom of the screen.
struct ShelfGeometry: Equatable {
    /// Height of the opaque front face below the floor (Mountain Lion); 0 for Leopard.
    var lip: CGFloat
    /// Height of the back edge above the bottom of the screen.
    var top: CGFloat
    var backLeft: CGFloat
    var backRight: CGFloat

    /// How far each front corner sticks out past the back corner for a floor `height` points tall.
    static func overhang(height: CGFloat) -> CGFloat { max(0, 12 + ceil((height - 17) / 2)) }

    var overhang: CGFloat { Self.overhang(height: top - lip) }
    var frontLeft: CGFloat { backLeft - overhang }
    var frontRight: CGFloat { backRight + overhang }

    /// Left and right edges of the floor at height `y`.
    func edges(at y: CGFloat) -> (left: CGFloat, right: CGFloat) {
        let t = min(max((y - lip) / max(top - lip, 1), 0), 1)
        return (frontLeft + (backLeft - frontLeft) * t, frontRight + (backRight - frontRight) * t)
    }

    /// Follows a point at `x` (measured at height `from`) into the floor's perspective at height `to`,
    /// keeping its relative position between the edges, so lines on the floor recede like the texture.
    func perspectiveX(_ x: CGFloat, from: CGFloat, to: CGFloat) -> CGFloat {
        let a = edges(at: from), b = edges(at: to)
        let u = (x - a.left) / max(a.right - a.left, 1)
        return b.left + u * (b.right - b.left)
    }

    /// The whole shelf outline: the lip (if any) plus the floor, with slightly rounded corners.
    func outline(backRadius: CGFloat = 3, lipRadius: CGFloat = 2) -> CGPath {
        let path = CGMutablePath()
        let points: [(CGPoint, CGFloat)] = lip > 0
            ? [(CGPoint(x: frontLeft, y: 0), lipRadius), (CGPoint(x: frontRight, y: 0), lipRadius),
               (CGPoint(x: frontRight, y: lip), 0), (CGPoint(x: backRight, y: top), backRadius),
               (CGPoint(x: backLeft, y: top), backRadius), (CGPoint(x: frontLeft, y: lip), 0)]
            : [(CGPoint(x: frontLeft, y: 0), 0), (CGPoint(x: frontRight, y: 0), 0),
               (CGPoint(x: backRight, y: top), backRadius), (CGPoint(x: backLeft, y: top), backRadius)]
        let start = CGPoint(x: (points[0].0.x + points[1].0.x) / 2, y: points[0].0.y)
        path.move(to: start)
        for i in 1...points.count {
            let (corner, radius) = points[i % points.count]
            let next = points[(i + 1) % points.count].0
            if radius > 0 { path.addArc(tangent1End: corner, tangent2End: next, radius: radius) } else { path.addLine(to: corner) }
        }
        path.closeSubpath()
        return path
    }
}
