import Foundation

enum OverloadBasis: String, CaseIterable {
    case cpu, mem, both
}

enum SessionState: Equatable {
    case idle, active, overloaded, frozen
}

enum Thresholds {
    static let idleCpu: Double = 3.0
    static let overloadCpu: Double = 80.0
    static let overloadMem: Double = 25.0
    static let overloadConfirmWindow: TimeInterval = 10
    static let frozenDuration: TimeInterval = 600
}

enum SessionStateEvaluator {
    struct History {
        var idleSince: Date?
        var overloadSince: Date?
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
        history: History,
        now: Date,
        basis: OverloadBasis
    ) -> SessionState {
        if isOverloaded(cpu: cpu, mem: mem, basis: basis),
           let since = history.overloadSince,
           now.timeIntervalSince(since) >= Thresholds.overloadConfirmWindow {
            return .overloaded
        }

        if isIdle(cpu: cpu),
           let since = history.idleSince,
           now.timeIntervalSince(since) >= Thresholds.frozenDuration {
            return .frozen
        }

        return isIdle(cpu: cpu) ? .idle : .active
    }
}

@MainActor
final class SessionStateTracker {
    private var history: [Int: SessionStateEvaluator.History] = [:]

    func states(for snapshot: ProcessSnapshot, now: Date, basis: OverloadBasis) -> [Int: SessionState] {
        let currentPIDs = Set(snapshot.processes.map { $0.pid })
        history = history.filter { currentPIDs.contains($0.key) }

        var result: [Int: SessionState] = [:]
        for process in snapshot.processes {
            var entry = history[process.pid] ?? SessionStateEvaluator.History(idleSince: nil, overloadSince: nil)

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

            history[process.pid] = entry
            result[process.pid] = SessionStateEvaluator.evaluate(
                cpu: process.cpu, mem: process.mem, history: entry, now: now, basis: basis
            )
        }
        return result
    }
}
