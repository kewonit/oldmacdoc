import AppKit
import QuartzCore
import UniformTypeIdentifiers

extension NSPasteboard.PasteboardType {
    static let dockTile = NSPasteboard.PasteboardType("com.kewonit.oldmacdoc.tile")
}

/// Layer-hosting view that draws the shelf and the icons and handles all interaction.
final class DockView: NSView, NSDraggingSource {
    static let trashID = "::trash"

    let model: DockModel
    let settings: SettingsStore
    let icons: IconEngine
    let trash: TrashMonitor
    /// The shelf moved, changed shape or slid (view coordinates; the second value is how far the
    /// dock is slid down for auto-hide). Called inside the frame's transaction, so the blur behind
    /// the glass moves in the same commit as the floor.
    var onShelfChange: ((ShelfGeometry, CGFloat, Float) -> Void)?
    /// Pointer activity the window controller should re-evaluate (hover, auto-hide).
    var onPointerActivity: (() -> Void)?

    final class TileElement: NSAccessibilityElement {
        var onPress: (() -> Void)?
        var onShowMenu: (() -> Void)?
        override func accessibilityPerformPress() -> Bool {
            onPress?()
            return onPress != nil
        }
        override func accessibilityPerformShowMenu() -> Bool {
            guard let onShowMenu else { return false }
            // Not inside the accessibility call: the system menu used with VoiceOver runs until it closes.
            DispatchQueue.main.async(execute: onShowMenu)
            return true
        }
    }

    /// What a menu was opened for.
    enum MenuSubject {
        case app(DockModel.Item)
        case trash
        case separator
        case stack(String)
    }
    static let separatorID = "::separator"

    private final class Tile {
        var item: DockModel.Item?
        let icon = CALayer()
        /// The mirrored bottom of the icon, with its fade and opacity baked in (see ShelfArt).
        let reflection = CALayer()
        /// Darkens the icon (in its own shape) while it's pressed or a drop target.
        let shade = CALayer()
        let shadeMask = CALayer()
        /// The app's badge (its unread count), over the icon's top right corner.
        let badge = CALayer()
        var badgeLabel: String?
        /// For a folder: what its art was last drawn from (display, sort and first items), and when the folder was
        /// last listed for it.
        var stackKey = ""
        var stackStamp = ""
        let shadow = CALayer()
        let indicator = CALayer()
        let element = TileElement()
        var image: CGImage?
        var requested: IconRequest?
        var frame: CGRect = .zero
        var placed = false
        /// The process this tile's launch bounce waits for. Only its id is kept: observing an
        /// NSRunningApplication that quits while it opens (Launchpad does, at once) crashed AppKit.
        var launchPID: pid_t?
        /// Which launch the bounce belongs to, so an earlier launch's timeout can't end a later one.
        var launchToken = 0
        var indicatorKey = ""
        /// What's left of a slide to a new place after a reorder, eased to 0.
        var offset: CGFloat = 0
        var sizeOffset: CGFloat = 0
        /// How much of its place the tile takes (0...1). Arriving apps grow in from 0; leaving ones
        /// shrink to 0 and are then removed, while their neighbours slide along, as on the original.
        var presence: CGFloat = 1
        var presenceTarget: CGFloat = 1
        var leaving: Bool { presenceTarget == 0 }
        var layers: [CALayer] { [icon, reflection, shadow, indicator] }
    }

    // MARK: Layers

    private let root = CALayer()
    /// The shelf (lip, front line and glass floor): one small image whose middle stretches to the
    /// dock's width (`contentsCenter`), so magnifying and sliding never redraw it.
    private let floor = CALayer()
    /// Leopard's "zebra" separator (an image), or Mountain Lion's groove (a dark and a light line).
    private let zebra = CALayer()
    private let grooveDark = CALayer()
    private let grooveLight = CALayer()
    /// Clips the reflections at the front line with its bounds (a rectangle costs nothing to clip to).
    private let reflections = CALayer()
    private let shadows = CALayer()
    private let tileLayer = CALayer()
    private let label = CATextLayer()
    private let labelBackground = CALayer()

    private var tiles: [String: Tile] = [:]
    private var order: [String] = []
    private var look = ShelfLook(style: .clear)
    private var paintKey = ""
    private var zebraImage: CGImage?
    /// Where the separator stands (view coordinates), for its menu.
    private var separatorX: CGFloat?
    /// The original labels: Lucida Grande 14 on a translucent black pill.
    private let labelFont = NSFont(name: "LucidaGrande", size: 14) ?? NSFont.systemFont(ofSize: 14)
    private var labelSizes: [String: CGSize] = [:]

    // MARK: Interaction state

    /// Latest pointer x over the dock, or nil when it's away.
    private var pointerTarget: CGFloat?
    /// Where the pointer was last seen over the dock, to keep the hovered tile right as tiles move.
    private var hoverPoint: NSPoint?
    /// Where the magnification bump is centred; kept while it deflates after the pointer leaves.
    private var pointerX: CGFloat = 0
    /// 0 at rest, 1 fully magnified; eased toward its target by the display link.
    private var magnify: CGFloat = 0
    private var link: CADisplayLink?
    private var lastFrame: CFTimeInterval = 0

    /// Auto-hide slide: 0 = shown, 1 = hidden. It moves at a constant rate toward its target on the
    /// display link and the offset follows a quadratic curve, so hiding accelerates away, showing
    /// settles into place, and reversing mid-slide continues from where it is.
    private var hideProgress: CGFloat = 0
    private var hideTarget: CGFloat = 0
    private var slideOffset: CGFloat = 0
    /// Whether the dock is shown or on its way to being shown.
    var isShown: Bool { hideTarget == 0 && asideTarget == 0 }

    /// Stepping aside while macOS shows its own Dock (Mission Control, App Exposé): 0 = present,
    /// 1 = faded out. Fades out fast so the two docks never overlap, and back in more gently.
    private var asideProgress: CGFloat = 0
    private var asideTarget: CGFloat = 0
    private(set) var reportedOpacity: Float = -1
    private var hovered: String?
    private var pressedID: String?
    private var pressPoint = NSPoint.zero
    private var dragID: String?
    private var dragOutside = false
    private var dragOrder: [String]?
    private var dropTarget: String?
    private var fileDragActive = false
    private var menuOpen = false
    /// The tile whose menu is open (it stays darkened), and what the menu was opened for.
    private var menuTileID: String?
    private var menuSubject: MenuSubject?
    /// The system menu shown instead while VoiceOver runs; it tracks the mouse itself until it closes.
    private var nativeMenuOpen = false
    /// The windows listed in the open menu, to bring one forward.
    private var menuWindows: [AppWindows.Window] = []
    let dockMenu = DockMenuController()
    let stacks = StackController()
    /// The folder whose stack is open (Fan or Grid; a List is a menu).
    private var stackTileID: String?
    private var stackWatchers: [String: DispatchSourceFileSystemObject] = [:]
    private var stackRefresh: [String: DispatchWorkItem] = [:]
    private let badges = BadgeMonitor()
    let strings = DockStrings.system()
    private lazy var appleMenus = AppleDockMenus(strings: strings)
    /// Opens the settings panel (the separator's Dock Settings…).
    var openSettings: (() -> Void)?
    private var launching: Set<String> = []
    private var launchCount = 0
    private var workspaceObservers: [NSObjectProtocol] = []
    private var holdWork: DispatchWorkItem?
    private var labelFade: DispatchWorkItem?
    private var dragFar = false

    /// True while a drag, drop or menu is in progress: the dock must stay up.
    var isBusy: Bool { dragID != nil || fileDragActive || menuOpen || stackTileID != nil || pressedID != nil }
    /// While these last the dock takes the mouse everywhere. An open menu that isn't following a held
    /// button needs only the shelf: a click anywhere else goes where it was aimed (and closes the menu).
    private var capturesPointer: Bool {
        dragID != nil || fileDragActive || pressedID != nil || nativeMenuOpen || (menuOpen && dockMenu.isTracking)
    }

    // MARK: Metrics

    private(set) var shelfRect: CGRect = .zero
    private(set) var shelfGeometry: ShelfGeometry?
    private(set) var reportedOffset: CGFloat = -1
    /// Resting icon size after shrinking to fit the screen.
    private var tileSize: CGFloat = 56
    private var maxScale: CGFloat = 1
    var baseSize: CGFloat { CGFloat(settings.settings.iconSize) }
    /// Where icons stand, above the bottom of the screen.
    private(set) var standY: CGFloat = 20
    /// Room for the largest magnified icon plus its label, or its launch bounce, on any shelf.
    static let maximumHeight: CGFloat = {
        let base = CGFloat(AppSettings.iconSizeRange.upperBound), magnified = CGFloat(AppSettings.magnifiedSizeRange.upperBound)
        let iconBase = ShelfStyle.allCases.map { ShelfLook(style: $0).iconBase }.max() ?? 0.4
        return (iconBase * base + max(magnified + 48, magnified * 1.62 + 8)).rounded()
    }()
    /// Spacing between tiles and the Trash's separator gap, as a share of the icon size.
    private static let spacing: CGFloat = 1, gapFactor: CGFloat = 0.36
    /// The largest icon size at which the dock, with the items it has now, fits across the screen.
    var largestFittingSize: CGFloat {
        let count = CGFloat(max(displayOrder.filter { !(tiles[$0]?.leaving ?? false) }.count, 1))
        return max(16, ((bounds.width * 0.94 - Self.spacing * count) / (count + Self.gapFactor)).rounded(.down))
    }
    private var reduceMotion: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }
    /// How far the dock slides to get completely off screen (resting icons, their shadows and glow).
    private var slideDistance: CGFloat { (standY + tileSize * 1.1 + 12).rounded() }

    init(model: DockModel, settings: SettingsStore, icons: IconEngine, trash: TrashMonitor) {
        self.model = model
        self.settings = settings
        self.icons = icons
        self.trash = trash
        super.init(frame: .zero)
        layer = root
        wantsLayer = true
        buildLayers()
        registerForDraggedTypes([.fileURL, .dockTile])
        setAccessibilityElement(true)
        setAccessibilityRole(.list)
        setAccessibilityLabel("Dock")
        applyStyle()
        reload()
        dockMenu.onChoose = { [weak self] command in self?.run(command) }
        badges.onChange = { [weak self] in self?.updateBadges() }
        badges.wanted = { [weak self] in
            guard let self else { return [:] }
            var wanted: [String: pid_t] = [:]
            for t in self.tiles.values {
                guard let item = t.item, item.isRunning else { continue }
                let key = BadgeMonitor.key(bundleID: item.bundleID, path: item.url.path)
                if let pid = self.model.pids[key] { wanted[key] = pid }
            }
            return wanted
        }
        badges.start()
        stacks.onClose = { [weak self] in self?.stackClosed() }
        dockMenu.loadFolder = { [weak self] path in self?.listRows(URL(fileURLWithPath: path)) ?? [] }
        // Leopard's Downloads stack hopped when a download finished.
        let downloads = DistributedNotificationCenter.default()
        workspaceObservers.append(downloads.addObserver(forName: .init("com.apple.DownloadFileFinished"), object: nil, queue: .main) {
            [weak self] note in
            guard let path = note.object as? String else { return }
            self?.downloadFinished(path)
        })
        dockMenu.onClose = { [weak self] in self?.menuClosed() }
        // A launch bounce ends when its app finishes launching, or quits (or crashes) before it does.
        let ws = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
            workspaceObservers.append(ws.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
                self?.launchEnded(pid: app.processIdentifier)
            })
        }
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    deinit {
        workspaceObservers.forEach {
            NSWorkspace.shared.notificationCenter.removeObserver($0)
            DistributedNotificationCenter.default().removeObserver($0)
        }
        stackWatchers.values.forEach { $0.cancel() }
    }

    override var isFlipped: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        dockMenu.passThroughWindow = window
        stacks.passThroughWindow = window
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        root.setContentsScaleRecursively(window?.backingScaleFactor ?? 2)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                       owner: self, userInfo: nil))
    }

    override func mouseMoved(with event: NSEvent) { onPointerActivity?() }
    override func mouseExited(with event: NSEvent) { onPointerActivity?() }

    override func accessibilityChildren() -> [Any]? { displayOrder.compactMap { id in tiles[id].flatMap { $0.leaving ? nil : $0.element } } }

    // MARK: Building layers

    private func buildLayers() {
        floor.contentsGravity = .resize
        zebra.contentsGravity = .resize
        reflections.masksToBounds = true
        [floor, zebra, grooveDark, grooveLight, reflections, shadows, tileLayer, labelBackground, label].forEach(root.addSublayer)
        labelBackground.backgroundColor = CGColor(gray: 0, alpha: 0.6)
        label.font = labelFont
        label.fontSize = labelFont.pointSize
        label.alignmentMode = .center
        label.foregroundColor = .white
        label.shadowColor = .black
        label.shadowOpacity = 0.9
        label.shadowRadius = 1
        label.shadowOffset = CGSize(width: 1, height: -1)
        label.isHidden = true
        labelBackground.isHidden = true
        root.setContentsScaleRecursively(NSScreen.main?.backingScaleFactor ?? 2)
    }

    func applyStyle() {
        look = ShelfLook(style: settings.settings.shelfStyle)
        paintKey = ""
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        // The new glass crossfades in rather than snapping.
        if window != nil, !reduceMotion { root.add(Self.crossfade(0.18), forKey: "style") }
        zebra.isHidden = look.era != .leopard
        grooveDark.isHidden = look.era == .leopard
        grooveLight.isHidden = look.era == .leopard
        grooveDark.backgroundColor = CGColor(gray: 0, alpha: look.style == .smoke ? 0.35 : 0.22)
        grooveLight.backgroundColor = CGColor(gray: 1, alpha: look.style == .smoke ? 0.15 : 0.35)
        tiles.values.forEach(styleTile)
        CATransaction.commit()
        layoutTiles()
    }

    private static func crossfade(_ duration: CFTimeInterval) -> CATransition {
        let fade = CATransition()
        fade.type = .fade
        fade.duration = duration
        fade.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        return fade
    }

    /// Restyles a tile for the current shelf: its reflection carries the shelf's opacity and fade.
    private func styleTile(_ t: Tile) {
        t.reflection.contents = t.image.flatMap { ShelfArt.reflection(of: $0, look: look) }
        t.indicatorKey = ""
    }

    private func makeTile(_ id: String) -> Tile {
        let t = Tile()
        for l in [t.icon, t.reflection] {
            l.contentsGravity = .resize
            l.minificationFilter = .trilinear
            l.magnificationFilter = .linear
        }
        t.shade.backgroundColor = CGColor(gray: 0, alpha: 0.4)
        t.shadeMask.contentsGravity = .resize
        t.shade.mask = t.shadeMask
        t.shade.isHidden = true
        t.icon.addSublayer(t.shade)
        t.badge.contentsGravity = .resize
        t.badge.isHidden = true
        t.icon.addSublayer(t.badge)
        t.shadow.contentsGravity = .resize
        t.indicator.opacity = 0
        tileLayer.addSublayer(t.icon)
        reflections.addSublayer(t.reflection)
        shadows.addSublayer(t.shadow)
        tileLayer.insertSublayer(t.indicator, at: 0)
        styleTile(t)
        let scale = window?.backingScaleFactor ?? 2
        t.layers.forEach { $0.setContentsScaleRecursively(scale) }
        t.element.setAccessibilityParent(self)
        t.element.setAccessibilityRole(.button)
        t.element.onPress = { [weak self] in self?.activate(id) }
        t.element.onShowMenu = { [weak self] in self?.showMenu(for: id, trigger: .keyboard) }
        tiles[id] = t
        return t
    }

    // MARK: Model sync

    /// Tiles already out of sight when they're removed (dragged off in a puff): they go at once.
    private var vanishing: Set<String> = []

    func reload() {
        // Adding or removing sublayers has a default cross-fade action that would fade the whole
        // icon row between its old and new state (ghosting). Structural changes are made without it:
        // new tiles grow in from nothing and removed ones shrink away, while the rest slide along.
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        let animate = window != nil && !reduceMotion && dragID == nil
        var ids: [String] = []
        for item in model.items {
            let existing = tiles[item.id]
            let t = existing ?? makeTile(item.id)
            if existing == nil, animate { t.presence = 0 }
            t.presenceTarget = 1
            if let old = existing?.item, item.isRunning, !old.isRunning {
                // Relaunched: pick up icon changes from app updates, stop any launch bounce.
                t.requested = nil
                icons.forget(appURL: item.url)
                stopBounce(item.id)
            }
            if item.id == menuTileID, let old = existing?.item, old.isRunning != item.isRunning {
                // Its menu was for an app that has since opened or quit.
                DispatchQueue.main.async { [weak self] in self?.closeMenu() }
            }
            t.item = item
            t.badgeLabel = badge(for: item)
            t.element.setAccessibilityLabel(item.name)
            t.element.setAccessibilityValue(accessibilityValue(item, badge: t.badgeLabel))
            ids.append(item.id)
        }
        let trashTile = tiles[Self.trashID] ?? makeTile(Self.trashID)
        trashTile.element.setAccessibilityLabel("Trash")
        ids.append(Self.trashID)

        // Gone from the model: its light goes out and it shrinks away where it was.
        var merged = ids
        let previous = order
        for (i, id) in previous.enumerated() where !ids.contains(id) {
            guard let t = tiles[id] else { continue }
            if id == menuTileID { DispatchQueue.main.async { [weak self] in self?.closeMenu() } }
            if !animate || vanishing.contains(id) || t.presence == 0 {
                removeTile(id)
                continue
            }
            t.presenceTarget = 0
            t.item?.isRunning = false
            stopBounce(id)
            // Keep its place: just after the nearest tile before it that's still there.
            let at = previous[..<i].last(where: { merged.contains($0) }).flatMap { merged.firstIndex(of: $0) }.map { $0 + 1 } ?? 0
            merged.insert(id, at: min(at, merged.count - 1)) // the Trash stays last
        }
        vanishing.removeAll()
        for id in tiles.keys where !merged.contains(id) { removeTile(id) }
        order = merged
        updateStackWatchers()
        refreshIcons(force: false)
        layoutTiles(animated: window != nil)
    }

    private func removeTile(_ id: String) {
        tiles[id]?.layers.forEach { $0.removeFromSuperlayer() }
        tiles[id] = nil
        order.removeAll { $0 == id }
        launching.remove(id)
        if hovered == id { hovered = nil }
        if pressedID == id { pressedID = nil }
    }

    /// Icons for a changed look that are still being drawn. They're swapped in together, so the row
    /// changes at once instead of icon by icon.
    private final class IconBatch {
        var pending: Int
        var ready: [(id: String, request: IconRequest, result: IconResult)] = []
        var flushed = false
        init(pending: Int) { self.pending = pending }
    }

    func refreshIcons(force: Bool) {
        let s = settings.settings
        var ready: [(Tile, IconResult)] = []
        var restyled: [(String, IconRequest)] = []
        for (id, t) in tiles {
            guard let item = t.item else {
                if t.image == nil { setImage(TrashArt.image(full: trash.isFull), shadow: nil, on: t) }
                continue
            }
            if item.isStack {
                refreshStackArt(id, force: force)
                continue
            }
            let key = settings.overrideKey(for: item)
            let request = IconRequest(appURL: item.url, bundleID: item.bundleID, finish: s.finish,
                                      mode: s.overrides[key]?.mode ?? .retro, customImageURL: settings.customImageURL(for: item))
            guard force || t.requested != request else { continue }
            t.requested = request
            if let hit = icons.cached(request) {
                ready.append((t, hit))
            } else if t.image == nil {
                // A new app: its plain icon until the finished one is ready, then that at once.
                setImage(IconEngine.cgImage(NSWorkspace.shared.icon(forFile: item.url.path), size: 256), shadow: nil, on: t)
                icons.load(request) { [weak self] result in
                    guard let tile = self?.tiles[id], tile.requested == request else { return }
                    self?.setImage(result.image, shadow: result.shadow, on: tile, fade: true)
                }
            } else {
                restyled.append((id, request))
            }
        }
        if !ready.isEmpty { swapIcons(ready) }
        guard !restyled.isEmpty else { return }
        // Wait for the whole row (but not forever: after a moment the rest follow as they finish).
        let batch = IconBatch(pending: restyled.count)
        for (id, request) in restyled {
            icons.load(request) { [weak self] result in
                batch.pending -= 1
                batch.ready.append((id, request, result))
                if batch.flushed || batch.pending == 0 { self?.flush(batch) }
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            guard !batch.flushed else { return }
            batch.flushed = true
            self?.flush(batch)
        }
    }

    private func flush(_ batch: IconBatch) {
        let swaps = batch.ready.compactMap { entry -> (Tile, IconResult)? in
            guard let t = tiles[entry.id], t.requested == entry.request else { return nil }
            return (t, entry.result)
        }
        batch.ready.removeAll()
        if batch.pending == 0 { batch.flushed = true }
        if !swaps.isEmpty { swapIcons(swaps) }
    }

    /// Swaps in new icons with one crossfade for the whole row (three transitions, not three per icon).
    private func swapIcons(_ swaps: [(Tile, IconResult)]) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        if window != nil, !reduceMotion {
            [tileLayer, reflections, shadows].forEach { $0.add(Self.crossfade(0.15), forKey: "swap") }
        }
        for (t, result) in swaps { setImage(result.image, shadow: result.shadow, on: t) }
        CATransaction.commit()
    }

    func trashChanged() {
        if let t = tiles[Self.trashID] { setImage(TrashArt.image(full: trash.isFull), shadow: nil, on: t, fade: true) }
    }

    private func setImage(_ image: CGImage?, shadow: CGImage?, on t: Tile, fade: Bool = false) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        if fade, t.image != nil, !reduceMotion {
            [t.icon, t.reflection, t.shadow].forEach { $0.add(Self.crossfade(0.15), forKey: "swap") }
        }
        t.image = image
        t.icon.contents = image
        t.shadeMask.contents = image
        t.reflection.contents = image.flatMap { ShelfArt.reflection(of: $0, look: look) }
        t.shadow.contents = shadow ?? Self.genericShadow
        CATransaction.commit()
    }

    private static let genericShadow: CGImage? = {
        let ctx = CGContext(data: nil, width: 160, height: 48, bitsPerComponent: 8, bytesPerRow: 640,
                            space: Bitmap.colorSpace, bitmapInfo: Bitmap.bitmapInfo)
        let colors = [CGColor(gray: 0, alpha: 0.7), CGColor(gray: 0, alpha: 0)] as CFArray
        guard let g = CGGradient(colorsSpace: Bitmap.colorSpace, colors: colors, locations: nil) else { return nil }
        ctx?.scaleBy(x: 1, y: 0.3)
        ctx?.drawRadialGradient(g, startCenter: CGPoint(x: 80, y: 80), startRadius: 0, endCenter: CGPoint(x: 80, y: 80),
                                endRadius: 70, options: [])
        return ctx?.makeImage()
    }()

    // MARK: Layout

    private var displayOrder: [String] {
        var ids = dragOrder ?? order
        if dragOutside, let d = dragID { ids.removeAll { $0 == d } }
        return ids
    }

    /// Renders the dock for the current state. Everything moves in one transaction with implicit
    /// animations off, so the floor, its mask, the blur and the icons never drift apart. With
    /// `animated`, icons slide from where they are drawn now to their new places (reorder, apps
    /// arriving or leaving); the display link eases the remaining offset away.
    func layoutTiles(animated: Bool = false) {
        let ids = displayOrder
        guard !ids.isEmpty, bounds.width > 0 else { return }
        // The separator stands before the folders and the Trash, as on the original.
        let trashIndex = ids.firstIndex { tiles[$0]?.item?.isStack == true } ?? ids.firstIndex(of: Self.trashID)
        // Tiles sit about a point apart (icons carry their own padding); the Trash gets a separator gap.
        let spacing = Self.spacing, gapFactor = Self.gapFactor
        tileSize = min(baseSize, largestFittingSize)
        // Relative to the size the icons really have, and none at all with magnification off.
        let magnified = settings.settings.magnification ? max(tileSize, CGFloat(settings.settings.magnifiedSize)) : tileSize
        maxScale = magnified / tileSize
        let s = tileSize
        standY = (look.iconBase * s).rounded()
        // The bump grows and shrinks with `magnify`, around where the pointer is (or last was).
        // Tiles arriving or leaving take part of their place, eased so they start and settle gently.
        let weights = ids.map { id -> CGFloat in
            let p = tiles[id]?.presence ?? 1
            return p * p * (3 - 2 * p)
        }
        let row = RowLayout.make(count: ids.count, baseSize: s, spacing: spacing, gapBefore: trashIndex,
                                 gap: s * gapFactor, centerX: bounds.midX, pointerX: magnify > 0 ? pointerX : nil,
                                 maxScale: 1 + (maxScale - 1) * magnify, effectWidth: s * 3, weights: weights)
        let slide = animated && !reduceMotion
        var shown: [RowLayout.Slot] = []
        for (i, id) in ids.enumerated() {
            let target = row.slots[i]
            guard let t = tiles[id] else { shown.append(target); continue }
            if slide && t.placed {
                t.offset = t.frame.midX - target.center
                t.sizeOffset = t.frame.width - target.size
            }
            shown.append(RowLayout.Slot(center: target.center + t.offset, size: max(1, target.size + t.sizeOffset)))
        }

        // The floor follows the icons as drawn; its ends keep a fixed slant.
        let lip = look.lipHeight(s), front = lip + look.lineHeight(s)
        let top = (look.floorHeight * s).rounded()
        let pad = spacing / 2 + look.backPad * s
        let shelf = ShelfGeometry(lip: lip, top: top, backLeft: shown[0].minX - pad, backRight: shown[shown.count - 1].maxX + pad)
        let scale = window?.backingScaleFactor ?? 2
        let indicator = IndicatorArt.image(era: look.era, size: s, scale: scale)
        let indicatorKey = "\(look.era)-\(s)-\(scale)"
        let indicatorY = look.indicatorY(s)

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        // Slide (quadratic: hiding accelerates away, showing settles in); under Reduce Motion, fade.
        let offset = reduceMotion ? (hideProgress >= 1 ? slideDistance : 0) : (slideDistance * hideProgress * hideProgress).rounded()
        let opacity = Float(reduceMotion ? 1 - hideProgress : 1) * Float(1 - asideProgress)
        if offset != slideOffset || root.sublayerTransform.m42 != -offset {
            slideOffset = offset
            root.sublayerTransform = CATransform3DMakeTranslation(0, -offset, 0)
        }
        if root.opacity != opacity { root.opacity = opacity }
        for (i, id) in ids.enumerated() {
            guard let t = tiles[id] else { continue }
            if t.indicatorKey != indicatorKey, let indicator {
                t.indicator.contents = indicator.image
                t.indicator.bounds = CGRect(origin: .zero, size: indicator.size)
                t.indicatorKey = indicatorKey
            }
            place(t, id: id, slot: shown[i], indicatorY: indicatorY)
            t.placed = true
        }

        // The floor is one stretchable image: only its frame changes from frame to frame.
        let box = CGRect(x: shelf.frontLeft, y: 0, width: shelf.frontRight - shelf.frontLeft, height: top)
        floor.frame = box
        let paint = "\(look.style.rawValue)-\(s)-\(top)-\(scale)"
        if paint != paintKey, let art = ShelfArt.floor(look: look, size: s, top: top, scale: scale) {
            floor.contents = art.image
            floor.contentsScale = scale
            floor.contentsCenter = art.center
            paintKey = paint
        }
        layoutSeparator(shelf, row: RowLayout(slots: shown), trashIndex: trashIndex, size: s, front: front, scale: scale)
        for l in [shadows, tileLayer] where l.frame != bounds { l.frame = bounds }
        // Reflections end at the front line: the container's bounds start there and clip (a plain
        // rectangle), and its coordinates stay the view's, so reflections are placed as everything else.
        let clip = CGRect(x: 0, y: front, width: bounds.width, height: max(0, bounds.height - front))
        if reflections.bounds != clip {
            reflections.bounds = clip
            reflections.position = CGPoint(x: clip.midX, y: clip.midY)
        }
        shelfRect = box
        // Magnification moves the tiles under a resting pointer: hover whatever is under it now.
        if pointerTarget != nil, dragID == nil, !menuOpen, stackTileID == nil, let p = hoverPoint {
            hovered = tileID(at: p)
        }
        updateLabel()
        if shelf != shelfGeometry || offset != reportedOffset || opacity != reportedOpacity {
            shelfGeometry = shelf
            reportedOffset = offset
            reportedOpacity = opacity
            onShelfChange?(shelf, offset, opacity)
        }
        CATransaction.commit()
        if slide { requestFrame() }
    }

    // MARK: Animation

    /// Renders the next frame at the display's refresh, so motion is even no matter how often
    /// pointer events arrive. The link runs only while something is moving.
    private func requestFrame() {
        guard window != nil else {
            layoutTiles()
            return
        }
        if link == nil {
            let l = displayLink(target: self, selector: #selector(step(_:)))
            l.add(to: .main, forMode: .common)
            link = l
        }
        link?.isPaused = false
    }

    #if DEBUG
    /// Set while the `menu` debug command opens a menu "pressed": as if the button were still down.
    private var debugMenuPressed = false
    /// Frame pacing for the `stats` debug command: when each frame was drawn, and how long after the
    /// pointer moved. Recorded only once `stats` has been asked for, and cleared at each report.
    private var statsOn = false
    private var statFrames: [CFTimeInterval] = []
    private var statLatency: [CFTimeInterval] = []
    private var pointerMovedAt: CFTimeInterval?

    func debugStats() -> String {
        statsOn = true
        defer { statFrames.removeAll(); statLatency.removeAll() }
        guard statFrames.count > 2 else { return "frames: \(statFrames.count)" }
        let gaps = zip(statFrames.dropFirst(), statFrames).map { $0 - $1 }
        let period = 1.0 / Double(window?.screen?.maximumFramesPerSecond ?? 60)
        let late = gaps.filter { $0 > period * 1.5 && $0 < 0.25 }.count
        let span = statFrames.last! - statFrames.first!
        let lat = statLatency.sorted()
        func ms(_ v: Double) -> String { String(format: "%.1f", v * 1000) }
        return "frames: \(statFrames.count) over \(ms(span)) ms (\(Int(Double(statFrames.count - 1) / max(span, 0.001))) fps), "
            + "late (>1.5 periods, <250 ms): \(late), pointer→frame median \(lat.isEmpty ? "-" : ms(lat[lat.count / 2])) ms, "
            + "p95 \(lat.isEmpty ? "-" : ms(lat[lat.count * 95 / 100])) ms"
    }
    #endif

    @objc private func step(_ link: CADisplayLink) {
        #if DEBUG
        if statsOn {
            statFrames.append(CACurrentMediaTime())
            if let moved = pointerMovedAt { statLatency.append(CACurrentMediaTime() - moved) }
        }
        pointerMovedAt = nil
        #endif
        let now = link.targetTimestamp
        let dt = lastFrame == 0 ? link.targetTimestamp - link.timestamp : min(max(now - lastFrame, 0), 1.0 / 20)
        lastFrame = now
        let instant = reduceMotion
        // Magnification eases in and out over ~0.18 s; tracking inside the dock is direct.
        let target: CGFloat = pointerTarget == nil ? 0 : 1
        magnify = instant ? target : Self.approach(magnify, target, dt: dt, tau: AutoHide.magnifyTau)
        var settled = magnify == target
        if asideProgress != asideTarget {
            let out = asideTarget > asideProgress
            let step = CGFloat(dt / (out ? AutoHide.stepAsideDuration : AutoHide.stepBackDuration))
            asideProgress = out ? min(asideTarget, asideProgress + step) : max(asideTarget, asideProgress - step)
            if asideProgress != asideTarget { settled = false }
        }
        if hideProgress != hideTarget {
            let hiding = hideTarget > hideProgress
            let duration = instant ? AutoHide.fadeDuration : (hiding ? AutoHide.hideDuration : AutoHide.showDuration)
            let step = CGFloat(dt / duration)
            hideProgress = hiding ? min(hideTarget, hideProgress + step) : max(hideTarget, hideProgress - step)
            if hideProgress != hideTarget { settled = false }
        }
        // Reorder slides settle in ~0.15 s.
        let decay = instant ? 0 : CGFloat(exp(-dt / AutoHide.slideTau))
        for t in tiles.values where t.offset != 0 || t.sizeOffset != 0 {
            t.offset = abs(t.offset * decay) < 0.25 ? 0 : t.offset * decay
            t.sizeOffset = abs(t.sizeOffset * decay) < 0.25 ? 0 : t.sizeOffset * decay
            if t.offset != 0 || t.sizeOffset != 0 { settled = false }
        }
        // Arriving tiles grow in and leaving ones shrink away; those gone are then removed.
        let grow = instant ? 1 : CGFloat(dt / AutoHide.arriveDuration)
        for t in tiles.values where t.presence != t.presenceTarget {
            t.presence = t.presence < t.presenceTarget ? min(t.presenceTarget, t.presence + grow) : max(t.presenceTarget, t.presence - grow)
            if t.presence != t.presenceTarget { settled = false }
        }
        for (id, t) in tiles where t.leaving && t.presence == 0 { removeTile(id) }
        layoutTiles()
        if settled {
            link.isPaused = true
            lastFrame = 0
        }
    }

    private static func approach(_ value: CGFloat, _ target: CGFloat, dt: CFTimeInterval, tau: CFTimeInterval) -> CGFloat {
        let next = target + (value - target) * CGFloat(exp(-dt / tau))
        return abs(next - target) < 0.002 ? target : next
    }

    /// Slides the dock in or out (auto-hide). Can be called mid-slide; it reverses smoothly.
    func setShown(_ shown: Bool, animated: Bool = true) {
        let target: CGFloat = shown ? 0 : 1
        guard target != hideTarget || hideProgress != target else { return }
        hideTarget = target
        if !shown { pointerMoved(nil) }
        if animated && window != nil {
            requestFrame()
        } else {
            hideProgress = target
            layoutTiles()
        }
    }

    /// Fades the dock out while macOS shows its own Dock, and back in once it has gone.
    func setSteppedAside(_ aside: Bool) {
        let target: CGFloat = aside ? 1 : 0
        guard target != asideTarget else { return }
        asideTarget = target
        if aside { pointerMoved(nil) }
        if window != nil {
            requestFrame()
        } else {
            asideProgress = target
            layoutTiles()
        }
    }

    /// Stops the display link (the dock is closing).
    func tearDown() {
        badges.stop()
        link?.invalidate()
        link = nil
    }

    private func layoutSeparator(_ shelf: ShelfGeometry, row: RowLayout, trashIndex: Int?, size s: CGFloat, front: CGFloat,
                                 scale: CGFloat) {
        guard let ti = trashIndex, ti > 0 else {
            zebra.frame = .zero
            grooveDark.bounds = .zero
            grooveLight.bounds = .zero
            separatorX = nil
            return
        }
        let x = (row.slots[ti - 1].maxX + row.slots[ti].minX) / 2
        separatorX = x
        switch look.era {
        case .leopard:
            // An upright image hanging from the back edge, as the original's separator was.
            guard let art = ShelfArt.zebra(size: s, top: shelf.top, front: front, scale: scale) else { return }
            if zebraImage !== art.image {
                zebra.contents = art.image
                zebra.contentsScale = scale
                zebraImage = art.image
            }
            zebra.frame = CGRect(x: (x - art.size.width / 2).rounded(), y: shelf.top - art.size.height,
                                 width: art.size.width, height: art.size.height)
        case .mountainLion:
            // A groove following the floor's perspective, from just below the back edge to just behind
            // the front line: two 1 pt lines, rotated into place rather than redrawn.
            let from = shelf.top - 4.0 / 64 * s, to = front + 5.0 / 64 * s
            let a = CGPoint(x: shelf.perspectiveX(x, from: standY, to: from), y: from)
            let b = CGPoint(x: shelf.perspectiveX(x, from: standY, to: to), y: to)
            Self.place(line: grooveDark, from: a, to: b, dx: -0.5)
            Self.place(line: grooveLight, from: a, to: b, dx: 0.5)
        }
    }

    /// Lays a 1 pt layer along the segment from `a` to `b`, shifted `dx` sideways.
    private static func place(line: CALayer, from a: CGPoint, to b: CGPoint, dx: CGFloat) {
        let v = CGPoint(x: b.x - a.x, y: b.y - a.y)
        line.bounds = CGRect(x: 0, y: 0, width: 1, height: hypot(v.x, v.y))
        line.position = CGPoint(x: (a.x + b.x) / 2 + dx, y: (a.y + b.y) / 2)
        line.setAffineTransform(CGAffineTransform(rotationAngle: atan2(-v.x, v.y)))
    }

    private func place(_ t: Tile, id: String, slot: RowLayout.Slot, indicatorY: CGFloat) {
        let s = slot.size
        // Icons grow up from their base and never cover the front line.
        let f = CGRect(x: slot.minX, y: standY - s * IconNormalizer.bottomMargin, width: s, height: s)
        t.frame = f
        let visible: Float = id == dragID ? 0 : 1
        t.icon.bounds = CGRect(origin: .zero, size: f.size)
        t.icon.position = CGPoint(x: f.midX, y: f.midY)
        t.icon.opacity = visible
        t.shade.frame = t.icon.bounds
        t.shadeMask.frame = t.shade.bounds
        t.shade.isHidden = !(id == pressedID || id == dropTarget || id == menuTileID || id == stackTileID)
        if let label = t.badgeLabel, let image = BadgeArt.image(label, height: Self.badgePixels) {
            // About a third of the icon's height, hanging a little past its top right corner.
            let h = s * 0.36 * CGFloat(image.height) / CGFloat(Self.badgePixels)
            let w = h * CGFloat(image.width) / CGFloat(image.height)
            t.badge.contents = image
            t.badge.frame = CGRect(x: s - w + s * 0.08, y: s - h + s * 0.06, width: w, height: h)
            t.badge.isHidden = false
        } else {
            t.badge.isHidden = true
        }
        // A 1:1 mirror image hanging from the icon's base (already flipped and faded), clipped at the
        // front line by the reflections layer.
        let depth = ShelfArt.reflectionDepth
        t.reflection.bounds = CGRect(x: 0, y: 0, width: s, height: s * depth)
        t.reflection.position = CGPoint(x: f.midX, y: standY - s * depth / 2)
        t.reflection.opacity = visible
        t.shadow.bounds = CGRect(x: 0, y: 0, width: s * 1.05, height: s * 0.32)
        t.shadow.position = CGPoint(x: f.midX, y: standY - s * 0.02)
        t.shadow.opacity = visible * look.shadowOpacity
        // Indicators keep their size while icons magnify.
        t.indicator.position = CGPoint(x: f.midX, y: indicatorY)
        let running = settings.settings.showIndicators && (t.item?.isRunning ?? false)
        let indicatorOpacity: Float = running ? visible : 0
        if t.presence < 1 {
            // Growing in or shrinking away: the light comes and goes with the tile.
            t.indicator.removeAnimation(forKey: "fade")
            t.indicator.opacity = indicatorOpacity * Float(t.presence)
        } else if t.indicator.opacity != indicatorOpacity {
            // Lights fade in and out as apps launch and quit.
            if t.placed && !reduceMotion {
                let fade = CABasicAnimation(keyPath: "opacity")
                fade.fromValue = t.indicator.presentation()?.opacity ?? t.indicator.opacity
                fade.duration = 0.25
                t.indicator.add(fade, forKey: "fade")
            }
            t.indicator.opacity = indicatorOpacity
        }
        t.element.setAccessibilityFrameInParentSpace(f)
    }

    // MARK: Stacks

    /// Opens a folder's stack above its tile: a Fan or a Grid, or a List (a menu of its items).
    private func openStack(_ id: String, as requested: StackView? = nil) {
        guard let window, let t = tiles[id], let item = t.item, let pin = model.stacks.pin(id),
              let screen = window.screen ?? NSScreen.screens.first else { return }
        closeMenu()
        let entries = StackEntry.sorted(StackEntry.contents(of: pin.url), by: pin.sort)
        let top = window.convertPoint(toScreen: convert(NSPoint(x: t.frame.midX, y: t.frame.maxY), to: nil))
        let capacity = StackLayout.fanCapacity(height: screen.visibleFrame.maxY - top.y - 8)
        let view = StackLayout.resolve(requested ?? pin.view, count: entries.count, fanCapacity: capacity)
        pressedID = nil
        if view == .list {
            menuSubject = .stack(id)
            menuTileID = id
            menuOpen = true
            updateLabel()
            layoutTiles()
            var rows = listRows(pin.url, sort: pin.sort, entries: entries)
            rows += [.separator, .item(strings[.openInFinder], .openStackFolder)]
            dockMenu.open(rows, anchorX: top.x, anchorTop: top.y, screen: screen,
                          style: MenuStyle.forShelf(settings.settings.shelfStyle), tracking: false)
            onPointerActivity?()
            return
        }
        stackTileID = id
        hovered = nil
        updateLabel()
        layoutTiles()
        if view == .grid {
            stacks.openGrid(folder: pin.url, title: item.name, entries: entries, sort: pin.sort, anchor: top, screen: screen,
                            strings: strings)
        } else {
            stacks.openFan(folder: pin.url, entries: entries, anchor: top, screen: screen, strings: strings)
        }
        onPointerActivity?()
    }

    private func stackClosed() {
        guard stackTileID != nil else { return }
        stackTileID = nil
        hovered = nil
        layoutTiles()
        onPointerActivity?()
    }

    /// A List stack's rows: files open, folders are submenus loaded when they open.
    private func listRows(_ folder: URL, sort: StackSort? = nil, entries: [StackEntry]? = nil) -> [DockMenuItem] {
        let order = sort ?? StackStore.stack(containing: folder.path, in: model.stacks.pins)?.sort ?? .name
        let shown = entries ?? StackEntry.sorted(StackEntry.contents(of: folder), by: order)
        guard !shown.isEmpty else { return [.header("No Items")] }
        return shown.map { entry in
            var row = DockMenuItem.item(entry.name, .openFile(entry.url.path))
            row.iconPath = entry.url.path
            if entry.isFolder { row.folderPath = entry.url.path }
            return row
        }
    }

    /// Draws a folder's tile when what it shows has changed: its first items (as a stack) or its icon.
    private func refreshStackArt(_ id: String, force: Bool) {
        guard let t = tiles[id], let pin = model.stacks.pin(id) else { return }
        // Listing a big folder (Downloads) isn't free: only when it or the stack's settings have changed. A folder's
        // modification date moves whenever something is added, removed or renamed in it.
        let modified = (try? pin.url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)?.timeIntervalSince1970 ?? 0
        let stamp = "\(pin.display)-\(pin.sort)-\(modified)"
        guard force || stamp != t.stackStamp || t.image == nil else { return }
        t.stackStamp = stamp
        let entries = pin.display == .stack ? Array(StackEntry.sorted(StackEntry.contents(of: pin.url), by: pin.sort).prefix(3)) : []
        let key = "\(pin.display)-\(pin.sort)-" + entries.map(\.url.path).joined(separator: "|")
        guard force || key != t.stackKey || t.image == nil else { return }
        t.stackKey = key
        setImage(StackArt.image(folder: pin.url, entries: entries, display: pin.display), shadow: nil, on: t, fade: t.image != nil)
    }

    /// Watches each folder in the dock, so its tile follows what's added to it.
    private func updateStackWatchers() {
        let ids = Set(tiles.values.compactMap { $0.item?.stackID })
        for (id, source) in stackWatchers where !ids.contains(id) {
            source.cancel()
            stackWatchers[id] = nil
        }
        for id in ids where stackWatchers[id] == nil {
            guard let pin = model.stacks.pin(id) else { continue }
            let fd = Darwin.open(pin.path, O_EVTONLY)
            guard fd >= 0 else { continue }
            let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: [.write, .rename, .delete], queue: .main)
            source.setEventHandler { [weak self, weak source] in
                if let events = source?.data, !events.isDisjoint(with: [.delete, .rename]) {
                    // The folder itself went or moved: stop watching what was there. The dock is rebuilt (a missing
                    // folder's tile goes until it's back), and watching starts again on what's at the path now.
                    source?.cancel()
                    self?.stackWatchers[id] = nil
                    self?.model.rebuild()
                    return
                }
                // A burst of changes (a download, a copy) redraws once it settles.
                self?.stackRefresh[id]?.cancel()
                let work = DispatchWorkItem { [weak self] in self?.refreshStackArt(id, force: false) }
                self?.stackRefresh[id] = work
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: work)
            }
            source.setCancelHandler { Darwin.close(fd) }
            source.resume()
            stackWatchers[id] = source
        }
    }

    /// A finished download lands in a folder in the dock: that stack hops once.
    private func downloadFinished(_ path: String) {
        let folder = URL(fileURLWithPath: path).deletingLastPathComponent().standardizedFileURL.path
        guard let id = model.stacks.pins.first(where: { $0.path == folder })?.id, let t = tiles[id], !reduceMotion else { return }
        refreshStackArt(id, force: false)
        let hop = CAKeyframeAnimation(keyPath: "transform.translation.y")
        hop.values = [0, t.frame.height * 0.45, 0]
        hop.keyTimes = [0, 0.5, 1]
        hop.timingFunctions = [CAMediaTimingFunction(controlPoints: 0.25, 0.46, 0.45, 0.94),
                               CAMediaTimingFunction(controlPoints: 0.55, 0.085, 0.68, 0.53)]
        hop.duration = 0.5
        t.icon.add(hop, forKey: "hop")
    }

    static func isFolder(_ url: URL) -> Bool {
        let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isPackageKey])
        return values?.isDirectory == true && values?.isPackage != true
    }

    /// Files dropped on a folder go into it (off the main thread); a name already there beeps.
    static func file(_ urls: [URL], into folder: URL, copy: Bool) {
        DispatchQueue.global(qos: .userInitiated).async {
            let failed = StackFiling.file(urls, into: folder, copy: copy).contains { !$0.value }
            if failed { DispatchQueue.main.async { NSSound.beep() } }
        }
    }

    #if DEBUG
    /// Debug hook: open the stack named `name` (its folder's name) as a Fan, Grid or List.
    func debugStack(_ name: String, view: StackView?) {
        guard let id = tiles.first(where: { $0.value.item?.isStack == true && $0.value.item?.name == name })?.key else { return }
        openStack(id, as: view)
    }

    func debugStackState() -> [String: Any] { stacks.debugState() }

    /// Debug hook: the same as dropping `urls` on the dock at `x` (at icon height).
    func debugDrop(_ urls: [URL], x: CGFloat) {
        _ = drop(urls, at: NSPoint(x: x, y: standY + tileSize / 2))
    }
    #endif

    // MARK: Badges

    /// Badges are drawn once per label at this height in pixels and scaled with the icon.
    private static let badgePixels = 96

    private func badge(for item: DockModel.Item) -> String? {
        item.isRunning ? badges.labels[BadgeMonitor.key(bundleID: item.bundleID, path: item.url.path)] : nil
    }

    private func accessibilityValue(_ item: DockModel.Item, badge: String?) -> String? {
        var parts: [String] = []
        if item.isRunning { parts.append("running") }
        if let badge { parts.append(badge.isEmpty ? "badge" : "badge \(badge)") }
        return parts.isEmpty ? nil : parts.joined(separator: ", ")
    }

    private func updateBadges() {
        for t in tiles.values {
            guard let item = t.item else { continue }
            let label = badge(for: item)
            guard label != t.badgeLabel else { continue }
            t.badgeLabel = label
            t.element.setAccessibilityValue(accessibilityValue(item, badge: label))
        }
        layoutTiles()
    }

    private func updateLabel() {
        guard let id = hovered, dragID == nil, !menuOpen, stackTileID == nil, let t = tiles[id] else {
            hideLabel(linger: dragID == nil && !menuOpen && stackTileID == nil)
            return
        }
        labelFade?.cancel()
        labelFade = nil
        label.opacity = 1
        labelBackground.opacity = 1
        let name = t.item?.name ?? "Trash"
        let text = labelSizes[name] ?? {
            let size = (name as NSString).size(withAttributes: [.font: labelFont])
            let rounded = CGSize(width: ceil(size.width), height: ceil(size.height))
            labelSizes[name] = rounded
            return rounded
        }()
        // A pill with 5 × 12 pt padding, about 10 pt above the icon.
        let w = text.width + 24, h = text.height + 10
        let x = min(max(4, t.frame.midX - w / 2), bounds.width - w - 4)
        let y = min(t.frame.maxY + 10, bounds.height - h - 2)
        labelBackground.cornerRadius = h / 2
        labelBackground.frame = CGRect(x: x, y: y, width: w, height: h)
        label.frame = CGRect(x: x, y: y + 4, width: w, height: text.height + 2)
        if (label.string as? String) != name { label.string = name }
        label.isHidden = false
        labelBackground.isHidden = false
    }

    /// The original Dock keeps the last label up for about 250 ms after the pointer leaves, then fades it.
    private func hideLabel(linger: Bool) {
        guard !label.isHidden, labelFade == nil else { return }
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.labelFade = nil
            CATransaction.begin()
            CATransaction.setAnimationDuration(linger ? 0.2 : 0)
            CATransaction.setCompletionBlock { [weak self] in
                guard let self, self.label.opacity == 0 else { return }
                self.label.isHidden = true
                self.labelBackground.isHidden = true
            }
            self.label.opacity = 0
            self.labelBackground.opacity = 0
            CATransaction.commit()
        }
        labelFade = work
        DispatchQueue.main.asyncAfter(deadline: .now() + (linger ? 0.25 : 0), execute: work)
    }

    // MARK: Hit testing and hover

    private func tileID(at p: NSPoint) -> String? {
        guard p.y >= 0 else { return nil }
        let slop = tileSize * 0.06
        for id in displayOrder where id != dragID {
            guard let t = tiles[id], !t.leaving else { continue }
            let f = t.frame
            if p.x >= f.minX - slop, p.x <= f.maxX + slop, p.y <= f.maxY { return id }
        }
        return nil
    }

    /// The area that should receive mouse events (grows while magnified).
    func isInteractive(_ p: NSPoint) -> Bool {
        if capturesPointer { return true }
        guard isShown else { return false }
        guard p.x >= shelfRect.minX, p.x <= shelfRect.maxX, p.y >= 0 else { return false }
        let magnified = pointerTarget != nil || magnify > 0.01
        let height = magnified ? standY + tileSize * maxScale + 8 : standY + tileSize + 4
        return p.y <= height
    }

    /// Hover position from the window controller (nil when the pointer is away).
    func pointerMoved(_ p: NSPoint?) {
        guard dragID == nil, !menuOpen, stackTileID == nil else { return }
        let newHover = p.flatMap { tileID(at: $0) }
        if p?.x == pointerTarget, newHover == hovered { return }
        pointerTarget = p?.x
        hoverPoint = p
        if let x = p?.x { pointerX = x }
        hovered = newHover
        #if DEBUG
        if pointerMovedAt == nil { pointerMovedAt = CACurrentMediaTime() }
        #endif
        requestFrame()
    }

    /// The first `count` apps as the dock shows them (finished icons, lit if running and lights are
    /// on), for the settings panel's pictures of each shelf.
    func previewItems(count: Int) -> [ShelfPreview.Item] {
        let lights = settings.settings.showIndicators
        return displayOrder.lazy.compactMap { id -> ShelfPreview.Item? in
            guard let t = self.tiles[id], !t.leaving, let item = t.item, let image = t.image else { return nil }
            return ShelfPreview.Item(image: image, lit: lights && item.isRunning)
        }.prefix(count).map { $0 }
    }

    #if DEBUG
    /// Debug hook: show the pressed state on the tile at `x` (nil clears it).
    func debugPress(at x: CGFloat?) {
        pressedID = x.flatMap { tileID(at: NSPoint(x: $0, y: standY + 4)) }
        layoutTiles()
    }

    /// Debug hook: open the menu of the tile at `x`, and close it again after `seconds`.
    func debugMenu(at x: CGFloat, seconds: TimeInterval) {
        showMenu(at: NSPoint(x: x, y: standY + 4), trigger: .keyboard)
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { [weak self] in self?.closeMenu() }
    }

    /// Debug hook: open the menu of the tile with this id (`::separator` for the separator), as a
    /// right-click would (`press`: the button stays down until `menu-release`) or left open (`sticky`).
    func debugMenu(id: String, pressed: Bool) {
        debugMenuPressed = pressed
        defer { debugMenuPressed = false }
        showMenu(for: id, trigger: pressed ? .rightClick : .keyboard)
    }

    /// Debug hook: a description of the dock's menu state, for the `dump` command.
    func debugMenuState() -> [String: Any] {
        var state = dockMenu.debugState()
        state["menuTile"] = menuTileID as Any
        state["busy"] = isBusy
        state["capturesPointer"] = capturesPointer
        state["shown"] = isShown
        state["separatorX"] = separatorX as Any
        state["appleMenuOpens"] = appleMenus.opens
        state["tiles"] = displayOrder.compactMap { id -> [String: Any]? in
            guard let t = tiles[id] else { return nil }
            return ["id": id, "x": t.frame.midX, "running": t.item?.isRunning ?? false, "name": t.item?.name ?? "Trash",
                    "art": t.stackKey, "badge": t.badgeLabel as Any]
        }
        return state
    }

    /// Debug hook: click the tile with this id (a bundle id, or `::trash`), as a plain click would.
    func debugClick(_ id: String) {
        activate(id)
    }

    /// Debug hook: play the removal puff above the shelf at `x`.
    func debugPoof(at x: CGFloat) {
        guard let window else { return }
        Poof.show(at: NSPoint(x: window.frame.minX + x, y: window.frame.minY + 200), iconSize: tileSize)
    }
    #endif

    // MARK: Mouse

    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        if dockMenu.isOpen || stacks.isOpen {
            // A click on the dock while a menu or stack is open closes it, and does nothing else, as with any menu.
            closeMenu()
            if event.modifierFlags.contains(.control) { showMenu(at: p, trigger: .controlClick) }
            return
        }
        if event.modifierFlags.contains(.control) { showMenu(at: p, trigger: .controlClick); return }
        pressedID = tileID(at: p)
        pressPoint = p
        layoutTiles()
        // Click and hold opens the menu, as in Leopard's Dock.
        holdWork?.cancel()
        if let id = pressedID {
            let work = DispatchWorkItem { [weak self] in
                guard let self, self.pressedID == id, self.dragID == nil else { return }
                // The icon that was pressed, wherever it is now (the row may have moved meanwhile).
                self.showMenu(for: id, trigger: .hold)
            }
            holdWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + AutoHide.holdForMenu, execute: work)
        }
    }

    override func mouseDragged(with event: NSEvent) {
        if dockMenu.isOpen, dockMenu.isTracking {
            // The menu opened under a held button (click and hold, Control-click): it follows the drag.
            dockMenu.hover(at: screenPoint(event))
            return
        }
        let p = convert(event.locationInWindow, from: nil)
        guard let id = pressedID, dragID == nil, id != Self.trashID, model.canMove(id),
              hypot(p.x - pressPoint.x, p.y - pressPoint.y) > 6 else { return }
        holdWork?.cancel()
        beginDrag(id, event: event)
    }

    override func rightMouseDragged(with event: NSEvent) {
        if dockMenu.isOpen, dockMenu.isTracking { dockMenu.hover(at: screenPoint(event)) }
    }

    override func rightMouseUp(with event: NSEvent) {
        if dockMenu.isOpen, dockMenu.isTracking { dockMenu.release(at: screenPoint(event)) }
    }

    private func screenPoint(_ event: NSEvent) -> NSPoint {
        window?.convertPoint(toScreen: event.locationInWindow) ?? NSEvent.mouseLocation
    }

    override func mouseUp(with event: NSEvent) {
        holdWork?.cancel()
        if dockMenu.isOpen, dockMenu.isTracking {
            dockMenu.release(at: screenPoint(event))
            return
        }
        guard let id = pressedID else { return }
        pressedID = nil
        layoutTiles()
        guard dragID == nil, tileID(at: convert(event.locationInWindow, from: nil)) == id else { return }
        let flags = event.modifierFlags.intersection([.command, .option])
        guard let item = tiles[id]?.item else { activate(id); return }
        if item.isStack {
            // A folder: Command shows it in Finder; any other click opens it (no apps are hidden).
            if flags == .command { NSWorkspace.shared.activateFileViewerSelecting([item.url]) } else { openStack(id) }
            return
        }
        switch flags {
        case .command:
            NSWorkspace.shared.activateFileViewerSelecting([item.url])
        case .option:
            // Switch to the app and hide the one you were in.
            let previous = NSWorkspace.shared.frontmostApplication
            activate(id)
            if let previous, previous != model.runningApplication(for: item) { previous.hide() }
        case [.command, .option]:
            // Switch to the app and hide all the others.
            activate(id)
            let target = model.runningApplication(for: item)
            for app in NSWorkspace.shared.runningApplications where app.activationPolicy == .regular && app != target
                && app.processIdentifier != ProcessInfo.processInfo.processIdentifier {
                app.hide()
            }
        default:
            activate(id)
        }
    }

    override func rightMouseDown(with event: NSEvent) {
        // Right-clicking again (on this icon or another) opens that icon's menu afresh.
        closeMenu()
        showMenu(at: convert(event.locationInWindow, from: nil), trigger: .rightClick)
    }

    private func activate(_ id: String) {
        if id == Self.trashID { trash.open(); return }
        if tiles[id]?.item?.isStack == true { openStack(id); return }
        guard let item = tiles[id]?.item, !launching.contains(id) else { return }
        if !item.isRunning {
            // Apps that never take a place in the Dock (Launchpad, Mission Control) open without a
            // bounce, as in Apple's Dock: they'd never show as running to end it.
            if AppBundleInfo.showsInDock(Bundle(url: item.url)?.infoDictionary) { startBounce(id) }
        } else if let app = model.runningApplication(for: item) {
            // Bring it forward straight away, with all its windows, as the Dock does. The open below
            // still sends the "reopen" that brings minimized windows back; it goes through
            // LaunchServices and takes longer.
            app.activate(options: [.activateAllWindows])
        }
        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        // For a running app this sends the same "reopen" Apple's Dock does, so minimized windows come back.
        NSWorkspace.shared.openApplication(at: item.url, configuration: config) { [weak self] app, error in
            DispatchQueue.main.async {
                guard let self, self.launching.contains(id) || error != nil else { return }
                if error != nil {
                    self.stopBounce(id)
                    NSSound.beep()
                } else if let app, !app.isTerminated, !app.isFinishedLaunching {
                    // Still opening: the workspace notifications end the bounce (see `launchEnded`).
                    self.tiles[id]?.launchPID = app.processIdentifier
                } else {
                    // Already open, or already gone (an app that quits as soon as it opens).
                    self.stopBounce(id)
                }
            }
        }
    }

    /// The app with this process id finished launching, or quit before it did.
    private func launchEnded(pid: pid_t) {
        for (id, t) in tiles where t.launchPID == pid { stopBounce(id) }
    }

    private func startBounce(_ id: String) {
        guard let t = tiles[id] else { return }
        launching.insert(id)
        launchCount += 1
        let token = launchCount
        t.launchToken = token
        DispatchQueue.main.asyncAfter(deadline: .now() + 15) { [weak self] in
            guard let self, self.tiles[id]?.launchToken == token else { return }
            self.stopBounce(id)
        }
        guard !reduceMotion else { return }
        let bounce = CAKeyframeAnimation(keyPath: "transform.translation.y")
        bounce.values = [0, t.frame.height * 0.6, 0]
        bounce.keyTimes = [0, 0.5, 1]
        // Quadratic ease-out going up and ease-in coming down: a parabolic hop.
        bounce.timingFunctions = [CAMediaTimingFunction(controlPoints: 0.25, 0.46, 0.45, 0.94),
                                  CAMediaTimingFunction(controlPoints: 0.55, 0.085, 0.68, 0.53)]
        bounce.duration = 0.6
        bounce.repeatCount = .infinity
        t.icon.add(bounce, forKey: "bounce")
    }

    private func stopBounce(_ id: String) {
        guard launching.remove(id) != nil, let t = tiles[id] else { return }
        t.launchPID = nil
        // Let the current hop finish instead of snapping down mid-air.
        guard let bounce = t.icon.animation(forKey: "bounce") else { return }
        let elapsed = t.icon.convertTime(CACurrentMediaTime(), from: nil) - bounce.beginTime
        let remaining = bounce.duration - elapsed.truncatingRemainder(dividingBy: bounce.duration)
        DispatchQueue.main.asyncAfter(deadline: .now() + remaining) { [weak t] in t?.icon.removeAnimation(forKey: "bounce") }
    }

    // MARK: Dragging icons (reorder / remove)

    private func beginDrag(_ id: String, event: NSEvent) {
        guard let t = tiles[id] else { return }
        let pb = NSPasteboardItem()
        pb.setString(id, forType: .dockTile)
        let item = NSDraggingItem(pasteboardWriter: pb)
        let image = t.image.map { NSImage(cgImage: $0, size: t.frame.size) } ?? NSImage(size: t.frame.size)
        item.setDraggingFrame(t.frame, contents: image)
        // Anything still shrinking away goes now, so the drag works on the dock as it stands.
        for other in order where tiles[other]?.leaving == true { removeTile(other) }
        dragID = id
        dragOutside = false
        dragOrder = order
        pressedID = nil
        hovered = nil
        let session = beginDraggingSession(with: [item], event: event, source: self)
        session.animatesToStartingPositionsOnCancelOrFail = false
        layoutTiles(animated: true)
    }

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        context == .withinApplication ? .move : [.move, .delete]
    }

    func draggingSession(_ session: NSDraggingSession, movedTo screenPoint: NSPoint) {
        guard let id = dragID, let window else { return }
        let p = convert(window.convertPoint(fromScreen: screenPoint), from: nil)
        let far = p.y > standY + tileSize * maxScale + 24 || p.x < shelfRect.minX - tileSize || p.x > shelfRect.maxX + tileSize
        dragFar = far
        let item = tiles[id]?.item
        // Only pinned apps that aren't running go up in a puff; running apps slide back.
        let poofs = model.canRemove(id) && (item?.isPinned ?? false) && !(item?.isRunning ?? false)
        if far && !poofs { return }
        if far && poofs {
            if !dragOutside {
                dragOutside = true
                pointerTarget = nil
                NSCursor.disappearingItem.set()
                layoutTiles(animated: true)
            }
            return
        }
        if dragOutside { NSCursor.arrow.set() }
        dragOutside = false
        // The gap takes the slot of whatever is under the pointer (the displayed layout already
        // contains the gap), so moving back over the old spot moves the icon back.
        let current = (dragOrder ?? order).filter { $0 != Self.trashID }
        var slot = current.firstIndex(of: id) ?? 0
        let half = tileSize * 0.06
        if let first = current.first.flatMap({ tiles[$0]?.frame }), p.x < first.minX {
            slot = 0
        } else if let last = current.last.flatMap({ tiles[$0]?.frame }), p.x > last.maxX {
            slot = current.count - 1
        } else if let hit = current.firstIndex(where: { other in
            guard let f = tiles[other]?.frame else { return false }
            return p.x >= f.minX - half && p.x < f.maxX + half
        }) {
            slot = hit
        }
        var ids = current.filter { $0 != id }
        // Apps stay among the kept apps, folders among the folders.
        let isStack = { (other: String) in self.tiles[other]?.item?.isStack ?? false }
        let kept = ids.filter { !isStack($0) && (tiles[$0]?.item?.isPinned ?? false) }.count
        let apps = ids.filter { !isStack($0) }.count
        ids.insert(id, at: DockSections.clamp(slot, isStack: isStack(id), keptApps: kept, apps: apps, stacks: ids.count - apps))
        ids.append(Self.trashID)
        pointerTarget = p.x
        pointerX = p.x
        let changed = ids != dragOrder
        dragOrder = ids
        layoutTiles(animated: changed)
        requestFrame()
    }

    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        guard let id = dragID else { return }
        let removed = dragOutside
        let releasedFar = dragFar
        let final = dragOrder
        let item = tiles[id]?.item
        dragID = nil
        dragOrder = nil
        dragOutside = false
        dragFar = false
        NSCursor.arrow.set()
        if removed {
            Poof.show(at: screenPoint, iconSize: tileSize)
            vanishing.insert(id) // already out of the row: it goes with the puff, it doesn't shrink
            model.setPinned(id, false)
        } else {
            if item?.isStack == true {
                let folders = (final ?? order).filter { tiles[$0]?.item?.isStack == true }
                if let index = folders.firstIndex(of: id) { model.moveStack(id, to: index) }
            } else if let final, let index = final.firstIndex(of: id) {
                model.place(id, at: index)
            }
            // A running app dragged off stays until it quits.
            if releasedFar, item?.isRunning == true, item?.isPinned == true, model.canRemove(id) { model.setPinned(id, false) }
        }
        reload()
        onPointerActivity?()
    }

    // MARK: Dropping files (Trash, open with app, add apps, custom icons)

    private func fileURLs(_ info: NSDraggingInfo) -> [URL] {
        info.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
    }

    private func isImage(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.contentTypeKey]).contentType)?.conforms(to: .image) ?? false
    }

    private func isOwnDrag(_ info: NSDraggingInfo) -> Bool { (info.draggingSource as AnyObject?) === self }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation { draggingUpdated(sender) }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        if isOwnDrag(sender) { return .move }
        let p = convert(sender.draggingLocation, from: nil)
        let urls = fileURLs(sender)
        guard !urls.isEmpty else { return [] }
        fileDragActive = true
        let target = tileID(at: p)
        var op: NSDragOperation = []
        if target == Self.trashID {
            op = .generic
        } else if let target, let item = tiles[target]?.item {
            if item.isStack {
                // Into the folder: moved, or copied with Option, from another disk, or when the source only lends a copy.
                op = Self.folderDropOperation(sender.draggingSourceOperationMask)
            } else {
                op = NSEvent.modifierFlags.contains(.option) && urls.count == 1 && isImage(urls[0]) ? .copy : .generic
            }
        } else if urls.allSatisfy({ $0.pathExtension == "app" || Self.isFolder($0) }) {
            op = .copy
        }
        let newTarget = op.isEmpty ? nil : target
        if pointerTarget != p.x || newTarget != dropTarget || hovered != target {
            dropTarget = newTarget
            pointerTarget = p.x
            pointerX = p.x
            hoverPoint = p
            hovered = target
            requestFrame()
        }
        return op
    }

    override func draggingExited(_ sender: NSDraggingInfo?) { endFileDrag() }
    override func draggingEnded(_ sender: NSDraggingInfo) { endFileDrag() }

    private func endFileDrag() {
        guard fileDragActive else { return }
        fileDragActive = false
        dropTarget = nil
        layoutTiles()
        onPointerActivity?()
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        if isOwnDrag(sender) { return true }
        defer { endFileDrag() }
        return drop(fileURLs(sender), at: convert(sender.draggingLocation, from: nil), allowed: sender.draggingSourceOperationMask)
    }

    /// What dropping on a folder does: move when the source allows it and Option isn't held, else copy.
    private static func folderDropOperation(_ allowed: NSDragOperation) -> NSDragOperation {
        if allowed.contains(.move), !NSEvent.modifierFlags.contains(.option) { return .move }
        if allowed.contains(.copy) { return .copy }
        return allowed.contains(.generic) ? .move : []
    }

    /// Files dropped at `p`: into the Trash, onto an app (opened with it) or a folder (filed into it), or
    /// between icons (apps and folders join the dock).
    private func drop(_ urls: [URL], at p: NSPoint, allowed: NSDragOperation = [.copy, .move]) -> Bool {
        guard !urls.isEmpty else { return false }
        let target = tileID(at: p)
        if target == Self.trashID {
            trash.trash(urls)
            return true
        }
        if let target, let item = tiles[target]?.item {
            if item.isStack {
                let operation = Self.folderDropOperation(allowed)
                guard !operation.isEmpty else { return false }
                Self.file(urls, into: item.url, copy: operation == .copy)
                return true
            }
            if NSEvent.modifierFlags.contains(.option), urls.count == 1, isImage(urls[0]) {
                setCustomIcon(urls[0], for: item)
            } else {
                NSWorkspace.shared.open(urls, withApplicationAt: item.url, configuration: NSWorkspace.OpenConfiguration())
            }
            return true
        }
        let apps = urls.filter { $0.pathExtension == "app" }
        let folders = urls.filter { $0.pathExtension != "app" && Self.isFolder($0) }
        guard !apps.isEmpty || !folders.isEmpty else { return false }
        // Folders join the folders, nearest where they were dropped.
        let shownStacks = order.filter { tiles[$0]?.item?.isStack == true && !(tiles[$0]?.leaving ?? true) }
        var stackIndex = shownStacks.firstIndex { p.x < (tiles[$0]?.frame.midX ?? 0) } ?? shownStacks.count
        for folder in folders {
            model.addStack(folder: folder, at: stackIndex)
            stackIndex += 1
        }
        let present = order.filter { !(tiles[$0]?.leaving ?? true) }
        var index = present.firstIndex { p.x < (tiles[$0]?.frame.midX ?? 0) } ?? present.count
        for app in apps {
            model.insert(appURL: app, at: index)
            index += 1
        }
        return true
    }

    // MARK: Context menu

    /// Opens the menu for what's at `p`: an icon, or the separator.
    private func showMenu(at p: NSPoint, trigger: MenuTracking.Trigger) {
        if let id = tileID(at: p) {
            showMenu(for: id, trigger: trigger)
        } else if let x = separatorX, abs(p.x - x) <= max(8, tileSize * Self.gapFactor / 2), p.y >= 0, p.y <= standY + tileSize {
            showMenu(for: Self.separatorID, trigger: trigger)
        }
    }

    /// Opens the menu of the tile `id` (or the separator) above it, pointing at it.
    func showMenu(for id: String, trigger: MenuTracking.Trigger) {
        guard let window, !nativeMenuOpen else { return }
        let subject: MenuSubject
        let anchor: CGRect
        if id == Self.separatorID {
            guard let x = separatorX else { return }
            subject = .separator
            anchor = CGRect(x: x, y: standY, width: 0, height: tileSize)
        } else {
            guard let t = tiles[id], !t.leaving else { return }
            anchor = t.frame
            subject = t.item.map { $0.isStack ? MenuSubject.stack($0.id) : .app($0) } ?? .trash
        }
        guard let screen = window.screen ?? NSScreen.screens.first else { return }
        closeMenu()
        holdWork?.cancel()
        pressedID = nil
        menuSubject = subject
        let items = menuItems(for: subject)
        guard !items.isEmpty else { return }
        menuTileID = id == Self.separatorID ? nil : id
        menuOpen = true
        updateLabel()
        layoutTiles()
        if NSWorkspace.shared.isVoiceOverEnabled {
            showNativeMenu(items, anchor: anchor)
            return
        }
        let top = window.convertPoint(toScreen: convert(NSPoint(x: anchor.midX, y: anchor.maxY), to: nil))
        var tracking = trigger != .keyboard && NSEvent.pressedMouseButtons != 0
        #if DEBUG
        if debugMenuPressed { tracking = true }
        #endif
        dockMenu.open(items, anchorX: top.x, anchorTop: top.y, screen: screen,
                  style: MenuStyle.forShelf(settings.settings.shelfStyle), tracking: tracking)
        onPointerActivity?()
    }

    /// With VoiceOver, the same menu as a system menu, which VoiceOver reads and drives.
    private func showNativeMenu(_ items: [DockMenuItem], anchor: CGRect) {
        let native = NativeMenu { [weak self] in self?.run($0) }
        let nsMenu = native.make(items)
        nativeMenuOpen = true
        onPointerActivity?()
        let size = nsMenu.size
        nsMenu.popUp(positioning: nil, at: NSPoint(x: anchor.midX - size.width / 2, y: anchor.maxY + 8 + size.height), in: self)
        withExtendedLifetime(native) {}
        nativeMenuOpen = false
        menuClosed()
    }

    /// The pointer moved (screen coordinates): an open menu or stack follows it.
    func popoverPointerMoved(_ p: NSPoint) {
        if dockMenu.isOpen { dockMenu.hover(at: p) }
        if stacks.isOpen { stacks.pointerMoved(to: p) }
    }

    /// Closes the menu, if one is open. The window controller calls this when the dock steps aside or hides.
    func closeMenu() {
        if dockMenu.isOpen { dockMenu.close() }
        if stacks.isOpen { stacks.close() }
    }

    private func menuClosed() {
        guard menuOpen else { return }
        menuOpen = false
        menuTileID = nil
        // Hover and the label come back where the pointer is now, without waiting for it to move.
        hovered = nil
        layoutTiles()
        onPointerActivity?()
    }

    private func menuItems(for subject: MenuSubject) -> [DockMenuItem] {
        switch subject {
        case .app(let item): return appMenuItems(item)
        case .trash: return DockMenuBuilder.trash(isFull: trash.isFull, strings: strings)
        case .separator:
            return DockMenuBuilder.separator(autoHide: settings.settings.autoHide, magnification: settings.settings.magnification,
                                             strings: strings)
        case .stack(let id): return stackMenuItems(id)
        }
    }

    /// An app's menu: its windows (read from the app now), its own items, recent documents, Open at Login
    /// and Assign To (from Apple's Dock, remembered per app), and the rest, which OldMacDoc does itself.
    private func appMenuItems(_ item: DockModel.Item) -> [DockMenuItem] {
        let app = item.isRunning ? model.runningApplication(for: item) : nil
        var state = AppMenuState()
        state.isRunning = app != nil
        state.isFinder = item.id == DockModel.finderID
        state.isHidden = app?.isHidden ?? false
        state.keepsInDock = item.keepsInDock
        let key = settings.overrideKey(for: item)
        state.iconMode = settings.settings.overrides[key]?.mode ?? .retro
        state.hasIconOverride = settings.settings.overrides[key] != nil
        menuWindows = []
        var slow = false
        if let app {
            if let windows = AppWindows.read(pid: app.processIdentifier, appName: item.name) {
                menuWindows = windows
                state.windows = windows.map(\.info)
            } else {
                // Slow to answer isn't the same as hung (an app indexing, or napping): Apple's Dock decides that,
                // so its menu is read afresh, and only its word puts up Not Responding and Force Quit.
                slow = true
            }
        }
        // The app's own items and recent files come from Apple's menu, read once per app (each read flickers at the
        // screen's edge), unless that's switched off. A slow app's is read afresh: only Apple's Dock says it's hung.
        let pid = app?.processIdentifier
        let fromApple = settings.settings.appleMenuItems
        let snapshot = fromApple || slow
            ? appleMenus.snapshot(for: item, pid: pid, windowTitles: Set(state.windows.map(\.title)), fresh: slow)
            : appleMenus.remembered(for: item, pid: pid)
        if let snapshot {
            state.notResponding = slow && snapshot.notResponding
            if fromApple { state.appleGroups = snapshot.groups }
            state.openAtLogin = snapshot.openAtLogin
        }
        // Open at Login and Assign To are read live, so they're never out of date; changing them replays Apple's row.
        let hasTile = appleMenus.hasTile(for: item)
        if !state.isFinder, let live = LoginItems.contains(item.url, bundleID: item.bundleID) { state.openAtLogin = live }
        state.openAtLoginCommand = .apple(snapshot?.openAtLoginPath ?? AppleMenuMirror.openAtLoginPath(strings: strings))
        state.openAtLoginEnabled = hasTile
        if hasTile, let id = item.bundleID {
            let live = DesktopAssignments.read(bundleID: id)
            if live.desktops > 1 {
                let rows = snapshot.map(\.assignTo).flatMap { $0.isEmpty ? nil : $0 } ?? AppleMenuMirror.standardAssignTo(strings: strings)
                state.assignTo = AppleMenuMirror.markAssignTo(rows, assignment: live.assignment, strings: strings)
            }
        }
        // As Apple's: only for an app with windows (those on other desktops, Apple's menu knows about).
        state.canShowAllWindows = app != nil && hasTile && (!state.windows.isEmpty || snapshot?.canShowAllWindows == true)
        return DockMenuBuilder.app(state, strings: strings)
    }

    private func run(_ command: DockCommand) {
        guard let subject = menuSubject else { return }
        switch subject {
        case .app(let item):
            // The app as it is now: it may have opened or quit since its menu opened.
            runApp(command, tiles[item.id]?.item ?? item)
        case .trash:
            if command == .openTrash { trash.open() } else if command == .emptyTrash { trash.empty() }
        case .separator:
            switch command {
            case .toggleAutoHide: settings.settings.autoHide.toggle()
            case .toggleMagnification: settings.settings.magnification.toggle()
            case .dockSettings: openSettings?()
            default: break
            }
        case .stack(let id): runStack(command, id)
        }
    }

    private func runApp(_ command: DockCommand, _ item: DockModel.Item) {
        let app = model.runningApplication(for: item)
        switch command {
        case .open: activate(item.id)
        case .hide: app?.hide()
        case .unhide: app?.unhide()
        case .hideOthers:
            for other in NSWorkspace.shared.runningApplications where other.activationPolicy == .regular && other != app
                && other.processIdentifier != ProcessInfo.processInfo.processIdentifier {
                other.hide()
            }
            app?.unhide()
            app?.activate(options: [])
        case .quit: app?.terminate()
        case .forceQuit: app?.forceTerminate()
        case .relaunch: relaunch(app, url: item.url)
        case .toggleKeepInDock: model.setPinned(item.id, !item.keepsInDock)
        case .showInFinder: NSWorkspace.shared.activateFileViewerSelecting([item.url])
        case .showAllWindows: appleMenus.showAllWindows(for: item)
        case .focusWindow(let i):
            if let app, i < menuWindows.count { AppWindows.focus(menuWindows[i].element, of: app) }
        case .apple(let path):
            let titles = Set(menuWindows.map(\.info.title))
            if !appleMenus.press(path, for: item, pid: app?.processIdentifier, windowTitles: titles) { NSSound.beep() }
        case .iconMode(let mode): updateOverride(item) { $0.mode = mode }
        case .chooseIconImage: chooseImage(for: item)
        case .resetIcon: resetIcon(for: item)
        case .newFinderWindow:
            NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: FileManager.default.homeDirectoryForCurrentUser.path)
        case .findInFinder: NSWorkspace.shared.showSearchResults(forQueryString: "")
        case .openFile(let path): NSWorkspace.shared.open(URL(fileURLWithPath: path))
        default: break
        }
    }

    /// Quits Finder and opens it again (Finder's menu offers this with Option, instead of Quit).
    private func relaunch(_ app: NSRunningApplication?, url: URL) {
        guard let app else { return }
        app.terminate()
        var ticks = 0
        Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { timer in
            ticks += 1
            if ticks == 30, !app.isTerminated { app.forceTerminate() }
            guard app.isTerminated || ticks > 60 else { return }
            timer.invalidate()
            NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
        }
    }

    private func updateOverride(_ item: DockModel.Item, _ change: (inout IconOverride) -> Void) {
        let key = settings.overrideKey(for: item)
        var o = settings.settings.overrides[key] ?? IconOverride()
        change(&o)
        settings.settings.overrides[key] = o
    }

    private func chooseImage(for item: DockModel.Item) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.message = "Choose an image for \(item.name)"
        NSApp.activate()
        if panel.runModal() == .OK, let url = panel.url { setCustomIcon(url, for: item) }
    }

    private func stackMenuItems(_ id: String) -> [DockMenuItem] {
        guard let pin = model.stacks.pin(id) else { return [] }
        return DockMenuBuilder.stack(name: pin.name, sort: pin.sort, display: pin.display, view: pin.view, strings: strings)
    }

    private func runStack(_ command: DockCommand, _ id: String) {
        guard let pin = model.stacks.pin(id) else { return }
        switch command {
        case .stackSort(let sort): model.updateStack(id) { $0.sort = sort }
        case .stackDisplay(let display): model.updateStack(id) { $0.display = display }
        case .stackView(let view): model.updateStack(id) { $0.view = view }
        case .removeStack: model.setPinned(id, false)
        case .showInFinder: NSWorkspace.shared.activateFileViewerSelecting([pin.url])
        case .openStackFolder: NSWorkspace.shared.open(pin.url)
        case .openFile(let path): NSWorkspace.shared.open(URL(fileURLWithPath: path))
        default: break
        }
        refreshStackArt(id, force: true)
    }

    private func resetIcon(for item: DockModel.Item) {
        let key = settings.overrideKey(for: item)
        if let name = settings.settings.overrides[key]?.customImage {
            try? FileManager.default.removeItem(at: Paths.customIcons.appendingPathComponent(name))
        }
        settings.settings.overrides[key] = nil
    }

    private func setCustomIcon(_ url: URL, for item: DockModel.Item) {
        guard NSImage(contentsOf: url) != nil else { NSSound.beep(); return }
        let key = settings.overrideKey(for: item)
        let safe = key.replacingOccurrences(of: "/", with: "_")
        let ext = url.pathExtension.isEmpty ? "png" : url.pathExtension
        let name = "\(safe)-\(Int(Date().timeIntervalSince1970)).\(ext)"
        guard (try? FileManager.default.copyItem(at: url, to: Paths.customIcons.appendingPathComponent(name))) != nil else {
            NSSound.beep()
            return
        }
        if let old = settings.settings.overrides[key]?.customImage {
            try? FileManager.default.removeItem(at: Paths.customIcons.appendingPathComponent(old))
        }
        updateOverride(item) { $0.customImage = name; $0.mode = .retro }
    }
}

/// Auto-hide and magnification timings.
enum AutoHide {
    /// A pointer that stops on the bottom edge has to rest there this long before the dock comes up,
    /// so clicks at the bottom of windows don't summon it. Pushing on into the edge skips the wait.
    static let revealDelay: TimeInterval = 0.1
    /// Two mouse events on the edge this close together are a push into it (the pointer is pinned
    /// there while the mouse keeps moving): the dock comes up at once.
    static let pushWindow: TimeInterval = 0.25
    /// How long after the pointer leaves before the dock goes.
    static let hideDelay: TimeInterval = 0.2
    /// The slide in is quick and settles into place; the slide out accelerates away.
    static let showDuration: CFTimeInterval = 0.15
    static let hideDuration: CFTimeInterval = 0.18
    /// With Reduce Motion the dock fades instead of sliding.
    static let fadeDuration: CFTimeInterval = 0.12
    /// Fading out when macOS shows its own Dock (fast, so the two never overlap) and back in.
    static let stepAsideDuration: CFTimeInterval = 0.08
    static let stepBackDuration: CFTimeInterval = 0.15
    /// Reveals are held off this long after a Space switch.
    static let transitionBlackout: TimeInterval = 0.4
    /// Bottom-corner margin left free for hot corners.
    static let cornerMargin: CGFloat = 8
    /// Magnification eases in and out with this time constant (~0.09 s to settle).
    static let magnifyTau: CFTimeInterval = 0.03
    /// After the settings panel closes, a dock that hides automatically goes this soon (the moment
    /// shows that it does, if that was just turned on).
    static let afterHoldDelay: TimeInterval = 0.5
    /// How long an app's tile takes to grow in when it opens, or shrink away when it leaves.
    static let arriveDuration: CFTimeInterval = 0.25
    /// Icons sliding to new places after a reorder settle with this time constant (~0.15 s).
    static let slideTau: CFTimeInterval = 0.05
    /// Click and hold this long to open an icon's menu.
    static let holdForMenu: TimeInterval = 0.5
}

/// The puff when an icon is dragged off the shelf: a five-frame flipbook of our own cloud art,
/// played at the drop point while the icon itself vanishes at once.
enum Poof {
    static let frameCount = 5
    static let duration: CFTimeInterval = 0.3

    static func show(at point: NSPoint, iconSize: CGFloat) {
        let side = max(80, min(128, iconSize * 2))
        let scale = NSScreen.main?.backingScaleFactor ?? 2
        let frames = PoofArt.frames(pixelSide: Int(side * scale))
        guard !frames.isEmpty else { return }
        let window = NSPanel(contentRect: NSRect(x: point.x - side / 2, y: point.y - side / 2, width: side, height: side),
                             styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.level = .popUpMenu
        let view = NSView()
        view.wantsLayer = true
        window.contentView = view
        let layer = CALayer()
        layer.frame = CGRect(x: 0, y: 0, width: side, height: side)
        layer.contentsGravity = .resize
        layer.contents = frames.last
        layer.opacity = 0
        view.layer?.addSublayer(layer)
        window.orderFrontRegardless()

        let flipbook = CAKeyframeAnimation(keyPath: "contents")
        flipbook.values = frames
        flipbook.calculationMode = .discrete
        flipbook.duration = duration
        let visible = CABasicAnimation(keyPath: "opacity")
        visible.fromValue = 1
        visible.toValue = 1
        visible.duration = duration
        CATransaction.begin()
        CATransaction.setCompletionBlock { window.orderOut(nil) }
        layer.add(flipbook, forKey: "poof")
        layer.add(visible, forKey: "visible")
        CATransaction.commit()
    }
}

/// Cloud frames for `Poof`, drawn in code: a burst of soft puffs that spreads out and fades.
enum PoofArt {
    private static var cache: [Int: [CGImage]] = [:]

    static func frames(pixelSide: Int) -> [CGImage] {
        if let hit = cache[pixelSide] { return hit }
        let frames = (0..<Poof.frameCount).compactMap { draw(frame: $0, side: pixelSide) }
        cache[pixelSide] = frames
        return frames
    }

    private static func draw(frame k: Int, side: Int) -> CGImage? {
        guard let ctx = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side * 4,
                                  space: Bitmap.colorSpace, bitmapInfo: Bitmap.bitmapInfo) else { return nil }
        let s = CGFloat(side), c = s / 2
        let t = CGFloat(k) / CGFloat(Poof.frameCount - 1)          // 0 ... 1
        let alpha = 1 - 0.7 * t
        let colors = [CGColor(gray: 1, alpha: alpha), CGColor(gray: 0.86, alpha: alpha * 0.95),
                      CGColor(gray: 0.7, alpha: alpha * 0.0)] as CFArray
        guard let gradient = CGGradient(colorsSpace: Bitmap.colorSpace, colors: colors, locations: [0, 0.65, 1]) else { return nil }

        // Puffs on a ring that spreads out, plus a core that thins away.
        var puffs: [(CGPoint, CGFloat)] = []
        let count = 8
        for i in 0..<count {
            let jitter = CGFloat((i * 37) % 11) / 11            // fixed pseudo-random variety
            let angle = CGFloat(i) / CGFloat(count) * 2 * .pi + jitter * 0.4
            let distance = s * (0.10 + 0.24 * t) * (0.85 + 0.3 * jitter)
            let radius = s * (0.13 + 0.07 * t) * (0.8 + 0.4 * jitter) * (1 - 0.25 * t)
            puffs.append((CGPoint(x: c + cos(angle) * distance, y: c + sin(angle) * distance * 0.85), radius))
        }
        if t < 0.8 { puffs.append((CGPoint(x: c, y: c), s * (0.2 - 0.12 * t))) }

        for (center, radius) in puffs {
            ctx.drawRadialGradient(gradient, startCenter: CGPoint(x: center.x - radius * 0.25, y: center.y + radius * 0.3),
                                   startRadius: 0, endCenter: center, endRadius: radius, options: [])
        }
        return ctx.makeImage()
    }
}

extension CALayer {
    func setContentsScaleRecursively(_ scale: CGFloat) {
        contentsScale = scale
        mask?.setContentsScaleRecursively(scale)
        sublayers?.forEach { $0.setContentsScaleRecursively(scale) }
    }
}
