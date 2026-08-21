import XCTest
@testable import ClaudeMonitor

@MainActor
final class FarmSettingsTests: XCTestCase {
    private let suiteName = "FarmSettingsTests"

    func test_defaultsToBothWhenNothingStored() {
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)

        let settings = FarmSettings(defaults: defaults)

        XCTAssertEqual(settings.basis, .both)
    }

    func test_persistsAcrossInstances() {
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)

        let settings = FarmSettings(defaults: defaults)
        settings.basis = .cpu

        let reloaded = FarmSettings(defaults: defaults)
        XCTAssertEqual(reloaded.basis, .cpu)
    }

    private func freshDefaults(_ name: String) -> UserDefaults {
        let d = UserDefaults(suiteName: name)!
        d.removePersistentDomain(forName: name)
        return d
    }

    func test_ceilingsSeedFromTheHeaviestRecordedBlock() {
        let d = freshDefaults("seed-basic")
        let s = FarmSettings(defaults: d)
        XCTAssertFalse(s.ceilingsSeeded)

        s.seedCeilingsIfNeeded(observedMaxTokens: 900, observedMaxCost: 9.0)

        XCTAssertTrue(s.ceilingsSeeded)
        XCTAssertEqual(s.tokenCeiling, 900)
        XCTAssertEqual(s.dollarCeiling, 9.0, accuracy: 0.0001)
    }

    /// The reason the flag exists. A heavier block arriving later must NOT raise the ceiling,
    /// or the bales refill and the denominator is moving again.
    func test_aLaterHeavierBlockDoesNotRaiseTheCeiling() {
        let d = freshDefaults("seed-once")
        let s = FarmSettings(defaults: d)
        s.seedCeilingsIfNeeded(observedMaxTokens: 900, observedMaxCost: 9.0)
        s.seedCeilingsIfNeeded(observedMaxTokens: 5000, observedMaxCost: 50.0)

        XCTAssertEqual(s.tokenCeiling, 900)
        XCTAssertEqual(s.dollarCeiling, 9.0, accuracy: 0.0001)
    }

    func test_aUserEditSurvivesAHeavierBlock() {
        let d = freshDefaults("seed-edit")
        let s = FarmSettings(defaults: d)
        s.seedCeilingsIfNeeded(observedMaxTokens: 900, observedMaxCost: 9.0)
        s.tokenCeiling = 2000
        s.seedCeilingsIfNeeded(observedMaxTokens: 5000, observedMaxCost: 50.0)

        XCTAssertEqual(s.tokenCeiling, 2000)
    }

    func test_ceilingsPersistAcrossInstances() {
        let d = freshDefaults("seed-persist")
        let a = FarmSettings(defaults: d)
        a.seedCeilingsIfNeeded(observedMaxTokens: 900, observedMaxCost: 9.0)
        a.tokenCeiling = 1234

        let b = FarmSettings(defaults: d)
        XCTAssertTrue(b.ceilingsSeeded)
        XCTAssertEqual(b.tokenCeiling, 1234)
        XCTAssertEqual(b.dollarCeiling, 9.0, accuracy: 0.0001)
    }

    /// Nothing recorded yet means nothing to seed from. Seeding must not fire on zeros, or
    /// the ceiling locks at zero forever and every gauge divides by nothing.
    func test_seedingDoesNotFireOnAnEmptyHistory() {
        let d = freshDefaults("seed-empty")
        let s = FarmSettings(defaults: d)
        s.seedCeilingsIfNeeded(observedMaxTokens: 0, observedMaxCost: 0)

        XCTAssertFalse(s.ceilingsSeeded)
        XCTAssertEqual(s.tokenCeiling, 0)
    }

    /// The failure mode `configureCeilings` exists to close: on a fresh install `ccusage`
    /// may never report before the user reaches the barn and sets a budget by hand. That
    /// edit lands while `ceilingsSeeded` is still false, and a later, first successful
    /// seed must not be allowed to treat it as unconfigured and overwrite it.
    func test_anExplicitEditBeforeAnySeedSurvivesTheFirstSeed() {
        let d = freshDefaults("seed-edit-before-seed")
        let s = FarmSettings(defaults: d)
        XCTAssertFalse(s.ceilingsSeeded)

        s.configureCeilings(tokens: 500_000, dollars: 20.0)
        XCTAssertTrue(s.ceilingsSeeded)

        s.seedCeilingsIfNeeded(observedMaxTokens: 5000, observedMaxCost: 50.0)

        XCTAssertEqual(s.tokenCeiling, 500_000)
        XCTAssertEqual(s.dollarCeiling, 20.0, accuracy: 0.0001)
    }

    /// The partial state a `didSet`-per-property fix would have let through: an edit to
    /// one field marking the ceilings seeded while the other field is still zero, which
    /// would wedge `FeedGaugeReader`'s `dollarCeiling > 0` guard shut for good. This is
    /// the exact call `FarmHouseModal`'s token field makes — the untouched dollar field
    /// re-clamped from its own current (still-zero) value, not written raw.
    func test_editingOneFieldCannotLeaveTheOtherAtZero() {
        let d = freshDefaults("seed-partial-state")
        let s = FarmSettings(defaults: d)
        XCTAssertEqual(s.dollarCeiling, 0)

        s.configureCeilings(tokens: FarmHouseModal.clampedTokenCeiling(500_000),
                            dollars: FarmHouseModal.clampedDollarCeiling(s.dollarCeiling))

        XCTAssertTrue(s.ceilingsSeeded)
        XCTAssertGreaterThan(s.dollarCeiling, 0)
        XCTAssertGreaterThan(s.tokenCeiling, 0)
    }
}
