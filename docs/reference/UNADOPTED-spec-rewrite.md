# Farm Scene — Implementation Spec

Renderer spec for the ClaudeMonitor **Farm** window. All coordinates are in **tiles**
(16 × 16 source px) or **1× pixels**, never screen pixels, unless stated. Screen pixels =
`1× px × scale`, integer scale only.

**Provenance markers** appear on every non-obvious value:

| tag | meaning |
|---|---|
| **[M]** | **Measured** out of an artifact with PIL. Fact. |
| **[R]** | **Reproduced** — verified by re-running `mock7.py` and diffing against the canonical PNG at 0 differing pixels. Fact. |
| **[I]** | **Inferred** — not settled by any artifact; a judgement call an engineer may need to revisit. |
| **[D]** | **My decision** — the artifacts were silent or contradictory; I chose, and it can be overruled. |
| **[H]** | **Human decision** already taken, recorded with its date. Do not relitigate. |

---

## 0. Provenance, and what this supersedes

### 0.1 The generator is the artifact

`scratchpad/mock7.py` is not a sketch of the design — it *is* the design. Re-running it
reproduces all four canonical PNGs **pixel-exactly**: **[R]**

```
mockup7.png            -> FARM-1-typical.png        0 differing px of 1,413,120
mockup7-allstates.png  -> FARM-5-all-states.png     0 differing px of 1,413,120
mockup7-dense.png      -> FARM-2-fourteen-pens.png  0 differing px of 2,129,920
mockup7-one.png        -> FARM-3-single-pen-3x.png  0 differing px of 1,474,560
```

Every value tagged **[R]** is therefore a measured property of the canonical renders, not a
claim about them. Where I disagree with `mock7.py` I say so explicitly (§0.3) — those are
the only places the Swift port should intentionally differ.

### 0.2 Artifact precedence

Later supersedes earlier. All six PNGs are outputs of one generator, so they do not in fact
contradict each other; the frozen-treatment change from green to grey happened *before*
this set was rendered.

| artifact | role | authority |
|---|---|---|
| `mock7.py` | the layout + cue algorithm | **normative** for geometry, tiles, colour |
| `FARM-1-typical.png` | 8 pens, honest state mix (13 idle/frozen, 1 active, 0 overloaded) | **canonical target** |
| `FARM-2-fourteen-pens.png` | 14 pens, density case | canonical |
| `FARM-3-single-pen-3x.png` | 1 pen @3×, sparse case | canonical |
| `FARM-4-state-cues.png` | 5 annotated cells | normative for **cue intent**; cell 5 is a *proposal* |
| `FARM-5-all-states.png` | synthetic, every state at once | study only — **not a representative farm** |
| `FARM-6-frozen-shade-test.png` | frozen shade ladder, 4 species × 5 levels | normative for the **frozen tint value** |

`FARM-1` deliberately shows **1 active animal out of 15**. Claude computes server-side, so
local CPU sits near zero; `idle`/`frozen` are the common states. A render full of activity
would flatter the design and misrepresent the product. The acceptance question for this
scene is *"is it pleasant when nothing is happening"*, not *"is it exciting"*.

### 0.3 Where the Swift port must deviate from `mock7.py`

These are findings from measuring the assets, not the designer's notes. Each is invisible
in a still frame, which is why the mockups do not show them.

| # | `mock7.py` does | build this instead | why |
|---|---|---|---|
| 1 | crops every sprite frame to **its own** bbox | crop to the **union rect** for that (species, sheet, row) — §3.5 | per-frame bboxes differ by up to **4 px H / 2 px V** **[M]**. Crop-to-own-bbox makes an animated animal shimmy sideways; a still never shows it |
| 2 | seeds pen wear with `hsh(name[0], len(name), rowIndex)` | seed with `fnv1a64(cwd)` only — §4.3 | the row index is in the seed, so a *new session elsewhere* reflows rows and **repaints every pen's dirt**. Contradicts the design's own stated rule |
| 3 | fills the world with `#6EBE5A` | fill with **`#84C669`** — §1.3 | `tile_0000.png` is 256 identical px of `#84C669` **[M]**; `#6EBE5A` is never visible in the mock but *would* be in the app's leftover/overscan strip |
| 4 | no animal cap; `pen_size` grows unbounded | cap displayed animals at 8, surplus as `+N` — §2.1, §3.2 | 20 sessions in one project ⇒ a 33-tile-wide pen ⇒ layout collapse |
| 5 | uses Python `random.Random` for wear + scatter | a specified integer-hash PRNG — §8.2 | Mersenne Twister is not reproducible in Swift |
| 6 | undefined for zero pens (`row_bands[0]` on an empty list) | explicit empty state — §2.7 | zero sessions is a normal, frequent condition |

### 0.4 This supersedes parts of the committed design doc

`docs/superpowers/specs/2026-08-15-farm-visualization-design.md` predates the art
direction. These sections of it are **superseded** and must not be built:

| that doc says | status |
|---|---|
| Art = **system emoji**, palette 🐄🐖🐑🐔🐴🦙🐐 | superseded — pixel art, 4 species (§7) |
| Ground = dashed `RoundedRectangle` fence dividers | superseded — tiled fences (§3.1). This is the `CURRENT-bad-ui.png` failure |
| State overlay = glow rings + 🏃🔥💤 badges | superseded — §6 |
| Layout = `LazyVGrid` / wrapping `HStack` | superseded — computed tile layout (§2) |
| Container = `WindowGroup(id: "farm")` + `openWindow` | superseded — hand-owned `NSWindow`. See commits `7d7851e` (WindowGroup terminated the app at launch) and `4d67d15` (AppKit-owned window). **Do not reintroduce `WindowGroup`, `Window`, or `MenuBarExtra`.** |

Still in force from that doc: pens = projects, animals = sessions, species from a stable
FNV-1a hash, and the requirement that a palette change be *"a conscious decision, not an
accidental reshuffle"* (§7.2). The dropdown's 🌾🏃🔥🥶 badges are **unchanged** — those are
the popover, not the farm.

---

## 1. Constants and the coordinate system

### 1.1 Constants

```
T          = 16          // source tile size, px
MARGIN_L   = 4           // tiles of woodland at the left edge — framing, not padding
MARGIN_R   = 4
MARGIN_T   = 3
FRAME_B    = 4           // rows reserved for the bottom treeline
GAP        = 2           // tiles between pens in a row
LANE_H     = 2           // dirt lane height
BARN_W     = 7
BARN_H     = 4
MAX_SHOWN  = 8           // animals drawn per pen; surplus becomes "+N"
GRASS_FILL = #84C669     // [M] tile_0000 is a flat solid of this colour
```
All **[R]** except `MAX_SHOWN` **[D]** and `GRASS_FILL` **[M]**.

### 1.2 Grid from window

```
COLS = floor(windowW / (T * scale))
ROWS = floor(windowH / (T * scale))
```

### 1.3 Leftover pixels

`COLS*T*scale` rarely equals `windowW`. The remainder strip (`< 48 px`) must be filled with
`GRASS_FILL` `#84C669`, **not** letterboxed and **not** stretched. Because `tile_0000` is a
flat solid of exactly that colour **[M]**, the seam is invisible. Using the mock's
`#6EBE5A` here would draw a visible darker band down the right edge — the mock never
exposes its own background colour, so this bug cannot be seen in the PNGs.

### 1.4 Scale selection

Integer only, nearest-neighbour, no fractional scaling ever. Try large → small, take the
first that fits (§2.5):

```
for s in [3, 2, 1]:
    if layoutFits(floor(w/(16*s)), floor(h/(16*s))): use s; break
else:
    use 1 and apply the degradation ladder (§2.6)
```

Measured feasibility for the canonical 8-pen scene, full margins **[M]**:

| window | 3× | 2× | 1× |
|---|---|---|---|
| 640×480 | no | no | no (needs 36 rows, has 30) |
| 800×600 | no | no | **OK** |
| 1024×768 | no | no | **OK** |
| 1280×800 | no | no | **OK** |
| **1472×960** | no | **OK** ← `FARM-1` | OK |
| 1664×1280 | no | **OK** ← `FARM-2` | OK |
| 1920×1080 | no | **OK** | OK |
| 2560×1440 | **OK** | OK | OK |

**Consequence to accept up front:** 3× is a large-display-only mode. `FARM-3` gets 3×
because it has *one* pen (32×20 tiles), not because 3× is generally reachable. Do not tune
the design to make 3× common.

Minimum window for the canonical 8-pen scene, `minCols × neededRows` **[M]**:

| margins | 1× | 2× | 3× |
|---|---|---|---|
| full | 496 × 464 | 992 × 928 | 1488 × 1392 |
| stripped (§2.6) | 400 × 352 | 800 × 704 | 1200 × 1056 |

Recommended `NSWindow.contentMinSize` = **640 × 480** **[D]**, with scrolling below the fit
threshold. Recommended default content size = **1472 × 960** **[D]** — that is exactly
`FARM-1`.

---

## 2. Layout algorithm

Ordering is fixed upstream by `FarmGrouping.pens(from:)`: **pens sorted by `cwd`, animals
sorted by `pid`**. The layout is a pure function of that ordered list plus `(COLS, ROWS)`.
Never sort by state, count, size, or arrival order — `ps aux` returns a different process
order on nearly every poll, and honouring it made the whole grid jump twice a second.

### 2.1 Pen size from occupancy

Species footprints, derived from **measured side-view content bboxes** **[M]**:

| species | walk side bbox | eat side bbox | max | footprint (tiles) |
|---|---|---|---|---|
| cow | 71 × 44 | 71 × 44 | 71 × 44 | 5 × 3 |
| sheep | 49 × 39 | 53 × 39 | 53 × 39 | 4 × 3 |
| pig | 55 × 30 | 57 × 30 | 57 × 30 | 4 × 2 |
| chicken | 31 × 26 | 32 × 27 | 32 × 27 | **3** × 2 |

> The chicken footprint is widened from its measured 2 tiles to **3** on purpose **[R]** —
> at 2 the slot lattice crowded and birds overlapped. Do not "correct" it back.

```
n         = min(animalCount, MAX_SHOWN)     // 8
rows      = (n <= 2) ? 1 : 2
cols      = ceil(n / rows)
interiorW = cols * footW + 1
interiorH = footH + (rows - 1) + 1
penW      = max(7, interiorW + 2)           // +2 = the fence ring
penH      = max(5, interiorH + 2)
```

Resulting pen sizes in tiles **[M]** — worth having in front of you while building:

| species | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8+ |
|---|---|---|---|---|---|---|---|---|
| cow | 8×6 | 13×6 | 13×7 | 13×7 | 18×7 | 18×7 | 23×7 | 23×7 |
| sheep | 7×6 | 11×6 | 11×7 | 11×7 | 15×7 | 15×7 | 19×7 | 19×7 |
| pig | 7×5 | 11×5 | 11×6 | 11×6 | 15×6 | 15×6 | 19×6 | 19×6 |
| chicken | 7×5 | 9×5 | 9×6 | 9×6 | 12×6 | 12×6 | 15×6 | 15×6 |

The cap at 8 is what stops this table running off the page: without it, 20 sessions in one
project produce a **33-tile-wide** pen that no window can hold. Not in `mock7.py` — add it.

### 2.2 Row packing

```
avail = COLS - MARGIN_L - MARGIN_R
rows, cur = [], []
curW = BARN_W + GAP + 1          // row 0 begins with the barn's slot already consumed
for pen in orderedPens:
    if curW + pen.w > avail && (cur.notEmpty || curW > 0):
        rows.append(cur); cur = []; curW = 0
    cur.append(pen); curW += pen.w + GAP
if cur.notEmpty: rows.append(cur)
```

**The wrap test must run even when the current row is empty.** Guarding it with
`if cur.notEmpty` skips the check on the first pen of row 0 — where `curW` is already 10
because of the barn — and that pen is then placed past the barn regardless of window width,
off the right edge **[R]**. The `curW > 0` clause is what keeps the check live.

The barn is **literally the first item in the flow**, not decoration placed afterwards.

### 2.3 Vertical placement

```
y = MARGIN_T
for (ri, row) in rows.enumerated():
    rowH = max(pen.h for pen in row)
    x = MARGIN_L + (ri == 0 ? BARN_W + GAP + 1 : 0)
    for pen in row:
        pen.origin = (x, y + (rowH - pen.h))    // BOTTOM-ALIGNED
        x += pen.w + GAP
    rowBands.append((y, rowH))
    y += rowH + LANE_H

lanes  = [rowBands[i].y + rowBands[i].h  for i in 0 ..< rowBands.count - 1]
BARN_X = MARGIN_L
BARN_Y = rowBands[0].y + rowBands[0].h - BARN_H
```

**Bottom-align pens within a row.** Pens of different heights then produce a ragged *top*
edge, which is the single line that does most to break the "dashboard of equal boxes" read
that `CURRENT-bad-ui.png` failed on. Do not top-align, do not centre.

`FARM-1` check: 8 pens at COLS=46 ⇒ 3 rows of **[2, 3, 3]**, lanes at y = 9 and 17 **[R]**.
See §2.5 for the full table and for how to read those counts off the image.

### 2.4 Lanes and gates

One 2-tile dirt lane between every consecutive pair of rows. There is **no** lane below the
last row and none above the first.

```
gate = (ri < rowCount-1) ? (side: S, lane: lanes[ri])
     : (ri > 0)          ? (side: N, lane: lanes[ri-1])
     : (side: S, lane: none)        // single-row farm: no lane exists
gx   = pen.x + pen.w / 2            // integer div; the 2-tile gap is at gx-1, gx
```

Lane x-extent is `[MARGIN_L + 1, COLS - MARGIN_R - 1]` **[R]** — the road **terminates**;
it does not bleed off the window edges. A road running off-screen reads as a cropped
screenshot; a road that ends reads as a place.

### 2.5 Fit rule — evaluate before committing to a scale

```
minCols    = maxPenW + BARN_W + GAP + 1 + MARGIN_L + MARGIN_R
neededRows = Σ rowH + LANE_H * laneCount + MARGIN_T + FRAME_B
fits       = (minCols <= COLS) && (neededRows <= ROWS)
```

A 2-cow pen (`penW = 13`) gives `minCols = 31` ⇒ **1488 px minimum width at 3×**, 992 at
2×, 496 at 1× **[M]**. That number is structural, not a preference: the LPC side-view cow
is 71 px against a 16 px tile (4.44 tiles), and pixel art cannot be downscaled at
non-integer ratios.

**The two canonical scenes**, computed from their actual pen lists **[M]** — these are the
rows to check a port against, because their pen widths are the real ones:

| scene | pens | COLS × ROWS | rows | pens per row | neededRows | minCols |
|---|---|---|---|---|---|---|
| **`FARM-1`** (`TYPICAL`) | 8 | 46 × 30 | 3 | **[2, 3, 3]** | 29 | 31 |
| **`FARM-2`** (`DENSE`) | 14 | 52 × 40 | 4 | **[3, 4, 4, 3]** | 37 | 31 |
| `DENSE` squeezed into `FARM-1`'s window | 14 | 46 × 30 | 5 | [2, 3, 4, 4, 1] | 45 | 31 |

`FARM-1`'s `[2, 3, 3]` is directly checkable against the image: row 0 is WATCHAGENTS + NFQ
(the barn eats the rest), row 1 is VESTIO-ADMIN + SADBITS + FEAT+BODY…, row 2 is ALBERT +
SEEDLING + DOTFILES. Lanes land at y = 9 and 17 **[R]**.

**Scaling trend**, from a *synthetic* list — one animal per pen, species cycling
cow → chicken → sheep → pig, at `COLS=46` **[M]**. Use it for the shape of the curve, not
for exact numbers; its `minCols` is 26 rather than 31 because no pen holds two cows:

| pens | rows | pens per row | neededRows | verdict at ROWS=30 |
|---|---|---|---|---|
| 1 | 1 | [1] | 13 | fits |
| 3 | 1 | [3] | 13 | fits |
| 5 | 2 | [3, 2] | 21 | fits |
| 20 | 6 | [3, 4, 4, 4, 4, 1] | 52 | overflow ⇒ scroll |
| 30 | 8 | [3, 4, 4, 4, 4, 4, 4, 3] | 69 | overflow ⇒ scroll |

**At 30 pens the farm is a scrolling map, not a single glance.** That is the honest outcome
and it should not be papered over by shrinking pens: a pen that cannot hold its animal is
worse than a scrollbar. See §10 Q3.

### 2.6 Degradation ladder — never clip a pen

Apply **in this order**, re-testing `fits` after each step. Measured recovery for the 8-pen
scene **[M]**:

| step | change | neededRows | minCols |
|---|---|---|---|
| 0 | full margins | 29 | 31 |
| 1 | `FRAME_B: 4 → 0` (drop the bottom treeline) | 25 | 31 |
| 2 | `MARGIN_T: 3 → 1` | 23 | 31 |
| 3 | `MARGIN_L/R: 4 → 1` | 22 | **25** |
| 4 | barn onto its own row band | +BARN_H rows | **−10 cols** |
| 5 | scroll (vertical first, then horizontal) | — | — |

Rules: **clip scenery before margins, margins before the barn, the barn before scrolling,
and never a pen.** Woodland is garnish; a half-drawn pen is a bug report. Step 4 trades 10
columns of width for `BARN_H` rows of height — use it only when the failure is on *width*.

### 2.7 Zero sessions — the empty state **[D]**

Not defined by any artifact; `mock7.py` indexes an empty `rowBands` and crashes. This is a
frequent, normal condition (the user closed every session), so it must be pleasant.

```
rowBands = [(MARGIN_T, BARN_H)]      // one synthetic band, barn height
lanes    = []                        // no lane: there is no second row
pens     = []
BARN_X, BARN_Y = MARGIN_L, MARGIN_T
```
Then: barn + apron (§4.2 source 2b) + the full farmyard prop cluster + complete woodland
treatment, exactly as in a populated farm. Add one nameplate (§3.2 geometry) centred on the
barn at `x = (BARN_X + BARN_W/2) * T`, mounted 2 px above the barn roof, reading
**`NO SESSIONS`**.

Scale for the empty state: pick the largest scale where `BARN_W + MARGIN_L + MARGIN_R ≤
COLS` and `MARGIN_T + BARN_H + FRAME_B ≤ ROWS` — usually 3×. An empty farm at 3× with a big
barn and deep woods reads as *quiet*; the same farm at 1× reads as *broken*.

**Do not** render an empty grey pane, a spinner, or "No sessions found" as HUD text. The
whole premise is that this window is nicer to look at than `ps aux`, and it is looked at
most often when nothing is running.

---

## 3. Pen anatomy

```
pen        = (x, y, penW, penH)              // includes the fence ring
interior   = (ix, iy, iw, ih) = (x+1, y+1, penW-2, penH-2)
IX,IY,IW,IH = interior × T                   // in 1× px
```
Minimum pen **7 × 5** ⇒ minimum interior **5 × 3** tiles = 80 × 48 px **[R]**.

### 3.1 Fence tiles

Kenney *Tiny Town* 1.1, `tile_XXXX.png`. Identities verified by inspection **[M]**:

| position | tile |
|---|---|
| top-left corner | `0044` |
| top-right corner | `0046` |
| bottom-left corner | `0068` |
| bottom-right corner | `0070` |
| horizontal rail | `0081` |
| vertical rail | `0047` |
| rail end — left cap | `0080` |
| rail end — right cap | `0082` |

Corners first, then rails fill `x+1 ..< x+penW-1` on the top and bottom rows and
`y+1 ..< y+penH-1` on the left and right columns.

**Gate:** a 2-tile gap at `gx-1, gx` on the gated rail. Those two cells get `0082` at `gx-1`
and `0080` at `gx` **[R]** — the rail ends cleanly on both sides of the opening. There is no
gate sprite in the pack and none is needed.

### 3.2 Nameplate

A wooden plate **nailed to the top rail**, centred, deliberately overlapping the fence so it
belongs to the world rather than floating above it as HUD. Colours **[M]**, sampled from
`FARM-1`:

| part | colour | note |
|---|---|---|
| outline | `#45262E` | 1 px, drawn as a rect 1 px larger on all sides |
| body | `#BC7A4A` | |
| top highlight | `#E8AE76` | 1 px row at `y0 + 1` |
| ink | `#301A16` | uppercase |

```
plateW = textWidthPx + 2*padX
plateH = capHeight + padTop + padBottom
x0     = (pen.x + penW/2) * T - plateW/2
y0     = pen.y * T + 14 - plateH          // overlaps the top rail
```

**Metrics are invariants, not constants.** `mock7.py`'s `plateH = 15` and `textWidth + 9`
are artifacts of PIL's `load_default()`, a font we do not have and will not ship. Derive the
plate from the shipped font's real metrics, honouring:

- `padTop` ≥ **3 px above cap height**
- `padBottom` ≥ **4 px below baseline** — **not optional.** At 12 px total the `Q` descender
  clipped and **`NFQ` rendered as `NEO`**, `DOTFILES` as `DOTEILES` **[R]**. Anyone who
  "tightens up" the plate reintroduces exactly this.
- minimum cap height **7 px**; below that, truncate harder rather than shrink the font.

**Truncation:** `maxPx = (penW - 1) * T`. Truncate and append `…`. `FARM-1` shows
`FEAT+BODY-TYPE-QUESTIONNAIRE` → `FEAT+BODY-TYPE-Q…` on a 10-wide pen **[R]**.

**Overflow suffix:** when `animalCount > MAX_SHOWN`, plate text is `LABEL +N` where
`N = animalCount - MAX_SHOWN`. Truncate **the label only** — the `+N` must survive, since it
is the only signal that animals are hidden **[D]**.

**A bundled bitmap pixel font is a requirement, not a preference.** Silkscreen or Press
Start 2P (both OFL, ~14 KB). SwiftUI `Text` antialiasing turns to mush on brown wood at this
size — that is what produced `NEO`/`DOTEILES`. The mockups fake it by rendering to a mask
and thresholding at 100/255, which `Canvas` cannot do. **We do not have the font; it must be
added** — see §10 B1. Ship `OFL.txt` alongside and do not rename the font file.

Do **not** use tile `0083` for the label — it is 16×16 and cannot hold text. Signpost only.

### 3.3 Trough

Every pen, no exceptions, including frozen ones **[R]**:

```
0107 (bucket)  at (ix,     iy + ih - 1)
0106 (barrel)  at (ix + 1, iy + ih - 1)
```
A frozen session's pen keeps its trough. The state means *resting*, not *abandoned*.

### 3.4 Animal slot lattice

Slot index is **`i` = position in the pid-sorted list, and never changes with state**
**[R]**. State applies an offset *within* the slot only (§6.4). Sorting animals by state
would teleport one across the pen on every state flip — the reshuffle complaint again, just
triggered by a different event.

```
wmax  = max sprite width in this pen        // from the union rects, §3.5
hmax  = max sprite height
ncols = max(1, min(count, IW / (wmax + 4)))
nrows = ceil(count / ncols)
depth = (hmax < 34) ? 11 : 8                // px of y separation between ranks
span  = IW - 6
slot  = span / ncols

col, row = i % ncols, i / ncols
rank     = nrows - 1 - row                  // rank 0 = frontmost
bx       = IX + 3 + col*slot + (slot - w)/2
by       = IY + IH - 1 - rank*depth         // by is the BASELINE (feet)
```
Apply the state offset (§6.4), then clamp:
```
bx = clamp(bx, IX + 2,     IX + IW - w - 2)
by = clamp(by, IY + h + 1, IY + IH + 8)
```
Draw the sprite image at `(bx, by - h)`.

**Overlap handling is the lattice plus `depth`, not collision resolution.** Animals in
different ranks *may* overlap slightly — that is the intended depth cue, resolved by the
y-sort (§6.6). The `+8` in the `by` clamp is what lets front-rank animals overlap the bottom
rail; that overlap is the only thing giving the scene a z-axis. Do not "fix" it.

### 3.5 Sprite frames — union crop rects **[M]**

**Crop every frame of a given (species, sheet, row) to the same rect.** LPC frames are
loosely centred in their cells, and per-frame content bboxes drift by up to **4 px
horizontally and 2 px vertically**. `mock7.py` crops each frame to its own bbox, which is
correct for a still and wrong the instant frames advance: the animal slides sideways as it
chews.

Rect is `(x, y, w, h)` within the frame cell. Rows: **1 = facing left, 3 = facing right**.

| species | sheet | cell | row 1 (left) | row 3 (right) |
|---|---|---|---|---|
| cow | walk | 128×128 | 20, 44, 71×45 | 36, 44, 71×45 |
| cow | eat | 128×128 | 21, 44, 71×44 | 36, 44, 71×44 |
| pig | walk | 128×128 | 34, 53, 55×31 | 39, 53, 55×31 |
| pig | eat | 128×128 | 32, 54, 57×30 | 39, 54, 57×30 |
| sheep | walk | 128×128 | 37, 43, 49×40 | 42, 43, 49×40 |
| sheep | eat | 128×128 | 33, 44, 53×39 | 42, 44, 53×39 |
| chicken | walk | 32×32 | 0, 4, 31×26 | 1, 4, 31×26 |
| chicken | eat | 32×32 | 0, 3, 32×27 | 0, 3, 32×27 |

Front/back rows, for reference. **Banned** for the four shipping states — quadruped
front/back views are 20–27 px wide by 28–72 px tall, tall thin totems, and are most of why
the earlier shipped animals looked wrong:

| species | row 0 (up/back) | row 2 (down/front) |
|---|---|---|
| cow | 51, 40, 27×72 | 51, 45, 27×59 |
| pig | 54, 43, 21×48 | 54, 46, 21×46 |
| sheep | 50, 39, 27×50 | 50, 47, 27×42 |
| chicken | 6, 1, 20×28 | 6, 2, 20×29 |

**Facing** alternates by slot index: `row = (i % 2 == 0) ? 3 : 1` **[R]**. The single
exception is the reserved attention state (§6.5).

---

## 4. Ground

### 4.1 Grass — clumped, never dusted

```
clump = hash(x/4, y/3, SALT_A) % 100        // integer division: coarse 4×3 cells
local = hash(x, y, SALT_B) % 100
tile  = 0001  if clump < 24  && local < 55  // tufts
      = 0002  if clump >= 93 && local < 35  // flowers
      = 0001  if local < 4                  // rare loners
      = 0000  otherwise                     // flat grass
```
`SALT_A = 7`, `SALT_B = 13` **[R]**.

The coarse `clump` term is the entire point: it makes variation form *regions*. A flat
per-tile probability — what the rejected `mockup3` did — is visual static, not texture.
Uniform value-noise was also tried and produced visible diagonal streaks; this coarse-cell +
local-hash form does not.

Keep the resulting tile id per cell in a `GRASS[x][y]` map; §5.5 needs it.

### 4.2 Dirt is derived, never authored

Build **one** `Set<Point>` of dirt cells from four sources, then autotile the whole set in a
single pass. Because they share a set, lanes, apron, thresholds and pen wear connect
automatically — no seam logic, no hand-placed junctions.

| # | source | rect |
|---|---|---|
| 1 | lanes | `rect(MARGIN_L+1, laneY, avail-2, LANE_H)` for each lane |
| 2a | barn spur | `rect(BARN_X+2, BARN_Y+BARN_H, 3, lanes[0]-(BARN_Y+BARN_H))` — omitted if no lanes |
| 2b | barn apron | `rect(BARN_X+1, BARN_Y+BARN_H, 5, 2)` |
| 3 | gate threshold | S: `(gx-1,yy),(gx,yy)` for `yy in pen.y+penH-1 ..< laneY`; N: same for `yy in laneY+LANE_H ..< pen.y+1` |
| 4 | pen wear | §4.3 |

### 4.3 Pen wear — a worn patch, not a dirt floor

Flooring the interior in dirt just swaps dark rounded rectangles for orange ones: the same
dashboard, recoloured. It was rendered and rejected. Per pen, the union of:

```
trough apron  : (ix,iy+ih-1) (ix+1,iy+ih-1) (ix,iy+ih-2) (ix+1,iy+ih-2)
gate inside   : (gx-1, gy) (gx, gy)     gy = iy+ih-1 for S gates, iy for N
standing patch: cx = ix + 2 + rnd(max(1, iw-4))
                cy = iy     + rnd(max(1, ih-1))
                for dy in -1...1, dx in -2...2:
                    if |dx| + 2*|dy| <= 2 + rnd(2): add (cx+dx, cy+dy)
```
Clip everything to the interior. Target coverage **25–35%** of the interior; grass must
survive in the corners and along the rails.

> **Seed from `fnv1a64(cwd)` alone** — §8.2. `mock7.py` folds the *row index* into this seed,
> which means a new session starting in an unrelated project reflows the rows and repaints
> the dirt in every pen on screen. Repainting ~40 ground tiles because something happened
> elsewhere is a bigger visible churn than the per-frame reshuffling that was already
> rejected. Never seed from live state, animal position, row, or time.

### 4.4 Dirt autotiler

For each dirt cell, test whether each 4-neighbour is **absent** from the dirt set:

| N free | S free | W free | E free | tile |
|:---:|:---:|:---:|:---:|---|
| ✓ | | ✓ | | `0012` |
| ✓ | | | ✓ | `0014` |
| | ✓ | ✓ | | `0036` |
| | ✓ | | ✓ | `0038` |
| ✓ | | | | `0013` |
| | ✓ | | | `0037` |
| | | ✓ | | `0024` |
| | | | ✓ | `0026` |
| | | | | interior fill ↓ |

Evaluate **in this order** — the corner cases must be tested before the edge cases.

Interior fill, `r = hash(x, y, 5) % 100` **[R]**:
`0025` if r<70, `0039` if r<80, `0040` if r<88, `0041` if r<94, else `0042`.

**The pack has no inner-corner dirt tiles** **[M]**. Keep dirt shapes convex-ish; concave
notches fall back to `0025` and look fine. Do not build S-bend paths. Tile `0043` was tried
as a crop bed and rejected — it is grey-flecked gravel and reads as rubble on grass.

---

## 5. Scenery

Rule for everything in this section: **test the occupancy set before drawing.** Occupancy is
seeded with all dirt cells, then every pen dilated by 1 tile, the barn dilated by 1 tile,
and each lane dilated by 1 tile **[R]**. That single test is what keeps trees off pens and
paths automatically *and* produces the ragged pen/woodland interface for free.

### 5.1 Barn — 7 × 4, the focal point, at the head of row 0

```
roof row 1 : 0052  0053 ×5  0054      then 0055 overwrites the centre (hay-loft window)
roof row 2 : 0064  0065 ×5  0066
wall rows  : 0072  0073 ×5  0075      (rows 2 ..< h)
ground row : 0084 at x+1 and x+w-2 ;  0074 0074 at centre (double door)
```

### 5.2 Farmyard cluster — always clustered, never scattered singly **[R]**

| tile | what | position |
|---|---|---|
| `0093` ×2 | hay | `(BARN_X+BARN_W, BARN_Y+BARN_H-1)` and `-2` |
| `0094` | hay stack | `(BARN_X+BARN_W+1, BARN_Y+BARN_H-1)` |
| `0116` | pitchfork | `(BARN_X-1, BARN_Y+BARN_H-1)` |
| `0106` / `0107` | barrel + bucket | `(BARN_X+BARN_W, BARN_Y+BARN_H+1)` and `+1` |
| `0130` | chest | `(BARN_X-1, BARN_Y+BARN_H+1)` |
| `0057` | mailbox | `(BARN_X+5, lanes[0]-1)` — omit if no lanes |
| `0083` | signpost | `(BARN_X+2, lanes[0]+LANE_H)` — omit if no lanes |
| `0103` | see caveat below | drawn on the *animal layer* at `((BARN_X+BARN_W-1)*T+2, (BARN_Y+BARN_H)*T+2)`, baseline `(BARN_Y+BARN_H)*T+18`, shadow width 10 |

`0103` participates in the y-sort and gets a ground shadow like an animal **[R]**. It has no
state and never animates **[D]**.

> **Caveat on `0103` — verify before assuming a wrong tile id.** `mock7.py`'s comment calls
> it "character by the door for scale and life", but inspected on its own it renders as a
> **blue-framed signboard, not a figure** **[M]**. The tile id is nonetheless correct — it is
> what produced `FARM-1` — so an engineer seeing a signboard has not made a mistake. Whether
> a *board* deserves a ground shadow and a y-sort slot is a live question: at barn scale it
> reads fine, which is presumably why it survived. If the shadow looks wrong on device, drop
> the shadow and draw it as a plain prop; nothing else depends on it.

### 5.3 Canopy bands — the rule that makes scenery read as deliberate

**Tiles `0006 0007 0008` over `0018 0019 0020` tile horizontally into a continuous canopy**
(autumn variant `0009 0010 0011` / `0021 0022 0023`) **[M]**. Used as *bands* you get a
forest; used as individual trees you get a field of lollipops. This is the single difference
between the rejected pass and the canonical one.

```
canopyBand(x0, x1, y, autumn):
    clamp x0,x1 to [0,COLS]; require x1-x0 >= 1 and 0 <= y and y+2 <= ROWS
    guard all cells in (x0..<x1, y..<y+2) unoccupied else return false
    top: 0006 at x0, 0008 at x1-1, 0007 between
    bot: 0018 at x0, 0020 at x1-1, 0019 between
    mark occupied; return true
```

**Horizontal treeline** — top edge grows down, bottom edge grows up; walk in runs:
```
h      = hash(x, edgeY, seed)
run    = 3 + h % 5                              // 3..7 columns
depth  = 1 + ((h >> 6) % 100 < 42 ? 1 : 0)      // 1 or 2 bands
inset  = (h >> 10) % 2                          // 0 or 1 tiles
autumn = (h >> 14) % 100 < 20
for b in 0..<depth:
    by = grow>0 ? edgeY+inset+b*2 : edgeY-inset-b*2-1
    if !canopyBand(x, xe, by, autumn) { depth = b; break }
```
**Vertical treeline** — `run = 2 + (h % 3)*2` rows (2/4/6), `w = 2 + (h>>5) % 3` tiles deep
(2..4), `autumn = (h>>9) % 100 < 18`. On failure, retry with `w-1` down to 1.

**Fringe**, per column/row just inside the mass: `hash % 100 < 30` (horizontal) or `< 34`
(vertical) ⇒ one small tree (`0004`/`0016`, autumn `0003`/`0015`); `< 44` / `< 52` ⇒ a bush
(`0005`/`0028`). This softens the straight interface between mass and lawn.

Placement calls **[R]**: `treelineH(0, COLS, 0, +1)`, `treelineH(0, COLS, ROWS-2, -1)`,
`treelineV(0, +1, 3, ROWS-5)`, `treelineV(COLS, -1, 3, ROWS-5)`, plus one band behind the
barn at `canopyBand(BARN_X-1, BARN_X+BARN_W+1, BARN_Y-2)` when `BARN_Y >= 4`, which nests
the barn into the landscape instead of leaving it stranded on lawn.

### 5.4 The middle: framed, not filled

**Open lawn is correct and intended.** The reference has a large empty middle; what makes it
not boring is that it is *framed*, not that it is full. Filling it uniformly is what made the
rejected pass read as confetti.

Leftover space in the **last row** gets three *clustered* features **[R]**, only when the gap
to the right of the last pen exceeds 10 tiles:

1. **Orchard block**, 11 tiles wide at `ox = COLS-3-11`, trees on a 3-tile lattice with
   alternating row offset — reads as *planted*, contrasting with the wild treeline.
2. **Hay yard** at `(lastX+4, lastRowY+1)`: `0093 0093` over `0094 0093` in a 2×2.
3. **Bush clumps** — a seeded scatter of `0005`/`0028`/`0027`, 10 around the orchard and 5
   near the hay yard.

Plus, everywhere: **hedge shoulders** — 12 bushes scattered along each lane's edge rows
(`ly-1 .. ly+LANE_H+1`), which gives the roads edges instead of letting them bleed into
lawn; and 12 more scattered over the whole field.

### 5.5 Undergrowth

300 candidate cells by hash; place `0029` (mushrooms) if `hash%4 == 0` else `0017` (sprout),
**only** where `GRASS[x][y] == 0001` (already a tuft cell) and only at 26% **[R]**. Gating on
the tuft map keeps undergrowth associated with rough ground rather than speckled across mown
lawn.

### 5.6 Scenery stability on relayout

Scenery is a pure function of `(COLS, ROWS, pen rects, lanes)`. It is therefore **rock stable
frame to frame** — which is the requirement — but it **does legitimately re-roll when the pen
set or the window size changes**, because those change the occupancy set.

Starting a session in project *A* can move a tree at the other end of the farm. **[D]** I
accept this and specify an **instant cut — no tween, no fade, no animated reflow.** Reasons:
a 2-second reflow animation on a window you glance at is exactly the "dizzy" complaint the
product exists to fix; and a tween would have to interpolate a discrete tile grid, which
cannot be done without fractional positions. Pens and animals hold their identity across the
cut, which is the part the eye tracks. See §10 Q2 if this proves annoying in practice.

---

## 6. State cues

### 6.1 Salience budget — read this before the table

Ranked by **how much the user must act**, which is what salience should track:

| rank | state | frequency | what the user should do |
|---|---|---|---|
| 1 | *needs attention* (future) | rare | **act now** |
| 2 | `overloaded` | rare | check your machine |
| 3 | `active` | brief flickers | nothing — but it is the interesting moment |
| 4 | `idle` | **common** | nothing |
| 5 | `frozen` | **common** | nothing — you just haven't typed in 10 minutes |

`frozen` is a **10-minute idle timer** (`docs/superpowers/specs/2026-08-14-session-state-model-design.md`),
not a death certificate. An earlier pass specced it as 40% alpha in a weed-choked pen — the
most dramatic treatment in the design applied to the *least actionable, most common* signal,
producing a farm of translucent ghosts in abandoned lots. That was rejected. **Frozen
recedes.** Delight in this scene comes from ambient life with no state meaning — staggered
grazing, the figure by the barn, the woodland — not from making common states loud.

### 6.2 The table

| state | sheet / frame | motion | position | colour | prop |
|---|---|---|---|---|---|
| `idle` | `eat`, col 2 base | slow eat cycle + rare short **anchored** wander | at the trough, head down, hangs back | full | trough |
| `frozen` | `eat`, **col 3 held** | **none** | back of pen | **cool multiply, k = 0.45** | trough |
| `active` | `walk` | walk cycle, traverses its slot | **forward**, overlaps the bottom rail | full | — |
| `overloaded` | `walk` | walk + 1 px integer bounce | forward | **red pulse 0 → 0.45 @ 1.2 Hz** | **bomb `0105`** |
| *needs attention* **(RESERVED)** | rows 0/2 | hop ~2 Hz | at the gate, **facing the viewer** | full | **plate `0095`** |

### 6.3 Measured tints

**Frozen — cool multiply, alpha untouched.** Verified against the `FARM-6` ladder by
regressing every changed pixel of the shaded columns against the unshaded column **[M]**:

| k | predicted (mr, mg, mb) | measured median ratio |
|---|---|---|
| 0.30 | 0.898, 0.922, 0.976 | 0.895, 0.919, 0.973 |
| **0.45** | **0.847, 0.883, 0.964** | **0.845, 0.883, 0.972** |
| 0.60 | 0.796, 0.844, 0.952 | 0.795, 0.846, 0.972 |

```
k = 0.45
mr, mg, mb = 1 - 0.34*k, 1 - 0.26*k, 1 - 0.08*k   // = 0.847, 0.883, 0.964
out = (r*mr, g*mg, b*mb, a)                        // alpha UNCHANGED
```

Why multiply, and why 0.45:
- **Desaturation fails.** Sheep, chicken and the Holstein cow are near-white and have no
  saturation to remove — only the pig changed. Visible across `FARM-6`'s species rows.
- **Alpha fade reads as broken/absent**, which is a lie about a common benign state.
- **Multiplication darkens white too**, so it works on all four species, and it reads as
  *shadow* rather than absence.
- **0.45 is the tested value**: 0.30 is invisible on the pig, 0.60 looks sickly.

Frozen keeps its ground shadow and its trough.

**Overloaded — red pulse.** The rendered still is `amt = 0.40`, recovered exactly by matching
pixel-count-identical colour pairs between `FARM-1` (that cow is `active`) and `FARM-5` (same
cow, `overloaded`) **[M]**:

| pixel count | base RGB | overloaded RGB | implied `amt` (R, G, B) |
|---|---|---|---|
| 2024 | 239, 233, 231 | 245, 158, 147 | 0.375, 0.403, 0.404 |
| 1592 | 58, 55, 55 | 136, 37, 35 | 0.396, 0.409, 0.404 |
| 1548 | 34, 33, 33 | 122, 22, 21 | 0.398, 0.417, 0.404 |
| 1292 | 210, 205, 203 | 228, 139, 129 | 0.404, 0.404, 0.404 |
| 740 | 130, 124, 124 | 180, 84, 79 | 0.400, 0.404, 0.403 |

```
r' = r + (255 - r) * amt
g' = g * (1 - amt * 0.8)
b' = b * (1 - amt * 0.9)
a' = a
```
The stills are one sample of a live pulse; `amt` oscillates **0 → 0.45 at 1.2 Hz** (§6.4).
The mockups happen to catch `amt ≈ 0.40`.

**Do not use playback rate as the overloaded cue.** A 4-frame sheet at 2× speed is exactly
the "fast jittery walk" that was rejected — it reads as a rendering defect, not a signal.
Colour is the strong channel across a dozen pens; rate is weak. Keep the walk near normal
speed and let the red do the work.

**Shadow** — every animal including frozen, and the barn figure **[R]**:
```
ellipse from (cx - sw/2, by - 4) to (cx + sw/2, by + 2)
cx = bx + w/2,  sw = w * 0.6
fill rgba(32, 62, 34, 0.314)     // 80/255
```
Draw **all shadows into one transparency layer and composite that layer once.** Drawing them
individually onto the scene double-darkens wherever two animals' shadows overlap, which the
mockups never show because PIL writes the ellipses into a single RGBA layer with replace
semantics **[M]**. In SwiftUI use one `Canvas` `drawLayer` for the shadow pass.

### 6.4 Position offsets and animation

Offsets applied **within the slot**, before the clamps in §3.4, `off = max(4, h/6)` **[R]**:

| state | Δby | Δbx |
|---|---|---|
| `idle` | `- off` | 0 |
| `frozen` | `- off - 2` | `+ 4` |
| `active` | `+ off` | `+ off` |
| `overloaded` | `+ off - 2` | `+ off - 2` |
| *attention* (reserved) | `+ off + 4` | 0 |

Everything below is **[I]** — the artifacts are stills and settle *no* timing whatsoever.
These are starting values chosen to satisfy the constraints the design does state; tune them
on device.

Deterministic per-animal phase, so pen-mates never march in lockstep:
```
phase(pid) = Double(fnv1a64("\(pid)") % 1000) / 1000.0      // stable per session
frameOf(t, fps, pid, n) = Int(t * fps + phase(pid) * n) % n
```

| state | timing |
|---|---|
| `idle` eat cycle | **1.8 fps** (0.556 s/frame), 4 frames ⇒ 2.2 s loop |
| `idle` wander | see below |
| `frozen` | **static**. `eat` col 3, no clock read at all |
| `active` walk | **8 fps**, 4 frames ⇒ 0.5 s loop |
| `active` traverse | **12 px/s** at 1×, ping-pong within the slot |
| `overloaded` walk | **8 fps** — same as active, deliberately |
| `overloaded` bounce | `Δy = -1 px` when `sin(2π · 3 · t + 2π·phase) > 0`, integer only |
| `overloaded` pulse | `amt = 0.225 · (1 - cos(2π · 1.2 · t + 2π·phase))` ⇒ 0 → 0.45 @ 1.2 Hz |
| *attention* hop | ~2 Hz, ±2 px integer |

**`idle` wander must be anchored.** Amplitude ≤ **1 tile (16 px at 1×)**, slow, with long
pauses, **always returning to the per-pid anchor** (the unmodified slot position):
```
u      = fract(t / 9.0 + phase(pid))          // 9 s period
travel = clamp((u - 0.70)/0.15, 0, 1) - clamp((u - 0.85)/0.15, 0, 1)
         // u < 0.70      : parked at the anchor (70% of the cycle)
         // 0.70 -> 0.85  : ramp out to 1 tile
         // 0.85 -> 1.00  : ramp straight back to the anchor
Δbx    = round(travel * 16 * dir(pid))        // integer px; dir = ±1 from the hash
```
i.e. ~70% of every cycle is standing still. Unanchored wander is the reshuffling complaint in
slow motion: invisible frame to frame, obvious after five minutes. The discriminator against
`active` is **amplitude and duty cycle**, not the presence of motion.

**`active` traverse stays inside its own slot** **[D]**. The design says "traverses the pen",
but a free traverse in a multi-animal pen makes animals walk through each other and breaks
the fixed-slot guarantee. Amplitude is `max(0, slot - w)` centred on the slot, so columns
never swap. Facing follows travel direction (row 3 moving right, row 1 moving left), which
also gives a free, legible reason for the sprite to flip.

All motion is a pure function of `(pid, t)` — no integration, no stored velocity, no
pathfinding. A dropped frame or a window occlusion must never accumulate drift.

**Snap every drawn position to integer 1× px before scaling.** Sub-pixel positions on a
nearest-neighbour upscale produce a 1-px shimmer along sprite edges.

### 6.5 The reserved fifth state

`0095` (red/white target plate **[M]**) is **reserved** and must not be spent on anything
else. `0105` (bomb) = *the machine is in trouble*; `0095` = *a human is needed*. Keeping them
distinct means `overloaded` still gets two channels (colour + prop) while the loudest prop
stays unspent for the state that will need to out-shout everything.

**Priority is settled. [H] (Albert, 2026-08-15):** *needs attention* **outranks**
`overloaded`. A session waiting on the human is more urgent than a busy machine. The ladder
in §6.1 stands, the badge assignments stand, and when the fifth state is implemented
`SessionStateEvaluator.evaluate` must check it **before** the overload branch — which means
the state-model doc's "overloaded takes priority over every other state" is amended, not
merely extended.

Badge geometry **[R]**: `0105` at `(bx + w/2 - 8, by - h - 13)` — horizontally centred on the
sprite, 13 px above its top edge. Badges draw **last, above every sprite**. Reserved badge
`0095` uses identical geometry at offset `-15`.

The reserved state faces the viewer. Rows 0/2 are banned for everything else, which is
precisely why it works: breaking the side-view rule *is* the signal. One animal in the whole
farm looking at you.

> **Sizing blocker for state five, found by measurement** **[M]**: the front-facing cow is
> **27 × 72 px**, but a 1-cow pen's interior is 6 × 4 tiles = 96 × **64 px**. The sprite is
> *taller than the pen* and the `by` clamp will shove it out of the enclosure. Pig is exactly
> at the limit; sheep and chicken have room.
>
> | species | row 0 size | 1-animal interior | verdict |
> |---|---|---|---|
> | cow | 27 × 72 | 96 × 64 | **overflows by 8 px** |
> | pig | 21 × 48 | 80 × 48 | exactly fits |
> | sheep | 27 × 50 | 80 × 64 | fits |
> | chicken | 20 × 28 | 80 × 48 | fits |
>
> Before state five ships, either `penH` gains +1 tile while any animal is in the attention
> state (relayout on state change — churn), or the attention pose stands **at the gate on the
> bottom rail** and is allowed to overflow the fence downward, which is consistent with "at
> the gate" and with front-rank animals already overlapping the rail. I recommend the latter
> **[D]**. This does not block the four shipping states.

### 6.6 Draw order

One sort, back to front, by baseline `y`:
```
1. ground (grass, dirt), fences, barn, scenery, props   — painter's order, no sorting
2. all shadows, into ONE layer, composited once
3. all sprites (animals + tile 0103), sorted ascending by baseline y
4. all badges
```
This is the only depth cue in the scene, and it is what makes front-rank and `active` animals
occlude the bottom rail. Kenney tiles carry baked dark outlines that give objects mass, but
without occlusion nothing has a z — that was a core diagnosis against the rejected pass.

### 6.7 Identifying overloaded and frozen in ~1 second across a dozen pens

- **Overloaded → colour.** It is the only red thing in a green-and-white scene, and the only
  bomb. Verify on `FARM-2`: one red sheep among 20 animals, bottom-centre, found before you
  have read a single label.
- **Frozen → value.** Shaded animals sit visibly darker and cooler than their pen-mates. This
  reads at pen scale without resolving the sprite, which is the whole point — you are
  comparing two animals in the same pen, not decoding one.
- **Idle vs active in a *still* frame** — a glance samples roughly one frame and a screenshot
  has none, so "one moves, one doesn't" is not sufficient. Carried by **head posture** (eat
  sheet = head down, walk sheet = head up) plus **depth** (idle hangs back at the rail;
  active steps forward ~12 px and occludes the bottom rail).

Note the deliberate asymmetry: the two common states are distinguished by *quiet* cues
(posture, value) and the two rare ones by *loud* cues (colour, prop). That is the salience
budget in §6.1 made concrete.

---

## 7. Species mapping

### 7.1 The palette must shrink from 7 to 4

`AnimalSpecies` declares 7 cases (cow, pig, sheep, chicken, horse, llama, goat) and
`species(forCWD:)` does `stableHash(cwd) % 7`. **We have LPC sheets for 4.** Horse and goat
have no art at all; llama is in the art brief but absent from `lpc/` **[M]**. As shipped,
**~3 of every 7 projects hash to something unrenderable.**

**Cut the enum to the four we can draw** **[D]**:

```swift
enum AnimalSpecies: String, CaseIterable {
    case cow     = "🐄"
    case pig     = "🐖"
    case sheep   = "🐑"
    case chicken = "🐔"
}
```
Order matters — it is the modulus order. Keep `cow, pig, sheep, chicken`; that is the order
the test vectors below assume. The emoji raw values stay, for the dropdown.

The alternative — sourcing three more style-compatible CC0/CC-BY sheets — has **not** been
verified as possible. Do not plan around it.

### 7.2 The reassignment is a one-time, conscious break

`% 7 → % 4` reassigns **every existing project's species exactly once** **[M]**:

| cwd | FNV-1a 64 | `% 7` (today) | `% 4` (new) |
|---|---|---|---|
| `/Users/albert/Projects/watchagents` | `0xe89a50c8879d099a` | 0 cow | 2 **sheep** |
| `/Users/albert/Projects/nfq` | `0xb7741b513731ba28` | 0 cow | 0 cow |
| `/Users/albert/vestio-admin` | `0xf0da85a586190862` | 3 chicken | 2 **sheep** |
| `/Users/albert/sadbits` | `0xab1bb6d6714c4912` | 0 cow | 2 **sheep** |
| `/Users/albert/dotfiles` | `0x99e6de6965a3b668` | 4 **horse (unrenderable)** | 0 cow |
| `/Users/albert/seedling` | `0xa4a82999bcfa7bd7` | 1 pig | 3 **chicken** |
| `/Users/albert/albert` | `0xe5d42643f7290334` | 3 chicken | 0 **cow** |
| `/tmp/scratch` | `0x9e1cfb3cc5438c56` | 6 **goat (unrenderable)** | 2 sheep |

The farm-viz design doc requires that a palette change be *"a conscious decision, not an
accidental reshuffle"*, enforced by a fixed-mapping test. **Update that test in the same
commit as the enum change**, using the table above as its vectors. Do not weaken the test to
make it pass.

`stableHash(cwd) % 4` is safe as-is: over a 150-path corpus of plausible project paths the
low two bits distribute 38 / 36 / 39 / 37 **[M]** — better, on this corpus, than
`(h >> 32) % 4` (29/44/39/38) or an xor-fold. No re-hashing or bit-folding is needed; keep
the existing one-line implementation.

### 7.3 Collisions are common — what distinguishes pens anyway

With 4 species, collisions are the norm, not an edge case **[M]**:

| pens | expected distinct species | expected pens per species |
|---|---|---|
| 4 | 2.7 of 4 | 1.0 |
| 8 | 3.6 of 4 | 2.0 |
| 14 | 3.9 of 4 | 3.5 |
| 30 | 4.0 of 4 | 7.5 |

Species is therefore **a texture, not an identifier**. It must never be load-bearing. Four
other channels carry identity, in the order the eye uses them:

1. **Position.** Pens are ordered by `cwd` and the order is stable, so a project keeps its
   place on screen across polls. This is what people actually navigate by, and it is the
   reason the ordering guarantee in §2 is non-negotiable.
2. **The nameplate.** The only unambiguous identifier; every pen has one, always.
3. **Pen size and silhouette.** Size is a function of species footprint × occupancy, so two
   cow pens with 1 and 4 sessions are 8×6 and 13×7 — visibly different objects.
4. **The wear pattern.** The standing patch is seeded from `fnv1a64(cwd)` (§4.3), so two
   adjacent same-species pens have differently-shaped dirt. It is subliminal, but it is what
   stops a row of sheep pens looking copy-pasted.

`FARM-1` has 3 chicken pens and 2 cow pens out of 8 and does not read as repetitive —
because of 1, 3 and 4.

---

## 8. Determinism

### 8.1 One hash, named explicitly

Two different hashes appear in the artifacts: the app's 64-bit FNV-1a over UTF-8 bytes
(`AnimalAssignment.stableHash`) and `mock7.py`'s 32-bit `hsh()` over integer words. The
renderer uses **exactly one implementation** — extend `AnimalAssignment` with an
integer-word overload:

```swift
// 32-bit FNV-1a over integer words — the mock's `hsh`, used for all grid noise.
static func gridHash(_ words: Int...) -> UInt32 {
    var h: UInt32 = 2166136261
    for w in words {
        h ^= UInt32(truncatingIfNeeded: w)
        h = h &* 16777619            // `&*` is required: FNV is defined mod 2^32
    }
    return h
}
```
`&*` (wrapping multiply), not `*` — a plain `*` traps on overflow in Swift. Same trap the
existing 64-bit implementation already documents.

**Never `Hasher` / `String.hashValue`** anywhere in this renderer. They reseed per process
launch, which would re-roll every species, every grass tuft and every tree on every app
restart.

For test vectors, assert the **whole 46×30 grass tile-id grid** against a golden fixture
rather than spot-checking individual cells; grid-noise bugs are systematic and a golden
fixture catches them at the first frame. Generate the fixture by dumping `mock7.py`'s
`GRASS` dict to a file — **not** by reading tile ids back out of `FARM-1.png`, where grass is
overdrawn by dirt, fences, the barn and scenery and cannot be recovered.

### 8.2 The PRNG contract — and what is *not* pixel-reproducible

`mock7.py` uses Python's `random.Random` (Mersenne Twister) for pen wear (`randrange` for the
patch centre and blob radius) and for `scatter()`. **An engineer cannot reproduce Mersenne
Twister in Swift, and must not try.** Replace it with an indexed hash draw:

```
draw(seed, k, n) = Int(gridHash(seed, k, 0x9E37) % UInt32(n))     // k = 0, 1, 2, … per call site
```
with `seed = UInt32(truncatingIfNeeded: fnv1a64(cwd))` for pen wear, and a per-feature
constant salt for scatter passes.

**Split the acceptance criteria accordingly — this is the difference between a day's work and
a week's:**

| pass | reproducible against the PNGs? | acceptance |
|---|---|---|
| layout, pen rects, lanes, gates | **yes** — pure integer arithmetic | exact match to §2.5's table |
| fences, barn, troughs, props | **yes** | exact tile ids at exact cells |
| grass variation | **yes** — integer hash | exact tile-id grid |
| dirt autotiler | **yes**, given the same dirt set | exact tile ids |
| canopy bands, treelines, fringe, orchard | **yes** — integer hash | exact placements |
| **pen wear blobs** | **no** — MT-seeded | 25–35% interior coverage; convex-ish; stable per `cwd`; identical across frames |
| **bush scatter, undergrowth** | **no** — MT-seeded | count in range; nothing on an occupied cell; identical across frames |

Do not spend time chasing pixel parity on the two unreproducible passes. Do insist on parity
for everything above them — those are where a layout bug hides.

### 8.3 Stability requirements, as testable invariants

1. Same `(pen list, COLS, ROWS)` ⇒ byte-identical scene, on every frame and every launch.
2. `t` may only affect: eat/walk frame index, idle wander offset, bounce offset, and the
   overloaded pulse amount. Nothing else may read the clock. In particular **no ground,
   scenery, layout or slot assignment may depend on `t`**.
3. A pen's identity (position in the order, species, wear pattern) depends only on `cwd`.
4. An animal's slot depends only on its index in the pid-sorted list — never on its state.

---

## 9. Asset packaging

### 9.1 What gets committed where

```
assets/farm/
├── tiles/                     132 × tile_XXXX.png, 16×16, from kenney/Tiles/
├── animals/                   8 × {cow,pig,sheep,chicken}_{walk,eat}.png
├── fonts/                     the bitmap pixel font + OFL.txt   (§10 B1)
└── ATTRIBUTION.md
```
Bundle as SwiftPM resources (`.copy("assets/farm")` in `Package.swift`) so the paths stay
stable. Load each tile once into a cache keyed by id — 132 × 16 × 16 RGBA is ~135 KB
resident, so preloading all of them when the window opens is fine and avoids a first-frame
hitch.

The existing `assets/` directory holds the unused Quaternius 3D models (CC0). Leave them;
they are unrelated to this work and their `License.txt` already covers them.

### 9.2 Licences — the CC-BY one is an obligation, not a courtesy

| asset | source | licence | obligation |
|---|---|---|---|
| Tiles | **Kenney — "Tiny Town" 1.1**, kenney.nl, dated 11-01-2023 **[M]**, per `kenney/License.txt` | **CC0 1.0** | none. Credit optional |
| Animals | **Daniel Eddeland**, LPC | **CC-BY 3.0** | **attribution required in the distributed work** |
| Font | Silkscreen or Press Start 2P | **OFL** | ship `OFL.txt`, do not rename the font file |

The repository is **MIT** and public, so every clone redistributes these assets. CC-BY 3.0
attribution is a licence condition on that redistribution — it is not satisfied by a commit
message. Required:

1. **`THIRD-PARTY-NOTICES.md`** at the repo root, listing each asset set, its author, licence,
   licence URL, and source URL.
2. **An in-app credits line** — the Farm window's menu or the dropdown's settings area. It
   must be reachable in the shipped app, not only in the repo.
3. **A `README.md` note** stating that MIT covers the *code* and that bundled assets carry
   their own licences.
4. **A statement of modification** for the LPC sheets — CC-BY 3.0 §4(c) requires indicating if
   changes were made. See §10 B2: we do not currently know whether these files are unmodified
   originals.

---

## 10. Open questions and blockers

### Blockers — an engineer will hit these

**B1. The bitmap font does not exist in the repo.** Every nameplate in every mockup depends on
it, and SwiftUI `Text` at this size is what produced `NEO`/`DOTEILES`. Someone must choose
Silkscreen or Press Start 2P, add the `.ttf` plus `OFL.txt` under `assets/farm/fonts/`, and
confirm the cap height at 1× is ≥ 7 px. **Nothing else in the design needs new art** — every
state cue is built from tint, position, held frames and existing tiles. This is the only
asset gap.

**B2. LPC provenance is undocumented — needs a human.** The `lpc/` directory contains eight
PNGs and **no licence file, no source URL, and no author file** **[M]**. Everything we "know"
(Daniel Eddeland, CC-BY 3.0, OpenGameArt) comes from the brief, not from the files. Two things
must be established by a human before shipping, and **I will not invent them**:
- the exact OpenGameArt page URL for the original submission;
- whether these files are unmodified originals or extracts. They look like extracts — 4×4
  grids at 512×512 with 128×128 cells, renamed to `{species}_{action}.png`. If they are
  derived, CC-BY 3.0 §4(c) requires the notice to say so.

Until B2 is resolved, do not tag a public release. Code can proceed.

### Open questions

**Q1. Does *needs attention* outrank `overloaded`? — RESOLVED [H] (Albert, 2026-08-15).**
Yes. Recorded in §6.5. `SessionStateEvaluator.evaluate` must check the fifth state before the
overload branch when it is implemented, which amends the state-model doc's "overloaded takes
priority over every other state". Still open beneath it: the front-facing pose overflows a cow
pen by 8 px (§6.5) — needs closing before state five ships, not now.

**Q2. Is an instant scenery cut on relayout acceptable?** §5.6. **[D]** Yes, on the grounds
that any reflow animation reintroduces exactly the visual churn this product exists to remove.
Worth checking against a real session that starts and stops repeatedly; if it proves
distracting, the cheap mitigation is to relayout at most once every N seconds rather than to
animate.

**Q3. What is the intended experience above ~14 pens?** Measured: 30 pens need 69 tile rows
(§2.5), so a single-glance farm is impossible without shrinking pens below their animals'
footprints. **[D]** I specified vertical scrolling with pens at full size. The alternatives —
a pen that cannot contain its animal, or a second "overflow" representation — are both worse,
but "what does a 30-session user actually want" is a product question the artifacts cannot
answer. Note that `FARM-2` (14 pens) is the largest case the designer rendered; **beyond 14
pens is unvalidated by any artifact.**

**Q4. `MAX_SHOWN = 8` and the `+N` plate suffix are mine.** **[D]** The cap appears in the
design's prose but not in `mock7.py`, and no render exercises it. 8 animals in one pen is
already 23 tiles wide for cows. Nobody has seen what `+N` looks like on a plate.

**Q5. All animation timing is inferred.** §6.4. Every mockup is a still; the artifacts fix
*what* moves and *why*, and settle no rate. The values given satisfy the stated constraints
(idle amplitude ≤ 1 tile with long pauses; overloaded not distinguished by rate; frozen
strictly static) but they are starting points to be tuned on device, not measurements.

---

## Appendix A — rejected approaches

Do not reintroduce these; each was rendered and looked at.

| tried | why not |
|---|---|
| Full-dirt pen interiors | Reads as an orange swatch — the same dashboard, recoloured |
| Frozen = 40% alpha + overgrown pen | Looks broken, and misrepresents a common benign state (§6.1) |
| Desaturation for frozen | Fails on white species — sheep, chicken, Holstein (§6.3) |
| Scattering individual trees to fill space | Confetti. Canopy bands instead (§5.3) |
| Tile `0043` as a crop bed | Grey-flecked gravel; reads as rubble on grass |
| State-sorted animal slots | Teleports animals across the pen on every state flip |
| Uniform value-noise for grass | Visible diagonal streaks; the §4.1 form does not streak |
| Playback rate as the overloaded cue | This *is* the "fast jittery walk" that was called stupid — reads as a defect, not a signal |
| Equal-size pens on a fixed grid | This is `CURRENT-bad-ui.png`. Occupancy-sized, bottom-aligned pens are the fix |

### Forced compromises worth knowing about

1. **The cow is 4.4 tiles wide.** 71 px against a 16 px tile. A 2-cow pen is 13 tiles, which
   drives the 1488 px-at-3× minimum width. Pixel art cannot be downscaled at non-integer
   ratios, so this is structural. Mitigation is the y-sorted depth lattice: animals stand at
   different depths and partially overlap, so pens do not grow linearly with occupancy.
2. **No inner-corner dirt tiles** (§4.4). Dirt blobs must stay convex-ish.
3. **No lying-down or sleeping frames.** LPC is walk + eat only, so the `frozen` pose is a
   held eat frame. An approximation, flagged rather than hidden.
4. **No particles, no Zzz, no emote bubbles, no water/pond/well/scarecrow/silo, no night
   tiles.** Every cue is built from tint, position, held frames and existing prop tiles.
5. **Text cannot sit on the pixel grid via SwiftUI `Text`** — hence the bundled bitmap font
   (§3.2). The mockup fakes it with a 1-bit threshold mask, which `Canvas` cannot do.
6. **`Canvas` + `TimelineView` is sufficient.** Everything reduces to "draw these sprites at
   these positions this frame", one y-sort, and a per-sprite colour multiply. No pathfinding:
   the idle wander is a 1-tile anchored oscillation and the active walk is a bounded traverse,
   both pure functions of `(pid, t)`.

---

## Appendix B — build order and acceptance

Build in this order; each step is independently verifiable against a canonical PNG.

1. **Ground fill + clumped grass.** Assert the 46×30 tile-id grid matches `FARM-1`. Check for
   diagonal streaking — its absence is the point of §4.1.
2. **Dirt set + autotiler + lanes.** Roads must terminate at `MARGIN±1`, and the barn spur
   must connect to lane 0 with no seam.
3. **Layout** — pen sizing, row packing, lane assignment, the fit rule. Verify against the
   §2.5 table at 1 / 3 / 8 / 14 / 30 pens, **and at 0** (§2.7). Verify the wrap test fires on
   an empty row (§2.2).
4. **Fences, gates, nameplates.** Bundle the font first (B1). Assert `NFQ` renders as `NFQ`
   and `DOTFILES` as `DOTFILES` — those two strings are the regression test.
5. **Animals** — union-rect frames (§3.5), slot lattice, y-sort, single-layer shadows.
   Acceptance is **same slot, same rank, same facing, baseline within ±2 px of `FARM-1`** —
   *not* pixel parity. The union-rect deviation (§0.3 #1) deliberately changes `w` and `h`
   relative to the mock's per-frame crop, which shifts `bx` by up to 2 px through
   `(slot - w)/2` and the drawn top edge by up to 2 px through `by - h`. Those few pixels
   are the fix working, not a bug — do not chase them.
6. **State cues**, in value order: frozen cool multiply → overloaded red pulse → head posture
   → forward/back offset → props → bounce. **Anchor the idle wander before shipping it, not
   after.**
7. **Woodland bands + fringe. Last** — it is garnish and it depends on the occupancy set
   already being correct.

Two whole-scene checks that no unit test will catch:

- **The idle test.** Set every session to `idle`/`frozen` and look at the window for a full
  minute. If it is boring or sad, the design has failed at its actual job — that is the state
  the farm will be in most of the time.
- **The one-second test.** Render 14 pens with exactly one `overloaded` animal somewhere in
  them and find it without reading a label.

---

## Appendix C — reference renders

| file (Desktop) | what | status |
|---|---|---|
| `FARM-1-typical.png` | 8 pens, honest distribution — 13 idle/frozen, 1 active, 0 overloaded | **canonical target** |
| `FARM-2-fourteen-pens.png` | 14 pens | canonical, density case |
| `FARM-3-single-pen-3x.png` | 1 pen @3× | canonical, sparse case |
| `FARM-4-state-cues.png` | 5 annotated cells: 4 shipping states + reserved slot | study — cell 5 is a proposal |
| `FARM-5-all-states.png` | synthetic, every state at once | study — **not representative** |
| `FARM-6-frozen-shade-test.png` | frozen shade ladder, 4 species × 5 levels | study — normative for `k` |

Regenerate any of them with `python3 scratchpad/mock7.py`; all four canonical renders come
back byte-identical **[R]**, so the mock stays usable as an oracle while porting.
