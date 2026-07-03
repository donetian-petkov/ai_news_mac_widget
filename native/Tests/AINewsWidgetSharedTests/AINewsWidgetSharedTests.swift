import XCTest
@testable import AINewsWidgetShared

final class AINewsWidgetSharedTests: XCTestCase {
    @MainActor
    func testSnapshotRoundTrip() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString, isDirectory: true)
        let store = SnapshotStore(rootDirectory: root)
        let category = WidgetCategory(id: 1, name: "World")
        let story = WidgetStory(id: "story-1", feedUrl: "https://example.com/rss", title: "Hello")
        let snapshot = WidgetSnapshot(
            categories: [category],
            activeCategoryID: category.id,
            storiesByCategory: [category.snapshotKey: [story]]
        )

        try store.saveSnapshot(snapshot)
        let loaded = store.loadSnapshot()

        XCTAssertEqual(loaded.categories.first?.name, "World")
        XCTAssertEqual(loaded.storiesByCategory[category.snapshotKey]?.first?.title, "Hello")
    }

    @MainActor
    func testCommandQueueAppends() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString, isDirectory: true)
        let store = SnapshotStore(rootDirectory: root)
        try store.appendCommand(WidgetCommand(kind: .expandCategory, categoryID: 42))
        try store.appendCommand(WidgetCommand(kind: .resetCategory, categoryID: 42))

        let commands = store.loadCommands()
        XCTAssertEqual(commands.count, 2)
        XCTAssertEqual(commands.first?.kind, .expandCategory)
        XCTAssertEqual(commands.last?.kind, .resetCategory)
    }
}
