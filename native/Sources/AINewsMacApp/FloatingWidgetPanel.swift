import AppKit
import SwiftUI
import UniformTypeIdentifiers
import AINewsWidgetShared

private enum FloatingWidgetLayoutMode: String, CaseIterable {
    case column
    case stack
}

@MainActor private var floatingWidgetHeaderPurple: Color {
    WidgetTheme.isNative ? Color.white.opacity(0.92) : Color(red: 0.56, green: 0.49, blue: 1.0)
}

/// The widget's colors. In the "macOS" background mode the theme palette is
/// swapped for the white-on-glass look of the system desktop widgets; the
/// management app keeps using the regular theme.
@MainActor
private enum WidgetTheme {
    static var isNative: Bool { ThemeSettings.shared.widgetBackgroundMode == .native }

    static var background: Color { isNative ? Color.black.opacity(0.12) : AINewsTheme.background }
    static var backgroundAlt: Color { isNative ? Color.white.opacity(0.14) : AINewsTheme.backgroundAlt }
    static var panel: Color { isNative ? Color.white.opacity(0.16) : AINewsTheme.panel }
    static var panelBorder: Color { isNative ? Color.white.opacity(0.22) : AINewsTheme.panelBorder }
    // Text and icons. In "macOS" mode these are the system's vibrant styles, so
    // they take on the colour of whatever is behind the glass, like the
    // built-in widgets, instead of staying a fixed white.
    static var textPrimary: AnyShapeStyle { isNative ? AnyShapeStyle(.primary) : AnyShapeStyle(AINewsTheme.textPrimary) }
    static var textSecondary: AnyShapeStyle { isNative ? AnyShapeStyle(.primary) : AnyShapeStyle(AINewsTheme.textSecondary) }
    static var textMuted: AnyShapeStyle { isNative ? AnyShapeStyle(.secondary) : AnyShapeStyle(AINewsTheme.textMuted) }
    static var accentBlue: AnyShapeStyle { isNative ? AnyShapeStyle(.primary) : AnyShapeStyle(AINewsTheme.accentBlue) }
    static var accentCyan: AnyShapeStyle { isNative ? AnyShapeStyle(.secondary) : AnyShapeStyle(AINewsTheme.accentCyan) }
    /// Plain colours for the few places that need a `Color` (underlines, chip fills).
    static var accentCyanColor: Color { isNative ? Color.white.opacity(0.80) : AINewsTheme.accentCyan }
    static var accentGold: Color { isNative ? Color(nsColor: .systemOrange) : AINewsTheme.accentGold }
}

private extension View {
    /// Story card chrome: the themed card normally, a light frosted tile in "macOS" mode.
    @ViewBuilder
    func floatingCardStyle() -> some View {
        if WidgetTheme.isNative {
            self
                .background(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(Color.white.opacity(0.08))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .strokeBorder(
                            LinearGradient(
                                colors: [Color.white.opacity(0.24), Color.white.opacity(0.06)],
                                startPoint: .top,
                                endPoint: .bottom
                            ),
                            lineWidth: 1
                        )
                )
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        } else {
            aiNewsCardStyle()
        }
    }
}

/// Holds a weak reference to the window a SwiftUI view is hosted in, so polling
/// code can check whether that window is actually on screen.
private final class HostingWindowBox {
    weak var window: NSWindow?
}

private struct HostingWindowReader: NSViewRepresentable {
    let box: HostingWindowBox
    var onWindow: (NSWindow) -> Void = { _ in }

    func makeNSView(context _: Context) -> NSView {
        ReaderView(box: box, onWindow: onWindow)
    }

    func updateNSView(_ nsView: NSView, context _: Context) {
        box.window = nsView.window ?? box.window
    }

    private final class ReaderView: NSView {
        let box: HostingWindowBox
        let onWindow: (NSWindow) -> Void

        init(box: HostingWindowBox, onWindow: @escaping (NSWindow) -> Void) {
            self.box = box
            self.onWindow = onWindow
            super.init(frame: .zero)
        }

        required init?(coder: NSCoder) { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            box.window = window
            if let window { onWindow(window) }
        }
    }
}

private struct PointingHandCursorView: NSViewRepresentable {
    func makeNSView(context _: Context) -> NSView {
        CursorView()
    }

    func updateNSView(_: NSView, context _: Context) {}

    private final class CursorView: NSView {
        override func resetCursorRects() {
            addCursorRect(bounds, cursor: .pointingHand)
        }

        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            trackingAreas.forEach(removeTrackingArea)
            addTrackingArea(
                NSTrackingArea(
                    rect: bounds,
                    options: [.activeAlways, .inVisibleRect, .mouseEnteredAndExited, .cursorUpdate],
                    owner: self
                )
            )
        }

        override func cursorUpdate(with event: NSEvent) {
            NSCursor.pointingHand.set()
            super.cursorUpdate(with: event)
        }

        override func mouseEntered(with event: NSEvent) {
            NSCursor.pointingHand.set()
            super.mouseEntered(with: event)
        }
    }
}

private extension View {
    func pointingHandCursor() -> some View {
        background(PointingHandCursorView())
    }

    func floatingHeaderCircle(size: CGFloat) -> some View {
        self
            .foregroundStyle(WidgetTheme.textSecondary)
            .frame(width: size, height: size)
            .background(
                Circle()
                    .fill(WidgetTheme.backgroundAlt.opacity(0.92))
            )
            .overlay(
                Circle()
                    .stroke(WidgetTheme.panelBorder.opacity(0.55), lineWidth: 1)
            )
    }

}

private struct FloatingPowerButtonChrome: ViewModifier {
    let poweredOn: Bool
    let size: CGFloat

    func body(content: Content) -> some View {
        content
            .frame(width: size, height: size)
            .background(
                Circle()
                    .fill(poweredOn ? floatingWidgetHeaderPurple : WidgetTheme.backgroundAlt.opacity(0.92))
            )
            .overlay(
                Circle()
                    .stroke(poweredOn ? floatingWidgetHeaderPurple : floatingWidgetHeaderPurple.opacity(0.82), lineWidth: 1.3)
            )
            .shadow(color: poweredOn ? floatingWidgetHeaderPurple.opacity(0.28) : Color.clear, radius: 6, x: 0, y: 0)
    }
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

    private static func frameKey(categoryID: Int, isFiltered: Bool, mode: FloatingWidgetLayoutMode) -> String {
        "AINewsFloatingWidgetFrame-\(widgetKey(categoryID: categoryID, isFiltered: isFiltered))-\(mode.rawValue)"
    }

    private static func storyOrderKey(categoryID: Int, isFiltered: Bool) -> String {
        "AINewsFloatingWidgetStoryOrder-\(widgetKey(categoryID: categoryID, isFiltered: isFiltered))"
    }

    private static func manualStoryOrderKey(categoryID: Int, isFiltered: Bool) -> String {
        "AINewsFloatingWidgetManualStoryOrder-\(widgetKey(categoryID: categoryID, isFiltered: isFiltered))"
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

    static func frame(categoryID: Int, isFiltered: Bool, mode: FloatingWidgetLayoutMode) -> NSRect? {
        guard let saved = UserDefaults.standard.string(forKey: frameKey(categoryID: categoryID, isFiltered: isFiltered, mode: mode)) else {
            return nil
        }
        let frame = NSRectFromString(saved)
        return frame.isEmpty ? nil : frame
    }

    static func setFrame(_ frame: NSRect, categoryID: Int, isFiltered: Bool, mode: FloatingWidgetLayoutMode) {
        UserDefaults.standard.set(
            NSStringFromRect(frame),
            forKey: frameKey(categoryID: categoryID, isFiltered: isFiltered, mode: mode)
        )
    }

    static func removeFrame(categoryID: Int, isFiltered: Bool, mode: FloatingWidgetLayoutMode) {
        UserDefaults.standard.removeObject(forKey: frameKey(categoryID: categoryID, isFiltered: isFiltered, mode: mode))
    }

    static func storyOrder(categoryID: Int, isFiltered: Bool) -> [String] {
        UserDefaults.standard.stringArray(forKey: storyOrderKey(categoryID: categoryID, isFiltered: isFiltered)) ?? []
    }

    static func hasManualStoryOrder(categoryID: Int, isFiltered: Bool) -> Bool {
        UserDefaults.standard.bool(forKey: manualStoryOrderKey(categoryID: categoryID, isFiltered: isFiltered))
    }

    static func setStoryOrder(_ order: [String], categoryID: Int, isFiltered: Bool) {
        UserDefaults.standard.set(order, forKey: storyOrderKey(categoryID: categoryID, isFiltered: isFiltered))
        UserDefaults.standard.set(true, forKey: manualStoryOrderKey(categoryID: categoryID, isFiltered: isFiltered))
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

private extension View {
    /// Glass for the "macOS" mode. On macOS 26+ this is the same Liquid Glass the
    /// system desktop widgets use: the background picks up the wallpaper, and
    /// because SwiftUI knows the content sits on glass, the vibrant text styles
    /// pick it up too. A light dark tint keeps the text readable on bright spots.
    @ViewBuilder
    func nativeWidgetGlass(_ enabled: Bool) -> some View {
        if !enabled {
            self
        } else if #available(macOS 26.0, *) {
            // Run the glass up under the see-through title bar, keeping the
            // header clear of the close button.
            self
                .padding(.top, 28)
                .ignoresSafeArea()
                .glassEffect(.regular.tint(Color.black.opacity(0.28)), in: Rectangle())
                .environment(\.colorScheme, .dark)
        } else {
            self
                .padding(.top, 28)
                .ignoresSafeArea()
                .background(.ultraThinMaterial)
                .environment(\.colorScheme, .dark)
        }
    }
}

/// In "macOS" mode the glass runs under the title bar and only the close button
/// stays, like a desktop widget; other modes keep the normal title bar.
@MainActor
private enum FloatingWidgetChrome {
    static func apply(to window: NSWindow) {
        let native = ThemeSettings.shared.widgetBackgroundMode == .native
        window.standardWindowButton(.zoomButton)?.isHidden = native
        window.standardWindowButton(.miniaturizeButton)?.isHidden = native
        guard window.styleMask.contains(.fullSizeContentView) != native else { return }
        // Changing the style mask makes AppKit refit the window, so put the
        // widget's size and position back afterwards.
        let frame = window.frame
        window.titlebarAppearsTransparent = native
        if native {
            window.styleMask.insert(.fullSizeContentView)
        } else {
            window.styleMask.remove(.fullSizeContentView)
        }
        window.setFrame(frame, display: true)
        window.invalidateShadow()
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
        let isFiltered = entry.key == filteredKey
        let mode = FloatingWidgetPreferences.layoutMode(categoryID: entry.key, isFiltered: isFiltered)
        FloatingWidgetPreferences.setFrame(window.frame, categoryID: entry.key, isFiltered: isFiltered, mode: mode)
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

    private func unmergeWidget(categoryID: Int) {
        guard
            categoryID != filteredKey,
            let mergedIDs = mergedCategoryIDsByBase[categoryID],
            !mergedIDs.isEmpty,
            let basePanel = panels[categoryID]
        else { return }

        isSnappingMergedWidget = true
        let baseName = names[categoryID] ?? categoryName(for: categoryID) ?? basePanel.title
        mergedCategoryIDsByBase.removeValue(forKey: categoryID)
        configurePanelContent(
            basePanel,
            categoryID: categoryID,
            categoryName: baseName,
            isFiltered: false,
            mergedCategoryIDs: []
        )
        basePanel.title = baseName

        let baseFrame = basePanel.frame
        for (index, id) in mergedIDs.enumerated() {
            let name = names[id] ?? categoryName(for: id) ?? "Feed \(id)"
            openWidget(
                categoryID: id,
                categoryName: name,
                isFiltered: false,
                frameOverride: splitFrame(from: baseFrame, index: index),
                mergedCategoryIDs: []
            )
        }

        basePanel.makeKeyAndOrderFront(nil)
        persistFrame(for: basePanel)
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

    private func splitFrame(from baseFrame: NSRect, index: Int) -> NSRect {
        var frame = baseFrame
        let gap: CGFloat = 28
        let stepX = baseFrame.width + gap
        let stepY = min(baseFrame.height + gap, 520)
        frame.origin.x += CGFloat(index + 1) * stepX

        let screenFrame = (NSScreen.screens.first { $0.visibleFrame.intersects(baseFrame) } ?? NSScreen.main)?.visibleFrame
        if let screenFrame, frame.maxX > screenFrame.maxX {
            frame.origin.x = baseFrame.origin.x - CGFloat(index + 1) * stepX
        }
        if let screenFrame, frame.minX < screenFrame.minX {
            frame.origin.x = min(max(baseFrame.origin.x, screenFrame.minX), screenFrame.maxX - frame.width)
            frame.origin.y -= CGFloat(index + 1) * stepY
        }
        if let screenFrame {
            frame.origin.y = min(max(frame.origin.y, screenFrame.minY), screenFrame.maxY - frame.height)
        }
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

    private func categoryName(for id: Int) -> String? {
        state.categories.first(where: { $0.id == id })?.name
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
        FloatingWidgetChrome.apply(to: panel)
        // Remember each widget's size/position across launches, per category.
        // We persist the frame ourselves (windowDidMove/Resize/WillClose) rather
        // than relying on AppKit's autosave, which is unreliable for panels.
        if let frameOverride {
            panel.setFrame(frameOverride, display: false)
        } else if let savedFrame = FloatingWidgetPreferences.frame(
            categoryID: categoryID,
            isFiltered: isFiltered,
            mode: FloatingWidgetPreferences.layoutMode(categoryID: categoryID, isFiltered: isFiltered)
        ) {
            panel.setFrame(savedFrame, display: false)
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
        let controller = NSHostingController(
            rootView: AnyView(
                FloatingWidgetView(
                    categoryID: categoryID,
                    categoryName: categoryName,
                    isFiltered: isFiltered,
                    mergedCategoryIDs: mergedCategoryIDs,
                    onUnmerge: { [weak self] in
                        self?.unmergeWidget(categoryID: categoryID)
                    }
                )
                .environmentObject(state)
                .environmentObject(ThemeSettings.shared)
            )
        )
        return controller
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
    var onUnmerge: () -> Void = {}

    @State private var stories: [WidgetStory] = []
    @State private var loading = false
    @State private var copiedStoryKey: String?
    @State private var draggedStoryKey: String?
    @State private var layoutMode: FloatingWidgetLayoutMode
    @State private var seenStoryKeys: Set<String>
    @State private var stackIndex = 0
    @State private var windowSize: CGSize = .zero
    @State private var lastAutoSizedStackSize: CGSize = .zero
    @State private var lastAutoSizedColumnSize: CGSize = .zero
    @State private var automaticLayoutSwitchInProgress = false
    @State private var explicitLayoutMode: FloatingWidgetLayoutMode?
    @State private var suppressResizeDrivenLayoutSwitch = false
    @State private var suppressResizeDuringRefresh = false
    @State private var lastSourceRefreshAt: Date?
    @State private var windowBox = HostingWindowBox()
    /// How many stories to show. Grows by `pageStep` via "Show More", resets to
    /// `pageStep` via "Reset". Mirrors ai_news_deploy_ready's column behaviour.
    @State private var visibleCount = 10
    /// True once the backend returns fewer stories than requested (no more left).
    @State private var reachedEnd = false
    private let pageStep = 10
    private let sourceRefreshInterval: TimeInterval = 60

    init(
        categoryID: Int,
        categoryName: String,
        isFiltered: Bool = false,
        mergedCategoryIDs: [Int] = [],
        onUnmerge: @escaping () -> Void = {}
    ) {
        self.categoryID = categoryID
        self.categoryName = categoryName
        self.isFiltered = isFiltered
        self.mergedCategoryIDs = mergedCategoryIDs
        self.onUnmerge = onUnmerge
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

    private var pollingFeedStatus: (enabled: Int, total: Int) {
        guard let feeds = state.runtimeConfig?.feeds else { return (0, 0) }
        let feedByURL = Dictionary(uniqueKeysWithValues: feeds.map { ($0.url, $0) })
        let feedURLs: [String]
        if isFiltered {
            feedURLs = feeds.map(\.url)
        } else {
            feedURLs = allCategoryIDs.flatMap { id in
                state.categories.first(where: { $0.id == id })?.feedUrls ?? []
            }
        }
        let uniqueFeedURLs = Array(Set(feedURLs))
        let knownFeeds = uniqueFeedURLs.compactMap { feedByURL[$0] }
        return (
            knownFeeds.filter { $0.settings.pollingEnabled }.count,
            knownFeeds.count
        )
    }

    private var serverStatusText: String {
        state.isRuntimePoweredOn ? "Server on" : "Server off"
    }

    private var fetchStatusText: String {
        if !state.isRuntimePoweredOn {
            return "Fetch off"
        }
        if loading {
            return "Fetching..."
        }
        let status = pollingFeedStatus
        if status.total == 0 {
            return "Fetch unknown"
        }
        if status.enabled == 0 {
            return "Fetch off"
        }
        if status.enabled == status.total {
            return "Fetch on"
        }
        return "Fetch \(status.enabled)/\(status.total)"
    }

    private var runtimeStatusTint: AnyShapeStyle {
        if !state.isRuntimePoweredOn || pollingFeedStatus.enabled == 0 {
            return WidgetTheme.textPrimary
        }
        if loading {
            return WidgetTheme.textPrimary
        }
        return WidgetTheme.textSecondary
    }

    private var runtimeStatusLine: String {
        "\(serverStatusText) · \(fetchStatusText)"
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
        let titleLines = ceil(Double(displayTitle(for: story).count) / lineWidth)
        let secondaryLength = secondaryTitle(for: story)?.isEmpty == false
            ? Double(secondaryTitle(for: story)?.count ?? 0)
            : 0
        let secondaryLines = ceil(secondaryLength / (lineWidth + 4.0))
        let omitSummary = story.shouldOmitSummary(showOriginalTitle: showOriginalTitles)
        let summaryLength = visibleSummary(for: story)?.count ?? 0
        let summaryLines = omitSummary ? 0 : max(1.0, ceil(Double(summaryLength) / (lineWidth + 4.0)))
        let researchLength = story.research?.count ?? 0
        let researchLines = max(1.0, ceil(Double(researchLength) / (lineWidth + 4.0)))
        let sourceLines = ceil(Double((story.source ?? story.feedUrl).count) / 28.0)
        let secondaryHeight = secondaryLines > 0 ? secondaryLines * 19.0 * scale + 8.0 : 0
        let summaryHeight = state.globalAiDefaults.summaryEnabled && !omitSummary ? (summaryLines * 21.0 * scale + 28.0) : 0
        let researchHeight = state.globalAiDefaults.researchEnabled ? (researchLines * 21.0 * scale + 28.0) : 0
        let cardHeight = max(
            214.0,
            42.0
            + (sourceLines * 18.0 * scale)
            + (titleLines * 27.0 * scale)
            + secondaryHeight
            + summaryHeight
            + researchHeight
        )
        let windowChrome = 178.0
        let screenLimit = Double(NSScreen.main?.visibleFrame.height ?? 900) * 0.86
        return CGFloat(min(max(cardHeight + windowChrome, 420.0), screenLimit))
    }

    private var estimatedStackCardHeight: CGFloat {
        max(estimatedStackWindowHeight - 178.0, 214.0)
    }

    private var estimatedStackWindowWidth: CGFloat {
        guard let story = currentStackStory else { return 436 }
        let titleWeight = min(CGFloat(displayTitle(for: story).count) * 0.38, 40)
        let summaryWeight = min(CGFloat(visibleSummary(for: story)?.count ?? 0) * 0.1, 22)
        return min(max(406 + titleWeight + summaryWeight, 430), 468)
    }

    private func stackStoryViewportHeight(for availableHeight: CGFloat) -> CGFloat {
        max(availableHeight, 214)
    }

    private func usesMiniatureStackLayout(size: CGSize) -> Bool {
        size.width < 360 || size.height < 300
    }

    private var stackToColumnHeightThreshold: CGFloat {
        min(max(estimatedStackWindowHeight + 96, 600), 700)
    }

    private func automaticLayoutMode(for size: CGSize) -> FloatingWidgetLayoutMode {
        if usesMiniatureStackLayout(size: size) {
            return .stack
        }
        if size.height >= stackToColumnHeightThreshold, size.width >= 400 {
            return .column
        }
        if size.width >= 760, size.height >= 560 {
            return .column
        }
        return .stack
    }

    private var estimatedColumnWindowWidth: CGFloat {
        420
    }

    private func estimatedColumnCardHeight(for story: WidgetStory) -> CGFloat {
        let titleLines = ceil(Double(displayTitle(for: story).count) / 30.0)
        let secondaryLength = secondaryTitle(for: story)?.isEmpty == false
            ? Double(secondaryTitle(for: story)?.count ?? 0)
            : 0
        let secondaryLines = ceil(secondaryLength / 34.0)
        let summaryLength = visibleSummary(for: story)?.count ?? 0
        let summaryLines = story.shouldOmitSummary(showOriginalTitle: showOriginalTitles)
            ? 0
            : max(1.0, ceil(Double(summaryLength) / 34.0))
        let sourceLines = ceil(Double((story.source ?? story.feedUrl).count) / 26.0)
        let labelHeight = storyLabels(for: story).isEmpty ? 0.0 : 20.0
        let baseHeight = coversEnabled ? 146.0 : 126.0
        let dynamicHeight = (titleLines * 20.0) + (secondaryLines * 14.0) + (summaryLines * 16.0) + (sourceLines * 8.0) + labelHeight
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

    private var usesNativeWidgetBackground: Bool {
        theme.widgetBackgroundMode == .native
    }

    private func applyWindowChrome() {
        // Only ever touch this widget's own panel, never the management window.
        guard let window = windowBox.window else { return }
        FloatingWidgetChrome.apply(to: window)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            if !usesNativeWidgetBackground {
                Divider().overlay(WidgetTheme.panelBorder.opacity(0.5))
            }
            content
        }
        .frame(minWidth: 220, minHeight: 180)
        .background(
            ZStack {
                FloatingGlassBackground(enabled: usesTransparentWidgetBackground)
                if usesNativeWidgetBackground {
                    Color.clear
                } else if usesTransparentWidgetBackground {
                    LinearGradient(
                        colors: [
                            WidgetTheme.backgroundAlt.opacity(0.16),
                            WidgetTheme.background.opacity(0.22)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    RadialGradient(
                        gradient: Gradient(colors: [WidgetTheme.panelBorder.opacity(0.08), .clear]),
                        center: UnitPoint(x: 0.05, y: 0.0),
                        startRadius: 0,
                        endRadius: 520
                    )
                    RadialGradient(
                        gradient: Gradient(colors: [WidgetTheme.accentCyanColor.opacity(0.05), .clear]),
                        center: UnitPoint(x: 1.0, y: 0.02),
                        startRadius: 0,
                        endRadius: 520
                    )
                } else {
                    LinearGradient(
                        colors: [
                            WidgetTheme.backgroundAlt.opacity(0.96),
                            WidgetTheme.background.opacity(0.98)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    RadialGradient(
                        gradient: Gradient(colors: [WidgetTheme.panelBorder.opacity(0.14), .clear]),
                        center: UnitPoint(x: 0.05, y: 0.0),
                        startRadius: 0,
                        endRadius: 520
                    )
                    RadialGradient(
                        gradient: Gradient(colors: [WidgetTheme.accentCyanColor.opacity(0.08), .clear]),
                        center: UnitPoint(x: 1.0, y: 0.02),
                        startRadius: 0,
                        endRadius: 520
                    )
                }
            }
            .ignoresSafeArea()
        )
        .nativeWidgetGlass(usesNativeWidgetBackground)
        .dynamicTypeSize(theme.widgetFontSize.dynamicTypeSize)
        .onChange(of: theme.revision) { _, _ in
            applyWindowChrome()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didResizeNotification)) { notification in
            guard let window = notification.object as? NSWindow,
                  currentWidgetWindow() === window else {
                return
            }
            if suppressResizeDrivenLayoutSwitch {
                windowSize = window.frame.size
                AINewsDebugLog.log(
                    "floating resize notice suppressed size=\(Int(window.frame.width))x\(Int(window.frame.height)) scope=\(displayCategoryName)"
                )
                return
            }
            if window.inLiveResize {
                _ = updateWindowSize(window.frame.size, isUserResize: true)
            } else {
                windowSize = window.frame.size
            }
        }
        .background(HostingWindowReader(box: windowBox) { _ in
            DispatchQueue.main.async { applyWindowChrome() }
        })
        .task {
            // Load now, then auto-refresh so the widget picks up new stories and
            // freshly generated summaries/translations without clicking reload.
            // While the panel is closed or the runtime is powered off, only check
            // cheaply every couple of seconds and reload as soon as it is back.
            // After failed reloads (backend down), wait longer each time.
            var consecutiveFailures = 0
            while !Task.isCancelled {
                guard shouldAutoRefresh else {
                    try? await Task.sleep(nanoseconds: 2_000_000_000)
                    continue
                }
                let succeeded = await reload()
                consecutiveFailures = succeeded ? 0 : consecutiveFailures + 1
                let delay = WidgetPollSchedule.delay(
                    base: isFiltered ? 3 : 12,
                    consecutiveFailures: consecutiveFailures
                )
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            }
        }
        // Refresh immediately when the app signals new AI content (summary/research/translation done).
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("AINewsWidgetShouldRefresh"))) { _ in
            guard shouldAutoRefresh else { return }
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
        .onChange(of: layoutMode) { oldValue, newValue in
            persistCurrentWindowFrame(for: oldValue)
            FloatingWidgetPreferences.setLayoutMode(newValue, categoryID: categoryID, isFiltered: isFiltered)
            if newValue == .stack {
                stackIndex = 0
            } else {
                clampStackIndex()
            }
            if automaticLayoutSwitchInProgress {
                automaticLayoutSwitchInProgress = false
                updateMinimumWindowSize()
            } else if restoreSavedWindowFrame(for: newValue) {
                automaticLayoutSwitchInProgress = false
            } else {
                resizeWindowForCurrentLayout(force: true)
            }
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
            if let window = currentWidgetWindow() {
                let switchedLayout = updateWindowSize(window.frame.size, isUserResize: false)
                if !switchedLayout {
                    resizeWindowForCurrentLayout(force: true)
                }
            } else {
                resizeWindowForCurrentLayout(force: true)
            }
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

    @discardableResult
    private func updateWindowSize(_ size: CGSize, isUserResize: Bool = false) -> Bool {
        guard size.width > 0, size.height > 0 else { return false }
        windowSize = size
        let preferred = automaticLayoutMode(for: size)
        if let explicitLayoutMode {
            if !isUserResize || preferred == explicitLayoutMode {
                return false
            }
            self.explicitLayoutMode = nil
        }
        guard preferred != layoutMode else { return false }
        explicitLayoutMode = nil
        automaticLayoutSwitchInProgress = true
        layoutMode = preferred
        AINewsDebugLog.log(
            "floating auto layout mode=\(preferred.rawValue) userResize=\(isUserResize) size=\(Int(size.width))x\(Int(size.height)) scope=\(displayCategoryName)"
        )
        return true
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
        // The title, the buttons and the status box do not fit on one line at the
        // usual widget width, so the status box gets its own row, centred.
        VStack(spacing: 8) {
            HStack(alignment: .center, spacing: 8) {
                compactHeaderTitleChip
                    .layoutPriority(1)
                Spacer(minLength: 4)
                compactHeaderActions
            }
            compactHeaderMetaInline
                .frame(maxWidth: .infinity, alignment: .center)
        }
    }

    private var headerTitleChip: some View {
        Button {
            if !mergedCategoryIDs.isEmpty {
                onUnmerge()
            }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "newspaper.fill")
                    .font(widgetFont(17, weight: .bold))
                    .foregroundStyle(WidgetTheme.textSecondary)
                Text(displayCategoryName)
                    .font(widgetHeaderTitle())
                    .foregroundStyle(WidgetTheme.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.9)
            }
        }
        .buttonStyle(.plain)
        .help(mergedCategoryIDs.isEmpty ? displayCategoryName : "Unmerge feeds")
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
                    .foregroundStyle(WidgetTheme.textSecondary)
                Text("\(tokenText) tokens")
                    .font(widgetHeaderStat(weight: .bold))
                    .foregroundStyle(WidgetTheme.textSecondary)
                Text(runtimeStatusLine)
                    .font(widgetHeaderStat())
                    .foregroundStyle(runtimeStatusTint)
                Text("\(pendingCount) pending")
                    .font(widgetHeaderStat())
                    .foregroundStyle(pendingCount > 0 ? WidgetTheme.textPrimary : WidgetTheme.textMuted)
            }
            .lineLimit(1)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(headerCapsuleFill)
            .overlay(headerCapsuleStroke)
        }
    }

    private var compactHeaderTitleChip: some View {
        Button {
            if !mergedCategoryIDs.isEmpty {
                onUnmerge()
            }
        } label: {
            HStack(spacing: 7) {
                Image(systemName: "newspaper.fill")
                    .font(widgetFont(16, weight: .bold))
                    .foregroundStyle(WidgetTheme.textSecondary)
                Text(displayCategoryName)
                    .font(widgetFont(17, weight: .bold))
                    .foregroundStyle(WidgetTheme.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        }
        .buttonStyle(.plain)
        .help(mergedCategoryIDs.isEmpty ? displayCategoryName : "Unmerge feeds")
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(compactHeaderCapsuleFill)
        .overlay(compactHeaderCapsuleStroke)
    }

    private var compactHeaderMetaInline: some View {
        TimelineView(.periodic(from: Date(), by: 30)) { context in
            VStack(spacing: 1) {
                Text("\(compactHeaderDate(context.date)) · \(tokenText) tokens")
                    .font(widgetFont(13, weight: .semibold))
                    .foregroundStyle(WidgetTheme.textSecondary)
                HStack(spacing: 0) {
                    Text("\(runtimeStatusLine) · ")
                        .foregroundStyle(runtimeStatusTint)
                    Text("\(pendingCount) pending")
                        .foregroundStyle(pendingCount > 0 ? WidgetTheme.textPrimary : WidgetTheme.textMuted)
                }
                .font(widgetFont(13, weight: .semibold))
            }
            .lineLimit(1)
            .minimumScaleFactor(0.75)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .background(compactHeaderMetaFill)
            .overlay(compactHeaderMetaStroke)
        }
    }

    private var compactHeaderActions: some View {
        HStack(spacing: 5) {
            headerPowerButton(size: 34, fontSize: 15)
            headerModeButton(.column, systemImage: "rectangle.grid.1x2", size: 30)
            headerModeButton(.stack, systemImage: "square.stack.3d.up", size: 30)
            if loading {
                ProgressView().controlSize(.small)
            }
            Button {
                Task { await reload(clearUnchangedNewLabels: true) }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(widgetFont(14, weight: .semibold))
                    .floatingHeaderCircle(size: 30)
            }
            .buttonStyle(.borderless)
            .help("Reload this category")
            .pointingHandCursor()
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    private var headerActions: some View {
        HStack(spacing: 6) {
            headerPowerButton(size: 34, fontSize: 15)
            headerModeButton(.column, systemImage: "rectangle.grid.1x2")
            headerModeButton(.stack, systemImage: "square.stack.3d.up")
            if loading {
                ProgressView().controlSize(.small)
            }
            Button {
                Task { await reload(clearUnchangedNewLabels: true) }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(widgetFont(14, weight: .semibold))
                    .floatingHeaderCircle(size: 30)
            }
            .buttonStyle(.borderless)
            .help("Reload this category")
            .pointingHandCursor()
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    private var headerCapsuleFill: some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(WidgetTheme.panel.opacity(0.58))
    }

    private var headerCapsuleStroke: some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .stroke(WidgetTheme.panelBorder.opacity(0.18), lineWidth: 1)
    }

    private var compactHeaderCapsuleFill: some View {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(WidgetTheme.panel.opacity(0.44))
    }

    private var compactHeaderCapsuleStroke: some View {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
            .stroke(WidgetTheme.panelBorder.opacity(0.14), lineWidth: 1)
    }

    private var compactHeaderMetaFill: some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(WidgetTheme.panel.opacity(0.56))
    }

    private var compactHeaderMetaStroke: some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .stroke(WidgetTheme.panelBorder.opacity(0.16), lineWidth: 1)
    }

    private func headerModeButton(_ mode: FloatingWidgetLayoutMode, systemImage: String, size: CGFloat = 28) -> some View {
        Button {
            switchLayoutMode(to: mode)
        } label: {
            Image(systemName: systemImage)
                .font(widgetFont(size >= 28 ? 13 : 11, weight: .semibold))
                .foregroundStyle(layoutMode == mode ? WidgetTheme.textPrimary : WidgetTheme.textSecondary)
                .frame(width: size, height: size)
                .background(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(layoutMode == mode ? floatingWidgetHeaderPurple.opacity(0.22) : WidgetTheme.backgroundAlt.opacity(0.9))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .stroke(
                            layoutMode == mode ? floatingWidgetHeaderPurple.opacity(0.9) : WidgetTheme.panelBorder.opacity(0.55),
                            lineWidth: 1
                        )
                )
        }
        .buttonStyle(.borderless)
        .help(mode == .column ? "Column view" : "Stack view")
        .pointingHandCursor()
    }

    private func headerPowerButton(size: CGFloat = 30, fontSize: CGFloat = 14) -> some View {
        Button {
            Task {
                if state.isRuntimePoweredOn {
                    await state.powerOff()
                } else {
                    await state.powerOn()
                }
            }
        } label: {
            Image(systemName: "power")
                .font(widgetFont(fontSize + 1.5, weight: .bold))
                .foregroundStyle(state.isRuntimePoweredOn ? Color.black.opacity(0.88) : floatingWidgetHeaderPurple)
                .modifier(FloatingPowerButtonChrome(poweredOn: state.isRuntimePoweredOn, size: size))
        }
        .buttonStyle(.borderless)
        .disabled(state.isBusy)
        .help(state.isRuntimePoweredOn ? "Power off local server and AI. \(runtimeStatusLine)" : "Power on local server and AI. \(runtimeStatusLine)")
        .pointingHandCursor()
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
                    .foregroundStyle(WidgetTheme.textPrimary)
                Text(isFiltered
                     ? "Add keywords (Workspace ▸ Keywords) or tracked topics (Settings ▸ Personalization) to see matches here."
                     : "Refresh this category, or generate summaries from the main window.")
                    .font(widgetFont(12))
                    .foregroundStyle(WidgetTheme.textSecondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(14)
        } else if layoutMode == .stack {
            stackContent
        } else {
            ScrollViewReader { scrollProxy in
                ZStack(alignment: .bottomTrailing) {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 12) {
                            Color.clear
                                .frame(height: 0)
                                .id("floating-column-top")
                            ForEach(stories) { story in
                                storyRow(story)
                            }
                            paginationControls(scrollProxy: scrollProxy)
                            Color.clear
                                .frame(height: 0)
                                .id("floating-column-bottom")
                        }
                        .padding(14)
                    }
                    columnJumpOverlay(scrollProxy: scrollProxy)
                        .padding(.trailing, 14)
                        .padding(.bottom, 18)
                        .opacity(stories.count > 1 ? 1 : 0)
                        .allowsHitTesting(stories.count > 1)
                }
            }
        }
    }

    private func scrollColumnToTop(_ scrollProxy: ScrollViewProxy) {
        withAnimation(.easeInOut(duration: 0.2)) {
            scrollProxy.scrollTo("floating-column-top", anchor: .top)
        }
    }

    private func scrollColumnToBottom(_ scrollProxy: ScrollViewProxy) {
        withAnimation(.easeInOut(duration: 0.2)) {
            scrollProxy.scrollTo("floating-column-bottom", anchor: .bottom)
        }
    }

    private func columnJumpOverlay(scrollProxy: ScrollViewProxy) -> some View {
        VStack(spacing: 8) {
            Button {
                scrollColumnToTop(scrollProxy)
            } label: {
                Image(systemName: "arrow.up.to.line")
                    .font(widgetFont(13, weight: .bold))
                    .foregroundStyle(WidgetTheme.textPrimary)
                    .frame(width: 34, height: 34)
                    .background(
                        Circle()
                            .fill(WidgetTheme.backgroundAlt.opacity(theme.widgetBackgroundMode == .transparent ? 0.82 : 0.96))
                    )
                    .overlay(
                        Circle()
                            .stroke(WidgetTheme.panelBorder.opacity(0.85), lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
            .help("Go to top")

            Button {
                scrollColumnToBottom(scrollProxy)
            } label: {
                Image(systemName: "arrow.down.to.line")
                    .font(widgetFont(13, weight: .bold))
                    .foregroundStyle(WidgetTheme.textPrimary)
                    .frame(width: 34, height: 34)
                    .background(
                        Circle()
                            .fill(WidgetTheme.backgroundAlt.opacity(theme.widgetBackgroundMode == .transparent ? 0.82 : 0.96))
                    )
                    .overlay(
                        Circle()
                            .stroke(WidgetTheme.panelBorder.opacity(0.85), lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
            .help("Go to bottom")
        }
    }

    @ViewBuilder
    private func paginationControls(scrollProxy: ScrollViewProxy) -> some View {
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
                    Task {
                        await reload()
                        await MainActor.run {
                            scrollColumnToTop(scrollProxy)
                        }
                    }
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

    private var stackContent: some View {
        GeometryReader { proxy in
            let availableViewportHeight = max(proxy.size.height - 94, 214)
            let measuredSize = windowSize == .zero ? proxy.size : windowSize
            let isMiniature = usesMiniatureStackLayout(size: measuredSize)

            Group {
                if isMiniature {
                    miniatureStackContent
                } else {
                    fullStackContent(availableViewportHeight: availableViewportHeight)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
    }

    private func fullStackContent(availableViewportHeight: CGFloat) -> some View {
        let cardHeight = min(estimatedStackCardHeight, availableViewportHeight)
        return VStack(spacing: 12) {
            ZStack(alignment: .topLeading) {
                if let tertiary = stackStory(offsetBy: 2) {
                    stackBackdropCard(for: tertiary, scale: 0.92, xOffset: 52, yOffset: 8, opacity: 0.10)
                }
                if let secondary = stackStory(offsetBy: 1) {
                    stackBackdropCard(for: secondary, scale: 0.96, xOffset: 28, yOffset: 4, opacity: 0.16)
                }
                if let current = currentStackStory {
                    storyRow(current, draggable: false, minCardHeight: cardHeight)
                        .frame(
                            maxWidth: .infinity,
                            minHeight: cardHeight,
                            alignment: .topLeading
                        )
                }
            }
            .frame(maxWidth: .infinity, minHeight: cardHeight, maxHeight: cardHeight, alignment: .top)
            .padding(.horizontal, 14)
            .padding(.top, 14)

            stackNavigationControls(spacing: 10, horizontalPadding: 14, bottomPadding: 14, iconOnly: false)
        }
    }

    private var miniatureStackContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let current = currentStackStory {
                VStack(alignment: .leading, spacing: 6) {
                    if current.hasNeutralTitle {
                        neutralizedTitleBadge(compact: true)
                    }
                    Text(displayTitle(for: current))
                        .font(widgetFont(15.5, weight: .bold))
                        .foregroundStyle(WidgetTheme.accentBlue)
                        .underline(isShowingNeutralTitle(for: current), color: WidgetTheme.accentCyanColor.opacity(0.85))
                        .lineLimit(3)
                        .minimumScaleFactor(0.78)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(WidgetTheme.backgroundAlt.opacity(0.94))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(WidgetTheme.panelBorder.opacity(0.72), lineWidth: 1)
                )
                .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .onTapGesture {
                    openStory(current)
                }
            }

            stackNavigationControls(spacing: 6, horizontalPadding: 0, bottomPadding: 0, iconOnly: true)
        }
        .padding(10)
    }

    private func stackNavigationControls(
        spacing: CGFloat,
        horizontalPadding: CGFloat,
        bottomPadding: CGFloat,
        iconOnly: Bool
    ) -> some View {
        HStack(spacing: spacing) {
            Button {
                goToStackStart()
            } label: {
                stackNavLabel(systemImage: "backward.end", title: "Start", iconOnly: iconOnly)
            }
            .buttonStyle(.plain)
            .disabled(stackIndex <= 0)

            Button {
                moveStack(by: -1)
            } label: {
                stackNavLabel(systemImage: "chevron.up", title: "Previous", iconOnly: iconOnly)
            }
            .buttonStyle(.plain)
            .disabled(stackIndex <= 0)

            stackPositionLabel

            Button {
                if canMoveStackForward {
                    moveStack(by: 1)
                } else {
                    loadMoreStackStories()
                }
            } label: {
                stackNavLabel(
                    systemImage: canMoveStackForward ? "chevron.down" : "plus",
                    title: canMoveStackForward ? "Next" : "Load \(pageStep)",
                    iconOnly: iconOnly
                )
            }
            .buttonStyle(.plain)
            .disabled(!canMoveStackForward && (!canLoadMoreStackStories || loading))
        }
        .padding(.horizontal, horizontalPadding)
        .padding(.bottom, bottomPadding)
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
                            .fill(WidgetTheme.accentCyanColor.opacity(0.06))
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
                    .stroke(WidgetTheme.panelBorder.opacity(0.12), lineWidth: 1)
            )
            .scaleEffect(scale)
            .offset(x: xOffset, y: yOffset)
            .opacity(opacity)
            .allowsHitTesting(false)
            .frame(height: 168)
    }

    private func stackNavLabel(systemImage: String, title: String, iconOnly: Bool = false) -> some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(widgetFont(12, weight: .semibold))
            if !iconOnly {
                Text(title)
                    .font(widgetFont(12, weight: .semibold))
            }
        }
        .foregroundStyle(WidgetTheme.textPrimary)
        .frame(maxWidth: .infinity, minHeight: iconOnly ? 30 : 0)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(WidgetTheme.backgroundAlt.opacity(0.92))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(WidgetTheme.panelBorder.opacity(0.75), lineWidth: 1)
        )
    }

    private var stackPositionLabel: some View {
        Text("\(stackIndex + 1) of \(stories.count)")
            .font(widgetFont(12, weight: .bold))
            .foregroundStyle(WidgetTheme.textPrimary)
            .lineLimit(1)
            .minimumScaleFactor(0.82)
            .frame(minWidth: 58)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                Capsule(style: .continuous)
                    .fill(WidgetTheme.backgroundAlt.opacity(0.9))
            )
            .overlay(
                Capsule(style: .continuous)
                    .stroke(WidgetTheme.panelBorder.opacity(0.65), lineWidth: 1)
            )
    }

    private var currentStackStory: WidgetStory? {
        guard stories.indices.contains(stackIndex) else { return stories.first }
        return stories[stackIndex]
    }

    private var canMoveStackForward: Bool {
        stackIndex < stories.count - 1
    }

    private var canLoadMoreStackStories: Bool {
        !reachedEnd && !stories.isEmpty && stackIndex >= stories.count - 1
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

    private func goToStackStart() {
        guard !stories.isEmpty else { return }
        if let current = currentStackStory {
            markStorySeen(current.storyKey)
        }
        stackIndex = 0
        if let first = currentStackStory {
            markStorySeen(first.storyKey)
        }
        resizeWindowForCurrentLayout(force: true)
        AINewsDebugLog.log("floating stack start scope=\(displayCategoryName)")
    }

    private func loadMoreStackStories() {
        guard canLoadMoreStackStories, !loading else { return }
        if let current = currentStackStory {
            markStorySeen(current.storyKey)
        }
        let nextIndex = stories.count
        visibleCount += pageStep
        Task {
            await reload()
            stackIndex = min(nextIndex, max(stories.count - 1, 0))
            resizeWindowForCurrentLayout(force: true)
        }
    }

    private func paginationButtonLabel(title: String, systemImage: String, prominent: Bool) -> some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(widgetFont(12, weight: .semibold))
            Text(title)
                .font(widgetFont(12, weight: .semibold))
                .lineLimit(1)
        }
        .foregroundStyle(prominent ? AnyShapeStyle(Color.black) : WidgetTheme.textPrimary)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(prominent ? WidgetTheme.accentCyanColor.opacity(0.96) : WidgetTheme.backgroundAlt.opacity(0.96))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(
                    prominent ? WidgetTheme.accentCyanColor.opacity(0.98) : WidgetTheme.panelBorder.opacity(0.85),
                    lineWidth: 1
                )
        )
        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    @AppStorage("ai_news_show_thumbnails") private var coversEnabled = true
    @AppStorage("ai_news_show_original_titles") private var showOriginalTitles = false

    private func displayTitle(for story: WidgetStory) -> String {
        story.displayTitle(showOriginalTitle: showOriginalTitles)
    }

    private func secondaryTitle(for story: WidgetStory) -> String? {
        story.secondaryTitle(showOriginalTitle: showOriginalTitles)
    }

    private func visibleSummary(for story: WidgetStory) -> String? {
        story.visibleSummary(showOriginalTitle: showOriginalTitles)
    }

    private func isShowingNeutralTitle(for story: WidgetStory) -> Bool {
        story.hasNeutralTitle && !showOriginalTitles
    }

    private func storyRow(_ story: WidgetStory, draggable: Bool = true, minCardHeight: CGFloat? = nil) -> some View {
        HStack(alignment: .top, spacing: 12) {
            if coversEnabled {
                StoryThumbnail(url: story.coverUrl.flatMap { URL(string: $0) }, size: 66)
            }
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .top, spacing: 8) {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            Text(story.source ?? story.feedUrl)
                                .font(widgetCaption(weight: .semibold))
                                .foregroundStyle(WidgetTheme.accentCyan)
                                .lineLimit(1)
                            if showsNewBadge(for: story) {
                                newBadge
                            }
                            if story.hasNeutralTitle {
                                neutralizedTitleBadge(compact: true)
                            }
                        }
                        if let date = story.publishedDate {
                            Text(date.formatted(date: .abbreviated, time: .shortened))
                                .font(widgetCaption2())
                                .foregroundStyle(WidgetTheme.textMuted)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    storyActionButtons(for: story)
                }

                storyLabelStrip(for: story)

                Text(displayTitle(for: story))
                    .font(widgetHeadline(weight: .bold))
                    .foregroundStyle(WidgetTheme.accentBlue)
                    .underline(isShowingNeutralTitle(for: story), color: WidgetTheme.accentCyanColor.opacity(0.85))
                    .fixedSize(horizontal: false, vertical: true)

                if let secondary = secondaryTitle(for: story) {
                    Text(secondary)
                        .font(widgetCaption())
                        .foregroundStyle(WidgetTheme.accentGold)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if !story.shouldOmitSummary(showOriginalTitle: showOriginalTitles) {
                    block("Summary", visibleSummary(for: story), pending: story.summaryPending, enabled: state.globalAiDefaults.summaryEnabled, accent: WidgetTheme.accentBlue)
                }
                block("Research", story.research, pending: story.researchPending, enabled: state.globalAiDefaults.researchEnabled, accent: WidgetTheme.accentCyan)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
        .frame(minHeight: minCardHeight, alignment: .top)
        .floatingCardStyle()
        .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .opacity(draggedStoryKey == story.storyKey ? 0.72 : 1)
        .onTapGesture {
            markStorySeen(story.storyKey)
            openStory(story)
        }
        .pointingHandCursor()
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
                        .foregroundStyle(WidgetTheme.accentCyan)
                        .lineLimit(1)
                    Text(displayTitle(for: story))
                        .font(widgetHeadline(weight: .bold))
                        .foregroundStyle(WidgetTheme.accentBlue)
                        .underline(isShowingNeutralTitle(for: story), color: WidgetTheme.accentCyanColor.opacity(0.85))
                        .lineLimit(3)
                    if let summary = visibleSummary(for: story), !summary.isEmpty {
                        Text(summary)
                            .font(widgetCaption())
                            .foregroundStyle(WidgetTheme.textSecondary)
                            .lineLimit(2)
                    }
                }
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(WidgetTheme.backgroundAlt.opacity(0.96))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(WidgetTheme.panelBorder.opacity(0.8), lineWidth: 1)
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

    private func hideStoryImmediately(_ story: WidgetStory) {
        let hiddenKey = story.storyKey
        stories.removeAll { $0.storyKey == hiddenKey }
        if copiedStoryKey == hiddenKey {
            copiedStoryKey = nil
        }
        clampStackIndex()
        persistStoryOrder()
        resizeWindowForCurrentLayout()
    }

    @ViewBuilder
    private func block(_ label: String, _ text: String?, pending: Bool, enabled: Bool, accent: AnyShapeStyle) -> some View {
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
                        .foregroundStyle(WidgetTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text(pending ? "Generating…" : "Not generated yet.")
                        .font(widgetBody())
                        .foregroundStyle(WidgetTheme.textMuted)
                }
            }
        }
    }

    private func storyActionButtons(for story: WidgetStory) -> some View {
        HStack(spacing: 8) {
            Button {
                hideStoryImmediately(story)
                Task { await state.triggerStoryAction(.hide, story: story, recordCommand: false) }
            } label: {
                Image(systemName: "eye.slash")
                    .font(widgetCaption(weight: .semibold))
                    .frame(width: 22, height: 22)
            }
            .buttonStyle(.borderless)
            .foregroundStyle(WidgetTheme.textMuted)
            .help("Hide this story from widgets")
            .pointingHandCursor()

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
                .frame(minWidth: copiedStoryKey == story.storyKey ? 58 : 22, minHeight: 22)
            }
            .buttonStyle(.borderless)
            .foregroundStyle(copiedStoryKey == story.storyKey ? WidgetTheme.accentCyan : WidgetTheme.textMuted)
            .help("Copy a share link for this story")
            .pointingHandCursor()
        }
        .fixedSize()
    }

    /// Background refreshes only make sense while the panel is on screen and the
    /// local runtime is powered on. Before the view is attached to a window we
    /// allow the first load.
    private var shouldAutoRefresh: Bool {
        guard state.isRuntimePoweredOn else { return false }
        guard let window = windowBox.window else { return true }
        return window.isVisible
    }

    /// Returns false when the widget could not fetch any stories (for example
    /// because the backend is unreachable), so the poll loop can back off.
    @discardableResult
    private func reload(clearUnchangedNewLabels: Bool = false) async -> Bool {
        suppressResizeDuringRefresh = true
        loading = true
        let previousStoryKeys = Set(stories.map(\.storyKey))
        defer {
            loading = false
            DispatchQueue.main.async {
                suppressResizeDuringRefresh = false
            }
        }
        guard let api = try? state.authorizedAPIClient() else { return false }
        var fetchedAnything = false
        AINewsDebugLog.log("floating reload start filtered=\(isFiltered) categories=\(allCategoryIDs) limit=\(visibleCount)")
        await refreshSourceFeedsIfDue(api: api)
        if isFiltered {
            if let response = try? await api.fetchKeywordMatchesPage(limit: visibleCount) {
                fetchedAnything = true
                updateStories(
                    response.stories,
                    resizeAfterUpdate: false,
                    reachedEndOverride: response.hasMore == false
                )
                AINewsDebugLog.log("floating reload page scope=filtered shown=\(response.stories.count) requested=\(visibleCount) hasMore=\(response.hasMore == true)")
                logTopStory(response.stories, scope: "filtered")
            }
        } else {
            var mergedStories: [WidgetStory] = []
            var fetchedCategoryCount = 0
            var categoryHasMore = false
            for id in allCategoryIDs {
                guard let response = try? await api.fetchStories(categoryID: id, limit: visibleCount) else { continue }
                fetchedCategoryCount += 1
                mergedStories.append(contentsOf: response.stories)
                if response.hasMore == true || (response.hasMore == nil && response.stories.count >= visibleCount) {
                    categoryHasMore = true
                }
            }
            let deduplicated = Dictionary(grouping: mergedStories, by: \.storyKey)
                .compactMap { $0.value.first }
                .sorted { lhs, rhs in lhs.publishedMs > rhs.publishedMs }
            fetchedAnything = fetchedCategoryCount > 0 || allCategoryIDs.isEmpty
            reachedEnd = fetchedCategoryCount > 0 && !categoryHasMore
            let limitedStories = Array(deduplicated.prefix(visibleCount))
            updateStories(limitedStories, resizeAfterUpdate: false, reachedEndOverride: reachedEnd)
            AINewsDebugLog.log("floating reload page scope=\(displayCategoryName) shown=\(limitedStories.count) requested=\(visibleCount) hasMore=\(!reachedEnd)")
            logTopStory(limitedStories, scope: displayCategoryName)
        }
        if clearUnchangedNewLabels {
            self.clearUnchangedNewLabels(previousStoryKeys: previousStoryKeys)
        }
        Task { await state.refreshUsage() }
        return fetchedAnything
    }

    private func refreshSourceFeedsIfDue(api: APIClient) async {
        let now = Date()
        if let lastSourceRefreshAt, now.timeIntervalSince(lastSourceRefreshAt) < sourceRefreshInterval {
            return
        }
        lastSourceRefreshAt = now

        let categoriesToRefresh: [WidgetCategory]
        if isFiltered {
            categoriesToRefresh = state.categories.filter { !$0.hidden && !$0.feedUrls.isEmpty }
        } else {
            categoriesToRefresh = allCategoryIDs.compactMap { id in
                state.categories.first(where: { $0.id == id && !$0.feedUrls.isEmpty })
            }
        }

        AINewsDebugLog.log("floating source refresh start filtered=\(isFiltered) categories=\(categoriesToRefresh.map(\.id))")
        for category in categoriesToRefresh {
            do {
                try await api.refreshCategory(category)
                AINewsDebugLog.log("floating source refresh ok category=\(category.id) feeds=\(category.feedUrls.count)")
            } catch {
                AINewsDebugLog.log("floating source refresh failed category=\(category.id) error=\(error.localizedDescription)")
            }
        }
    }

    private func logTopStory(_ stories: [WidgetStory], scope: String) {
        guard let first = stories.first else {
            AINewsDebugLog.log("floating reload empty scope=\(scope)")
            return
        }
        let published = first.publishedDate.map { ISO8601DateFormatter().string(from: $0) } ?? "unknown"
        AINewsDebugLog.log("floating reload top scope=\(scope) published=\(published) title=\(first.title)")
    }

    private func updateStories(_ fetchedStories: [WidgetStory], resizeAfterUpdate: Bool, reachedEndOverride: Bool? = nil) {
        reachedEnd = reachedEndOverride ?? (fetchedStories.count < visibleCount)
        stories = applyLocalOrder(to: fetchedStories)
        clampStackIndex()
        if resizeAfterUpdate {
            resizeWindowForCurrentLayout()
        }
    }

    private func clearUnchangedNewLabels(previousStoryKeys: Set<String>) {
        let unchangedKeys = Set(stories.map(\.storyKey)).intersection(previousStoryKeys)
        guard !unchangedKeys.isEmpty else { return }
        seenStoryKeys.formUnion(unchangedKeys)
        persistSeenStories()
    }

    private func applyLocalOrder(to fetchedStories: [WidgetStory]) -> [WidgetStory] {
        guard FloatingWidgetPreferences.hasManualStoryOrder(categoryID: categoryID, isFiltered: isFiltered) else {
            return fetchedStories
        }
        let storedOrder = FloatingWidgetPreferences.storyOrder(categoryID: categoryID, isFiltered: isFiltered)
        guard !storedOrder.isEmpty else { return fetchedStories }
        let byKey = Dictionary(uniqueKeysWithValues: fetchedStories.map { ($0.storyKey, $0) })
        let storedKeySet = Set(storedOrder)
        let freshStories = fetchedStories.filter { !storedKeySet.contains($0.storyKey) }
        let manuallyOrderedStories = storedOrder.compactMap { byKey[$0] }
        return freshStories + manuallyOrderedStories
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
        if layoutMode == .stack && currentStackStory?.storyKey != story.storyKey {
            return false
        }
        return !seenStoryKeys.contains(story.storyKey)
    }

    private func storyLabels(for story: WidgetStory) -> [String] {
        let topicLabels = story.topicLabels
            .compactMap(cleanLabel)
            .map(displayLabel)
            .filter { !$0.isEmpty }
        if !topicLabels.isEmpty {
            return Array(topicLabels.prefix(3))
        }
        if let newsType = cleanLabel(story.newsType) {
            return [displayLabel(newsType)]
        }
        return []
    }

    private func cleanLabel(_ value: String?) -> String? {
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

    private func storyLabelStrip(for story: WidgetStory) -> some View {
        HStack(spacing: 6) {
            ForEach(storyLabels(for: story), id: \.self) { label in
                Text(label)
                    .font(widgetCaption2(weight: .bold))
                    .foregroundStyle(WidgetTheme.accentCyan)
                    .lineLimit(1)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(
                        Capsule(style: .continuous)
                            .fill(WidgetTheme.accentCyanColor.opacity(0.12))
                    )
                    .overlay(
                        Capsule(style: .continuous)
                            .stroke(WidgetTheme.accentCyanColor.opacity(0.32), lineWidth: 1)
                    )
            }
        }
    }

    private var newBadge: some View {
        Text("NEW")
            .font(widgetCaption2(weight: .bold))
            .foregroundStyle(Color.black)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(
                Capsule(style: .continuous)
                    .fill(WidgetTheme.accentGold.opacity(0.98))
            )
    }

    private func neutralizedTitleBadge(compact: Bool = false) -> some View {
        Button {
            showOriginalTitles.toggle()
        } label: {
            HStack(spacing: 4) {
                Image(systemName: showOriginalTitles ? "text.quote" : "checkmark.seal.fill")
                if !compact {
                    Text(showOriginalTitles ? "Original title" : "Neutral title")
                } else {
                    Text(showOriginalTitles ? "Original" : "Neutral")
                }
            }
            .font(widgetCaption2(weight: .bold))
            .foregroundStyle(WidgetTheme.accentCyan)
            .padding(.horizontal, compact ? 6 : 8)
            .padding(.vertical, 2)
            .background(
                Capsule(style: .continuous)
                    .fill(WidgetTheme.accentCyanColor.opacity(showOriginalTitles ? 0.08 : 0.15))
            )
            .overlay(
                Capsule(style: .continuous)
                    .stroke(WidgetTheme.accentCyanColor.opacity(showOriginalTitles ? 0.38 : 0.55), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .help(showOriginalTitles ? "Showing the original headline. Click to show the neutral headline." : "Showing the AI-neutralized headline. Click to show the original headline.")
    }

    private func switchLayoutMode(to mode: FloatingWidgetLayoutMode) {
        guard mode != layoutMode else { return }
        persistCurrentWindowFrame(for: layoutMode)
        explicitLayoutMode = mode
        automaticLayoutSwitchInProgress = false
        suppressProgrammaticResizeSwitch()
        layoutMode = mode
        AINewsDebugLog.log("floating manual layout mode=\(mode.rawValue) scope=\(displayCategoryName)")
    }

    private func suppressProgrammaticResizeSwitch() {
        suppressResizeDrivenLayoutSwitch = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) {
            suppressResizeDrivenLayoutSwitch = false
        }
    }

    private func persistCurrentWindowFrame(for mode: FloatingWidgetLayoutMode) {
        guard let window = currentWidgetWindow() else { return }
        FloatingWidgetPreferences.setFrame(window.frame, categoryID: categoryID, isFiltered: isFiltered, mode: mode)
    }

    @discardableResult
    private func restoreSavedWindowFrame(for mode: FloatingWidgetLayoutMode) -> Bool {
        guard let savedFrame = FloatingWidgetPreferences.frame(categoryID: categoryID, isFiltered: isFiltered, mode: mode) else {
            return false
        }
        guard mode != .stack || automaticLayoutMode(for: savedFrame.size) == .stack else {
            FloatingWidgetPreferences.removeFrame(categoryID: categoryID, isFiltered: isFiltered, mode: mode)
            AINewsDebugLog.log(
                "floating ignored invalid saved \(mode.rawValue) frame size=\(Int(savedFrame.width))x\(Int(savedFrame.height)) scope=\(displayCategoryName)"
            )
            return false
        }
        DispatchQueue.main.async {
            guard let window = currentWidgetWindow() else { return }
            suppressProgrammaticResizeSwitch()
            window.minSize = mode == .stack ? NSSize(width: 300, height: 190) : NSSize(width: 400, height: 260)
            window.setFrame(savedFrame, display: true, animate: true)
            windowSize = savedFrame.size
        }
        return true
    }

    private func updateMinimumWindowSize() {
        DispatchQueue.main.async {
            guard let window = currentWidgetWindow() else { return }
            window.minSize = layoutMode == .stack ? NSSize(width: 300, height: 190) : NSSize(width: 400, height: 260)
            windowSize = window.frame.size
        }
    }

    private func resizeWindowForCurrentLayout(force: Bool = false, allowShrink: Bool = true) {
        DispatchQueue.main.async {
            guard let window = currentWidgetWindow() else { return }
            suppressProgrammaticResizeSwitch()
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
            window.minSize = layoutMode == .stack ? NSSize(width: 300, height: 190) : NSSize(width: 400, height: 260)
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
