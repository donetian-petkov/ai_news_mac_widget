import Foundation
import SwiftUI

@MainActor
public final class WidgetAppState: ObservableObject {
    @Published public var session: UserSession?
    @Published public var categories: [WidgetCategory] = []
    @Published public var selectedCategoryID: Int?
    @Published public var stories: [WidgetStory] = []
    @Published public var usage: AIUsageExport?
    @Published public var runtimeConfig: RuntimeConfigResponse?
    @Published public var globalAiDefaults = GlobalAiDefaults()
    @Published public var accountSettings = AccountSettings()
    @Published public var isBusy = false
    @Published public var errorMessage: String?
    @Published public var statusMessage: String?
    @Published public var providerKeyDraft = ""
    @Published public var providerKeyStatus: [String: Bool] = [:]
    @Published public var scrollToStoryID: String?
    @Published public var showingSettings = false
    @Published public var showingWidgetHelp = false
    @Published public var showingWorkspace = false
    @Published public var exportedUsageURL: URL?

    private let sessionStore: SessionStore
    private let snapshotStore: SnapshotStore
    private var isProcessingCommands = false

    public init(
        sessionStore: SessionStore? = nil,
        snapshotStore: SnapshotStore? = nil
    ) {
        self.sessionStore = sessionStore ?? .shared
        self.snapshotStore = snapshotStore ?? .shared
        self.session = self.sessionStore.session
        let snapshot = self.snapshotStore.loadSnapshot()
        self.categories = snapshot.categories
        self.selectedCategoryID = snapshot.activeCategoryID ?? snapshot.categories.first?.id
        self.stories = snapshot.activeCategoryID.flatMap { snapshot.storiesByCategory[String($0)] } ?? []
    }

    public var backendURLString: String {
        get { sessionStore.baseURLString }
        set { sessionStore.baseURLString = newValue }
    }

    public func refreshDiscoveredBackendURL() {
        sessionStore.synchronizeDiscoveredBaseURL()
    }

    public var selectedCategory: WidgetCategory? {
        categories.first(where: { $0.id == selectedCategoryID })
    }

    public func bootstrapIfNeeded() async {
        refreshDiscoveredBackendURL()
        await waitForBackendReady()
        guard session != nil else { return }
        // Always refresh categories from the backend on launch. The cached snapshot gives
        // an instant first paint, but its category IDs can be stale relative to the backend
        // DB (which is re-seeded on install), which would make every stories request 404.
        // reloadEverything fetches fresh categories and re-validates the selected one.
        await reloadEverything(selectFirstCategory: selectedCategoryID == nil, suppressUnauthorizedAlert: true)
        await processPendingCommands()
    }

    public func signIn(username: String, password: String, register: Bool) async {
        await runBusy("Signing in...") {
            self.refreshDiscoveredBackendURL()
            await self.waitForBackendReady()
            let api = try self.makeAPIClient()
            let session = try await (register ? api.register(username: username, password: password) : api.login(username: username, password: password))
            self.sessionStore.save(session: session)
            self.session = session
            await self.reloadEverything(selectFirstCategory: true, suppressUnauthorizedAlert: true)
        }
    }

    public func signOut() {
        sessionStore.clear()
        session = nil
        categories = []
        stories = []
        usage = nil
        runtimeConfig = nil
        selectedCategoryID = nil
        errorMessage = nil
        statusMessage = nil
        try? snapshotStore.saveSnapshot(WidgetSnapshot())
    }

    public func reloadEverything(selectFirstCategory: Bool = false, suppressUnauthorizedAlert: Bool = false) async {
        await runBusy("Refreshing categories...", suppressUnauthorizedAlert: suppressUnauthorizedAlert) {
            self.refreshDiscoveredBackendURL()
            var api = try self.makeAPIClient()
            let bootstrap: WidgetBootstrapResponse
            do {
                bootstrap = try await api.fetchBootstrap()
            } catch APIClientError.notFound {
                if let runtimeURL = BackendDiscovery.runtimeBackendURLString() {
                    self.backendURLString = runtimeURL
                    api = try self.makeAPIClient()
                    bootstrap = try await api.fetchBootstrap()
                } else {
                    throw APIClientError.server(message: "Widget backend not found at \(self.backendURLString). Start the local backend or reopen the app so it can relaunch it.")
                }
            }
            self.categories = bootstrap.categories.sorted(by: { lhs, rhs in
                lhs.sortOrder == rhs.sortOrder ? lhs.name < rhs.name : lhs.sortOrder < rhs.sortOrder
            })
            self.usage = bootstrap.usage
            if selectFirstCategory || self.selectedCategoryID == nil || !self.categories.contains(where: { $0.id == self.selectedCategoryID }) {
                self.selectedCategoryID = self.categories.first(where: { !$0.hidden })?.id ?? self.categories.first?.id
            }
            try await self.refreshAllCategorySnapshots(using: api)
            await self.loadRuntimeContext(suppressUnauthorizedAlert: suppressUnauthorizedAlert)
            await self.loadStoriesForSelectedCategory(suppressUnauthorizedAlert: suppressUnauthorizedAlert)
            self.statusMessage = "Updated \(self.categories.count) categories."
        }
    }

    public func loadRuntimeContext(suppressUnauthorizedAlert: Bool = false) async {
        do {
            refreshDiscoveredBackendURL()
            let api = try makeAPIClient()
            runtimeConfig = try await api.fetchRuntimeConfig()
            if let defaults = runtimeConfig?.aiDefaults {
                globalAiDefaults = defaults
            }
            accountSettings = try await api.fetchAccountSettings()
            if let provider = runtimeConfig?.aiProvider {
                providerKeyStatus[provider] = try await api.fetchProviderKeyStatus(provider: provider)
            }
        } catch {
            handleAsyncError(error, suppressUnauthorizedAlert: suppressUnauthorizedAlert)
        }
    }

    public func selectCategory(_ category: WidgetCategory) async {
        selectedCategoryID = category.id
        await loadStoriesForSelectedCategory()
    }

    public func loadStoriesForSelectedCategory(limit: Int? = nil, suppressUnauthorizedAlert: Bool = false) async {
        guard let category = selectedCategory else { return }
        do {
            refreshDiscoveredBackendURL()
            let api = try makeAPIClient()
            let response = try await api.fetchStories(categoryID: category.id, limit: limit ?? category.activeCount)
            stories = response.stories
            updateCategory(response.category)
            saveSnapshot()
        } catch {
            handleAsyncError(error, suppressUnauthorizedAlert: suppressUnauthorizedAlert)
        }
    }

    public func expandSelectedCategory() async {
        guard let category = selectedCategory else { return }
        await runBusy("Showing more stories...") {
            let api = try self.makeAPIClient()
            let updated = try await api.expandCategory(categoryID: category.id)
            self.updateCategory(updated)
            try await Task.sleep(nanoseconds: 150_000_000)
            await self.loadStoriesForSelectedCategory(limit: updated.activeCount)
        }
    }

    public func resetSelectedCategory() async {
        guard let category = selectedCategory else { return }
        await runBusy("Resetting category...") {
            let api = try self.makeAPIClient()
            let updated = try await api.resetCategory(categoryID: category.id)
            self.updateCategory(updated)
            await self.loadStoriesForSelectedCategory(limit: updated.activeCount)
            self.scrollToTop()
        }
    }

    public func toggleVisibility(for category: WidgetCategory) async {
        await runBusy(category.hidden ? "Showing category..." : "Hiding category...") {
            let api = try self.makeAPIClient()
            let updated = try await api.setCategoryVisibility(categoryID: category.id, hidden: !category.hidden)
            self.updateCategory(updated)
            if updated.hidden, self.selectedCategoryID == updated.id {
                self.selectedCategoryID = self.categories.first(where: { !$0.hidden && $0.id != updated.id })?.id
                await self.loadStoriesForSelectedCategory()
            }
        }
    }

    public func togglePin(for story: WidgetStory) async {
        guard let category = selectedCategory else { return }
        let shouldPin = !category.isPinned(story)
        await runBusy(shouldPin ? "Pinning story..." : "Unpinning story...") {
            let api = try self.makeAPIClient()
            let updated = try await api.pinStory(categoryID: category.id, story: story, pinned: shouldPin)
            self.updateCategory(updated)
            await self.loadStoriesForSelectedCategory(limit: updated.activeCount)
        }
    }

    public func createCategory(
        name: String,
        description: String,
        feedUrls: [String]
    ) async {
        await runBusy("Creating category...") {
            let api = try self.makeAPIClient()
            let nextSortOrder = (self.categories.map(\.sortOrder).max() ?? -1) + 1
            let category = WidgetCategory(
                id: 0,
                name: name,
                description: description,
                feedUrls: feedUrls,
                sortOrder: nextSortOrder
            )
            let created = try await api.createCategory(category)
            self.updateCategory(created)
            self.selectedCategoryID = created.id
            await self.loadStoriesForSelectedCategory(limit: created.activeCount)
            self.statusMessage = "Created \(created.name)."
        }
    }

    public func saveCategory(_ category: WidgetCategory) async {
        await runBusy("Saving category...") {
            let api = try self.makeAPIClient()
            let updated = try await api.updateCategory(category)
            self.updateCategory(updated)
            if self.selectedCategoryID == updated.id {
                await self.loadStoriesForSelectedCategory(limit: updated.activeCount)
            }
            self.statusMessage = "Saved \(updated.name)."
        }
    }

    public func archiveCategory(_ category: WidgetCategory) async {
        await runBusy("Removing category...") {
            let api = try self.makeAPIClient()
            try await api.archiveCategory(categoryID: category.id)
            self.categories.removeAll { $0.id == category.id }
            if self.selectedCategoryID == category.id {
                self.selectedCategoryID = self.categories.first(where: { !$0.hidden })?.id ?? self.categories.first?.id
                await self.loadStoriesForSelectedCategory(suppressUnauthorizedAlert: true)
            }
            self.saveSnapshot()
            self.statusMessage = "Removed \(category.name)."
        }
    }

    public func moveCategory(_ category: WidgetCategory, direction: Int) async {
        let sorted = categories.sorted {
            $0.sortOrder == $1.sortOrder ? $0.name < $1.name : $0.sortOrder < $1.sortOrder
        }
        guard let index = sorted.firstIndex(where: { $0.id == category.id }) else { return }
        let targetIndex = index + direction
        guard sorted.indices.contains(targetIndex) else { return }

        await runBusy("Reordering category...") {
            let api = try self.makeAPIClient()
            var current = sorted[index]
            var other = sorted[targetIndex]
            let currentOrder = current.sortOrder
            current.sortOrder = other.sortOrder
            other.sortOrder = currentOrder
            let updatedCurrent = try await api.updateCategory(current)
            let updatedOther = try await api.updateCategory(other)
            self.updateCategory(updatedCurrent)
            self.updateCategory(updatedOther)
            self.statusMessage = "Reordered categories."
        }
    }

    public func setAllCategoryVisibility(hidden: Bool) async {
        let targets = categories.filter { $0.hidden != hidden }
        guard !targets.isEmpty else { return }
        await runBusy(hidden ? "Hiding categories..." : "Showing categories...") {
            let api = try self.makeAPIClient()
            var updatedCategories = self.categories
            for category in targets {
                let updated = try await api.setCategoryVisibility(categoryID: category.id, hidden: hidden)
                if let index = updatedCategories.firstIndex(where: { $0.id == updated.id }) {
                    updatedCategories[index] = updated
                }
            }
            self.categories = updatedCategories.sorted {
                $0.sortOrder == $1.sortOrder ? $0.name < $1.name : $0.sortOrder < $1.sortOrder
            }
            if hidden, let selected = self.selectedCategory, selected.hidden {
                self.selectedCategoryID = self.categories.first(where: { !$0.hidden })?.id ?? self.categories.first?.id
                await self.loadStoriesForSelectedCategory(suppressUnauthorizedAlert: true)
            }
            self.saveSnapshot()
            self.statusMessage = hidden ? "All categories hidden from widgets." : "All categories visible in widgets."
        }
    }

    public func setAllCategoryCounts(expanded: Bool) async {
        let targets = categories.filter { expanded ? $0.activeCount != $0.expandedCount : $0.activeCount != $0.preferredCount }
        guard !targets.isEmpty else { return }
        await runBusy(expanded ? "Expanding categories..." : "Resetting categories...") {
            let api = try self.makeAPIClient()
            var updatedCategories = self.categories
            for category in targets {
                let updated = try await (expanded
                    ? api.expandCategory(categoryID: category.id)
                    : api.resetCategory(categoryID: category.id))
                if let index = updatedCategories.firstIndex(where: { $0.id == updated.id }) {
                    updatedCategories[index] = updated
                }
            }
            self.categories = updatedCategories.sorted {
                $0.sortOrder == $1.sortOrder ? $0.name < $1.name : $0.sortOrder < $1.sortOrder
            }
            if let selected = self.selectedCategory {
                await self.loadStoriesForSelectedCategory(limit: selected.activeCount)
            }
            self.saveSnapshot()
            self.statusMessage = expanded ? "Expanded all widget categories to 10 stories." : "Reset all widget categories to 5 stories."
        }
    }

    public func refreshVisibleCategories() async {
        let targets = categories.filter { !$0.hidden }
        guard !targets.isEmpty else { return }
        await runBusy("Refreshing visible categories...") {
            let api = try self.makeAPIClient()
            for category in targets {
                try await api.refreshCategory(category)
            }
            self.statusMessage = "Refresh requested for \(targets.count) visible categories."
        }
    }

    public func triggerStoryAction(_ action: WidgetStoryAction, story: WidgetStory) async {
        await triggerStoryAction(action, story: story, recordCommand: true)
    }

    public func saveStory(_ story: WidgetStory) async {
        await runBusy("Saving story...") {
            let api = try self.makeAPIClient()
            _ = try await api.saveStory(SavedStoryPayload(
                itemId: story.id,
                feedUrl: story.feedUrl,
                title: story.title,
                link: story.link,
                source: story.source,
                coverUrl: nil,
                tags: [],
                note: "",
                read: false,
                archived: false
            ))
            self.statusMessage = "Saved \(story.title)."
        }
    }

    public func authorizedAPIClient() throws -> APIClient {
        try makeAPIClient()
    }

    public func triggerStoryAction(_ action: WidgetStoryAction, story: WidgetStory, recordCommand: Bool) async {
        await runBusy("Sending \(action.rawValue) request...") {
            let api = try self.makeAPIClient()
            try await api.triggerStoryAction(action, story: story)
            self.statusMessage = "\(action.rawValue.capitalized) queued for \(story.title)."
            if recordCommand {
                try? self.snapshotStore.appendCommand(
                    WidgetCommand(
                        kind: {
                            switch action {
                            case .summary: return .openSummary
                            case .research: return .openResearch
                            case .translation: return .openTranslation
                            case .refresh: return .refreshCategory
                            }
                        }(),
                        categoryID: self.selectedCategoryID,
                        storyID: story.id,
                        feedURL: story.feedUrl
                    )
                )
            }
        }
    }

    public func refreshSelectedCategory() async {
        await refreshSelectedCategory(recordCommand: true)
    }

    public func refreshSelectedCategory(recordCommand: Bool) async {
        guard let category = selectedCategory else { return }
        await runBusy("Refreshing feeds...") {
            let api = try self.makeAPIClient()
            try await api.refreshCategory(category)
            self.statusMessage = "Refresh requested for \(category.name)."
            if recordCommand {
                try? self.snapshotStore.appendCommand(WidgetCommand(kind: .refreshCategory, categoryID: category.id))
            }
        }
    }

    public func refreshUsage() async {
        do {
            refreshDiscoveredBackendURL()
            let api = try makeAPIClient()
            usage = try await api.fetchUsage()
        } catch {
            handleAsyncError(error, suppressUnauthorizedAlert: false)
        }
    }

    public func resetUsage() async {
        await runBusy("Resetting AI usage...") {
            let api = try self.makeAPIClient()
            self.usage = try await api.resetUsage()
            self.statusMessage = "AI usage counters reset."
        }
    }

    public func exportUsageJSON() async {
        do {
            if usage == nil {
                refreshDiscoveredBackendURL()
                let api = try makeAPIClient()
                usage = try await api.fetchUsage()
            }
            guard let usage else { return }
            let data = try JSONEncoder.pretty.encode(usage)
            let url = try writeUsageExport(data: data, fileExtension: "json")
            exportedUsageURL = url
            statusMessage = "Exported AI usage JSON."
        } catch {
            handleAsyncError(error, suppressUnauthorizedAlert: false)
        }
    }

    public func exportUsageCSV() async {
        do {
            if usage == nil {
                refreshDiscoveredBackendURL()
                let api = try makeAPIClient()
                usage = try await api.fetchUsage()
            }
            guard let usage else { return }
            let csv = usageCSV(usage)
            guard let data = csv.data(using: .utf8) else {
                throw CocoaError(.fileWriteUnknown)
            }
            let url = try writeUsageExport(data: data, fileExtension: "csv")
            exportedUsageURL = url
            statusMessage = "Exported AI usage CSV."
        } catch {
            handleAsyncError(error, suppressUnauthorizedAlert: false)
        }
    }

    public func saveProviderKey() async {
        guard let provider = runtimeConfig?.aiProvider, !providerKeyDraft.isEmpty else { return }
        await runBusy("Saving provider key...") {
            let api = try self.makeAPIClient()
            try await api.saveProviderKey(provider: provider, apiKey: self.providerKeyDraft)
            self.providerKeyStatus[provider] = true
            self.providerKeyDraft = ""
            self.statusMessage = "Saved API key for \(provider.uppercased())."
        }
    }

    public func saveSettings() async {
        await runBusy("Saving AI settings...") {
            let api = try self.makeAPIClient()
            try await api.saveAccountSettings(self.accountSettings)
            self.statusMessage = "Saved AI settings."
        }
    }

    public func saveFeedSettings(_ feed: RuntimeFeed) async {
        await runBusy("Saving feed settings...") {
            let api = try self.makeAPIClient()
            let updatedFeed = try await api.saveFeedSettings(feed)
            self.updateRuntimeFeed(updatedFeed)
            self.statusMessage = "Saved settings for \(updatedFeed.label)."
        }
    }

    public func saveGlobalAiDefaults() async {
        await runBusy("Saving global AI settings...") {
            let api = try self.makeAPIClient()
            try await api.saveGlobalAiDefaults(self.globalAiDefaults)
            await self.loadRuntimeContext()
            self.statusMessage = "Applied global AI settings to every feed."
        }
    }

    /// Apply one set of AI toggles to every feed in a category (a per-category override
    /// implemented as feed-level overrides, since the AI pipeline is per-feed).
    public func applyAiSettings(to category: WidgetCategory, settings: GlobalAiDefaults) async {
        let feedUrls = category.feedUrls.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        guard !feedUrls.isEmpty else {
            errorMessage = "This category has no feeds to update."
            return
        }
        await runBusy("Applying AI settings to \(category.name)...") {
            let api = try self.makeAPIClient()
            for feedUrl in feedUrls {
                try await api.setFeedAiSettings(
                    feedUrl: feedUrl,
                    summaryEnabled: settings.summaryEnabled,
                    researchEnabled: settings.researchEnabled,
                    translationEnabled: settings.translationEnabled
                )
            }
            await self.loadRuntimeContext()
            self.statusMessage = "Applied AI settings to \(feedUrls.count) feed\(feedUrls.count == 1 ? "" : "s") in \(category.name)."
        }
    }

    public func scrollToTop() {
        scrollToStoryID = stories.first?.id
    }

    public func startCommandLoop() async {
        while !Task.isCancelled {
            if session != nil {
                await processPendingCommands()
            }
            try? await Task.sleep(nanoseconds: 2_000_000_000)
        }
    }

    public func handleIncomingURL(_ url: URL) async {
        guard url.scheme == "ainewswidget", url.host == "story" else { return }
        guard session != nil else { return }
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return }

        let categoryID = components.queryItems?.first(where: { $0.name == "category" })?.value.flatMap(Int.init)
        let storyID = components.queryItems?.first(where: { $0.name == "id" })?.value
        let feedURL = components.queryItems?.first(where: { $0.name == "feed" })?.value
        let action = components.queryItems?.first(where: { $0.name == "action" })?.value
            .flatMap(WidgetDeepLinkAction.init(rawValue:))
            ?? .open

        if let categoryID, let category = categories.first(where: { $0.id == categoryID }) {
            selectedCategoryID = category.id
            await loadStoriesForSelectedCategory(limit: category.activeCount, suppressUnauthorizedAlert: true)
        }

        guard
            let storyID,
            let feedURL,
            let story = stories.first(where: { $0.id == storyID && $0.feedUrl == feedURL })
        else {
            return
        }

        scrollToStoryID = story.id

        switch action {
        case .open:
            break
        case .summary:
            await triggerStoryAction(.summary, story: story, recordCommand: false)
        case .research:
            await triggerStoryAction(.research, story: story, recordCommand: false)
        case .translation:
            await triggerStoryAction(.translation, story: story, recordCommand: false)
        }
    }

    private func updateCategory(_ category: WidgetCategory) {
        if let index = categories.firstIndex(where: { $0.id == category.id }) {
            categories[index] = category
        } else {
            categories.append(category)
        }
        categories.sort { lhs, rhs in
            lhs.sortOrder == rhs.sortOrder ? lhs.name < rhs.name : lhs.sortOrder < rhs.sortOrder
        }
        saveSnapshot()
    }

    private func saveSnapshot() {
        var snapshot = snapshotStore.loadSnapshot()
        snapshot.lastUpdated = Date()
        snapshot.categories = categories
        snapshot.activeCategoryID = selectedCategoryID
        if let selectedCategoryID {
            snapshot.storiesByCategory[String(selectedCategoryID)] = stories
        }
        try? snapshotStore.saveSnapshot(snapshot)
    }

    private func refreshAllCategorySnapshots(using api: APIClient) async throws {
        let master = try await api.fetchMaster()
        var snapshot = snapshotStore.loadSnapshot()
        snapshot.lastUpdated = Date()
        snapshot.categories = master.categories.map(\.category)
        for category in master.categories {
            snapshot.storiesByCategory[String(category.id)] = category.stories
        }
        if let selectedCategoryID {
            snapshot.activeCategoryID = selectedCategoryID
            if let selectedStories = snapshot.storiesByCategory[String(selectedCategoryID)] {
                stories = selectedStories
            }
        }
        try snapshotStore.saveSnapshot(snapshot)
    }

    private func processPendingCommands() async {
        guard !isProcessingCommands else { return }
        let commands = snapshotStore.loadCommands()
        guard !commands.isEmpty else { return }

        isProcessingCommands = true
        defer { isProcessingCommands = false }
        try? snapshotStore.clearCommands()

        for command in commands {
            await execute(command)
        }
    }

    private func execute(_ command: WidgetCommand) async {
        if let categoryID = command.categoryID,
           let category = categories.first(where: { $0.id == categoryID }) {
            selectedCategoryID = category.id
            await loadStoriesForSelectedCategory(limit: category.activeCount, suppressUnauthorizedAlert: true)
        }

        switch command.kind {
        case .refreshCategory:
            await refreshSelectedCategory(recordCommand: false)
        case .pinStory:
            guard let story = story(for: command) else { return }
            await togglePin(for: story)
        case .toggleCategoryVisibility:
            guard let category = selectedCategory else { return }
            await toggleVisibility(for: category)
        case .expandCategory:
            await expandSelectedCategory()
        case .resetCategory:
            await resetSelectedCategory()
        case .openSummary:
            guard let story = story(for: command) else { return }
            await triggerStoryAction(.summary, story: story, recordCommand: false)
        case .openResearch:
            guard let story = story(for: command) else { return }
            await triggerStoryAction(.research, story: story, recordCommand: false)
        case .openTranslation:
            guard let story = story(for: command) else { return }
            await triggerStoryAction(.translation, story: story, recordCommand: false)
        }
    }

    private func story(for command: WidgetCommand) -> WidgetStory? {
        stories.first(where: { story in
            story.id == command.storyID && story.feedUrl == command.feedURL
        })
    }

    private func runBusy(_ status: String, suppressUnauthorizedAlert: Bool = false, operation: @escaping () async throws -> Void) async {
        guard !isBusy else { return }
        isBusy = true
        errorMessage = nil
        statusMessage = status
        do {
            try await operation()
        } catch {
            handleAsyncError(error, suppressUnauthorizedAlert: suppressUnauthorizedAlert)
        }
        isBusy = false
    }

    private func makeAPIClient() throws -> APIClient {
        try APIClient(baseURLString: backendURLString, token: session?.token)
    }

    private func handleAsyncError(_ error: Error, suppressUnauthorizedAlert: Bool) {
        if case APIClientError.unauthorized = error {
            signOut()
            statusMessage = "Local session expired. Sign in again."
            if !suppressUnauthorizedAlert {
                errorMessage = error.localizedDescription
            }
            return
        }
        // During background/startup loads (suppress flag set), a 404 usually just means
        // the freshly started backend hasn't loaded the cached category/feed yet. Don't
        // raise a scary alert for that — only surface 404s from explicit user actions.
        if case APIClientError.notFound = error, suppressUnauthorizedAlert {
            statusMessage = "Connecting to the local backend…"
            return
        }
        errorMessage = error.localizedDescription
    }

    private func waitForBackendReady(maxAttempts: Int = 20) async {
        for attempt in 0..<maxAttempts {
            refreshDiscoveredBackendURL()
            if let api = try? makeAPIClient(), await api.isBackendReachable() {
                return
            }
            if attempt < maxAttempts - 1 {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
        }
    }

    private func updateRuntimeFeed(_ feed: RuntimeFeed) {
        guard var runtimeConfig else { return }
        if let index = runtimeConfig.feeds.firstIndex(where: { $0.url == feed.url }) {
            runtimeConfig.feeds[index] = feed
        } else {
            runtimeConfig.feeds.append(feed)
        }
        self.runtimeConfig = runtimeConfig
    }

    private func writeUsageExport(data: Data, fileExtension: String) throws -> URL {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withDashSeparatorInDate, .withColonSeparatorInTime]
        let stamp = formatter.string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("ai-news-usage-\(stamp)")
            .appendingPathExtension(fileExtension)
        try data.write(to: url, options: .atomic)
        return url
    }

    private func usageCSV(_ usage: AIUsageExport) -> String {
        var lines = [
            "scope,kind,requests,inputTokens,outputTokens,totalTokens,model,label,createdAt",
            "totals,,,\(usage.inputTokens),\(usage.outputTokens),\(usage.totalTokens),,,"
        ]
        for key in usage.byKind.keys.sorted() {
            guard let stats = usage.byKind[key] else { continue }
            lines.append("byKind,\(csvField(key)),\(stats.requests),\(stats.inputTokens),\(stats.outputTokens),\(stats.totalTokens),,,")
        }
        for item in usage.recent {
            lines.append([
                "recent",
                csvField(item.kind),
                "",
                "\(item.inputTokens)",
                "\(item.outputTokens)",
                "\(item.totalTokens)",
                csvField(item.model),
                csvField(item.label),
                "\(item.createdAt)"
            ].joined(separator: ","))
        }
        return lines.joined(separator: "\n")
    }

    private func csvField(_ value: String) -> String {
        let escaped = value.replacingOccurrences(of: "\"", with: "\"\"")
        return "\"\(escaped)\""
    }
}

private extension JSONEncoder {
    static var pretty: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}
