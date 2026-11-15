import AppKit
import CoreImage
import CryptoKit
import Foundation
import UniformTypeIdentifiers

/// What to draw for one app. The shelf style isn't part of it: icons look the same on every shelf,
/// so switching shelves never re-renders them.
struct IconRequest: Hashable {
    var appURL: URL
    var bundleID: String?
    var finish: FinishLevel
    var mode: IconMode
    /// An image the user chose for the app. Skips plate removal.
    var customImageURL: URL?
}

struct IconResult {
    let image: CGImage
    /// Squashed, blurred silhouette the shelf draws under the icon.
    let shadow: CGImage?
}

/// Builds the retro icon for an app: best source -> lift plate -> even out size -> finish -> cache.
/// Nothing is ever written into the app itself.
final class IconEngine {
    static let finishVersion = 1
    static let outputSize = 512
    private static let workSize = 1024

    enum Source { case custom, legacy, system }

    let cacheDir: URL
    /// Finished icons by request, so going back to a finish (or reloading the dock) is instant
    /// (main thread only). Each is a 512 px image (about 1 MB once drawn) plus a small shadow; the
    /// limit holds a few finishes' worth for a full dock, and past it the memory starts over.
    private var memory: [IconRequest: IconResult] = [:]
    private static let memoryLimit = 100
    /// Completions waiting on a render already in flight (main thread only).
    private var waiting: [IconRequest: [(IconResult) -> Void]] = [:]
    private let queue: OperationQueue = {
        let q = OperationQueue()
        q.name = "IconEngine"
        q.maxConcurrentOperationCount = 2
        q.qualityOfService = .utility
        return q
    }()
    private let context = CIContext(options: [.cacheIntermediates: false])

    init(cacheDir: URL = Paths.iconCache) {
        self.cacheDir = cacheDir
        queue.addOperation { [cacheDir] in Self.prune(cacheDir, olderThanDays: 45) }
    }

    /// Drops cache files nobody has read for a while (old app versions, styles no longer used).
    static func prune(_ dir: URL, olderThanDays days: Double) {
        let cutoff = Date().addingTimeInterval(-days * 86_400)
        let keys: [URLResourceKey] = [.contentModificationDateKey]
        let files = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: keys)) ?? []
        for file in files {
            let date = (try? file.resourceValues(forKeys: Set(keys)))?.contentModificationDate ?? .distantPast
            if date < cutoff { try? FileManager.default.removeItem(at: file) }
        }
    }

    /// A finished icon already in memory. Cheap: no file access (call from the main thread).
    func cached(_ request: IconRequest) -> IconResult? { memory[request] }

    /// Drops an app's icons from memory, so the next request re-checks its version and icon file
    /// (after the app is updated, say).
    func forget(appURL: URL) {
        memory = memory.filter { $0.key.appURL != appURL }
    }

    /// Calls `completion` on the main queue once the finished icon is ready. Call from the main thread.
    /// Everything that touches the disk (the cache key reads the app's Info.plist) runs off the main thread.
    func load(_ request: IconRequest, completion: @escaping (IconResult) -> Void) {
        if let hit = memory[request] { completion(hit); return }
        if waiting[request] != nil { waiting[request]?.append(completion); return }
        waiting[request] = [completion]
        queue.addOperation { [weak self] in
            guard let self else { return }
            let key = self.cacheKey(for: request)
            let file = self.cacheDir.appendingPathComponent(key + ".png")
            var image = Self.readPNG(file)
            if image != nil {
                // Keep recently used files out of `prune`.
                try? FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: file.path)
            } else if let rendered = self.render(request) {
                image = rendered
                Self.writePNG(rendered, to: file)
            }
            let result = image.map { IconResult(image: $0, shadow: self.makeShadow(from: $0)) }
            DispatchQueue.main.async {
                let callbacks = self.waiting.removeValue(forKey: request) ?? []
                guard let result else { return }
                if self.memory.count >= Self.memoryLimit { self.memory.removeAll() }
                self.memory[request] = result
                callbacks.forEach { $0(result) }
            }
        }
    }

    // MARK: Cache key: bundle ID, app version, icon file date, finish version, options.

    func cacheKey(for r: IconRequest) -> String {
        let info = NSDictionary(contentsOf: r.appURL.appendingPathComponent("Contents/Info.plist"))
        let version = (info?["CFBundleVersion"] as? String) ?? ""
        let iconFile = Self.legacyIconURL(for: r.appURL) ?? r.appURL.appendingPathComponent("Contents/Info.plist")
        let parts: [String] = [
            r.bundleID ?? r.appURL.path, version, Self.stamp(iconFile), "v\(Self.finishVersion)",
            r.finish.rawValue, r.mode.rawValue,
            r.customImageURL.map { $0.path + Self.stamp($0) } ?? "",
        ]
        let digest = SHA256.hash(data: Data(parts.joined(separator: "|").utf8))
        return digest.prefix(16).map { String(format: "%02x", $0) }.joined()
    }

    private static func stamp(_ url: URL) -> String {
        let date = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date
        return String(Int(date?.timeIntervalSince1970 ?? 0))
    }

    // MARK: Pipeline

    /// The app's older .icns in Contents/Resources, which often holds the original free-shaped artwork.
    static func legacyIconURL(for appURL: URL) -> URL? {
        let info = NSDictionary(contentsOf: appURL.appendingPathComponent("Contents/Info.plist"))
        guard var name = info?["CFBundleIconFile"] as? String, !name.isEmpty else { return nil }
        if (name as NSString).pathExtension.isEmpty { name += ".icns" }
        let url = appURL.appendingPathComponent("Contents/Resources").appendingPathComponent(name)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    static func cgImage(_ image: NSImage, size: Int) -> CGImage? {
        var rect = CGRect(x: 0, y: 0, width: size, height: size)
        return image.cgImage(forProposedRect: &rect, context: nil, hints: [.interpolation: NSImageInterpolation.high.rawValue])
    }

    func render(_ r: IconRequest) -> CGImage? {
        var source = Source.system
        var picture: CGImage?
        if let custom = r.customImageURL, let img = NSImage(contentsOf: custom) {
            picture = Self.cgImage(img, size: Self.workSize); source = .custom
        }
        if picture == nil, r.mode == .retro, let legacy = Self.legacyIconURL(for: r.appURL), let img = NSImage(contentsOf: legacy) {
            picture = Self.cgImage(img, size: Self.workSize); source = .legacy
        }
        if picture == nil {
            picture = Self.cgImage(NSWorkspace.shared.icon(forFile: r.appURL.path), size: Self.workSize); source = .system
        }
        guard let picture, var bitmap = Bitmap(cgImage: picture, size: Self.workSize) else { return nil }

        if r.mode == .retro {
            let isApple = (r.bundleID ?? "").hasPrefix("com.apple.")
            if source == .system, !isApple, let lifted = PlateDetector.lift(bitmap) {
                bitmap = lifted
            }
        }

        guard let sized = IconNormalizer.normalize(bitmap, outputSize: Self.outputSize) else { return nil }
        guard r.mode == .retro, let tuning = RetroFinish.tuning(level: r.finish) else { return sized.image }
        return RetroFinish.apply(sized.image, contentRect: sized.contentRect, tuning: tuning, context: context) ?? sized.image
    }

    func makeShadow(from icon: CGImage) -> CGImage? {
        let w: CGFloat = 160, h: CGFloat = 48
        let src = CIImage(cgImage: icon)
        let black = src.applyingFilter("CIColorMatrix", parameters: [
            "inputRVector": CIVector(x: 0, y: 0, z: 0, w: 0), "inputGVector": CIVector(x: 0, y: 0, z: 0, w: 0),
            "inputBVector": CIVector(x: 0, y: 0, z: 0, w: 0), "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 0.85),
        ])
        let sx = w * 0.82 / src.extent.width, sy = h * 0.3 / src.extent.height
        let squashed = black.transformed(by: CGAffineTransform(scaleX: sx, y: sy))
            .transformed(by: CGAffineTransform(translationX: w * 0.09, y: h * 0.35))
            .applyingGaussianBlur(sigma: 3.5)
        return context.createCGImage(squashed, from: CGRect(x: 0, y: 0, width: w, height: h),
                                     format: .RGBA8, colorSpace: Bitmap.colorSpace)
    }

    // MARK: PNG

    static func readPNG(_ url: URL) -> CGImage? {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(src, 0, nil)
    }

    static func writePNG(_ image: CGImage, to url: URL) {
        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else { return }
        CGImageDestinationAddImage(dest, image, nil)
        CGImageDestinationFinalize(dest)
    }
}
