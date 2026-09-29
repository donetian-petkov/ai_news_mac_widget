import XCTest
@testable import AINewsWidgetShared

final class SnapshotStoreDedupTests: XCTestCase {
    private func makeRoot() -> URL {
        URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString, isDirectory: true)
    }

    private func sampleSnapshot(lastUpdated: Date = Date(), title: String = "Hello") -> WidgetSnapshot {
        let category = WidgetCategory(id: 1, name: "World")
        let story = WidgetStory(id: "story-1", feedUrl: "https://example.com/rss", title: title)
        return WidgetSnapshot(
            lastUpdated: lastUpdated,
            categories: [category],
            activeCategoryID: category.id,
            storiesByCategory: [category.snapshotKey: [story], "2": [], "3": []],
            pendingByCategory: ["1": 0, "2": 3, "3": 1]
        )
    }

    @MainActor
    func testSavingSameSnapshotTwiceDoesNotRewriteFile() throws {
        let root = makeRoot()
        let store = SnapshotStore(rootDirectory: root)
        let fileURL = root.appendingPathComponent("widget-snapshot.json")

        try store.saveSnapshot(sampleSnapshot(lastUpdated: Date(timeIntervalSince1970: 1_000)))
        let firstBytes = try Data(contentsOf: fileURL)
        let firstDate = try FileManager.default.attributesOfItem(atPath: fileURL.path)[.modificationDate] as? Date

        // Only lastUpdated differs: must be treated as unchanged.
        try store.saveSnapshot(sampleSnapshot(lastUpdated: Date(timeIntervalSince1970: 2_000)))
        let secondBytes = try Data(contentsOf: fileURL)
        let secondDate = try FileManager.default.attributesOfItem(atPath: fileURL.path)[.modificationDate] as? Date

        XCTAssertEqual(store.snapshotWriteCount, 1)
        XCTAssertEqual(firstBytes, secondBytes)
        XCTAssertEqual(firstDate, secondDate)
    }

    @MainActor
    func testChangedSnapshotIsWritten() throws {
        let root = makeRoot()
        let store = SnapshotStore(rootDirectory: root)
        try store.saveSnapshot(sampleSnapshot(title: "Hello"))
        try store.saveSnapshot(sampleSnapshot(title: "Changed"))
        XCTAssertEqual(store.snapshotWriteCount, 2)
        XCTAssertEqual(store.loadSnapshot().storiesByCategory["1"]?.first?.title, "Changed")
    }

    @MainActor
    func testExternalWriteForcesNextSave() throws {
        let root = makeRoot()
        let store = SnapshotStore(rootDirectory: root)
        let other = SnapshotStore(rootDirectory: root)
        try store.saveSnapshot(sampleSnapshot(title: "Hello"))
        // Another process (the widget extension) rewrites the file.
        Thread.sleep(forTimeInterval: 0.02)
        try other.saveSnapshot(sampleSnapshot(title: "Hidden elsewhere"))
        // The app saving its (unchanged) state must still land on disk.
        try store.saveSnapshot(sampleSnapshot(title: "Hello"))
        XCTAssertEqual(store.snapshotWriteCount, 2)
        XCTAssertEqual(store.loadSnapshot().storiesByCategory["1"]?.first?.title, "Hello")
    }
}
