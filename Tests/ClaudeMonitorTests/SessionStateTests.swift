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

    private func history(idle: Date?, dormant: Date? = nil) -> SessionStateEvaluator.History {
        SessionStateEvaluator.History(idleSince: idle, overloadSince: nil, dormantSince: dormant)
    }

    func test_dormantWhenTerminalIdleLongerThanDormantDuration() {
        let start = Date()
        let now = start.addingTimeInterval(Thresholds.frozenDuration + 1)
        let state = SessionStateEvaluator.evaluate(
            cpu: 0, mem: 1, ttyIdle: Thresholds.dormantDuration + 1,
            history: history(idle: start), now: now, basis: .both)
        XCTAssertEqual(state, .dormant)
    }

    /// The half of the definition that makes the feature safe. A session Claude is
    /// grinding through while you are at lunch has an idle terminal and a busy CPU, and
    /// filing it into the barn would hide the most interesting thing on the farm.
    func test_aWorkingSessionIsNeverDormantHoweverLongTheTerminalHasBeenIdle() {
        let state = SessionStateEvaluator.evaluate(
            cpu: 50, mem: 1, ttyIdle: 86400,
            history: history(idle: nil), now: Date(), basis: .both)
        XCTAssertEqual(state, .active)
    }

    /// Overload is driven through MEM, not CPU: a CPU-driven overload (cpu >= 80) also
    /// makes `isIdle` false, so the session could never reach the idle/frozen/dormant
    /// branch at all — the test would pass with the precedence check deleted. Idle CPU
    /// plus high mem satisfies every precondition for dormant AND overloaded at once, so
    /// `.overloaded` winning is a real result of the precedence rule, not a side effect
    /// of the session never being a dormant candidate in the first place.
    func test_overloadedOutranksDormant() {
        let start = Date()
        let now = start.addingTimeInterval(Thresholds.frozenDuration + 1)
        var h = history(idle: start)
        h.overloadSince = start
        let state = SessionStateEvaluator.evaluate(
            cpu: 0, mem: 30, ttyIdle: 86400, history: h, now: now, basis: .both)
        XCTAssertEqual(state, .overloaded)
    }

    func test_frozenButNotYetDormantBelowTheTerminalThreshold() {
        let start = Date()
        let now = start.addingTimeInterval(Thresholds.frozenDuration + 1)
        let state = SessionStateEvaluator.evaluate(
            cpu: 0, mem: 1, ttyIdle: Thresholds.dormantDuration - 1,
            history: history(idle: start), now: now, basis: .both)
        XCTAssertEqual(state, .frozen)
    }

    /// A process with no controlling terminal has no idle time to measure. It must fall
    /// through to frozen rather than being treated as infinitely idle.
    func test_aSessionWithNoTerminalIsNeverDormant() {
        let start = Date()
        let now = start.addingTimeInterval(Thresholds.frozenDuration + 1)
        let state = SessionStateEvaluator.evaluate(
            cpu: 0, mem: 1, ttyIdle: nil,
            history: history(idle: start), now: now, basis: .both)
        XCTAssertEqual(state, .frozen)
    }

    @MainActor
    func test_trackerRecordsWhenASessionFirstFellAsleepAndForgetsOnWake() {
        let tracker = SessionStateTracker()
        let t0 = Date()
        var asleep = ClaudeProcess(pid: 7, cpu: 0, mem: 1)
        asleep.ttyIdle = Thresholds.dormantDuration + 1
        let snap = ProcessSnapshot(processes: [asleep], cpuTotal: 0, memTotal: 1, sessionCount: 1)

        _ = tracker.states(for: snap, now: t0, basis: .both)
        let later = t0.addingTimeInterval(Thresholds.frozenDuration + 1)
        _ = tracker.states(for: snap, now: later, basis: .both)
        let since = tracker.history(for: 7)?.dormantSince
        XCTAssertNotNil(since)

        // Stamped once, on the first dormant evaluation — not advanced on every poll.
        _ = tracker.states(for: snap, now: later.addingTimeInterval(60), basis: .both)
        XCTAssertEqual(tracker.history(for: 7)?.dormantSince, since)

        // You type; w's idle resets; the animal is awake and the stamp is gone.
        var awake = asleep
        awake.ttyIdle = 0
        let awakeSnap = ProcessSnapshot(processes: [awake], cpuTotal: 0, memTotal: 1, sessionCount: 1)
        _ = tracker.states(for: awakeSnap, now: later.addingTimeInterval(120), basis: .both)
        XCTAssertNil(tracker.history(for: 7)?.dormantSince)
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

    func test_overloadedViaMemWhileCPUIsIdle() {
        let tracker = SessionStateTracker()
        let t0 = Date()

        let memHeavy = ProcessSnapshot(
            processes: [ClaudeProcess(pid: 9, cpu: 0, mem: 30)],
            cpuTotal: 0, memTotal: 30, sessionCount: 1
        )
        _ = tracker.states(for: memHeavy, now: t0, basis: .both)
        let states = tracker.states(for: memHeavy, now: t0.addingTimeInterval(Thresholds.overloadConfirmWindow + 1), basis: .both)
        XCTAssertEqual(states[9], .overloaded)
    }

    func test_frozenResetsToActiveOnNewCPUActivity_thenIdleNotFrozen() {
        let tracker = SessionStateTracker()
        let t0 = Date()

        let idle = ProcessSnapshot(
            processes: [ClaudeProcess(pid: 11, cpu: 0, mem: 1)],
            cpuTotal: 0, memTotal: 1, sessionCount: 1
        )
        _ = tracker.states(for: idle, now: t0, basis: .both)
        let frozenStates = tracker.states(for: idle, now: t0.addingTimeInterval(Thresholds.frozenDuration + 1), basis: .both)
        XCTAssertEqual(frozenStates[11], .frozen)

        // CPU activity resumes — the idle streak must clear, not just happen to be nil-on-first-tick.
        let busy = ProcessSnapshot(
            processes: [ClaudeProcess(pid: 11, cpu: 50, mem: 1)],
            cpuTotal: 50, memTotal: 1, sessionCount: 1
        )
        let activeStates = tracker.states(for: busy, now: t0.addingTimeInterval(Thresholds.frozenDuration + 2), basis: .both)
        XCTAssertEqual(activeStates[11], .active)

        // A subsequent idle tick must restart the idle-duration clock from zero, not treat
        // the process as still "long idle" from before the CPU activity interrupted it.
        let idleAgain = ProcessSnapshot(
            processes: [ClaudeProcess(pid: 11, cpu: 0, mem: 1)],
            cpuTotal: 0, memTotal: 1, sessionCount: 1
        )
        let idleAgainStates = tracker.states(for: idleAgain, now: t0.addingTimeInterval(Thresholds.frozenDuration + 3), basis: .both)
        XCTAssertEqual(idleAgainStates[11], .idle)
    }
}

/// The farm anchors an animal that stops walking at the spot it stopped, and the instant
/// it stopped is `idleSince` — already tracked here for the frozen escalation, now also
/// read by `FarmAnimalPlacer`.
@MainActor
final class SessionStateTrackerIdleSinceTests: XCTestCase {
    private func snapshot(cpu: Double) -> ProcessSnapshot {
        ProcessSnapshot(processes: [ClaudeProcess(pid: 1, cpu: cpu, mem: 5)],
                        cpuTotal: cpu, memTotal: 5, sessionCount: 1)
    }

    func test_idleSinceIsUnsetWhileBusy() {
        let tracker = SessionStateTracker()
        _ = tracker.states(for: snapshot(cpu: 50), now: Date(), basis: .both)
        XCTAssertNil(tracker.history(for: 1)?.idleSince)
    }

    func test_idleSinceIsTheMomentTheSessionStoppedWorking() {
        let tracker = SessionStateTracker()
        let t0 = Date()
        _ = tracker.states(for: snapshot(cpu: 50), now: t0, basis: .both)
        let stopped = t0.addingTimeInterval(2)
        _ = tracker.states(for: snapshot(cpu: 0), now: stopped, basis: .both)

        XCTAssertEqual(tracker.history(for: 1)?.idleSince, stopped)
    }

    /// It marks the moment work *stopped*, not the latest poll — otherwise the anchor
    /// would creep forward every two seconds and the animal would drift across the pen
    /// while standing still.
    func test_idleSinceDoesNotAdvanceWhileTheSessionStaysIdle() {
        let tracker = SessionStateTracker()
        let t0 = Date()
        _ = tracker.states(for: snapshot(cpu: 50), now: t0, basis: .both)
        let stopped = t0.addingTimeInterval(2)
        _ = tracker.states(for: snapshot(cpu: 0), now: stopped, basis: .both)
        _ = tracker.states(for: snapshot(cpu: 0), now: stopped.addingTimeInterval(30), basis: .both)

        XCTAssertEqual(tracker.history(for: 1)?.idleSince, stopped)
    }

    func test_idleSinceClearsWhenTheSessionPicksUpAgain() {
        let tracker = SessionStateTracker()
        let t0 = Date()
        _ = tracker.states(for: snapshot(cpu: 0), now: t0, basis: .both)
        _ = tracker.states(for: snapshot(cpu: 90), now: t0.addingTimeInterval(2), basis: .both)

        XCTAssertNil(tracker.history(for: 1)?.idleSince)
    }
}
