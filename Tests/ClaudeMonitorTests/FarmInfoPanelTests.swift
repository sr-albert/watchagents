import XCTest
import SwiftUI
@testable import ClaudeMonitor

final class FarmInfoPanelTests: XCTestCase {
    private var pens: [FarmPen] {
        FarmGrouping.pens(from: [
            ClaudeProcess(pid: 901, cpu: 12.5, mem: 3.1, cwd: "/Users/someone/code/watchagents",
                          state: .active),
            ClaudeProcess(pid: 902, cpu: 0.2, mem: 1.0, cwd: "/Users/someone/code/watchagents",
                          state: .idle),
            ClaudeProcess(pid: 903, cpu: 91.0, mem: 8.4, cwd: "/Users/someone/dotfiles",
                          state: .overloaded),
        ])
    }

    private let block = UsageBlock(pct: 62, usedTokens: "1.2M", maxTokens: "2.0M", cost: 4.21,
                                   burnRate: "1,203", estimatedCost: 6.80, resetIn: "1h 14m",
                                   startLocal: "09:00", endLocal: "14:00")

    @MainActor
    func test_panel_bodyEvaluatesForAPopulatedFarm() {
        _ = FarmInfoPanel(pens: pens, usage: .active(block), onSelectProject: { _ in }).body
    }

    /// The farm can be empty between the app launching and the first poll landing, and
    /// again whenever the last session exits.
    @MainActor
    func test_panel_bodyEvaluatesForAnEmptyFarm() {
        _ = FarmInfoPanel(pens: [], usage: .active(block), onSelectProject: { _ in }).body
    }

    /// `ccusage` is optional — two of the three results say "no numbers", and both have to
    /// render something rather than an empty hole where the block section is.
    @MainActor
    func test_panel_bodyEvaluatesForEveryUsageResult() {
        for usage: UsageBlockResult in [.active(block), .noActiveBlock, .unavailable] {
            _ = FarmInfoPanel(pens: pens, usage: usage, onSelectProject: { _ in }).body
        }
    }
}
