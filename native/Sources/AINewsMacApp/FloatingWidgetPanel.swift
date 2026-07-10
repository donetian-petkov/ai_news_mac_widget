import AppKit
import SwiftUI
import UniformTypeIdentifiers
import AINewsWidgetShared

private enum FloatingWidgetLayoutMode: String, CaseIterable {
    case column
    case stack
}

struct SavedWidgetEntry: Codable, Equatable, Identifiable {
    var id: String = UUID().uuidString
    var categoryID: Int
    var categoryName: String
    var isFiltered: Bool
    var frame: String
    var mergedCategoryIDs: [Int]? = nil

    init(
        id: String = UUID().uuidString,
        categoryID: Int,
        categoryName: String,
        isFiltered: Bool,
        frame: String,
        mergedCategoryIDs: [Int]? = nil
    ) {
        self.id = id
        self.categoryID = categoryID
        self.categoryName = categoryName
        self.isFiltered = isFiltered
        self.frame = frame
        self.mergedCategoryIDs = mergedCategoryIDs
    }

    private enum CodingKeys: String, CodingKey {
        case id, categoryID, categoryName, isFiltered, frame, mergedCategoryIDs
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        categoryID = try container.decode(Int.self, forKey: .categoryID)
        categoryName = try container.decode(String.self, forKey: .categoryName)
        isFiltered = try container.decode(Bool.self, forKey: .isFiltered)
        frame = try container.decode(String.self, forKey: .frame)
        mergedCategoryIDs = try container.decodeIfPresent([Int].self, forKey: .mergedCategoryIDs)
    }
}

struct SavedWidgetView: Codable, Equatable, Identifiable {
    var id: String = UUID().uuidString
    var name: String
    var widgets: [SavedWidgetEntry]
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
}

enum SavedWidgetViewStore {
    private static let key = "AINewsSavedWidgetViews"

    static func load() -> [SavedWidgetView] {
        guard let data = UserDefaults.standard.data(forKey: key) else { return [] }
        return (try? JSONDecoder().decode([SavedWidgetView].self, from: data)) ?? []
    }

    static func save(_ views: [SavedWidgetView]) {
        guard let data = try? JSONEncoder().encode(views) else { return }
        UserDefaults.standard.set(data, forKey: key)
        NotificationCenter.default.post(name: .aiNewsSavedWidgetViewsChanged, object: nil)
    }

    static func upsert(_ view: SavedWidgetView) {
        var views = load()
        if let index = views.firstIndex(where: { $0.id == view.id }) {
            views[index] = view
        } else {
            views.insert(view, at: 0)
        }
        save(views)
    }

    static func delete(id: String) {
        save(load().filter { $0.id != id })
    }

    static func view(id: String) -> SavedWidgetView? {
        load().first(where: { $0.id == id })
    }
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
    let enabled: Bool

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.state = .active
        view.material = .sidebar
        view.blendingMode = .behindWindow
        view.isEmphasized = false
        view.alphaValue = enabled ? 0.82 : 0
        view.isHidden = !enabled
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.state = .active
        nsView.alphaValue = enabled ? 0.82 : 0
        nsView.isHidden = !enabled
    }
}

/// Owns always-on-top `NSPanel`s that mirror categories. Each category gets its
/// own panel, so several can float at once. Unlike a WidgetKit widget, these are
/// windows the app controls, so they float above other apps and scroll.
@MainActor
final class FloatingWidgetManager: NSObject, NSWindowDelegate {
    private var panels: [Int: NSPanel] = [:]
    private var names: [Int: String] = [:]
    private var mergedCategoryIDsByBase: [Int: [Int]] = [:]
    private var closedStack: [Int] = []
    private let state: WidgetAppState
    private var cascadeIndex = 0
    private var isSnappingMergedWidget = false

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
        guard let window = notification.object as? NSWindow else { return }
        persistFrame(for: window)
        maybeMergeMovedWindow(window)
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

    func saveCurrentView(named rawName: String, replacingID: String? = nil) {
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        let entries = currentVisibleEntries()
        guard !name.isEmpty, !entries.isEmpty else { return }
        var view = SavedWidgetViewStore.view(id: replacingID ?? "") ?? SavedWidgetView(name: name, widgets: [])
        view.name = name
        view.widgets = entries
        view.updatedAt = Date()
        SavedWidgetViewStore.upsert(view)
    }

    func applySavedView(id: String) {
        guard let view = SavedWidgetViewStore.view(id: id) else { return }
        let targetIDs = Set(view.widgets.map(\.categoryID))
        for (id, panel) in panels where panel.isVisible && !targetIDs.contains(id) {
            persistFrame(for: panel)
            panel.orderOut(nil)
        }
        for widget in view.widgets {
            let baseFrame = NSRectFromString(widget.frame)
            openWidget(
                categoryID: widget.categoryID,
                categoryName: widget.categoryName,
                isFiltered: widget.isFiltered,
                frameOverride: baseFrame,
                mergedCategoryIDs: widget.mergedCategoryIDs ?? []
            )
        }
    }

    private func currentVisibleEntries() -> [SavedWidgetEntry] {
        let visible = panels
            .filter { _, panel in panel.isVisible }
            .sorted {
                (names[$0.key] ?? $0.value.title).localizedCaseInsensitiveCompare(names[$1.key] ?? $1.value.title) == .orderedAscending
            }
        visible.forEach { _, panel in persistFrame(for: panel) }

        var consumed = Set<Int>()
        var entries: [SavedWidgetEntry] = []

        for (id, panel) in visible {
            guard !consumed.contains(id) else { continue }
            consumed.insert(id)

            if id == filteredKey {
                entries.append(
                    SavedWidgetEntry(
                        categoryID: id,
                        categoryName: names[id] ?? panel.title,
                        isFiltered: true,
                        frame: NSStringFromRect(panel.frame)
                    )
                )
                continue
            }

            let mergedIDs = mergedCategoryIDsByBase[id] ?? []
            mergedIDs.forEach { consumed.insert($0) }

            entries.append(
                SavedWidgetEntry(
                    categoryID: id,
                    categoryName: names[id] ?? panel.title,
                    isFiltered: false,
                    frame: NSStringFromRect(panel.frame),
                    mergedCategoryIDs: mergedIDs.isEmpty ? nil : mergedIDs
                )
            )
        }

        return entries
    }

    private func maybeMergeMovedWindow(_ window: NSWindow) {
        guard !isSnappingMergedWidget, let movedID = panelID(for: window), movedID != filteredKey else { return }

        let candidates = panels.compactMap { id, panel -> (id: Int, panel: NSPanel, ratio: CGFloat)? in
            guard id != movedID, id != filteredKey, panel.isVisible else { return nil }
            let ratio = mergedOverlapRatio(window.frame, panel.frame)
            return ratio >= 0.50 ? (id, panel, ratio) : nil
        }
        guard let target = candidates.max(by: { $0.ratio < $1.ratio }) else { return }

        isSnappingMergedWidget = true
        let movedMergedIDs = mergedCategoryIDsByBase[movedID] ?? []
        let targetMergedIDs = mergedCategoryIDsByBase[target.id] ?? []
        let combined = orderedUnique(targetMergedIDs + [movedID] + movedMergedIDs)
            .filter { $0 != target.id && $0 != filteredKey }
        mergedCategoryIDsByBase[target.id] = combined
        mergedCategoryIDsByBase.removeValue(forKey: movedID)

        if let movedPanel = panels.removeValue(forKey: movedID) {
            persistFrame(for: movedPanel)
            movedPanel.orderOut(nil)
        }
        configurePanelContent(
            target.panel,
            categoryID: target.id,
            categoryName: names[target.id] ?? target.panel.title,
            isFiltered: false,
            mergedCategoryIDs: combined
        )
        target.panel.title = mergedTitle(categoryName: names[target.id] ?? target.panel.title, mergedCategoryIDs: combined)
        target.panel.makeKeyAndOrderFront(nil)
        persistFrame(for: target.panel)
        isSnappingMergedWidget = false
    }

    private func panelID(for window: NSWindow) -> Int? {
        panels.first(where: { $0.value === window })?.key
    }

    private func mergedFrame(for baseFrame: NSRect, index: Int) -> NSRect {
        var frame = baseFrame
        let offset = CGFloat((index + 1) * 34)
        frame.origin.x += offset
        frame.origin.y -= offset
        return frame
    }

    private func orderedUnique(_ ids: [Int]) -> [Int] {
        var seen = Set<Int>()
        return ids.filter { seen.insert($0).inserted }
    }

    private func mergedOverlapRatio(_ a: NSRect, _ b: NSRect) -> CGFloat {
        let intersection = a.intersection(b)
        guard !intersection.isNull, !intersection.isEmpty else { return 0 }
        let smallerArea = min(rectArea(a), rectArea(b))
        guard smallerArea > 0 else { return 0 }
        return rectArea(intersection) / smallerArea
    }

    private func rectArea(_ rect: NSRect) -> CGFloat {
        max(rect.width, 0) * max(rect.height, 0)
    }

    func openWidget(
        categoryID: Int,
        categoryName: String,
        isFiltered: Bool = false,
        frameOverride: NSRect? = nil,
        mergedCategoryIDs: [Int] = []
    ) {
        names[categoryID] = categoryName
        mergedCategoryIDsByBase[categoryID] = mergedCategoryIDs.isEmpty ? nil : mergedCategoryIDs
        closedStack.removeAll { $0 == categoryID }
        if let existing = panels[categoryID] {
            if let frameOverride {
                existing.setFrame(frameOverride, display: true, animate: true)
            }
            configurePanelContent(
                existing,
                categoryID: categoryID,
                categoryName: categoryName,
                isFiltered: isFiltered,
                mergedCategoryIDs: mergedCategoryIDs
            )
            existing.title = mergedTitle(categoryName: categoryName, mergedCategoryIDs: mergedCategoryIDs)
            existing.makeKeyAndOrderFront(nil)
            return
        }

        let hostingController = makeHostingController(
            categoryID: categoryID,
            categoryName: categoryName,
            isFiltered: isFiltered,
            mergedCategoryIDs: mergedCategoryIDs
        )
        hostingController.view.wantsLayer = true
        hostingController.view.layer?.backgroundColor = NSColor.clear.cgColor

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 560),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        panel.title = mergedTitle(categoryName: categoryName, mergedCategoryIDs: mergedCategoryIDs)
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
        panel.minSize = NSSize(width: 400, height: 260)
        // Remember each widget's size/position across launches, per category.
        // We persist the frame ourselves (windowDidMove/Resize/WillClose) rather
        // than relying on AppKit's autosave, which is unreliable for panels.
        if let frameOverride {
            panel.setFrame(frameOverride, display: false)
        } else if let saved = UserDefaults.standard.string(forKey: Self.frameKey(categoryID)) {
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

    private func makeHostingController(
        categoryID: Int,
        categoryName: String,
        isFiltered: Bool,
        mergedCategoryIDs: [Int]
    ) -> NSHostingController<AnyView> {
        NSHostingController(
            rootView: AnyView(
                FloatingWidgetView(
                    categoryID: categoryID,
                    categoryName: categoryName,
                    isFiltered: isFiltered,
                    mergedCategoryIDs: mergedCategoryIDs
                )
                .environmentObject(state)
                .environmentObject(ThemeSettings.shared)
            )
        )
    }

    private func configurePanelContent(
        _ panel: NSPanel,
        categoryID: Int,
        categoryName: String,
        isFiltered: Bool,
        mergedCategoryIDs: [Int]
    ) {
        let hostingController = makeHostingController(
            categoryID: categoryID,
            categoryName: categoryName,
            isFiltered: isFiltered,
            mergedCategoryIDs: mergedCategoryIDs
        )
        hostingController.view.wantsLayer = true
        hostingController.view.layer?.backgroundColor = NSColor.clear.cgColor
        panel.contentViewController = hostingController
    }

    private func mergedTitle(categoryName: String, mergedCategoryIDs: [Int]) -> String {
        mergedCategoryIDs.isEmpty ? categoryName : "\(categoryName) + \(mergedCategoryIDs.count)"
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
    var mergedCategoryIDs: [Int] = []

    @State private var stories: [WidgetStory] = []
    @State private var loading = false
    @State private var copiedStoryKey: String?
    @State private var draggedStoryKey: String?
    @State private var layoutMode: FloatingWidgetLayoutMode
    @State private var seenStoryKeys: Set<String>
    @State private var stackIndex = 0
    @State private var lastAutoSizedStackSize: CGSize = .zero
    @State private var lastAutoSizedColumnSize: CGSize = .zero
    @State private var suppressResizeDuringRefresh = false
    /// How many stories to show. Grows by `pageStep` via "Show More", resets to
    /// `pageStep` via "Reset". Mirrors ai_news_deploy_ready's column behaviour.
    @State private var visibleCount = 10
    /// True once the backend returns fewer stories than requested (no more left).
    @State private var reachedEnd = false
    private let pageStep = 10

    init(categoryID: Int, categoryName: String, isFiltered: Bool = false, mergedCategoryIDs: [Int] = []) {
        self.categoryID = categoryID
        self.categoryName = categoryName
        self.isFiltered = isFiltered
        self.mergedCategoryIDs = mergedCategoryIDs
        _layoutMode = State(initialValue: FloatingWidgetPreferences.layoutMode(categoryID: categoryID, isFiltered: isFiltered))
        _seenStoryKeys = State(initialValue: FloatingWidgetPreferences.seenStories(categoryID: categoryID, isFiltered: isFiltered))
    }

    private var allCategoryIDs: [Int] {
        var seen = Set<Int>()
        return ([categoryID] + mergedCategoryIDs).filter { seen.insert($0).inserted }
    }

    private var displayCategoryName: String {
        mergedCategoryIDs.isEmpty ? categoryName : "\(categoryName) + \(mergedCategoryIDs.count)"
    }

    private var pendingCount: Int {
        if isFiltered {
            return state.aiProgress.values.reduce(0) { $0 + $1.pending }
        }
        return allCategoryIDs.reduce(into: 0) { total, id in
            guard let category = state.categories.first(where: { $0.id == id }) else { return }
            total += category.feedUrls.reduce(0) { subtotal, url in
                subtotal + (state.aiProgress[url]?.pending ?? 0)
            }
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

    private func compactHeaderDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = .current
        formatter.dateFormat = "d MMM · HH:mm"
        return formatter.string(from: date)
    }

    private var orderedStoryKeys: [String] {
        stories.map(\.storyKey)
    }

    private var estimatedStackWindowHeight: CGFloat {
        guard let story = currentStackStory else { return 460 }
        let scale = Double(widgetFontScale)
        let lineWidth = estimatedStackWindowWidth > 450 ? 34.0 : 30.0
        let titleLines = ceil(Double(story.title.count) / lineWidth)
        let translatedLength = story.translatedTitle?.isEmpty == false && story.translatedTitle != story.title
            ? Double(story.translatedTitle?.count ?? 0)
            : 0
        let translatedLines = ceil(translatedLength / (lineWidth + 4.0))
        let summaryLength = story.summary?.count ?? 0
        let summaryLines = max(1.0, ceil(Double(summaryLength) / (lineWidth + 4.0)))
        let researchLength = story.research?.count ?? 0
        let researchLines = max(1.0, ceil(Double(researchLength) / (lineWidth + 4.0)))
        let sourceLines = ceil(Double((story.source ?? story.feedUrl).count) / 28.0)
        let translatedHeight = translatedLines > 0 ? translatedLines * 19.0 * scale + 8.0 : 0
        let summaryHeight = state.globalAiDefaults.summaryEnabled ? (summaryLines * 21.0 * scale + 28.0) : 0
        let researchHeight = state.globalAiDefaults.researchEnabled ? (researchLines * 21.0 * scale + 28.0) : 0
        let cardHeight = max(
            214.0,
            42.0
            + (sourceLines * 18.0 * scale)
            + (titleLines * 27.0 * scale)
            + translatedHeight
            + summaryHeight
            + researchHeight
        )
        let windowChrome = 178.0
        let screenLimit = Double(NSScreen.main?.visibleFrame.height ?? 900) * 0.86
        return CGFloat(min(max(cardHeight + windowChrome, 420.0), screenLimit))
    }

    private var estimatedStackWindowWidth: CGFloat {
        guard let story = currentStackStory else { return 436 }
        let titleWeight = min(CGFloat(story.title.count) * 0.38, 40)
        let summaryWeight = min(CGFloat(story.summary?.count ?? 0) * 0.1, 22)
        return min(max(406 + titleWeight + summaryWeight, 430), 468)
    }

    private func stackStoryViewportHeight(for availableHeight: CGFloat) -> CGFloat {
        max(availableHeight, 214)
    }

    private var estimatedColumnWindowWidth: CGFloat {
        420
    }

    private func estimatedColumnCardHeight(for story: WidgetStory) -> CGFloat {
        let titleLines = ceil(Double(story.title.count) / 30.0)
        let translatedLength = story.translatedTitle?.isEmpty == false && story.translatedTitle != story.title
            ? Double(story.translatedTitle?.count ?? 0)
            : 0
        let translatedLines = ceil(translatedLength / 34.0)
        let summaryLines = ceil(Double((story.summary ?? "").count) / 34.0)
        let sourceLines = ceil(Double((story.source ?? story.feedUrl).count) / 26.0)
        let baseHeight = coversEnabled ? 138.0 : 118.0
        let dynamicHeight = (titleLines * 20.0) + (translatedLines * 14.0) + (summaryLines * 16.0) + (sourceLines * 8.0)
        return min(max(baseHeight + dynamicHeight, 150.0), 300.0)
    }

    private var estimatedColumnWindowHeight: CGFloat {
        let visibleStories = Array(stories.prefix(4))
        let cardsHeight = visibleStories.reduce(0.0) { $0 + estimatedColumnCardHeight(for: $1) }
        let spacingHeight = max(Double(max(visibleStories.count - 1, 0)) * 12.0, 0)
        let paginationHeight = (!reachedEnd ? 58.0 : 0) + (visibleCount > pageStep ? 58.0 : 0)
        let baseChrome = 140.0
        let total = baseChrome + cardsHeight + spacingHeight + paginationHeight
        return CGFloat(min(max(total, 420.0), 980.0))
    }

    private var usesTransparentWidgetBackground: Bool {
        theme.widgetBackgroundMode == .transparent
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
                FloatingGlassBackground(enabled: usesTransparentWidgetBackground)
                if usesTransparentWidgetBackground {
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
                } else {
                    LinearGradient(
                        colors: [
                            AINewsTheme.backgroundAlt.opacity(0.96),
                            AINewsTheme.background.opacity(0.98)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    RadialGradient(
                        gradient: Gradient(colors: [AINewsTheme.panelBorder.opacity(0.14), .clear]),
                        center: UnitPoint(x: 0.05, y: 0.0),
                        startRadius: 0,
                        endRadius: 520
                    )
                    RadialGradient(
                        gradient: Gradient(colors: [AINewsTheme.accentCyan.opacity(0.08), .clear]),
                        center: UnitPoint(x: 1.0, y: 0.02),
                        startRadius: 0,
                        endRadius: 520
                    )
                }
            }
        )
        .dynamicTypeSize(theme.widgetFontSize.dynamicTypeSize)
        .task {
            // Load now, then auto-refresh so the widget picks up new stories and
            // freshly generated summaries/translations without clicking reload.
            while !Task.isCancelled {
                await reload()
                try? await Task.sleep(nanoseconds: isFiltered ? 3_000_000_000 : 12_000_000_000)
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
            if newValue == .stack {
                stackIndex = 0
            } else {
                clampStackIndex()
            }
            resizeWindowForCurrentLayout(force: true)
        }
        .onChange(of: stackIndex) { _, _ in
            guard !suppressResizeDuringRefresh else { return }
            resizeWindowForCurrentLayout(force: true)
        }
        .onChange(of: currentStackStory?.storyKey) { _, _ in
            guard !suppressResizeDuringRefresh else { return }
            resizeWindowForCurrentLayout(force: true)
        }
        .onAppear {
            resizeWindowForCurrentLayout(force: true)
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
            Text(displayCategoryName)
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
                Text(compactHeaderDate(context.date))
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
            Text(displayCategoryName)
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
                Text(compactHeaderDate(context.date))
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
            let availableViewportHeight = max(proxy.size.height - 94, 214)

            VStack(spacing: 12) {
                ZStack(alignment: .topLeading) {
                    if let tertiary = stackStory(offsetBy: 2) {
                        stackBackdropCard(for: tertiary, scale: 0.92, xOffset: 52, yOffset: 8, opacity: 0.10)
                    }
                    if let secondary = stackStory(offsetBy: 1) {
                        stackBackdropCard(for: secondary, scale: 0.96, xOffset: 28, yOffset: 4, opacity: 0.16)
                    }
                    if let current = currentStackStory {
                        storyRow(current, draggable: false, minCardHeight: stackStoryViewportHeight(for: availableViewportHeight))
                            .frame(
                                maxWidth: .infinity,
                                minHeight: stackStoryViewportHeight(for: availableViewportHeight),
                                alignment: .topLeading
                            )
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 214, maxHeight: availableViewportHeight, alignment: .top)
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

                    stackPositionLabel

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
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
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

    private var stackPositionLabel: some View {
        Text("\(stackIndex + 1) of \(stories.count)")
            .font(widgetFont(12, weight: .bold))
            .foregroundStyle(AINewsTheme.textPrimary)
            .lineLimit(1)
            .frame(minWidth: 72)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                Capsule(style: .continuous)
                    .fill(AINewsTheme.backgroundAlt.opacity(0.9))
            )
            .overlay(
                Capsule(style: .continuous)
                    .stroke(AINewsTheme.panelBorder.opacity(0.65), lineWidth: 1)
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

    private func storyRow(_ story: WidgetStory, draggable: Bool = true, minCardHeight: CGFloat? = nil) -> some View {
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
        .frame(minHeight: minCardHeight, alignment: .top)
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
        suppressResizeDuringRefresh = true
        loading = true
        defer {
            loading = false
            DispatchQueue.main.async {
                suppressResizeDuringRefresh = false
            }
        }
        await state.refreshUsage()
        guard let api = try? state.authorizedAPIClient() else { return }
        if isFiltered {
            if let matches = try? await api.fetchKeywordMatches(limit: visibleCount) {
                updateStories(matches, resizeAfterUpdate: false)
            }
        } else {
            var mergedStories: [WidgetStory] = []
            var exhaustedCategories = 0
            for id in allCategoryIDs {
                guard let response = try? await api.fetchStories(categoryID: id, limit: visibleCount) else { continue }
                mergedStories.append(contentsOf: response.stories)
                if response.stories.count < visibleCount {
                    exhaustedCategories += 1
                }
            }
            let deduplicated = Dictionary(grouping: mergedStories, by: \.storyKey)
                .compactMap { $0.value.first }
                .sorted { lhs, rhs in lhs.publishedMs > rhs.publishedMs }
            reachedEnd = exhaustedCategories == allCategoryIDs.count
            updateStories(Array(deduplicated.prefix(visibleCount)), resizeAfterUpdate: false, reachedEndOverride: reachedEnd)
        }
    }

    private func updateStories(_ fetchedStories: [WidgetStory], resizeAfterUpdate: Bool, reachedEndOverride: Bool? = nil) {
        reachedEnd = reachedEndOverride ?? (fetchedStories.count < visibleCount)
        stories = applyLocalOrder(to: fetchedStories)
        clampStackIndex()
        persistStoryOrder()
        if resizeAfterUpdate {
            resizeWindowForCurrentLayout()
        }
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

    private func resizeWindowForCurrentLayout(force: Bool = false, allowShrink: Bool = true) {
        DispatchQueue.main.async {
            guard let window = currentWidgetWindow() else { return }
            var frame = window.frame
            let targetWidth: CGFloat
            let targetHeight: CGFloat

            if layoutMode == .stack {
                let estimatedWidth = estimatedStackWindowWidth
                let estimatedHeight = estimatedStackWindowHeight
                let isNearLastAutoSize =
                    abs(frame.width - lastAutoSizedStackSize.width) < 14 &&
                    abs(frame.height - lastAutoSizedStackSize.height) < 14

                if force || lastAutoSizedStackSize == .zero || (allowShrink && isNearLastAutoSize) {
                    targetWidth = estimatedWidth
                    targetHeight = estimatedHeight
                } else {
                    targetWidth = max(frame.width, estimatedWidth)
                    targetHeight = max(frame.height, estimatedHeight)
                }
                lastAutoSizedStackSize = CGSize(width: targetWidth, height: targetHeight)
            } else {
                let estimatedWidth = estimatedColumnWindowWidth
                let estimatedHeight = estimatedColumnWindowHeight
                let isNearLastAutoSize =
                    abs(frame.width - lastAutoSizedColumnSize.width) < 14 &&
                    abs(frame.height - lastAutoSizedColumnSize.height) < 14

                if force || lastAutoSizedColumnSize == .zero || isNearLastAutoSize {
                    targetWidth = estimatedWidth
                    targetHeight = estimatedHeight
                } else {
                    targetWidth = max(frame.width, estimatedWidth)
                    targetHeight = max(frame.height, estimatedHeight)
                }
                lastAutoSizedColumnSize = CGSize(width: targetWidth, height: targetHeight)
            }
            let deltaHeight = targetHeight - frame.height
            let deltaWidth = targetWidth - frame.width
            frame.origin.y -= deltaHeight
            frame.origin.x -= deltaWidth / 2
            frame.size.height = targetHeight
            frame.size.width = targetWidth
            window.minSize = layoutMode == .stack ? NSSize(width: 430, height: 220) : NSSize(width: 400, height: 260)
            window.setFrame(frame, display: true, animate: true)
        }
    }

    private func currentWidgetWindow() -> NSWindow? {
        if let exact = NSApp.windows.first(where: { $0.title == displayCategoryName && $0.isVisible }) {
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
