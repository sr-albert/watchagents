import XCTest
@testable import ClaudeMonitor

final class SkeletonTests: XCTestCase {
    @MainActor
    func test_dropdownView_instantiates_andBodyEvaluatesWithoutCrashing() {
        let viewModel = MonitorViewModel()
        let view = DropdownView(viewModel: viewModel, overloadSettings: viewModel.overloadSettings)
        _ = view.body
    }

    func test_sessionStateBadge_mapsEachStateToADistinctEmoji() {
        XCTAssertEqual(SessionStateBadge.emoji(for: .idle), "🌾")
        XCTAssertEqual(SessionStateBadge.emoji(for: .active), "🏃")
        XCTAssertEqual(SessionStateBadge.emoji(for: .overloaded), "🔥")
        XCTAssertEqual(SessionStateBadge.emoji(for: .frozen), "🥶")
        XCTAssertEqual(SessionStateBadge.emoji(for: .dormant), "😴")
    }

    func test_sessionStateBadge_mapsEachStateToADistinctLabel() {
        XCTAssertEqual(SessionStateBadge.label(for: .idle), "Idle")
        XCTAssertEqual(SessionStateBadge.label(for: .active), "Active")
        XCTAssertEqual(SessionStateBadge.label(for: .overloaded), "Overloaded")
        XCTAssertEqual(SessionStateBadge.label(for: .frozen), "Frozen")
        XCTAssertEqual(SessionStateBadge.label(for: .dormant), "Sleeping")
    }

    @MainActor
    func test_dormantThresholdPersistsAndDefaultsToFourHours() {
        let suite = UserDefaults(suiteName: "dormant-threshold-test")!
        suite.removePersistentDomain(forName: "dormant-threshold-test")

        XCTAssertEqual(OverloadSettings(defaults: suite).dormantAfterHours, 4)

        let settings = OverloadSettings(defaults: suite)
        settings.dormantAfterHours = 8
        XCTAssertEqual(OverloadSettings(defaults: suite).dormantAfterHours, 8)

        suite.removePersistentDomain(forName: "dormant-threshold-test")
    }
}
