import ServiceManagement
import SwiftUI

/// What the settings panel needs from the rest of the app.
struct SettingsActions {
    var about: () -> Void
    var checkForUpdates: () -> Void
    var quit: () -> Void
    var openLoginItems: () -> Void
    /// The Magnification slider is being dragged (the dock shows magnification meanwhile).
    var magnifying: (Bool) -> Void
    /// Asks for Accessibility and opens its page in System Settings.
    var openAccessibility: () -> Void = {}
}

/// State of the panel that doesn't live in the settings, read each time it opens: how big the dock can
/// get on this screen, the pictures of each shelf (the user's own icons on their wallpaper), and Open
/// at Login, which only macOS knows.
@MainActor
final class SettingsPanelModel: ObservableObject {
    @Published var largestFitting: Double?
    @Published private(set) var shelfPictures: [ShelfStyle: CGImage] = [:]
    @Published private(set) var loginStatus: SMAppService.Status = .notRegistered
    @Published private(set) var loginError: String?
    /// The sides of the main display Apple's Dock can wait on. The panel closes when displays change,
    /// so reading them when it opens is enough.
    @Published private(set) var freeSideEdges: Set<String> = ["left", "right"]
    /// Whether the dock's menus can show each app's windows and its own items.
    @Published private(set) var accessibilityAllowed = true

    static let pictureSize = CGSize(width: 150, height: 40)

    var opensAtLogin: Bool { loginStatus == .enabled || loginStatus == .requiresApproval }
    var loginNeedsApproval: Bool { loginStatus == .requiresApproval }

    func refresh(largestFitting: Double?, icons: [ShelfPreview.Item], screen: NSScreen?) {
        self.largestFitting = largestFitting
        loginStatus = SMAppService.mainApp.status
        loginError = nil
        freeSideEdges = AppleDockManager.mainDisplayFreeSideEdges
        accessibilityAllowed = AccessibilityAccess.isTrusted
        let scale = screen?.backingScaleFactor ?? 2
        let wallpaper = Self.wallpaper(for: screen)
        var pictures: [ShelfStyle: CGImage] = [:]
        for style in ShelfStyle.allCases {
            pictures[style] = ShelfPreview.thumbnail(style, size: Self.pictureSize, scale: scale, items: icons, wallpaper: wallpaper)
        }
        shelfPictures = pictures
    }

    /// The desktop picture, read small (nil for a live wallpaper or one that can't be read).
    private static func wallpaper(for screen: NSScreen?) -> CGImage? {
        guard let screen, let url = NSWorkspace.shared.desktopImageURL(for: screen),
              let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options = [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: 1200,
                       kCGImageSourceCreateThumbnailWithTransform: true] as CFDictionary
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options)
    }

    func setOpensAtLogin(_ on: Bool) {
        let service = SMAppService.mainApp
        do {
            if on { try service.register() } else { try service.unregister() }
            loginError = nil
        } catch {
            loginError = on ? "Couldn’t turn on Open at Login: \(error.localizedDescription)"
                            : "Couldn’t turn off Open at Login: \(error.localizedDescription)"
        }
        loginStatus = service.status
    }
}

/// The settings panel under the menu bar icon. Every change applies at once; the dock stays up while
/// the panel is open, so each change can be seen.
struct SettingsView: View {
    @ObservedObject var store: SettingsStore
    @ObservedObject var model: SettingsPanelModel
    @ObservedObject var updater: UpdaterController
    let actions: SettingsActions

    static let width: CGFloat = 316
    private static let labelWidth: CGFloat = 104

    private var controls: DockSizeControls { DockSizeControls(settings: store.settings, largestFitting: model.largestFitting) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            shelves
            Divider().padding(.vertical, 12)
            VStack(alignment: .leading, spacing: 10) {
                finish
                sizeSlider
                magnificationSlider
            }
            Divider().padding(.vertical, 12)
            VStack(alignment: .leading, spacing: 9) {
                switchRow("Hide automatically", isOn: $store.settings.autoHide)
                switchRow("Lights for open apps", isOn: $store.settings.showIndicators)
                loginToggle
                if model.accessibilityAllowed { appleItemsToggle } else { accessibilityRow }
            }
            Divider().padding(.vertical, 12)
            missionControl
            if let version = updater.availableVersion {
                updateRow(version)
                    .padding(.top, 12)
            }
            Divider().padding(.vertical, 12)
            footer
        }
        .padding(16)
        .frame(width: Self.width)
        .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: Shelf

    private var shelves: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Shelf").font(.headline)
            VStack(spacing: 2) {
                ForEach(ShelfStyle.allCases) { style in
                    ShelfChoice(style: style, picture: model.shelfPictures[style], isSelected: store.settings.shelfStyle == style) {
                        store.settings.shelfStyle = style
                    }
                }
            }
            .accessibilityRepresentation {
                Picker("Shelf", selection: $store.settings.shelfStyle) {
                    ForEach(ShelfStyle.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.radioGroup)
            }
            // Each row's highlight reaches into the margin, so the pictures line up with everything else.
            .padding(.horizontal, -ShelfChoice.inset)
        }
    }

    // MARK: Icons and sizes

    private var finish: some View {
        row("Icon finish") {
            Picker("Icon finish", selection: $store.settings.finish) {
                ForEach(FinishLevel.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            // As wide as a slider and its readout, so the rows line up on both sides.
            .frame(maxWidth: .infinity)
        }
    }

    private var sizeSlider: some View {
        let c = controls
        return row("Size") {
            Slider(value: Binding(get: { c.size }, set: { apply(DockSizeControls.settingSize($0, in: store.settings)) }),
                   in: c.sizeRange)
                .accessibilityLabel("Size")
                .accessibilityValue("\(Int(c.size.rounded())) points")
            readout(DockSizeControls.readout(c.size))
        }
    }

    private var magnificationSlider: some View {
        let c = controls
        return row("Magnification") {
            Slider(value: Binding(get: { c.magnification }, set: { apply(DockSizeControls.settingMagnification($0, in: store.settings)) }),
                   in: DockSizeControls.magnificationRange, onEditingChanged: actions.magnifying)
                .accessibilityLabel("Magnification")
                .accessibilityValue(c.magnificationIsOff ? "Off" : "\(Int(c.magnification.rounded())) points")
            readout(c.magnificationReadout)
        }
    }

    /// Settings only change when a value really does (a slider reports every movement).
    private func apply(_ new: AppSettings) {
        if new != store.settings { store.settings = new }
    }

    private func row<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 8) {
            Text(title)
                .frame(width: Self.labelWidth, alignment: .leading)
                .accessibilityHidden(true)
            content()
        }
    }

    private func readout(_ text: String) -> some View {
        Text(text)
            .monospacedDigit()
            .foregroundStyle(.secondary)
            .frame(width: 46, alignment: .trailing)
            .accessibilityHidden(true)
    }

    // MARK: Open at Login and updates

    /// A setting that's on or off: its name on the left, the switch at the right edge, as in Control Center.
    private func switchRow(_ title: String, isOn: Binding<Bool>) -> some View {
        HStack {
            Text(title).accessibilityHidden(true)
            Spacer(minLength: 8)
            Toggle(title, isOn: isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
        }
    }

    private var loginToggle: some View {
        VStack(alignment: .leading, spacing: 4) {
            switchRow("Open at login", isOn: Binding(get: { model.opensAtLogin }, set: { model.setOpensAtLogin($0) }))
                .accessibilityHint(model.loginNeedsApproval ? "Needs approval in System Settings, Login Items" : "")
            if model.loginNeedsApproval {
                HStack(spacing: 4) {
                    Text("Needs approval in System Settings")
                    Button("Open…", action: actions.openLoginItems).buttonStyle(.link)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            if let error = model.loginError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// Copying each app's own items from Apple's Dock flickers its menu at the screen's edge once per app.
    private var appleItemsToggle: some View {
        VStack(alignment: .leading, spacing: 3) {
            switchRow("Items from Apple’s Dock", isOn: $store.settings.appleMenuItems)
            Text("Each app’s own menu items, like New Window, and its recent files. Reading them makes Apple’s hidden Dock flicker at the edge of the screen once per app.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// Shown only while Accessibility isn't allowed: what it adds, and where to allow it.
    private var accessibilityRow: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("Menus show each app’s windows and its own items, and maximised windows stop above the dock, once OldMacDoc may use Accessibility.")
                .fixedSize(horizontal: false, vertical: true)
            Button("Allow in System Settings…", action: actions.openAccessibility).buttonStyle(.link)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    // MARK: Mission Control

    /// Which side Mission Control's + for a new desktop sits on. Apple's Dock waits on the other edge.
    private var missionControl: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Mission Control").font(.headline)
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Add Desktop button").accessibilityHidden(true)
                    Spacer(minLength: 8)
                    Picker("Add Desktop button in Mission Control", selection: $store.settings.addDesktopSide) {
                        ForEach(AddDesktopSide.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize()
                }
                if let note = addDesktopNote {
                    Text(note)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    /// Why the + can't go where it was asked for: Apple's Dock would have to wait on an edge with
    /// another display against it. Decided the same way as where the app really puts it.
    private var addDesktopNote: String? {
        let edge = store.settings.addDesktopSide.dockEdge
        guard AppleDockManager.sideEdge(preferring: edge, free: model.freeSideEdges) != edge else { return nil }
        return "Needs the main display’s \(edge) edge free of other displays."
    }

    private func updateRow(_ version: String) -> some View {
        Button(action: actions.checkForUpdates) {
            HStack(spacing: 8) {
                Image(systemName: "arrow.down.circle.fill")
                    .foregroundStyle(Color.accentColor)
                    .imageScale(.large)
                Text("OldMacDoc \(version) is available")
                Spacer(minLength: 4)
                Text("Install…").foregroundStyle(Color.accentColor)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: Footer

    private var footer: some View {
        HStack {
            FooterButton(title: "About", action: actions.about)
            Spacer()
            FooterButton(title: "Check for Updates…", action: actions.checkForUpdates)
                .disabled(!updater.isConfigured || !updater.canCheck)
            Spacer()
            FooterButton(title: "Quit", action: actions.quit)
        }
    }
}

/// A plain text button for the panel's last row, which brightens under the pointer.
private struct FooterButton: View {
    let title: String
    let action: () -> Void
    @State private var hovering = false
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button(action: action) {
            Text(title)
                .foregroundStyle(!isEnabled ? AnyShapeStyle(.tertiary) : hovering ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
                .padding(.vertical, 2)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

/// One shelf to choose: the user's own icons on it, over their wallpaper, with its name and era.
private struct ShelfChoice: View {
    let style: ShelfStyle
    let picture: CGImage?
    let isSelected: Bool
    let choose: () -> Void

    private static let size = SettingsPanelModel.pictureSize
    static let inset: CGFloat = 6

    private var era: String {
        switch style {
        case .clear: "Leopard"
        case .frosted: "Mountain Lion"
        case .smoke: "A darker take"
        }
    }

    var body: some View {
        Button(action: choose) {
            HStack(spacing: 12) {
                Group {
                    if let picture {
                        Image(decorative: picture, scale: CGFloat(picture.width) / Self.size.width)
                    } else {
                        Color.secondary.opacity(0.2)
                    }
                }
                .frame(width: Self.size.width, height: Self.size.height)
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(style.title).fontWeight(isSelected ? .semibold : .regular)
                    Text(era).font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Image(systemName: "checkmark")
                    .fontWeight(.semibold)
                    .foregroundStyle(Color.accentColor)
                    .opacity(isSelected ? 1 : 0)
                    .accessibilityHidden(true)
            }
            .padding(Self.inset)
            .background {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isSelected ? Color.accentColor.opacity(0.14) : Color.clear)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
