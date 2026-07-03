import SwiftUI
import WidgetKit
import AppIntents
import AINewsWidgetShared

@available(macOS 14.0, *)
struct WidgetCategoryEntity: AppEntity, Identifiable {
    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Category")
    static var defaultQuery = WidgetCategoryQuery()

    let id: Int
    let name: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)")
    }
}

@available(macOS 14.0, *)
struct WidgetCategoryQuery: EntityQuery {
    func entities(for identifiers: [Int]) async throws -> [WidgetCategoryEntity] {
        let snapshot = await MainActor.run { SnapshotStore.shared.loadSnapshot() }
        return snapshot.categories
            .filter { identifiers.contains($0.id) }
            .map { WidgetCategoryEntity(id: $0.id, name: $0.name) }
    }

    func suggestedEntities() async throws -> [WidgetCategoryEntity] {
        let snapshot = await MainActor.run { SnapshotStore.shared.loadSnapshot() }
        return snapshot.categories
            .filter { !$0.hidden }
            .sorted { $0.sortOrder == $1.sortOrder ? $0.name < $1.name : $0.sortOrder < $1.sortOrder }
            .map { WidgetCategoryEntity(id: $0.id, name: $0.name) }
    }
}

@available(macOS 14.0, *)
struct CategorySelectionIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Category"
    static var description = IntentDescription("Choose which AI News category this widget should show.")

    @Parameter(title: "Category")
    var category: WidgetCategoryEntity?

    init() {}
}

@available(macOS 14.0, *)
struct CategoryWidgetEntry: TimelineEntry {
    let date: Date
    let category: WidgetCategory?
    let stories: [WidgetStory]
}

@available(macOS 14.0, *)
struct MasterWidgetEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot
}

@available(macOS 14.0, *)
struct CategoryWidgetProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> CategoryWidgetEntry {
        CategoryWidgetEntry(
            date: Date(),
            category: WidgetCategory(id: 1, name: "Science", activeCount: 5),
            stories: [
                WidgetStory(id: "1", feedUrl: "feed", title: "Ingenuity images reveal a blade broke off", summary: "A short summary for the widget preview."),
                WidgetStory(id: "2", feedUrl: "feed", title: "A new material solved a long-time engineering issue", summary: "Another compact summary line.")
            ]
        )
    }

    func snapshot(for configuration: CategorySelectionIntent, in context: Context) async -> CategoryWidgetEntry {
        await entry(for: configuration)
    }

    func timeline(for configuration: CategorySelectionIntent, in context: Context) async -> Timeline<CategoryWidgetEntry> {
        let entry = await entry(for: configuration)
        return Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(300)))
    }

    private func entry(for configuration: CategorySelectionIntent) async -> CategoryWidgetEntry {
        let snapshot = await MainActor.run { SnapshotStore.shared.loadSnapshot() }
        let visibleCategories = snapshot.categories.filter { !$0.hidden }
        let category = configuration.category.flatMap { selected in
            visibleCategories.first(where: { $0.id == selected.id })
        } ?? visibleCategories.first ?? snapshot.categories.first
        let stories = category.flatMap { snapshot.storiesByCategory[String($0.id)] } ?? []
        return CategoryWidgetEntry(date: Date(), category: category, stories: stories)
    }
}

@available(macOS 14.0, *)
struct MasterWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> MasterWidgetEntry {
        MasterWidgetEntry(date: Date(), snapshot: WidgetSnapshot())
    }

    func getSnapshot(in context: Context, completion: @escaping (MasterWidgetEntry) -> Void) {
        Task {
            let snapshot = await MainActor.run { SnapshotStore.shared.loadSnapshot() }
            completion(MasterWidgetEntry(date: Date(), snapshot: snapshot))
        }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<MasterWidgetEntry>) -> Void) {
        Task {
            let snapshot = await MainActor.run { SnapshotStore.shared.loadSnapshot() }
            let entry = MasterWidgetEntry(date: Date(), snapshot: snapshot)
            completion(Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(300))))
        }
    }
}

@available(macOS 14.0, *)
struct CategoryWidgetView: View {
    let entry: CategoryWidgetEntry

    var body: some View {
        if let category = entry.category {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(category.name)
                        .font(.headline)
                        .foregroundStyle(AINewsTheme.textPrimary)
                    Spacer()
                    Button(intent: RefreshCategoryIntent(categoryID: category.id)) {
                        Image(systemName: "arrow.clockwise")
                    }
                    .buttonStyle(.plain)
                }

                ForEach(entry.stories.prefix(category.activeCount), id: \.storyKey) { story in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(story.title)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(AINewsTheme.accentBlue)
                            .lineLimit(2)
                        Text(story.summary ?? story.source ?? story.feedUrl)
                            .font(.caption)
                            .foregroundStyle(AINewsTheme.textSecondary)
                            .lineLimit(2)
                    }
                    if story.storyKey != entry.stories.prefix(category.activeCount).last?.storyKey {
                        Divider()
                            .overlay(AINewsTheme.panelBorder.opacity(0.4))
                    }
                }
            }
            .padding(16)
            .containerBackground(for: .widget) {
                AINewsTheme.background
            }
        } else {
            VStack(alignment: .leading, spacing: 8) {
                Text("AI News")
                    .font(.headline)
                    .foregroundStyle(AINewsTheme.textPrimary)
                Text("Open the app, sign in, and refresh categories to populate this widget.")
                    .font(.caption)
                    .foregroundStyle(AINewsTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(16)
            .containerBackground(for: .widget) {
                AINewsTheme.background
            }
        }
    }
}

@available(macOS 14.0, *)
struct MasterWidgetView: View {
    let entry: MasterWidgetEntry

    private var visibleCategories: [WidgetCategory] {
        entry.snapshot.categories
            .filter { !$0.hidden }
            .sorted { $0.sortOrder == $1.sortOrder ? $0.name < $1.name : $0.sortOrder < $1.sortOrder }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("AI News")
                    .font(.headline)
                    .foregroundStyle(AINewsTheme.textPrimary)
                Spacer()
                Text("\(visibleCategories.count) live")
                    .font(.caption)
                    .foregroundStyle(AINewsTheme.textMuted)
            }

            ForEach(Array(visibleCategories.prefix(4)), id: \.id) { category in
                let topStory = entry.snapshot.storiesByCategory[String(category.id)]?.first
                VStack(alignment: .leading, spacing: 4) {
                    Text(category.name)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AINewsTheme.accentCyan)
                    Text(topStory?.title ?? "No stories cached yet")
                        .font(.caption)
                        .foregroundStyle(AINewsTheme.textSecondary)
                        .lineLimit(2)
                }
                if category.id != visibleCategories.prefix(4).last?.id {
                    Divider()
                        .overlay(AINewsTheme.panelBorder.opacity(0.35))
                }
            }
        }
        .padding(16)
        .containerBackground(for: .widget) {
            AINewsTheme.background
        }
    }
}

@available(macOS 14.0, *)
struct CategoryWidget: Widget {
    let kind = "AINewsCategoryWidget"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: kind, intent: CategorySelectionIntent.self, provider: CategoryWidgetProvider()) { entry in
            CategoryWidgetView(entry: entry)
        }
        .configurationDisplayName("AI News Category")
        .description("Show one category with five to ten image-free AI News stories.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

@available(macOS 14.0, *)
struct MasterWidget: Widget {
    let kind = "AINewsMasterWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: MasterWidgetProvider()) { entry in
            MasterWidgetView(entry: entry)
        }
        .configurationDisplayName("AI News Master")
        .description("See the live category overview across your AI News widget workspace.")
        .supportedFamilies([.systemMedium, .systemLarge])
    }
}

@available(macOS 14.0, *)
@main
struct AINewsWidgetBundle: WidgetBundle {
    var body: some Widget {
        MasterWidget()
        CategoryWidget()
    }
}
