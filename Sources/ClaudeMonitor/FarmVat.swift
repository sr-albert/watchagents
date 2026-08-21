import CoreGraphics
import Foundation

/// The vat's liquid, composited over tile `0130` rather than drawn as new art.
///
/// Two tiles ship: `0130` empty and `0131` full. Two states cannot express the gap between
/// the bales and the vat, which is the entire reason the vat measures dollars — so the
/// intermediate levels are painted. Compositing a solid band over an existing tile is the
/// same class of pixel operation as the §5.3 state tints; nothing is drawn that is not
/// already in the pack, so §7's "no new art" holds.
///
/// Every constant here was measured by differencing `0130` against `0131`, not chosen by eye.
enum FarmVat {
    /// The well's interior, in 16x16 tile space. Uniformly `rgb(63, 38, 49)` in `0130`.
    static let wellX = 5...10
    static let wellY = 6...8

    static let surface = (r: 118, g: 228, b: 255)
    static let body = (r: 0, g: 154, b: 220)

    /// Which rows to paint and in what colour, filling bottom-up. The surface highlight is the
    /// liquid's top face, so it moves down as the vat empties rather than staying at y = 6.
    static func fillRows(level: Int) -> [(y: Int, colour: (r: Int, g: Int, b: Int))] {
        guard level > 0 else { return [] }
        let clamped = min(level, wellY.count)
        let top = wellY.upperBound - clamped + 1
        return (top...wellY.upperBound).map { y in
            (y: y, colour: y == top ? surface : body)
        }
    }

    /// Draws `tile` into a fresh 16x16 context and paints `fillRows(level:)` over it as
    /// 6px-wide, 1px-tall rectangles. At level 3 this must reproduce tile `0131` exactly
    /// (see `VatFillTests`) — the correctness check for levels 1 and 2, which no test can
    /// see the way a full composite can.
    ///
    /// Row coordinates from `fillRows` are top-down/y-down, matching every other tile
    /// coordinate in this codebase, but `CGContext`'s device space is bottom-left/y-up.
    /// Converted per rect below rather than by flipping the context — see the note on
    /// `renderStaticLayer` in FarmView.swift for why a context flip is the wrong fix: it
    /// would leave the rows in the right order but draw the tile itself upside down.
    static func compose(over tile: CGImage, level: Int) -> CGImage {
        let size = 16
        guard let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8,
                                   bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                   bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return tile }
        ctx.draw(tile, in: CGRect(x: 0, y: 0, width: size, height: size))

        for row in fillRows(level: level) {
            let c = row.colour
            ctx.setFillColor(red: CGFloat(c.r) / 255, green: CGFloat(c.g) / 255,
                              blue: CGFloat(c.b) / 255, alpha: 1)
            ctx.fill(CGRect(x: wellX.lowerBound, y: size - (row.y + 1),
                             width: wellX.count, height: 1))
        }
        return ctx.makeImage() ?? tile
    }

    /// Raw RGBA bytes of `image`, for byte-equality comparison in tests. Premultiplied
    /// alpha, matching every other bitmap context in this codebase — both sides of the
    /// comparison go through the same conversion, so premultiplication cancels out.
    static func rgbaBytes(of image: CGImage) -> [UInt8] {
        let w = image.width, h = image.height
        var data = [UInt8](repeating: 0, count: w * h * 4)
        guard let ctx = CGContext(data: &data, width: w, height: h, bitsPerComponent: 8,
                                   bytesPerRow: w * 4, space: CGColorSpaceCreateDeviceRGB(),
                                   bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return data }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        return data
    }
}
