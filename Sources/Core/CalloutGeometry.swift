import CoreGraphics

/// The original Dock's menus, and Leopard's Grid stacks, hang above the icon with a pointer aimed at it:
/// a right-angled point 26 × 13 pt, centred on the icon, with the menu's left edge near the icon's
/// (so the pointer sits about 25 pt in). Measured from Siracusa's Leopard and Snow Leopard screenshots
/// and Apple's 2011–2013 guidelines (reports/Original Dock right click menus.md).
enum Callout {
    static let pointerWidth: CGFloat = 26
    static let pointerHeight: CGFloat = 13
    /// The pointer's axis from the menu's left edge, when nothing pushes the menu along.
    static let axisInset: CGFloat = 25
    /// Between the pointer's tip and the top of the icon.
    static let gap: CGFloat = 6
    /// Kept clear at the screen's edges.
    static let margin: CGFloat = 6

    enum Alignment { case leading, centered }

    struct Placement: Equatable {
        /// The body, without the pointer, in screen coordinates (y up).
        var body: CGRect
        /// The pointer's axis, in screen coordinates.
        var pointerX: CGFloat
        /// The whole window: the body plus the pointer below it.
        var frame: CGRect { CGRect(x: body.minX, y: body.minY - pointerHeight, width: body.width, height: body.height + pointerHeight) }
        /// True when the content didn't fit and has to scroll.
        var isClipped: Bool
    }

    /// Where a menu of `size` goes above an icon whose top centre is (`anchorX`, `anchorTop`).
    /// - Parameters:
    ///   - screen: the whole screen, which limits left and right.
    ///   - top: how high it may go (the bottom of the menu bar).
    static func place(size: CGSize, anchorX: CGFloat, anchorTop: CGFloat, screen: CGRect, top: CGFloat,
                      cornerRadius: CGFloat, alignment: Alignment = .leading) -> Placement {
        let width = min(size.width, screen.width - 2 * margin)
        var x = alignment == .leading ? anchorX - axisInset : anchorX - width / 2
        x = min(max(x, screen.minX + margin), screen.maxX - margin - width)
        let y = anchorTop + gap + pointerHeight
        let available = max(pointerHeight * 2, top - margin - y)
        let height = min(size.height, available)
        let body = CGRect(x: x, y: y, width: width, height: height)
        return Placement(body: body, pointerX: pointerX(anchorX, in: body, cornerRadius: cornerRadius),
                         isClipped: height < size.height)
    }

    /// The pointer stays over the icon, but never runs into the body's rounded corners.
    static func pointerX(_ anchorX: CGFloat, in body: CGRect, cornerRadius: CGFloat) -> CGFloat {
        let lo = body.minX + cornerRadius + pointerWidth / 2, hi = body.maxX - cornerRadius - pointerWidth / 2
        return lo > hi ? body.midX : min(max(anchorX, lo), hi)
    }

    /// A submenu beside the row it belongs to (`row`, screen coordinates): to the right, or to the left
    /// when there's no room, top-aligned with the row and kept on screen.
    static func submenu(size: CGSize, row: CGRect, parent: CGRect, screen: CGRect, top: CGFloat,
                        inset: CGFloat) -> (frame: CGRect, isClipped: Bool) {
        let overlap: CGFloat = 2
        var x = parent.maxX - overlap
        if x + size.width > screen.maxX - margin { x = parent.minX - size.width + overlap }
        x = min(max(x, screen.minX + margin), screen.maxX - margin - size.width)
        let height = min(size.height, top - margin - (screen.minY + margin))
        var y = row.maxY + inset - height
        y = min(max(y, screen.minY + margin), top - margin - height)
        return (CGRect(x: x, y: y, width: size.width, height: height), height < size.height)
    }

    /// The outline: a rounded body with the pointer hanging from its bottom edge at `pointerX`. In the
    /// window's own coordinates: the body starts `pointerHeight` up from the bottom.
    static func path(size: CGSize, pointerX px: CGFloat?, cornerRadius r: CGFloat) -> CGPath {
        let path = CGMutablePath()
        let ph = px == nil ? 0 : pointerHeight
        let body = CGRect(x: 0, y: ph, width: size.width, height: size.height - ph)
        path.move(to: CGPoint(x: body.minX + r, y: body.maxY))
        path.addArc(tangent1End: CGPoint(x: body.maxX, y: body.maxY), tangent2End: CGPoint(x: body.maxX, y: body.minY), radius: r)
        path.addArc(tangent1End: CGPoint(x: body.maxX, y: body.minY), tangent2End: CGPoint(x: body.minX, y: body.minY), radius: r)
        if let px {
            path.addLine(to: CGPoint(x: px + pointerWidth / 2, y: body.minY))
            path.addLine(to: CGPoint(x: px, y: 0))
            path.addLine(to: CGPoint(x: px - pointerWidth / 2, y: body.minY))
        }
        path.addArc(tangent1End: CGPoint(x: body.minX, y: body.minY), tangent2End: CGPoint(x: body.minX, y: body.maxY), radius: r)
        path.addArc(tangent1End: CGPoint(x: body.minX, y: body.maxY), tangent2End: CGPoint(x: body.maxX, y: body.maxY), radius: r)
        path.closeSubpath()
        return path
    }
}
