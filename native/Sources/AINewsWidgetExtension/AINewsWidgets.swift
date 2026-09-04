import SwiftUI
import WidgetKit
import AppIntents
import AINewsWidgetShared

private let widgetDynamicTypeSize = AINewsFontPreferenceStore.storedWidgetFontSize().dynamicTypeSize

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
    let pendingCount: Int
    let alertCount: Int
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
            ],
            pendingCount: 2,
            alertCount: 1
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
        let pendingCount = category.flatMap { snapshot.pendingByCategory[String($0.id)] } ?? 0
        return CategoryWidgetEntry(date: Date(), category: category, stories: stories, pendingCount: pendingCount, alertCount: snapshot.monitorAlerts.count)
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
    @Environment(\.widgetFamily) private var family
    let entry: CategoryWidgetEntry

    private func storyURL(_ story: WidgetStory, action: WidgetDeepLinkAction = .open) -> URL? {
        guard let category = entry.category else { return nil }
        return WidgetDeepLink.storyURL(
            categoryID: category.id,
            storyID: story.id,
            feedURL: story.feedUrl,
            action: action
        )
    }

    var body: some View {
        if let category = entry.category {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(category.name)
                        .font(.headline)
                        .foregroundStyle(AINewsTheme.textPrimary)
                    Spacer()
                    if family != .systemSmall {
                        if category.activeCount > category.preferredCount {
                            Button(intent: ResetCategoryIntent(categoryID: category.id)) {
                                Image(systemName: "arrow.up.to.line")
                            }
                            .buttonStyle(.plain)
                        } else {
                            Button(intent: ExpandCategoryIntent(categoryID: category.id)) {
                                Image(systemName: "arrow.down.to.line")
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    Button(intent: RefreshCategoryIntent(categoryID: category.id)) {
                        Image(systemName: "arrow.clockwise")
                    }
                    .buttonStyle(.plain)
                }

                if entry.pendingCount > 0 {
                    Text("\(entry.pendingCount) pending")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(AINewsTheme.accentGold)
                }
                if entry.alertCount > 0 {
                    Label("\(entry.alertCount) monitor alert\(entry.alertCount == 1 ? "" : "s")", systemImage: "bell.badge.fill")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(AINewsTheme.accentGold)
                }

                if family != .systemSmall {
                    HStack(spacing: 12) {
                        Button(intent: ToggleCategoryVisibilityIntent(categoryID: category.id)) {
                            Label(category.hidden ? "Show" : "Hide", systemImage: category.hidden ? "eye.slash" : "eye")
                        }
                        .buttonStyle(.plain)

                        Text(category.activeCount > category.preferredCount ? "10-story view" : "5-story view")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(AINewsTheme.textMuted)
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AINewsTheme.accentCyan)
                }

                ForEach(Array(entry.stories.prefix(category.activeCount).enumerated()), id: \.element.storyKey) { index, story in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(alignment: .top, spacing: 8) {
                            Link(destination: storyURL(story) ?? URL(string: "ainewswidget://story")!) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(story.title)
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(AINewsTheme.accentBlue)
                                        .underline(story.hasNeutralTitle, color: AINewsTheme.accentCyan.opacity(0.85))
                                        .lineLimit(2)
                                    StorySubtitleLine(story: story)
                                    if story.hasNeutralTitle {
                                        NeutralTitleMarker(compact: family == .systemSmall)
                                    }
                                    StoryLabelStrip(story: story, compact: family == .systemSmall)
                                    Text(story.summary ?? story.source ?? story.feedUrl)
                                        .font(.caption)
                                        .foregroundStyle(AINewsTheme.textSecondary)
                                        .lineLimit(2)
                                }
                            }
                            .buttonStyle(.plain)

                            if family == .systemSmall {
                                Button(intent: OpenShareIntent(categoryID: category.id, storyID: story.id, feedURL: story.feedUrl)) {
                                    Image(systemName: "square.and.arrow.up")
                                }
                                .buttonStyle(.plain)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(AINewsTheme.textMuted)
                            }
                        }

                        if family != .systemSmall {
                            HStack(spacing: 12) {
                                Button(intent: OpenSummaryIntent(categoryID: category.id, storyID: story.id, feedURL: story.feedUrl)) {
                                    Image(systemName: story.hasSummary ? "text.bubble.fill" : "text.bubble")
                                }
                                .buttonStyle(.plain)

                                Button(intent: OpenResearchIntent(categoryID: category.id, storyID: story.id, feedURL: story.feedUrl)) {
                                    Image(systemName: story.hasResearch ? "sparkles.rectangle.stack.fill" : "sparkles.rectangle.stack")
                                }
                                .buttonStyle(.plain)

                                Button(intent: OpenTranslationIntent(categoryID: category.id, storyID: story.id, feedURL: story.feedUrl)) {
                                    Image(systemName: story.hasTranslation ? "globe.americas.fill" : "globe")
                                }
                                .buttonStyle(.plain)

                                Button(intent: OpenShareIntent(categoryID: category.id, storyID: story.id, feedURL: story.feedUrl)) {
                                    Image(systemName: "square.and.arrow.up")
                                }
                                .buttonStyle(.plain)

                                Button(intent: PinStoryIntent(categoryID: category.id, storyID: story.id, feedURL: story.feedUrl)) {
                                    Image(systemName: category.isPinned(story) ? "pin.fill" : "pin")
                                }
                                .buttonStyle(.plain)
                            }
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(actionTint(for: story))
                        }
                    }
                    if story.storyKey != entry.stories.prefix(category.activeCount).last?.storyKey {
                        Divider()
                            .overlay(AINewsTheme.panelBorder.opacity(0.4))
                    }
                }
            }
            .padding(16)
            .dynamicTypeSize(widgetDynamicTypeSize)
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
            .dynamicTypeSize(widgetDynamicTypeSize)
            .containerBackground(for: .widget) {
                AINewsTheme.background
            }
        }
    }

    private func actionTint(for story: WidgetStory) -> some ShapeStyle {
        if story.summaryPending || story.researchPending || story.translationPending {
            return AINewsTheme.accentGold
        }
        if story.hasSummary || story.hasResearch || story.hasTranslation {
            return AINewsTheme.accentCyan
        }
        return AINewsTheme.textMuted
    }
}

@available(macOS 14.0, *)
struct MasterWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: MasterWidgetEntry

    private var visibleCategories: [WidgetCategory] {
        entry.snapshot.categories
            .filter { !$0.hidden }
            .sorted { $0.sortOrder == $1.sortOrder ? $0.name < $1.name : $0.sortOrder < $1.sortOrder }
    }

    private var totalPending: Int {
        visibleCategories.reduce(into: 0) { total, category in
            total += entry.snapshot.pendingByCategory[String(category.id)] ?? 0
        }
    }

    private var alertCount: Int {
        entry.snapshot.monitorAlerts.count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("AI News")
                    .font(.headline)
                    .foregroundStyle(AINewsTheme.textPrimary)
                Spacer()
                Text(totalPending > 0 ? "\(visibleCategories.count) live · \(totalPending) pending" : "\(visibleCategories.count) live")
                    .font(.caption)
                    .foregroundStyle(totalPending > 0 ? AINewsTheme.accentGold : AINewsTheme.textMuted)
            }

            if alertCount > 0 {
                Label("\(alertCount) monitor alert\(alertCount == 1 ? "" : "s")", systemImage: "bell.badge.fill")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(AINewsTheme.accentGold)
            }

            if family != .systemMedium {
                HStack(spacing: 12) {
                    if let firstVisible = visibleCategories.first {
                        Button(intent: RefreshCategoryIntent(categoryID: firstVisible.id)) {
                            Image(systemName: "arrow.clockwise")
                        }
                        .buttonStyle(.plain)
                    }
                    Link(destination: URL(string: "ainewswidget://story")!) {
                        Image(systemName: "arrow.up.right.square")
                    }
                    .buttonStyle(.plain)
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(AINewsTheme.accentCyan)
            }

            ForEach(Array(visibleCategories.prefix(4)), id: \.id) { category in
                let topStory = entry.snapshot.storiesByCategory[String(category.id)]?.first
                HStack(alignment: .top, spacing: 10) {
                    Link(
                        destination: topStory.flatMap {
                            WidgetDeepLink.storyURL(categoryID: category.id, storyID: $0.id, feedURL: $0.feedUrl)
                        } ?? URL(string: "ainewswidget://story")!
                    ) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(category.name)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(AINewsTheme.accentCyan)
                            if let pendingCount = entry.snapshot.pendingByCategory[String(category.id)], pendingCount > 0 {
                                Text("\(pendingCount) pending")
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(AINewsTheme.accentGold)
                            }
                            Text(topStory?.title ?? "No stories cached yet")
                                .font(.caption)
                                .foregroundStyle(AINewsTheme.textSecondary)
                                .lineLimit(2)
                            if let topStory {
                                StorySubtitleLine(story: topStory)
                                StoryLabelStrip(story: topStory, compact: true)
                            }
                        }
                    }
                    .buttonStyle(.plain)

                    if family != .systemMedium {
                        VStack(spacing: 8) {
                            Button(intent: ToggleCategoryVisibilityIntent(categoryID: category.id)) {
                                Image(systemName: category.hidden ? "eye.slash" : "eye")
                            }
                            .buttonStyle(.plain)

                            Button(intent: RefreshCategoryIntent(categoryID: category.id)) {
                                Image(systemName: "arrow.clockwise")
                            }
                            .buttonStyle(.plain)
                        }
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(AINewsTheme.textMuted)
                    }
                }
                if category.id != visibleCategories.prefix(4).last?.id {
                    Divider()
                        .overlay(AINewsTheme.panelBorder.opacity(0.35))
                }
            }
        }
        .padding(16)
        .dynamicTypeSize(widgetDynamicTypeSize)
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
struct KeywordWidgetEntry: TimelineEntry {
    let date: Date
    let keywords: [String]
    let stories: [WidgetStory]
    let pendingCount: Int
    let alertCount: Int
}

@available(macOS 14.0, *)
struct KeywordWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> KeywordWidgetEntry {
        KeywordWidgetEntry(
            date: Date(),
            keywords: ["openai", "robotics"],
            stories: [
                WidgetStory(id: "1", feedUrl: "feed", title: "OpenAI ships a new model for agents", summary: "Matched your tracked topics."),
                WidgetStory(id: "2", feedUrl: "feed", title: "Humanoid robotics startup raises a large round", summary: "Another tracked-topic match.")
            ],
            pendingCount: 16,
            alertCount: 1
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (KeywordWidgetEntry) -> Void) {
        Task {
            completion(await entry())
        }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<KeywordWidgetEntry>) -> Void) {
        Task {
            let entry = await entry()
            completion(Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(300))))
        }
    }

    private func entry() async -> KeywordWidgetEntry {
        let snapshot = await MainActor.run { SnapshotStore.shared.loadSnapshot() }
        return KeywordWidgetEntry(
            date: Date(),
            keywords: snapshot.keywords,
            stories: snapshot.keywordMatches,
            pendingCount: snapshot.totalPendingCount,
            alertCount: snapshot.monitorAlerts.count
        )
    }
}

@available(macOS 14.0, *)
struct KeywordWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: KeywordWidgetEntry

    private var storyLimit: Int {
        switch family {
        case .systemSmall: return 3
        case .systemMedium: return 4
        default: return 8
        }
    }

    private func storyURL(_ story: WidgetStory) -> URL {
        if let link = story.link, let url = URL(string: link) {
            return url
        }
        return URL(string: "ainewswidget://story")!
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Keywords", systemImage: "text.magnifyingglass")
                    .font(.headline)
                    .foregroundStyle(AINewsTheme.textPrimary)
                Spacer()
                Text(entry.pendingCount > 0
                     ? "\(entry.stories.count) match\(entry.stories.count == 1 ? "" : "es") · \(entry.pendingCount) pending"
                     : "\(entry.stories.count) match\(entry.stories.count == 1 ? "" : "es")")
                    .font(.caption)
                    .foregroundStyle(entry.pendingCount > 0 ? AINewsTheme.accentGold : AINewsTheme.textMuted)
            }

            if entry.alertCount > 0 {
                Label("\(entry.alertCount) monitor alert\(entry.alertCount == 1 ? "" : "s")", systemImage: "bell.badge.fill")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(AINewsTheme.accentGold)
            }

            if family != .systemSmall, !entry.keywords.isEmpty {
                Text(entry.keywords.prefix(6).joined(separator: " · "))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AINewsTheme.accentCyan)
                    .lineLimit(1)
            }

            if entry.stories.isEmpty {
                Text(entry.keywords.isEmpty
                     ? "Add tracked topics in the app, then refresh to see matches here."
                     : "No matching stories cached yet. Refresh in the app to populate this widget.")
                    .font(.caption)
                    .foregroundStyle(AINewsTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                ForEach(Array(entry.stories.prefix(storyLimit).enumerated()), id: \.element.storyKey) { index, story in
                    HStack(alignment: .top, spacing: 8) {
                        Link(destination: storyURL(story)) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(story.title)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(AINewsTheme.accentBlue)
                                    .underline(story.hasNeutralTitle, color: AINewsTheme.accentCyan.opacity(0.85))
                                    .lineLimit(2)
                                StorySubtitleLine(story: story)
                                if story.hasNeutralTitle {
                                    NeutralTitleMarker(compact: family == .systemSmall)
                                }
                                StoryLabelStrip(story: story, compact: family == .systemSmall)
                                if family != .systemSmall {
                                    Text(story.summary ?? story.source ?? story.feedUrl)
                                        .font(.caption)
                                        .foregroundStyle(AINewsTheme.textSecondary)
                                        .lineLimit(2)
                                }
                            }
                        }
                        .buttonStyle(.plain)

                        if family == .systemSmall {
                            Button(intent: OpenShareIntent(categoryID: 0, storyID: story.id, feedURL: story.feedUrl)) {
                                Image(systemName: "square.and.arrow.up")
                            }
                            .buttonStyle(.plain)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(AINewsTheme.textMuted)
                        } else {
                            Button(intent: OpenShareIntent(categoryID: 0, storyID: story.id, feedURL: story.feedUrl)) {
                                Image(systemName: "square.and.arrow.up")
                            }
                            .buttonStyle(.plain)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(AINewsTheme.textMuted)
                        }
                    }

                    if story.storyKey != entry.stories.prefix(storyLimit).last?.storyKey {
                        Divider()
                            .overlay(AINewsTheme.panelBorder.opacity(0.4))
                    }
                }
            }
        }
        .padding(16)
        .dynamicTypeSize(widgetDynamicTypeSize)
        .containerBackground(for: .widget) {
            AINewsTheme.background
        }
    }
}

@available(macOS 14.0, *)
struct KeywordWidget: Widget {
    let kind = "AINewsKeywordWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: KeywordWidgetProvider()) { entry in
            KeywordWidgetView(entry: entry)
        }
        .configurationDisplayName("AI News Keywords")
        .description("Show the latest stories that match your tracked topics.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

private struct StorySubtitleLine: View {
    let story: WidgetStory

    var body: some View {
        let text = storySubtitle(story)
        if !text.isEmpty {
            Text(text)
                .font(.caption2.weight(.medium))
                .foregroundStyle(AINewsTheme.textMuted)
                .lineLimit(1)
        }
    }

    private func storySubtitle(_ story: WidgetStory) -> String {
        var parts: [String] = []
        if let source = clean(story.source) {
            parts.append(source)
        }
        if let age = relativeAge(story.publishedDate) {
            parts.append(age)
        }
        return parts.joined(separator: " · ")
    }
}

private struct StoryLabelStrip: View {
    let story: WidgetStory
    let compact: Bool

    var body: some View {
        let labels = storyLabels(story, compact: compact)
        if !labels.isEmpty {
            HStack(spacing: 4) {
                ForEach(labels, id: \.self) { label in
                    Text(label)
                        .font(.caption2.weight(.bold))
                        .lineLimit(1)
                        .foregroundStyle(AINewsTheme.accentCyan)
                        .padding(.horizontal, compact ? 5 : 6)
                        .padding(.vertical, 2)
                        .background(
                            Capsule(style: .continuous)
                                .fill(AINewsTheme.accentCyan.opacity(0.12))
                        )
                }
            }
        }
    }

    private func storyLabels(_ story: WidgetStory, compact: Bool) -> [String] {
        var labels: [String] = []
        if isFresh(story.publishedDate) {
            labels.append("New")
        }
        if story.isMatch {
            labels.append("Match")
        }
        if !compact, let newsType = clean(story.newsType) {
            labels.append(displayLabel(newsType))
        }
        if !compact, let mood = clean(story.mood) {
            labels.append(displayLabel(mood))
        }
        return Array(labels.prefix(compact ? 2 : 4))
    }
}

private func clean(_ value: String?) -> String? {
    let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    return trimmed.isEmpty ? nil : trimmed
}

private func displayLabel(_ value: String) -> String {
    value
        .replacingOccurrences(of: "_", with: " ")
        .replacingOccurrences(of: "-", with: " ")
        .split(separator: " ")
        .map { word in
            let lower = word.lowercased()
            return lower.prefix(1).uppercased() + lower.dropFirst()
        }
        .joined(separator: " ")
}

private func relativeAge(_ date: Date?) -> String? {
    guard let date else { return nil }
    let seconds = max(0, Int(Date().timeIntervalSince(date)))
    if seconds < 60 { return "now" }
    let minutes = seconds / 60
    if minutes < 60 { return "\(minutes)m ago" }
    let hours = minutes / 60
    if hours < 24 { return "\(hours)h ago" }
    let days = hours / 24
    if days < 7 { return "\(days)d ago" }
    return nil
}

private func isFresh(_ date: Date?) -> Bool {
    guard let date else { return false }
    return Date().timeIntervalSince(date) >= 0 && Date().timeIntervalSince(date) <= 24 * 60 * 60
}

private struct NeutralTitleMarker: View {
    let compact: Bool

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: "checkmark.seal.fill")
            if !compact {
                Text("Neutral")
            }
        }
        .font(.caption2.weight(.bold))
        .foregroundStyle(AINewsTheme.accentCyan)
        .padding(.horizontal, compact ? 5 : 7)
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

@available(macOS 14.0, *)
@main
struct AINewsWidgetBundle: WidgetBundle {
    var body: some Widget {
        MasterWidget()
        CategoryWidget()
        KeywordWidget()
    }
}
