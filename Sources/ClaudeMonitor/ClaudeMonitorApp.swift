import SwiftUI

@main
struct ClaudeMonitorApp: App {
    var body: some Scene {
        MenuBarExtra {
            DropdownView()
        } label: {
            Image(systemName: "bolt.fill")
        }
        .menuBarExtraStyle(.window)
    }
}
