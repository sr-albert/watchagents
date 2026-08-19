import XCTest
@testable import ClaudeMonitor

final class FarmSceneryGaugeTests: XCTestCase {
    private func layout(cols: Int, rows: Int) -> FarmLayout {
        FarmLayoutEngine.layout(pens: [FarmPen(cwd: "/a", label: "a", species: .cow,
                                               processes: [])], cols: cols, rows: rows)
    }

    func test_noGaugeMeansNoProps() {
        XCTAssertTrue(FarmScenery.gaugeProps(layout: layout(cols: 60, rows: 40),
                                             gauge: nil).isEmpty)
    }

    func test_aFullGaugeDrawsThreeBalesAndAVat() {
        let props = FarmScenery.gaugeProps(layout: layout(cols: 60, rows: 40),
                                           gauge: FeedGauge(bales: 3, vat: 0))
        XCTAssertEqual(props.filter { $0.tile == 93 }.count, 3)
        XCTAssertEqual(props.filter { $0.tile == 130 }.count, 1)
        // `FarmView` splits this array positionally — `dropLast()` for the bales,
        // `last` for the vat — rather than filtering by tile. Nothing else pins that
        // order here, and a reorder would still pass both counts above while making
        // `FarmView` composite the vat's fill onto a bale and draw the vat as bare.
        XCTAssertEqual(props.last?.tile, 130, "FarmView splits this array positionally — the vat must be last")
    }

    func test_anEmptyGaugeDrawsNoBalesButKeepsTheVat() {
        let props = FarmScenery.gaugeProps(layout: layout(cols: 60, rows: 40),
                                           gauge: FeedGauge(bales: 0, vat: 3))
        XCTAssertEqual(props.filter { $0.tile == 93 }.count, 0)
        XCTAssertEqual(props.filter { $0.tile == 130 }.count, 1,
                       "the vat is always present; it is its fill that varies")
        XCTAssertEqual(props.last?.tile, 130, "FarmView splits this array positionally — the vat must be last")
    }

    /// All-or-nothing. A layout too small for the reserved cluster draws ZERO gauge props —
    /// never one or two. A half-drawn gauge lies about the budget.
    func test_aLayoutTooSmallDrawsNoGaugePropsAtAll() {
        let small = layout(cols: 10, rows: 12)
        // Precondition, not decoration: this test is only meaningful if the barn IS placed
        // and a gauge cell falls outside the window. If the barn were absent, `gaugeProps`
        // would return [] for that reason instead, and the all-or-nothing rule would go
        // untested while the test still passed.
        XCTAssertNotNil(small.barnX, "fixture must still place a barn, or this tests nothing")
        let props = FarmScenery.gaugeProps(layout: small,
                                           gauge: FeedGauge(bales: 3, vat: 1))
        XCTAssertTrue(props.isEmpty,
                      "expected all-or-nothing, got a partial cluster of \(props.count)")
    }

    func test_theDecorativeNeighboursAreNotGaugeProps() {
        let props = FarmScenery.gaugeProps(layout: layout(cols: 60, rows: 40),
                                           gauge: FeedGauge(bales: 3, vat: 3))
        for decorative in [94, 106, 107, 116] {
            XCTAssertTrue(props.allSatisfy { $0.tile != decorative },
                          "tile \(decorative) is decoration and must not be a gauge prop")
        }
    }
}
