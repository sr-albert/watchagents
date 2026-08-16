import CoreGraphics

/// One clickable animal: the session behind it and the box it occupies, in 1× tile-pixel
/// space (the space everything after `ctx.scaleBy` is drawn in — callers must divide a
/// window point by the current scale before looking it up).
struct HitTarget: Equatable {
    let pid: Int
    let rect: CGRect
}

/// One clickable pen: the project behind it and its fence, in the same 1× tile-pixel
/// space as `HitTarget`. The fence is the ring between the two rects — `rect` is the
/// pen's outer edge and `innerRect` is the hole the animals stand in.
struct PenTarget: Equatable {
    let index: Int
    let rect: CGRect
    let innerRect: CGRect
}

/// The barn, as a click target: the whole building, in the same 1x tile-pixel space as
/// the others. There is at most one per scene, and a layout can have none.
struct BarnTarget: Equatable {
    let rect: CGRect
}

/// Maps a point in the farm to the session under it. Bounding boxes only — per-pixel
/// alpha testing would make the gaps between a cow's legs un-clickable for no benefit,
/// since animals are already spaced far enough apart that their boxes rarely overlap.
enum FarmHitTest {
    /// A couple of pixels of slop around every sprite. The sprites are trimmed to their
    /// exact visible bounds, so without this the outermost pixel row is a miss.
    static let padding: CGFloat = 2

    /// No animal's clickable box is ever smaller than one tile. A chicken trims to
    /// ~31×26px, but individual walk frames are narrower still, and at scale 1 a sprite
    /// is drawn at its own pixel size — the smallest animals would otherwise be a
    /// pixel-hunt.
    static let minimumSize: CGFloat = 16

    /// Preserves the input's ordering, which `pid(at:in:)` depends on: `collectSprites`
    /// returns its list sorted ascending by baseline `y`, i.e. back to front.
    static func targets(from sprites: [Sprite]) -> [HitTarget] {
        sprites.compactMap { sprite in
            guard let pid = sprite.pid else { return nil }
            return HitTarget(pid: pid, rect: hitRect(for: sprite))
        }
    }

    private static func hitRect(for sprite: Sprite) -> CGRect {
        grown(CGRect(x: CGFloat(sprite.x), y: CGFloat(sprite.y),
                     width: CGFloat(sprite.image.width), height: CGFloat(sprite.image.height))
            .insetBy(dx: -padding, dy: -padding))
    }

    /// Front-to-back, so the animal you can actually see at `point` wins over any drawn
    /// behind it. `targets` arrives back-to-front (see `targets(from:)`), hence the
    /// reverse.
    static func pid(at point: CGPoint, in targets: [HitTarget]) -> Int? {
        targets.reversed().first { $0.rect.contains(point) }?.pid
    }

    /// Pen geometry is fixed for a given layout, so unlike `targets(from:)` this needs
    /// nothing from the frame currently on screen — pens do not move between frames the
    /// way animals do.
    static func penTargets(from pens: [PlacedPen]) -> [PenTarget] {
        pens.enumerated().map { index, pen in
            let body = CGRect(x: CGFloat(pen.x) * tile, y: CGFloat(pen.y) * tile,
                              width: CGFloat(pen.w) * tile, height: CGFloat(pen.h) * tile)
            return PenTarget(index: index,
                             rect: body.insetBy(dx: -padding, dy: -padding),
                             innerRect: body.insetBy(dx: tile + padding, dy: tile + padding))
        }
    }

    /// The fence, which is `FarmPenFurniture.fenceTiles`' one-tile perimeter ring with a
    /// couple of pixels of slop on both of its edges. Clicking it opens the project;
    /// the interior stays the animals'.
    ///
    /// The gated rail has a 2-tile opening with no fence tiles in it, and this hits
    /// across that gap anyway — people aim at the outline of a pen, and a dead spot in
    /// the middle of one rail of every pen would read as a bug.
    ///
    /// A pen too small to have an interior yields a null `innerRect`, which contains no
    /// point, so the whole pen stays clickable rather than collapsing to nothing.
    static func penFenceIndex(at point: CGPoint, in targets: [PenTarget]) -> Int? {
        targets.first { $0.rect.contains(point) && !$0.innerRect.contains(point) }?.index
    }

    /// The whole building is the target, not the doorway. The doors are two tiles wide,
    /// and a 32px target inside a 112px building would be a pixel-hunt for the largest,
    /// least missable object in the scene. Nothing else is clickable underneath: scenery
    /// keeps a one-tile buffer around the barn, so it cannot overlap a pen.
    static func barnTarget(from layout: FarmLayout) -> BarnTarget? {
        guard let x = layout.barnX, let y = layout.barnY else { return nil }
        let body = CGRect(x: CGFloat(x) * tile, y: CGFloat(y) * tile,
                          width: CGFloat(FarmLayoutEngine.barnW) * tile,
                          height: CGFloat(FarmLayoutEngine.barnH) * tile)
        return BarnTarget(rect: body.insetBy(dx: -padding, dy: -padding))
    }

    /// Tile size in 1× pixels. Pen coordinates are tiles; hit testing is in pixels.
    private static let tile: CGFloat = 16

    /// Enforces `minimumSize`, growing about the rect's own centre so the enlarged box
    /// still sits on what it stands for rather than drifting off one corner of it.
    private static func grown(_ rectIn: CGRect) -> CGRect {
        var rect = rectIn
        if rect.width < minimumSize {
            rect = rect.insetBy(dx: -(minimumSize - rect.width) / 2, dy: 0)
        }
        if rect.height < minimumSize {
            rect = rect.insetBy(dx: 0, dy: -(minimumSize - rect.height) / 2)
        }
        return rect
    }
}
