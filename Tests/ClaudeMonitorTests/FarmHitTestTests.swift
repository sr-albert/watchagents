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
    /// A pen laid out at tile (4,3), 8x6 tiles — so its rectangle in 1x pixels is
    /// (64, 48, 128, 96) and its fence ring is the outermost 16px band of that.
    private let pen = placedPen("alpha", x: 4, y: 3)

    func test_penFenceIndex_hitsTheRailsOfTheRing() {
        let targets = FarmHitTest.penTargets(from: [pen])

        // Top rail, then left rail.
        XCTAssertEqual(FarmHitTest.penFenceIndex(at: CGPoint(x: 128, y: 52), in: targets), 0)
        XCTAssertEqual(FarmHitTest.penFenceIndex(at: CGPoint(x: 68, y: 90), in: targets), 0)
    }

    /// The interior is the animals' surface — their own hit test owns those points, and
    /// clicking a cow must not open the project instead of the cow.
    func test_penFenceIndex_missesThePenInterior() {
        let targets = FarmHitTest.penTargets(from: [pen])

        XCTAssertNil(FarmHitTest.penFenceIndex(at: CGPoint(x: 128, y: 96), in: targets))
    }

    func test_penFenceIndex_missesOpenGround() {
        let targets = FarmHitTest.penTargets(from: [pen])

        XCTAssertNil(FarmHitTest.penFenceIndex(at: CGPoint(x: 600, y: 600), in: targets))
    }

    /// The gated rail has a 2-tile opening with no fence tiles in it, but the ring stays
    /// clickable across the gap: people aim at the outline of the pen, and carving a dead
    /// spot into the middle of one rail of every pen would just feel broken.
    func test_penFenceIndex_hitsTheGateOpening() {
        let targets = FarmHitTest.penTargets(from: [pen])
        XCTAssertEqual(pen.gate, .south)

        // Bottom rail, in the 2-tile gap at gateX-1/gateX.
        XCTAssertEqual(FarmHitTest.penFenceIndex(at: CGPoint(x: CGFloat(pen.gateX) * 16, y: 136),
                                                 in: targets), 0)
    }

    /// A pen only two tiles across has no interior left once the ring is taken out; the
    /// whole thing has to stay clickable rather than collapsing to nothing.
    func test_penFenceIndex_treatsAVeryThinPenAsAllFence() {
        let thin = placedPen("thin", x: 4, y: 3, w: 2, h: 2)
        let targets = FarmHitTest.penTargets(from: [thin])

        XCTAssertEqual(FarmHitTest.penFenceIndex(at: CGPoint(x: 4 * 16 + 8, y: 3 * 16 + 8),
                                                 in: targets), 0)
    }

    func test_penFenceIndex_distinguishesAdjacentPens() {
        let other = placedPen("beta", x: 20, y: 3)
        let targets = FarmHitTest.penTargets(from: [pen, other])

        XCTAssertEqual(FarmHitTest.penFenceIndex(at: CGPoint(x: 128, y: 52), in: targets), 0)
        XCTAssertEqual(FarmHitTest.penFenceIndex(at: CGPoint(x: 24 * 16, y: 52), in: targets), 1)
    }
}
