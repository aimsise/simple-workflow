#!/usr/bin/env python3
"""Generate the glanceable `/brief chain=on` overview (light + dark).

A short, landscape, large-text figure for the TOP of README.md — readable at
GitHub's ~860px content width without zooming. The exhaustive figure (agents,
hooks, harness) lives in docs/gen-brief-chain-flow.py and is linked/collapsed
below it. Renders two files for a <picture> dark-mode swap:

    docs/brief-chain-overview.png        (light)
    docs/brief-chain-overview-dark.png   (dark)

Re-generate:  python3 docs/gen-brief-chain-overview.py
Glyph rule: Arial lacks ↻ ★ ⇄ ≤ — use only ASCII plus → · — ×.
"""

import os
from PIL import Image, ImageDraw, ImageFont

S = 2
W, H = 960, 640
HERE = os.path.dirname(os.path.abspath(__file__))

_FONTS = {
    False: ["/System/Library/Fonts/Supplemental/Arial.ttf",
            "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf", "/Library/Fonts/Arial.ttf"],
    True: ["/System/Library/Fonts/Supplemental/Arial Bold.ttf",
           "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf", "/Library/Fonts/Arial Bold.ttf"],
}
_fc = {}


def font(size, bold=False):
    k = (round(size, 1), bold)
    if k in _fc:
        return _fc[k]
    f = None
    for p in _FONTS[bold]:
        if os.path.exists(p):
            try:
                f = ImageFont.truetype(p, int(round(size * S))); break
            except Exception:
                pass
    _fc[k] = f or ImageFont.load_default()
    return _fc[k]


def P(v):
    return int(round(v * S))


LIGHT = {
    "bg": (255, 255, 255), "ink": (17, 24, 39), "gray": (107, 114, 128), "line": (71, 85, 105),
    "skill": ((219, 234, 254), (37, 99, 235), (30, 58, 138)),
    "agent": ((220, 252, 231), (22, 163, 74), (20, 83, 45)),
    "io": ((241, 245, 249), (100, 116, 139), (51, 65, 85)),
    "pr": ((237, 233, 254), (124, 58, 237), (76, 29, 149)),
    "loop": (220, 38, 38), "labelbg": (255, 255, 255),
}
DARK = {
    "bg": (13, 17, 23), "ink": (230, 237, 243), "gray": (148, 158, 170), "line": (139, 148, 158),
    "skill": ((23, 37, 64), (96, 165, 250), (191, 219, 254)),
    "agent": ((18, 46, 33), (74, 222, 128), (187, 247, 208)),
    "io": ((30, 41, 59), (113, 128, 150), (203, 213, 225)),
    "pr": ((45, 40, 74), (167, 139, 250), (221, 214, 254)),
    "loop": (248, 113, 113), "labelbg": (13, 17, 23),
}

d = None
C = None


def box(x0, y0, x1, y1, role, width=2.4, radius=11):
    fill, bd, _ = C[role] if role in ("skill", "agent", "io", "pr") else (None, role, None)
    d.rounded_rectangle([P(x0), P(y0), P(x1), P(y1)], radius=P(radius), fill=fill, outline=bd, width=P(width))


def text(x, y, s, size=12, color=None, bold=False, anchor="lm"):
    d.text((P(x), P(y)), s, font=font(size, bold), fill=color or C["ink"], anchor=anchor)


def text_bg(x, y, s, size=11, color=None, bold=True):
    f = font(size, bold)
    w = f.getlength(s) / S
    d.rectangle([P(x - w / 2 - 5), P(y - size * 0.75), P(x + w / 2 + 5), P(y + size * 0.75)], fill=C["labelbg"])
    d.text((P(x), P(y)), s, font=f, fill=color or C["ink"], anchor="mm")


def rich(x, y, segs, size=12):
    cx = x
    for t, col, b in segs:
        f = font(size, b)
        d.text((P(cx), P(y)), t, font=f, fill=col, anchor="lm")
        cx += f.getlength(t) / S
    return cx


def ahead(x, y, dr, size=7, color=None):
    color = color or C["line"]
    if dr == "down":
        p = [(x, y), (x - size, y - size * 1.5), (x + size, y - size * 1.5)]
    elif dr == "up":
        p = [(x, y), (x - size, y + size * 1.5), (x + size, y + size * 1.5)]
    elif dr == "right":
        p = [(x, y), (x - size * 1.5, y - size), (x - size * 1.5, y + size)]
    else:
        p = [(x, y), (x + size * 1.5, y - size), (x + size * 1.5, y + size)]
    d.polygon([(P(a), P(b)) for a, b in p], fill=color)


def varrow(x, y0, y1, color=None):
    d.line([P(x), P(y0), P(x), P(y1)], fill=color or C["line"], width=P(2.4))
    ahead(x, y1, "down", color=color)


def harrow(x0, x1, y):
    d.line([P(x0), P(y), P(x1), P(y)], fill=C["line"], width=P(2.4))
    ahead(x1, y, "right")


def dashed(x0, y0, x1, y1, color, width=2.2, dash=10, gap=6):
    import math
    dist = math.hypot(x1 - x0, y1 - y0)
    if dist == 0:
        return
    ux, uy = (x1 - x0) / dist, (y1 - y0) / dist
    pos = 0.0
    while pos < dist:
        seg = min(dash, dist - pos)
        d.line([P(x0 + ux * pos), P(y0 + uy * pos), P(x0 + ux * (pos + seg)), P(y0 + uy * (pos + seg))],
               fill=color, width=P(width))
        pos += dash + gap


def dashed_rect(x0, y0, x1, y1, color, width=2.4, dash=12, gap=7):
    dashed(x0, y0, x1, y0, color, width, dash, gap)
    dashed(x1, y0, x1, y1, color, width, dash, gap)
    dashed(x1, y1, x0, y1, color, width, dash, gap)
    dashed(x0, y1, x0, y0, color, width, dash, gap)


def swatch(x, y, role, label, dash=False):
    if dash:
        dashed(x, y, x + 24, y, C["loop"], 2.8, 6, 3)
        tx = x + 32
    else:
        fill, bd, _ = C[role]
        d.rounded_rectangle([P(x), P(y - 7), P(x + 22), P(y + 7)], radius=P(3), fill=fill, outline=bd, width=P(1.8))
        tx = x + 30
    text(tx, y, label, size=12.5, color=C["ink"])
    return tx + font(12.5).getlength(label) / S + 28


def build(theme, out):
    global d, C
    C = theme
    img = Image.new("RGB", (W * S, H * S), C["bg"])
    globals()["d"] = ImageDraw.Draw(img)

    AG = C["agent"][2]
    SK = C["skill"][2]
    IO = C["io"][2]
    GR = C["gray"]

    # header
    text(40, 40, "How  /brief chain=on  runs", size=22, bold=True, color=C["ink"])
    lx = swatch(40, 80, "skill", "skill")
    lx = swatch(lx, 80, "agent", "subagent")
    lx = swatch(lx, 80, None, "loop", dash=True)

    # ---- band 1: setup chain ----
    bw = (880 - 88) / 3
    xs = [40, 40 + bw + 44, 40 + 2 * (bw + 44)]
    by0, by1 = 104, 192
    titles = [("/brief", [[("spawns ", C["ink"], False), ("researcher", AG, True)],
                          [("writes brief.md + policy", IO, False)]]),
              ("/create-ticket", [[("splits scope into N tickets", C["ink"], False)],
                                  [("agents: ", C["ink"], False), ("decomposer, planner", AG, True)]]),
              ("/autopilot", [[("orchestrates the run", C["ink"], False)],
                              [("ticket-by-ticket (topological)", C["ink"], False)]])]
    for x0, (nm, lines) in zip(xs, titles):
        box(x0, by0, x0 + bw, by1, "skill")
        text(x0 + 14, by0 + 24, nm, size=15.5, bold=True, color=SK)
        rich(x0 + 14, by0 + 50, lines[0], size=11.5)
        rich(x0 + 14, by0 + 70, lines[1], size=11.5)
    harrow(xs[0] + bw, xs[1], (by0 + by1) / 2)
    harrow(xs[1] + bw, xs[2], (by0 + by1) / 2)

    # autopilot -> loop
    apx = xs[2] + bw / 2
    varrow(apx, by1, 224)

    # ---- per-ticket loop container ----
    LX0, LY0, LX1, LY1 = 40, 228, 920, 452
    dashed_rect(LX0, LY0, LX1, LY1, C["loop"])
    text(LX0 + 16, LY0 + 18, "PER-TICKET LOOP  —  repeats for each ticket", size=13.5, bold=True, color=C["loop"])
    text(LX0 + 16, LY0 + 38, "(auto-/compact resets the context window between tickets)", size=10.5, color=C["loop"])

    ibw = (848 - 80) / 3
    ix = [56, 56 + ibw + 40, 56 + 2 * (ibw + 40)]
    iy0, iy1 = 290, 400
    sc = [("/scout", [[("investigate + plan", C["ink"], False)],
                      [("researcher · planner", AG, True)]]),
          ("/impl", [[("verify loop", C["loop"], True), (" — Generator/Evaluator, max 9", C["ink"], False)],
                    [("implementer · ac-evaluator", AG, True)]]),
          ("/ship", [[("commit + open PR", C["ink"], False)],
                    [("learns via ", C["ink"], False), ("/tune", SK, True)]])]
    for x0, (nm, lines) in zip(ix, sc):
        box(x0, iy0, x0 + ibw, iy1, "skill")
        text(x0 + 12, iy0 + 22, nm, size=15, bold=True, color=SK)
        rich(x0 + 12, iy0 + 48, lines[0], size=11.5)
        rich(x0 + 12, iy0 + 70, lines[1], size=11.5)
    harrow(ix[0] + ibw, ix[1], (iy0 + iy1) / 2)
    harrow(ix[1] + ibw, ix[2], (iy0 + iy1) / 2)

    # loop-back arrow (under boxes)
    scx = ix[0] + ibw / 2
    shx = ix[2] + ibw / 2
    lby = 426
    dashed(shx, iy1, shx, lby, C["loop"], 2.4, 9, 6)
    dashed(shx, lby, scx, lby, C["loop"], 2.4, 9, 6)
    dashed(scx, lby, scx, iy1, C["loop"], 2.4, 9, 6)
    ahead(scx, iy1 + 2, "up", color=C["loop"])
    text_bg((scx + shx) / 2, lby, "yes — next ticket", size=10.5, color=C["loop"])

    # loop -> PR
    varrow((LX0 + LX1) / 2, LY1, 488)
    text_bg((LX0 + LX1) / 2 + 92, (LY1 + 488) / 2, "all tickets done", size=10, color=GR)

    PX0, PX1 = 320, 640
    box(PX0, 488, PX1, 540, "pr")
    text((PX0 + PX1) / 2, 514, "All tickets shipped  →  Pull Request(s)", size=13, bold=True, color=C["pr"][2], anchor="mm")

    # caption (ties to harness + points to detail)
    text(40, 578, "Throughout, lifecycle hooks DRIVE the loop (the Stop hook re-injects \"continue\") and GUARD every write,",
         size=11.5, color=GR)
    rich(40, 598, [("and each subagent runs in an isolated context (information firewall).  ", GR, False),
                  ("Full flow — agents · hooks · harness — below.", C["ink"], True)], size=11.5)

    img.save(out)
    print("wrote", out, img.size)


build(LIGHT, os.path.join(HERE, "brief-chain-overview.png"))
build(DARK, os.path.join(HERE, "brief-chain-overview-dark.png"))
