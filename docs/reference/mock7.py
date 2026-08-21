#!/usr/bin/env python3
"""mock7 — Farm scene, pass 4. The layout is COMPUTED, so this file doubles as
the spec for the Swift implementation.

Algorithm
  1. pen size  = f(species footprint, animal count)      -> occupancy-sized pens
  2. row pack  = greedy left-to-right in deterministic order, wrap on overflow
                 (row 1 reserves the barn's slot first)
  3. lane      = 2-tile dirt road between every pair of rows; pens gate onto the
                 nearest lane (S if there is a lane below, else N)
  4. leftovers = orchard rows / woodland / hedges, placed by seeded hash so they
                 never move between frames
"""
from PIL import Image, ImageDraw, ImageFont
import os, math, random, sys

BASE = "/private/tmp/claude-502/-Users-albert-Projects-watchagents/7d0a172a-20d2-456f-8859-352dc8ac7f6f/scratchpad"
TILES, LPC = f"{BASE}/kenney/Tiles", f"{BASE}/lpc"
T = 16

_cache = {}
def tile(n):
    if n not in _cache:
        _cache[n] = Image.open(os.path.join(TILES, f"tile_{n:04d}.png")).convert("RGBA")
    return _cache[n]

def hsh(*a):
    h = 2166136261
    for v in a:
        h = ((h ^ (int(v) & 0xFFFFFFFF)) * 16777619) & 0xFFFFFFFF
    return h

# species footprint in tiles, from the measured side-view bboxes
FOOT = {"cow": (5, 3), "sheep": (4, 3), "pig": (4, 2), "chicken": (3, 2)}

def pen_size(species, n):
    fw, fh = FOOT[species]
    rows = 1 if n <= 2 else 2
    cols = math.ceil(n / rows)
    iw = cols * fw + 1
    ih = fh + (rows - 1) + 1
    return max(7, iw + 2), max(5, ih + 2)

# ---------------------------------------------------------------------------
def render(project_list, out, COLS, ROWS, SCALE, seed0=1):
    """project_list: [(name, species, [states...])] in deterministic order"""
    world = Image.new("RGBA", (COLS * T, ROWS * T), (110, 190, 90, 255))
    def put(n, cx, cy):
        if 0 <= cx < COLS and 0 <= cy < ROWS:
            world.alpha_composite(tile(n), (cx * T, cy * T))

    # ---------------------------------------------------------- ground ------
    GRASS = {}
    for y in range(ROWS):
        for x in range(COLS):
            c, l = hsh(x // 4, y // 3, 7) % 100, hsh(x, y, 13) % 100
            n = 1 if (c < 24 and l < 55) else (2 if (c >= 93 and l < 35) else (1 if l < 4 else 0))
            GRASS[(x, y)] = n
            put(n, x, y)

    # ---------------------------------------------------------- layout ------
    MARGIN_L, MARGIN_R, MARGIN_T = 4, 4, 3
    FRAME_B = 4                      # rows reserved for the bottom treeline
    GAP = 2                      # tiles between pens in a row
    LANE_H = 2

    BARN_W, BARN_H = 7, 4
    avail = COLS - MARGIN_L - MARGIN_R

    sized = [(nm, sp, sts) + pen_size(sp, len(sts)) for (nm, sp, sts) in project_list]

    rows, cur, curw = [], [], BARN_W + GAP + 1     # barn occupies the head of row 1
    for item in sized:
        w = item[3]
        # NOTE: the wrap test must run even when the row is empty, otherwise the
        # first pen of row 0 is placed past the barn regardless of window width.
        if curw + w > avail and (cur or curw > 0):
            rows.append(cur); cur, curw = [], 0
            if w > avail:                      # still too wide: nothing more to give
                pass
        cur.append(item); curw += w + GAP
    if cur:
        rows.append(cur)
    rows = [r for r in rows if r]

    # vertical placement
    placed, y = [], MARGIN_T
    row_bands = []
    for ri, row in enumerate(rows):
        rh = max(it[4] for it in row)
        x = MARGIN_L + (BARN_W + GAP + 1 if ri == 0 else 0)
        for it in row:
            nm, sp, sts, pw, ph = it
            placed.append((nm, sp, sts, x, y + (rh - ph), pw, ph, ri))
            x += pw + GAP
        row_bands.append((y, rh))
        y += rh + LANE_H
    lanes = [row_bands[i][0] + row_bands[i][1] for i in range(len(row_bands) - 1)]
    needed_h = y - LANE_H + FRAME_B
    if needed_h > ROWS:
        print(f"  !! layout needs {needed_h} rows, window has {ROWS}: "
              f"drop scale or scroll (never clip a pen)")
    max_pen_w = max(it[3] for it in sized) if sized else 0
    if max_pen_w + BARN_W + GAP + 1 + MARGIN_L + MARGIN_R > COLS:
        print(f"  !! widest pen {max_pen_w} does not fit beside the barn at COLS={COLS}")

    BARN_X, BARN_Y = MARGIN_L, row_bands[0][0] + row_bands[0][1] - BARN_H

    pens = []
    for (nm, sp, sts, px, py, pw, ph, ri) in placed:
        if ri < len(rows) - 1:
            gate, lane = "S", lanes[ri]
        else:
            gate, lane = ("N", lanes[ri - 1]) if ri > 0 else ("S", None)
        pens.append((nm, sp, sts, px, py, pw, ph, gate, lane, hsh(nm.encode()[0] if nm else 0, len(nm), ri)))

    # ------------------------------------------------------ dirt autotile ----
    dirt = set()
    def rect(x, y, w, h):
        for j in range(h):
            for i in range(w):
                if 0 <= x + i < COLS and 0 <= y + j < ROWS:
                    dirt.add((x + i, y + j))
    for ly in lanes:
        rect(MARGIN_L + 1, ly, avail - 2, LANE_H)
    if lanes:
        rect(BARN_X + 2, BARN_Y + BARN_H, 3, lanes[0] - (BARN_Y + BARN_H))
    rect(BARN_X + 1, BARN_Y + BARN_H, 5, 2)

    for (nm, sp, sts, px, py, pw, ph, gate, lane, sd) in pens:
        ix, iy, iw, ih = px + 1, py + 1, pw - 2, ph - 2
        r = random.Random(sd)
        gx = px + pw // 2
        cells = {(ix, iy + ih - 1), (ix + 1, iy + ih - 1), (ix, iy + ih - 2), (ix + 1, iy + ih - 2)}
        cells |= {(gx - 1, iy + ih - 1), (gx, iy + ih - 1)} if gate == "S" else {(gx - 1, iy), (gx, iy)}
        cx = ix + 2 + r.randrange(max(1, iw - 4)); cy = iy + r.randrange(max(1, ih - 1))
        for dy in range(-1, 2):
            for dx in range(-2, 3):
                if abs(dx) + abs(dy) * 2 <= 2 + r.randrange(2):
                    cells.add((cx + dx, cy + dy))
        for (x, y_) in cells:
            if ix <= x < ix + iw and iy <= y_ < iy + ih:
                dirt.add((x, y_))
        if lane is not None:                      # threshold from gate to lane
            if gate == "S":
                for yy in range(py + ph - 1, lane):
                    dirt.add((gx - 1, yy)); dirt.add((gx, yy))
            else:
                for yy in range(lane + LANE_H, py + 1):
                    dirt.add((gx - 1, yy)); dirt.add((gx, yy))

    for (x, y_) in sorted(dirt):
        n, s = (x, y_ - 1) not in dirt, (x, y_ + 1) not in dirt
        w, e = (x - 1, y_) not in dirt, (x + 1, y_) not in dirt
        if n and w:   t = 12
        elif n and e: t = 14
        elif s and w: t = 36
        elif s and e: t = 38
        elif n:       t = 13
        elif s:       t = 37
        elif w:       t = 24
        elif e:       t = 26
        else:
            rr = hsh(x, y_, 5) % 100
            t = 25 if rr < 70 else (39 if rr < 80 else (40 if rr < 88 else (41 if rr < 94 else 42)))
        put(t, x, y_)

    # ------------------------------------------------------------ barn -------
    def barn(x, y, w, h):
        for i in range(w):
            put(52 if i == 0 else (54 if i == w - 1 else 53), x + i, y)
        put(55, x + w // 2, y)
        for i in range(w):
            put(64 if i == 0 else (66 if i == w - 1 else 65), x + i, y + 1)
        for j in range(2, h):
            for i in range(w):
                put(72 if i == 0 else (75 if i == w - 1 else 73), x + i, y + j)
        gy = y + h - 1
        put(84, x + 1, gy); put(84, x + w - 2, gy)
        put(74, x + w // 2 - 1, gy); put(74, x + w // 2, gy)
    barn(BARN_X, BARN_Y, BARN_W, BARN_H)

    # ----------------------------------------------------------- scenery -----
    occupied = set(dirt)
    def mark(x, y, w=1, h=1):
        for j in range(h):
            for i in range(w):
                occupied.add((x + i, y + j))
    for (nm, sp, sts, px, py, pw, ph, g, l, sd) in pens:
        mark(px - 1, py - 1, pw + 2, ph + 2)
    mark(BARN_X - 1, BARN_Y - 1, BARN_W + 2, BARN_H + 2)
    for ly in lanes:
        mark(MARGIN_L - 1, ly - 1, COLS - MARGIN_L - MARGIN_R + 2, LANE_H + 2)

    def clear(x, y, w=1, h=1):
        for j in range(h):
            for i in range(w):
                if not (0 <= x + i < COLS and 0 <= y + j < ROWS): return False
                if (x + i, y + j) in occupied: return False
        return True

    def small_tree(x, y, au): put(3 if au else 4, x, y); put(15 if au else 16, x, y + 1)
    # Tiles 0006-0008 / 0018-0020 (and autumn 0009-0011 / 0021-0023) are
    # deliberately NOT used anywhere. See the note on stand() below.

    def scatter(cands, x0, y0, x1, y1, n, seed):
        r = random.Random(seed)
        for _ in range(n * 12):
            if n <= 0: break
            x = r.randrange(x0, max(x0 + 1, x1)); y = r.randrange(y0, max(y0 + 1, y1))
            if clear(x, y):
                put(r.choice(cands), x, y); mark(x, y); n -= 1

    def orchard(x0, y0, x1, y1, seed):
        """planted rows — reads as agriculture, contrasts with wild woodland"""
        items = []
        for j, y in enumerate(range(y0, y1 - 1, 3)):
            off = 1 if j % 2 else 0
            for x in range(x0 + off, x1, 3):
                if clear(x, y, 1, 2):
                    mark(x, y, 1, 2)
                    items.append((y, x, hsh(x, y, seed) % 100 < 22))
        for (y, x, au) in sorted(items):
            small_tree(x, y, au)

    # ---- TREE STANDS ------------------------------------------------------
    # Woodland is dense stands of the 2-tall single tree (0004/0016, autumn
    # 0003/0015) at 1-tile spacing, drawn BACK TO FRONT so canopies overlap and
    # hide the trunks behind them.
    #
    # This REPLACES an earlier "canopy band" attempt that tiled 0006/0007/0008
    # over 0018/0019/0020. Those are forest-INTERIOR pieces whose dark outlines
    # are meant to continue into their neighbours; with open grass above them the
    # top arcs dangle unattached and the band reads as an upside-down cave
    # ceiling. A single tree has an unambiguous silhouette -- canopy on top,
    # trunk at the bottom -- and cannot read upside down at any density.
    def stand(x0, x1, y0, y1, seed, density=0.80, autumn=0.18, ramp=None):
        """ramp = per-row density multipliers from the OUTER edge inward. That
        thinning is what makes the treeline ragged instead of a solid ribbon."""
        x0, x1 = max(0, x0), min(COLS, x1)
        y0, y1 = max(0, y0), min(ROWS - 1, y1)
        items = []
        for ri, y in enumerate(range(y0, y1)):
            d = density * (ramp[min(ri, len(ramp) - 1)] if ramp else 1.0)
            for x in range(x0, x1):
                h = hsh(x, y, seed)
                if h % 100 >= int(d * 100):
                    continue
                yy = y + ((h >> 7) % 2)
                if not clear(x, yy, 1, 2):
                    continue
                mark(x, yy + 1, 1, 1)      # reserve the TRUNK only -> canopies nest
                items.append((yy, x, (h >> 13) % 100 < int(autumn * 100)))
        for (y, x, au) in sorted(items):
            small_tree(x, y, au)

    RAMP = (1.0, 0.85, 0.55, 0.30)         # dense at the edge, thinning inward

    stand(0, COLS, 0, MARGIN_T, seed0 * 3 + 1, ramp=RAMP)
    stand(0, COLS, ROWS - FRAME_B, ROWS - 1, seed0 * 3 + 4, ramp=tuple(reversed(RAMP)))
    stand(0, MARGIN_L - 1, MARGIN_T, ROWS - FRAME_B, seed0 * 3 + 2, density=0.72)
    stand(COLS - MARGIN_R + 1, COLS, MARGIN_T, ROWS - FRAME_B, seed0 * 3 + 3, density=0.72)
    if BARN_Y >= 3:
        stand(BARN_X - 1, BARN_X + BARN_W + 1, max(0, BARN_Y - 2), BARN_Y,
              seed0 * 3 + 5, density=0.75)

    # Leftover space in the final row: a COMPACT orchard block + clustered
    # features, never a uniform fill. Open lawn is allowed — it is framed.
    if placed:
        last_row_y, last_row_h = row_bands[-1]
        last_x = max(p[3] + p[5] for p in placed if p[7] == len(rows) - 1)
        gapw = COLS - 3 - (last_x + 3)
        if gapw > 10:
            ox = COLS - 3 - 11
            orchard(ox, last_row_y, ox + 11, last_row_y + min(last_row_h, 7), seed0 * 7)
            scatter([5, 5, 28, 27], ox - 2, last_row_y - 1, ox + 12,
                    last_row_y + last_row_h + 1, 10, seed0 * 11)
            # a tidy hay yard gives the open lawn a destination
            hx, hy = last_x + 4, last_row_y + 1
            for i, n in enumerate((93, 93)):
                if clear(hx + i, hy): put(n, hx + i, hy); mark(hx + i, hy)
            if clear(hx, hy + 1): put(94, hx, hy + 1); mark(hx, hy + 1)
            if clear(hx + 1, hy + 1): put(93, hx + 1, hy + 1); mark(hx + 1, hy + 1)
            scatter([5, 5, 28], last_x + 2, last_row_y + 2,
                    last_x + 9, last_row_y + last_row_h + 1, 5, seed0 * 17)

    for ly in lanes:                      # hedge shoulders break up the road
        scatter([5, 28, 27], MARGIN_L, ly - 1, COLS - MARGIN_R, ly + LANE_H + 1, 12, ly * 97 + seed0)
    scatter([5, 5, 28, 27], 2, 2, COLS - 2, ROWS - 2, 12, seed0 * 13)

    for i in range(300):
        x, y = hsh(i, 1, seed0) % COLS, hsh(i, 2, seed0) % ROWS
        if clear(x, y) and GRASS.get((x, y)) == 1 and hsh(i, 3) % 100 < 26:
            put(29 if hsh(i, 4) % 4 == 0 else 17, x, y); mark(x, y)

    # ------------------------------------------------------ farmyard props ---
    def prop(n, x, y): put(n, x, y); occupied.add((x, y))
    prop(93, BARN_X + BARN_W, BARN_Y + BARN_H - 1)
    prop(93, BARN_X + BARN_W, BARN_Y + BARN_H - 2)
    prop(94, BARN_X + BARN_W + 1, BARN_Y + BARN_H - 1)
    prop(116, BARN_X - 1, BARN_Y + BARN_H - 1)
    prop(106, BARN_X + BARN_W, BARN_Y + BARN_H + 1)
    prop(107, BARN_X + BARN_W + 1, BARN_Y + BARN_H + 1)
    prop(130, BARN_X - 1, BARN_Y + BARN_H + 1)
    if lanes:
        prop(57, BARN_X + 5, lanes[0] - 1)          # mailbox
        prop(83, BARN_X + 2, lanes[0] + LANE_H)     # signpost at the crossroads

    # ------------------------------------------------------------- fences ----
    F_TL, F_TR, F_BL, F_BR, F_H, F_V, F_HL, F_HR = 44, 46, 68, 70, 81, 47, 80, 82
    for (nm, sp, sts, x, y, w, h, gate, lane, sd) in pens:
        gx = x + w // 2
        tg = {gx - 1, gx} if gate == "N" else set()
        bg = {gx - 1, gx} if gate == "S" else set()
        put(F_TL, x, y); put(F_TR, x + w - 1, y)
        put(F_BL, x, y + h - 1); put(F_BR, x + w - 1, y + h - 1)
        for i in range(1, w - 1):
            cx = x + i
            put((F_HR if cx == gx - 1 else F_HL) if cx in tg else F_H, cx, y)
            put((F_HR if cx == gx - 1 else F_HL) if cx in bg else F_H, cx, y + h - 1)
        for j in range(1, h - 1):
            put(F_V, x, y + j); put(F_V, x + w - 1, y + j)

    # --------------------------------------------------- pen interior --------
    for (nm, sp, sts, px, py, pw, ph, gate, lane, sd) in pens:
        ix, iy, iw, ih = px + 1, py + 1, pw - 2, ph - 2
        put(107, ix, iy + ih - 1)          # every pen keeps its trough
        put(106, ix + 1, iy + ih - 1)

    # ----------------------------------------------------------- animals -----
    sheets = {}
    def frame(a, kind, row, col):
        k = (a, kind)
        if k not in sheets:
            sheets[k] = Image.open(os.path.join(LPC, f"{a}_{kind}.png")).convert("RGBA")
        im = sheets[k]; fw, fh = im.size[0] // 4, im.size[1] // 4
        fr = im.crop((col * fw, row * fh, (col + 1) * fw, (row + 1) * fh))
        b = fr.getbbox()
        return fr.crop(b) if b else fr

    def recolor(img, fn):
        out = img.copy(); px = out.load()
        for y in range(out.size[1]):
            for x in range(out.size[0]):
                p = px[x, y]
                if p[3]: px[x, y] = fn(p)
        return out
    def hot(img, amt=0.40):
        return recolor(img, lambda p: (min(255, int(p[0] + (255 - p[0]) * amt)),
                                       int(p[1] * (1 - amt * .8)), int(p[2] * (1 - amt * .9)), p[3]))
    def shade(img, k=0.45):
        """Cool multiplicative shade -- 'asleep in shadow', NOT a ghost.
        Desaturation was tried and fails: sheep/chicken/cow are near-white and
        have no saturation to remove. Multiplying darkens white too. Alpha fade
        was also tried and reads as broken/absent, which is wrong for a common
        benign state (see cue_test.png / cue_test2.png)."""
        mr, mg, mb = 1 - .34 * k, 1 - .26 * k, 1 - .08 * k
        return recolor(img, lambda p: (int(p[0] * mr), int(p[1] * mg), int(p[2] * mb), p[3]))

    Lf, Rt = 1, 3
    draws, badges = [], []
    for (nm, sp, sts, px, py, pw, ph, gate, lane, sd) in pens:
        ix, iy, iw, ih = px + 1, py + 1, pw - 2, ph - 2
        IX, IY, IW, IH = ix * T, iy * T, iw * T, ih * T
        imgs = []
        for i, st in enumerate(sts):
            f = Rt if i % 2 == 0 else Lf
            img = frame(sp, "eat", f, 2) if st == "idle" else \
                  frame(sp, "eat", f, 3) if st == "frozen" else \
                  frame(sp, "walk", f, (i * 2 + 1) % 4)
            imgs.append((st, img))
        wmax = max(im.size[0] for (_, im) in imgs)
        hmax = max(im.size[1] for (_, im) in imgs)
        ncols = max(1, min(len(imgs), IW // (wmax + 4)))
        nrows = max(1, math.ceil(len(imgs) / ncols))
        depth = 11 if hmax < 34 else 8
        span = IW - 6
        for i, (st, img) in enumerate(imgs):
            col, row = i % ncols, i // ncols
            w, h = img.size
            rank = nrows - 1 - row
            slot = span / ncols
            bx = IX + 3 + int(col * slot + (slot - w) / 2)
            by = IY + IH - 1 - rank * depth
            # STATE -> POSITION. idle animals hang back at the rail with their
            # heads down; working animals come FORWARD toward the viewer and
            # overlap the bottom rail (y-sorted), which reads even in a still.
            off = max(4, h // 6)
            if st == "idle":         by -= off
            elif st == "frozen":     by -= off + 2; bx += 4
            elif st == "active":     by += off; bx += off
            elif st == "overloaded": by += off - 2; bx += off - 2   # +bounce
            bx = max(IX + 2, min(bx, IX + IW - w - 2))
            by = max(IY + h + 1, min(by, IY + IH + 8))
            if st == "overloaded":
                # 0105 (bomb) = machine danger. 0095 (red plate) is RESERVED for
                # the future 'needs attention' state, which must out-shout this.
                img = hot(img); badges.append((bx + w // 2 - 8, by - h - 13, 105))
            elif st == "frozen":
                img = shade(img)
            draws.append((by, img, bx, by - h, int(w * .6), st))

    draws.append(((BARN_Y + BARN_H) * T + 18, tile(103),
                  (BARN_X + BARN_W - 1) * T + 2, (BARN_Y + BARN_H) * T + 2, 10, "idle"))

    sh = Image.new("RGBA", world.size, (0, 0, 0, 0)); sdw = ImageDraw.Draw(sh)
    for (sy, img, x, y, sw, st) in draws:
        cx = x + img.size[0] // 2
        sdw.ellipse([cx - sw // 2, sy - 4, cx + sw // 2, sy + 2], fill=(32, 62, 34, 80))
    world.alpha_composite(sh)
    for (sy, img, x, y, sw, st) in sorted(draws, key=lambda d: d[0]):
        world.alpha_composite(img, (int(x), int(y)))
    for (bx, by, n) in badges:
        world.alpha_composite(tile(n), (int(bx), int(by)))

    # ------------------------------------------------------------ labels -----
    font = ImageFont.load_default()
    d1 = ImageDraw.Draw(world)
    WOOD_HI, WOOD, WOOD_LO, INK = (232, 174, 118, 255), (188, 122, 74, 255), (69, 38, 46, 255), (48, 26, 22, 255)
    for (nm, sp, sts, px, py, pw, ph, gate, lane, sd) in pens:
        text, maxpx = nm.upper(), (pw - 1) * T
        s = text
        while d1.textlength(s, font=font) + 9 > maxpx and len(s) > 3: s = s[:-1]
        if s != text: s = s[:-1] + "…"
        w, h = int(d1.textlength(s, font=font)) + 9, 15
        x0, y0 = int((px + pw / 2) * T - w // 2), int(py * T + 14 - h)
        d1.rectangle([x0 - 1, y0 - 1, x0 + w + 1, y0 + h], fill=WOOD_LO)
        d1.rectangle([x0, y0, x0 + w, y0 + h - 1], fill=WOOD)
        d1.rectangle([x0 + 1, y0 + 1, x0 + w - 1, y0 + 1], fill=WOOD_HI)
        # Crisp, non-antialiased glyphs: render to a mask and threshold. This is
        # what a bundled bitmap font (Silkscreen / Press Start 2P) gives you for
        # free; SwiftUI Text antialiasing turns to mush on the wood at this size.
        m = Image.new("L", (w + 2, h + 2), 0)
        ImageDraw.Draw(m).text((5, 3), s, font=font, fill=255)
        m = m.point(lambda v: 255 if v > 100 else 0)
        world.paste(INK[:3] + (255,), (x0, y0), m)

    world.resize((COLS * T * SCALE, ROWS * T * SCALE), Image.NEAREST).convert("RGB").save(out)
    print("wrote", out, "rows:", len(rows), "lanes:", lanes)


# TYPICAL farm. Claude's work happens server-side, so local CPU sits near zero:
# `idle` and `frozen` are the common states and `active` is a brief flicker.
# This is the honest distribution and the real test of "is it nice to look at
# when nothing is happening".
TYPICAL = [
    ("watchagents", "cow",     ["idle", "frozen"]),
    ("nfq",         "chicken", ["frozen", "idle", "frozen", "frozen"]),
    ("vestio-admin","sheep",   ["idle"]),
    ("sadbits",     "pig",     ["frozen", "idle"]),
    ("feat+body-type-questionnaire", "cow", ["active"]),
    ("albert",      "chicken", ["idle", "frozen", "frozen"]),
    ("seedling",    "sheep",   ["frozen"]),
    ("dotfiles",    "pig",     ["idle"]),
]

# SYNTHETIC — every state at once. Not representative; for cue comparison only.
ALLSTATES = [
    ("watchagents", "cow",     ["active", "idle"]),
    ("nfq",         "chicken", ["active", "idle", "idle", "idle"]),
    ("vestio-admin","sheep",   ["idle"]),
    ("sadbits",     "pig",     ["idle", "active"]),
    ("feat+body-type-questionnaire", "cow", ["overloaded"]),
    ("albert",      "chicken", ["active", "idle", "overloaded"]),
    ("seedling",    "sheep",   ["frozen"]),
    ("dotfiles",    "pig",     ["frozen"]),
]

DENSE = TYPICAL + [
    ("kernel-notes", "sheep",  ["frozen"]),
    ("mailer",       "chicken",["idle", "frozen"]),
    ("tui-sandbox",  "pig",    ["frozen"]),
    ("infra",        "cow",    ["idle"]),
    ("scratch",      "chicken",["frozen"]),
    ("db-migrate",   "sheep",  ["overloaded"]),
]

if __name__ == "__main__":
    render(TYPICAL,   f"{BASE}/mockup7.png", 46, 30, 2)
    render(ALLSTATES, f"{BASE}/mockup7-allstates.png", 46, 30, 2)
    render(DENSE, f"{BASE}/mockup7-dense.png", 52, 40, 2, seed0=5)
    render(TYPICAL[:1], f"{BASE}/mockup7-one.png", 32, 20, 3, seed0=9)
