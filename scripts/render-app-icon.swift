import AppKit
import Foundation

let arguments = CommandLine.arguments.dropFirst()
let outputPath = arguments.first ?? "native/Assets.xcassets/AppIcon.appiconset"
let outputDirectory = URL(fileURLWithPath: outputPath)
let fileManager = FileManager.default

try fileManager.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

let sizes = [16, 32, 64, 128, 256, 512, 1024]

func color(_ white: CGFloat, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(calibratedWhite: white / 255, alpha: alpha)
}

func newspaperImage(size: CGFloat) -> NSImage {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()
    defer { image.unlockFocus() }

    NSGraphicsContext.current?.imageInterpolation = .high

    let canvas = NSRect(x: 0, y: 0, width: size, height: size)
    NSColor.clear.setFill()
    canvas.fill()

    let glyphColor = color(8)
    let accentColor = color(78)
    let lineColor = color(229)

    let paperRect = NSRect(
        x: size * 0.36,
        y: size * 0.14,
        width: size * 0.44,
        height: size * 0.64
    )
    let paperPath = NSBezierPath(roundedRect: paperRect, xRadius: size * 0.045, yRadius: size * 0.045)
    glyphColor.setFill()
    paperPath.fill()

    let spineRect = NSRect(
        x: size * 0.23,
        y: size * 0.22,
        width: size * 0.105,
        height: size * 0.48
    )
    let spinePath = NSBezierPath(roundedRect: spineRect, xRadius: size * 0.052, yRadius: size * 0.052)
    glyphColor.setFill()
    spinePath.fill()

    let lineHeight = size * 0.06
    let longLineWidth = size * 0.24
    let topLine1 = NSRect(x: size * 0.45, y: size * 0.61, width: longLineWidth, height: lineHeight)
    let topLine2 = NSRect(x: size * 0.45, y: size * 0.49, width: longLineWidth * 0.92, height: lineHeight)
    let bottomLine = NSRect(x: size * 0.45, y: size * 0.24, width: longLineWidth * 1.1, height: lineHeight)

    [topLine1, topLine2, bottomLine].forEach { rect in
        let path = NSBezierPath(roundedRect: rect, xRadius: lineHeight / 2, yRadius: lineHeight / 2)
        lineColor.setFill()
        path.fill()
    }

    let squareRect = NSRect(
        x: size * 0.46,
        y: size * 0.36,
        width: size * 0.11,
        height: size * 0.11
    )
    let squarePath = NSBezierPath(roundedRect: squareRect, xRadius: size * 0.018, yRadius: size * 0.018)
    accentColor.setFill()
    squarePath.fill()

    let shortLineWidth = size * 0.11
    let shortLine1 = NSRect(x: size * 0.60, y: size * 0.40, width: shortLineWidth, height: size * 0.05)
    let shortLine2 = NSRect(x: size * 0.60, y: size * 0.31, width: shortLineWidth, height: size * 0.05)

    [shortLine1, shortLine2].forEach { rect in
        let path = NSBezierPath(roundedRect: rect, xRadius: rect.height / 2, yRadius: rect.height / 2)
        lineColor.setFill()
        path.fill()
    }

    return image
}

func pngData(from image: NSImage, size: Int) -> Data? {
    let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: size,
        pixelsHigh: size,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    )

    guard let bitmap else { return nil }

    NSGraphicsContext.saveGraphicsState()
    guard let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
        NSGraphicsContext.restoreGraphicsState()
        return nil
    }
    NSGraphicsContext.current = context
    context.imageInterpolation = .high
    NSColor.clear.setFill()
    NSBezierPath(rect: NSRect(x: 0, y: 0, width: size, height: size)).fill()
    image.draw(in: NSRect(x: 0, y: 0, width: size, height: size))
    NSGraphicsContext.restoreGraphicsState()

    return bitmap.representation(using: .png, properties: [:])
}

for size in sizes {
    let image = newspaperImage(size: CGFloat(size))
    guard let data = pngData(from: image, size: size) else {
        fputs("Failed to render size \(size)\n", stderr)
        exit(1)
    }
    let outputURL = outputDirectory.appendingPathComponent("icon-\(size).png")
    try data.write(to: outputURL)
    print("Wrote \(outputURL.path)")
}
