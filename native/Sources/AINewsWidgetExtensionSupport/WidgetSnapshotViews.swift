import SwiftUI
import AINewsWidgetShared

public struct CategoryWidgetPreviewView: View {
    public let category: WidgetCategory
    public let stories: [WidgetStory]

    public init(category: WidgetCategory, stories: [WidgetStory]) {
        self.category = category
        self.stories = stories
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(category.name)
                .font(.headline)
                .foregroundStyle(AINewsTheme.textPrimary)
            ForEach(stories.prefix(category.activeCount), id: \.storyKey) { story in
                VStack(alignment: .leading, spacing: 3) {
                    Text(story.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AINewsTheme.accentBlue)
                        .underline(story.hasNeutralTitle, color: AINewsTheme.accentCyan.opacity(0.85))
                        .lineLimit(2)
                    if story.hasNeutralTitle {
                        SnapshotNeutralTitleMarker()
                    }
                    Text(story.summary ?? story.source ?? story.feedUrl)
                        .font(.caption)
                        .foregroundStyle(AINewsTheme.textSecondary)
                        .lineLimit(2)
                }
                if story.id != stories.prefix(category.activeCount).last?.id {
                    Divider().overlay(AINewsTheme.panelBorder.opacity(0.35))
                }
            }
        }
        .padding(16)
        .aiNewsPanelStyle()
    }
}

private struct SnapshotNeutralTitleMarker: View {
    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: "checkmark.seal.fill")
            Text("Neutral")
        }
        .font(.caption2.weight(.bold))
        .foregroundStyle(AINewsTheme.accentCyan)
        .padding(.horizontal, 7)
        .padding(.vertical, 2)
        .background(
            Capsule(style: .continuous)
                .fill(AINewsTheme.accentCyan.opacity(0.14))
        )
        .overlay(
            Capsule(style: .continuous)
                .stroke(AINewsTheme.accentCyan.opacity(0.55), lineWidth: 1)
        )
    }
}
