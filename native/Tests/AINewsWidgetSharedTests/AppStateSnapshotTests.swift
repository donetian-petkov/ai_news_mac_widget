import XCTest
@testable import AINewsWidgetShared

final class AppStateSnapshotTests: XCTestCase {
    @MainActor
    private func makeState() -> (WidgetAppState, SnapshotStore) {
        let root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString, isDirectory: true)
        let store = SnapshotStore(rootDirectory: root)
        let sessions = SessionStore(defaults: UserDefaults(suiteName: UUID().uuidString)!)
        return (WidgetAppState(sessionStore: sessions, snapshotStore: store), store)
    }

    @MainActor
    func testFilteredViewFallsBackToStoriesWhenKeywordMatchesEmpty() {
        let (state, store) = makeState()
        let story = WidgetStory(id: "s1", feedUrl: "https://example.com/rss", title: "Shown")
        state.selectedCategoryID = FilteredCategoryID
        state.stories = [story]
        state.keywordMatches = []
        state.saveSnapshot()
        XCTAssertEqual(store.loadSnapshot().keywordMatches.map(\.id), ["s1"])
    }

    @MainActor
    func testKeywordMatchesWinWhenPresent() {
        let (state, store) = makeState()
        state.selectedCategoryID = FilteredCategoryID
        state.stories = [WidgetStory(id: "s1", feedUrl: "f", title: "a")]
        state.keywordMatches = [WidgetStory(id: "k1", feedUrl: "f", title: "b")]
        state.saveSnapshot()
        XCTAssertEqual(store.loadSnapshot().keywordMatches.map(\.id), ["k1"])
    }

    @MainActor
    func testCategoryViewKeepsKeywordMatchesAndStoresStories() {
        let (state, store) = makeState()
        state.selectedCategoryID = 7
        state.stories = [WidgetStory(id: "s1", feedUrl: "f", title: "a")]
        state.keywordMatches = []
        state.saveSnapshot()
        let snapshot = store.loadSnapshot()
        XCTAssertEqual(snapshot.keywordMatches.count, 0)
        XCTAssertEqual(snapshot.storiesByCategory["7"]?.map(\.id), ["s1"])
    }
}
