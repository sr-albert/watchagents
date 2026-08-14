import SwiftUI

@main
struct ClaudeMonitorApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // No window-based UI — the menu bar item and its popover are owned by AppDelegate.
        // SwiftUI's `App` protocol requires at least one Scene; `Settings` never shows a
        // window for an `LSUIElement` app, so it's the correct empty placeholder here.
        Settings {
            EmptyView()
        }
    }
}
