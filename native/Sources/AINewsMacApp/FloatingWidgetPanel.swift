import AppKit
import SwiftUI
import AINewsWidgetShared

/// Owns always-on-top `NSPanel`s that mirror categories. Each category gets its
/// own panel, so several can float at once. Unlike a WidgetKit widget, these are
/// windows the app controls, so they float above other apps and scroll.
@MainActor
final class FloatingWidgetManager: NSObject, NSWindowDelegate {
    private var panels: [Int: NSPanel] = [:]
    private var names: [Int: String] = [:]
    private var closedStack: [Int] = []
    private let state: WidgetAppState
    private var cascadeIndex = 0

    init(state: WidgetAppState) {
        self.state = state
        super.init()
    }

    /// Sentinel id for the keyword-matches ("Filtered") floating widget.
    private let filteredKey = -1

    /// Open (or focus) a floating widget for whichever category is selected.
    func openForSelectedCategory() {
        guard let category = state.selectedCategory else { return }
        openWidget(categoryID: category.id, categoryName: category.name)
    }

    /// Open (or focus) the Filtered floating widget (keyword/tracked-topic matches).
    func openFiltered() {
        openWidget(categoryID: filteredKey, categoryName: "Filtered", isFiltered: true)
    }

    /// Reopen the most recently closed widget (⌘⇧T, browser-style).
    func reopenLastClosed() {
        guard let id = closedStack.popLast(), let name = names[id] else { return }
        openWidget(categoryID: id, categoryName: name, isFiltered: id == filteredKey)
    }

    /// UserDefaults key holding a category's persisted panel frame.
    private static func frameKey(_ id: Int) -> String { "AINewsFloatingWidgetFrame-\(id)" }

    /// Save the panel's current frame so size/position survive close + relaunch.
    private func persistFrame(for window: NSWindow) {
        guard let entry = panels.first(where: { $0.value === window }) else { return }
        UserDefaults.standard.set(NSStringFromRect(window.frame), forKey: Self.frameKey(entry.key))
    }

    func windowDidMove(_ notification: Notification) {
        if let window = notification.object as? NSWindow { persistFrame(for: window) }
    }

    func windowDidResize(_ notification: Notification) {
        if let window = notification.object as? NSWindow { persistFrame(for: window) }
    }

    func windowWillClose(_ notification: Notification) {
        guard
            let window = notification.object as? NSWindow,
            let entry = panels.first(where: { $0.value === window })
        else { return }
        persistFrame(for: window)
        let id = entry.key
        closedStack.removeAll { $0 == id }
        closedStack.append(id)
    }

    func openWidget(categoryID: Int, categoryName: String, isFiltered: Bool = false) {
        names[categoryID] = categoryName
        closedStack.removeAll { $0 == categoryID }
        if let existing = panels[categoryID] {
            existing.makeKeyAndOrderFront(nil)
            return
        }

        let hosting = NSHostingView(
            rootView: FloatingWidgetView(categoryID: categoryID, categoryName: categoryName, isFiltered: isFiltered)
                .environmentObject(state)
                .environmentObject(ThemeSettings.shared)
        )

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 340, height: 480),
            styleMask: [.titled, .closable, .resizable, .utilityWindow, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.title = categoryName
        panel.contentView = hosting
        // Float above other apps and follow the user across Spaces / full-screen.
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        // Keep the panel object around when closed so reopening the same category
        // just brings it back instead of leaking a new one.
        panel.isReleasedWhenClosed = false
        panel.minSize = NSSize(width: 220, height: 180)
        // Remember each widget's size/position across launches, per category.
        // We persist the frame ourselves (windowDidMove/Resize/WillClose) rather
        // than relying on AppKit's autosave, which is unreliable for panels.
        if let saved = UserDefaults.standard.string(forKey: Self.frameKey(categoryID)) {
            panel.setFrame(NSRectFromString(saved), display: false)
        } else {
            panel.center()
            // Offset each new panel so multiple widgets don't stack exactly on top.
            let offset = CGFloat((cascadeIndex % 6) * 32)
            panel.setFrameOrigin(NSPoint(x: panel.frame.origin.x + offset, y: panel.frame.origin.y - offset))
        }
        cascadeIndex += 1

        panel.delegate = self
        panels[categoryID] = panel
        panel.makeKeyAndOrderFront(nil)
    }
}

/// Compact, scrollable view shown inside a floating panel. Fetches its own
/// category's stories so multiple widgets can show different categories at once.
private struct FloatingWidgetView: View {
    @EnvironmentObject private var state: WidgetAppState
    @EnvironmentObject private var theme: ThemeSettings
    let categoryID: Int
    let categoryName: String
    var isFiltered: Bool = false

    @State private var stories: [WidgetStory] = []
    @State private var loading = false
    @State private var copiedStoryKey: String?
    /// How many stories to show. Grows by `pageStep` via "Show More", resets to
    /// `pageStep` via "Reset". Mirrors ai_news_deploy_ready's column behaviour.
    @State private var visibleCount = 10
    /// True once the backend returns fewer stories than requested (no more left).
    @State private var reachedEnd = false
    private let pageStep = 10

    private var pendingCount: Int {
        if isFiltered {
            return state.aiProgress.values.reduce(0) { $0 + $1.pending }
        }
        guard let category = state.categories.first(where: { $0.id == categoryID }) else { return 0 }
        return category.feedUrls.reduce(into: 0) { total, url in
            total += state.aiProgress[url]?.pending ?? 0
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider().overlay(AINewsTheme.panelBorder.opacity(0.5))
            content
        }
        .frame(minWidth: 220, minHeight: 180)
        .background(AINewsBackground())
        .dynamicTypeSize(theme.fontSize.dynamicTypeSize)
        .task {
            // Load now, then auto-refresh so the widget picks up new stories and
            // freshly generated summaries/translations without clicking reload.
            while !Task.isCancelled {
                await reload()
                try? await Task.sleep(nanoseconds: 12_000_000_000)
            }
        }
        // Refresh immediately when the app signals new AI content (summary/research/translation done).
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("AINewsWidgetShouldRefresh"))) { _ in
            Task { await reload() }
        }
        .onChange(of: state.lastSharedStoryKey) { _, newValue in
            guard let newValue else { return }
            copiedStoryKey = newValue
            Task {
                try? await Task.sleep(nanoseconds: 1_600_000_000)
                if copiedStoryKey == newValue {
                    copiedStoryKey = nil
                }
            }
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "newspaper.fill")
                .foregroundStyle(AINewsTheme.accentBlue)
            Text(categoryName)
                .font(AINewsTheme.font(16, weight: .bold))
                .foregroundStyle(AINewsTheme.textPrimary)
                .lineLimit(1)
            Spacer(minLength: 8)
            // Centered: live time/date + total AI token usage.
            TimelineView(.periodic(from: Date(), by: 30)) { context in
                VStack(spacing: 1) {
                    Text(context.date.formatted(date: .abbreviated, time: .shortened))
                        .font(AINewsTheme.font(11, weight: .semibold))
                        .foregroundStyle(AINewsTheme.textSecondary)
                    Text("\(tokenText) tokens")
                        .font(AINewsTheme.font(10))
                        .foregroundStyle(AINewsTheme.accentCyan)
                    Text("\(pendingCount) pending")
                        .font(AINewsTheme.font(10, weight: .semibold))
                        .foregroundStyle(pendingCount > 0 ? AINewsTheme.accentGold : AINewsTheme.textMuted)
                }
                .lineLimit(1)
            }
            Spacer(minLength: 8)
            if loading {
                ProgressView().controlSize(.small)
            }
            Button {
                Task { await reload() }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(AINewsTheme.font(14, weight: .semibold))
                    .foregroundStyle(AINewsTheme.textPrimary)
                    .frame(width: 30, height: 30)
                    .background(
                        Circle()
                            .fill(AINewsTheme.backgroundAlt.opacity(0.96))
                    )
                    .overlay(
                        Circle()
                            .stroke(AINewsTheme.panelBorder.opacity(0.85), lineWidth: 1)
                    )
            }
            .buttonStyle(.borderless)
            .help("Reload this category")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var tokenText: String {
        let n = state.usage?.totalTokens ?? 0
        if n >= 1_000_000 { return String(format: "%.1fM", Double(n) / 1_000_000) }
        if n >= 1_000 { return String(format: "%.1fk", Double(n) / 1_000) }
        return "\(n)"
    }

    @ViewBuilder
    private var content: some View {
        if stories.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text(loading ? "Loading…" : "No stories yet")
                    .font(AINewsTheme.font(14, weight: .semibold))
                    .foregroundStyle(AINewsTheme.textPrimary)
                Text(isFiltered
                     ? "Add keywords (Workspace ▸ Keywords) or tracked topics (Settings ▸ Personalization) to see matches here."
                     : "Refresh this category, or generate summaries from the main window.")
                    .font(AINewsTheme.font(12))
                    .foregroundStyle(AINewsTheme.textSecondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(14)
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(stories) { story in
                        storyRow(story)
                    }
                    paginationControls
                }
                .padding(14)
            }
        }
    }

    @ViewBuilder
    private var paginationControls: some View {
        VStack(spacing: 8) {
            if !reachedEnd {
                Button {
                    visibleCount += pageStep
                    Task { await reload() }
                } label: {
                    paginationButtonLabel(
                        title: "Show \(pageStep) More News",
                        systemImage: "chevron.down",
                        prominent: true
                    )
                }
                .buttonStyle(.plain)
            }
            if visibleCount > pageStep {
                Button {
                    visibleCount = pageStep
                    Task { await reload() }
                } label: {
                    paginationButtonLabel(
                        title: "Reset to the First \(pageStep) News",
                        systemImage: "arrow.uturn.up",
                        prominent: false
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.top, 4)
    }

    private func paginationButtonLabel(title: String, systemImage: String, prominent: Bool) -> some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(AINewsTheme.font(12, weight: .semibold))
            Text(title)
                .font(AINewsTheme.font(12, weight: .semibold))
                .lineLimit(1)
        }
        .foregroundStyle(prominent ? Color.black : AINewsTheme.textPrimary)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(prominent ? AINewsTheme.accentCyan.opacity(0.96) : AINewsTheme.backgroundAlt.opacity(0.96))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(
                    prominent ? AINewsTheme.accentCyan.opacity(0.98) : AINewsTheme.panelBorder.opacity(0.85),
                    lineWidth: 1
                )
        )
        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    @AppStorage("ai_news_show_thumbnails") private var coversEnabled = true

    private func storyRow(_ story: WidgetStory) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 12) {
                if coversEnabled {
                    StoryThumbnail(url: story.coverUrl.flatMap { URL(string: $0) }, size: 66)
                }
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .top, spacing: 8) {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(spacing: 6) {
                                Text(story.source ?? story.feedUrl)
                                    .font(AINewsTheme.font(11, weight: .semibold))
                                    .foregroundStyle(AINewsTheme.accentCyan)
                                    .lineLimit(1)
                                if let mood = story.mood, !mood.isEmpty {
                                    MoodChip(mood: mood)
                                }
                            }
                            if let date = story.publishedDate {
                                Text(date.formatted(date: .abbreviated, time: .shortened))
                                    .font(AINewsTheme.font(10))
                                    .foregroundStyle(AINewsTheme.textMuted)
                            }
                        }
                        Spacer(minLength: 8)
                        Button {
                            Task { await state.shareStory(story) }
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: copiedStoryKey == story.storyKey ? "checkmark" : "square.and.arrow.up")
                                    .font(AINewsTheme.font(12, weight: .semibold))
                                if copiedStoryKey == story.storyKey {
                                    Text("Copied")
                                        .font(AINewsTheme.font(10, weight: .semibold))
                                }
                            }
                        }
                        .buttonStyle(.borderless)
                        .foregroundStyle(copiedStoryKey == story.storyKey ? AINewsTheme.accentCyan : AINewsTheme.textMuted)
                        .help("Copy a share link for this story")
                    }

                    Text(story.title)
                        .font(AINewsTheme.font(14, weight: .bold))
                        .foregroundStyle(AINewsTheme.accentBlue)
                        .fixedSize(horizontal: false, vertical: true)
                    if let translated = story.translatedTitle, !translated.isEmpty, translated != story.title {
                        Text(translated)
                            .font(AINewsTheme.font(12))
                            .foregroundStyle(AINewsTheme.accentGold)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    block("Summary", story.summary, pending: story.summaryPending, enabled: state.globalAiDefaults.summaryEnabled, accent: AINewsTheme.accentBlue)
                    block("Research", story.research, pending: story.researchPending, enabled: state.globalAiDefaults.researchEnabled, accent: AINewsTheme.accentCyan)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(12)
        .aiNewsCardStyle()
        .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .onTapGesture {
            openStory(story)
        }
    }

    private func openStory(_ story: WidgetStory) {
        guard let link = story.link, let url = URL(string: link) else { return }
        NSWorkspace.shared.open(url)
    }

    @ViewBuilder
    private func block(_ label: String, _ text: String?, pending: Bool, enabled: Bool, accent: Color) -> some View {
        // Only show the section when the action is enabled — disabling it globally hides
        // it here even if older content still exists on the story.
        if enabled {
            VStack(alignment: .leading, spacing: 2) {
                Text(label.uppercased())
                    .font(AINewsTheme.font(10, weight: .semibold))
                    .foregroundStyle(accent.opacity(0.9))
                if let text, !text.isEmpty {
                    Text(text)
                        .font(AINewsTheme.font(12))
                        .foregroundStyle(AINewsTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text(pending ? "Generating…" : "Not generated yet.")
                        .font(AINewsTheme.font(12))
                        .foregroundStyle(AINewsTheme.textMuted)
                }
            }
        }
    }

    private func reload() async {
        loading = true
        defer { loading = false }
        await state.refreshUsage()
        guard let api = try? state.authorizedAPIClient() else { return }
        if isFiltered {
            if let matches = try? await api.fetchKeywordMatches(limit: visibleCount) {
                stories = matches
                reachedEnd = matches.count < visibleCount
            }
        } else if let response = try? await api.fetchStories(categoryID: categoryID, limit: visibleCount) {
            stories = response.stories
            reachedEnd = response.stories.count < visibleCount
        }
    }
}
