import XCTest
@testable import ClaudeMonitor

final class SkeletonTests: XCTestCase {
    func test_dropdownView_instantiates_andBodyEvaluatesWithoutCrashing() {
        let view = DropdownView()
        _ = view.body
    }
}
