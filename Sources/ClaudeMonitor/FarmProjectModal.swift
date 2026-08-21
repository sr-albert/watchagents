import SwiftUI

/// Everything known about one project, shown centred over the farm when you click a
/// pen's name plate. Where `FarmDetailCard` answers "what is this one animal doing",
/// this answers "what is this whole pen doing" — the aggregate the farm deliberately
/// does not draw, since spec §5.1 keeps the resting scene quiet.
///
/// Read-only, like the card, and painted in the same wood/ink `FarmPalette` so it reads
/// as a notice board rather than a system panel. The dimming scrim, the centring and the
/// dismiss gestures belong to `FarmView`, which owns the layer this is presented in.
struct FarmProjectModal: View {
    let pen: FarmPen
    let onClose: () -> Void

    private var cpuTotal: Double { pen.processes.reduce(0) { $0 + $1.cpu } }
    private var memTotal: Double { pen.processes.reduce(0) { $0 + $1.mem } }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            path
            rule
            summary
            rule
            sessions
        }
        .foregroundStyle(FarmPalette.ink)
        .padding(14)
        .frame(width: 380, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(FarmPalette.wood)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(FarmPalette.woodLo, lineWidth: 2)
                )
        )
        .shadow(color: .black.opacity(0.45), radius: 18, y: 6)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(pen.label)
                .font(.system(.title3, design: .rounded).weight(.bold))
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 0)
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .bold))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close")
        }
    }

    private var path: some View {
        // The one string worth pasting into a terminal, so it is never truncated to an
        // ellipsis you cannot recover the middle of.
        Text(pen.cwd)
            .font(.system(size: 10, design: .monospaced))
            .opacity(0.75)
            .textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var summary: some View {
        HStack(spacing: 14) {
            stat("SESSIONS", String(pen.processes.count))
            stat("CPU", String(format: "%.1f%%", cpuTotal))
            stat("MEM", String(format: "%.1f%%", memTotal))
            Spacer(minLength: 0)
            // Which animal this project's pen is stocked with, so the modal can be tied
            // back to the pen you clicked without hunting for it.
            Text("\(pen.species.rawValue) \(pen.species.assetName)")
                .font(.system(.caption, design: .rounded))
                .opacity(0.7)
        }
    }

    private var sessions: some View {
        // Capped rather than unbounded: a project can hold far more sessions than the
        // eight a pen draws, and a modal taller than the farm window would clip against
        // its own scrim.
        ScrollView {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(pen.processes, id: \.pid) { process in
                    sessionRow(process)
                }
            }
        }
        .frame(maxHeight: 220)
    }

    private func sessionRow(_ process: ClaudeProcess) -> some View {
        HStack(spacing: 8) {
            Text(SessionStateBadge.emoji(for: process.state))
                .font(.system(size: 12))
            Text("PID \(process.pid)")
                .font(.system(.caption, design: .monospaced))
                .textSelection(.enabled)
            Text(SessionStateBadge.label(for: process.state))
                .font(.system(.caption, design: .rounded))
                .opacity(0.7)
            Spacer(minLength: 8)
            Text(String(format: "%.1f%%", process.cpu))
                .font(.system(.caption, design: .monospaced))
            Text(String(format: "%.1f%%", process.mem))
                .font(.system(.caption, design: .monospaced))
                .opacity(0.75)
        }
    }

    private func stat(_ name: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(name)
                .font(.system(size: 9, design: .monospaced))
                .opacity(0.65)
            Text(value)
                .font(.system(.subheadline, design: .monospaced).weight(.semibold))
        }
    }

    private var rule: some View {
        Rectangle()
            .fill(FarmPalette.ink.opacity(0.35))
            .frame(height: 1)
    }
}
