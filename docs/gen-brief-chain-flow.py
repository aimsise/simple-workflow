#!/usr/bin/env python3
"""Generate the detailed `/brief chain=on` execution flow (light + dark).

Renders, with Pillow only (no external diagram toolchain), an annotated flowchart
of the default `/brief chain=on` path: what each phase does, which subagents it
spawns, what it writes, what is handed off *between* phases, which lifecycle hooks
fire, where the two nested loops are, and which harness mechanism governs each
step. Collapsed under a <details> in README.md. Emits two files for a <picture>
dark-mode swap:

    docs/brief-chain-flow.png        (light)
    docs/brief-chain-flow-dark.png   (dark)

Re-generate from anywhere:  python3 docs/gen-brief-chain-flow.py
Glyph rule: Arial lacks ↻ ↺ ★ ⇄ ≤ (they render as tofu boxes), so we use only
ASCII plus the safe arrows → · — × and draw loop/marker glyphs as shapes.
"""

import os
from PIL import Image, ImageDraw, ImageFont

# ---------------------------------------------------------------- canvas / scale
S = 2
W, H = 1200, 2000
HERE = os.path.dirname(os.path.abspath(__file__))

# ------------------------------------------------------------------------- fonts
_FONT_CANDIDATES = {
    False: ["/System/Library/Fonts/Supplemental/Arial.ttf",
            "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf", "/Library/Fonts/Arial.ttf"],
    True: ["/System/Library/Fonts/Supplemental/Arial Bold.ttf",
           "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf", "/Library/Fonts/Arial Bold.ttf"],
}
_font_cache = {}


def font(size, bold=False):
    key = (round(size, 1), bold)
    if key in _font_cache:
        return _font_cache[key]
    f = None
    for path in _FONT_CANDIDATES[bold]:
        if os.path.exists(path):
            try:
                f = ImageFont.truetype(path, int(round(size * S)))
                break
            except Exception:
                pass
    if f is None:
        f = ImageFont.load_default()
    _font_cache[key] = f
    return f


def P(v):
    return int(round(v * S))


# ------------------------------------------------------------------------ themes
# Every name used by the drawing body is supplied per theme via globals().update,
# so the same layout renders in light or dark. Names that previously were inline
# tuples (diamond / separator / hook-name / harness-desc) are themed too, since a
# hard-coded dark brown would vanish on a dark background.
LIGHT = {
    "BG": (255, 255, 255), "LABELBG": (255, 255, 255),
    "INK": (17, 24, 39), "GRAY": (107, 114, 128), "LINE": (71, 85, 105), "SLATE": (71, 85, 105),
    "SKILL_FILL": (219, 234, 254), "SKILL_BD": (37, 99, 235), "SKILL_TX": (30, 58, 138),
    "AGENT_FILL": (220, 252, 231), "AGENT_BD": (22, 163, 74), "AGENT_TX": (20, 83, 45),
    "HOOK_FILL": (255, 250, 235), "HOOK_BD": (217, 119, 6), "HOOK_TX": (124, 65, 16),
    "IO_FILL": (241, 245, 249), "IO_BD": (100, 116, 139), "IO_TX": (51, 65, 85),
    "PR_FILL": (237, 233, 254), "PR_BD": (124, 58, 237), "PR_TX": (76, 29, 149),
    "TRANS_FILL": (248, 250, 252), "TRANS_BD": (203, 213, 225),
    "HARN_FILL": (245, 243, 255), "HARN_BD": (124, 58, 237), "HARN_TX": (67, 56, 202),
    "LOOP": (220, 38, 38),
    "DIAMOND_FILL": (254, 249, 195), "DIAMOND_TX": (133, 77, 14),
    "SEP": (229, 210, 170), "HOOKNAME": (146, 64, 14), "HARNDESC": (55, 48, 110),
}
DARK = {
    "BG": (13, 17, 23), "LABELBG": (13, 17, 23),
    "INK": (230, 237, 243), "GRAY": (148, 158, 170), "LINE": (139, 148, 158), "SLATE": (162, 172, 186),
    "SKILL_FILL": (23, 37, 64), "SKILL_BD": (96, 165, 250), "SKILL_TX": (191, 219, 254),
    "AGENT_FILL": (18, 46, 33), "AGENT_BD": (74, 222, 128), "AGENT_TX": (187, 247, 208),
    "HOOK_FILL": (38, 32, 17), "HOOK_BD": (217, 160, 40), "HOOK_TX": (252, 211, 77),
    "IO_FILL": (30, 41, 59), "IO_BD": (113, 128, 150), "IO_TX": (203, 213, 225),
    "PR_FILL": (45, 40, 74), "PR_BD": (167, 139, 250), "PR_TX": (221, 214, 254),
    "TRANS_FILL": (30, 41, 59), "TRANS_BD": (71, 85, 105),
    "HARN_FILL": (35, 31, 64), "HARN_BD": (139, 109, 240), "HARN_TX": (199, 191, 247),
    "LOOP": (248, 113, 113),
    "DIAMOND_FILL": (60, 52, 20), "DIAMOND_TX": (253, 224, 71),
    "SEP": (70, 60, 35), "HOOKNAME": (252, 211, 77), "HARNDESC": (199, 191, 247),
}

d = None  # set per build()


# ----------------------------------------------------------------------- helpers
# Helpers read theme colours from globals at CALL time (no colour default args, so
# nothing binds to a single theme at def time).
def box(x0, y0, x1, y1, fill, outline, width=2, radius=10):
    d.rounded_rectangle([P(x0), P(y0), P(x1), P(y1)], radius=P(radius),
                        fill=fill, outline=outline, width=P(width))


def dashed_line(x0, y0, x1, y1, color, width=2, dash=9, gap=6):
    import math
    dx, dy = x1 - x0, y1 - y0
    dist = math.hypot(dx, dy)
    if dist == 0:
        return
    ux, uy = dx / dist, dy / dist
    pos = 0.0
    while pos < dist:
        seg = min(dash, dist - pos)
        d.line([P(x0 + ux * pos), P(y0 + uy * pos),
                P(x0 + ux * (pos + seg)), P(y0 + uy * (pos + seg))], fill=color, width=P(width))
        pos += dash + gap


def dashed_rect(x0, y0, x1, y1, color, width=2, dash=10, gap=6):
    dashed_line(x0, y0, x1, y0, color, width, dash, gap)
    dashed_line(x1, y0, x1, y1, color, width, dash, gap)
    dashed_line(x1, y1, x0, y1, color, width, dash, gap)
    dashed_line(x0, y1, x0, y0, color, width, dash, gap)


def text(x, y, s, size=12.5, color=None, bold=False, anchor="lm"):
    d.text((P(x), P(y)), s, font=font(size, bold), fill=color if color is not None else INK, anchor=anchor)


def text_bg(x, y, s, size=10.5, color=None, bold=False, bg=None, padx=4, pady=1):
    f = font(size, bold)
    w = f.getlength(s) / S
    h = size * 1.25
    d.rectangle([P(x - w / 2 - padx), P(y - h / 2 - pady),
                 P(x + w / 2 + padx), P(y + h / 2 + pady)], fill=bg if bg is not None else LABELBG)
    d.text((P(x), P(y)), s, font=f, fill=color if color is not None else INK, anchor="mm")


def rich(x, y, segs, size=12.5):
    cx = x
    for t, color, bold in segs:
        f = font(size, bold)
        d.text((P(cx), P(y)), t, font=f, fill=color, anchor="lm")
        cx += f.getlength(t) / S
    return cx


def arrowhead(x, y, direction, size=7, color=None):
    color = color if color is not None else LINE
    if direction == "down":
        pts = [(x, y), (x - size, y - size * 1.5), (x + size, y - size * 1.5)]
    elif direction == "up":
        pts = [(x, y), (x - size, y + size * 1.5), (x + size, y + size * 1.5)]
    elif direction == "left":
        pts = [(x, y), (x + size * 1.5, y - size), (x + size * 1.5, y + size)]
    else:
        pts = [(x, y), (x - size * 1.5, y - size), (x - size * 1.5, y + size)]
    d.polygon([(P(a), P(b)) for a, b in pts], fill=color)


def red_dot(x, y, r=4.5, color=None):
    d.ellipse([P(x - r), P(y - r), P(x + r), P(y + r)], fill=color if color is not None else LOOP)


# -------------------------------------------------------------------- geometry
MX0, MX1 = 60, 642
MCX = (MX0 + MX1) / 2
HX0, HX1 = 694, 1162


def build(theme, out):
    globals().update(theme)
    global d
    img = Image.new("RGB", (W * S, H * S), BG)
    d = ImageDraw.Draw(img)

    def trans(y0, lines):
        n = len(lines)
        gap = {1: 56, 2: 70, 3: 86}[n]
        y1 = y0 + gap
        d.line([P(MCX), P(y0), P(MCX), P(y1)], fill=LINE, width=P(2))
        arrowhead(MCX, y1, "down")
        ph = 16 + 17 * n
        pw = max(font(10.5).getlength(s) / S for s in lines) + 30
        cy = (y0 + y1) / 2
        box(MCX - pw / 2, cy - ph / 2, MCX + pw / 2, cy + ph / 2, TRANS_FILL, TRANS_BD, width=1.3, radius=9)
        ty = cy - (n - 1) * 8.5
        for s in lines:
            text(MCX, ty, s, size=10.5, color=SLATE, anchor="mm")
            ty += 17
        return y1

    # header
    text(40, 34, "/brief chain=on  —  execution flow", size=24, bold=True, color=INK)
    text(40, 64, "what each phase does, what passes between phases, which harness applies — and where the two loops are",
         size=12.5, color=GRAY)
    lx = 40
    ly = 92

    def swatch(x, fill, bd, label, dashed=False):
        if dashed:
            dashed_line(x, ly, x + 22, ly, LOOP, 2.6, 5, 3)
        else:
            d.rounded_rectangle([P(x), P(ly - 6), P(x + 20), P(ly + 7)], radius=P(3),
                                fill=fill, outline=bd, width=P(1.6))
        tx = x + (28 if not dashed else 30)
        text(tx, ly, label, size=11, color=INK)
        return tx + font(11).getlength(label) / S + 24

    lx = swatch(lx, SKILL_FILL, SKILL_BD, "skill")
    lx = swatch(lx, AGENT_FILL, AGENT_BD, "agent (subagent)")
    lx = swatch(lx, HOOK_FILL, HOOK_BD, "hook")
    lx = swatch(lx, TRANS_FILL, TRANS_BD, "handoff + harness")
    lx = swatch(lx, None, None, "loop / iterates", dashed=True)

    # 1. user IO
    box(MX0, 126, MX1, 172, IO_FILL, IO_BD)
    text(MCX, 149, 'User types   /brief "<idea>"   (chain=on is the default)',
         size=12.5, color=IO_TX, anchor="mm")
    d.line([P(MCX), P(172), P(MCX), P(204)], fill=LINE, width=P(2))
    arrowhead(MCX, 204, "down")

    # 2. /brief
    B0 = 204
    box(MX0, B0, MX1, B0 + 122, SKILL_FILL, SKILL_BD)
    text(MX0 + 16, B0 + 20, "/brief", size=15.5, bold=True, color=SKILL_TX)
    text(MX0 + 70, B0 + 21, "· skill", size=11.5, color=GRAY)
    rich(MX0 + 16, B0 + 48, [("spawns ", INK, False), ("researcher", AGENT_TX, True),
                            (" (subagent) — quick codebase pre-scan", INK, False)], size=12)
    text(MX0 + 16, B0 + 70, "runs an interactive Socratic interview to capture requirements", size=12, color=INK)
    rich(MX0 + 16, B0 + 94, [("writes  ", INK, False), ("brief.md", IO_TX, True),
                            ("  +  ", GRAY, False), ("autopilot-policy.yaml", IO_TX, True)], size=12)

    y = trans(B0 + 122, ["hands off brief.md  ·  on chain=on, auto-kick.yaml arms the",
                         "Stop-hook chain so the hand-off cannot stall"])

    # 3. /create-ticket
    C0 = y
    box(MX0, C0, MX1, C0 + 150, SKILL_FILL, SKILL_BD)
    text(MX0 + 16, C0 + 20, "/create-ticket", size=15.5, bold=True, color=SKILL_TX)
    text(MX0 + 142, C0 + 21, "· skill", size=11.5, color=GRAY)
    text(MX0 + 16, C0 + 48, "splits the scope into N tickets through independent layers (Agent tool):", size=12, color=INK)
    rich(MX0 + 16, C0 + 72, [("researcher", AGENT_TX, True), ("  →  ", GRAY, False),
                            ("decomposer", AGENT_TX, True), ("  →  ", GRAY, False),
                            ("planner", AGENT_TX, True), ("  →  ", GRAY, False),
                            ("ticket-evaluator", AGENT_TX, True)], size=12)
    rich(MX0 + 16, C0 + 98, [("quality gate FAIL  →  ", INK, False), ("planner", AGENT_TX, True),
                            (" retry ×2 ", INK, False), ("(loop)", LOOP, True)], size=12)
    rich(MX0 + 16, C0 + 124, [("writes  ", INK, False), ("ticket.md ×N  +  split-plan.md", IO_TX, True)], size=12)

    y = trans(C0 + 150, ["split-plan.md is the single source of truth  ·  one",
                         "phase-state.yaml is created per ticket (the state machine)"])

    # 4. /autopilot
    A0 = y
    box(MX0, A0, MX1, A0 + 84, SKILL_FILL, SKILL_BD)
    text(MX0 + 16, A0 + 22, "/autopilot", size=15.5, bold=True, color=SKILL_TX)
    text(MX0 + 104, A0 + 23, "· skill — orchestrator", size=11.5, color=GRAY)
    text(MX0 + 16, A0 + 52, "runs each ticket in dependency (topological) order", size=12, color=INK)

    y = trans(A0 + 84, ["Stop hook  autopilot-continue  re-injects a \"continue\" prompt every",
                        "turn — this is what DRIVES the loop; state files make the run resumable"])

    # PER-TICKET LOOP box
    OLY0 = y + 4
    OLX0, OLX1 = 40, 666
    text(OLX0 + 16, OLY0 + 18, "PER-TICKET LOOP  —  one pass per ticket", size=13, bold=True, color=LOOP)
    text(OLX0 + 16, OLY0 + 38, "(auto-/compact resets the context window at every ticket boundary)", size=10.5, color=LOOP)

    SX0, SX1 = 64, 638
    SCX = (SX0 + SX1) / 2

    # 5. /scout
    S0 = OLY0 + 60
    box(SX0, S0, SX1, S0 + 118, SKILL_FILL, SKILL_BD)
    text(SX0 + 14, S0 + 20, "/scout", size=14.5, bold=True, color=SKILL_TX)
    text(SX0 + 76, S0 + 21, "· skill (thin orchestrator) — chains two sub-skills:", size=11, color=GRAY)
    rich(SX0 + 14, S0 + 50, [("/investigate", SKILL_TX, True), ("  →  ", GRAY, False),
                            ("researcher", AGENT_TX, True), ("  →  ", GRAY, False),
                            ("investigation.md", IO_TX, True)], size=12)
    rich(SX0 + 14, S0 + 76, [("/plan2doc", SKILL_TX, True), ("  →  ", GRAY, False),
                            ("planner", AGENT_TX, True), (" (size-routed)  →  ", GRAY, False),
                            ("plan.md", IO_TX, True)], size=12)

    y = trans(S0 + 118, ["investigation.md + plan.md land on disk  ·  the plan's Acceptance",
                         "Criteria become the FIXED rubric for the evaluator (information firewall)"])

    # 6. /impl
    I0 = y
    IMPL_H = 268
    box(SX0, I0, SX1, I0 + IMPL_H, SKILL_FILL, SKILL_BD)
    text(SX0 + 14, I0 + 20, "/impl", size=14.5, bold=True, color=SKILL_TX)
    text(SX0 + 64, I0 + 21, "· skill — runs the Generator / Evaluator loop, then audits", size=11, color=GRAY)

    ILY0 = I0 + 40
    ILY1 = ILY0 + 132
    dashed_rect(SX0 + 18, ILY0, SX1 - 18, ILY1, LOOP, width=2, dash=8, gap=5)
    text(SX0 + 30, ILY0 + 16, "VERIFY LOOP  —  max 9 rounds (default)", size=10.5, bold=True, color=LOOP)
    gA0, gA1 = SX0 + 34, SX0 + 280
    eA0, eA1 = SX1 - 280, SX1 - 34
    gby0, gby1 = ILY0 + 36, ILY0 + 96
    box(gA0, gby0, gA1, gby1, AGENT_FILL, AGENT_BD, radius=8)
    text((gA0 + gA1) / 2, gby0 + 22, "implementer", size=12.5, bold=True, color=AGENT_TX, anchor="mm")
    text((gA0 + gA1) / 2, gby0 + 42, "(Generator) writes code", size=10, color=AGENT_TX, anchor="mm")
    box(eA0, gby0, eA1, gby1, AGENT_FILL, AGENT_BD, radius=8)
    text((eA0 + eA1) / 2, gby0 + 22, "ac-evaluator", size=12.5, bold=True, color=AGENT_TX, anchor="mm")
    text((eA0 + eA1) / 2, gby0 + 42, "(Evaluator) per-AC verdict", size=10, color=AGENT_TX, anchor="mm")
    fy = (gby0 + gby1) / 2
    d.line([P(gA1), P(fy), P(eA0), P(fy)], fill=LINE, width=P(2.4))
    arrowhead(eA0, fy, "right")
    text_bg((gA1 + eA0) / 2, fy - 14, "verify", size=10, color=GRAY)
    mid = (gA0 + eA1) / 2
    gcx = (gA0 + gA1) / 2
    ecx = (eA0 + eA1) / 2
    by = gby1 + 16
    dashed_line(ecx, gby1, ecx, by, LOOP, 2, 6, 4)
    dashed_line(ecx, by, gcx, by, LOOP, 2, 6, 4)
    dashed_line(gcx, by, gcx, gby1, LOOP, 2, 6, 4)
    arrowhead(gcx, gby1 + 2, "up", color=LOOP)
    text_bg(mid, by, "FAIL  →  next round", size=10.5, color=LOOP, bold=True)

    rich(SX0 + 14, ILY1 + 22, [("on ", INK, False), ("PASS", AGENT_TX, True), ("  →  ", GRAY, False),
                              ("/audit", SKILL_TX, True),
                              (" (skill) spawns three reviewers in parallel:", INK, False)], size=12)
    ay0 = ILY1 + 38
    ay1 = ay0 + 48
    aw = (SX1 - SX0 - 28 - 2 * 14) / 3
    for i, (nm, sub) in enumerate([("code-reviewer", None), ("security-scanner", None),
                                  ("doc-verifier *", "(conditional)")]):
        ax0 = SX0 + 14 + i * (aw + 14)
        box(ax0, ay0, ax0 + aw, ay1, AGENT_FILL, AGENT_BD, radius=8)
        if sub:
            text(ax0 + aw / 2, ay0 + 18, nm, size=11, bold=True, color=AGENT_TX, anchor="mm")
            text(ax0 + aw / 2, ay0 + 34, sub, size=9, color=AGENT_TX, anchor="mm")
        else:
            text(ax0 + aw / 2, ay0 + 24, nm, size=11, bold=True, color=AGENT_TX, anchor="mm")

    y = trans(I0 + IMPL_H, ["subagents return < 500-token summaries; full artifacts stay on",
                           "disk (context conservation) — the orchestrator window stays lean"])

    # 7. /ship
    SH0 = y
    box(SX0, SH0, SX1, SH0 + 122, SKILL_FILL, SKILL_BD)
    text(SX0 + 14, SH0 + 20, "/ship", size=14.5, bold=True, color=SKILL_TX)
    text(SX0 + 60, SH0 + 21, "· skill", size=11, color=GRAY)
    rich(SX0 + 14, SH0 + 48, [("commit (", INK, False), ("git", IO_TX, True), (")  →  ", GRAY, False),
                             ("/tune", SKILL_TX, True), (" distils eval logs into the cross-session KB", INK, False)], size=12)
    rich(SX0 + 14, SH0 + 72, [("push branch  →  open a Pull Request via ", INK, False),
                             ("gh", IO_TX, True)], size=12)
    rich(SX0 + 14, SH0 + 96, [("move ticket  →  ", INK, False), ("backlog/done/", IO_TX, True)], size=12)

    # decision diamond
    DCX, DCY = SCX, SH0 + 122 + 56
    d.line([P(SCX), P(SH0 + 122), P(SCX), P(DCY - 30)], fill=LINE, width=P(2))
    arrowhead(SCX, DCY - 30, "down")
    d.polygon([(P(DCX), P(DCY - 28)), (P(DCX + 104), P(DCY)),
               (P(DCX), P(DCY + 28)), (P(DCX - 104), P(DCY))],
              fill=DIAMOND_FILL, outline=LOOP, width=P(2))
    text(DCX, DCY, "more tickets?", size=11.5, bold=True, color=DIAMOND_TX, anchor="mm")

    OLY1 = DCY + 52
    dashed_rect(OLX0, OLY0, OLX1, OLY1, LOOP, width=2.4, dash=11, gap=6)

    # yes -> loop back up to /scout
    LBX = 50
    dashed_line(DCX - 104, DCY, LBX, DCY, LOOP, 2.4, 9, 6)
    dashed_line(LBX, DCY, LBX, S0 + 50, LOOP, 2.4, 9, 6)
    dashed_line(LBX, S0 + 50, SX0, S0 + 50, LOOP, 2.4, 9, 6)
    arrowhead(SX0, S0 + 50, "right", color=LOOP)
    text_bg(DCX - 150, DCY, "yes  —  next ticket", size=10.5, color=LOOP, bold=True)

    # no -> PR
    d.line([P(SCX), P(DCY + 28), P(SCX), P(OLY1 + 46)], fill=LINE, width=P(2))
    arrowhead(SCX, OLY1 + 46, "down")
    text_bg(SCX + 96, OLY1 + 24, "no (all tickets done)", size=10.5, color=GRAY)

    # PR
    PR0 = OLY1 + 48
    box(MX0, PR0, MX1, PR0 + 48, PR_FILL, PR_BD)
    text(MCX, PR0 + 24, "All tickets shipped   →   Pull Request(s) on GitHub",
         size=13, bold=True, color=PR_TX, anchor="mm")

    # HOOKS lane
    HY0, HY1 = 204, 1196
    box(HX0, HY0, HX1, HY1, HOOK_FILL, HOOK_BD, width=2, radius=12)
    text(HX0 + 18, HY0 + 24, "Lifecycle hooks  —  always-on", size=14, bold=True, color=HOOK_TX)
    text(HX0 + 18, HY0 + 45, "(hooks.json — fire around every tool call & every turn)", size=10, color=GRAY)

    def hgroup(yy, title):
        text(HX0 + 18, yy, title, size=12, bold=True, color=HOOK_TX)
        return yy + 22

    def hitem(yy, name, desc, marker=False):
        if marker:
            red_dot(HX0 + 22, yy, 4.5)
        rich(HX0 + 32, yy, [(name, HOOKNAME, True)], size=10.5)
        if desc:
            text(HX0 + 32, yy + 16, desc, size=9.5, color=GRAY)
            return yy + 35
        return yy + 22

    hy = HY0 + 78
    hy = hgroup(hy, "SessionStart")
    hy = hitem(hy, "session-start.sh", "boot + resume re-inject")
    hy += 8
    hy = hgroup(hy, "PreToolUse")
    hy = hitem(hy, "pre-bash / write / edit-safety.sh", "PII · destructive · identity guards")
    hy = hitem(hy, "pre-state-transition.sh", "block illegal status writes")
    hy = hitem(hy, "pre-bash-contract-guard.sh", "block bash state-mutation")
    hy = hitem(hy, "pre-next-scout-auto-compact.sh", "/compact at ticket boundary")
    hy = hitem(hy, "pre-askuserquestion-guard.sh", "non-interactive gate")
    hy += 8
    hy = hgroup(hy, "PreCompact")
    hy = hitem(hy, "pre-compact-save.sh", "snapshot state before /compact")
    hy += 8
    hy = hgroup(hy, "PostToolUse")
    hy = hitem(hy, "post-phase-checkpoint.sh", "persist phase-state.yaml")
    hy = hitem(hy, "post-ship-state-auto-compact.sh", "/compact safety net")
    hy = hitem(hy, "post-skill-cleanup.sh", "")
    hy += 8
    hy = hgroup(hy, "Stop   (the loop drivers)")
    ac_y = hy
    hy = hitem(hy, "autopilot-continue.sh", "re-injects \"continue\"  =  the loop", marker=True)
    hy = hitem(hy, "impl- / scout-checkpoint-guard.sh", "block premature stop mid-phase")
    hy = hitem(hy, "session-stop-log.sh", "")

    hy += 12
    d.line([P(HX0 + 18), P(hy), P(HX1 - 18), P(hy)], fill=SEP, width=P(1))
    hy += 16
    text(HX0 + 18, hy, "How the hooks shape the loop", size=11.5, bold=True, color=HOOK_TX)
    hy += 22
    for ln in ["• Pre-*-safety / contract / state guards vet every",
               "  Write / Edit / Bash before it runs.",
               "• auto-compact hooks refresh the context window",
               "  between tickets so it never fills up.",
               "• Stop hooks re-inject \"continue\" until every ticket",
               "  reaches backlog/done/ — that IS the per-ticket loop."]:
        text(HX0 + 26, hy, ln, size=10, color=SLATE)
        hy += 17

    # connector: autopilot-continue -> PER-TICKET LOOP box
    gapx = 680
    dashed_line(HX0, ac_y, gapx, ac_y, LOOP, 2.4, 8, 5)
    dashed_line(gapx, ac_y, gapx, OLY0 + 26, LOOP, 2.4, 8, 5)
    dashed_line(gapx, OLY0 + 26, OLX1, OLY0 + 26, LOOP, 2.4, 8, 5)
    arrowhead(OLX1, OLY0 + 26, "left", color=LOOP)
    text_bg(OLX0 + 470, OLY0 + 26, "Stop hook drives the loop", size=10.5, color=LOOP, bold=True)

    # HARNESS key panel
    KY0 = PR0 + 84
    KY1 = KY0 + 214
    box(MX0, KY0, HX1, KY1, HARN_FILL, HARN_BD, width=2, radius=12)
    text(MX0 + 18, KY0 + 24, "The harness applied across the whole run", size=14, bold=True, color=HARN_TX)
    text(MX0 + 18, KY0 + 47, "Together these mechanisms ARE the plugin's closed inner loop of loop engineering — the scheduler (\"outer\") loop is delegated to Claude Code (/loop · /schedule).",
         size=10.5, color=SLATE)
    ky = KY0 + 76
    HARN = [
        ("Information firewall", "code authors and code judges never share a context — the Generator (implementer) and Evaluator (ac-evaluator) are separate fresh subagents, so the judge cannot be biased by the author."),
        ("Context conservation", "every subagent returns a < 500-token summary; full artifacts (investigation, plan, eval rounds) live on disk; auto-/compact runs between tickets."),
        ("State machine", "autopilot-state.yaml + one phase-state.yaml per ticket record every step, so any compaction, crash or /clear is resumable from the last checkpoint."),
        ("Bounded closed loops", "the per-ticket loop and the verify loop (Generator/Evaluator, up to 9 rounds) stop only when the Acceptance-Criteria contract passes or a round cap is hit."),
        ("Lifecycle guards", "hooks vet every Write / Edit / Bash, snapshot state before /compact, and decide continue-vs-stop on every turn."),
    ]
    for title, desc in HARN:
        ex = rich(MX0 + 18, ky, [("• ", HARN_TX, True), (title + " — ", HARN_TX, True)], size=11)
        text(ex, ky, desc, size=10.5, color=HARNDESC, anchor="lm")
        ky += 27

    text(40, KY1 + 26, "*  doc-verifier runs only when a documentation / advertised-interface surface is touched.",
         size=10, color=GRAY)

    img.save(out)
    print("wrote", out, img.size)


build(LIGHT, os.path.join(HERE, "brief-chain-flow.png"))
build(DARK, os.path.join(HERE, "brief-chain-flow-dark.png"))
