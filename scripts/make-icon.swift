import AppKit

// Renders the Strays app icon: a plug glyph on a teal→indigo gradient
// squircle, exported as an .iconset and compiled to dist/AppIcon.icns.

func drawIcon(pixel: Int) -> NSBitmapImageRep {
    let size = CGFloat(pixel)
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: pixel, pixelsHigh: pixel,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: size, height: size)

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

    // macOS icon grid: content sits inset with a transparent margin.
    let inset = size * 0.085
    let rect = NSRect(x: inset, y: inset, width: size - inset * 2, height: size - inset * 2)
    let radius = rect.width * 0.235
    let squircle = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)

    // Gradient background: deep indigo → teal.
    let gradient = NSGradient(colors: [
        NSColor(srgbRed: 0x37/255, green: 0x35/255, blue: 0x8F/255, alpha: 1),
        NSColor(srgbRed: 0x22/255, green: 0x6E/255, blue: 0x77/255, alpha: 1)
    ])!
    gradient.draw(in: squircle, angle: -90)

    // Subtle top sheen.
    NSColor.white.withAlphaComponent(0.10).setFill()
    let sheen = NSBezierPath(roundedRect: NSRect(x: rect.minX, y: rect.midY, width: rect.width, height: rect.height/2), xRadius: radius, yRadius: radius)
    sheen.addClip()
    squircle.fill()
    NSGraphicsContext.current?.cgContext.resetClip()

    // Plug glyph, white, centered.
    let config = NSImage.SymbolConfiguration(pointSize: size * 0.46, weight: .semibold)
    if let symbol = NSImage(systemSymbolName: "powerplug.fill", accessibilityDescription: nil)?
        .withSymbolConfiguration(config) {
        let glyph = NSRect(
            x: (size - symbol.size.width) / 2,
            y: (size - symbol.size.height) / 2,
            width: symbol.size.width, height: symbol.size.height)
        symbol.draw(in: glyph)
        NSColor.white.set()
        glyph.fill(using: .sourceAtop)
    }

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

let root = FileManager.default.currentDirectoryPath
let iconset = "\(root)/dist/AppIcon.iconset"
try? FileManager.default.createDirectory(atPath: iconset, withIntermediateDirectories: true)

let variants: [(name: String, px: Int)] = [
    ("icon_16x16", 16), ("icon_16x16@2x", 32),
    ("icon_32x32", 32), ("icon_32x32@2x", 64),
    ("icon_128x128", 128), ("icon_128x128@2x", 256),
    ("icon_256x256", 256), ("icon_256x256@2x", 512),
    ("icon_512x512", 512), ("icon_512x512@2x", 1024),
]
for variant in variants {
    let rep = drawIcon(pixel: variant.px)
    if let data = rep.representation(using: .png, properties: [:]) {
        try? data.write(to: URL(fileURLWithPath: "\(iconset)/\(variant.name).png"))
    }
}
print("wrote iconset to \(iconset)")
