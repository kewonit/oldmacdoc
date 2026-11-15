import CoreGraphics

/// Where the settings panel opens, in screen coordinates (y up), like Control Center: just under its
/// menu bar item, left edges aligned, kept on screen. When the item can't be seen (a full menu bar, or
/// behind the camera housing), it opens at the top right of the screen instead, under the menu bar.
enum PanelPlacement {
    static let gapBelowItem: CGFloat = 5
    static let screenMargin: CGFloat = 8
    static let fallbackRightMargin: CGFloat = 10
    static let fallbackGapBelowMenuBar: CGFloat = 6

    /// - Parameters:
    ///   - item: the menu bar item's frame on screen, or nil when it isn't visible.
    ///   - screen: the screen's whole frame.
    ///   - visible: the screen's visible frame (below the menu bar, above Apple's Dock).
    ///   - menuBarHeight: the menu bar's height on that screen (taller with a camera housing).
    static func frame(size: CGSize, item: CGRect?, screen: CGRect, visible: CGRect, menuBarHeight: CGFloat) -> CGRect {
        let top: CGFloat, left: CGFloat
        if let item {
            top = item.minY - gapBelowItem
            left = item.minX
        } else {
            top = min(visible.maxY, screen.maxY - menuBarHeight) - fallbackGapBelowMenuBar
            left = screen.maxX - fallbackRightMargin - size.width
        }
        let x = min(max(left, screen.minX + screenMargin), screen.maxX - screenMargin - size.width)
        let y = max(top - size.height, visible.minY + screenMargin)
        return CGRect(x: x.rounded(), y: y.rounded(), width: size.width, height: size.height)
    }
}
