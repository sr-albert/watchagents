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
