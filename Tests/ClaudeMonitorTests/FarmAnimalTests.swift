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
