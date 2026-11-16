import CoreGraphics

/// Where a stack's items go when it opens: Leopard's Fan (a curve rising from the tile, bending
/// right) and Grid (a panel of icons with names).
enum StackLayout {
    // MARK: Fan

    static let fanIcon: CGFloat = 48
    /// From one item's centre to the next, up the curve.
    static let fanStep: CGFloat = 54
    /// The lowest item's centre above the top of the tile.
    static let fanStart: CGFloat = 36
    /// Leopard showed at most this many items in a fan; the rest are a click away in Finder.
    static let fanMaximum = 15

    struct FanSlot: Equatable {
        /// The icon's centre, relative to the top centre of the tile (y up).
        var center: CGPoint
        /// Tilted gently along the curve (radians, clockwise negative).
        var rotation: CGFloat
    }

    /// How many items fit in a fan with `height` above the tile, including the "Open in Finder" row.
    static func fanCapacity(height: CGFloat) -> Int {
        max(1, min(fanMaximum, Int((height - fanStart - fanIcon / 2) / fanStep) + 1))
    }

    /// `count` slots, the first nearest the dock. The curve bends right as it rises, by about a fifth
    /// of its height at the top, and items tilt with it.
    static func fan(count: Int) -> [FanSlot] {
        guard count > 0 else { return [] }
        let height = fanStep * CGFloat(max(count - 1, 1))
        let bend = min(height * 0.2, 140)
        return (0..<count).map { i in
            let y = fanStart + fanStep * CGFloat(i)
            let t = (y - fanStart) / height
            let x = bend * t * t
            let slope = 2 * bend * t / height // dx/dy
            return FanSlot(center: CGPoint(x: x, y: y), rotation: -atan(slope) * 0.6)
        }
    }

    // MARK: Grid

    static let gridIcon: CGFloat = 64
    static let gridCell = CGSize(width: 96, height: 100)
    static let gridPadding: CGFloat = 16
    /// Room for the title row (and Open in Finder) at the top of the panel.
    static let gridHeader: CGFloat = 34
    /// Narrow enough for one item, wide enough for Back, the title and Open in Finder.
    static let gridMinimumWidth: CGFloat = 340

    /// Columns for `count` items: about square, a little wider than tall, and never wider than fits.
    static func gridColumns(count: Int, maxWidth: CGFloat) -> Int {
        let fit = max(1, Int((maxWidth - 2 * gridPadding) / gridCell.width))
        let square = Int(ceil(sqrt(Double(max(count, 1)) * 1.4)))
        return max(1, min(fit, min(square, max(count, 1)), 8))
    }

    /// The grid's content size (all rows, before any scrolling).
    static func gridSize(count: Int, columns: Int) -> CGSize {
        let rows = max(1, Int(ceil(Double(max(count, 1)) / Double(columns))))
        return CGSize(width: CGFloat(columns) * gridCell.width + 2 * gridPadding,
                      height: CGFloat(rows) * gridCell.height + 2 * gridPadding + gridHeader)
    }

    // MARK: Which view

    /// Automatic is a Fan when the items fit in one, and a Grid otherwise.
    static func resolve(_ view: StackView, count: Int, fanCapacity: Int) -> StackView {
        guard view == .automatic else { return view }
        return count <= fanCapacity - 1 ? .fan : .grid
    }
}

/// The dock's sections: Finder, kept apps and open apps, then the folders, then the Trash. An item
/// dragged along the dock stays in its own section.
enum DockSections {
    /// Where the dragged item goes among the others (the order without it and without the Trash),
    /// given the slot under the pointer. Counts are of the other items.
    /// - Parameters:
    ///   - keptApps: kept apps, Finder included (always first, so nothing goes before it).
    ///   - apps: all apps, kept and open; the folders follow them.
    ///   - stacks: folders.
    static func clamp(_ slot: Int, isStack: Bool, keptApps: Int, apps: Int, stacks: Int) -> Int {
        isStack ? min(max(slot, apps), apps + stacks) : min(max(slot, 1), keptApps)
    }
}
