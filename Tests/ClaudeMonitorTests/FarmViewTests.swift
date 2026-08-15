import XCTest
import SwiftUI
@testable import ClaudeMonitor

final class AnimalOverlayTests: XCTestCase {
    func test_badge_mapsEachStateCorrectly() {
        XCTAssertNil(AnimalOverlay.badge(for: .idle))
        XCTAssertEqual(AnimalOverlay.badge(for: .active), "🏃")
        XCTAssertEqual(AnimalOverlay.badge(for: .overloaded), "🔥")
        XCTAssertEqual(AnimalOverlay.badge(for: .frozen), "💤")
    }

    func test_tint_mapsEachStateToADistinctColor() {
        XCTAssertEqual(AnimalOverlay.tint(for: .idle), .clear)
        XCTAssertEqual(AnimalOverlay.tint(for: .active), .green.opacity(0.2))
        XCTAssertEqual(AnimalOverlay.tint(for: .overloaded), .red.opacity(0.15))
        XCTAssertEqual(AnimalOverlay.tint(for: .frozen), .blue.opacity(0.12))
    }
}

final class FarmViewSkeletonTests: XCTestCase {
    @MainActor
    func test_farmView_instantiates_andBodyEvaluatesWithoutCrashing() {
        let view = FarmView(viewModel: MonitorViewModel())
        _ = view.body
    }

    @MainActor
    func test_penView_instantiates_andBodyEvaluatesWithoutCrashing() {
        let pen = FarmPen(
            cwd: "/tmp",
            label: "tmp",
            species: .cow,
            processes: [ClaudeProcess(pid: 1, cpu: 0, mem: 0)]
        )
        let view = PenView(pen: pen)
        _ = view.body
    }

    @MainActor
    func test_animalView_instantiates_andBodyEvaluatesWithoutCrashing() {
        let view = AnimalView(species: .cow, state: .active)
        _ = view.body
    }
}
