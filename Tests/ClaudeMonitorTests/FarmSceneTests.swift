import XCTest
import CoreGraphics
@testable import ClaudeMonitor

final class FarmSceneScaleTests: XCTestCase {
    func test_prefersLargerScaleWhenItFits() {
        // A small layout in a big window should render chunky, not tiny.
        let s = FarmScene.scale(cols: 20, rows: 12, width: 1600, height: 1000)
        XCTAssertEqual(s, 3)
    }

    func test_dropsToSmallerScaleWhenTheLayoutIsWide() {
        let s = FarmScene.scale(cols: 46, rows: 28, width: 1000, height: 700)
        XCTAssertLessThan(s, 3)
        XCTAssertGreaterThanOrEqual(s, 1)
    }

    func test_neverReturnsZeroOrFractional() {
        for w in stride(from: 320.0, to: 2600.0, by: 137.0) {
            for h in stride(from: 240.0, to: 1600.0, by: 149.0) {
                let s = FarmScene.scale(cols: 46, rows: 28, width: w, height: h)
                XCTAssertTrue([1, 2, 3].contains(s), "scale \(s) at \(w)x\(h)")
            }
        }
    }
}

final class FarmSceneDrawOrderTests: XCTestCase {
    func test_animalsAreSortedBackToFrontByBaseline() {
        // Spec §5.4: one y-sort provides the depth cue that lets front-rank animals
        // occlude the bottom rail and each other.
        let procs = (0..<4).map { ClaudeProcess(pid: 400 + $0, cpu: 0, mem: 0, cwd: "/p") }
        let pen = FarmPen(cwd: "/p", label: "p", species: .chicken, processes: procs)
        let size = FarmLayoutEngine.penSize(species: .chicken, animalCount: 4)
        let placed = PlacedPen(pen: pen, x: 3, y: 3, w: size.w, h: size.h,
                               gate: .south, gateX: 3 + size.w / 2)
        let sorted = FarmScene.drawOrder(FarmAnimalPlacer.place(pen: placed, time: 0))
        XCTAssertEqual(sorted.map(\.by), sorted.map(\.by).sorted())
    }
}
