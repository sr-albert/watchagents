import XCTest
@testable import ClaudeMonitor

final class SkeletonTests: XCTestCase {
    @MainActor
    func test_dropdownView_instantiates_andBodyEvaluatesWithoutCrashing() {
        let view = DropdownView(viewModel: MonitorViewModel())
        _ = view.body
    }
}
