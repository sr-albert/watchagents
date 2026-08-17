import Foundation

enum OverloadBasis: String, CaseIterable {
    case cpu, mem, both
}

enum SessionState: Equatable {
    case idle, active, overloaded, frozen, dormant
}

enum Thresholds {
    static let idleCpu: Double = 3.0
    static let overloadCpu: Double = 80.0
    static let overloadMem: Double = 25.0
    static let overloadConfirmWindow: TimeInterval = 10
    static let frozenDuration: TimeInterval = 600
    /// Terminal idle before `frozen` escalates to `dormant`. Four hours: long enough that
    /// lunch or a long meeting does not put a live session to bed, short enough that
    /// yesterday's leftovers are asleep by the time you sit down.
    ///
    /// `FarmHouseModal`'s picker separately hardcodes the hour values it offers
    /// (`[1, 2, 4, 8, 24]`) instead of deriving them from this constant, so changing this
    /// default to a value outside that set renders the picker blank for every user by
    /// default until they touch it.
    static let dormantDuration: TimeInterval = 14400
}

enum SessionStateEvaluator {
    struct History {
        var idleSince: Date?
        var overloadSince: Date?
        /// When this session first evaluated as dormant. Recorded rather than derived:
        /// `w` reports idle time at minute resolution, so `now - (ttyIdle - threshold)`
        /// would advance in lockstep with `now` for a whole minute at a time and the gate
        /// walk would never leave its first frame.
        var dormantSince: Date?
    }

    static func isIdle(cpu: Double) -> Bool {
        cpu < Thresholds.idleCpu
    }

    static func isOverloaded(cpu: Double, mem: Double, basis: OverloadBasis) -> Bool {
        switch basis {
        case .cpu:  return cpu >= Thresholds.overloadCpu
        case .mem:  return mem >= Thresholds.overloadMem
        case .both: return cpu >= Thresholds.overloadCpu || mem >= Thresholds.overloadMem
        }
    }

    static func evaluate(
        cpu: Double,
        mem: Double,
        ttyIdle: TimeInterval? = nil,
        history: History,
        now: Date,
        basis: OverloadBasis,
        dormantAfter: TimeInterval = Thresholds.dormantDuration
    ) -> SessionState {
        if isOverloaded(cpu: cpu, mem: mem, basis: basis),
           let since = history.overloadSince,
           now.timeIntervalSince(since) >= Thresholds.overloadConfirmWindow {
            return .overloaded
        }

        if isIdle(cpu: cpu),
           let since = history.idleSince,
           now.timeIntervalSince(since) >= Thresholds.frozenDuration {
            // Dormant is a strict escalation of frozen, and requires both halves. Terminal
            // idle alone would bed down a session running a long autonomous task, and hide
            // an overloaded runaway — the two things most worth seeing.
            if let ttyIdle, ttyIdle >= dormantAfter { return .dormant }
            return .frozen
        }

        return isIdle(cpu: cpu) ? .idle : .active
    }
}

@MainActor
final class SessionStateTracker {
    private var history: [Int: SessionStateEvaluator.History] = [:]

    /// Read-only view of what the tracker remembers about a pid. `idleSince` is the farm's
    /// resting anchor (`FarmAnimalPlacer.place`) as well as the frozen escalation's clock.
    func history(for pid: Int) -> SessionStateEvaluator.History? { history[pid] }

    func states(
        for snapshot: ProcessSnapshot,
        now: Date,
        basis: OverloadBasis,
        dormantAfter: TimeInterval = Thresholds.dormantDuration
    ) -> [Int: SessionState] {
        let currentPIDs = Set(snapshot.processes.map { $0.pid })
        history = history.filter { currentPIDs.contains($0.key) }

        var result: [Int: SessionState] = [:]
        for process in snapshot.processes {
            var entry = history[process.pid] ?? SessionStateEvaluator.History(
                idleSince: nil, overloadSince: nil, dormantSince: nil)

            if SessionStateEvaluator.isIdle(cpu: process.cpu) {
                if entry.idleSince == nil { entry.idleSince = now }
            } else {
                entry.idleSince = nil
            }

            if SessionStateEvaluator.isOverloaded(cpu: process.cpu, mem: process.mem, basis: basis) {
                if entry.overloadSince == nil { entry.overloadSince = now }
            } else {
                entry.overloadSince = nil
            }

            let state = SessionStateEvaluator.evaluate(
                cpu: process.cpu, mem: process.mem, ttyIdle: process.ttyIdle,
                history: entry, now: now, basis: basis, dormantAfter: dormantAfter
            )

            // Stamped once, on the first poll that evaluates dormant, and cleared the
            // moment it does not. There is no wake path to write: you type, `w`'s idle
            // resets, and the next poll evaluates frozen or idle.
            if state == .dormant {
                if entry.dormantSince == nil { entry.dormantSince = now }
            } else {
                entry.dormantSince = nil
            }

            history[process.pid] = entry
            result[process.pid] = state
        }
        return result
    }
}
