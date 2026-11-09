#!/usr/bin/env python3
"""Generate shell/mooi-surface.plm: the Sigil (D207) and the Subsurface (D209-D214) in one scene.

The Sigil: four hosts (0 the Pill, 1-3 islands), each one line of N = 64 points: the logic writes each point's
target (h{k}_tx{i}, h{k}_ty{i}) and the scene springs to it, adds the temperament's wobble, the music's ripple
and the pointer's push, and draws it as the Sigil body. Its surfaces: `bar` (every host's resting form and its
zone) and `drop` (the Pill's display).

The Subsurface (docs/superpowers/specs/2026-11-08-subsurface-design.md): `ground` (level background, mapped after
the wallpaper: the wallpaper cut open, the hubs and components below it, the Overview's canvas), `edge` (level
bottom, above the citizens: the effect's rim, the keyboard) and `desk` (the Presences left on the wallpaper).
Run: python3 tools/gen-surface.py
"""
from pathlib import Path
import importlib.util
import math

_spec = importlib.util.spec_from_file_location("gen_opening", Path(__file__).resolve().parent / "gen-opening.py")
opening = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(opening)

N = 64
HOSTS = 4
OUT = Path(__file__).resolve().parent.parent / "shell" / "mooi-surface.plm"
# lib/surface/shapes.KINDS, 1-based in the scene's h{k}_kind
KINDS = ["clock", "wave", "disc", "ring", "card", "strip", "ribbon", "horizon", "spaces", "dots", "bars", "face"]
K = {k: i + 1 for i, k in enumerate(KINDS)}

# ── D209: what lives below the wallpaper ──
# The places are lib/surface/below.luau's defaults at 1920×1080 (the unit test holds the two together): the hubs
# on their arc, the components in their row, BMO's home.
HUBS = [("apps", "Apps", 360, 220), ("music", "Music", 320, 140), ("walls", "Wallpapers", 360, 120),
        ("settings", "Settings", 300, 140), ("notes", "Notices", 320, 220)]
COMPONENTS = [("wifi", "Wi-Fi"), ("bt", "Bluetooth"), ("volume", "Volume"), ("bright", "Brightness"),
              ("battery", "Battery"), ("power", "Power")]
COMP, GAP, RIGHT, BOTTOM = 56, 12, 32, 96
APP_N, WALL_N, NOTE_N = 12, 6, 4
# the Settings hub's marks: lib/surface/below.luau `SETTINGS` (word, the page's tab in mooi-settings)
SETTINGS = [("Theme & colour", 1), ("Bar & Frame", 3), ("Wallpapers", 9), ("Widgets", 10), ("Sound", 12),
            ("Power", 13), ("BMO", 11), ("The Subsurface", 21)]
POWER = [("Lock", 951), ("Sleep", 952), ("Log out", 953), ("Restart", 954), ("Shut down", 955)]
VIZ_N = 16         # the Music hub's own visualiser: bars inside the music thing (the visualiser rule)
# what the keyboard types into the Apps hub (the Overview keeps the keyboard; while Super is held the
# compositor's own Super shortcuts take the letters)
TYPED = [chr(c) for c in range(ord("a"), ord("z") + 1)]
GLYPH = {"wifi": "≋", "bt": "ᛒ", "volume": "♪", "bright": "☀", "battery": "▭", "power": "⏻"}


def below_defaults(w, h):
    out = {}
    n = len(HUBS)
    for i, (id, _, bw, bh) in enumerate(HUBS):
        f = i / (n - 1)
        t = 2 * f - 1
        out[id] = (int(math.floor(w * (0.12 + 0.76 * f) - bw / 2 + 0.5)),
                   int(math.floor(h * (0.30 + 0.06 * t * t) - bh / 2 + 0.5)), bw, bh)
    x0 = w - RIGHT - (len(COMPONENTS) * COMP + (len(COMPONENTS) - 1) * GAP)
    for i, (id, _) in enumerate(COMPONENTS):
        out[id] = (x0 + i * (COMP + GAP), h - BOTTOM - COMP, COMP, COMP)
    return out


def below_decls():
    """The facts, words and pictures the logic writes; declared before the surfaces that draw them."""
    P = below_defaults(1920, 1080)
    L = ["", "    // ── the subsurface (D209): the hubs, the components, the places the logic writes ──",
         "    event sb_press ->     // a hub mark or a component (hub * 100 + item, 900 + component)",
         "    event sb_drag ->      // a place being dragged out (its code)",
         "    event sb_drop ->      // and let go",
         "    event sb_wheel ->     // a component's wheel (component * 10 + up)",
         "    event sb_rsz ->       // a hub's shape handle being dragged (its code)",
         "    event sb_rsz_drop ->  // and let go",
         "    event sb_seek ->      // the Music hub's line pressed (the pointer's x)",
         "    event op_type ->      // a letter typed while the Apps hub is snapped (its code; 8 rubs one out)",
         "    event op_bx ->        // from BMO: where he stands, x * 4096 + y",
         "    event op_bs ->        // ... and how big he is, w * 4096 + h",
         "    event op_wbar ->      // from mooi-widgets: how far below the screen's top its surface starts",
         "    fact sf_snap = 0      // what the opening hugs: hub 1-5, component 11-16, BMO 20, a widget 30, none 0",
         "    spring sg.rise = 320, 26",
         '    text ap_q = ""        // what has been typed into the Apps hub'] + [
        f"    prop hb{k}_up = 0 ~sg.rise" for k in range(1, len(HUBS) + 1)] + [
        f"    follow hb{k}_up = if(op_vis and (op_mode > 2 or sf_snap == {k}), 1, 0)" for k in range(1, len(HUBS) + 1)] + [
        f"    prop cp{k}_up = 0 ~sg.rise" for k in range(1, len(COMPONENTS) + 1)] + [
        f"    follow cp{k}_up = if(op_vis and (op_mode > 2 or sf_snap == {10 + k}), 1, 0)" for k in range(1, len(COMPONENTS) + 1)]
    for k, (id, _, bw, bh) in enumerate(HUBS, start=1):
        x, y, _, _ = P[id]
        L += [f"    fact hb{k}_x = {x}", f"    fact hb{k}_y = {y}", f"    fact hb{k}_w = {bw}", f"    fact hb{k}_h = {bh}",
              f'    text hb{k}_sz = ""']
    for k, (id, _) in enumerate(COMPONENTS, start=1):
        x, y, _, _ = P[id]
        L += [f"    fact cp{k}_x = {x}", f"    fact cp{k}_y = {y}", f"    fact cp{k}_on = true",
              f"    fact cp{k}_lit = false", f"    fact cp{k}_frac = 0", f'    text cp{k}_val = ""']
    L += ["    fact pw_open = false", "    fact pw_arm = 0        // the power row asking again (its number), or none"]
    for n in range(1, APP_N + 1):
        L += [f"    fact ab{n}_on = false", f"    fact ab{n}_iconed = false",
              f'    text ab{n}_name = ""', f'    text ab{n}_letter = ""', f'    text ab{n}_path = ""',
              f"    image ab{n}_img = from ab{n}_path, 32, 32"]
    L += ["    fact mu_on = false", "    fact mu_playing = false", "    fact mu_prog = 0", "    fact mu_len = 0",
          '    text mu_t1 = ""', '    text mu_t2 = ""', '    text mu_art = ""', "    image mu_img = from mu_art, 64, 64"]
    for n in range(1, WALL_N + 1):
        L += [f"    fact wl{n}_on = false", f'    text wl{n}_thumb = ""', f"    image wl{n}_img = from wl{n}_thumb, 48, 40"]
    for n in range(1, NOTE_N + 1):
        L += [f"    fact nt{n}_on = false", f'    text nt{n}_t1 = ""', f'    text nt{n}_t2 = ""',
              f"    fact nt{n}_act = false", f'    text nt{n}_a1 = ""']
    L += ["    fact nt_n = 0"]
    return L


def below_group(base="            "):
    """The opening's content: the hubs as places (each draggable as a whole), the app marks, the music, the
    wallpapers, the settings marks, the notices, the components and the power row. A zone answers only while
    the opening is firm (`op_live`); nothing here is time-driven — the logic writes every value.

    Coming up (the spec §6): every thing is drawn at 96 % and faded while it lies below; the one the opening
    snaps to — and everything in a section or the Overview — rises to its full size on a spring, with a depth
    shadow under its plate."""
    c = base + "    "
    L = [f"{base}// below: what lives under the wallpaper (D209) — the hubs and the components",
         f"{base}group {{", f"{c}show: op_mode > 0", f"{c}opacity: min(1, op_k)"]

    def rising(up, cx, cy, body):
        """body (lines at `c`) inside a group that rises with `up` round (cx, cy)."""
        return ([f"{c}group {{", f"{c}    pivot: {cx}, {cy}", f"{c}    scale: 0.96 + 0.04 * {up}",
                 f"{c}    opacity: 0.72 + 0.28 * {up}"] + ["    " + ln for ln in body] + [f"{c}}}"])

    def plate(k, label):
        return [f'{c}// hub {k}: {label}',
                f"{c}group {{ glow: 26, 0.55 * hb{k}_up, #000000",
                f"{c}    box {{ from: hb{k}_x, hb{k}_y; size: hb{k}_w, hb{k}_h; corner: 18; color: rgb(0.07, 0.08, 0.07); opacity: 0.94 }} }}",
                f"{c}box {{ from: hb{k}_x + 0.5, hb{k}_y + 0.5; size: hb{k}_w - 1, hb{k}_h - 1; corner: 18; stroke: if(sf_snap == {k}, 1.6, 1); color: rgb(h0_r, h0_g, h0_b); opacity: 0.28 + 0.2 * hb{k}_up + if(sf_snap == {k}, 0.4, 0) }}",
                f'{c}text "{label}" {{ at: hb{k}_x + 16, hb{k}_y + 20; anchor: left center; size: 10; weight: 700; family: "Share Tech Mono"; color: muted; show: sf_labels > 0.5 }}']

    # the whole place: dragged out to make a Presence, let go to bury it (arranged, in the Overview)
    def place_zone(k, label):
        return [f'{c}zone box hbz{k}_0 {{ from: hb{k}_x, hb{k}_y; size: hb{k}_w, hb{k}_h; corner: 18; cursor: grab; role: button; label: "{label}"; show: op_live }}',
                f"{c}on drag hbz{k}_0 {{ emit sb_drag({k * 100}) }}",
                f"{c}on release hbz{k}_0 {{ emit sb_drop({k * 100}) }}"]

    def hub(k, label, body):
        cx, cy = f"hb{k}_x + hb{k}_w / 2", f"hb{k}_y + hb{k}_h / 2"
        return rising(f"hb{k}_up", cx, cy, plate(k, label) + place_zone(k, label.title()) + body)

    # 1 · Apps: four by three marks, the most launched first (the logic chooses them); typed letters filter them
    B = [f'{c}text ap_q {{ at: hb1_x + 64, hb1_y + 20; anchor: left center; size: 10; weight: 700; family: "Share Tech Mono"; color: ink; width: hb1_w - 80; lines: 1 }}']
    cw, ch = "(hb1_w - 36) / 4", "(hb1_h - 56) / 3"
    for n in range(1, APP_N + 1):
        col, row = (n - 1) % 4, (n - 1) // 4
        mx, my = f"hb1_x + 18 + {col} * {cw}", f"hb1_y + 40 + {row} * {ch}"
        ix = f"{mx} + ({cw} - 30) / 2"
        B += [f'{c}zone box hbz1_{n} {{ from: {mx}, {my}; size: {cw} - 4, {ch} - 4; corner: 10; cursor: pointer; role: button; label: "App {n}"; show: op_live and ab{n}_on }}',
              f"{c}box {{ from: {ix}, {my}; size: 30, 30; corner: 8; color: rgb(0.14, 0.15, 0.13); opacity: 0.9; show: ab{n}_on }}",
              f"{c}text ab{n}_letter {{ at: {ix} + 15, {my} + 15; anchor: center; align: center; size: 12; weight: 700; family: \"Exo 2\"; color: ink; show: ab{n}_on and not ab{n}_iconed }}",
              f"{c}image ab{n}_img {{ at: {ix}, {my}; size: 30, 30; fit: cover; show: ab{n}_on and ab{n}_iconed }}",
              f"{c}text ab{n}_name {{ at: {mx} + {cw} / 2, {my} + {ch} - 10; anchor: center; align: center; size: 9; family: \"Exo 2\"; color: muted; width: {cw} - 4; lines: 1; show: ab{n}_on }}",
              f"{c}on press hbz1_{n} {{ emit sb_press({100 + n}) }}"]
    L += hub(1, "APPS", B)

    # 2 · Music: art, the two words, the controls, its line (a press seeks) and its own visualiser
    B = [f"{c}box {{ from: hb2_x + 18, hb2_y + 40; size: 64, 64; corner: 10; color: rgb(0.13, 0.14, 0.12); opacity: 0.9 }}",
         f"{c}image mu_img {{ at: hb2_x + 18, hb2_y + 40; size: 64, 64; fit: cover; show: mu_on }}",
         f'{c}text "♫" {{ at: hb2_x + 50, hb2_y + 72; anchor: center; align: center; size: 22; color: muted; show: not mu_on }}',
         f"{c}text mu_t1 {{ at: hb2_x + 94, hb2_y + 50; anchor: left center; size: 13; weight: 700; family: \"Exo 2\"; color: ink; width: max(80, hb2_w - 106); lines: 1 }}",
         f"{c}text mu_t2 {{ at: hb2_x + 94, hb2_y + 70; anchor: left center; size: 10; family: \"Share Tech Mono\"; color: muted; width: max(80, hb2_w - 106); lines: 1 }}"]
    for n, (glyph, label, code) in enumerate([("‹", "Previous", 201), ("", "Play or pause", 202), ("›", "Next", 203)], start=1):
        bx = f"hb2_x + {92 + (n - 1) * 34}"
        B += [f'{c}zone box hbz2_{n} {{ from: {bx}, hb2_y + 88; size: 28, 28; corner: 14; cursor: pointer; role: button; label: "{label}"; show: op_live }}',
              f"{c}box {{ from: {bx}, hb2_y + 88; size: 28, 28; corner: 14; stroke: 1; color: rgb(h0_r, h0_g, h0_b); opacity: 0.35 + 0.5 * hbz2_{n}.hover }}",
              f"{c}on press hbz2_{n} {{ emit sb_press({code}) }}"]
        if n == 2:
            B += [f'{c}text "▶" {{ at: {bx} + 14, hb2_y + 102; anchor: center; align: center; size: 14; weight: 700; family: "Exo 2"; color: ink; show: not mu_playing }}',
                  f'{c}text "❚❚" {{ at: {bx} + 14, hb2_y + 102; anchor: center; align: center; size: 12; weight: 700; family: "Exo 2"; color: ink; show: mu_playing }}']
        else:
            B += [f'{c}text "{glyph}" {{ at: {bx} + 14, hb2_y + 102; anchor: center; align: center; size: 16; weight: 700; family: "Exo 2"; color: ink }}']
    # the visualiser: bars right of the controls, from the audio level, still when nothing plays
    vx0, vw = "hb2_x + 210", f"max(0, hb2_w - 228) / {VIZ_N}"
    B += [f"{c}group {{", f"{c}    show: mu_playing and hb2_w > 260"]
    for i in range(VIZ_N):
        hgt = f"max(1, 22 * clamp(lv.level, 0, 1) * (0.35 + 0.65 * abs(sin({i * 1.9:.1f} + lv.level * 7))))"
        B += [f"{c}    box {{ from: {vx0} + {i} * {vw}, hb2_y + 116 - {hgt}; size: max(1, {vw} - 2), {hgt}; corner: 1; color: rgb(h0_r, h0_g, h0_b); opacity: 0.7 }}"]
    B += [f"{c}}}",
          f"{c}box {{ from: hb2_x + 18, hb2_y + 120; size: max(1, hb2_w - 36), 1.4; color: muted; opacity: 0.18 }}",
          f"{c}box {{ from: hb2_x + 18, hb2_y + 120; size: max(1, (hb2_w - 36) * clamp(mu_prog, 0, 1)), 1.4; color: rgb(h0_r, h0_g, h0_b); opacity: 0.8 }}",
          f'{c}zone box hbz2_seek {{ from: hb2_x + 18, hb2_y + 113; size: max(1, hb2_w - 36), 14; cursor: pointer; role: slider; label: "Where the song is"; show: op_live and mu_len > 0 }}',
          f"{c}on press hbz2_seek {{ emit sb_seek(round(pointer.x)) }}"]
    L += hub(2, "MUSIC", B)

    # 3 · Wallpapers: the six newest thumbnails; a press wears one
    B = []
    cell, tw, th = "(hb3_w - 32) / 6", "min(48, (hb3_w - 32) / 6 - 6)", "min(40, hb3_h - 52)"
    for n in range(1, WALL_N + 1):
        tx = f"hb3_x + 16 + {n - 1} * {cell}"
        B += [f'{c}zone box hbz3_{n} {{ from: {tx}, hb3_y + 42; size: {tw}, {th}; corner: 6; cursor: pointer; role: button; label: "Wallpaper {n}"; show: op_live and wl{n}_on }}',
              f"{c}box {{ from: {tx}, hb3_y + 42; size: {tw}, {th}; corner: 6; color: rgb(0.12, 0.13, 0.11); opacity: 0.9; show: wl{n}_on }}",
              f"{c}image wl{n}_img {{ at: {tx}, hb3_y + 42; size: {tw}, {th}; fit: cover; show: wl{n}_on }}",
              f"{c}on press hbz3_{n} {{ emit sb_press({300 + n}) }}"]
    L += hub(3, "WALLPAPERS", B)

    # 4 · Settings: eight marks; a press opens mooi-settings at that page
    B = []
    cw, rh = "(hb4_w - 40) / 2", "(hb4_h - 40) / 4"
    for n, (label, _) in enumerate(SETTINGS, start=1):
        col, row = (n - 1) % 2, (n - 1) // 2
        sx, sy = f"hb4_x + 14 + {col} * ({cw} + 12)", f"hb4_y + 36 + {row} * {rh}"
        B += [f'{c}zone box hbz4_{n} {{ from: {sx}, {sy}; size: {cw}, max(18, {rh} - 2); corner: 6; cursor: pointer; role: button; label: "{label}"; show: op_live }}',
              f"{c}box {{ from: {sx}, {sy}; size: {cw}, max(18, {rh} - 2); corner: 6; color: rgb(0.13, 0.14, 0.12); opacity: 0.5 + 0.4 * hbz4_{n}.hover }}",
              f'{c}text "{label}" {{ at: {sx} + 7, {sy} + 11; anchor: left center; size: 9; family: "Exo 2"; color: ink; width: {cw} - 14; lines: 1 }}',
              f"{c}on press hbz4_{n} {{ emit sb_press({400 + n}) }}"]
    L += hub(4, "SETTINGS", B)

    # 5 · Notices: four from the bar's feed, newest first — a press is the notice's own default (or the
    # Nexus), its first action as a chip, a cross that dismisses it — and Clear for all of them
    B = []
    rh = "(hb5_h - 64) / 4"
    for n in range(1, NOTE_N + 1):
        ny = f"hb5_y + 34 + {n - 1} * {rh}"
        rx = "hb5_x + hb5_w - 34"            # the cross
        ax = "hb5_x + hb5_w - 104"           # the action chip
        B += [f'{c}zone box hbz5_{n} {{ from: hb5_x + 10, {ny}; size: hb5_w - 120, max(28, {rh} - 4); corner: 8; cursor: pointer; role: button; label: "Notice {n}"; show: op_live and nt{n}_on }}',
              f"{c}text nt{n}_t1 {{ at: hb5_x + 18, {ny} + 10; anchor: left center; size: 10; weight: 700; family: \"Exo 2\"; color: ink; width: hb5_w - if(nt{n}_act, 132, 62); lines: 1; show: nt{n}_on }}",
              f"{c}text nt{n}_t2 {{ at: hb5_x + 18, {ny} + 24; anchor: left center; size: 9; family: \"Share Tech Mono\"; color: muted; width: hb5_w - if(nt{n}_act, 132, 62); lines: 1; show: nt{n}_on }}",
              f"{c}on press hbz5_{n} {{ emit sb_press({500 + n}) }}",
              f'{c}zone box hbz5_a{n} {{ from: {ax}, {ny} + 4; size: 62, 20; corner: 10; cursor: pointer; role: button; label: "{{nt{n}_a1}}"; show: op_live and nt{n}_on and nt{n}_act }}',
              f"{c}box {{ from: {ax}, {ny} + 4; size: 62, 20; corner: 10; stroke: 1; color: rgb(h0_r, h0_g, h0_b); opacity: 0.4 + 0.5 * hbz5_a{n}.hover; show: nt{n}_on and nt{n}_act }}",
              f"{c}text nt{n}_a1 {{ at: {ax} + 31, {ny} + 14; anchor: center; align: center; size: 8; weight: 700; family: \"Share Tech Mono\"; color: ink; width: 56; lines: 1; show: nt{n}_on and nt{n}_act }}",
              f"{c}on press hbz5_a{n} {{ emit sb_press({520 + n}) }}",
              f'{c}zone box hbz5_x{n} {{ from: {rx}, {ny} + 4; size: 20, 20; corner: 10; cursor: pointer; role: button; label: "Dismiss notice {n}"; show: op_live and nt{n}_on }}',
              f'{c}text "×" {{ at: {rx} + 10, {ny} + 14; anchor: center; align: center; size: 13; family: "Exo 2"; color: if(hbz5_x{n}.hover > 0.5, ink, muted); show: nt{n}_on }}',
              f"{c}on press hbz5_x{n} {{ emit sb_press({540 + n}) }}"]
    B += [f'{c}text "Nothing new" {{ at: hb5_x + 18, hb5_y + 48; anchor: left center; size: 10; family: "Exo 2"; color: muted; show: nt_n < 0.5 }}',
          f'{c}zone box hbz5_clear {{ from: hb5_x + hb5_w - 72, hb5_y + hb5_h - 30; size: 56, 22; corner: 11; cursor: pointer; role: button; label: "Clear the notices"; show: op_live and nt_n > 0 }}',
          f"{c}box {{ from: hb5_x + hb5_w - 72, hb5_y + hb5_h - 30; size: 56, 22; corner: 11; stroke: 1; color: rgb(h0_r, h0_g, h0_b); opacity: 0.4 + 0.5 * hbz5_clear.hover; show: nt_n > 0 }}",
          f'{c}text "CLEAR" {{ at: hb5_x + hb5_w - 44, hb5_y + hb5_h - 19; anchor: center; align: center; size: 8; weight: 700; family: "Share Tech Mono"; color: muted; show: nt_n > 0 }}',
          f"{c}on press hbz5_clear {{ emit sb_press(590) }}"]
    L += hub(5, "NOTICES", B)

    # D212: the shape handles — a hub's size is shaped by its bottom-right corner, only in the Overview,
    # with its size read out while the corner is held
    for k, (_, label, _, _) in enumerate(HUBS, start=1):
        hx, hy = f"hb{k}_x + hb{k}_w - 16", f"hb{k}_y + hb{k}_h - 16"
        L += [f"{c}// hub {k}'s shape handle",
              f"{c}box {{ from: {hx}, {hy}; size: 10, 10; corner: 2; stroke: 1; color: rgb(h0_r, h0_g, h0_b); opacity: 0.6; show: op_mode == 4 }}",
              f'{c}text hb{k}_sz {{ at: hb{k}_x + hb{k}_w - 24, hb{k}_y + hb{k}_h - 30; anchor: right center; size: 9; family: "Share Tech Mono"; color: muted; show: op_mode == 4 and sf_rsz > {k - 0.5} and sf_rsz < {k + 0.5} }}',
              f'{c}zone box hbr{k} {{ from: hb{k}_x + hb{k}_w - 18, hb{k}_y + hb{k}_h - 18; size: 18, 18; corner: 4; cursor: pointer; role: button; label: "Resize {label}"; show: op_live and op_mode == 4 }}',
              f"{c}on drag hbr{k} {{ emit sb_rsz({k * 100}) }}",
              f"{c}on release hbr{k} {{ emit sb_rsz_drop({k * 100}) }}"]

    # the components: one row, each a small plate with its word and value
    for k, (id, label) in enumerate(COMPONENTS, start=1):
        B = [f'{c}// component {k}: {label}',
             f'{c}zone box cpz{k} {{ from: cp{k}_x, cp{k}_y; size: 56, 56; corner: 14; cursor: pointer; role: button; label: "{label}"; show: op_live and cp{k}_on }}',
             f"{c}group {{ glow: 18, 0.5 * cp{k}_up, #000000",
             f"{c}    box {{ from: cp{k}_x, cp{k}_y; size: 56, 56; corner: 14; color: rgb(0.09, 0.10, 0.09); opacity: 0.94; show: cp{k}_on }} }}",
             f"{c}box {{ from: cp{k}_x + 0.5, cp{k}_y + 0.5; size: 55, 55; corner: 14; stroke: if(sf_snap == {10 + k}, 1.6, 1); color: rgb(h0_r, h0_g, h0_b); opacity: 0.22 + 0.3 * cp{k}_lit + if(sf_snap == {10 + k}, 0.4, 0); show: cp{k}_on }}",
             f'{c}text "{GLYPH[id]}" {{ at: cp{k}_x + 28, cp{k}_y + 22; anchor: center; align: center; size: 15; family: "Exo 2"; color: if(cp{k}_lit, ink, muted); show: cp{k}_on }}',
             f"{c}text cp{k}_val {{ at: cp{k}_x + 28, cp{k}_y + 40; anchor: center; align: center; size: 8; family: \"Share Tech Mono\"; color: muted; width: 50; lines: 1; show: cp{k}_on }}",
             # a component acts when it is let go without a drag (the logic tells the two apart), so dragging
             # Wi-Fi out to the wallpaper does not also switch the radio
             f"{c}on drag cpz{k} {{ emit sb_drag({900 + k}) }}",
             f"{c}on release cpz{k} {{ emit sb_drop({900 + k}) }}"]
        if id in ("volume", "bright", "battery"):
            B += [f"{c}box {{ from: cp{k}_x + 10, cp{k}_y + 46; size: 36, 1.6; color: muted; opacity: 0.25; show: cp{k}_on }}",
                  f"{c}box {{ from: cp{k}_x + 10, cp{k}_y + 46; size: max(1, 36 * clamp(cp{k}_frac, 0, 1)), 1.6; color: rgb(h0_r, h0_g, h0_b); opacity: 0.9; show: cp{k}_on }}"]
        if id in ("volume", "bright"):
            B += [f"{c}on scroll cpz{k} {{ emit sb_wheel({k * 10} + if(wheel > 0, 1, 0)) }}"]
        L += rising(f"cp{k}_up", f"cp{k}_x + 28", f"cp{k}_y + 28", B)

    # the power row: five ways out, the last three each ask again
    L += [f"{c}// power: five ways out, the last three ask twice",
          f"{c}group {{", f"{c}    show: pw_open",
          f"{c}    box {{ from: cp6_x - 208, cp6_y - 202; size: 200, 194; corner: 14; color: rgb(0.07, 0.08, 0.07); opacity: 0.97 }}",
          f"{c}    box {{ from: cp6_x - 207.5, cp6_y - 201.5; size: 199, 193; corner: 14; stroke: 1; color: rgb(h0_r, h0_g, h0_b); opacity: 0.3 }}"]
    for n, (label, code) in enumerate(POWER, start=1):
        py = f"cp6_y - 194 + {(n - 1) * 36}"
        col = f"if(pw_arm == {n}, #ff9b8a, ink)" if n >= 3 else "ink"
        L += [f'{c}    zone box pwz{n} {{ from: cp6_x - 200, {py}; size: 184, 32; corner: 8; cursor: pointer; role: button; label: "{label}"; show: op_live and pw_open }}',
              f"{c}    box {{ from: cp6_x - 200, {py}; size: 184, 32; corner: 8; color: rgb(0.12, 0.13, 0.11); opacity: 0.8 }}",
              f'{c}    text "{label}" {{ at: cp6_x - 186, {py} + 16; anchor: left center; size: 10; family: "Exo 2"; color: {col}; show: pw_arm != {n} }}',
              f"{c}    on press pwz{n} {{ emit sb_press({code}) }}"]
        if n >= 3:
            L += [f'{c}    text "Press again to {label.lower()}" {{ at: cp6_x - 186, {py} + 16; anchor: left center; size: 10; weight: 700; family: "Exo 2"; color: {col}; show: pw_arm == {n} }}']
    L += [f"{c}}}", f"{base}}}"]
    return L


def host_decls(k):
    out = [f"    // host {k}"]
    for name, val in (("on", "false"), ("x", "0"), ("y", "0"), ("w", "0"), ("h", "0"), ("form", "1"), ("src", "0"),
                      ("kind", "1"), ("cx", "0"), ("r", "0.84"), ("g", "0.89"), ("b", "0.54"), ("val", "0"), ("rip", "0")):
        out.append(f"    fact h{k}_{name} = {val}")
    out += [f"    text h{k}_t1 = \"\"", f"    text h{k}_t2 = \"\""]
    for i in range(N):
        out += [f"    fact h{k}_tx{i} = -100", f"    fact h{k}_ty{i} = -100",
                f"    prop h{k}_x{i} = -100 ~sg.pt", f"    follow h{k}_x{i} = h{k}_tx{i}",
                f"    prop h{k}_y{i} = -100 ~sg.pt", f"    follow h{k}_y{i} = h{k}_ty{i}"]
    return out


def host_lets(k):
    """Each point as drawn: sprung place + wobble + the music's ripple, then pushed from (or drawn to) the
    pointer within 40 px."""
    out = []
    amp = "(wob + breath * 0.5 * (1 + sin(ph * 0.3)))"
    for i in range(N):
        out.append(f"    let h{k}_wx{i} = h{k}_x{i}")
        out.append(f"    let h{k}_wy{i} = h{k}_y{i} + sin(ph + {i * 23}) * {amp} * 0.4 + sin(ph * 2 + {i * 40}) * lv.level * 7 * h{k}_rip")
        out.append(f"    let h{k}_d{i} = sqrt(pow(h{k}_wx{i} - cursor.x, 2) + pow(h{k}_wy{i} - cursor.y, 2) + 1)")
        out.append(f"    let h{k}_p{i} = push * max(0, 40 - h{k}_d{i}) / 40 * 6 / h{k}_d{i}")
        out.append(f"    let h{k}_X{i} = h{k}_wx{i} + (h{k}_wx{i} - cursor.x) * h{k}_p{i}")
        out.append(f"    let h{k}_Y{i} = h{k}_wy{i} + (h{k}_wy{i} - cursor.y) * h{k}_p{i}")
    return out


def steps(k):
    return "; ".join([f"move h{k}_X0, h{k}_Y0"] + [f"line h{k}_X{i}, h{k}_Y{i}" for i in range(1, N)])


def line(k, ind, show):
    col = f"rgb(h{k}_r, h{k}_g, h{k}_b)"
    head_x = "pick(mod(floor(ph * 0.3), 64), " + ", ".join(f"h{k}_X{i}" for i in range(N)) + ")"
    head_y = "pick(mod(floor(ph * 0.3), 64), " + ", ".join(f"h{k}_Y{i}" for i in range(N)) + ")"
    s = steps(k)
    i2 = ind + "    "
    return [f"{ind}group {{",
            f"{i2}show: {show}",
            f"{i2}group {{",
            f"{i2}    glow: 22, 0.5 * st_glow, {col}",
            f"{i2}    path {{ stroke: 8; color: {col}; opacity: 0.1; {s} }}",
            f"{i2}    path {{ stroke: 3.2; color: {col}; opacity: 0.3; {s} }}",
            f"{i2}}}",
            f"{i2}path {{ stroke: 1.7; color: {col}; {s} }}",
            f"{i2}group {{ glow: 12, 0.9 * st_glow, #ffffff",
            f"{i2}    ellipse {{ at: {head_x}, {head_y}; radius: 2; color: #ffffff; show: wob > 0 }} }}",
            f"{ind}}}"]


def zone_bar(k, ind):
    return [f"{ind}zone box hz{k} {{ from: h{k}_x, h{k}_y; size: max(1, h{k}_w), max(1, h{k}_h); cursor: pointer; role: button; label: \"The Sigil\"; show: h{k}_on }}",
            f"{ind}on press hz{k} {{ emit sg_press({k}) }}",
            f"{ind}on press right hz{k} {{ emit sg_rpress({k}) }}",
            f"{ind}on scroll hz{k} {{ emit sg_wheel({k * 2} + if(wheel > 0, 1, 0)) }}",
            f"{ind}let hz{k}_in = hz{k}.hover > 0.5",
            f"{ind}on change hz{k}_in while hz{k}_in {{ emit sg_hover({k * 4 + 1}) }}",
            f"{ind}on change hz{k}_in while not hz{k}_in {{ emit sg_hover({k * 4}) }}"]


def compact_text(k, ind):
    col = f"mix(ink, rgb(h{k}_r, h{k}_g, h{k}_b), 0.15)"
    return [f"{ind}text h{k}_t1 {{ at: h{k}_cx, h{k}_y + h{k}_h / 2; anchor: left center; size: 12; weight: 700; family: \"Exo 2\"; color: {col}; width: max(10, h{k}_x + h{k}_w - h{k}_cx - 6); lines: 1; show: h{k}_on and h{k}_form > 0.5 and h{k}_form < 1.5 }}"]


def display_insides(ind):
    """The Pill's display (host 0, form 2): the kind's decoration in the display box (d_x, d_y, d_w, d_h, from
    the logic, which placed the line in the same box), and its words at (d_tx, d_ty)."""
    col = "rgb(h0_r, h0_g, h0_b)"
    i2 = ind + "    "
    out = [f"{ind}// the cover as halftone: the disc's inside (kind {K['disc']}), a pattern turning slowly, tinted"]
    out.append(f"{ind}group {{")
    out.append(f"{i2}show: h0_kind == {K['disc']}")
    out.append(f"{i2}let dr = min(d_h * 0.42, d_w * 0.2) - 3")
    out.append(f"{i2}let dcx = d_x + dr + 5")
    out.append(f"{i2}let dcy = d_y + d_h / 2")
    for gy in range(-10, 11):
        for gx in range(-10, 11):
            if gx * gx + gy * gy > 100:
                continue
            v = f"(0.5 + 0.5 * sin({gx * 37 + gy * 11} + ph * 0.15) * cos({gy * 29 - gx * 7} - ph * 0.1))"
            out.append(f"{i2}ellipse {{ at: dcx + {gx} * dr / 10, dcy + {gy} * dr / 10; radius: max(0.3, dr / 10 * 0.48 * {v}); color: mix({col}, #ffffff, 0.25 * {v}); opacity: 0.9 }}")
    out.append(f"{ind}}}")
    out += [f"{ind}// the ring's fill (kind {K['ring']}): a progress arc to h0_val",
            f"{ind}group {{",
            f"{i2}show: h0_kind == {K['ring']}",
            f"{i2}let rr = min(d_h * 0.4, d_w * 0.2) - 9",
            f"{i2}arc {{ at: d_x + rr + 11, d_y + d_h / 2; radius: rr; span: clamp(h0_val, 0, 1) * 306deg; rotate: 180deg - clamp(h0_val, 0, 1) * 153deg + 153deg; width: 6; color: {col} }}",
            f"{ind}}}",
            f"{ind}// the ribbon's fill (kind {K['ribbon']})",
            f"{ind}box {{ from: d_x + d_w * 0.05 + 4, d_y + d_h / 2 - 7; size: max(1, (d_w * 0.9 - 8) * clamp(h0_val, 0, 1)), 14; corner: 7; color: {col}; opacity: 0.85; show: h0_kind == {K['ribbon']} }}",
            f"{ind}// the horizon's sun (kind {K['horizon']}): where the day is on its arc (h0_val 0 sunrise … 1 sunset)",
            f"{ind}group {{",
            f"{i2}show: h0_kind == {K['horizon']}",
            f"{i2}glow: 18, 0.8 * st_glow, #ffd678",
            f"{i2}ellipse {{ at: d_x + d_w / 2 - cos(clamp(h0_val, 0, 1) * 180) * (d_w - 4) * 0.36, d_y + d_h - 2 - sin(clamp(h0_val, 0, 1) * 180) * (d_h - 4); radius: 10; color: #ffd678 }}",
            f"{ind}}}",
            f"{ind}// its words",
            f"{ind}text h0_t1 {{ at: d_tx, d_ty; anchor: left center; size: 22; weight: 700; family: \"Exo 2\"; color: ink; width: max(20, d_x + d_w - d_tx - 8); lines: 1 }}",
            f"{ind}text h0_t2 {{ at: d_tx, d_ty + 26; anchor: left center; size: 13; family: \"Share Tech Mono\"; color: muted; width: max(20, d_x + d_w - d_tx - 8); lines: 1 }}"]
    return out


def field(ind):
    """The field: points behind the display, warmed by the pointer, every 12 px (the budget, spec §11)."""
    out = [f"{ind}group {{", f"{ind}    show: field_on"]
    for gy in range(0, 19):
        for gx in range(0, 51):
            x, y = f"d_x + {gx * 12}", f"d_y + {gy * 12}"
            out.append(f"{ind}    box {{ from: {x}, {y}; size: 1.4, 1.4; color: rgb(h0_r, h0_g, h0_b); opacity: 0.06 + 0.4 * max(0, 1 - (abs({x} - cursor.x) + abs({y} - cursor.y)) / 150) }}")
    out.append(f"{ind}}}")
    return out


def scene():
    L = ["language 0.9", "",
         "// The Sigil (D207): one living line in place of the Pill — GENERATED by tools/gen-surface.py; do not edit.",
         "// The logic (shell/mooi-surface.luau) decides what each host shows and writes its points' targets;",
         "// this scene springs them, makes them live (wobble, ripple, the pointer) and draws the Sigil body.",
         "",
         "scene Sigil {",
         "    permissions {",
         '        run: "pleamar", "mooi", "hyprctl", "readlink", "nmcli", "bluetoothctl", "systemctl", "playerctl"',
         '        services: "files", "files.write", "env", "audio.level", "media", "audio", "audio.*", "media.*", "battery", "network", "network.*", "bluetooth", "bluetooth.*", "brightness", "brightness.*", "apps", "apps.launch", "workspaces", "window", "clock"',
         "    }",
         "    service audio.level as lv { level: number }",
         "    spring sg.pt = 260, 20",
         "    spring sg.drop = 300, 30",
         "    prop ph = 0",
         "    spin ph by if((h0_on or h1_on or h2_on or h3_on) and (wob > 0 or h0_rip > 0 or h1_rip > 0), 220, 0)",
         "    fact wob = 2.5", "    fact breath = 2.5", "    fact push = 1.6", "    fact field_on = true", "    fact calm = true",
         "    fact st_glow = 1",
         "    // its two text colours, from the palette (the logic): no theme import, nothing else to declare",
         "    fact ink_r = 0.93", "    fact ink_g = 0.88", "    fact ink_b = 0.84", "    fact mut_r = 0.55", "    fact mut_g = 0.56", "    fact mut_b = 0.52",
         "    let ink = rgb(ink_r, ink_g, ink_b)", "    let muted = rgb(mut_r, mut_g, mut_b)",
         "    // the display's plate: the palette's surface (seen live: without one the windows showed through)",
         "    fact pl_r = 0.09", "    fact pl_g = 0.10", "    fact pl_b = 0.09",
         "    // the Pill's display box and where its words go (from the logic, which put the line in the same box)",
         "    fact d_x = 0", "    fact d_y = 40", "    fact d_w = 600", "    fact d_h = 220", "    fact d_tx = 0", "    fact d_ty = 0",
         "    prop h0_drop = 0 ~sg.drop",
         "    follow h0_drop = if(h0_on and h0_form > 1.5, 1, 0)",
         "    event sg_press ->      // a host pressed (its number)",
         "    event sg_rpress ->     // a host right-pressed",
         "    event sg_hover ->      // k * 4 + area * 2 + on (area 0 the bar, 1 the display)",
         "    event sg_wheel ->      // k * 2 + 1 turning up"]
    for k in range(HOSTS):
        L += host_decls(k)
    for k in range(HOSTS):
        L += host_lets(k)
    L += ["", "    let op_px = cursor.x      // the pointer for the opening's follow mode (outside the generated block)", "    let op_py = cursor.y"]
    L += opening.text().rstrip("\n").split("\n")
    L += below_decls()
    L += ["", "    surface bar {", "        size: full, 40", "        anchor: top", "        level: top", "        reserve: -1",
          "        keyboard: none", "        rate: 60, 20 while calm",
          "        open: h0_on or h1_on or h2_on or h3_on      // no host, no surface (review I1)"]
    for k in range(HOSTS):
        show = f"h{k}_on" + (" and h0_drop < 0.5" if k == 0 else "")
        L += line(k, "        ", show)
        L += compact_text(k, "        ")
        L += zone_bar(k, "        ")
    L += ["    }", "", "    surface drop {", "        size: full, 300", "        anchor: top", "        level: top", "        reserve: -1",
          "        keyboard: none", "        rate: 60, 20 while calm", "        open: h0_drop > 0.01",
          "        group {", "            opacity: h0_drop",
          "            // the display's plate: the bar's surface, a hairline in the line's colour",
          "            box { from: d_x, d_y; size: d_w, d_h; corner: 18; color: rgb(pl_r, pl_g, pl_b); opacity: 0.98 }",
          "            box { from: d_x + 0.5, d_y + 0.5; size: d_w - 1, d_h - 1; corner: 18; stroke: 1; color: rgb(h0_r, h0_g, h0_b); opacity: 0.3 }"]
    L += field("            ")
    L += display_insides("            ")
    L += line(0, "            ", "h0_on")
    L += ["            zone box dz { from: d_x, d_y; size: d_w, d_h; cursor: pointer; role: button; label: \"The Sigil's display\" }",
          "            on press dz { emit sg_press(0) }",
          "            let dz_in = dz.hover > 0.5",
          "            on change dz_in while dz_in { emit sg_hover(3) }",
          "            on change dz_in while not dz_in { emit sg_hover(2) }",
          "        }", "    }"]
    L += surface_layers()
    L += ["}", ""]
    return "\n".join(L)


SLOTS = 8          # Presence slots on the desk layer (phase 1)
HOLE_GROW = 40     # the edge draws the torn wallpaper this far round the hole


def surface_layers():
    """D209: the opening drawn at the wallpaper — `ground` (level background: the hole's dark ground, later the
    hubs) and `edge` (level bottom, above the widgets: the torn rim and the warped wallpaper round it, no zones) —
    and the desk layer (Presences, under the windows). Nothing at level top or overlay: never over a window."""
    g = HOLE_GROW
    effects = ["tear", "aperture", "membrane", "ripple", "fold", "dissolve", "glass", "glow"]
    L = ["", "    // ── Surface (D209): the opening's ground and edge, and the Presences ──"]
    for e in effects:
        L += [f'    shader {e} = file "shaders/{e}.wgsl"']
    L += ['    shader ground = file "shaders/ground.wgsl"',
          '    shader aura = file "shaders/aura.wgsl"',
          "    fact rv_on = false", "    fact sf_firm = false   // the opening is open and the pointer has moved: the keyboard is ours",
          "    fact sf_fx = 1         // the opening's look: 1 tear · 2 aperture · 3 membrane · 4 ripple · 5 fold · 6 dissolve · 7 glass · 8 glow",
          "    fact sf_int = 0.85     // the effect's strength",
          "    fact sf_edge = 0.5     // the lip's width",
          "    fact sf_col = 0        // the rim's colour: 0 accent · 1 plain · 2 warm",
          "    fact sf_param = 85500  // intensity, edge and colour in one value for the shaders",
          "    fact sf_wall = true", "    fact sf_dim = 0.35", "    fact sf_tint = 0.18", "    fact sf_fit = 0",
          "    fact sf_grid = 0.45", "    fact sf_labels = true", "    fact sf_glow = 1", "    fact sf_ping = 0",
          "    fact sf_ovm = 16", "    fact sf_power_confirm = true", "    fact sf_edit = false", "    fact sf_rsz = 0",
          "    text rv_wall = \"\"", "    image rv_img = from rv_wall, 0, 0",
          "    image sf_cover = from rv_wall, 0, 0", "    image sf_contain = from rv_wall, 0, 0",
         "    event rv_down ->       // from `mooi reveal down`: Super went down",
         "    event rv_up ->         // from `mooi reveal up`: Super came up",
         "    event rv_esc ->        // Escape while revealing",
         "    event rv_move ->       // x * 10000 + y: the pointer while revealing",
         "    event sf_edit ->       // the settings page: move the places, let go to keep them",
         "    event sf_reset ->      // the settings page: put every place back to the layout's",
         "    event sf_undo ->       // the Overview: put the last dragged place back",
         "    event pp_rpress ->     // a Presence right-pressed: edit it",
         "    event pp_ctl ->        // slot * 10 + 1 previous · 2 play/pause · 3 next",
         "    event pp_drag ->       // slot * 100000000 + x * 10000 + y while dragged in edit",
         "    event pp_drop ->       // a Presence let go (its slot): a press if it was not dragged",
         "    event ed_undo ->", "    event ed_redo ->", "    event ed_done ->"]
    for k in range(SLOTS):
        L += [f"    fact p{k}_on = false", f"    fact p{k}_x = 0", f"    fact p{k}_y = 0", f"    fact p{k}_w = 220", f"    fact p{k}_h = 28",
              f"    fact p{k}_mode = 0", f"    fact p{k}_prog = 0", f"    fact p{k}_edit = false",
              f"    fact p{k}_r = 0.84", f"    fact p{k}_g = 0.89", f"    fact p{k}_b = 0.54",
              f"    text p{k}_t1 = \"\"", f"    text p{k}_t2 = \"\"", f"    text p{k}_icon = \"♫\""]
    # the ground: just above the wallpaper, under the widgets and the windows
    L += ["", "    surface ground {", "        size: full, full", "        anchor: top", "        level: background", "        reserve: -1",
          "        keyboard: none", "        rate: 60, 20 while calm", "        open: op_vis"] + opening.probe() + [
          "        group {",
          "            clip box { from: op_x, op_y; size: op_w, op_h; corner: op_r }",
          "            // the wallpaper the opening is cut into: the real one, fitted, with a tint, then the ground's",
          "            // own skin over it (a group's shader sees what the group holds, so the hubs stay above it)",
          "            group {",
          "                clip box { from: op_x, op_y; size: op_w, op_h; corner: op_r }",
          "                image sf_cover { at: 0, 0; size: ground.width, ground.height; fit: cover; show: sf_wall and sf_fit < 0.5 }",
          "                image sf_contain { at: 0, 0; size: ground.width, ground.height; fit: contain; show: sf_wall and sf_fit > 0.5 }",
          "                box { from: op_x, op_y; size: op_w, op_h; color: rgb(0.62, 0.84, 0.74); opacity: sf_tint * 0.16; show: sf_wall }",
          "                shader: ground, op_k, op_x, op_y, sf_dim, sf_grid, sf_tint",
          "            }",
          "            // light through the skin: a soft glow at Music and the Notices while the opening is open",
          "            shader aura { at: op_x, op_y; size: op_w, op_h; values: op_k, op_x, op_y, hb2_x, hb2_y, hb5_x, hb5_y, sf_glow + sf_ping * 1.5; colors: rgb(0.62, 0.84, 0.74), rgb(0.95, 0.62, 0.38); show: op_vis and sf_glow > 0.5 }",
          "            // the Overview: the wallpaper pulls back to a thin lit margin and the canvas takes the screen",
          "            box { from: op_x + sf_ovm, op_y + sf_ovm; size: max(0, op_w - 2 * sf_ovm), max(0, op_h - 2 * sf_ovm); corner: max(0, op_r - 6); color: rgb(0.035, 0.05, 0.055); opacity: 0.99; show: op_vis and op_mode == 4 }",
          "            // its grid: three uprights and two crossbars, faint enough to arrange against without seeing lines",
          "            box { from: op_x + op_w * 0.25, op_y + sf_ovm; size: 1, max(0, op_h - 2 * sf_ovm); color: rgb(0.62, 0.84, 0.74); opacity: 0.03; show: op_vis and op_mode == 4 }",
          "            box { from: op_x + op_w * 0.5, op_y + sf_ovm; size: 1, max(0, op_h - 2 * sf_ovm); color: rgb(0.62, 0.84, 0.74); opacity: 0.03; show: op_vis and op_mode == 4 }",
          "            box { from: op_x + op_w * 0.75, op_y + sf_ovm; size: 1, max(0, op_h - 2 * sf_ovm); color: rgb(0.62, 0.84, 0.74); opacity: 0.03; show: op_vis and op_mode == 4 }",
          "            box { from: op_x + sf_ovm, op_y + op_h * 0.33; size: max(0, op_w - 2 * sf_ovm), 1; color: rgb(0.62, 0.84, 0.74); opacity: 0.03; show: op_vis and op_mode == 4 }",
          "            box { from: op_x + sf_ovm, op_y + op_h * 0.66; size: max(0, op_w - 2 * sf_ovm), 1; color: rgb(0.62, 0.84, 0.74); opacity: 0.03; show: op_vis and op_mode == 4 }",
          "            text \"THE SUBSURFACE\" { at: op_x + sf_ovm + 24, op_y + sf_ovm + 48; anchor: left center; size: 11; weight: 700; family: \"Share Tech Mono\"; color: rgb(0.62, 0.84, 0.74); show: op_vis and op_mode == 4 }",
          "            text \"drag to arrange  /  Esc to close\" { at: op_x + sf_ovm + 24, op_y + sf_ovm + 66; anchor: left center; size: 10; family: \"Share Tech Mono\"; color: rgb(0.55, 0.6, 0.58); show: op_mode == 4 and sf_labels > 0.5 }"]
    L += below_group()
    L += ["            // the Overview's three controls, over the canvas at its top right",
          "            box { from: op_x + op_w - sf_ovm - 230, op_y + sf_ovm + 40; size: 218, 26; corner: 6; color: rgb(0.08, 0.1, 0.11); opacity: 0.72; show: op_vis and op_mode == 4 }",
          "            text \"UNDO\" { at: op_x + op_w - sf_ovm - 230 + 34, op_y + sf_ovm + 40 + 13; anchor: center; align: center; size: 9; weight: 700; family: \"Share Tech Mono\"; color: rgb(0.62, 0.84, 0.74); show: op_vis and op_mode == 4 }",
          "            text \"RESET\" { at: op_x + op_w - sf_ovm - 230 + 109, op_y + sf_ovm + 40 + 13; anchor: center; align: center; size: 9; weight: 700; family: \"Share Tech Mono\"; color: rgb(0.62, 0.84, 0.74); show: op_vis and op_mode == 4 }",
          "            text \"CLOSE\" { at: op_x + op_w - sf_ovm - 230 + 184, op_y + sf_ovm + 40 + 13; anchor: center; align: center; size: 9; weight: 700; family: \"Share Tech Mono\"; color: rgb(0.62, 0.84, 0.74); show: op_vis and op_mode == 4 }",
          "            zone box ov_undo { from: op_x + op_w - sf_ovm - 230, op_y + sf_ovm + 40; size: 68, 26; cursor: pointer; role: button; label: \"Undo the last place\"; show: op_live and op_mode == 4 }",
          "            on press ov_undo { emit sf_undo }",
          "            zone box ov_reset { from: op_x + op_w - sf_ovm - 230 + 75, op_y + sf_ovm + 40; size: 68, 26; cursor: pointer; role: button; label: \"Put every place back\"; show: op_live and op_mode == 4 }",
          "            on press ov_reset { emit sf_reset }",
          "            zone box ov_close { from: op_x + op_w - sf_ovm - 230 + 150, op_y + sf_ovm + 40; size: 68, 26; cursor: pointer; role: button; label: \"Close the Overview\"; show: op_live and op_mode == 4 }",
          "            on press ov_close { emit rv_esc }",
          "            // a press on the thin wallpaper margin closes it too",
          "            zone box ov_edge_t { from: op_x, op_y; size: op_w, max(1, sf_ovm); cursor: pointer; role: button; label: \"Close the Overview\"; show: op_live and op_mode == 4 and sf_ovm > 0.5 }",
          "            on press ov_edge_t { emit rv_esc }",
          "            zone box ov_edge_b { from: op_x, op_y + op_h - sf_ovm; size: op_w, max(1, sf_ovm); cursor: pointer; role: button; label: \"Close the Overview\"; show: op_live and op_mode == 4 and sf_ovm > 0.5 }",
          "            on press ov_edge_b { emit rv_esc }",
          "            zone box ov_edge_l { from: op_x, op_y + sf_ovm; size: max(1, sf_ovm), max(0, op_h - 2 * sf_ovm); cursor: pointer; role: button; label: \"Close the Overview\"; show: op_live and op_mode == 4 and sf_ovm > 0.5 }",
          "            on press ov_edge_l { emit rv_esc }",
          "            zone box ov_edge_r { from: op_x + op_w - sf_ovm, op_y + sf_ovm; size: max(1, sf_ovm), max(0, op_h - 2 * sf_ovm); cursor: pointer; role: button; label: \"Close the Overview\"; show: op_live and op_mode == 4 and sf_ovm > 0.5 }",
          "            on press ov_edge_r { emit rv_esc }",
          "            // the Overview's thin lit margin: the wallpaper's edge, pulled back",
          "            box { from: op_x + sf_ovm, op_y + sf_ovm; size: max(0, op_w - 2 * sf_ovm), max(0, op_h - 2 * sf_ovm); stroke: 1; color: rgb(0.62, 0.84, 0.74); opacity: 0.32; show: op_vis and op_mode == 4 and sf_ovm > 0.5 }",
          "        }",
          "    }"]
    # the edge: the torn wallpaper round the hole, above the widgets, under the windows; it catches nothing
    clip = f"clip box {{ from: op_x - {g}, op_y - {g}; size: op_w + {g * 2}, op_h + {g * 2}; corner: op_r + {g} }}"
    img = "image rv_img { at: 0, 0; size: edge.width, edge.height; fit: cover }"
    L += ["", "    surface edge {", "        size: full, full", "        anchor: top", "        level: bottom", "        reserve: -1",
          "        keyboard: exclusive while op_vis and sf_firm", "        rate: 60", "        open: op_vis"] + opening.probe() + [
          "        // where the pointer is, told to the logic as it moves (every 6 px), while revealing",
          "        let rv_q = round(cursor.x / 6) * 100000 + round(cursor.y / 6)",
          "        on change rv_q while rv_on or op_vis { emit rv_move(round(cursor.x) * 10000 + round(cursor.y)) }",
          "        // the keyboard, once the opening is firm: walk the places, press, widen, heal",
          "        on key Escape { emit rv_esc }",
          "        on key Tab { emit op_key(1) }",
          "        on key Shift+Tab { emit op_key(-1) }",
          "        on key Return { emit op_key(2) }",
          "        on key Page_Up { emit op_wheel(1) }",
          "        on key Page_Down { emit op_wheel(-1) }",
          "        // typing into the Apps hub, while it is snapped or the Overview is open: letters, a space, a rub-out"]
    for ch in TYPED:
        L += [f"        on key {ch} while sf_snap == 1 or op_mode == 4 {{ emit op_type({ord(ch)}) }}"]
    L += ["        on key space while sf_snap == 1 or op_mode == 4 { emit op_type(32) }",
          "        on key BackSpace while sf_snap == 1 or op_mode == 4 { emit op_type(8) }",
          "        // the eight looks: the real wallpaper, cut open over the hole (the surface's own size: screen.height",
          "        // is the scene's first surface's, the 40 px bar strip — found live, D208)",
          "        // a group's shader sees its own box: the clip's, from its top left corner — each derives the screen",
          "        // origin from op_x/op_y in its own file, so all eight values are free for shape and strength",
          "        // (the intensity, edge and colour arrive packed in sf_param: see the shaders)"]
    for i, e in enumerate(effects, start=1):
        L += ["        group {",
              f"            show: sf_fx > {i - 0.5} and sf_fx < {i + 0.5}",
              f"            {clip}",
              f"            shader: {e}, op_k, op_x, op_y, op_w, op_h, op_r, sf_param, 0",
              f"            {img}",
              "        }"]
    L += ["    }"]
    # the desk surface: Presences under the windows
    any_on = " or ".join(f"p{k}_on" for k in range(SLOTS))
    L += ["", "    surface desk {", "        size: full, full", "        anchor: top", "        level: bottom", "        reserve: -1",
          "        keyboard: none", "        rate: 60, 20 while calm", f"        open: {any_on}"]
    for k in range(SLOTS):
        i2 = "            "
        col = f"rgb(p{k}_r, p{k}_g, p{k}_b)"
        L += [f"        group {{", f"{i2}show: p{k}_on",
              f"{i2}let p{k}_near = if(sqrt(pow(cursor.x - (p{k}_x + p{k}_w / 2), 2) + pow(cursor.y - (p{k}_y + p{k}_h / 2), 2)) < 160, 1, 0)",
              f"{i2}let p{k}_show = min(2, p{k}_mode + p{k}_near)    // coming near wakes it a step",
              f"{i2}// ghost: its mark, one line, a hairline of progress",
              f"{i2}text p{k}_icon {{ at: p{k}_x + 10, p{k}_y + 14; anchor: center; size: 14; color: {col} }}",
              f"{i2}text p{k}_t1 {{ at: p{k}_x + 24, p{k}_y + 14; anchor: left center; size: if(p{k}_show > 0.5, 15, 12); weight: 700; family: \"Exo 2\"; color: ink; width: max(20, p{k}_w - 30); lines: 1 }}",
              f"{i2}box {{ from: p{k}_x + 24, p{k}_y + 26; size: max(1, (p{k}_w - 30) * clamp(p{k}_prog, 0, 1)), 1.4; color: {col}; opacity: 0.8 }}",
              f"{i2}// embedded and full: the second line",
              f"{i2}text p{k}_t2 {{ at: p{k}_x + 24, p{k}_y + 42; anchor: left center; size: 12; family: \"Share Tech Mono\"; color: muted; width: max(20, p{k}_w - 30); lines: 1; show: p{k}_show > 0.5 }}",
              f"{i2}// full: the controls",
              f"{i2}group {{", f"{i2}    show: p{k}_show > 1.5"]
        for n, (glyph, label) in enumerate([("‹", "Previous"), ("▶", "Play or pause"), ("›", "Next")], start=1):
            L += [f"{i2}    zone box pc{k}_{n} {{ from: p{k}_x + 24 + {(n - 1) * 34}, p{k}_y + 56; size: 28, 28; corner: 14; cursor: pointer; role: button; label: \"{label}\" }}",
                  f"{i2}    box {{ from: p{k}_x + 24 + {(n - 1) * 34}, p{k}_y + 56; size: 28, 28; corner: 14; stroke: 1; color: {col}; opacity: 0.4 + 0.6 * pc{k}_{n}.hover }}",
                  f"{i2}    text \"{glyph}\" {{ at: p{k}_x + 38 + {(n - 1) * 34}, p{k}_y + 70; anchor: center; size: 14; weight: 700; family: \"Exo 2\"; color: ink }}",
                  f"{i2}    on press pc{k}_{n} {{ emit pp_ctl({k * 10 + n}) }}"]
        L += [f"{i2}}}",
              f"{i2}// the whole Presence: a press, a right press (edit), and in edit a drag",
              f"{i2}zone box pz{k} {{ from: p{k}_x, p{k}_y; size: p{k}_w, if(p{k}_show > 1.5, 52, p{k}_h); cursor: if(p{k}_edit, grab, pointer); role: button; label: \"A Presence\" }}",
              f"{i2}// a press acts when it is let go without a drag; dragged in edit it moves, dragged into an opening it is buried",
              f"{i2}on press right pz{k} {{ emit pp_rpress({k}) }}",
              f"{i2}on drag pz{k} while p{k}_edit or op_live {{ emit pp_drag({k * 100000000} + round(pointer.x) * 10000 + round(pointer.y)) }}",
              f"{i2}on release pz{k} {{ emit pp_drop({k}) }}",
              f"{i2}// edit: a dashed outline and its strip — undo, redo, done",
              f"{i2}group {{", f"{i2}    show: p{k}_edit",
              f"{i2}    box {{ from: p{k}_x - 4, p{k}_y - 4; size: p{k}_w + 8, p{k}_h + 8; corner: 6; stroke: 1.2; color: {col}; opacity: 0.8 }}"]
        for n, (glyph, ev) in enumerate([("↶", "ed_undo"), ("↷", "ed_redo"), ("Done", "ed_done")]):
            w = 44 if glyph == "Done" else 26
            x = f"p{k}_x + {n * 32}"
            L += [f"{i2}    zone box ed{k}_{n} {{ from: {x}, p{k}_y - 34; size: {w}, 24; corner: 4; cursor: pointer; role: button; label: \"{ev}\" }}",
                  f"{i2}    box {{ from: {x}, p{k}_y - 34; size: {w}, 24; corner: 4; color: rgb(pl_r, pl_g, pl_b); opacity: 0.9 }}",
                  f"{i2}    text \"{glyph}\" {{ at: {x} + {w / 2}, p{k}_y - 22; anchor: center; size: 12; weight: 700; family: \"Exo 2\"; color: ink }}",
                  f"{i2}    on press ed{k}_{n} {{ emit {ev} }}"]
        L += [f"{i2}}}", "        }"]
    L += ["    }"]
    return L

if __name__ == "__main__":
    OUT.write_text(scene())
