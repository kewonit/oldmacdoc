import CoreImage
import Foundation

/// The retro look: richer colour, a curved gloss across the top third, a soft bevel and
/// gentle shading toward the bottom. Shadows and reflections are added by the shelf.
enum RetroFinish {
    struct Tuning: Equatable {
        var saturation: CGFloat
        var contrast: CGFloat
        var gloss: CGFloat
        var bevel: CGFloat
        var shade: CGFloat
    }

    /// The same on every shelf, so changing shelves never has to re-render the icons.
    static func tuning(level: FinishLevel) -> Tuning? {
        let k: CGFloat
        switch level {
        case .off: return nil
        case .subtle: k = 0.5
        case .full: k = 1
        }
        return Tuning(saturation: 1 + 0.14 * k, contrast: 1 + 0.06 * k, gloss: 0.45 * k, bevel: 0.5 * k, shade: 0.22 * k)
    }

    static func apply(_ cg: CGImage, contentRect r: CGRect, tuning t: Tuning, context: CIContext) -> CGImage? {
        let src = CIImage(cgImage: cg)
        let extent = src.extent
        var img = src.applyingFilter("CIColorControls", parameters: [
            kCIInputSaturationKey: t.saturation, kCIInputContrastKey: t.contrast, kCIInputBrightnessKey: 0,
        ])

        // White silhouette carrying the icon's alpha.
        let silhouette = src.applyingFilter("CIColorMatrix", parameters: [
            "inputRVector": CIVector(x: 0, y: 0, z: 0, w: 0), "inputGVector": CIVector(x: 0, y: 0, z: 0, w: 0),
            "inputBVector": CIVector(x: 0, y: 0, z: 0, w: 0), "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1),
            "inputBiasVector": CIVector(x: 1, y: 1, z: 1, w: 0),
        ])
        func tint(_ image: CIImage, white: Bool, alpha: CGFloat) -> CIImage {
            let v: CGFloat = white ? 1 : 0
            return image.applyingFilter("CIColorMatrix", parameters: [
                "inputRVector": CIVector(x: 0, y: 0, z: 0, w: 0), "inputGVector": CIVector(x: 0, y: 0, z: 0, w: 0),
                "inputBVector": CIVector(x: 0, y: 0, z: 0, w: 0), "inputAVector": CIVector(x: 0, y: 0, z: 0, w: alpha),
                "inputBiasVector": CIVector(x: v, y: v, z: v, w: 0),
            ])
        }
        func atop(_ top: CIImage, _ base: CIImage) -> CIImage {
            top.applyingFilter("CISourceAtopCompositing", parameters: [kCIInputBackgroundImageKey: base])
        }

        // Shading toward the bottom.
        if t.shade > 0, let shade = CIFilter(name: "CILinearGradient", parameters: [
            "inputPoint0": CIVector(x: r.midX, y: r.minY), "inputPoint1": CIVector(x: r.midX, y: r.minY + r.height * 0.5),
            "inputColor0": CIColor(red: 0, green: 0, blue: 0, alpha: t.shade), "inputColor1": CIColor(red: 0, green: 0, blue: 0, alpha: 0),
        ])?.outputImage {
            img = atop(shade.cropped(to: extent), img)
        }

        // Bevel: a lit rim along top edges, a darker rim along bottom edges.
        if t.bevel > 0 {
            let d = max(2, r.width * 0.014)
            func rim(_ dy: CGFloat) -> CIImage {
                silhouette.applyingFilter("CISourceOutCompositing", parameters: [
                    kCIInputBackgroundImageKey: silhouette.transformed(by: CGAffineTransform(translationX: 0, y: dy)),
                ]).applyingGaussianBlur(sigma: d * 0.6).cropped(to: extent)
            }
            img = atop(tint(rim(-d), white: true, alpha: t.bevel), img)
            img = atop(tint(rim(d), white: false, alpha: t.bevel * 0.5), img)
        }

        // Curved gloss over the top third, kept slightly inside the icon's edge.
        if t.gloss > 0 {
            let radius = r.width * 1.2
            let glossBottom = r.maxY - r.height * 0.36
            if let disk = CIFilter(name: "CIRadialGradient", parameters: [
                "inputCenter": CIVector(x: r.midX, y: glossBottom + radius),
                "inputRadius0": radius - 1.5, "inputRadius1": radius,
                "inputColor0": CIColor(red: 1, green: 1, blue: 1, alpha: 1), "inputColor1": CIColor(red: 1, green: 1, blue: 1, alpha: 0),
            ])?.outputImage, let fade = CIFilter(name: "CILinearGradient", parameters: [
                "inputPoint0": CIVector(x: r.midX, y: r.maxY), "inputPoint1": CIVector(x: r.midX, y: glossBottom),
                "inputColor0": CIColor(red: 1, green: 1, blue: 1, alpha: t.gloss),
                "inputColor1": CIColor(red: 1, green: 1, blue: 1, alpha: t.gloss * 0.12),
            ])?.outputImage {
                let inset = silhouette.applyingFilter("CIMorphologyMinimum", parameters: [kCIInputRadiusKey: max(1, r.width * 0.025)])
                let gloss = fade.applyingFilter("CISourceInCompositing", parameters: [kCIInputBackgroundImageKey: disk])
                    .applyingFilter("CISourceInCompositing", parameters: [kCIInputBackgroundImageKey: inset])
                    .cropped(to: extent)
                img = gloss.applyingFilter("CISourceOverCompositing", parameters: [kCIInputBackgroundImageKey: img])
            }
        }

        return context.createCGImage(img.cropped(to: extent), from: extent, format: .RGBA8, colorSpace: Bitmap.colorSpace)
    }
}
