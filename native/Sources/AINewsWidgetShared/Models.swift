import Foundation

public let FilteredFeedURL = "__filtered__"
public let FilteredCategoryID = -1

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
    public var originalTitle: String?
    public var translatedTitle: String?
    public var neutralTitle: String?
    public var neutralTitleBg: String?
    public var neutralTitleEn: String?
    public var neutralTitleStatus: String?
    public var neutralTitleReason: String?
    public var neutralTitleClassification: String?
    public var neutralTitleConfidence: Double?
    public var link: String?
    public var source: String?
    public var publishedMs: Int64
    public var summary: String?
    public var research: String?
    public var mood: String?
    public var newsType: String?
    public var topicLabels: [String]
    public var isMatch: Bool
    public var filteredOk: Bool
    public var summaryPending: Bool
    public var researchPending: Bool
    public var translationPending: Bool
    public var neutralTitlePending: Bool
    public var hasSummary: Bool
    public var hasResearch: Bool
    public var hasTranslation: Bool
    public var hasNeutralTitle: Bool
    public var coverUrl: String?
    public var imagesEnabled: Bool

    public init(
        id: String,
        feedUrl: String,
        title: String,
        originalTitle: String? = nil,
        translatedTitle: String? = nil,
        neutralTitle: String? = nil,
        neutralTitleBg: String? = nil,
        neutralTitleEn: String? = nil,
        neutralTitleStatus: String? = nil,
        neutralTitleReason: String? = nil,
        neutralTitleClassification: String? = nil,
        neutralTitleConfidence: Double? = nil,
        link: String? = nil,
        source: String? = nil,
        publishedMs: Int64 = 0,
        summary: String? = nil,
        research: String? = nil,
        mood: String? = nil,
        newsType: String? = nil,
        topicLabels: [String] = [],
        isMatch: Bool = true,
        filteredOk: Bool = true,
        summaryPending: Bool = false,
        researchPending: Bool = false,
        translationPending: Bool = false,
        neutralTitlePending: Bool = false,
        hasSummary: Bool = false,
        hasResearch: Bool = false,
        hasTranslation: Bool = false,
        hasNeutralTitle: Bool = false,
        coverUrl: String? = nil,
        imagesEnabled: Bool = false
    ) {
        self.id = id
        self.feedUrl = feedUrl
        self.title = title
        self.originalTitle = originalTitle
        self.translatedTitle = translatedTitle
        self.neutralTitle = neutralTitle
        self.neutralTitleBg = neutralTitleBg
        self.neutralTitleEn = neutralTitleEn
        self.neutralTitleStatus = neutralTitleStatus
        self.neutralTitleReason = neutralTitleReason
        self.neutralTitleClassification = neutralTitleClassification
        self.neutralTitleConfidence = neutralTitleConfidence
        self.link = link
        self.source = source
        self.publishedMs = publishedMs
        self.summary = summary
        self.research = research
        self.mood = mood
        self.newsType = newsType
        self.topicLabels = topicLabels
        self.isMatch = isMatch
        self.filteredOk = filteredOk
        self.summaryPending = summaryPending
        self.researchPending = researchPending
        self.translationPending = translationPending
        self.neutralTitlePending = neutralTitlePending
        self.hasSummary = hasSummary
        self.hasResearch = hasResearch
        self.hasTranslation = hasTranslation
        self.hasNeutralTitle = hasNeutralTitle
        self.coverUrl = coverUrl
        self.imagesEnabled = imagesEnabled
    }

    private enum CodingKeys: String, CodingKey {
        case id, feedUrl, title, originalTitle, translatedTitle, neutralTitle, neutralTitleBg, neutralTitleEn
        case neutralTitleStatus, neutralTitleReason, neutralTitleClassification, neutralTitleConfidence
        case link, source, publishedMs, summary, research, mood, newsType, topicLabels
        case isMatch, filteredOk, summaryPending, researchPending, translationPending, neutralTitlePending
        case hasSummary, hasResearch, hasTranslation, hasNeutralTitle, coverUrl, imagesEnabled
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        feedUrl = try container.decode(String.self, forKey: .feedUrl)
        title = try container.decode(String.self, forKey: .title)
        originalTitle = try container.decodeIfPresent(String.self, forKey: .originalTitle)
        translatedTitle = try container.decodeIfPresent(String.self, forKey: .translatedTitle)
        neutralTitle = try container.decodeIfPresent(String.self, forKey: .neutralTitle)
        neutralTitleBg = try container.decodeIfPresent(String.self, forKey: .neutralTitleBg)
        neutralTitleEn = try container.decodeIfPresent(String.self, forKey: .neutralTitleEn)
        neutralTitleStatus = try container.decodeIfPresent(String.self, forKey: .neutralTitleStatus)
        neutralTitleReason = try container.decodeIfPresent(String.self, forKey: .neutralTitleReason)
        neutralTitleClassification = try container.decodeIfPresent(String.self, forKey: .neutralTitleClassification)
        neutralTitleConfidence = try container.decodeIfPresent(Double.self, forKey: .neutralTitleConfidence)
        link = try container.decodeIfPresent(String.self, forKey: .link)
        source = try container.decodeIfPresent(String.self, forKey: .source)
        publishedMs = try container.decodeIfPresent(Int64.self, forKey: .publishedMs) ?? 0
        summary = try container.decodeIfPresent(String.self, forKey: .summary)
        research = try container.decodeIfPresent(String.self, forKey: .research)
        mood = try container.decodeIfPresent(String.self, forKey: .mood)
        newsType = try container.decodeIfPresent(String.self, forKey: .newsType)
        topicLabels = try container.decodeIfPresent([String].self, forKey: .topicLabels) ?? []
        isMatch = try container.decodeIfPresent(Bool.self, forKey: .isMatch) ?? true
        filteredOk = try container.decodeIfPresent(Bool.self, forKey: .filteredOk) ?? true
        summaryPending = try container.decodeIfPresent(Bool.self, forKey: .summaryPending) ?? false
        researchPending = try container.decodeIfPresent(Bool.self, forKey: .researchPending) ?? false
        translationPending = try container.decodeIfPresent(Bool.self, forKey: .translationPending) ?? false
        neutralTitlePending = try container.decodeIfPresent(Bool.self, forKey: .neutralTitlePending) ?? false
        hasSummary = try container.decodeIfPresent(Bool.self, forKey: .hasSummary) ?? false
        hasResearch = try container.decodeIfPresent(Bool.self, forKey: .hasResearch) ?? false
        hasTranslation = try container.decodeIfPresent(Bool.self, forKey: .hasTranslation) ?? false
        hasNeutralTitle = try container.decodeIfPresent(Bool.self, forKey: .hasNeutralTitle) ?? false
        coverUrl = try container.decodeIfPresent(String.self, forKey: .coverUrl)
        imagesEnabled = try container.decodeIfPresent(Bool.self, forKey: .imagesEnabled) ?? false
    }

    public var storyKey: String {
        "\(feedUrl)::\(id)"
    }

    private static func cleanTitle(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    public var sourceOriginalTitle: String {
        Self.cleanTitle(originalTitle) ?? title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public var preferredNeutralTitle: String? {
        let original = sourceOriginalTitle
        let candidates = [
            neutralTitle,
            neutralTitleBg,
            neutralTitleEn,
            hasNeutralTitle && title.trimmingCharacters(in: .whitespacesAndNewlines) != original ? title : nil
        ]
        for candidate in candidates {
            if let cleaned = Self.cleanTitle(candidate), cleaned != original {
                return cleaned
            }
        }
        return nil
    }

    public func displayTitle(showOriginalTitle: Bool) -> String {
        if showOriginalTitle {
            return sourceOriginalTitle
        }
        return preferredNeutralTitle ?? sourceOriginalTitle
    }

    public func secondaryTitle(showOriginalTitle: Bool) -> String? {
        let primary = displayTitle(showOriginalTitle: showOriginalTitle)
        if showOriginalTitle {
            return nil
        }
        guard let translated = Self.cleanTitle(translatedTitle),
              translated != primary,
              translated != sourceOriginalTitle
        else {
            return nil
        }
        return translated
    }

    public func visibleSummary(showOriginalTitle: Bool) -> String? {
        guard let cleanedSummary = Self.cleanTitle(summary) else { return nil }
        return shouldOmitSummary(showOriginalTitle: showOriginalTitle) ? nil : cleanedSummary
    }

    public func shouldOmitSummary(showOriginalTitle: Bool) -> Bool {
        guard let cleanedSummary = Self.cleanTitle(summary),
              !showOriginalTitle,
              let neutral = preferredNeutralTitle
        else {
            return false
        }
        return Self.summaryIsRedundant(cleanedSummary, withTitle: neutral)
    }

    private static func summaryIsRedundant(_ summary: String, withTitle title: String) -> Bool {
        let summaryKey = comparableKey(summary)
        let titleKey = comparableKey(title)
        guard !summaryKey.isEmpty, !titleKey.isEmpty else { return false }
        if summaryKey == titleKey || titleKey.contains(summaryKey) || summaryKey.contains(titleKey) {
            return true
        }

        let summaryWords = Set(comparableWords(summary).filter { $0.count > 2 })
        let titleWords = Set(comparableWords(title).filter { $0.count > 2 })
        guard summaryWords.count >= 3, !titleWords.isEmpty else { return false }

        let overlap = summaryWords.intersection(titleWords).count
        let novelWords = summaryWords.subtracting(titleWords).count
        let overlapRatio = Double(overlap) / Double(summaryWords.count)
        return overlapRatio >= 0.78 && novelWords <= 2
    }

    private static func comparableKey(_ value: String) -> String {
        comparableWords(value).joined(separator: " ")
    }

    private static func comparableWords(_ value: String) -> [String] {
        var normalized = ""
        for scalar in value.lowercased().unicodeScalars {
            if CharacterSet.alphanumerics.contains(scalar) {
                normalized.unicodeScalars.append(scalar)
            } else {
                normalized.append(" ")
            }
        }
        return normalized
            .split(separator: " ")
            .map(String.init)
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
    public var hasMore: Bool?
    public var pinnedStoryKey: String?
    public var imagesEnabled: Bool
}

public struct KeywordMatchesResponse: Codable, Sendable {
    public var ok: Bool
    public var stories: [WidgetStory]
    public var count: Int
    public var limit: Int?
    public var hasMore: Bool?
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

public struct RuleAlertsResponse: Codable, Sendable {
    public var ok: Bool
    public var items: [HistoryEntry]
    public var count: Int?
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
    public var criteria: String
    public var keywords: [String]
    public var sources: [String]
    public var moods: [String]
    public var newsTypes: [String]
    public var discordWebhookUrl: String
    public var dailyScanTime: String
    public var lastCheckedAtMs: Double
    public var lastRunDate: String

    public init(
        enabled: Bool = true,
        name: String,
        criteria: String = "",
        keywords: [String] = [],
        sources: [String] = [],
        moods: [String] = [],
        newsTypes: [String] = [],
        discordWebhookUrl: String = "",
        dailyScanTime: String = "23:55",
        lastCheckedAtMs: Double = 0,
        lastRunDate: String = ""
    ) {
        self.enabled = enabled
        self.name = name
        self.criteria = criteria
        self.keywords = keywords
        self.sources = sources
        self.moods = moods
        self.newsTypes = newsTypes
        self.discordWebhookUrl = discordWebhookUrl
        self.dailyScanTime = dailyScanTime
        self.lastCheckedAtMs = lastCheckedAtMs
        self.lastRunDate = lastRunDate
    }

    private enum CodingKeys: String, CodingKey {
        case enabled, name, criteria, keywords, sources, moods, newsTypes, discordWebhookUrl, dailyScanTime, lastCheckedAtMs, lastRunDate
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? "Alert rule"
        criteria = try container.decodeIfPresent(String.self, forKey: .criteria) ?? ""
        keywords = try container.decodeIfPresent([String].self, forKey: .keywords) ?? []
        sources = try container.decodeIfPresent([String].self, forKey: .sources) ?? []
        moods = try container.decodeIfPresent([String].self, forKey: .moods) ?? []
        newsTypes = try container.decodeIfPresent([String].self, forKey: .newsTypes) ?? []
        discordWebhookUrl = try container.decodeIfPresent(String.self, forKey: .discordWebhookUrl) ?? ""
        dailyScanTime = try container.decodeIfPresent(String.self, forKey: .dailyScanTime) ?? "23:55"
        lastCheckedAtMs = try container.decodeIfPresent(Double.self, forKey: .lastCheckedAtMs) ?? 0
        lastRunDate = try container.decodeIfPresent(String.self, forKey: .lastRunDate) ?? ""
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
    public var neutralTitlesEnabled: Bool

    public init(
        summaryEnabled: Bool = false,
        researchEnabled: Bool = false,
        translationEnabled: Bool = true,
        neutralTitlesEnabled: Bool = false
    ) {
        self.summaryEnabled = summaryEnabled
        self.researchEnabled = researchEnabled
        self.translationEnabled = translationEnabled
        self.neutralTitlesEnabled = neutralTitlesEnabled
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

public struct OpsAiJobEvent: Codable, Sendable {
    public var stage: String
    public var kind: String?
    public var id: String?
    public var feedUrl: String?
    public var reason: String?
    public var isoTime: String?
    public var manual: Bool?
    public var bulk: Bool?
}

public struct OpsQueuedAiJob: Codable, Sendable {
    public var kind: String
    public var id: String
    public var feedUrl: String
    public var manual: Bool
    public var bulk: Bool?
    public var enqueuedAtMs: Double
    public var ageMs: Double
}

public struct OpsAiJobsQueue: Codable, Sendable {
    public var size: Int
    public var inFlight: Int
    public var bulkQueued: Int?
    public var bulkInFlight: Int?
    public var deadLetters: Int
    public var countsByKind: [String: Int]
    public var pausedAll: Bool?
    public var pausedKinds: [String]?
    public var queuedJobs: [OpsQueuedAiJob]?
    public var inFlightKeys: [String]?
}

public struct OpsBackendHealth: Codable, Sendable {
    public var aiAvailable: Bool
    public var aiEnabled: Bool
    public var lastEventAt: String?
    public var lastSuccessAt: String?
    public var stalled: Bool
    public var failingFeeds: Int
    public var breakerFeeds: Int
}

public struct OpsAiJobsResponse: Codable, Sendable {
    public var ok: Bool
    public var newsAccessLocked: Bool
    public var queue: OpsAiJobsQueue
    public var events: [OpsAiJobEvent]
    public var health: OpsBackendHealth?
}

public struct OpsAiQueueControlResponse: Codable, Sendable {
    public var ok: Bool
    public var action: String
    public var kind: String
    public var affected: Int
    public var queued: Int?
    public var queue: OpsAiJobsQueue
}

public struct DatabaseBackup: Codable, Sendable {
    public var path: String
    public var filename: String
    public var sizeBytes: Int
    public var createdAt: String
    public var reason: String
}

public struct DatabaseBackupResponse: Codable, Sendable {
    public var ok: Bool
    public var backup: DatabaseBackup
}

public struct AiFeedProgress: Codable, Sendable, Identifiable {
    public var feedUrl: String
    public var label: String
    public var done: Int
    public var total: Int
    public var pending: Int
    public var blocked: Int
    public var totalRelevant: Int
    public var id: String { feedUrl }
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
    public var aiEnabled: Bool
    public var summaryEnabled: Bool
    public var translationEnabled: Bool
    public var neutralTitlesEnabled: Bool
    public var researchEnabled: Bool
    public var discordWebhookUrl: String?
    public var budget: String
    public var pollingEnabled: Bool
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
    /// Pending AI outputs aggregated per widget category id.
    public var pendingByCategory: [String: Int]
    /// Tracked topics the user configured (drives the Keywords widget header).
    public var keywords: [String]
    /// Stories that matched the tracked topics, powering the dedicated Keywords widget.
    public var keywordMatches: [WidgetStory]
    /// Recent AI monitor alerts shown in the app and summarized by widgets.
    public var monitorAlerts: [HistoryEntry]
    /// Total pending AI outputs across the filtered/keyword-matches story set.
    public var filteredPendingCount: Int
    /// Total pending AI outputs across the entire app queue.
    public var totalPendingCount: Int
    /// Desired local runtime state shared by the Mac app and widgets.
    public var runtimePower: RuntimePowerState

    public init(
        lastUpdated: Date = Date(),
        categories: [WidgetCategory] = [],
        activeCategoryID: Int? = nil,
        storiesByCategory: [String: [WidgetStory]] = [:],
        pendingByCategory: [String: Int] = [:],
        keywords: [String] = [],
        keywordMatches: [WidgetStory] = [],
        monitorAlerts: [HistoryEntry] = [],
        filteredPendingCount: Int = 0,
        totalPendingCount: Int = 0,
        runtimePower: RuntimePowerState = RuntimePowerState()
    ) {
        self.lastUpdated = lastUpdated
        self.categories = categories
        self.activeCategoryID = activeCategoryID
        self.storiesByCategory = storiesByCategory
        self.pendingByCategory = pendingByCategory
        self.keywords = keywords
        self.keywordMatches = keywordMatches
        self.monitorAlerts = monitorAlerts
        self.filteredPendingCount = filteredPendingCount
        self.totalPendingCount = totalPendingCount
        self.runtimePower = runtimePower
    }

    enum CodingKeys: String, CodingKey {
        case lastUpdated, categories, activeCategoryID, storiesByCategory, pendingByCategory, keywords, keywordMatches, monitorAlerts, filteredPendingCount, totalPendingCount, runtimePower
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        lastUpdated = try container.decodeIfPresent(Date.self, forKey: .lastUpdated) ?? Date()
        categories = try container.decodeIfPresent([WidgetCategory].self, forKey: .categories) ?? []
        activeCategoryID = try container.decodeIfPresent(Int.self, forKey: .activeCategoryID)
        storiesByCategory = try container.decodeIfPresent([String: [WidgetStory]].self, forKey: .storiesByCategory) ?? [:]
        pendingByCategory = try container.decodeIfPresent([String: Int].self, forKey: .pendingByCategory) ?? [:]
        // Tolerate older snapshots written before these fields existed.
        keywords = try container.decodeIfPresent([String].self, forKey: .keywords) ?? []
        keywordMatches = try container.decodeIfPresent([WidgetStory].self, forKey: .keywordMatches) ?? []
        monitorAlerts = try container.decodeIfPresent([HistoryEntry].self, forKey: .monitorAlerts) ?? []
        filteredPendingCount = try container.decodeIfPresent(Int.self, forKey: .filteredPendingCount) ?? 0
        totalPendingCount = try container.decodeIfPresent(Int.self, forKey: .totalPendingCount) ?? 0
        runtimePower = try container.decodeIfPresent(RuntimePowerState.self, forKey: .runtimePower) ?? RuntimePowerState()
    }
}

public struct RuntimePowerState: Codable, Equatable, Sendable {
    public var isPoweredOn: Bool
    public var autoPowerOffAt: Date?

    public init(isPoweredOn: Bool = true, autoPowerOffAt: Date? = nil) {
        self.isPoweredOn = isPoweredOn
        self.autoPowerOffAt = autoPowerOffAt
    }

    public func normalized(now: Date = Date()) -> RuntimePowerState {
        if let autoPowerOffAt, autoPowerOffAt <= now {
            return RuntimePowerState(isPoweredOn: false, autoPowerOffAt: nil)
        }
        return self
    }

    public var isEffectivelyPoweredOn: Bool {
        normalized().isPoweredOn
    }
}

public enum WidgetStoryAction: String, CaseIterable, Codable, Sendable {
    case summary
    case research
    case translation
    case neutralTitle = "neutral_title"
    case refresh
    case hide
}

public enum WidgetDeepLinkAction: String, Codable, Sendable {
    case open
    case summary
    case research
    case translation
    case neutralTitle = "neutral_title"
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
        case openNeutralTitle
        case openShare
        case hideStory
        case powerOn
        case powerOff
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
