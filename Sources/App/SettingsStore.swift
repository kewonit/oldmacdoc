import Combine
import Foundation

final class SettingsStore: ObservableObject {
    @Published var settings: AppSettings {
        didSet { if settings != oldValue { scheduleSave() } }
    }
    /// Whether settings were saved before this launch. Without them, the first launch picks up how the
    /// user had Apple's Dock.
    let existedAtLaunch: Bool
    private let url: URL
    private var pendingSave: DispatchWorkItem?

    init(url: URL = Paths.settingsFile) {
        self.url = url
        existedAtLaunch = FileManager.default.fileExists(atPath: url.path)
        settings = JSONFile.load(AppSettings.self, from: url) ?? AppSettings()
    }

    /// Slider drags change settings many times a second; write once they settle.
    private func scheduleSave() {
        pendingSave?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.flush() }
        pendingSave = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: work)
    }

    func flush() {
        guard let work = pendingSave else { return }
        work.cancel()
        pendingSave = nil
        try? JSONFile.save(settings, to: url)
    }

    func overrideKey(for item: DockModel.Item) -> String { item.bundleID ?? item.url.path }

    /// The image the user chose for an app, if they chose one and it's still there.
    func customImageURL(for item: DockModel.Item) -> URL? {
        let key = overrideKey(for: item)
        if let name = settings.overrides[key]?.customImage {
            let url = Paths.customIcons.appendingPathComponent(name)
            if FileManager.default.fileExists(atPath: url.path) { return url }
        }
        return nil
    }
}
