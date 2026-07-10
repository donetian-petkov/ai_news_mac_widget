import SwiftUI
import AppKit
import AINewsWidgetShared
import Combine

private func copyTextToPasteboard(_ text: String) {
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(text, forType: .string)
}

struct RootView: View {
    @EnvironmentObject private var state: WidgetAppState
    // Observed so the whole view tree re-renders (re-reading AINewsTheme colors)
    // when the theme or font size changes.
    @EnvironmentObject private var theme: ThemeSettings

    var body: some View {
        Group {
            if state.session == nil {
                LoginView()
            } else {
                DashboardView()
            }
        }
        .background(AINewsBackground())
        .onOpenURL { url in
            Task {
                await state.handleIncomingURL(url)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .aiNewsRefreshRequested)) { _ in
            Task {
                await state.reloadEverything(selectFirstCategory: state.selectedCategoryID == nil)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .aiNewsOpenSettings)) { _ in
            state.showingSettings = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .aiNewsOpenWidgetHelp)) { _ in
            state.showingWidgetHelp = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .aiNewsOpenWorkspace)) { _ in
            state.showingWorkspace = true
        }
        .onChange(of: state.exportedUsageURL) { _, newValue in
            guard let newValue else { return }
            NSWorkspace.shared.activateFileViewerSelecting([newValue])
        }
        .onChange(of: state.pendingSharedURL) { _, newValue in
            guard let newValue, !newValue.isEmpty else { return }
            copyTextToPasteboard(newValue)
            state.pendingSharedURL = nil
        }
        .alert("Something needs attention", isPresented: Binding(
            get: { state.errorMessage != nil },
            set: { if !$0 { state.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {
                state.errorMessage = nil
            }
        } message: {
            Text(state.errorMessage ?? "")
        }
    }
}

private struct LoginView: View {
    @EnvironmentObject private var state: WidgetAppState
    @State private var username = ""
    @State private var password = ""
    @State private var registerMode = false

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text("AI News for Mac")
                .font(AINewsTheme.font(40, weight: .bold))
                .foregroundStyle(AINewsTheme.textPrimary)

            Text("Local backend, native dashboard, widget-ready snapshots.")
                .font(.title3)
                .foregroundStyle(AINewsTheme.textSecondary)

            Text("This standalone app keeps its own local account and provider keys.")
                .font(.subheadline)
                .foregroundStyle(AINewsTheme.textMuted)

            VStack(alignment: .leading, spacing: 14) {
                Text("Backend URL")
                    .foregroundStyle(AINewsTheme.textSecondary)
                TextField("http://127.0.0.1:4000", text: Binding(
                    get: { state.backendURLString },
                    set: { state.backendURLString = $0 }
                ))
                .textFieldStyle(.roundedBorder)

                Text("Username")
                    .foregroundStyle(AINewsTheme.textSecondary)
                TextField("name@example.com", text: $username)
                    .textFieldStyle(.roundedBorder)

                Text("Password")
                    .foregroundStyle(AINewsTheme.textSecondary)
                SecureField("Password", text: $password)
                    .textFieldStyle(.roundedBorder)
            }

            HStack(spacing: 14) {
                Button(registerMode ? "Create account" : "Sign in") {
                    Task {
                        await state.signIn(username: username, password: password, register: registerMode)
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(AINewsTheme.accentBlue)
                .disabled(state.isBusy || username.isEmpty || password.isEmpty)

                Button(registerMode ? "Use sign in" : "Need an account?") {
                    registerMode.toggle()
                }
                .buttonStyle(.bordered)
            }

            if let statusMessage = state.statusMessage {
                Text(statusMessage)
                    .foregroundStyle(AINewsTheme.textMuted)
            }
        }
        .padding(36)
        .frame(maxWidth: 720)
        .aiNewsPanelStyle()
        .padding(40)
    }
}

private struct DashboardView: View {
    @EnvironmentObject private var state: WidgetAppState
    @EnvironmentObject private var theme: ThemeSettings
    @AppStorage("ai_news_show_hidden_categories") private var showHiddenCategories = true
    @State private var storySearch = ""

    private var sidebarCategories: [WidgetCategory] {
        showHiddenCategories ? state.categories : state.categories.filter { !$0.hidden }
    }

    private var filteredFeedPending: Int {
        state.aiProgress[FilteredFeedURL]?.pending ?? state.keywordMatches.reduce(into: 0) { total, story in
            if story.summaryPending { total += 1 }
            if story.researchPending { total += 1 }
            if story.translationPending { total += 1 }
        }
    }

    private var filteredFeedVisibleCount: Int {
        min(state.keywordMatches.count, 30)
    }

    private var detailTitle: String {
        if state.isFilteredSelected {
            return "Filtered Feed"
        }
        return state.selectedCategory?.name ?? "Pick a category"
    }

    private var detailSubtitle: String {
        if state.isFilteredSelected {
            if state.keywords.isEmpty {
                return "Keyword-matched stories live here. Add keywords in Workspace to turn this feed on."
            }
            return "Stories matching your tracked keywords. Keywords: \(state.keywords.joined(separator: ", "))"
        }
        if let description = state.selectedCategory?.description, !description.isEmpty {
            return description
        }
        return "Stories are image-free here on purpose, so the text and AI actions stay fast and widget-safe."
    }

    private var visibleCategoryCount: Int {
        state.categories.filter { !$0.hidden }.count
    }

    private var hiddenCategoryCount: Int {
        state.categories.filter { $0.hidden }.count
    }

    private var aggregateProgress: (done: Int, total: Int, pending: Int, blocked: Int, totalRelevant: Int) {
        var done = 0, total = 0, pending = 0, blocked = 0, totalRelevant = 0
        for p in state.aiProgress.values {
            done += p.done
            total += p.total
            pending += p.pending
            blocked += p.blocked
            totalRelevant += p.totalRelevant
        }
        return (done, total, pending, blocked, totalRelevant)
    }

    private func categoryProgress(_ category: WidgetCategory) -> (done: Int, total: Int, pending: Int, blocked: Int, totalRelevant: Int) {
        var done = 0, total = 0, pending = 0, blocked = 0, totalRelevant = 0
        for url in category.feedUrls {
            if let p = state.aiProgress[url] {
                done += p.done
                total += p.total
                pending += p.pending
                blocked += p.blocked
                totalRelevant += p.totalRelevant
            }
        }
        return (done, total, pending, blocked, totalRelevant)
    }

    private func runtimeFeed(for url: String) -> RuntimeFeed? {
        state.runtimeConfig?.feeds.first(where: { $0.url == url })
    }

    private func selectedCategoryFeeds(_ category: WidgetCategory) -> [RuntimeFeed] {
        category.feedUrls.compactMap { runtimeFeed(for: $0) }
    }

    private var backendHealthSummary: String? {
        guard let health = state.backendOps?.health else { return nil }
        if !health.aiEnabled || !health.aiAvailable {
            return "AI is not fully configured."
        }
        if health.stalled {
            return "AI queue stalled."
        }
        if health.breakerFeeds > 0 || health.failingFeeds > 0 {
            return "\(health.breakerFeeds) feeds cooling down, \(health.failingFeeds) failing."
        }
        if state.backendOps?.queue.size ?? 0 > 0 || state.backendOps?.queue.inFlight ?? 0 > 0 {
            return "AI queue active."
        }
        return "Backend healthy."
    }

    private var filteredStories: [WidgetStory] {
        let query = storySearch.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return state.stories }
        let lowered = query.lowercased()
        return state.stories.filter { story in
            story.title.lowercased().contains(lowered)
                || (story.source?.lowercased().contains(lowered) ?? false)
                || (story.summary?.lowercased().contains(lowered) ?? false)
                || (story.research?.lowercased().contains(lowered) ?? false)
                || (story.translatedTitle?.lowercased().contains(lowered) ?? false)
        }
    }

    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 220, ideal: 250, max: 280)
        } detail: {
            detail
        }
        .sheet(isPresented: $state.showingSettings) {
            SettingsView()
                .environmentObject(state)
                .environmentObject(theme)
                .frame(minWidth: 760, minHeight: 520)
        }
        .sheet(isPresented: $state.showingWidgetHelp) {
            WidgetHelpView()
                .environmentObject(state)
                .environmentObject(theme)
                .frame(minWidth: 640, minHeight: 460)
        }
        .sheet(isPresented: $state.showingWorkspace) {
            WorkspaceView()
                .environmentObject(state)
                .environmentObject(theme)
                .frame(minWidth: 980, minHeight: 700)
        }
        .task {
            // Keep the header AI progress bar current.
            while !Task.isCancelled {
                await state.refreshAiProgress()
                try? await Task.sleep(nanoseconds: 6_000_000_000)
            }
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 10) {
                    Image(systemName: "newspaper.fill")
                        .foregroundStyle(AINewsTheme.accentBlue)
                    Text("AI News")
                        .font(AINewsTheme.font(18, weight: .bold))
                        .foregroundStyle(AINewsTheme.textPrimary)
                    Spacer()
                    Button {
                        Task { await state.reloadEverything() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .buttonStyle(.bordered)
                    .help("Refresh categories")
                }
                Text("Categories")
                    .font(AINewsTheme.font(12, weight: .semibold))
                    .foregroundStyle(AINewsTheme.textMuted)
                    .textCase(.uppercase)
                HStack(spacing: 8) {
                    Text("\(visibleCategoryCount) visible")
                    Text("\(hiddenCategoryCount) hidden")
                }
                .font(.caption)
                .foregroundStyle(AINewsTheme.textMuted)

                let total = aggregateProgress
                if total.total > 0 || total.blocked > 0 {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.white.opacity(0.2))
                            Capsule()
                                .fill(AINewsTheme.accentCyan)
                                .frame(width: max(4, geo.size.width * CGFloat(total.done) / CGFloat(max(total.total, 1))))
                        }
                    }
                    .frame(height: 6)
                    Text("All feeds · \(total.done)/\(total.total) · \(total.pending) pending")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(AINewsTheme.accentCyan)
                    if total.blocked > 0 {
                        Text("\(total.blocked) waiting on manual action or higher budget")
                            .font(.caption2)
                            .foregroundStyle(AINewsTheme.textMuted)
                    }
                }
                if let backendHealthSummary {
                    Text(backendHealthSummary)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle((state.backendOps?.health?.stalled ?? false) ? AINewsTheme.accentRose : AINewsTheme.textMuted)
                }
            }

            List(selection: Binding(
                get: { state.selectedCategoryID },
                set: { newValue in
                    if newValue == FilteredCategoryID {
                        Task { await state.selectFilteredFeed() }
                    } else if let id = newValue, let category = state.categories.first(where: { $0.id == id }) {
                        Task { await state.selectCategory(category) }
                    }
                }
            )) {
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Filtered Feed")
                            .font(AINewsTheme.font(15, weight: .semibold))
                            .foregroundStyle(AINewsTheme.textPrimary)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                        Text("\(filteredFeedVisibleCount) visible")
                            .font(.caption)
                            .foregroundStyle(AINewsTheme.textMuted)
                        if !state.keywordMatches.isEmpty || filteredFeedPending > 0 {
                            GeometryReader { geo in
                                ZStack(alignment: .leading) {
                                    Capsule().fill(Color.white.opacity(0.25))
                                    Capsule()
                                        .fill(AINewsTheme.accentCyan)
                                        .frame(width: max(4, geo.size.width * CGFloat(state.keywordMatches.count) / CGFloat(max(state.keywordMatches.count + filteredFeedPending, 1))))
                                }
                            }
                            .frame(height: 6)
                            Text("\(state.keywordMatches.count) loaded · \(filteredFeedPending) pending")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(AINewsTheme.accentCyan)
                        }
                    }
                    Spacer()
                    Image(systemName: "line.3.horizontal.decrease.circle")
                        .foregroundStyle(AINewsTheme.accentCyan)
                }
                .tag(FilteredCategoryID)
                .padding(.vertical, 6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .onTapGesture {
                    Task { await state.selectFilteredFeed() }
                }
                .onTapGesture(count: 2) {
                    Task { await state.selectFilteredFeed() }
                    NotificationCenter.default.post(name: .aiNewsOpenFilteredWidget, object: nil)
                }

                ForEach(sidebarCategories) { category in
                    HStack(spacing: 10) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(category.name)
                                .font(AINewsTheme.font(15, weight: .semibold))
                                .foregroundStyle(AINewsTheme.textPrimary)
                                .lineLimit(2)
                                .fixedSize(horizontal: false, vertical: true)
                            Text(category.hidden ? "Hidden" : "\(category.activeCount) visible")
                                .font(.caption)
                                .foregroundStyle(AINewsTheme.textMuted)
                            let p = categoryProgress(category)
                            if p.total > 0 || p.blocked > 0 {
                                GeometryReader { geo in
                                    ZStack(alignment: .leading) {
                                        Capsule().fill(Color.white.opacity(0.25))
                                        Capsule()
                                            .fill(AINewsTheme.accentGold)
                                            .frame(width: max(4, geo.size.width * CGFloat(p.done) / CGFloat(max(p.total, 1))))
                                    }
                                }
                                .frame(height: 6)
                                Text("\(p.done)/\(p.total) · \(p.pending) pending")
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(AINewsTheme.accentGold)
                                if p.blocked > 0 {
                                    Text("\(p.blocked) blocked by budget/manual mode")
                                        .font(.caption2)
                                        .foregroundStyle(AINewsTheme.textMuted)
                                }
                            }
                        }
                        Spacer()
                        Button {
                            Task { await state.toggleVisibility(for: category) }
                        } label: {
                            Image(systemName: category.hidden ? "eye.slash" : "eye")
                        }
                        .buttonStyle(.plain)
                    }
                    .tag(category.id)
                    .padding(.vertical, 6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        Task { await state.selectCategory(category) }
                    }
                    .onTapGesture(count: 2) {
                        Task { await state.selectCategory(category) }
                        NotificationCenter.default.post(
                            name: .aiNewsOpenCategoryWidget,
                            object: nil,
                            userInfo: [
                                "categoryID": category.id,
                                "categoryName": category.name
                            ]
                        )
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(AINewsTheme.panel.opacity(0.7))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

            Toggle("Show hidden", isOn: $showHiddenCategories)
                .toggleStyle(.switch)
                .foregroundStyle(AINewsTheme.textSecondary)

            Button("Settings & AI") {
                state.showingSettings = true
            }
            .buttonStyle(.borderedProminent)
            .tint(AINewsTheme.accentCyan)

            Button("Workspace") {
                state.showingWorkspace = true
            }
            .buttonStyle(.bordered)

            Button("Saved Views") {
                UserDefaults.standard.set(8, forKey: "AINewsWorkspacePreferredTab")
                state.showingWorkspace = true
                NotificationCenter.default.post(name: .aiNewsOpenSavedViews, object: nil)
            }
            .buttonStyle(.bordered)

            Button("Widget Help") {
                state.showingWidgetHelp = true
            }
            .buttonStyle(.bordered)

            Button("Show Widget") {
                NotificationCenter.default.post(name: .aiNewsToggleFloatingWidget, object: nil)
            }
            .buttonStyle(.borderedProminent)
            .tint(AINewsTheme.accentGold)
            .help("Open an always-on-top, scrollable widget for the currently selected feed/category.")

            Button("Show Filtered Widget") {
                NotificationCenter.default.post(name: .aiNewsOpenFilteredWidget, object: nil)
            }
            .buttonStyle(.bordered)
            .tint(AINewsTheme.accentCyan)
            .help("Open the separate filtered feed widget built from your keyword-matched stories.")

            Button("Sign out") {
                state.signOut()
            }
            .buttonStyle(.bordered)
        }
        .padding(20)
        .background(AINewsTheme.backgroundAlt)
    }

    private var detail: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(detailTitle)
                        .font(AINewsTheme.font(30, weight: .bold))
                        .foregroundStyle(AINewsTheme.textPrimary)
                    Text(detailSubtitle)
                        .foregroundStyle(AINewsTheme.textSecondary)
                }
                Spacer()
                HStack(spacing: 10) {
                    Button("Top") { state.scrollToTop() }
                    Button("Reset 5") { Task { await state.resetSelectedCategory() } }
                        .disabled(state.isFilteredSelected)
                    Button("Expand 10") { Task { await state.expandSelectedCategory() } }
                        .disabled(state.isFilteredSelected)
                    Button("Refresh") { Task { await state.refreshSelectedCategory() } }
                }
                .buttonStyle(.bordered)
            }

            HStack(spacing: 12) {
                Label(state.backendURLString, systemImage: "network")
                    .font(.caption)
                    .foregroundStyle(AINewsTheme.textMuted)
                if state.isBusy {
                    ProgressView()
                        .controlSize(.small)
                }
            }

            if let runtimeConfig = state.runtimeConfig {
                HStack(spacing: 14) {
                    Label(runtimeConfig.aiProvider.uppercased(), systemImage: runtimeConfig.aiEnabled ? "brain.head.profile" : "brain")
                    Label(runtimeConfig.summaryModel, systemImage: "text.bubble")
                    Label(runtimeConfig.researchModel, systemImage: "sparkles.rectangle.stack")
                    if let usage = state.usage {
                        Label("\(formatTokens(usage.totalTokens)) tokens", systemImage: "gauge.with.needle")
                            .foregroundStyle(AINewsTheme.accentCyan)
                            .help("\(usage.inputTokens) in / \(usage.outputTokens) out — total AI tokens used. Details in Settings & AI.")
                    }
                }
                .font(.caption)
                .foregroundStyle(AINewsTheme.textMuted)
            }

            if let statusMessage = state.statusMessage {
                Text(statusMessage)
                    .font(.subheadline)
                    .foregroundStyle(AINewsTheme.accentCyan)
            }

            if let selected = state.selectedCategory {
                let progress = categoryProgress(selected)
                if progress.total > 0 && progress.done < progress.total {
                    VStack(alignment: .leading, spacing: 3) {
                        ProgressView(value: Double(progress.done), total: Double(progress.total))
                            .tint(AINewsTheme.accentCyan)
                        Text("Generating AI for \(selected.name) — \(progress.total - progress.done) pending · \(progress.done)/\(progress.total) done")
                            .font(.caption)
                            .foregroundStyle(AINewsTheme.textMuted)
                    }
                }

                let feeds = selectedCategoryFeeds(selected)
                if !feeds.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("Feed controls")
                                .font(.headline)
                                .foregroundStyle(AINewsTheme.textPrimary)
                            Spacer()
                            Text("\(feeds.count) feed\(feeds.count == 1 ? "" : "s")")
                                .font(.caption)
                                .foregroundStyle(AINewsTheme.textMuted)
                        }

                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 12) {
                                ForEach(feeds, id: \.url) { feed in
                                    FeedQuickControlCard(feed: feed)
                                }
                            }
                            .padding(.vertical, 2)
                        }
                    }
                    .padding(16)
                    .aiNewsPanelStyle()
                }
            }

            HStack(spacing: 12) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(AINewsTheme.textMuted)
                TextField(state.isFilteredSelected ? "Search stories in the filtered feed" : "Search stories in this category", text: $storySearch)
                    .textFieldStyle(.plain)
                    .foregroundStyle(AINewsTheme.textPrimary)
                if !storySearch.isEmpty {
                    Button {
                        storySearch = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(AINewsTheme.textMuted)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(AINewsTheme.panel.opacity(0.7))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(AINewsTheme.panelBorder.opacity(0.45), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

            if !storySearch.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text("\(filteredStories.count) result\(filteredStories.count == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundStyle(AINewsTheme.textMuted)
            }

            if state.categories.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    Text("No categories loaded yet")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(AINewsTheme.textPrimary)
                    Text("If the backend moved to another port, this app now follows it automatically. Try Refresh once the backend is running.")
                        .foregroundStyle(AINewsTheme.textSecondary)
                    Button("Refresh now") {
                        Task { await state.reloadEverything(selectFirstCategory: true) }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(AINewsTheme.accentBlue)
                }
                .padding(22)
                .frame(maxWidth: 560, alignment: .leading)
                .aiNewsPanelStyle()
            }

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 18) {
                        if filteredStories.isEmpty && !storySearch.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            VStack(alignment: .leading, spacing: 10) {
                                Text("No stories match")
                                    .font(.title3.weight(.semibold))
                                    .foregroundStyle(AINewsTheme.textPrimary)
                                Text("Try a broader term or clear the search field.")
                                    .foregroundStyle(AINewsTheme.textSecondary)
                            }
                            .padding(22)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .aiNewsPanelStyle()
                        }
                        ForEach(filteredStories) { story in
                            StoryCardView(story: story)
                                .id(story.id)
                        }
                    }
                    .padding(.bottom, 24)
                }
                .onChange(of: state.scrollToStoryID) { _, newValue in
                    guard let newValue else { return }
                    withAnimation(.easeInOut(duration: 0.25)) {
                        proxy.scrollTo(newValue, anchor: .top)
                    }
                }
            }
        }
        .padding(24)
        .background(AINewsBackground())
    }
}

private struct WidgetHelpView: View {
    @EnvironmentObject private var state: WidgetAppState

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Text("Add the widgets")
                    .font(AINewsTheme.font(28, weight: .bold))
                    .foregroundStyle(AINewsTheme.textPrimary)
                Spacer()
                Button("Done") {
                    state.showingWidgetHelp = false
                }
            }

            VStack(alignment: .leading, spacing: 14) {
                helpStep(number: 1, title: "Install the app", body: "Use the installed AI News Widget app in Applications so macOS can discover the widget extension.")
                helpStep(number: 2, title: "Open the Widget gallery", body: "On the Mac desktop, Control-click the desktop or Notification Center, then choose Edit Widgets.")
                helpStep(number: 3, title: "Search for AI News", body: "Add either the master widget for category overview or a category widget for one news group.")
                helpStep(number: 4, title: "Pick a category widget", body: "After placing a category widget, edit it and choose the category you want that widget to follow.")
                helpStep(number: 5, title: "Use the app for deeper actions", body: "Summary, research, translation, pinning, feed AI controls, and category management stay in sync with the widgets through the shared local snapshot.")
            }
            .padding(20)
            .aiNewsPanelStyle()

            VStack(alignment: .leading, spacing: 10) {
                Text("Widget types")
                    .font(.headline)
                    .foregroundStyle(AINewsTheme.textSecondary)
                Text("Master widget: category overview with quick refresh and visibility controls.")
                    .foregroundStyle(AINewsTheme.textPrimary)
                Text("Category widget: 5-story default view, 10-story expansion, pinning, and per-story AI actions.")
                    .foregroundStyle(AINewsTheme.textPrimary)
            }
            .padding(20)
            .aiNewsPanelStyle()

            Spacer()
        }
        .padding(28)
        .background(AINewsBackground())
    }

    private func helpStep(number: Int, title: String, body: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Text("\(number)")
                .font(.headline.weight(.bold))
                .foregroundStyle(AINewsTheme.accentBlue)
                .frame(width: 28, height: 28)
                .background(AINewsTheme.accentBlue.opacity(0.16))
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(AINewsTheme.textPrimary)
                Text(body)
                    .foregroundStyle(AINewsTheme.textSecondary)
            }
        }
    }
}

private struct StoryCardView: View {
    @EnvironmentObject private var state: WidgetAppState
    let story: WidgetStory

    @AppStorage("ai_news_show_thumbnails") private var coversEnabled = true

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            if coversEnabled {
                StoryThumbnail(url: story.coverUrl.flatMap { URL(string: $0) }, size: 120)
            }
            VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Text(story.source ?? story.feedUrl)
                            .font(.headline)
                            .foregroundStyle(AINewsTheme.textPrimary)
                        if let mood = story.mood, !mood.isEmpty {
                            MoodChip(mood: mood)
                        }
                    }
                    if let date = story.publishedDate {
                        Text(date.formatted(date: .abbreviated, time: .shortened))
                            .font(.caption)
                            .foregroundStyle(AINewsTheme.textMuted)
                    }
                }
                Spacer()
                if let category = state.selectedCategory, category.isPinned(story) {
                    Label("Pinned", systemImage: "pin.fill")
                        .font(.caption)
                        .foregroundStyle(AINewsTheme.accentGold)
                }
            }

            Text(story.title)
                .font(AINewsTheme.font(28, weight: .bold))
                .foregroundStyle(AINewsTheme.accentBlue)

            if let translated = story.translatedTitle, !translated.isEmpty, translated != story.title {
                Text(translated)
                    .font(.title3)
                    .foregroundStyle(AINewsTheme.textSecondary)
            }

            Divider().overlay(AINewsTheme.panelBorder.opacity(0.55))

            storyBlock(title: "Summary", text: story.summary, pending: story.summaryPending, accent: AINewsTheme.accentBlue)
            storyBlock(title: "Research", text: story.research, pending: story.researchPending, accent: AINewsTheme.accentCyan)
            // Only show Translation when one exists or is in progress. For stories already
            // in the display language (e.g. Bulgarian feeds), translation isn't needed, so
            // showing "Not translated yet." would be misleading noise.
            if translatedStoryText != nil || story.translationPending {
                storyBlock(
                    title: "Translation",
                    text: translatedStoryText,
                    pending: story.translationPending,
                    accent: AINewsTheme.accentGold,
                    emptyLabel: "Not translated yet."
                )
            }

            HStack(spacing: 12) {
                actionButton("Summary", systemImage: "text.bubble", tint: AINewsTheme.accentBlue) {
                    Task { await state.triggerStoryAction(.summary, story: story) }
                }
                actionButton("Research", systemImage: "sparkles.rectangle.stack", tint: AINewsTheme.accentCyan) {
                    Task { await state.triggerStoryAction(.research, story: story) }
                }
                actionButton("Translate", systemImage: "globe", tint: AINewsTheme.accentGold) {
                    Task { await state.triggerStoryAction(.translation, story: story) }
                }
                actionButton("Save", systemImage: "bookmark", tint: AINewsTheme.accentCyan) {
                    Task { await state.saveStory(story) }
                }
                Menu {
                    Button { copyTextToPasteboard(story.link ?? "") } label: { Label("Copy link", systemImage: "link") }
                    Button { openShare("https://x.com/intent/post") } label: { Label("Share on X", systemImage: "character.bubble") }
                    Button { openShare("https://www.facebook.com/sharer/sharer.php") } label: { Label("Facebook", systemImage: "person.2.fill") }
                    Button { openShare("https://www.reddit.com/submit") } label: { Label("Reddit", systemImage: "globe") }
                    Divider()
                    Button { Task { await state.createLocalStoryShareLink(story) } } label: { Label("Create local share link", systemImage: "square.and.arrow.up") }
                } label: {
                    Label("Share", systemImage: "square.and.arrow.up")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .tint(AINewsTheme.accentGold)
                if !state.isFilteredSelected {
                    actionButton("Pin", systemImage: "pin", tint: AINewsTheme.accentRose) {
                        Task { await state.togglePin(for: story) }
                    }
                }
                Button {
                    if let link = story.link, let url = URL(string: link) {
                        NSWorkspace.shared.open(url)
                    }
                } label: {
                    Label("Open source", systemImage: "arrow.up.right.square")
                }
                .buttonStyle(.bordered)
                .tint(AINewsTheme.textSecondary)
            }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(22)
        .aiNewsCardStyle(cornerRadius: 18)
    }

    @ViewBuilder
    private func storyBlock(title: String, text: String?, pending: Bool, accent: Color, emptyLabel: String = "Not generated yet.") -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title.uppercased())
                    .font(.caption)
                    .foregroundStyle(AINewsTheme.textMuted)
                if pending {
                    Text("Queued")
                        .font(.caption)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(accent.opacity(0.18))
                        .foregroundStyle(accent)
                        .clipShape(Capsule())
                }
            }
            if let text, !text.isEmpty {
                Text(text)
                    .font(.body)
                    .foregroundStyle(AINewsTheme.textPrimary)
            } else {
                Text(pending ? "Waiting for the local AI queue." : emptyLabel)
                    .foregroundStyle(AINewsTheme.textMuted)
            }
        }
    }

    private var translatedStoryText: String? {
        guard let translated = story.translatedTitle, !translated.isEmpty, translated != story.title else {
            return nil
        }
        return translated
    }

    private func actionButton(_ title: String, systemImage: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
        }
        .buttonStyle(.borderedProminent)
        .tint(tint)
    }

    private func openShare(_ base: String) {
        guard let link = story.link, !link.isEmpty, var comps = URLComponents(string: base) else { return }
        if base.contains("x.com") {
            comps.queryItems = [URLQueryItem(name: "text", value: "\(story.title) \(link)")]
        } else if base.contains("reddit") {
            comps.queryItems = [URLQueryItem(name: "url", value: link), URLQueryItem(name: "title", value: story.title)]
        } else {
            comps.queryItems = [URLQueryItem(name: "u", value: link)]
        }
        if let url = comps.url { NSWorkspace.shared.open(url) }
    }
}

private struct KeywordsWorkspaceTab: View {
    @EnvironmentObject private var state: WidgetAppState
    @State private var keywords: [String] = []
    @State private var draft = ""
    @State private var matches: [WidgetStory] = []
    @State private var loading = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header(title: "Keywords & Filtered", subtitle: "Stories matching these keywords are highlighted in the Filtered list below.")

            HStack(spacing: 10) {
                TextField("Add a keyword and press Return", text: $draft)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { addKeyword() }
                Button("Add") { addKeyword() }
                    .buttonStyle(.borderedProminent)
                    .tint(AINewsTheme.accentBlue)
                    .disabled(draft.trimmingCharacters(in: .whitespaces).isEmpty)
            }

            if keywords.isEmpty {
                Text("No keywords yet. Add some to build the Filtered list.")
                    .font(.caption)
                    .foregroundStyle(AINewsTheme.textMuted)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 8)], spacing: 8) {
                    ForEach(keywords, id: \.self) { keyword in
                        HStack(spacing: 6) {
                            Text(keyword)
                                .font(.caption)
                                .foregroundStyle(AINewsTheme.textPrimary)
                            Spacer(minLength: 0)
                            Button {
                                remove(keyword)
                            } label: {
                                Image(systemName: "xmark.circle.fill").foregroundStyle(AINewsTheme.textMuted)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(AINewsTheme.panel.opacity(0.7))
                        .clipShape(Capsule())
                    }
                }
            }

            HStack {
                Text("Filtered stories")
                    .font(.headline)
                    .foregroundStyle(AINewsTheme.textSecondary)
                if loading { ProgressView().controlSize(.small) }
                Spacer()
                Button("Refresh") { Task { await loadMatches() } }
                    .buttonStyle(.bordered)
            }

            ScrollView {
                LazyVStack(spacing: 12) {
                    if matches.isEmpty {
                        Text("No stories match your keywords yet.")
                            .font(.caption)
                            .foregroundStyle(AINewsTheme.textMuted)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.top, 8)
                    }
                    ForEach(matches) { story in
                        Button {
                            if let link = story.link, let url = URL(string: link) { NSWorkspace.shared.open(url) }
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(story.source ?? story.feedUrl)
                                    .font(.caption2).foregroundStyle(AINewsTheme.textMuted)
                                Text(story.title)
                                    .font(.headline).foregroundStyle(AINewsTheme.accentBlue)
                                    .fixedSize(horizontal: false, vertical: true)
                                if let summary = story.summary, !summary.isEmpty {
                                    Text(summary).font(.body).foregroundStyle(AINewsTheme.textSecondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(16)
                            .aiNewsPanelStyle()
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .task { await reload() }
    }

    private func reload() async {
        do {
            let api = try state.authorizedAPIClient()
            keywords = try await api.fetchKeywords()
        } catch { state.errorMessage = error.localizedDescription }
        await loadMatches()
    }

    private func loadMatches() async {
        loading = true
        defer { loading = false }
        if let api = try? state.authorizedAPIClient() {
            matches = (try? await api.fetchKeywordMatches(limit: 40)) ?? matches
        }
    }

    private func addKeyword() {
        let value = draft.trimmingCharacters(in: .whitespaces)
        guard !value.isEmpty, !keywords.contains(where: { $0.caseInsensitiveCompare(value) == .orderedSame }) else { return }
        keywords.append(value)
        draft = ""
        Task { await save() }
    }

    private func remove(_ keyword: String) {
        keywords.removeAll { $0 == keyword }
        Task { await save() }
    }

    private func save() async {
        do {
            let api = try state.authorizedAPIClient()
            keywords = try await api.saveKeywords(keywords)
            state.statusMessage = "Updated keywords."
            // Give the backend a moment to reprocess, then refresh matches.
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            await loadMatches()
        } catch { state.errorMessage = error.localizedDescription }
    }
}

private struct DiagnosticsWorkspaceTab: View {
    @EnvironmentObject private var state: WidgetAppState
    @State private var ops: OpsAiJobsResponse?
    @State private var loading = false

    private func stageColor(_ stage: String) -> Color {
        switch stage {
        case "success": return AINewsTheme.accentCyan
        case "error", "drop": return AINewsTheme.accentRose
        case "skip": return AINewsTheme.textMuted
        default: return AINewsTheme.accentBlue // enqueue/start
        }
    }

    private var issues: [OpsAiJobEvent] {
        (ops?.events ?? []).filter { $0.stage == "error" || $0.stage == "drop" }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    header(title: "Diagnostics", subtitle: "Token usage, AI job queue, issues, and live logs.")
                    Spacer()
                    if loading { ProgressView().controlSize(.small) }
                    Button("Refresh") { Task { await reload() } }.buttonStyle(.bordered)
                }

                // Token usage
                if let usage = state.usage {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Token usage").font(.headline).foregroundStyle(AINewsTheme.textSecondary)
                        HStack(spacing: 24) {
                            metric("Total", "\(usage.totalTokens)")
                            metric("Input", "\(usage.inputTokens)")
                            metric("Output", "\(usage.outputTokens)")
                        }
                        ForEach(usage.byKind.keys.sorted(), id: \.self) { key in
                            if let s = usage.byKind[key] {
                                Text("\(key): \(s.requests) req · \(s.totalTokens) tok")
                                    .font(.caption).foregroundStyle(AINewsTheme.textMuted)
                            }
                        }
                    }
                    .padding(16).aiNewsPanelStyle()
                }

                // Queue
                if let q = ops?.queue {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("AI job queue").font(.headline).foregroundStyle(AINewsTheme.textSecondary)
                        HStack(spacing: 24) {
                            metric("Queued", "\(q.size)")
                            metric("In flight", "\(q.inFlight)")
                            metric("Dead", "\(q.deadLetters)")
                        }
                        HStack(spacing: 14) {
                            ForEach(q.countsByKind.keys.sorted(), id: \.self) { k in
                                if let v = q.countsByKind[k], v > 0 {
                                    Text("\(k) \(v)").font(.caption).foregroundStyle(AINewsTheme.textMuted)
                                }
                            }
                        }
                    }
                    .padding(16).aiNewsPanelStyle()
                }

                if let health = ops?.health {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Backend health").font(.headline).foregroundStyle(AINewsTheme.textSecondary)
                        HStack(spacing: 24) {
                            metric("AI", health.aiEnabled && health.aiAvailable ? "ready" : "off")
                            metric("Failing feeds", "\(health.failingFeeds)")
                            metric("Cooling down", "\(health.breakerFeeds)")
                        }
                        Text(health.stalled ? "Queue looks stalled." : "Queue looks alive.")
                            .font(.caption)
                            .foregroundStyle(health.stalled ? AINewsTheme.accentRose : AINewsTheme.textMuted)
                        if let lastSuccessAt = health.lastSuccessAt {
                            Text("Last AI success: \(lastSuccessAt)")
                                .font(.caption2)
                                .foregroundStyle(AINewsTheme.textMuted)
                        }
                    }
                    .padding(16).aiNewsPanelStyle()
                }

                // Issues
                VStack(alignment: .leading, spacing: 8) {
                    Text("Issues (\(issues.count))").font(.headline).foregroundStyle(AINewsTheme.accentRose)
                    if issues.isEmpty {
                        Text("No errors or drops.").font(.caption).foregroundStyle(AINewsTheme.textMuted)
                    } else {
                        ForEach(Array(issues.prefix(30).enumerated()), id: \.offset) { _, e in
                            logRow(e)
                        }
                    }
                }
                .padding(16).aiNewsPanelStyle()

                // Full log
                VStack(alignment: .leading, spacing: 8) {
                    Text("Recent AI job log").font(.headline).foregroundStyle(AINewsTheme.textSecondary)
                    ForEach(Array((ops?.events ?? []).prefix(120).enumerated()), id: \.offset) { _, e in
                        logRow(e)
                    }
                }
                .padding(16).aiNewsPanelStyle()
            }
        }
        .task {
            while !Task.isCancelled {
                await reload()
                try? await Task.sleep(nanoseconds: 5_000_000_000)
            }
        }
    }

    private func metric(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.system(size: 20, weight: .bold)).foregroundStyle(AINewsTheme.textPrimary)
            Text(label).font(.caption2).foregroundStyle(AINewsTheme.textMuted)
        }
    }

    private func logRow(_ e: OpsAiJobEvent) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(e.stage.uppercased())
                .font(.caption2.weight(.bold))
                .foregroundStyle(stageColor(e.stage))
                .frame(width: 66, alignment: .leading)
            VStack(alignment: .leading, spacing: 1) {
                Text("\(e.kind ?? "?")\(e.reason.map { " · \($0)" } ?? "")")
                    .font(.caption).foregroundStyle(AINewsTheme.textPrimary)
                Text([e.isoTime, e.id].compactMap { $0 }.joined(separator: "  "))
                    .font(.caption2).foregroundStyle(AINewsTheme.textMuted).lineLimit(1)
            }
        }
    }

    private func reload() async {
        loading = true
        defer { loading = false }
        await state.refreshUsage()
        if let api = try? state.authorizedAPIClient() {
            ops = try? await api.fetchOpsAiJobs(limit: 150)
        }
    }
}

private struct WorkspaceView: View {
    @EnvironmentObject private var state: WidgetAppState
    @State private var tab = UserDefaults.standard.integer(forKey: "AINewsWorkspacePreferredTab")

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Workspace")
                    .font(AINewsTheme.font(28, weight: .bold))
                    .foregroundStyle(AINewsTheme.textPrimary)
                Spacer()
                Picker("Workspace", selection: $tab) {
                    Text("Library").tag(0)
                    Text("History").tag(1)
                    Text("Sources").tag(2)
                    Text("Automations").tag(3)
                    Text("Digests").tag(4)
                    Text("OPML").tag(5)
                    Text("Keywords").tag(6)
                    Text("Diagnostics").tag(7)
                    Text("Saved Views").tag(8)
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(width: 200)
                Button("Done") { state.showingWorkspace = false }
            }
            .padding(24)

            Group {
                switch tab {
                case 0:
                    LibraryWorkspaceTab()
                case 1:
                    HistoryWorkspaceTab()
                case 2:
                    SourcesWorkspaceTab()
                case 3:
                    AutomationsWorkspaceTab()
                case 4:
                    DigestsWorkspaceTab()
                case 5:
                    OpmlWorkspaceTab()
                case 6:
                    KeywordsWorkspaceTab()
                case 7:
                    DiagnosticsWorkspaceTab()
                default:
                    SavedWidgetViewsWorkspaceTab()
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
        .background(AINewsBackground())
        .onChange(of: tab) { _, newValue in
            UserDefaults.standard.set(newValue, forKey: "AINewsWorkspacePreferredTab")
        }
        .onReceive(NotificationCenter.default.publisher(for: .aiNewsOpenSavedViews)) { _ in
            tab = 8
        }
    }
}

private struct SavedWidgetViewsWorkspaceTab: View {
    @EnvironmentObject private var state: WidgetAppState
    @State private var views: [SavedWidgetView] = []
    @State private var captureName = ""

    private var availableTargets: [(id: Int, name: String, isFiltered: Bool)] {
        [(FilteredCategoryID, "Filtered Feed", true)] + state.categories.map { ($0.id, $0.name, false) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header(
                    title: "Saved widget views",
                    subtitle: "Capture, restore, and edit exact floating widget layouts: feed, position, width, and height."
                )

                VStack(alignment: .leading, spacing: 12) {
                    Text("Capture current open widgets")
                        .font(.headline)
                        .foregroundStyle(AINewsTheme.textSecondary)
                    HStack {
                        TextField("View name", text: $captureName)
                            .textFieldStyle(.roundedBorder)
                        Button("Save Current View") {
                            let name = captureName.trimmingCharacters(in: .whitespacesAndNewlines)
                            guard !name.isEmpty else { return }
                            NotificationCenter.default.post(
                                name: .aiNewsSaveCurrentWidgetView,
                                object: nil,
                                userInfo: ["name": name]
                            )
                            captureName = ""
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                                load()
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(AINewsTheme.accentCyan)
                    }
                    Button("Create Empty View") {
                        let name = captureName.trimmingCharacters(in: .whitespacesAndNewlines)
                        var view = SavedWidgetView(name: name.isEmpty ? "New widget view" : name, widgets: [])
                        view.widgets.append(defaultWidgetEntry())
                        SavedWidgetViewStore.upsert(view)
                        captureName = ""
                        load()
                    }
                    .buttonStyle(.bordered)
                }
                .padding(16)
                .aiNewsPanelStyle()

                if views.isEmpty {
                    Text("No saved views yet. Open one or more floating widgets, position them, then save the current view.")
                        .foregroundStyle(AINewsTheme.textMuted)
                        .padding(16)
                        .aiNewsPanelStyle()
                } else {
                    ForEach($views) { $view in
                        savedViewEditor(view: $view)
                    }
                }
            }
        }
        .task { load() }
        .onReceive(NotificationCenter.default.publisher(for: .aiNewsSavedWidgetViewsChanged)) { _ in
            load()
        }
    }

    private func savedViewEditor(view: Binding<SavedWidgetView>) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                TextField("View name", text: view.name)
                    .font(AINewsTheme.font(18, weight: .semibold))
                    .textFieldStyle(.roundedBorder)
                Spacer()
                Button("Apply") {
                    NotificationCenter.default.post(
                        name: .aiNewsApplySavedWidgetView,
                        object: nil,
                        userInfo: ["id": view.wrappedValue.id]
                    )
                }
                .buttonStyle(.borderedProminent)
                .tint(AINewsTheme.accentGold)
                Button("Save Changes") {
                    var updated = view.wrappedValue
                    updated.updatedAt = Date()
                    SavedWidgetViewStore.upsert(updated)
                    load()
                }
                .buttonStyle(.bordered)
                Button("Delete", role: .destructive) {
                    SavedWidgetViewStore.delete(id: view.wrappedValue.id)
                    load()
                }
                .buttonStyle(.bordered)
            }

            Text("\(view.wrappedValue.widgets.count) widget\(view.wrappedValue.widgets.count == 1 ? "" : "s")")
                .font(.caption)
                .foregroundStyle(AINewsTheme.textMuted)

            ForEach(view.widgets) { $entry in
                SavedWidgetEntryRow(
                    view: view,
                    entry: $entry,
                    availableTargets: availableTargets,
                    onRemove: {
                        view.wrappedValue.widgets.removeAll { $0.id == entry.id }
                    }
                )
            }

            Button("Add Widget") {
                view.wrappedValue.widgets.append(defaultWidgetEntry())
            }
            .buttonStyle(.bordered)
        }
        .padding(16)
        .aiNewsPanelStyle()
    }

    private func defaultWidgetEntry() -> SavedWidgetEntry {
        let target = availableTargets.first ?? (FilteredCategoryID, "Filtered Feed", true)
        return SavedWidgetEntry(
            categoryID: target.id,
            categoryName: target.name,
            isFiltered: target.isFiltered,
            frame: NSStringFromRect(NSRect(x: 120, y: 160, width: 430, height: 560))
        )
    }

    private func load() {
        views = SavedWidgetViewStore.load()
    }
}

private struct SavedWidgetEntryRow: View {
    @Binding var view: SavedWidgetView
    @Binding var entry: SavedWidgetEntry
    let availableTargets: [(id: Int, name: String, isFiltered: Bool)]
    let onRemove: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Picker("Feed", selection: Binding(
                    get: { entry.categoryID },
                    set: { newValue in
                        if let target = availableTargets.first(where: { $0.id == newValue }) {
                            entry.categoryID = target.id
                            entry.categoryName = target.name
                            entry.isFiltered = target.isFiltered
                            view.updatedAt = Date()
                        }
                    }
                )) {
                    ForEach(availableTargets, id: \.id) { target in
                        Text(target.name).tag(target.id)
                    }
                }
                .pickerStyle(.menu)
                Spacer()
                Button("Remove", role: .destructive, action: onRemove)
                    .buttonStyle(.bordered)
            }

            HStack {
                frameField("X", .x)
                frameField("Y", .y)
                frameField("W", .width)
                frameField("H", .height)
            }
        }
        .padding(12)
        .background(AINewsTheme.backgroundAlt.opacity(0.55))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(AINewsTheme.panelBorder.opacity(0.45), lineWidth: 1)
        )
    }

    private enum FrameField {
        case x, y, width, height
    }

    private func frameField(_ label: String, _ field: FrameField) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(AINewsTheme.textMuted)
            TextField(label, text: frameBinding(field))
                .textFieldStyle(.roundedBorder)
                .frame(width: 86)
        }
    }

    private func frameBinding(_ field: FrameField) -> Binding<String> {
        Binding(
            get: {
                let rect = NSRectFromString(entry.frame)
                let value: CGFloat
                switch field {
                case .x: value = rect.origin.x
                case .y: value = rect.origin.y
                case .width: value = rect.width
                case .height: value = rect.height
                }
                return String(format: "%.0f", value)
            },
            set: { rawValue in
                guard let number = Double(rawValue.trimmingCharacters(in: .whitespaces)) else { return }
                var rect = NSRectFromString(entry.frame)
                switch field {
                case .x: rect.origin.x = number
                case .y: rect.origin.y = number
                case .width: rect.size.width = max(260, number)
                case .height: rect.size.height = max(220, number)
                }
                entry.frame = NSStringFromRect(rect)
                view.updatedAt = Date()
            }
        )
    }
}

private struct AutomationsWorkspaceTab: View {
    @EnvironmentObject private var state: WidgetAppState
    @State private var rules: [FeatureRecord<AlertRulePayload>] = []
    @State private var schedules: [FeatureRecord<SchedulePayload>] = []
    @State private var ruleName = ""
    @State private var ruleKeywords = ""
    @State private var ruleWebhook = ""
    @State private var scheduleName = ""
    @State private var scheduleCadence = "daily"
    @State private var scheduleFormat = "executive"
    @State private var scheduleWebhook = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header(title: "Rules and schedules", subtitle: "Create keyword-driven alerts and recurring briefings with local history and Discord delivery.")

                VStack(alignment: .leading, spacing: 12) {
                    Text("Create alert rule")
                        .font(.headline)
                        .foregroundStyle(AINewsTheme.textPrimary)
                    TextField("Rule name", text: $ruleName)
                        .textFieldStyle(.roundedBorder)
                    TextField("Keywords, comma separated", text: $ruleKeywords)
                        .textFieldStyle(.roundedBorder)
                    TextField("Discord webhook (optional)", text: $ruleWebhook)
                        .textFieldStyle(.roundedBorder)
                    Button("Create rule") { Task { await createRule() } }
                        .buttonStyle(.borderedProminent)
                        .tint(AINewsTheme.accentBlue)
                        .disabled(ruleName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                .padding(16)
                .aiNewsPanelStyle()

                VStack(alignment: .leading, spacing: 12) {
                    Text("Create schedule")
                        .font(.headline)
                        .foregroundStyle(AINewsTheme.textPrimary)
                    TextField("Schedule name", text: $scheduleName)
                        .textFieldStyle(.roundedBorder)
                    HStack {
                        Picker("Cadence", selection: $scheduleCadence) {
                            Text("Hourly").tag("hourly")
                            Text("Daily").tag("daily")
                            Text("Weekly").tag("weekly")
                        }
                        Picker("Format", selection: $scheduleFormat) {
                            Text("Executive").tag("executive")
                            Text("Bullets").tag("bullets")
                            Text("Narrative").tag("narrative")
                        }
                    }
                    .pickerStyle(.segmented)
                    TextField("Discord webhook (optional)", text: $scheduleWebhook)
                        .textFieldStyle(.roundedBorder)
                    Button("Create schedule") { Task { await createSchedule() } }
                        .buttonStyle(.borderedProminent)
                        .tint(AINewsTheme.accentCyan)
                        .disabled(scheduleName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                .padding(16)
                .aiNewsPanelStyle()

                VStack(alignment: .leading, spacing: 12) {
                    Text("Alert rules")
                        .font(.headline)
                        .foregroundStyle(AINewsTheme.textSecondary)
                    ForEach(rules) { rule in
                        automationCard(
                            title: rule.title,
                            subtitle: rule.payload.keywords.joined(separator: ", "),
                            enabled: rule.payload.enabled,
                            footer: rule.payload.discordWebhookUrl.isEmpty ? "No Discord delivery" : "Discord delivery configured",
                            toggle: { enabled in await updateRule(rule, enabled: enabled) },
                            run: { await runRule(rule) }
                        )
                    }
                }

                VStack(alignment: .leading, spacing: 12) {
                    Text("Schedules")
                        .font(.headline)
                        .foregroundStyle(AINewsTheme.textSecondary)
                    ForEach(schedules) { schedule in
                        automationCard(
                            title: schedule.title,
                            subtitle: "\(schedule.payload.cadence.capitalized) • \(schedule.payload.format.capitalized)",
                            enabled: schedule.payload.enabled,
                            footer: schedule.payload.discordWebhookUrl.isEmpty ? "No Discord delivery" : "Discord delivery configured",
                            toggle: { enabled in await updateSchedule(schedule, enabled: enabled) },
                            run: { await runSchedule(schedule) }
                        )
                    }
                }
            }
        }
        .task { await reload() }
    }

    private func reload() async {
        do {
            let api = try state.authorizedAPIClient()
            rules = try await api.fetchRules()
            schedules = try await api.fetchSchedules()
        } catch {
            state.errorMessage = error.localizedDescription
        }
    }

    private func createRule() async {
        do {
            let api = try state.authorizedAPIClient()
            let created = try await api.createRule(AlertRulePayload(
                enabled: true,
                name: ruleName.trimmingCharacters(in: .whitespacesAndNewlines),
                keywords: ruleKeywords.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty },
                sources: [],
                moods: [],
                newsTypes: [],
                discordWebhookUrl: ruleWebhook.trimmingCharacters(in: .whitespacesAndNewlines),
                lastCheckedAtMs: 0
            ))
            rules.insert(created, at: 0)
            ruleName = ""
            ruleKeywords = ""
            ruleWebhook = ""
        } catch {
            state.errorMessage = error.localizedDescription
        }
    }

    private func createSchedule() async {
        do {
            let api = try state.authorizedAPIClient()
            let created = try await api.createSchedule(SchedulePayload(
                enabled: true,
                name: scheduleName.trimmingCharacters(in: .whitespacesAndNewlines),
                cadence: scheduleCadence,
                time: "08:00",
                feedUrls: state.runtimeConfig?.feeds.map(\.url) ?? [],
                format: scheduleFormat,
                discordWebhookUrl: scheduleWebhook.trimmingCharacters(in: .whitespacesAndNewlines),
                nextRunAtMs: 0,
                lastRunAtMs: 0
            ))
            schedules.insert(created, at: 0)
            scheduleName = ""
            scheduleCadence = "daily"
            scheduleFormat = "executive"
            scheduleWebhook = ""
        } catch {
            state.errorMessage = error.localizedDescription
        }
    }

    private func updateRule(_ rule: FeatureRecord<AlertRulePayload>, enabled: Bool) async {
        do {
            let api = try state.authorizedAPIClient()
            var payload = rule.payload
            payload.enabled = enabled
            let updated = try await api.updateRule(id: rule.id, payload: payload)
            if let index = rules.firstIndex(where: { $0.id == rule.id }) { rules[index] = updated }
        } catch {
            state.errorMessage = error.localizedDescription
        }
    }

    private func updateSchedule(_ schedule: FeatureRecord<SchedulePayload>, enabled: Bool) async {
        do {
            let api = try state.authorizedAPIClient()
            var payload = schedule.payload
            payload.enabled = enabled
            let updated = try await api.updateSchedule(id: schedule.id, payload: payload)
            if let index = schedules.firstIndex(where: { $0.id == schedule.id }) { schedules[index] = updated }
        } catch {
            state.errorMessage = error.localizedDescription
        }
    }

    private func runRule(_ rule: FeatureRecord<AlertRulePayload>) async {
        do {
            let api = try state.authorizedAPIClient()
            try await api.runRule(id: rule.id)
            state.statusMessage = "Ran \(rule.title)."
        } catch {
            state.errorMessage = error.localizedDescription
        }
    }

    private func runSchedule(_ schedule: FeatureRecord<SchedulePayload>) async {
        do {
            let api = try state.authorizedAPIClient()
            try await api.runSchedule(id: schedule.id)
            state.statusMessage = "Ran \(schedule.title)."
        } catch {
            state.errorMessage = error.localizedDescription
        }
    }
}

private struct DigestsWorkspaceTab: View {
    @EnvironmentObject private var state: WidgetAppState
    @State private var digests: [FeatureRecord<DigestPayload>] = []
    @State private var bodyDraft = ""
    @State private var format = "executive"
    @State private var webhook = ""
    @State private var sharedURL: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header(title: "Digest builder", subtitle: "Create manual digests from the current story list, send them to Discord later, or generate share links.")

                VStack(alignment: .leading, spacing: 12) {
                    Picker("Format", selection: $format) {
                        Text("Executive").tag("executive")
                        Text("Bullets").tag("bullets")
                        Text("Narrative").tag("narrative")
                    }
                    .pickerStyle(.segmented)

                    TextEditor(text: $bodyDraft)
                        .frame(minHeight: 180)
                        .padding(12)
                        .background(AINewsTheme.panel.opacity(0.7))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(AINewsTheme.panelBorder.opacity(0.45), lineWidth: 1)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                    TextField("Discord webhook (optional)", text: $webhook)
                        .textFieldStyle(.roundedBorder)

                    HStack {
                        Button("Use current stories") {
                            let lines = state.stories.prefix(10).enumerated().map { "\($0.offset + 1). \($0.element.title)" }
                            bodyDraft = lines.joined(separator: "\n")
                        }
                        .buttonStyle(.bordered)
                        Button("Create digest") { Task { await createDigest() } }
                            .buttonStyle(.borderedProminent)
                            .tint(AINewsTheme.accentBlue)
                            .disabled(bodyDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        Button("Export Markdown") { exportMarkdown() }
                            .buttonStyle(.bordered)
                    }

                    if let sharedURL {
                        Text(sharedURL)
                            .font(.caption)
                            .foregroundStyle(AINewsTheme.accentCyan)
                    }
                }
                .padding(16)
                .aiNewsPanelStyle()

                VStack(alignment: .leading, spacing: 12) {
                    Text("Saved digests")
                        .font(.headline)
                        .foregroundStyle(AINewsTheme.textSecondary)
                    ForEach(digests) { digest in
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Text(digest.title)
                                    .font(.headline)
                                    .foregroundStyle(AINewsTheme.textPrimary)
                                Spacer()
                                Button("Create share link") {
                                    Task { await share(digest) }
                                }
                                .buttonStyle(.bordered)
                            }
                            Text(digest.payload.body)
                                .foregroundStyle(AINewsTheme.textSecondary)
                                .lineLimit(4)
                        }
                        .padding(16)
                        .aiNewsPanelStyle()
                    }
                }
            }
        }
        .task { await reload() }
    }

    private func reload() async {
        do {
            let api = try state.authorizedAPIClient()
            digests = try await api.fetchDigests()
        } catch {
            state.errorMessage = error.localizedDescription
        }
    }

    private func createDigest() async {
        do {
            let api = try state.authorizedAPIClient()
            let created = try await api.createDigest(DigestPayload(
                storyIds: Array(state.stories.prefix(10).map(\.id)),
                feedUrls: Array(Set(state.stories.prefix(10).map(\.feedUrl))).sorted(),
                body: bodyDraft.trimmingCharacters(in: .whitespacesAndNewlines),
                format: format,
                discordWebhookUrl: webhook.trimmingCharacters(in: .whitespacesAndNewlines)
            ))
            digests.insert(created, at: 0)
            state.statusMessage = "Created digest."
        } catch {
            state.errorMessage = error.localizedDescription
        }
    }

    private func share(_ digest: FeatureRecord<DigestPayload>) async {
        do {
            let api = try state.authorizedAPIClient()
            let response = try await api.createShare(kind: "digest", title: digest.title, payload: [
                "storyIds": .array(digest.payload.storyIds.map(JSONValue.string)),
                "feedUrls": .array(digest.payload.feedUrls.map(JSONValue.string)),
                "body": .string(digest.payload.body),
                "format": .string(digest.payload.format),
                "discordWebhookUrl": .string(digest.payload.discordWebhookUrl)
            ])
            sharedURL = response.url.hasPrefix("http")
                ? response.url
                : "\(state.backendURLString)\(response.url)"
        } catch {
            state.errorMessage = error.localizedDescription
        }
    }

    private func exportMarkdown() {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("ai-news-digest.md")
        do {
            try bodyDraft.write(to: url, atomically: true, encoding: .utf8)
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } catch {
            state.errorMessage = error.localizedDescription
        }
    }
}

private func automationCard(
    title: String,
    subtitle: String,
    enabled: Bool,
    footer: String,
    toggle: @escaping (Bool) async -> Void,
    run: @escaping () async -> Void
) -> some View {
    VStack(alignment: .leading, spacing: 10) {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(AINewsTheme.textPrimary)
                Text(subtitle)
                    .foregroundStyle(AINewsTheme.textSecondary)
            }
            Spacer()
            Toggle("Enabled", isOn: Binding(
                get: { enabled },
                set: { value in Task { await toggle(value) } }
            ))
            .toggleStyle(.switch)
            .labelsHidden()
        }
        Text(footer)
            .font(.caption)
            .foregroundStyle(AINewsTheme.textMuted)
        Button("Run now") { Task { await run() } }
            .buttonStyle(.bordered)
    }
    .padding(16)
    .aiNewsPanelStyle()
}

private struct LibraryWorkspaceTab: View {
    @EnvironmentObject private var state: WidgetAppState
    @State private var items: [FeatureRecord<SavedStoryPayload>] = []
    @State private var loading = false
    @State private var noteDrafts: [Int: String] = [:]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header(title: "Saved stories", subtitle: "Stories you pinned for later reading, notes, and follow-up.")

            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(items) { item in
                        VStack(alignment: .leading, spacing: 12) {
                            HStack(alignment: .top) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(item.payload.title)
                                        .font(.headline)
                                        .foregroundStyle(AINewsTheme.textPrimary)
                                    Text(item.payload.source ?? item.payload.feedUrl)
                                        .font(.caption)
                                        .foregroundStyle(AINewsTheme.textMuted)
                                }
                                Spacer()
                                Toggle("Read", isOn: Binding(
                                    get: { item.payload.read },
                                    set: { value in
                                        Task { await update(item, mutate: { $0.read = value }) }
                                    }
                                ))
                                .toggleStyle(.switch)
                                .labelsHidden()
                            }

                            TextField("Add a note", text: Binding(
                                get: { noteDrafts[item.id] ?? item.payload.note },
                                set: { noteDrafts[item.id] = $0 }
                            ))
                            .textFieldStyle(.roundedBorder)

                            HStack {
                                Button("Save note") {
                                    Task {
                                        await update(item, mutate: { $0.note = noteDrafts[item.id] ?? item.payload.note })
                                    }
                                }
                                .buttonStyle(.bordered)
                                if let link = item.payload.link, let url = URL(string: link) {
                                    Button("Open source") { NSWorkspace.shared.open(url) }
                                        .buttonStyle(.bordered)
                                }
                                Spacer()
                                Button("Remove", role: .destructive) {
                                    Task { await remove(item) }
                                }
                                .buttonStyle(.bordered)
                            }
                        }
                        .padding(16)
                        .aiNewsPanelStyle()
                    }
                }
            }
        }
        .task { await reload() }
    }

    private func reload() async {
        loading = true
        defer { loading = false }
        do {
            let api = try state.authorizedAPIClient()
            items = try await api.fetchLibrary()
            noteDrafts = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0.payload.note) })
        } catch {
            state.errorMessage = error.localizedDescription
        }
    }

    private func update(_ item: FeatureRecord<SavedStoryPayload>, mutate: (inout SavedStoryPayload) -> Void) async {
        do {
            let api = try state.authorizedAPIClient()
            var payload = item.payload
            mutate(&payload)
            let updated = try await api.updateSavedStory(id: item.id, payload: payload)
            if let index = items.firstIndex(where: { $0.id == item.id }) {
                items[index] = updated
            }
        } catch {
            state.errorMessage = error.localizedDescription
        }
    }

    private func remove(_ item: FeatureRecord<SavedStoryPayload>) async {
        do {
            let api = try state.authorizedAPIClient()
            try await api.deleteSavedStory(id: item.id)
            items.removeAll { $0.id == item.id }
        } catch {
            state.errorMessage = error.localizedDescription
        }
    }
}

private struct HistoryWorkspaceTab: View {
    @EnvironmentObject private var state: WidgetAppState
    @State private var history: HistoryResponse?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header(title: "Feed and delivery history", subtitle: "See fetched items, queued AI actions, and why something was or was not sent.")

            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(history?.items ?? []) { item in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text(item.stage.replacingOccurrences(of: "_", with: " ").capitalized)
                                    .font(.headline)
                                    .foregroundStyle(AINewsTheme.textPrimary)
                                Spacer()
                                Text(item.status.capitalized)
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(item.status == "failed" ? AINewsTheme.accentRose : AINewsTheme.accentCyan)
                            }
                            if let title = item.title, !title.isEmpty {
                                Text(title)
                                    .foregroundStyle(AINewsTheme.textPrimary)
                            }
                            if let reason = item.reason, !reason.isEmpty {
                                Text(reason)
                                    .foregroundStyle(AINewsTheme.textSecondary)
                            }
                            if let details = item.details, !details.isEmpty {
                                Text(details.map { "\($0.key): \($0.value.stringValue)" }.sorted().joined(separator: " • "))
                                    .font(.caption)
                                    .foregroundStyle(AINewsTheme.textMuted)
                            }
                        }
                        .padding(16)
                        .aiNewsPanelStyle()
                    }

                    if let fetched = history?.fetched, !fetched.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Recently fetched")
                                .font(.headline)
                                .foregroundStyle(AINewsTheme.textSecondary)
                            ForEach(fetched) { item in
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(item.title ?? item.itemId)
                                        .foregroundStyle(AINewsTheme.textPrimary)
                                    Text(item.source ?? item.feedUrl)
                                        .font(.caption)
                                        .foregroundStyle(AINewsTheme.textMuted)
                                }
                                .padding(.vertical, 6)
                            }
                        }
                        .padding(16)
                        .aiNewsPanelStyle()
                    }
                }
            }
        }
        .task { await reload() }
    }

    private func reload() async {
        do {
            let api = try state.authorizedAPIClient()
            history = try await api.fetchHistory()
        } catch {
            state.errorMessage = error.localizedDescription
        }
    }
}

private struct SourcesWorkspaceTab: View {
    @EnvironmentObject private var state: WidgetAppState
    @State private var sources: [SourceProfile] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header(title: "Source profiles", subtitle: "Watch source activity, latest story, Discord state, and the mood/type mix.")

            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(sources) { source in
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(source.label)
                                        .font(.headline)
                                        .foregroundStyle(AINewsTheme.textPrimary)
                                    Text(source.url)
                                        .font(.caption)
                                        .foregroundStyle(AINewsTheme.textMuted)
                                        .lineLimit(1)
                                }
                                Spacer()
                                Text(source.discordEnabled ? "Discord on" : "Discord off")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(source.discordEnabled ? AINewsTheme.accentCyan : AINewsTheme.textMuted)
                            }
                            Text("Recent stories: \(source.recentCount)")
                                .foregroundStyle(AINewsTheme.textSecondary)
                            if let latest = source.latest {
                                Text(latest.title)
                                    .foregroundStyle(AINewsTheme.textPrimary)
                            }
                            if !source.moods.isEmpty {
                                Text("Moods: \(source.moods.map { "\($0.key) \($0.value)" }.sorted().joined(separator: " • "))")
                                    .font(.caption)
                                    .foregroundStyle(AINewsTheme.textMuted)
                            }
                            if !source.newsTypes.isEmpty {
                                Text("Types: \(source.newsTypes.map { "\($0.key) \($0.value)" }.sorted().joined(separator: " • "))")
                                    .font(.caption)
                                    .foregroundStyle(AINewsTheme.textMuted)
                            }
                        }
                        .padding(16)
                        .aiNewsPanelStyle()
                    }
                }
            }
        }
        .task { await reload() }
    }

    private func reload() async {
        do {
            let api = try state.authorizedAPIClient()
            sources = try await api.fetchSources()
        } catch {
            state.errorMessage = error.localizedDescription
        }
    }
}

private struct OpmlWorkspaceTab: View {
    @EnvironmentObject private var state: WidgetAppState
    @State private var opml = ""
    @State private var preview: [OpmlFeed] = []
    @State private var exportedFileURL: URL?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header(title: "Import and export feeds", subtitle: "Paste OPML to preview and import, or export the current feed set.")

            TextEditor(text: $opml)
                .font(.system(.body, design: .monospaced))
                .frame(minHeight: 180)
                .padding(12)
                .background(AINewsTheme.panel.opacity(0.7))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(AINewsTheme.panelBorder.opacity(0.45), lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

            HStack {
                Button("Preview OPML") { Task { await doPreview() } }
                    .buttonStyle(.bordered)
                Button("Import feeds") { Task { await doImport() } }
                    .buttonStyle(.borderedProminent)
                    .tint(AINewsTheme.accentBlue)
                Button("Export current feeds") { Task { await doExport() } }
                    .buttonStyle(.bordered)
            }

            if !preview.isEmpty {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(preview) { feed in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(feed.title)
                                    .foregroundStyle(AINewsTheme.textPrimary)
                                Text(feed.xmlUrl)
                                    .font(.caption)
                                    .foregroundStyle(AINewsTheme.textMuted)
                            }
                            .padding(14)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .aiNewsPanelStyle()
                        }
                    }
                }
            }
        }
    }

    private func doPreview() async {
        do {
            let api = try state.authorizedAPIClient()
            preview = try await api.previewOpml(opml)
        } catch {
            state.errorMessage = error.localizedDescription
        }
    }

    private func doImport() async {
        do {
            let api = try state.authorizedAPIClient()
            let result = try await api.importOpml(opml)
            preview = result.feeds
            state.statusMessage = "Imported \(result.added) feeds."
            await state.reloadEverything(selectFirstCategory: state.selectedCategoryID == nil)
        } catch {
            state.errorMessage = error.localizedDescription
        }
    }

    private func doExport() async {
        do {
            let api = try state.authorizedAPIClient()
            let xml = try await api.exportOpml()
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("ai-news-feeds.opml")
            try xml.write(to: url, atomically: true, encoding: .utf8)
            exportedFileURL = url
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } catch {
            state.errorMessage = error.localizedDescription
        }
    }
}

private func formatTokens(_ n: Int) -> String {
    if n >= 1_000_000 { return String(format: "%.1fM", Double(n) / 1_000_000) }
    if n >= 1_000 { return String(format: "%.1fk", Double(n) / 1_000) }
    return "\(n)"
}

private func header(title: String, subtitle: String) -> some View {
    VStack(alignment: .leading, spacing: 6) {
        Text(title)
            .font(AINewsTheme.font(24, weight: .bold))
            .foregroundStyle(AINewsTheme.textPrimary)
        Text(subtitle)
            .foregroundStyle(AINewsTheme.textSecondary)
    }
}

private struct SettingsView: View {
    @EnvironmentObject private var state: WidgetAppState
    @EnvironmentObject private var theme: ThemeSettings
    @AppStorage("ai_news_show_thumbnails") private var showThumbnails = true
    @State private var regionDraft = ""
    @State private var topicsDraft = ""
    @State private var newCategoryName = ""
    @State private var newCategoryDescription = ""
    @State private var newCategoryFeedURLs = Set<String>()
    @State private var editingCategoryID: Int?

    private var appearancePanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Appearance")
                .font(.headline)
                .foregroundStyle(AINewsTheme.textSecondary)
            Picker("Theme", selection: Binding(
                get: { theme.vibe },
                set: { theme.vibe = $0 }
            )) {
                ForEach(AINewsVibe.allCases, id: \.self) { vibe in
                    Text(vibe.displayName).tag(vibe)
                }
            }
            .pickerStyle(.menu)
            Picker("App text size", selection: Binding(
                get: { theme.appFontSize },
                set: { theme.appFontSize = $0 }
            )) {
                ForEach(AINewsFontSize.allCases, id: \.self) { size in
                    Text(size.displayName).tag(size)
                }
            }
            .pickerStyle(.segmented)
            Picker("Widget text size", selection: Binding(
                get: { theme.widgetFontSize },
                set: { theme.widgetFontSize = $0 }
            )) {
                ForEach(AINewsFontSize.allCases, id: \.self) { size in
                    Text(size.displayName).tag(size)
                }
            }
            .pickerStyle(.segmented)
            Picker("Widget background", selection: Binding(
                get: { theme.widgetBackgroundMode },
                set: { theme.widgetBackgroundMode = $0 }
            )) {
                ForEach(AINewsWidgetBackgroundMode.allCases, id: \.self) { mode in
                    Text(mode.displayName).tag(mode)
                }
            }
            .pickerStyle(.segmented)
        }
        .padding(16)
        .aiNewsPanelStyle()
    }

    private var personalizationPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Personalization")
                .font(.headline)
                .foregroundStyle(AINewsTheme.textSecondary)
            Text("Region and tracked topics steer AI research and relevance.")
                .font(.caption)
                .foregroundStyle(AINewsTheme.textMuted)
            TextField("Region (e.g. Bulgaria)", text: $regionDraft)
                .textFieldStyle(.roundedBorder)
            TextField("Tracked topics, comma separated", text: $topicsDraft)
                .textFieldStyle(.roundedBorder)
            Button("Save personalization") {
                Task { await savePreferences() }
            }
            .buttonStyle(.borderedProminent)
            .tint(AINewsTheme.accentBlue)
        }
        .padding(16)
        .aiNewsPanelStyle()
        .task { await loadPreferences() }
        .task {
            // Keep per-feed AI progress bars current while Settings is open.
            while !Task.isCancelled {
                await state.refreshAiProgress()
                try? await Task.sleep(nanoseconds: 6_000_000_000)
            }
        }
    }

    private func loadPreferences() async {
        guard regionDraft.isEmpty, topicsDraft.isEmpty else { return }
        if let api = try? state.authorizedAPIClient(), let prefs = try? await api.fetchPreferences() {
            regionDraft = prefs.region
            topicsDraft = prefs.topics.joined(separator: ", ")
        }
    }

    private func savePreferences() async {
        do {
            let api = try state.authorizedAPIClient()
            let topics = topicsDraft.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            try await api.savePreferences(region: regionDraft.trimmingCharacters(in: .whitespaces), topics: topics)
            state.statusMessage = "Saved personalization."
        } catch {
            state.errorMessage = error.localizedDescription
        }
    }

    static let providerOptions = ["openai", "claude", "openrouter", "local"]

    // Curated model suggestions per provider, mirroring the backend defaults in
    // server.ts (modelOptionsByProvider). Free text is still allowed via the field.
    private struct ModelSuggestions {
        var summary: [String]
        var research: [String]
        var ask: [String]
    }

    private static let modelOptionsByProvider: [String: ModelSuggestions] = [
        "openai": ModelSuggestions(
            summary: ["gpt-4.1-nano", "gpt-4.1-mini", "gpt-4o-mini", "gpt-4.1"],
            research: ["gpt-4.1-mini", "gpt-4.1", "gpt-4o-mini"],
            ask: ["gpt-4.1-nano", "gpt-4.1-mini", "gpt-4o-mini"]
        ),
        "claude": ModelSuggestions(
            summary: ["claude-3-5-haiku-latest", "claude-3-7-sonnet-latest"],
            research: ["claude-3-7-sonnet-latest", "claude-3-5-haiku-latest"],
            ask: ["claude-3-5-haiku-latest", "claude-3-7-sonnet-latest"]
        ),
        "openrouter": ModelSuggestions(
            summary: ["openai/gpt-4.1-mini", "openai/gpt-4.1", "anthropic/claude-3.5-haiku"],
            research: ["openai/gpt-4.1", "openai/gpt-4.1-mini", "anthropic/claude-3.7-sonnet"],
            ask: ["openai/gpt-4.1-mini", "openai/gpt-4.1-nano", "anthropic/claude-3.5-haiku"]
        )
    ]

    private func modelSuggestions(for kind: KeyPath<ModelSuggestions, [String]>) -> [String] {
        let provider = (state.accountSettings.aiProvider ?? state.runtimeConfig?.aiProvider ?? "openai")
            .lowercased()
        return SettingsView.modelOptionsByProvider[provider]?[keyPath: kind] ?? []
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
            HStack {
                Text("AI & Widget Settings")
                    .font(AINewsTheme.font(28, weight: .bold))
                    .foregroundStyle(AINewsTheme.textPrimary)
                Spacer()
                Button("Done") {
                    state.showingSettings = false
                }
            }

            appearancePanel

            personalizationPanel

            if let runtimeConfig = state.runtimeConfig {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Runtime")
                        .font(.headline)
                        .foregroundStyle(AINewsTheme.textSecondary)
                    Text("Provider: \(runtimeConfig.aiProvider.uppercased())")
                    Text("Summary model: \(runtimeConfig.summaryModel)")
                    Text("Research model: \(runtimeConfig.researchModel)")
                    Text("Ask model: \(runtimeConfig.askModel)")
                }
                .foregroundStyle(AINewsTheme.textPrimary)

                VStack(alignment: .leading, spacing: 12) {
                    Text("Global AI settings")
                        .font(.headline)
                        .foregroundStyle(AINewsTheme.textSecondary)
                    Text("Baseline for every feed. Per-feed and per-category settings below override this.")
                        .font(.caption)
                        .foregroundStyle(AINewsTheme.textMuted)
                    HStack(spacing: 14) {
                        Toggle("Summary", isOn: $state.globalAiDefaults.summaryEnabled)
                        Toggle("Translation", isOn: $state.globalAiDefaults.translationEnabled)
                        Toggle("Research", isOn: $state.globalAiDefaults.researchEnabled)
                    }
                    .toggleStyle(.switch)
                    Button("Apply to all feeds") {
                        Task { await state.saveGlobalAiDefaults() }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(AINewsTheme.accentBlue)
                }
                .padding(16)
                .aiNewsPanelStyle()

                VStack(alignment: .leading, spacing: 12) {
                    Text("Feed AI controls")
                        .font(.headline)
                        .foregroundStyle(AINewsTheme.textSecondary)

                    ScrollView {
                        LazyVStack(spacing: 12) {
                            ForEach(runtimeConfig.feeds, id: \.url) { feed in
                                FeedSettingsCard(feed: feed)
                            }
                        }
                    }
                    .frame(minHeight: 180, maxHeight: 260)
                }
            }

            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Widget categories")
                        .font(.headline)
                        .foregroundStyle(AINewsTheme.textSecondary)
                    Spacer()
                    Button("Show all") {
                        Task { await state.setAllCategoryVisibility(hidden: false) }
                    }
                    .buttonStyle(.bordered)
                    Button("Hide all") {
                        Task { await state.setAllCategoryVisibility(hidden: true) }
                    }
                    .buttonStyle(.bordered)
                    Button("Reset all") {
                        Task { await state.setAllCategoryCounts(expanded: false) }
                    }
                    .buttonStyle(.bordered)
                    Button("Expand all") {
                        Task { await state.setAllCategoryCounts(expanded: true) }
                    }
                    .buttonStyle(.bordered)
                    Button("Refresh visible") {
                        Task { await state.refreshVisibleCategories() }
                    }
                    .buttonStyle(.bordered)
                }

                createCategoryPanel

                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(state.categories) { category in
                            categoryManagementRow(category)
                        }
                    }
                }
                .frame(minHeight: 160, maxHeight: 240)
            }

            VStack(alignment: .leading, spacing: 12) {
                Text("Local account settings")
                    .font(.headline)
                    .foregroundStyle(AINewsTheme.textSecondary)

                EditableComboField(
                    placeholder: "Preferred provider",
                    value: Binding(
                        get: { state.accountSettings.aiProvider ?? "" },
                        set: { state.accountSettings.aiProvider = $0.isEmpty ? nil : $0 }
                    ),
                    suggestions: SettingsView.providerOptions
                )

                EditableComboField(
                    placeholder: "Summary model",
                    value: Binding(
                        get: { state.accountSettings.summaryModel ?? "" },
                        set: { state.accountSettings.summaryModel = $0.isEmpty ? nil : $0 }
                    ),
                    suggestions: modelSuggestions(for: \.summary)
                )

                EditableComboField(
                    placeholder: "Research model",
                    value: Binding(
                        get: { state.accountSettings.researchModel ?? "" },
                        set: { state.accountSettings.researchModel = $0.isEmpty ? nil : $0 }
                    ),
                    suggestions: modelSuggestions(for: \.research)
                )

                EditableComboField(
                    placeholder: "Ask model",
                    value: Binding(
                        get: { state.accountSettings.askModel ?? "" },
                        set: { state.accountSettings.askModel = $0.isEmpty ? nil : $0 }
                    ),
                    suggestions: modelSuggestions(for: \.ask)
                )

                Toggle("Show cover thumbnails on stories", isOn: $showThumbnails)

                Button("Save settings") {
                    Task { await state.saveSettings() }
                }
                .buttonStyle(.borderedProminent)
                .tint(AINewsTheme.accentBlue)
            }

            VStack(alignment: .leading, spacing: 12) {
                Text("Provider key")
                    .font(.headline)
                    .foregroundStyle(AINewsTheme.textSecondary)

                SecureField("Provider API key", text: $state.providerKeyDraft)
                    .textFieldStyle(.roundedBorder)

                HStack {
                    Button("Save key") {
                        Task { await state.saveProviderKey() }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(AINewsTheme.accentCyan)

                    if let provider = state.runtimeConfig?.aiProvider {
                        Text(state.providerKeyStatus[provider] == true ? "Saved for \(provider.uppercased())" : "No saved key")
                            .foregroundStyle(AINewsTheme.textMuted)
                    }
                }
            }

            if let usage = state.usage {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("AI usage")
                            .font(.headline)
                            .foregroundStyle(AINewsTheme.textSecondary)
                        Spacer()
                        Button("Refresh") { Task { await state.refreshUsage() } }
                        Button("Export JSON") { Task { await state.exportUsageJSON() } }
                        Button("Export CSV") { Task { await state.exportUsageCSV() } }
                        Button("Reset usage") { Task { await state.resetUsage() } }
                    }

                    HStack(spacing: 20) {
                        usageBadge("Input", value: usage.inputTokens)
                        usageBadge("Output", value: usage.outputTokens)
                        usageBadge("Total", value: usage.totalTokens)
                    }

                    ForEach(Array(usage.byKind.keys.sorted()), id: \.self) { key in
                        if let stats = usage.byKind[key] {
                            Text("\(key): \(stats.requests) requests • \(stats.totalTokens) tokens")
                                .foregroundStyle(AINewsTheme.textPrimary)
                        }
                    }

                    if !usage.recent.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Recent requests")
                                .font(.headline)
                                .foregroundStyle(AINewsTheme.textSecondary)

                            ForEach(Array(usage.recent.prefix(8))) { item in
                                HStack(alignment: .top) {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(item.label)
                                            .foregroundStyle(AINewsTheme.textPrimary)
                                        Text("\(item.kind) • \(item.model)")
                                            .font(.caption)
                                            .foregroundStyle(AINewsTheme.textMuted)
                                    }
                                    Spacer()
                                    VStack(alignment: .trailing, spacing: 4) {
                                        Text("\(item.totalTokens) tokens")
                                            .foregroundStyle(AINewsTheme.accentCyan)
                                        Text(Date(timeIntervalSince1970: TimeInterval(item.createdAt) / 1000).formatted(date: .omitted, time: .shortened))
                                            .font(.caption)
                                            .foregroundStyle(AINewsTheme.textMuted)
                                    }
                                }
                                .padding(.vertical, 6)
                                if item.id != usage.recent.prefix(8).last?.id {
                                    Divider()
                                        .overlay(AINewsTheme.panelBorder.opacity(0.4))
                                }
                            }
                        }
                        .padding(16)
                        .aiNewsPanelStyle()
                    }
                }
            }

            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .padding(28)
        .background(AINewsBackground())
    }

    private func usageBadge(_ title: String, value: Int) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased())
                .font(.caption)
                .foregroundStyle(AINewsTheme.textMuted)
            Text(value.formatted())
                .font(.title2.bold())
                .foregroundStyle(AINewsTheme.textPrimary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .aiNewsPanelStyle()
    }

    private var availableFeedURLs: [String] {
        state.runtimeConfig?.feeds.map(\.url) ?? []
    }

    private func feedLabel(for url: String) -> String {
        state.runtimeConfig?.feeds.first(where: { $0.url == url })?.label ?? url
    }

    private var createCategoryPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Create category")
                .font(.headline)
                .foregroundStyle(AINewsTheme.textPrimary)

            TextField("Category name", text: $newCategoryName)
                .textFieldStyle(.roundedBorder)

            TextField("Description", text: $newCategoryDescription)
                .textFieldStyle(.roundedBorder)

            feedMembershipEditor(selection: $newCategoryFeedURLs)

            HStack {
                Button("Create category") {
                    let selectedFeeds = availableFeedURLs.filter { newCategoryFeedURLs.contains($0) }
                    Task {
                        await state.createCategory(
                            name: newCategoryName.trimmingCharacters(in: .whitespacesAndNewlines),
                            description: newCategoryDescription.trimmingCharacters(in: .whitespacesAndNewlines),
                            feedUrls: selectedFeeds
                        )
                        newCategoryName = ""
                        newCategoryDescription = ""
                        newCategoryFeedURLs = []
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(AINewsTheme.accentBlue)
                .disabled(newCategoryName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || newCategoryFeedURLs.isEmpty)

                Text("\(newCategoryFeedURLs.count) feeds selected")
                    .font(.caption)
                    .foregroundStyle(AINewsTheme.textMuted)
            }
        }
        .padding(16)
        .aiNewsPanelStyle()
    }

    private func categoryManagementRow(_ category: WidgetCategory) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            let feedSelection = Binding<Set<String>>(
                get: { Set(category.feedUrls) },
                set: { updated in
                    var next = category
                    next.feedUrls = availableFeedURLs.filter { updated.contains($0) }
                    Task { await state.saveCategory(next) }
                }
            )

            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 4) {
                    if editingCategoryID == category.id {
                        TextField("Category name", text: Binding(
                            get: { category.name },
                            set: { value in
                                var next = category
                                next.name = value
                                Task { await state.saveCategory(next) }
                            }
                        ))
                        .textFieldStyle(.roundedBorder)

                        TextField("Description", text: Binding(
                            get: { category.description },
                            set: { value in
                                var next = category
                                next.description = value
                                Task { await state.saveCategory(next) }
                            }
                        ))
                        .textFieldStyle(.roundedBorder)
                    } else {
                        Text(category.name)
                            .font(.headline)
                            .foregroundStyle(AINewsTheme.textPrimary)
                        Text(category.hidden ? "Hidden from widgets" : "\(category.activeCount)-story widget view")
                            .font(.caption)
                            .foregroundStyle(AINewsTheme.textMuted)
                    }
                }
                Spacer()
                Button(editingCategoryID == category.id ? "Done" : "Edit") {
                    editingCategoryID = editingCategoryID == category.id ? nil : category.id
                }
                .buttonStyle(.bordered)
                Button {
                    Task { await state.moveCategory(category, direction: -1) }
                } label: {
                    Image(systemName: "arrow.up")
                }
                .buttonStyle(.bordered)
                Button {
                    Task { await state.moveCategory(category, direction: 1) }
                } label: {
                    Image(systemName: "arrow.down")
                }
                .buttonStyle(.bordered)
                Button(category.hidden ? "Show" : "Hide") {
                    Task { await state.toggleVisibility(for: category) }
                }
                .buttonStyle(.bordered)
                Button("Share") {
                    Task { await shareCategory(category) }
                }
                .buttonStyle(.bordered)
                Button("Remove", role: .destructive) {
                    Task { await state.archiveCategory(category) }
                }
                .buttonStyle(.bordered)
            }

            if editingCategoryID == category.id {
                feedMembershipEditor(selection: feedSelection)
            }

            HStack(spacing: 10) {
                Button("Reset 5") {
                    Task {
                        await state.selectCategory(category)
                        await state.resetSelectedCategory()
                    }
                }
                .buttonStyle(.bordered)

                Button("Expand 10") {
                    Task {
                        await state.selectCategory(category)
                        await state.expandSelectedCategory()
                    }
                }
                .buttonStyle(.bordered)

                Button("Refresh") {
                    Task {
                        await state.selectCategory(category)
                        await state.refreshSelectedCategory(recordCommand: false)
                    }
                }
                .buttonStyle(.bordered)
            }

            CategoryAiControls(category: category)
        }
        .padding(16)
        .aiNewsPanelStyle()
    }

    private func feedMembershipEditor(selection: Binding<Set<String>>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Feeds")
                .font(.caption.weight(.semibold))
                .foregroundStyle(AINewsTheme.textMuted)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 180), spacing: 10)], spacing: 10) {
                ForEach(availableFeedURLs, id: \.self) { feedURL in
                    Toggle(isOn: Binding(
                        get: { selection.wrappedValue.contains(feedURL) },
                        set: { enabled in
                            var next = selection.wrappedValue
                            if enabled {
                                next.insert(feedURL)
                            } else {
                                next.remove(feedURL)
                            }
                            selection.wrappedValue = next
                        }
                    )) {
                        Text(feedLabel(for: feedURL))
                            .font(.caption)
                            .foregroundStyle(AINewsTheme.textPrimary)
                    }
                    .toggleStyle(.checkbox)
                }
            }
        }
    }

    private func shareCategory(_ category: WidgetCategory) async {
        do {
            let api = try state.authorizedAPIClient()
            let response = try await api.createShare(kind: "collection", title: category.name, payload: [
                "name": .string(category.name),
                "description": .string(category.description),
                "feedUrls": .array(category.feedUrls.map(JSONValue.string)),
                "storyIds": .array(category.storyIds.map(JSONValue.string)),
                "tags": .array(category.tags.map(JSONValue.string))
            ])
            let shareURL = response.url.hasPrefix("http") ? response.url : "\(state.backendURLString)\(response.url)"
            copyTextToPasteboard(shareURL)
            state.statusMessage = "Copied category share link."
        } catch {
            state.errorMessage = error.localizedDescription
        }
    }
}

/// A text field that also offers a dropdown of suggested values.
/// Users can pick a suggestion or type any custom value (free text).
private struct EditableComboField: View {
    let placeholder: String
    @Binding var value: String
    let suggestions: [String]

    var body: some View {
        HStack(spacing: 6) {
            TextField(placeholder, text: $value)
                .textFieldStyle(.roundedBorder)

            if !suggestions.isEmpty {
                Menu {
                    ForEach(suggestions, id: \.self) { option in
                        Button {
                            value = option
                        } label: {
                            if option == value {
                                Label(option, systemImage: "checkmark")
                            } else {
                                Text(option)
                            }
                        }
                    }
                } label: {
                    Image(systemName: "list.bullet")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(AINewsTheme.textSecondary)
                        .frame(width: 16, height: 16)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .frame(width: 24)
                .help("Choose a suggested value")
            }
        }
    }
}

private struct CategoryAiControls: View {
    @EnvironmentObject private var state: WidgetAppState
    let category: WidgetCategory
    @State private var settings = GlobalAiDefaults()
    @State private var expanded = false

    private var feedCount: Int { category.feedUrls.count }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                expanded.toggle()
            } label: {
                Label("Category AI settings", systemImage: expanded ? "chevron.down" : "chevron.right")
                    .font(.caption.weight(.semibold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(AINewsTheme.textMuted)

            if expanded {
                Text("Applies these toggles to all \(feedCount) feed\(feedCount == 1 ? "" : "s") in this category (overrides the global defaults).")
                    .font(.caption)
                    .foregroundStyle(AINewsTheme.textMuted)
                Toggle("Summaries", isOn: $settings.summaryEnabled)
                Toggle("Research", isOn: $settings.researchEnabled)
                Toggle("Translations", isOn: $settings.translationEnabled)
                Button("Apply to \(feedCount) feed\(feedCount == 1 ? "" : "s")") {
                    Task { await state.applyAiSettings(to: category, settings: settings) }
                }
                .buttonStyle(.borderedProminent)
                .tint(AINewsTheme.accentCyan)
                .disabled(feedCount == 0)
            }
        }
        .onAppear { settings = state.globalAiDefaults }
    }
}

private struct FeedQuickControlCard: View {
    @EnvironmentObject private var state: WidgetAppState
    let feed: RuntimeFeed

    private var fetchLabel: String {
        feed.settings.pollingEnabled ? "Fetching" : "Fetch off"
    }

    private var aiLabel: String {
        feed.settings.aiEnabled ? "AI on" : "AI paused"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(feed.label)
                .font(.headline)
                .foregroundStyle(AINewsTheme.textPrimary)
                .lineLimit(1)
            Text(feed.url)
                .font(.caption2)
                .foregroundStyle(AINewsTheme.textMuted)
                .lineLimit(1)

            HStack(spacing: 8) {
                statusPill(fetchLabel, active: feed.settings.pollingEnabled, accent: AINewsTheme.accentBlue)
                statusPill(aiLabel, active: feed.settings.aiEnabled, accent: AINewsTheme.accentGold)
            }

            if let progress = state.aiProgress[feed.url], progress.total > 0 || progress.blocked > 0 {
                Text(progress.pending > 0
                     ? "\(progress.pending) pending · \(progress.done)/\(progress.total) ready"
                     : "\(progress.done)/\(progress.total) ready")
                    .font(.caption2)
                    .foregroundStyle(AINewsTheme.textMuted)
            }

            HStack(spacing: 8) {
                Button(feed.settings.pollingEnabled || feed.settings.aiEnabled ? "Turn off" : "Resume") {
                    Task {
                        await state.setFeedOperationalState(
                            feedURL: feed.url,
                            pollingEnabled: !(feed.settings.pollingEnabled || feed.settings.aiEnabled),
                            aiEnabled: !(feed.settings.pollingEnabled || feed.settings.aiEnabled)
                        )
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(feed.settings.pollingEnabled || feed.settings.aiEnabled ? AINewsTheme.accentRose : AINewsTheme.accentBlue)

                Button(feed.settings.aiEnabled ? "Pause AI" : "Resume AI") {
                    Task { await state.setFeedAiEnabled(feedURL: feed.url, enabled: !feed.settings.aiEnabled) }
                }
                .buttonStyle(.bordered)
            }
        }
        .frame(width: 260, alignment: .leading)
        .padding(16)
        .aiNewsPanelStyle()
    }

    @ViewBuilder
    private func statusPill(_ title: String, active: Bool, accent: Color) -> some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(active ? accent : AINewsTheme.textMuted)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                Capsule()
                    .fill((active ? accent : Color.white.opacity(0.18)).opacity(0.16))
            )
            .overlay(
                Capsule()
                    .stroke((active ? accent : Color.white.opacity(0.18)).opacity(0.55), lineWidth: 1)
            )
    }
}

private struct FeedSettingsCard: View {
    @EnvironmentObject private var state: WidgetAppState
    @State private var draft: RuntimeFeed
    @State private var webhookDraft: String

    init(feed: RuntimeFeed) {
        _draft = State(initialValue: feed)
        _webhookDraft = State(initialValue: feed.settings.discordWebhookUrl ?? "")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(draft.label)
                        .font(.headline)
                        .foregroundStyle(AINewsTheme.textPrimary)
                    Text(draft.url)
                        .font(.caption)
                        .foregroundStyle(AINewsTheme.textMuted)
                        .lineLimit(1)
                }
                Spacer()
                Text(draft.settings.budget.capitalized)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AINewsTheme.accentGold)
            }

            HStack(spacing: 14) {
                Toggle("Fetch", isOn: Binding(
                    get: { draft.settings.pollingEnabled },
                    set: { enabled in
                        draft.settings.pollingEnabled = enabled
                        persist()
                    }
                ))
                Toggle("AI", isOn: Binding(
                    get: { draft.settings.aiEnabled },
                    set: { enabled in
                        draft.settings.aiEnabled = enabled
                        persist()
                    }
                ))
            }
            .toggleStyle(.switch)

            HStack(spacing: 14) {
                Toggle("Summary", isOn: Binding(
                    get: { draft.settings.summaryEnabled },
                    set: { enabled in
                        draft.settings.summaryEnabled = enabled
                        persist()
                    }
                ))
                Toggle("Translation", isOn: Binding(
                    get: { draft.settings.translationEnabled },
                    set: { enabled in
                        draft.settings.translationEnabled = enabled
                        persist()
                    }
                ))
                Toggle("Research", isOn: Binding(
                    get: { draft.settings.researchEnabled },
                    set: { enabled in
                        draft.settings.researchEnabled = enabled
                        persist()
                    }
                ))
            }
            .toggleStyle(.switch)
            .disabled(!draft.settings.aiEnabled)
            .opacity(draft.settings.aiEnabled ? 1 : 0.55)

            if let progress = state.aiProgress[draft.url], progress.total > 0 {
                VStack(alignment: .leading, spacing: 3) {
                    ProgressView(value: Double(progress.done), total: Double(max(progress.total, 1)))
                        .tint(progress.pending > 0 ? AINewsTheme.accentCyan : AINewsTheme.accentGold)
                    Text(progress.pending > 0
                         ? "\(progress.pending) pending · \(progress.done)/\(progress.total) generated"
                         : "All \(progress.total) generated")
                        .font(.caption2)
                        .foregroundStyle(AINewsTheme.textMuted)
                    if progress.blocked > 0 {
                        Text("\(progress.blocked) waiting on manual trigger or high budget")
                            .font(.caption2)
                            .foregroundStyle(AINewsTheme.textMuted)
                    }
                }
            }

            HStack(spacing: 16) {
                Picker("Budget", selection: Binding(
                    get: { draft.settings.budget },
                    set: { value in
                        draft.settings.budget = value
                        persist()
                    }
                )) {
                    Text("Low").tag("low")
                    Text("Standard").tag("standard")
                    Text("High").tag("high")
                }
                .pickerStyle(.segmented)

                Stepper(value: Binding(
                    get: { draft.settings.intervalSec },
                    set: { value in
                        draft.settings.intervalSec = value
                        persist()
                    }
                ), in: 30...3600, step: 15) {
                    Text("Every \(draft.settings.intervalSec)s")
                        .foregroundStyle(AINewsTheme.textSecondary)
                }
                .frame(maxWidth: 180, alignment: .leading)
            }

            HStack(spacing: 10) {
                TextField("Discord webhook (optional)", text: $webhookDraft)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit {
                        draft.settings.discordWebhookUrl = webhookDraft.isEmpty ? nil : webhookDraft
                        persist()
                    }

                Button("Save webhook") {
                    draft.settings.discordWebhookUrl = webhookDraft.isEmpty ? nil : webhookDraft
                    persist()
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(16)
        .aiNewsPanelStyle()
        .onChange(of: state.runtimeConfig?.feeds.first(where: { $0.url == draft.url })) { _, newValue in
            guard let newValue else { return }
            draft = newValue
            webhookDraft = newValue.settings.discordWebhookUrl ?? ""
        }
    }

    private func persist() {
        Task {
            await state.saveFeedSettings(draft)
        }
    }
}
