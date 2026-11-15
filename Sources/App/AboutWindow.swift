import AppKit
import SwiftUI

/// About OldMacDoc: the icon, the version (selectable, for bug reports), where to find out more, and
/// the licences of what it's built with.
@MainActor
final class AboutWindowController {
    var checkForUpdates: () -> Void = {}
    var canCheckForUpdates: () -> Bool = { false }
    private var window: NSWindow?

    func show() {
        let window = self.window ?? makeWindow()
        self.window = window
        window.center()
        // Activation is cooperative since macOS 14 and may be declined; the window still comes to the front.
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
    }

    private func makeWindow() -> NSWindow {
        let view = AboutView(canCheckForUpdates: canCheckForUpdates(), checkForUpdates: { [weak self] in
            self?.window?.close()
            self?.checkForUpdates()
        })
        let hosting = NSHostingView(rootView: view)
        let window = AboutWindow(contentRect: NSRect(origin: .zero, size: hosting.fittingSize),
                                 styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: false)
        window.title = "About \(AppInfo.name)"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        // There's no Dock icon to bring it back from another Space: it always opens on this one.
        window.collectionBehavior = [.moveToActiveSpace]
        window.contentView = hosting
        window.setContentSize(hosting.fittingSize)
        // Only the close button: there's nothing to minimise or zoom.
        window.standardWindowButton(.miniaturizeButton)?.isHidden = true
        window.standardWindowButton(.zoomButton)?.isHidden = true
        return window
    }
}

/// Esc and ⌘W close it (an accessory app has no menu bar menu to carry ⌘W).
private final class AboutWindow: NSWindow {
    override func cancelOperation(_ sender: Any?) { close() }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command, event.charactersIgnoringModifiers == "w" {
            close()
            return true
        }
        return super.performKeyEquivalent(with: event)
    }
}

private struct AboutView: View {
    let canCheckForUpdates: Bool
    let checkForUpdates: () -> Void

    private static let website = URL(string: "https://oldmacdoc.edbn.me")!
    private static let repository = URL(string: "https://github.com/kewonit/oldmacdoc")!
    private static let releaseNotes = URL(string: "https://github.com/kewonit/oldmacdoc/blob/main/CHANGELOG.md")!

    private var version: String {
        let info = Bundle.main.infoDictionary ?? [:]
        let short = info["CFBundleShortVersionString"] as? String ?? AppInfo.version
        return (info["CFBundleVersion"] as? String).map { "Version \(short) (\($0))" } ?? "Version \(short)"
    }

    var body: some View {
        VStack(spacing: 0) {
            // From the app's own asset catalog: the system's icon cache can lag behind a new build.
            Image(nsImage: NSImage(named: "AppIcon") ?? NSApp.applicationIconImage)
                .resizable()
                .frame(width: 112, height: 112)
                .accessibilityHidden(true)
                .padding(.bottom, 10)
            Text(AppInfo.name)
                .font(.system(size: 22, weight: .semibold))
            Text(version)
                .font(.callout)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .padding(.top, 2)
            Text("The 3D glass Dock, back on your Mac.")
                .padding(.top, 14)
            Text("Free and open source, under the MIT License.")
                .foregroundStyle(.secondary)
                .padding(.top, 2)

            HStack(spacing: 16) {
                Link("Website", destination: Self.website)
                Link("GitHub", destination: Self.repository)
                Link("Release Notes", destination: Self.releaseNotes)
            }
            .padding(.top, 16)

            HStack(spacing: 10) {
                Button("Acknowledgements", action: Self.showAcknowledgements)
                if canCheckForUpdates {
                    Button("Check for Updates…", action: checkForUpdates)
                }
            }
            .controlSize(.regular)
            .padding(.top, 16)

            Text("Mac, macOS and Dock are trademarks of Apple Inc. OldMacDoc is not affiliated with Apple.")
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            .font(.caption)
            .foregroundStyle(.tertiary)
            .padding(.top, 18)
        }
        .padding(.horizontal, 32)
        .padding(.top, 36)
        .padding(.bottom, 22)
        .frame(width: 380)
    }

    /// The licences of OldMacDoc and of what ships inside it (Sparkle), as bundled in the app.
    private static func showAcknowledgements() {
        for name in ["THIRD_PARTY_NOTICES.md", "LICENSE"] {
            guard let url = Bundle.main.url(forResource: name, withExtension: nil) else { continue }
            NSWorkspace.shared.open(url)
        }
    }
}
