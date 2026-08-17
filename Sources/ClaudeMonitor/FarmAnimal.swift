import Foundation

/// Where to draw one animal and which frame to draw. Pure placement data — this
/// type does not touch `CGImage`/`CGContext`; Task 10's renderer looks up the actual
/// sprite bytes for `species`/`sheet`/`row`/`frame` and draws them anchored at the
/// baseline `(bx, by)`.
struct AnimalPlacement: Equatable {
    let pid: Int
    let species: AnimalSpecies
    let state: SessionState
    let sheet: AnimalAction
    let row: Int, frame: Int      // into the 4x4 sheet
    let bx: Int, by: Int          // 1x px; by is the BASELINE (feet)
    let badgeTile: Int?
}

/// Per-pixel colour transform for one animal.
///
///     out.r = src.r * r + (255 - src.r) * redLift
///     out.g = src.g * g
///     out.b = src.b * b
///     out.a = src.a * a
///
/// Only the red channel has a lerp term. Spec §5.3's overloaded red is
/// `r' = r + (255-r)*amt` — a lerp toward white that no multiplier can express, since
/// the required factor depends on the source pixel; green and blue are plain multiplies.
/// Applying `redLift` to green or blue would brighten dark pixels instead of tinting
/// them (a black patch at g=20 would render 118 instead of 13).
struct AnimalTint: Equatable {
    let r, g, b, a: Double
    /// Lerp-toward-255 amount, red channel ONLY. Zero for every state except overloaded.
    var redLift: Double = 0
}

/// Spec `docs/farm-design-spec.md` §3.4 (slot lattice), §5.2-5.4 (state cues, exact
/// values, draw order) and §5.6 (anchored idle wander). Ported from `mock7.py:411-496`
/// and `states.py`, generalized from a single static frame to a `time`-driven one.
enum FarmAnimalPlacer {
    /// Tile size in px (spec §1, `T = 16`).
    private static let tile = 16

    /// Measured LPC **side-view** bboxes, px (spec §2.1). A pen holds a single
    /// species, so this single constant stands in for the §3.4 lattice's
    /// `wmax`/`hmax` — there's no need to load and trim actual sprite frames just to
    /// place them; that pixel work belongs to the renderer in Task 10.
    ///
    /// Not `private`: this is an approximation of the real, per-frame trimmed sprite
    /// box (mock7.py computed `wmax`/`hmax` from the actual cropped bitmap), used here
    /// only for layout math — slot spacing, the state offset, and the `(bx, by)`
    /// clamps above. The renderer draws with the real trimmed `CGImage`'s actual
    /// dimensions (badge offset `(bx + w/2 - 8, by - h - 13)`, draw anchor
    /// `(bx, by - h)`), which is *more* accurate against `mock7.py` than this table —
    /// this table is off from the real trimmed bounds by up to +4px width, -7px
    /// height. That's expected: this is a placement-time approximation, not a second
    /// source of truth to keep in sync with the renderer's.
    static func spriteSize(for species: AnimalSpecies) -> (w: Int, h: Int) {
        switch species {
        case .cow: return (71, 44)
        case .sheep: return (49, 39)
        case .pig: return (55, 30)
        case .chicken: return (31, 26)
        }
    }

    /// Rows 1 (left) and 3 (right) only — spec §5.3: rows 0/2 are front/back views,
    /// tall thin totems, and most of why the previously shipped animals looked wrong.
    /// Alternates by slot index so neighbouring animals don't all face one way.
    ///
    /// This is the resting facing. An `.active` animal overrides it every frame to match
    /// its direction of travel, so two of them can face the same way — they are walking,
    /// and where they are pointed is not a decoration to be varied.
    static func spriteRow(slotIndex: Int) -> Int {
        slotIndex % 2 == 0 ? 3 : 1
    }

    /// Static per-slot stagger (`mock7.py`'s `(i*2+1) % 4`) advanced by `time` so the
    /// walk cycle actually plays; spec §5.3 asks overloaded to keep "walk playback
    /// near normal rate" too, so both `.active` and `.overloaded` share this.
    private static func walkFrame(slotIndex: Int, time: Double) -> Int {
        let base = (slotIndex * 2 + 1) % 4
        let advance = Int(time * 6.0)
        // Swift's `%` preserves the dividend's sign, so a raw `% 4` can go negative when
        // `time < 0` — this value indexes a sprite-sheet column, so that would crash
        // Task 10's renderer rather than just draw a wrong pixel. `time` should never be
        // negative in practice, but the failure mode is severe enough to guard for one line.
        return (((base + advance) % 4) + 4) % 4
    }

    /// 1px **integer** vertical bounce for `overloaded` (spec §5.2), toggling at ~2Hz,
    /// phased per pid so a pen full of overloaded animals doesn't bounce in lockstep.
    private static func bounce(pid: Int, time: Double) -> Int {
        let phase = Double(StableHash.pick(1000, pid, 0x54)) / 1000.0
        return Int((time + phase) * 2.0) % 2
    }

    /// Spec §5.6: short (<=1 tile), slow, long pauses, **always returning to a
    /// per-pid anchor**. Unanchored drift is invisible frame-to-frame but is the
    /// reshuffling complaint in slow motion after five minutes, so this envelope
    /// spends most of its cycle at rest and only briefly bumps away and back.
    private static func idleWander(pid: Int, time: Double) -> (dx: Int, dy: Int) {
        let period = 6.0 + Double(StableHash.pick(400, pid, 0x51)) / 100.0   // ~6-10s
        let phase = Double(StableHash.pick(1000, pid, 0x52)) / 1000.0 * period
        let t = (time + phase).truncatingRemainder(dividingBy: period)
        let excursion = 0.18 * period
        guard t > period - excursion else { return (0, 0) }   // long pause, anchored
        let localT = (t - (period - excursion)) / excursion
        let bump = sin(localT * .pi)          // 0 -> 1 -> 0: always resolves to anchor
        let dir = StableHash.pick(2, pid, 0x53) == 0 ? 1 : -1
        return (Int((Double(dir) * 3 * bump).rounded()), Int(bump.rounded()))
    }

    /// Traverse speed, px/s. Slow enough to read as grazing-pace walking rather than
    /// pacing, and close enough to the 6fps walk cycle's stride that the feet do not
    /// visibly skate.
    private static let walkSpeed = 12.0

    /// Spec §5.2 ("walk cycle, traverses the pen") and §5.6 ("`active` is a continuous
    /// traverse of the pen"). The walk cycle shipped without this: the legs moved and the
    /// animal stood still.
    ///
    /// A triangle wave, deliberately not a sine. A sine eases to a stop at each end while
    /// the legs keep cycling at a constant 6fps, which reads as slipping on ice; constant
    /// speed matches the constant-rate animation.
    ///
    /// `travel` is the room inside the animal's own lattice slot, so nobody ever steps
    /// onto a neighbour's ground and §7's "no pathfinding needed" keeps holding. Pens are
    /// sized snugly (`FarmLayoutEngine.footprint` allows a lone cow ~15px of slack), so
    /// this is about a tile of ground, not a lap. That still satisfies §5.6, whose
    /// discriminator against idle is amplitude and duty cycle: `idleWander` is ±3px at an
    /// 18% duty cycle, this is 5x the amplitude and never at rest.
    private static func activeTraverse(pid: Int, travel: Int,
                                       time: Double) -> (dx: Int, facingRight: Bool) {
        guard travel > 0 else { return (0, true) }

        let period = 2 * Double(travel) / walkSpeed          // out and back
        let phase = Double(StableHash.pick(1000, pid, 0x55)) / 1000.0 * period
        // `truncatingRemainder` keeps the dividend's sign, and a negative `t` would put
        // the animal outside its slot rather than merely at the wrong phase.
        var t = (time + phase).truncatingRemainder(dividingBy: period)
        if t < 0 { t += period }

        let u = t / period
        let ramp = u < 0.5 ? u * 2 : (1 - u) * 2             // 0 -> 1 -> 0
        let offset = Double(travel) * (ramp - 0.5)           // centred on the slot
        return (Int(offset.rounded()), u < 0.5)
    }

    /// Room an animal has to walk inside its own lattice slot, leaving 2px of air between
    /// neighbouring sprite boxes at their closest approach. Not more: the sprites are
    /// trimmed to their visible bounds, so 2px is real daylight, and every pixel spent
    /// here comes straight out of the travel of the fullest pens — at 4px a pen of eight
    /// cows had 6px to walk in, which is back to standing still.
    private static func travel(slot: Double, spriteW: Int) -> Int {
        max(0, Int(slot) - spriteW - 2)
    }

    static func place(pen: PlacedPen, time: Double) -> [AnimalPlacement] {
        let species = pen.pen.species
        let processes = pen.pen.processes
        guard !processes.isEmpty else { return [] }

        let (w, h) = spriteSize(for: species)

        // Interior box in px (spec §3.4).
        let iw = pen.w - 2, ih = pen.h - 2
        let IX = (pen.x + 1) * tile, IY = (pen.y + 1) * tile
        let IW = iw * tile, IH = ih * tile

        let count = processes.count
        // The same column count the pen was *built* for. Deriving it here from how many
        // sprites happen to fit (`IW / (w + 4)`) let a pen that was sized for four columns
        // be filled with five, and the surplus column came out of the slack each animal
        // needs to walk in — which is why crowded pens had active animals standing still.
        // `footprint` guarantees a column is wider than its sprite, so this always fits.
        let ncols = FarmLayoutEngine.penColumns(animalCount: count)
        let nrows = Int(ceil(Double(count) / Double(ncols)))
        let depth = h < 34 ? 11 : 8                 // px of y separation between ranks
        let span = Double(IW - 6)
        let slot = span / Double(ncols)

        return processes.enumerated().map { i, process in
            let col = i % ncols
            let row = i / ncols
            let rank = nrows - 1 - row              // rank 0 = frontmost

            var bx = IX + 3 + Int(Double(col) * slot + (slot - Double(w)) / 2)
            var by = IY + IH - 1 - rank * depth

            // State offset within the slot, spec §5.3: off = max(4, h/6).
            let off = max(4, h / 6)
            let sheet: AnimalAction
            let frame: Int
            var badgeTile: Int?
            // Which way the animal is drawn facing. Fixed per slot for every state
            // except `.active`, which overrides it to match its direction of travel.
            var facingRow = spriteRow(slotIndex: i)

            // Where the animal's walk ended, if it has stopped: the traverse evaluated at
            // the instant it went quiet. A resting animal stands here instead of at its
            // slot centre, so going idle no longer snaps it back across the pen it just
            // walked. Pure, like everything else here — the memory is `idleSince`, which
            // `SessionStateTracker` has always kept for the frozen escalation.
            let restingDx = process.idleSince.map {
                activeTraverse(pid: process.pid, travel: travel(slot: slot, spriteW: w),
                               time: $0.timeIntervalSinceReferenceDate).dx
            } ?? 0

            switch process.state {
            case .idle:
                // eat sheet col 2, head down, hangs back at the rail, plus anchored
                // wander (spec §5.6) about wherever it stopped.
                sheet = .eat; frame = 2
                by -= off
                let (wdx, wdy) = idleWander(pid: process.pid, time: time)
                bx += restingDx + wdx; by += wdy
            case .frozen:
                // eat sheet col 3, held frame — no motion, no time dependence at all.
                // Holds the resting anchor too: a frozen session is an idle one ten
                // minutes on, and without this it teleports at the ten-minute mark.
                // The back-of-pen `by` is §5.2's own cue and is unaffected.
                sheet = .eat; frame = 3
                by -= off + 2
                bx += restingDx
            case .dormant:
                sheet = .eat; frame = 3
                by -= off + 2
                bx += restingDx
            case .active:
                // walk sheet, forward, overlaps the bottom rail, traversing its slot
                // (spec §5.2). The static `bx += off` the other walking states use is
                // dropped here: it is a nudge off the slot's centre, and an animal that
                // swings symmetrically about that centre is the thing that keeps it clear
                // of its neighbours. Facing follows the direction of travel — walking left
                // in the right-facing row is moonwalking, and reads as broken rather than
                // merely still.
                sheet = .walk
                frame = walkFrame(slotIndex: i, time: time)
                by += off
                let (tdx, facingRight) = activeTraverse(
                    pid: process.pid, travel: travel(slot: slot, spriteW: w), time: time)
                bx += tdx
                facingRow = facingRight ? 3 : 1
            case .overloaded:
                // walk sheet + 1px integer bounce, forward, bomb badge (0105).
                // 0095 (red plate) is reserved for the future needs-attention state.
                sheet = .walk
                frame = walkFrame(slotIndex: i, time: time)
                by += off - 2 - bounce(pid: process.pid, time: time)
                bx += off - 2
                badgeTile = 105
            }

            bx = max(IX + 2, min(bx, IX + IW - w - 2))
            by = max(IY + h + 1, min(by, IY + IH + 8))

            return AnimalPlacement(
                pid: process.pid, species: species, state: process.state,
                sheet: sheet, row: facingRow, frame: frame,
                bx: bx, by: by, badgeTile: badgeTile
            )
        }
    }

    static func tint(for state: SessionState, time: Double) -> AnimalTint {
        switch state {
        case .idle, .active:
            return AnimalTint(r: 1.0, g: 1.0, b: 1.0, a: 1.0)
        case .frozen, .dormant:
            // Spec §5.3: cool multiply, k = 0.45, alpha untouched, constant over
            // time (frozen must not animate at all). Desaturation was tried and
            // fails — sheep, chicken and the Holstein cow are near-white and have
            // no saturation to remove. Alpha fade was tried and reads as
            // broken/absent. Multiplying darkens white too, so it works across all
            // four species.
            return AnimalTint(r: 0.847, g: 0.883, b: 0.964, a: 1.0)
        case .overloaded:
            // Spec §5.3: amt oscillates 0 -> 0.45 at 1.2Hz.
            //   r' = r + (255-r)*amt   (r starts at max, so the tint's r stays 1)
            //   g' = g*(1 - amt*0.8)
            //   b' = b*(1 - amt*0.9)
            // alpha unchanged — overloaded must stay opaque, only colour pulses.
            let amt = 0.225 * (1 - cos(2 * Double.pi * 1.2 * time))
            return AnimalTint(r: 1.0, g: 1.0 - amt * 0.8, b: 1.0 - amt * 0.9, a: 1.0, redLift: amt)
        }
    }
}
