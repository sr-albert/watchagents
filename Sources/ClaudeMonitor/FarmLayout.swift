import Foundation

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

    static func penSize(species: AnimalSpecies, animalCount: Int) -> (w: Int, h: Int) {
        let foot = footprint(for: species)
        let n = min(animalCount, 8)
        let rows = n <= 2 ? 1 : 2
        let cols = Int(ceil(Double(n) / Double(rows)))
        let interiorW = cols * foot.w + 1
        let interiorH = foot.h + (rows - 1) + 1
        return (max(7, interiorW + 2), max(5, interiorH + 2))
    }

    static func layout(pens: [FarmPen], cols: Int, rows: Int) -> FarmLayout {
        guard !pens.isEmpty else {
            return FarmLayout(pens: [], laneYs: [], barnX: nil, barnY: nil,
                               cols: cols, rows: rows, requiredRows: 0)
        }

        let avail = cols - marginL - marginR

        // (pen, w, h) in input order, sizes computed from species + occupancy.
        let sized: [(pen: FarmPen, w: Int, h: Int)] = pens.map {
            let size = penSize(species: $0.species, animalCount: $0.processes.count)
            return ($0, size.w, size.h)
        }

        // -------------------------------------------------------------- row packing
        var packedRows: [[(pen: FarmPen, w: Int, h: Int)]] = []
        var currentRow: [(pen: FarmPen, w: Int, h: Int)] = []
        var curW = barnW + gap + 1   // row 0 starts with the barn's slot consumed

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

        // -------------------------------------------------------- vertical placement
        struct PlacedItem {
            let pen: FarmPen
            let x: Int, y: Int, w: Int, h: Int
            let rowIndex: Int
        }

        var placedItems: [PlacedItem] = []
        var rowBands: [(y: Int, h: Int)] = []
        var y = marginT

        for (rowIndex, row) in packedRows.enumerated() {
            let rowH = row.map { $0.h }.max() ?? 0
            var x = marginL + (rowIndex == 0 ? barnW + gap + 1 : 0)
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
        let barnY = rowBands.isEmpty ? nil : rowBands[0].y + rowBands[0].h - barnH

        // -------------------------------------------------------------- gate assignment
        let rowCount = packedRows.count
        let placedPens: [PlacedPen] = placedItems.map { item in
            let gate: GateSide
            if item.rowIndex < rowCount - 1 {
                gate = .south
            } else if item.rowIndex > 0 {
                gate = .north
            } else {
                gate = .none
            }
            let gateX = item.x + item.w / 2
            return PlacedPen(pen: item.pen, x: item.x, y: item.y, w: item.w, h: item.h,
                              gate: gate, gateX: gateX)
        }

        return FarmLayout(pens: placedPens, laneYs: laneYs, barnX: barnX, barnY: barnY,
                           cols: cols, rows: rows, requiredRows: requiredRows)
    }
}
