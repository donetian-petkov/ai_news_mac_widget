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

    let tileRect = NSRect(
        x: size * 0.12,
        y: size * 0.12,
        width: size * 0.76,
        height: size * 0.76
    )
    let tilePath = NSBezierPath(
        roundedRect: tileRect,
        xRadius: size * 0.15,
        yRadius: size * 0.15
    )
    let tileGradient = NSGradient(colors: [color(6), color(12)])!
    tileGradient.draw(in: tilePath, angle: -90)
    let tileHighlight = NSGradient(colors: [
        NSColor(calibratedWhite: 1, alpha: 0.08),
        NSColor(calibratedWhite: 1, alpha: 0.0)
    ])!
    tileHighlight.draw(in: tilePath, angle: -90)

    let badgeRect = NSRect(
        x: size * 0.34,
        y: size * 0.21,
        width: size * 0.42,
        height: size * 0.50
    )
    let badgePath = NSBezierPath(
        roundedRect: badgeRect,
        xRadius: size * 0.06,
        yRadius: size * 0.06
    )
    let badgeGradient = NSGradient(colors: [color(72), color(58)])!
    badgeGradient.draw(in: badgePath, angle: -90)
    NSColor(calibratedWhite: 1, alpha: 0.08).setStroke()
    badgePath.lineWidth = max(1, size * 0.005)
    badgePath.stroke()

    let glyphFill = color(10)
    let glyphDetail = color(240)
    let accentColor = color(156)

    let paperRect = NSRect(
        x: size * 0.42,
        y: size * 0.25,
        width: size * 0.28,
        height: size * 0.42
    )
    let paperPath = NSBezierPath(roundedRect: paperRect, xRadius: size * 0.04, yRadius: size * 0.04)
    glyphFill.setFill()
    paperPath.fill()

    let spineRect = NSRect(
        x: size * 0.27,
        y: size * 0.31,
        width: size * 0.05,
        height: size * 0.27
    )
    let spinePath = NSBezierPath(roundedRect: spineRect, xRadius: size * 0.03, yRadius: size * 0.03)
    glyphFill.setFill()
    spinePath.fill()

    let lineHeight = size * 0.038
    let longLineWidth = size * 0.17
    let topLine1 = NSRect(x: size * 0.48, y: size * 0.56, width: longLineWidth, height: lineHeight)
    let topLine2 = NSRect(x: size * 0.48, y: size * 0.48, width: longLineWidth * 0.88, height: lineHeight)
    let bottomLine = NSRect(x: size * 0.48, y: size * 0.33, width: longLineWidth * 1.02, height: lineHeight)

    [topLine1, topLine2, bottomLine].forEach { rect in
        let path = NSBezierPath(roundedRect: rect, xRadius: lineHeight / 2, yRadius: lineHeight / 2)
        glyphDetail.setFill()
        path.fill()
    }

    let squareRect = NSRect(
        x: size * 0.49,
        y: size * 0.39,
        width: size * 0.072,
        height: size * 0.072
    )
    let squarePath = NSBezierPath(roundedRect: squareRect, xRadius: size * 0.018, yRadius: size * 0.018)
    accentColor.setFill()
    squarePath.fill()

    let shortLineWidth = size * 0.075
    let shortLine1 = NSRect(x: size * 0.60, y: size * 0.42, width: shortLineWidth, height: size * 0.032)
    let shortLine2 = NSRect(x: size * 0.60, y: size * 0.36, width: shortLineWidth, height: size * 0.032)

    [shortLine1, shortLine2].forEach { rect in
        let path = NSBezierPath(roundedRect: rect, xRadius: rect.height / 2, yRadius: rect.height / 2)
        glyphDetail.setFill()
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
