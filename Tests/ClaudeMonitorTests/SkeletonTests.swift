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
        XCTAssertEqual(SessionStateBadge.label(for: .dormant), "Sleeping")
    }
}
