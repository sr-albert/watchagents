import SwiftUI

@main
struct ClaudeMonitorApp: App {
    @StateObject private var viewModel = MonitorViewModel()

    var body: some Scene {
        MenuBarExtra {
            DropdownView(viewModel: viewModel)
                .task { viewModel.startPolling() }
        } label: {
            // The label is instantiated at launch, whereas `.window`-style content is
            // created lazily on first open — so polling has to start from here too.
            MenuBarLabel(usageResult: viewModel.usageResult)
                .task { viewModel.startPolling() }
        }
        .menuBarExtraStyle(.window)
    }
}

private struct MenuBarLabel: View {
    let usageResult: UsageBlockResult

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "bolt.fill")
            if case .active(let block) = usageResult {
                Text("\(block.pct)%")
            }
        }
    }
}
