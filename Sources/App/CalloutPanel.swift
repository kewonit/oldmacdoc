import AppKit

/// The look of the dock's menus and Grid stacks: Leopard's light menu on the Clear Glass shelf, and
/// Snow Leopard's charcoal one (used through Mavericks) on Frosted and Smoke. Measured from Siracusa's
/// screenshots (reports/Original Dock right click menus.md).
struct MenuStyle {
    var fill: NSColor
    var rim: NSColor?
    var rimWidth: CGFloat
    var cornerRadius: CGFloat
    var text: NSColor
    var disabledText: NSColor
    var highlightTop: NSColor
    var highlightBottom: NSColor
    var highlightText: NSColor
    var separator: NSColor
    var font: NSFont
    var dark: Bool

    static let rowHeight: CGFloat = 19
    static let separatorHeight: CGFloat = 12
    static let verticalPadding: CGFloat = 5
    static let textInset: CGFloat = 21
    static let markInset: CGFloat = 7
    static let trailingInset: CGFloat = 20
    static let arrowSpace: CGFloat = 18
    static let iconSize: CGFloat = 16

    static let lucidaGrande = NSFont(name: "LucidaGrande", size: 14) ?? .menuFont(ofSize: 14)

    static func forShelf(_ style: ShelfStyle) -> MenuStyle {
        let reduce = NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
        switch style {
        case .clear:
            // Leopard's pop-up menu: light, a little translucent, with the selection colour's gradient.
            let accent = NSColor.controlAccentColor.usingColorSpace(.sRGB) ?? .systemBlue
            return MenuStyle(fill: NSColor(srgbRed: 236 / 255, green: 236 / 255, blue: 236 / 255, alpha: reduce ? 1 : 0.94),
                             rim: NSColor(white: 0, alpha: 0.12), rimWidth: 1, cornerRadius: 5,
                             text: .black, disabledText: NSColor(white: 0, alpha: 0.35),
                             highlightTop: accent.blended(withFraction: 0.25, of: .white) ?? accent,
                             highlightBottom: accent.blended(withFraction: 0.1, of: .black) ?? accent,
                             highlightText: .white, separator: NSColor(white: 0, alpha: 0.12),
                             font: lucidaGrande, dark: false)
        case .frosted, .smoke:
            // Snow Leopard's Dock menu: charcoal at 80%, a soft white rim, a blue gradient selection.
            return MenuStyle(fill: NSColor(srgbRed: 24 / 255, green: 24 / 255, blue: 24 / 255, alpha: reduce ? 1 : 0.9),
                             rim: NSColor(white: 1, alpha: 0.3), rimWidth: 1.5, cornerRadius: 6,
                             text: .white, disabledText: NSColor(white: 1, alpha: 0.35),
                             highlightTop: NSColor(srgbRed: 115 / 255, green: 127 / 255, blue: 240 / 255, alpha: 1),
                             highlightBottom: NSColor(srgbRed: 67 / 255, green: 84 / 255, blue: 250 / 255, alpha: 1),
                             highlightText: .white, separator: NSColor(white: 1, alpha: 0.2),
                             font: lucidaGrande, dark: true)
        }
    }
}

/// A borderless window drawn as the menu's material, with the pointer when it hangs above an icon.
/// It takes the keyboard without making OldMacDoc the active app, like the settings panel.
final class CalloutPanel: NSPanel {
    /// Only the first menu takes the keyboard: submenus can't, so opening one never closes the menu.
    let takesKeyboard: Bool
    var onKey: ((NSEvent) -> Bool)?
    var onFlags: ((NSEvent) -> Void)?
    var onResignKey: (() -> Void)?

    init(takesKeyboard: Bool) {
        self.takesKeyboard = takesKeyboard
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        isFloatingPanel = true
        level = .popUpMenu // after isFloatingPanel, which resets the level; above the dock
        collectionBehavior = [.canJoinAllSpaces, .transient, .ignoresCycle, .fullScreenAuxiliary]
        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isMovable = false
        isReleasedWhenClosed = false
        animationBehavior = .none
        acceptsMouseMovedEvents = true
    }

    override var canBecomeKey: Bool { takesKeyboard }
    override var canBecomeMain: Bool { false }

    override func keyDown(with event: NSEvent) {
        if onKey?(event) != true { super.keyDown(with: event) }
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        onKey?(event) ?? false
    }

    override func flagsChanged(with event: NSEvent) {
        onFlags?(event)
        super.flagsChanged(with: event)
    }

    override func resignKey() {
        super.resignKey()
        onResignKey?()
    }
}

/// Draws the panel's material: the body, its rim and the pointer, as one shape.
final class CalloutChromeView: NSView {
    var style: MenuStyle { didSet { needsDisplay = true } }
    /// The pointer's axis in this view's coordinates, or nil for a submenu (no pointer).
    var pointerX: CGFloat? { didSet { needsDisplay = true } }

    init(style: MenuStyle) {
        self.style = style
        super.init(frame: .zero)
        wantsLayer = true
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override var isOpaque: Bool { false }

    /// The body, without the pointer.
    var bodyRect: CGRect {
        let ph = pointerX == nil ? 0 : Callout.pointerHeight
        return CGRect(x: 0, y: ph, width: bounds.width, height: bounds.height - ph)
    }

    var outline: CGPath { Callout.path(size: bounds.size, pointerX: pointerX, cornerRadius: style.cornerRadius) }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        ctx.clear(bounds)
        let path = outline
        ctx.addPath(path)
        ctx.setFillColor(style.fill.cgColor)
        ctx.fillPath()
        if let rim = style.rim {
            // Inside the edge, so the window's own shape (and shadow) stays the outline.
            ctx.saveGState()
            ctx.addPath(path)
            ctx.clip()
            ctx.addPath(path)
            ctx.setStrokeColor(rim.cgColor)
            ctx.setLineWidth(style.rimWidth * 2)
            ctx.strokePath()
            ctx.restoreGState()
        }
    }
}
