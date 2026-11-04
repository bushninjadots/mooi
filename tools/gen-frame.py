#!/usr/bin/env python3
"""Generates the pieces of mooi's scenes that pleamar cannot repeat itself: a `body` holds shapes,
not `repeat`s. Run it after changing it; it rewrites the text between `// <gen:NAME>` and
`// </gen:NAME>` in the scene each block belongs to.

  tools/gen-frame.py

- shell/mooi.plm, `slices`: the helix's pinched middle.
- shell/mooi-frame.plm, `frame`: the screen frame (D128): one silhouette — the band's four moving
  edges, its four corners and the bar's pieces — drawn by four surfaces that do not overlap (the top
  and the foot the full width, the sides between them), so each repaints only its own pixels while
  the music moves it, and cut into tiles that meet exactly (below).
"""
import re, pathlib

ROOT = pathlib.Path(__file__).resolve().parent.parent
HELIX = ROOT / "shell" / "mooi.plm"
FRAME = ROOT / "shell" / "mooi-frame.plm"

# ── The helix (shell/mooi.plm) ──

def slices(indent, color):
    """The helix's pinched middle: 13 slices of 18 px between the two twisting edges."""
    out = []
    for k in range(13):
        sx = f"(hx_a + {k * 18})"
        w = f"smooth(0, 1, clamp(({sx} + 2 - hx_a) / 14, 0, 1) * clamp((hx_b - {sx} - 2) / 14, 0, 1))"
        p = f"(90 - ({sx} + 2 - chain_x) / fl.pitch * fl.dna_twist + spin)"
        st = f"mix(pt, fl.cy - amp * sin({p}), {w})"
        sb = f"mix(pb, fl.cy + amp * sin({p}), {w})"
        out.append(f"{indent}box {{ color: {color}; from: {sx}, min({st}, {sb}); size: 6.4, max(0.5, abs({sb} - {st})); show: helix_edges and {sx} < hx_b }}")
    return "\n".join(out)

# ── The frame (shell/mooi-frame.plm) ──
#
# Why tiles: pleamar draws a `body` as one quad over its bounding box, and every pixel of it measures
# its distance to every segment of every shape in the body (twice with a shadow). One body for the whole
# frame made each pixel of the band pay for every segment of the frame (~46 % of the GPU with music,
# against ~10 % tiled and in straight steps). So each strip is cut into tiles, each a body clipped to
# its own stretch (the clip bounds the quad) that holds only the shapes within reach of it. Edges are cut
# into pieces of the same chain of samples, so the pieces on both sides of a cut are the same segments
# and the tiles meet exactly; what lies past a piece's cut ends is farther away than a shadow reaches.

TOP = 160       # the top strip: the bar's tallest row (offset 40 + rail 15 + height 44), its fillet and shadow
BOT = 128       # the foot strip, and the sides' width: the widest band (16) pushed in by the most reach (64)
SIDE = 128
NS = 48         # samples down each side (one every 22.5 px on a 1080 px screen)
NF = 64         # samples along the top and the foot (one every 30 px on a 1920 px screen)
G = 6           # chain pieces to a tile (~135 px down a side, ~180 px along the top)
REF_W, REF_H = 1920, 1080   # the screen the reach of a tile is worked out on; it scales with the screen
MARGIN = 64     # how far past its tile a shape still counts (shadow ≤ ~26 px, fillet 12 px; to spare)
CORNER = 300    # how far from its screen corner a corner's round, its shadow and a piece in it can reach

def side_wave(y):
    """How far the sides' inner edge is pushed in at height y (iNiR: sin(y·0.011 + t), sin(y·0.027 − 1.4t);
    pleamar's sin takes degrees)."""
    return f"wl * (0.6 + 0.24 * sin(({y}) * 0.630254 + wa) + 0.16 * sin(({y}) * 1.546986 - wb))"

def end_wave(x):
    """How far the top's and the foot's inner edge is pushed in at x (sin(x·0.009 − t), sin(x·0.023 + 1.2t))."""
    return f"wt * (0.6 + 0.24 * sin(({x}) * 0.515662 - wa) + 0.16 * sin(({x}) * 1.317803 + wc))"

def num(v):
    return f"{v:.6f}".rstrip("0").rstrip(".") or "0"

def wave_lets(ind):
    out = [f"{ind}// the moving edges, sampled: sw down the sides (left and right alike), fw along the top and foot"]
    out += [f"{ind}let sw{k} = {side_wave(f'H * {num(k / NS)}')}" for k in range(NS + 1)]
    out += [f"{ind}let fw{k} = {end_wave(f'W * {num(k / NF)}')}" for k in range(NF + 1)]
    out += [
        f"{ind}// where each corner's round starts on the top (or foot) and on the side: in two steps, as the",
        f"{ind}// moving side shifts where the top's edge is met; a corner a piece of the bar sits in turns at its foot",
        f"{ind}let yTL0 = if(covL, foot, bt + {end_wave('bs + frr')})",
        f"{ind}let xTL = bs + {side_wave('yTL0 + frr')}",
        f"{ind}let yTL = if(covL, foot, bt + {end_wave('xTL + frr')})",
        f"{ind}let yTR0 = if(covR, foot, bt + {end_wave('W - bs - frr')})",
        f"{ind}let xTR = W - bs - {side_wave('yTR0 + frr')}",
        f"{ind}let yTR = if(covR, foot, bt + {end_wave('xTR - frr')})",
        f"{ind}let yBL0 = H - bb - {end_wave('bs + frr')}",
        f"{ind}let xBL = bs + {side_wave('yBL0 - frr')}",
        f"{ind}let yBL = H - bb - {end_wave('xBL + frr')}",
        f"{ind}let yBR0 = H - bb - {end_wave('W - bs - frr')}",
        f"{ind}let xBR = W - bs - {side_wave('yBR0 - frr')}",
        f"{ind}let yBR = H - bb - {end_wave('xBR - frr')}",
    ]
    return out

# ── The edges as chains of pieces ──
# An edge is its samples joined by straight steps. They are close enough that the line stays within a
# tenth of a pixel of the wave (its shortest swing is ~230 px long), so it reads as a smooth curve; a
# `curve` would be flattened by pleamar into length/4 segments, and every one of them is measured by
# every pixel of the tile. Each piece knows the stretch of the edge, as a fraction of the screen along
# it, that it covers.

class Edge:
    def __init__(self, n, wave, point, out):
        self.n, self.wave, self.point, self.out = n, wave, point, out   # out(point) → the same, past the band

    def at(self, k):
        return self.point(f"{self.wave}{k}", f"{num(k / self.n)}")

    def pieces(self):
        """(from, to, start point, step) for each piece of the chain."""
        return [(k / self.n, (k + 1) / self.n, self.at(k), f"line {self.at(k + 1)}") for k in range(self.n)]

    def path(self, ind, lo, hi):
        """The band behind the stretch of edge from lo to hi (fractions): a closed path whose inner side is
        the moving edge; None when no piece falls there."""
        ps = [p for p in self.pieces() if p[1] > lo and p[0] < hi]
        if not ps:
            return []
        start, end = ps[0][2], self.end_of(ps[-1])
        steps = [f"move {self.out(start)}", f"line {start}"] + [p[3] for p in ps] + [f"line {self.out(end)}", "close"]
        pad = ind + "       "
        return [f"{ind}path {{ {steps[0]}"] + [pad + s for s in steps[1:-1]] + [f"{pad}{steps[-1]} }}"]

    def end_of(self, piece):
        return piece[3].split(" ", 1)[1]

def xy(p):
    x, y = p.rsplit(", ", 1)
    return x, y

EDGES = {
    "left": Edge(NS, "sw", lambda w, f: f"bs + {w}, H * {f}", lambda p: f"-40, {xy(p)[1]}"),
    "right": Edge(NS, "sw", lambda w, f: f"W - bs - {w}, H * {f}", lambda p: f"W + 40, {xy(p)[1]}"),
    "top": Edge(NF, "fw", lambda w, f: f"W * {f}, bt + {w}", lambda p: f"{xy(p)[0]}, -40"),
    "foot": Edge(NF, "fw", lambda w, f: f"W * {f}, H - bb - {w}", lambda p: f"{xy(p)[0]}, H + 40"),
}

CORNERS = {
    "tl": "path { move -40, -40; line xTL + frr, -40; line xTL + frr, yTL; curve xTL, yTL + frr via xTL, yTL; line -40, yTL + frr; close }",
    "tr": "path { move W + 40, -40; line xTR - frr, -40; line xTR - frr, yTR; curve xTR, yTR + frr via xTR, yTR; line W + 40, yTR + frr; close }",
    "bl": "path { move -40, H + 40; line xBL + frr, H + 40; line xBL + frr, yBL; curve xBL, yBL - frr via xBL, yBL; line -40, yBL - frr; close }",
    "br": "path { move W + 40, H + 40; line xBR - frr, H + 40; line xBR - frr, yBR; curve xBR, yBR - frr via xBR, yBR; line W + 40, yBR - frr; close }",
}

# Without the band (D153) the pieces float where the bar's own plates would: from its offset, not the top.
PY = "if(band_on, -40, st_offset)"
PH = "if(band_on, 40 + {b}, {b} - st_offset)"
PIECES = [(f"ix{i} - 3", f"ix{i} + iw{i} + 3",
           f"box {{ from: ix{i} - 3, {PY}; size: iw{i} + 6, {PH.format(b='row_b')}; corner: fl.radius; blend: kf; show: bar_mode == 0 and iw{i} > 1", "}")
          for i in range(16)] + [
    ("plx - n_pad", "plx + plw + n_pad", f"box {{ from: plx - n_pad, {PY}; size: plw + 2 * n_pad, {PH.format(b='n_b')}; corner: n_r; blend: kf; show: bar_mode == 2 and plw > 1", "}"),
    ("pcx - n_pad", "pcx + pcw + n_pad", f"box {{ from: pcx - n_pad, {PY}; size: pcw + 2 * n_pad, {PH.format(b='n_b')}; corner: n_r; blend: kf; show: bar_mode == 2 and pcw > 1", "}"),
    ("prx - n_pad", "prx + prw + n_pad", f"box {{ from: prx - n_pad, {PY}; size: prw + 2 * n_pad, {PH.format(b='n_b')}; corner: n_r; blend: kf; show: bar_mode == 2 and prw > 1", "}"),
    ("gp_x", "gp_x + gp_w", f"box {{ from: gp_x, {PY}; size: gp_w, {PH.format(b='row_b')}; corner: fl.radius; blend: kf; show: bar_mode == 1 and gp_w > 1", "}"),
]

BODY = [
    "color: fcol",
    "opacity: fop",
    "glass: if(glassy, 100%, 0%)",
    "lens: false",
    "frost: 1% * st_frost",
    "smoke: 1% * st_smoke",
    "shadow: 0, st_sh_y, st_sh_blur, 100% * st_sh_a",
    "border: if(st_frame_edge < 1.5, st_owidth, 0), fnec",
]

def tile(ind, clip, shapes, show=None):
    i2, i3 = ind + "    ", ind + "        "
    # the band's shapes (its edges and corners are the tiles' paths) only while it is on (D153)
    shapes = [[l.replace("path { ", "path { show: band_on; ", 1) for l in sh] for sh in shapes]
    head = [f"{ind}group {{"] + ([f"{i2}show: {show}"] if show else [])
    return (head + [f"{i2}clip box {{ {clip} }}", f"{i2}body {{"] + [i3 + b for b in BODY]
            + [l if l.startswith(i3) else i3 + l for s in shapes for l in s] + [f"{i2}}}", f"{ind}}}"])

def chunks(edge, lo_px, hi_px, ref):
    """The edge's pieces in runs of G, keeping those whose stretch reaches between lo_px and hi_px."""
    ps = edge.pieces()
    for a in range(0, len(ps), G):
        run = ps[a:a + G]
        lo, hi = run[0][0], run[-1][1]
        if hi * ref > lo_px and lo * ref < hi_px:
            yield a == 0, a + G >= len(ps), lo, hi

# The place (D152): an island grown out of the bar's piece. While it is out, the top strip's tiles it
# crosses are drawn by `frame_p` (on the top layer, over the windows, under the bar's content) with the
# island's box in each body, so it melts into the piece and the band; `frame_t` leaves those tiles out.
# Two places (D152): an island under the bar (`pl`, the top strip's) and the Control Nexus's deck (`dk`),
# each grown out of an edge (the side notch's panels stay its own: D153). A tile a place crosses is drawn by `frame_p`
# with every place's box in its body; the screen is cut into tiles that do not overlap, so each pixel of a
# place is drawn once (only the top strip's tiles reach down past their strip, for an island).
PLACES = ["pl", "dk"]
def place_box(p):
    return f"box {{ from: {p}_bx, {p}_by; size: max(1, {p}_bw), max(1, {p}_bh); corner: {p}_br; blend: 30; show: {p}_act }}"
def crossed(which, a, b):
    """Is the tile crossed by a place? `a`, `b`: its stretch along its strip (x for the top and the foot,
    y for the sides)."""
    conds = []
    for p in PLACES:
        if which == "top":
            c = f"{p}_l < {b} and {p}_e > {a} and {p}_t < {TOP} + 40"
        elif which == "foot":
            c = f"{p}_l < {b} and {p}_e > {a} and {p}_b > H - {BOT}"
        elif which == "left":
            c = f"{p}_l < W / 2 and {p}_t < {b} and {p}_b > {a}"
        else:
            c = f"{p}_e > W / 2 and {p}_t < {b} and {p}_b > {a}"
        conds.append(f"({p}_act and {c})")
    return " or ".join(conds)

def end_tiles(ind, which, place=False):
    """The top's or the foot's tiles, along the full width (`place`: the copies frame_p draws)."""
    edge, m = EDGES[which], MARGIN / REF_W
    top = which == "top"
    y0, y1 = ("-40", f"{TOP} + 40") if top else (f"H - {BOT}", f"{BOT} + 40")
    out = []
    for first, last, lo, hi in chunks(edge, -1, REF_W + 1, REF_W):
        x0 = "-40" if first else f"W * {num(lo)}"
        x1 = "W + 40" if last else f"W * {num(hi)}"
        shapes = [edge.path("", lo - m, hi + m)]
        near_l, near_r = lo * REF_W < CORNER, hi * REF_W > REF_W - CORNER
        reach = (TOP if top else BOT) + MARGIN
        if near_l:
            shapes.append(EDGES["left"].path("", -1, reach / REF_H) if top else EDGES["left"].path("", 1 - reach / REF_H, 2))
            shapes.append([CORNERS["tl" if top else "bl"]])
        if near_r:
            shapes.append(EDGES["right"].path("", -1, reach / REF_H) if top else EDGES["right"].path("", 1 - reach / REF_H, 2))
            shapes.append([CORNERS["tr" if top else "br"]])
        if top:
            shapes += [[f"{box} and {a} < {x1} + 48 and {b} > {x0} - 48 {end}"] for a, b, box, end in PIECES]
        cr = crossed(which, x0, x1)
        if place:
            shapes += [[place_box(p)] for p in (PLACES if top else PLACES[1:])]
            h = f"max({y1}, if(pl_act, pl_y + pl_h + 80, 0))" if top else y1
            out += tile(ind, f"from: {x0}, {y0}; size: ({x1}) - ({x0}), {h}", shapes, cr)
        else:
            out += tile(ind, f"from: {x0}, {y0}; size: ({x1}) - ({x0}), {y1}", shapes, f"not ({cr})")
    return out

def side_tiles(ind, which, place=False):
    """A side's tiles, between the top strip and the foot strip (`place`: the copies frame_p draws)."""
    edge, m = EDGES[which], MARGIN / REF_H
    left = which == "left"
    out = []
    for _, _, lo, hi in chunks(edge, TOP, REF_H - BOT, REF_H):
        y0 = f"max({TOP}, H * {num(lo)})"
        y1 = f"min(H - {BOT}, H * {num(hi)})"
        x0, w = ("-40", "W / 2 + 40") if left else ("W / 2", "W / 2 + 40")
        shapes = [edge.path("", lo - m, hi + m)]
        if lo * REF_H < CORNER:
            shapes.append([CORNERS["tl" if left else "tr"]])
        if hi * REF_H > REF_H - CORNER:
            shapes.append([CORNERS["bl" if left else "br"]])
        cr = crossed(which, y0, y1)
        if place:
            shapes += [[place_box(p)] for p in PLACES[1:]]
            out += tile(ind, f"from: {x0}, {y0}; size: {w}, max(0, {y1} - {y0})", shapes, cr)
        else:
            out += tile(ind, f"from: {x0}, {y0}; size: {w}, max(0, {y1} - {y0})", shapes, f"not ({cr})")
    return out

LIGHTS = {   # the edges again, 1.5 px back into the band
    "left": Edge(NS, "sw", lambda w, f: f"bs - 1.5 + {w}, H * {f}", None),
    "right": Edge(NS, "sw", lambda w, f: f"W - bs + 1.5 - {w}, H * {f}", None),
    "foot": Edge(NF, "fw", lambda w, f: f"W * {f}, H - bb + 1.5 - {w}", None),
}

def light(ind, which):
    """The etched light, 1.5 px inside the moving edge, along the straight run between two corners."""
    edge = LIGHTS[which]
    # its glow reaches 5 px past the clip, so the run stops 8 px short of each corner's round
    clip = {"left": "from: -40, yTL + frr + 8; size: W + 80, max(0, yBL - yTL - 2 * frr - 16)",
            "right": "from: -40, yTR + frr + 8; size: W + 80, max(0, yBR - yTR - 2 * frr - 16)",
            "foot": "from: xBL + frr + 8, -40; size: max(0, xBR - xBL - 2 * frr - 16), H + 80"}[which]
    pieces = edge.pieces()
    path = [f"move {pieces[0][2]}"] + [p[3] for p in pieces]
    pad = ind + "           "
    return ([f"{ind}group {{",
             f"{ind}    show: band_on and {'wt' if which == 'foot' else 'wl'} > 0.5",
             f"{ind}    opacity: 0.35 * clamp(flev * 2, 0, 1)",
             f"{ind}    glow: 5, 0.6 * st_glow, fg.primary",
             f"{ind}    clip box {{ {clip} }}",
             f"{ind}    path {{ stroke: 1.4; color: fg.primary"]
            + [pad + s for s in path[:-1]] + [f"{pad}{path[-1]} }}", f"{ind}}}"])

STRIPS = [
    # name, size, anchor, margin, move, tiles, lights
    ("frame_t", f"full, {TOP}", "top", None, None, lambda i: end_tiles(i, "top"), ["left", "right"]),
    ("frame_b", f"full, {BOT}", "bottom", None, f"0, {BOT} - H", lambda i: end_tiles(i, "foot"), ["left", "right", "foot"]),
    ("frame_l", f"{SIDE}, full", "left", f"{TOP}, 0, {BOT}, 0", f"0, -{TOP}", lambda i: side_tiles(i, "left"), ["left"]),
    ("frame_r", f"{SIDE}, full", "right", f"{TOP}, 0, {BOT}, 0", f"{SIDE} - W, -{TOP}", lambda i: side_tiles(i, "right"), ["right"]),
]

def strips(ind):
    out = []
    for name, size, anchor, margin, move, tiles, lights in STRIPS:
        i2, i3, i4 = ind + "    ", ind + "        ", ind + "            "
        out += [f"{ind}surface {name} {{", f"{i2}size: {size}", f"{i2}anchor: {anchor}"]
        if margin:
            out.append(f"{i2}margin: {margin}")
        out += [f"{i2}level: bottom", f"{i2}reserve: -1", f"{i2}rate: 30", f"{i2}group {{"]
        if move:
            out.append(f"{i3}move: {move}")
        out += [f"{i3}group {{", f"{i4}glow: 8, if(st_frame_edge > 0.5 and st_frame_edge < 1.5, 0.8, 0) * st_glow, fl.phos"]
        out += tiles(i4)
        out.append(f"{i3}}}")
        for l in lights:
            out += light(i3, l)
        out += [f"{i2}}}", f"{ind}}}", ""]
    return out[:-1]

def place_surface(ind):
    """frame_p (D152): the full screen, on the top layer only while a place is out; the top strip's
    tiles that it crosses, the place melted into them."""
    i2, i3, i4 = ind + "    ", ind + "        ", ind + "            "
    act = " or ".join(f"{p}_act" for p in PLACES)
    return ([f"{ind}surface frame_p {{", f"{i2}size: full, full", f"{i2}anchor: top", f"{i2}level: bottom, top while {act}",
             # the monitor's own rate: without one it kept frame_t's 30, and the morph ran at half the
             # bar's (D153)
             f"{i2}reserve: -1", f"{i2}rate: 60", f"{i2}group {{", f"{i3}show: {act}", f"{i3}group {{",
             f"{i4}glow: 8, if(st_frame_edge > 0.5 and st_frame_edge < 1.5, 0.8, 0) * st_glow, fl.phos"]
            + end_tiles(i4, "top", place=True) + end_tiles(i4, "foot", place=True)
            + side_tiles(i4, "left", place=True) + side_tiles(i4, "right", place=True) + [f"{i3}}}", f"{i2}}}", f"{ind}}}"])

def frame():
    ind = "    "
    return "\n".join(wave_lets(ind) + [""] + strips(ind) + [""] + place_surface(ind))

GEN = {
    HELIX: {"slices": lambda: slices("            ", "pick(bar_surface, fl.hull, fl.hull, fl.hull, fl.hull, fl.steel_700)")},
    FRAME: {"frame": frame},
}

def main():
    for scene, blocks in GEN.items():
        text = scene.read_text()
        for name, fn in blocks.items():
            pat = re.compile(r"([ \t]*)// <gen:%s>\n.*?// </gen:%s>" % (name, name), re.S)
            if not pat.search(text):
                raise SystemExit(f"marker <gen:{name}> not found in {scene}")
            text = pat.sub(lambda m: f"{m.group(1)}// <gen:{name}>\n{fn()}\n{m.group(1)}// </gen:{name}>", text)
        scene.write_text(text)

if __name__ == "__main__":
    main()
