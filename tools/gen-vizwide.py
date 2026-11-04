#!/usr/bin/env python3
"""Generates shell/ui/vizwide.plm: the desktop widgets' visualisers (D138), twelve modes drawn at any
number of bars (16-128). Bars come from the widgets scene's models vzA / vzB / vzC (one record per
bar: v, pk), so the bar modes are written once per lane (A, B, C) from one template here; the path
modes (Aurora, Liquid, Scope, the Ring's wave, Horizon's far layers) read the scene's 32 bands
vs0...vs31 and are shared. A path cannot be built in a loop, so its points are written out here.
Never hand-edit vizwide.plm: change this file and run it.

  tools/gen-vizwide.py
"""
import math, pathlib

ROOT = pathlib.Path(__file__).resolve().parent.parent
OUT = ROOT / "shell" / "ui" / "vizwide.plm"
VS = ", ".join(f"vs{i}" for i in range(32))


def vs(i):
    """band i (0-31) of the 32 path bands"""
    return f"vs{int(i) % 32}"


def bars_component(L):
    m = f"vz{L}"
    return f'''
    // Spectrum (style 0), Mirror (1) and Skyline (2) from lane {L}'s bars: thin bars with round
    // caps, a lit top, peak dots that hold and fall, and a reflection under a waterline.
    component Bars{L}(x: number, y: number, w: number, h: number, u: number, n: number, gap: number,
                     peaks: bool, refl: bool, style: number, t1: color, t2: color, still: bool) {{
        size: w, h
        let bw = w / max(1, n)
        let bwi = max(1, bw * (1 - gap))
        let mirror = style > 0.5 and style < 1.5
        let water = style > 1.5 or refl
        let fy = if(mirror, y + h / 2, if(water, y + h * 0.72, y + h))
        let reach = if(mirror, h * 0.47, if(water, h * 0.7, h * 0.96))
        for b in {m} {{
            let v = if(still, 0.06, clamp(b.v, 0.015, 1))
            let bx = x + b.index * bw + (bw - bwi) / 2
            let hh = v * reach
            let r = min(bwi / 2, 3 * u)
            box {{ from: bx, fy - hh; size: bwi, if(mirror, hh * 2, hh); corner: r; color: mix(t1, t2, v * 0.8) }}
            box {{ from: bx, fy - hh; size: bwi, min(hh, 3 * u); corner: r; color: mix(t2, #ffffff, 0.3); opacity: 0.85 }}
            box {{ from: bx, fy - b.pk * reach - 2.5 * u; size: bwi, 2 * u; corner: 1; color: t2
                  show: peaks and not still and b.pk > b.v + 0.02 }}
            box {{ from: bx, fy + if(mirror, hh - 2 * u, 0); size: bwi, 2 * u; corner: 1; color: t2; show: mirror and peaks and not still }}
            box {{ from: bx, fy + 2 * u; size: bwi, hh * 0.38; corner: r; color: t1; opacity: 0.16; show: water and not mirror }}
        }}
        box {{ from: x, fy; size: w, 1; color: t2; opacity: 0.35; show: water and not mirror }}
    }}

    // LED: a dot matrix, one column per bar, ten rows; the peak row lit in the second colour.
    component LED{L}(x: number, y: number, w: number, h: number, u: number, n: number, gap: number,
                    peaks: bool, t1: color, t2: color, dim: color, still: bool) {{
        size: w, h
        let bw = w / max(1, n)
        let rh = h / 10
        let dr = max(0.8, min(bw * (1 - gap * 0.5), rh) * 0.36)
        for b in {m} {{
            let v = if(still, 0.15, b.v)
            let cx = x + b.index * bw + bw / 2
            repeat row in 0..10 {{
                let lit = v * 10 > row + 0.5
                let top = peaks and not still and floor(b.pk * 10 - 0.01) == row
                ellipse {{ at: cx, y + h - row * rh - rh / 2; radius: dr
                          color: if(top, t2, if(lit, if(row >= 8, t2, t1), dim)); opacity: if(lit or top, 1, 0.35) }}
            }}
        }}
    }}

    // Ring: one spoke per bar round a centre, a peak dot on each, turning slowly while it plays.
    component Spokes{L}(x: number, y: number, w: number, h: number, u: number, n: number,
                       peaks: bool, t1: color, t2: color, still: bool) {{
        size: w, h
        let cx = x + w / 2
        let cy = y + h / 2
        let cr = min(w, h) * 0.27
        let reach = min(w, h) * 0.2
        group {{
            pivot: cx, cy
            rotate: np_turn * 0.15deg
            for b in {m} {{
                let v = if(still, 0.12, clamp(b.v, 0.02, 1))
                let a = b.index * 360 / max(1, n)
                line {{ from: cx + sin(a) * cr, cy - cos(a) * cr; to: cx + sin(a) * (cr + 3 * u + v * reach), cy - cos(a) * (cr + 3 * u + v * reach)
                       width: max(1, min(3 * u, 2 * 3.1416 * cr / max(1, n) * 0.55)); color: mix(t1, t2, v) }}
                ellipse {{ at: cx + sin(a) * (cr + 5 * u + b.pk * reach), cy - cos(a) * (cr + 5 * u + b.pk * reach); radius: 1.3 * u; color: t2
                          show: peaks and not still }}
            }}
        }}
    }}

    // Horizon's near layer: a stepped skyline over every bar, with a lit crest.
    component HorizonFront{L}(x: number, y: number, w: number, h: number, u: number, n: number, t1: color, t2: color, still: bool) {{
        size: w, h
        let bw = w / max(1, n)
        let base = y + h * 0.9
        for b in {m} {{
            let v = if(still, 0.1, b.v)
            let lift = v * h * 0.42
            box {{ from: x + b.index * bw, base - lift; size: bw + 0.6, y + h - base + lift; color: t1; opacity: 0.55 }}
            box {{ from: x + b.index * bw, base - lift; size: bw + 0.6, 1.6 * u; color: mix(t1, #ffffff, 0.45); opacity: 0.9 }}
        }}
    }}

    // Lane {L}: whichever of the twelve its widget has chosen (lib/widgets MODES order).
    component Lane{L}(x: number, y: number, w: number, h: number, u: number, mode: number, n: number, gap: number,
                     glow: number, peaks: bool, refl: bool, t1: color, t2: color, dim: color, still: bool, lean: number = 0) {{
        size: w, h
        let gl = min(10 * u, 12)
        group {{ glow: gl, glow, t1; shader: slant, lean while lean != 0; show: mode < 0.5
                Bars{L}(x, y, w, h, u, n, gap, peaks, refl, 0, t1, t2, still) }}
        group {{ glow: gl, glow, t1; shader: slant, lean while lean != 0; show: mode > 0.5 and mode < 1.5
                Bars{L}(x, y, w, h, u, n, gap, peaks, refl, 1, t1, t2, still) }}
        group {{ show: mode > 1.5 and mode < 2.5
                RingWave(x, y, w, h, u, t1, t2, still)
                Spokes{L}(x, y, w, h, u, n, peaks, t1, t2, still) }}
        group {{ show: mode > 2.5 and mode < 3.5
                Aurora4(x, y, w, h, u, t1, t2, still) }}
        group {{ glow: gl, glow * 0.6, t1; shader: slant, lean while lean != 0; show: mode > 3.5 and mode < 4.5
                LED{L}(x, y, w, h, u, n, gap, peaks, t1, t2, dim, still) }}
        group {{ glow: gl, glow, t1; shader: slant, lean while lean != 0; show: mode > 4.5 and mode < 5.5
                Orbit2(x, y, w, h, u, t1, t2, dim, still) }}
        group {{ show: mode > 5.5 and mode < 6.5
                Scope3(x, y, w, h, u, glow, t1, t2, still) }}
        group {{ shader: slant, lean while lean != 0; show: mode > 6.5 and mode < 7.5
                HorizonBack(x, y, w, h, u, t1, t2, still)
                HorizonFront{L}(x, y, w, h, u, n, t1, t2, still) }}
        group {{ glow: gl, glow, t1; show: mode > 7.5 and mode < 8.5
                Dust2(x, y, w, h, u, t1, t2, still) }}
        group {{ show: mode > 8.5 and mode < 9.5
                Ripple2(x, y, w, h, u, t1, t2, still) }}
        group {{ glow: gl, glow, t1; shader: slant, lean while lean != 0; show: mode > 9.5 and mode < 10.5
                Bars{L}(x, y, w, h, u, n, gap, peaks, true, 2, t1, t2, still) }}
        group {{ show: mode > 10.5
                Liquid2(x, y, w, h, u, t1, t2, still) }}
    }}
'''


def closed_path(points, indent="                   "):
    out = []
    for i, (px, py) in enumerate(points):
        out.append(("move " if i == 0 else "line ") + f"{px}, {py}")
    return ("\n" + indent).join(out) + "\n" + indent + "close"


def shared():
    s = []
    # Aurora: three layers of light, each its own drift, straight steps under a blur; a lit crest.
    layers = []
    for l in range(3):
        base, amp, spd = 0.42 - l * 0.11, 0.34 - l * 0.05, 0.35 + l * 0.3
        pts = ["x, y + h"]
        crest = []
        for j in range(13):
            fx = j / 12
            a = j * 3 + l * 5
            band = f"({vs(a - 1)} + {vs(a)} * 2 + {vs(a + 1)}) / 4"
            yy = f"y + h - h * ({base:.2f} + {amp:.2f} * if(still, 0.25, {band}) + sin(np_turn * {spd:.2f} + {j * 23 + l * 61}) * 0.05)"
            pts.append(f"x + w * {fx:.4f}, {yy}")
            crest.append((f"x + w * {fx:.4f}", yy))
        pts.append("x + w, y + h")
        col = ["t1", "mix(t1, t2, 0.5)", "t2"][l]
        body = "\n                   ".join(("move " if i == 0 else "line ") + p for i, p in enumerate(pts))
        layers.append(f"            path {{ color: {col}; opacity: {0.62 - l * 0.1:.2f}\n                   {body}\n                   close }}")
        if l == 2:
            top = "\n                   ".join(("move " if i == 0 else "line ") + f"{a}, {b}" for i, (a, b) in enumerate(crest))
            rim = f"        path {{ stroke: 1.4 * u; color: mix(t2, #ffffff, 0.35); opacity: 0.7\n                   {top} }}"
    s.append(f'''
    // Aurora: three layers of light drifting at their own pace (the far ones slow), a lit crest.
    component Aurora4(x: number, y: number, w: number, h: number, u: number, t1: color, t2: color, still: bool) {{
        size: w, h
        group {{
            blur: 6
{chr(10).join(layers)}
        }}
{rim}
    }}''')

    # Horizon's far layers: three ranges of hills behind the near skyline, parallax by pace.
    hl = []
    for l in range(2):
        base, amp, spd = 0.46 + l * 0.18, 0.32 - l * 0.06, 0.25 + l * 0.3
        pts = ["x, y + h"]
        for j in range(17):
            fx = j / 16
            yy = f"y + h * {base:.2f} - h * {amp:.2f} * if(still, 0.2, {vs(j + l * 7)}) * (0.6 + 0.4 * sin(np_turn * {spd:.2f} + {j * 37 + l * 90}))"
            pts.append(f"x + w * {fx:.4f}, {yy}")
        pts.append("x + w, y + h")
        body = "\n                   ".join(("move " if i == 0 else "line ") + p for i, p in enumerate(pts))
        col = ["mix(t2, t1, 0.2)", "mix(t1, t2, 0.4)"][l]
        hl.append(f"            path {{ color: {col}; opacity: {0.16 + l * 0.1:.2f}\n                   {body}\n                   close }}")
    s.append(f'''
    // Horizon's two far ranges, behind the near skyline (HorizonFront): each drifts at its own pace.
    component HorizonBack(x: number, y: number, w: number, h: number, u: number, t1: color, t2: color, still: bool) {{
        size: w, h
{chr(10).join(hl)}
    }}''')

    # Liquid: an outer skin and an inner glow, 32 points each, the bass at the bottom.
    def blob(rk, ampk):
        pts = []
        for k in range(32):
            a = k * 360 / 32
            band = round((k if k <= 16 else 32 - k) / 16 * 31)
            r = f"{rk} * (1 + if(still, 0.08, ({vs(band - 1)} + {vs(band)} * 2 + {vs(band + 1)}) / 4) * {ampk} + sin({a:g} * 3 + np_turn * 1.5) * 0.03)"
            pts.append((f"lcx + sin({a:g}) * {r}", f"lcy + cos({a:g}) * {r}"))
        return closed_path(pts)
    s.append(f'''
    // Liquid: an outer skin that bulges with the bands (bass at the bottom) round an inner glow.
    component Liquid2(x: number, y: number, w: number, h: number, u: number, t1: color, t2: color, still: bool) {{
        size: w, h
        let lcx = x + w / 2
        let lcy = y + h / 2
        let lr = min(w, h) * 0.26
        group {{
            blur: 14
            path {{ color: t2; opacity: 0.55
                   {blob("lr * 0.62", "0.3")} }}
        }}
        group {{
            blur: 3
            path {{ color: mix(t1, t2, 0.3); opacity: 0.8
                   {blob("lr", "0.42")} }}
        }}
        path {{ stroke: 1.2 * u; color: mix(t1, #ffffff, 0.35); opacity: 0.6
               {blob("lr", "0.42")} }}
    }}''')

    # The ring's inner wave: a closed waveform of 48 points inside the spokes, with a soft glow.
    pts = []
    for k in range(48):
        a = k * 7.5
        band = round((k if k <= 24 else 48 - k) / 24 * 31)
        r = f"rr * (0.86 + if(still, 0.04, {vs(band)}) * 0.2)"
        pts.append((f"cx + sin({a:g}) * {r}", f"cy - cos({a:g}) * {r}"))
    s.append(f'''
    // The Ring's inner wave and glow (its spokes are the lane's own, one per bar).
    component RingWave(x: number, y: number, w: number, h: number, u: number, t1: color, t2: color, still: bool) {{
        size: w, h
        let cx = x + w / 2
        let cy = y + h / 2
        let rr = min(w, h) * 0.24
        group {{
            blur: 16
            ellipse {{ at: cx, cy; radius: rr * 0.62; color: t2; opacity: 0.1 + if(still, 0, vs0 * 0.18) }}
        }}
        path {{ stroke: 1.5 * u; color: t2; opacity: 0.85
               {closed_path(pts)} }}
    }}''')

    # Scope: the trace now (32 bands) and three afterimages behind it (the logic's last frames).
    frames = []
    for hidx, alpha in ((2, 0.1), (1, 0.18), (0, 0.32)):
        F = ", ".join(f"so{hidx}_{i}" for i in range(24))
        def at(e): return f"mix(pick(floor({e}), {F}), pick(min(23, floor({e}) + 1), {F}), {e} - floor({e}))"
        frames.append(f'''        repeat k in 0..46 {{
            let f0 = k / 46
            let f1 = (k + 1) / 46
            let b0 = if(still, 0.06, {at("f0 * 23")})
            let b1 = if(still, 0.06, {at("f1 * 23")})
            line {{ from: x + f0 * w, sm + sin(f0 * 1080 + ph - {hidx + 1} * 30) * b0 * h * 0.34; to: x + f1 * w, sm + sin(f1 * 1080 + ph - {hidx + 1} * 30) * b1 * h * 0.34
                   width: 1.2 * u; color: t1; opacity: {alpha} }}
        }}''')
    s.append(f'''
    // Scope: a thin phosphor trace with three true afterimages (the last frames, fading behind it).
    component Scope3(x: number, y: number, w: number, h: number, u: number, glow: number, t1: color, t2: color, still: bool) {{
        size: w, h
        let sm = y + h / 2
        let ph = np_turn * 9
{chr(10).join(frames)}
        group {{
            glow: min(8 * u, 10), max(0.3, glow), t1
            repeat k in 0..64 {{
                let f0 = k / 64
                let f1 = (k + 1) / 64
                let b0 = if(still, 0.06, mix(pick(floor(f0 * 31), {VS}), pick(min(31, floor(f0 * 31) + 1), {VS}), f0 * 31 - floor(f0 * 31)))
                let b1 = if(still, 0.06, mix(pick(floor(f1 * 31), {VS}), pick(min(31, floor(f1 * 31) + 1), {VS}), f1 * 31 - floor(f1 * 31)))
                line {{ from: x + f0 * w, sm + sin(f0 * 1080 + ph) * b0 * h * 0.34 + sin(f0 * 3100 + ph * 0.4) * b0 * h * 0.06
                       to: x + f1 * w, sm + sin(f1 * 1080 + ph) * b1 * h * 0.34 + sin(f1 * 3100 + ph * 0.4) * b1 * h * 0.06
                       width: 1.5 * u; color: mix(t1, t2, b0 * 0.5) }}
            }}
        }}
    }}''')

    s.append('''
    // Dust: two depths of specks (far: small and slow; near: larger and quicker), each leaving a
    // short trail along the way the beat throws it.
    component Dust2(x: number, y: number, w: number, h: number, u: number, t1: color, t2: color, still: bool) {
        size: w, h
        repeat k in 0..96 {
            let near = mod(k, 2) == 1
            let bx = mod(k * 61, 97) / 97
            let by = mod(k * k * 7 + k * 29, 89) / 89
            let pace = if(near, 1.6, 0.7)
            let push = np_scatter * if(near, 0.4, 0.2)
            let dx = bx + if(still, 0, sin(np_turn * (0.3 + mod(k, 5) * 0.1) * pace + k * 37) * 0.02) + (bx - 0.5) * push
            let dy = by + if(still, 0, cos(np_turn * (0.25 + mod(k, 7) * 0.08) * pace + k * 53) * 0.03) + (by - 0.5) * push
            let px = x + clamp(dx, 0, 1) * w
            let py = y + clamp(dy, 0, 1) * h
            line { from: px, py; to: px - (bx - 0.5) * push * w * 0.25, py - (by - 0.5) * push * h * 0.25
                   width: if(near, 1.4, 0.8) * u; color: if(mod(k, 3) == 0, t2, t1); opacity: if(near, 0.45, 0.25) * min(1, np_scatter * 2) }
            ellipse { at: px, py; radius: (if(near, 1.3, 0.6) + mod(k, 4) * 0.25) * u
                      color: if(mod(k, 3) == 0, t2, t1); opacity: if(near, 0.75, 0.4) + np_scatter * 0.25 }
        }
    }

    // Ripple: rings from the centre on each beat, each thick where it hit hardest, with a faint
    // refracting band inside it.
    component Ripple2(x: number, y: number, w: number, h: number, u: number, t1: color, t2: color, still: bool) {
        size: w, h
        let rcx = x + w / 2
        let rcy = y + h / 2
        let half = min(w, h) / 2
        repeat k in 0..4 {
            let rr = pick(k, rp_r0, rp_r1, rp_r2, rp_r3)
            let ra = if(still, 0, pick(k, rp_a0, rp_a1, rp_a2, rp_a3))
            arc { at: rcx, rcy; radius: max(1, rr * half * 0.93); width: 7 * u; span: 360deg; color: mix(t1, #ffffff, 0.3); opacity: ra * 0.1 }
            arc { at: rcx, rcy; radius: max(1, rr * half); width: (1 + ra * 2.5) * u; span: 360deg; color: mix(t1, t2, rr); opacity: ra }
        }
        group {
            glow: 8 * u, 0.6, t1
            ellipse { at: rcx, rcy; radius: (3 + if(still, 0, vs0 * 5)) * u; color: t1 }
        }
    }

    // Orbit: particles on three rings, each trailing a fading arc; the low band swells the inner
    // ring, the high speeds the outer.
    component Orbit2(x: number, y: number, w: number, h: number, u: number, t1: color, t2: color, dim: color, still: bool) {
        size: w, h
        let ocx = x + w / 2
        let ocy = y + h / 2
        let base = min(w, h) / 2
        let lo = if(still, 0.2, (vs0 + vs1 + vs2 + vs3 + vs4 + vs5) / 6)
        let hi = if(still, 0.1, (vs24 + vs26 + vs28 + vs30 + vs31) / 5)
        repeat ring in 0..3 {
            let rr = base * (0.36 + ring * 0.27) * (1 + if(ring == 0, lo * 0.25, 0))
            arc { at: ocx, ocy; radius: rr; width: 1; span: 360deg; color: dim; opacity: 0.5 }
            repeat p in 0..6 {
                let a = p * 60 + ring * 20 + np_turn * (0.6 + ring * 0.5) * (1 + if(ring == 2, hi, 0))
                arc { at: ocx, ocy; radius: rr; width: (1.2 + ring * 0.4) * u; span: 28deg; rotate: (a - 28) * 1deg
                      color: if(mod(p + ring, 3) == 0, t2, t1); opacity: 0.35 }
                ellipse { at: ocx + sin(a) * rr, ocy - cos(a) * rr; radius: (1.6 + ring * 0.7 + lo * 2) * u
                          color: if(mod(p + ring, 3) == 0, t2, t1) }
            }
        }
    }''')
    return "".join(s)


def main():
    head = '''language 0.9

// GENERATED by tools/gen-vizwide.py — do not edit; change the generator and run it.
// The desktop widgets' visualisers (D138): twelve modes at 16-128 bars. Bar modes read the scene's
// models vzA / vzB / vzC (a lane each), path modes its 32 bands vs0...vs31; the Scope's afterimages
// so0_*...so2_*, the ripples' rings rp_*, the beat's push np_scatter and the drift np_turn.
library VizWide {
    // The lean (lib/widgets options.lean): a shear of what a lane holds, inside its own box. It goes
    // on the modes whose drawing has no effects of its own — a shader and a glow cannot be nested.
    shader slant = file "../shaders/lean.wgsl"
'''
    body = shared() + "".join(bars_component(L) for L in "ABC")
    OUT.write_text(head + body + "\n}\n")
    print(f"wrote {OUT.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
