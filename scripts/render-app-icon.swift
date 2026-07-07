import AppKit
import Foundation

let fileManager = FileManager.default
let outputDirectory = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "")

guard !outputDirectory.path.isEmpty else {
    fputs("Usage: swift render-app-icon.swift <iconset-directory>\n", stderr)
    exit(1)
}

try fileManager.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

let sizes = [16, 32, 64, 128, 256, 512, 1024]

func color(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(calibratedRed: red / 255, green: green / 255, blue: blue / 255, alpha: alpha)
}

func drawIcon(size: CGFloat) -> NSImage {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()
    defer { image.unlockFocus() }

    NSGraphicsContext.current?.imageInterpolation = .high

    let canvas = NSRect(x: 0, y: 0, width: size, height: size)
    let outerInset = size * 0.035
    let outerRect = canvas.insetBy(dx: outerInset, dy: outerInset)
    let outerRadius = size * 0.23
    let outerPath = NSBezierPath(roundedRect: outerRect, xRadius: outerRadius, yRadius: outerRadius)

    let outerGradient = NSGradient(colors: [
        color(122, 130, 133),
        color(162, 169, 172),
        color(111, 118, 121)
    ])!
    outerGradient.draw(in: outerPath, angle: -90)

    color(12, 14, 18, 0.4).setStroke()
    outerPath.lineWidth = max(2, size * 0.01)
    outerPath.stroke()

    let innerGlowRect = outerRect.insetBy(dx: size * 0.05, dy: size * 0.05)
    let innerGlowPath = NSBezierPath(roundedRect: innerGlowRect, xRadius: size * 0.18, yRadius: size * 0.18)
    let innerGlow = NSGradient(colors: [
        color(255, 255, 255, 0.16),
        color(255, 255, 255, 0.03)
    ])!
    innerGlow.draw(in: innerGlowPath, angle: 90)

    let bodyInsetX = size * 0.28
    let bodyInsetTop = size * 0.21
    let bodyInsetBottom = size * 0.2
    let bodyRect = NSRect(
        x: bodyInsetX,
        y: bodyInsetBottom,
        width: size - bodyInsetX * 2,
        height: size - bodyInsetTop - bodyInsetBottom
    )

    let bodyRadius = size * 0.06
    let bodyPath = NSBezierPath(roundedRect: bodyRect, xRadius: bodyRadius, yRadius: bodyRadius)
    color(10, 11, 14).setFill()
    bodyPath.fill()

    let spineWidth = size * 0.09
    let spineRect = NSRect(
        x: bodyRect.minX - spineWidth * 1.04,
        y: bodyRect.minY + size * 0.035,
        width: spineWidth,
        height: bodyRect.height - size * 0.07
    )
    let spinePath = NSBezierPath(roundedRect: spineRect, xRadius: spineWidth * 0.48, yRadius: spineWidth * 0.48)
    color(10, 11, 14).setFill()
    spinePath.fill()

    let headlineRect = NSRect(
        x: bodyRect.minX + size * 0.075,
        y: bodyRect.maxY - size * 0.145,
        width: bodyRect.width * 0.52,
        height: size * 0.04
    )
    let headlinePath = NSBezierPath(roundedRect: headlineRect, xRadius: headlineRect.height / 2, yRadius: headlineRect.height / 2)
    color(235, 238, 243).setFill()
    headlinePath.fill()

    let cardWidth = bodyRect.width * 0.27
    let cardHeight = bodyRect.height * 0.23
    let cardRect = NSRect(
        x: bodyRect.maxX - cardWidth - size * 0.06,
        y: bodyRect.maxY - cardHeight - size * 0.08,
        width: cardWidth,
        height: cardHeight
    )
    let cardPath = NSBezierPath(roundedRect: cardRect, xRadius: size * 0.03, yRadius: size * 0.03)
    color(52, 60, 72).setFill()
    cardPath.fill()

    let textBarHeight = size * 0.035
    let bars: [(CGFloat, CGFloat, CGFloat)] = [
        (bodyRect.maxY - size * 0.245, 0.46, 1),
        (bodyRect.maxY - size * 0.31, 0.49, 0.9),
        (bodyRect.maxY - size * 0.45, 0.62, 0.95),
        (bodyRect.maxY - size * 0.58, 0.5, 0.82),
        (bodyRect.maxY - size * 0.67, 0.56, 0.88)
    ]

    for (y, widthFactor, alpha) in bars {
        let rect = NSRect(
            x: bodyRect.minX + size * 0.07,
            y: y,
            width: bodyRect.width * widthFactor,
            height: textBarHeight
        )
        let path = NSBezierPath(roundedRect: rect, xRadius: textBarHeight / 2, yRadius: textBarHeight / 2)
        color(231, 235, 241, alpha).setFill()
        path.fill()
    }

    let dotRadius = size * 0.028
    let dotRect = NSRect(
        x: bodyRect.midX - dotRadius,
        y: bodyRect.minY + size * 0.055,
        width: dotRadius * 2,
        height: dotRadius * 2
    )
    let dotPath = NSBezierPath(ovalIn: dotRect)
    color(10, 11, 14).setFill()
    dotPath.fill()

    return image
}

for size in sizes {
    let image = drawIcon(size: CGFloat(size))
    guard
        let tiff = image.tiffRepresentation,
        let representation = NSBitmapImageRep(data: tiff),
        let pngData = representation.representation(using: .png, properties: [:])
    else {
        fputs("Failed to render icon at \(size)\n", stderr)
        exit(1)
    }

    let outputURL = outputDirectory.appendingPathComponent("icon-\(size).png")
    try pngData.write(to: outputURL)
    print("Wrote \(outputURL.path)")
}
