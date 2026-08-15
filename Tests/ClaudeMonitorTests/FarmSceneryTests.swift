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

    func test_treesFormBandsNotScatteredLollipops() {
        // Spec §6.2: canopy tiles used as bands make a forest; used individually they
        // make a field of lollipops. Canopy tops (0006/0007/0008) should mostly have a
        // horizontal canopy neighbour.
        let (layout, dirt) = fixture(8)
        let scenery = FarmScenery.decorate(layout: layout, dirt: dirt)
        let canopy = Set(scenery.filter { [6, 7, 8, 9, 10, 11].contains($0.tile) }
                                .map { TilePoint(x: $0.x, y: $0.y) })
        XCTAssertGreaterThan(canopy.count, 8, "hardly any canopy was placed")
        let withNeighbour = canopy.filter {
            canopy.contains(TilePoint(x: $0.x - 1, y: $0.y))
                || canopy.contains(TilePoint(x: $0.x + 1, y: $0.y))
        }
        XCTAssertGreaterThan(Double(withNeighbour.count) / Double(canopy.count), 0.75,
                             "canopy tiles are isolated — they read as lollipops")
    }

    func test_staysInsideTheCanvas() {
        let (layout, dirt) = fixture(8)
        for s in FarmScenery.decorate(layout: layout, dirt: dirt) {
            XCTAssertTrue((0..<layout.cols).contains(s.x))
            XCTAssertTrue((0..<layout.rows).contains(s.y))
        }
    }
}
