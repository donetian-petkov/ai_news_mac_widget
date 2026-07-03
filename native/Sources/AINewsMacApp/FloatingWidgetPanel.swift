import AppKit
import SwiftUI
import AINewsWidgetShared

/// Owns an always-on-top `NSPanel` that mirrors the currently selected category.
/// Unlike a WidgetKit widget, this is a window the app controls, so it can float
/// above other apps (`.floating` level) and scroll like any SwiftUI view.
@MainActor
final class FloatingWidgetManager {
    private var panel: NSPanel?
    private let state: WidgetAppState

    init(state: WidgetAppState) {
        self.state = state
    }

    /// Shows the panel if hidden, hides it if already on screen.
    func toggle() {
        if let panel, panel.isVisible {
            panel.orderOut(nil)
        } else {
            show()
        }
    }

    func show() {
        if let panel {
            panel.makeKeyAndOrderFront(nil)
            return
        }

        let hosting = NSHostingView(
            rootView: FloatingWidgetView().environmentObject(state)
        )

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 340, height: 480),
            styleMask: [.titled, .closable, .resizable, .utilityWindow, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.title = "AI News"
        panel.contentView = hosting
        // Float above other apps and follow the user across Spaces / full-screen.
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.setFrameAutosaveName("AINewsFloatingWidget")
        if panel.frame.origin == .zero {
            panel.center()
        }
        self.panel = panel
        panel.makeKeyAndOrderFront(nil)
    }
}

/// Compact, scrollable view shown inside the floating panel.
private struct FloatingWidgetView: View {
    @EnvironmentObject private var state: WidgetAppState

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider().overlay(AINewsTheme.panelBorder.opacity(0.5))
            content
        }
        .frame(minWidth: 280, minHeight: 320)
        .background(AINewsTheme.background)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "newspaper.fill")
                .foregroundStyle(AINewsTheme.accentBlue)
            Text(state.selectedCategory?.name ?? "AI News")
                .font(.headline)
                .foregroundStyle(AINewsTheme.textPrimary)
                .lineLimit(1)
            Spacer()
            Button {
                Task { await state.loadStoriesForSelectedCategory() }
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
        if state.stories.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text("No stories yet")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AINewsTheme.textPrimary)
                Text("Pick a category in the main window, then refresh.")
                    .font(.caption)
                    .foregroundStyle(AINewsTheme.textSecondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(14)
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(state.stories) { story in
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
}
