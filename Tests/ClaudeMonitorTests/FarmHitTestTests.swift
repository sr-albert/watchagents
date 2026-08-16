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
