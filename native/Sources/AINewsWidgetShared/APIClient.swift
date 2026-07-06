import Foundation

public enum APIClientError: LocalizedError {
    case invalidBaseURL
    case unauthorized
    case invalidResponse
    case notFound
    case server(message: String)

    public var errorDescription: String? {
        switch self {
        case .invalidBaseURL:
            return "The backend URL is invalid."
        case .unauthorized:
            return "You need to sign in again."
        case .invalidResponse:
            return "The backend returned an invalid response."
        case .notFound:
            return "The app reached a backend that does not expose the widget API."
        case .server(let message):
            return message
        }
    }
}

private struct ErrorEnvelope: Codable {
    var error: String
}

private struct AuthResponse: Codable {
    var token: String
    var user: UserAccount
}

private struct HealthResponse: Codable {
    var ok: Bool
}

public struct APIClient: Sendable {
    public var baseURL: URL
    public var token: String?

    public init(baseURLString: String, token: String? = nil) throws {
        guard let url = URL(string: baseURLString) else {
            throw APIClientError.invalidBaseURL
        }
        self.baseURL = url
        self.token = token
    }

    public func login(username: String, password: String) async throws -> UserSession {
        let body = ["username": username, "password": password]
        let response: AuthResponse = try await send(path: "/api/auth/login", method: "POST", body: body)
        return UserSession(token: response.token, user: response.user)
    }

    public func isBackendReachable() async -> Bool {
        do {
            let response: HealthResponse = try await send(path: "/api/health")
            return response.ok
        } catch {
            return false
        }
    }

    public func register(username: String, password: String) async throws -> UserSession {
        let body = ["username": username, "password": password]
        let response: AuthResponse = try await send(path: "/api/auth/register", method: "POST", body: body)
        return UserSession(token: response.token, user: response.user)
    }

    public func fetchBootstrap() async throws -> WidgetBootstrapResponse {
        try await send(path: "/api/widget/bootstrap")
    }

    public func fetchMaster() async throws -> WidgetMasterResponse {
        try await send(path: "/api/widget/master")
    }

    public func fetchRuntimeConfig() async throws -> RuntimeConfigResponse {
        try await send(path: "/api/runtime/config")
    }

    public func saveFeedSettings(_ feed: RuntimeFeed) async throws -> RuntimeFeed {
        struct Body: Codable {
            var feedUrl: String
            var summaryEnabled: Bool
            var translationEnabled: Bool
            var researchEnabled: Bool
            var discordWebhookUrl: String?
            var budget: String
            var intervalSec: Int
        }
        let response: RuntimeFeedMutationResponse = try await send(
            path: "/api/runtime/feed-settings",
            method: "PUT",
            body: Body(
                feedUrl: feed.url,
                summaryEnabled: feed.settings.summaryEnabled,
                translationEnabled: feed.settings.translationEnabled,
                researchEnabled: feed.settings.researchEnabled,
                discordWebhookUrl: feed.settings.discordWebhookUrl,
                budget: feed.settings.budget,
                intervalSec: feed.settings.intervalSec
            )
        )
        return response.feed
    }

    public func saveGlobalAiDefaults(_ defaults: GlobalAiDefaults) async throws {
        struct Body: Codable {
            var summaryEnabled: Bool
            var researchEnabled: Bool
            var translationEnabled: Bool
        }
        let _: RuntimeAiDefaultsResponse = try await send(
            path: "/api/runtime/ai-defaults",
            method: "PUT",
            body: Body(
                summaryEnabled: defaults.summaryEnabled,
                researchEnabled: defaults.researchEnabled,
                translationEnabled: defaults.translationEnabled
            )
        )
    }

    /// Set only the AI toggles for one feed, preserving its other settings (budget, interval).
    /// Used to apply category-level AI settings across every feed in a category.
    public func setFeedAiSettings(
        feedUrl: String,
        summaryEnabled: Bool,
        researchEnabled: Bool,
        translationEnabled: Bool
    ) async throws {
        struct Body: Codable {
            var feedUrl: String
            var summaryEnabled: Bool
            var researchEnabled: Bool
            var translationEnabled: Bool
        }
        let _: RuntimeFeedMutationResponse = try await send(
            path: "/api/runtime/feed-settings",
            method: "PUT",
            body: Body(
                feedUrl: feedUrl,
                summaryEnabled: summaryEnabled,
                researchEnabled: researchEnabled,
                translationEnabled: translationEnabled
            )
        )
    }

    /// Ask the backend to generate any missing AI outputs (summary/research/translation)
    /// for stories whose feeds have those actions enabled. Used on launch so enabled
    /// outputs get backfilled instead of only generating for newly fetched items.
    @discardableResult
    public func regenerateMissingAI(limit: Int = 200) async throws -> RegenerateResponse {
        struct Body: Codable { var kind: String; var missingOnly: Bool; var limit: Int }
        return try await send(
            path: "/api/maintenance/regenerate",
            method: "POST",
            body: Body(kind: "all", missingOnly: true, limit: limit)
        )
    }

    public func fetchPreferences() async throws -> (region: String, topics: [String]) {
        struct Response: Codable { var ok: Bool; var localRegion: String; var trackedTopics: [String] }
        let response: Response = try await send(path: "/api/preferences")
        return (response.localRegion, response.trackedTopics)
    }

    public func savePreferences(region: String, topics: [String]) async throws {
        struct Body: Codable { var localRegion: String; var trackedTopics: [String] }
        struct Response: Codable { var ok: Bool }
        let _: Response = try await send(path: "/api/preferences", method: "PUT", body: Body(localRegion: region, trackedTopics: topics))
    }

    public func fetchAiProgress() async throws -> [AiFeedProgress] {
        struct Response: Codable { var ok: Bool; var feeds: [AiFeedProgress] }
        let response: Response = try await send(path: "/api/ai-progress")
        return response.feeds
    }

    public func fetchKeywords() async throws -> [String] {
        struct Response: Codable { var ok: Bool; var keywords: [String] }
        let response: Response = try await send(path: "/api/keywords")
        return response.keywords
    }

    @discardableResult
    public func saveKeywords(_ keywords: [String]) async throws -> [String] {
        struct Body: Codable { var keywords: [String] }
        struct Response: Codable { var ok: Bool; var keywords: [String] }
        let response: Response = try await send(path: "/api/keywords", method: "PUT", body: Body(keywords: keywords))
        return response.keywords
    }

    public func fetchKeywordMatches(limit: Int = 30) async throws -> [WidgetStory] {
        struct Response: Codable { var ok: Bool; var stories: [WidgetStory] }
        let response: Response = try await send(path: "/api/widget/keyword-matches?limit=\(limit)")
        return response.stories
    }

    public func fetchAccountSettings() async throws -> AccountSettings {
        let response: AccountSettingsResponse = try await send(path: "/api/account/settings")
        return response.settings
    }

    public func saveAccountSettings(_ settings: AccountSettings) async throws {
        struct Body: Codable { var settings: AccountSettings }
        let _: BasicSuccessResponse = try await send(path: "/api/account/settings", method: "PUT", body: Body(settings: settings))
    }

    public func fetchProviderKeyStatus(provider: String) async throws -> Bool {
        let response: ProviderKeyStatusResponse = try await send(path: "/api/auth/provider-key/\(provider)")
        return response.hasKey
    }

    public func saveProviderKey(provider: String, apiKey: String) async throws {
        struct Body: Codable { var provider: String; var apiKey: String }
        let _: BasicSuccessResponse = try await send(path: "/api/auth/provider-key", method: "POST", body: Body(provider: provider, apiKey: apiKey))
    }

    public func fetchUsage() async throws -> AIUsageExport {
        let response: AIUsageExportResponse = try await send(path: "/api/ai-usage/export")
        return response.usage
    }

    public func fetchLibrary() async throws -> [FeatureRecord<SavedStoryPayload>] {
        let response: FeatureListResponse<SavedStoryPayload> = try await send(path: "/api/library")
        return response.items
    }

    public func saveStory(_ payload: SavedStoryPayload) async throws -> FeatureRecord<SavedStoryPayload> {
        let response: FeatureMutationResponse<SavedStoryPayload> = try await send(path: "/api/library", method: "POST", body: payload)
        guard let item = response.item else { throw APIClientError.invalidResponse }
        return item
    }

    public func updateSavedStory(id: Int, payload: SavedStoryPayload) async throws -> FeatureRecord<SavedStoryPayload> {
        let response: FeatureMutationResponse<SavedStoryPayload> = try await send(path: "/api/library/\(id)", method: "PUT", body: payload)
        guard let item = response.item else { throw APIClientError.invalidResponse }
        return item
    }

    public func deleteSavedStory(id: Int) async throws {
        let _: BasicSuccessResponse = try await send(path: "/api/library/\(id)", method: "DELETE")
    }

    public func fetchHistory(feedURL: String? = nil) async throws -> HistoryResponse {
        var path = "/api/history"
        if let feedURL, !feedURL.isEmpty {
            path += "?feedUrl=\(feedURL.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? feedURL)"
        }
        return try await send(path: path)
    }

    public func fetchSources() async throws -> [SourceProfile] {
        let response: SourcesResponse = try await send(path: "/api/sources")
        return response.items
    }

    public func previewOpml(_ opml: String) async throws -> [OpmlFeed] {
        struct Body: Codable { var opml: String }
        let response: OpmlPreviewResponse = try await send(path: "/api/opml/import-preview", method: "POST", body: Body(opml: opml))
        return response.feeds
    }

    public func importOpml(_ opml: String) async throws -> OpmlImportResponse {
        struct Body: Codable { var opml: String }
        return try await send(path: "/api/opml/import", method: "POST", body: Body(opml: opml))
    }

    public func exportOpml() async throws -> String {
        try await sendText(path: "/api/opml/export")
    }

    public func fetchRules() async throws -> [FeatureRecord<AlertRulePayload>] {
        let response: FeatureListResponse<AlertRulePayload> = try await send(path: "/api/rules")
        return response.items
    }

    public func createRule(_ payload: AlertRulePayload) async throws -> FeatureRecord<AlertRulePayload> {
        let response: FeatureMutationResponse<AlertRulePayload> = try await send(path: "/api/rules", method: "POST", body: payload)
        guard let item = response.item else { throw APIClientError.invalidResponse }
        return item
    }

    public func updateRule(id: Int, payload: AlertRulePayload) async throws -> FeatureRecord<AlertRulePayload> {
        let response: FeatureMutationResponse<AlertRulePayload> = try await send(path: "/api/rules/\(id)", method: "PUT", body: payload)
        guard let item = response.item else { throw APIClientError.invalidResponse }
        return item
    }

    public func runRule(id: Int) async throws {
        let _: BasicSuccessResponse = try await send(path: "/api/rules/\(id)/run", method: "POST")
    }

    public func fetchSchedules() async throws -> [FeatureRecord<SchedulePayload>] {
        let response: FeatureListResponse<SchedulePayload> = try await send(path: "/api/schedules")
        return response.items
    }

    public func createSchedule(_ payload: SchedulePayload) async throws -> FeatureRecord<SchedulePayload> {
        let response: FeatureMutationResponse<SchedulePayload> = try await send(path: "/api/schedules", method: "POST", body: payload)
        guard let item = response.item else { throw APIClientError.invalidResponse }
        return item
    }

    public func updateSchedule(id: Int, payload: SchedulePayload) async throws -> FeatureRecord<SchedulePayload> {
        let response: FeatureMutationResponse<SchedulePayload> = try await send(path: "/api/schedules/\(id)", method: "PUT", body: payload)
        guard let item = response.item else { throw APIClientError.invalidResponse }
        return item
    }

    public func runSchedule(id: Int) async throws {
        let _: BasicSuccessResponse = try await send(path: "/api/schedules/\(id)/run", method: "POST")
    }

    public func fetchDigests() async throws -> [FeatureRecord<DigestPayload>] {
        let response: FeatureListResponse<DigestPayload> = try await send(path: "/api/digests")
        return response.items
    }

    public func createDigest(_ payload: DigestPayload) async throws -> FeatureRecord<DigestPayload> {
        let response: FeatureMutationResponse<DigestPayload> = try await send(path: "/api/digests", method: "POST", body: payload)
        guard let item = response.item else { throw APIClientError.invalidResponse }
        return item
    }

    public func createShare(kind: String, title: String, payload: [String: JSONValue]) async throws -> ShareCreateResponse {
        struct Body: Codable {
            var kind: String
            var title: String
            var payload: [String: JSONValue]
        }
        return try await send(path: "/api/share", method: "POST", body: Body(kind: kind, title: title, payload: payload))
    }

    public func resetUsage() async throws -> AIUsageExport {
        let response: AIUsageExportResponse = try await send(path: "/api/ai-usage/reset", method: "POST")
        return response.usage
    }

    public func fetchStories(categoryID: Int, limit: Int? = nil) async throws -> CategoryStoriesResponse {
        var path = "/api/widget/categories/\(categoryID)/stories"
        if let limit {
            path += "?limit=\(limit)"
        }
        return try await send(path: path)
    }

    public func createCategory(_ category: WidgetCategory) async throws -> WidgetCategory {
        let response: FeatureItemResponse = try await send(
            path: "/api/collections",
            method: "POST",
            body: categoryPayload(category)
        )
        guard let item = response.item else { throw APIClientError.invalidResponse }
        return item.category
    }

    public func updateCategory(_ category: WidgetCategory) async throws -> WidgetCategory {
        let response: FeatureItemResponse = try await send(
            path: "/api/collections/\(category.id)",
            method: "PUT",
            body: categoryPayload(category)
        )
        guard let item = response.item else { throw APIClientError.invalidResponse }
        return item.category
    }

    public func archiveCategory(categoryID: Int) async throws {
        let _: BasicSuccessResponse = try await send(path: "/api/collections/\(categoryID)", method: "DELETE")
    }

    public func setCategoryVisibility(categoryID: Int, hidden: Bool) async throws -> WidgetCategory {
        struct Body: Codable { var hidden: Bool }
        let response: WidgetCategoryMutationResponse = try await send(path: "/api/widget/categories/\(categoryID)/visibility", method: "POST", body: Body(hidden: hidden))
        guard let item = response.item else { throw APIClientError.invalidResponse }
        return item
    }

    public func expandCategory(categoryID: Int) async throws -> WidgetCategory {
        let response: WidgetCategoryMutationResponse = try await send(path: "/api/widget/categories/\(categoryID)/expand", method: "POST")
        guard let item = response.item else { throw APIClientError.invalidResponse }
        return item
    }

    public func resetCategory(categoryID: Int) async throws -> WidgetCategory {
        let response: WidgetCategoryMutationResponse = try await send(path: "/api/widget/categories/\(categoryID)/reset", method: "POST")
        guard let item = response.item else { throw APIClientError.invalidResponse }
        return item
    }

    public func pinStory(categoryID: Int, story: WidgetStory?, pinned: Bool) async throws -> WidgetCategory {
        struct Body: Codable {
            var itemId: String
            var feedUrl: String
            var pinned: Bool
        }
        let response: WidgetCategoryMutationResponse = try await send(
            path: "/api/widget/categories/\(categoryID)/pin",
            method: "POST",
            body: Body(itemId: story?.id ?? "", feedUrl: story?.feedUrl ?? "", pinned: pinned)
        )
        guard let item = response.item else { throw APIClientError.invalidResponse }
        return item
    }

    public func triggerStoryAction(_ action: WidgetStoryAction, story: WidgetStory) async throws {
        struct Body: Codable { var action: String; var itemId: String; var feedUrl: String }
        let _: StoryActionResponse = try await send(
            path: "/api/widget/stories/action",
            method: "POST",
            body: Body(action: action.rawValue, itemId: story.id, feedUrl: story.feedUrl)
        )
    }

    public func refreshCategory(_ category: WidgetCategory) async throws {
        struct Body: Codable { var action: String; var itemId: String; var feedUrl: String }
        for feedURL in category.feedUrls {
            let _: StoryActionResponse = try await send(
                path: "/api/widget/stories/action",
                method: "POST",
                body: Body(action: WidgetStoryAction.refresh.rawValue, itemId: "category-refresh", feedUrl: feedURL)
            )
        }
    }

    private func send<Response: Decodable, Body: Encodable>(
        path: String,
        method: String = "GET",
        body: Body
    ) async throws -> Response {
        let data = try JSONEncoder().encode(body)
        return try await send(path: path, method: method, bodyData: data)
    }

    private func send<Response: Decodable>(
        path: String,
        method: String = "GET"
    ) async throws -> Response {
        try await send(path: path, method: method, bodyData: nil)
    }

    private func send<Response: Decodable>(
        path: String,
        method: String,
        bodyData: Data?
    ) async throws -> Response {
        var request = URLRequest(url: makeURL(path: path))
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let token, !token.isEmpty {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        if let bodyData {
            request.httpBody = bodyData
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw APIClientError.invalidResponse
        }
        if http.statusCode == 401 {
            let errorEnvelope = try? JSONDecoder().decode(ErrorEnvelope.self, from: data)
            let message = (errorEnvelope?.error ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if message.isEmpty || message.caseInsensitiveCompare("Unauthorized") == .orderedSame {
                throw APIClientError.unauthorized
            }
            throw APIClientError.server(message: message)
        }
        if http.statusCode == 404 {
            throw APIClientError.notFound
        }
        if !(200...299).contains(http.statusCode) {
            let errorEnvelope = try? JSONDecoder().decode(ErrorEnvelope.self, from: data)
            throw APIClientError.server(message: errorEnvelope?.error ?? "Request failed with status \(http.statusCode).")
        }
        do {
            return try JSONDecoder().decode(Response.self, from: data)
        } catch {
            throw APIClientError.server(message: "Failed to decode backend response: \(error.localizedDescription)")
        }
    }

    private func sendText(
        path: String,
        method: String = "GET"
    ) async throws -> String {
        var request = URLRequest(url: makeURL(path: path))
        request.httpMethod = method
        if let token, !token.isEmpty {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw APIClientError.invalidResponse
        }
        if http.statusCode == 401 {
            throw APIClientError.unauthorized
        }
        if http.statusCode == 404 {
            throw APIClientError.notFound
        }
        if !(200...299).contains(http.statusCode) {
            let errorEnvelope = try? JSONDecoder().decode(ErrorEnvelope.self, from: data)
            throw APIClientError.server(message: errorEnvelope?.error ?? "Request failed with status \(http.statusCode).")
        }
        guard let text = String(data: data, encoding: .utf8) else {
            throw APIClientError.invalidResponse
        }
        return text
    }

    private func makeURL(path: String) -> URL {
        if path.hasPrefix("http://") || path.hasPrefix("https://") {
            return URL(string: path)!
        }

        let trimmedPath = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let components = trimmedPath.split(separator: "?", maxSplits: 1, omittingEmptySubsequences: false)
        let relativePath = String(components.first ?? "")
        let query = components.count > 1 ? String(components[1]) : nil

        var url = baseURL.appendingPathComponent(relativePath)
        if let query, !query.isEmpty {
            var urlComponents = URLComponents(url: url, resolvingAgainstBaseURL: false)
            urlComponents?.percentEncodedQuery = query
            if let resolvedURL = urlComponents?.url {
                url = resolvedURL
            }
        }
        return url
    }

    private func categoryPayload(_ category: WidgetCategory) -> WidgetCategoryPayload {
        WidgetCategoryPayload(
            name: category.name,
            description: category.description,
            feedUrls: category.feedUrls,
            storyIds: category.storyIds,
            tags: category.tags,
            hidden: category.hidden,
            sortOrder: category.sortOrder,
            preferredCount: category.preferredCount,
            expandedCount: category.expandedCount,
            activeCount: category.activeCount,
            pinnedStoryId: category.pinnedStoryId,
            pinnedFeedUrl: category.pinnedFeedUrl
        )
    }
}
