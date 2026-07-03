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

    public func perform() async throws -> some IntentResult {
        try await persist(WidgetCommand(kind: .openTranslation, categoryID: categoryID, storyID: storyID, feedURL: feedURL))
        return .result()
    }
}
