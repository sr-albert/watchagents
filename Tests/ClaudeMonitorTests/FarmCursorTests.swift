import XCTest
import AppKit
@testable import ClaudeMonitor

final class FarmCursorTests: XCTestCase {
    @MainActor
    func test_bothCursorsBuild() throws {
        XCTAssertNotNil(FarmCursor.normal)
        XCTAssertNotNil(FarmCursor.interactable)
    }

    /// The cursor is the only affordance left once the `!` chip is gone, so the two
    /// states have to be told apart by shape, not just by tint. Different silhouettes
    /// mean different bitmap sizes here.
    @MainActor
    func test_theTwoStatesHaveDifferentSilhouettes() throws {
        let normal = try XCTUnwrap(FarmCursor.normal).image.size
        let hand = try XCTUnwrap(FarmCursor.interactable).image.size

        XCTAssertNotEqual(normal, hand)
    }

    /// Hot spots are in points from the image's top-left, and must land on a drawn pixel:
    /// the arrow's tip, and the tip of the hand's pointing finger. An off-by-a-few here
    /// is invisible in a screenshot and maddening in use.
    @MainActor
    func test_hotSpotsSitOnThePointingPixel() throws {
        XCTAssertEqual(try XCTUnwrap(FarmCursor.normal).hotSpot, NSPoint(x: 0, y: 0))
        XCTAssertEqual(try XCTUnwrap(FarmCursor.interactable).hotSpot, NSPoint(x: 4, y: 0))
    }

    /// Rendered at 2x and declared at half that in points, so one art pixel is one point.
    /// Without this the bitmap is resampled and the pixel art turns to mush.
    @MainActor
    func test_bitmapIsTwiceTheDeclaredPointSize() throws {
        let image = try XCTUnwrap(FarmCursor.interactable).image
        let rep = try XCTUnwrap(image.representations.first)

        XCTAssertEqual(Double(rep.pixelsWide), image.size.width * 2, accuracy: 0.001)
        XCTAssertEqual(Double(rep.pixelsHigh), image.size.height * 2, accuracy: 0.001)
    }
}
