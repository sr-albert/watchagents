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

    func test_retiredCanopyBandTilesNeverAppear() {
        // 0006-0008 over 0018-0020 (and the autumn variants) are forest-interior pieces:
        // their outlines are drawn to continue into neighbouring tiles, so against open
        // grass the top arcs dangle and the band reads as an upside-down cave ceiling.
        // They are out of the design; this pins them out.
        let (layout, dirt) = fixture(8)
        let scenery = FarmScenery.decorate(layout: layout, dirt: dirt)

        let retired: Set<Int> = [6, 7, 8, 9, 10, 11, 18, 19, 20, 21, 22, 23]
        XCTAssertFalse(scenery.contains { retired.contains($0.tile) })
    }

    /// No trees and no scattered bushes anywhere. Two attempts at a treeline both read
    /// badly (see the note in `decorate`), and sprinkling single bushes across open
    /// ground is confetti. What decorates the scene now is the farm itself — the barn and
    /// its yard, the pens, the roads, the hay — over ground detail. Pinned so a later
    /// pass has to change this test deliberately rather than by accident.
    func test_nothingPlantsTreesOrBushes() {
        let (layout, dirt) = fixture(8)
        let scenery = FarmScenery.decorate(layout: layout, dirt: dirt)

        // 0003/0004 canopies over 0015/0016 trunks, and the 0005/0027/0028 bushes.
        let flora: Set<Int> = [3, 4, 5, 15, 16, 27, 28]
        XCTAssertEqual(scenery.filter { flora.contains($0.tile) }, [])
    }

    func test_staysInsideTheCanvas() {
        let (layout, dirt) = fixture(8)
        for s in FarmScenery.decorate(layout: layout, dirt: dirt) {
            XCTAssertTrue((0..<layout.cols).contains(s.x))
            XCTAssertTrue((0..<layout.rows).contains(s.y))
        }
    }
}
