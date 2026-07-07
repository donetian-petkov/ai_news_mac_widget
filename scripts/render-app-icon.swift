import AppKit
import Foundation

let arguments = CommandLine.arguments.dropFirst()
let sourcePath = arguments.first ?? "native/Support/AppIconSource.png"
let outputPath = arguments.dropFirst().first ?? "native/Assets.xcassets/AppIcon.appiconset"

let fileManager = FileManager.default
let sourceURL = URL(fileURLWithPath: sourcePath)
let outputDirectory = URL(fileURLWithPath: outputPath)

guard let sourceImage = NSImage(contentsOf: sourceURL) else {
    fputs("Could not load source icon at \(sourceURL.path)\n", stderr)
    exit(1)
}

try fileManager.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

let sizes = [16, 32, 64, 128, 256, 512, 1024]

func pngData(from image: NSImage, size: Int) -> Data? {
    let targetSize = NSSize(width: size, height: size)
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
    NSBezierPath(rect: NSRect(origin: .zero, size: targetSize)).fill()
    sourceImage.draw(in: NSRect(origin: .zero, size: targetSize))

    NSGraphicsContext.restoreGraphicsState()
    return bitmap.representation(using: .png, properties: [:])
}

for size in sizes {
    guard let data = pngData(from: sourceImage, size: size) else {
        fputs("Failed to render size \(size)\n", stderr)
        exit(1)
    }
    let outputURL = outputDirectory.appendingPathComponent("icon-\(size).png")
    try data.write(to: outputURL)
    print("Wrote \(outputURL.path)")
}
