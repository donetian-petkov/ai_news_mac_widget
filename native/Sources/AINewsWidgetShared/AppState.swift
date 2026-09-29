import Foundation
import SwiftUI

@MainActor
public final class WidgetAppState: ObservableObject {
    @Published public var session: UserSession?
    @Published public var categories: [WidgetCategory] = []
    @Published public var selectedCategoryID: Int?
    @Published public var stories: [WidgetStory] = []
    @Published public var keywords: [String] = []
    @Published public var keywordMatches: [WidgetStory] = []
    @Published public var monitorAlerts: [HistoryEntry] = []
    @Published public var usage: AIUsageExport?
    @Published public var runtimeConfig: RuntimeConfigResponse?
    @Published public var aiProgress: [String: AiFeedProgress] = [:]
    @Published public var backendOps: OpsAiJobsResponse?
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
    @Published public var pendingSharedURL: String?
    @Published public var lastSharedStoryKey: String?
    @Published public var lastShareMessage: String?
    @Published public var scrollToTopSignal = 0
    @Published public var runtimePower = RuntimePowerState()

    private let sessionStore: SessionStore
    private let snapshotStore: SnapshotStore
    private var isProcessingCommands = false
    private var startBackend: (@MainActor () -> Void)?
    private var stopBackend: (@MainActor () -> Void)?

    public init(
        sessionStore: SessionStore? = nil,
        snapshotStore: SnapshotStore? = nil
    ) {
        self.sessionStore = sessionStore ?? .shared
        self.snapshotStore = snapshotStore ?? .shared
        self.session = self.sessionStore.session
        let snapshot = self.snapshotStore.loadSnapshot()
        let normalizedPower = snapshot.runtimePower.normalized()
        self.runtimePower = normalizedPower
        if normalizedPower != snapshot.runtimePower {
            try? self.snapshotStore.setRuntimePower(normalizedPower)
        }
        self.categories = snapshot.categories
        self.selectedCategoryID = snapshot.activeCategoryID ?? snapshot.categories.first?.id
        self.keywords = snapshot.keywords
        self.keywordMatches = snapshot.keywordMatches
        self.monitorAlerts = snapshot.monitorAlerts
        if snapshot.activeCategoryID == FilteredCategoryID {
            self.stories = snapshot.keywordMatches
        } else {
            self.stories = snapshot.activeCategoryID.flatMap { snapshot.storiesByCategory[String($0)] } ?? []
        }
    }

    public var backendURLString: String {
        get { sessionStore.baseURLString }
        set { sessionStore.baseURLString = newValue }
    }

    public func refreshDiscoveredBackendURL() {
        sessionStore.synchronizeDiscoveredBaseURL()
    }

    public func configureBackendPower(start: @escaping @MainActor () -> Void, stop: @escaping @MainActor () -> Void) {
        startBackend = start
        stopBackend = stop
    }

    public var isRuntimePoweredOn: Bool {
        runtimePower.normalized().isPoweredOn
    }

    public var autoPowerOffAt: Date? {
        runtimePower.normalized().autoPowerOffAt
    }

    public var selectedCategory: WidgetCategory? {
        categories.first(where: { $0.id == selectedCategoryID })
    }

    public var isFilteredSelected: Bool {
        selectedCategoryID == FilteredCategoryID
    }

    public func bootstrapIfNeeded() async {
        normalizeRuntimePower()
        guard runtimePower.isPoweredOn else {
            statusMessage = "Runtime is powered off. Use Power On to start the local server and AI."
            return
        }
        refreshDiscoveredBackendURL()
        await waitForBackendReady()
        guard session != nil else { return }
        // Always refresh categories from the backend on launch. The cached snapshot gives
        // an instant first paint, but its category IDs can be stale relative to the backend
        // DB (which is re-seeded on install), which would make every stories request 404.
        // reloadEverything fetches fresh categories and re-validates the selected one.
        await reloadEverything(selectFirstCategory: selectedCategoryID == nil, suppressUnauthorizedAlert: true)
        await backfillMissingAI()
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

    public func resetPassword(username: String, password: String) async {
        await runBusy("Resetting password...") {
            self.refreshDiscoveredBackendURL()
            await self.waitForBackendReady()
            let api = try self.makeAPIClient()
            let session = try await api.resetPassword(username: username, password: password)
            self.sessionStore.save(session: session)
            self.session = session
            await self.reloadEverything(selectFirstCategory: true, suppressUnauthorizedAlert: true)
            self.statusMessage = "Password reset. Signed in."
        }
    }

    public func signOut() {
        sessionStore.clear()
        session = nil
        categories = []
        stories = []
        keywords = []
        keywordMatches = []
        monitorAlerts = []
        usage = nil
        runtimeConfig = nil
        selectedCategoryID = nil
        errorMessage = nil
        statusMessage = nil
        lastSharedStoryKey = nil
        lastShareMessage = nil
        try? snapshotStore.saveSnapshot(WidgetSnapshot(runtimePower: runtimePower))
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
            await self.refreshAiProgress()
            try await self.refreshAllCategorySnapshots(using: api)
            await self.refreshMonitorAlerts(using: api)
            await self.loadRuntimeContext(suppressUnauthorizedAlert: suppressUnauthorizedAlert)
            await self.loadStoriesForSelectedCategory(suppressUnauthorizedAlert: suppressUnauthorizedAlert)
            self.scrollToTop()
            self.statusMessage = "Updated \(self.categories.count) categories."
        }
    }

    /// On launch, ask the backend to generate any missing AI outputs for enabled feeds,
    /// then refresh the selected category so the results show up as they land.
    public func backfillMissingAI() async {
        guard runtimeConfig?.aiEnabled == true else { return }
        do {
            let api = try makeAPIClient()
            let result = try await api.regenerateMissingAI(kind: "summary", limit: 240)
            let q = result.queued
            AINewsDebugLog.log("backfill queued summary=\(q.summary) research=\(q.research) translation=\(q.translation) skipped summary=\(result.skipped.summary)")
            let total = q.summary + q.research + q.translation
            guard total > 0 else {
                statusMessage = "Summaries and translations are up to date."
                return
            }
            var parts: [String] = []
            if q.summary > 0 { parts.append("\(q.summary) summaries") }
            if q.research > 0 { parts.append("\(q.research) research") }
            if q.translation > 0 { parts.append("\(q.translation) translations") }
            statusMessage = "Generating \(parts.joined(separator: ", "))…"
            // Follow the real backend queue instead of declaring completion after a
            // fixed delay. Large refreshes can enqueue many jobs, and some providers
            // legitimately need retry/cooldown time.
            var idlePolls = 0
            for _ in 0..<60 {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                backendOps = try? await api.fetchOpsAiJobs(limit: 80)
                await refreshAiProgress()
                await loadStoriesForSelectedCategory(suppressUnauthorizedAlert: true)
                await refreshUsage()

                let queueSize = backendOps?.queue.size ?? 0
                let inFlight = backendOps?.queue.inFlight ?? 0
                if queueSize == 0 && inFlight == 0 {
                    idlePolls += 1
                    if idlePolls >= 2 { break }
                } else {
                    idlePolls = 0
                    statusMessage = "Generating \(parts.joined(separator: ", "))… \(queueSize) queued, \(inFlight) running."
                }
            }
            statusMessage = "Finished generating \(parts.joined(separator: ", "))."
        } catch {
            // Backfill is best-effort; never surface an alert for it.
        }
    }

    public func refreshAiProgress() async {
        guard let api = try? makeAPIClient(), let feeds = try? await api.fetchAiProgress() else { return }
        let progress = Dictionary(uniqueKeysWithValues: feeds.map { ($0.feedUrl, $0) })
        let progressChanged = progress != aiProgress
        if progressChanged {
            aiProgress = progress
        }
        backendOps = try? await api.fetchOpsAiJobs(limit: 80)
        // Pending counts in the widget snapshot come from aiProgress; only rewrite
        // the snapshot when those numbers actually moved.
        if progressChanged {
            saveSnapshot()
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
            backendOps = try? await api.fetchOpsAiJobs(limit: 80)
        } catch {
            handleAsyncError(error, suppressUnauthorizedAlert: suppressUnauthorizedAlert)
        }
    }

    public func selectCategory(_ category: WidgetCategory) async {
        selectedCategoryID = category.id
        await loadStoriesForSelectedCategory()
        scrollToTop()
    }

    public func selectFilteredFeed() async {
        selectedCategoryID = FilteredCategoryID
        await loadStoriesForSelectedCategory()
        scrollToTop()
    }

    public func loadStoriesForSelectedCategory(limit: Int? = nil, suppressUnauthorizedAlert: Bool = false) async {
        do {
            refreshDiscoveredBackendURL()
            let api = try makeAPIClient()
            if isFilteredSelected {
                let matches = try await api.fetchKeywordMatches(limit: limit ?? 30)
                stories = matches
                keywordMatches = matches
            } else {
                guard let category = selectedCategory else { return }
                let response = try await api.fetchStories(categoryID: category.id, limit: limit ?? category.activeCount)
                stories = response.stories
                updateCategory(response.category)
            }
            // Signal floating widgets to refresh (picks up newly generated AI content).
            NotificationCenter.default.post(name: Notification.Name("AINewsWidgetShouldRefresh"), object: nil)
            saveSnapshot()
        } catch {
            handleAsyncError(error, suppressUnauthorizedAlert: suppressUnauthorizedAlert)
        }
    }

    public func expandSelectedCategory() async {
        guard !isFilteredSelected, let category = selectedCategory else { return }
        await runBusy("Showing more stories...") {
            let api = try self.makeAPIClient()
            let updated = try await api.expandCategory(categoryID: category.id)
            self.updateCategory(updated)
            try await Task.sleep(nanoseconds: 150_000_000)
            await self.loadStoriesForSelectedCategory(limit: updated.activeCount)
        }
    }

    public func resetSelectedCategory() async {
        guard !isFilteredSelected, let category = selectedCategory else { return }
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
        guard !isFilteredSelected, let category = selectedCategory else { return }
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

    public func shareStory(_ story: WidgetStory) async {
        await runBusy("Preparing share link...") {
            if let sourceLink = story.link, !sourceLink.isEmpty {
                self.pendingSharedURL = sourceLink
                self.statusMessage = "Copied article link for \(story.title)."
                self.lastSharedStoryKey = story.storyKey
                self.lastShareMessage = "Copied"
                return
            }

            throw APIClientError.server(message: "This story does not expose a shareable article URL.")
        }
    }

    public func createLocalStoryShareLink(_ story: WidgetStory) async {
        await runBusy("Preparing local share link...") {
            let api = try self.makeAPIClient()
            let response = try await api.createShare(kind: "story", title: story.title, payload: [
                "itemId": .string(story.id),
                "feedUrl": .string(story.feedUrl),
                "title": .string(story.title),
                "link": .string(story.link ?? ""),
                "source": .string(story.source ?? ""),
                "summary": .string(story.summary ?? ""),
                "research": .string(story.research ?? "")
            ])
            let shareURL = response.url.hasPrefix("http") ? response.url : "\(self.backendURLString)\(response.url)"
            self.pendingSharedURL = shareURL
            self.statusMessage = "Copied local share link for \(story.title)."
            self.lastSharedStoryKey = story.storyKey
            self.lastShareMessage = "Copied local link"
        }
    }

    public func authorizedAPIClient() throws -> APIClient {
        try makeAPIClient()
    }

    public func triggerStoryAction(_ action: WidgetStoryAction, story: WidgetStory, recordCommand: Bool) async {
        if action == .hide {
            removeStoryLocally(story)
            statusMessage = "Hidden \(story.title)."
            do {
                let api = try makeAPIClient()
                try await api.triggerStoryAction(action, story: story)
            } catch {
                errorMessage = error.localizedDescription
            }
            if recordCommand {
                try? snapshotStore.appendCommand(
                    WidgetCommand(
                        kind: .hideStory,
                        categoryID: selectedCategoryID,
                        storyID: story.id,
                        feedURL: story.feedUrl
                    )
                )
            }
            return
        }

        await runBusy("Sending \(action.rawValue) request...") {
            let api = try self.makeAPIClient()
            try await api.triggerStoryAction(action, story: story)
            self.statusMessage = "\(action.rawValue.capitalized) queued for \(story.title)."
            // The backend generates asynchronously. Poll the category so the freshly
            // generated summary/research/translation shows up without a manual refresh.
            await self.pollForStoryActionResult(action, story: story)
            if recordCommand {
                try? self.snapshotStore.appendCommand(
                    WidgetCommand(
                        kind: {
                            switch action {
                            case .summary: return .openSummary
                            case .research: return .openResearch
                            case .translation: return .openTranslation
                            case .neutralTitle: return .openNeutralTitle
                            case .refresh: return .refreshCategory
                            case .hide: return .hideStory
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

    private func pollForStoryActionResult(_ action: WidgetStoryAction, story: WidgetStory) async {
        guard action != .refresh && action != .hide else { return }
        func hasResult(_ s: WidgetStory) -> Bool {
            switch action {
            case .summary: return !(s.summary ?? "").isEmpty
            case .research: return !(s.research ?? "").isEmpty
            case .translation: return !(s.translatedTitle ?? "").isEmpty
            case .neutralTitle: return s.hasNeutralTitle || !s.neutralTitlePending
            case .refresh, .hide: return true
            }
        }
        // Poll for up to ~16s; generation usually completes within a few seconds.
        for _ in 0..<8 {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            await loadStoriesForSelectedCategory(suppressUnauthorizedAlert: true)
            if let updated = stories.first(where: { $0.id == story.id && $0.feedUrl == story.feedUrl }),
               hasResult(updated) {
                statusMessage = "\(action.rawValue.capitalized) ready for \(story.title)."
                return
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
            await self.loadStoriesForSelectedCategory(suppressUnauthorizedAlert: true)
            self.scrollToTop()
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

    public func setFeedPolling(feedURL: String, enabled: Bool) async {
        guard var feed = runtimeConfig?.feeds.first(where: { $0.url == feedURL }) else {
            errorMessage = "Feed not found."
            return
        }
        feed.settings.pollingEnabled = enabled
        await saveFeedSettings(feed)
    }

    public func setFeedAiEnabled(feedURL: String, enabled: Bool) async {
        guard var feed = runtimeConfig?.feeds.first(where: { $0.url == feedURL }) else {
            errorMessage = "Feed not found."
            return
        }
        feed.settings.aiEnabled = enabled
        await saveFeedSettings(feed)
    }

    public func setFeedOperationalState(feedURL: String, pollingEnabled: Bool, aiEnabled: Bool) async {
        guard var feed = runtimeConfig?.feeds.first(where: { $0.url == feedURL }) else {
            errorMessage = "Feed not found."
            return
        }
        feed.settings.pollingEnabled = pollingEnabled
        feed.settings.aiEnabled = aiEnabled
        await saveFeedSettings(feed)
    }

    public func saveGlobalAiDefaults() async {
        await runBusy("Saving global AI settings...") {
            let api = try self.makeAPIClient()
            try await api.saveGlobalAiDefaults(self.globalAiDefaults)
            await self.loadRuntimeContext()
            self.statusMessage = "Applied global AI settings to every feed."
        }
    }

    public func applyBudgetToAllFeeds(_ budget: String) async {
        guard ["low", "standard", "high"].contains(budget) else {
            errorMessage = "Choose Low, Standard, or High budget."
            return
        }
        guard let feeds = runtimeConfig?.feeds, !feeds.isEmpty else {
            errorMessage = "No feeds available to update."
            return
        }
        await runBusy("Applying \(budget.capitalized) budget to all feeds...") {
            let api = try self.makeAPIClient()
            for var feed in feeds {
                feed.settings.budget = budget
                _ = try await api.saveFeedSettings(feed)
            }
            await self.loadRuntimeContext()
            await self.refreshAiProgress()
            self.statusMessage = "Applied \(budget.capitalized) budget to \(feeds.count) feed\(feeds.count == 1 ? "" : "s")."
        }
    }

    public func controlAiQueue(
        action: String,
        kind: String = "all",
        bulkOnly: Bool = false,
        backgroundOnly: Bool = false
    ) async {
        await runBusy("Updating AI queue...") {
            let api = try self.makeAPIClient()
            let response = try await api.controlOpsAiQueue(
                action: action,
                kind: kind,
                bulkOnly: bulkOnly,
                backgroundOnly: backgroundOnly
            )
            self.backendOps = try? await api.fetchOpsAiJobs(limit: 150)
            await self.refreshAiProgress()
            let queued = response.queued ?? 0
            let suffix = queued > 0 ? ", requeued \(queued)" : ""
            self.statusMessage = "AI queue \(action.replacingOccurrences(of: "_", with: " ")) affected \(response.affected)\(suffix)."
        }
    }

    public func powerOn() async {
        await setRuntimePower(poweredOn: true, autoPowerOffAt: nil, status: "Powering on local server and AI…")
    }

    public func powerOff() async {
        await setRuntimePower(poweredOn: false, autoPowerOffAt: nil, status: "Powering off local server and AI…")
    }

    public func schedulePowerOff(afterHours hours: Double) async {
        let clampedHours = min(max(hours, 0.25), 24)
        guard runtimePower.isPoweredOn else {
            statusMessage = "Runtime is already powered off."
            return
        }
        let deadline = Date().addingTimeInterval(clampedHours * 3600)
        runtimePower = RuntimePowerState(isPoweredOn: true, autoPowerOffAt: deadline)
        persistRuntimePower()
        let formatted = Self.powerDateFormatter.string(from: deadline)
        statusMessage = "Auto power-off scheduled for \(formatted)."
    }

    public func cancelScheduledPowerOff() {
        guard runtimePower.autoPowerOffAt != nil else { return }
        runtimePower = RuntimePowerState(isPoweredOn: runtimePower.isPoweredOn, autoPowerOffAt: nil)
        persistRuntimePower()
        statusMessage = "Auto power-off cancelled."
    }

    private func setRuntimePower(poweredOn: Bool, autoPowerOffAt: Date?, status: String) async {
        isBusy = true
        errorMessage = nil
        statusMessage = status
        runtimePower = RuntimePowerState(isPoweredOn: poweredOn, autoPowerOffAt: autoPowerOffAt).normalized()
        persistRuntimePower()

        if poweredOn {
            startBackend?()
            await waitForBackendReady(maxAttempts: 12)
            if session != nil, let api = try? makeAPIClient() {
                _ = try? await api.controlOpsAiQueue(action: "resume")
                await loadRuntimeContext(suppressUnauthorizedAlert: true)
                await refreshAiProgress()
            }
            statusMessage = "Local server and AI are powered on."
        } else {
            if session != nil, let api = try? makeAPIClient() {
                _ = try? await api.controlOpsAiQueue(action: "pause")
            }
            stopBackend?()
            if var config = runtimeConfig {
                config.aiEnabled = false
                runtimeConfig = config
            }
            backendOps = nil
            statusMessage = "Local server and AI are powered off."
        }

        isBusy = false
    }

    public func createDatabaseBackup(reason: String = "manual") async {
        await runBusy("Creating database backup...") {
            let api = try self.makeAPIClient()
            let response = try await api.createDatabaseBackup(reason: reason)
            let sizeMb = Double(response.backup.sizeBytes) / 1_048_576.0
            self.statusMessage = String(format: "Database backup created: %@ (%.1f MB).", response.backup.filename, sizeMb)
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
                    translationEnabled: settings.translationEnabled,
                    neutralTitlesEnabled: settings.neutralTitlesEnabled
                )
            }
            await self.loadRuntimeContext()
            self.statusMessage = "Applied AI settings to \(feedUrls.count) feed\(feedUrls.count == 1 ? "" : "s") in \(category.name)."
        }
    }

    public func scrollToTop() {
        scrollToTopSignal += 1
        scrollToStoryID = stories.first?.id
    }

    public func startCommandLoop() async {
        while !Task.isCancelled {
            await enforcePowerSchedule()
            await processPendingCommands()
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

        if let categoryID {
            if categoryID == FilteredCategoryID {
                selectedCategoryID = FilteredCategoryID
                await loadStoriesForSelectedCategory(limit: 30, suppressUnauthorizedAlert: true)
            } else if let category = categories.first(where: { $0.id == categoryID }) {
                selectedCategoryID = category.id
                await loadStoriesForSelectedCategory(limit: category.activeCount, suppressUnauthorizedAlert: true)
            }
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
        case .neutralTitle:
            await triggerStoryAction(.neutralTitle, story: story, recordCommand: false)
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
            if selectedCategoryID == FilteredCategoryID {
                snapshot.keywordMatches = keywordMatches.isEmpty ? stories : keywordMatches
            } else {
                snapshot.storiesByCategory[String(selectedCategoryID)] = stories
            }
        }
        snapshot.keywords = keywords
        snapshot.keywordMatches = keywordMatches
        snapshot.monitorAlerts = monitorAlerts
        snapshot.pendingByCategory = Dictionary(uniqueKeysWithValues: categories.map { (String($0.id), pendingCount(for: $0)) })
        snapshot.filteredPendingCount = aiProgress[FilteredFeedURL]?.pending ?? pendingOutputCount(in: snapshot.keywordMatches)
        snapshot.totalPendingCount = aiProgress.values.reduce(0) { $0 + $1.pending }
        snapshot.runtimePower = runtimePower.normalized()
        try? snapshotStore.saveSnapshot(snapshot)
    }

    private func persistRuntimePower() {
        runtimePower = runtimePower.normalized()
        try? snapshotStore.setRuntimePower(runtimePower)
    }

    private func normalizeRuntimePower() {
        let normalized = runtimePower.normalized()
        if normalized != runtimePower {
            runtimePower = normalized
            persistRuntimePower()
        }
    }

    private func removeStoryLocally(_ story: WidgetStory) {
        stories.removeAll { $0.storyKey == story.storyKey }
        keywordMatches.removeAll { $0.storyKey == story.storyKey }
        try? snapshotStore.hideStory(storyID: story.id, feedURL: story.feedUrl)
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
        // Best-effort: refresh the Keywords widget feed. A failure here must not
        // abort the category snapshot that already succeeded above.
        if let keywords = try? await api.fetchKeywords() {
            snapshot.keywords = keywords
            self.keywords = keywords
        }
        if let matches = try? await api.fetchKeywordMatches(limit: 30) {
            snapshot.keywordMatches = matches
            self.keywordMatches = matches
            if self.isFilteredSelected {
                self.stories = matches
            }
        }
        if let alerts = try? await api.fetchRuleAlerts(limit: 20) {
            snapshot.monitorAlerts = alerts
            self.monitorAlerts = alerts
        }
        snapshot.pendingByCategory = Dictionary(uniqueKeysWithValues: snapshot.categories.map { (String($0.id), pendingCount(for: $0)) })
        snapshot.filteredPendingCount = aiProgress[FilteredFeedURL]?.pending ?? pendingOutputCount(in: snapshot.keywordMatches)
        snapshot.totalPendingCount = aiProgress.values.reduce(0) { $0 + $1.pending }
        try snapshotStore.saveSnapshot(snapshot)
    }

    public func refreshMonitorAlerts() async {
        guard let api = try? makeAPIClient() else { return }
        await refreshMonitorAlerts(using: api)
    }

    private func refreshMonitorAlerts(using api: APIClient) async {
        guard let alerts = try? await api.fetchRuleAlerts(limit: 20) else { return }
        monitorAlerts = alerts
        saveSnapshot()
    }

    private func pendingCount(for category: WidgetCategory) -> Int {
        category.feedUrls.reduce(into: 0) { total, url in
            total += aiProgress[url]?.pending ?? 0
        }
    }

    private func pendingOutputCount(in stories: [WidgetStory]) -> Int {
        stories.reduce(into: 0) { total, story in
            if story.summaryPending { total += 1 }
            if story.researchPending { total += 1 }
            if story.translationPending { total += 1 }
            if story.neutralTitlePending { total += 1 }
        }
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
        switch command.kind {
        case .powerOn:
            await powerOn()
            return
        case .powerOff:
            await powerOff()
            return
        default:
            break
        }

        guard session != nil, runtimePower.isPoweredOn else { return }

        if let categoryID = command.categoryID {
            if categoryID == FilteredCategoryID {
                selectedCategoryID = FilteredCategoryID
                await loadStoriesForSelectedCategory(limit: 30, suppressUnauthorizedAlert: true)
            } else if let category = categories.first(where: { $0.id == categoryID }) {
                selectedCategoryID = category.id
                await loadStoriesForSelectedCategory(limit: category.activeCount, suppressUnauthorizedAlert: true)
            }
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
        case .openNeutralTitle:
            guard let story = story(for: command) else { return }
            await triggerStoryAction(.neutralTitle, story: story, recordCommand: false)
        case .openShare:
            guard let story = story(for: command) else { return }
            await shareStory(story)
        case .hideStory:
            guard let story = story(for: command) else { return }
            await triggerStoryAction(.hide, story: story, recordCommand: false)
        case .powerOn, .powerOff:
            break
        }
    }

    private func story(for command: WidgetCommand) -> WidgetStory? {
        if let current = stories.first(where: { story in
            story.id == command.storyID && story.feedUrl == command.feedURL
        }) {
            return current
        }

        let snapshot = snapshotStore.loadSnapshot()
        let cachedCategories = snapshot.storiesByCategory.values.lazy.flatMap { $0 }
        if let cached = cachedCategories.first(where: { story in
            story.id == command.storyID && story.feedUrl == command.feedURL
        }) {
            return cached
        }

        return snapshot.keywordMatches.first(where: { story in
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
            for candidate in BackendDiscovery.candidateBackendURLStrings(primary: backendURLString) {
                if let api = try? APIClient(baseURLString: candidate, token: session?.token),
                   await api.isBackendReachable() {
                    if backendURLString != candidate {
                        backendURLString = candidate
                    }
                    return
                }
            }
            if attempt < maxAttempts - 1 {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
        }
    }

    private func enforcePowerSchedule() async {
        guard runtimePower.isPoweredOn, let deadline = runtimePower.autoPowerOffAt else { return }
        guard deadline <= Date() else { return }
        await setRuntimePower(poweredOn: false, autoPowerOffAt: nil, status: "Auto power-off reached. Stopping local server and AI…")
    }

    private static let powerDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter
    }()

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
