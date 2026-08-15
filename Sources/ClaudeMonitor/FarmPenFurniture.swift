import CoreGraphics
import Foundation

/// Builds the fence ring (with its gate opening), trough, and hanging name plate for a
/// single pen. Pure logic — this returns tile placements and geometry, it never draws.
/// Ported from `mock7.py:390-410` (fences/trough) and `mock7.py:497-end` (labels), per
/// spec §3.1 (fence tiles), §3.2 (sign geometry) and §3.3 (trough).
enum FarmPenFurniture {
    // Fence tile ids, spec §3.1.
    private static let fTopLeft = 44, fTopRight = 46, fBottomLeft = 68, fBottomRight = 70
    private static let fHorizontal = 81, fVertical = 47
    private static let fCapLeft = 80, fCapRight = 82

    /// The fence ring around a pen: four corners, straight rails on all four edges, and
    /// (per §3.1) a 2-tile gap on the gated edge at `gateX-1, gateX`, capped with
    /// `0082` (right-end cap, at `gateX-1`) and `0080` (left-end cap, at `gateX`) so the
    /// rail terminates cleanly on both sides of the opening. There is no gate sprite in
    /// the pack — this reads correctly. A `.none` gate leaves the rail unbroken.
    static func fenceTiles(for pen: PlacedPen) -> [SceneryTile] {
        var out: [SceneryTile] = []
        let x = pen.x, y = pen.y, w = pen.w, h = pen.h
        let gateX = pen.gateX

        // The gate only ever opens onto the top rail (a `.north` gate) or the bottom
        // rail (a `.south` gate); each set below is the columns to leave open on the
        // rail the gate actually sits on.
        let topGate: Set<Int> = pen.gate == .north ? [gateX - 1, gateX] : []
        let bottomGate: Set<Int> = pen.gate == .south ? [gateX - 1, gateX] : []

        out.append(SceneryTile(x: x, y: y, tile: fTopLeft))
        out.append(SceneryTile(x: x + w - 1, y: y, tile: fTopRight))
        out.append(SceneryTile(x: x, y: y + h - 1, tile: fBottomLeft))
        out.append(SceneryTile(x: x + w - 1, y: y + h - 1, tile: fBottomRight))

        for i in 1..<(w - 1) {
            let cx = x + i
            let topTile = topGate.contains(cx) ? (cx == gateX - 1 ? fCapRight : fCapLeft) : fHorizontal
            out.append(SceneryTile(x: cx, y: y, tile: topTile))
            let bottomTile = bottomGate.contains(cx) ? (cx == gateX - 1 ? fCapRight : fCapLeft) : fHorizontal
            out.append(SceneryTile(x: cx, y: y + h - 1, tile: bottomTile))
        }

        for j in 1..<(h - 1) {
            out.append(SceneryTile(x: x, y: y + j, tile: fVertical))
            out.append(SceneryTile(x: x + w - 1, y: y + j, tile: fVertical))
        }

        return out
    }

    /// Every pen keeps its trough, including frozen ones (§3.3): a bucket (`0107`) and
    /// a barrel (`0106`) at the bottom-left of the interior — the pen rect inset by the
    /// 1-tile fence ring.
    static func troughTiles(for pen: PlacedPen) -> [SceneryTile] {
        let ix = pen.x + 1, iy = pen.y + 1, ih = pen.h - 2
        return [
            SceneryTile(x: ix, y: iy + ih - 1, tile: 107),
            SceneryTile(x: ix + 1, y: iy + ih - 1, tile: 106),
        ]
    }

    /// Occupancy is capped at 8 for pen sizing (`FarmLayoutEngine.penSize`); any surplus
    /// animals are reported here as a `+N` suffix rather than silently dropped. The
    /// label is uppercased, `+N` appended if needed, then truncated to fit the pen
    /// (§3.2): `maxPx = (penW - 1) * 16` — the brief's assertion, budgeting the text
    /// alone. mock7.py:504 budgets `textlength(s) + 9` (text plus the plate's 9px of
    /// padding) instead; following the brief here makes the plate up to 9px wider than
    /// mock7's, which still fits inside `penW * 16` once centred, so nothing overflows.
    static func signLabel(for pen: PlacedPen) -> String {
        let name = pen.pen.label.uppercased()
        let surplus = pen.pen.processes.count - 8
        let suffix = surplus > 0 ? " +\(surplus)" : ""
        let maxPx = (pen.w - 1) * 16
        // Truncate the name against the budget left over after the suffix, then
        // reattach the suffix — truncating the combined string first could chop the
        // "+N" off the end, silently un-reporting the surplus this exists to show.
        let nameBudget = max(0, maxPx - PixelText.measure(suffix))
        return PixelText.truncate(name, maxPx: nameBudget) + suffix
    }

    /// Geometry of the wooden name plate, nailed to the top rail and centred over it.
    /// All values are 1× pixels (§3.2). `plateH = 15` is not negotiable: at 12 the `Q`
    /// descender clipped and rendered `NFQ` as `NEO`, `DOTFILES` as `DOTEILES`.
    static func signRect(for pen: PlacedPen) -> CGRect {
        let plateH = 15
        let textWidth = PixelText.measure(signLabel(for: pen))
        let plateW = textWidth + 9
        // `pen.w` divided as a fraction of a tile, not truncated to a whole tile first
        // (mock7.py:507 is `(px + pw / 2) * T`, Python float division) — truncating
        // `pen.w / 2` before scaling by 16 shifts the plate off true centre on every
        // odd-width pen, and 7-wide pens (the spec §3 minimum) are routine, not rare.
        let penCentreX = CGFloat(pen.x) * 16 + CGFloat(pen.w) * 16 / 2
        let x0 = penCentreX - CGFloat(plateW) / 2
        let y0 = pen.y * 16 + 14 - plateH
        return CGRect(x: x0, y: CGFloat(y0), width: CGFloat(plateW), height: CGFloat(plateH))
    }
}
