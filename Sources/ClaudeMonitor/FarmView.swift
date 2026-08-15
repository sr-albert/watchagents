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
private struct BuiltScene {
    let layout: FarmLayout
    let staticImage: CGImage?
    let signs: [(rect: CGRect, image: CGImage?)]
    let contentCols: Int
    let contentRows: Int
}

private func buildScene(pens: [FarmPen], layout: FarmLayout) -> BuiltScene {
    // `FarmLayoutEngine.layout` reports no barn at all when there are no pens (there's
    // nothing to bottom-align a row to). Spec: the empty state must still be a farm —
    // grass, barn, woodland — not a blank window. Stand the barn near the top margin
    // ourselves in that case; every downstream function already treats `barnX`/`barnY`
    // as optional; this just fills them in instead of leaving them nil.
    let normalized: FarmLayout
    if layout.pens.isEmpty {
        normalized = FarmLayout(
            pens: [], laneYs: [],
            barnX: FarmLayoutEngine.marginL, barnY: FarmLayoutEngine.marginT,
            cols: layout.cols, rows: layout.rows,
            requiredRows: FarmLayoutEngine.marginT + FarmLayoutEngine.barnH + FarmLayoutEngine.frameB
        )
    } else {
        normalized = layout
    }

    let dirt = FarmDirt.dirtCells(layout: normalized)
    // `decorate` already emits the barn as its first tiles, in composite order with
    // every scenery layer after it — spec's "barn" and "scenery" draw-order steps are
    // one call, not two.
    let scenery = FarmScenery.decorate(layout: normalized, dirt: dirt)

    var furniture: [SceneryTile] = []
    var signs: [(rect: CGRect, image: CGImage?)] = []
    for pen in normalized.pens {
        furniture.append(contentsOf: FarmPenFurniture.fenceTiles(for: pen))
        furniture.append(contentsOf: FarmPenFurniture.troughTiles(for: pen))
        let rect = FarmPenFurniture.signRect(for: pen)
        let label = FarmPenFurniture.signLabel(for: pen)
        signs.append((rect, PixelText.image(label)))
    }

    let contentRows = max(normalized.rows, normalized.requiredRows)
    let contentCols = normalized.cols
    let staticImage = renderStaticLayer(dirt: dirt, scenery: scenery, furniture: furniture,
                                        cols: contentCols, rows: contentRows)

    return BuiltScene(layout: normalized, staticImage: staticImage, signs: signs,
                       contentCols: contentCols, contentRows: contentRows)
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
    // matching mock7.py's PIL canvas. Flip once so `blitTile(x, y)` below can use those
    // coordinates directly.
    ctx.translateBy(x: 0, y: CGFloat(h))
    ctx.scaleBy(x: 1, y: -1)

    func blitTile(_ id: Int, _ x: Int, _ y: Int) {
        guard let image = FarmAssets.tile(id) else { return }
        ctx.draw(image, in: CGRect(x: x * 16, y: y * 16, width: 16, height: 16))
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

/// Picks the scale (spec §1/§2.4) by trying 3, 2, 1 in order: at each candidate, lay the
/// real pens out against that scale's window-in-tiles and check the §2.4 fit rule via
/// `FarmScene.scale`. A bigger scale means fewer available columns, which means *more*
/// row-wrapping, not less — so each candidate needs its own real layout, not one
/// computed at a different scale.
private func selectScaleAndLayout(pens: [FarmPen], width: CGFloat, height: CGFloat) -> (scale: Int, layout: FarmLayout) {
    guard width > 0, height > 0 else {
        return (1, FarmLayoutEngine.layout(pens: pens, cols: 1, rows: 1))
    }

    for s in [3, 2, 1] {
        let winCols = Int(width) / (16 * s)
        let winRows = Int(height) / (16 * s)
        guard winCols > 0, winRows > 0 else { continue }
        let layout = FarmLayoutEngine.layout(pens: pens, cols: winCols, rows: winRows)
        let maxPenW = layout.pens.map(\.w).max() ?? 0
        let minCols = maxPenW + FarmLayoutEngine.barnW + FarmLayoutEngine.gap + 1
            + FarmLayoutEngine.marginL + FarmLayoutEngine.marginR
        // Test this candidate directly rather than via `FarmScene.scale(...) == s`:
        // `requiredRows` shrinks as `winCols` grows (fewer columns wrap pens into more
        // rows), so re-running `FarmScene.scale` with *this* candidate's looser
        // `requiredRows` can report a bigger scale than the one actually under test —
        // which would skip over a smaller scale that genuinely fits.
        if winCols >= minCols && winRows >= layout.requiredRows {
            return (s, layout)
        }
    }

    // Nothing fit without scrolling, even at scale 1. Spec §2.4: never clip a pen —
    // scroll instead. Re-run the layout with its own required row count so the
    // woodland/frame bounds (which read `layout.rows`) cover the full scrollable area.
    let winCols = max(1, Int(width) / 16)
    let winRows = max(1, Int(height) / 16)
    var layout = FarmLayoutEngine.layout(pens: pens, cols: winCols, rows: winRows)
    if layout.requiredRows > layout.rows {
        layout = FarmLayoutEngine.layout(pens: pens, cols: winCols, rows: layout.requiredRows)
    }
    return (1, layout)
}

// MARK: - Per-frame drawing

/// One sprite in the depth-sorted draw list: an animal or the farmer (spec §5.4's
/// baseline y-sort, extended to the farmer per the brief — he has no `AnimalPlacement`
/// of his own, but participates in the same sort and gets the same shadow treatment).
private struct Sprite {
    let by: Int
    let x: Int, y: Int
    let image: CGImage
    let shadowCenterX: Int
    let shadowWidth: Int
    let badge: (x: Int, y: Int, tile: Int)?
}

private func collectSprites(scene: BuiltScene, time: Double) -> [Sprite] {
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
                                   shadowWidth: Int(Double(frame.width) * 0.6), badge: badge))
        }
    }

    // The farmer (tile 0103): spec §6.1 lists him, no task placed him. mock7.py:484-485
    // appends him to the y-sorted draw list right after the animals — same sort key
    // convention, same shadow treatment, drawn at a fixed spot by the barn door. `x, y`
    // here are already the sprite's top-left (not a baseline) per mock7.py; only the
    // sort key uses the baseline-style `+ 18`.
    if let barnX = scene.layout.barnX, let barnY = scene.layout.barnY, let farmer = FarmAssets.tile(103) {
        let fx = (barnX + FarmLayoutEngine.barnW - 1) * 16 + 2
        let fy = (barnY + FarmLayoutEngine.barnH) * 16 + 2
        let sortKey = (barnY + FarmLayoutEngine.barnH) * 16 + 18
        sprites.append(Sprite(by: sortKey, x: fx, y: fy, image: farmer,
                               shadowCenterX: fx + 8, shadowWidth: 10, badge: nil))
    }

    return sprites.sorted { $0.by < $1.by }
}

/// Pixel art scaled with smoothing turns to mush; `.interpolation(.none)` keeps every
/// blit nearest-neighbour under the context's integer `scaleBy`.
private func pixelImage(_ cg: CGImage) -> Image {
    Image(decorative: cg, scale: 1, orientation: .up).interpolation(.none)
}

private func draw(scene: BuiltScene, scale: Int, time: Double, canvasSize: CGSize, into ctx: inout GraphicsContext) {
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

    // 6. Animals (+ the farmer): one y-sort, shadows first (as one pass, matching
    // mock7.py compositing the whole shadow layer before any sprite), then the sprites.
    let sprites = collectSprites(scene: scene, time: time)
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

    // 8. Sign plates, drawn last.
    let woodHi = Color(red: 232.0 / 255, green: 174.0 / 255, blue: 118.0 / 255)
    let wood = Color(red: 188.0 / 255, green: 122.0 / 255, blue: 74.0 / 255)
    let woodLo = Color(red: 69.0 / 255, green: 38.0 / 255, blue: 46.0 / 255)
    let ink = Color(red: 48.0 / 255, green: 26.0 / 255, blue: 22.0 / 255)
    for sign in scene.signs {
        let r = sign.rect
        ctx.fill(Path(CGRect(x: r.minX - 1, y: r.minY - 1, width: r.width + 2, height: r.height + 1)),
                 with: .color(woodLo))
        ctx.fill(Path(r), with: .color(wood))
        ctx.fill(Path(CGRect(x: r.minX + 1, y: r.minY + 1, width: max(0, r.width - 2), height: 1)),
                 with: .color(woodHi))
        guard let img = sign.image else { continue }
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
            layer.addFilter(.colorMultiply(ink))
            layer.draw(pixelImage(img), in: CGRect(x: tx, y: ty, width: CGFloat(img.width), height: CGFloat(img.height)))
        }
    }
}

// MARK: - View

struct FarmView: View {
    @ObservedObject var viewModel: MonitorViewModel

    var body: some View {
        VStack(spacing: 0) {
            GeometryReader { geo in
                let pens = FarmGrouping.pens(from: viewModel.snapshot.processes)
                let (scale, rawLayout) = selectScaleAndLayout(pens: pens, width: geo.size.width, height: geo.size.height)
                let scene = buildScene(pens: pens, layout: rawLayout)
                let tile = CGFloat(16 * scale)
                let contentWidth = max(geo.size.width, CGFloat(scene.contentCols) * tile)
                let contentHeight = max(geo.size.height, CGFloat(scene.contentRows) * tile)

                ScrollView(.vertical, showsIndicators: true) {
                    TimelineView(.animation) { context in
                        Canvas { ctx, size in
                            draw(scene: scene, scale: scale,
                                 time: context.date.timeIntervalSinceReferenceDate,
                                 canvasSize: size, into: &ctx)
                        }
                        .frame(width: contentWidth, height: contentHeight)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            // Spec's CC-BY obligation for the LPC animal art (see THIRD-PARTY-NOTICES.md):
            // attribution "in the app's Farm window credits."
            Text("Art: Kenney (CC0) · LPC farm animals by Daniel Eddeland (CC-BY 3.0)")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .padding(.vertical, 4)
                .frame(maxWidth: .infinity)
        }
        .frame(minWidth: 420, minHeight: 320)
    }
}
