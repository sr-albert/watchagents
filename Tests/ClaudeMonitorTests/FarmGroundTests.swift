import XCTest
@testable import ClaudeMonitor

final class StableHashTests: XCTestCase {
    func test_isDeterministicAcrossCalls() {
        XCTAssertEqual(StableHash.of(3, 7, 11), StableHash.of(3, 7, 11))
    }

    func test_differentInputsDiffer() {
        XCTAssertNotEqual(StableHash.of(1, 2), StableHash.of(2, 1))
        XCTAssertNotEqual(StableHash.of(1, 2), StableHash.of(1, 3))
    }

    func test_handlesNegativeCoordinates() {
        // Tile coords can go negative near the margins; this must not trap.
        XCTAssertEqual(StableHash.of(-4, -9), StableHash.of(-4, -9))
    }
}

final class FarmGroundTests: XCTestCase {
    func test_grassTileIsStableForACell() {
        XCTAssertEqual(FarmGround.grassTile(x: 12, y: 5), FarmGround.grassTile(x: 12, y: 5))
    }

    func test_grassTileOnlyReturnsGrassVariants() {
        for y in 0..<40 {
            for x in 0..<60 {
                let t = FarmGround.grassTile(x: x, y: y)
                XCTAssertTrue([0, 1, 2].contains(t), "unexpected ground tile \(t) at \(x),\(y)")
            }
        }
    }

    func test_plainGrassDominatesButVariationExists() {
        var counts: [Int: Int] = [:]
        for y in 0..<40 {
            for x in 0..<60 {
                counts[FarmGround.grassTile(x: x, y: y), default: 0] += 1
            }
        }
        let total = 40 * 60
        // Plain grass must dominate, or the field reads as noise (the mockup3 failure).
        XCTAssertGreaterThan(counts[0] ?? 0, total * 70 / 100)
        // ...but variation must actually appear, or the field is a flat green slab.
        XCTAssertGreaterThan(counts[1] ?? 0, 0, "no grass tufts generated")
    }

    func test_variationFormsClumpsNotStatic() {
        // Neighbours of a tuft should be tufts far more often than the global rate —
        // that is what makes variation read as regions instead of confetti.
        var tufts = 0, tuftNeighbours = 0, sampled = 0
        for y in 1..<39 {
            for x in 1..<59 {
                if FarmGround.grassTile(x: x, y: y) == 1 {
                    tufts += 1
                    for (dx, dy) in [(1, 0), (-1, 0), (0, 1), (0, -1)] {
                        sampled += 1
                        if FarmGround.grassTile(x: x + dx, y: y + dy) == 1 { tuftNeighbours += 1 }
                    }
                }
            }
        }
        XCTAssertGreaterThan(tufts, 0)
        let neighbourRate = Double(tuftNeighbours) / Double(sampled)
        XCTAssertGreaterThan(neighbourRate, 0.20, "tufts are scattered, not clumped")
    }
}
