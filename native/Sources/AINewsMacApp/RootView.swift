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
            }

            List(selection: Binding(
                get: { state.selectedCategoryID },
                set: { newValue in
                    if let id = newValue, let category = state.categories.first(where: { $0.id == id }) {
                        Task { await state.selectCategory(category) }
                    }
                }
            )) {
                ForEach(state.categories) { category in
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

            Button("Settings & AI") {
                state.showingSettings = true
            }
            .buttonStyle(.borderedProminent)
            .tint(AINewsTheme.accentCyan)

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
                        ForEach(state.stories) { story in
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
    private func storyBlock(title: String, text: String?, pending: Bool, accent: Color) -> some View {
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
                Text(pending ? "Waiting for the local AI queue." : "Not generated yet.")
                    .foregroundStyle(AINewsTheme.textMuted)
            }
        }
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
}
