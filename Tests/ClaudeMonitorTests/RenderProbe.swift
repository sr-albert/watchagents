import XCTest
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
@testable import ClaudeMonitor

final class RenderProbe: XCTestCase {
    /// Left: tile 0094 drawn on its own. Right: the same tile as it comes out of
    /// `renderStaticLayer`, cropped from the barn's shoulder. If those differ, the
    /// renderer is flipping tiles.
    func test_hiveInIsolationVersusInScene() throws {
        var procs: [ClaudeProcess] = []
        for i in 0..<7 {
            procs.append(ClaudeProcess(pid: 100 + i, cpu: 0, mem: 0, cwd: "/Users/a/code/proj\(i % 4)"))
        }
        let pens = FarmGrouping.pens(from: procs)
        let layout = FarmLayoutEngine.layout(pens: pens, cols: 46, rows: 28)
        let scene = buildScene(pens: pens, layout: layout)
        let full = try XCTUnwrap(scene.staticImage)

        let bx = try XCTUnwrap(layout.barnX)
        let by = try XCTUnwrap(layout.barnY)
        let hiveX: Int = bx + FarmLayoutEngine.barnW + 1
        let hiveY: Int = by + FarmLayoutEngine.barnH - 1
        print("HIVE tile at \(hiveX),\(hiveY)  image \(full.width)x\(full.height)")
        let inScene = try XCTUnwrap(full.cropping(
            to: CGRect(x: hiveX * 16, y: hiveY * 16, width: 16, height: 16)))

        let s = 16
        let w: Int = 16 * s * 2 + 24
        let h: Int = 16 * s + 16
        let ctx = try XCTUnwrap(CGContext(data: nil, width: w, height: h, bitsPerComponent: 8,
                                          bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        ctx.setFillColor(CGColor(red: 0.43, green: 0.75, blue: 0.35, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        ctx.interpolationQuality = .none
        ctx.draw(try XCTUnwrap(FarmAssets.tile(94)),
                 in: CGRect(x: 8, y: 8, width: 16 * s, height: 16 * s))
        ctx.draw(inScene, in: CGRect(x: 16 + 16 * s, y: 8, width: 16 * s, height: 16 * s))

        let out = try XCTUnwrap(ctx.makeImage())
        let url = URL(fileURLWithPath: ProcessInfo.processInfo.environment["OUT"] ?? "/tmp/h.png")
        let dest = try XCTUnwrap(CGImageDestinationCreateWithURL(
            url as CFURL, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(dest, out, nil)
        XCTAssertTrue(CGImageDestinationFinalize(dest))
        print("WROTE \(url.path)")
    }
}
