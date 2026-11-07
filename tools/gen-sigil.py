#!/usr/bin/env python3
"""Generate shell/mooi-sigil.plm: the Sigil's scene (D207, docs/superpowers/specs/2026-11-07-sigil-design.md).

Four hosts (0 the Pill, 1-3 islands), each one line of N = 64 points: the logic writes each point's target
(h{k}_tx{i}, h{k}_ty{i}) and the scene springs to it, adds the temperament's wobble, the music's ripple and
the pointer's push, and draws it as the Sigil body (three stroke passes and a pen head). Two surfaces: `bar`
(the bar's height, always open; every host's resting form and its zone) and `drop` (open only while the Pill
shows a display: the line, the display's insides, the field). Run: python3 tools/gen-sigil.py
"""
from pathlib import Path

N = 64
HOSTS = 4
OUT = Path(__file__).resolve().parent.parent / "shell" / "mooi-sigil.plm"
# lib/sigil/shapes.KINDS, 1-based in the scene's h{k}_kind
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
         "// The Sigil (D207): one living line in place of the Pill — GENERATED by tools/gen-sigil.py; do not edit.",
         "// The logic (shell/mooi-sigil.luau) decides what each host shows and writes its points' targets;",
         "// this scene springs them, makes them live (wobble, ripple, the pointer) and draws the Sigil body.",
         "",
         "scene Sigil {",
         "    permissions {",
         '        run: "pleamar", "mooi", "hyprctl"',
         '        services: "files", "env", "audio.level", "media", "audio", "audio.*", "battery", "network", "bluetooth", "workspaces", "window", "clock"',
         "    }",
         "    service audio.level as lv { level: number }",
         "    spring sg.pt = 260, 20",
         "    spring sg.drop = 300, 30",
         "    prop ph = 0",
         "    spin ph by if(wob > 0 or h0_rip > 0 or h1_rip > 0, 220, 0)",
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
    L += ["", "    surface bar {", "        size: full, 40", "        anchor: top", "        level: top", "        reserve: -1",
          "        keyboard: none", "        rate: 60, 20 while calm"]
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
          "        }", "    }", "}", ""]
    return "\n".join(L)


if __name__ == "__main__":
    OUT.write_text(scene())
