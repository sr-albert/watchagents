import Foundation

struct FarmPen: Equatable {
    let cwd: String
    let label: String
    let species: AnimalSpecies
    let processes: [ClaudeProcess]
}

enum FarmGrouping {
    /// Pens and their animals are ordered deterministically (by cwd, then by pid)
    /// rather than by the order processes arrive in. `ps aux` returns matching
    /// processes in a different order on nearly every poll, so preserving arrival
    /// order made the whole grid reshuffle every refresh — pens visibly jumping
    /// between positions twice a second.
    static func pens(from processes: [ClaudeProcess]) -> [FarmPen] {
        var groups: [String: [ClaudeProcess]] = [:]
        for process in processes {
            groups[process.cwd, default: []].append(process)
        }

        return groups.keys.sorted().map { cwd in
            FarmPen(
                cwd: cwd,
                label: URL(fileURLWithPath: cwd).lastPathComponent,
                species: AnimalAssignment.species(forCWD: cwd),
                processes: (groups[cwd] ?? []).sorted { $0.pid < $1.pid }
            )
        }
    }
}
