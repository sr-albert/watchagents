import CoreGraphics
import CoreText
import Foundation

/// Renders label text to a crisp 1× bitmap once, then the renderer blits it like any
/// other sprite. Drawing text directly into `Canvas` antialiases it — on the brown sign
/// plate at this size that turned "NFQ" into "NEO" and "DOTFILES" into "DOTEILES".
enum PixelText {
    /// Silkscreen's design size. Rendering at a non-integer multiple reintroduces the
    /// blurring this type exists to avoid.
    static let pointSize: CGFloat = 8
    static let glyphHeight = 11

    private static let lock = NSLock()
    nonisolated(unsafe) private static var cache: [String: CGImage] = [:]

    nonisolated(unsafe) private static let font: CTFont? = {
        guard let url = FarmAssets.fontURL else { return nil }
        CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        guard let data = CGDataProvider(url: url as CFURL),
              let cg = CGFont(data) else { return nil }
        return CTFontCreateWithGraphicsFont(cg, pointSize, nil, nil)
    }()

    static func measure(_ s: String) -> Int {
        guard let font else { return s.count * 8 }
        let attr = NSAttributedString(string: s, attributes: [.font: font])
        let line = CTLineCreateWithAttributedString(attr)
        return Int(CTLineGetTypographicBounds(line, nil, nil, nil).rounded(.up))
    }

    static func image(_ s: String) -> CGImage? {
        lock.lock()
        defer { lock.unlock() }
        if let hit = cache[s] { return hit }
        guard let font else { return nil }

        let w = max(1, measure(s)), h = glyphHeight
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8,
                                  bytesPerRow: w * 4,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }

        // Every antialiasing path off: this is why the output is crisp.
        ctx.setAllowsAntialiasing(false)
        ctx.setShouldAntialias(false)
        ctx.setAllowsFontSmoothing(false)
        ctx.setShouldSmoothFonts(false)
        ctx.setAllowsFontSubpixelPositioning(false)
        ctx.setShouldSubpixelPositionFonts(false)
        ctx.setAllowsFontSubpixelQuantization(false)

        let attr = NSAttributedString(string: s, attributes: [
            .font: font,
            .foregroundColor: CGColor(red: 1, green: 1, blue: 1, alpha: 1)
        ])
        let line = CTLineCreateWithAttributedString(attr)
        ctx.textPosition = CGPoint(x: 0, y: 3)
        CTLineDraw(line, ctx)

        guard let img = ctx.makeImage() else { return nil }
        cache[s] = img
        return img
    }

    static func truncate(_ s: String, maxPx: Int) -> String {
        if measure(s) <= maxPx { return s }
        var out = s
        while !out.isEmpty && measure(out + "…") > maxPx {
            out.removeLast()
        }
        return out + "…"
    }
}
