import SwiftUI

@main
struct ClaudeMonitorApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // No window-based scene: the menu bar item, its popover, and the farm window are
        // all owned by AppDelegate via AppKit. A `WindowGroup` here would auto-open a
        // window at launch (no suppression API before macOS 15), is multi-instance so it
        // cannot bring an existing window forward, and `openWindow` does not activate an
        // `LSUIElement` app — so the window opened behind whatever was in front.
        // SwiftUI's `App` requires at least one Scene; `Settings` never shows one here.
        Settings {
            EmptyView()
        }
    }
}
