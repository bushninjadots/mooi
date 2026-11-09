#!/usr/bin/env python3
"""The shared opening block (D209): one text, written into every program under the wallpaper.

Holding Super opens the wallpaper. `mooi-surface` owns the opening and sends three packed numbers
(`op_a`, `op_b`, `op_c`, see shell/lib/surface/opening.luau `pack`) to every program under the wallpaper
(mooi-widgets, mooi-viz, BMO); each of them, and mooi-surface itself, turns them into the same sprung hole
(op_x, op_y, op_w, op_h, op_r, op_k) with the identical text below, so the hole is the same shape everywhere.

The block never names the pointer. (D218: nor do the scenes for the opening's sake any more — every mode draws
the hole mooi-surface sends, which reads the pointer from Hyprland while Super is held; the notes below are why
naming it was costly.) Why (Pleamar src, compiler.rs:532): a scene that
names `cursor` in any form, `cursor.x` or `desk.cursor.x` (mentions_part, compiler.rs:901), sets
`wants_cursor`; that starts the compositor cursor feed at 30 Hz (platform/hyprland.rs:87, mod.rs:1199) and
every pointer move counts as activity for `idle` rules (render.rs:1356). Qualifying the name does not help,
and it cannot be switched off while the Surface is off, so only a scene that already reads the pointer may
define op_px from it: mooi-surface (`cursor.x`) and mooi-widgets (`desk.cursor.x`, already named there). mooi-viz
and BMO define them as plain facts (0) so Surface off is exactly main; whoever feeds follow mode there (Tasks
8/9: emit, or a conscious `cursor` mention) writes them. The hole is in SCREEN coordinates (mooi-surface's
surfaces use reserve: -1); a citizen whose surface starts lower (widgets, below the bar's reserve) adds its own
offset to draw it: left to Task 8. With sf_on false nothing here moves: op_mode is 0, so every target is
constant and the springs rest.

Run: python3 tools/gen-opening.py   (rewrites the text between `// <gen:opening>` and `// </gen:opening>` in
shell/mooi-widgets.plm, shell/mooi-viz.plm and shell/bmo/bmo.plm; shell/mooi-surface.plm gets the same block
from tools/gen-surface.py, which calls block()).
"""
import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
FILES = [ROOT / "shell" / "mooi-widgets.plm", ROOT / "shell" / "mooi-viz.plm", ROOT / "shell" / "bmo" / "bmo.plm"]
R = 90  # the follow square's half-side: lib/surface/opening.luau `M.R`
FAINT = 0.45  # how open a fresh opening is until it is firm: lib/surface/opening.luau `M.FAINT`
OPEN, CLOSE = "    // <gen:opening>", "    // </gen:opening>"
POPEN, PCLOSE = "        // <gen:opening-probe>", "        // </gen:opening-probe>"


def block():
    """The block's lines (4-space indent, scene level), without the markers."""
    return [
        "    // The opening (D209): mooi-surface packs the hole into three numbers (lib/surface/opening `pack`);",
        "    // every program turns them into the same sprung rectangle. mode = c / 1000: closed 0 · follow 1 · snapped 2 ·",
        "    // section 3 · full 4. Follow sends no a, b: the target is the square of side 2 * R on the pointer.",
        "    // A fresh opening is faint (c carries 500) until it is firm or snapped: drawn weaker, and no zone answers.",
        "    event op_a ->          // x * 4096 + y",
        "    event op_b ->          // w * 4096 + h",
        "    event op_c ->          // mode * 1000 + (500 while faint) + r",
        "    event sf_set ->        // the Surface: bit 0 on, bit 1 BMO lives below",
        "    event op_want ->       // to mooi-surface: what a program under the wallpaper asks for",
        "    event op_key ->        // the keyboard: 1 next · -1 before · 2 press what is snapped",
        "    event op_wheel ->      // the wheel while the opening shows: 1 widen · -1 narrow",
        "    fact op_ta = 0",
        "    fact op_tb = 0",
        "    fact op_tc = 0",
        "    fact sf_on = false     // Surface on",
        "    fact sf_bmo = true     // BMO lives below",
        "    on op_a(v) { op_ta = v }",
        "    on op_b(v) { op_tb = v }",
        "    on op_c(v) { op_tc = v }",
        "    on sf_set(v) { sf_on = mod(v, 2) == 1; sf_bmo = floor(v / 2) == 1 }",
        "    spring sg.op = 380, 34",
        "    let op_mode = if(sf_on, floor(op_tc / 1000), 0)",
        "    let op_r1 = op_tc - floor(op_tc / 1000) * 1000",
        "    let op_faint = op_r1 > 499.5",
        "    let op_r0 = op_r1 - if(op_faint, 500, 0)",
        "    let op_ax = floor(op_ta / 4096)",
        "    let op_aw = floor(op_tb / 4096)",
        "    // D218: every mode, follow too, draws the hole mooi-surface sends: it reads the pointer from Hyprland",
        "    // while Super is held (a scene's own pointer reading stands still while it is over anything else)",
        "    let op_tx = op_ax",
        "    let op_ty = op_ta - op_ax * 4096",
        "    let op_tw = op_aw",
        "    let op_th = op_tb - op_aw * 4096",
        "    let op_tr = op_r0",
        "    prop op_x = 0 ~sg.op",
        "    follow op_x = op_tx",
        "    prop op_y = 0 ~sg.op",
        "    follow op_y = op_ty",
        "    prop op_w = 0 ~sg.op",
        "    follow op_w = op_tw",
        "    prop op_h = 0 ~sg.op",
        "    follow op_h = op_th",
        "    prop op_r = 0 ~sg.op",
        "    follow op_r = op_tr",
        "    prop op_k = 0 ~sg.op",
        f"    follow op_k = if(op_mode > 0, if(op_faint, {FAINT}, 1), 0)",
        "    let op_vis = sf_on and op_k > 0.01",
        "    let op_live = op_vis and not op_faint     // what is below answers a press only once the opening is firm",
    ]


def probe(ind="        "):
    """D214, found by rendering it: Pleamar repaints only the boxes that changed, and a clip box that moves does
    not count the part it has just left, so a moving hole left its old rims and its old contents behind on every
    surface that clips to it. A near-invisible veil (about 1/255) that changes with the hole makes each frame
    repaint the whole surface while the opening shows; when the opening closes it goes, and the surface rests."""
    return [f"{ind}// the opening's repaint (D214): a moving clip leaves what it uncovered behind unless the whole",
            f"{ind}// surface is repainted; this veil changes with the hole, and is gone when the opening is",
            f"{ind}box {{ from: 0, 0; size: 8192, 8192; color: #000000; opacity: 0.004 + 0.001 * fract((op_x + op_y + op_w + op_h) / 97); show: op_k > 0.001 }}"]


def text():
    return "\n".join([OPEN] + block() + [CLOSE]) + "\n"


def probe_text():
    return "\n".join([POPEN] + probe() + [PCLOSE]) + "\n"


def rewrite(src):
    """src with the text between both pairs of markers replaced; None if a marker is missing."""
    for o, c, body in ((OPEN, CLOSE, text()), (POPEN, PCLOSE, probe_text())):
        a, b = src.find(o + "\n"), src.find(c + "\n")
        if a < 0 or b < a:
            return None
        src = src[:a] + body + src[b + len(c) + 1:]
    return src


def main():
    bad = []
    for f in FILES:
        new = rewrite(f.read_text())
        if new is None:
            bad.append(f)
        else:
            f.write_text(new)
    for f in bad:
        print(f"gen-opening: {f.relative_to(ROOT)} lacks the `{OPEN.strip()}` or `{POPEN.strip()}` markers", file=sys.stderr)
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
