import XCTest
@testable import ClaudeMonitor

final class FarmSceneryTests: XCTestCase {
    private func fixture(_ n: Int, cols: Int = 46, rows: Int = 28)
        -> (FarmLayout, Set<TilePoint>) {
        let pens = (0..<n).map { i -> FarmPen in
            let path = "/p\(i)"
            return FarmPen(cwd: path, label: "p\(i)", species: .cow,
                           processes: [ClaudeProcess(pid: 100 + i, cpu: 0, mem: 0, cwd: path)])
        }
        let l = FarmLayoutEngine.layout(pens: pens, cols: cols, rows: rows)
        return (l, FarmDirt.dirtCells(layout: l))
    }

    func test_barnIsSevenByFour() {
        let tiles = FarmScenery.barnTiles(x: 4, y: 3)
        let xs = tiles.map(\.x), ys = tiles.map(\.y)
        XCTAssertEqual(xs.max()! - xs.min()! + 1, 7)
        XCTAssertEqual(ys.max()! - ys.min()! + 1, 4)
    }

    func test_sceneryNeverCollidesWithPens() {
        let (layout, dirt) = fixture(8)
        let scenery = FarmScenery.decorate(layout: layout, dirt: dirt)
        for s in scenery {
            for p in layout.pens {
                let inside = s.x >= p.x && s.x < p.x + p.w && s.y >= p.y && s.y < p.y + p.h
                XCTAssertFalse(inside, "scenery tile \(s.tile) at \(s.x),\(s.y) is inside a pen")
            }
        }
    }

    func test_sceneryNeverCoversDirt() {
        let (layout, dirt) = fixture(8)
        for s in FarmScenery.decorate(layout: layout, dirt: dirt) {
            XCTAssertFalse(dirt.contains(TilePoint(x: s.x, y: s.y)),
                           "scenery is blocking a road at \(s.x),\(s.y)")
        }
    }

    func test_sceneryIsDeterministic() {
        let (layout, dirt) = fixture(6)
        XCTAssertEqual(FarmScenery.decorate(layout: layout, dirt: dirt),
                       FarmScenery.decorate(layout: layout, dirt: dirt))
    }

    /// Canopy tops, either season. `smallTree` draws 0004 (or autumn 0003) over a trunk.
    private func canopyCells(_ scenery: [SceneryTile]) -> Set<TilePoint> {
        Set(scenery.filter { $0.tile == 3 || $0.tile == 4 }
                   .map { TilePoint(x: $0.x, y: $0.y) })
    }

    func test_woodlandIsDenseStandsAndNotRetiredCanopyBands() {
        // Spec §6.2, as corrected 2026-08-16: 0006-0008 over 0018-0020 are forest-
        // *interior* pieces whose outlines are drawn to continue into their neighbours.
        // With open grass above, the top arcs dangle and the band reads upside down.
        // Woodland is dense stands of the 2-tall single tree instead — packed tightly
        // enough that canopies touch, rather than standing apart as lollipops.
        let (layout, dirt) = fixture(8)
        let scenery = FarmScenery.decorate(layout: layout, dirt: dirt)

        let retired: Set<Int> = [6, 7, 8, 9, 10, 11, 18, 19, 20, 21, 22, 23]
        XCTAssertFalse(scenery.contains { retired.contains($0.tile) },
                       "canopy-band tiles are retired from the design — they read upside down")

        let canopy = canopyCells(scenery)
        XCTAssertGreaterThan(canopy.count, 40, "hardly any woodland was placed")
        // A neighbour one row up or down still touches: placement jitters trees by a
        // tile vertically, and a canopy at (x+1, y+1) sits directly beside this tree's
        // trunk. Same-row-only adjacency would score a perfectly dense stand at ~0.6.
        let touching = canopy.filter { cell in
            (-1...1).contains { dy in
                canopy.contains(TilePoint(x: cell.x - 1, y: cell.y + dy))
                    || canopy.contains(TilePoint(x: cell.x + 1, y: cell.y + dy))
            }
        }
        XCTAssertGreaterThan(Double(touching.count) / Double(canopy.count), 0.75,
                             "trees stand apart — that is a field of lollipops, not a stand")
    }

    func test_theTopTreelineThinsInward() {
        // The density ramp is what makes the treeline ragged instead of a solid ribbon.
        // Compared in pairs of rows rather than row by row: a tree gets one tile of
        // vertical jitter, so any single row draws from two source rows of the ramp.
        let (layout, dirt) = fixture(8)
        let canopy = canopyCells(FarmScenery.decorate(layout: layout, dirt: dirt))
        let outer = canopy.filter { $0.y <= 1 }.count
        let inner = canopy.filter { $0.y == 2 || $0.y == 3 }.count
        XCTAssertGreaterThan(outer, inner, "the top treeline is not thinning inward")
    }

    func test_staysInsideTheCanvas() {
        let (layout, dirt) = fixture(8)
        for s in FarmScenery.decorate(layout: layout, dirt: dirt) {
            XCTAssertTrue((0..<layout.cols).contains(s.x))
            XCTAssertTrue((0..<layout.rows).contains(s.y))
        }
    }
}
