import AppKit
import SwiftUI
import AINewsWidgetShared

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        BackendSupervisor.shared.ensureBackendStarted()
        NSApp.setActivationPolicy(.regular)
        NSApp.applicationIconImage = NSImage(
            systemSymbolName: "newspaper.fill",
            accessibilityDescription: "AI News"
        )
        NSApp.activate(ignoringOtherApps: true)
        for window in NSApp.windows {
            window.makeKeyAndOrderFront(nil)
        }
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
