#!/usr/bin/env python3
"""Generate shell/mooi-surface.plm: the Sigil (D207) and the Subsurface (D209-D214) in one scene.

The Sigil: four hosts (0 the Pill, 1-3 islands), each one line of N = 64 points: the logic writes each point's
target (h{k}_tx{i}, h{k}_ty{i}) and the scene springs to it, adds the temperament's wobble, the music's ripple
and the pointer's push, and draws it as the Sigil body. Its surfaces: `bar` (every host's resting form and its
zone) and `drop` (the Pill's display).

The Subsurface (docs/superpowers/specs/2026-11-08-subsurface-design.md): `ground` (level background, mapped after
the wallpaper: the wallpaper cut open, the hubs and components below it, the Overview's canvas), `edge` (level
bottom, above the citizens: the effect's rim, the keyboard). What lives below is mooi-widgets' (D215).
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

# what the keyboard types into Launch's grid while the Overview is open (forwarded to mooi-widgets, D215)
TYPED = [chr(c) for c in range(ord("a"), ord("z") + 1)]


def below_decls():
    """D215: what lives below is the widgets (mooi-widgets); this scene keeps only what the opening needs to know
    of them — what it snaps to, BMO's and the widgets' reports, and where the light through the skin glows."""
    return ["", "    // ── the subsurface (D209, D215): the opening's own facts; the things below are mooi-widgets' ──",
            "    event op_type ->      // a letter typed in the Overview (its code; 8 rubs one out): sent on to Launch's grid",
            "    event lw_try ->       // D221: Live wallpaper's Try it (from mooi-settings): every effect that is on, now",
            "    event op_bx ->        // from BMO: where he stands, x * 4096 + y",
            "    event op_bs ->        // ... and how big he is, w * 4096 + h",
            "    event op_wbar ->      // from mooi-widgets: how far below the screen's top its surface starts",
            "    event op_wkey ->      // an edit key in the Overview, sent on to mooi-widgets as its own (wg_key)",
            "    event sb_drag ->      // from mooi-widgets: a widget is being dragged in the opening (-1)",
            "    event sb_drop ->      // ... and let go",
            "    fact sf_snap = 0      // what the opening hugs: BMO 20, a widget 30, none 0",
            "    // light through the skin: the centres of the Now Playing and Notices widgets, on the screen (far off: none)",
            "    fact au_mx = -9999", "    fact au_my = -9999", "    fact au_nx = -9999", "    fact au_ny = -9999"]


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
         '        services: "files", "files.write", "env", "audio.level", "media", "audio", "audio.*", "media.*", "battery", "network", "network.*", "bluetooth", "bluetooth.*", "brightness", "brightness.*", "apps", "apps.launch", "workspaces", "window", "clock", "capture", "thumbnails", "thumbnails.*"',
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


HOLE_GROW = 40     # the edge draws the torn wallpaper this far round the hole


def surface_layers():
    """D209: the opening drawn at the wallpaper — `ground` (level background: the hole's dark ground, later the
    hubs) and `edge` (level bottom, above the widgets: the torn rim and the warped wallpaper round it, no zones) —
    (D215: the Presences are widgets kept above now, mooi-widgets'). Nothing at level top or overlay: never over a window."""
    g = HOLE_GROW
    effects = ["tear", "aperture", "membrane", "ripple", "fold", "dissolve", "glass", "glow"]
    L = ["", "    // ── Surface (D209): the opening's ground and edge, and the Presences ──"]
    for e in effects:
        L += [f'    shader {e} = file "shaders/{e}.wgsl"']
    L += ['    shader ground = file "shaders/ground.wgsl"',
          '    shader aura = file "shaders/aura.wgsl"',
          '    shader bulge = file "shaders/bulge.wgsl"',
          '    shader skin = file "shaders/skin.wgsl"',
          '    shader music = file "shaders/music.wgsl"',
          "    fact rv_on = false", "    fact sf_firm = false   // the opening is open and the pointer has moved: the keyboard is ours",
          "    fact sf_fx = 1         // the opening's look: 1 tear · 2 aperture · 3 membrane · 4 ripple · 5 fold · 6 dissolve · 7 glass · 8 glow",
          "    fact sf_int = 0.85     // the effect's strength",
          "    fact sf_edge = 0.5     // the lip's width",
          "    fact sf_col = 0        // the rim's colour: 0 accent · 1 plain · 2 warm",
          "    fact sf_param = 85500  // intensity, edge and colour in one value for the shaders",
          "    fact sf_wall = true", "    fact sf_dim = 0.35", "    fact sf_tint = 0.18", "    fact sf_fit = 0",
          "    fact sf_grid = 0.45", "    fact sf_labels = true", "    fact sf_glow = 1", "    fact sf_ping = 0",
          "    fact sf_ovm = 16",
          "    text rv_wall = \"\"", "    image rv_img = from rv_wall, 0, 0",
          "    image sf_cover = from rv_wall, 0, 0", "    image sf_contain = from rv_wall, 0, 0",
         "    event rv_down ->       // from `mooi reveal down`: Super went down",
         "    event rv_up ->         // from `mooi reveal up`: Super came up",
         "    event rv_esc ->        // Escape while revealing",
         "    event rv_move ->       // x * 10000 + y: the pointer while revealing",
         ]
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
          "                shader: ground, op_k, op_x, op_y, sf_dim, sf_grid, sf_tint, op_w, op_h",
          "            }",
          "            // light through the skin: a soft glow at Music and the Notices while the opening is open",
          "            shader aura { at: op_x, op_y; size: op_w, op_h; values: op_k, op_x, op_y, au_mx, au_my, au_nx, au_ny, sf_glow + sf_ping * 1.5; colors: rgb(0.62, 0.84, 0.74), rgb(0.95, 0.62, 0.38); show: op_vis and sf_glow > 0.5 }",
          "            // the Overview: the wallpaper pulls back to a thin lit margin and the canvas takes the screen",
          "            box { from: op_x + sf_ovm, op_y + sf_ovm; size: max(0, op_w - 2 * sf_ovm), max(0, op_h - 2 * sf_ovm); corner: max(0, op_r - 6); color: rgb(0.035, 0.05, 0.055); opacity: 0.99; show: op_vis and op_mode == 4 and not sf_mu }",
          "            // its grid: three uprights and two crossbars, faint enough to arrange against without seeing lines",
          "            box { from: op_x + op_w * 0.25, op_y + sf_ovm; size: 1, max(0, op_h - 2 * sf_ovm); color: rgb(0.62, 0.84, 0.74); opacity: 0.03; show: op_vis and op_mode == 4 and not sf_mu }",
          "            box { from: op_x + op_w * 0.5, op_y + sf_ovm; size: 1, max(0, op_h - 2 * sf_ovm); color: rgb(0.62, 0.84, 0.74); opacity: 0.03; show: op_vis and op_mode == 4 and not sf_mu }",
          "            box { from: op_x + op_w * 0.75, op_y + sf_ovm; size: 1, max(0, op_h - 2 * sf_ovm); color: rgb(0.62, 0.84, 0.74); opacity: 0.03; show: op_vis and op_mode == 4 and not sf_mu }",
          "            box { from: op_x + sf_ovm, op_y + op_h * 0.33; size: max(0, op_w - 2 * sf_ovm), 1; color: rgb(0.62, 0.84, 0.74); opacity: 0.03; show: op_vis and op_mode == 4 and not sf_mu }",
          "            box { from: op_x + sf_ovm, op_y + op_h * 0.66; size: max(0, op_w - 2 * sf_ovm), 1; color: rgb(0.62, 0.84, 0.74); opacity: 0.03; show: op_vis and op_mode == 4 and not sf_mu }",
          "            text \"THE SUBSURFACE\" { at: op_x + sf_ovm + 24, op_y + op_h - sf_ovm - 44; anchor: left center; size: 11; weight: 700; family: \"Share Tech Mono\"; color: rgb(0.62, 0.84, 0.74); show: op_vis and op_mode == 4 }",
          "            text \"the widgets are in edit mode: drag, resize, undo  /  type to find an app  /  Esc to close\" { at: op_x + sf_ovm + 24, op_y + op_h - sf_ovm - 26; anchor: left center; size: 10; family: \"Share Tech Mono\"; color: rgb(0.55, 0.6, 0.58); show: op_mode == 4 and sf_labels > 0.5 }"]
    L += tiles_ground()
    L += music_overview()
    L += ["            // the Overview's close, over the canvas at its top right (undo is the widgets' own, in edit mode)",
          "            box { from: op_x + op_w - sf_ovm - 92, op_y + sf_ovm + 108; size: 80, 26; corner: 6; color: rgb(0.08, 0.1, 0.11); opacity: 0.72; show: op_vis and op_mode == 4 }",
          "            text \"CLOSE\" { at: op_x + op_w - sf_ovm - 52, op_y + sf_ovm + 108 + 13; anchor: center; align: center; size: 9; weight: 700; family: \"Share Tech Mono\"; color: rgb(0.62, 0.84, 0.74); show: op_vis and op_mode == 4 }",
          "            zone box ov_close { from: op_x + op_w - sf_ovm - 92, op_y + sf_ovm + 108; size: 80, 26; cursor: pointer; role: button; label: \"Close the Overview\"; show: op_live and op_mode == 4 }",
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
          "        // typing into Launch's grid while the Overview is open: letters, a space, a rub-out"]
    for ch in TYPED:
        L += [f"        on key {ch} while op_mode == 4 {{ emit op_type({ord(ch)}) }}"]
    # the widgets' edit keys (mooi-widgets.plm `wg_key`): the opening holds the keyboard in the Overview
    WKEYS = [("Left", 1), ("Right", 2), ("Up", 3), ("Down", 4), ("Shift+Left", 5), ("Shift+Right", 6), ("Shift+Up", 7),
             ("Shift+Down", 8), ("Delete", 9), ("Ctrl+d", 10), ("Ctrl+z", 11), ("Ctrl+Shift+z", 12), ("Ctrl+a", 13)]
    L += [f"        on key {k} while op_mode == 4 {{ emit op_wkey({c}) }}" for k, c in WKEYS]
    L += ["        on key space while op_mode == 4 { emit op_type(32) }",
          "        on key BackSpace while op_mode == 4 { emit op_type(8) }",
          "        // the eight looks: the real wallpaper, cut open over the hole (the surface's own size: screen.height",
          "        // is the scene's first surface's, the 40 px bar strip — found live, D208)",
          "        // a group's shader sees its own box: the clip's, from its top left corner — each derives the screen",
          "        // origin from op_x/op_y in its own file, so all eight values are free for shape and strength",
          "        // (the intensity, edge and colour arrive packed in sf_param: see the shaders)"]
    # D221: the lip — every effect gets a clear lit edge, so the hole reads as a hole and not a smudge
    L += ["        // the lip: a thin lit line round the hole, with a soft glow (every effect has it)",
          f"        group {{ glow: 18, 0.9 * op_k, {ACCENT}; show: op_vis and op_mode < 4",
          f"            box {{ from: op_x, op_y; size: op_w, op_h; corner: op_r; stroke: 2; color: {ACCENT}; opacity: 0.9 * op_k }} }}"]
    for i, e in enumerate(effects, start=1):
        L += ["        group {",
              f"            show: sf_fx > {i - 0.5} and sf_fx < {i + 0.5}",
              f"            {clip}",
              f"            shader: {e}, op_k, op_x, op_y, op_w, op_h, op_r, sf_param, 0",
              f"            {img}",
              "        }"]
    L += ["    }"]
    L += push_layers()
    L += peer_layer()
    return L


WARM = "rgb(0.95, 0.62, 0.38)"
ACCENT = "rgb(0.62, 0.84, 0.74)"


LIVE_FX = ["ripple", "breathe", "flow", "sweep"]


def live_groups(img):
    L = []
    for k in LIVE_FX:
        amt = "sk_swp" if k == "sweep" else "max(lv.level, lw_boost)"
        # the sweep fades by its strength: the packed number rebuilt with the strength times how seen it is
        packed = f"lw_{k}_p - lw_{k}_s * 10000 + round(lw_{k}_s * sk_swa) * 10000" if k == "sweep" else f"lw_{k}_p"
        L += ["        group {", f"            show: lw_{k}",
              f"            clip box {{ from: lw_{k}_x, lw_{k}_y; size: lw_{k}_w, lw_{k}_h; corner: if(lw_whole, 0, 48) }}",
              f"            shader: skin, lw_speed + min(0.999, {amt}), lw_{k}_x, lw_{k}_y, lw_{k}_bx, lw_{k}_by, lw_{k}_bw, lw_{k}_bh, {packed}",
              f"            {img}", "        }"]
    return L


B6 = "mb_v0, mb_v1, mb_v2, mb_v3, mb_v4, mb_v5"
TILES = 8


def phase4_decls():
    """D224 (the Subsurface's phase 4): the peek — the window behind, live, in a round patch of the one in front —
    and the buried windows' tiles under the wallpaper."""
    L = ["    // ── phase 4 (D224): peering and burying ──",
         "    fact pr_on = false     // a peek: Super held over a window with another behind it",
         "    fact pr_x = 0", "    fact pr_y = 0", "    fact pr_r = 110",
         "    fact pr_bx = 0", "    fact pr_by = 0", "    fact pr_bw = 1", "    fact pr_bh = 1",
         '    text pr_pic = ""', "    image pr_img = from pr_pic, 0, 0",
         "    prop pr_rs = 0 ~sg.op", "    follow pr_rs = if(pr_on, pr_r, 0)",
         "    event bury ->         // Super+Alt+B: the focused window under the wallpaper",
         "    event bt_go ->        // a buried window's tile pressed: it comes back"]
    for i in range(1, TILES + 1):
        L += [f"    fact bt{i} = false", f"    fact bt{i}x = 0", f"    fact bt{i}y = 0", f"    fact bt{i}w = 240", f"    fact bt{i}h = 150",
              f'    text bt{i}_pic = ""', f"    image bt{i}_img = from bt{i}_pic, 0, 0", f'    text bt{i}_name = ""']
    return L


def tiles_ground():
    """D224: the buried windows' tiles — their last picture, their app and title — under the wallpaper, seen in the
    opening; a press brings the window back."""
    L = ["            // D224: buried windows, each a tile where it was buried; a press brings it back"]
    for i in range(1, TILES + 1):
        x, y, w, h = f"bt{i}x", f"bt{i}y", f"bt{i}w", f"bt{i}h"
        L += [f"            group {{ show: op_vis and bt{i} and not sf_mu",
              f"                group {{ glow: 18, 0.5, #000000",
              f"                    box {{ from: {x}, {y}; size: {w}, {h}; corner: 10; color: rgb(0.05, 0.06, 0.07); opacity: 0.94 }} }}",
              f"                group {{ clip box {{ from: {x} + 6, {y} + 6; size: {w} - 12, {h} - 34; corner: 6 }}",
              f"                    image bt{i}_img {{ at: {x} + 6, {y} + 6; size: {w} - 12, {h} - 34; fit: cover }} }}",
              f"                text bt{i}_name {{ at: {x} + 10, {y} + {h} - 14; anchor: left center; size: 10; weight: 700; family: \"Share Tech Mono\"; color: rgb(0.86, 0.9, 0.88); width: {w} - 20; lines: 1 }}",
              f"                box {{ from: {x} + 0.5, {y} + 0.5; size: {w} - 1, {h} - 1; corner: 10; stroke: 1; color: {ACCENT}; opacity: 0.5 }}",
              f"                zone box bt_z{i} {{ from: {x}, {y}; size: {w}, {h}; corner: 10; cursor: pointer; role: button; label: \"Bring this window back\"; show: op_live and bt{i} }}",
              f"                on press bt_z{i} {{ emit bt_go({i}) }}",
              "            }"]
    return L


def peer_layer():
    """D224: the peek — over the windows (level overlay), catching nothing: the window behind, live and where it is,
    inside a round patch at the pointer, with the opening's lit lip. The wheel widens it."""
    return ["", "    surface peer {", "        size: full, full", "        anchor: top", "        level: overlay", "        reserve: -1",
            "        keyboard: none", "        rate: 60, 20 while calm", "        open: pr_on or pr_rs > 1",
            "        group {",
            "            clip box { from: pr_x - pr_rs, pr_y - pr_rs; size: pr_rs * 2, pr_rs * 2; corner: pr_rs }",
            "            box { from: pr_x - pr_rs, pr_y - pr_rs; size: pr_rs * 2, pr_rs * 2; color: rgb(0.03, 0.04, 0.035) }",
            "            image pr_img { at: pr_bx, pr_by; size: pr_bw, pr_bh }",
            "        }",
            f"        group {{ glow: 18, 0.9, {ACCENT}",
            f"            ellipse {{ at: pr_x, pr_y; radius: max(1, pr_rs); stroke: 2; color: {ACCENT}; opacity: 0.9 }} }}",
            "    }"]


def music_decls():
    """D223: Music in the picture — its bands (springs over the logic's targets, packed three to a number as
    lib/surface/music `pack`), its places, and the Overview's Music mode."""
    L = ["    // ── Music in the picture (D223): the bands, the places it grows from, the Overview's Music mode ──",
         "    fact lw_music = false", "    fact lw_music_p = 0", "    spring sg.mb = 520, 34"]
    for i in range(16):
        L += [f"    fact mb_t{i} = 0", f"    prop mb{i} = 0 ~sg.mb", f"    follow mb{i} = mb_t{i}"]
    for g in range(6):
        parts = [f"round(mb{g * 3 + j} * 255) * {m}" if g * 3 + j < 16 else "0" for j, m in ((0, "65536"), (1, "256"), (2, "1"))]
        expr = " + ".join(p.replace(" * 1", "") if p.endswith(" * 1") else p for p in parts)
        L += [f"    let mb_v{g} = {expr}"]
    L += ["    fact mu_e = false", "    fact mu_ex = 0", "    fact mu_ey = 0", "    fact mu_ew = 1", "    fact mu_eh = 1"]
    for i in range(1, 5):
        L += [f"    fact mu_a{i} = false", f"    fact mu_a{i}x = 0", f"    fact mu_a{i}y = 0", f"    fact mu_a{i}w = 1", f"    fact mu_a{i}h = 1"]
    for i in range(1, 3):
        L += [f"    fact mu_c{i} = false", f"    fact mu_c{i}v = 0", f"    fact mu_c{i}r = 0", f"    fact mu_c{i}g = 0", f"    fact mu_c{i}b = 0"]
    L += ["    fact mu_s = false", '    text mu_cutp = ""', "    image mu_cut = from mu_cutp, 0, 0",
          "    fact sf_mu = false     // the Overview's Music mode",
          "    fact mu_tool = 0       // 1 draw an area · 2 pick a colour · 3 drag the edge line",
          "    fact mu_px = 0", "    fact mu_py = 0", "    fact mu_qx = 0", "    fact mu_qy = 0", "    fact mu_dr = false",
          "    event mu_mode ->      // the Overview's Music mode: 1 in · 0 out",
          "    event mu_at ->        // an area drawn: its corner, x * 4096 + y",
          "    event mu_wh ->        // ... and its size, w * 4096 + h",
          "    event mu_pick ->      // a colour picked at x * 4096 + y",
          "    event mu_edge ->      // the edge line moved to this y",
          "    event mu_tog ->       // 1 the edge on/off · 2 the subject on/off",
          "    event mu_clear ->     // every area and colour let go"]
    return L


def music_groups(img):
    L = ["        // Music in the picture (D223): strips of the picture pulled up out of it by the music"]
    def bars(show, x, y, w, h):
        return ["        group {", f"            show: lw_music and {show}",
                f"            clip box {{ from: {x}, {y}; size: {w}, {h} }}",
                f"            shader: music, {B6}, lw_music_p, 0", f"            {img}", "        }"]
    L += bars("mu_e", "mu_ex", "mu_ey", "mu_ew", "mu_eh")
    for i in range(1, 5):
        L += bars(f"mu_a{i}", f"mu_a{i}x", f"mu_a{i}y", f"mu_a{i}w", f"mu_a{i}h")
    for i in range(1, 3):
        L += ["        group {", f"            show: lw_music and mu_c{i}",
              "            clip box { from: 0, 0; size: skin.width, skin.height }",
              f"            shader: music, {B6}, lw_music_p + 1000000, mu_c{i}v", f"            {img}", "        }"]
    L += ["        group {", "            show: lw_music and mu_s",
          "            clip box { from: 0, 0; size: skin.width, skin.height }",
          f"            shader: music, {B6}, lw_music_p + 2000000, 0",
          "            image mu_cut { at: 0, 0; size: skin.width, skin.height; fit: cover }", "        }"]
    return L


def music_overview():
    """D223: the Overview's Music mode — the whole picture, a toolbar, boxes drawn, colours picked, the edge dragged."""
    A = ACCENT
    tb = "op_y + sf_ovm + 64"
    tools = [("mu_t_edge", "EDGE", "mu_e", "emit mu_tog(1)"), ("mu_t_subject", "SUBJECT", "mu_s", "emit mu_tog(2)"),
             ("mu_t_area", "DRAW AREA", "mu_tool == 1", "mu_tool = 1"), ("mu_t_colour", "PICK COLOUR", "mu_tool == 2", "mu_tool = 2"),
             ("mu_t_line", "MOVE EDGE", "mu_tool == 3", "mu_tool = 3"), ("mu_t_clear", "CLEAR", "false", "emit mu_clear"),
             ("mu_t_done", "DONE", "false", "mu_tool = 0; emit mu_mode(0)")]
    L = ["            // D223: the Overview's Music mode — the whole picture at full light, and where the music grows from",
         f"            box {{ from: op_x + op_w - sf_ovm - 184, op_y + sf_ovm + 108; size: 80, 26; corner: 6; color: rgb(0.08, 0.1, 0.11); opacity: 0.72; show: op_vis and op_mode == 4 and not sf_mu }}",
         f"            text \"MUSIC\" {{ at: op_x + op_w - sf_ovm - 144, op_y + sf_ovm + 121; anchor: center; align: center; size: 9; weight: 700; family: \"Share Tech Mono\"; color: {A}; show: op_vis and op_mode == 4 and not sf_mu }}",
         "            zone box ov_music { from: op_x + op_w - sf_ovm - 184, op_y + sf_ovm + 108; size: 80, 26; cursor: pointer; role: button; label: \"Music in the picture: where it grows from\"; show: op_live and op_mode == 4 and not sf_mu }",
         "            on press ov_music { emit mu_mode(1) }",
         "            group {", "                show: op_vis and op_mode == 4 and sf_mu",
         "                clip box { from: op_x, op_y; size: op_w, op_h; corner: op_r }",
         "                image sf_cover { at: 0, 0; size: ground.width, ground.height; fit: cover }",
         "                // where it grows from: the edge line, the areas, the rubber band",
         f"                line {{ from: op_x, mu_ey + mu_eh; to: op_x + op_w, mu_ey + mu_eh; width: 2; color: {A}; opacity: if(mu_e, 0.9, 0.3) }}",
         f"                text \"EDGE\" {{ at: op_x + 24, mu_ey + mu_eh - 12; anchor: left center; size: 9; weight: 700; family: \"Share Tech Mono\"; color: {A}; opacity: if(mu_e, 1, 0.4) }}"]
    for i in range(1, 5):
        L += [f"                box {{ from: mu_a{i}x, mu_a{i}y; size: mu_a{i}w, mu_a{i}h; corner: 4; stroke: 1.5; color: {A}; opacity: 0.85; show: mu_a{i} }}"]
    L += [f"                box {{ from: min(mu_px, mu_qx), min(mu_py, mu_qy); size: abs(mu_qx - mu_px), abs(mu_qy - mu_py); corner: 4; stroke: 1.5; color: {WARM}; show: mu_dr }}",
          "                // the toolbar",
          f"                box {{ from: op_x + op_w / 2 - 430, {tb} - 6; size: 860, 40; corner: 8; color: rgb(0.05, 0.06, 0.07); opacity: 0.88 }}"]
    for n, (z, label, lit, act) in enumerate(tools):
        x = f"op_x + op_w / 2 - 422 + {n * 112}"
        L += [f"                box {{ from: {x}, {tb}; size: 106, 28; corner: 5; color: if({lit}, rgb(0.62, 0.84, 0.74), rgb(0.12, 0.14, 0.15)); opacity: 0.92 }}",
              f"                text \"{label}\" {{ at: {x} + 53, {tb} + 14; anchor: center; align: center; size: 9; weight: 700; family: \"Share Tech Mono\"; color: if({lit}, rgb(0.05, 0.06, 0.07), rgb(0.86, 0.9, 0.88)) }}",
              f"                zone box {z} {{ from: {x}, {tb}; size: 106, 28; cursor: pointer; role: button; label: \"{label.title()}\"; show: op_live }}",
              f"                on press {z} {{ {act} }}"]
    L += [f"                box {{ from: op_x + op_w / 2 + 364, {tb} + 6; size: 16, 16; corner: 3; color: rgb(mu_c1r, mu_c1g, mu_c1b); show: mu_c1 }}",
          f"                box {{ from: op_x + op_w / 2 + 384, {tb} + 6; size: 16, 16; corner: 3; color: rgb(mu_c2r, mu_c2g, mu_c2b); show: mu_c2 }}",
          f"                text \"DRAG A BOX · CLICK A COLOUR IN THE PICTURE · DRAG THE EDGE LINE\" {{ at: op_x + op_w / 2, {tb} + 48; anchor: center; align: center; size: 9; family: \"Share Tech Mono\"; color: rgb(0.86, 0.9, 0.88) }}",
          "                // the picture itself: draw, pick, drag",
          f"                zone box mu_z {{ from: op_x, {tb} + 60; size: op_w, op_h - (sf_ovm + 124); cursor: crosshair; role: button; label: \"The picture\"; show: op_live and mu_tool > 0 }}",
          "                on press mu_z while mu_tool == 1 { mu_px = pointer.x; mu_py = pointer.y; mu_qx = pointer.x; mu_qy = pointer.y; mu_dr = true }",
          "                on drag mu_z while mu_tool == 1 { mu_qx = pointer.x; mu_qy = pointer.y }",
          "                on release mu_z while mu_tool == 1 {",
          "                    mu_dr = false",
          "                    emit mu_at(round(min(mu_px, mu_qx)) * 4096 + round(min(mu_py, mu_qy)))",
          "                    emit mu_wh(round(abs(mu_qx - mu_px)) * 4096 + round(abs(mu_qy - mu_py)))",
          "                }",
          "                on press mu_z while mu_tool == 2 { emit mu_pick(round(pointer.x) * 4096 + round(pointer.y)) }",
          "                on press mu_z while mu_tool == 3 { emit mu_edge(round(pointer.y)) }",
          "                on drag mu_z while mu_tool == 3 { emit mu_edge(round(pointer.y)) }",
          "            }"]
    return L


def push_layers():
    """D217, push up from below (the Subsurface spec §9, §9a): `skin` (level bottom: over the wallpaper, under the
    windows; patches round the widgets below — their glow, a visualiser moving the picture, the clock's sweep at
    the hour, a bulge with news and its words) and `light` (level overlay: a notice's spark, its line to the app's
    window and once round its border; one zone, the spark's, so every other click passes through). The logic is
    lib/surface/light's; both are shut while the opening shows the real things."""
    img = "image rv_img { at: 0, 0; size: skin.width, skin.height; fit: cover }"
    L = ["", "    // ── push up from below (D217): what lives below reaches up through the picture ──"]
    L += ["    fact sk_on = false     // the rest: anything glowing, moving or sweeping",
          "    fact sk_g = 1          // the glow: 0 off · 1 subtle · 2 bright",
          "    fact sk_mx = -9999", "    fact sk_my = -9999", "    fact sk_mp = false   // Now Playing, playing",
          "    fact sk_nx = -9999", "    fact sk_ny = -9999", "    fact sk_nn = false   // Notices, holding news",
          "    // Live wallpaper (D219): each effect's patch (or the screen), its widget's box, its packed numbers",
          "    fact lw_on = false", "    fact lw_whole = false", "    fact lw_speed = 100", "    fact lw_boost = 0",
          ] + music_decls() + phase4_decls() + [
          ] + [f"    fact lw_{k}{f} = {v}" for k in LIVE_FX for f, v in (("", "false"), ("_x", "-9999"), ("_y", "-9999"), ("_w", "1"), ("_h", "1"),
                                                                    ("_bx", "-9999"), ("_by", "-9999"), ("_bw", "1"), ("_bh", "1"), ("_p", "0"), ("_s", "0"))] + [
          "    fact sk_swt = 0      // the hour's sweep: where its band is going (0 … 1)",
          "    fact sk_swv = 0      // ... and how seen it is",
          "    spring sg.slow = 14, 7.5",
          "    prop sk_swp = 0 ~sg.slow", "    follow sk_swp = sk_swt",
          "    prop sk_swa = 0 ~sg.op", "    follow sk_swa = sk_swv",
          "    fact pu_on = false     // the push: a bulge and its words",
          "    fact pu_x = 0", "    fact pu_y = 0", "    fact pu_w = 1", "    fact pu_h = 1",
          "    fact pu_bt = 0", "    fact pu_wt = 0", "    fact pu_plate = false   // high contrast: a plate under the words",
          '    text pu_words = ""',
          "    spring sg.bulge = 180, 16",
          "    prop pu_b = 0 ~sg.bulge", "    follow pu_b = pu_bt",
          "    prop pu_wd = 0 ~sg.op", "    follow pu_wd = pu_wt",
          "    fact lt_on = false     // the light: a notice's spark, its line, the window's border",
          "    fact lt_sx = 0", "    fact lt_sy = 0", "    fact lt_tx = 0", "    fact lt_ty = 0",
          "    fact lt_rx = 0", "    fact lt_ry = 0", "    fact lt_rw = 1", "    fact lt_rh = 1",
          "    fact lt_win = false   // a window to travel to",
          "    fact lt_so = 0        // the side the line meets: 0 top · 1 right · 2 bottom · 3 left (the trace starts there)",
          "    fact lt_n = 1         // a burst: how many",
          "    fact lt_st = 0", "    fact lt_tt = 0", "    fact lt_bt = 0", "    fact lt_kt = 0",
          "    event lt_go ->        // the spark pressed",
          "    spring sg.lt = 70, 16", "    spring sg.ltb = 26, 10",
          "    prop lt_s = 0 ~sg.op", "    follow lt_s = lt_st",
          "    prop lt_t = 0 ~sg.lt", "    follow lt_t = lt_tt",
          "    prop lt_b = 0 ~sg.ltb", "    follow lt_b = lt_bt",
          "    prop lt_k = 0 ~sg.op", "    follow lt_k = lt_kt"]
    L += ["", "    surface skin {", "        size: full, full", "        anchor: top", "        level: bottom", "        reserve: -1",
          "        keyboard: none", "        rate: 30, 20 while calm",
          "        open: not op_vis and (lw_on or (sf_on and (sk_on or pu_on)))",
          "        // the glow through: a soft breath at Now Playing while it plays, at Notices while it holds news",
          f"        shader aura {{ at: sk_mx - 220, sk_my - 220; size: 440, 440; values: 1, sk_mx - 220, sk_my - 220, sk_mx, sk_my, -9999, -9999, sk_g * (0.75 + 0.5 * lv.level); colors: {ACCENT}, {WARM}; show: sk_mp }}",
          f"        shader aura {{ at: sk_nx - 220, sk_ny - 220; size: 440, 440; values: 1, sk_nx - 220, sk_ny - 220, -9999, -9999, sk_nx, sk_ny, sk_g; colors: {ACCENT}, {WARM}; show: sk_nn }}",
          "        // Live wallpaper (D219): one pass per effect over its patch (or the screen) — ripple, breathe, flow, sweep;",
          "        // the first number carries the speed (whole) and the music's level (or the sweep's place)"] + live_groups(img) + music_groups(img) + [
          "        // news: the picture bulges over the widget's place ...",
          "        group {", "            show: pu_on and pu_b > 0.005",
          "            clip box { from: pu_x - 48, pu_y - 48; size: pu_w + 96, pu_h + 96; corner: 48 }",
          "            shader: bulge, pu_b, pu_x - 48, pu_y - 48, pu_x, pu_y, pu_w, pu_h, 1",
          f"            {img}", "        }",
          "        // ... and its words press up through it, then settle back",
          "        group {", "            show: pu_on and pu_wd > 0.01", "            opacity: pu_wd",
          "            box { from: pu_x + pu_w / 2 - min(pu_w, 420) / 2, pu_y + pu_h / 2 - 18; size: min(pu_w, 420), 36; corner: 8; color: rgb(0.05, 0.06, 0.06); opacity: 0.86; show: pu_plate }",
          "            group { glow: 16, 0.7, #000000",
          "                text pu_words { at: pu_x + pu_w / 2, pu_y + pu_h / 2 + 8 * (1 - pu_wd); anchor: center; align: center; size: 16; weight: 600; family: \"Exo 2\"; color: rgb(0.95, 0.96, 0.95); width: min(pu_w, 420) - 16; lines: 1 } }",
          "        }", "    }"]
    # the light: the border, side by side from the side the line meets
    sides = [("lt_rx", "lt_ry", "lt_rx + lt_rw * {p}", "lt_ry"),
             ("lt_rx + lt_rw", "lt_ry", "lt_rx + lt_rw", "lt_ry + lt_rh * {p}"),
             ("lt_rx + lt_rw", "lt_ry + lt_rh", "lt_rx + lt_rw - lt_rw * {p}", "lt_ry + lt_rh"),
             ("lt_rx", "lt_ry + lt_rh", "lt_rx", "lt_ry + lt_rh - lt_rh * {p}")]
    L += ["", "    surface light {", "        size: full, full", "        anchor: top", "        level: overlay", "        reserve: -1",
          "        keyboard: none", "        rate: 60, 20 while calm", "        open: lt_on",
          "        // the line: a short comet from the spark to where it meets the window",
          "        let lt_a = max(0, lt_t - 0.3)",
          f"        group {{ glow: 10, 0.9, {WARM}; opacity: lt_k; show: lt_win and lt_t > 0.01",
          f"            line {{ from: lt_sx + (lt_tx - lt_sx) * lt_a, lt_sy + (lt_ty - lt_sy) * lt_a; to: lt_sx + (lt_tx - lt_sx) * lt_t, lt_sy + (lt_ty - lt_sy) * lt_t; width: 2; color: {WARM} }} }}",
          "        // once round the window's border, from the side the line met"]
    for i in range(4):
        L += [f"        let lt_p{i} = clamp(lt_b * 4 - mod({i} - lt_so + 4, 4), 0, 1)"]
    L += [f"        group {{ glow: 12, 0.8, {WARM}; opacity: lt_k; show: lt_win and lt_b > 0.001"]
    for i, (x0, y0, x1, y1) in enumerate(sides):
        p = f"lt_p{i}"
        L += [f"            line {{ from: {x0}, {y0}; to: {x1.format(p=p)}, {y1.format(p=p)}; width: 2; color: {WARM}; show: {p} > 0.001 }}"]
    L += ["        }",
          "        // the spark, and how many came at once",
          f"        group {{ glow: 14, 0.9 * lt_s, {WARM}",
          f"            ellipse {{ at: lt_sx, lt_sy; radius: 3 + 3 * lt_s; color: {WARM}; opacity: lt_s }} }}",
          "        text \"{lt_n}\" { at: lt_sx + 12, lt_sy - 10; anchor: left center; size: 10; weight: 700; family: \"Share Tech Mono\"; color: rgb(0.95, 0.62, 0.38); opacity: lt_s; show: lt_n > 1.5 }",
          "        zone box lt_z { from: lt_sx - 14, lt_sy - 14; size: 28, 28; cursor: pointer; role: button; label: \"Open the notices\"; show: lt_s > 0.2 }",
          "        on press lt_z { emit lt_go }",
          "    }"]
    return L


if __name__ == "__main__":
    OUT.write_text(scene())
