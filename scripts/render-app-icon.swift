import AppKit
import Foundation

let arguments = CommandLine.arguments.dropFirst()
let outputPath = arguments.dropFirst().first ?? "native/Assets.xcassets/AppIcon.appiconset"
let outputDirectory = URL(fileURLWithPath: outputPath)
let fileManager = FileManager.default

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

    let pageFill = color(228)
    let pageStroke = color(182)
    let ink = color(18)
    let photo = color(120)

    let paperRect = NSRect(
        x: size * 0.42,
        y: size * 0.24,
        width: size * 0.28,
        height: size * 0.44
    )
    let paperPath = NSBezierPath(
        roundedRect: paperRect,
        xRadius: size * 0.038,
        yRadius: size * 0.038
    )
    pageFill.setFill()
    paperPath.fill()
    pageStroke.setStroke()
    paperPath.lineWidth = max(1, size * 0.005)
    paperPath.stroke()

    let foldPath = NSBezierPath()
    foldPath.move(to: NSPoint(x: paperRect.maxX - size * 0.052, y: paperRect.maxY))
    foldPath.line(to: NSPoint(x: paperRect.maxX, y: paperRect.maxY))
    foldPath.line(to: NSPoint(x: paperRect.maxX, y: paperRect.maxY - size * 0.052))
    foldPath.close()
    color(205).setFill()
    foldPath.fill()

    let spineRect = NSRect(
        x: size * 0.27,
        y: size * 0.30,
        width: size * 0.045,
        height: size * 0.28
    )
    let spinePath = NSBezierPath(
        roundedRect: spineRect,
        xRadius: size * 0.023,
        yRadius: size * 0.023
    )
    pageFill.setFill()
    spinePath.fill()
    pageStroke.setStroke()
    spinePath.lineWidth = max(1, size * 0.004)
    spinePath.stroke()

    let lineHeight = size * 0.036
    let topLine1 = NSRect(x: size * 0.47, y: size * 0.56, width: size * 0.15, height: lineHeight)
    let topLine2 = NSRect(x: size * 0.47, y: size * 0.48, width: size * 0.14, height: lineHeight)
    let bottomLine = NSRect(x: size * 0.47, y: size * 0.32, width: size * 0.17, height: lineHeight)
    for rect in [topLine1, topLine2, bottomLine] {
        let path = NSBezierPath(roundedRect: rect, xRadius: lineHeight / 2, yRadius: lineHeight / 2)
        ink.setFill()
        path.fill()
    }

    let photoRect = NSRect(
        x: size * 0.47,
        y: size * 0.39,
        width: size * 0.066,
        height: size * 0.066
    )
    let photoPath = NSBezierPath(roundedRect: photoRect, xRadius: size * 0.012, yRadius: size * 0.012)
    photo.setFill()
    photoPath.fill()

    let shortLine1 = NSRect(x: size * 0.57, y: size * 0.42, width: size * 0.075, height: size * 0.03)
    let shortLine2 = NSRect(x: size * 0.57, y: size * 0.35, width: size * 0.075, height: size * 0.03)
    for rect in [shortLine1, shortLine2] {
        let path = NSBezierPath(roundedRect: rect, xRadius: rect.height / 2, yRadius: rect.height / 2)
        ink.setFill()
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
    let image = iconImage(size: CGFloat(size))
    guard let data = pngData(from: image, size: size) else {
        fputs("Failed to render size \(size)\n", stderr)
        exit(1)
    }
    let outputURL = outputDirectory.appendingPathComponent("icon-\(size).png")
    try data.write(to: outputURL)
    print("Wrote \(outputURL.path)")
}
