import Foundation

struct FarmPen: Equatable {
    let cwd: String
    let label: String
    let species: AnimalSpecies
    let processes: [ClaudeProcess]
}

enum FarmGrouping {
    static func pens(from processes: [ClaudeProcess]) -> [FarmPen] {
        var order: [String] = []
        var groups: [String: [ClaudeProcess]] = [:]

        for process in processes {
            if groups[process.cwd] == nil {
                order.append(process.cwd)
            }
            groups[process.cwd, default: []].append(process)
        }

        return order.map { cwd in
            FarmPen(
                cwd: cwd,
                label: URL(fileURLWithPath: cwd).lastPathComponent,
                species: AnimalAssignment.species(forCWD: cwd),
                processes: groups[cwd] ?? []
            )
        }
    }
}
