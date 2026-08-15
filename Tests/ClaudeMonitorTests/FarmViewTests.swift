import XCTest
import SwiftUI
@testable import ClaudeMonitor

final class FarmViewSkeletonTests: XCTestCase {
    @MainActor
    func test_farmView_instantiates_andBodyEvaluatesWithoutCrashing() {
        let view = FarmView(viewModel: MonitorViewModel())
        _ = view.body
    }
}

final class FarmViewSceneAssemblyTests: XCTestCase {
    func test_collectSprites_sortedAscendingByBaseline() {
        let procs = (0..<6).map { ClaudeProcess(pid: $0, cpu: 0, mem: 0, cwd: "/proj\($0 % 3)") }
        let pens = FarmGrouping.pens(from: procs)
        let layout = FarmLayoutEngine.layout(pens: pens, cols: 60, rows: 40)
        let scene = buildScene(pens: pens, layout: layout)

        let sprites = collectSprites(scene: scene, time: 0)
        XCTAssertEqual(sprites.map(\.by), sprites.map(\.by).sorted())
    }

    func test_collectSprites_includesFarmerExactlyWhenBarnExists() {
        let procs = (0..<6).map { ClaudeProcess(pid: $0, cpu: 0, mem: 0, cwd: "/proj\($0 % 3)") }
        let pens = FarmGrouping.pens(from: procs)
        let layout = FarmLayoutEngine.layout(pens: pens, cols: 60, rows: 40)
        let scene = buildScene(pens: pens, layout: layout)

        XCTAssertNotNil(scene.layout.barnX)
        XCTAssertNotNil(scene.layout.barnY)

        let animalCount = scene.layout.pens.reduce(0) { $0 + FarmAnimalPlacer.place(pen: $1, time: 0).count }
        let sprites = collectSprites(scene: scene, time: 0)
        // buildScene synthesizes a barn even for empty pens, so a barn is always present
        // here and the farmer must always be the "+1" over the animal placements.
        XCTAssertEqual(sprites.count, animalCount + 1)
    }
}
