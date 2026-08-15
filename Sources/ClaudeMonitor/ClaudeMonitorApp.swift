import SwiftUI

@main
struct ClaudeMonitorApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup(id: "farm") {
            FarmView(viewModel: appDelegate.viewModel)
        }
        // `Settings` never shows a window for an `LSUIElement` app; kept as the
        // menu-bar-only placeholder scene alongside the farm window.
        Settings {
            EmptyView()
        }
    }
}
