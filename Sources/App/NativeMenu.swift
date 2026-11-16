import AppKit

/// The same menu as a system NSMenu, for VoiceOver, which knows how to read and drive real menus.
/// Option-only rows (Finder's Relaunch) are left out; Option alternates work as in any menu.
final class NativeMenu: NSObject {
    private let onChoose: (DockCommand) -> Void
    private var commands: [DockCommand] = []

    init(onChoose: @escaping (DockCommand) -> Void) {
        self.onChoose = onChoose
    }

    func make(_ items: [DockMenuItem]) -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.font = MenuStyle.lucidaGrande
        for item in visibleRows(items, option: false) {
            switch item.kind {
            case .separator: menu.addItem(.separator())
            case .header:
                if #available(macOS 14, *) { menu.addItem(.sectionHeader(title: item.title)) }
            case .item:
                let row = add(item.title, item.command, to: menu)
                row.isEnabled = item.isEnabled
                row.state = item.mark == .none ? .off : .on
                if item.mark == .diamond { row.onStateImage = NSImage(systemSymbolName: "diamond.fill", accessibilityDescription: "minimized") }
                if let path = item.iconPath {
                    let icon = NSWorkspace.shared.icon(forFile: path)
                    icon.size = NSSize(width: 16, height: 16)
                    row.image = icon
                }
                if let sub = item.submenu { row.submenu = make(sub) }
                if let alt = item.optionTitle {
                    let alternate = add(alt, item.optionCommand ?? item.command, to: menu)
                    alternate.isAlternate = true
                    alternate.keyEquivalentModifierMask = .option
                    alternate.isEnabled = item.isEnabled
                }
            }
        }
        return menu
    }

    private func add(_ title: String, _ command: DockCommand, to menu: NSMenu) -> NSMenuItem {
        let row = menu.addItem(withTitle: title, action: #selector(choose(_:)), keyEquivalent: "")
        row.target = self
        row.tag = commands.count
        commands.append(command)
        return row
    }

    @objc private func choose(_ sender: NSMenuItem) {
        guard sender.tag < commands.count else { return }
        let command = commands[sender.tag]
        DispatchQueue.main.async { self.onChoose(command) }
    }
}
