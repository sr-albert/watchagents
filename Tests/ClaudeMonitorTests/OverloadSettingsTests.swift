import XCTest
@testable import ClaudeMonitor

@MainActor
final class OverloadSettingsTests: XCTestCase {
    private let suiteName = "OverloadSettingsTests"

    func test_defaultsToBothWhenNothingStored() {
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)

        let settings = OverloadSettings(defaults: defaults)

        XCTAssertEqual(settings.basis, .both)
    }

    func test_persistsAcrossInstances() {
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)

        let settings = OverloadSettings(defaults: defaults)
        settings.basis = .cpu

        let reloaded = OverloadSettings(defaults: defaults)
        XCTAssertEqual(reloaded.basis, .cpu)
    }
}
