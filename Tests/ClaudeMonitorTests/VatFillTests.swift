import XCTest
@testable import ClaudeMonitor

final class VatFillTests: XCTestCase {
    private let surface = (r: 118, g: 228, b: 255)
    private let body = (r: 0, g: 154, b: 220)

    func test_anEmptyVatPaintsNothing() {
        XCTAssertTrue(FarmVat.fillRows(level: 0).isEmpty)
    }

    func test_liquidFillsFromTheBottomUp() {
        let one = FarmVat.fillRows(level: 1)
        XCTAssertEqual(one.map(\.y), [8])

        let two = FarmVat.fillRows(level: 2)
        XCTAssertEqual(two.map(\.y), [7, 8])

        let three = FarmVat.fillRows(level: 3)
        XCTAssertEqual(three.map(\.y), [6, 7, 8])
    }

    /// The highlight is the liquid's surface, so it belongs on the topmost filled row and
    /// nowhere else — at every level, not just when full.
    func test_theHighlightSitsOnTheSurfaceAtEveryLevel() {
        for level in 1...3 {
            let rows = FarmVat.fillRows(level: level)
            let top = rows.min { $0.y < $1.y }!
            XCTAssertEqual(top.colour.r, surface.r, "level \(level)")
            XCTAssertEqual(top.colour.g, surface.g, "level \(level)")
            XCTAssertEqual(top.colour.b, surface.b, "level \(level)")
            for row in rows where row.y != top.y {
                XCTAssertEqual(row.colour.r, body.r)
                XCTAssertEqual(row.colour.g, body.g)
                XCTAssertEqual(row.colour.b, body.b)
            }
        }
    }

    /// The invariant the whole compositing approach rests on: a full composite must reproduce
    /// the shipped filled tile exactly. If this fails, the geometry or the colours are wrong —
    /// and a tile that composites wrong is invisible in code and obvious in a PNG (see 0074).
    func test_aFullCompositeEqualsTheShippedFilledTile() throws {
        let empty = try XCTUnwrap(FarmAssets.tile(130), "tile 0130 missing")
        let filled = try XCTUnwrap(FarmAssets.tile(131), "tile 0131 missing")

        let composed = FarmVat.compose(over: empty, level: 3)
        XCTAssertEqual(FarmVat.rgbaBytes(of: composed), FarmVat.rgbaBytes(of: filled),
                       "level 3 over 0130 must be byte-identical to 0131")
    }

    func test_levelZeroCompositeEqualsTheEmptyTile() throws {
        let empty = try XCTUnwrap(FarmAssets.tile(130))
        XCTAssertEqual(FarmVat.rgbaBytes(of: FarmVat.compose(over: empty, level: 0)),
                       FarmVat.rgbaBytes(of: empty))
    }
}
