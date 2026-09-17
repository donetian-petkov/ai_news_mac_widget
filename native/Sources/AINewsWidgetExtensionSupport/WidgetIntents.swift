import Foundation
import AppIntents
import SwiftUI
import AINewsWidgetShared

@available(macOS 14.0, *)
private func persist(_ command: WidgetCommand) async throws {
    try await MainActor.run {
        try SnapshotStore.shared.appendCommand(command)
    }
}

@available(macOS 14.0, *)
private func hideStoryImmediately(categoryID: Int, storyID: String, feedURL: String) async throws {
    try await MainActor.run {
        try SnapshotStore.shared.hideStory(storyID: storyID, feedURL: feedURL)
    }

    let sessionContext = await MainActor.run { () -> (baseURLString: String, token: String?) in
        let store = SessionStore.shared
        return (store.baseURLString, store.session?.token)
    }
    guard let token = sessionContext.token, !token.isEmpty else {
        try await persist(WidgetCommand(kind: .hideStory, categoryID: categoryID, storyID: storyID, feedURL: feedURL))
        return
    }

    do {
        let api = try APIClient(baseURLString: sessionContext.baseURLString, token: token)
        try await api.triggerStoryAction(.hide, story: WidgetStory(id: storyID, feedUrl: feedURL, title: storyID))
    } catch {
        try await persist(WidgetCommand(kind: .hideStory, categoryID: categoryID, storyID: storyID, feedURL: feedURL))
    }
}

@available(macOS 14.0, *)
public struct ToggleRuntimePowerIntent: AppIntent {
    public static let title: LocalizedStringResource = "Toggle AI News Power"
    public static let openAppWhenRun = true

    public init() {}

    public func perform() async throws -> some IntentResult {
        try await MainActor.run {
            let store = SnapshotStore.shared
            let snapshot = store.loadSnapshot()
            let current = snapshot.runtimePower.normalized()
            let next = RuntimePowerState(isPoweredOn: !current.isPoweredOn, autoPowerOffAt: nil)
            try store.setRuntimePower(next)
            try store.appendCommand(WidgetCommand(kind: next.isPoweredOn ? .powerOn : .powerOff))
        }
        return .result()
    }
}

@available(macOS 14.0, *)
public struct RefreshCategoryIntent: AppIntent {
    public static let title: LocalizedStringResource = "Refresh Category"
    public static let openAppWhenRun = true

    @Parameter(title: "Category ID") public var categoryID: Int

    public init() {}
    public init(categoryID: Int) {
        self.categoryID = categoryID
    }

    public func perform() async throws -> some IntentResult {
        try await persist(WidgetCommand(kind: .refreshCategory, categoryID: categoryID))
        return .result()
    }
}

@available(macOS 14.0, *)
public struct PinStoryIntent: AppIntent {
    public static let title: LocalizedStringResource = "Pin Story"
    public static let openAppWhenRun = true

    @Parameter(title: "Category ID") public var categoryID: Int
    @Parameter(title: "Story ID") public var storyID: String
    @Parameter(title: "Feed URL") public var feedURL: String

    public init() {}
    public init(categoryID: Int, storyID: String, feedURL: String) {
        self.categoryID = categoryID
        self.storyID = storyID
        self.feedURL = feedURL
    }

    public func perform() async throws -> some IntentResult {
        try await persist(WidgetCommand(kind: .pinStory, categoryID: categoryID, storyID: storyID, feedURL: feedURL))
        return .result()
    }
}

@available(macOS 14.0, *)
public struct ToggleCategoryVisibilityIntent: AppIntent {
    public static let title: LocalizedStringResource = "Toggle Category Visibility"
    public static let openAppWhenRun = true

    @Parameter(title: "Category ID") public var categoryID: Int

    public init() {}
    public init(categoryID: Int) {
        self.categoryID = categoryID
    }

    public func perform() async throws -> some IntentResult {
        try await persist(WidgetCommand(kind: .toggleCategoryVisibility, categoryID: categoryID))
        return .result()
    }
}

@available(macOS 14.0, *)
public struct ExpandCategoryIntent: AppIntent {
    public static let title: LocalizedStringResource = "Expand Category"
    public static let openAppWhenRun = true

    @Parameter(title: "Category ID") public var categoryID: Int

    public init() {}
    public init(categoryID: Int) {
        self.categoryID = categoryID
    }

    public func perform() async throws -> some IntentResult {
        try await persist(WidgetCommand(kind: .expandCategory, categoryID: categoryID))
        return .result()
    }
}

@available(macOS 14.0, *)
public struct ResetCategoryIntent: AppIntent {
    public static let title: LocalizedStringResource = "Reset Category"
    public static let openAppWhenRun = true

    @Parameter(title: "Category ID") public var categoryID: Int

    public init() {}
    public init(categoryID: Int) {
        self.categoryID = categoryID
    }

    public func perform() async throws -> some IntentResult {
        try await persist(WidgetCommand(kind: .resetCategory, categoryID: categoryID))
        return .result()
    }
}

@available(macOS 14.0, *)
public struct OpenSummaryIntent: AppIntent {
    public static let title: LocalizedStringResource = "Open Summary"
    public static let openAppWhenRun = true

    @Parameter(title: "Category ID") public var categoryID: Int
    @Parameter(title: "Story ID") public var storyID: String
    @Parameter(title: "Feed URL") public var feedURL: String

    public init() {}
    public init(categoryID: Int, storyID: String, feedURL: String) {
        self.categoryID = categoryID
        self.storyID = storyID
        self.feedURL = feedURL
    }

    public func perform() async throws -> some IntentResult {
        try await persist(WidgetCommand(kind: .openSummary, categoryID: categoryID, storyID: storyID, feedURL: feedURL))
        return .result()
    }
}

@available(macOS 14.0, *)
public struct OpenResearchIntent: AppIntent {
    public static let title: LocalizedStringResource = "Open Research"
    public static let openAppWhenRun = true

    @Parameter(title: "Category ID") public var categoryID: Int
    @Parameter(title: "Story ID") public var storyID: String
    @Parameter(title: "Feed URL") public var feedURL: String

    public init() {}
    public init(categoryID: Int, storyID: String, feedURL: String) {
        self.categoryID = categoryID
        self.storyID = storyID
        self.feedURL = feedURL
    }

    public func perform() async throws -> some IntentResult {
        try await persist(WidgetCommand(kind: .openResearch, categoryID: categoryID, storyID: storyID, feedURL: feedURL))
        return .result()
    }
}

@available(macOS 14.0, *)
public struct OpenTranslationIntent: AppIntent {
    public static let title: LocalizedStringResource = "Open Translation"
    public static let openAppWhenRun = true

    @Parameter(title: "Category ID") public var categoryID: Int
    @Parameter(title: "Story ID") public var storyID: String
    @Parameter(title: "Feed URL") public var feedURL: String

    public init() {}
    public init(categoryID: Int, storyID: String, feedURL: String) {
        self.categoryID = categoryID
        self.storyID = storyID
        self.feedURL = feedURL
    }

    public func perform() async throws -> some IntentResult {
        try await persist(WidgetCommand(kind: .openTranslation, categoryID: categoryID, storyID: storyID, feedURL: feedURL))
        return .result()
    }
}

@available(macOS 14.0, *)
public struct OpenShareIntent: AppIntent {
    public static let title: LocalizedStringResource = "Share Story"
    public static let openAppWhenRun = true

    @Parameter(title: "Category ID") public var categoryID: Int
    @Parameter(title: "Story ID") public var storyID: String
    @Parameter(title: "Feed URL") public var feedURL: String

    public init() {}
    public init(categoryID: Int, storyID: String, feedURL: String) {
        self.categoryID = categoryID
        self.storyID = storyID
        self.feedURL = feedURL
    }

    public func perform() async throws -> some IntentResult {
        try await persist(WidgetCommand(kind: .openShare, categoryID: categoryID, storyID: storyID, feedURL: feedURL))
        return .result()
    }
}

@available(macOS 14.0, *)
public struct HideStoryIntent: AppIntent {
    public static let title: LocalizedStringResource = "Hide Story"
    public static let openAppWhenRun = true

    @Parameter(title: "Category ID") public var categoryID: Int
    @Parameter(title: "Story ID") public var storyID: String
    @Parameter(title: "Feed URL") public var feedURL: String

    public init() {}
    public init(categoryID: Int, storyID: String, feedURL: String) {
        self.categoryID = categoryID
        self.storyID = storyID
        self.feedURL = feedURL
    }

    public func perform() async throws -> some IntentResult {
        try await hideStoryImmediately(categoryID: categoryID, storyID: storyID, feedURL: feedURL)
        return .result()
    }
}
