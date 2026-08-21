import SwiftUI

/// The whole farm at a glance, docked to the trailing edge of the farm window.
///
/// The three information surfaces answer three different questions and this is the widest
/// of them: `FarmDetailCard` is one animal, `FarmProjectModal` is one pen, and this is
/// every pen at once plus the usage block none of the others can show.
///
/// It overlaps the menu-bar dropdown on the totals, and that is fine — the dropdown is for
/// when the farm window is shut. What it adds over the dropdown is the per-pen rollup: the
/// dropdown lists raw processes, which is the wall of session text the farm exists to
/// replace.
///
/// Painted in the same wood/ink `FarmPalette` as the plates and the modal, so an open panel
/// reads as a noticeboard nailed to the fence rather than an inspector bolted to the side.
struct FarmInfoPanel: View {
    let pens: [FarmPen]
    let usage: UsageBlockResult
    /// Hands a pen's cwd back to `FarmView`, which opens the project modal already built
    /// for fence clicks. Rows are navigation as well as readout.
    let onSelectProject: (String) -> Void

    static let width: CGFloat = 240

    private var totals: FarmCensus.Totals { FarmCensus.totals(for: pens) }
    private var rows: [FarmCensus.PenRow] { FarmCensus.rows(for: pens) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            census
            load
            rule
            penList
            rule
            usageSection
        }
        .foregroundStyle(FarmPalette.ink)
        .padding(14)
        .frame(width: Self.width, alignment: .leading)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(FarmPalette.wood)
        .overlay(alignment: .leading) {
            Rectangle().fill(FarmPalette.woodLo).frame(width: 2)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("THE FARM")
                .font(.system(.headline, design: .rounded).weight(.bold))
            // `ProcessSnapshot.sessionCount` is unique cwds, not sessions — the dropdown
            // labels it "sessions" and is wrong. Counted here from the pens so the two
            // numbers say what they mean: one animal per process, one pen per project.
            Text("\(totals.animals) animal\(totals.animals == 1 ? "" : "s") in "
                 + "\(totals.pens) pen\(totals.pens == 1 ? "" : "s")")
                .font(.system(.caption, design: .rounded))
                .opacity(0.75)
        }
    }

    /// Two columns rather than one line: at 240pt a single row of four counts wraps, and a
    /// wrapped row reads as two unrelated ones. The fifth tally sits alone on a third row,
    /// held to the same column width as the four above it — stretched full-width it stops
    /// reading as part of the same block.
    private var census: some View {
        let s = totals.states
        return VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 0) {
                tally(.active, s.active)
                tally(.idle, s.idle)
            }
            HStack(spacing: 0) {
                tally(.overloaded, s.overloaded)
                tally(.frozen, s.frozen)
            }
            HStack(spacing: 0) {
                tally(.dormant, s.dormant)
                Spacer(minLength: 0)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private func tally(_ state: SessionState, _ count: Int) -> some View {
        HStack(spacing: 4) {
            Text(SessionStateBadge.emoji(for: state))
                .font(.system(size: 11))
            Text("\(count)")
                .font(.system(.caption, design: .monospaced).weight(.semibold))
            Text(SessionStateBadge.label(for: state).lowercased())
                .font(.system(.caption, design: .rounded))
                // A zero is context for the counts that aren't zero, not news in itself.
                .opacity(count == 0 ? 0.45 : 0.75)
        }
        .opacity(count == 0 ? 0.6 : 1)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var load: some View {
        HStack(spacing: 14) {
            stat("CPU", String(format: "%.1f%%", totals.cpu))
            stat("MEM", String(format: "%.1f%%", totals.mem))
            Spacer(minLength: 0)
        }
    }

    private var penList: some View {
        // Scrolls rather than growing: the panel is as tall as the window and a farm can
        // hold more projects than fit, but the usage block below must stay reachable.
        ScrollView {
            VStack(alignment: .leading, spacing: 2) {
                if rows.isEmpty {
                    Text("No sessions running.")
                        .font(.system(.caption, design: .rounded))
                        .opacity(0.7)
                        .padding(.vertical, 4)
                }
                ForEach(rows, id: \.cwd) { row in
                    penRow(row)
                }
            }
        }
        .frame(maxHeight: .infinity)
    }

    private func penRow(_ row: FarmCensus.PenRow) -> some View {
        Button {
            onSelectProject(row.cwd)
        } label: {
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 5) {
                    Text(SessionStateBadge.emoji(for: row.worst))
                        .font(.system(size: 10))
                    Text(row.label)
                        .font(.system(.caption, design: .rounded).weight(.semibold))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer(minLength: 4)
                    Text("×\(row.sessions)")
                        .font(.system(size: 10, design: .monospaced))
                        .opacity(0.7)
                }
                HStack(spacing: 8) {
                    Text(String(format: "%.1f%%", row.cpu))
                        .font(.system(size: 10, design: .monospaced))
                    Text(String(format: "%.1f%%", row.mem))
                        .font(.system(size: 10, design: .monospaced))
                        .opacity(0.75)
                    Spacer(minLength: 0)
                    Text(row.species.rawValue)
                        .font(.system(size: 10))
                }
                .opacity(0.85)
            }
            .padding(.vertical, 4)
            .padding(.horizontal, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(
            RoundedRectangle(cornerRadius: 4).fill(FarmPalette.woodHi.opacity(0.22))
        )
        // Same hand as the fence: a row opens the same modal a fence click does. Leaving
        // a row returns to the farm's own arrow and never to `FarmCursor.reset()`, which
        // is AppKit's system arrow — that belongs to the pointer leaving the farm
        // altogether, and using it here flashes the cursor between two adjacent rows.
        .onHover { inside in FarmCursor.set(interactable: inside) }
        .accessibilityLabel("\(row.label), \(row.sessions) sessions")
    }

    @ViewBuilder
    private var usageSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("USAGE BLOCK")
                .font(.system(size: 9, design: .monospaced))
                .opacity(0.65)
            switch usage {
            case .unavailable:
                Text("No ccusage data").font(.system(.caption, design: .rounded)).opacity(0.7)
            case .noActiveBlock:
                Text("No active block").font(.system(.caption, design: .rounded)).opacity(0.7)
            case .active(let block):
                HStack(spacing: 6) {
                    Text("\(block.pct)%")
                        .font(.system(.subheadline, design: .monospaced).weight(.semibold))
                    Text("resets in \(block.resetIn)")
                        .font(.system(.caption, design: .rounded))
                        .opacity(0.75)
                }
                ProgressView(value: Double(min(block.pct, 100)), total: 100)
                    .tint(FarmPalette.woodLo)
                Text("\(block.usedTokens) / \(block.maxTokens) tokens")
                    .font(.system(size: 10, design: .monospaced))
                    .opacity(0.8)
                Text(String(format: "$%.2f · %@ tok/min", block.cost, block.burnRate))
                    .font(.system(size: 10, design: .monospaced))
                    .opacity(0.8)
            }
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
