import XCTest
@testable import ClaudeMonitor

final class FarmDirtTests: XCTestCase {
    private func layout(_ n: Int, cols: Int = 46, rows: Int = 40) -> FarmLayout {
        let pens = (0..<n).map { i -> FarmPen in
            let path = "/p\(i)"
            return FarmPen(cwd: path, label: "p\(i)", species: .cow,
                           processes: [ClaudeProcess(pid: 100 + i, cpu: 0, mem: 0, cwd: path)])
        }
        return FarmLayoutEngine.layout(pens: pens, cols: cols, rows: rows)
    }

    func test_lanesBecomeDirt() {
        let l = layout(8)
        let dirt = FarmDirt.dirtCells(layout: l)
        XCTAssertFalse(l.laneYs.isEmpty)
        for laneY in l.laneYs {
            XCTAssertTrue(dirt.contains(TilePoint(x: l.marginL + 2, y: laneY)),
                          "lane row \(laneY) should be dirt")
        }
    }

    func test_lanesTerminateInsideTheMargins() {
        let l = layout(8)
        let dirt = FarmDirt.dirtCells(layout: l)
        for cell in dirt {
            XCTAssertGreaterThanOrEqual(cell.x, l.marginL)
            XCTAssertLessThan(cell.x, l.cols - l.marginR)
        }
    }

    func test_dirtIsDeterministic() {
        let l = layout(6)
        XCTAssertEqual(FarmDirt.dirtCells(layout: l), FarmDirt.dirtCells(layout: l))
    }

    func test_penWearStaysInsideItsPen() {
        let l = layout(4)
        let dirt = FarmDirt.dirtCells(layout: l)
        // Every dirt cell is either in a lane, in the barn spur column range, or inside
        // some pen's interior — never inside a pen's fence ring.
        for placed in l.pens {
            for cell in dirt where cell.x == placed.x || cell.x == placed.x + placed.w - 1 {
                let insideVertically = cell.y > placed.y && cell.y < placed.y + placed.h - 1
                XCTAssertFalse(insideVertically,
                               "wear must not sit under the vertical fence rails")
            }
        }
    }

    func test_autotilePicksEdgeTilesForABlob() {
        // A 3x3 solid blob: corners get corner tiles, centre gets an interior fill.
        var dirt = Set<TilePoint>()
        for y in 0..<3 { for x in 0..<3 { dirt.insert(TilePoint(x: x, y: y)) } }
        XCTAssertEqual(FarmDirt.tile(at: TilePoint(x: 0, y: 0), in: dirt), 12) // N+W free
        XCTAssertEqual(FarmDirt.tile(at: TilePoint(x: 2, y: 0), in: dirt), 14) // N+E free
        XCTAssertEqual(FarmDirt.tile(at: TilePoint(x: 0, y: 2), in: dirt), 36) // S+W free
        XCTAssertEqual(FarmDirt.tile(at: TilePoint(x: 2, y: 2), in: dirt), 38) // S+E free
        XCTAssertEqual(FarmDirt.tile(at: TilePoint(x: 1, y: 0), in: dirt), 13) // N free
        XCTAssertEqual(FarmDirt.tile(at: TilePoint(x: 1, y: 2), in: dirt), 37) // S free
        XCTAssertEqual(FarmDirt.tile(at: TilePoint(x: 0, y: 1), in: dirt), 24) // W free
        XCTAssertEqual(FarmDirt.tile(at: TilePoint(x: 2, y: 1), in: dirt), 26) // E free
        let centre = FarmDirt.tile(at: TilePoint(x: 1, y: 1), in: dirt)
        XCTAssertTrue([25, 39, 40, 41, 42].contains(centre),
                      "interior should use a fill variant, got \(centre)")
    }

    /// Fix 4: locks the cross-file invariant `FarmDirt` relies on but doesn't itself
    /// enforce — `FarmDirt.dirtCells`'s south-gate threshold derives
    /// `laneY = placed.y + placed.h`, which is only correct because
    /// `FarmLayoutEngine.layout` bottom-aligns every pen within its row
    /// (`y: y + (rowH - item.h)`). If that ever stopped being true, the gate threshold
    /// would stop lining up with the lane and this test would catch it, not a
    /// screenshot.
    func test_gateThresholdConnectsGateToLaneWithNoGap() {
        let l = layout(8) // multi-row fixture: some pens south-gated, some north-gated.
        let dirt = FarmDirt.dirtCells(layout: l)
        XCTAssertFalse(l.laneYs.isEmpty, "fixture must actually be multi-row")

        var checkedSouth = false, checkedNorth = false
        for placed in l.pens {
            let gx = placed.gateX
            switch placed.gate {
            case .south:
                checkedSouth = true
                // The cross-file invariant itself: the lane this pen gates onto is
                // exactly its own bottom edge.
                let laneY = placed.y + placed.h
                XCTAssertTrue(l.laneYs.contains(laneY),
                              "south gate at pen y=\(placed.y) expects a lane at \(laneY)")
                // Continuous chain: gate-inside cell (`iy+ih-1` == `y+h-2`) ->
                // threshold (`y+h-1`) -> both lane rows (`laneY`, `laneY+1`).
                let start = placed.y + placed.h - 2
                let end = laneY + FarmLayoutEngine.laneH - 1
                for y in start...end {
                    XCTAssertTrue(dirt.contains(TilePoint(x: gx - 1, y: y)),
                                  "gap at (\(gx - 1), \(y)) in the south gate-to-lane chain")
                    XCTAssertTrue(dirt.contains(TilePoint(x: gx, y: y)),
                                  "gap at (\(gx), \(y)) in the south gate-to-lane chain")
                }
            case .north:
                checkedNorth = true
                guard let laneY = l.laneYs.last else { continue }
                // Continuous chain: both lane rows -> threshold -> gate-inside cell.
                for y in laneY...(placed.y + 1) {
                    XCTAssertTrue(dirt.contains(TilePoint(x: gx - 1, y: y)),
                                  "gap at (\(gx - 1), \(y)) in the north gate-to-lane chain")
                    XCTAssertTrue(dirt.contains(TilePoint(x: gx, y: y)),
                                  "gap at (\(gx), \(y)) in the north gate-to-lane chain")
                }
            case .none:
                break
            }
        }
        XCTAssertTrue(checkedSouth, "fixture must include at least one south-gated pen")
        XCTAssertTrue(checkedNorth, "fixture must include at least one north-gated pen")
    }

    func test_interiorFillIsStablePerCell() {
        var dirt = Set<TilePoint>()
        for y in 0..<5 { for x in 0..<5 { dirt.insert(TilePoint(x: x, y: y)) } }
        let p = TilePoint(x: 2, y: 2)
        XCTAssertEqual(FarmDirt.tile(at: p, in: dirt), FarmDirt.tile(at: p, in: dirt))
    }
}
