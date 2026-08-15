import XCTest
@testable import ClaudeMonitor

final class SessionStateEvaluatorTests: XCTestCase {
    func test_activeWhenCPUAboveIdleThreshold() {
        let now = Date()
        let history = SessionStateEvaluator.History(idleSince: nil, overloadSince: nil)
        let state = SessionStateEvaluator.evaluate(cpu: 10, mem: 5, history: history, now: now, basis: .both)
        XCTAssertEqual(state, .active)
    }

    func test_idleWhenCPUBelowIdleThreshold() {
        let now = Date()
        let history = SessionStateEvaluator.History(idleSince: now, overloadSince: nil)
        let state = SessionStateEvaluator.evaluate(cpu: 1, mem: 5, history: history, now: now, basis: .both)
        XCTAssertEqual(state, .idle)
    }

    func test_frozenWhenIdleLongerThanFrozenDuration() {
        let start = Date()
        let now = start.addingTimeInterval(Thresholds.frozenDuration + 1)
        let history = SessionStateEvaluator.History(idleSince: start, overloadSince: nil)
        let state = SessionStateEvaluator.evaluate(cpu: 1, mem: 5, history: history, now: now, basis: .both)
        XCTAssertEqual(state, .frozen)
    }

    func test_notYetFrozenWhenIdleShorterThanFrozenDuration() {
        let start = Date()
        let now = start.addingTimeInterval(Thresholds.frozenDuration - 1)
        let history = SessionStateEvaluator.History(idleSince: start, overloadSince: nil)
        let state = SessionStateEvaluator.evaluate(cpu: 1, mem: 5, history: history, now: now, basis: .both)
        XCTAssertEqual(state, .idle)
    }

    func test_overloadedWhenSustainedPastConfirmWindow() {
        let start = Date()
        let now = start.addingTimeInterval(Thresholds.overloadConfirmWindow + 1)
        let history = SessionStateEvaluator.History(idleSince: nil, overloadSince: start)
        let state = SessionStateEvaluator.evaluate(cpu: 95, mem: 5, history: history, now: now, basis: .cpu)
        XCTAssertEqual(state, .overloaded)
    }

    func test_notYetOverloadedDuringConfirmWindow_doesNotFlicker() {
        let start = Date()
        let now = start.addingTimeInterval(1)
        let history = SessionStateEvaluator.History(idleSince: nil, overloadSince: start)
        let state = SessionStateEvaluator.evaluate(cpu: 95, mem: 5, history: history, now: now, basis: .cpu)
        XCTAssertEqual(state, .active)
    }

    func test_overloadTakesPriorityOverFrozen() {
        let start = Date()
        let now = start.addingTimeInterval(Thresholds.frozenDuration + Thresholds.overloadConfirmWindow + 1)
        let history = SessionStateEvaluator.History(idleSince: start, overloadSince: start)
        let state = SessionStateEvaluator.evaluate(cpu: 95, mem: 5, history: history, now: now, basis: .cpu)
        XCTAssertEqual(state, .overloaded)
    }

    func test_overloadBasisCPUIgnoresMem() {
        XCTAssertFalse(SessionStateEvaluator.isOverloaded(cpu: 5, mem: 99, basis: .cpu))
        XCTAssertTrue(SessionStateEvaluator.isOverloaded(cpu: 95, mem: 5, basis: .cpu))
    }

    func test_overloadBasisMemIgnoresCPU() {
        XCTAssertFalse(SessionStateEvaluator.isOverloaded(cpu: 99, mem: 5, basis: .mem))
        XCTAssertTrue(SessionStateEvaluator.isOverloaded(cpu: 5, mem: 30, basis: .mem))
    }

    func test_overloadBasisBothTriggersOnEither() {
        XCTAssertTrue(SessionStateEvaluator.isOverloaded(cpu: 95, mem: 5, basis: .both))
        XCTAssertTrue(SessionStateEvaluator.isOverloaded(cpu: 5, mem: 30, basis: .both))
        XCTAssertFalse(SessionStateEvaluator.isOverloaded(cpu: 5, mem: 5, basis: .both))
    }
}

@MainActor
final class SessionStateTrackerTests: XCTestCase {
    func test_transitionsToActiveThenIdleAcrossPolls() {
        let tracker = SessionStateTracker()
        let t0 = Date()

        let busy = ProcessSnapshot(
            processes: [ClaudeProcess(pid: 1, cpu: 50, mem: 5)],
            cpuTotal: 50, memTotal: 5, sessionCount: 1
        )
        let states1 = tracker.states(for: busy, now: t0, basis: .both)
        XCTAssertEqual(states1[1], .active)

        let idle = ProcessSnapshot(
            processes: [ClaudeProcess(pid: 1, cpu: 0, mem: 5)],
            cpuTotal: 0, memTotal: 5, sessionCount: 1
        )
        let states2 = tracker.states(for: idle, now: t0.addingTimeInterval(2), basis: .both)
        XCTAssertEqual(states2[1], .idle)
    }

    func test_escalatesToFrozenAfterSustainedIdle() {
        let tracker = SessionStateTracker()
        let t0 = Date()

        let idle = ProcessSnapshot(
            processes: [ClaudeProcess(pid: 3, cpu: 0, mem: 1)],
            cpuTotal: 0, memTotal: 1, sessionCount: 1
        )
        _ = tracker.states(for: idle, now: t0, basis: .both)
        let later = tracker.states(for: idle, now: t0.addingTimeInterval(Thresholds.frozenDuration + 1), basis: .both)
        XCTAssertEqual(later[3], .frozen)
    }

    func test_prunesHistoryForVanishedPID_soReusedPIDStartsFresh() {
        let tracker = SessionStateTracker()
        let t0 = Date()

        let overloaded = ProcessSnapshot(
            processes: [ClaudeProcess(pid: 7, cpu: 95, mem: 5)],
            cpuTotal: 95, memTotal: 5, sessionCount: 1
        )
        _ = tracker.states(for: overloaded, now: t0, basis: .cpu)
        _ = tracker.states(for: overloaded, now: t0.addingTimeInterval(Thresholds.overloadConfirmWindow + 1), basis: .cpu)

        // PID 7 disappears for a tick (session ended)...
        let empty = ProcessSnapshot(processes: [], cpuTotal: 0, memTotal: 0, sessionCount: 0)
        _ = tracker.states(for: empty, now: t0.addingTimeInterval(Thresholds.overloadConfirmWindow + 2), basis: .cpu)

        // ...then the OS reuses PID 7 for an unrelated new process. It must not inherit
        // the old overload streak — the confirm window has to restart from scratch.
        let reused = ProcessSnapshot(
            processes: [ClaudeProcess(pid: 7, cpu: 95, mem: 5)],
            cpuTotal: 95, memTotal: 5, sessionCount: 1
        )
        let states = tracker.states(for: reused, now: t0.addingTimeInterval(Thresholds.overloadConfirmWindow + 3), basis: .cpu)
        XCTAssertEqual(states[7], .active)
    }
}
