import SwiftUI

/// What is inside the barn when you open its doors: the storehouse, and the controls.
///
/// The farm's other two surfaces answer "what is this animal doing" (`FarmDetailCard`) and
/// "what is this project doing" (`FarmProjectModal`); the side panel answers "what is the
/// whole farm doing". This one is not about sessions at all. A barn stores the harvest, so
/// it holds the usage block — tokens, cost, burn — given the room the panel's four cramped
/// lines cannot; and a farmhouse is where the farmer lives, so it holds the settings that
/// were otherwise stranded in the menu-bar dropdown, out of reach whenever the farm window
/// is the thing you are looking at.
///
/// Read-and-set, unlike the other two, which are read-only. The scrim, the centring and
/// the dismiss gestures belong to `FarmView`.
struct FarmHouseModal: View {
    let usage: UsageBlockResult
    @ObservedObject var overloadSettings: OverloadSettings
    let onClose: () -> Void

    /// Owned here rather than passed in, matching `DropdownView`: the manager reads the
    /// real login-item registration on init, so a second instance is a second read of the
    /// same system state, not a second source of truth.
    @StateObject private var loginItem = LoginItemManager()

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            rule
            storehouse
            rule
            settings
            rule
            quit
        }
        .foregroundStyle(FarmPalette.ink)
        .padding(14)
        .frame(width: 360, alignment: .leading)
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
            Text("THE FARMHOUSE")
                .font(.system(.title3, design: .rounded).weight(.bold))
            Spacer(minLength: 0)
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .bold))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close")
        }
    }

    @ViewBuilder
    private var storehouse: some View {
        VStack(alignment: .leading, spacing: 6) {
            section("THE STOREHOUSE")
            switch usage {
            case .unavailable:
                note("No ccusage data available.")
            case .noActiveBlock:
                note("No active usage block.")
            case .active(let block):
                Text("\(block.startLocal) → \(block.endLocal)")
                    .font(.system(size: 10, design: .monospaced))
                    .opacity(0.75)
                HStack(spacing: 8) {
                    // Clamped: a block can run past its own ceiling, and an unclamped
                    // value overflows the track rather than pinning it full.
                    ProgressView(value: Double(min(block.pct, 100)), total: 100)
                        .tint(FarmPalette.woodLo)
                    Text("\(block.pct)%")
                        .font(.system(.subheadline, design: .monospaced).weight(.semibold))
                }
                Text("\(block.usedTokens) / \(block.maxTokens) tokens")
                    .font(.system(size: 11, design: .monospaced))
                    .opacity(0.85)
                stat("Spent", String(format: "$%.2f", block.cost))
                stat("Burn", "\(block.burnRate) tok/min")
                stat("Projected", String(format: "$%.2f", block.estimatedCost))
                stat("Resets in", block.resetIn)
            }
        }
    }

    private var settings: some View {
        VStack(alignment: .leading, spacing: 8) {
            section("SETTINGS")
            Picker("Overload trigger", selection: $overloadSettings.basis) {
                ForEach(OverloadBasis.allCases, id: \.self) { basis in
                    Text(basis.rawValue.uppercased()).tag(basis)
                }
            }
            .pickerStyle(.segmented)
            Toggle("Launch at login", isOn: Binding(
                get: { loginItem.isEnabled },
                set: { loginItem.setEnabled($0) }
            ))
            .font(.system(.callout, design: .rounded))
        }
    }

    /// Last, behind its own rule, and not styled as anything inviting. The barn is a
    /// decorative building people will click out of curiosity, and quitting the app should
    /// not be one accidental pixel away from reading a token count.
    private var quit: some View {
        Button("Quit ClaudeMonitor") { NSApplication.shared.terminate(nil) }
            .buttonStyle(.plain)
            .font(.system(.caption, design: .rounded))
            .opacity(0.75)
    }

    private func section(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 9, design: .monospaced))
            .opacity(0.65)
    }

    private func note(_ text: String) -> some View {
        Text(text)
            .font(.system(.caption, design: .rounded))
            .opacity(0.7)
    }

    private func stat(_ name: String, _ value: String) -> some View {
        HStack(spacing: 8) {
            Text(name)
                .font(.system(size: 10, design: .monospaced))
                .opacity(0.65)
            Spacer(minLength: 8)
            Text(value)
                .font(.system(.caption, design: .monospaced).weight(.semibold))
        }
    }

    private var rule: some View {
        Rectangle()
            .fill(FarmPalette.ink.opacity(0.35))
            .frame(height: 1)
    }
}
