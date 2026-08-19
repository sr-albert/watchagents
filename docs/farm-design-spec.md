# Farm Scene — Implementation Spec

Source of truth for the renderer. All numbers are in **tiles** (16px) or **1× pixels**
unless stated. Reference implementation: `docs/reference/mock7.py` — `render()` is this
algorithm; `docs/reference/states.py` renders the state key. Both were written in a
throwaway scratch directory and vendored here so the pointer survives the session that
made it; they are documentation, not part of any build target.

---

## 0. STOP — two corrections before you write code

### 0a. Your reverse-engineered state cues are one revision stale

You listed: *"overloaded = red pulse + 1px bounce + plate 0095 badge; frozen = held
still, 40% faded blue-grey, pen overgrown with mushrooms."* That is the **old**
FARM-4. I changed both after the product context landed. Current:

| | you have (stale) | **build this** |
|---|---|---|
| overloaded badge | plate `0095` | **bomb `0105`** |
| frozen colour | 40% alpha, blue-grey fade | **cool multiply, no alpha change** |
| frozen pen | overgrown + mushrooms | **normal pen, no overgrowth** |

**Why frozen changed.** The state-model doc says Claude's work happens server-side, so
local CPU sits near zero and **`idle`/`frozen` are the common states, not exceptions**.
The old treatment put the most dramatic art in the design on the least actionable,
most common signal — rendering a farm of translucent ghosts standing in abandoned lots.
Wrong about what the state means, and not something anyone keeps in a menu bar.

**Why the badge changed.** `0095` (red plate) is now **reserved** for the future
"needs attention" state, which must out-shout everything. `0105` (bomb) reads as
*machine in trouble*; `0095` reads as *a human is needed*. Keeping them distinct means
`overloaded` still has two channels while the loudest prop stays unspent.

Re-open `FARM-4-state-cues.png` — it now has five cells and says "cool SHADE 45% (not
faded)".

### 0b. `AnimalSpecies` can't be drawn

`AnimalSpecies` declares 7 cases (cow, pig, sheep, chicken, horse, llama, goat);
`species(forCWD:)` does `stableHash(cwd) % 7`. **We have LPC sheets for 4.** Horse and
goat have no art at all; llama is in the art brief but absent from `lpc/`. ~3 of every
7 projects hash to something unrenderable.

Recommended: cut the enum to the 4 we have. `% 4` **reassigns every project's species
once** — the farm-viz spec requires that be "a conscious decision, not an accidental
reshuffle", so update the fixed-mapping test in the same commit.

Also: **LPC is CC-BY 3.0.** Public MIT repo ⇒ attribution required in the distributed
work. Needs `THIRD-PARTY-NOTICES.md` + an in-app Credits line + a README note that MIT
covers the code while assets keep their own licenses. Kenney is CC0, no obligation.

---

## 1. Constants

```
T            = 16            // tile px
MIN_MARGIN   = 1             // tiles; the side band pens are ALWAYS packed against
MIN_V_MARGIN = 2             // ditto above/below — see §2.6 for why it is not 1
SLACK_SPLIT  = 3:4           // top:bottom share of the leftover (see §2.6)
GAP          = 2             // tiles between pens in a row
LANE_H       = 2             // dirt lane height
BARN_W, BARN_H = 7, 4
GRASS_BG     = #6EBE5A
```

Scale selection:
```
for s in [3, 2, 1]:
    COLS = floor(winW / (16*s));  ROWS = floor(winH / (16*s))
    if layoutFits(COLS, ROWS): use s
else: use 1 and scroll vertically
```
Integer scale only. Leftover pixels: extend the ground fill, do not letterbox.

---

## 2. Layout algorithm

### 2.1 Pen size from occupancy

Footprints, from measured LPC **side-view** bboxes:

| species | side bbox | footprint (tiles) |
|---|---|---|
| cow | 71 × 44 | 5 × 3 |
| sheep | 49 × 39 | 4 × 3 |
| pig | 55 × 30 | 4 × 2 |
| chicken | 31 × 26 | **3** × 2 |

> chicken is deliberately widened from the measured 2 — at 2 the slot lattice crowded
> and birds overlapped. Do not "correct" it back.

```
n         = min(animalCount, 8)          // surplus shown as "+N" on the sign
rows      = (n <= 2) ? 1 : 2
cols      = ceil(n / rows)
interiorW = cols * footW + 1
interiorH = footH + (rows - 1) + 1
penW      = max(7, interiorW + 2)        // +2 = fence ring
penH      = max(5, interiorH + 2)
```

Worked examples: 1 cow → 8×6. 2 cows → 13×6. 1 pig → 7×5. 4 chickens → 9×6.

### 2.2 Row packing

Walk pens in the existing deterministic order (path, then pid). Never sort by state.

```
avail = COLS - 2*MIN_MARGIN
curW  = BARN_W + GAP + 1            // row 0 starts with the barn's slot consumed
for pen in pens:
    if curW + pen.w > avail && (row.notEmpty || curW > 0):
        rows.append(row); row = []; curW = 0
    row.append(pen); curW += pen.w + GAP
```

**The wrap test must run even when the row is empty.** My first version guarded it with
`if row.notEmpty` — on the first pen of row 0 the row is empty, so the check is skipped
and the pen lands past the barn regardless of window width, off the right edge.

Vertical placement:
```
y = MIN_V_MARGIN
for each row:
    rowH = max(pen.h for pen in row)
    x = MIN_MARGIN + (rowIndex == 0 ? BARN_W + GAP + 1 : 0)
    for pen in row:
        pen.origin = (x, y + (rowH - pen.h))     // BOTTOM-ALIGNED
        x += pen.w + GAP
    y += rowH + LANE_H
```

**Bottom-align pens within the row.** Different pen heights then produce a ragged top
edge. This single line does more to kill the "dashboard" read than anything else.

`BARN_X = MIN_MARGIN`, `BARN_Y = row0.y + row0.h - BARN_H` — both before centring (§2.6).

### 2.3 Lanes and gates

One 2-tile dirt lane between every pair of rows: `laneY[i] = row[i].y + row[i].h`.

```
gate side: row i gates "S" onto laneY[i]  if i < rowCount-1
           last row gates "N" onto laneY[i-1]
gate x   : gx = pen.x + pen.w / 2        // 2-tile gap at gx-1, gx
```

Lane extent: `x ∈ [MARGIN_L+1, COLS-MARGIN_R-1]`. It terminates; it does not bleed off
the edges.

### 2.4 Fit rule
```
minCols = maxPenW + BARN_W + GAP + 1 + 2*MIN_MARGIN
minRows = Σ rowH + 2*laneCount + 2*MIN_V_MARGIN
```

**Both are measured against `MIN_MARGIN`, never against a roomier band.** The margins are
slack (§2.6), so a scale may only ever be rejected because the *pens* don't fit. Testing
the fit against a fixed 4/3/4 margin instead is what "clip scenery first, then scroll"
below is meant to prevent, and skipping that rung is a real bug we shipped: a five-pen
farm needed 28 rows at 2× in a window of 27 — **one row** — and so rendered at 1×, half
the tile size, with the farm using a quarter of its window. Seven of those 28 rows were
scenery band. Note the cliff, not just the case: a 57px change in window height flipped
the whole scene between 1× and 2×.
A 2-cow pen (`penW=13`) ⇒ `minCols = 25` ⇒ **1200px minimum width at 3×, 800 at 2×,
400 at 1×**. If 1× still fails on width, move the barn to its own row (recovers 10
columns). If it fails on height, **scroll vertically**.

**Never clip a pen.** The ladder is: give up scenery band (that is what §2.6 packing
against the minimum *is*), then a scale, then scroll.

### 2.5 Measured capacity

| pens | window | scale | result |
|---|---|---|---|
| 1 | 512×320 | 3× | 1 row, no lanes. Barn + pen + spur + woodland |
| 3 | 1472×960 | 2× | 2 rows, 1 lane |
| 8 | 1472×960 | 2× | 3 rows, 2 lanes — **`FARM-1`** |
| 12 | 1472×960 | 2× | needs 37 rows, has 30 → **drop to 1×** |
| 14 | 1664×1280 | 2× | 4 rows, 3 lanes — **`FARM-2`** |
| 30 | 1472×960 | 1× | 4 rows, 3 lanes — fits |
| 30 | 1104×720 | 1× | needs 53 rows, has 45 → **scroll** |

Rule of thumb: 2× comfortably holds ~8–9 pens in a 1472×960 window. Scale is the
primary lever; scrolling is the last resort.

### 2.6 Elastic margins — the packing is centred, not the margins padded

Everything above packs into the top-left against `MIN_MARGIN`. Then measure what it came
to and slide the whole thing into the middle:

```
contentW = max(pen.x + pen.w for pen) ∪ (BARN_X + BARN_W)  −  MIN_MARGIN
contentH = lastRow.y + lastRow.h  −  MIN_V_MARGIN
slack    = ROWS - contentH

MARGIN_L = max(MIN_MARGIN, (COLS - contentW) / 2)
MARGIN_R = max(MIN_MARGIN, COLS - contentW - MARGIN_L)
MARGIN_T = max(MIN_V_MARGIN, min(slack * 3/7, slack - MIN_V_MARGIN))   // SLACK_SPLIT

dx = MARGIN_L - MIN_MARGIN ;  dy = MARGIN_T - MIN_V_MARGIN  // translate pens, lanes, barn
```

**Slide a finished packing; never pack against the grown margins.** Growing them first
shrinks `avail`, re-wraps pens into more rows, and breaks the fit the caller just proved
at this scale.

The 3:4 vertical share is the proportion the old fixed `MARGIN_T`/`FRAME_B` had, and the
inner `min` stops it spending ground the bottom band still needs.

**`MIN_V_MARGIN` is 2 where `MIN_MARGIN` is 1, and the two must not be merged.** At one
tile a 30-pen farm put the first row's top rail and the last row's bottom rail ~10px from
the window edge, and the field read as cut off instead of continuing past it. The sides
don't shear the same way: a row that fills its width ends in pens of differing widths, so
that edge is ragged already. Raising *both* to 2 fixes the top and bottom and then takes
two columns off every row's packing budget — `MIN_MARGIN` is what `avail` is measured
against — which wraps pens into more rows and pushes layouts back down a scale: a farm of
eight 4-cow pens went from 47 rows to 74 at 2×. That is the harm this whole rung exists
to undo, so the sides stay at 1.

`MARGIN_L`/`MARGIN_R`/`MARGIN_T` are **outputs of the layout**, so anything positioned
against the field's edge — lane extent (§4.2), hedge shoulders (§6.3), the empty farm's
barn — reads them from the layout. Nothing may assume a fixed inset. An empty farm has
`contentW = BARN_W`, which stands its lone barn in the middle of the field.

---

## 3. Pen anatomy

```
pen rect      = (x, y, penW, penH)          // includes the fence ring
interior      = (x+1, y+1, penW-2, penH-2)  // ix, iy, iw, ih
IX,IY,IW,IH   = interior in pixels
```
Minimum pen: **7 × 5** (interior 5 × 3). Interior padding for sprites: 2px left/right,
1px top (see §3.4 clamps).

### 3.1 Fence tiles

| position | tile |
|---|---|
| top-left corner | `0044` |
| top-right corner | `0046` |
| bottom-left corner | `0068` |
| bottom-right corner | `0070` |
| horizontal rail | `0081` |
| vertical rail | `0047` |
| rail end, left cap | `0080` |
| rail end, right cap | `0082` |

Gate = 2-tile gap at `gx-1, gx` on the gated rail; the two cells get `0082` (at gx-1)
and `0080` (at gx) so the rail ends cleanly. There is no gate sprite in the pack; this
reads correctly.

### 3.2 Sign mount

Nailed to the **top rail**, centred, overlapping it. All @1×:
```
plateH   = 15
plateW   = textWidth + 9
x0       = (pen.x + penW/2)*16 - plateW/2
y0       = pen.y*16 + 14 - plateH
outline  #45262E   1px, drawn as a rect 1px larger on all sides
body     #BC7A4A
highlight#E8AE76   1px row at y0+1
text     #301A16   uppercase, drawn at (x0+5, y0+3)
```
3px above cap height, **4px below baseline**. Not optional — at `plateH=12` the `Q`
descender clipped and **`NFQ` rendered as `NEO`**, `DOTFILES` as `DOTEILES`.

Truncation: `maxPx = (penW - 1) * 16`, truncate and append `…`.
`FEAT+BODY-TYPE-QUESTIONNAIRE` → `FEAT+BODY-TYPE-Q…` on a 10-wide pen.

**Bundle a bitmap pixel font** — Silkscreen or Press Start 2P, both OFL, ~14 KB. This
is a requirement, not a preference: SwiftUI `Text` antialiasing turns to mush on brown
wood at this size (that's what produced NEO/DOTEILES). Ship `OFL.txt`, don't rename.
Minimum cap height 7px; below that truncate harder rather than shrinking the font.
Do **not** use tile `0083` for the name — it's 16×16 and can't hold text (signpost only).

### 3.3 Trough

Every pen, no exceptions (including frozen):
```
0107 (bucket) at (ix,   iy+ih-1)
0106 (barrel) at (ix+1, iy+ih-1)
```

### 3.4 Animal placement inside a pen

Slot lattice — **index is by pid order and never changes with state**:
```
wmax  = max sprite width in this pen
hmax  = max sprite height
ncols = max(1, min(count, IW / (wmax + 4)))
nrows = ceil(count / ncols)
depth = (hmax < 34) ? 11 : 8        // px of y separation between ranks
span  = IW - 6
slot  = span / ncols

for i, animal:
    col  = i % ncols;  row = i / ncols
    rank = nrows - 1 - row          // rank 0 = frontmost
    bx   = IX + 3 + col*slot + (slot - w)/2
    by   = IY + IH - 1 - rank*depth
```
Then apply the **state offset within the slot** (§5.3), then clamp:
```
bx = clamp(bx, IX + 2, IX + IW - w - 2)
by = clamp(by, IY + h + 1, IY + IH + 8)
```
`by` is the sprite **baseline** (feet); draw the image at `(bx, by - h)`.

Overlap avoidance is the lattice plus `depth`, not collision resolution. Animals in
different ranks *may* overlap slightly — that's the intended depth cue, resolved by
the y-sort (§5.4). The `+8` in the `by` clamp lets front-rank animals overlap the
bottom rail, which is the depth read.

---

## 4. Ground

### 4.1 Grass — clumped, not dusted

```
clump = hash(x/4, y/3, SALT_A) % 100
local = hash(x, y, SALT_B) % 100
tile  = 0001  if clump < 24  && local < 55     // tufts
      = 0002  if clump >= 93 && local < 35     // flowers
      = 0001  if local < 4                     // rare loners
      = 0000  otherwise
```
The coarse `clump` term is what makes variation form *regions*. A flat per-tile
probability (what mockup3 did) is visual static. Use FNV-1a, not `Hasher` — same
reseeding problem as the species hash.

### 4.2 Dirt — derived, not authored

Dirt is **computed from pen positions**, never hand-placed. Build one
`Set<Point>` from four sources, then autotile the whole set in one pass so everything
connects automatically:

1. **Lanes** — `rect(MARGIN_L+1, laneY, avail-2, 2)` for each lane.
2. **Barn spur + apron** — `rect(BARN_X+2, BARN_Y+BARN_H, 3, laneY[0]-(BARN_Y+BARN_H))`
   and `rect(BARN_X+1, BARN_Y+BARN_H, 5, 2)`.
3. **Gate threshold** — from the gate to its lane:
   `S: for yy in (pen.y+penH-1 ..< laneY): add (gx-1,yy),(gx,yy)`
   `N: for yy in (laneY+2 ..< pen.y+1): same`
4. **Pen wear** (§4.3).

### 4.3 Pen wear — worn patch, NOT a dirt floor

Flooring the interior in dirt just swaps dark rounded rects for orange ones — the same
dashboard, recoloured. Per pen, union of:
```
trough apron : (ix,iy+ih-1) (ix+1,iy+ih-1) (ix,iy+ih-2) (ix+1,iy+ih-2)
gate inside  : (gx-1, gy) (gx, gy)     gy = iy+ih-1 for S gates, iy for N
standing patch: cx = ix + 2 + rand(iw-4);  cy = iy + rand(ih-1)
                for dy in -1...1, dx in -2...2:
                    if |dx| + 2*|dy| <= 2 + rand(2): add (cx+dx, cy+dy)
```
Clip to the interior. Target ~25–35% coverage; grass survives in corners and along
the rails.

> **Seed `rand` from `hash(projectPath)` only.** Never from live state or animal
> position. Repainting ~40 ground tiles when a session flips would be a bigger visible
> churn than the per-frame reshuffling that was already rejected.

### 4.4 Dirt autotiler

For each dirt cell, test whether each 4-neighbour is **absent** from the dirt set:

| N free | S free | W free | E free | tile |
|---|---|---|---|---|
| ✓ | | ✓ | | `0012` |
| ✓ | | | ✓ | `0014` |
| | ✓ | ✓ | | `0036` |
| | ✓ | | ✓ | `0038` |
| ✓ | | | | `0013` |
| | ✓ | | | `0037` |
| | | ✓ | | `0024` |
| | | | ✓ | `0026` |
| | | | | interior fill ↓ |

Interior fill, `r = hash(x,y,SALT_C) % 100`:
`0025` if r<70, `0039` if r<80, `0040` if r<88, `0041` if r<94, else `0042`.

**There are no inner-corner tiles in this pack.** Keep dirt shapes convex-ish; concave
notches fall back to `0025` and look fine. Don't build S-bend paths.

---

## 5. State cues

### 5.1 Salience budget

Ranked by **how much the user must act** — that's what salience should track:

| rank | state | frequency | action |
|---|---|---|---|
| 1 | *needs attention* (future) | rare | **act now** |
| 2 | `overloaded` | rare | check your machine |
| 3 | `active` | brief flickers | nothing, but it's the interesting moment |
| 4 | `idle` | **common** | nothing |
| 5 | `frozen` | **common** | nothing — you just haven't typed in 10 min |
| 6 | `dormant` | **common** | nothing — it is asleep in the barn, and out of the scene |

`dormant` is the only cue here that *reduces* what is on screen. At rest it adds no
colour, no motion and no badge — it takes an animal out of the pens entirely. That is why
it can be common without violating the budget above. (The transition into that state is
its own brief cue, covered in §5.2's table — this paragraph is about the resting barn
state, not the walk that gets it there.)

The scene must stay pleasant when nothing is happening — that's the product's premise.
Delight comes from **ambient life with no state meaning** (staggered grazing, the
farmer's barnyard loop, the woodland), not from making common states loud.

**The feed gauge is not in this table, and that is deliberate.** The ranking above
scores *per-session* states — how urgently one animal needs you. The gauge (§6.1) is a
*whole-farm* reading: three bales and a vat describing the current usage block, not any
one pid. It has nothing to compete for rank against, because it is not answering the
question this table answers.

It is also silent at every level, the same way `dormant` is silent at rest: no motion,
no colour shift, no badge, whether the third bale just came down or the vat just topped
out. That silence is structural, not a restraint someone could loosen later — the gauge
is baked into the cached static layer, which by construction cannot animate. So
it can never out-rank `overloaded` for attention the way a badge or a pulse would; the
only thing it is allowed to say is what is already standing or filled on the ground.

### 5.2 Table

| state | motion | position | colour | prop |
|---|---|---|---|---|
| `idle` | slow eat cycle + rare short **anchored** wander, per-pid phase offset | at the trough, head down | full | trough |
| `frozen` | **none** — held frame | back of pen | **cool multiply** | — |
| `dormant` | 3s walk to the gate, then **absent** | in the barn | cool multiply (as `frozen`) | — |
| `active` | walk cycle, traverses the pen | forward, overlaps bottom rail | full | — |
| `overloaded` | walk + 1px integer bounce | forward | **red pulse** | **bomb `0105`** |
| *needs attention* **(RESERVED)** | hop ~2 Hz | **at the gate, facing viewer** | full | **plate `0095`** |

### 5.3 Exact values

**Frozen — cool multiply, `k = 0.45`, alpha untouched:**
```
mr = 1 - 0.34*k = 0.847
mg = 1 - 0.26*k = 0.883
mb = 1 - 0.08*k = 0.964
out = (r*mr, g*mg, b*mb, a)          // a UNCHANGED
```
Frozen keeps its ground shadow and trough. It is present, just resting.

> Desaturation was tried and **fails**: sheep, chicken and the Holstein cow are
> near-white and have no saturation to remove — only the pig changed. Alpha fade was
> tried and reads as broken/absent. Multiplying darkens white too, so it works across
> all four species and reads as shadow. 45% is the tested value: 30% is invisible on
> the pig, 60% looks sickly. See `FARM-6-frozen-shade-test.png`.

**Dormant — the frozen multiply, unchanged:**

`dormant` reuses `frozen`'s exact tint. Not a deeper shade: two states separated only by
how dark they are cannot be told apart side by side, and §7 already rejected alpha fade
for reading as broken. Dormancy is said by *location* — the animal is in the barn — so the
shade only has to say "resting", which this value already says across all four species.

Escalation: `idle` → `frozen` (10 min of idle CPU) → `dormant` (4h of terminal idle, *and*
still frozen). The second condition is load-bearing: without it a session running a long
autonomous task while you are away would be filed into the barn.

4h is the default, not a fixed constant: it is `FarmSettings.dormantAfterHours`,
user-adjustable from the barn.

**Overloaded — red pulse, `amt` oscillating `0 → 0.45` at 1.2 Hz:**
```
r' = r + (255 - r) * amt
g' = g * (1 - amt*0.8)
b' = b * (1 - amt*0.9)
a' = a
```
(at `amt = 0.40`: `g *= 0.68`, `b *= 0.64`)
Plus a 1px **integer** vertical bounce. Keep walk playback near normal rate.

**Badge:** tile `0105`, drawn at `(bx + w/2 - 8, by - h - 13)` — horizontally centred
on the sprite, 13px above the sprite's top edge. Drawn last, above all sprites.

**Reserved (needs attention):** identical geometry, tile `0095`, offset `-15`.

**Position offsets**, applied within the slot, `off = max(4, h/6)`:
```
idle       : by -= off
frozen     : by -= off + 2 ;  bx += 4
active     : by += off     ;  bx += off
overloaded : by += off - 2 ;  bx += off - 2
attention  : by += off + 4          // at the gate
```

**Shadow:** ellipse `(cx - sw/2, by - 4) → (cx + sw/2, by + 2)`, `sw = w * 0.6`,
fill `rgba(32, 62, 34, 0.31)`. Every animal including frozen.

**Frames:** `eat` sheet col 2 for `idle`, `eat` col 3 for `frozen`, `walk` for
`active`/`overloaded`. Rows **1 (left) and 3 (right) only**, alternating by slot index.
Rows 0/2 are banned — quadruped front/back views are 27×57–71px, tall thin totems, and
are most of why the shipped animals looked wrong. The single exception is the reserved
attention state, where facing the viewer *is* the signal.

### 5.4 Draw order

Sort every sprite by baseline `y`, back to front, then draw. One sort. This is the
depth cue: front-rank and `active` animals occlude the bottom rail and each other.
Badges draw after all sprites.

### 5.5 Spotting it in ~1 second across a dozen pens

- **Overloaded** → colour. The only red thing in a green-and-white scene, plus the only
  bomb. Verify on `FARM-2`: one red sheep among 20 animals, found before you read a
  single label.
- **Frozen** → value. Shaded animals sit visibly darker/cooler than pen-mates. Reads at
  pen scale without resolving the sprite.
- **idle vs active in a still frame** → **head posture** (eat sheet = head down, walk
  sheet = head up) plus **depth** (idle hangs back, active steps forward ~12px and
  overlaps the rail). A glance samples one frame and a screenshot has none, so
  motion-vs-static alone is not enough.

### 5.6 Idle wander — anchor it

Short (≤1 tile), slow, long pauses, **always returning to a per-pid anchor point**.
Unanchored wander is the reshuffling complaint in slow motion: invisible frame-to-frame,
obvious after five minutes. The discriminator against `active` is **amplitude and duty
cycle**, not the presence of motion — `active` is a continuous traverse of the pen.

### 5.7 Open question — RESOLVED

The state-model doc says `overloaded` "takes priority over every other state." Whether
*needs attention* outranks it in that evaluation order is a product call.

**Decision (Albert, 2026-08-15): yes — *needs attention* outranks `overloaded`.** A
session waiting on the human is more urgent than a busy machine. The ladder in §5.1
stands as written, and the badge assignments stay as specified: `0095` (red plate)
reserved for *needs attention*, `0105` (bomb) for `overloaded`. When the fifth state is
implemented, `SessionStateEvaluator.evaluate` must check it **before** the overload
branch.

---

## 6. Focal point and scenery

### 6.1 Barn — 7 × 4 at the head of row 0

```
roof row 1 : 0052  0053 ×5  0054      // 0055 replaces centre = hay-loft window
roof row 2 : 0064  0065 ×5  0066
wall rows  : 0072  0073 ×5  0075
ground row : 0084 at x+1 and x+w-2 ; 0074 0074 at centre (double door)
```
Farmyard cluster — **always clustered, never scattered singly**: `0094` beehive at the
barn's right shoulder, `0116` pitchfork on the left wall, `0106`/`0107`
barrel+bucket, `0057` mailbox on the lane, `0083` signpost at the
crossroads, `0103` character by the door for scale and life. The right shoulder also
carries the feed gauge (below): three `0093` bales stacked in the column the hay pair
used to occupy, and the relocated `0130` two columns over, with the barrel's column
sitting between them — no longer a chest, but the vat the gauge's fill is painted into.

**Two of those tiles are now a gauge, not decoration.** The bales and the vat are
mirrors of each other, and deliberately asymmetric about which way they round: the three
`0093` bales `ceil` over what *remains* of the block's *token* ceiling, so a single
remaining token still leaves one standing; the vat `floor`s over what is *spent* of a
separate *dollar* ceiling, so a cent short of the ceiling is not yet a full vat. Both
divide by thirds, one bale or one vat-row per third. The relocated `0130` is the vat's
empty tile; its fill is painted over it, not drawn as new art (§7 compromise 4 has the
byte-equality proof). `0094` beehive, `0106`/`0107` barrel+bucket and `0116` pitchfork
keep doing exactly what they
always did — pure decoration, no reading required. The split exists so the corner still
looks like a farmyard corner and not an instrument panel: two props start meaning
something, and the rest of the cluster stays exactly as busy and as legible as before.

The four gauge cells are reserved at the barn's own buffer (`FarmScenery.swift:129`),
the same place and mechanism as the barn footprint itself. That reservation does **not**
keep pens off the cluster — pen positions are already fixed by `FarmLayoutEngine.layout`
before this scenery pass runs at all, so nothing here could move a pen even if it tried.
What it actually protects the four cells from is the *other* scenery passes that run
later in the same function: the seeded mushroom scatter and the last-row hay yard
(§6.3), both of which test the same occupancy set this reservation feeds. `gaugeProps`
carries its own, separate pen-collision check — that is what actually keeps the gauge
off a pen, and it is why the whole cluster is withheld together rather than half-drawn:
a bale or the vat quietly failing to appear because it landed on a pen would read as
spent budget, and the gauge cannot afford that lie — the same reason it returns no props
at all for missing usage data rather than a zeroed set. Absent and empty have to stay
visually distinct.

The two ceilings behind the bales and the vat are not private to this corner. They are
the same `tokenCeiling`/`dollarCeiling` that `FarmSettings` seeds once from your
heaviest recorded block and then freezes, editable from the barn's settings.
`tokenCeiling` is also the denominator behind four other readouts: the always-visible
**menu-bar percentage**, the dropdown's progress bar and label, the storehouse, and the
info panel. `dollarCeiling` has no such reach — it is the vat's denominator and nothing
else's. Five places reading `tokenCeiling` is the point — one configured ceiling, not
several that can quietly drift apart — and the vat is the one place that reads a second,
independent number instead.

### 6.2 Tree stands — the rule that makes scenery deliberate

> **CORRECTION, SUPERSEDED (2026-08-16).** This spec twice recorded that the canopy
> band tiled from `0006 0007 0008` over `0018 0019 0020` "reads upside down", and
> retired those tiles as unusable forest-interior art. **That diagnosis was wrong.**
> The band read upside down because *the renderer drew every tile in the static layer
> upside down* — a y-axis flip in the cached-layer path, fixed in commit `0801ade`
> ("Stop the static layer drawing every tile upside down"). Trees, canopy, barn and
> grass were all inverted; the canopy band was simply the one place where inversion
> produced a shape recognisable enough to notice.
>
> So: `0006`–`0008`, `0018`–`0020`, `0009`–`0011` and `0021`–`0023` are **not** known-bad
> art. They are **untested since the flip fix** and currently unused. `docs/reference/
> trees-fixed.png` is a post-fix render of the woodland and shows a correct forest frame.
> Whether to restore the woodland — reverting `ac4f57b`, and possibly part of `370893b`
> — is an open decision for the user, who has twice asked for *fewer* trees. Do not
> restore it unprompted, and do not repeat the "bad art" diagnosis: the art was never
> the problem.
>
> The rule below still stands on its own merits — dense stands of the 2-tall single
> tree have an unambiguous silhouette regardless — and is what the code builds today.

Woodland is built from **dense stands of the 2-tall single tree** — `0004` over `0016`
(autumn: `0003` over `0015`) — at 1-tile spacing, drawn **back to front** so canopies
overlap and hide the trunks behind them. A single tree has an unambiguous silhouette
(canopy on top, trunk at the bottom) and cannot read upside down at any density.

```
stand(x0, x1, y0, y1, seed, density = 0.80, autumn = 0.18, ramp):
    items = []
    for rowIndex, y in enumerate(y0 ..< y1):
        d = density * ramp[min(rowIndex, ramp.count-1)]
        for x in x0 ..< x1:
            h = hash(x, y, seed)
            if h % 100 >= Int(d * 100) { continue }
            yy = y + ((h >> 7) % 2)                  // 1-tile vertical jitter
            if !clear(x, yy, w: 1, h: 2) { continue }
            mark(x, yy + 1, w: 1, h: 1)              // reserve the TRUNK ONLY,
                                                     // so canopies may nest
            items.append((yy, x, (h >> 13) % 100 < Int(autumn * 100)))
    for (y, x, isAutumn) in items.sorted(by: y) {    // BACK TO FRONT
        draw 0003/0004 at (x, y);  draw 0015/0016 at (x, y+1)
    }
```

**`mark` the trunk cell only, not the whole 1×2.** Reserving both rows prevents trees
from nesting and collapses the mass back into evenly-spaced lollipops — which is the
original mockup3 failure.

**The density ramp is what makes the treeline ragged** — dense at the outer edge,
thinning inward, instead of a solid ribbon:
```
RAMP = (1.0, 0.85, 0.55, 0.30)      // indexed from the OUTER edge inward

stand(0, COLS, 0, MARGIN_T,                       ramp: RAMP)              // top
stand(0, COLS, ROWS-FRAME_B, ROWS-1,              ramp: RAMP.reversed())   // bottom
stand(0, MARGIN_L-1, MARGIN_T, ROWS-FRAME_B,      density: 0.72)           // left
stand(COLS-MARGIN_R+1, COLS, MARGIN_T, ROWS-FRAME_B, density: 0.72)        // right
stand(BARN_X-1, BARN_X+BARN_W+1, BARN_Y-2, BARN_Y, density: 0.75)          // copse
```

> Written when the margins were fixed at 4/3/4. They are now the layout's leftover
> (§2.6), so read them from the layout and take `FRAME_B` as `ROWS - MARGIN_T - contentH`.
> A band that used to be 3–4 tiles can now be a dozen, which is worth looking at before
> restoring any of this.

Every placement tests the occupancy set first, which keeps trees off pens automatically
and produces the ragged pen/woodland interface for free.

**Fringe** — softens the inner edge further, per column: `hash % 100 < 30` → one extra
tree; `< 44` → a bush (`0005`/`0028`).

### 6.3 Keeping the middle neither empty nor noisy

- **Open lawn is correct and intended.** The reference has a big empty middle. What
  makes it not-boring is that it's *framed*. Do not fill it uniformly — that's what
  made mockup3 read as confetti.
- **Leftover in the last row** gets three *clustered* features, not a sprinkle:
  1. a compact **orchard block** — trees on a 3-tile lattice with alternating row
     offset, so it reads as *planted* and contrasts with the wild treeline;
  2. a **hay yard** — `0093 0093` / `0094 0093` in a 2×2;
  3. 5–10 bush clumps (`0005`/`0028`/`0027`) via seeded scatter.
- **Hedge shoulders** — ~12 bushes scattered along each lane's edge rows. Gives roads
  edges instead of letting them bleed into lawn.
- Mushrooms `0029` and sprouts `0017` only on cells that are already grass-tuft
  (`0001`) and only at ~22% — keeps them associated with the rough ground.
- **Everything tests the occupancy set before drawing.** That's what keeps trees off
  pens automatically and produces the ragged pen/woodland interface for free.

---

## 7. Rejected, and forced compromises

### Rejected after rendering it
| tried | why not |
|---|---|
| Full-dirt pen interiors | Reads as an orange swatch — the same dashboard, recoloured |
| Frozen = 40% alpha + overgrown pen | Looks broken; misrepresents a common benign state (§0a) |
| Desaturation for frozen | Fails on white species — sheep, chicken, Holstein |
| Scattering individual trees sparsely to fill space | Confetti. Dense stands with trunk-only reservation instead (§6.2) |
| ~~Canopy bands from `0006-0008`/`0018-0020`~~ | ~~Reads upside down~~ — **struck out: it was the renderer flip, not the art (`0801ade`). Unused but not rejected; see §6.2** |
| Tile `0043` as a crop bed | It's grey-flecked gravel; reads as rubble on grass |
| State-sorted animal slots | Teleports animals across the pen on every state flip |
| Uniform value-noise for grass | Produced visible diagonal streaks; §4.1 form doesn't |
| Playback rate as the overloaded cue | This *is* the "fast jittery walk" that got called stupid — reads as a defect, not a signal |

### Forced compromises

1. **The cow is 4.4 tiles wide.** LPC side-view cow is 71px against a 16px tile. A
   2-cow pen is 13 tiles, which is what drives the 1488px-at-3× minimum width. Pixel
   art can't be downscaled at non-integer ratios, so this is structural. Mitigation is
   the y-sorted depth lattice — animals stand at different depths and partially
   overlap, so pens don't grow linearly with occupancy.
2. **No inner-corner dirt tiles.** Dirt blobs must stay convex-ish (§4.4).
3. **No lying-down or sleeping frames.** LPC is walk + eat only. The `frozen` pose is a
   held eat frame — an approximation, flagged rather than hidden.
4. **No particles, no Zzz, no emote bubbles, no water/pond/well/scarecrow/silo, no
   night tiles.** Every cue above is built from tint, position, held frames and
   existing prop tiles. Nothing needs new art except the font.

   The feed gauge's vat (§6.1) looks like it spends the banned "well" — liquid sitting
   in a basin — but it doesn't: `FarmVat.compose` paints solid, measured-colour rows
   over the existing `0130` tile, the same class of operation as the §5.3 state tints, a
   colour transform on shipped pixels rather than new art. That claim is checkable, not
   asserted: at level 3 (budget exhausted) the composite is byte-identical to the
   already-shipped `0131` tile, which is what `VatFillTests` pins.
5. **Text can't sit on the pixel grid via SwiftUI `Text`** — hence the bundled bitmap
   font (§3.2). The mockup fakes it with a 1-bit threshold mask, which you can't do in
   `Canvas`.
6. **`Canvas` + `TimelineView` is sufficient.** Everything reduces to "draw these
   sprites at these positions this frame", one y-sort, and a per-sprite colour
   multiply. No pathfinding needed: the idle wander is a 1-tile anchored oscillation
   and the active walk is a fixed traverse — both pure functions of `(pid, time)`.

---

## 8. Build order

1. Ground fill + clumped variation, grass only. Check it doesn't streak.
2. Dirt autotiler + lanes. Check roads terminate and connect.
3. Layout: pen sizing, row packing, lane assignment, **fit rule**. Verify at 1 / 8 / 14 / 30.
4. Fences + gates + nameplates — **bundle the font first**.
5. Animals: side-view frames, slot lattice, y-sort, shadows.
6. State cues in value order: cool shade `frozen` → red pulse `overloaded` → head
   posture → forward/back offset → props → bounce. **Anchor the idle wander before you
   ship it, not after.**
7. Woodland bands + fringe. **Last** — it's garnish and it depends on the occupancy set
   already being correct.

---

## 9. Reference renders

| file (Desktop) | what | status |
|---|---|---|
| `FARM-1-typical.png` | 8 pens, **honest distribution** — 13 idle/frozen, 1 active, 0 overloaded | **canonical target** |
| `FARM-2-fourteen-pens.png` | 14 pens, realistic distribution | canonical, density case |
| `FARM-3-single-pen-3x.png` | 1 pen @3× | canonical, sparse case |
| `FARM-4-state-cues.png` | 5 cells: 4 shipping states + reserved slot | study — **cell 5 is a proposal, not spec** |
| `FARM-5-all-states.png` | **synthetic**, every state at once | study — **not representative** |
| `FARM-6-frozen-shade-test.png` | frozen treatment trial across all 4 species | study |

`FARM-1` deliberately shows 1 active animal out of 15. An action-packed render flatters
the design and lies about the product; this is the real test of "is it pleasant when
nothing is happening." It passes.
