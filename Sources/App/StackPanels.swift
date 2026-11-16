import AppKit

/// An open stack: Leopard's Fan (a curve of icons rising from the tile, names to their left) or its Grid
/// (a dark panel of icons with the pointer). Items open with a click and can be dragged out; arrow keys,
/// Return and Esc work; a click anywhere else closes it.
final class StackController {
    var onClose: (() -> Void)?
    /// Clicks in this window (the dock) are left to it: it closes the stack itself.
    weak var passThroughWindow: NSWindow?
    private(set) var isOpen = false
    private var panel: CalloutPanel?
    private var monitors: [Any] = []
    private var observers: [(NotificationCenter, NSObjectProtocol)] = []
    /// While an item is being dragged out, closing waits until the drag ends.
    fileprivate var dragging = false
    private var closeAfterDrag = false

    // MARK: Fan

    func openFan(folder: URL, entries: [StackEntry], anchor: NSPoint, screen: NSScreen, strings: DockStrings) {
        close(notify: false)
        let available = screen.visibleFrame.maxY - anchor.y - 8
        let capacity = StackLayout.fanCapacity(height: available)
        let shown = Array(entries.prefix(capacity - 1))
        let more = entries.count - shown.count
        let top = more > 0 ? "\(more) More in Finder" : strings[.openInFinder]
        let view = FanView(entries: shown, topTitle: top, folder: folder, controller: self)
        let panel = CalloutPanel(takesKeyboard: true)
        panel.hasShadow = false
        // The fan's own coordinates start at the tile's top centre; place the panel so that point is `anchor`,
        // moved along only as far as the screen's edges need.
        var frame = CGRect(origin: CGPoint(x: anchor.x + view.originOffset.x, y: anchor.y + view.originOffset.y), size: view.fanSize)
        frame.origin.x = min(max(frame.minX, screen.frame.minX + 4), screen.frame.maxX - frame.width - 4)
        panel.setFrame(frame, display: false)
        panel.contentView = view
        present(panel)
        view.animateIn()
    }

    // MARK: Grid

    func openGrid(folder: URL, title: String, entries: [StackEntry], sort: StackSort, anchor: NSPoint, screen: NSScreen,
                  strings: DockStrings) {
        close(notify: false)
        var style = MenuStyle.forShelf(.smoke) // Leopard's grid was dark on every shelf
        style.fill = style.fill.withAlphaComponent(NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency ? 1 : 0.93)
        let content = GridContent(folder: folder, title: title, entries: entries, sort: sort, openTitle: strings[.openInFinder],
                                  controller: self)
        let panel = CalloutPanel(takesKeyboard: true)
        let chrome = CalloutChromeView(style: style)
        panel.contentView = chrome
        chrome.addSubview(content)
        content.onResize = { [weak self, weak panel, weak chrome, weak content] in
            guard let self, let panel, let chrome, let content else { return }
            self.layoutGrid(panel: panel, chrome: chrome, content: content, anchor: anchor, screen: screen, style: style)
        }
        layoutGrid(panel: panel, chrome: chrome, content: content, anchor: anchor, screen: screen, style: style)
        present(panel)
        panel.makeFirstResponder(content.grid)
    }

    private func layoutGrid(panel: CalloutPanel, chrome: CalloutChromeView, content: GridContent, anchor: NSPoint, screen: NSScreen,
                            style: MenuStyle) {
        let size = content.preferredSize(maxWidth: screen.frame.width * 0.9)
        let p = Callout.place(size: size, anchorX: anchor.x, anchorTop: anchor.y, screen: screen.frame,
                              top: screen.visibleFrame.maxY, cornerRadius: style.cornerRadius, alignment: .centered)
        panel.setFrame(p.frame, display: false)
        chrome.frame = CGRect(origin: .zero, size: p.frame.size)
        chrome.pointerX = p.pointerX - p.frame.minX
        content.frame = chrome.bodyRect
        content.layoutContent()
        panel.invalidateShadow()
    }

    // MARK: Opening and closing

    private func present(_ panel: CalloutPanel) {
        self.panel = panel
        isOpen = true
        panel.onKey = { [weak self] event in self?.key(event) ?? false }
        panel.onResignKey = { [weak self] in DispatchQueue.main.async { self?.close() } }
        panel.makeKeyAndOrderFront(nil)
        installMonitors()
    }

    func close() { close(notify: true) }

    /// The pointer moved (screen coordinates): the item under it lights up.
    func pointerMoved(to p: NSPoint) {
        guard isOpen, let panel, let view = panel.contentView else { return }
        let local = panel.convertPoint(fromScreen: p)
        if let fan = view as? FanView {
            fan.hover(fan.convert(local, from: nil))
        } else if let grid = view.subviews.compactMap({ $0 as? GridContent }).first?.grid {
            grid.hover(grid.convert(local, from: nil))
        }
    }

    private func close(notify: Bool) {
        guard isOpen else { return }
        if dragging {
            closeAfterDrag = true
            panel?.orderOut(nil)
            return
        }
        isOpen = false
        removeMonitors()
        panel?.onResignKey = nil
        panel?.orderOut(nil)
        panel = nil
        if notify { onClose?() }
    }

    fileprivate func dragEnded() {
        dragging = false
        if closeAfterDrag {
            closeAfterDrag = false
            close()
        }
    }

    /// Opens an item: folders in the Fan open in Finder (as in Leopard); everything else opens as usual.
    fileprivate func open(_ url: URL) {
        close()
        NSWorkspace.shared.open(url)
    }

    private func key(_ event: NSEvent) -> Bool {
        guard isOpen, let view = panel?.contentView else { return false }
        if event.keyCode == 53 { close(); return true }
        if let fan = view as? FanView { return fan.key(event) }
        if let grid = view.subviews.compactMap({ $0 as? GridContent }).first { return grid.key(event) }
        return false
    }

    private func installMonitors() {
        let downs: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        if let m = NSEvent.addGlobalMonitorForEvents(matching: downs, handler: { [weak self] _ in self?.close() }) { monitors.append(m) }
        if let m = NSEvent.addLocalMonitorForEvents(matching: downs, handler: { [weak self] event in
            guard let self, let window = event.window else { return event }
            if window !== self.panel, window !== self.passThroughWindow { self.close() }
            return event
        }) { monitors.append(m) }
        let ws = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.activeSpaceDidChangeNotification, NSWorkspace.willSleepNotification,
                     NSWorkspace.sessionDidResignActiveNotification] {
            observers.append((ws, ws.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in self?.close() }))
        }
        let nc = NotificationCenter.default
        observers.append((nc, nc.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) {
            [weak self] _ in self?.close()
        }))
    }

    private func removeMonitors() {
        monitors.forEach(NSEvent.removeMonitor)
        monitors.removeAll()
        observers.forEach { $0.0.removeObserver($0.1) }
        observers.removeAll()
    }

    #if DEBUG
    func debugState() -> [String: Any] {
        guard let panel else { return ["open": isOpen] }
        let f = panel.frame
        var state: [String: Any] = ["open": isOpen, "frame": [f.minX, f.minY, f.width, f.height], "window": panel.windowNumber,
                                    "key": panel.isKeyWindow]
        if let fan = panel.contentView as? FanView { state["kind"] = "fan"; state["items"] = fan.titles }
        if let grid = panel.contentView?.subviews.compactMap({ $0 as? GridContent }).first {
            state["kind"] = "grid"; state["items"] = grid.grid.entries.map(\.name); state["title"] = grid.titleText
        }
        return state
    }

    func debugOpenItem(_ name: String) {
        guard let view = panel?.contentView else { return }
        if let fan = view as? FanView { fan.debugOpen(name) }
        if let grid = view.subviews.compactMap({ $0 as? GridContent }).first { grid.grid.debugOpen(name) }
    }
    #endif
}

// MARK: - Dragging an item out

/// Starts dragging a file out of a stack (to Finder, the desktop or an app), as Leopard allowed.
private final class StackDragSource: NSObject, NSDraggingSource {
    weak var controller: StackController?

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        context == .outsideApplication ? [.copy, .move, .link, .generic] : []
    }

    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        controller?.dragEnded()
    }

    func begin(_ url: URL, icon: NSImage, frame: CGRect, from view: NSView, event: NSEvent) {
        let item = NSDraggingItem(pasteboardWriter: url as NSURL)
        item.setDraggingFrame(frame, contents: icon)
        controller?.dragging = true
        view.beginDraggingSession(with: [item], event: event, source: self)
    }
}

// MARK: - Fan

private final class FanView: NSView {
    private struct Slot {
        var url: URL?
        var title: String
        var iconRect: CGRect
        var labelRect: CGRect
        let icon = CALayer()
        let pill = CALayer()
        let label = CATextLayer()
    }

    private var slots: [Slot] = []
    private let folder: URL
    private weak var controller: StackController?
    /// Where the tile's top centre is in this view's coordinates (negated: the view's origin from it).
    private(set) var originOffset = CGPoint.zero
    private(set) var fanSize = CGSize.zero
    private var highlighted: Int? { didSet { if highlighted != oldValue { restyle() } } }
    private var pressed: Int?
    private var pressPoint = NSPoint.zero
    private let source = StackDragSource()
    private static let font = NSFont(name: "LucidaGrande-Bold", size: 12) ?? .boldSystemFont(ofSize: 12)

    var titles: [String] { slots.map(\.title) }

    init(entries: [StackEntry], topTitle: String, folder: URL, controller: StackController) {
        self.folder = folder
        self.controller = controller
        source.controller = controller
        super.init(frame: .zero)
        wantsLayer = true
        layer?.masksToBounds = false
        let items: [(URL?, String)] = entries.map { ($0.url, $0.name) } + [(nil, topTitle)]
        let positions = StackLayout.fan(count: items.count)
        let size = StackLayout.fanIcon
        var built: [Slot] = []
        for (i, (url, title)) in items.enumerated() {
            let c = positions[i].center
            let iconRect = CGRect(x: c.x - size / 2, y: c.y - size / 2, width: size, height: size)
            let textWidth = ceil((title as NSString).size(withAttributes: [.font: Self.font]).width)
            let w = min(textWidth + 22, 320), h: CGFloat = 20
            let labelRect = CGRect(x: iconRect.minX - 8 - w, y: c.y - h / 2, width: w, height: h)
            let slot = Slot(url: url, title: title, iconRect: iconRect, labelRect: labelRect)
            slot.icon.contents = url.map { IconEngine.cgImage(NSWorkspace.shared.icon(forFile: $0.path), size: 96) }
                ?? StackArt.finderArrow(size: 96)
            slot.icon.contentsGravity = .resizeAspect
            slot.icon.setAffineTransform(CGAffineTransform(rotationAngle: positions[i].rotation))
            slot.icon.shadowOpacity = 0.4
            slot.icon.shadowRadius = 3
            slot.icon.shadowOffset = CGSize(width: 0, height: -2)
            slot.pill.cornerRadius = h / 2
            slot.label.string = title
            slot.label.font = Self.font
            slot.label.fontSize = Self.font.pointSize
            slot.label.foregroundColor = .white
            slot.label.alignmentMode = .center
            slot.label.truncationMode = .middle
            slot.label.contentsScale = 2
            built.append(slot)
        }
        slots = built
        // Bounds around every icon and label, with room for shadows.
        var box = slots.reduce(CGRect.null) { $0.union($1.iconRect).union($1.labelRect) }.insetBy(dx: -10, dy: -10)
        box.origin.y = min(box.minY, 0)
        originOffset = box.origin
        fanSize = box.size
        frame = CGRect(origin: .zero, size: box.size)
        for i in slots.indices {
            slots[i].iconRect = slots[i].iconRect.offsetBy(dx: -box.minX, dy: -box.minY)
            slots[i].labelRect = slots[i].labelRect.offsetBy(dx: -box.minX, dy: -box.minY)
            layer?.addSublayer(slots[i].pill)
            slots[i].pill.addSublayer(slots[i].label)
            layer?.addSublayer(slots[i].icon)
        }
        restyle()
        setAccessibilityElement(true)
        setAccessibilityRole(.list)
        setAccessibilityLabel(FileManager.default.displayName(atPath: folder.path))
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    private func restyle() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for (i, slot) in slots.enumerated() {
            slot.icon.bounds = CGRect(origin: .zero, size: slot.iconRect.size)
            slot.icon.position = CGPoint(x: slot.iconRect.midX, y: slot.iconRect.midY)
            slot.pill.frame = slot.labelRect
            slot.pill.backgroundColor = i == highlighted
                ? CGColor(srgbRed: 0.27, green: 0.38, blue: 0.95, alpha: 0.95) : CGColor(gray: 0, alpha: 0.72)
            slot.label.frame = CGRect(x: 8, y: 2, width: slot.labelRect.width - 16, height: slot.labelRect.height - 4)
        }
        CATransaction.commit()
    }

    /// Items spring out of the tile along the curve (or fade in with Reduce Motion).
    func animateIn() {
        let reduce = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        let start = CGPoint(x: -originOffset.x, y: -originOffset.y)
        for (i, slot) in slots.enumerated() {
            for l in [slot.icon, slot.pill] {
                if reduce {
                    let fade = CABasicAnimation(keyPath: "opacity")
                    fade.fromValue = 0
                    fade.duration = 0.15
                    l.add(fade, forKey: "in")
                } else {
                    let move = CABasicAnimation(keyPath: "position")
                    move.fromValue = NSValue(point: start)
                    move.duration = 0.18 + Double(i) * 0.012
                    move.timingFunction = CAMediaTimingFunction(name: .easeOut)
                    let grow = CABasicAnimation(keyPath: "transform.scale")
                    grow.fromValue = 0.3
                    grow.duration = move.duration
                    l.add(move, forKey: "in")
                    l.add(grow, forKey: "grow")
                }
            }
        }
    }

    private func slot(at p: NSPoint) -> Int? {
        slots.indices.last { slots[$0].iconRect.insetBy(dx: -4, dy: -4).contains(p) || slots[$0].labelRect.contains(p) }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                       owner: self, userInfo: nil))
    }

    override func mouseMoved(with event: NSEvent) { hover(convert(event.locationInWindow, from: nil)) }
    override func mouseExited(with event: NSEvent) { highlighted = nil }

    func hover(_ p: NSPoint) { highlighted = slot(at: p) }

    override func hitTest(_ point: NSPoint) -> NSView? {
        // Clicks between the items fall through to whatever is behind (and close the fan).
        slot(at: convert(point, from: superview)) == nil ? nil : self
    }

    override func mouseDown(with event: NSEvent) {
        pressPoint = convert(event.locationInWindow, from: nil)
        pressed = slot(at: pressPoint)
    }

    override func mouseDragged(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        guard let i = pressed, let url = slots[i].url, hypot(p.x - pressPoint.x, p.y - pressPoint.y) > 4 else { return }
        pressed = nil
        source.begin(url, icon: NSWorkspace.shared.icon(forFile: url.path), frame: slots[i].iconRect, from: self, event: event)
    }

    override func mouseUp(with event: NSEvent) {
        defer { pressed = nil }
        guard let i = pressed, i == slot(at: convert(event.locationInWindow, from: nil)) else { return }
        choose(i)
    }

    private func choose(_ i: Int) {
        controller?.open(slots[i].url ?? folder)
    }

    func key(_ event: NSEvent) -> Bool {
        switch event.keyCode {
        case 126: highlighted = min((highlighted ?? -1) + 1, slots.count - 1) // ↑ goes up the fan
        case 125: highlighted = max((highlighted ?? slots.count) - 1, 0)
        case 36, 76, 49: if let i = highlighted { choose(i) }
        default: return false
        }
        return true
    }

    override func accessibilityChildren() -> [Any]? {
        slots.enumerated().map { i, slot in
            let e = StackItemElement { [weak self] in self?.choose(i) }
            e.setAccessibilityParent(self)
            e.setAccessibilityRole(.button)
            e.setAccessibilityLabel(slot.title)
            e.setAccessibilityFrameInParentSpace(slot.iconRect.union(slot.labelRect))
            return e
        }
    }

    #if DEBUG
    func debugOpen(_ name: String) { if let i = slots.firstIndex(where: { $0.title == name }) { choose(i) } }
    #endif
}

private final class StackItemElement: NSAccessibilityElement {
    let press: () -> Void
    init(press: @escaping () -> Void) {
        self.press = press
        super.init()
    }
    override func accessibilityPerformPress() -> Bool {
        press()
        return true
    }
}

// MARK: - Grid

/// The Grid's contents: a title row (with Back inside a subfolder, and Open in Finder) over a scrolling grid.
private final class GridContent: NSView {
    let grid: GridView
    private let scroll = NSScrollView()
    private let title = NSTextField(labelWithString: "")
    private let back = NSButton(title: "◀︎", target: nil, action: nil)
    private let openButton = NSButton(title: "", target: nil, action: nil)
    private var path: [(url: URL, name: String)]
    private let sort: StackSort
    private weak var controller: StackController?
    var onResize: (() -> Void)?
    var titleText: String { title.stringValue }

    init(folder: URL, title: String, entries: [StackEntry], sort: StackSort, openTitle: String, controller: StackController) {
        self.sort = sort
        self.controller = controller
        path = [(folder, title)]
        grid = GridView(entries: entries, controller: controller)
        super.init(frame: .zero)
        grid.onNavigate = { [weak self] url, name in self?.navigate(to: url, name: name) }
        scroll.drawsBackground = false
        scroll.contentView.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.scrollerStyle = .overlay
        scroll.autohidesScrollers = true
        scroll.documentView = grid
        addSubview(scroll)
        self.title.font = NSFont(name: "LucidaGrande-Bold", size: 13) ?? .boldSystemFont(ofSize: 13)
        self.title.textColor = .white
        self.title.alignment = .center
        self.title.lineBreakMode = .byTruncatingMiddle
        addSubview(self.title)
        for b in [back, openButton] {
            b.isBordered = false
            b.contentTintColor = .white
            b.font = NSFont(name: "LucidaGrande", size: 12) ?? .systemFont(ofSize: 12)
            b.target = self
            addSubview(b)
        }
        back.action = #selector(goBack)
        back.setAccessibilityLabel("Back")
        openButton.attributedTitle = NSAttributedString(string: openTitle + " ➜", attributes: [
            .foregroundColor: NSColor.white, .font: NSFont(name: "LucidaGrande", size: 12) ?? .systemFont(ofSize: 12)])
        openButton.action = #selector(openInFinder)
        updateTitle()
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    func preferredSize(maxWidth: CGFloat) -> CGSize {
        let columns = StackLayout.gridColumns(count: grid.entries.count, maxWidth: maxWidth)
        grid.columns = columns
        return StackLayout.gridSize(count: grid.entries.count, columns: columns)
    }

    func layoutContent() {
        let header = StackLayout.gridHeader
        title.frame = CGRect(x: 60, y: bounds.height - header + 6, width: bounds.width - 120 - 60, height: 20)
        back.frame = CGRect(x: 10, y: bounds.height - header + 4, width: 30, height: 24)
        back.isHidden = path.count < 2
        openButton.sizeToFit()
        openButton.frame = CGRect(x: bounds.width - openButton.frame.width - 12, y: bounds.height - header + 4,
                                  width: openButton.frame.width, height: 24)
        scroll.frame = CGRect(x: 0, y: 0, width: bounds.width, height: bounds.height - header)
        grid.frame = CGRect(x: 0, y: 0, width: bounds.width, height: max(grid.contentHeight, scroll.contentSize.height))
        grid.needsDisplay = true
    }

    private func updateTitle() { title.stringValue = path.last?.name ?? "" }

    /// A subfolder opens in place, as in Snow Leopard's Grid.
    private func navigate(to url: URL, name: String) {
        path.append((url, name))
        grid.entries = StackEntry.sorted(StackEntry.contents(of: url), by: sort)
        updateTitle()
        onResize?()
    }

    @objc private func goBack() {
        guard path.count > 1 else { return }
        path.removeLast()
        grid.entries = StackEntry.sorted(StackEntry.contents(of: path[path.count - 1].url), by: sort)
        updateTitle()
        onResize?()
    }

    @objc private func openInFinder() {
        controller?.open(path[path.count - 1].url)
    }

    func key(_ event: NSEvent) -> Bool {
        if event.keyCode == 51 || (event.keyCode == 126 && event.modifierFlags.contains(.command)) {
            goBack()
            return true
        }
        return grid.key(event)
    }
}

private final class GridView: NSView {
    var entries: [StackEntry] {
        didSet {
            highlighted = entries.isEmpty ? nil : 0
            icons.removeAll()
            needsDisplay = true
            NSAccessibility.post(element: self, notification: .layoutChanged)
        }
    }
    var columns = 4
    var onNavigate: ((URL, String) -> Void)?
    private weak var controller: StackController?
    private var icons: [URL: NSImage] = [:]
    private var highlighted: Int? { didSet { if highlighted != oldValue { needsDisplay = true } } }
    private var pressed: Int?
    private var pressPoint = NSPoint.zero
    private let source = StackDragSource()

    init(entries: [StackEntry], controller: StackController) {
        self.entries = entries
        self.controller = controller
        source.controller = controller
        super.init(frame: .zero)
        setAccessibilityElement(true)
        setAccessibilityRole(.list)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    var contentHeight: CGFloat {
        let rows = max(1, Int(ceil(Double(entries.count) / Double(max(columns, 1)))))
        return CGFloat(rows) * StackLayout.gridCell.height + 2 * StackLayout.gridPadding
    }

    private func cell(_ i: Int) -> CGRect {
        let cell = StackLayout.gridCell
        let used = CGFloat(columns) * cell.width
        let left = (bounds.width - used) / 2
        return CGRect(x: left + CGFloat(i % columns) * cell.width, y: StackLayout.gridPadding + CGFloat(i / columns) * cell.height,
                      width: cell.width, height: cell.height)
    }

    private func index(at p: NSPoint) -> Int? {
        entries.indices.first { cell($0).insetBy(dx: 4, dy: 2).contains(p) }
    }

    override func draw(_ dirtyRect: NSRect) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        paragraph.lineBreakMode = .byTruncatingMiddle
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont(name: "LucidaGrande", size: 11) ?? .systemFont(ofSize: 11), .foregroundColor: NSColor.white,
            .paragraphStyle: paragraph]
        for (i, entry) in entries.enumerated() {
            let r = cell(i)
            guard r.intersects(dirtyRect) else { continue }
            if i == highlighted {
                NSColor(white: 1, alpha: 0.16).setFill()
                NSBezierPath(roundedRect: r.insetBy(dx: 5, dy: 3), xRadius: 7, yRadius: 7).fill()
            }
            let icon = icons[entry.url] ?? {
                let image = NSWorkspace.shared.icon(forFile: entry.url.path)
                icons[entry.url] = image
                return image
            }()
            let side = StackLayout.gridIcon
            icon.draw(in: CGRect(x: r.midX - side / 2, y: r.minY + 6, width: side, height: side), from: .zero,
                      operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
            (entry.name as NSString).draw(with: CGRect(x: r.minX + 6, y: r.minY + side + 10, width: r.width - 12, height: 28),
                                          options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine], attributes: attrs)
        }
        if entries.isEmpty {
            ("No Items" as NSString).draw(at: NSPoint(x: bounds.midX - 30, y: 30), withAttributes: attrs)
        }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseMoved, .activeAlways, .inVisibleRect], owner: self, userInfo: nil))
    }

    override func mouseMoved(with event: NSEvent) { hover(convert(event.locationInWindow, from: nil)) }

    func hover(_ p: NSPoint) {
        guard visibleRect.contains(p), let i = index(at: p) else { return }
        highlighted = i
    }

    override func mouseDown(with event: NSEvent) {
        pressPoint = convert(event.locationInWindow, from: nil)
        pressed = index(at: pressPoint)
    }

    override func mouseDragged(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        guard let i = pressed, hypot(p.x - pressPoint.x, p.y - pressPoint.y) > 4 else { return }
        pressed = nil
        let r = cell(i)
        let side = StackLayout.gridIcon
        source.begin(entries[i].url, icon: NSWorkspace.shared.icon(forFile: entries[i].url.path),
                     frame: CGRect(x: r.midX - side / 2, y: r.minY + 6, width: side, height: side), from: self, event: event)
    }

    override func mouseUp(with event: NSEvent) {
        defer { pressed = nil }
        guard let i = pressed, i == index(at: convert(event.locationInWindow, from: nil)) else { return }
        choose(i)
    }

    private func choose(_ i: Int) {
        let entry = entries[i]
        if entry.isFolder { onNavigate?(entry.url, entry.name) } else { controller?.open(entry.url) }
    }

    func key(_ event: NSEvent) -> Bool {
        guard !entries.isEmpty else { return false }
        let i = highlighted ?? 0
        switch event.keyCode {
        case 123: highlighted = max(i - 1, 0)
        case 124: highlighted = min(i + 1, entries.count - 1)
        case 126: highlighted = max(i - columns, 0)
        case 125: highlighted = min(i + columns, entries.count - 1)
        case 36, 76: choose(i)
        default: return false
        }
        if let h = highlighted { scrollToVisible(cell(h)) }
        return true
    }

    override func accessibilityChildren() -> [Any]? {
        entries.indices.map { i in
            // By file, not by place: the list changes when a subfolder opens.
            let url = entries[i].url
            let e = StackItemElement { [weak self] in
                guard let self, let j = self.entries.firstIndex(where: { $0.url == url }) else { return }
                self.choose(j)
            }
            e.setAccessibilityParent(self)
            e.setAccessibilityRole(.button)
            e.setAccessibilityLabel(entries[i].name)
            e.setAccessibilityFrameInParentSpace(cell(i))
            return e
        }
    }

    #if DEBUG
    func debugOpen(_ name: String) { if let i = entries.firstIndex(where: { $0.name == name }) { choose(i) } }
    #endif
}
