import CoreGraphics
import Foundation

struct PixelRect: Equatable {
    var minX: Int, minY: Int, maxX: Int, maxY: Int
    var width: Int { maxX - minX + 1 }
    var height: Int { maxY - minY + 1 }
}

/// 8-bit RGBA premultiplied sRGB bitmap. Row 0 is the top of the image.
struct Bitmap {
    let width: Int
    let height: Int
    var data: [UInt8]

    static let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
    static let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue

    init(width: Int, height: Int) {
        self.width = width
        self.height = height
        data = [UInt8](repeating: 0, count: width * height * 4)
    }

    /// Draws `image` aspect-fit and centred in a `size` x `size` canvas.
    init?(cgImage: CGImage, size: Int) {
        var buffer = [UInt8](repeating: 0, count: size * size * 4)
        let ok = buffer.withUnsafeMutableBytes { raw -> Bool in
            guard let ctx = CGContext(data: raw.baseAddress, width: size, height: size, bitsPerComponent: 8,
                                      bytesPerRow: size * 4, space: Bitmap.colorSpace,
                                      bitmapInfo: Bitmap.bitmapInfo) else { return false }
            ctx.interpolationQuality = .high
            let w = CGFloat(cgImage.width), h = CGFloat(cgImage.height), side = CGFloat(size)
            let s = side / max(w, h, 1)
            ctx.draw(cgImage, in: CGRect(x: (side - w * s) / 2, y: (side - h * s) / 2, width: w * s, height: h * s))
            return true
        }
        guard ok else { return nil }
        width = size
        height = size
        data = buffer
    }

    func makeImage() -> CGImage? {
        guard let provider = CGDataProvider(data: Data(data) as CFData) else { return nil }
        return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
                       space: Bitmap.colorSpace, bitmapInfo: CGBitmapInfo(rawValue: Bitmap.bitmapInfo),
                       provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
    }

    @inline(__always) func offset(_ x: Int, _ y: Int) -> Int { (y * width + x) * 4 }
    @inline(__always) func alpha(_ x: Int, _ y: Int) -> UInt8 { data[offset(x, y) + 3] }

    /// Un-premultiplied colour, components in 0...1 (rgb in xyz, alpha in w).
    @inline(__always) func color(_ x: Int, _ y: Int) -> SIMD4<Float> {
        let o = offset(x, y)
        let a = Float(data[o + 3]) / 255
        guard a > 0 else { return .zero }
        return SIMD4(Float(data[o]) / 255 / a, Float(data[o + 1]) / 255 / a, Float(data[o + 2]) / 255 / a, a)
    }

    @inline(__always) mutating func set(_ x: Int, _ y: Int, rgb: SIMD3<Float>, alpha: Float) {
        let o = offset(x, y)
        let a = max(0, min(1, alpha))
        let c = clamp01(rgb) * a
        data[o] = UInt8((c.x * 255).rounded())
        data[o + 1] = UInt8((c.y * 255).rounded())
        data[o + 2] = UInt8((c.z * 255).rounded())
        data[o + 3] = UInt8((a * 255).rounded())
    }

    func opaqueBounds(threshold: UInt8) -> PixelRect? {
        var r = PixelRect(minX: width, minY: height, maxX: -1, maxY: -1)
        for y in 0..<height {
            for x in 0..<width where data[(y * width + x) * 4 + 3] > threshold {
                r.minX = min(r.minX, x); r.maxX = max(r.maxX, x)
                r.minY = min(r.minY, y); r.maxY = max(r.maxY, y)
            }
        }
        return r.maxX >= 0 ? r : nil
    }
}

@inline(__always) func clamp01(_ v: SIMD3<Float>) -> SIMD3<Float> {
    v.replacing(with: 0, where: v .< 0).replacing(with: 1, where: v .> 1)
}

@inline(__always) func colorDistance(_ a: SIMD3<Float>, _ b: SIMD3<Float>) -> Float {
    let d = a - b
    return max(Swift.abs(d.x), max(Swift.abs(d.y), Swift.abs(d.z)))
}

extension SIMD4 where Scalar == Float {
    var rgb: SIMD3<Float> { SIMD3(x, y, z) }
}
