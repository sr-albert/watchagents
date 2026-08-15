import XCTest
import CoreGraphics
@testable import ClaudeMonitor

private func makePens(_ specs: [(species: AnimalSpecies, count: Int)]) -> [FarmPen] {
    specs.enumerated().map { i, spec in
        let procs = (0..<spec.count).map { ClaudeProcess(pid: i * 100 + $0, cpu: 0, mem: 0, cwd: "/p\(i)") }
        return FarmPen(cwd: "/p\(i)", label: "p\(i)", species: spec.species, processes: procs)
    }
}

final class FarmSceneSelectScaleAndLayoutTests: XCTestCase {
    func test_prefersLargerScaleWhenItFits() {
        // A small layout in a big window should render chunky, not tiny.
        let pens = makePens([(.chicken, 2), (.chicken, 2)])
        let (scale, layout) = FarmScene.selectScaleAndLayout(pens: pens, width: 1600, height: 1000)
        XCTAssertEqual(scale, 3)
        XCTAssertLessThanOrEqual(layout.requiredRows, Int(1000) / (16 * scale))
    }

    func test_dropsToSmallerScaleWhenTheLayoutIsWide() {
        // Hand-verified: eight 13-wide cow pens give minCols = 13 + barnW(7) + gap(2) + 1 +
        // marginL(4) + marginR(4) = 31. At scale 3 winCols = 1000/48 = 20 < 31 (rejected on
        // columns alone). At scale 2 winCols = 1000/32 = 31 (columns clear), but the
        // available row width only fits one 13-wide pen per row after the barn's slot, so
        // all 8 pens stack into 8 rows and requiredRows balloons to 77, far past
        // winRows = 700/32 = 21. At scale 1 (winCols=62, winRows=43) the wider row budget
        // packs pens 3/3/2 across 3 rows, requiredRows = 32, which fits.
        let pens = makePens((0..<8).map { _ in (AnimalSpecies.cow, 4) })
        let (scale, layout) = FarmScene.selectScaleAndLayout(pens: pens, width: 1000, height: 700)
        XCTAssertEqual(scale, 1)
        XCTAssertLessThanOrEqual(layout.requiredRows, Int(700) / (16 * scale))
    }

    /// The regression case documented in the Task 10 report: `requiredRows` shrinks as the
    /// candidate scale shrinks (fewer pixels per tile means more columns are available, so
    /// pens wrap into fewer rows, not more). The buggy version accepted a candidate scale
    /// `s` by re-deriving a scale from scratch using *that candidate's own* `requiredRows`
    /// (rather than checking `winCols`/`winRows` against it directly) — and because a
    /// looser (smaller) `requiredRows` computed for a wider-column candidate can also
    /// satisfy a *tighter-column* candidate's row budget, that re-derivation can report a
    /// scale other than the one under test, rejecting a scale that genuinely fits and
    /// eventually falling through to the scroll fallback on a scale smaller than correct.
    ///
    /// This exact case was empirically verified against both implementations: with the
    /// buggy re-derivation reintroduced, these inputs at 1400×1300 produce scale 1
    /// (falling through to the "nothing fit" scroll fallback even though scale 2 fits);
    /// with the direct-check fix in this file, they correctly produce scale 2. Six
    /// 9-wide/5-tall chicken pens give minCols = 9 + barnW(7) + gap(2) + 1 + marginL(4) +
    /// marginR(4) = 27. At scale 3, winCols = 1400/48 = 29 (columns clear) but this
    /// candidate's own layout needs 33 rows against winRows = 1300/48 = 27 — scale 3
    /// correctly fails on rows. At scale 2, winCols = 1400/32 = 43 and this candidate's
    /// own layout needs only 26 rows against winRows = 1300/32 = 40 — scale 2 genuinely
    /// fits, and is the correct answer.
    func test_circularDependency_choosesLargestScaleThatGenuinelyFitsWithoutFallingBackToScroll() {
        let pens = makePens((0..<6).map { _ in (AnimalSpecies.chicken, 2) })
        let width: CGFloat = 1400
        let height: CGFloat = 1300
        let (scale, layout) = FarmScene.selectScaleAndLayout(pens: pens, width: width, height: height)
        XCTAssertEqual(scale, 2)

        // The chosen scale must be one that actually fits at its own window-in-tiles
        // budget, i.e. it did NOT take the "nothing fit, scroll" fallback.
        let winRows = Int(height) / (16 * scale)
        XCTAssertLessThanOrEqual(layout.requiredRows, winRows)
    }

    func test_neverReturnsZeroOrFractional() {
        let pens = makePens((0..<8).map { _ in (AnimalSpecies.cow, 4) })
        for w in stride(from: 320.0, to: 2600.0, by: 137.0) {
            for h in stride(from: 240.0, to: 1600.0, by: 149.0) {
                let (scale, _) = FarmScene.selectScaleAndLayout(pens: pens, width: w, height: h)
                XCTAssertTrue([1, 2, 3].contains(scale), "scale \(scale) at \(w)x\(h)")
            }
        }
    }

    func test_narrowWindowDegradesRatherThanCrashing() {
        let pens = makePens((0..<6).map { _ in (AnimalSpecies.cow, 4) })
        let (scale, layout) = FarmScene.selectScaleAndLayout(pens: pens, width: 50, height: 40)
        XCTAssertEqual(scale, 1)
        XCTAssertEqual(layout.pens.count, pens.count, "every pen must still be placed, never dropped")
    }

    func test_zeroSizeWindowFallsBackWithoutCrashing() {
        let pens = makePens([(.chicken, 1)])
        let (scale, layout) = FarmScene.selectScaleAndLayout(pens: pens, width: 0, height: 0)
        XCTAssertEqual(scale, 1)
        XCTAssertEqual(layout.cols, 1)
        XCTAssertEqual(layout.rows, 1)
    }

    func test_emptyPens() {
        let (scale, layout) = FarmScene.selectScaleAndLayout(pens: [], width: 1200, height: 800)
        // maxPenW=0, minCols = 0+barnW(7)+gap(2)+1+marginL(4)+marginR(4) = 18, requiredRows=0;
        // scale 3 gives winCols=25, winRows=16, both comfortably clear the empty-pens minimums.
        XCTAssertEqual(scale, 3)
        XCTAssertTrue(layout.pens.isEmpty)
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
