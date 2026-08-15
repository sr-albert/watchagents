import Foundation

/// A single tile-grid coordinate. Used as the currency for the dirt set so the
/// autotiler and its callers (Tasks 6, 10) don't need to reach back into `FarmLayout`.
struct TilePoint: Hashable {
    let x: Int, y: Int
}

/// Derives the dirt network (lanes, barn spur, gate thresholds, pen wear) from a
/// `FarmLayout` and autotiles the result. Spec §4.2–§4.4, ported from `mock7.py:117-167`.
///
/// Dirt is *computed*, never hand-placed: everything here is a pure function of pen
/// geometry (plus, for pen wear, a hash of the project path) so the ground never
/// reshuffles when live state changes.
enum FarmDirt {
    static func dirtCells(layout: FarmLayout) -> Set<TilePoint> {
        var dirt = Set<TilePoint>()
        let avail = layout.cols - FarmLayoutEngine.marginL - FarmLayoutEngine.marginR

        func addRect(_ x: Int, _ y: Int, _ w: Int, _ h: Int) {
            guard w > 0, h > 0 else { return }
            for j in 0..<h {
                for i in 0..<w {
                    let px = x + i, py = y + j
                    guard px >= 0, px < layout.cols, py >= 0, py < layout.rows else { continue }
                    dirt.insert(TilePoint(x: px, y: py))
                }
            }
        }

        // 1. Lanes — a 2-tile dirt road between every pair of rows. Terminates inside
        // the margins; it does not bleed off the edges.
        for laneY in layout.laneYs {
            addRect(FarmLayoutEngine.marginL + 1, laneY, avail - 2, FarmLayoutEngine.laneH)
        }

        // 2. Barn spur + apron.
        if let barnX = layout.barnX, let barnY = layout.barnY {
            if let firstLane = layout.laneYs.first {
                addRect(barnX + 2, barnY + FarmLayoutEngine.barnH, 3,
                        firstLane - (barnY + FarmLayoutEngine.barnH))
            }
            addRect(barnX + 1, barnY + FarmLayoutEngine.barnH, 5, 2)
        }

        // 3 & 4: gate thresholds and pen wear, per pen.
        for placed in layout.pens {
            let ix = placed.x + 1, iy = placed.y + 1
            let iw = placed.w - 2, ih = placed.h - 2
            let gx = placed.gateX

            var cells = Set<TilePoint>()

            // Trough apron — always present, every pen, no exceptions.
            cells.insert(TilePoint(x: ix, y: iy + ih - 1))
            cells.insert(TilePoint(x: ix + 1, y: iy + ih - 1))
            cells.insert(TilePoint(x: ix, y: iy + ih - 2))
            cells.insert(TilePoint(x: ix + 1, y: iy + ih - 2))

            // Gate inside — the pair of interior cells just behind the gate gap.
            switch placed.gate {
            case .south:
                cells.insert(TilePoint(x: gx - 1, y: iy + ih - 1))
                cells.insert(TilePoint(x: gx, y: iy + ih - 1))
            case .north:
                cells.insert(TilePoint(x: gx - 1, y: iy))
                cells.insert(TilePoint(x: gx, y: iy))
            case .none:
                break
            }

            // Standing patch — a worn diamond-ish smear, not a floor. Seeded only from
            // the project path hash, never from live state/animal position/time, so
            // the ground doesn't repaint when a session's state flips.
            // NOTE: `StableHash.pick(2, …)` must not be used for the per-cell jitter
            // below. FNV-1a's multiplier is odd, so multiplying-by-odd mod 2^64
            // preserves the *low* bit of the running hash — `pick(2, …)` only ever
            // reads that one surviving bit, which here is dominated by the small
            // loop-counter values fed in, giving a degenerate alternating sequence
            // instead of a ragged draw. Pulling from bit 32 of `StableHash.of` (after
            // several mixing rounds) avoids that and folding `dx, dy` into the hash
            // makes the jitter genuinely per-cell rather than one flip per pen.
            let pathHash = Int(truncatingIfNeeded: AnimalAssignment.stableHash(placed.pen.cwd))
            let cxRange = max(1, iw - 4)
            let cyRange = max(1, ih - 1)
            let cx = ix + 2 + Int((StableHash.of(pathHash, 0xD4) >> 32) % UInt64(cxRange))
            let cy = iy + Int((StableHash.of(pathHash, 0xD5) >> 32) % UInt64(cyRange))
            for dy in -1...1 {
                for dx in -2...2 {
                    let jitter = StableHash.of(pathHash, dx, dy, 0xC3)
                    let threshold = 2 + Int((jitter >> 32) & 1)
                    if abs(dx) + 2 * abs(dy) <= threshold {
                        cells.insert(TilePoint(x: cx + dx, y: cy + dy))
                    }
                }
            }

            // Clip pen wear to the interior — never under the fence rails.
            for cell in cells where cell.x >= ix && cell.x < ix + iw && cell.y >= iy && cell.y < iy + ih {
                dirt.insert(cell)
            }

            // Gate threshold: the strip of dirt connecting the gate to its lane.
            switch placed.gate {
            case .south:
                // South-gated pens are bottom-aligned to their row, so the row's
                // bottom edge — and thus the lane below it — is exactly `y + h`.
                let laneY = placed.y + placed.h
                for yy in (placed.y + placed.h - 1)..<laneY {
                    dirt.insert(TilePoint(x: gx - 1, y: yy))
                    dirt.insert(TilePoint(x: gx, y: yy))
                }
            case .north:
                if let laneY = layout.laneYs.last {
                    let start = laneY + FarmLayoutEngine.laneH
                    let end = placed.y + 1
                    if start < end {
                        for yy in start..<end {
                            dirt.insert(TilePoint(x: gx - 1, y: yy))
                            dirt.insert(TilePoint(x: gx, y: yy))
                        }
                    }
                }
            case .none:
                break
            }
        }

        return dirt
    }

    /// Autotile: for each dirt cell, test whether each 4-neighbour is absent from the
    /// dirt set, and pick the edge tile per §4.4's table. No inner-corner tiles exist in
    /// this pack, so concave notches fall through to the interior fill.
    static func tile(at p: TilePoint, in dirt: Set<TilePoint>) -> Int {
        let n = !dirt.contains(TilePoint(x: p.x, y: p.y - 1))
        let s = !dirt.contains(TilePoint(x: p.x, y: p.y + 1))
        let w = !dirt.contains(TilePoint(x: p.x - 1, y: p.y))
        let e = !dirt.contains(TilePoint(x: p.x + 1, y: p.y))

        if n && w { return 12 }
        if n && e { return 14 }
        if s && w { return 36 }
        if s && e { return 38 }
        if n { return 13 }
        if s { return 37 }
        if w { return 24 }
        if e { return 26 }

        let r = StableHash.pick(100, p.x, p.y, 5)
        if r < 70 { return 25 }
        if r < 80 { return 39 }
        if r < 88 { return 40 }
        if r < 94 { return 41 }
        return 42
    }
}
