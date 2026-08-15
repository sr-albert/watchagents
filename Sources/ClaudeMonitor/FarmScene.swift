import CoreGraphics
import Foundation

/// Scale selection (spec §1 / §2.4) and the animal depth sort (spec §5.4) — the two
/// small, pure decisions that sit outside any single Task 1-9 piece and above
/// `FarmView`'s drawing code. Nothing downstream depends on this type.
enum FarmScene {
    /// Picks the largest integer scale in `{3, 2, 1}` at which a layout needing at
    /// least `cols` columns and `rows` rows fits inside a `width`×`height` window,
    /// falling back to `1` (the caller then scrolls vertically, per spec §2.4 — never
    /// clip a pen) rather than ever returning `0` or a fractional scale.
    static func scale(cols: Int, rows: Int, width: CGFloat, height: CGFloat) -> Int {
        for s in [3, 2, 1] {
            let winCols = Int(width) / (16 * s)
            let winRows = Int(height) / (16 * s)
            if winCols >= cols && winRows >= rows {
                return s
            }
        }
        return 1
    }

    /// Spec §5.4: one stable sort by baseline `y`, back to front. `FarmAnimalPlacer.place`
    /// deliberately returns pid order, not depth order, so this is the renderer's job.
    /// `Array.sorted(by:)` has been a stable sort since Swift 5, so ties (animals sharing
    /// a baseline) keep their original relative order.
    static func drawOrder(_ animals: [AnimalPlacement]) -> [AnimalPlacement] {
        animals.sorted { $0.by < $1.by }
    }
}
