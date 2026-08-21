import XCTest
import SwiftUI
import CoreGraphics
@testable import ClaudeMonitor

/// Normalises any `CGImage` into a 16x16 RGBA buffer so two tiles can be compared byte
/// for byte regardless of the colour space or alpha layout they arrived in.
private func tileBytes(_ image: CGImage) -> [UInt8] {
    var data = [UInt8](repeating: 0, count: 16 * 16 * 4)
    let ctx = CGContext(data: &data, width: 16, height: 16, bitsPerComponent: 8,
                        bytesPerRow: 16 * 4, space: CGColorSpaceCreateDeviceRGB(),
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.draw(image, in: CGRect(x: 0, y: 0, width: 16, height: 16))
    return data
}

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

    /// Fix 3: the static layer (ground/dirt/scenery/fences/troughs) must be memoized
    /// across calls that share the same geometry key, and invalidated the moment that
    /// key actually changes — a cache that never hits or one that always hits would
    /// both pass every other test in this file, since they all call `buildScene` once.
    func test_buildScene_memoizesStaticLayerByGeometryOnly() {
        let procsA = (0..<4).map { ClaudeProcess(pid: $0, cpu: 0, mem: 0, cwd: "/proj\($0 % 2)") }
        let pensA = FarmGrouping.pens(from: procsA)
        let layoutA = FarmLayoutEngine.layout(pens: pensA, cols: 60, rows: 40)

        let first = buildScene(pens: pensA, layout: layoutA)
        let second = buildScene(pens: pensA, layout: layoutA)
        XCTAssertNotNil(first.staticImage)
        XCTAssertTrue(first.staticImage === second.staticImage,
                      "same (cwd, species, count, cols, rows) must reuse the cached static image")

        // Change one pen's process count (same cwd/species) — this changes pen
        // geometry (occupancy affects pen size), so it must invalidate the cache.
        var procsB = procsA
        procsB.append(ClaudeProcess(pid: 99, cpu: 0, mem: 0, cwd: "/proj0"))
        let pensB = FarmGrouping.pens(from: procsB)
        let layoutB = FarmLayoutEngine.layout(pens: pensB, cols: 60, rows: 40)
        let third = buildScene(pens: pensB, layout: layoutB)
        XCTAssertFalse(third.staticImage === second.staticImage,
                       "a pen's occupancy change must invalidate the cached static image")

        // ...and a later call back on the original geometry must still hit the cache
        // (the cache holds the *last* key, not a one-shot dirty flag).
        let fourth = buildScene(pens: pensA, layout: layoutA)
        XCTAssertFalse(fourth.staticImage === third.staticImage,
                       "returning to the original geometry must not reuse the now-stale cached image")
    }

    /// The seam between the renderer and `FarmHitTest`: every animal sprite must carry
    /// the session it stands for, and the tile-0103 barn-door fixture must not — it is
    /// scenery riding in the same depth-sorted list, and selecting it would be nonsense.
    func test_collectSprites_carriesThePIDOfEveryAnimalAndNoneForTheFixture() {
        let procs = (0..<6).map { ClaudeProcess(pid: 100 + $0, cpu: 0, mem: 0, cwd: "/proj\($0 % 3)") }
        let pens = FarmGrouping.pens(from: procs)
        let layout = FarmLayoutEngine.layout(pens: pens, cols: 60, rows: 40)
        let scene = buildScene(pens: pens, layout: layout)

        let sprites = collectSprites(scene: scene, time: 0)

        XCTAssertEqual(sprites.compactMap(\.pid).sorted(), procs.map(\.pid).sorted())
        XCTAssertEqual(sprites.filter { $0.pid == nil }.count, 1)
    }

    /// The static layer must blit each tile the way it was drawn. `renderStaticLayer`
    /// flips its coordinate system so tile rows run top-down, and that flip applies to
    /// the image content too unless it is undone per blit — which put every tile in the
    /// right cell upside down. It cost two rewrites of the woodland before anyone
    /// noticed, because the symptom looks exactly like bad art.
    ///
    /// Checked on tile 0094, the beehive beside the barn: strongly asymmetric top to
    /// bottom, and at a position fixed by `barnTiles`.
    func test_staticLayerBlitsTilesTheRightWayUp() throws {
        let procs = (0..<4).map { ClaudeProcess(pid: 100 + $0, cpu: 0, mem: 0, cwd: "/p\($0)") }
        let pens = FarmGrouping.pens(from: procs)
        let layout = FarmLayoutEngine.layout(pens: pens, cols: 46, rows: 28)
        let scene = buildScene(pens: pens, layout: layout)

        let image = try XCTUnwrap(scene.staticImage)
        let bx = try XCTUnwrap(scene.layout.barnX)
        let by = try XCTUnwrap(scene.layout.barnY)
        let hiveX = bx + FarmLayoutEngine.barnW + 1
        let hiveY = by + FarmLayoutEngine.barnH - 1
        let drawn = try XCTUnwrap(image.cropping(
            to: CGRect(x: hiveX * 16, y: hiveY * 16, width: 16, height: 16)))

        // Only the tile's own opaque pixels: the cell in the scene has grass composited
        // behind the hive, which the source tile leaves transparent.
        let inScene = tileBytes(drawn)
        let source = tileBytes(try XCTUnwrap(FarmAssets.tile(94)))
        var compared = 0
        for i in stride(from: 0, to: source.count, by: 4) where source[i + 3] == 255 {
            compared += 1
            XCTAssertEqual(Array(inScene[i..<(i + 3)]), Array(source[i..<(i + 3)]),
                           "tile 0094 differs from the source at byte \(i) — the static "
                           + "layer is not blitting it as it was drawn")
        }
        XCTAssertGreaterThan(compared, 100, "the fixture found no hive to compare")
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
