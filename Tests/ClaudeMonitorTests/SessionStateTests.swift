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
