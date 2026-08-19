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
}
