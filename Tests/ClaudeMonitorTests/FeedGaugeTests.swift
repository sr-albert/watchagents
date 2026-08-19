import XCTest
@testable import ClaudeMonitor

final class FeedGaugeTests: XCTestCase {
    private func block(tokens: Int, cost: Double) -> UsageBlockResult {
        .active(UsageBlock(
            pct: 0, usedTokens: "", maxTokens: "", cost: cost, burnRate: "",
            estimatedCost: 0, resetIn: "", startLocal: "", endLocal: "",
            rawTokens: tokens, observedMaxTokens: 0, observedMaxCost: 0))
    }

    private func gauge(tokens: Int, cost: Double) -> FeedGauge? {
        FeedGaugeReader.gauge(for: block(tokens: tokens, cost: cost),
                              tokenCeiling: 1000, dollarCeiling: 10)
    }

    func test_balesEmptyInThirds() {
        XCTAssertEqual(gauge(tokens: 0, cost: 0)?.bales, 3)      // nothing spent
        XCTAssertEqual(gauge(tokens: 300, cost: 0)?.bales, 3)    // 70% remains
        XCTAssertEqual(gauge(tokens: 500, cost: 0)?.bales, 2)    // half remains
        XCTAssertEqual(gauge(tokens: 700, cost: 0)?.bales, 1)    // 30% remains
        XCTAssertEqual(gauge(tokens: 1000, cost: 0)?.bales, 0)   // nothing remains
    }

    /// "Must not read empty until it IS empty." One token left is still one bale.
    func test_aSingleRemainingTokenStillShowsABale() {
        XCTAssertEqual(gauge(tokens: 999, cost: 0)?.bales, 1)
    }

    func test_overspendClampsToZeroRatherThanGoingNegative() {
        XCTAssertEqual(gauge(tokens: 5000, cost: 0)?.bales, 0)
    }

    func test_theVatFillsInThirds() {
        XCTAssertEqual(gauge(tokens: 0, cost: 0)?.vat, 0)
        XCTAssertEqual(gauge(tokens: 0, cost: 3.0)?.vat, 0)
        XCTAssertEqual(gauge(tokens: 0, cost: 3.4)?.vat, 1)
        XCTAssertEqual(gauge(tokens: 0, cost: 6.7)?.vat, 2)
        XCTAssertEqual(gauge(tokens: 0, cost: 10.0)?.vat, 3)
    }

    /// The mirror of the bale rule: not full until it IS full.
    func test_aCentShortOfTheCeilingIsNotAFullVat() {
        XCTAssertEqual(gauge(tokens: 0, cost: 9.99)?.vat, 2)
    }

    func test_overspendClampsTheVatFull() {
        XCTAssertEqual(gauge(tokens: 0, cost: 50)?.vat, 3)
    }

    /// The case route A exists for. A block a quarter through its tokens but three-quarters
    /// through its dollars must show the two gauges disagreeing — that gap IS the signal
    /// (expensive models, or poor cache hits). If this cannot be produced, the two gauges are
    /// redundant and the design has failed.
    func test_theTwoGaugesCanDisagree() {
        let g = gauge(tokens: 250, cost: 7.5)
        XCTAssertEqual(g?.bales, 3)
        XCTAssertEqual(g?.vat, 2)
    }

    /// Absent, not empty. "No ccusage" and "no budget left" mean opposite things and must
    /// never render the same way.
    func test_unavailableDrawsNoGaugeAtAll() {
        XCTAssertNil(FeedGaugeReader.gauge(for: .unavailable, tokenCeiling: 1000, dollarCeiling: 10))
    }

    func test_unseededCeilingsDrawNoGaugeAtAll() {
        XCTAssertNil(FeedGaugeReader.gauge(for: block(tokens: 5, cost: 1),
                                           tokenCeiling: 0, dollarCeiling: 0))
    }

    /// A block that has not started has spent nothing. That is true, not a placeholder.
    func test_noActiveBlockReadsAsFullAndUnspent() {
        let g = FeedGaugeReader.gauge(for: .noActiveBlock, tokenCeiling: 1000, dollarCeiling: 10)
        XCTAssertEqual(g, FeedGauge(bales: 3, vat: 0))
    }
}
