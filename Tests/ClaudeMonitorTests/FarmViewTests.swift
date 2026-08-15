import XCTest
import SwiftUI
@testable import ClaudeMonitor

final class FarmViewSkeletonTests: XCTestCase {
    @MainActor
    func test_farmView_instantiates_andBodyEvaluatesWithoutCrashing() {
        let view = FarmView(viewModel: MonitorViewModel())
        _ = view.body
    }
}
