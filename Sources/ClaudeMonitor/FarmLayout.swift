import Foundation

/// `.none` is currently unreachable — every real layout is either single-row (south
/// gate onto open ground) or multi-row (north/south onto a lane) — kept only as a
/// defensive default should a future layout shape produce a gateless pen.
enum GateSide: Equatable { case north, south, none }

struct PlacedPen: Equatable {
    let pen: FarmPen
    let x: Int, y: Int, w: Int, h: Int
    let gate: GateSide
    let gateX: Int
}

struct FarmLayout: Equatable {
    let pens: [PlacedPen]
    let laneYs: [Int]
    let barnX: Int?
    let barnY: Int?
    let cols: Int
    let rows: Int
    /// Rows the layout actually needs. When this exceeds `rows`, the caller scrolls;
    /// pens are never dropped or clipped.
    let requiredRows: Int
}

enum FarmLayoutEngine {
    static let marginL = 4, marginR = 4, marginT = 3, frameB = 4
    static let gap = 2, laneH = 2, barnW = 7, barnH = 4

    /// Species footprint in tiles, from measured LPC side-view bboxes. Chicken is
    /// deliberately widened from its measured 2 — at 2 the slot lattice crowds and
    /// birds overlap. Spec §2.1 says do not "correct" this back.
    static func footprint(for species: AnimalSpecies) -> (w: Int, h: Int) {
        switch species {
        case .cow: return (5, 3)
        case .sheep: return (4, 3)
        case .pig: return (4, 2)
        case .chicken: return (3, 2)
        }
    }

    /// How many animals stand side by side in a pen. The pen is built around this number
    /// (`penSize` below) and the animals are laid out against it
    /// (`FarmAnimalPlacer.place`), so it has to be one function: the two used to derive it
    /// separately — sizing from the footprint, placing from how many sprites physically
    /// fit — and disagreed whenever a pen had room for more columns than it was sized for.
    /// The surplus columns ate the slack an active animal walks in, which left a pen of
    /// four chickens with nowhere to go and its occupants walking on the spot.
    static func penColumns(animalCount: Int) -> Int {
        let n = min(animalCount, 8)
        let rows = n <= 2 ? 1 : 2
        return max(1, Int(ceil(Double(n) / Double(rows))))
    }

    static func penSize(species: AnimalSpecies, animalCount: Int) -> (w: Int, h: Int) {
        let foot = footprint(for: species)
        let n = min(animalCount, 8)
        let rows = n <= 2 ? 1 : 2
        let cols = penColumns(animalCount: animalCount)
        let interiorW = cols * foot.w + 1
        let interiorH = foot.h + (rows - 1) + 1
        return (max(7, interiorW + 2), max(5, interiorH + 2))
    }

    static func layout(pens: [FarmPen], cols: Int, rows: Int) -> FarmLayout {
        guard !pens.isEmpty else {
            // Fix 6: the empty-farm scene is still a barn + frame, not a blank canvas,
            // so it has a real minimum height even with zero pens. Reporting it here
            // (rather than leaving `requiredRows` at 0) lets `FarmScene` pick a scale
            // that doesn't need to scroll just to show an empty farm.
            return FarmLayout(pens: [], laneYs: [], barnX: nil, barnY: nil,
                               cols: cols, rows: rows,
                               requiredRows: marginT + barnH + frameB)
        }

        let avail = cols - marginL - marginR

        // (pen, w, h) in input order, sizes computed from species + occupancy.
        let sized: [(pen: FarmPen, w: Int, h: Int)] = pens.map {
            let size = penSize(species: $0.species, animalCount: $0.processes.count)
            return ($0, size.w, size.h)
        }

        // Spec §2.4: "never clip a pen"; if 1x still fails on width, move the barn to
        // its own row (recovers BARN_W+GAP+1 columns). Tested against the *widest* pen
        // overall, not just row 0's actual occupant — row 0 is the tightest row (its
        // budget is reduced by the barn's slot) so this is the binding constraint
        // regardless of which row the widest pen actually lands in.
        let maxPenW = sized.map { $0.w }.max() ?? 0
        let barnOwnRow = barnW + gap + 1 + maxPenW > avail

        // -------------------------------------------------------------- row packing
        var packedRows: [[(pen: FarmPen, w: Int, h: Int)]] = []
        var currentRow: [(pen: FarmPen, w: Int, h: Int)] = []
        // Row 0 starts with the barn's slot consumed, unless the barn had to move to
        // its own row above the pens, in which case every row (including row 0) gets
        // the full width budget.
        var curW = barnOwnRow ? 0 : barnW + gap + 1

        for item in sized {
            // The wrap test must run even when the row is empty: otherwise the first
            // pen of row 0 skips the width check and lands past the barn regardless
            // of window width, running off the right edge.
            if curW + item.w > avail && (!currentRow.isEmpty || curW > 0) {
                packedRows.append(currentRow)
                currentRow = []
                curW = 0
            }
            currentRow.append(item)
            curW += item.w + gap
        }
        if !currentRow.isEmpty {
            packedRows.append(currentRow)
        }
        // mock7.py:84 — `rows = [r for r in rows if r]`. Without this, a wrap that
        // fires on an empty row (e.g. the very first pen alone doesn't fit the row-0
        // budget) leaves a phantom empty row ahead of the real one, corrupting row
        // indices, `barnY`, `laneYs`, and gate assignment downstream.
        packedRows = packedRows.filter { !$0.isEmpty }

        // -------------------------------------------------------- vertical placement
        struct PlacedItem {
            let pen: FarmPen
            let x: Int, y: Int, w: Int, h: Int
            let rowIndex: Int
        }

        var placedItems: [PlacedItem] = []
        var rowBands: [(y: Int, h: Int)] = []
        // When the barn has its own row, reserve BARN_H rows for it plus `gap` rows
        // before the first pen row. `FarmDirt` draws the barn's ground apron
        // unconditionally for 2 rows below it (== `gap`), so that apron fills this
        // reserved band exactly instead of leaving a dead strip of bare grass.
        var y = marginT + (barnOwnRow ? barnH + gap : 0)

        for (rowIndex, row) in packedRows.enumerated() {
            let rowH = row.map { $0.h }.max() ?? 0
            var x = marginL + (rowIndex == 0 && !barnOwnRow ? barnW + gap + 1 : 0)
            for item in row {
                // Bottom-aligned within the row: different pen heights then produce a
                // ragged top edge, which is a large part of what stops the scene
                // reading as a grid of cards.
                placedItems.append(PlacedItem(pen: item.pen, x: x, y: y + (rowH - item.h),
                                               w: item.w, h: item.h, rowIndex: rowIndex))
                x += item.w + gap
            }
            rowBands.append((y: y, h: rowH))
            y += rowH + laneH
        }

        let laneYs = (0..<max(0, rowBands.count - 1)).map { rowBands[$0].y + rowBands[$0].h }
        // Rows the layout actually needs (mock7's `needed_h`), not clamped to the
        // window's `rows` — the caller compares this against `rows` to decide whether
        // it must scroll.
        let requiredRows = y - laneH + frameB

        let barnX = marginL
        let barnY: Int?
        if rowBands.isEmpty {
            barnY = nil
        } else if barnOwnRow {
            barnY = marginT
        } else {
            barnY = rowBands[0].y + rowBands[0].h - barnH
        }

        // -------------------------------------------------------------- gate assignment
        let rowCount = packedRows.count
        let placedPens: [PlacedPen] = placedItems.map { item in
            let gate: GateSide
            if item.rowIndex < rowCount - 1 {
                gate = .south
            } else if item.rowIndex > 0 {
                gate = .north
            } else {
                // Fix 1: mock7.py:114 — a lone row (rowCount == 1) still gates south,
                // it just has no lane on the other side (`lane = None`). The pen still
                // needs a break in its fence ring; `FarmDirt` is what skips drawing a
                // threshold onto a lane that doesn't exist.
                gate = .south
            }
            let gateX = item.x + item.w / 2
            return PlacedPen(pen: item.pen, x: item.x, y: item.y, w: item.w, h: item.h,
                              gate: gate, gateX: gateX)
        }

        return FarmLayout(pens: placedPens, laneYs: laneYs, barnX: barnX, barnY: barnY,
                           cols: cols, rows: rows, requiredRows: requiredRows)
    }
}
