import XCTest
@testable import ClaudeMonitor

private func pen(_ path: String, _ species: AnimalSpecies, _ count: Int) -> FarmPen {
    FarmPen(
        cwd: path,
        label: (path as NSString).lastPathComponent,
        species: species,
        processes: (0..<count).map { ClaudeProcess(pid: 100 + $0, cpu: 0, mem: 0, cwd: path) }
    )
}

/// Number of distinct rows in a layout, counted by distinct pen bottom edges
/// (`y + h`) — a stand-in for a row index the struct doesn't expose.
private func rowCount(of layout: FarmLayout) -> Int {
    Set(layout.pens.map { $0.y + $0.h }).count
}

final class FarmPenSizeTests: XCTestCase {
    func test_footprintsMatchSpec() {
        XCTAssertEqual(FarmLayoutEngine.footprint(for: .cow).w, 5)
        XCTAssertEqual(FarmLayoutEngine.footprint(for: .sheep).w, 4)
        XCTAssertEqual(FarmLayoutEngine.footprint(for: .pig).w, 4)
        // Chicken is deliberately widened from its measured 2 — at 2 the slot lattice
        // crowds and birds overlap. Spec §2.1 says do not "correct" this back.
        XCTAssertEqual(FarmLayoutEngine.footprint(for: .chicken).w, 3)
    }

    func test_workedExamplesFromSpec() {
        var s = FarmLayoutEngine.penSize(species: .cow, animalCount: 1)
        XCTAssertEqual([s.w, s.h], [8, 6])
        s = FarmLayoutEngine.penSize(species: .cow, animalCount: 2)
        XCTAssertEqual([s.w, s.h], [13, 6])
        s = FarmLayoutEngine.penSize(species: .pig, animalCount: 1)
        XCTAssertEqual([s.w, s.h], [7, 5])
        s = FarmLayoutEngine.penSize(species: .chicken, animalCount: 4)
        XCTAssertEqual([s.w, s.h], [9, 6])
    }

    func test_neverBelowMinimumPenSize() {
        let s = FarmLayoutEngine.penSize(species: .chicken, animalCount: 1)
        XCTAssertGreaterThanOrEqual(s.w, 7)
        XCTAssertGreaterThanOrEqual(s.h, 5)
    }

    func test_capsOccupancyAtEight() {
        let eight = FarmLayoutEngine.penSize(species: .chicken, animalCount: 8)
        let twenty = FarmLayoutEngine.penSize(species: .chicken, animalCount: 20)
        XCTAssertEqual([eight.w, eight.h], [twenty.w, twenty.h],
                       "surplus animals are shown as +N on the sign, not by growing the pen")
    }
}

final class FarmLayoutTests: XCTestCase {
    func test_firstPenSitsBesideTheBarnWhenTheWindowIsWideEnough() {
        // cols must clear the §2.4 fit rule: 13 + barnW(7) + gap(2) + 1 + margins(8) = 31.
        let layout = FarmLayoutEngine.layout(pens: [pen("/a", .cow, 2)], cols: 40, rows: 40)
        let placed = layout.pens[0]
        XCTAssertEqual(placed.x, FarmLayoutEngine.marginL + FarmLayoutEngine.barnW + FarmLayoutEngine.gap + 1,
                       "row 0 must reserve the barn's slot")
        XCTAssertLessThanOrEqual(placed.x + placed.w, 40 - FarmLayoutEngine.marginR)
    }

    func test_narrowWindowDegradesWithoutCorruptingTheLayout() {
        // Below the fit rule the layout can't be pretty, but it must never be corrupt:
        // no phantom lanes, no off-canvas barn, no gate on a single-row layout.
        let layout = FarmLayoutEngine.layout(pens: [pen("/a", .cow, 2)], cols: 24, rows: 40)
        XCTAssertEqual(layout.pens.count, 1, "pens are never dropped")
        if let by = layout.barnY { XCTAssertGreaterThanOrEqual(by, 0, "barn placed off-canvas") }
        XCTAssertEqual(layout.laneYs.count, max(0, rowCount(of: layout) - 1),
                       "a lane exists only between two real rows")
        if rowCount(of: layout) == 1 {
            XCTAssertEqual(layout.pens[0].gate, .south,
                           "single-row layouts still gate south (mock7.py:114), even with no lane on the other side")
        }
    }

    func test_penOrderMatchesInputOrder() {
        let pens = [pen("/a", .cow, 1), pen("/b", .pig, 1), pen("/c", .sheep, 1)]
        let layout = FarmLayoutEngine.layout(pens: pens, cols: 60, rows: 40)
        XCTAssertEqual(layout.pens.map { $0.pen.cwd }, ["/a", "/b", "/c"],
                       "layout must never reorder pens — ordering is settled upstream")
    }

    func test_pensInARowAreBottomAligned() {
        // A tall pen beside a short one: their bottom edges must line up, giving the
        // ragged top edge that stops the scene reading as a grid of cards.
        let layout = FarmLayoutEngine.layout(
            pens: [pen("/tall", .cow, 2), pen("/short", .pig, 1)],
            cols: 60, rows: 40
        )
        let a = layout.pens[0], b = layout.pens[1]
        XCTAssertEqual(a.y + a.h, b.y + b.h, "pens in a row must be bottom-aligned")
    }

    func test_lanesSitBetweenRows() {
        let pens = (0..<8).map { pen("/p\($0)", .cow, 1) }
        let layout = FarmLayoutEngine.layout(pens: pens, cols: 46, rows: 40)
        XCTAssertGreaterThan(layout.laneYs.count, 0, "multi-row layouts need dirt lanes")
        for laneY in layout.laneYs {
            for placed in layout.pens {
                let penBottom = placed.y + placed.h
                XCTAssertFalse(laneY < penBottom && laneY + 2 > placed.y,
                               "lane at \(laneY) overlaps pen at \(placed.y)..<\(penBottom)")
            }
        }
    }

    func test_emptyInputProducesEmptyLayout() {
        let layout = FarmLayoutEngine.layout(pens: [], cols: 46, rows: 28)
        XCTAssertTrue(layout.pens.isEmpty)
        XCTAssertTrue(layout.laneYs.isEmpty)
    }

    func test_reportsRequiredRowsWhenItOverflows() {
        let pens = (0..<30).map { pen("/p\($0)", .cow, 1) }
        let layout = FarmLayoutEngine.layout(pens: pens, cols: 46, rows: 20)
        XCTAssertGreaterThan(layout.requiredRows, 20,
                             "caller needs to know it must scroll")
        XCTAssertEqual(layout.pens.count, 30, "never drop pens — scroll instead")
    }

    func test_everyPenStaysWithinHorizontalMargins() {
        let pens = (0..<14).map { pen("/p\($0)", [.cow, .pig, .sheep, .chicken][$0 % 4], 1 + $0 % 3) }
        let layout = FarmLayoutEngine.layout(pens: pens, cols: 52, rows: 60)
        for placed in layout.pens {
            XCTAssertGreaterThanOrEqual(placed.x, 4)
            XCTAssertLessThanOrEqual(placed.x + placed.w, 52 - 4)
        }
    }

    func test_gateAndGateXOnMultiRowLayout() {
        let pens = (0..<8).map { pen("/p\($0)", .cow, 1) }
        let layout = FarmLayoutEngine.layout(pens: pens, cols: 46, rows: 40)
        let bottoms = Set(layout.pens.map { $0.y + $0.h })
        XCTAssertGreaterThan(bottoms.count, 1, "expected a multi-row layout for this fixture")
        let lastBottom = bottoms.max()!
        for placed in layout.pens {
            let bottom = placed.y + placed.h
            if bottom == lastBottom {
                XCTAssertEqual(placed.gate, .north, "last row gates north onto the lane above")
            } else {
                XCTAssertEqual(placed.gate, .south, "non-last rows gate south onto the lane below")
            }
            XCTAssertEqual(placed.gateX, placed.x + placed.w / 2)
        }
    }

    func test_barnXAndBarnYOnNormalLayout() {
        let layout = FarmLayoutEngine.layout(pens: [pen("/a", .cow, 1)], cols: 40, rows: 40)
        XCTAssertEqual(layout.barnX, FarmLayoutEngine.marginL)
        let row0Bottom = layout.pens.map { $0.y + $0.h }.max()!
        XCTAssertEqual(layout.barnY, row0Bottom - FarmLayoutEngine.barnH)
    }

    func test_pensNeverOverlapEachOther() {
        let pens = (0..<14).map { pen("/p\($0)", [.cow, .pig, .sheep, .chicken][$0 % 4], 1 + $0 % 3) }
        let layout = FarmLayoutEngine.layout(pens: pens, cols: 52, rows: 60)
        for i in 0..<layout.pens.count {
            for j in (i + 1)..<layout.pens.count {
                let a = layout.pens[i], b = layout.pens[j]
                let disjoint = a.x + a.w <= b.x || b.x + b.w <= a.x
                            || a.y + a.h <= b.y || b.y + b.h <= a.y
                XCTAssertTrue(disjoint, "pens \(i) and \(j) overlap")
            }
        }
    }
}
