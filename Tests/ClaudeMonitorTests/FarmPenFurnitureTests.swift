import XCTest
import CoreGraphics
@testable import ClaudeMonitor

private func makePen(w: Int = 10, h: Int = 6, gate: GateSide = .south,
                     label: String = "PROJ", animals: Int = 1) -> PlacedPen {
    let procs = (0..<animals).map { ClaudeProcess(pid: 300 + $0, cpu: 0, mem: 0, cwd: "/\(label)") }
    let pen = FarmPen(cwd: "/\(label)", label: label, species: .cow, processes: procs)
    return PlacedPen(pen: pen, x: 4, y: 4, w: w, h: h, gate: gate, gateX: 4 + w / 2)
}

final class FarmFenceTests: XCTestCase {
    func test_cornersUseTheSpecifiedTiles() {
        let p = makePen()
        let f = FarmPenFurniture.fenceTiles(for: p)
        func tile(_ x: Int, _ y: Int) -> Int? { f.first { $0.x == x && $0.y == y }?.tile }
        XCTAssertEqual(tile(p.x, p.y), 44)                       // top-left
        XCTAssertEqual(tile(p.x + p.w - 1, p.y), 46)             // top-right
        XCTAssertEqual(tile(p.x, p.y + p.h - 1), 68)             // bottom-left
        XCTAssertEqual(tile(p.x + p.w - 1, p.y + p.h - 1), 70)   // bottom-right
    }

    func test_railsFillTheEdges() {
        let p = makePen()
        let f = FarmPenFurniture.fenceTiles(for: p)
        let top = f.filter { $0.y == p.y && $0.x > p.x && $0.x < p.x + p.w - 1 }
        XCTAssertFalse(top.isEmpty)
        for t in top { XCTAssertEqual(t.tile, 81, "top rail should be horizontal rail 0081") }
    }

    func test_southGateLeavesATwoTileOpeningWithCappedRails() {
        let p = makePen(gate: .south)
        let f = FarmPenFurniture.fenceTiles(for: p)
        let bottomY = p.y + p.h - 1
        func tile(_ x: Int) -> Int? { f.first { $0.x == x && $0.y == bottomY }?.tile }
        XCTAssertEqual(tile(p.gateX - 1), 82, "left of the gate should cap with 0082")
        XCTAssertEqual(tile(p.gateX), 80, "right of the gate should cap with 0080")
    }

    func test_penWithNoGateIsFullyEnclosed() {
        let p = makePen(gate: .none)
        let f = FarmPenFurniture.fenceTiles(for: p)
        let bottomY = p.y + p.h - 1
        let bottomTiles = f.filter { $0.y == bottomY }
        XCTAssertEqual(bottomTiles.count, p.w, "no-gate pens have an unbroken bottom rail")
    }
}

final class FarmTroughTests: XCTestCase {
    func test_everyPenGetsABucketAndBarrel() {
        let p = makePen()
        let t = FarmPenFurniture.troughTiles(for: p)
        XCTAssertEqual(Set(t.map(\.tile)), [106, 107])
        // Bottom-left of the interior.
        XCTAssertEqual(t.map(\.y).min(), p.y + p.h - 2)
    }
}

final class FarmSignTests: XCTestCase {
    func test_labelIsUppercased() {
        XCTAssertEqual(FarmPenFurniture.signLabel(for: makePen(label: "watchagents")),
                       "WATCHAGENTS")
    }

    func test_longLabelsAreTruncatedToFitThePen() {
        let p = makePen(w: 10, label: "feat+body-type-questionnaire")
        let label = FarmPenFurniture.signLabel(for: p)
        XCTAssertLessThanOrEqual(PixelText.measure(label), (p.w - 1) * 16)
        XCTAssertTrue(label.hasSuffix("…"))
    }

    func test_surplusAnimalsAreShownAsPlusN() {
        // Occupancy is capped at 8 for pen sizing; the rest are reported on the sign.
        let label = FarmPenFurniture.signLabel(for: makePen(w: 20, label: "big", animals: 11))
        XCTAssertTrue(label.contains("+3"), "expected a +3 suffix, got \(label)")
    }

    func test_signIsCentredOnTheTopRail() {
        let p = makePen(w: 10)
        let r = FarmPenFurniture.signRect(for: p)
        let penCentre = CGFloat(p.x * 16 + p.w * 16 / 2)
        XCTAssertEqual(r.midX, penCentre, accuracy: 1.0)
        XCTAssertEqual(r.height, 15, "plateH must be 15 — at 12 the Q descender clipped")
    }
}
