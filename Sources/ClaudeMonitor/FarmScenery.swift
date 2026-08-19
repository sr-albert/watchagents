import Foundation

/// A single tile placement. Task 9 (fences/troughs) reuses this type, so it stays a
/// plain shared struct rather than nested inside `FarmScenery`.
struct SceneryTile: Equatable {
    let x: Int, y: Int, tile: Int
}

/// Places the barn, the farmyard cluster around it, and the woodland that frames the
/// scene. Ported from `mock7.py:168-389` (spec §6). Pure logic — this returns tile
/// placements, it never draws.
///
/// Everything here tests an occupancy set (dirt ∪ pens ∪ lanes, each with a one-tile
/// buffer) before drawing. That's what keeps scenery off pens and roads automatically
/// and produces the ragged pen/woodland interface for free (§6.3).
///
/// `decorate`'s returned array is draw order, not an unordered bag of tiles: later
/// entries composite over earlier ones at the same cell. Do not y-sort or de-duplicate
/// it downstream — see the note above the farmyard cluster for why.
enum FarmScenery {
    /// A fixed scene seed — mock7.py's `seed0` default. Placement must never depend on
    /// time or live state, only on stable inputs, so this is a constant rather than a
    /// parameter.
    private static let seed0 = 1

    /// The 7×4 barn: two roof rows, wall rows, and a ground row with a double door.
    /// Spec §6.1 / mock7.py:169-181.
    static func barnTiles(x: Int, y: Int) -> [SceneryTile] {
        let w = FarmLayoutEngine.barnW, h = FarmLayoutEngine.barnH
        var out: [SceneryTile] = []
        func put(_ n: Int, _ cx: Int, _ cy: Int) {
            out.append(SceneryTile(x: cx, y: cy, tile: n))
        }
        // Roof row 1, then the hay-loft window overwrites its centre tile.
        for i in 0..<w {
            put(i == 0 ? 52 : (i == w - 1 ? 54 : 53), x + i, y)
        }
        put(55, x + w / 2, y)
        // Roof row 2.
        for i in 0..<w {
            put(i == 0 ? 64 : (i == w - 1 ? 66 : 65), x + i, y + 1)
        }
        // Wall rows.
        for j in 2..<h {
            for i in 0..<w {
                put(i == 0 ? 72 : (i == w - 1 ? 75 : 73), x + i, y + j)
            }
        }
        // Ground row overrides: side windows, then the double door at centre.
        let gy = y + h - 1
        put(84, x + 1, gy)
        put(84, x + w - 2, gy)
        for t in barnDoorTiles(x: x, y: y, open: false) { put(t.tile, t.x, t.y) }
        return out
    }

    /// The barn's double door, shut or open.
    ///
    /// Shut is `0085`/`0087` — a pair that meets under the wall's single arch, unlike
    /// `0086` twice, which brings its own frame and reads as two front doors side by side.
    /// Open is `0074` twice, the dark opening, which is what the barn used to wear
    /// permanently: it stood agape at rest, so there was no state left for opening it to
    /// change.
    ///
    /// There are no half-open tiles in the pack, so this is a cut rather than a swing.
    /// Callers draw the open state as an overlay on top of the shut one — see `FarmView` —
    /// rather than rebuilding the barn, because the barn lives in the cached static layer
    /// and door state would throw that cache away on every click.
    ///
    /// Opening therefore repaints the wall (`0073`) before the opening. `0074` is an arch
    /// with transparent corners, meant to composite onto a wall; laid straight over the
    /// shut door its corners let the brown door panels show through, and the barn reads as
    /// having doors both open and closed at once.
    ///
    /// Returned in draw order, so a caller paints them front to back as given.
    static func barnDoorTiles(x: Int, y: Int, open: Bool) -> [SceneryTile] {
        let gy = y + FarmLayoutEngine.barnH - 1
        let cx = x + FarmLayoutEngine.barnW / 2
        guard open else {
            return [SceneryTile(x: cx - 1, y: gy, tile: 85),
                    SceneryTile(x: cx, y: gy, tile: 87)]
        }
        return [cx - 1, cx].flatMap { dx in
            [SceneryTile(x: dx, y: gy, tile: 73), SceneryTile(x: dx, y: gy, tile: 74)]
        }
    }

    static func decorate(layout: FarmLayout, dirt: Set<TilePoint>) -> [SceneryTile] {
        var out: [SceneryTile] = []
        var occupied = dirt

        func put(_ n: Int, _ px: Int, _ py: Int) {
            guard px >= 0, px < layout.cols, py >= 0, py < layout.rows else { return }
            out.append(SceneryTile(x: px, y: py, tile: n))
        }
        func mark(_ x: Int, _ y: Int, _ w: Int = 1, _ h: Int = 1) {
            for j in 0..<h {
                for i in 0..<w {
                    occupied.insert(TilePoint(x: x + i, y: y + j))
                }
            }
        }
        func clear(_ x: Int, _ y: Int, _ w: Int = 1, _ h: Int = 1) -> Bool {
            for j in 0..<h {
                for i in 0..<w {
                    let px = x + i, py = y + j
                    guard px >= 0, px < layout.cols, py >= 0, py < layout.rows else { return false }
                    if occupied.contains(TilePoint(x: px, y: py)) { return false }
                }
            }
            return true
        }

        // ---- barn --------------------------------------------------------------
        if let bx = layout.barnX, let by = layout.barnY {
            for t in barnTiles(x: bx, y: by) {
                put(t.tile, t.x, t.y)
            }
        }

        // ---- occupancy buffers ---------------------------------------------------
        // A one-tile buffer around every pen, the barn, and every lane keeps
        // woodland/scatter from crowding right up against them — this is what
        // produces the ragged interface, not a hand-tuned margin.
        for p in layout.pens {
            mark(p.x - 1, p.y - 1, p.w + 2, p.h + 2)
        }
        if let bx = layout.barnX, let by = layout.barnY {
            mark(bx - 1, by - 1, FarmLayoutEngine.barnW + 2, FarmLayoutEngine.barnH + 2)
            // The feed gauge's cluster (Task 6) reserves its own ground here, before
            // mushrooms/hay-yard scattering runs below, so those passes route around it
            // instead of the gauge's bales silently losing a scatter-placed mushroom.
            let gauge = gaugeCells(bx: bx, by: by)
            for cell in gauge.bales + [gauge.vat] {
                mark(cell.x, cell.y)
            }
        }
        for ly in layout.laneYs {
            mark(layout.marginL - 1, ly - 1,
                 layout.cols - layout.marginL - layout.marginR + 2,
                 FarmLayoutEngine.laneH + 2)
        }

        // ---- no woodland frame ----------------------------------------------
        // The scene has no treeline. Two attempts at one both failed on the same
        // problem: the pack's canopy pieces (0006-0008 over 0018-0020) are
        // forest-*interior* art whose outlines run into their neighbours, so against
        // open grass the top arcs dangle and the band reads upside down; and the single
        // tree (0004 over 0016) packs into a sawtooth, because a canopy sits directly on
        // its neighbour's trunk and leaves nothing but a row of the notches cut into the
        // canopy's base. An empty margin looks better than either, and it is what the
        // farm is for — the pens are the content.
        //
        // Tiles 0006-0011 and 0018-0023 are unused anywhere in the design; the test
        // suite pins that so a future pass cannot reintroduce them by accident.

        // ---- leftover space in the last row: clustered, not a sprinkle (§6.3) ----
        if !layout.pens.isEmpty {
            let rowGroups = Dictionary(grouping: layout.pens, by: { $0.y + $0.h })
            if let bottomKey = rowGroups.keys.max(), let lastRowPens = rowGroups[bottomKey] {
                let lastRowH = lastRowPens.map(\.h).max() ?? 0
                let lastRowY = bottomKey - lastRowH
                let lastX = lastRowPens.map { $0.x + $0.w }.max() ?? 0
                let gapw = layout.cols - 3 - (lastX + 3)
                if gapw > 10 {
                    // A tidy hay yard gives the open lawn a destination. It is the only
                    // thing planted out here now: a sprinkle of bushes across open ground
                    // is confetti, and confetti was the complaint.
                    let hx = lastX + 4, hy = lastRowY + 1
                    for (i, n) in [93, 93].enumerated() {
                        if clear(hx + i, hy) { put(n, hx + i, hy); mark(hx + i, hy) }
                    }
                    if clear(hx, hy + 1) { put(93, hx, hy + 1); mark(hx, hy + 1) }
                    if clear(hx + 1, hy + 1) { put(93, hx + 1, hy + 1); mark(hx + 1, hy + 1) }
                }
            }
        }

        // Mushrooms only on cells that are already grass-tuft, and only
        // at ~22-26% — keeps them associated with the rough ground (§6.3).
        for i in 0..<300 {
            let x = StableHash.pick(layout.cols, i, 1, seed0)
            let y = StableHash.pick(layout.rows, i, 2, seed0)
            if clear(x, y), FarmGround.grassTile(x: x, y: y) == FarmGround.tuft,
               StableHash.pick(100, i, 3) < 26 {
                // Mushrooms (0029) only. The 0017 sprouts that used to share this pass
                // are two thin stems inside a heavy dark outline: at farm scale the
                // green all but disappears and they read as random dark squiggles on
                // the lawn, which is what a viewer flagged them as.
                guard StableHash.pick(4, i, 4) == 0 else { continue }
                put(29, x, y)
                mark(x, y)
            }
        }

        // ---- farmyard cluster — always clustered, never scattered singly (§6.1) --
        // Positions are chosen to sit beside the barn's own footprint, outside every
        // pen's column range and above the lane rows; `placeProp` still tests dirt and
        // pens before drawing; that's what protects this against any layout where the
        // margins are unusually tight. (mock7.py places the barrel/bucket and the
        // signpost a row further down, which sits on the lane itself whenever a lane
        // exists — moved up here so scenery never covers a road tile.)
        //
        // NOTE: the returned array is draw order, not an unordered bag of tiles —
        // later entries composite over earlier ones at the same cell (e.g. barnTiles'
        // hay-loft window and double door, the treeline fringe, and this farmyard
        // cluster all rely on that). Do not y-sort or de-duplicate it downstream.
        func placeProp(_ n: Int, _ x: Int, _ y: Int) {
            guard x >= 0, x < layout.cols, y >= 0, y < layout.rows else { return }
            guard !dirt.contains(TilePoint(x: x, y: y)) else { return }
            let insidePen = layout.pens.contains {
                x >= $0.x && x < $0.x + $0.w && y >= $0.y && y < $0.y + $0.h
            }
            guard !insidePen else { return }
            put(n, x, y)
            mark(x, y)
        }
        if let bx = layout.barnX, let by = layout.barnY {
            let w = FarmLayoutEngine.barnW, h = FarmLayoutEngine.barnH
            // The two bales and the chest that used to live here are now `gaugeProps`
            // (Task 6) — a bale that silently fails to draw would read as spent budget,
            // so those props no longer go through this best-effort `placeProp` path.
            placeProp(94, bx + w + 1, by + h - 1)   // beehive, beside the hay
            placeProp(116, bx - 1, by + h - 1)      // pitchfork, left wall
            placeProp(106, bx + w + 1, by + h - 2)  // barrel, right shoulder
            placeProp(107, bx + w + 2, by + h - 1)  // bucket, right shoulder
            if let firstLane = layout.laneYs.first {
                placeProp(57, bx + 5, firstLane - 1)                              // mailbox
                placeProp(83, bx - 1, firstLane + FarmLayoutEngine.laneH)         // signpost
            }
        }

        return out
    }

    /// The feed gauge's four cells at the barn's right shoulder: three bales stacked in
    /// the column the old pair of hay props used, and the vat one column over, above the
    /// barrel/beehive/bucket row. Shared by the reservation in `decorate` and by
    /// `gaugeProps` itself, so the two can never disagree about where the cluster sits.
    private static func gaugeCells(bx: Int, by: Int) -> (bales: [TilePoint], vat: TilePoint) {
        let w = FarmLayoutEngine.barnW, h = FarmLayoutEngine.barnH
        let bales = (0..<3).map { TilePoint(x: bx + w, y: by + h - 1 - $0) }
        let vat = TilePoint(x: bx + w + 2, y: by + h - 2)
        return (bales, vat)
    }

    /// The straw-bale-and-vat token-budget reading (spec §6.1's farmyard cluster, wearing
    /// a second job). The three bales are a vertical stack, ground cell first; spending
    /// the budget takes the stack down from the top, so `gauge.bales` keeps that many
    /// cells starting from the bottom of `gaugeCells`'s array. The vat's fill is painted
    /// separately (`FarmVat`) over the tile placed here.
    ///
    /// Deliberately not `placeProp`: that helper silently skips a cell it cannot draw, which is
    /// right for decoration and wrong here. A bale that quietly fails to appear reads as spent
    /// budget — the gauge would lie. So the cells are reserved up front, and if the cluster
    /// cannot be placed the whole gauge is withheld rather than half-drawn.
    static func gaugeProps(layout: FarmLayout, gauge: FeedGauge?) -> [SceneryTile] {
        guard let gauge, let bx = layout.barnX, let by = layout.barnY else { return [] }
        let cells = gaugeCells(bx: bx, by: by)
        let allCells = cells.bales + [cells.vat]

        func fits(_ p: TilePoint) -> Bool {
            guard p.x >= 0, p.x < layout.cols, p.y >= 0, p.y < layout.rows else { return false }
            return !layout.pens.contains {
                p.x >= $0.x && p.x < $0.x + $0.w && p.y >= $0.y && p.y < $0.y + $0.h
            }
        }
        guard allCells.allSatisfy(fits) else { return [] }

        var out = cells.bales.prefix(gauge.bales).map { SceneryTile(x: $0.x, y: $0.y, tile: 93) }
        out.append(SceneryTile(x: cells.vat.x, y: cells.vat.y, tile: 130))
        return out
    }
}
