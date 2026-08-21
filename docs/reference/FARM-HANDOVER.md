# Farm scene — handover

> **Delivery note:** `SendMessage` is disabled for my session (errors as unavailable,
> in subagents too), so this file is the channel. It's the written half of the four
> PNGs you already have.
>
> **Your file list is one revision stale.** `FARM-1-hero.png` no longer exists — I
> renamed it `FARM-1-typical.png` after changing what it depicts (see §4).
> `watchagents-farm-v1/v2/v3.png` are yours, not mine. Current set is
> `FARM-1-typical`, `FARM-2-fourteen-pens`, `FARM-3-single-pen-3x`,
> `FARM-4-state-cues`, `FARM-5-all-states`, `FARM-6-frozen-shade-test`,
> plus `FARM-ART-SPEC.md` (the long version of this).

Generator: `scratchpad/mock7.py`. `render()` **is** the layout algorithm — port it
directly. `scratchpad/states.py` makes the state key.

---

## 0. Two things that block you before any art question

**0a. The species palette can't be drawn.** `AnimalSpecies` declares 7 cases (cow, pig,
sheep, chicken, horse, llama, goat) and `species(forCWD:)` does `stableHash(cwd) % 7`.
We have LPC sheets for **4**. Horse and goat have **no art at all**; llama is in the art
brief but absent from `lpc/`. ~3 of every 7 projects hash to something unrenderable.

- **Recommended:** cut to the 4 we have. But `% 4` reassigns every existing project's
  species **once**, and the farm-viz spec explicitly requires that be "a conscious
  decision, not an accidental reshuffle" — so update the fixed-mapping test in the same
  commit. Pen *size* already varies by species, so silhouette variety survives.
- **Alternative:** source 3 more sheets. I have **not** verified that CC0/CC-BY,
  style-compatible horse/goat sheets exist. Don't treat that as established.

**0b. CC-BY attribution.** Kenney is CC0 — no obligation. **LPC (Daniel Eddeland) is
CC-BY 3.0**, attribution required *in the distributed work*, and a public MIT repo
redistributes to every cloner. Needs `THIRD-PARTY-NOTICES.md` + an in-app Credits line
+ a README note that MIT covers the *code* while assets keep their own licenses.

---

## 1. Diagnosis — why mockup3 is a dashboard with a grass texture

1. **Same silhouette as the thing it replaces.** Four identical 13×8 rectangles on a
   2×2 grid with a gutter. That's `CURRENT-bad-ui.png` rotated into two columns with
   grass applied. A fence isn't a place; it's a `border-radius` with more pixels.
2. **Occupancy ~3%.** 13×8 = 104 tiles holding 1–3 animals. The reference's chicken run
   is 6×5 = 30 tiles holding 5 birds — sized to its flock. Empty pens read as *loading*.
3. **Uniform noise is not texture.** 90% tile `0000`, then `0001`/`0002` dusted at a flat
   per-tile probability. Uniform random has no clusters, no regions, no direction — it's
   visual static. Real ground has *areas*.
4. **Confetti scenery.** Trees placed one at a time at random spacing; flowers at 5%
   everywhere. Nature clumps. Even distribution reads as noise; clustered reads as
   composition.
5. **No focal point.** The barn is 3×3 in a corner at the same visual weight as a tree,
   connected to nothing. The eye has nowhere to land and nothing to follow.
6. **Everything on one plane.** No overlaps, no shadows, no y-sorting. Kenney tiles have
   baked dark outlines that give objects mass, but nothing occludes anything, so no z.
7. **Inside and outside the fence are the same ground** — so the fence encloses nothing.
8. **Labels are HUD.** Antialiased 16px Arial with a drop shadow over 2×
   nearest-neighbour pixels. Loudest "this is software" signal in the frame.
9. **Wrong sprite rows.** LPC cow front/back views are 27×57–71px — a tall thin totem.
   That's most of why the animals look stupid. Measured side views are 71×43.
   **Side view only, always** (rows 1 and 3).

Your own list had the barn, labels, rigid grid and missing paths. The two it didn't have
are #3/#4 (uniform vs clustered distribution) and #9 (the sprite rows).

---

## 2. Layout spec

### 2.1 Tile grid from window
```
scale = clamp(floor(min(w/320, h/224)), 1, 3)      // 3x only on large windows
COLS  = floor(w / (16*scale)),  ROWS = floor(h / (16*scale))
```
Integer only. Leftover pixels: extend the ground fill (grass `#6EBE5A`).

Margins, in tiles: `MARGIN_L = MARGIN_R = 4`, `MARGIN_T = 3`, `FRAME_B = 4`.
These are woodland, not padding.

### 2.2 Pen size from occupancy
Measured side-view bboxes → footprints:

| species | side bbox | footprint |
|---|---|---|
| cow | 71 × 44 | 5 × 3 |
| sheep | 49 × 39 | 4 × 3 |
| pig | 55 × 30 | 4 × 2 |
| chicken | 31 × 26 | **3** × 2 |

> chicken is widened from the measured 2 on purpose — 2 crowded the slot lattice and
> birds overlapped. Don't "correct" it back.

```
rows      = (n <= 2) ? 1 : 2
cols      = ceil(n / rows)
interiorW = cols * footW + 1
interiorH = footH + (rows - 1) + 1
penW      = max(7, interiorW + 2)     // +2 for the fence ring
penH      = max(5, interiorH + 2)
```
Cap displayed animals at 8; surplus becomes `+N` on the nameplate.

### 2.3 Row packing (deterministic — no reshuffle)
Walk the ordered pen list left→right. Row 0 starts with `BARN_W + GAP + 1` already
consumed — **the barn is literally the first item in the flow**. `GAP = 2`.

Pens in a row are **bottom-aligned** to the row band (`rowH = max(penH)`), so the top
edge is ragged. That alone kills the grid read; don't top-align.

**The wrap test must run even when the row is empty.** My first version had
`if cur && curw + w > avail` — on the first item of a row `cur` is empty, so the check
is skipped and the pen is placed past the barn regardless of window width, off the
right edge.

### 2.4 Lanes
A 2-tile dirt lane between every pair of rows. Row *i* gates **S** onto the lane below;
the final row gates **N** onto the lane above. Lane x-extent is
`[MARGIN_L+1, COLS-MARGIN_R-1]` — it terminates, it does not bleed off the edges.

### 2.5 Fit rule — run before layout
```
minCols = maxPenW + BARN_W + GAP + 1 + MARGIN_L + MARGIN_R
minRows = sum(rowHeights) + 2*laneCount + MARGIN_T + FRAME_B
```
A 2-cow pen (`penW = 13`) gives `minCols = 31` → **1488px min width at 3×, 992 at 2×,
496 at 1×.** Try scale 3→2→1, take the first that satisfies both. If 1× still fails on
width, move the barn to its own row (recovers 10 columns). If it fails on height,
scroll vertically. **Never clip a pen** — clip scenery first, then margins.

### 2.6 Degradation
- **1 pen** → 1 row, no lanes. Barn + pen + spur + woodland. Bump to 3×. (`FARM-3`)
- **8 pens** → 3 rows, 2 lanes. (`FARM-1`)
- **14 pens** → 4 rows, 3 lanes, still glanceable. (`FARM-2`)

---

## 3. Ground, focal point, dead space

### 3.1 Open country
Base grass `0000`. Variation **clumped, not dusted** — this is the single cheapest fix
for #3 in the diagnosis:
```
clump = hash(x/4, y/3, saltA) % 100
local = hash(x, y, saltB) % 100
tile  = 0001 (tufts)   if clump < 24 && local < 55
      = 0002 (flowers) if clump >= 93 && local < 35
      = 0001           if local < 4          // rare loners
      = 0000           otherwise
```

### 3.2 Dirt — one shared autotiled set
Keep a `Set<Point>` of dirt cells; lanes, barnyard apron, gate thresholds and pen wear
all feed the same set, so they connect automatically. Pick per cell:

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

No inner-corner tiles exist in this pack — keep dirt shapes convex-ish; concave notches
fall back to `0025` and look fine.

### 3.3 Pen interiors — worn patch, NOT a dirt floor
Flooring the pen in dirt just swaps dark rounded rects for orange ones. Per pen, dirt =
union of: the 2×2 trough apron (interior bottom-left), the 2×1 threshold inside the
gate, and one irregular standing patch (radius ~2). ~25–35% of the interior; grass
survives in the corners and along the rails.

> **Seeded from `hash(projectPath)` only.** Never from live state or animal position.
> Repainting 40 ground tiles when a session flips would be a bigger visible churn than
> the reshuffling that already got rejected.

### 3.4 Focal point
**Barn, 7×4**, at the head of row 0:
- roof row 1: `0052 0053×5 0054`, with `0055` swapped in at centre (hay-loft window)
- roof row 2: `0064 0065×5 0066`
- wall rows: `0072 0073×5 0075`
- ground row: `0084` windows at ±1 from the ends, double door `0074 0074` at centre

Dirt apron in front, spur down to lane 0. **Farmyard cluster, never scattered singly:**
hay `0093 0093 0094` at the barn's right shoulder, `0116` pitchfork on the left wall,
`0106`/`0107` barrel+bucket, `0130` chest, `0057` mailbox on the lane, `0083` signpost
at the crossroads, `0103` character by the door for scale and life.

### 3.5 Dead space — the canopy-band trick
**The find that fixed the scenery:** `0006 0007 0008` over `0018 0019 0020` (autumn:
`0009 0010 0011` / `0021 0022 0023`) **tile horizontally into a continuous canopy.**
Used as *bands* you get a forest; used as individual trees you get a field of
lollipops. This is the whole difference between my pass 3 and pass 4.

- **Horizontal treeline:** walk the edge in runs of 3–7 columns; each run gets depth
  1–2 bands and a 0–1 tile inset. Ragged, never a straight ribbon.
- **Vertical treeline:** same, runs of 2–6 rows, 2–4 tiles deep.
- **Fringe:** ~30% of columns get a single `0004/0016` (or `0003/0015`) just inside the
  mass, ~14% a bush `0005/0028`. Softens the interface.
- Every band placement tests the occupancy set; if blocked, reduce depth/width. That's
  what keeps trees off pens automatically.
- A band behind the barn nests it into the landscape.
- **Open lawn is allowed and good** — the reference has a big empty middle. What makes
  it not-boring is that it's *framed*. Don't fill it uniformly.
- **Leftover in the last row:** one compact orchard block (trees on a 3-tile lattice
  with alternating row offset — reads as planted, contrasts with wild woods), one hay
  yard, a few bush clumps.

### 3.6 Labels
A wooden **nameplate nailed to the top rail**, centred, overlapping the fence so it's
part of the world:
```
plate 15px tall @1x   outline #45262E (1px)   body #BC7A4A   top highlight row #E8AE76
text uppercase, ink #301A16, inset (5,3): 3px above cap height, 4px below baseline
max width = (penW - 1) * 16 px, truncate with ...
```
- 4px below baseline is not optional — at 12px the `Q` descender clipped and **`NFQ`
  rendered as `NEO`**, `DOTFILES` as `DOTEILES`.
- **A bitmap pixel font is a requirement, not a preference.** Silkscreen or Press
  Start 2P, both OFL, ~14 KB. **We don't have it; it needs adding.** SwiftUI `Text`
  antialiasing turns to mush on brown wood at this size — I tested it, see above.
  Ship `OFL.txt`, don't rename the font. Minimum cap height 7px; below that truncate
  harder rather than shrinking.
- Do **not** use `0083` for the name — it's 16×16 and can't hold text. Signpost only.

---

## 4. What each PNG is

| file | what it is | status |
|---|---|---|
| **`FARM-1-typical.png`** | 8 pens, **the honest state distribution** — 13 idle/frozen, 1 active, 0 overloaded | **CANONICAL TARGET** |
| `FARM-2-fourteen-pens.png` | 14 pens, realistic distribution | canonical, density case |
| `FARM-3-single-pen-3x.png` | 1 pen at 3× | canonical, sparse case |
| `FARM-4-state-cues.png` | 5 cells: the 4 shipping states + the reserved slot | supporting study |
| `FARM-5-all-states.png` | **synthetic** — every state at once | supporting only, **not representative** |
| `FARM-6-frozen-shade-test.png` | frozen treatment trial across all 4 species | supporting study |

Why FARM-1 changed from my earlier "hero": the state-model doc says Claude's work
happens server-side, so local CPU sits near zero and **idle/frozen are the common
states**. A render full of active/overloaded animals flatters the design and lies about
the product. FARM-1 now shows 1 active animal out of 15 — the real test of "is this
pleasant when nothing is happening." It passes.

**`FARM-4` cell 5 (`+ATTENTION`) is a proposal, not a spec'd state.** It's drawn with
the same nameplate as the four shipping ones, so please don't let it get screenshotted
without that caveat.

---

## 5. State cues

### 5.1 Salience budget — read before the table
Ranked by **how much the user needs to act**, which is what salience should track:

| rank | state | frequency | action |
|---|---|---|---|
| 1 | *needs attention* (future) | rare | **act now** |
| 2 | `overloaded` | rare | check your machine |
| 3 | `active` | brief flickers | nothing, but it's the interesting moment |
| 4 | `idle` | **common** | nothing |
| 5 | `frozen` | **common** | nothing — you just haven't typed in 10 min |

**Correction to what I sent you before:** I originally specced `frozen` as 40% alpha +
a weed-choked pen — the most dramatic treatment in the design. That's backwards. If
frozen is common, that renders a farm of translucent ghosts in abandoned lots: a lie
about what the state means, and not something you'd keep in your menu bar. **If you
started building against that, stop.** Frozen now recedes.

### 5.2 Table
| state | motion | position | colour | prop |
|---|---|---|---|---|
| `idle` | slow eat cycle + rare **short anchored wander**, per-pid phase offset | at the trough, head down | full | trough `0107`+`0106` |
| `frozen` | **none** — held frame | back of pen | **cool shade ×(0.85, 0.88, 0.96)**, solid | — |
| `active` | walk cycle, traverses the pen | steps **forward**, y-sorted, overlaps bottom rail | full | — |
| `overloaded` | walk + 1px integer bounce | forward | red pulse toward (255,110,85), 0→0.45 @1.2 Hz | **bomb `0105`** over head |
| *needs attention* **(RESERVED)** | hop ~2 Hz | **at the gate, facing viewer** | full | **red plate `0095`** over head |

### 5.3 How you spot overloaded/frozen in ~1 second across 12 pens
- **Overloaded:** colour. It's the only red thing in a green-and-white scene, plus the
  only bomb. Verify on `FARM-2` — one red sheep out of 20 animals, bottom right; you
  find it before you've read a single label.
- **Frozen:** value. Shaded animals sit visibly darker/cooler than their full-colour
  pen-mates. Works at pen scale without resolving the sprite.
- **Idle vs active in a still frame** (a glance samples one frame, a screenshot has
  none): carried by **head posture** — eat sheet = head down, walk sheet = head up —
  plus **depth**: idle hangs back at the rail, active steps forward ~12px and occludes
  the bottom rail.

### 5.4 Why these specific values
- **Frozen is a cool multiplicative shade, not desaturation and not alpha.** I tried all
  three — `FARM-6`. Desaturation **fails**: sheep, chicken and the Holstein are
  near-white with no saturation to remove, only the pig changed. Alpha reads as
  broken/absent. Multiplying darkens white too, so it works on all four species and
  reads as shadow rather than absence. **45% is the tested value** (30% invisible on
  the pig, 60% looks sickly). Frozen keeps its ground shadow and trough — it's present,
  just resting.
- **Frozen pens are NOT overgrown.** Overgrowth is right for a much longer dormancy tier
  if you ever add one; it's wrong for a 10-minute timer.
- **`idle` wander must return to a per-pid anchor.** Short (≤1 tile), slow, long pauses,
  always drifting home. Unanchored wander is the reshuffling complaint in slow motion —
  invisible frame-to-frame, obvious after five minutes. The discriminator against
  `active` is **amplitude and duty cycle**, not the presence of motion.
- **Don't use playback rate for overloaded.** A 4-frame sheet at 2× is exactly the "fast
  jittery walk" that got called stupid — reads as a defect, not a signal. Colour is the
  strong channel across a dozen pens; rate is weak.
- **Two props, two meanings.** `0105` bomb = *the machine is in trouble*. `0095` red
  plate = *a human is needed*. Keeping them distinct means `overloaded` still has two
  channels (colour + prop) while the loudest prop stays unspent.
- **The reserved state faces the viewer.** Rows 0/2 are normally banned (totem poles) —
  which is exactly why it works: breaking the side-view rule *is* the signal.
  One animal in the whole farm looking at you.

**Open question that's yours, not mine:** the state doc says `overloaded` "takes
priority over every other state." Whether *needs attention* outranks it is a product
call. My ladder assumes it does; if not, swap the two prop assignments.

### 5.5 Mechanics
- **Slot assignment is by pid order and never changes with state.** State applies an
  offset *within* the slot only. Do not sort animals by state — an idle→active flip
  would teleport one across the pen.
- **Facing:** side view only, rows 1 (left) / 3 (right), alternating by slot index.
  Only exception is the reserved attention state.
- **Draw order:** sort by baseline y, back to front. Every animal gets a dark ellipse
  shadow `rgba(32,62,34,0.31)` for ground contact. This is your depth cue — one sort.

---

## 6. Tried and rejected, and where the constraints bite

**Rejected after rendering it:**
- *Full-dirt pen interiors.* Reads as an orange swatch — the same dashboard, recoloured.
- *Frozen = 40% alpha + overgrown pen.* Looks broken, and misrepresents a common benign
  state. (§5.1)
- *Desaturation for frozen.* Fails on white species. (§5.4)
- *Scattering individual trees to fill space.* Confetti. Canopy bands instead. (§3.5)
- *Tile `0043` as a crop bed.* It's grey-flecked gravel; reads as rubble on grass.
- *State-sorted animal slots.* Reintroduces teleporting on every state flip.
- *Uniform value-noise for grass variation.* Produced visible diagonal streaks; the
  coarse-cell + local-hash form in §3.1 doesn't.

**Where the constraints force a compromise you should know about:**

1. **The cow is 4.4 tiles wide.** LPC side-view cow is 71px against a 16px tile. A 2-cow
   pen is 13 tiles wide, which is what drives the 1488px-at-3× minimum window. You
   can't downscale pixel art at non-integer ratios, so this is structural. Mitigation is
   y-sorted depth stacking — animals stand at different depths and partially overlap, so
   pens don't grow linearly with occupancy.
2. **No inner-corner dirt tiles.** Dirt blobs must stay convex-ish. Concave notches fall
   back to `0025` — acceptable, but don't build S-bend paths.
3. **No lying-down or sleeping frames.** LPC is walk + eat only. The `frozen` pose is a
   held eat frame. It's an approximation and I'm flagging it rather than pretending.
4. **No particles, no Zzz, no emote bubbles, no water/pond/well/scarecrow/silo, no
   night tiles.** Every state cue above is built from tint, position, held frames and
   existing prop tiles — nothing needs new art except the font.
5. **Text can't sit on the pixel grid via SwiftUI `Text`.** Hence the bitmap-font
   requirement (§3.6). The mockup fakes it with a 1-bit threshold mask; you can't do
   that in `Canvas`, so bundle the font.
6. **`Canvas` + `TimelineView` is fine for all of this** — everything reduces to "draw
   these sprites at these positions this frame", one y-sort, and a per-sprite colour
   multiply. No pathfinding: the idle wander is a 1-tile anchored oscillation and the
   active walk is a fixed traverse, both pure functions of `(pid, time)`.

---

## 7. Build order
1. Ground fill + clumped variation, grass only. Check it doesn't streak.
2. Dirt autotiler + lanes. Check roads terminate and connect.
3. Layout: pen sizing, row packing, lane assignment, **fit rule**. Verify 1 / 8 / 14.
4. Fences + gates + nameplates (font first).
5. Animals: side-view frames, slot lattice, y-sort, shadows.
6. State cues, in value order: cool shade for `frozen` → red pulse for `overloaded` →
   head posture → forward/back offset → props → bounce. **Anchor the idle wander before
   you ship it, not after.**
7. Woodland bands + fringe. **Last** — it's garnish and it depends on the occupancy set
   already being correct.
