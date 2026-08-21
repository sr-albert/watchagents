import SwiftUI

/// Which animal's card is on screen, and whether it can be dismissed.
///
/// Two inputs, because there are two ways to ask for a card and they mean different
/// things: the pointer is "what is this one", a click is "keep this one up while I go and
/// look at something else". Pure so the precedence can be tested without SwiftUI — it is
/// the whole behaviour, and the view around it is just a card in a corner.
enum FarmCardSelection {
    /// Pointing beats pinning: the pointer is the more recent statement of intent, and a
    /// pin that ignored it would make the farm feel stuck on an animal you have moved on
    /// from.
    static func shownPID(hovered: Int?, pinned: Int?) -> Int? {
        hovered ?? pinned
    }

    /// The close button belongs to the pin. On a hover card it cannot be reached at all —
    /// travelling to the corner leaves the animal, and the card is gone before the pointer
    /// arrives.
    static func isDismissable(shown: Int?, pinned: Int?) -> Bool {
        shown != nil && shown == pinned
    }
}

/// The read-only card shown when you click an animal: which session it is and what it is
/// doing right now. Deliberately not a control panel — spec §5.1 keeps the resting scene
/// quiet, and the farm exists because reading a wall of session text was the original
/// complaint. This is the on-demand detail layer, not a list that is always open.
///
/// Painted in the same wood/ink palette as the pen signs (`FarmPalette`) so it reads as
/// part of the farm rather than a system panel dropped on top of it.
struct FarmDetailCard: View {
    let process: ClaudeProcess
    /// Nil for a card the pointer is holding open, which has nothing to dismiss — see
    /// `FarmCardSelection.isDismissable`.
    let onClose: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text("PID \(process.pid)")
                    .font(.system(.headline, design: .monospaced))
                Spacer(minLength: 0)
                if let onClose {
                    Button(action: onClose) {
                        Image(systemName: "xmark")
                            .font(.system(size: 10, weight: .bold))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Close")
                }
            }

            Text(URL(fileURLWithPath: process.cwd).lastPathComponent)
                .font(.system(.subheadline, design: .rounded).weight(.semibold))
            Text(process.cwd)
                .font(.system(size: 10, design: .monospaced))
                .opacity(0.7)
                .lineLimit(2)
                .truncationMode(.head)

            Rectangle()
                .fill(FarmPalette.ink.opacity(0.35))
                .frame(height: 1)
                .padding(.vertical, 2)

            metric("CPU", value: process.cpu)
            metric("MEM", value: process.mem)

            Text("\(SessionStateBadge.emoji(for: process.state))  \(SessionStateBadge.label(for: process.state))")
                .font(.system(.caption, design: .rounded).weight(.semibold))
                .padding(.top, 2)
        }
        // The pid and path are the two things worth pasting into a terminal.
        .textSelection(.enabled)
        .foregroundStyle(FarmPalette.ink)
        .padding(10)
        .frame(width: 210, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(FarmPalette.wood)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(FarmPalette.woodLo, lineWidth: 2)
                )
        )
        .shadow(color: .black.opacity(0.3), radius: 6, y: 2)
    }

    private func metric(_ name: String, value: Double) -> some View {
        HStack(spacing: 6) {
            Text(name)
                .font(.system(size: 10, design: .monospaced))
                .opacity(0.75)
            Text(String(format: "%.1f%%", value))
                .font(.system(.caption, design: .monospaced))
        }
    }
}
