#!/usr/bin/env python3
"""The shared opening block (D209): one text, written into every program under the wallpaper.

Holding Super opens the wallpaper. `mooi-surface` owns the opening and sends three packed numbers
(`op_a`, `op_b`, `op_c`, see shell/lib/surface/opening.luau `pack`) to every program under the wallpaper
(mooi-widgets, mooi-viz, BMO); each of them, and mooi-surface itself, turns them into the same sprung hole
(op_x, op_y, op_w, op_h, op_r, op_k) with the identical text below, so the hole is the same shape everywhere.

The block never names the pointer: the follow target reads `op_px`, `op_py` (the pointer, in the scene's own
pixels), which each scene defines OUTSIDE the markers. Why (Pleamar src, compiler.rs:532): a scene that
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
        "    spring sg.op = 220, 24",
        "    let op_mode = if(sf_on, floor(op_tc / 1000), 0)",
        "    let op_r0 = op_tc - floor(op_tc / 1000) * 1000",
        "    let op_ax = floor(op_ta / 4096)",
        "    let op_aw = floor(op_tb / 4096)",
        f"    let op_tx = if(op_mode == 1, op_px - {R}, op_ax)",
        f"    let op_ty = if(op_mode == 1, op_py - {R}, op_ta - op_ax * 4096)",
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
