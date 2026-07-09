import AppKit
import SwiftUI
import UniformTypeIdentifiers
import AINewsWidgetShared

private enum FloatingWidgetLayoutMode: String, CaseIterable {
    case column
    case stack
}

private enum FloatingWidgetPreferences {
    private static func widgetKey(categoryID: Int, isFiltered: Bool) -> String {
        isFiltered ? "filtered" : "category-\(categoryID)"
    }

    private static func layoutModeKey(categoryID: Int, isFiltered: Bool) -> String {
        "AINewsFloatingWidgetLayout-\(widgetKey(categoryID: categoryID, isFiltered: isFiltered))"
    }

    private static func storyOrderKey(categoryID: Int, isFiltered: Bool) -> String {
        "AINewsFloatingWidgetStoryOrder-\(widgetKey(categoryID: categoryID, isFiltered: isFiltered))"
    }

    private static func seenStoriesKey(categoryID: Int, isFiltered: Bool) -> String {
        "AINewsFloatingWidgetSeenStories-\(widgetKey(categoryID: categoryID, isFiltered: isFiltered))"
    }

    static func layoutMode(categoryID: Int, isFiltered: Bool) -> FloatingWidgetLayoutMode {
        let raw = UserDefaults.standard.string(forKey: layoutModeKey(categoryID: categoryID, isFiltered: isFiltered)) ?? FloatingWidgetLayoutMode.column.rawValue
        return FloatingWidgetLayoutMode(rawValue: raw) ?? .column
    }

    static func setLayoutMode(_ mode: FloatingWidgetLayoutMode, categoryID: Int, isFiltered: Bool) {
        UserDefaults.standard.set(mode.rawValue, forKey: layoutModeKey(categoryID: categoryID, isFiltered: isFiltered))
    }

    static func storyOrder(categoryID: Int, isFiltered: Bool) -> [String] {
        UserDefaults.standard.stringArray(forKey: storyOrderKey(categoryID: categoryID, isFiltered: isFiltered)) ?? []
    }

    static func setStoryOrder(_ order: [String], categoryID: Int, isFiltered: Bool) {
        UserDefaults.standard.set(order, forKey: storyOrderKey(categoryID: categoryID, isFiltered: isFiltered))
    }

    static func seenStories(categoryID: Int, isFiltered: Bool) -> Set<String> {
        Set(UserDefaults.standard.stringArray(forKey: seenStoriesKey(categoryID: categoryID, isFiltered: isFiltered)) ?? [])
    }

    static func setSeenStories(_ storyKeys: Set<String>, categoryID: Int, isFiltered: Bool) {
        UserDefaults.standard.set(Array(storyKeys).sorted(), forKey: seenStoriesKey(categoryID: categoryID, isFiltered: isFiltered))
    }
}

private struct FloatingGlassBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.state = .active
        view.material = .sidebar
        view.blendingMode = .behindWindow
        view.isEmphasized = false
        view.alphaValue = 0.82
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.state = .active
        nsView.alphaValue = 0.82
    }
}

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
        openWidget(categoryID: filteredKey, categoryName: "Filtered Feed", isFiltered: true)
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

        let hostingController = NSHostingController(
            rootView: FloatingWidgetView(categoryID: categoryID, categoryName: categoryName, isFiltered: isFiltered)
                .environmentObject(state)
                .environmentObject(ThemeSettings.shared)
        )
        hostingController.view.wantsLayer = true
        hostingController.view.layer?.backgroundColor = NSColor.clear.cgColor

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 340, height: 480),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        panel.title = categoryName
        panel.contentViewController = hostingController
        panel.titlebarAppearsTransparent = false
        panel.titleVisibility = .hidden
        panel.isMovableByWindowBackground = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        // Float above other apps and follow the user across Spaces / full-screen.
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = false
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
    @State private var draggedStoryKey: String?
    @State private var layoutMode: FloatingWidgetLayoutMode
    @State private var seenStoryKeys: Set<String>
    @State private var stackIndex = 0
    /// How many stories to show. Grows by `pageStep` via "Show More", resets to
    /// `pageStep` via "Reset". Mirrors ai_news_deploy_ready's column behaviour.
    @State private var visibleCount = 10
    /// True once the backend returns fewer stories than requested (no more left).
    @State private var reachedEnd = false
    private let pageStep = 10

    init(categoryID: Int, categoryName: String, isFiltered: Bool = false) {
        self.categoryID = categoryID
        self.categoryName = categoryName
        self.isFiltered = isFiltered
        _layoutMode = State(initialValue: FloatingWidgetPreferences.layoutMode(categoryID: categoryID, isFiltered: isFiltered))
        _seenStoryKeys = State(initialValue: FloatingWidgetPreferences.seenStories(categoryID: categoryID, isFiltered: isFiltered))
    }

    private var pendingCount: Int {
        if isFiltered {
            return state.aiProgress.values.reduce(0) { $0 + $1.pending }
        }
        guard let category = state.categories.first(where: { $0.id == categoryID }) else { return 0 }
        return category.feedUrls.reduce(into: 0) { total, url in
            total += state.aiProgress[url]?.pending ?? 0
        }
    }

    private var widgetFontScale: CGFloat {
        theme.widgetFontSize.scale
    }

    private func widgetFont(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size * widgetFontScale, weight: weight)
    }

    private func widgetCaption2(weight: Font.Weight = .regular) -> Font {
        widgetFont(11, weight: weight)
    }

    private func widgetCaption(weight: Font.Weight = .regular) -> Font {
        widgetFont(12.5, weight: weight)
    }

    private func widgetBody(weight: Font.Weight = .regular) -> Font {
        widgetFont(15.5, weight: weight)
    }

    private func widgetHeadline(weight: Font.Weight = .semibold) -> Font {
        widgetFont(18, weight: weight)
    }

    private func widgetHeaderTitle(weight: Font.Weight = .bold) -> Font {
        widgetFont(20, weight: weight)
    }

    private func widgetHeaderMeta(weight: Font.Weight = .semibold) -> Font {
        widgetFont(14, weight: weight)
    }

    private func widgetHeaderStat(weight: Font.Weight = .semibold) -> Font {
        widgetFont(13, weight: weight)
    }

    private var orderedStoryKeys: [String] {
        stories.map(\.storyKey)
    }

    private var estimatedStackWindowHeight: CGFloat {
        guard let story = currentStackStory else { return 460 }
        let titleLines = ceil(Double(story.title.count) / 34.0)
        let summaryLength = story.summary?.count ?? 0
        let summaryLines = ceil(Double(summaryLength) / 38.0)
        let baseHeight = 230.0
        let dynamicHeight = (titleLines * 22.0) + (summaryLines * 16.0)
        return CGFloat(min(max(baseHeight + dynamicHeight, 430.0), 580.0))
    }

    private var estimatedStackWindowWidth: CGFloat {
        470
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider().overlay(AINewsTheme.panelBorder.opacity(0.5))
            content
        }
        .frame(minWidth: 220, minHeight: 180)
        .background(
            ZStack {
                FloatingGlassBackground()
                LinearGradient(
                    colors: [
                        AINewsTheme.backgroundAlt.opacity(0.16),
                        AINewsTheme.background.opacity(0.22)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                RadialGradient(
                    gradient: Gradient(colors: [AINewsTheme.panelBorder.opacity(0.08), .clear]),
                    center: UnitPoint(x: 0.05, y: 0.0),
                    startRadius: 0,
                    endRadius: 520
                )
                RadialGradient(
                    gradient: Gradient(colors: [AINewsTheme.accentCyan.opacity(0.05), .clear]),
                    center: UnitPoint(x: 1.0, y: 0.02),
                    startRadius: 0,
                    endRadius: 520
                )
            }
        )
        .dynamicTypeSize(theme.widgetFontSize.dynamicTypeSize)
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
        .onChange(of: layoutMode) { _, newValue in
            FloatingWidgetPreferences.setLayoutMode(newValue, categoryID: categoryID, isFiltered: isFiltered)
            clampStackIndex()
            resizeWindowForCurrentLayout()
        }
        .onAppear {
            resizeWindowForCurrentLayout()
        }
    }

    private var header: some View {
        Group {
            if layoutMode == .stack {
                headerCompactLayout
            } else {
                ViewThatFits(in: .horizontal) {
                    headerExpandedLayout
                    headerCompactLayout
                }
            }
        }
        .padding(.horizontal, layoutMode == .stack ? 12 : 14)
        .padding(.vertical, layoutMode == .stack ? 8 : 10)
    }

    private var headerExpandedLayout: some View {
        HStack(spacing: 8) {
            headerTitleChip
                .fixedSize(horizontal: true, vertical: false)
            Spacer(minLength: 8)
            headerMetaChip
                .fixedSize(horizontal: true, vertical: false)
            Spacer(minLength: 8)
            headerActions
        }
    }

    private var headerCompactLayout: some View {
        HStack(alignment: .center, spacing: 10) {
            compactHeaderTitleChip
                .layoutPriority(1)
            Spacer(minLength: 4)
            compactHeaderMetaInline
            Spacer(minLength: 4)
            compactHeaderActions
        }
    }

    private var headerTitleChip: some View {
        HStack(spacing: 10) {
            Image(systemName: "newspaper.fill")
                .font(widgetFont(17, weight: .bold))
                .foregroundStyle(AINewsTheme.accentBlue)
            Text(categoryName)
                .font(widgetHeaderTitle())
                .foregroundStyle(AINewsTheme.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.9)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(headerCapsuleFill)
        .overlay(headerCapsuleStroke)
    }

    private var headerMetaChip: some View {
        TimelineView(.periodic(from: Date(), by: 30)) { context in
            VStack(spacing: 1) {
                Text(context.date.formatted(date: .abbreviated, time: .shortened))
                    .font(widgetHeaderMeta())
                    .foregroundStyle(AINewsTheme.textSecondary)
                Text("\(tokenText) tokens")
                    .font(widgetHeaderStat(weight: .bold))
                    .foregroundStyle(AINewsTheme.accentCyan)
                Text("\(pendingCount) pending")
                    .font(widgetHeaderStat())
                    .foregroundStyle(pendingCount > 0 ? AINewsTheme.accentGold : AINewsTheme.textMuted)
            }
            .lineLimit(1)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(headerCapsuleFill)
            .overlay(headerCapsuleStroke)
        }
    }

    private var compactHeaderTitleChip: some View {
        HStack(spacing: 7) {
            Image(systemName: "newspaper.fill")
                .font(widgetFont(14, weight: .bold))
                .foregroundStyle(AINewsTheme.accentBlue)
            Text(categoryName)
                .font(widgetFont(15, weight: .bold))
                .foregroundStyle(AINewsTheme.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.84)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(compactHeaderCapsuleFill)
        .overlay(compactHeaderCapsuleStroke)
    }

    private var compactHeaderMetaInline: some View {
        TimelineView(.periodic(from: Date(), by: 30)) { context in
            VStack(spacing: -1) {
                Text(context.date.formatted(date: .abbreviated, time: .shortened))
                    .font(widgetFont(11.5, weight: .semibold))
                    .foregroundStyle(AINewsTheme.textSecondary)
                Text("\(tokenText) tokens")
                    .font(widgetFont(10.75, weight: .bold))
                    .foregroundStyle(AINewsTheme.accentCyan)
                Text("\(pendingCount) pending")
                    .font(widgetFont(10.75, weight: .semibold))
                    .foregroundStyle(pendingCount > 0 ? AINewsTheme.accentGold : AINewsTheme.textMuted)
            }
            .lineLimit(1)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(compactHeaderMetaFill)
            .overlay(compactHeaderMetaStroke)
            .frame(minWidth: 104)
        }
    }

    private var compactHeaderActions: some View {
        HStack(spacing: 5) {
            headerModeButton(.column, systemImage: "rectangle.grid.1x2", size: 26)
            headerModeButton(.stack, systemImage: "square.stack.3d.up", size: 26)
            if loading {
                ProgressView().controlSize(.small)
            }
            Button {
                Task { await reload() }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(widgetFont(12.5, weight: .semibold))
                    .foregroundStyle(AINewsTheme.textPrimary)
                    .frame(width: 28, height: 28)
                    .background(
                        Circle()
                            .fill(AINewsTheme.backgroundAlt.opacity(0.96))
                    )
                    .overlay(
                        Circle()
                            .stroke(AINewsTheme.panelBorder.opacity(0.82), lineWidth: 1)
                    )
            }
            .buttonStyle(.borderless)
            .help("Reload this category")
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    private var headerActions: some View {
        HStack(spacing: 6) {
            headerModeButton(.column, systemImage: "rectangle.grid.1x2")
            headerModeButton(.stack, systemImage: "square.stack.3d.up")
            if loading {
                ProgressView().controlSize(.small)
            }
            Button {
                Task { await reload() }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(widgetFont(14, weight: .semibold))
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
        .fixedSize(horizontal: true, vertical: false)
    }

    private var headerCapsuleFill: some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(AINewsTheme.panel.opacity(0.58))
    }

    private var headerCapsuleStroke: some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .stroke(AINewsTheme.panelBorder.opacity(0.18), lineWidth: 1)
    }

    private var compactHeaderCapsuleFill: some View {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(AINewsTheme.panel.opacity(0.44))
    }

    private var compactHeaderCapsuleStroke: some View {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
            .stroke(AINewsTheme.panelBorder.opacity(0.14), lineWidth: 1)
    }

    private var compactHeaderMetaFill: some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(AINewsTheme.panel.opacity(0.56))
    }

    private var compactHeaderMetaStroke: some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .stroke(AINewsTheme.panelBorder.opacity(0.16), lineWidth: 1)
    }

    private func headerModeButton(_ mode: FloatingWidgetLayoutMode, systemImage: String, size: CGFloat = 28) -> some View {
        Button {
            layoutMode = mode
        } label: {
            Image(systemName: systemImage)
                .font(widgetFont(size == 28 ? 12 : 11, weight: .semibold))
                .foregroundStyle(layoutMode == mode ? Color.black : AINewsTheme.textPrimary)
                .frame(width: size, height: size)
                .background(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(layoutMode == mode ? AINewsTheme.accentCyan.opacity(0.95) : AINewsTheme.backgroundAlt.opacity(0.9))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .stroke(
                            layoutMode == mode ? AINewsTheme.accentCyan.opacity(0.98) : AINewsTheme.panelBorder.opacity(0.75),
                            lineWidth: 1
                        )
                )
        }
        .buttonStyle(.borderless)
        .help(mode == .column ? "Column view" : "Stack view")
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
                    .font(widgetFont(14, weight: .semibold))
                    .foregroundStyle(AINewsTheme.textPrimary)
                Text(isFiltered
                     ? "Add keywords (Workspace ▸ Keywords) or tracked topics (Settings ▸ Personalization) to see matches here."
                     : "Refresh this category, or generate summaries from the main window.")
                    .font(widgetFont(12))
                    .foregroundStyle(AINewsTheme.textSecondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(14)
        } else if layoutMode == .stack {
            stackContent
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

    private var stackContent: some View {
        GeometryReader { proxy in
            VStack(spacing: 12) {
                ZStack {
                    if let tertiary = stackStory(offsetBy: 2) {
                        stackBackdropCard(for: tertiary, scale: 0.92, xOffset: 52, yOffset: 8, opacity: 0.10)
                    }
                    if let secondary = stackStory(offsetBy: 1) {
                        stackBackdropCard(for: secondary, scale: 0.96, xOffset: 28, yOffset: 4, opacity: 0.16)
                    }
                    if let current = currentStackStory {
                        ScrollView {
                            storyRow(current, draggable: false)
                        }
                        .scrollIndicators(.hidden)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: max(220, proxy.size.height - 84))
                .padding(.horizontal, 14)
                .padding(.top, 14)

                HStack(spacing: 10) {
                    Button {
                        moveStack(by: -1)
                    } label: {
                        stackNavLabel(systemImage: "chevron.up", title: "Previous")
                    }
                    .buttonStyle(.plain)
                    .disabled(stackIndex <= 0)

                    Text("\(stackIndex + 1) of \(stories.count)")
                        .font(widgetFont(12, weight: .semibold))
                        .foregroundStyle(AINewsTheme.textMuted)
                        .frame(minWidth: 72)

                    Button {
                        moveStack(by: 1)
                    } label: {
                        stackNavLabel(systemImage: "chevron.down", title: "Next")
                    }
                    .buttonStyle(.plain)
                    .disabled(stackIndex >= stories.count - 1)
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 14)
            }
        }
    }

    private func stackBackdropCard(for _: WidgetStory, scale: CGFloat, xOffset: CGFloat, yOffset: CGFloat, opacity: Double) -> some View {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [Color.white.opacity(0.035), Color.white.opacity(0.012)],
                    startPoint: .topLeading,
                    endPoint: .bottom
                )
            )
            .overlay(
                HStack(alignment: .top, spacing: 12) {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.white.opacity(0.018))
                        .frame(width: 64, height: 64)

                    VStack(alignment: .leading, spacing: 8) {
                        Capsule(style: .continuous)
                            .fill(AINewsTheme.accentCyan.opacity(0.06))
                            .frame(width: 112, height: 12)
                        Capsule(style: .continuous)
                            .fill(Color.white.opacity(0.024))
                            .frame(height: 18)
                        Capsule(style: .continuous)
                            .fill(Color.white.opacity(0.02))
                            .frame(width: 190, height: 18)
                        Capsule(style: .continuous)
                            .fill(Color.white.opacity(0.018))
                            .frame(width: 146, height: 12)
                    }
                    Spacer(minLength: 0)
                }
                .padding(14),
                alignment: .topLeading
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(AINewsTheme.panelBorder.opacity(0.12), lineWidth: 1)
            )
            .scaleEffect(scale)
            .offset(x: xOffset, y: yOffset)
            .opacity(opacity)
            .allowsHitTesting(false)
            .frame(height: 168)
    }

    private func stackNavLabel(systemImage: String, title: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(widgetFont(12, weight: .semibold))
            Text(title)
                .font(widgetFont(12, weight: .semibold))
        }
        .foregroundStyle(AINewsTheme.textPrimary)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(AINewsTheme.backgroundAlt.opacity(0.92))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(AINewsTheme.panelBorder.opacity(0.75), lineWidth: 1)
        )
    }

    private var currentStackStory: WidgetStory? {
        guard stories.indices.contains(stackIndex) else { return stories.first }
        return stories[stackIndex]
    }

    private func stackStory(offsetBy offset: Int) -> WidgetStory? {
        let target = stackIndex + offset
        guard stories.indices.contains(target) else { return nil }
        return stories[target]
    }

    private func moveStack(by delta: Int) {
        guard !stories.isEmpty else { return }
        if let current = currentStackStory {
            markStorySeen(current.storyKey)
        }
        stackIndex = max(0, min(stories.count - 1, stackIndex + delta))
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
                .font(widgetFont(12, weight: .semibold))
            Text(title)
                .font(widgetFont(12, weight: .semibold))
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

    private func storyRow(_ story: WidgetStory, draggable: Bool = true) -> some View {
        ZStack(alignment: .topTrailing) {
            HStack(alignment: .top, spacing: 12) {
                if coversEnabled {
                    StoryThumbnail(url: story.coverUrl.flatMap { URL(string: $0) }, size: 66)
                }
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Text(story.source ?? story.feedUrl)
                            .font(widgetCaption(weight: .semibold))
                            .foregroundStyle(AINewsTheme.accentCyan)
                            .lineLimit(1)
                        if showsNewBadge(for: story) {
                            newBadge
                        }
                        if let mood = story.mood, !mood.isEmpty {
                            MoodChip(mood: mood)
                        }
                    }
                    if let date = story.publishedDate {
                        Text(date.formatted(date: .abbreviated, time: .shortened))
                            .font(widgetCaption2())
                            .foregroundStyle(AINewsTheme.textMuted)
                    }

                    Text(story.title)
                        .font(widgetHeadline(weight: .bold))
                        .foregroundStyle(AINewsTheme.accentBlue)
                        .fixedSize(horizontal: false, vertical: true)

                    if let translated = story.translatedTitle, !translated.isEmpty, translated != story.title {
                        Text(translated)
                            .font(widgetCaption())
                            .foregroundStyle(AINewsTheme.accentGold)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    block("Summary", story.summary, pending: story.summaryPending, enabled: state.globalAiDefaults.summaryEnabled, accent: AINewsTheme.accentBlue)
                    block("Research", story.research, pending: story.researchPending, enabled: state.globalAiDefaults.researchEnabled, accent: AINewsTheme.accentCyan)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.trailing, 30)
            }

            Button {
                Task { await state.shareStory(story) }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: copiedStoryKey == story.storyKey ? "checkmark" : "square.and.arrow.up")
                        .font(widgetCaption(weight: .semibold))
                    if copiedStoryKey == story.storyKey {
                        Text("Copied")
                            .font(widgetCaption2(weight: .semibold))
                    }
                }
            }
            .buttonStyle(.borderless)
            .foregroundStyle(copiedStoryKey == story.storyKey ? AINewsTheme.accentCyan : AINewsTheme.textMuted)
            .help("Copy a share link for this story")
        }
        .padding(12)
        .aiNewsCardStyle()
        .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .opacity(draggedStoryKey == story.storyKey ? 0.72 : 1)
        .onTapGesture {
            openStory(story)
        }
        .onDrag {
            guard draggable else { return NSItemProvider() }
            draggedStoryKey = story.storyKey
            return NSItemProvider(object: story.storyKey as NSString)
        } preview: {
            HStack(alignment: .top, spacing: 10) {
                if coversEnabled {
                    StoryThumbnail(url: story.coverUrl.flatMap { URL(string: $0) }, size: 46)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(story.source ?? story.feedUrl)
                        .font(widgetCaption(weight: .semibold))
                        .foregroundStyle(AINewsTheme.accentCyan)
                        .lineLimit(1)
                    Text(story.title)
                        .font(widgetHeadline(weight: .bold))
                        .foregroundStyle(AINewsTheme.accentBlue)
                        .lineLimit(3)
                    if let summary = story.summary, !summary.isEmpty {
                        Text(summary)
                            .font(widgetCaption())
                            .foregroundStyle(AINewsTheme.textSecondary)
                            .lineLimit(2)
                    }
                }
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(AINewsTheme.backgroundAlt.opacity(0.96))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(AINewsTheme.panelBorder.opacity(0.8), lineWidth: 1)
            )
            .opacity(0.9)
            .frame(width: 300, alignment: .leading)
        }
        .onDrop(of: [UTType.plainText], delegate: StoryDropDelegate(
            targetStoryKey: story.storyKey,
            stories: $stories,
            draggedStoryKey: $draggedStoryKey,
            onReordered: persistStoryOrder,
            onStackNeedsClamp: clampStackIndex
        ))
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
                    .font(widgetCaption2(weight: .semibold))
                    .foregroundStyle(accent.opacity(0.9))
                if let text, !text.isEmpty {
                    Text(text)
                        .font(widgetBody())
                        .foregroundStyle(AINewsTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text(pending ? "Generating…" : "Not generated yet.")
                        .font(widgetBody())
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
                updateStories(matches)
            }
        } else if let response = try? await api.fetchStories(categoryID: categoryID, limit: visibleCount) {
            updateStories(response.stories)
        }
    }

    private func updateStories(_ fetchedStories: [WidgetStory]) {
        reachedEnd = fetchedStories.count < visibleCount
        stories = applyLocalOrder(to: fetchedStories)
        clampStackIndex()
        persistStoryOrder()
    }

    private func applyLocalOrder(to fetchedStories: [WidgetStory]) -> [WidgetStory] {
        let storedOrder = FloatingWidgetPreferences.storyOrder(categoryID: categoryID, isFiltered: isFiltered)
        guard !storedOrder.isEmpty else { return fetchedStories }
        let byKey = Dictionary(uniqueKeysWithValues: fetchedStories.map { ($0.storyKey, $0) })
        var ordered = storedOrder.compactMap { byKey[$0] }
        let seen = Set(ordered.map(\.storyKey))
        ordered.append(contentsOf: fetchedStories.filter { !seen.contains($0.storyKey) })
        return ordered
    }

    private func persistStoryOrder() {
        FloatingWidgetPreferences.setStoryOrder(orderedStoryKeys, categoryID: categoryID, isFiltered: isFiltered)
    }

    private func persistSeenStories() {
        FloatingWidgetPreferences.setSeenStories(seenStoryKeys, categoryID: categoryID, isFiltered: isFiltered)
    }

    private func clampStackIndex() {
        stackIndex = max(0, min(stackIndex, max(stories.count - 1, 0)))
    }

    private func markStorySeen(_ storyKey: String) {
        guard !storyKey.isEmpty, !seenStoryKeys.contains(storyKey) else { return }
        seenStoryKeys.insert(storyKey)
        persistSeenStories()
    }

    private func showsNewBadge(for story: WidgetStory) -> Bool {
        layoutMode == .stack && currentStackStory?.storyKey == story.storyKey && !seenStoryKeys.contains(story.storyKey)
    }

    private var newBadge: some View {
        Text("NEW")
            .font(widgetCaption2(weight: .bold))
            .foregroundStyle(Color.black)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(
                Capsule(style: .continuous)
                    .fill(AINewsTheme.accentGold.opacity(0.98))
            )
    }

    private func resizeWindowForCurrentLayout() {
        DispatchQueue.main.async {
            guard let window = currentWidgetWindow() else { return }
            var frame = window.frame
            let targetHeight: CGFloat = layoutMode == .stack ? estimatedStackWindowHeight : max(frame.height, 560)
            let targetWidth: CGFloat = layoutMode == .stack ? estimatedStackWindowWidth : frame.width
            let deltaHeight = targetHeight - frame.height
            let deltaWidth = targetWidth - frame.width
            frame.origin.y -= deltaHeight
            frame.origin.x -= deltaWidth / 2
            frame.size.height = targetHeight
            frame.size.width = targetWidth
            window.setFrame(frame, display: true, animate: true)
        }
    }

    private func currentWidgetWindow() -> NSWindow? {
        if let exact = NSApp.windows.first(where: { $0.title == categoryName && $0.isVisible }) {
            return exact
        }
        return NSApp.keyWindow ?? NSApp.mainWindow
    }
}

private struct StoryDropDelegate: DropDelegate {
    let targetStoryKey: String
    @Binding var stories: [WidgetStory]
    @Binding var draggedStoryKey: String?
    let onReordered: () -> Void
    let onStackNeedsClamp: () -> Void

    func dropEntered(info: DropInfo) {
        guard let draggedStoryKey, draggedStoryKey != targetStoryKey else { return }
        guard let fromIndex = stories.firstIndex(where: { $0.storyKey == draggedStoryKey }),
              let toIndex = stories.firstIndex(where: { $0.storyKey == targetStoryKey }) else { return }
        let adjustedTarget = fromIndex < toIndex ? toIndex : toIndex
        if fromIndex != adjustedTarget {
            stories.move(fromOffsets: IndexSet(integer: fromIndex), toOffset: adjustedTarget)
        }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        draggedStoryKey = nil
        onReordered()
        onStackNeedsClamp()
        return true
    }

    func dropExited(info: DropInfo) {
        onReordered()
    }
}
