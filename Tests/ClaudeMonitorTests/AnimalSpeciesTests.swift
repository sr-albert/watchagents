import XCTest
@testable import ClaudeMonitor

final class AnimalAssignmentTests: XCTestCase {
    func test_species_isStableAcrossRepeatedCalls() {
        let cwd = "/Users/albert/Projects/watchagents"
        let first = AnimalAssignment.species(forCWD: cwd)
        let second = AnimalAssignment.species(forCWD: cwd)
        XCTAssertEqual(first, second)
    }

    func test_species_isAlwaysAValidPaletteMember() {
        let samples = [
            "/Users/albert/Projects/watchagents",
            "/Users/albert/Projects/vestio-admin",
            "/Users/albert/Projects/sadbits",
            "(unknown)",
            "",
        ]
        for cwd in samples {
            XCTAssertTrue(AnimalSpecies.allCases.contains(AnimalAssignment.species(forCWD: cwd)))
        }
    }

    func test_stableHash_ofEmptyString_isTheFNVOffsetBasis() {
        // FNV-1a's loop never executes for an empty string, so the result is
        // definitionally the offset basis constant — this pins the algorithm choice
        // without needing to hand-compute a multi-byte hash.
        XCTAssertEqual(AnimalAssignment.stableHash(""), 0xcbf29ce484222325)
    }

    func test_knownCWDsMapToStableSpecies() {
        // Pins real computed output against the palette in Global Constraints order.
        // A future palette reorder that changes any of these must be a conscious
        // decision, not an accidental reshuffle — that's what this test guards.
        XCTAssertEqual(AnimalAssignment.species(forCWD: "/Users/albert/Projects/watchagents"), .cow)
        XCTAssertEqual(AnimalAssignment.species(forCWD: "/Users/albert/Projects/vestio-admin"), .chicken)
        XCTAssertEqual(AnimalAssignment.species(forCWD: "/Users/albert/Projects/sadbits"), .pig)
    }
}
