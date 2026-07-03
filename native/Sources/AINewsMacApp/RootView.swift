import SwiftUI
import AppKit
import AINewsWidgetShared
import Combine

struct RootView: View {
    @EnvironmentObject private var state: WidgetAppState

    var body: some View {
        Group {
            if state.session == nil {
                LoginView()
            } else {
                DashboardView()
            }
        }
        .background(AINewsTheme.background.ignoresSafeArea())
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
        .onChange(of: state.exportedUsageURL) { _, newValue in
            guard let newValue else { return }
            NSWorkspace.shared.activateFileViewerSelecting([newValue])
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
                .font(.system(size: 40, weight: .bold))
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
    @AppStorage("ai_news_show_hidden_categories") private var showHiddenCategories = true
    @State private var storySearch = ""

    private var sidebarCategories: [WidgetCategory] {
        showHiddenCategories ? state.categories : state.categories.filter { !$0.hidden }
    }

    private var visibleCategoryCount: Int {
        state.categories.filter { !$0.hidden }.count
    }

    private var hiddenCategoryCount: Int {
        state.categories.filter { $0.hidden }.count
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
                .frame(minWidth: 760, minHeight: 520)
        }
        .sheet(isPresented: $state.showingWidgetHelp) {
            WidgetHelpView()
                .environmentObject(state)
                .frame(minWidth: 640, minHeight: 460)
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 10) {
                    Image(systemName: "newspaper.fill")
                        .foregroundStyle(AINewsTheme.accentBlue)
                    Text("AI News")
                        .font(.system(size: 18, weight: .bold))
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
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(AINewsTheme.textMuted)
                    .textCase(.uppercase)
                HStack(spacing: 8) {
                    Text("\(visibleCategoryCount) visible")
                    Text("\(hiddenCategoryCount) hidden")
                }
                .font(.caption)
                .foregroundStyle(AINewsTheme.textMuted)
            }

            List(selection: Binding(
                get: { state.selectedCategoryID },
                set: { newValue in
                    if let id = newValue, let category = state.categories.first(where: { $0.id == id }) {
                        Task { await state.selectCategory(category) }
                    }
                }
            )) {
                ForEach(sidebarCategories) { category in
                    HStack(spacing: 10) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(category.name)
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(AINewsTheme.textPrimary)
                                .lineLimit(2)
                                .fixedSize(horizontal: false, vertical: true)
                            Text(category.hidden ? "Hidden" : "\(category.activeCount) visible")
                                .font(.caption)
                                .foregroundStyle(AINewsTheme.textMuted)
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

            Button("Widget Help") {
                state.showingWidgetHelp = true
            }
            .buttonStyle(.bordered)

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
                    Text(state.selectedCategory?.name ?? "Pick a category")
                        .font(.system(size: 30, weight: .bold))
                        .foregroundStyle(AINewsTheme.textPrimary)
                    Text(state.selectedCategory?.description.isEmpty == false ? state.selectedCategory?.description ?? "" : "Stories are image-free here on purpose, so the text and AI actions stay fast and widget-safe.")
                        .foregroundStyle(AINewsTheme.textSecondary)
                }
                Spacer()
                HStack(spacing: 10) {
                    Button("Top") { state.scrollToTop() }
                    Button("Reset 5") { Task { await state.resetSelectedCategory() } }
                    Button("Expand 10") { Task { await state.expandSelectedCategory() } }
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
                }
                .font(.caption)
                .foregroundStyle(AINewsTheme.textMuted)
            }

            if let statusMessage = state.statusMessage {
                Text(statusMessage)
                    .font(.subheadline)
                    .foregroundStyle(AINewsTheme.accentCyan)
            }

            HStack(spacing: 12) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(AINewsTheme.textMuted)
                TextField("Search stories in this category", text: $storySearch)
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
        .background(AINewsTheme.background)
    }
}

private struct WidgetHelpView: View {
    @EnvironmentObject private var state: WidgetAppState

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Text("Add the widgets")
                    .font(.system(size: 28, weight: .bold))
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
        .background(AINewsTheme.background.ignoresSafeArea())
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

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 6) {
                    Text(story.source ?? story.feedUrl)
                        .font(.headline)
                        .foregroundStyle(AINewsTheme.textPrimary)
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
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(AINewsTheme.accentBlue)

            if let translated = story.translatedTitle, !translated.isEmpty, translated != story.title {
                Text(translated)
                    .font(.title3)
                    .foregroundStyle(AINewsTheme.textSecondary)
            }

            Divider().overlay(AINewsTheme.panelBorder.opacity(0.55))

            storyBlock(title: "Summary", text: story.summary, pending: story.summaryPending, accent: AINewsTheme.accentBlue)
            storyBlock(title: "Research", text: story.research, pending: story.researchPending, accent: AINewsTheme.accentCyan)
            storyBlock(
                title: "Translation",
                text: translatedStoryText,
                pending: story.translationPending,
                accent: AINewsTheme.accentGold,
                emptyLabel: "Not translated yet."
            )

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
                actionButton("Pin", systemImage: "pin", tint: AINewsTheme.accentRose) {
                    Task { await state.togglePin(for: story) }
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
        .padding(22)
        .aiNewsPanelStyle()
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
}

private struct SettingsView: View {
    @EnvironmentObject private var state: WidgetAppState
    @State private var newCategoryName = ""
    @State private var newCategoryDescription = ""
    @State private var newCategoryFeedURLs = Set<String>()
    @State private var editingCategoryID: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Text("AI & Widget Settings")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(AINewsTheme.textPrimary)
                Spacer()
                Button("Done") {
                    state.showingSettings = false
                }
            }

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

                TextField("Preferred provider", text: Binding(
                    get: { state.accountSettings.aiProvider ?? "" },
                    set: { state.accountSettings.aiProvider = $0.isEmpty ? nil : $0 }
                ))
                .textFieldStyle(.roundedBorder)

                TextField("Summary model", text: Binding(
                    get: { state.accountSettings.summaryModel ?? "" },
                    set: { state.accountSettings.summaryModel = $0.isEmpty ? nil : $0 }
                ))
                .textFieldStyle(.roundedBorder)

                TextField("Research model", text: Binding(
                    get: { state.accountSettings.researchModel ?? "" },
                    set: { state.accountSettings.researchModel = $0.isEmpty ? nil : $0 }
                ))
                .textFieldStyle(.roundedBorder)

                TextField("Ask model", text: Binding(
                    get: { state.accountSettings.askModel ?? "" },
                    set: { state.accountSettings.askModel = $0.isEmpty ? nil : $0 }
                ))
                .textFieldStyle(.roundedBorder)

                Toggle("Disable cover images in this product", isOn: Binding(
                    get: { !(state.accountSettings.showNewsCovers ?? false) },
                    set: { state.accountSettings.showNewsCovers = !$0 }
                ))

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

            Spacer()
        }
        .padding(28)
        .background(AINewsTheme.background.ignoresSafeArea())
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
                Button(category.hidden ? "Show" : "Hide") {
                    Task { await state.toggleVisibility(for: category) }
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
