import SwiftUI
import AppKit

struct DropdownView: View {
    @ObservedObject var viewModel: MonitorViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Claude Code Session Monitor")
                .font(.headline)

            sessionsSection
            Divider()
            usageSection
            Divider()
            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
        }
        .padding()
        .frame(width: 360)
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
                ForEach(snapshot.processes, id: \.pid) { proc in
                    VStack(alignment: .leading, spacing: 1) {
                        Text("PID \(proc.pid)  CPU \(proc.cpu, specifier: "%.1f")%  MEM \(proc.mem, specifier: "%.1f")%")
                            .font(.system(.caption, design: .monospaced))
                        Text("📂 \(proc.cwd)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
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
