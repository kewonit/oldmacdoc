// Crops dock captures for the website and makes the link-preview card.
//
//   images crop <pad> <left|-> <width|-> <in.png>...
//     Crops every capture to the same rectangle: what's drawn in any of them (alpha above 0), plus
//     <pad> pixels, so shots of the same dock line up. With <left> and <width> (pixels), that range
//     is kept across instead. Writes <in>.crop.png next to each input.
//
//   images icons <in.png> <row> <count>
//     Finds the icons along pixel row <row> (counted up from the bottom; pick one through the icons,
//     above the shelf) and prints "<left> <width>" in pixels for the <count> icons nearest the
//     middle, from halfway into the gap before the first to halfway into the gap after the last, so
//     a crop never cuts an icon in half.
//
//   images card <in.png> <out.png> <width> <height> <red> <green> <blue>
//     Centres the (transparent) image on a solid colour, at most 92% of the card's width, for
//     services that don't show transparency.
import AppKit

func load(_ path: String) -> CGImage {
    guard let image = NSImage(contentsOfFile: path)?.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
        FileHandle.standardError.write(Data("Can't read \(path)\n".utf8))
        exit(1)
    }
    return image
}

func save(_ image: CGImage, _ path: String) {
    let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
    guard let data, (try? data.write(to: URL(fileURLWithPath: path))) != nil else {
        FileHandle.standardError.write(Data("Can't write \(path)\n".utf8))
        exit(1)
    }
}

/// Draws `image` into a fresh RGBA context (row 0 at the top), so its alpha can be read.
func pixels(_ image: CGImage) -> (data: [UInt8], width: Int, height: Int) {
    let w = image.width, h = image.height
    var data = [UInt8](repeating: 0, count: w * h * 4)
    data.withUnsafeMutableBytes { raw in
        let ctx = CGContext(data: raw.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
    }
    return (data, w, h)
}

/// The rectangle that holds everything drawn, in image coordinates (top-left origin).
func drawnBounds(_ image: CGImage) -> CGRect? {
    let (data, w, h) = pixels(image)
    var minX = w, minY = h, maxX = -1, maxY = -1
    data.withUnsafeBufferPointer { p in
        for y in 0..<h {
            let row = y * w * 4
            for x in 0..<w where p[row + x * 4 + 3] > 0 {
                minX = min(minX, x); maxX = max(maxX, x)
                minY = min(minY, y); maxY = max(maxY, y)
            }
        }
    }
    return maxX < 0 ? nil : CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
}

let args = Array(CommandLine.arguments.dropFirst())
switch args.first {
case "crop" where args.count >= 5:
    let pad = CGFloat(Int(args[1]) ?? 0)
    let paths = Array(args.dropFirst(4))
    let images = paths.map(load)
    guard var rect = images.compactMap(drawnBounds).reduce(nil, { (r: CGRect?, b) in r?.union(b) ?? b }) else {
        FileHandle.standardError.write(Data("Nothing is drawn in the captures\n".utf8))
        exit(1)
    }
    rect = rect.insetBy(dx: -pad, dy: -pad)
    if let left = Int(args[2]), let width = Int(args[3]) {
        rect.origin.x = CGFloat(left)
        rect.size.width = CGFloat(width)
    }
    rect = rect.intersection(CGRect(x: 0, y: 0, width: images[0].width, height: images[0].height)).integral
    for (path, image) in zip(paths, images) {
        guard let cropped = image.cropping(to: rect) else { exit(1) }
        save(cropped, (path as NSString).deletingPathExtension + ".crop.png")
    }
    print("\(Int(rect.width)) \(Int(rect.height))")
case "icons" where args.count == 4:
    let (data, w, h) = pixels(load(args[1]))
    let row = h - 1 - min(max(Int(args[2]) ?? 0, 0), h - 1)
    let count = Int(args[3]) ?? 8
    // Runs of drawn pixels along the row are the icons; the clear stretches between them are gaps.
    var runs: [(start: Int, end: Int)] = []
    var start: Int?
    for x in 0...w {
        let drawn = x < w && data[(row * w + x) * 4 + 3] > 8
        if drawn, start == nil { start = x }
        if !drawn, let s = start { runs.append((s, x)); start = nil }
    }
    runs = runs.filter { $0.end - $0.start > 20 } // icons, not stray antialiasing
    guard runs.count >= count else {
        FileHandle.standardError.write(Data("Found \(runs.count) icons on row \(args[2]), need \(count)\n".utf8))
        exit(1)
    }
    let middle = Double(w) / 2
    let first = runs.indices.dropLast(count - 1).min { a, b in
        abs(Double(runs[a].start + runs[a + count - 1].end) / 2 - middle) < abs(Double(runs[b].start + runs[b + count - 1].end) / 2 - middle)
    }!
    let last = first + count - 1
    let left = first > 0 ? (runs[first - 1].end + runs[first].start) / 2 : max(0, runs[first].start - 8)
    let right = last + 1 < runs.count ? (runs[last].end + runs[last + 1].start) / 2 : min(w, runs[last].end + 8)
    print("\(left) \(right - left)")
case "card" where args.count == 8:
    let image = load(args[1])
    let w = Int(args[3])!, h = Int(args[4])!
    let color = CGColor(srgbRed: CGFloat(Double(args[5])!) / 255, green: CGFloat(Double(args[6])!) / 255,
                        blue: CGFloat(Double(args[7])!) / 255, alpha: 1)
    let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.setFillColor(color)
    ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
    ctx.interpolationQuality = .high
    let scale = min(Double(w) * 0.92 / Double(image.width), Double(h) * 0.92 / Double(image.height))
    let size = CGSize(width: Double(image.width) * scale, height: Double(image.height) * scale)
    ctx.draw(image, in: CGRect(x: (CGFloat(w) - size.width) / 2, y: (CGFloat(h) - size.height) / 2,
                               width: size.width, height: size.height))
    save(ctx.makeImage()!, args[2])
default:
    FileHandle.standardError.write(Data("Usage: images crop <pad> <left|-> <width|-> <in.png>...\n       images card <in.png> <out.png> <width> <height> <r> <g> <b>\n".utf8))
    exit(1)
}
