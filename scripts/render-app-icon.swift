import AppKit
import Foundation

let arguments = CommandLine.arguments.dropFirst()
let sourcePath = arguments.first ?? "native/Support/AppIconSource.png"
let outputPath = arguments.dropFirst().first ?? "native/Assets.xcassets/AppIcon.appiconset"

let sourceURL = URL(fileURLWithPath: sourcePath)
let outputDirectory = URL(fileURLWithPath: outputPath)
let fileManager = FileManager.default

guard let sourceImage = NSImage(contentsOf: sourceURL) else {
    fputs("Could not load source image at \(sourceURL.path)\n", stderr)
    exit(1)
}

try fileManager.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

let sizes = [16, 32, 64, 128, 256, 512, 1024]

func color(_ white: CGFloat, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(calibratedWhite: white / 255, alpha: alpha)
}

func iconImage(size: CGFloat) -> NSImage {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()
    defer { image.unlockFocus() }

    guard let context = NSGraphicsContext.current else { return image }
    context.imageInterpolation = .high

    let canvas = NSRect(x: 0, y: 0, width: size, height: size)
    NSColor.clear.setFill()
    canvas.fill()

    let tileRect = NSRect(
        x: size * 0.12,
        y: size * 0.12,
        width: size * 0.76,
        height: size * 0.76
    )
    let tilePath = NSBezierPath(
        roundedRect: tileRect,
        xRadius: size * 0.16,
        yRadius: size * 0.16
    )
    let tileGradient = NSGradient(colors: [color(5), color(14)])!
    tileGradient.draw(in: tilePath, angle: -90)
    NSColor(calibratedWhite: 1, alpha: 0.06).setStroke()
    tilePath.lineWidth = max(1, size * 0.004)
    tilePath.stroke()

    let imageRect = NSRect(
        x: tileRect.minX + size * 0.10,
        y: tileRect.minY + size * 0.10,
        width: tileRect.width - size * 0.20,
        height: tileRect.height - size * 0.20
    )
    let imageClip = NSBezierPath(
        roundedRect: imageRect,
        xRadius: size * 0.055,
        yRadius: size * 0.055
    )
    let sourceRect = NSRect(
        x: sourceImage.size.width * 0.01,
        y: sourceImage.size.height * 0.14,
        width: sourceImage.size.width * 0.98,
        height: sourceImage.size.height * 0.80
    )

    let shadow = NSShadow()
    shadow.shadowColor = NSColor(calibratedWhite: 0, alpha: 0.35)
    shadow.shadowBlurRadius = size * 0.03
    shadow.shadowOffset = NSSize(width: 0, height: -size * 0.012)

    NSGraphicsContext.saveGraphicsState()
    shadow.set()
    NSColor(calibratedWhite: 0.48, alpha: 0.95).setFill()
    imageClip.fill()
    NSGraphicsContext.restoreGraphicsState()

    NSGraphicsContext.saveGraphicsState()
    imageClip.addClip()
    sourceImage.draw(
        in: imageRect,
        from: sourceRect,
        operation: .copy,
        fraction: 1
    )
    NSGraphicsContext.restoreGraphicsState()

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
    let image = iconImage(size: CGFloat(size))
    guard let data = pngData(from: image, size: size) else {
        fputs("Failed to render size \(size)\n", stderr)
        exit(1)
    }
    let outputURL = outputDirectory.appendingPathComponent("icon-\(size).png")
    try data.write(to: outputURL)
    print("Wrote \(outputURL.path)")
}
