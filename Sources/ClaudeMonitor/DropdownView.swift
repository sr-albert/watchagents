import SwiftUI
import AppKit

enum SessionStateBadge {
    static func emoji(for state: SessionState) -> String {
        switch state {
        case .idle: return "🌾"
        case .active: return "🏃"
        case .overloaded: return "🔥"
        case .frozen: return "🥶"
        case .dormant: return "😴"
        }
    }

    static func label(for state: SessionState) -> String {
        switch state {
        case .idle: return "Idle"
        case .active: return "Active"
        case .overloaded: return "Overloaded"
        case .frozen: return "Frozen"
        case .dormant: return "Sleeping"
        }
    }
}

struct DropdownView: View {
    @ObservedObject var viewModel: MonitorViewModel
    @ObservedObject var settings: FarmSettings
    var onOpenFarm: () -> Void = {}
    @StateObject private var loginItem = LoginItemManager()

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Claude Code Session Monitor")
                .font(.headline)

            sessionsSection
            Divider()
            usageSection
            Divider()
            Toggle("Launch at Login", isOn: Binding(
                get: { loginItem.isEnabled },
                set: { loginItem.setEnabled($0) }
            ))
            Picker("Overload trigger", selection: $settings.basis) {
                ForEach(OverloadBasis.allCases, id: \.self) { basis in
                    Text(basis.rawValue.uppercased()).tag(basis)
                }
            }
            Button("Open Farm 🌾") {
                onOpenFarm()
            }
            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
        }
        .padding()
        .frame(width: 360)
    }

    /// One two-line row plus the `VStack` spacing under it.
    static let rowHeight: CGFloat = 34
    /// Chosen so the whole popover clears a 13" display with the usage block and all four
    /// controls below it still on screen: roughly 330pt of fixed chrome leaves this much.
    static let maxListHeight: CGFloat = 260

    static func listHeight(for sessions: Int) -> CGFloat {
        min(CGFloat(sessions) * rowHeight, maxListHeight)
    }

    private var sessionsSection: some View {
        let snapshot = viewModel.snapshot
        return VStack(alignment: .leading, spacing: 4) {
            if snapshot.processes.isEmpty {
                Text("No active Claude sessions found.")
                    .foregroundStyle(.secondary)
            } else {
                Text("\(snapshot.sessionCount) unique session\(snapshot.sessionCount == 1 ? "" : "s")  (\(snapshot.processes.count) processes)")
                    .fontWeight(.semibold)
                ProgressView(value: min(snapshot.cpuTotal, 100), total: 100) {
                    Text("CPU \(snapshot.cpuTotal, specifier: "%.1f")%")
                }
                ProgressView(value: min(snapshot.memTotal, 100), total: 100) {
                    Text("MEM \(snapshot.memTotal, specifier: "%.1f")%")
                }
                // Capped and scrolled, not grown: 20 processes is an ordinary day with
                // worktrees, and an uncapped list made the popover taller than the screen
                // — which pushes the usage block and every control below it (launch at
                // login, the overload picker, Open Farm, Quit) off the bottom, out of
                // reach. The list is the part that varies, so the list is the part that
                // scrolls.
                ScrollView {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(snapshot.processes, id: \.pid) { proc in
                            VStack(alignment: .leading, spacing: 1) {
                                Text("\(SessionStateBadge.emoji(for: proc.state)) PID \(proc.pid)  CPU \(proc.cpu, specifier: "%.1f")%  MEM \(proc.mem, specifier: "%.1f")%")
                                    .font(.system(.caption, design: .monospaced))
                                // One line, always: a wrapped path silently doubles a row,
                                // and the height below is computed from a fixed row height.
                                // Truncated in the middle rather than the tail — these are
                                // worktree paths whose project and whose branch both live
                                // at the end, and tail truncation drops both.
                                Text("📂 \(proc.cwd)")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
                // An explicit height, not `maxHeight`: a `ScrollView` is greedy along its
                // scroll axis and would claim the whole cap even for two sessions, leaving
                // the popover mostly empty. `listHeight` shrinks to the content until it
                // hits the cap.
                .frame(height: Self.listHeight(for: snapshot.processes.count))
            }
        }
    }

    private var usageSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Usage Block").fontWeight(.semibold)
            switch viewModel.usageResult {
            case .unavailable:
                Text("Usage data unavailable").foregroundStyle(.secondary)
            case .noActiveBlock:
                Text("No active usage block").foregroundStyle(.secondary)
            case .active(let block):
                Text("\(block.startLocal) → \(block.endLocal)  ·  Reset in \(block.resetIn)")
                ProgressView(value: Double(block.pct), total: 100) {
                    Text("Tokens \(block.usedTokens) / \(block.maxTokens)  (\(block.pct)%)")
                }
                Text("Cost $\(block.cost, specifier: "%.2f")  ·  Burn \(block.burnRate) tok/min  ·  Est $\(block.estimatedCost, specifier: "%.2f")")
                    .font(.caption)
            }
        }
    }
}
