import AppKit

/// The farm's own pointer: a pixel-art arrow, and a pointing hand for anything you can
/// click. Drawn from the masks below rather than shipped as art, so this adds no asset
/// and no third-party licence to `THIRD-PARTY-NOTICES.md`.
///
/// With the `!` chip gone, the cursor *is* the affordance — the only thing that tells
/// you a fence or an animal will respond. That is the whole reason it exists, so the two
/// states have to differ in silhouette and not merely in colour.
@MainActor
enum FarmCursor {
    /// `#` outline, `o` fill, anything else transparent. Rows may be ragged; they are
    /// padded to the widest one.
    private static let arrowArt = [
        "#",
        "##",
        "#o#",
        "#oo#",
        "#ooo#",
        "#oooo#",
        "#ooooo#",
        "#oooooo#",
        "#ooooooo#",
        "#oooooooo#",
        "#ooooo#####",
        "#oo#oo#",
        "#o# #oo#",
        "##   #oo#",
        "      #oo#",
        "       ###",
    ]

    private static let handArt = [
        "   ##",
        "  #oo#",
        "  #oo#",
        "  #oo#",
        "  #oo#",
        "  #oo#####",
        "  #oo#oo#o#",
        "  #oo#oo#oo#",
        "###oo#oo#oo#",
        "#ooooooooooo#",
        "#ooooooooooo#",
        " #oooooooooo#",
        " #ooooooooo#",
        "  #oooooooo#",
        "  #oooooooo#",
        "   ########",
    ]

    /// Matches `FarmPalette.ink` and `FarmPalette.woodHi`; kept as raw components here
    /// because this file builds a bitmap rather than a SwiftUI view.
    private static let ink: (Double, Double, Double) = (48 / 255, 26 / 255, 22 / 255)
    private static let bone: (Double, Double, Double) = (240 / 255, 236 / 255, 220 / 255)
    private static let gold: (Double, Double, Double) = (232 / 255, 174 / 255, 118 / 255)

    static let normal = cursor(arrowArt, fill: bone, hotSpot: NSPoint(x: 0, y: 0))
    static let interactable = cursor(handArt, fill: gold, hotSpot: NSPoint(x: 4, y: 0))

    /// Called on every hover event rather than only on transitions: AppKit resets the
    /// pointer from the window's own cursor rects as it moves, so a cursor set once does
    /// not stay set.
    static func set(interactable isInteractable: Bool) {
        (isInteractable ? interactable : normal)?.set()
    }

    static func reset() {
        NSCursor.arrow.set()
    }

    /// Rendered at 2× and then declared to be half that size in points, so one art pixel
    /// is exactly one point — nearest-neighbour crisp on a Retina display instead of the
    /// blur a 1× bitmap would get scaled up to.
    private static func cursor(_ art: [String], fill: (Double, Double, Double),
                               hotSpot: NSPoint) -> NSCursor? {
        let w = art.map(\.count).max() ?? 0, h = art.count
        guard w > 0, h > 0 else { return nil }
        let s = 2
        guard let ctx = CGContext(data: nil, width: w * s, height: h * s, bitsPerComponent: 8,
                                  bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }

        for (row, line) in art.enumerated() {
            for (col, ch) in line.enumerated() {
                let rgb: (Double, Double, Double)
                switch ch {
                case "#": rgb = ink
                case "o": rgb = fill
                default: continue
                }
                ctx.setFillColor(CGColor(red: rgb.0, green: rgb.1, blue: rgb.2, alpha: 1))
                // The art reads top-down; a `CGContext`'s origin is bottom-left.
                ctx.fill(CGRect(x: col * s, y: (h - row - 1) * s, width: s, height: s))
            }
        }

        guard let cg = ctx.makeImage() else { return nil }
        let image = NSImage(cgImage: cg, size: NSSize(width: w, height: h))
        return NSCursor(image: image, hotSpot: hotSpot)
    }
}
