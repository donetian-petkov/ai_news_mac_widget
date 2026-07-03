import AppKit
import SwiftUI
import AINewsWidgetShared

extension Notification.Name {
    static let aiNewsOpenSettings = Notification.Name("AINewsOpenSettings")
    static let aiNewsRefreshRequested = Notification.Name("AINewsRefreshRequested")
    static let aiNewsOpenWidgetHelp = Notification.Name("AINewsOpenWidgetHelp")
    static let aiNewsOpenWorkspace = Notification.Name("AINewsOpenWorkspace")
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        BackendSupervisor.shared.ensureBackendStarted()
        NSApp.setActivationPolicy(.regular)
        let icon = NSImage(
            systemSymbolName: "newspaper.fill",
            accessibilityDescription: "AI News"
        )
        NSApp.applicationIconImage = icon
        configureStatusItem(icon: icon)
        NSApp.activate(ignoringOtherApps: true)
        showMainWindow()
    }

    private func configureStatusItem(icon: NSImage?) {
        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = icon
            button.image?.isTemplate = true
            button.toolTip = "AI News Widget"
        }

        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Open AI News", action: #selector(openMainWindow), keyEquivalent: "o"))
        menu.addItem(NSMenuItem(title: "Workspace", action: #selector(openWorkspace), keyEquivalent: "l"))
        menu.addItem(NSMenuItem(title: "Refresh Categories", action: #selector(requestRefresh), keyEquivalent: "r"))
        menu.addItem(NSMenuItem(title: "Settings & AI", action: #selector(openSettings), keyEquivalent: ","))
        menu.addItem(NSMenuItem(title: "Widget Help", action: #selector(openWidgetHelp), keyEquivalent: "w"))
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

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }
}

@main
struct AINewsMacApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var state = WidgetAppState()

    var body: some Scene {
        WindowGroup("AI News Widget") {
            RootView()
                .environmentObject(state)
                .frame(minWidth: 1180, minHeight: 760)
                .preferredColorScheme(.dark)
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
