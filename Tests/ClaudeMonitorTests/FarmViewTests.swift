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

final class AnimalMotionModelTests: XCTestCase {
    func test_frozenIsCompletelyStill_atEveryInstant() {
        for t in stride(from: 0.0, to: 5.0, by: 0.25) {
            XCTAssertEqual(
                AnimalMotionModel.motion(for: .frozen, time: t, phase: 0),
                AnimalMotion()
            )
        }
    }

    func test_eachStateUsesAQualitativelyDifferentMotionChannel() {
        // Sample a full second so a state can't be judged by a single instant that
        // happens to sit at a zero crossing.
        func channels(_ state: SessionState) -> (x: Bool, y: Bool, scale: Bool, rot: Bool) {
            var x = false, y = false, scale = false, rot = false
            for t in stride(from: 0.0, to: 1.0, by: 0.01) {
                let m = AnimalMotionModel.motion(for: state, time: t, phase: 0)
                if abs(m.offsetX) > 0.01 { x = true }
                if abs(m.offsetY) > 0.01 { y = true }
                if abs(m.scale - 1) > 0.001 { scale = true }
                if abs(m.rotation) > 0.01 { rot = true }
            }
            return (x, y, scale, rot)
        }

        let idle = channels(.idle)
        XCTAssertTrue(idle.scale, "idle should breathe via scale")
        XCTAssertFalse(idle.x, "idle should not travel horizontally")
        XCTAssertFalse(idle.y, "idle should not travel vertically")
        XCTAssertFalse(idle.rot, "idle should not rotate")

        let active = channels(.active)
        XCTAssertTrue(active.y, "active should hop vertically")
        XCTAssertFalse(active.x, "active should not travel horizontally")
        XCTAssertFalse(active.rot, "active should not rotate")

        let overloaded = channels(.overloaded)
        XCTAssertTrue(overloaded.x, "overloaded should shake horizontally")
        XCTAssertTrue(overloaded.rot, "overloaded should wobble")
        XCTAssertFalse(overloaded.y, "overloaded should not bob vertically like active")
    }

    func test_activeHopsAboveRestingPosition_neverBelow() {
        for t in stride(from: 0.0, to: 2.0, by: 0.01) {
            let m = AnimalMotionModel.motion(for: .active, time: t, phase: 0)
            XCTAssertLessThanOrEqual(m.offsetY, 0.0001, "a hop should never sink below rest")
        }
    }

    func test_motionIsDeterministic_forTheSameInputs() {
        let first = AnimalMotionModel.motion(for: .active, time: 1.234, phase: 0.5)
        let second = AnimalMotionModel.motion(for: .active, time: 1.234, phase: 0.5)
        XCTAssertEqual(first, second)
    }

    func test_phaseIsStablePerPID_andSpreadsAnimalsApart() {
        XCTAssertEqual(AnimalMotionModel.phase(forPID: 4242), AnimalMotionModel.phase(forPID: 4242))
        XCTAssertNotEqual(AnimalMotionModel.phase(forPID: 100), AnimalMotionModel.phase(forPID: 700))
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
        let view = PenView(pen: pen, time: 0)
        _ = view.body
    }

    @MainActor
    func test_animalView_instantiates_andBodyEvaluatesWithoutCrashing() {
        let view = AnimalView(species: .cow, state: .active, pid: 1, time: 0)
        _ = view.body
    }
}
