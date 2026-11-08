#!/usr/bin/env python3
"""Generate shell/mooi-surface.plm: the Sigil's scene (D207, docs/superpowers/specs/2026-11-07-sigil-design.md).

Four hosts (0 the Pill, 1-3 islands), each one line of N = 64 points: the logic writes each point's target
(h{k}_tx{i}, h{k}_ty{i}) and the scene springs to it, adds the temperament's wobble, the music's ripple and
the pointer's push, and draws it as the Sigil body (three stroke passes and a pen head). Two surfaces: `bar`
(the bar's height, always open; every host's resting form and its zone) and `drop` (open only while the Pill
shows a display: the line, the display's insides, the field). Run: python3 tools/gen-surface.py
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
BMO = (160, 196)
APP_N, WALL_N, NOTE_N = 12, 6, 4
SETTINGS = ["Bar & Frame", "Wallpapers", "Widgets", "Theme", "Islands", "Notch", "Sound", "The Sigil"]
POWER = [("Lock", 951), ("Sleep", 952), ("Log out", 953), ("Restart", 954), ("Shut down", 955)]
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
    out["bmo"] = (int(math.floor(0.06 * w + 0.5)), h - 300, BMO[0], BMO[1])
    return out


def below_decls():
    """The facts, words and pictures the logic writes; declared before the surfaces that draw them."""
    P = below_defaults(1920, 1080)
    L = ["", "    // ── the subsurface (D209): the hubs, the components, the places the logic writes ──",
         "    event sb_press ->     // a hub mark or a component (hub * 100 + item, 900 + component)",
         "    event sb_drag ->      // a place being dragged out (its code)",
         "    event sb_drop ->      // and let go",
         "    event sb_wheel ->     // a component's wheel (component * 10 + up)"]
    for k, (id, _, bw, bh) in enumerate(HUBS, start=1):
        x, y, _, _ = P[id]
        L += [f"    fact hb{k}_x = {x}", f"    fact hb{k}_y = {y}", f"    fact hb{k}_w = {bw}", f"    fact hb{k}_h = {bh}"]
    for k, (id, _) in enumerate(COMPONENTS, start=1):
        x, y, _, _ = P[id]
        L += [f"    fact cp{k}_x = {x}", f"    fact cp{k}_y = {y}", f"    fact cp{k}_on = true",
              f"    fact cp{k}_lit = false", f"    fact cp{k}_frac = 0", f'    text cp{k}_val = ""']
    L += ["    fact pw_open = false", "    fact pw_arm = false"]
    for n in range(1, APP_N + 1):
        L += [f"    fact ab{n}_on = false", f"    fact ab{n}_iconed = false",
              f'    text ab{n}_name = ""', f'    text ab{n}_letter = ""', f'    text ab{n}_path = ""',
              f"    image ab{n}_img = from ab{n}_path, 32, 32"]
    L += ["    fact mu_on = false", "    fact mu_playing = false", "    fact mu_prog = 0",
          '    text mu_t1 = ""', '    text mu_t2 = ""', '    text mu_art = ""', "    image mu_img = from mu_art, 64, 64"]
    for n in range(1, WALL_N + 1):
        L += [f"    fact wl{n}_on = false", f'    text wl{n}_thumb = ""', f"    image wl{n}_img = from wl{n}_thumb, 48, 40"]
    for n in range(1, NOTE_N + 1):
        L += [f"    fact nt{n}_on = false", f'    text nt{n}_t1 = ""', f'    text nt{n}_t2 = ""']
    L += ["    fact nt_n = 0"]
    return L


def below_group(base="            "):
    """The opening's content: the hubs as places (each draggable as a whole), the app marks, the music, the
    wallpapers, the settings marks, the notices, the components and the power row. Every zone is live only
    while the opening shows (`op_vis`); nothing here is time-driven — the logic writes every value."""
    c = base + "    "
    L = [f"{base}// below: what lives under the wallpaper (D209) — the hubs, the components, BMO's home",
         f"{base}group {{", f"{c}show: op_mode > 0"]

    def plate(k, label):
        return [f'{c}// hub {k}: {label}',
                f"{c}box {{ from: hb{k}_x, hb{k}_y; size: hb{k}_w, hb{k}_h; corner: 18; color: rgb(0.07, 0.08, 0.07); opacity: 0.94 }}",
                f"{c}box {{ from: hb{k}_x + 0.5, hb{k}_y + 0.5; size: hb{k}_w - 1, hb{k}_h - 1; corner: 18; stroke: 1; color: rgb(h0_r, h0_g, h0_b); opacity: 0.28 }}",
                f'{c}text "{label}" {{ at: hb{k}_x + 16, hb{k}_y + 20; anchor: left center; size: 10; weight: 700; family: "Share Tech Mono"; color: muted }}']

    # the whole place: dragged out to make a Presence, let go to bury it
    def place_zone(k, label):
        return [f'{c}zone box hbz{k}_0 {{ from: hb{k}_x, hb{k}_y; size: hb{k}_w, hb{k}_h; corner: 18; cursor: grab; role: button; label: "{label}"; show: op_vis and op_mode > 0 }}',
                f"{c}on drag hbz{k}_0 {{ emit sb_drag({k * 100}) }}",
                f"{c}on release hbz{k}_0 {{ emit sb_drop({k * 100}) }}"]

    # 1 · Apps: four by three marks, the most launched first (the logic chooses them)
    L += plate(1, "APPS") + place_zone(1, "Apps")
    for n in range(1, APP_N + 1):
        col, row = (n - 1) % 4, (n - 1) // 4
        mx, my = f"hb1_x + {18 + col * 81}", f"hb1_y + {40 + row * 56}"
        L += [f'{c}zone box hbz1_{n} {{ from: {mx}, {my}; size: 78, 52; corner: 10; cursor: pointer; role: button; label: "App {n}"; show: op_vis and op_mode > 0 and ab{n}_on }}',
              f"{c}box {{ from: {mx}, {my}; size: 30, 30; corner: 8; color: rgb(0.14, 0.15, 0.13); opacity: 0.9; show: op_vis and ab{n}_on }}",
              f"{c}text ab{n}_letter {{ at: {mx} + 15, {my} + 15; anchor: center; align: center; size: 12; weight: 700; family: \"Exo 2\"; color: ink; show: op_vis and ab{n}_on and not ab{n}_iconed }}",
              f"{c}image ab{n}_img {{ at: {mx}, {my}; size: 30, 30; fit: cover; show: op_vis and ab{n}_on and ab{n}_iconed }}",
              f"{c}text ab{n}_name {{ at: {mx} + 15, {my} + 42; anchor: center; align: center; size: 9; family: \"Exo 2\"; color: muted; width: 76; lines: 1; show: op_vis and ab{n}_on }}",
              f"{c}on press hbz1_{n} {{ emit sb_press({100 + n}) }}"]

    # 2 · Music: art, the two words, the controls, a hairline of progress
    L += plate(2, "MUSIC") + place_zone(2, "Music")
    L += [f"{c}box {{ from: hb2_x + 18, hb2_y + 40; size: 64, 64; corner: 10; color: rgb(0.13, 0.14, 0.12); opacity: 0.9 }}",
          f"{c}image mu_img {{ at: hb2_x + 18, hb2_y + 40; size: 64, 64; fit: cover; show: op_vis and mu_on }}",
          f'{c}text "♫" {{ at: hb2_x + 50, hb2_y + 72; anchor: center; align: center; size: 22; color: muted; show: op_vis and not mu_on }}',
          f"{c}text mu_t1 {{ at: hb2_x + 94, hb2_y + 50; anchor: left center; size: 13; weight: 700; family: \"Exo 2\"; color: ink; width: 208; lines: 1 }}",
          f"{c}text mu_t2 {{ at: hb2_x + 94, hb2_y + 70; anchor: left center; size: 10; family: \"Share Tech Mono\"; color: muted; width: 208; lines: 1 }}"]
    for n, (glyph, label, code) in enumerate([("‹", "Previous", 201), ("", "Play or pause", 202), ("›", "Next", 203)], start=1):
        bx = f"hb2_x + {92 + (n - 1) * 34}"
        L += [f'{c}zone box hbz2_{n} {{ from: {bx}, hb2_y + 88; size: 28, 28; corner: 14; cursor: pointer; role: button; label: "{label}"; show: op_vis and op_mode > 0 }}',
              f"{c}box {{ from: {bx}, hb2_y + 88; size: 28, 28; corner: 14; stroke: 1; color: rgb(h0_r, h0_g, h0_b); opacity: 0.35 + 0.5 * hbz2_{n}.hover }}",
              f"{c}on press hbz2_{n} {{ emit sb_press({code}) }}"]
        if n == 2:
            L += [f'{c}text "▶" {{ at: {bx} + 14, hb2_y + 102; anchor: center; align: center; size: 14; weight: 700; family: "Exo 2"; color: ink; show: op_vis and not mu_playing }}',
                  f'{c}text "❚❚" {{ at: {bx} + 14, hb2_y + 102; anchor: center; align: center; size: 12; weight: 700; family: "Exo 2"; color: ink; show: op_vis and mu_playing }}']
        else:
            L += [f'{c}text "{glyph}" {{ at: {bx} + 14, hb2_y + 102; anchor: center; align: center; size: 16; weight: 700; family: "Exo 2"; color: ink }}']
    L += [f"{c}box {{ from: hb2_x + 18, hb2_y + 120; size: max(1, (hb2_w - 36) * clamp(mu_prog, 0, 1)), 1.4; color: rgb(h0_r, h0_g, h0_b); opacity: 0.8 }}"]

    # 3 · Wallpapers: the six newest thumbnails; a press wears one
    L += plate(3, "WALLPAPERS") + place_zone(3, "Wallpapers")
    for n in range(1, WALL_N + 1):
        tx = f"hb3_x + {16 + (n - 1) * 56}"
        L += [f'{c}zone box hbz3_{n} {{ from: {tx}, hb3_y + 42; size: 48, 40; corner: 6; cursor: pointer; role: button; label: "Wallpaper {n}"; show: op_vis and op_mode > 0 and wl{n}_on }}',
              f"{c}box {{ from: {tx}, hb3_y + 42; size: 48, 40; corner: 6; color: rgb(0.12, 0.13, 0.11); opacity: 0.9; show: op_vis and wl{n}_on }}",
              f"{c}image wl{n}_img {{ at: {tx}, hb3_y + 42; size: 48, 40; fit: cover; show: op_vis and wl{n}_on }}",
              f"{c}on press hbz3_{n} {{ emit sb_press({300 + n}) }}"]

    # 4 · Settings: eight marks; a press opens the settings window
    L += plate(4, "SETTINGS") + place_zone(4, "Settings")
    for n, label in enumerate(SETTINGS, start=1):
        col, row = (n - 1) % 2, (n - 1) // 2
        sx, sy = f"hb4_x + {14 + col * 138}", f"hb4_y + {36 + row * 24}"
        L += [f'{c}zone box hbz4_{n} {{ from: {sx}, {sy}; size: 132, 22; corner: 6; cursor: pointer; role: button; label: "{label}"; show: op_vis and op_mode > 0 }}',
              f"{c}box {{ from: {sx}, {sy}; size: 132, 22; corner: 6; color: rgb(0.13, 0.14, 0.12); opacity: 0.5 + 0.4 * hbz4_{n}.hover; show: op_vis }}",
              f'{c}text "{label}" {{ at: {sx} + 7, {sy} + 11; anchor: left center; size: 9; family: "Exo 2"; color: ink; width: 118; lines: 1 }}',
              f"{c}on press hbz4_{n} {{ emit sb_press({400 + n}) }}"]

    # 5 · Notices: four from the bar's feed, and its own Clear
    L += plate(5, "NOTICES") + place_zone(5, "Notices")
    for n in range(1, NOTE_N + 1):
        ny = f"hb5_y + {34 + (n - 1) * 38}"
        L += [f'{c}zone box hbz5_{n} {{ from: hb5_x + 10, {ny}; size: 300, 34; corner: 8; cursor: pointer; role: button; label: "Notice {n}"; show: op_vis and op_mode > 0 and nt{n}_on }}',
              f"{c}text nt{n}_t1 {{ at: hb5_x + 18, {ny} + 10; anchor: left center; size: 10; weight: 700; family: \"Exo 2\"; color: ink; width: 280; lines: 1; show: op_vis and nt{n}_on }}",
              f"{c}text nt{n}_t2 {{ at: hb5_x + 18, {ny} + 24; anchor: left center; size: 9; family: \"Share Tech Mono\"; color: muted; width: 280; lines: 1; show: op_vis and nt{n}_on }}",
              f"{c}on press hbz5_{n} {{ emit sb_press({500 + n}) }}"]
    L += [f'{c}zone box hbz5_clear {{ from: hb5_x + 248, hb5_y + 190; size: 56, 22; corner: 11; cursor: pointer; role: button; label: "Clear the notices"; show: op_vis and op_mode > 0 and nt_n > 0 }}',
          f"{c}box {{ from: hb5_x + 248, hb5_y + 190; size: 56, 22; corner: 11; stroke: 1; color: rgb(h0_r, h0_g, h0_b); opacity: 0.4 + 0.5 * hbz5_clear.hover }}",
          f'{c}text "CLEAR" {{ at: hb5_x + 276, hb5_y + 201; anchor: center; align: center; size: 8; weight: 700; family: "Share Tech Mono"; color: muted }}',
          f"{c}on press hbz5_clear {{ emit sb_press(590) }}"]

    # the components: one row, each a small plate with its word and value
    for k, (id, label) in enumerate(COMPONENTS, start=1):
        L += [f'{c}// component {k}: {label}',
              f'{c}zone box cpz{k} {{ from: cp{k}_x, cp{k}_y; size: 56, 56; corner: 14; cursor: pointer; role: button; label: "{label}"; show: op_vis and op_mode > 0 and cp{k}_on }}',
              f"{c}box {{ from: cp{k}_x, cp{k}_y; size: 56, 56; corner: 14; color: rgb(0.09, 0.10, 0.09); opacity: 0.94; show: op_vis and cp{k}_on }}",
              f"{c}box {{ from: cp{k}_x + 0.5, cp{k}_y + 0.5; size: 55, 55; corner: 14; stroke: 1; color: rgb(h0_r, h0_g, h0_b); opacity: 0.22 + 0.3 * cp{k}_lit; show: op_vis and cp{k}_on }}",
              f'{c}text "{GLYPH[id]}" {{ at: cp{k}_x + 28, cp{k}_y + 22; anchor: center; align: center; size: 15; family: "Exo 2"; color: if(cp{k}_lit, ink, muted); show: op_vis and cp{k}_on }}',
              f"{c}text cp{k}_val {{ at: cp{k}_x + 28, cp{k}_y + 40; anchor: center; align: center; size: 8; family: \"Share Tech Mono\"; color: muted; width: 50; lines: 1; show: op_vis and cp{k}_on }}",
              f"{c}on press cpz{k} {{ emit sb_press({900 + k}) }}",
              f"{c}on drag cpz{k} {{ emit sb_drag({900 + k}) }}"]
        if id in ("volume", "bright", "battery"):
            L += [f"{c}box {{ from: cp{k}_x + 10, cp{k}_y + 46; size: 36, 1.6; color: muted; opacity: 0.25; show: op_vis and cp{k}_on }}",
                  f"{c}box {{ from: cp{k}_x + 10, cp{k}_y + 46; size: max(1, 36 * clamp(cp{k}_frac, 0, 1)), 1.6; color: rgb(h0_r, h0_g, h0_b); opacity: 0.9; show: op_vis and cp{k}_on }}"]
        if id in ("volume", "bright"):
            L += [f"{c}on scroll cpz{k} {{ emit sb_wheel({k * 10} + if(wheel > 0, 1, 0)) }}"]

    # the power row: five ways out, the last three armed by a second press
    L += [f"{c}// power: five ways out, the last three ask twice",
          f"{c}group {{", f"{c}    show: op_vis and pw_open",
          f"{c}    box {{ from: cp6_x - 208, cp6_y - 202; size: 200, 194; corner: 14; color: rgb(0.07, 0.08, 0.07); opacity: 0.97 }}",
          f"{c}    box {{ from: cp6_x - 207.5, cp6_y - 201.5; size: 199, 193; corner: 14; stroke: 1; color: rgb(h0_r, h0_g, h0_b); opacity: 0.3 }}"]
    for n, (label, code) in enumerate(POWER, start=1):
        py = f"cp6_y - 194 + {(n - 1) * 36}"
        col = "if(pw_arm, #ff9b8a, ink)" if n >= 3 else "ink"
        L += [f'{c}    zone box pwz{n} {{ from: cp6_x - 200, {py}; size: 184, 32; corner: 8; cursor: pointer; role: button; label: "{label}"; show: op_vis and pw_open }}',
              f"{c}    box {{ from: cp6_x - 200, {py}; size: 184, 32; corner: 8; color: rgb(0.12, 0.13, 0.11); opacity: 0.8; show: op_vis and pw_open }}",
              f'{c}    text "{label}" {{ at: cp6_x - 186, {py} + 16; anchor: left center; size: 10; family: "Exo 2"; color: {col}; show: op_vis and pw_open }}',
              f"{c}    on press pwz{n} {{ emit sb_press({code}) }}"]
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
         '        run: "pleamar", "mooi", "hyprctl", "readlink", "nmcli", "bluetoothctl", "systemctl"',
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
    L = ["", "    // ── Surface (D209): the opening's ground and edge, and the Presences ──",
         '    shader aperture = file "shaders/aperture.wgsl"',
         '    shader tear = file "shaders/tear.wgsl"',
         '    shader ground = file "shaders/ground.wgsl"',
         "    fact rv_on = false", "    fact rv_stage = 0", "    fact sf_firm = false   // the opening is open and the pointer has moved: the keyboard is ours",
         "    fact sf_fx = 1         // the opening's look: 1 the Tear, 2 the Aperture",
         "    text rv_wall = \"\"", "    image rv_img = from rv_wall, 0, 0",
         "    event rv_down ->       // from `mooi reveal down`: Super went down",
         "    event rv_up ->         // from `mooi reveal up`: Super came up",
         "    event rv_esc ->        // Escape while revealing",
         "    event rv_move ->       // x * 10000 + y: the pointer while revealing",
         "    event rv_outside ->    // a press while revealing",
         "    event pp_press ->      // a Presence pressed (its slot)",
         "    event pp_rpress ->     // a Presence right-pressed: edit it",
         "    event pp_ctl ->        // slot * 10 + 1 previous · 2 play/pause · 3 next",
         "    event pp_drag ->       // slot * 100000000 + x * 10000 + y while dragged in edit",
         "    event pp_drop ->       // slot, let go after a drag",
         "    event ed_undo ->", "    event ed_redo ->", "    event ed_done ->"]
    for k in range(SLOTS):
        L += [f"    fact p{k}_on = false", f"    fact p{k}_x = 0", f"    fact p{k}_y = 0", f"    fact p{k}_w = 220", f"    fact p{k}_h = 28",
              f"    fact p{k}_mode = 0", f"    fact p{k}_prog = 0", f"    fact p{k}_edit = false",
              f"    fact p{k}_r = 0.84", f"    fact p{k}_g = 0.89", f"    fact p{k}_b = 0.54",
              f"    text p{k}_t1 = \"\"", f"    text p{k}_t2 = \"\"", f"    text p{k}_icon = \"♫\""]
    # the ground: just above the wallpaper, under the widgets and the windows
    L += ["", "    surface ground {", "        size: full, full", "        anchor: top", "        level: background", "        reserve: -1",
          "        keyboard: none", "        rate: 60, 20 while calm", "        open: op_vis",
          "        group {",
          "            clip box { from: op_x, op_y; size: op_w, op_h; corner: op_r }",
          "            // the subsurface's dark ground and its grid, fixed to the screen",
          "            shader ground { at: op_x, op_y; size: op_w, op_h; corner: op_r; values: op_k, op_x, op_y }"]
    L += below_group()
    L += ["        }",
          "    }"]
    # the edge: the torn wallpaper round the hole, above the widgets, under the windows; it catches nothing
    clip = f"clip box {{ from: op_x - {g}, op_y - {g}; size: op_w + {g * 2}, op_h + {g * 2}; corner: op_r + {g} }}"
    img = "image rv_img { at: 0, 0; size: edge.width, edge.height; fit: cover }"
    L += ["", "    surface edge {", "        size: full, full", "        anchor: top", "        level: bottom", "        reserve: -1",
          "        keyboard: exclusive while op_vis and sf_firm", "        rate: 60", "        open: op_vis",
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
          "        // the Tear: the real wallpaper, torn open over the hole (the surface's own size: screen.height is the",
          "        // scene's first surface's, the 40 px bar strip — found live, D208)",
          "        // a group's shader sees its own box: the clip's, from its top left corner (found live) — so each is told",
          "        // where that corner is on the screen (kept on it: the box does not reach past the surface)",
          f"        let ed_ox = max(0, op_x - {g})",
          f"        let ed_oy = max(0, op_y - {g})",
          "        group {",
          "            show: sf_fx < 1.5",
          f"            {clip}",
          "            shader: tear, op_k, op_x, op_y, op_w, op_h, op_r, ed_ox, ed_oy",
          f"            {img}",
          "        }",
          "        // the Aperture, the other look: a lens and a lit rim round the same clear hole",
          "        group {",
          "            show: sf_fx > 1.5",
          f"            {clip}",
          "            shader: aperture, op_k, op_x, op_y, op_w, op_h, op_r, ed_ox, ed_oy",
          f"            {img}",
          "        }",
          "    }"]
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
              f"{i2}on press pz{k} {{ emit pp_press({k}) }}",
              f"{i2}on press right pz{k} {{ emit pp_rpress({k}) }}",
              f"{i2}on drag pz{k} while p{k}_edit {{ emit pp_drag({k * 100000000} + round(pointer.x) * 10000 + round(pointer.y)) }}",
              f"{i2}on release pz{k} while p{k}_edit {{ emit pp_drop({k}) }}",
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
