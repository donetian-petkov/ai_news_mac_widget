import SwiftUI
import AINewsWidgetShared

@main
struct AINewsMacApp: App {
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
        }
        .windowResizability(.contentSize)
    }
}
