import XCTest
@testable import ClaudeMonitor

final class FarmAssetsTests: XCTestCase {
    func test_loadsAGrassTile() {
        let img = FarmAssets.tile(0)
        XCTAssertNotNil(img, "tile 0000 (grass) must load from the bundle")
        XCTAssertEqual(img?.width, 16)
        XCTAssertEqual(img?.height, 16)
    }

    func test_loadsEveryTileIDTheSpecReferences() {
        // Every tile ID named in docs/farm-design-spec.md.
        let ids = [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16,
                   17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29,
                   36, 37, 38, 39, 40, 41, 42, 44, 46, 47, 52, 53, 54, 55,
                   57, 64, 65, 66, 68, 70, 72, 73, 74, 75, 80, 81, 82, 83,
                   84, 93, 94, 95, 103, 105, 106, 107, 116, 130]
        for id in ids {
            XCTAssertNotNil(FarmAssets.tile(id), "tile \(id) missing from bundle")
        }
    }

    func test_loadsEveryAnimalSheet() {
        for species in AnimalSpecies.allCases {
            for action in [AnimalAction.walk, .eat] {
                XCTAssertNotNil(
                    FarmAssets.animalSheet(species, action),
                    "\(species) \(action) sheet missing"
                )
            }
        }
    }

    func test_bundlesTheFont() {
        XCTAssertNotNil(FarmAssets.fontURL, "Silkscreen font must be bundled")
    }
}
