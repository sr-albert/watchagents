import CoreGraphics
import Foundation
import ImageIO

enum AnimalAction: String {
    case walk, eat
}

/// Loads the bundled pixel art. Images are cached because the renderer asks for the
/// same handful of tiles on every frame.
enum FarmAssets {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var cache: [String: CGImage] = [:]

    private static func load(_ subdirectory: String, _ name: String) -> CGImage? {
        let key = "\(subdirectory)/\(name)"
        lock.lock()
        defer { lock.unlock() }
        if let hit = cache[key] { return hit }
        guard let url = Bundle.module.url(
                forResource: name,
                withExtension: "png",
                subdirectory: "Resources/\(subdirectory)"
              ),
              let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else { return nil }
        cache[key] = image
        return image
    }

    static func tile(_ id: Int) -> CGImage? {
        load("tiles", String(format: "tile_%04d", id))
    }

    static func animalSheet(_ species: AnimalSpecies, _ action: AnimalAction) -> CGImage? {
        load("animals", "\(species.assetName)_\(action.rawValue)")
    }

    static let fontURL: URL? = Bundle.module.url(
        forResource: "Silkscreen-Regular",
        withExtension: "ttf",
        subdirectory: "Resources/fonts"
    )
}

// `AnimalSpecies` still has seven cases at this point but only four have sprite sheets.
// This extension is deliberately total, so the gap shows up as a `nil` sheet (which
// `test_loadsEveryAnimalSheet` catches) rather than as a compile error. Task 2 removes
// the three artless cases and moves this property onto the enum itself.
extension AnimalSpecies {
    var assetName: String {
        switch self {
        case .cow: return "cow"
        case .pig: return "pig"
        case .sheep: return "sheep"
        case .chicken: return "chicken"
        default: return "__missing__"
        }
    }
}
