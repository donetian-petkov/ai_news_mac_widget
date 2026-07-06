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

    func windowWillClose(_ notification: Notification) {
        guard
            let window = notification.object as? NSWindow,
            let entry = panels.first(where: { $0.value === window })
        else { return }
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
        let autosaveName = "AINewsFloatingWidget-\(categoryID)"
        let restored = panel.setFrameUsingName(autosaveName)
        panel.setFrameAutosaveName(autosaveName)
        if !restored {
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
                try? await Task.sleep(nanoseconds: 45_000_000_000)
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
            Spacer()
            if loading {
                ProgressView().controlSize(.small)
            }
            Button {
                Task { await reload() }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .help("Reload this category")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private var content: some View {
        if stories.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text(loading ? "Loading…" : "No stories yet")
                    .font(AINewsTheme.font(14, weight: .semibold))
                    .foregroundStyle(AINewsTheme.textPrimary)
                Text("Refresh this category, or generate summaries from the main window.")
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
                }
                .padding(14)
            }
        }
    }

    @AppStorage("ai_news_show_thumbnails") private var coversEnabled = true

    private func storyRow(_ story: WidgetStory) -> some View {
        Button {
            if let link = story.link, let url = URL(string: link) {
                NSWorkspace.shared.open(url)
            }
        } label: {
            HStack(alignment: .top, spacing: 12) {
                if coversEnabled, let cover = story.coverUrl, let url = URL(string: cover) {
                    StoryThumbnail(url: url, size: 66)
                }
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
                    block("Summary", story.summary, pending: story.summaryPending, accent: AINewsTheme.accentBlue)
                    block("Research", story.research, pending: story.researchPending, accent: AINewsTheme.accentCyan)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(12)
            .aiNewsCardStyle()
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func block(_ label: String, _ text: String?, pending: Bool, accent: Color) -> some View {
        if let text, !text.isEmpty {
            VStack(alignment: .leading, spacing: 2) {
                Text(label.uppercased())
                    .font(AINewsTheme.font(10, weight: .semibold))
                    .foregroundStyle(accent.opacity(0.9))
                Text(text)
                    .font(AINewsTheme.font(12))
                    .foregroundStyle(AINewsTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } else if pending {
            Text("\(label): generating…")
                .font(AINewsTheme.font(10))
                .foregroundStyle(AINewsTheme.textMuted)
        }
    }

    private func reload() async {
        loading = true
        defer { loading = false }
        guard let api = try? state.authorizedAPIClient() else { return }
        if isFiltered {
            if let matches = try? await api.fetchKeywordMatches(limit: 20) {
                stories = matches
            }
        } else if let response = try? await api.fetchStories(categoryID: categoryID, limit: 10) {
            stories = response.stories
        }
    }
}
