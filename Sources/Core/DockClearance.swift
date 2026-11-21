import CoreGraphics

/// Keeps maximised and tiled windows clear of the dock while it doesn't hide, as Apple's Dock does.
///
/// Apple's Dock is parked with auto-hide on (see AppleDockManager), so macOS thinks the bottom of the screen
/// is free: zoom, Fill and tiling size windows to `NSScreen.visibleFrame`, which only Apple's Dock and the
/// menu bar shrink, and no API lets another app take space from it. So once macOS has maximised or tiled a
/// window, it's shortened to end above the dock, through Accessibility (as uBar, ExtraDock and Docky do).
/// These are the rules; DockClearanceController watches the windows and applies them.
///
/// All rects are in Accessibility coordinates: the origin is the top left of the main display and y points
/// down, so `maxY` is a window's bottom edge and a display above the main one has a negative y.
enum DockClearance {
    /// Slack when comparing edges, in points: apps round their frames (Terminal to whole lines of text).
    static let slack: CGFloat = 2
    /// The largest gap a tiled window keeps from the screen's edges ("Tiled windows have margins").
    static let maximumMargin: CGFloat = 24
    /// A window is never made shorter than this; one that would be is left as it is.
    static let minimumHeight: CGFloat = 100

    struct Geometry: Equatable {
        /// The main display, where the dock is.
        var display: CGRect
        /// Its visible frame: below the menu bar, and down to the bottom of the screen (Apple's Dock hides).
        var visible: CGRect
        /// The dock's resting top. The band below it, across the whole display as with Apple's Dock, is the
        /// dock's: maximised and tiled windows end above it.
        var bandTop: CGFloat
    }

    struct Window: Equatable {
        var frame: CGRect
        var isStandard = true
        var isMinimized = false
        /// On a display with a notch, a full-screen window has exactly the frame of a filled one: only the
        /// window can say which it is (`AXFullScreen`).
        var isFullScreen = false
        var isResizable = true
    }

    /// A window that was shortened: where it was before macOS maximised it (when known), the frame macOS
    /// gave it, and the frame it was given instead.
    struct Record: Equatable {
        var before: CGRect?
        var full: CGRect
        var set: CGRect
    }

    /// The window's frame, the pointer and the left button while a window moved or resized.
    struct Sample: Equatable {
        var frame: CGRect
        var pointer: CGPoint
        var buttonDown: Bool
    }

    enum Action: Equatable {
        case leave
        /// Shorten it to this frame: it ends above the dock.
        case shrink(CGRect)
        /// Put it back where it was before it was maximised (the user un-zoomed it).
        case restore(CGRect)
    }

    /// What to do with a window whose frame has settled. `previous` is its last settled frame (nil when it's
    /// new, or when everything is looked at again), `record` what was done to it last. `putBack` is true when
    /// it was given its full frame again straight after being shortened: macOS keeps a tiled window's frame
    /// for a moment after placing it, so that's macOS insisting, not the user un-zooming.
    static func action(_ w: Window, previous: CGRect?, record: Record?, edgeDrag: Bool, putBack: Bool = false,
                       in g: Geometry) -> Action {
        guard w.isStandard, !w.isMinimized, !w.isFullScreen, w.isResizable else { return .leave }
        let f = w.frame
        guard g.display.contains(CGPoint(x: f.midX, y: f.midY)) else { return .leave }
        // Covering the whole display while the menu bar takes room: full screen without saying so. With the
        // menu bar hidden, that's also what Fill gives, so only `isFullScreen` can tell then.
        if same(f, g.display), !same(g.visible, g.display) { return .leave }
        // Resized by hand, even onto the frame macOS gave it (the pointer stops at the screen's edge).
        if edgeDrag { return .leave }
        if let previous {
            // A shortened window no longer looks maximised to AppKit, so zooming it again only fills the
            // screen again: that's the user un-zooming it, so it goes back where it was.
            if !putBack, let record, let before = record.before, same(previous, record.set), same(f, record.full) {
                return .restore(before)
            }
            // Moved, not resized: a window someone drags is never resized. One arriving from another
            // display (Move to, at the same size) is looked at as it lands.
            if sameSize(previous, f), g.display.contains(CGPoint(x: previous.midX, y: previous.midY)) { return .leave }
        }
        guard let target = cleared(f, in: g, known: record != nil) else { return .leave }
        return .shrink(target)
    }

    /// The frame that ends above the dock for a window macOS maximised or tiled into the band, keeping its
    /// top, left and width; nil for any other window. `known` is true for a window that was shortened before.
    static func cleared(_ f: CGRect, in g: Geometry, known: Bool = false) -> CGRect? {
        // It ends in the band: below the dock's top, and not past the bottom of the screen.
        guard f.maxY > g.bandTop + slack, f.maxY <= g.display.maxY + slack else { return nil }
        guard let margin = margin(f, in: g, known: known) else { return nil }
        let height = (g.bandTop - margin - f.minY).rounded(.down)
        guard height >= minimumHeight else { return nil }
        return CGRect(x: f.minX, y: f.minY, width: f.width, height: height)
    }

    /// The gap a maximised or tiled window keeps from the edges of the visible frame: 0 for zoom and for
    /// Fill and tiles without margins, the tile margin with them. Nil when the window isn't placed the way
    /// macOS places those: against the top, left or right of the visible frame as well as the bottom.
    static func margin(_ f: CGRect, in g: Geometry, known: Bool = false) -> CGFloat? {
        let v = g.visible
        let top = f.minY - v.minY
        let sides = [top, f.minX - v.minX, v.maxX - f.maxX]
        let bottom = v.maxY - f.maxY
        func near(_ gap: CGFloat) -> Bool { gap >= -slack && gap <= maximumMargin }
        if near(bottom) {
            // Down to the bottom of the screen: another side keeps the same gap.
            let m = max(0, bottom)
            return sides.contains { abs($0 - m) <= slack } ? m : nil
        }
        // Ending higher up: a window shortened before (the dock grew since), against a side as it was then;
        // or one that runs from the top (zoomed while a shorter dock showed). A window that only touches a
        // side and ends a little above the bottom of the screen was put there by hand.
        if known { return sides.filter(near).min().map { max(0, $0) } }
        return near(top) ? max(0, top) : nil
    }

    /// The record after a window was shortened from `full` to `set`. One that was already shortened, and is
    /// shortened again (the dock grew, or macOS gave it its full frame back straight away), keeps where it
    /// was before and the frame macOS gave it, so un-zooming still works.
    static func record(full: CGRect, previous: CGRect?, old: Record?, set: CGRect) -> Record {
        if let old, same(full, old.set) || same(full, old.full) { return Record(before: old.before, full: old.full, set: set) }
        return Record(before: previous.flatMap { same($0, full) ? nil : $0 }, full: full, set: set)
    }

    /// Whether the window was being resized by hand: the button held near one of its edges (or just
    /// outside it, where the resize cursor shows). Near the top edge only within a few points, so a
    /// double-click on the title bar still counts as a zoom.
    static func isEdgeDrag(_ samples: [Sample]) -> Bool {
        samples.contains { s in
            guard s.buttonDown else { return false }
            let f = s.frame, p = s.pointer
            guard f.insetBy(dx: -6, dy: -6).contains(p) else { return false }
            return p.x < f.minX + 8 || p.x > f.maxX - 8 || p.y > f.maxY - 8 || p.y < f.minY + 4
        }
    }

    /// The geometry for the main display's frame and visible frame in screen coordinates (origin at the
    /// bottom left, y up), with the dock's resting top in points above the display's bottom.
    static func geometry(display: CGRect, visible: CGRect, restingTop: CGFloat, primaryMaxY: CGFloat) -> Geometry {
        let d = axRect(display, primaryMaxY: primaryMaxY)
        return Geometry(display: d, visible: axRect(visible, primaryMaxY: primaryMaxY), bandTop: d.maxY - restingTop)
    }

    /// A rect in screen coordinates as Accessibility has it. `primaryMaxY` is the top of the main display
    /// (`NSScreen.screens[0]`) in screen coordinates.
    static func axRect(_ r: CGRect, primaryMaxY: CGFloat) -> CGRect {
        CGRect(x: r.minX, y: primaryMaxY - r.maxY, width: r.width, height: r.height)
    }

    static func same(_ a: CGRect, _ b: CGRect) -> Bool {
        abs(a.minX - b.minX) <= slack && abs(a.minY - b.minY) <= slack && sameSize(a, b)
    }

    static func sameSize(_ a: CGRect, _ b: CGRect) -> Bool {
        abs(a.width - b.width) <= slack && abs(a.height - b.height) <= slack
    }
}
