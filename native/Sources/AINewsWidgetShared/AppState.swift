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
    @Published public var accountSettings = AccountSettings()
    @Published public var isBusy = false
    @Published public var errorMessage: String?
    @Published public var statusMessage: String?
    @Published public var providerKeyDraft = ""
    @Published public var providerKeyStatus: [String: Bool] = [:]
    @Published public var scrollToStoryID: String?
    @Published public var showingSettings = false

    private let sessionStore: SessionStore
    private let snapshotStore: SnapshotStore
    private var isProcessingCommands = false

    public init(
        sessionStore: SessionStore = .shared,
        snapshotStore: SnapshotStore = .shared
    ) {
        self.sessionStore = sessionStore
        self.snapshotStore = snapshotStore
        self.session = sessionStore.session
        let snapshot = snapshotStore.loadSnapshot()
        self.categories = snapshot.categories
        self.selectedCategoryID = snapshot.activeCategoryID ?? snapshot.categories.first?.id
        self.stories = snapshot.activeCategoryID.flatMap { snapshot.storiesByCategory[String($0)] } ?? []
    }

    public var backendURLString: String {
        get { sessionStore.baseURLString }
        set { sessionStore.baseURLString = newValue }
    }

    public func refreshDiscoveredBackendURL() {
        sessionStore.baseURLString = BackendDiscovery.discoveredBackendURLString(fallback: sessionStore.baseURLString)
    }

    public var selectedCategory: WidgetCategory? {
        categories.first(where: { $0.id == selectedCategoryID })
    }

    public func bootstrapIfNeeded() async {
        refreshDiscoveredBackendURL()
        await waitForBackendReady()
        guard session != nil else { return }
        if categories.isEmpty {
            await reloadEverything(selectFirstCategory: true, suppressUnauthorizedAlert: true)
        } else {
            await loadRuntimeContext(suppressUnauthorizedAlert: true)
            await loadStoriesForSelectedCategory(suppressUnauthorizedAlert: true)
        }
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
            let api = try self.makeAPIClient()
            let bootstrap = try await api.fetchBootstrap()
            self.categories = bootstrap.categories.sorted(by: { lhs, rhs in
                lhs.sortOrder == rhs.sortOrder ? lhs.name < rhs.name : lhs.sortOrder < rhs.sortOrder
            })
            self.usage = bootstrap.usage
            if selectFirstCategory || self.selectedCategoryID == nil || !self.categories.contains(where: { $0.id == self.selectedCategoryID }) {
                self.selectedCategoryID = self.categories.first(where: { !$0.hidden })?.id ?? self.categories.first?.id
            }
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

    public func triggerStoryAction(_ action: WidgetStoryAction, story: WidgetStory) async {
        await triggerStoryAction(action, story: story, recordCommand: true)
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
}
