#!/usr/bin/env python3
"""states.py — the four shipping session states plus the RESERVED slot for a
future "needs attention" state, rendered side by side with the same species and
pen size so the cues can be compared directly. Cell 5 is a PROPOSAL, not spec."""
from PIL import Image, ImageDraw, ImageFont
import os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import mock7 as M

BASE = M.BASE
T, SCALE = 16, 3
PW, PH = 10, 6            # pen tiles
CELLS = [("cow", "idle"), ("cow", "frozen"), ("cow", "active"),
         ("cow", "overloaded"), ("cow", "attention")]
NOTE = {
    "idle":       ["COMMON. graze + short anchored", "wander. full colour, at trough", "quiet on purpose"],
    "frozen":     ["COMMON. held still, no motion", "cool SHADE 45% (not faded)", "back of pen. benign, quiet"],
    "active":     ["RARE. walk, traverses the pen", "head UP, steps forward,", "overlaps rail. full colour"],
    "overloaded": ["RARE. red pulse 0->0.45 +", "1px bounce. bomb 0105 badge", "= machine in trouble"],
    "attention":  ["FUTURE / RESERVED SLOT.", "at the gate, faces viewer, hops.", "red plate 0095 = wants YOU"],
}

W = PW * len(CELLS) + 2 * (len(CELLS) + 1)
H = PH + 6
img = Image.new("RGBA", (W * T, H * T), (110, 190, 90, 255))
def put(n, x, y):
    if 0 <= x < W and 0 <= y < H:
        img.alpha_composite(M.tile(n), (x * T, y * T))
for y in range(H):
    for x in range(W):
        c, l = M.hsh(x // 4, y // 3, 7) % 100, M.hsh(x, y, 13) % 100
        put(1 if (c < 24 and l < 55) else (2 if (c >= 93 and l < 35) else 0), x, y)

F_TL, F_TR, F_BL, F_BR, F_H, F_V, F_HL, F_HR = 44, 46, 68, 70, 81, 47, 80, 82
draws, badges = [], []
for i, (sp, st) in enumerate(CELLS):
    px, py = 2 + i * (PW + 2), 2
    ix, iy, iw, ih = px + 1, py + 1, PW - 2, PH - 2
    IX, IY, IW, IH = ix * T, iy * T, iw * T, ih * T
    # ground: the same static worn patch for every state. Frozen used to get an
    # overgrown pen here; that was removed -- see spec section 5.
    if True:
        cells = {(ix, iy + ih - 1), (ix + 1, iy + ih - 1), (ix, iy + ih - 2),
                 (ix + 1, iy + ih - 2), (ix + 3, iy + 1), (ix + 4, iy + 1),
                 (ix + 4, iy), (ix + 5, iy + 1), (ix + 3, iy)}
        for (x, y) in cells:
            n_, s_ = (x, y - 1) not in cells, (x, y + 1) not in cells
            w_, e_ = (x - 1, y) not in cells, (x + 1, y) not in cells
            t = 12 if (n_ and w_) else 14 if (n_ and e_) else 36 if (s_ and w_) else \
                38 if (s_ and e_) else 13 if n_ else 37 if s_ else 24 if w_ else 26 if e_ else 25
            put(t, x, y)
    gx = px + PW // 2
    put(F_TL, px, py); put(F_TR, px + PW - 1, py)
    put(F_BL, px, py + PH - 1); put(F_BR, px + PW - 1, py + PH - 1)
    for k in range(1, PW - 1):
        cx = px + k
        put(F_H, cx, py)
        put((F_HR if cx == gx - 1 else F_HL) if cx in (gx - 1, gx) else F_H, cx, py + PH - 1)
    for j in range(1, PH - 1):
        put(F_V, px, py + j); put(F_V, px + PW - 1, py + j)
    put(107, ix, iy + ih - 1); put(106, ix + 1, iy + ih - 1)

    row = 3
    spr = M.__dict__  # reuse frame loader
    sheets = {}
    def frame(a, kind, r, c):
        k = (a, kind)
        if k not in sheets:
            sheets[k] = Image.open(os.path.join(M.LPC, f"{a}_{kind}.png")).convert("RGBA")
        im = sheets[k]; fw, fh = im.size[0] // 4, im.size[1] // 4
        fr = im.crop((c * fw, r * fh, (c + 1) * fw, (r + 1) * fh))
        b = fr.getbbox()
        return fr.crop(b) if b else fr
    f = frame(sp, "eat", row, 2) if st == "idle" else \
        frame(sp, "eat", row, 3) if st == "frozen" else frame(sp, "walk", row, 1)
    if st == "attention":
        f = frame(sp, "walk", 2, 1)          # faces the viewer at the gate
    w, h = f.size
    off = max(4, h // 6)
    bx = IX + (IW - w) // 2
    by = IY + IH - 1
    if st == "idle":         by -= off
    elif st == "frozen":     by -= off + 2
    elif st == "active":     by += off
    elif st == "overloaded": by += off - 2
    elif st == "attention":  by += off + 4
    draws.append((by, f, bx, by - h, int(w * .6), st))

def recolor(im, fn):
    o = im.copy(); p = o.load()
    for y in range(o.size[1]):
        for x in range(o.size[0]):
            q = p[x, y]
            if q[3]: p[x, y] = fn(q)
    return o

final = []
for (by, f, bx, ty, sw, st) in draws:
    if st == "overloaded":
        f = recolor(f, lambda q: (min(255, int(q[0] + (255 - q[0]) * .40)),
                                  int(q[1] * .68), int(q[2] * .64), q[3]))
        badges.append((bx + f.size[0] // 2 - 8, ty - 13, 105))
    elif st == "attention":
        badges.append((bx + f.size[0] // 2 - 8, ty - 15, 95))
    elif st == "frozen":
        k = .45
        mr, mg, mb = 1 - .34 * k, 1 - .26 * k, 1 - .08 * k
        f = recolor(f, lambda q: (int(q[0] * mr), int(q[1] * mg), int(q[2] * mb), q[3]))
    final.append((by, f, bx, ty, sw, st))

sh = Image.new("RGBA", img.size, (0, 0, 0, 0)); sd = ImageDraw.Draw(sh)
for (by, f, bx, ty, sw, st) in final:
    cx = bx + f.size[0] // 2
    sd.ellipse([cx - sw // 2, by - 4, cx + sw // 2, by + 2], fill=(32, 62, 34, 80))
img.alpha_composite(sh)
for (by, f, bx, ty, sw, st) in sorted(final, key=lambda d: d[0]):
    img.alpha_composite(f, (bx, ty))
for (bx, by, n) in badges:
    img.alpha_composite(M.tile(n), (bx, by))

font = ImageFont.load_default()
d = ImageDraw.Draw(img)
WOOD_HI, WOOD, WOOD_LO, INK = (232, 174, 118, 255), (188, 122, 74, 255), (69, 38, 46, 255), (48, 26, 22, 255)
for i, (sp, st) in enumerate(CELLS):
    px = 2 + i * (PW + 2)
    s = ("+ATTENTION" if st == "attention" else st.upper())
    w, h = int(d.textlength(s, font=font)) + 8, 12
    x0, y0 = int((px + PW / 2) * T - w // 2), 2 * T + 1
    d.rectangle([x0 - 1, y0 - 1, x0 + w + 1, y0 + h], fill=WOOD_LO)
    d.rectangle([x0, y0, x0 + w, y0 + h - 1], fill=WOOD)
    d.rectangle([x0 + 1, y0 + 1, x0 + w - 1, y0 + 1], fill=WOOD_HI)
    d.text((x0 + 5, y0 + 3), s, font=font, fill=INK)
    for j, line in enumerate(NOTE[st]):
        d.text((px * T + 2, (2 + PH) * T + 6 + j * 10), line, font=font, fill=(30, 55, 28, 255))

img.resize((img.size[0] * SCALE, img.size[1] * SCALE), Image.NEAREST).convert("RGB").save(f"{BASE}/states.png")
print("wrote states.png")
