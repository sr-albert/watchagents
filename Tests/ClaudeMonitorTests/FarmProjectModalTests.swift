import XCTest
import SwiftUI
@testable import ClaudeMonitor

final class FarmProjectModalTests: XCTestCase {
    private func pen(_ processes: [ClaudeProcess]) -> FarmPen {
        FarmPen(cwd: "/Users/someone/code/watchagents", label: "watchagents",
                species: .cow, processes: processes)
    }

    @MainActor
    func test_modal_bodyEvaluatesForAPopulatedProject() {
        let procs = (0..<3).map {
            ClaudeProcess(pid: 900 + $0, cpu: Double($0), mem: Double($0) / 2,
                          cwd: "/Users/someone/code/watchagents")
        }
        _ = FarmProjectModal(pen: pen(procs), onClose: {}).body
    }

    /// A project can lose every session between the click and the next poll — the modal
    /// has to survive the frame before `FarmView` notices and dismisses it.
    @MainActor
    func test_modal_bodyEvaluatesForAProjectWithNoSessions() {
        _ = FarmProjectModal(pen: pen([]), onClose: {}).body
    }
}
