import Foundation

public enum APIClientError: LocalizedError {
    case invalidBaseURL
    case unauthorized
    case invalidResponse
    case server(message: String)

    public var errorDescription: String? {
        switch self {
        case .invalidBaseURL:
            return "The backend URL is invalid."
        case .unauthorized:
            return "You need to sign in again."
        case .invalidResponse:
            return "The backend returned an invalid response."
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
