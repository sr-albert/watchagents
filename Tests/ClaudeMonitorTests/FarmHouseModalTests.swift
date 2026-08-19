import XCTest
import SwiftUI
@testable import ClaudeMonitor

final class FarmHouseModalTests: XCTestCase {
    private let block = UsageBlock(pct: 62, usedTokens: "1.2M", maxTokens: "2.0M", cost: 4.21,
                                   burnRate: "1,203", estimatedCost: 6.80, resetIn: "2h 07m",
                                   startLocal: "08:00", endLocal: "13:00",
                                   rawTokens: 1_200_000, observedMaxTokens: 2_000_000,
                                   observedMaxCost: 4.21)

    /// `ccusage` is optional and two of the three results carry no numbers. All three have
    /// to render something — the storehouse is half the reason the door opens.
    @MainActor
    func test_house_bodyEvaluatesForEveryUsageResult() {
        let settings = FarmSettings(defaults: UserDefaults(suiteName: #function)!)
        for usage: UsageBlockResult in [.active(block), .noActiveBlock, .unavailable] {
            _ = FarmHouseModal(usage: usage, settings: settings, sleepers: [], onClose: {}).body
        }
    }

    /// A block can run past its own ceiling. The bar must clamp rather than overflow its
    /// track, the same way the dropdown's does.
    @MainActor
    func test_house_bodyEvaluatesForABlockOverItsLimit() {
        let settings = FarmSettings(defaults: UserDefaults(suiteName: #function)!)
        let over = UsageBlock(pct: 140, usedTokens: "2.8M", maxTokens: "2.0M", cost: 9.9,
                              burnRate: "4,000", estimatedCost: 12.0, resetIn: "12m",
                              startLocal: "08:00", endLocal: "13:00",
                              rawTokens: 2_800_000, observedMaxTokens: 2_000_000,
                              observedMaxCost: 9.9)
        _ = FarmHouseModal(usage: .active(over), settings: settings, sleepers: [], onClose: {}).body
    }
}
