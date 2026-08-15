import XCTest
import CoreGraphics
@testable import ClaudeMonitor

final class PixelTextTests: XCTestCase {
    func test_rendersAnImageForASimpleLabel() {
        let img = PixelText.image("WATCHAGENTS")
        XCTAssertNotNil(img)
        XCTAssertGreaterThan(img?.width ?? 0, 0)
        XCTAssertGreaterThan(img?.height ?? 0, 0)
    }

    func test_widthGrowsWithLength() {
        XCTAssertGreaterThan(PixelText.measure("DOTFILES"), PixelText.measure("NFQ"))
    }

    func test_measureMatchesRenderedWidth() {
        let s = "SADBITS"
        XCTAssertEqual(PixelText.measure(s), PixelText.image(s)?.width)
    }

    func test_renderIsCrisp_noAntialiasedGreys() throws {
        // The whole point of this task. A crisp 1-bit render has only fully
        // transparent and fully opaque pixels; antialiasing introduces partial alpha,
        // which is what turned NFQ into "NEO" on the wooden plate.
        let img = try XCTUnwrap(PixelText.image("NFQ"))
        let w = img.width, h = img.height
        var buf = [UInt8](repeating: 0, count: w * h * 4)
        let ctx = CGContext(data: &buf, width: w, height: h, bitsPerComponent: 8,
                            bytesPerRow: w * 4,
                            space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.draw(img, in: CGRect(x: 0, y: 0, width: w, height: h))
        var partial = 0
        for i in stride(from: 3, to: buf.count, by: 4) where buf[i] > 8 && buf[i] < 247 {
            partial += 1
        }
        XCTAssertEqual(partial, 0, "\(partial) antialiased pixels — text will look mushy")
    }

    func test_truncateAppendsEllipsisAndFits() {
        let long = "FEAT+BODY-TYPE-QUESTIONNAIRE"
        let maxPx = 9 * 16
        let out = PixelText.truncate(long, maxPx: maxPx)
        XCTAssertLessThanOrEqual(PixelText.measure(out), maxPx)
        XCTAssertTrue(out.hasSuffix("…"), "truncated labels get an ellipsis")
    }

    func test_truncateLeavesShortLabelsAlone() {
        XCTAssertEqual(PixelText.truncate("NFQ", maxPx: 200), "NFQ")
    }

    func test_descendersAreNotClipped() throws {
        // plateH=12 clipped the Q descender and rendered NFQ as NEO. The glyph box
        // must be tall enough that a Q differs from an O.
        let q = try XCTUnwrap(PixelText.image("Q"))
        let o = try XCTUnwrap(PixelText.image("O"))
        XCTAssertEqual(q.height, o.height)
        func opaqueCount(_ img: CGImage) -> Int {
            let w = img.width, h = img.height
            var buf = [UInt8](repeating: 0, count: w * h * 4)
            let ctx = CGContext(data: &buf, width: w, height: h, bitsPerComponent: 8,
                                bytesPerRow: w * 4, space: CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            ctx.draw(img, in: CGRect(x: 0, y: 0, width: w, height: h))
            return stride(from: 3, to: buf.count, by: 4).reduce(0) { buf[$1] > 127 ? $0 + 1 : $0 }
        }
        XCTAssertNotEqual(opaqueCount(q), opaqueCount(o),
                          "Q renders identically to O — the descender is being clipped")
    }
}
