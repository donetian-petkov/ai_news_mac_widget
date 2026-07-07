import AppKit
import SwiftUI
import AINewsWidgetShared

extension Notification.Name {
    static let aiNewsOpenSettings = Notification.Name("AINewsOpenSettings")
    static let aiNewsRefreshRequested = Notification.Name("AINewsRefreshRequested")
    static let aiNewsOpenWidgetHelp = Notification.Name("AINewsOpenWidgetHelp")
    static let aiNewsOpenWorkspace = Notification.Name("AINewsOpenWorkspace")
    static let aiNewsToggleFloatingWidget = Notification.Name("AINewsToggleFloatingWidget")
    static let aiNewsOpenFilteredWidget = Notification.Name("AINewsOpenFilteredWidget")
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var appState: WidgetAppState?
    private var floatingWidgetManager: FloatingWidgetManager?

    /// Called from the SwiftUI scene once the shared app state exists.
    @MainActor
    func attach(state: WidgetAppState) {
        appState = state
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        BackendSupervisor.shared.ensureBackendStarted()
        NSApp.setActivationPolicy(.regular)
        if let bundledIcon = NSImage(named: "AppIcon") {
            NSApp.applicationIconImage = bundledIcon
        } else {
            NSApp.applicationIconImage = NSWorkspace.shared.icon(forFile: Bundle.main.bundlePath)
        }
        configureStatusItem()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(toggleFloatingWidget),
            name: .aiNewsToggleFloatingWidget,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(openFilteredWidget),
            name: .aiNewsOpenFilteredWidget,
            object: nil
        )
        NSApp.activate(ignoringOtherApps: true)
        showMainWindow()
    }

    private func configureStatusItem() {
        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            let statusIcon = NSImage(
                systemSymbolName: "newspaper.fill",
                accessibilityDescription: "AI News"
            )
            statusIcon?.isTemplate = true
            button.image = statusIcon
            button.toolTip = "AI News Widget"
        }

        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Open AI News", action: #selector(openMainWindow), keyEquivalent: "o"))
        menu.addItem(NSMenuItem(title: "Workspace", action: #selector(openWorkspace), keyEquivalent: "l"))
        menu.addItem(NSMenuItem(title: "Refresh Categories", action: #selector(requestRefresh), keyEquivalent: "r"))
        menu.addItem(NSMenuItem(title: "Settings & AI", action: #selector(openSettings), keyEquivalent: ","))
        menu.addItem(NSMenuItem(title: "Widget Help", action: #selector(openWidgetHelp), keyEquivalent: "w"))
        menu.addItem(NSMenuItem(title: "Floating Widget", action: #selector(toggleFloatingWidget), keyEquivalent: "f"))
        menu.addItem(NSMenuItem(title: "Filtered Widget", action: #selector(openFilteredWidget), keyEquivalent: ""))
        let reopenItem = NSMenuItem(title: "Reopen Closed Widget", action: #selector(reopenClosedWidget), keyEquivalent: "t")
        reopenItem.keyEquivalentModifierMask = [.command, .shift]
        menu.addItem(reopenItem)
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(quitApp), keyEquivalent: "q"))
        menu.items.forEach { $0.target = self }
        statusItem.menu = menu
        self.statusItem = statusItem
    }

    func showMainWindow() {
        NSApp.activate(ignoringOtherApps: true)
        for window in NSApp.windows {
            window.makeKeyAndOrderFront(nil)
        }
    }

    @objc private func openMainWindow() {
        showMainWindow()
    }

    @objc private func requestRefresh() {
        showMainWindow()
        NotificationCenter.default.post(name: .aiNewsRefreshRequested, object: nil)
    }

    @objc private func openWorkspace() {
        showMainWindow()
        NotificationCenter.default.post(name: .aiNewsOpenWorkspace, object: nil)
    }

    @objc private func openSettings() {
        showMainWindow()
        NotificationCenter.default.post(name: .aiNewsOpenSettings, object: nil)
    }

    @objc private func openWidgetHelp() {
        showMainWindow()
        NotificationCenter.default.post(name: .aiNewsOpenWidgetHelp, object: nil)
    }

    @MainActor
    @objc private func toggleFloatingWidget() {
        guard let appState else { return }
        if floatingWidgetManager == nil {
            floatingWidgetManager = FloatingWidgetManager(state: appState)
        }
        floatingWidgetManager?.openForSelectedCategory()
    }

    @MainActor
    @objc private func reopenClosedWidget() {
        floatingWidgetManager?.reopenLastClosed()
    }

    @MainActor
    @objc private func openFilteredWidget() {
        guard let appState else { return }
        if floatingWidgetManager == nil {
            floatingWidgetManager = FloatingWidgetManager(state: appState)
        }
        floatingWidgetManager?.openFiltered()
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Don't leave the backend running as a stale orphan for the next launch.
        BackendSupervisor.shared.stopBackend()
    }
}

@main
struct AINewsMacApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var state = WidgetAppState()
    @StateObject private var theme = ThemeSettings.shared

    var body: some Scene {
        WindowGroup("AI News Widget") {
            RootView()
                .environmentObject(state)
                .environmentObject(theme)
                .dynamicTypeSize(theme.fontSize.dynamicTypeSize)
                .preferredColorScheme(theme.vibe == .light ? .light : .dark)
                .frame(minWidth: 1180, minHeight: 760)
                .task {
                    appDelegate.attach(state: state)
                }
                .task {
                    await state.bootstrapIfNeeded()
                }
                .task {
                    await state.startCommandLoop()
                }
        }
        .defaultSize(width: 1280, height: 820)
        .windowResizability(.contentSize)
    }
}
