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

_spec = importlib.util.spec_from_file_location("gen_opening", Path(__file__).resolve().parent / "gen-opening.py")
opening = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(opening)

N = 64
HOSTS = 4
OUT = Path(__file__).resolve().parent.parent / "shell" / "mooi-surface.plm"
# lib/surface/shapes.KINDS, 1-based in the scene's h{k}_kind
KINDS = ["clock", "wave", "disc", "ring", "card", "strip", "ribbon", "horizon", "spaces", "dots", "bars", "face"]
K = {k: i + 1 for i, k in enumerate(KINDS)}


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
         '        run: "pleamar", "mooi", "hyprctl", "readlink"',
         '        services: "files", "files.write", "env", "audio.level", "media", "audio", "audio.*", "media.*", "battery", "network", "bluetooth", "workspaces", "window", "clock"',
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
         "    fact rv_on = false", "    fact rv_stage = 0",
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
          "            shader ground { at: op_x, op_y; size: op_w, op_h; corner: op_r; values: op_k, op_x, op_y }",
          "            // below: what lives under the wallpaper (Task 6 fills this group)",
          "            group {",
          "                show: op_mode > 0",
          "            }",
          "        }",
          "    }"]
    # the edge: the torn wallpaper round the hole, above the widgets, under the windows; it catches nothing
    clip = f"clip box {{ from: op_x - {g}, op_y - {g}; size: op_w + {g * 2}, op_h + {g * 2}; corner: op_r + {g} }}"
    img = "image rv_img { at: 0, 0; size: edge.width, edge.height; fit: cover }"
    L += ["", "    surface edge {", "        size: full, full", "        anchor: top", "        level: bottom", "        reserve: -1",
          "        keyboard: none", "        rate: 60", "        open: op_vis",
          "        // where the pointer is, told to the logic as it moves (every 6 px), while revealing",
          "        let rv_q = round(cursor.x / 6) * 100000 + round(cursor.y / 6)",
          "        on change rv_q while rv_on or op_vis { emit rv_move(round(cursor.x) * 10000 + round(cursor.y)) }",
          "        on key Escape { emit rv_esc }",
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
