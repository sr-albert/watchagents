import CoreGraphics
import SwiftUI

// MARK: - Sprite frames

/// A single LPC sheet frame, cropped to its own visible bounding box. Sheets are laid
/// out on a 4×4 grid of much bigger cells than the actual character (e.g. the cow
/// sheets are 512×512, i.e. 128×128 per cell, for a ~71×44px animal) — drawing the raw
/// cell would put a huge transparent margin around the sprite and break every offset in
/// `FarmAnimalPlacer`. Ported from `mock7.py`'s `frame()`, which does the same trim with
/// PIL's `getbbox()`.
private enum SpriteFrameCache {
    struct Frame {
        let image: CGImage
        let width: Int
        let height: Int
    }

    private static let lock = NSLock()
    nonisolated(unsafe) private static var cache: [String: Frame?] = [:]

    static func frame(species: AnimalSpecies, action: AnimalAction, row: Int, col: Int) -> Frame? {
        let key = "\(species.rawValue)|\(action.rawValue)|\(row)|\(col)"
        lock.lock()
        defer { lock.unlock() }
        if let hit = cache[key] { return hit }
        let result = build(species: species, action: action, row: row, col: col)
        cache[key] = result
        return result
    }

    private static func build(species: AnimalSpecies, action: AnimalAction, row: Int, col: Int) -> Frame? {
        guard let sheet = FarmAssets.animalSheet(species, action) else { return nil }
        let fw = sheet.width / 4, fh = sheet.height / 4
        guard fw > 0, fh > 0 else { return nil }
        guard let cell = sheet.cropping(to: CGRect(x: col * fw, y: row * fh, width: fw, height: fh))
        else { return nil }
        guard let (trimmed, w, h) = trimToVisibleBounds(cell) else { return nil }
        return Frame(image: trimmed, width: w, height: h)
    }

    /// Renders `image` into a raw RGBA buffer, scans for the alpha bounding box, and
    /// crops to it. Straight (non-premultiplied) alpha so a fully-transparent pixel is
    /// unambiguously `alpha == 0`, regardless of the source PNG's own alpha convention.
    private static func trimToVisibleBounds(_ image: CGImage) -> (CGImage, Int, Int)? {
        let w = image.width, h = image.height
        guard w > 0, h > 0 else { return nil }
        var data = [UInt8](repeating: 0, count: w * h * 4)
        // Bitmap contexts only support *premultiplied* alpha layouts — `.last` (straight
        // alpha) makes `CGContext(data:...)` return nil, silently discarding every sprite
        // this is called for. Premultiplication doesn't affect the alpha channel itself,
        // which is all this bbox scan reads, so no un-premultiply step is needed here.
        guard let ctx = CGContext(data: &data, width: w, height: h, bitsPerComponent: 8,
                                   bytesPerRow: w * 4, space: CGColorSpaceCreateDeviceRGB(),
                                   bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))

        var minX = w, minY = h, maxX = -1, maxY = -1
        for y in 0..<h {
            let rowBase = y * w * 4
            for x in 0..<w where data[rowBase + x * 4 + 3] != 0 {
                if x < minX { minX = x }
                if x > maxX { maxX = x }
                if y < minY { minY = y }
                if y > maxY { maxY = y }
            }
        }
        guard maxX >= minX, maxY >= minY else { return nil }
        let rect = CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
        guard let cropped = image.cropping(to: rect) else { return nil }
        return (cropped, Int(rect.width), Int(rect.height))
    }
}

// MARK: - Per-pixel tint

/// Applies `AnimalTint`'s exact per-channel formula (see the doc comment on
/// `AnimalTint` in `FarmAnimal.swift`) and caches the tinted bitmap. `colorMultiply` — a
/// SwiftUI/Core Image filter — cannot express this: the red channel is a *lerp toward
/// 255*, not a multiply, so it needs a manual pixel pass. Cached by a caller-supplied key
/// so a still (`idle`/`frozen`) or slowly-changing (`overloaded`, quantized) tint is
/// computed once, not once per animated frame.
private enum SpriteTintCache {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var cache: [String: CGImage] = [:]

    static func apply(_ tint: AnimalTint, to image: CGImage, cacheKey: String) -> CGImage {
        // Identity tint (idle/active): skip the whole pipeline, including the cache.
        if tint.r == 1, tint.g == 1, tint.b == 1, tint.a == 1, tint.redLift == 0 {
            return image
        }
        lock.lock()
        defer { lock.unlock() }
        if let hit = cache[cacheKey] { return hit }
        let result = render(tint, image) ?? image
        cache[cacheKey] = result
        return result
    }

    private static func render(_ tint: AnimalTint, _ image: CGImage) -> CGImage? {
        let w = image.width, h = image.height
        guard w > 0, h > 0 else { return nil }
        var data = [UInt8](repeating: 0, count: w * h * 4)
        // As above: bitmap contexts require premultiplied alpha, so read/write
        // premultiplied values and un/re-premultiply around the tint formula, which is
        // defined (spec §5.3, `AnimalTint`'s doc comment) in terms of straight RGB.
        guard let ctx = CGContext(data: &data, width: w, height: h, bitsPerComponent: 8,
                                   bytesPerRow: w * 4, space: CGColorSpaceCreateDeviceRGB(),
                                   bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))

        for i in stride(from: 0, to: data.count, by: 4) {
            let a = Double(data[i + 3])
            guard a != 0 else { continue }
            let r = Double(data[i]) * 255 / a
            let g = Double(data[i + 1]) * 255 / a
            let b = Double(data[i + 2]) * 255 / a
            let outR = r * tint.r + (255 - r) * tint.redLift
            let outG = g * tint.g
            let outB = b * tint.b
            let outA = a * tint.a
            data[i] = UInt8(max(0, min(255, outR * outA / 255)).rounded())
            data[i + 1] = UInt8(max(0, min(255, outG * outA / 255)).rounded())
            data[i + 2] = UInt8(max(0, min(255, outB * outA / 255)).rounded())
            data[i + 3] = UInt8(max(0, min(255, outA)).rounded())
        }
        return ctx.makeImage()
    }
}

/// A stable cache key for a placement's (sprite, tint) pair. Frozen's tint is constant,
/// so it caches forever; overloaded's tint pulses continuously, so its `redLift` is
/// quantized to 16 steps — visually indistinguishable from the exact value, but it means
/// a pen full of overloaded animals doesn't rebuild a tinted bitmap on every one of 60
/// frames a second.
private func tintCacheKey(spriteKey: String, state: SessionState, tint: AnimalTint) -> String {
    switch state {
    case .idle, .active:
        return spriteKey
    case .frozen:
        return spriteKey + "|frozen"
    case .overloaded:
        let bucket = Int((tint.redLift / 0.45 * 16).rounded())
        return spriteKey + "|ovl\(bucket)"
    }
}

// MARK: - Scene composition

/// Everything needed to draw one frame: the static geometry (computed once per pens/
/// window-size change, not per animation tick) plus a pre-flattened bitmap of every
/// time-invariant layer. Redrawing ground/dirt/scenery/fences tile-by-tile inside the
/// `TimelineView(.animation)` closure would mean thousands of small `CGImage` composites
/// 60 times a second for a busy farm; instead that whole stack is rendered once into
/// `staticImage` here, and the per-frame closure just blits it and then draws the
/// handful of things that actually change (animals, their tints, sign plates).
struct BuiltScene {
    let layout: FarmLayout
    let staticImage: CGImage?
    let signs: [(rect: CGRect, image: CGImage?)]
    let contentCols: Int
    let contentRows: Int
}

func buildScene(pens: [FarmPen], layout: FarmLayout) -> BuiltScene {
    // `FarmLayoutEngine.layout` reports no barn at all when there are no pens (there's
    // nothing to bottom-align a row to). Spec: the empty state must still be a farm —
    // grass, barn, woodland — not a blank window. Stand the barn near the top margin
    // ourselves in that case; every downstream function already treats `barnX`/`barnY`
    // as optional; this just fills them in instead of leaving them nil.
    let normalized: FarmLayout
    if layout.pens.isEmpty {
        // Fix 6: `rows` must already be at least `requiredRows` here, the same way the
        // scroll path (`FarmScene`'s "nothing fit" fallback) re-derives `rows` from
        // `requiredRows` before returning. Leaving `rows` at the window's (possibly
        // smaller) row count while reporting a bigger `requiredRows` separately made
        // `FarmDirt`/`FarmScenery` — which clip against `layout.rows`, not
        // `requiredRows` — draw the treeline and frame against the wrong, shorter
        // bound, at whatever scale is short enough to hit it.
        normalized = FarmLayout(
            pens: [], laneYs: [],
            barnX: FarmLayoutEngine.marginL, barnY: FarmLayoutEngine.marginT,
            cols: layout.cols, rows: max(layout.rows, layout.requiredRows),
            requiredRows: layout.requiredRows
        )
    } else {
        normalized = layout
    }

    var signs: [(rect: CGRect, image: CGImage?)] = []
    for pen in normalized.pens {
        let rect = FarmPenFurniture.signRect(for: pen)
        let label = FarmPenFurniture.signLabel(for: pen)
        signs.append((rect, PixelText.image(label)))
    }

    let contentRows = max(normalized.rows, normalized.requiredRows)
    let contentCols = normalized.cols

    // Fix 3: the static layer (ground, dirt, barn/scenery, fences, troughs) is a pure
    // function of pen geometry — (cwd, species, occupancy) per pen, in order, plus the
    // window's cols/rows — and never of live session `state`. `MonitorViewModel`
    // republishes `snapshot` roughly every 2s even when nothing about the farm's
    // shape changed, which without this cache re-ran `FarmScenery.decorate`'s scatter/
    // mushroom passes and ~1400+ `CGImage` blits in `renderStaticLayer` on every poll.
    let key = StaticLayerKey(
        cols: normalized.cols, rows: normalized.rows,
        pens: normalized.pens.map {
            StaticLayerKey.PenKey(cwd: $0.pen.cwd, species: $0.pen.species, count: $0.pen.processes.count)
        }
    )
    let staticImage = StaticLayerCache.image(for: key) {
        let dirt = FarmDirt.dirtCells(layout: normalized)
        // `decorate` already emits the barn as its first tiles, in composite order
        // with every scenery layer after it — spec's "barn" and "scenery" draw-order
        // steps are one call, not two.
        let scenery = FarmScenery.decorate(layout: normalized, dirt: dirt)

        var furniture: [SceneryTile] = []
        for pen in normalized.pens {
            furniture.append(contentsOf: FarmPenFurniture.fenceTiles(for: pen))
            furniture.append(contentsOf: FarmPenFurniture.troughTiles(for: pen))
        }
        return renderStaticLayer(dirt: dirt, scenery: scenery, furniture: furniture,
                                 cols: contentCols, rows: contentRows)
    }

    return BuiltScene(layout: normalized, staticImage: staticImage, signs: signs,
                       contentCols: contentCols, contentRows: contentRows)
}

/// Fix 3: cache key for the static layer. Deliberately excludes everything about live
/// session state — `SessionState`, cpu/mem, pid — since none of it affects ground,
/// dirt, scenery, fences, or troughs (spec §4.2-§4.4, §6). Keyed on the *raw*
/// `cols`/`rows` fields that `FarmDirt`/`FarmScenery` actually clip against, not the
/// derived `contentCols`/`contentRows` — two layouts that agree on `requiredRows` but
/// differ in `rows` (e.g. one needing to scroll and one not) still clip differently
/// and must not collide. `requiredRows` itself is a pure function of `(cols, rows,
/// pens)`, so it doesn't need its own slot in the key.
private struct StaticLayerKey: Equatable {
    struct PenKey: Equatable {
        let cwd: String
        let species: AnimalSpecies
        let count: Int
    }
    let cols: Int
    let rows: Int
    let pens: [PenKey]
}

/// Single-slot memo (not a growing dictionary): this app shows one farm view at a
/// time, so there is only ever one "current" static layer worth keeping. A stale
/// cached image would be a visible bug, so every field the layer actually depends on
/// must be in `StaticLayerKey` — see its doc comment.
private enum StaticLayerCache {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var lastKey: StaticLayerKey?
    nonisolated(unsafe) private static var lastImage: CGImage?

    static func image(for key: StaticLayerKey, build: () -> CGImage?) -> CGImage? {
        lock.lock()
        defer { lock.unlock() }
        if let lastKey, lastKey == key {
            return lastImage
        }
        let image = build()
        lastKey = key
        lastImage = image
        return image
    }
}

/// Flattens ground + dirt + barn/scenery + fences/troughs into one offscreen bitmap, in
/// 1× tile-pixel space (draw order per spec §8, steps 1-5).
private func renderStaticLayer(dirt: Set<TilePoint>, scenery: [SceneryTile], furniture: [SceneryTile],
                                cols: Int, rows: Int) -> CGImage? {
    let w = max(1, cols * 16), h = max(1, rows * 16)
    guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                               space: CGColorSpaceCreateDeviceRGB(),
                               bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    else { return nil }
    // CGContext's default device space is bottom-left-origin/y-up; every tile coordinate
    // in this codebase (FarmLayout, FarmDirt, FarmScenery...) is top-left-origin/y-down,
    // matching mock7.py's PIL canvas. Converted per blit, in the `y` term below.
    //
    // Deliberately NOT by flipping the context with `scaleBy(x: 1, y: -1)`: that puts the
    // rows in the right order but the CTM then applies to the tile bitmaps as well, so
    // every tile lands in its correct cell drawn upside down. It is a quiet failure —
    // ground and rails are near enough symmetric to look fine — and it cost two rewrites
    // of the woodland, whose trees were flipped canopy-under-trunk, before anyone traced
    // it back here rather than blaming the art.
    func blitTile(_ id: Int, _ x: Int, _ y: Int) {
        guard let image = FarmAssets.tile(id) else { return }
        ctx.draw(image, in: CGRect(x: x * 16, y: h - (y + 1) * 16, width: 16, height: 16))
    }

    for y in 0..<rows {
        for x in 0..<cols {
            blitTile(FarmGround.grassTile(x: x, y: y), x, y)
        }
    }
    for p in dirt where p.x >= 0 && p.x < cols && p.y >= 0 && p.y < rows {
        blitTile(FarmDirt.tile(at: p, in: dirt), p.x, p.y)
    }
    for t in scenery { blitTile(t.tile, t.x, t.y) }
    for t in furniture { blitTile(t.tile, t.x, t.y) }

    return ctx.makeImage()
}

// MARK: - Per-frame drawing

/// One sprite in the depth-sorted draw list: an animal or the fixed tile-0103 prop
/// beside the barn door (kept as `farmer` below for naming continuity with mock7.py —
/// spec §5.4's baseline y-sort, extended to it per the brief — it has no
/// `AnimalPlacement` of its own, but participates in the same sort and gets the same
/// shadow treatment). It isn't actually a character: 0103 renders as a grey-framed
/// wooden fixture (a window or cabinet), not a person — see the note above where it's
/// placed, below.
struct Sprite {
    let by: Int
    let x: Int, y: Int
    let image: CGImage
    let shadowCenterX: Int
    let shadowWidth: Int
    let badge: (x: Int, y: Int, tile: Int)?
    /// The session this sprite stands for, for hit-testing (`FarmHitTest`). `nil` for the
    /// tile-0103 fixture below, which is scenery — there is no session to select.
    let pid: Int?
}

func collectSprites(scene: BuiltScene, time: Double) -> [Sprite] {
    var sprites: [Sprite] = []

    for pen in scene.layout.pens {
        for placement in FarmScene.drawOrder(FarmAnimalPlacer.place(pen: pen, time: time)) {
            guard let frame = SpriteFrameCache.frame(species: placement.species, action: placement.sheet,
                                                      row: placement.row, col: placement.frame)
            else { continue }
            let spriteKey = "\(placement.species.rawValue)|\(placement.sheet.rawValue)|\(placement.row)|\(placement.frame)"
            let tint = FarmAnimalPlacer.tint(for: placement.state, time: time)
            let key = tintCacheKey(spriteKey: spriteKey, state: placement.state, tint: tint)
            let image = SpriteTintCache.apply(tint, to: frame.image, cacheKey: key)

            var badge: (x: Int, y: Int, tile: Int)?
            if let badgeTile = placement.badgeTile {
                // Spec §5.3: horizontally centred on the sprite, 13px above its top edge.
                badge = (placement.bx + frame.width / 2 - 8, placement.by - frame.height - 13, badgeTile)
            }
            sprites.append(Sprite(by: placement.by, x: placement.bx, y: placement.by - frame.height,
                                   image: image, shadowCenterX: placement.bx + frame.width / 2,
                                   shadowWidth: Int(Double(frame.width) * 0.6), badge: badge,
                                   pid: placement.pid))
        }
    }

    // Tile 0103: spec §6.1 lists a "character by the door for scale and life", but
    // 0103 is not a character — it renders as a grey-framed wooden fixture (a window
    // or cabinet). The code faithfully ports mock7.py:484, so this is the spec's prose
    // that's wrong, not the asset choice; the asset pack simply has no door-side
    // character sprite. mock7.py:484-485 appends it to the y-sorted draw list right
    // after the animals — same sort key convention, same shadow treatment, drawn at a
    // fixed spot by the barn door. `x, y` here are already the sprite's top-left (not
    // a baseline) per mock7.py; only the sort key uses the baseline-style `+ 18`.
    if let barnX = scene.layout.barnX, let barnY = scene.layout.barnY, let farmer = FarmAssets.tile(103) {
        let fx = (barnX + FarmLayoutEngine.barnW - 1) * 16 + 2
        let fy = (barnY + FarmLayoutEngine.barnH) * 16 + 2
        let sortKey = (barnY + FarmLayoutEngine.barnH) * 16 + 18
        sprites.append(Sprite(by: sortKey, x: fx, y: fy, image: farmer,
                               shadowCenterX: fx + 8, shadowWidth: 10, badge: nil, pid: nil))
    }

    return sprites.sorted { $0.by < $1.by }
}

/// The hit targets for the frame the `Canvas` most recently drew. Sprite positions are
/// `time`-dependent (walk cycle, bounce, idle wander) and a gesture handler has no access
/// to the `TimelineView`'s date, so recomputing them there would hit-test a frame that was
/// never on screen. Handing the gesture what was actually drawn keeps clicking WYSIWYG.
/// Single-slot and lock-guarded, the same idiom as `StaticLayerCache` — one farm window
/// exists at a time, so there is only ever one current frame.
private enum LastDrawnFrame {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var stored: [HitTarget] = []
    nonisolated(unsafe) private static var storedPens: [PenTarget] = []

    static func store(_ value: [HitTarget], pens: [PenTarget]) {
        lock.lock()
        defer { lock.unlock() }
        stored = value
        storedPens = pens
    }

    static func targets() -> [HitTarget] {
        lock.lock()
        defer { lock.unlock() }
        return stored
    }

    /// Pens do not move between frames, so unlike the sprite boxes these are published
    /// here for cost rather than for correctness: `signRect` measures its label's pixel
    /// width, and recomputing that for every pen on every mouse-move event is wasteful
    /// when the answer only changes when the layout does.
    static func penTargets() -> [PenTarget] {
        lock.lock()
        defer { lock.unlock() }
        return storedPens
    }
}

/// The wooden sign palette, shared by the pen name plates drawn here and the detail card
/// in `FarmDetailCard.swift` so the card reads as part of the same farm.
enum FarmPalette {
    static let woodHi = Color(red: 232.0 / 255, green: 174.0 / 255, blue: 118.0 / 255)
    static let wood = Color(red: 188.0 / 255, green: 122.0 / 255, blue: 74.0 / 255)
    static let woodLo = Color(red: 69.0 / 255, green: 38.0 / 255, blue: 46.0 / 255)
    static let ink = Color(red: 48.0 / 255, green: 26.0 / 255, blue: 22.0 / 255)
}

/// Pixel art scaled with smoothing turns to mush; `.interpolation(.none)` keeps every
/// blit nearest-neighbour under the context's integer `scaleBy`.
private func pixelImage(_ cg: CGImage) -> Image {
    Image(decorative: cg, scale: 1, orientation: .up).interpolation(.none)
}

/// One wooden plate with a pixel-text label centred on it: the pen signs nailed to the
/// top rail, and the pointer/selection name plate above an animal.
private func drawPlate(_ r: CGRect, text: CGImage?, into ctx: inout GraphicsContext) {
    ctx.fill(Path(CGRect(x: r.minX - 1, y: r.minY - 1, width: r.width + 2, height: r.height + 1)),
             with: .color(FarmPalette.woodLo))
    ctx.fill(Path(r), with: .color(FarmPalette.wood))
    ctx.fill(Path(CGRect(x: r.minX + 1, y: r.minY + 1, width: max(0, r.width - 2), height: 1)),
             with: .color(FarmPalette.woodHi))
    guard let img = text else { return }
    // Rounded to a whole pixel: `PixelText.image` is a pre-rendered crisp bitmap
    // meant to be blitted like a sprite, and `plateW = textWidth + 9` (odd whenever
    // textWidth is even) makes the mathematically-centred offset land on a half
    // pixel — with `.interpolation(.none)` that sub-pixel offset makes Core
    // Graphics resample individual glyph columns inconsistently, visibly distorting
    // letters like R/D rather than just shifting the whole label half a pixel.
    let tx = (r.minX + (r.width - CGFloat(img.width)) / 2).rounded()
    let ty = (r.minY + (r.height - CGFloat(img.height)) / 2).rounded()
    // `PixelText.image` renders white glyphs on transparent — recolor them to ink
    // via a multiply filter rather than baking a colour into the (cached) bitmap.
    ctx.drawLayer { layer in
        layer.addFilter(.colorMultiply(FarmPalette.ink))
        layer.draw(pixelImage(img), in: CGRect(x: tx, y: ty, width: CGFloat(img.width), height: CGFloat(img.height)))
    }
}

private func draw(scene: BuiltScene, scale: Int, time: Double, canvasSize: CGSize,
                  doorsOpen: Bool, into ctx: inout GraphicsContext) {
    // Leftover window space (the common case — window pixel size is rarely an exact
    // multiple of 16*scale) extends the ground fill; it never letterboxes.
    let grassBG = Color(red: 110.0 / 255, green: 190.0 / 255, blue: 90.0 / 255)
    ctx.fill(Path(CGRect(origin: .zero, size: canvasSize)), with: .color(grassBG))

    let tile = CGFloat(16 * scale)
    if let staticImage = scene.staticImage {
        let w = CGFloat(scene.contentCols) * tile
        let h = CGFloat(scene.contentRows) * tile
        ctx.draw(pixelImage(staticImage), in: CGRect(x: 0, y: 0, width: w, height: h))
    }

    ctx.scaleBy(x: CGFloat(scale), y: CGFloat(scale))

    // 6. Animals (+ the tile-0103 barn-door fixture): one y-sort, shadows first (as one pass, matching
    // mock7.py compositing the whole shadow layer before any sprite), then the sprites.
    let sprites = collectSprites(scene: scene, time: time)
    // Publish this exact frame's boxes for the hover/click handlers — see `LastDrawnFrame`.
    LastDrawnFrame.store(FarmHitTest.targets(from: sprites),
                         pens: FarmHitTest.penTargets(from: scene.layout.pens))
    let shadowColor = Color(red: 32.0 / 255, green: 62.0 / 255, blue: 34.0 / 255, opacity: 0.31)
    for s in sprites {
        let cx = CGFloat(s.shadowCenterX), sw = CGFloat(s.shadowWidth), sy = CGFloat(s.by)
        let rect = CGRect(x: cx - sw / 2, y: sy - 4, width: sw, height: 6)
        ctx.fill(Path(ellipseIn: rect), with: .color(shadowColor))
    }
    for s in sprites {
        ctx.draw(pixelImage(s.image),
                  in: CGRect(x: s.x, y: s.y, width: s.image.width, height: s.image.height))
    }

    // 7. Badges, after every sprite.
    for s in sprites {
        guard let badge = s.badge, let img = FarmAssets.tile(badge.tile) else { continue }
        ctx.draw(pixelImage(img), in: CGRect(x: badge.x, y: badge.y, width: img.width, height: img.height))
    }

    // 7b. The barn's doors, when the farmhouse is open. Painted over the shut pair the
    // static layer already baked in, rather than rebuilt into it: that layer is cached and
    // only regenerated when the layout changes, so putting door state in it would discard
    // the whole barn, ground and scenery on every click.
    if doorsOpen, let bx = scene.layout.barnX, let by = scene.layout.barnY {
        for t in FarmScenery.barnDoorTiles(x: bx, y: by, open: true) {
            guard let img = FarmAssets.tile(t.tile) else { continue }
            ctx.draw(pixelImage(img),
                     in: CGRect(x: t.x * 16, y: t.y * 16, width: 16, height: 16))
        }
    }

    // 8. Sign plates, drawn last.
    for sign in scene.signs {
        drawPlate(sign.rect, text: sign.image, into: &ctx)
    }

    // 9. Nothing hangs over the animal here any more. The pointer used to raise a small
    // wooden "PID nnnn" plate at exactly this spot; `FarmDetailCard` now sits there
    // instead, and carries the pid along with everything else the plate could not fit.

}

// MARK: - View

/// Window point → the 1× tile-pixel space every animal is drawn in.
private func farmPoint(_ point: CGPoint, scale: Int) -> CGPoint {
    CGPoint(x: point.x / CGFloat(scale), y: point.y / CGFloat(scale))
}

struct FarmView: View {
    @ObservedObject var viewModel: MonitorViewModel
    @State private var hoveredPID: Int?
    @State private var selectedPID: Int?
    /// Keyed by working directory, not by pen index: the pen list is rebuilt from every
    /// snapshot and a project that exits shifts every index after it, which would leave
    /// an open modal silently showing a different project.
    @State private var modalCWD: String?
    /// Persisted, because the panel costs the farm 240pt of the width it picks its tile
    /// scale from: someone who shuts it to get 2x animals back wants it to stay shut.
    @AppStorage("farmInfoPanelOpen") private var panelOpen = true
    /// Whether the barn's doors are open, which is the same thing as whether the farmhouse
    /// modal is showing — the doors are the modal's only opening animation.
    @State private var houseOpen = false
    /// The box of the animal the card belongs to, in 1x tile-pixel space, captured when it
    /// was pointed at or clicked rather than read per frame. An active animal is walking,
    /// and a card that chased it would jitter along at mouse-move rate and slide out from
    /// under the pointer; anchoring it where you aimed is both steadier and easier to read.
    @State private var cardRect: CGRect?

    /// Resolved live from the current snapshot rather than captured at hover or click
    /// time, so the card's numbers tick with the poll and the card dismisses itself when
    /// the session exits.
    private var cardProcess: ClaudeProcess? {
        guard let pid = FarmCardSelection.shownPID(hovered: hoveredPID, pinned: selectedPID)
        else { return nil }
        return viewModel.snapshot.processes.first { $0.pid == pid }
    }

    /// Same rule as `selectedProcess`: live, so the modal's aggregates tick with the poll
    /// and it closes itself when the project's last session exits.
    private var modalPen: FarmPen? {
        guard let modalCWD else { return nil }
        return pens.first { $0.cwd == modalCWD }
    }

    private var pens: [FarmPen] { FarmGrouping.pens(from: viewModel.snapshot.processes) }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                // A sibling of the panel rather than something the panel is laid over:
                // the farm picks its tile scale from the width this `GeometryReader`
                // reports, so the panel has to take that width away for real.
                farmCanvas
                panelTab
                if panelOpen {
                    FarmInfoPanel(pens: pens, usage: viewModel.usageResult) { cwd in
                        modalCWD = cwd
                        selectedPID = nil
                    }
                    .transition(.move(edge: .trailing))
                }
            }

            // Spec's CC-BY obligation for the LPC animal art (see THIRD-PARTY-NOTICES.md):
            // attribution "in the app's Farm window credits."
            Text("Art: Kenney (CC0) · LPC farm animals by Daniel Eddeland (CC-BY 3.0)")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .padding(.vertical, 4)
                .frame(maxWidth: .infinity)
        }
        // Mounted here, on the whole window, and deliberately not inside the `ScrollView`
        // above: content inside it scrolls, so a modal placed there would drift off
        // centre the moment the farm was scrolled.
        .overlay {
            if houseOpen {
                ZStack {
                    Color.black.opacity(0.45)
                        .ignoresSafeArea()
                        .onTapGesture { houseOpen = false }
                    FarmHouseModal(usage: viewModel.usageResult,
                                   overloadSettings: viewModel.overloadSettings) {
                        houseOpen = false
                    }
                }
                .onExitCommand { houseOpen = false }
                .transition(.opacity)
            }
        }
        .overlay {
            if let pen = modalPen {
                ZStack {
                    Color.black.opacity(0.45)
                        .ignoresSafeArea()
                        .onTapGesture { modalCWD = nil }
                    FarmProjectModal(pen: pen) { modalCWD = nil }
                }
                // Escape is wired but not relied on: this is an `LSUIElement` accessory
                // app whose window is not always key, and a non-key window may never see
                // the command. The scrim and the close button are the dismissals that
                // always work.
                .onExitCommand { modalCWD = nil }
                .transition(.opacity)
            }
        }
        // Spec §2.4's own 1x minimum width: with the barn on its own row (Fix 2), the
        // worst realistic pen (8 of the largest species, penW=23) needs
        // 23 + marginL(4) + marginR(4) = 31 columns = 496px at 1x. Below this, a pen
        // could clip past the right margin. The panel and its tab are added on top of
        // that, so opening the panel widens the window rather than squeezing the farm
        // under its own minimum.
        .frame(minWidth: 496 + Self.tabWidth + (panelOpen ? FarmInfoPanel.width : 0),
               minHeight: 320)
    }

    private var farmCanvas: some View {
        GeometryReader { geo in
            let (scale, rawLayout) = FarmScene.selectScaleAndLayout(pens: pens, width: geo.size.width, height: geo.size.height)
            let scene = buildScene(pens: pens, layout: rawLayout)
            let tile = CGFloat(16 * scale)
            let contentWidth = max(geo.size.width, CGFloat(scene.contentCols) * tile)
            let contentHeight = max(geo.size.height, CGFloat(scene.contentRows) * tile)

            ScrollView(.vertical, showsIndicators: true) {
                // The fastest thing on screen is the 6fps walk cycle (bounce is
                // 2Hz, the pulse 1.2Hz) — `.animation` alone redraws at 60-120Hz
                // even when every animal is idle/frozen, which spec §5.1 says is
                // the common case. Throttling to 12Hz loses nothing visible and
                // cuts redraws 5-10x for a scene that's usually motionless.
                TimelineView(.animation(minimumInterval: 1.0 / 12.0)) { context in
                    Canvas { ctx, size in
                        draw(scene: scene, scale: scale,
                             time: context.date.timeIntervalSinceReferenceDate,
                             canvasSize: size,
                             doorsOpen: houseOpen, into: &ctx)
                    }
                    .frame(width: contentWidth, height: contentHeight)
                    // Anchored to the animal, inside the scrolling content, so the card
                    // stays with its subject rather than sitting in a corner you have to
                    // look away to read.
                    .overlay(alignment: .topLeading) {
                        if let process = cardProcess, let rect = cardRect {
                            anchoredCard(process, over: rect, scale: scale,
                                         contentWidth: contentWidth)
                        }
                    }
                    // Everything after `ctx.scaleBy` — every animal — is drawn in 1×
                    // tile-pixel space, so window points divide by `scale` before any
                    // hit test. `.local` keeps this correct once the view scrolls.
                    .onContinuousHover(coordinateSpace: .local) { phase in
                        switch phase {
                        case .active(let point):
                            let p = farmPoint(point, scale: scale)
                            let target = FarmHitTest.target(at: p, in: LastDrawnFrame.targets())
                            // Only assign on a real transition: moving the pointer
                            // within one animal must not re-evaluate `body` at
                            // mouse-move rate.
                            if target?.pid != hoveredPID {
                                hoveredPID = target?.pid
                                if let target { cardRect = target.rect }
                            }
                            let hit = target?.pid
                            // Re-set on every event, not only on transitions:
                            // AppKit's own cursor rects reassert themselves as the
                            // pointer moves and would clobber a one-shot set.
                            let onFence = FarmHitTest.penFenceIndex(
                                at: p, in: LastDrawnFrame.penTargets()) != nil
                            let onBarn = FarmHitTest.barnTarget(from: scene.layout)?
                                .rect.contains(p) ?? false
                            FarmCursor.set(interactable: hit != nil || onFence || onBarn)
                        case .ended:
                            if hoveredPID != nil { hoveredPID = nil }
                            FarmCursor.reset()
                        }
                    }
                    // `onTapGesture` only reports a location on macOS 14; a
                    // zero-distance drag gives one on 13. `simultaneousGesture`, not
                    // `gesture`: a zero-distance drag attached exclusively would
                    // compete with the enclosing ScrollView for the event stream. The
                    // translation guard below is what keeps an actual drag from
                    // selecting anything.
                    .simultaneousGesture(
                        DragGesture(minimumDistance: 0).onEnded { value in
                            guard abs(value.translation.width) < 3,
                                  abs(value.translation.height) < 3 else { return }
                            let p = farmPoint(value.location, scale: scale)
                            // The barn is checked first, though nothing contests it:
                            // scenery keeps a one-tile buffer around it, so no pen or
                            // animal can be underneath.
                            if FarmHitTest.barnTarget(from: scene.layout)?.rect.contains(p) == true {
                                houseOpen = true
                                selectedPID = nil
                                return
                            }
                            // The fence wins over the animals. It is the pen's
                            // outline, an animal can stand against the inside of it,
                            // and someone aiming at a rail means the project.
                            if let pen = FarmHitTest.penFenceIndex(at: p, in: LastDrawnFrame.penTargets()) {
                                modalCWD = scene.layout.pens[pen].pen.cwd
                                selectedPID = nil
                                return
                            }
                            let target = FarmHitTest.target(at: p, in: LastDrawnFrame.targets())
                            selectedPID = target?.pid
                            if let target { cardRect = target.rect }
                        }
                    )
                }
            }
            // Bottom-trailing, not top: `FarmLayoutEngine` puts the barn and the first
            // pen along row 0, so a card in the top-right corner would routinely cover
            // the very animal you just clicked. The last pen row is the one that runs
            // short, which makes the bottom-right the emptiest corner of the scene.

        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// `FarmDetailCard`'s own fixed width, needed here to keep it on screen.
    private static let cardWidth: CGFloat = 210
    /// Only used to decide which side of the animal the card goes on. The real height is
    /// whatever the content comes to; this is a deliberate over-estimate, so the card flips
    /// below the animal slightly sooner than it strictly has to rather than one frame too
    /// late, with its top row already cut off by the edge of the farm.
    private static let cardHeightGuess: CGFloat = 190

    /// The card, hung off the animal's own box. Positioned by overlaying a zero-size point
    /// so the layout never needs the card's height: `.bottom` alignment puts the card
    /// *above* the point, `.top` puts it below, and either way the card sizes itself.
    private func anchoredCard(_ process: ClaudeProcess, over rect: CGRect, scale: Int,
                              contentWidth: CGFloat) -> some View {
        let s = CGFloat(scale)
        let above = rect.minY * s > Self.cardHeightGuess
        let y = above ? rect.minY * s - 6 : rect.maxY * s + 6
        // Centred on the animal, then pulled back inside the farm: an animal against
        // either edge would otherwise hang half its card off the side.
        let half = Self.cardWidth / 2 + 4
        let x = min(max(rect.midX * s, half), max(half, contentWidth - half))
        let pinned = FarmCardSelection.isDismissable(shown: process.pid, pinned: selectedPID)

        return Color.clear
            .frame(width: 0, height: 0)
            .overlay(alignment: above ? .bottom : .top) {
                FarmDetailCard(process: process,
                               onClose: pinned ? { selectedPID = nil } : nil)
            }
            .offset(x: x, y: y)
            // A hover card is transparent to the pointer: it has nothing to click, and
            // taking events would let it steal the hover from the animal holding it open.
            // A pinned one has to accept them, or its close button is unreachable.
            .allowsHitTesting(pinned)
    }

    private static let tabWidth: CGFloat = 14

    /// The panel's handle: a strip down the farm's trailing edge. Full height rather than
    /// a small corner button because the farm scrolls and a vertical scrollbar would land
    /// on top of anything smaller, and because the panel is the only farm control that is
    /// not diegetic — there is no barn or fence to hang it on.
    private var panelTab: some View {
        Button {
            withAnimation(.easeOut(duration: 0.18)) { panelOpen.toggle() }
        } label: {
            Image(systemName: panelOpen ? "chevron.right" : "chevron.left")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(FarmPalette.ink)
                .frame(width: Self.tabWidth)
                .frame(maxHeight: .infinity)
                .background(FarmPalette.woodHi)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        // Not `FarmCursor.reset()` on the way out: the tab is flush against the canvas,
        // whose `onContinuousHover` re-asserts the cursor on every mouse-move event, and
        // the two would race across the seam and flicker the pixel arrow to AppKit's.
        .onHover { inside in FarmCursor.set(interactable: inside) }
        .help(panelOpen ? "Hide farm information" : "Show farm information")
        .accessibilityLabel(panelOpen ? "Hide farm information" : "Show farm information")
    }
}
