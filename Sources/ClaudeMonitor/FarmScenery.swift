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
        put(74, x + w / 2 - 1, gy)
        put(74, x + w / 2, gy)
        return out
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
        }
        for ly in layout.laneYs {
            mark(FarmLayoutEngine.marginL - 1, ly - 1,
                 layout.cols - FarmLayoutEngine.marginL - FarmLayoutEngine.marginR + 2,
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
                    if clear(hx, hy + 1) { put(94, hx, hy + 1); mark(hx, hy + 1) }
                    if clear(hx + 1, hy + 1) { put(93, hx + 1, hy + 1); mark(hx + 1, hy + 1) }
                }
            }
        }

        // Mushrooms and sprouts only on cells that are already grass-tuft, and only
        // at ~22-26% — keeps them associated with the rough ground (§6.3).
        for i in 0..<300 {
            let x = StableHash.pick(layout.cols, i, 1, seed0)
            let y = StableHash.pick(layout.rows, i, 2, seed0)
            if clear(x, y), FarmGround.grassTile(x: x, y: y) == FarmGround.tuft,
               StableHash.pick(100, i, 3) < 26 {
                put(StableHash.pick(4, i, 4) == 0 ? 29 : 17, x, y)
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
            placeProp(93, bx + w, by + h - 2)       // hay, right shoulder
            placeProp(93, bx + w, by + h - 1)       // hay, right shoulder
            placeProp(94, bx + w + 1, by + h - 1)   // hay, right shoulder
            placeProp(116, bx - 1, by + h - 1)      // pitchfork, left wall
            placeProp(106, bx + w + 1, by + h - 2)  // barrel, right shoulder
            placeProp(107, bx + w + 2, by + h - 1)  // bucket, right shoulder
            placeProp(130, bx - 1, by + h + 1)      // chest, left of the barn
            if let firstLane = layout.laneYs.first {
                placeProp(57, bx + 5, firstLane - 1)                              // mailbox
                placeProp(83, bx - 1, firstLane + FarmLayoutEngine.laneH)         // signpost
            }
        }

        return out
    }
}
