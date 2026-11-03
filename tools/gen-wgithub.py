#!/usr/bin/env python3
"""Generates shell/ui/wgithub.plm: the GitHub widget (D140) in its three layouts — card, commits,
pulse — for each of its two lanes. A lane reads its own facts (g1_*, g2_*) and models (g1c commits,
g1r runs, g1a activity …), and a scene cannot pick a model by a number, so the components are
written once per lane from the template here. Never hand-edit wgithub.plm: change this and run it.

  tools/gen-wgithub.py
"""
import pathlib

ROOT = pathlib.Path(__file__).resolve().parent.parent
OUT = ROOT / "shell" / "ui" / "wgithub.plm"

TEMPLATE = '''
    // Lane {J}: the repository's card, its commits, or its pulse (lib/ghparse; mooi-widgets.luau reads gh).
    component Gh{J}(x: number, y: number, w: number, h: number, u: number, lay: number, plate: bool,
                   ink: color, acc: color, hzv: number, tnv: number) {{
        size: w, h
        let ok = mix(acc, #5fd38a, 0.6)
        let bad = fl.ember
        let pad = 16 * u
        wg.Ground(x, y, w, h, u, plate, hzv, tnv)
        // the name (a press opens it on GitHub) and what GitHub said, if anything went wrong
        zone box gt{J} {{ from: x + pad, y + 8 * u; size: w - 2 * pad, 26 * u; cursor: pointer; role: link; label: "Open {{g{J}_name}} on GitHub"; show: not editing }}
        text "⌥  {{g{J}_name}}" {{ at: x + pad, y + 21 * u; anchor: left center; size: 14 * u; weight: 700; family: "Exo 2"; color: mix(ink, acc, 0.25 * gt{J}.hover)
              width: w - 2 * pad; lines: 1 }}
        on press gt{J} {{ emit gh_open({J} * 100) }}
        text g{J}_state {{ at: x + pad, y + 46 * u; anchor: left center; size: 10 * u; family: "Share Tech Mono"; color: bad; width: w - 2 * pad; lines: 2 }}
        // the CI marks: the last runs as lit squares, newest first
        for r in g{J}r {{
            box {{ from: x + w - pad - (r.index + 1) * 14 * u, y + 15 * u; size: 10 * u, 10 * u; corner: 2 * u
                  color: pick(r.st, mix(ink, acc, 0.3), ok, bad, acc); opacity: if(r.st == 3, 0.5 + 0.5 * sin(np_turn * 30), 0.95) }}
        }}

        // card: what it is, its numbers, its language and branch and last push
        group {{
            show: lay < 0.5
            text g{J}_desc {{ at: x + pad, y + 52 * u; anchor: left center; size: 12 * u; family: "Exo 2"; color: ink; opacity: 0.85; width: w - 2 * pad; lines: 2 }}
            text g{J}_stats {{ at: x + pad, y + h - 48 * u; anchor: left center; size: 12 * u; weight: 600; family: "Share Tech Mono"; color: ink; width: w - 2 * pad; lines: 1 }}
            text g{J}_meta {{ at: x + pad, y + h - 24 * u; anchor: left center; size: 10 * u; family: "Share Tech Mono"; color: mix(ink, acc, 0.5); width: w - 2 * pad; lines: 1 }}
        }}

        // commits: the last ones on the default branch, each with its checks' mark
        group {{
            show: lay > 0.5 and lay < 1.5
            let rh = 30 * u
            for c in g{J}c {{
                let cy = y + 44 * u + c.index * rh
                group {{
                    show: cy + rh < y + h - 6 * u
                    zone box gc{J} {{ from: x + pad, cy; size: w - 2 * pad, rh - 2 * u; cursor: pointer; role: link; label: "Open {{c.sha}}: {{c.msg}}"; show: not editing }}
                    box {{ from: x + pad - 4 * u, cy; size: w - 2 * pad + 8 * u, rh - 2 * u; corner: 4 * u; color: ink; opacity: 0.06 * gc{J}.hover }}
                    ellipse {{ at: x + pad + 4 * u, cy + rh / 2 - u; radius: 3.5 * u; color: pick(c.st, mix(ink, acc, 0.3), ok, bad, acc) }}
                    text c.msg {{ at: x + pad + 16 * u, cy + 9 * u; anchor: left center; size: 12 * u; family: "Exo 2"; color: ink; width: w - 2 * pad - 80 * u; lines: 1 }}
                    text "{{c.sha}} · {{c.who}}" {{ at: x + pad + 16 * u, cy + 21 * u; anchor: left center; size: 9 * u; family: "Share Tech Mono"; color: mix(ink, acc, 0.5); width: w - 2 * pad - 80 * u; lines: 1 }}
                    text c.when {{ at: x + w - pad, cy + 9 * u; anchor: right center; size: 9 * u; family: "Share Tech Mono"; color: mix(ink, acc, 0.4) }}
                    on press gc{J} {{ emit gh_open({J} * 100 + c.index + 1) }}
                }}
            }}
        }}

        // pulse: twelve weeks of commits as bars, and the runs with their branches
        group {{
            show: lay > 1.5 and lay < 2.5
            let gx = x + pad
            let gw = w * 0.52 - pad
            let gy = y + 44 * u
            let gh = h - 84 * u
            let bw = gw / 12
            for a in g{J}a {{
                box {{ from: gx + a.index * bw + bw * 0.15, gy + gh - max(2 * u, a.v * gh); size: bw * 0.7, max(2 * u, a.v * gh); corner: 2 * u
                      color: mix(acc, ink, 0.2 * (1 - a.v)); opacity: 0.4 + 0.6 * a.v }}
            }}
            box {{ from: gx, gy + gh; size: gw, 1; color: ink; opacity: 0.25 }}
            text g{J}_total {{ at: gx, y + h - 22 * u; anchor: left center; size: 10 * u; family: "Share Tech Mono"; color: mix(ink, acc, 0.5); width: gw; lines: 1 }}
            let rx = x + w * 0.56
            let rw = w * 0.44 - pad
            for r in g{J}r {{
                let ry = gy + r.index * 26 * u
                group {{
                    show: ry + 24 * u < y + h
                    zone box gr{J} {{ from: rx, ry; size: rw, 24 * u; cursor: pointer; role: link; label: "Open the run {{r.name}}"; show: not editing }}
                    box {{ from: rx - 4 * u, ry; size: rw + 8 * u, 24 * u; corner: 4 * u; color: ink; opacity: 0.06 * gr{J}.hover }}
                    ellipse {{ at: rx + 5 * u, ry + 12 * u; radius: 4 * u; color: pick(r.st, mix(ink, acc, 0.3), ok, bad, acc)
                              opacity: if(r.st == 3, 0.5 + 0.5 * sin(np_turn * 30), 1) }}
                    text r.name {{ at: rx + 16 * u, ry + 8 * u; anchor: left center; size: 10 * u; weight: 600; family: "Share Tech Mono"; color: ink; width: rw - 70 * u; lines: 1 }}
                    text "{{r.branch}} · {{r.when}}" {{ at: rx + 16 * u, ry + 19 * u; anchor: left center; size: 8 * u; family: "Share Tech Mono"; color: mix(ink, acc, 0.5); width: rw - 20 * u; lines: 1 }}
                    on press gr{J} {{ emit gh_open({J} * 100 + 11 + r.index) }}
                }}
            }}
        }}

        // activity: the owner's year of contributions, a cell a day (52 weeks, Sunday at the top)
        group {{
            show: lay > 2.5
            let cw = min((w - 2 * pad) / 52, (h - 74 * u) / 7)
            let gx = x + w / 2 - cw * 26
            let gy = y + 46 * u
            for c in g{J}h {{
                box {{ from: gx + floor(c.index / 7) * cw, gy + mod(c.index, 7) * cw; size: cw * 0.82, cw * 0.82; corner: cw * 0.2
                      color: if(c.lv > 0.5, acc, ink); opacity: if(c.lv < -0.5, 0, if(c.lv < 0.5, 0.08, 0.25 + 0.1875 * c.lv)) }}
            }}
            text g{J}_heat {{ at: x + pad, y + h - 16 * u; anchor: left center; size: 10 * u; family: "Share Tech Mono"; color: mix(ink, acc, 0.5); width: w - 2 * pad; lines: 1 }}
        }}
    }}
'''


def main():
    head = '''language 0.9

// GENERATED by tools/gen-wgithub.py — do not edit; change the generator and run it.
// The GitHub repo widget (D140): card, commits and pulse, for each of its two lanes.

import "widgets.plm" as wg

library WGithub {'''
    body = "".join(TEMPLATE.format(J=j) for j in (1, 2))
    OUT.write_text(head + body + "}\n")
    print(f"wrote {OUT.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
