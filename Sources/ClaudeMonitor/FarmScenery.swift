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

        // ---- small helpers used by orchard rows and treeline fringe -------------
        func smallTree(_ x: Int, _ y: Int, _ autumn: Bool) {
            put(autumn ? 3 : 4, x, y)
            put(autumn ? 15 : 16, x, y + 1)
        }

        // ---- canopy bands: the load-bearing rule from §6.2 ----------------------
        // 0006 0007 0008 over 0018 0019 0020 tile horizontally into one continuous
        // canopy (autumn: 0009 0010 0011 / 0021 0022 0023). Used as bands you get a
        // forest; used as individual trees you get a field of lollipops.
        @discardableResult
        func canopyBand(_ x0In: Int, _ x1In: Int, _ y: Int, _ seed: Int, autumn: Bool) -> Bool {
            let x0 = max(0, x0In), x1 = min(layout.cols, x1In)
            guard x1 - x0 >= 1, y >= 0, y + 2 <= layout.rows else { return false }
            guard clear(x0, y, x1 - x0, 2) else { return false }
            let top = autumn ? [9, 10, 11] : [6, 7, 8]
            let bot = autumn ? [21, 22, 23] : [18, 19, 20]
            for x in x0..<x1 {
                let a = x == x0 ? top[0] : (x == x1 - 1 ? top[2] : top[1])
                let b = x == x0 ? bot[0] : (x == x1 - 1 ? bot[2] : bot[1])
                put(a, x, y)
                put(b, x, y + 1)
            }
            mark(x0, y, x1 - x0, 2)
            return true
        }

        // Ragged horizontal treeline. grow=+1 grows downward from edgeY, grow=-1
        // grows upward (edgeY is the outermost row of the band).
        func treelineH(_ x0: Int, _ x1: Int, _ edgeY: Int, _ grow: Int, _ seed: Int) {
            var fringe: [(y: Int, x: Int, autumn: Bool)] = []
            var x = x0
            while x < x1 {
                let h = StableHash.of(x, edgeY, seed)
                let run = 3 + Int(h % 5)
                let xe = min(x + run, x1)
                let initialDepth = 1 + ((h >> 6) % 100 < 42 ? 1 : 0)
                var depth = initialDepth
                let inset = Int((h >> 10) % 2)
                let autumn = (h >> 14) % 100 < 20
                for b in 0..<initialDepth {
                    let by = grow > 0 ? (edgeY + inset + b * 2) : (edgeY - inset - b * 2 - 1)
                    if !canopyBand(x, xe, by, seed + b, autumn: autumn) {
                        depth = b
                        break
                    }
                }
                // Fringe of single trees/bushes just inside the mass.
                for fx in x..<xe {
                    let hf = StableHash.of(fx, edgeY, seed, 5)
                    if hf % 100 < 30 {
                        let fy = grow > 0 ? (edgeY + inset + depth * 2) : (edgeY - inset - depth * 2 - 1)
                        if clear(fx, fy, 1, 2) {
                            mark(fx, fy, 1, 2)
                            fringe.append((fy, fx, (hf >> 8) % 100 < 20))
                        }
                    } else if hf % 100 < 44 {
                        let fy = grow > 0 ? (edgeY + inset + depth * 2 + 1) : (edgeY - inset - depth * 2)
                        if clear(fx, fy) {
                            put((hf >> 12) % 2 == 1 ? 5 : 28, fx, fy)
                            mark(fx, fy)
                        }
                    }
                }
                x = xe
            }
            for f in fringe.sorted(by: { $0.y == $1.y ? $0.x < $1.x : $0.y < $1.y }) {
                smallTree(f.x, f.y, f.autumn)
            }
        }

        // Ragged vertical treeline. side=+1 hugs the left edge, -1 the right.
        func treelineV(_ edgeX: Int, _ side: Int, _ y0: Int, _ y1: Int, _ seed: Int) {
            var fringe: [(y: Int, x: Int, autumn: Bool)] = []
            var y = y0
            while y < y1 - 1 {
                let h = StableHash.of(edgeX, y, seed)
                let run = 2 + Int(h % 3) * 2
                let w = 2 + Int((h >> 5) % 3)
                let autumn = (h >> 9) % 100 < 18
                var b = 0
                while b < run {
                    let bx0 = side > 0 ? edgeX : edgeX - w
                    if !canopyBand(max(0, bx0), min(layout.cols, bx0 + w), y + b, seed + b, autumn: autumn) {
                        var ww = w
                        while ww > 1 {
                            ww -= 1
                            let bx0b = side > 0 ? edgeX : edgeX - ww
                            if canopyBand(max(0, bx0b), min(layout.cols, bx0b + ww), y + b, seed + b, autumn: autumn) {
                                break
                            }
                        }
                    }
                    b += 2
                }
                for fy in y..<min(y + run, y1) {
                    let hf = StableHash.of(edgeX, fy, seed, 9)
                    let fx = side > 0 ? (edgeX + w) : (edgeX - w - 1)
                    if hf % 100 < 34 && clear(fx, fy, 1, 2) {
                        mark(fx, fy, 1, 2)
                        fringe.append((fy, fx, (hf >> 8) % 100 < 20))
                    } else if hf % 100 < 52 && clear(fx, fy) {
                        put((hf >> 12) % 2 == 1 ? 5 : 28, fx, fy)
                        mark(fx, fy)
                    }
                }
                y += run
            }
            for f in fringe.sorted(by: { $0.y == $1.y ? $0.x < $1.x : $0.y < $1.y }) {
                smallTree(f.x, f.y, f.autumn)
            }
        }

        // Planted orchard rows — a 3-tile lattice with alternating row offset, so it
        // reads as agriculture and contrasts with the wild treeline (§6.3).
        func orchard(_ x0: Int, _ y0: Int, _ x1: Int, _ y1: Int, _ seed: Int) {
            var items: [(y: Int, x: Int, autumn: Bool)] = []
            var j = 0
            var y = y0
            while y < y1 - 1 {
                let off = j % 2 != 0 ? 1 : 0
                var x = x0 + off
                while x < x1 {
                    if clear(x, y, 1, 2) {
                        mark(x, y, 1, 2)
                        items.append((y, x, StableHash.pick(100, x, y, seed) < 22))
                    }
                    x += 3
                }
                j += 1
                y += 3
            }
            for it in items.sorted(by: { $0.y == $1.y ? $0.x < $1.x : $0.y < $1.y }) {
                smallTree(it.x, it.y, it.autumn)
            }
        }

        // Seeded scatter of small props, retried up to 12x per requested count so a
        // crowded target rect still yields close to `n` items.
        func scatter(_ cands: [Int], _ x0: Int, _ y0: Int, _ x1: Int, _ y1: Int, _ nIn: Int, _ seed: Int) {
            var n = nIn
            guard n > 0 else { return }
            let xUpper = max(x0 + 1, x1), yUpper = max(y0 + 1, y1)
            var i = 0
            let maxIter = n * 12
            while i < maxIter && n > 0 {
                let x = x0 + StableHash.pick(xUpper - x0, seed, i, 1)
                let y = y0 + StableHash.pick(yUpper - y0, seed, i, 2)
                if clear(x, y) {
                    let c = cands[StableHash.pick(cands.count, seed, i, 3)]
                    put(c, x, y)
                    mark(x, y)
                    n -= 1
                }
                i += 1
            }
        }

        // ---- woodland frame ------------------------------------------------------
        treelineH(0, layout.cols, 0, +1, seed0 * 3 + 1)
        treelineH(0, layout.cols, layout.rows - 2, -1, seed0 * 3 + 4)
        treelineV(0, +1, 3, layout.rows - 5, seed0 * 3 + 2)
        treelineV(layout.cols, -1, 3, layout.rows - 5, seed0 * 3 + 3)
        // A copse behind the barn nests it into the landscape.
        if let bx = layout.barnX, let by = layout.barnY, by >= 4 {
            canopyBand(bx - 1, bx + FarmLayoutEngine.barnW + 1, by - 2, seed0 * 3 + 5, autumn: false)
        }

        // ---- leftover space in the last row: clustered, not a sprinkle (§6.3) ----
        if !layout.pens.isEmpty {
            let rowGroups = Dictionary(grouping: layout.pens, by: { $0.y + $0.h })
            if let bottomKey = rowGroups.keys.max(), let lastRowPens = rowGroups[bottomKey] {
                let lastRowH = lastRowPens.map(\.h).max() ?? 0
                let lastRowY = bottomKey - lastRowH
                let lastX = lastRowPens.map { $0.x + $0.w }.max() ?? 0
                let gapw = layout.cols - 3 - (lastX + 3)
                if gapw > 10 {
                    let ox = layout.cols - 3 - 11
                    orchard(ox, lastRowY, ox + 11, lastRowY + min(lastRowH, 7), seed0 * 7)
                    scatter([5, 5, 28, 27], ox - 2, lastRowY - 1, ox + 12,
                            lastRowY + lastRowH + 1, 10, seed0 * 11)
                    // A tidy hay yard gives the open lawn a destination.
                    let hx = lastX + 4, hy = lastRowY + 1
                    for (i, n) in [93, 93].enumerated() {
                        if clear(hx + i, hy) { put(n, hx + i, hy); mark(hx + i, hy) }
                    }
                    if clear(hx, hy + 1) { put(94, hx, hy + 1); mark(hx, hy + 1) }
                    if clear(hx + 1, hy + 1) { put(93, hx + 1, hy + 1); mark(hx + 1, hy + 1) }
                    scatter([5, 5, 28], lastX + 2, lastRowY + 2,
                            lastX + 9, lastRowY + lastRowH + 1, 5, seed0 * 17)
                }
            }
        }

        // Hedge shoulders break up the road.
        for ly in layout.laneYs {
            scatter([5, 28, 27], FarmLayoutEngine.marginL, ly - 1,
                    layout.cols - FarmLayoutEngine.marginR, ly + FarmLayoutEngine.laneH + 1,
                    12, ly * 97 + seed0)
        }
        // General lawn scatter — a few clustered features, not a uniform fill.
        scatter([5, 5, 28, 27], 2, 2, layout.cols - 2, layout.rows - 2, 12, seed0 * 13)

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
