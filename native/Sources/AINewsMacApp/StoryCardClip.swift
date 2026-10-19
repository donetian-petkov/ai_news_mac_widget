import AppKit
import SwiftUI

/// Copies a story card to the clipboard as a picture of the card as the widget shows it, to
/// paste and share. Only the picture goes on the clipboard: with text alongside, most apps
/// paste the text instead.
@MainActor
enum StoryCardClip {
    static func copyImage<Content: View>(of content: Content) -> Bool {
        let renderer = ImageRenderer(content: content)
        renderer.scale = NSScreen.main?.backingScaleFactor ?? 2
        guard let image = renderer.nsImage,
              let tiff = image.tiffRepresentation,
              let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) else { return false }
        let item = NSPasteboardItem()
        item.setData(png, forType: .png)
        item.setData(tiff, forType: .tiff)
        NSPasteboard.general.clearContents()
        return NSPasteboard.general.writeObjects([item])
    }
}
