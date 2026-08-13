import SwiftUI

@main
struct ClaudeMonitorApp: App {
    @StateObject private var viewModel = MonitorViewModel()

    var body: some Scene {
        MenuBarExtra {
            DropdownView(viewModel: viewModel)
        } label: {
            MenuBarLabel(usageResult: viewModel.usageResult)
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
