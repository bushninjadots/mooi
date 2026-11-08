#!/usr/bin/env python3
"""The shared opening block (D209): one text, written into every program under the wallpaper.

Holding Super opens the wallpaper. `mooi-surface` owns the opening and sends three packed numbers
(`op_a`, `op_b`, `op_c`, see shell/lib/surface/opening.luau `pack`) to every program under the wallpaper
(mooi-widgets, mooi-viz, BMO); each of them, and mooi-surface itself, turns them into the same sprung hole
(op_x, op_y, op_w, op_h, op_r, op_k) with the identical text below, so the hole is the same shape everywhere.
Run: python3 tools/gen-opening.py   (rewrites the text between `// <gen:opening>` and `// </gen:opening>` in
shell/mooi-widgets.plm, shell/mooi-viz.plm and shell/bmo/bmo.plm; shell/mooi-surface.plm gets the same block
from tools/gen-surface.py, which calls block()).
"""
import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
FILES = [ROOT / "shell" / "mooi-widgets.plm", ROOT / "shell" / "mooi-viz.plm", ROOT / "shell" / "bmo" / "bmo.plm"]
R = 90  # the follow square's half-side: lib/surface/opening.luau `M.R`
OPEN, CLOSE = "    // <gen:opening>", "    // </gen:opening>"


def block():
    """The block's lines (4-space indent, scene level), without the markers."""
    return [
        "    // The opening (D209): mooi-surface packs the hole into three numbers (lib/surface/opening `pack`);",
        "    // every program turns them into the same sprung rectangle. mode = c / 1000: closed 0 · follow 1 · snapped 2 ·",
        "    // section 3 · full 4. Follow sends no a, b: the target is the square of side 2 * R on the pointer.",
        "    event op_a ->          // x * 4096 + y",
        "    event op_b ->          // w * 4096 + h",
        "    event op_c ->          // mode * 1000 + r",
        "    event sf_set ->        // the Surface: bit 0 on, bit 1 BMO lives below",
        "    event op_want ->       // to mooi-surface: what a program under the wallpaper asks for",
        "    fact op_ta = 0",
        "    fact op_tb = 0",
        "    fact op_tc = 0",
        "    fact sf_on = false     // Surface on",
        "    fact sf_bmo = true     // BMO lives below",
        "    on op_a(v) { op_ta = v }",
        "    on op_b(v) { op_tb = v }",
        "    on op_c(v) { op_tc = v }",
        "    on sf_set(v) { sf_on = mod(v, 2) == 1; sf_bmo = floor(v / 2) == 1 }",
        "    spring sg.op = 220, 24",
        "    let op_mode = floor(op_tc / 1000)",
        "    let op_r0 = op_tc - op_mode * 1000",
        "    let op_ax = floor(op_ta / 4096)",
        "    let op_aw = floor(op_tb / 4096)",
        f"    let op_tx = if(op_mode == 1, cursor.x - {R}, op_ax)",
        f"    let op_ty = if(op_mode == 1, cursor.y - {R}, op_ta - op_ax * 4096)",
        f"    let op_tw = if(op_mode == 1, {2 * R}, op_aw)",
        f"    let op_th = if(op_mode == 1, {2 * R}, op_tb - op_aw * 4096)",
        f"    let op_tr = if(op_mode == 1, {R}, op_r0)",
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
        "    follow op_k = if(op_mode > 0, 1, 0)",
        "    let op_vis = sf_on and op_k > 0.01",
        "    let sf_below = sf_on",
    ]


def text():
    return "\n".join([OPEN] + block() + [CLOSE]) + "\n"


def rewrite(src):
    """src with the text between the markers replaced; None if a marker is missing."""
    a, b = src.find(OPEN + "\n"), src.find(CLOSE + "\n")
    if a < 0 or b < a:
        return None
    return src[:a] + text() + src[b + len(CLOSE) + 1:]


def main():
    bad = []
    for f in FILES:
        new = rewrite(f.read_text())
        if new is None:
            bad.append(f)
        else:
            f.write_text(new)
    for f in bad:
        print(f"gen-opening: {f.relative_to(ROOT)} has no `{OPEN.strip()}` / `{CLOSE.strip()}` markers", file=sys.stderr)
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
