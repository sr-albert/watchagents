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

    /// `UsageBlockFetcher` treats `tokenCeiling <= 0` as "not configured" and falls back to
    /// the moving denominator this feature exists to remove. A zero (or negative, from a
    /// pasted value) ceiling must never reach `FarmSettings`, or the gauge silently starts
    /// drifting again with nothing in the log to explain why.
    func test_clampedTokenCeiling_neverReturnsZeroOrBelow() {
        XCTAssertEqual(FarmHouseModal.clampedTokenCeiling(0), 1)
        XCTAssertEqual(FarmHouseModal.clampedTokenCeiling(-5), 1)
        XCTAssertEqual(FarmHouseModal.clampedTokenCeiling(500_000), 500_000)
    }

    /// Same failure mode, in dollars.
    func test_clampedDollarCeiling_neverReturnsZeroOrBelow() {
        XCTAssertEqual(FarmHouseModal.clampedDollarCeiling(0), 0.01, accuracy: 0.0001)
        XCTAssertEqual(FarmHouseModal.clampedDollarCeiling(-3.5), 0.01, accuracy: 0.0001)
        XCTAssertEqual(FarmHouseModal.clampedDollarCeiling(9.75), 9.75, accuracy: 0.0001)
    }
}
