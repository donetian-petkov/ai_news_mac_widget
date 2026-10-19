import AppKit
import SwiftUI
import AINewsWidgetShared

/// Copies a story card to the clipboard for sharing: a picture of the card for apps that take
/// images (Messages, Slack, Mail) and the same text with the link for apps that take text.
@MainActor
enum StoryCardClip {
    static func copy(title: String, summary: String?, source: String, date: Date?, link: String?, coverURL: URL?) async {
        let cover = await loadCover(coverURL)
        let card = StoryCardImage(title: title, summary: summary, source: source, date: date, link: link, cover: cover)
        let renderer = ImageRenderer(content: card)
        renderer.scale = 2
        let item = NSPasteboardItem()
        if let image = renderer.nsImage,
           let tiff = image.tiffRepresentation,
           let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) {
            item.setData(png, forType: .png)
        }
        item.setString(text(title: title, summary: summary, source: source, date: date, link: link), forType: .string)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects([item])
    }

    static func text(title: String, summary: String?, source: String, date: Date?, link: String?) -> String {
        var lines = [title]
        if let summary, !summary.isEmpty { lines.append(summary) }
        var footer = source
        if let date { footer += " · " + date.formatted(date: .abbreviated, time: .shortened) }
        lines.append(footer)
        if let link, !link.isEmpty { lines.append(link) }
        return lines.joined(separator: "\n")
    }

    /// The cover is shown in the widget by an async view, which a rendered image cannot wait
    /// for, so it is fetched here; a slow or missing cover just leaves it out.
    private static func loadCover(_ url: URL?) async -> NSImage? {
        guard let url else { return nil }
        var request = URLRequest(url: url)
        request.timeoutInterval = 4
        guard let (data, _) = try? await URLSession.shared.data(for: request) else { return nil }
        return NSImage(data: data)
    }
}

/// The card as it is copied. It has its own solid light colours: the widget's see-through
/// glass would come out as an empty grey box once pasted somewhere else.
private struct StoryCardImage: View {
    let title: String
    let summary: String?
    let source: String
    let date: Date?
    let link: String?
    let cover: NSImage?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let cover {
                Image(nsImage: cover)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 472, height: 220)
                    .clipped()
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            HStack(spacing: 6) {
                Text(source)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color(red: 0.0, green: 0.42, blue: 0.55))
                if let date {
                    Text("· " + date.formatted(date: .abbreviated, time: .shortened))
                        .font(.system(size: 12))
                        .foregroundStyle(Color(white: 0.38))
                }
            }
            .lineLimit(1)
            Text(title)
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(Color(white: 0.08))
                .fixedSize(horizontal: false, vertical: true)
            if let summary, !summary.isEmpty {
                Text(summary)
                    .font(.system(size: 14))
                    .foregroundStyle(Color(white: 0.22))
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let host = link.flatMap({ URL(string: $0)?.host }) {
                Text(host)
                    .font(.system(size: 11))
                    .foregroundStyle(Color(white: 0.45))
            }
        }
        .padding(16)
        .frame(width: 504, alignment: .leading)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}
