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
                        .lineLimit(2)
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
