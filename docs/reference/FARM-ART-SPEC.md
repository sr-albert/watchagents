# Farm scene — art direction spec

Reference renders (on Desktop):
- `FARM-1-typical.png` — 8 pens, **the honest state distribution** (13 idle/frozen,
  1 active, 0 overloaded). This is what the window looks like most of the time and is
  the real test of "is this pleasant when nothing is happening".
- `FARM-5-all-states.png` — **synthetic**, every state at once. Not representative;
  for cue comparison only.
- `FARM-2-fourteen-pens.png` — 14 pens, 52×40 tiles @2× (density test)
- `FARM-3-single-pen-3x.png` — 1 pen, 32×20 tiles @3× (sparse test)
- `FARM-4-state-cues.png` — the four states side by side @3×

Generator: `mock7.py` (`render()` is the layout algorithm, 1:1 portable to Swift),
`states.py` (state key).

---

## 1. Why mockup3 read as a dashboard

1. **Same silhouette as the thing it replaces.** Four identical 13×8 rectangles on a
   2×2 grid with a gutter. That is `CURRENT-bad-ui.png` rotated into two columns with
   a grass texture applied. A fence is not a place; it is a `border-radius` with more
   pixels.
2. **Occupancy ~3%.** A 13×8 pen is 104 tiles holding 1–3 animals. In the reference,
   the chicken run is 6×5 = 30 tiles holding 5 birds. Empty pens read as *loading*.
3. **Uniform noise ≠ texture.** 90% tile 0000, then 0001/0002 dusted at a flat
   probability per tile. Uniform random has no clusters, no regions, no direction —
   it is visual static. Real ground has *areas*.
4. **Confetti scenery.** Trees placed one at a time at random with collision spacing;
   flowers at 5% everywhere. Nature clumps. Even distribution reads as noise.
5. **No focal point.** The barn is 3×3 in a corner, the same visual weight as a tree,
   connected to nothing. The eye has nowhere to land and nowhere to travel.
6. **Everything on one plane.** No overlaps, no shadows, no y-sorting. Kenney tiles
   have baked dark outlines that give objects mass, but with nothing occluding
   anything there is no depth.
7. **Inside and outside the fence are the same ground.** So the fence encloses nothing.
8. **Labels are HUD.** Antialiased 16px Arial with a drop shadow floating over 2×
   nearest-neighbour pixels. This is the single loudest "this is software" signal.
9. **Down-facing quadruped frames.** LPC cow front/back views are 27×57–71px — a
   tall thin totem. Measured: side views are 71×43. Side view only, always.

---

## 2. Layout

### Tile grid from window
```
scale  = clamp(floor(min(w/320, h/224)), 1, 3)     // 3× only on large windows
COLS   = floor(w / (16*scale)),  ROWS = floor(h / (16*scale))
```
Never fractional. Leftover pixels go to a symmetric letterbox of grass colour
`#6EBE5A`, or just extend the ground fill.

### Frame margins (tiles)
`MARGIN_L = MARGIN_R = 4`, `MARGIN_T = 3`, `FRAME_B = 4`. These are woodland.

### Pen size from occupancy
Species side-view footprints, measured from the sheets:

| species | side bbox px | footprint tiles |
|---|---|---|
| cow     | 71 × 44 | 5 × 3 |
| sheep   | 49 × 39 | 4 × 3 |
| pig     | 55 × 30 | 4 × 2 |
| chicken | 31 × 26 | 3 × 2 (widened from the measured 2 — 2 crowded the slot lattice and chickens overlapped; don't 'correct' it back) |

```
rows = (n <= 2) ? 1 : 2
cols = ceil(n / rows)
interiorW = cols * footW + 1
interiorH = footH + (rows - 1) + 1
penW = max(7, interiorW + 2)      // +2 for the fence ring
penH = max(5, interiorH + 2)
```
Cap displayed animals at 8; surplus becomes `+N` appended to the sign text.

### Row packing (deterministic, no reshuffle)
Walk the ordered pen list left→right. Row 1 starts with `BARN_W + GAP + 1` already
consumed — the barn is literally the first item in the flow. Add pens while
`usedWidth + penW <= COLS - MARGIN_L - MARGIN_R`; otherwise start a new row.
`GAP = 2` tiles between pens. Pens in a row are **bottom-aligned** to the row band
(`rowH = max(penH)`), which gives a ragged top edge — that alone kills the grid look.

### Lanes
A 2-tile dirt lane sits between every pair of rows. Row *i* gates **S** onto the lane
below it; the final row gates **N** onto the lane above. Lane x-extent is
`[MARGIN_L+1, COLS-MARGIN_R-1]` — it terminates, it does not bleed off the edges.

### Fit rule (must run before layout — this is not optional)
The packing loop must wrap-test **every** pen including the first in a row, otherwise
row 0's first pen is placed past the barn regardless of window width and renders off
the right edge.

```
minCols = maxPenW + BARN_W + GAP + 1 + MARGIN_L + MARGIN_R
minRows = sum(rowHeights) + 2*laneCount + MARGIN_T + FRAME_B
```
For a 2-cow pen (`penW = 13`) that is `minCols = 31` → **1488 px minimum window width
at 3×, 992 px at 2×, 496 px at 1×.** Pick scale by trying 3 → 2 → 1 and taking the
first that satisfies both. If even 1× fails on width, move the barn to its own row
(recovers 10 columns). If 1× fails on height, scroll vertically. **Never clip a pen.**

### Degradation
- **1 pen** → 1 row, no lanes; barn + pen, a short spur, woodland frame. See
  `FARM-3`. Bump to 3× so it does not look like a lost cow in a field.
- **~14 pens** → 4 rows, 3 lanes. See `FARM-2`. Still readable at a glance.
- **Overflow**: drop scale 3→2→1 first. Then let pens fall to their minimum
  (`penW=7, penH=5`). Then clip scenery — margins shrink to 1, woodland disappears.
  **Never clip a pen.** If pens still do not fit, scroll vertically; do not shrink.

---

## 3. Ground treatment

### Open country
Base grass `0000`. Variation is **clumped, not dusted**:
```
clump = hash(x/4, y/3, salt) % 100     // coarse cell -> regions
local = hash(x, y, salt2) % 100
tile  = 0001 (tufts)   if clump < 24 && local < 55
      = 0002 (flowers) if clump >= 93 && local < 35
      = 0001           if local < 4          // rare loners
      = 0000           otherwise
```

### Dirt (lanes, barnyard, pen wear) — one shared autotiled set
Maintain a `Set<Point>` of dirt cells, then pick per cell from neighbour occupancy:

| N free | S free | W free | E free | tile |
|---|---|---|---|---|
| ✓ | | ✓ | | 0012 |
| ✓ | | | ✓ | 0014 |
| | ✓ | ✓ | | 0036 |
| | ✓ | | ✓ | 0038 |
| ✓ | | | | 0013 |
| | ✓ | | | 0037 |
| | | ✓ | | 0024 |
| | | | ✓ | 0026 |
| | | | | 0025 70% / 0039 10% / 0040 8% / 0041 6% / 0042 6% |

Because lanes, gate thresholds and pen wear all feed the same set, they connect
automatically. There are no inner-corner tiles in this pack, so keep dirt shapes
convex-ish; concave notches fall back to `0025` and look fine.

### Pen interiors — worn patch, not a swatch
Do **not** floor the whole pen in dirt; that just swaps dark rounded rects for orange
ones. Per pen, dirt = union of:
- the 2×2 apron under the trough (interior bottom-left),
- the 2×1 threshold inside the gate,
- one irregular standing patch, radius ~2, placed by `hash(projectPath)`.

Roughly 25–35% of the interior. Grass survives in the corners and along the rails.

> **This is seeded from the project path only.** It must never depend on live state
> or animal position — repainting 40 ground tiles when a session flips would be a
> bigger visible churn than the reshuffling that was already rejected.
> The one exception is `frozen` (see §5), which is durable by definition.

---

## 4. Focal point, framing, filler

- **Barn** 7×4 at the head of row 1: roof `0052 0053×5 0054` with `0055` swapped in at
  centre for the hay-loft window, second roof row `0064 0065×5 0066`, two wall rows
  `0072 0073×5 0075`, ground row gets `0084` windows at ±1 from the ends and a double
  door `0074 0074` at centre. Apron of dirt in front, spur down to lane 1.
- **Farmyard cluster** (never scattered singly): hay `0093 0093 0094` stacked at the
  barn's right shoulder, `0116` pitchfork against the left wall, `0106`/`0107`
  barrel+bucket, `0130` chest, `0057` mailbox on the lane, `0083` signpost at the
  crossroads, `0103` character by the door for scale and life.
- **Woodland frame.** The key discovery: tiles `0006 0007 0008` over `0018 0019 0020`
  (and autumn `0009 0010 0011`/`0021 0022 0023`) **tile horizontally into a
  continuous canopy**. Use them as *bands*, not as individual trees — that is the
  difference between a forest and a field of lollipops.
  - Horizontal treeline: walk the edge in runs of 3–7 columns; each run gets depth 1
    or 2 bands and a 0–1 tile inset. Ragged, never a straight ribbon.
  - Vertical treeline: same idea, runs of 2–6 rows, 2–4 tiles deep.
  - Fringe: ~30% of columns get a single `0004/0016` (or `0003/0015`) just inside the
    mass, ~14% get a bush `0005/0028`. Softens the interface.
  - A band behind the barn nests it into the landscape.
  - Every band placement must test the occupancy set; if blocked, reduce depth/width.
    That is what keeps trees off the pens automatically.
- **Open lawn is allowed and good.** The reference has a big empty middle. What makes
  it not-boring is that it is *framed*. Do not fill it uniformly.
- **Leftover in the last row**: one compact orchard block (trees on a 3-tile lattice
  with alternating row offset — reads as planted, contrasts with wild woods), one hay
  yard, a few bush clumps. Not a uniform sprinkle.

---

## 5. State cues

### The salience budget (read this before the table)

The state-model spec is explicit: *"most of Claude's actual computation happens on
Anthropic's servers, so the local CLI process is often near-0% CPU even while a
session is productive. Idle/Frozen are expected to be the common states, not
exceptions."* That inverts the obvious design.

Ranked by **how much the user needs to act**, which is what salience should track:

| rank | state | frequency | user action |
|---|---|---|---|
| 1 | *needs attention* (future) | rare | **act now** — it is blocked on you |
| 2 | `overloaded` | rare | check your machine |
| 3 | `active` | brief flickers | nothing, but it is the interesting moment |
| 4 | `idle` | **common** | nothing |
| 5 | `frozen` | **common** | nothing — it just means you haven't typed in 10 min |

My first pass had this backwards: it gave `frozen` the most dramatic treatment in the
whole design (40% alpha fade + a weed-choked pen). If frozen is common, that renders a
farm of translucent ghosts standing in abandoned lots — which is both a lie about what
the state means and the opposite of a thing you'd keep in your menu bar. **Frozen now
recedes.** It is "asleep in the shade," not "dead."

Conversely, the *scene* has to stay alive when nothing is happening. That is the
product's whole premise. Delight is carried by **ambient life that has no state
meaning** — staggered grazing, the farmer pottering the barnyard loop, the woodland —
not by making the common states loud.

### Table

| state | motion | position | colour | prop |
|---|---|---|---|---|
| `idle` | slow eat cycle + rare **short anchored wander**, per-pid phase offset | at the trough, head down | full | trough 0107+0106 |
| `frozen` | **none** — held frame | back of pen | **cool shade ×(0.85, 0.88, 0.96)**, solid | — |
| `active` | walk cycle, traverses the pen | steps **forward**, y-sorted, overlaps bottom rail | full | — |
| `overloaded` | walk + 1px integer bounce | forward | red pulse toward (255,110,85), 0→0.45 @1.2 Hz | **bomb `0105`** over head |
| *needs attention* **(RESERVED)** | hop, ~2 Hz | **at the gate, facing the viewer** | full | **red plate `0095`** over head |

### Why these specific choices

- **Frozen is a cool multiplicative shade, not desaturation and not alpha.** I tried
  all three (`cue_test.png`, `cue_test2.png`). Desaturation *fails*: sheep, chicken and
  the Holstein cow are near-white and have no saturation to remove — only the pig
  changed. Alpha fade reads as broken/absent. Multiplying toward cool blue-grey darkens
  white too, so it works across all four species, and it reads as shadow rather than
  absence. **45% is the tested value**; 30% is invisible on the pig, 60% starts to look
  sickly.
- **Frozen keeps its ground shadow** and its trough. It is present, just resting.
- **Frozen pens are NOT overgrown.** Overgrowth is the right art for a much longer
  dormancy tier if one is ever added; it is wrong for a 10-minute timer.
- **`idle` wander must return to a per-pid anchor point.** Short (≤1 tile), slow, with
  long pauses, always drifting back home. Unanchored wander is the reshuffling
  complaint in slow motion — invisible frame to frame, obvious after five minutes.
  The discriminator against `active` is **amplitude and duty cycle**, not the mere
  presence of motion: `active` is a continuous traverse of the pen.
- **Two props, two meanings.** `0105` (bomb) = *the machine is in trouble*.
  `0095` (red plate) = *a human is needed*. Keeping them distinct means `overloaded`
  still has two channels (colour + prop) while the loudest prop stays unspent.
- **The reserved state faces the viewer.** Rows 0/2 (front/back) are normally banned
  because quadrupeds foreshorten into totem poles — but that is exactly why it works
  here. Breaking the side-view rule is itself the signal: one animal in the whole farm
  is looking at you.

### Open question for you, not for me

The state-model spec says `overloaded` "takes priority over every other state." Whether
*needs attention* will outrank it in that evaluation order is a product call, not an
art call. My ladder assumes it does; if it doesn't, swap the two prop assignments.

### Mechanics

- **Slot assignment is by pid order and never changes with state.** State only applies
  an offset *within* the slot. Do not sort animals by state — an idle→active flip would
  teleport one across the pen, which is the jitter that already got rejected.
- **Facing**: side view only, rows 1 (left) / 3 (right), alternating by slot index.
  The single exception is the reserved attention state.
- **Draw order**: sort by baseline y, back to front. Every animal gets a small dark
  ellipse shadow `rgba(32,62,34,0.31)` for ground contact.
- Pen ground is seeded from `hash(projectPath)` only and never repainted on a state
  change — see the callout in §3.

## 6. Labels

A wooden **nameplate nailed to the top rail**, centred, overlapping the fence so it is
part of the world rather than floating over it:

```
plate height 12px @1×, drawn at 1× then scaled with the rest
outline #45262E (1px), body #BC7A4A, top highlight row #E8AE76
text: uppercase, ink #301A16, 1px inset at (5, 3)
```

- Max plate width = `(penW - 1) * 16` px. Truncate with `…`.
  `FEAT+BODY-TYPE-QUESTIONNAIRE` → `FEAT+BODY-TYPE-Q…` on a 10-wide pen. Test with
  real project names; the short ones hide the problem.
- **A bitmap pixel font is a requirement, not a preference.** Ship **Silkscreen**
  (OFL, ~14 KB) or **Press Start 2P** (OFL). *We do not currently have this asset* —
  it needs adding.
  I tested the alternative and it fails: antialiased glyphs at this size on brown
  wood turn to mush. In my own earlier render `NFQ` read as **NEO** and `DOTFILES`
  as **DOTEILES** — two independent F/E and Q/O confusions on one plate. On a
  monitoring tool that mislabels which project you are looking at, that is a bug.
  The current mockup renders glyphs through a 1-bit threshold mask to simulate a
  true bitmap font; compare `FARM-1` (crisp) against the earlier passes (mush).
- **Plate geometry** (all @1×, scaled with the world): plate height **15px**, text
  baseline inset `(5, 3)` leaving 3px above cap height and **4px below baseline for
  descenders** — `Q`, `g`, `y`, `p` were being clipped at 12px. Minimum cap height
  **7px**. Below that, truncate harder rather than shrinking the font.
- Do **not** use tile `0083` (the small hanging sign) for the name — it is 16×16 and
  cannot hold text. Use it as a signpost prop at the crossroads only.

---

## 7. Assets, licensing, and one blocking finding

### 7a. BLOCKING: the species palette does not match the art we have

`AnimalSpecies` declares **7 cases** — cow, pig, sheep, chicken, horse, llama, goat —
and `AnimalAssignment.species(forCWD:)` does `stableHash(cwd) % 7`.

We have LPC sheets for **4**: cow, pig, sheep, chicken. **Horse and goat have no art
at all. Llama is named in the art brief but is not present in `lpc/`.** Roughly 3 of
every 7 projects currently map to a species that cannot be drawn.

Two options, both need a deliberate decision:

1. **Reduce the palette to the 4 we have.** Cheapest and ships today. But `% 4` instead
   of `% 7` **reassigns every existing project's species once**. The farm-visualization
   spec explicitly requires that a palette change be *"a conscious decision, not an
   accidental reshuffle,"* with a fixed-mapping unit test — so that test needs updating
   in the same commit, and it is worth a one-line note in the release notes.
2. **Source 3 more sheets** to keep `% 7`. The LPC ecosystem plausibly has candidates,
   but **I have not verified that specific horse/goat sheets exist, are CC-BY or CC0,
   and are style-compatible with Eddeland's set** — do not treat that as established.
   Zero budget means CC0/CC-BY only.

Option 1 is my recommendation: 4 species across a dozen pens is plenty of variety, and
the pen *size* already differs per species, which adds silhouette variety for free.

### 7b. BLOCKING BEFORE SHIP: CC-BY attribution

- **Kenney Tiny Town — CC0.** No obligation. Safe in an MIT repo.
- **LPC farm animals (Daniel Eddeland) — CC-BY 3.0.** Attribution is *required in the
  distributed work*, and this is a public MIT repo, so every clone redistributes it.
  Needs: a `THIRD-PARTY-NOTICES.md` at repo root naming the author, the license and the
  source URL, **and** a visible in-app credit (a "Credits" item in the dropdown is
  enough). Note in the README that the repo's MIT license covers the *code*; bundled
  assets keep their own licenses. This is cheap but it is a real obligation, not a nicety.
- **Silkscreen / Press Start 2P — SIL OFL 1.1.** Redistributable and free. Ship
  `OFL.txt` alongside the font, don't sell the font on its own, and don't modify it
  while keeping the Reserved Font Name.

### 7c. Art we do not have (do not assume it)

- No dust/smoke/particle sprites.
- No "Zzz", no speech or emote bubbles.
- No lying-down or sleeping frames — the LPC set is walk + eat only. The `frozen` pose
  is a held eat frame, which is an approximation. Flagging it rather than pretending.
- No tilled-soil furrows. `0043` is grey-flecked gravel; it reads as rubble on grass,
  so I dropped it.
- No water, pond, well, scarecrow, silo, or night/dusk tiles.
- No gate *sprite* — the gate is a 2-tile gap in the rail with `0080`/`0082` end caps,
  which works fine.
- No pixel font in the repo yet (see §6).

### 7d. Room left for what's deferred

- **Fifth state (needs attention).** Reserved slot is specified in §5: gate position +
  viewer-facing frame + `0095` plate. Nothing else uses that combination.
- **Other agents (Codex, Gemini).** Species is already spent on *project*, so the tool
  needs its own channel. Ranked:
  1. **One farmstead per tool.** Group rows by tool; each group gets its own header
     building (barn `0052/0064/0072` red for one, the grey shed set `0048/0060/0076`
     for another) and the groups are separated by a hedgerow. This reuses the existing
     row/lane structure at zero cost and scales to 3–4 tools. My recommendation.
  2. **A marker on the gatepost** — one tile from a small set beside each pen's gate.
     Cheaper, but only a couple of legible options exist in the pack.

## 8. Implementation order

1. Ground fill + clumped variation, grass only. Verify it does not streak.
2. Dirt autotiler + lanes. Verify roads terminate and connect.
3. Layout: pen sizing, row packing, lane assignment. Verify 1 / 8 / 14 pens.
4. Fences + gates + nameplates.
5. Animals: side-view frames, slot lattice, y-sort, shadows.
6. State cues, in this order of value: frozen overgrowth → red pulse → head posture →
   forward/back offset → bounce.
7. Woodland bands + fringe. Do this last; it is pure garnish and it is the part that
   most needs the occupancy set to already be correct.
