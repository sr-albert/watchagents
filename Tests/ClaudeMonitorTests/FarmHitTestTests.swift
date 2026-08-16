import XCTest
import CoreGraphics
@testable import ClaudeMonitor

/// A blank image of a given size — `Sprite`'s hit box comes from its image dimensions,
/// so these tests only need something with the right `width`/`height`.
private func stubImage(_ w: Int, _ h: Int) -> CGImage {
    let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpaceCreateDeviceRGB(),
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    return ctx.makeImage()!
}

private func sprite(pid: Int?, x: Int, y: Int, w: Int, h: Int, by: Int) -> Sprite {
    Sprite(by: by, x: x, y: y, image: stubImage(w, h),
           shadowCenterX: x + w / 2, shadowWidth: w, badge: nil, pid: pid)
}

final class FarmHitTestTests: XCTestCase {
    func test_pid_returnsTheSpriteContainingThePoint() {
        let targets = FarmHitTest.targets(from: [
            sprite(pid: 11, x: 0, y: 0, w: 40, h: 30, by: 30),
            sprite(pid: 22, x: 100, y: 60, w: 40, h: 30, by: 90),
        ])

        XCTAssertEqual(FarmHitTest.pid(at: CGPoint(x: 20, y: 15), in: targets), 11)
        XCTAssertEqual(FarmHitTest.pid(at: CGPoint(x: 120, y: 75), in: targets), 22)
    }

    /// `collectSprites` returns its list sorted ascending by baseline `y` — back to
    /// front — and the renderer draws it in that order, so the *last* overlapping sprite
    /// is the one actually visible at the point. Clicking must select what you can see,
    /// not the animal hidden behind it.
    func test_pid_returnsTheFrontmostSpriteWhenTwoOverlap() {
        let targets = FarmHitTest.targets(from: [
            sprite(pid: 11, x: 0, y: 0, w: 40, h: 40, by: 40),
            sprite(pid: 22, x: 20, y: 20, w: 40, h: 40, by: 60),
        ])

        XCTAssertEqual(FarmHitTest.pid(at: CGPoint(x: 30, y: 30), in: targets), 22)
    }

    func test_pid_returnsNilOnEmptyGround() {
        let targets = FarmHitTest.targets(from: [
            sprite(pid: 11, x: 0, y: 0, w: 40, h: 30, by: 30),
        ])

        XCTAssertNil(FarmHitTest.pid(at: CGPoint(x: 300, y: 300), in: targets))
    }

    /// The tile-0103 barn-door fixture rides in the same depth-sorted draw list as the
    /// animals but has no session behind it, so it must never be selectable.
    func test_targets_skipsSpritesWithoutAPID() {
        let targets = FarmHitTest.targets(from: [
            sprite(pid: nil, x: 0, y: 0, w: 16, h: 16, by: 16),
            sprite(pid: 11, x: 100, y: 0, w: 40, h: 30, by: 30),
        ])

        XCTAssertEqual(targets.map(\.pid), [11])
        XCTAssertNil(FarmHitTest.pid(at: CGPoint(x: 8, y: 8), in: targets))
    }

    /// A chicken trims to ~31×26px, but a frame of its walk cycle can be far narrower.
    /// At scale 1 a sprite is drawn at its own pixel size, so without a floor the
    /// smallest animals become nearly unclickable.
    func test_targets_growsSmallSpritesToAMinimumTouchBox() {
        let targets = FarmHitTest.targets(from: [
            sprite(pid: 11, x: 50, y: 50, w: 6, h: 6, by: 56),
        ])

        XCTAssertEqual(targets.count, 1)
        XCTAssertGreaterThanOrEqual(targets[0].rect.width, 16)
        XCTAssertGreaterThanOrEqual(targets[0].rect.height, 16)
        // Grown about its own centre, so the box still sits on the sprite.
        XCTAssertEqual(targets[0].rect.midX, 53, accuracy: 0.001)
        XCTAssertEqual(targets[0].rect.midY, 53, accuracy: 0.001)
    }
}

private func placedPen(_ label: String, x: Int, y: Int, w: Int = 8, h: Int = 6) -> PlacedPen {
    let cwd = "/Users/someone/code/\(label)"
    let pen = FarmPen(cwd: cwd, label: label, species: .cow,
                      processes: [ClaudeProcess(pid: 1, cpu: 0, mem: 0, cwd: cwd)])
    return PlacedPen(pen: pen, x: x, y: y, w: w, h: h, gate: .south, gateX: x + w / 2)
}

final class FarmPenHitTestTests: XCTestCase {
    func test_penIndex_returnsThePenUnderThePoint() {
        let targets = FarmHitTest.penTargets(from: [
            placedPen("alpha", x: 4, y: 3),
            placedPen("beta", x: 20, y: 3),
        ])

        // Pen coordinates are tiles; hit testing happens in 1× pixels, 16 to the tile.
        XCTAssertEqual(FarmHitTest.penIndex(at: CGPoint(x: 6 * 16, y: 5 * 16), in: targets), 0)
        XCTAssertEqual(FarmHitTest.penIndex(at: CGPoint(x: 22 * 16, y: 5 * 16), in: targets), 1)
    }

    func test_penIndex_returnsNilOnOpenGround() {
        let targets = FarmHitTest.penTargets(from: [placedPen("alpha", x: 4, y: 3)])

        XCTAssertNil(FarmHitTest.penIndex(at: CGPoint(x: 40 * 16, y: 30 * 16), in: targets))
    }

    /// The name plate is nailed to the top rail and its upper edge clears the pen's own
    /// rectangle. The hover region has to take in that overhang, or the `!` badge would
    /// flicker off whenever the pointer strayed onto the top of the plate it sits on.
    func test_penIndex_includesTheSignPlateOverhangingThePenTop() {
        let pen = placedPen("alpha", x: 4, y: 3)
        let targets = FarmHitTest.penTargets(from: [pen])
        let sign = FarmPenFurniture.signRect(for: pen)
        let penTop = CGFloat(pen.y * 16)

        XCTAssertLessThan(sign.minY, penTop, "fixture assumes the plate overhangs the pen top")
        XCTAssertEqual(FarmHitTest.penIndex(at: CGPoint(x: sign.midX, y: sign.minY), in: targets), 0)
        // ...and the padded box reaches above the plate itself, so the very top pixel
        // row of the sign is not a miss.
        XCTAssertLessThan(targets[0].rect.minY, sign.minY)
    }

    /// Opening the project modal is a click on the plate specifically — the rest of the
    /// pen belongs to the animals, whose own hit test already owns those points.
    func test_penSignIndex_hitsOnlyThePlate() {
        let pen = placedPen("alpha", x: 4, y: 3)
        let targets = FarmHitTest.penTargets(from: [pen])
        let sign = FarmPenFurniture.signRect(for: pen)

        XCTAssertEqual(FarmHitTest.penSignIndex(at: CGPoint(x: sign.midX, y: sign.midY), in: targets), 0)
        // Middle of the pen body: inside the pen, but not on its plate.
        XCTAssertNil(FarmHitTest.penSignIndex(at: CGPoint(x: 6 * 16, y: 5 * 16), in: targets))
    }

    /// A plate overhangs the top of its own pen, so with a tall pen above it the plate
    /// can land inside that upper pen's rectangle. Resolving by pen order alone points at
    /// the upper pen while the pointer is squarely on the lower pen's own name plate,
    /// which lights the chip on the wrong sign.
    func test_penIndex_prefersThePlateOwnerWhereAPlateOverlapsThePenAbove() {
        let upper = placedPen("upper", x: 4, y: 3, h: 8)
        let lower = placedPen("lower", x: 4, y: 11)
        let targets = FarmHitTest.penTargets(from: [upper, lower])
        let plate = FarmPenFurniture.signRect(for: lower)

        XCTAssertLessThan(plate.minY, CGFloat((upper.y + upper.h) * 16),
                          "fixture assumes the lower plate reaches into the upper pen")
        XCTAssertEqual(FarmHitTest.penIndex(at: CGPoint(x: plate.midX, y: plate.minY + 0.5),
                                            in: targets), 1)
    }

    /// The `!` chip sits just off the right end of the plate, not on it, so the click
    /// target has to reach past the plate's own edge — otherwise the one pixel everybody
    /// aims at is the one pixel that misses.
    func test_penSignIndex_hitsTheInfoBadgeBesideThePlate() {
        let pen = placedPen("alpha", x: 4, y: 3)
        let targets = FarmHitTest.penTargets(from: [pen])
        let badge = FarmPenFurniture.infoBadgeRect(for: pen)

        XCTAssertGreaterThan(badge.minX, FarmPenFurniture.signRect(for: pen).maxX - 4,
                             "fixture assumes the chip hangs off the right end of the plate")
        XCTAssertEqual(FarmHitTest.penSignIndex(at: CGPoint(x: badge.midX, y: badge.midY), in: targets), 0)
    }

    /// The plate is 15px tall and can be narrow for a short project name, so it gets the
    /// same minimum touch box as the smallest animals rather than its own new numbers.
    func test_penSignTarget_isAtLeastTheMinimumTouchBox() {
        let targets = FarmHitTest.penTargets(from: [placedPen("a", x: 4, y: 3)])

        XCTAssertGreaterThanOrEqual(targets[0].signRect.width, FarmHitTest.minimumSize)
        XCTAssertGreaterThanOrEqual(targets[0].signRect.height, FarmHitTest.minimumSize)
    }
}
