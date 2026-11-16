import AppKit

/// The dock's menus, drawn the way the original Dock drew them: hanging above the icon with a pointer
/// aimed at it, in Leopard's light or Snow Leopard's charcoal material. It behaves like a menu:
/// press, drag and release on a row; or click the icon and then click a row; arrow keys, Return,
/// Esc and type-select; submenus open on hover; Option swaps Hide for Hide Others and Quit for Force Quit.
final class DockMenuController {
    var onChoose: ((DockCommand) -> Void)?
    var onClose: (() -> Void)?
    /// Rows for a folder's submenu in a List stack, loaded when it opens.
    var loadFolder: ((String) -> [DockMenuItem])?
    /// Clicks in this window (the dock) are left to it: it closes or reopens the menu itself.
    weak var passThroughWindow: NSWindow?

    private(set) var isOpen = false
    /// Following a mouse button held since the menu opened (press, drag, release).
    private(set) var isTracking = false

    private var levels: [Level] = []
    private var style = MenuStyle.forShelf(.clear)
    private var screenFrame: CGRect = .zero
    private var topLimit: CGFloat = 0
    private var anchorX: CGFloat = 0
    private var anchorTop: CGFloat = 0
    private var alignment: Callout.Alignment = .leading
    private var option = false
    private var enteredMenu = false
    private var typed = ""
    private var typedAt: TimeInterval = 0
    private var pendingSubmenu: DispatchWorkItem?
    private var monitors: [Any] = []
    private var observers: [(NotificationCenter, NSObjectProtocol)] = []

    private final class Level {
        let panel: CalloutPanel
        let chrome: CalloutChromeView
        let scroll = NSScrollView()
        let rowsView: MenuRowsView
        var items: [DockMenuItem]
        /// The row in the level above that this submenu belongs to.
        var parentRow: Int?

        init(items: [DockMenuItem], style: MenuStyle, root: Bool) {
            self.items = items
            panel = CalloutPanel(takesKeyboard: root)
            chrome = CalloutChromeView(style: style)
            rowsView = MenuRowsView(style: style)
            scroll.drawsBackground = false
            scroll.contentView.drawsBackground = false
            scroll.borderType = .noBorder
            scroll.scrollerStyle = .overlay
            scroll.hasVerticalScroller = false
            scroll.documentView = rowsView
            chrome.addSubview(scroll)
            panel.contentView = chrome
            panel.title = root ? "Dock menu" : "Submenu"
        }
    }

    // MARK: Opening and closing

    /// Opens `items` above an icon whose top centre is (`anchorX`, `anchorTop`) in screen coordinates.
    /// - Parameter tracking: a mouse button is still down (it chooses where it's let go).
    func open(_ items: [DockMenuItem], anchorX: CGFloat, anchorTop: CGFloat, screen: NSScreen, style: MenuStyle,
              tracking: Bool, alignment: Callout.Alignment = .leading) {
        close(notify: false)
        guard !items.isEmpty else { return }
        self.style = style
        self.anchorX = anchorX
        self.anchorTop = anchorTop
        self.alignment = alignment
        screenFrame = screen.frame
        topLimit = screen.visibleFrame.maxY
        option = NSEvent.modifierFlags.contains(.option)
        enteredMenu = false
        isTracking = tracking
        isOpen = true
        typed = ""
        let level = Level(items: items, style: style, root: true)
        wire(level)
        levels = [level]
        layout(0)
        level.panel.makeKeyAndOrderFront(nil)
        installMonitors()
        NSAccessibility.post(element: level.rowsView, notification: NSAccessibility.Notification(rawValue: "AXMenuOpened"))
    }

    func close() { close(notify: true) }

    #if DEBUG
    private(set) var lastCloseReason = ""
    #endif

    private func close(notify: Bool, reason: String = "asked") {
        guard isOpen else { return }
        #if DEBUG
        lastCloseReason = reason
        #endif
        isOpen = false
        isTracking = false
        pendingSubmenu?.cancel()
        pendingSubmenu = nil
        removeMonitors()
        let root = levels.first?.rowsView
        for level in levels.reversed() {
            level.panel.onResignKey = nil
            level.panel.orderOut(nil)
        }
        levels.removeAll()
        if let root { NSAccessibility.post(element: root, notification: NSAccessibility.Notification(rawValue: "AXMenuClosed")) }
        if notify { onClose?() }
    }

    private func wire(_ level: Level) {
        level.rowsView.controller = self
        level.panel.onKey = { [weak self] in self?.key($0) ?? false }
        level.panel.onFlags = { [weak self] in self?.flagsChanged($0) }
        if level.panel.takesKeyboard {
            level.panel.onResignKey = { [weak self] in
                // Another window took the keyboard (a click in another app, the settings panel).
                DispatchQueue.main.async { self?.close(notify: true, reason: "resignKey") }
            }
        }
    }

    // MARK: Layout

    private func rows(for items: [DockMenuItem]) -> [DockMenuItem] {
        visibleRows(items, option: option).map { item in
            var row = item
            let r = item.resolved(option: option)
            row.title = r.title
            row.command = r.command
            return row
        }
    }

    /// Sizes and places level `k`: the first above the icon, submenus beside their row.
    private func layout(_ k: Int) {
        let level = levels[k]
        level.rowsView.style = style
        level.chrome.style = style
        level.rowsView.rows = rows(for: level.items)
        let size = level.rowsView.measure()
        let frame: CGRect, pointer: CGFloat?, clipped: Bool
        if k == 0 {
            let p = Callout.place(size: size, anchorX: anchorX, anchorTop: anchorTop, screen: screenFrame, top: topLimit,
                                  cornerRadius: style.cornerRadius, alignment: alignment)
            frame = p.frame
            pointer = p.pointerX - p.frame.minX
            clipped = p.isClipped
        } else {
            let parent = levels[k - 1]
            let row = parent.rowsView.screenRect(ofRow: level.parentRow ?? 0)
            let s = Callout.submenu(size: size, row: row, parent: parent.panel.frame, screen: screenFrame, top: topLimit,
                                    inset: MenuStyle.verticalPadding)
            frame = s.frame
            pointer = nil
            clipped = s.isClipped
        }
        level.panel.setFrame(frame, display: false)
        level.chrome.frame = CGRect(origin: .zero, size: frame.size)
        level.chrome.pointerX = pointer
        level.scroll.frame = level.chrome.bodyRect
        level.rowsView.frame = CGRect(origin: .zero, size: CGSize(width: frame.width, height: size.height))
        level.scroll.hasVerticalScroller = clipped
        level.panel.invalidateShadow()
        level.chrome.needsDisplay = true
        level.rowsView.needsDisplay = true
    }

    // MARK: Pointer

    private func hit(_ p: NSPoint) -> (level: Int, row: Int?)? {
        for k in levels.indices.reversed() where levels[k].panel.frame.contains(p) {
            let view = levels[k].rowsView
            let local = view.convert(levels[k].panel.convertPoint(fromScreen: p), from: nil)
            guard view.visibleRect.contains(local) else { return (k, nil) }
            return (k, view.row(at: local))
        }
        return nil
    }

    /// The pointer is at `p` (screen coordinates): highlight what's under it, open or close submenus.
    func hover(at p: NSPoint) {
        guard isOpen else { return }
        guard let (k, row) = hit(p) else {
            // Away from the menu: the deepest menu loses its highlight, unless it leads to an open submenu.
            if let last = levels.last, levels.count == 1 || last.rowsView.highlighted != nil {
                last.rowsView.highlighted = nil
            }
            return
        }
        enteredMenu = true
        let level = levels[k]
        // In a submenu: the rows leading to it stay lit, and nothing pending closes it.
        for j in stride(from: k, to: 0, by: -1) { levels[j - 1].rowsView.highlighted = levels[j].parentRow }
        if k > 0, k == levels.count - 1 { pendingSubmenu?.cancel() }
        guard let row, level.rowsView.rows[row].isSelectable else {
            if levels.count == k + 1 { level.rowsView.highlighted = nil }
            return
        }
        if levels.count > k + 1, levels[k + 1].parentRow == row {
            // Back on the row whose submenu is open: keep it.
            pendingSubmenu?.cancel()
            level.rowsView.highlighted = row
            levels[k + 1].rowsView.highlighted = nil
            return
        }
        level.rowsView.highlighted = row
        let item = level.rowsView.rows[row]
        schedule(after: item.submenu != nil || item.folderPath != nil ? 0.1 : 0.2) { [weak self] in
            guard let self, self.isOpen, k < self.levels.count, self.levels[k].rowsView.highlighted == row else { return }
            self.closeLevels(after: k)
            if item.submenu != nil || item.folderPath != nil { self.openSubmenu(k, row) }
        }
    }

    /// The button went up at `p`: choose, stay open to be clicked, or close.
    func release(at p: NSPoint) {
        guard isOpen, isTracking else { return }
        isTracking = false
        let target = hit(p)
        var overItem = false
        if let (k, row) = target, let row {
            let item = levels[k].rowsView.rows[row]
            overItem = item.isSelectable && item.submenu == nil && item.folderPath == nil
        }
        switch MenuTracking.release(enteredMenu: enteredMenu, overItem: overItem, overMenu: target != nil) {
        case .choose: if let (k, row) = target, let row { choose(k, row) }
        case .stayOpen: break
        case .close: close()
        }
    }

    /// A click on a row while the menu stays open.
    fileprivate func clicked(_ view: MenuRowsView, row: Int?) {
        guard let k = levels.firstIndex(where: { $0.rowsView === view }), let row else { return }
        let item = view.rows[row]
        guard item.isSelectable else { return }
        if item.submenu != nil || item.folderPath != nil {
            pendingSubmenu?.cancel()
            closeLevels(after: k)
            view.highlighted = row
            openSubmenu(k, row)
        } else {
            choose(k, row)
        }
    }

    fileprivate func moved(_ view: MenuRowsView, to local: NSPoint?) {
        guard let window = view.window else { return }
        if let local {
            hover(at: window.convertPoint(toScreen: view.convert(local, to: nil)))
        } else {
            hover(at: NSPoint(x: -100_000, y: -100_000))
        }
    }

    private func schedule(after delay: TimeInterval, _ work: @escaping () -> Void) {
        pendingSubmenu?.cancel()
        let item = DispatchWorkItem(block: work)
        pendingSubmenu = item
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
    }

    private func openSubmenu(_ k: Int, _ row: Int) {
        let parent = levels[k]
        let item = parent.rowsView.rows[row]
        var sub = item.submenu ?? []
        if sub.isEmpty, let path = item.folderPath { sub = loadFolder?(path) ?? [] }
        guard !sub.isEmpty else { return }
        closeLevels(after: k)
        let level = Level(items: sub, style: style, root: false)
        level.parentRow = row
        wire(level)
        levels.append(level)
        layout(levels.count - 1)
        level.panel.order(.above, relativeTo: parent.panel.windowNumber)
    }

    private func closeLevels(after k: Int) {
        while levels.count > k + 1 {
            let level = levels.removeLast()
            level.panel.orderOut(nil)
        }
    }

    private func choose(_ k: Int, _ row: Int) {
        let item = levels[k].rowsView.rows[row]
        guard item.isSelectable, item.submenu == nil, item.folderPath == nil else { return }
        let command = item.command
        close()
        // After the menu has gone, so dialogs it starts (Empty Trash, Choose Image) come up on their own.
        DispatchQueue.main.async { [weak self] in self?.onChoose?(command) }
    }

    // MARK: Keyboard

    private func key(_ event: NSEvent) -> Bool {
        guard isOpen, event.type == .keyDown else { return false }
        isTracking = false
        let k = levels.count - 1
        let view = levels[k].rowsView
        let selectable = view.rows.map(\.isSelectable)
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        switch event.keyCode {
        case 125: view.highlight(MenuTracking.next(from: view.highlighted, step: 1, selectable: selectable))
        case 126: view.highlight(MenuTracking.next(from: view.highlighted, step: -1, selectable: selectable))
        case 124: // →
            if let row = view.highlighted, view.rows[row].submenu != nil || view.rows[row].folderPath != nil {
                openSubmenu(k, row)
                if let sub = levels.last, levels.count > k + 1 {
                    sub.rowsView.highlight(MenuTracking.next(from: nil, step: 1, selectable: sub.rowsView.rows.map(\.isSelectable)))
                }
            }
        case 123: // ←
            if k > 0 { closeLevels(after: k - 1) }
        case 36, 76, 49: // Return, Enter, Space
            if let row = view.highlighted { clicked(view, row: row) }
        case 53: close() // Esc
        default:
            if flags == .command, event.charactersIgnoringModifiers == "." { close(); return true }
            guard flags.subtracting([.shift, .capsLock]).isEmpty, let chars = event.characters, !chars.isEmpty,
                  chars.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) }) else { return true }
            let now = ProcessInfo.processInfo.systemUptime
            typed = now - typedAt > 1 ? chars : typed + chars
            typedAt = now
            if let row = MenuTracking.typeSelect(typed, titles: view.rows.map(\.title), selectable: selectable, from: view.highlighted) {
                view.highlight(row)
            }
        }
        return true
    }

    private func flagsChanged(_ event: NSEvent) {
        let held = event.modifierFlags.contains(.option)
        guard held != option, isOpen else { return }
        option = held
        for k in levels.indices {
            let highlighted = levels[k].rowsView.highlighted
            layout(k)
            if let h = highlighted, h < levels[k].rowsView.rows.count { levels[k].rowsView.highlighted = h }
        }
    }

    // MARK: Closing on clicks elsewhere

    private func installMonitors() {
        let downs: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        if let m = NSEvent.addGlobalMonitorForEvents(matching: downs, handler: { [weak self] _ in self?.close(notify: true, reason: "click elsewhere") }) {
            monitors.append(m)
        }
        if let m = NSEvent.addLocalMonitorForEvents(matching: downs, handler: { [weak self] event in
            guard let self, let window = event.window else { return event }
            let ours = self.levels.contains { $0.panel === window }
            if !ours, window !== self.passThroughWindow { self.close(notify: true, reason: "click in our window") }
            return event
        }) { monitors.append(m) }
        let ws = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.activeSpaceDidChangeNotification, NSWorkspace.willSleepNotification,
                     NSWorkspace.sessionDidResignActiveNotification, NSWorkspace.didActivateApplicationNotification] {
            observers.append((ws, ws.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                let app = (note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.bundleIdentifier ?? ""
                self?.close(notify: true, reason: "\(name.rawValue) \(app)")
            }))
        }
        let nc = NotificationCenter.default
        observers.append((nc, nc.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil,
                                             queue: .main) { [weak self] _ in self?.close(notify: true, reason: "screens") }))
    }

    private func removeMonitors() {
        monitors.forEach(NSEvent.removeMonitor)
        monitors.removeAll()
        observers.forEach { $0.0.removeObserver($0.1) }
        observers.removeAll()
    }

    // MARK: Debug hooks

    #if DEBUG
    /// The menu's state, for the `dump` debug command.
    func debugState() -> [String: Any] {
        [
            "open": isOpen, "tracking": isTracking, "option": option, "monitors": monitors.count, "closed": lastCloseReason,
            "levels": levels.map { level -> [String: Any] in
                let f = level.panel.frame
                return ["frame": [f.minX, f.minY, f.width, f.height], "key": level.panel.isKeyWindow,
                        "window": level.panel.windowNumber, "pointerX": level.chrome.pointerX.map { $0 + f.minX } as Any,
                        "highlighted": level.rowsView.highlighted as Any,
                        "rowCenters": level.rowsView.rows.indices.map { i -> [CGFloat] in
                            let r = level.rowsView.screenRect(ofRow: i)
                            return [r.midX, r.midY]
                        },
                        "rows": level.rowsView.rows.map { r -> String in
                            switch r.kind {
                            case .separator: return "---"
                            case .header: return "[\(r.title)]"
                            case .item: return (r.mark == .check ? "✓ " : r.mark == .diamond ? "◆ " : "") + r.title
                                + (r.isEnabled ? "" : " (disabled)") + (r.submenu != nil || r.folderPath != nil ? " ▸" : "")
                            }
                        }]
            },
        ]
    }

    /// Keys for the `menu-key` debug command, as the keyboard would send them.
    func debugKey(_ name: String) {
        let codes: [String: UInt16] = ["down": 125, "up": 126, "right": 124, "left": 123, "return": 36, "esc": 53, "space": 49]
        let code = codes[name] ?? 0
        let chars = codes[name] == nil ? name : ""
        if let e = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0,
                                    context: nil, characters: chars, charactersIgnoringModifiers: chars, isARepeat: false, keyCode: code) {
            _ = key(e)
        }
    }

    func debugOption(_ on: Bool) {
        guard on != option, isOpen else { return }
        option = on
        for k in levels.indices { layout(k) }
    }

    /// Chooses the row reached by these titles (opening submenus on the way); with `dry`, only highlights it.
    func debugChoose(_ path: [String], dry: Bool) -> Bool {
        guard isOpen else { return false }
        for (depth, title) in path.enumerated() {
            guard depth < levels.count, let row = levels[depth].rowsView.rows.firstIndex(where: { $0.title == title }) else { return false }
            levels[depth].rowsView.highlighted = row
            if depth == path.count - 1 {
                if !dry { clicked(levels[depth].rowsView, row: row) }
            } else {
                closeLevels(after: depth)
                openSubmenu(depth, row)
            }
        }
        return true
    }
    #endif
}

/// The rows of one menu: drawn, hit-tested and exposed to accessibility as a menu.
final class MenuRowsView: NSView {
    weak var controller: DockMenuController?
    var style: MenuStyle { didSet { needsDisplay = true } }
    var rows: [DockMenuItem] = [] {
        didSet {
            highlighted = nil
            rowElements = nil
            needsDisplay = true
        }
    }
    var highlighted: Int? {
        didSet { if highlighted != oldValue { needsDisplay = true } }
    }
    private var icons: [String: NSImage] = [:]
    private var rowElements: [MenuRowElement]?

    init(style: MenuStyle) {
        self.style = style
        super.init(frame: .zero)
        setAccessibilityElement(true)
        setAccessibilityRole(.menu)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override var isFlipped: Bool { true }
    override var isOpaque: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    private var hasIcons: Bool { rows.contains { $0.iconPath != nil } }
    private var hasSubmenus: Bool { rows.contains { $0.submenu != nil || $0.folderPath != nil } }
    private var textX: CGFloat { MenuStyle.textInset + (hasIcons ? MenuStyle.iconSize + 5 : 0) }

    private func height(of row: DockMenuItem) -> CGFloat {
        row.kind == .separator ? MenuStyle.separatorHeight : MenuStyle.rowHeight
    }

    func rowRect(_ i: Int) -> CGRect {
        var y = MenuStyle.verticalPadding
        for j in 0..<i { y += height(of: rows[j]) }
        return CGRect(x: 0, y: y, width: bounds.width, height: height(of: rows[i]))
    }

    func screenRect(ofRow i: Int) -> CGRect {
        guard let window, i < rows.count else { return .zero }
        return window.convertToScreen(convert(rowRect(i), to: nil))
    }

    func row(at p: NSPoint) -> Int? {
        var y = MenuStyle.verticalPadding
        for (i, r) in rows.enumerated() {
            let h = height(of: r)
            if p.y >= y, p.y < y + h, p.x >= 0, p.x <= bounds.width { return i }
            y += h
        }
        return nil
    }

    /// Sets the highlight and scrolls it into view.
    func highlight(_ row: Int?) {
        highlighted = row
        if let row { scrollToVisible(rowRect(row)) }
    }

    /// The size the rows need: the widest title plus room for marks, icons and submenu arrows.
    func measure() -> CGSize {
        let attrs: [NSAttributedString.Key: Any] = [.font: style.font]
        let widest = rows.map { ($0.title as NSString).size(withAttributes: attrs).width }.max() ?? 0
        let width = min(max(widest + textX + MenuStyle.trailingInset + (hasSubmenus ? MenuStyle.arrowSpace : 0), 120), 460)
        let height = rows.reduce(MenuStyle.verticalPadding * 2) { $0 + height(of: $1) }
        return CGSize(width: ceil(width), height: ceil(height))
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byTruncatingMiddle
        for (i, row) in rows.enumerated() {
            let r = rowRect(i)
            guard r.intersects(dirtyRect) else { continue }
            switch row.kind {
            case .separator:
                ctx.setFillColor(style.separator.cgColor)
                ctx.fill(CGRect(x: 1, y: (r.midY - 0.5).rounded(), width: r.width - 2, height: 1))
            case .header, .item:
                let lit = highlighted == i && row.isSelectable
                if lit {
                    let gradient = NSGradient(starting: style.highlightTop, ending: style.highlightBottom)
                    gradient?.draw(in: r, angle: 90)
                }
                let color = lit ? style.highlightText : (row.isEnabled ? style.text : style.disabledText)
                let attrs: [NSAttributedString.Key: Any] = [.font: style.font, .foregroundColor: color, .paragraphStyle: paragraph]
                let lineHeight = ceil(style.font.ascender - style.font.descender)
                let textY = r.minY + (r.height - lineHeight) / 2
                switch row.mark {
                case .check: ("✓" as NSString).draw(at: NSPoint(x: MenuStyle.markInset, y: textY), withAttributes: attrs)
                case .diamond: ("◆" as NSString).draw(at: NSPoint(x: MenuStyle.markInset, y: textY), withAttributes: attrs)
                case .none: break
                }
                if let path = row.iconPath {
                    let image = icons[path] ?? {
                        let image = NSWorkspace.shared.icon(forFile: path)
                        icons[path] = image
                        return image
                    }()
                    image.draw(in: CGRect(x: MenuStyle.textInset - 2, y: r.midY - MenuStyle.iconSize / 2,
                                          width: MenuStyle.iconSize, height: MenuStyle.iconSize))
                }
                let right = r.maxX - MenuStyle.trailingInset - (hasSubmenus ? MenuStyle.arrowSpace : 0)
                (row.title as NSString).draw(with: CGRect(x: textX, y: textY, width: max(0, right - textX), height: lineHeight),
                                             options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine], attributes: attrs)
                if row.submenu != nil || row.folderPath != nil {
                    // A small solid triangle, as the original drew.
                    let x = r.maxX - 16, y = r.midY
                    ctx.beginPath()
                    ctx.move(to: CGPoint(x: x, y: y - 4.5))
                    ctx.addLine(to: CGPoint(x: x + 6.5, y: y))
                    ctx.addLine(to: CGPoint(x: x, y: y + 4.5))
                    ctx.closePath()
                    ctx.setFillColor(color.cgColor)
                    ctx.fillPath()
                }
            }
        }
    }

    // MARK: Mouse while the menu stays open

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                       owner: self, userInfo: nil))
    }

    override func mouseMoved(with event: NSEvent) { controller?.moved(self, to: convert(event.locationInWindow, from: nil)) }
    override func mouseEntered(with event: NSEvent) { controller?.moved(self, to: convert(event.locationInWindow, from: nil)) }
    override func mouseExited(with event: NSEvent) { controller?.moved(self, to: nil) }
    override func mouseDragged(with event: NSEvent) { controller?.moved(self, to: convert(event.locationInWindow, from: nil)) }
    override func rightMouseDragged(with event: NSEvent) { mouseDragged(with: event) }
    override func mouseDown(with event: NSEvent) {}
    override func rightMouseDown(with event: NSEvent) {}
    override func mouseUp(with event: NSEvent) { controller?.clicked(self, row: row(at: convert(event.locationInWindow, from: nil))) }
    override func rightMouseUp(with event: NSEvent) { mouseUp(with: event) }

    // MARK: Accessibility

    override func accessibilityChildren() -> [Any]? {
        if let rowElements { return rowElements }
        let made = rows.indices.compactMap { i -> MenuRowElement? in
            guard rows[i].kind != .separator else { return nil }
            let e = MenuRowElement(view: self, row: i)
            e.setAccessibilityParent(self)
            e.setAccessibilityRole(.menuItem)
            e.setAccessibilityLabel(rows[i].title)
            e.setAccessibilityEnabled(rows[i].isSelectable)
            if rows[i].mark != .none { e.setAccessibilityValue(rows[i].mark == .check ? "checked" : "minimized") }
            e.setAccessibilityFrameInParentSpace(rowRect(i))
            return e
        }
        rowElements = made
        return made
    }

    fileprivate func pressRow(_ i: Int) { controller?.clicked(self, row: i) }
}

private final class MenuRowElement: NSAccessibilityElement {
    weak var view: MenuRowsView?
    let row: Int

    init(view: MenuRowsView, row: Int) {
        self.view = view
        self.row = row
        super.init()
    }

    override func accessibilityPerformPress() -> Bool {
        view?.pressRow(row)
        return true
    }
}
