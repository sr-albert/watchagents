import XCTest
@testable import ClaudeMonitor

final class FarmCensusTests: XCTestCase {
    private func process(_ pid: Int, cpu: Double = 0, mem: Double = 0,
                         cwd: String, state: SessionState = .idle) -> ClaudeProcess {
        ClaudeProcess(pid: pid, cpu: cpu, mem: mem, cwd: cwd, state: state)
    }

    private func pens(_ processes: [ClaudeProcess]) -> [FarmPen] {
        FarmGrouping.pens(from: processes)
    }

    func test_totalsCountAnimalsAndPens() {
        let all = pens([
            process(1, cwd: "/a"), process(2, cwd: "/a"), process(3, cwd: "/a"),
            process(4, cwd: "/b"),
        ])
        let totals = FarmCensus.totals(for: all)

        XCTAssertEqual(totals.animals, 4)
        XCTAssertEqual(totals.pens, 2)
    }

    func test_totalsSumCpuAndMemAcrossEveryPen() {
        let all = pens([
            process(1, cpu: 10.5, mem: 1.5, cwd: "/a"),
            process(2, cpu: 4.5, mem: 0.5, cwd: "/a"),
            process(3, cpu: 5.0, mem: 2.0, cwd: "/b"),
        ])
        let totals = FarmCensus.totals(for: all)

        XCTAssertEqual(totals.cpu, 20.0, accuracy: 0.0001)
        XCTAssertEqual(totals.mem, 4.0, accuracy: 0.0001)
    }

    func test_theCensusCountsEveryStateSeparately() {
        let all = pens([
            process(1, cwd: "/a", state: .idle),
            process(2, cwd: "/a", state: .idle),
            process(3, cwd: "/b", state: .active),
            process(4, cwd: "/c", state: .overloaded),
            process(5, cwd: "/d", state: .frozen),
        ])
        let states = FarmCensus.totals(for: all).states

        XCTAssertEqual(states.idle, 2)
        XCTAssertEqual(states.active, 1)
        XCTAssertEqual(states.overloaded, 1)
        XCTAssertEqual(states.frozen, 1)
    }

    /// The panel reads top-to-bottom in the same order the pens are laid out in the
    /// scene, so a row can be matched to a pen by eye. `FarmGrouping` sorts by cwd for
    /// exactly that reason; re-sorting here (by CPU, say) would make rows swap places on
    /// every poll.
    func test_rowsKeepTheSceneOrderOfThePens() {
        let all = pens([
            process(1, cwd: "/zebra"), process(2, cwd: "/apple"), process(3, cwd: "/mango"),
        ])
        XCTAssertEqual(FarmCensus.rows(for: all).map(\.cwd), ["/apple", "/mango", "/zebra"])
    }

    func test_eachRowSumsOnlyItsOwnPen() {
        let all = pens([
            process(1, cpu: 3.0, mem: 1.0, cwd: "/a"),
            process(2, cpu: 4.0, mem: 2.0, cwd: "/a"),
            process(3, cpu: 99.0, mem: 9.0, cwd: "/b"),
        ])
        let row = FarmCensus.rows(for: all)[0]

        XCTAssertEqual(row.label, "a")
        XCTAssertEqual(row.sessions, 2)
        XCTAssertEqual(row.cpu, 7.0, accuracy: 0.0001)
        XCTAssertEqual(row.mem, 3.0, accuracy: 0.0001)
    }

    /// Shared by every test in this file that needs "the state that wins" without wiring
    /// up a full pen: builds one pen out of the given states and reads back its `worst`.
    private func worst(_ states: [SessionState]) -> SessionState {
        let procs = states.enumerated().map { process($0.offset, cwd: "/a", state: $0.element) }
        return FarmCensus.rows(for: pens(procs))[0].worst
    }

    /// A pen shows the state of the animal that most wants looking at, not the state of
    /// the majority — one overloaded session among nine idle ones is the whole reason to
    /// glance at the row.
    func test_aRowReportsTheStateMostNeedingAttention() {
        XCTAssertEqual(worst([.idle, .idle]), .idle)
        XCTAssertEqual(worst([.idle, .active]), .active)
        XCTAssertEqual(worst([.active, .frozen]), .frozen)
        XCTAssertEqual(worst([.frozen, .overloaded]), .overloaded)
        XCTAssertEqual(worst([.overloaded, .idle, .active, .frozen]), .overloaded)
    }

    /// A pen with no animals cannot happen from `FarmGrouping`, but `FarmPen` allows it
    /// and the panel must not divide by zero or crash reaching for a first element.
    func test_anEmptyPenReportsIdleAndZeroes() {
        let empty = FarmPen(cwd: "/a", label: "a", species: .cow, processes: [])
        let row = FarmCensus.rows(for: [empty])[0]

        XCTAssertEqual(row.sessions, 0)
        XCTAssertEqual(row.cpu, 0)
        XCTAssertEqual(row.worst, .idle)
    }

    func test_anEmptyFarmCountsNothing() {
        let totals = FarmCensus.totals(for: [])

        XCTAssertEqual(totals.animals, 0)
        XCTAssertEqual(totals.pens, 0)
        XCTAssertEqual(totals.cpu, 0)
        XCTAssertEqual(totals.states, FarmCensus.StateCensus())
        XCTAssertEqual(FarmCensus.rows(for: []), [])
    }

    func test_dormantSessionsAreTalliedSeparatelyFromFrozen() {
        let states = FarmCensus.totals(for: pens([
            process(1, cwd: "/a", state: .frozen),
            process(2, cwd: "/b", state: .dormant),
            process(3, cwd: "/c", state: .dormant),
        ])).states

        XCTAssertEqual(states.frozen, 1)
        XCTAssertEqual(states.dormant, 2)
    }

    /// Dormant is the least salient state there is: it takes an animal out of the scene
    /// rather than adding a cue to it. A pen sign should say "asleep" only when there is
    /// nothing else in the pen to say.
    func test_dormantIsTheLeastSalientState() {
        XCTAssertEqual(worst([.dormant, .idle]), .idle)
        XCTAssertEqual(worst([.dormant, .active]), .active)
        XCTAssertEqual(worst([.dormant, .frozen]), .frozen)
        XCTAssertEqual(worst([.dormant, .overloaded]), .overloaded)
        XCTAssertEqual(worst([.dormant]), .dormant)
    }

    func test_sleepersListsEveryDormantSessionAndNothingElse() {
        let rows = FarmCensus.sleepers(for: pens([
            process(3, cwd: "/home/zed", state: .dormant),
            process(1, cwd: "/home/apex", state: .dormant),
            process(2, cwd: "/home/apex", state: .frozen),
        ]))

        XCTAssertEqual(rows.map(\.pid), [1, 3])
        XCTAssertEqual(rows.map(\.label), ["apex", "zed"])
    }

    func test_sleepersIsEmptyWhenNobodyIsAsleep() {
        XCTAssertTrue(FarmCensus.sleepers(for: pens([
            process(1, cwd: "/a", state: .idle),
        ])).isEmpty)
    }
}
