import AppKit
import SwiftUI
import AINewsWidgetShared

/// Owns always-on-top `NSPanel`s that mirror categories. Each category gets its
/// own panel, so several can float at once. Unlike a WidgetKit widget, these are
/// windows the app controls, so they float above other apps and scroll.
@MainActor
final class FloatingWidgetManager {
    private var panels: [Int: NSPanel] = [:]
    private let state: WidgetAppState
    private var cascadeIndex = 0

    init(state: WidgetAppState) {
        self.state = state
    }

    /// Open (or focus) a floating widget for whichever category is selected.
    func openForSelectedCategory() {
        guard let category = state.selectedCategory else { return }
        openWidget(categoryID: category.id, categoryName: category.name)
    }

    func openWidget(categoryID: Int, categoryName: String) {
        if let existing = panels[categoryID] {
            existing.makeKeyAndOrderFront(nil)
            return
        }

        let hosting = NSHostingView(
            rootView: FloatingWidgetView(categoryID: categoryID, categoryName: categoryName)
                .environmentObject(state)
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
        panel.center()
        // Offset each new panel so multiple widgets don't stack exactly on top.
        let offset = CGFloat((cascadeIndex % 6) * 32)
        cascadeIndex += 1
        panel.setFrameOrigin(NSPoint(x: panel.frame.origin.x + offset, y: panel.frame.origin.y - offset))

        panels[categoryID] = panel
        panel.makeKeyAndOrderFront(nil)
    }
}

/// Compact, scrollable view shown inside a floating panel. Fetches its own
/// category's stories so multiple widgets can show different categories at once.
private struct FloatingWidgetView: View {
    @EnvironmentObject private var state: WidgetAppState
    let categoryID: Int
    let categoryName: String

    @State private var stories: [WidgetStory] = []
    @State private var loading = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider().overlay(AINewsTheme.panelBorder.opacity(0.5))
            content
        }
        .frame(minWidth: 280, minHeight: 320)
        .background(AINewsTheme.background)
        .task { await reload() }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "newspaper.fill")
                .foregroundStyle(AINewsTheme.accentBlue)
            Text(categoryName)
                .font(.headline)
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
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AINewsTheme.textPrimary)
                Text("Refresh this category, or generate summaries from the main window.")
                    .font(.caption)
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

    private func storyRow(_ story: WidgetStory) -> some View {
        Button {
            if let link = story.link, let url = URL(string: link) {
                NSWorkspace.shared.open(url)
            }
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                Text(story.source ?? story.feedUrl)
                    .font(.caption2)
                    .foregroundStyle(AINewsTheme.textMuted)
                    .lineLimit(1)
                Text(story.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AINewsTheme.accentBlue)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
                if let summary = story.summary, !summary.isEmpty {
                    Text(summary)
                        .font(.caption)
                        .foregroundStyle(AINewsTheme.textSecondary)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(AINewsTheme.panel.opacity(0.7))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func reload() async {
        loading = true
        defer { loading = false }
        guard let api = try? state.authorizedAPIClient() else { return }
        if let response = try? await api.fetchStories(categoryID: categoryID, limit: 10) {
            stories = response.stories
        }
    }
}
