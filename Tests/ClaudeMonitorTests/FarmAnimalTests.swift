import XCTest
@testable import ClaudeMonitor

private func placedPen(_ states: [SessionState], species: AnimalSpecies = .cow) -> PlacedPen {
    let procs = states.enumerated().map { i, s in
        var p = ClaudeProcess(pid: 200 + i, cpu: 0, mem: 0, cwd: "/proj")
        p.state = s
        return p
    }
    let pen = FarmPen(cwd: "/proj", label: "proj", species: species, processes: procs)
    let size = FarmLayoutEngine.penSize(species: species, animalCount: procs.count)
    return PlacedPen(pen: pen, x: 5, y: 5, w: size.w, h: size.h, gate: .south,
                     gateX: 5 + size.w / 2)
}

final class FarmAnimalPlacementTests: XCTestCase {
    func test_placesOneEntryPerProcess() {
        let p = FarmAnimalPlacer.place(pen: placedPen([.idle, .active, .frozen]), time: 0)
        XCTAssertEqual(p.count, 3)
        XCTAssertEqual(p.map(\.pid), [200, 201, 202], "order follows pid, never state")
    }

    func test_slotIsByPidOrderAndDoesNotMoveWhenStateChanges() {
        // Spec §3.4: slot index is by pid order and never changes with state, or animals
        // teleport across the pen whenever a session flips.
        let a = FarmAnimalPlacer.place(pen: placedPen([.idle, .idle]), time: 0)
        let b = FarmAnimalPlacer.place(pen: placedPen([.overloaded, .idle]), time: 0)
        // Column assignment (which slot) must be unchanged; only the within-slot offset
        // differs, which is bounded and small.
        XCTAssertLessThan(abs(a[1].bx - b[1].bx), 20,
                          "second animal jumped slots when the first changed state")
    }

    func test_animalsStayInsideThePenInterior() {
        for count in 1...8 {
            let pen = placedPen(Array(repeating: .idle, count: count), species: .chicken)
            for a in FarmAnimalPlacer.place(pen: pen, time: 0) {
                XCTAssertGreaterThanOrEqual(a.bx, pen.x * 16)
                XCTAssertLessThanOrEqual(a.bx, (pen.x + pen.w) * 16)
            }
        }
    }

    func test_idleUsesEatSheetAndActiveUsesWalkSheet() {
        let p = FarmAnimalPlacer.place(pen: placedPen([.idle, .active]), time: 0)
        XCTAssertEqual(p[0].sheet, .eat, "idle grazes — head down")
        XCTAssertEqual(p[1].sheet, .walk, "active walks — head up")
    }

    func test_frozenIsAHeldFrame() {
        let t0 = FarmAnimalPlacer.place(pen: placedPen([.frozen]), time: 0)[0]
        let t1 = FarmAnimalPlacer.place(pen: placedPen([.frozen]), time: 3.7)[0]
        XCTAssertEqual(t0.frame, t1.frame, "frozen must not animate at all")
        XCTAssertEqual(t0.bx, t1.bx)
        XCTAssertEqual(t0.by, t1.by)
    }

    func test_onlySideFacingRowsAreUsed() {
        // Rows 0/2 (front/back) are banned by the global constraints — tall thin totems.
        for slot in 0..<8 {
            XCTAssertTrue([1, 3].contains(FarmAnimalPlacer.spriteRow(slotIndex: slot)))
        }
    }

    func test_activeStandsForwardOfIdle() {
        // The still-frame discriminator: idle hangs back, active steps forward.
        let idle = FarmAnimalPlacer.place(pen: placedPen([.idle]), time: 0)[0]
        let active = FarmAnimalPlacer.place(pen: placedPen([.active]), time: 0)[0]
        XCTAssertGreaterThan(active.by, idle.by, "active should sit lower (nearer viewer)")
    }

    func test_badgeAssignment() {
        let p = FarmAnimalPlacer.place(pen: placedPen([.idle, .active, .overloaded, .frozen]), time: 0)
        XCTAssertNil(p[0].badgeTile)
        XCTAssertNil(p[1].badgeTile)
        XCTAssertEqual(p[2].badgeTile, 105, "overloaded gets the bomb; 0095 is reserved")
        XCTAssertNil(p[3].badgeTile)
    }
}

final class FarmAnimalTintTests: XCTestCase {
    func test_idleAndActiveAreUntinted() {
        for state in [SessionState.idle, .active] {
            let t = FarmAnimalPlacer.tint(for: state, time: 0)
            XCTAssertEqual(t.r, 1.0, accuracy: 0.001)
            XCTAssertEqual(t.g, 1.0, accuracy: 0.001)
            XCTAssertEqual(t.b, 1.0, accuracy: 0.001)
            XCTAssertEqual(t.a, 1.0, accuracy: 0.001)
        }
    }

    func test_frozenIsACoolMultiplyWithAlphaUntouched() {
        // Spec §5.3, k = 0.45. Alpha must NOT change — fading reads as broken/absent,
        // and desaturation fails on the near-white species.
        let t = FarmAnimalPlacer.tint(for: .frozen, time: 0)
        XCTAssertEqual(t.r, 0.847, accuracy: 0.002)
        XCTAssertEqual(t.g, 0.883, accuracy: 0.002)
        XCTAssertEqual(t.b, 0.964, accuracy: 0.002)
        XCTAssertEqual(t.a, 1.0, accuracy: 0.001, "frozen must not fade")
        XCTAssertLessThan(t.r, t.b, "the shade must be cool, not warm")
    }

    func test_frozenTintIsConstantOverTime() {
        XCTAssertEqual(FarmAnimalPlacer.tint(for: .frozen, time: 0),
                       FarmAnimalPlacer.tint(for: .frozen, time: 9.1))
    }

    func test_overloadedPulsesRedAndStaysOpaque() {
        var sawWarm = false
        for step in 0..<40 {
            let t = FarmAnimalPlacer.tint(for: .overloaded, time: Double(step) * 0.05)
            XCTAssertEqual(t.a, 1.0, accuracy: 0.001)
            XCTAssertLessThanOrEqual(t.g, 1.0)
            if t.g < 0.9 && t.b < 0.9 { sawWarm = true }
        }
        XCTAssertTrue(sawWarm, "overloaded never reached a red phase")
    }

    func test_overloadedPulseVaries() {
        let samples = stride(from: 0.0, to: 1.0, by: 0.05)
            .map { FarmAnimalPlacer.tint(for: .overloaded, time: $0).g }
        XCTAssertGreaterThan(samples.max()! - samples.min()!, 0.1, "the pulse is flat")
    }

    func test_onlyOverloadedLiftsTowardRed() {
        for state in [SessionState.idle, .active, .frozen] {
            XCTAssertEqual(FarmAnimalPlacer.tint(for: state, time: 0.3).redLift, 0, accuracy: 0.0001,
                           "\(state) must not lift the red channel")
        }
    }

    func test_overloadedLiftOscillatesAcrossTheSpecRange() {
        let lifts = stride(from: 0.0, to: 1.0, by: 0.02)
            .map { FarmAnimalPlacer.tint(for: .overloaded, time: $0).redLift }
        XCTAssertGreaterThanOrEqual(lifts.min()!, -0.0001)
        XCTAssertLessThanOrEqual(lifts.max()!, 0.4501, "spec §5.3 caps amt at 0.45")
        XCTAssertGreaterThan(lifts.max()! - lifts.min()!, 0.3, "the pulse should traverse most of its range")
    }
}

final class FarmAnimalWanderTests: XCTestCase {
    func test_idleWanderStaysAnchored() {
        // §5.6: small amplitude, always returning to a per-pid anchor. Free drift is
        // invisible frame-to-frame and obvious after five minutes.
        let pen = placedPen([.idle])
        let samples = stride(from: 0.0, through: 120.0, by: 0.5).map {
            FarmAnimalPlacer.place(pen: pen, time: $0)[0]
        }
        let xs = samples.map(\.bx), ys = samples.map(\.by)
        XCTAssertLessThanOrEqual(xs.max()! - xs.min()!, 16, "wander exceeded one tile horizontally")
        XCTAssertLessThanOrEqual(ys.max()! - ys.min()!, 16, "wander exceeded one tile vertically")
        // And it must genuinely return, not creep: the last minute must cover the same
        // ground as the first, which a drifting implementation would not.
        let firstHalf = Set(samples.prefix(samples.count / 2).map(\.bx))
        let secondHalf = Set(samples.suffix(samples.count / 2).map(\.bx))
        XCTAssertFalse(firstHalf.intersection(secondHalf).isEmpty,
                       "the animal never revisits its earlier positions — it is drifting")
    }
}

/// Spec §5.2 ("walk cycle, traverses the pen"), §5.6 ("`active` is a continuous traverse
/// of the pen") and §7 ("the active walk is a fixed traverse — a pure function of
/// `(pid, time)`"). The walk cycle shipped without the traverse: the legs moved and the
/// animal did not.
final class FarmAnimalTraverseTests: XCTestCase {
    /// 0.17s, not a round number: the traverse period is `2 * travel / 12`, which for a
    /// cow is exactly 2.5s. A 0.25s step divides that evenly and samples the same ten
    /// phases forever, which understates the range and invents stalls at the turns.
    private func track(_ pen: PlacedPen, index: Int = 0,
                       through seconds: Double = 120) -> [AnimalPlacement] {
        stride(from: 0.0, through: seconds, by: 0.17).map {
            FarmAnimalPlacer.place(pen: pen, time: $0)[index]
        }
    }

    /// §5.6 defines the discriminator against idle as **amplitude and duty cycle**, not
    /// the presence of motion — so this measures against the idle wander rather than a
    /// magic number. It has to: pens are sized snugly around their animals (a lone cow
    /// has 15px of slack in a 96px interior), so "traverses the pen" is about a tile of
    /// ground, and a fixed threshold would either be unreachable or prove nothing.
    func test_anActiveAnimalCoversFarMoreGroundThanAnIdleOne() {
        let active = track(placedPen([.active])).map(\.bx)
        let idle = track(placedPen([.idle])).map(\.bx)
        let activeRange = active.max()! - active.min()!
        let idleRange = idle.max()! - idle.min()!

        XCTAssertGreaterThan(activeRange, 12, "active is walking on the spot — the whole bug")
        XCTAssertGreaterThan(activeRange, idleRange * 3,
                             "active (\(activeRange)px) barely out-ranges idle (\(idleRange)px)")
    }

    /// The other half of §5.6's discriminator. Idle spends most of its cycle anchored;
    /// active is a continuous traverse, so it should be in motion nearly every sample.
    func test_activeIsMovingAlmostAlways_andIdleIsMostlyAtRest() {
        func dutyCycle(_ state: SessionState) -> Double {
            let xs = track(placedPen([state])).map(\.bx)
            let moved = zip(xs, xs.dropFirst()).filter { $0 != $1 }.count
            return Double(moved) / Double(xs.count - 1)
        }
        XCTAssertGreaterThan(dutyCycle(.active), 0.8)
        XCTAssertLessThan(dutyCycle(.idle), 0.4)
    }

    func test_anActiveAnimalStaysInsideThePenAtEveryOccupancy() {
        for count in 1...8 {
            for species in [AnimalSpecies.cow, .chicken] {
                let pen = placedPen(Array(repeating: .active, count: count), species: species)
                let (w, _) = FarmAnimalPlacer.spriteSize(for: species)
                for index in 0..<count {
                    for a in track(pen, index: index, through: 60) {
                        XCTAssertGreaterThanOrEqual(a.bx, (pen.x + 1) * 16,
                                                    "\(species) \(count)x walked through the left rail")
                        XCTAssertLessThanOrEqual(a.bx + w, (pen.x + pen.w - 1) * 16,
                                                 "\(species) \(count)x walked through the right rail")
                    }
                }
            }
        }
    }

    /// Each animal traverses its own lattice slot, which is what lets §7 hold — "no
    /// pathfinding needed". Two animals sharing ground would need collision handling the
    /// spec rules out, and would read as one walking through the other.
    func test_neighboursNeverWalkThroughEachOther() {
        let pen = placedPen(Array(repeating: .active, count: 4))
        let (w, _) = FarmAnimalPlacer.spriteSize(for: .cow)
        let left = track(pen, index: 0, through: 60).map(\.bx)
        let right = track(pen, index: 1, through: 60).map(\.bx)

        for (l, r) in zip(left, right) {
            XCTAssertLessThanOrEqual(l + w, r, "their sprite boxes overlap — one walked through the other")
        }
    }

    /// An animal walking left in the right-facing row is moonwalking. This is the part
    /// that reads as broken rather than merely still.
    func test_theAnimalFacesTheWayItIsWalking() {
        let samples = track(placedPen([.active]), through: 60)
        var checked = 0
        // Pairs that straddle a turn are skipped: the peak sits between the two samples,
        // so the rounded x can still be rising after the animal has already turned, and
        // the direction inferred from the pair is genuinely ambiguous. Every pair within
        // one half-cycle is checked, which is what catches an inverted facing.
        for (a, b) in zip(samples, samples.dropFirst()) where a.bx != b.bx && a.row == b.row {
            XCTAssertEqual(b.row, b.bx > a.bx ? 3 : 1,
                           "facing row \(b.row) while moving \(b.bx > a.bx ? "right" : "left")")
            checked += 1
        }
        XCTAssertGreaterThan(checked, 100, "not enough movement sampled to prove anything")
    }

    /// It has to turn around, not walk off and clamp against the rail — a clamped animal
    /// stands still with its legs going, which is the bug wearing a different hat.
    func test_theTraverseTurnsRoundRatherThanPilingIntoTheRail() {
        let xs = track(placedPen([.active]), through: 120).map(\.bx)
        // Longest unbroken run at either extreme. A clamped walk parks there for many
        // consecutive samples; a turn touches it and leaves, so runs stay short. Counting
        // total visits instead would flag a perfectly good turn that happens often.
        func longestRun(at value: Int) -> Int {
            var best = 0, run = 0
            for x in xs {
                run = x == value ? run + 1 : 0
                best = max(best, run)
            }
            return best
        }
        XCTAssertLessThanOrEqual(longestRun(at: xs.max()!), 3, "piling up against one end")
        XCTAssertLessThanOrEqual(longestRun(at: xs.min()!), 3, "piling up against one end")
    }

    /// Every active animal must actually move, at every occupancy a pen can hold. The
    /// traverse degrading to nothing in a crowded pen is not a graceful degradation — it
    /// is the reported bug, unfixed, in the pens most likely to have it noticed.
    func test_everyActiveAnimalMovesAtEveryOccupancy() {
        var stuck: [String] = []
        for species in AnimalSpecies.allCases {
            for count in 1...8 {
                let pen = placedPen(Array(repeating: .active, count: count), species: species)
                for index in 0..<count {
                    let xs = track(pen, index: index, through: 30).map(\.bx)
                    let range = xs.max()! - xs.min()!
                    if range < 8 { stuck.append("\(species) x\(count) slot \(index): \(range)px") }
                }
            }
        }
        XCTAssertEqual(stuck, [], "animals walking on the spot:\n" + stuck.joined(separator: "\n"))
    }

    func test_theTraverseIsDeterministic() {
        let pen = placedPen([.active, .active])
        XCTAssertEqual(FarmAnimalPlacer.place(pen: pen, time: 17.5),
                       FarmAnimalPlacer.place(pen: pen, time: 17.5))
    }

    /// Spec §5.2 gives `overloaded` "walk + 1px integer bounce" and does not say it
    /// traverses: its cues are the red pulse, the bomb and the bounce, and a roaming
    /// overloaded animal would blur the one distinction §5.6 rests on.
    func test_overloadedStaysPut() {
        let xs = track(placedPen([.overloaded]), through: 60).map(\.bx)
        XCTAssertLessThanOrEqual(xs.max()! - xs.min()!, 2)
    }

    /// Two animals in one pen must not turn in lockstep — spec §5.1 wants ambient life,
    /// and synchronised movement reads as a mechanism rather than a farm.
    func test_penMatesAreOutOfPhase() {
        let pen = placedPen([.active, .active])
        let a = track(pen, index: 0, through: 60).map(\.bx)
        let b = track(pen, index: 1, through: 60).map(\.bx)
        let deltaA = zip(a, a.dropFirst()).map { $1 - $0 }
        let deltaB = zip(b, b.dropFirst()).map { $1 - $0 }
        XCTAssertNotEqual(deltaA, deltaB, "both animals move identically")
    }
}

/// An animal that walks to one end of its pen and then goes idle must stay there. Before
/// this it snapped back to its slot centre — it had walked, and then un-walked.
final class FarmAnimalRestingAnchorTests: XCTestCase {
    private func pen(_ state: SessionState, since: Double?) -> PlacedPen {
        var p = ClaudeProcess(pid: 200, cpu: 0, mem: 0, cwd: "/proj")
        p.state = state
        p.idleSince = since.map { Date(timeIntervalSinceReferenceDate: $0) }
        let farmPen = FarmPen(cwd: "/proj", label: "proj", species: .cow, processes: [p])
        let size = FarmLayoutEngine.penSize(species: .cow, animalCount: 1)
        return PlacedPen(pen: farmPen, x: 5, y: 5, w: size.w, h: size.h, gate: .south,
                         gateX: 5 + size.w / 2)
    }

    private func bx(_ state: SessionState, since: Double?, at time: Double) -> Int {
        FarmAnimalPlacer.place(pen: pen(state, since: since), time: time)[0].bx
    }

    /// "Does not reset", stated directly: the frame it stops walking and the frame it is
    /// resting are the same place.
    func test_theAnimalRestsWhereItStoppedWalking() {
        for stop in [3.1, 17.6, 41.3, 88.9] {
            let stopped = bx(.active, since: nil, at: stop)
            let resting = bx(.idle, since: stop, at: stop)
            // Within the idle wander's own ±3px, which rides on top of the anchor from the
            // first frame — the animal is resting *there*, not standing to attention.
            XCTAssertLessThanOrEqual(abs(resting - stopped), 3,
                                     "jumped on going idle at t=\(stop): \(stopped) -> \(resting)")
        }
    }

    /// Stopping at different points in the traverse must rest at different points, or the
    /// anchor is not really being remembered — it is just a differently-placed constant.
    func test_stoppingAtDifferentTimesRestsInDifferentPlaces() {
        let stops = stride(from: 0.0, to: 2.5, by: 0.25).map { bx(.idle, since: $0, at: 60) }
        XCTAssertGreaterThan(Set(stops).count, 4, "every stop resolves to the same anchor")
    }

    /// The wander is still a wander: it oscillates about the remembered spot rather than
    /// carrying the animal away from it (spec §5.6).
    func test_theRestingAnimalStillWandersAboutItsAnchor() {
        let anchor = bx(.idle, since: 41.3, at: 41.3)
        let xs = stride(from: 41.3, through: 161.3, by: 0.17).map { bx(.idle, since: 41.3, at: $0) }
        for x in xs {
            XCTAssertLessThanOrEqual(abs(x - anchor), 4, "wandered off its anchor")
        }
        XCTAssertGreaterThan(Set(xs).count, 1, "the wander stopped happening")
    }

    /// Freezing is the same animal ten minutes later. Without this it teleports at the
    /// ten-minute mark, which is the same complaint on a delay.
    func test_freezingHoldsTheSameSpotAsResting() {
        // Against the active position rather than the idle one: frozen is a held frame
        // with no wander, so the two are exactly equal or the anchor is not being applied.
        XCTAssertEqual(bx(.frozen, since: 41.3, at: 700), bx(.active, since: nil, at: 41.3))
    }

    /// Every existing caller and fixture passes no `idleSince`. Those animals must sit
    /// where they always have — the centre of their slot.
    func test_withoutAStopTimeTheAnimalRestsAtItsSlotCentre() {
        let withNoHistory = bx(.idle, since: nil, at: 0)
        let active = bx(.active, since: nil, at: 0)
        // Slot centre is where the traverse is at its own zero crossing, which the wander
        // then oscillates about; the two need only agree to within the wander's amplitude.
        XCTAssertLessThanOrEqual(abs(withNoHistory - active), 12)
    }
}
