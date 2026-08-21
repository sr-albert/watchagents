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

    /// The 0017 sprout is two thin stems inside a heavy dark outline. At farm scale the
    /// green all but vanishes and it reads as a dark squiggle dropped on the lawn, so it
    /// is out; mushrooms carry the ground detail instead. The 0094 beehive stays a
    /// deliberate single prop by the barn and never joins the hay yard, where it just
    /// looks like a hay bale someone drew a hole in.
    func test_theLawnCarriesNoSproutsAndTheHayYardIsAllHay() {
        let (layout, dirt) = fixture(8)
        let scenery = FarmScenery.decorate(layout: layout, dirt: dirt)

        XCTAssertFalse(scenery.contains { $0.tile == 17 })
        XCTAssertLessThanOrEqual(scenery.filter { $0.tile == 94 }.count, 1)
    }

    func test_staysInsideTheCanvas() {
        let (layout, dirt) = fixture(8)
        for s in FarmScenery.decorate(layout: layout, dirt: dirt) {
            XCTAssertTrue((0..<layout.cols).contains(s.x))
            XCTAssertTrue((0..<layout.rows).contains(s.y))
        }
    }
}

/// The barn is the only thing in the scene you can open. Its doors rest shut so that
/// opening them means something — before this it stood permanently agape (tile 0074
/// twice, a dark hole), and there was no state left to change.
final class FarmBarnDoorTests: XCTestCase {
    private func doors(_ tiles: [SceneryTile]) -> [Int] {
        let gy = 3 + FarmLayoutEngine.barnH - 1
        let cx = 4 + FarmLayoutEngine.barnW / 2
        return [cx - 1, cx].compactMap { x in
            tiles.last { $0.x == x && $0.y == gy }?.tile
        }
    }

    func test_theBarnRestsWithItsDoorsShut() {
        XCTAssertEqual(doors(FarmScenery.barnTiles(x: 4, y: 3)), [85, 87])
    }

    /// The last tile painted at each door cell is the dark opening 0074.
    func test_theOpenDoorsAreTheDarkOpening() {
        let open = FarmScenery.barnDoorTiles(x: 4, y: 3, open: true)
        let gy = 3 + FarmLayoutEngine.barnH - 1
        let cx = 4 + FarmLayoutEngine.barnW / 2
        for x in [cx - 1, cx] {
            XCTAssertEqual(open.last { $0.x == x && $0.y == gy }?.tile, 74)
        }
    }

    /// 0074 is an arch with transparent corners, drawn to composite onto a wall. Laid
    /// straight over the shut door those corners show the brown panels through, and the
    /// barn reads as open and closed at the same time — so the wall goes down first.
    func test_openingTheDoorsRepaintsTheWallUnderneath() {
        let open = FarmScenery.barnDoorTiles(x: 4, y: 3, open: true)
        let gy = 3 + FarmLayoutEngine.barnH - 1
        let cx = 4 + FarmLayoutEngine.barnW / 2
        for x in [cx - 1, cx] {
            let atCell = open.filter { $0.x == x && $0.y == gy }.map(\.tile)
            XCTAssertEqual(atCell, [73, 74], "the wall must be repainted before the opening")
        }
    }

    /// The open state is drawn over the shut one as an overlay, so it has to land on
    /// exactly the same two cells or the barn grows a third door.
    func test_openAndShutDoorsOccupyTheSameCells() {
        func cells(_ open: Bool) -> Set<TilePoint> {
            Set(FarmScenery.barnDoorTiles(x: 4, y: 3, open: open)
                .map { TilePoint(x: $0.x, y: $0.y) })
        }
        XCTAssertEqual(cells(true), cells(false))
    }

    func test_theDoorsSitOnTheBarnsGroundRow() {
        for t in FarmScenery.barnDoorTiles(x: 4, y: 3, open: true) {
            XCTAssertEqual(t.y, 3 + FarmLayoutEngine.barnH - 1)
            XCTAssertTrue((4..<(4 + FarmLayoutEngine.barnW)).contains(t.x))
        }
    }
}
