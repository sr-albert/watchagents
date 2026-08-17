import CoreGraphics
import Foundation

/// Scale selection (spec §1 / §2.4) and the animal depth sort (spec §5.4) — the two
/// small, pure decisions that sit outside any single Task 1-9 piece and above
/// `FarmView`'s drawing code. Nothing downstream depends on this type.
enum FarmScene {
    /// Picks the scale (spec §1/§2.4) by trying 3, 2, 1 in order: at each candidate, lay
    /// the real pens out against that scale's window-in-tiles and check the §2.4 fit rule
    /// directly. A bigger scale means fewer available columns, which means *more*
    /// row-wrapping, not less — so each candidate needs its own real layout, not one
    /// computed at a different scale.
    static func selectScaleAndLayout(pens: [FarmPen], width: CGFloat, height: CGFloat) -> (scale: Int, layout: FarmLayout) {
        guard width > 0, height > 0 else {
            return (1, FarmLayoutEngine.layout(pens: pens, cols: 1, rows: 1))
        }

        for s in [3, 2, 1] {
            let winCols = Int(width) / (16 * s)
            let winRows = Int(height) / (16 * s)
            guard winCols > 0, winRows > 0 else { continue }
            let layout = FarmLayoutEngine.layout(pens: pens, cols: winCols, rows: winRows)
            let maxPenW = layout.pens.map(\.w).max() ?? 0
            let minCols = maxPenW + FarmLayoutEngine.barnW + FarmLayoutEngine.gap + 1
                + 2 * FarmLayoutEngine.minMargin
            // Test this candidate directly (`winCols`/`winRows` against `minCols`/this
            // layout's own `requiredRows`) rather than by re-invoking this same function
            // recursively: `requiredRows` shrinks as `winCols` grows (fewer columns wrap
            // pens into more rows), so re-deriving a scale from *this* candidate's looser
            // `requiredRows` can report a bigger scale than the one actually under test —
            // which would skip over a smaller scale that genuinely fits.
            if winCols >= minCols && winRows >= layout.requiredRows {
                return (s, layout)
            }
        }

        // Nothing fit without scrolling, even at scale 1. Spec §2.4: never clip a pen —
        // scroll instead. Re-run the layout with its own required row count so the
        // woodland/frame bounds (which read `layout.rows`) cover the full scrollable area.
        let winCols = max(1, Int(width) / 16)
        let winRows = max(1, Int(height) / 16)
        var layout = FarmLayoutEngine.layout(pens: pens, cols: winCols, rows: winRows)
        if layout.requiredRows > layout.rows {
            layout = FarmLayoutEngine.layout(pens: pens, cols: winCols, rows: layout.requiredRows)
        }
        return (1, layout)
    }

    /// Spec §5.4: one stable sort by baseline `y`, back to front. `FarmAnimalPlacer.place`
    /// deliberately returns pid order, not depth order, so this is the renderer's job.
    /// `Array.sorted(by:)` has been a stable sort since Swift 5, so ties (animals sharing
    /// a baseline) keep their original relative order.
    static func drawOrder(_ animals: [AnimalPlacement]) -> [AnimalPlacement] {
        animals.sorted { $0.by < $1.by }
    }
}
