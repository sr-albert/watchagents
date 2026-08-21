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
    /// The scenery band around the farm, in tiles. Not a constant: pens are packed
    /// against `FarmLayoutEngine.minMargin` and the leftover is handed back here, so
    /// these are how much open ground this particular layout ended up with. Anything
    /// drawn relative to the field's edge — lanes, hedge shoulders, the empty farm's
    /// barn — must read these rather than assume a fixed inset.
    let marginL: Int
    let marginR: Int
    let marginT: Int

    init(pens: [PlacedPen], laneYs: [Int], barnX: Int?, barnY: Int?,
         cols: Int, rows: Int, requiredRows: Int,
         marginL: Int = FarmLayoutEngine.minMargin,
         marginR: Int = FarmLayoutEngine.minMargin,
         marginT: Int = FarmLayoutEngine.minVerticalMargin) {
        self.pens = pens
        self.laneYs = laneYs
        self.barnX = barnX
        self.barnY = barnY
        self.cols = cols
        self.rows = rows
        self.requiredRows = requiredRows
        self.marginL = marginL
        self.marginR = marginR
        self.marginT = marginT
    }
}

enum FarmLayoutEngine {
    /// Pens are always packed against this margin, never against a roomier one. Spec
    /// §2.4 ranks the ways a layout may give ground when it doesn't fit: "clip scenery
    /// first (margins → 1), then scroll" — and dropping a scale is worse than either,
    /// because it halves the size of every animal on screen. Packing tight and giving
    /// the slack back afterwards (`margins(cols:rows:contentW:contentH:)`) means a scale
    /// is only ever rejected because the *pens* don't fit. The five-pen farm that
    /// prompted this needed 28 rows at 2x against a window of 27 — one row — and so
    /// rendered at 1x using a quarter of its window.
    ///
    static let minMargin = 1

    /// The band above the first row and below the last. Two tiles where the sides get
    /// one: at 30 pens a single shared tile put the first row's top rail and the last
    /// row's bottom rail ~10px from the window edge, and the field read as cut off rather
    /// than continuing past it. The sides don't suffer the same way — a row that fills its
    /// width ends in pens of differing widths, so the edge there is ragged, not sheared.
    ///
    /// It is deliberately *not* the same number as `minMargin`, because `minMargin` is
    /// what a row's packing budget is measured against: raising it to 2 takes two columns
    /// off every row, which wraps pens into more rows and pushes layouts back down a
    /// scale — the exact harm this rung exists to undo. A farm of eight 4-cow pens went
    /// from 47 rows to 74 at 2x when the two were shared.
    static let minVerticalMargin = 2
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

    /// Hands the space the packing didn't use back to the scenery band. Horizontally the
    /// farm is centred; vertically the leftover splits 3:4, the proportion the spec's own
    /// `MARGIN_T`/`FRAME_B` had, which leaves a little more open ground below the farm
    /// than above it. Without this the farm packs into the top-left corner and every
    /// column and row it didn't need becomes dead lawn in the bottom-right.
    static func margins(cols: Int, rows: Int, contentW: Int, contentH: Int) -> (l: Int, r: Int, t: Int) {
        let l = max(minMargin, (cols - contentW) / 2)
        let r = max(minMargin, cols - contentW - l)
        // The inner `min` keeps the 3:4 share from spending ground the bottom band still
        // needs: with only just enough slack to clear both bands, 3/7 of it would round
        // the bottom back under `minVerticalMargin`.
        let slack = rows - contentH
        let t = max(minVerticalMargin, min(slack * 3 / 7, slack - minVerticalMargin))
        return (l, r, t)
    }

    static func layout(pens: [FarmPen], cols: Int, rows: Int) -> FarmLayout {
        guard !pens.isEmpty else {
            // Fix 6: the empty-farm scene is still a barn + frame, not a blank canvas,
            // so it has a real minimum height even with zero pens. Reporting it here
            // (rather than leaving `requiredRows` at 0) lets `FarmScene` pick a scale
            // that doesn't need to scroll just to show an empty farm.
            let m = margins(cols: cols, rows: rows, contentW: barnW, contentH: barnH)
            return FarmLayout(pens: [], laneYs: [], barnX: nil, barnY: nil,
                               cols: cols, rows: rows,
                               requiredRows: barnH + 2 * minVerticalMargin,
                               marginL: m.l, marginR: m.r, marginT: m.t)
        }

        let avail = cols - 2 * minMargin

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
        var y = minVerticalMargin + (barnOwnRow ? barnH + gap : 0)

        for (rowIndex, row) in packedRows.enumerated() {
            let rowH = row.map { $0.h }.max() ?? 0
            var x = minMargin + (rowIndex == 0 && !barnOwnRow ? barnW + gap + 1 : 0)
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

        let contentBottom = y - laneH
        // Rows the layout actually needs (mock7's `needed_h`), not clamped to the
        // window's `rows` — the caller compares this against `rows` to decide whether
        // it must scroll. Measured against the minimum margin, because that is what the
        // packing above used: reporting a roomier band here would reject scales that fit.
        let requiredRows = contentBottom + minVerticalMargin

        var barnX = minMargin
        var barnY: Int?
        if rowBands.isEmpty {
            barnY = nil
        } else if barnOwnRow {
            barnY = minVerticalMargin
        } else {
            barnY = rowBands[0].y + rowBands[0].h - barnH
        }

        // ------------------------------------------------------------------- centring
        // Everything above was packed into the top-left against the minimum bands. Measure what
        // it came to and slide the whole thing into the middle of the window. Sliding a
        // finished packing is the only safe order: growing the margins *before* packing
        // would shrink `avail`, re-wrap pens into more rows, and break the fit that the
        // caller already proved at this scale.
        let contentRight = max(placedItems.map { $0.x + $0.w }.max() ?? 0, barnX + barnW)
        let m = margins(cols: cols, rows: rows,
                        contentW: contentRight - minMargin, contentH: contentBottom - minVerticalMargin)
        let dx = m.l - minMargin, dy = m.t - minVerticalMargin
        barnX += dx
        barnY = barnY.map { $0 + dy }
        let laneYs = (0..<max(0, rowBands.count - 1)).map { rowBands[$0].y + rowBands[$0].h + dy }

        // -------------------------------------------------------------- gate assignment
        let rowCount = packedRows.count
        let placedPens: [PlacedPen] = placedItems.map { item in
            let item = PlacedItem(pen: item.pen, x: item.x + dx, y: item.y + dy,
                                   w: item.w, h: item.h, rowIndex: item.rowIndex)
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
                           cols: cols, rows: rows, requiredRows: requiredRows,
                           marginL: m.l, marginR: m.r, marginT: m.t)
    }
}
