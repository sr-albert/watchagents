import Foundation

/// The whole farm, counted: the numbers `FarmInfoPanel` puts on screen.
///
/// Kept out of the view so the arithmetic can be tested without evaluating SwiftUI, and
/// because the panel is the one place the farm states aggregates outright — everywhere
/// else they live in posture, colour and motion (spec §5.1).
enum FarmCensus {
    /// How many animals are in each state, right now. Four explicit fields rather than a
    /// dictionary keyed by `SessionState`: the set is closed and fixed at four, and a
    /// dictionary would make the panel unwrap an optional per row to render a zero.
    struct StateCensus: Equatable {
        var idle = 0
        var active = 0
        var overloaded = 0
        var frozen = 0
    }

    struct Totals: Equatable {
        let animals: Int
        let pens: Int
        let cpu: Double
        let mem: Double
        let states: StateCensus
    }

    /// One pen's line in the panel. `worst` is the state of the animal in it that most
    /// wants looking at — see `severity`.
    struct PenRow: Equatable {
        let cwd: String
        let label: String
        let species: AnimalSpecies
        let sessions: Int
        let cpu: Double
        let mem: Double
        let worst: SessionState
    }

    static func totals(for pens: [FarmPen]) -> Totals {
        var states = StateCensus()
        var cpu = 0.0, mem = 0.0, animals = 0

        for pen in pens {
            for process in pen.processes {
                animals += 1
                cpu += process.cpu
                mem += process.mem
                switch process.state {
                case .idle: states.idle += 1
                case .active: states.active += 1
                case .overloaded: states.overloaded += 1
                case .frozen: states.frozen += 1
                case .dormant: states.frozen += 1
                }
            }
        }

        return Totals(animals: animals, pens: pens.count, cpu: cpu, mem: mem, states: states)
    }

    /// Rows in the order the pens were given, which `FarmGrouping.pens` has already sorted
    /// by cwd. Deliberately not re-sorted by load: the panel sits beside the scene and is
    /// read against it, and a busiest-first order would reshuffle on every poll — the same
    /// jumping that made `FarmGrouping` sort deterministically in the first place.
    static func rows(for pens: [FarmPen]) -> [PenRow] {
        pens.map { pen in
            PenRow(
                cwd: pen.cwd,
                label: pen.label,
                species: pen.species,
                sessions: pen.processes.count,
                cpu: pen.processes.reduce(0) { $0 + $1.cpu },
                mem: pen.processes.reduce(0) { $0 + $1.mem },
                // An empty pen cannot come out of `FarmGrouping`, but `FarmPen` permits
                // one, so this falls back rather than forcing a first element.
                worst: pen.processes.map(\.state).max { severity($0) < severity($1) } ?? .idle
            )
        }
    }

    /// Attention, not frequency: one overloaded session among nine idle ones is the whole
    /// reason to look at a row, so it sets the row's state. Frozen outranks active because
    /// a session stuck for ten minutes is a thing to go and deal with; an active one is
    /// the farm working as intended.
    private static func severity(_ state: SessionState) -> Int {
        switch state {
        case .overloaded: return 3
        case .frozen: return 2
        case .dormant: return 2
        case .active: return 1
        case .idle: return 0
        }
    }
}
