import AppKit

// Renders AppIcon.iconset. Usage: swift Scripts/make-icon.swift <output-dir>

let outputDirectory = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon.iconset"
try? FileManager.default.createDirectory(atPath: outputDirectory, withIntermediateDirectories: true)

func renderPNG(pixels: Int) -> Data? {
    let size = NSSize(width: pixels, height: pixels)
    let image = NSImage(size: size)
    image.lockFocus()
    guard let context = NSGraphicsContext.current?.cgContext else { image.unlockFocus(); return nil }

    let side = CGFloat(pixels)
    let inset = side * 0.06
    let rounded = NSBezierPath(
        roundedRect: NSRect(x: inset, y: inset, width: side - inset * 2, height: side - inset * 2),
        xRadius: side * 0.225, yRadius: side * 0.225
    )
    rounded.addClip()

    let colors = [
        NSColor(srgbRed: 0.24, green: 0.56, blue: 1.00, alpha: 1).cgColor,
        NSColor(srgbRed: 0.09, green: 0.30, blue: 0.86, alpha: 1).cgColor,
    ] as CFArray
    let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1])!
    context.drawLinearGradient(gradient, start: CGPoint(x: 0, y: side), end: CGPoint(x: side, y: 0), options: [])

    let glyphConfig = NSImage.SymbolConfiguration(pointSize: side * 0.44, weight: .semibold)
    if let symbol = NSImage(systemSymbolName: "sparkles", accessibilityDescription: nil)?
        .withSymbolConfiguration(glyphConfig) {
        let glyphSize = symbol.size
        let white = NSImage(size: glyphSize)
        white.lockFocus()
        NSColor.white.setFill()
        NSRect(origin: .zero, size: glyphSize).fill()
        symbol.draw(at: .zero, from: NSRect(origin: .zero, size: glyphSize),
                    operation: .destinationIn, fraction: 1)
        white.unlockFocus()
        let origin = NSPoint(x: (side - glyphSize.width) / 2, y: (side - glyphSize.height) / 2)
        white.draw(at: origin, from: NSRect(origin: .zero, size: glyphSize),
                   operation: .sourceOver, fraction: 0.96)
    }

    image.unlockFocus()

    guard
        let tiff = image.tiffRepresentation,
        let rep = NSBitmapImageRep(data: tiff)
    else { return nil }
    return rep.representation(using: .png, properties: [:])
}

let variants: [(name: String, pixels: Int)] = [
    ("icon_16x16", 16), ("icon_16x16@2x", 32),
    ("icon_32x32", 32), ("icon_32x32@2x", 64),
    ("icon_128x128", 128), ("icon_128x128@2x", 256),
    ("icon_256x256", 256), ("icon_256x256@2x", 512),
    ("icon_512x512", 512), ("icon_512x512@2x", 1024),
]

for variant in variants {
    guard let data = renderPNG(pixels: variant.pixels) else {
        FileHandle.standardError.write(Data("failed to render \(variant.name)\n".utf8))
        exit(1)
    }
    let url = URL(fileURLWithPath: outputDirectory).appendingPathComponent("\(variant.name).png")
    try? data.write(to: url)
}

print("wrote \(variants.count) icon variants to \(outputDirectory)")
