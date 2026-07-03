import Foundation

public enum JSONValue: Codable, Equatable, Sendable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case object([String: JSONValue])
    case array([JSONValue])
    case null

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([String: JSONValue].self) {
            self = .object(value)
        } else if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported JSON value.")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value):
            try container.encode(value)
        case .number(let value):
            try container.encode(value)
        case .bool(let value):
            try container.encode(value)
        case .object(let value):
            try container.encode(value)
        case .array(let value):
            try container.encode(value)
        case .null:
            try container.encodeNil()
        }
    }

    public var stringValue: String {
        switch self {
        case .string(let value):
            return value
        case .number(let value):
            if value.rounded() == value {
                return String(Int(value))
            }
            return String(value)
        case .bool(let value):
            return value ? "true" : "false"
        case .object(let value):
            return value.map { "\($0.key): \($0.value.stringValue)" }.joined(separator: ", ")
        case .array(let value):
            return value.map(\.stringValue).joined(separator: ", ")
        case .null:
            return ""
        }
    }
}

public struct UserSession: Codable, Equatable, Sendable {
    public var token: String
    public var user: UserAccount

    public init(token: String, user: UserAccount) {
        self.token = token
        self.user = user
    }
}

public struct UserAccount: Codable, Equatable, Hashable, Identifiable, Sendable {
    public var id: Int
    public var username: String

    public init(id: Int, username: String) {
        self.id = id
        self.username = username
    }
}

public struct WidgetCategory: Codable, Equatable, Hashable, Identifiable, Sendable {
    public var id: Int
    public var name: String
    public var description: String
    public var feedUrls: [String]
    public var storyIds: [String]
    public var tags: [String]
    public var hidden: Bool
    public var sortOrder: Int
    public var preferredCount: Int
    public var expandedCount: Int
    public var activeCount: Int
    public var pinnedStoryId: String
    public var pinnedFeedUrl: String
    public var createdAt: String
    public var updatedAt: String

    public init(
        id: Int,
        name: String,
        description: String = "",
        feedUrls: [String] = [],
        storyIds: [String] = [],
        tags: [String] = [],
        hidden: Bool = false,
        sortOrder: Int = 0,
        preferredCount: Int = 5,
        expandedCount: Int = 10,
        activeCount: Int = 5,
        pinnedStoryId: String = "",
        pinnedFeedUrl: String = "",
        createdAt: String = "",
        updatedAt: String = ""
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.feedUrls = feedUrls
        self.storyIds = storyIds
        self.tags = tags
        self.hidden = hidden
        self.sortOrder = sortOrder
        self.preferredCount = preferredCount
        self.expandedCount = expandedCount
        self.activeCount = activeCount
        self.pinnedStoryId = pinnedStoryId
        self.pinnedFeedUrl = pinnedFeedUrl
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    public var snapshotKey: String {
        String(id)
    }

    public func isPinned(_ story: WidgetStory) -> Bool {
        story.id == pinnedStoryId && story.feedUrl == pinnedFeedUrl
    }
}

public struct WidgetStory: Codable, Equatable, Hashable, Identifiable, Sendable {
    public var id: String
    public var feedUrl: String
    public var title: String
    public var translatedTitle: String?
    public var link: String?
    public var source: String?
    public var publishedMs: Int64
    public var summary: String?
    public var research: String?
    public var mood: String?
    public var newsType: String?
    public var isMatch: Bool
    public var filteredOk: Bool
    public var summaryPending: Bool
    public var researchPending: Bool
    public var translationPending: Bool
    public var hasSummary: Bool
    public var hasResearch: Bool
    public var hasTranslation: Bool
    public var imagesEnabled: Bool

    public init(
        id: String,
        feedUrl: String,
        title: String,
        translatedTitle: String? = nil,
        link: String? = nil,
        source: String? = nil,
        publishedMs: Int64 = 0,
        summary: String? = nil,
        research: String? = nil,
        mood: String? = nil,
        newsType: String? = nil,
        isMatch: Bool = true,
        filteredOk: Bool = true,
        summaryPending: Bool = false,
        researchPending: Bool = false,
        translationPending: Bool = false,
        hasSummary: Bool = false,
        hasResearch: Bool = false,
        hasTranslation: Bool = false,
        imagesEnabled: Bool = false
    ) {
        self.id = id
        self.feedUrl = feedUrl
        self.title = title
        self.translatedTitle = translatedTitle
        self.link = link
        self.source = source
        self.publishedMs = publishedMs
        self.summary = summary
        self.research = research
        self.mood = mood
        self.newsType = newsType
        self.isMatch = isMatch
        self.filteredOk = filteredOk
        self.summaryPending = summaryPending
        self.researchPending = researchPending
        self.translationPending = translationPending
        self.hasSummary = hasSummary
        self.hasResearch = hasResearch
        self.hasTranslation = hasTranslation
        self.imagesEnabled = imagesEnabled
    }

    public var storyKey: String {
        "\(feedUrl)::\(id)"
    }

    public var publishedDate: Date? {
        publishedMs > 0 ? Date(timeIntervalSince1970: TimeInterval(publishedMs) / 1000.0) : nil
    }
}

public struct WidgetBootstrapResponse: Codable, Sendable {
    public var ok: Bool
    public var user: UserAccount
    public var categories: [WidgetCategory]
    public var usage: AIUsageExport
    public var widget: WidgetDisplaySettings
}

public struct WidgetDisplaySettings: Codable, Equatable, Sendable {
    public var imagesEnabled: Bool
    public var defaultCount: Int
    public var expandedCount: Int
}

public struct CategoryStoriesResponse: Codable, Sendable {
    public var ok: Bool
    public var category: WidgetCategory
    public var stories: [WidgetStory]
    public var count: Int
    public var limit: Int
    public var pinnedStoryKey: String?
    public var imagesEnabled: Bool
}

public struct WidgetCategoriesResponse: Codable, Sendable {
    public var ok: Bool
    public var items: [WidgetCategory]
}

public struct WidgetMasterCategory: Codable, Sendable {
    public var id: Int
    public var name: String
    public var description: String
    public var feedUrls: [String]
    public var storyIds: [String]
    public var tags: [String]
    public var hidden: Bool
    public var sortOrder: Int
    public var preferredCount: Int
    public var expandedCount: Int
    public var activeCount: Int
    public var pinnedStoryId: String
    public var pinnedFeedUrl: String
    public var createdAt: String?
    public var updatedAt: String?
    public var stories: [WidgetStory]

    public var category: WidgetCategory {
        WidgetCategory(
            id: id,
            name: name,
            description: description,
            feedUrls: feedUrls,
            storyIds: storyIds,
            tags: tags,
            hidden: hidden,
            sortOrder: sortOrder,
            preferredCount: preferredCount,
            expandedCount: expandedCount,
            activeCount: activeCount,
            pinnedStoryId: pinnedStoryId,
            pinnedFeedUrl: pinnedFeedUrl,
            createdAt: createdAt ?? "",
            updatedAt: updatedAt ?? ""
        )
    }
}

public struct WidgetMasterResponse: Codable, Sendable {
    public var ok: Bool
    public var categories: [WidgetMasterCategory]
    public var visibleCategories: Int
    public var lastRefreshMs: Int64
    public var imagesEnabled: Bool
}

public struct WidgetCategoryMutationResponse: Codable, Sendable {
    public var ok: Bool
    public var item: WidgetCategory?
}

public struct FeatureItemResponse: Codable, Sendable {
    public var ok: Bool
    public var item: FeatureItem?
}

public struct FeatureItem: Codable, Sendable {
    public var id: Int
    public var userId: Int
    public var kind: String
    public var title: String
    public var payload: WidgetCategoryPayload
    public var archived: Bool
    public var createdAt: String
    public var updatedAt: String

    public var category: WidgetCategory {
        WidgetCategory(
            id: id,
            name: title,
            description: payload.description,
            feedUrls: payload.feedUrls,
            storyIds: payload.storyIds,
            tags: payload.tags,
            hidden: payload.hidden,
            sortOrder: payload.sortOrder,
            preferredCount: payload.preferredCount,
            expandedCount: payload.expandedCount,
            activeCount: payload.activeCount,
            pinnedStoryId: payload.pinnedStoryId,
            pinnedFeedUrl: payload.pinnedFeedUrl,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }
}

public struct WidgetCategoryPayload: Codable, Equatable, Hashable, Sendable {
    public var name: String
    public var description: String
    public var feedUrls: [String]
    public var storyIds: [String]
    public var tags: [String]
    public var hidden: Bool
    public var sortOrder: Int
    public var preferredCount: Int
    public var expandedCount: Int
    public var activeCount: Int
    public var pinnedStoryId: String
    public var pinnedFeedUrl: String
}

public struct FeatureRecord<Payload: Codable & Sendable>: Codable, Sendable, Identifiable {
    public var id: Int
    public var userId: Int
    public var kind: String
    public var title: String
    public var payload: Payload
    public var archived: Bool
    public var createdAt: String
    public var updatedAt: String
}

public struct FeatureListResponse<Payload: Codable & Sendable>: Codable, Sendable {
    public var ok: Bool
    public var items: [FeatureRecord<Payload>]
}

public struct FeatureMutationResponse<Payload: Codable & Sendable>: Codable, Sendable {
    public var ok: Bool
    public var item: FeatureRecord<Payload>?
}

public struct SavedStoryPayload: Codable, Equatable, Hashable, Sendable {
    public var itemId: String
    public var feedUrl: String
    public var title: String
    public var link: String?
    public var source: String?
    public var coverUrl: String?
    public var tags: [String]
    public var note: String
    public var read: Bool
    public var archived: Bool

    public init(
        itemId: String,
        feedUrl: String,
        title: String,
        link: String? = nil,
        source: String? = nil,
        coverUrl: String? = nil,
        tags: [String] = [],
        note: String = "",
        read: Bool = false,
        archived: Bool = false
    ) {
        self.itemId = itemId
        self.feedUrl = feedUrl
        self.title = title
        self.link = link
        self.source = source
        self.coverUrl = coverUrl
        self.tags = tags
        self.note = note
        self.read = read
        self.archived = archived
    }
}

public struct HistoryEntry: Codable, Equatable, Sendable, Identifiable {
    public var id: Int
    public var userId: Int?
    public var feedUrl: String?
    public var itemId: String?
    public var title: String?
    public var source: String?
    public var stage: String
    public var status: String
    public var reason: String?
    public var detailsJson: String?
    public var createdAt: String
    public var details: [String: JSONValue]?
}

public struct HistoryFetchedEntry: Codable, Equatable, Hashable, Sendable, Identifiable {
    public var id: String {
        "\(feedUrl)-\(itemId)-\(publishedMs ?? 0)"
    }

    public var feedUrl: String
    public var itemId: String
    public var title: String?
    public var source: String?
    public var publishedMs: Int64?
    public var createdAt: String?
    public var stage: String
    public var status: String
}

public struct HistoryResponse: Codable, Sendable {
    public var ok: Bool
    public var items: [HistoryEntry]
    public var fetched: [HistoryFetchedEntry]
}

public struct SourceProfile: Codable, Equatable, Sendable, Identifiable {
    public var id: String { url }
    public var url: String
    public var label: String
    public var kind: String
    public var intervalSec: Int?
    public var discordWebhookUrl: String?
    public var recentCount: Int
    public var latest: WidgetStory?
    public var moods: [String: Int]
    public var newsTypes: [String: Int]
    public var discordEnabled: Bool
}

public struct SourcesResponse: Codable, Sendable {
    public var ok: Bool
    public var items: [SourceProfile]
}

public struct OpmlFeed: Codable, Equatable, Hashable, Sendable, Identifiable {
    public var id: String { xmlUrl }
    public var title: String
    public var xmlUrl: String
    public var htmlUrl: String?
}

public struct OpmlPreviewResponse: Codable, Sendable {
    public var ok: Bool
    public var feeds: [OpmlFeed]
}

public struct OpmlImportResponse: Codable, Sendable {
    public var ok: Bool
    public var feeds: [OpmlFeed]
    public var added: Int
}

public struct AlertRulePayload: Codable, Equatable, Hashable, Sendable {
    public var enabled: Bool
    public var name: String
    public var keywords: [String]
    public var sources: [String]
    public var moods: [String]
    public var newsTypes: [String]
    public var discordWebhookUrl: String
    public var lastCheckedAtMs: Double

    public init(
        enabled: Bool = true,
        name: String,
        keywords: [String] = [],
        sources: [String] = [],
        moods: [String] = [],
        newsTypes: [String] = [],
        discordWebhookUrl: String = "",
        lastCheckedAtMs: Double = 0
    ) {
        self.enabled = enabled
        self.name = name
        self.keywords = keywords
        self.sources = sources
        self.moods = moods
        self.newsTypes = newsTypes
        self.discordWebhookUrl = discordWebhookUrl
        self.lastCheckedAtMs = lastCheckedAtMs
    }
}

public struct SchedulePayload: Codable, Equatable, Hashable, Sendable {
    public var enabled: Bool
    public var name: String
    public var cadence: String
    public var time: String
    public var feedUrls: [String]
    public var format: String
    public var discordWebhookUrl: String
    public var nextRunAtMs: Double
    public var lastRunAtMs: Double

    public init(
        enabled: Bool = true,
        name: String,
        cadence: String = "daily",
        time: String = "08:00",
        feedUrls: [String] = [],
        format: String = "executive",
        discordWebhookUrl: String = "",
        nextRunAtMs: Double = 0,
        lastRunAtMs: Double = 0
    ) {
        self.enabled = enabled
        self.name = name
        self.cadence = cadence
        self.time = time
        self.feedUrls = feedUrls
        self.format = format
        self.discordWebhookUrl = discordWebhookUrl
        self.nextRunAtMs = nextRunAtMs
        self.lastRunAtMs = lastRunAtMs
    }
}

public struct DigestPayload: Codable, Equatable, Hashable, Sendable {
    public var storyIds: [String]
    public var feedUrls: [String]
    public var body: String
    public var format: String
    public var discordWebhookUrl: String

    public init(
        storyIds: [String] = [],
        feedUrls: [String] = [],
        body: String = "",
        format: String = "executive",
        discordWebhookUrl: String = ""
    ) {
        self.storyIds = storyIds
        self.feedUrls = feedUrls
        self.body = body
        self.format = format
        self.discordWebhookUrl = discordWebhookUrl
    }
}

public struct ShareCreateResponse: Codable, Sendable {
    public var ok: Bool
    public var token: String
    public var url: String
}

public struct StoryActionResponse: Codable, Sendable {
    public var ok: Bool
    public var action: String
    public var itemId: String?
    public var feedUrl: String?
}

public struct RuntimeConfigResponse: Codable, Sendable {
    public var ok: Bool
    public var aiProvider: String
    public var aiAvailable: Bool
    public var aiEnabled: Bool
    public var summaryModel: String
    public var researchModel: String
    public var askModel: String
    public var summaryLang: String
    public var researchLang: String
    public var titleDisplayLanguage: String
    public var aiDefaults: GlobalAiDefaults?
    public var feeds: [RuntimeFeed]
}

public struct GlobalAiDefaults: Codable, Equatable, Sendable {
    public var summaryEnabled: Bool
    public var researchEnabled: Bool
    public var translationEnabled: Bool

    public init(
        summaryEnabled: Bool = false,
        researchEnabled: Bool = false,
        translationEnabled: Bool = true
    ) {
        self.summaryEnabled = summaryEnabled
        self.researchEnabled = researchEnabled
        self.translationEnabled = translationEnabled
    }
}

public struct RuntimeFeedMutationResponse: Codable, Sendable {
    public var ok: Bool
    public var feed: RuntimeFeed
}

public struct RuntimeAiDefaultsResponse: Codable, Sendable {
    public var ok: Bool
    public var aiDefaults: GlobalAiDefaults
}

public struct RegenerateResponse: Codable, Sendable {
    public struct Counts: Codable, Sendable {
        public var summary: Int
        public var translation: Int
        public var research: Int
    }
    public var ok: Bool
    public var queued: Counts
    public var skipped: Counts
}

public struct RuntimeFeed: Codable, Equatable, Hashable, Sendable {
    public var url: String
    public var label: String
    public var kind: String
    public var intervalSec: Int
    public var settings: RuntimeFeedSettings
}

public struct RuntimeFeedSettings: Codable, Equatable, Hashable, Sendable {
    public var summaryEnabled: Bool
    public var translationEnabled: Bool
    public var researchEnabled: Bool
    public var discordWebhookUrl: String?
    public var budget: String
    public var intervalSec: Int
    public var kind: String
    public var label: String?
}

public struct AccountSettingsResponse: Codable, Sendable {
    public var settings: AccountSettings
}

public struct AccountSettings: Codable, Equatable, Sendable {
    public var aiProvider: String?
    public var summaryModel: String?
    public var researchModel: String?
    public var askModel: String?
    public var showNewsCovers: Bool?

    public init(
        aiProvider: String? = nil,
        summaryModel: String? = nil,
        researchModel: String? = nil,
        askModel: String? = nil,
        showNewsCovers: Bool? = nil
    ) {
        self.aiProvider = aiProvider
        self.summaryModel = summaryModel
        self.researchModel = researchModel
        self.askModel = askModel
        self.showNewsCovers = showNewsCovers
    }
}

public struct ProviderKeyStatusResponse: Codable, Sendable {
    public var hasKey: Bool
}

public struct BasicSuccessResponse: Codable, Sendable {
    public var ok: Bool?
    public var saved: Bool?
}

public struct AIUsageExportResponse: Codable, Sendable {
    public var ok: Bool
    public var usage: AIUsageExport
}

public struct AIUsageExport: Codable, Equatable, Sendable {
    public var generatedAt: String
    public var inputTokens: Int
    public var outputTokens: Int
    public var totalTokens: Int
    public var runtimeStartedAt: Int64
    public var byKind: [String: AIUsageByKind]
    public var recent: [AIRecentUsage]
}

public struct AIUsageByKind: Codable, Equatable, Sendable {
    public var requests: Int
    public var inputTokens: Int
    public var outputTokens: Int
    public var totalTokens: Int
}

public struct AIRecentUsage: Codable, Equatable, Hashable, Identifiable, Sendable {
    public var id: String {
        "\(kind)-\(createdAt)-\(label)"
    }

    public var kind: String
    public var model: String
    public var label: String
    public var inputTokens: Int
    public var outputTokens: Int
    public var totalTokens: Int
    public var createdAt: Int64
}

public struct WidgetSnapshot: Codable, Equatable, Sendable {
    public var lastUpdated: Date
    public var categories: [WidgetCategory]
    public var activeCategoryID: Int?
    public var storiesByCategory: [String: [WidgetStory]]

    public init(
        lastUpdated: Date = Date(),
        categories: [WidgetCategory] = [],
        activeCategoryID: Int? = nil,
        storiesByCategory: [String: [WidgetStory]] = [:]
    ) {
        self.lastUpdated = lastUpdated
        self.categories = categories
        self.activeCategoryID = activeCategoryID
        self.storiesByCategory = storiesByCategory
    }
}

public enum WidgetStoryAction: String, CaseIterable, Codable, Sendable {
    case summary
    case research
    case translation
    case refresh
}

public enum WidgetDeepLinkAction: String, Codable, Sendable {
    case open
    case summary
    case research
    case translation
}

public struct WidgetCommand: Codable, Equatable, Hashable, Identifiable, Sendable {
    public enum Kind: String, Codable, Sendable {
        case refreshCategory
        case pinStory
        case toggleCategoryVisibility
        case expandCategory
        case resetCategory
        case openSummary
        case openResearch
        case openTranslation
    }

    public var id: UUID
    public var kind: Kind
    public var categoryID: Int?
    public var storyID: String?
    public var feedURL: String?
    public var createdAt: Date

    public init(
        id: UUID = UUID(),
        kind: Kind,
        categoryID: Int? = nil,
        storyID: String? = nil,
        feedURL: String? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.kind = kind
        self.categoryID = categoryID
        self.storyID = storyID
        self.feedURL = feedURL
        self.createdAt = createdAt
    }
}

public enum WidgetDeepLink {
    public static func storyURL(
        categoryID: Int,
        storyID: String,
        feedURL: String,
        action: WidgetDeepLinkAction = .open
    ) -> URL? {
        var components = URLComponents()
        components.scheme = "ainewswidget"
        components.host = "story"
        components.queryItems = [
            URLQueryItem(name: "category", value: String(categoryID)),
            URLQueryItem(name: "id", value: storyID),
            URLQueryItem(name: "feed", value: feedURL),
            URLQueryItem(name: "action", value: action.rawValue)
        ]
        return components.url
    }
}
