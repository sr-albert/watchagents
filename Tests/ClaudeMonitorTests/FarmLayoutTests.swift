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
    func test_wrapsTheFirstPenWhenItCannotFitBesideTheBarn() {
        // Regression: the wrap test must run even when the row is empty. If it is
        // guarded by `row.notEmpty`, the first pen of row 0 lands past the barn
        // regardless of window width and runs off the right edge.
        let layout = FarmLayoutEngine.layout(
            pens: [pen("/a", .cow, 2)],   // 13 wide
            cols: 24, rows: 40            // too narrow for barn(7)+gap(2)+1+13+margins
        )
        let placed = layout.pens[0]
        XCTAssertLessThanOrEqual(placed.x + placed.w, 24 - 4,
                                 "pen overflows the right margin")
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
