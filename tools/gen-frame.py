#!/usr/bin/env python3
"""Generates the pieces of shell/mooi.plm that pleamar cannot repeat itself: a `body` holds
shapes, not `repeat`s, and the helix's pinched middle and the screen frame's swell lobes are
bodies (one silhouette each). Run it after changing these; it rewrites the text between the
`// <gen:NAME>` and `// </gen:NAME>` markers in shell/mooi.plm.

  tools/gen-frame.py
"""
import re, pathlib

SCENE = pathlib.Path(__file__).resolve().parent.parent / "shell" / "mooi.plm"

def slices(indent, color):
    """The helix's pinched middle: 56 slices of 4 px between the two twisting edges."""
    out = []
    for k in range(56):
        sx = f"(hx_a + {k * 4})"
        w = f"smooth(0, 1, clamp(({sx} + 2 - hx_a) / 14, 0, 1) * clamp((hx_b - {sx} - 2) / 14, 0, 1))"
        p = f"(90 - ({sx} + 2 - chain_x) / fl.pitch * fl.dna_twist + spin)"
        st = f"mix(pt, fl.cy - amp * sin({p}), {w})"
        sb = f"mix(pb, fl.cy + amp * sin({p}), {w})"
        out.append(f"{indent}box {{ color: {color}; from: {sx}, min({st}, {sb}); size: 4.6, max(0.5, abs({sb} - {st})); show: helix_edges and {sx} < hx_b }}")
    return "\n".join(out)

def lobes(indent):
    """The screen frame's swell: wide flat lobes along each edge whose heights are a wave
    travelling with the music's phase (Tide's maths). Seven along the top (under the bar) and
    the bottom, four up each side; `crests` makes them narrow drops."""
    out = []
    def lobe(at, length, horizontal, phase, amp_name):
        r = f"({length} * if(frame_style == 1, 0.28, 0.62)) * clamp({amp_name} / 4, 0, 1)"
        h = f"max(0.5, {amp_name} * if(frame_style == 1, 1.3, 0.8) * (0.5 + 0.5 * sin({phase:.2f} * 57.3 - fphs * 126)))"
        scale = f"1, {h} / max(0.5, {length} * if(frame_style == 1, 0.28, 0.62))" if horizontal else f"{h} / max(0.5, {length} * if(frame_style == 1, 0.28, 0.62)), 1"
        out.append(f"{indent}ellipse {{ at: {at}; radius: {r}; scale: {scale}; blend: 22 * clamp({amp_name} / 4, 0, 1); show: {amp_name} > 0.5 and frame_style < 1.5 }}")
    for i in range(7):
        x = (i + 0.5) / 7
        lobe(f"W * {x:.4f}, st_res", "W / 7", True, i * 1.15, "aflat")
        lobe(f"W * {x:.4f}, H - bt", "W / 7", True, 0.8 + i * 1.15, "aflat")
    for i in range(4):
        y = (i + 0.5) / 4
        lobe(f"bs, H * {y:.4f}", "H / 4", False, 1.6 + i * 1.15, "aside")
        lobe(f"W - bs, H * {y:.4f}", "H / 4", False, 2.4 + i * 1.15, "aside")
    return "\n".join(out)

GEN = {
    "slices": lambda: slices("            ", "pick(bar_surface, fl.hull, fl.hull, fl.hull, fl.hull, fl.steel_700)"),
    "lobes": lambda: lobes("            "),
}

def main():
    text = SCENE.read_text()
    for name, fn in GEN.items():
        pat = re.compile(r"([ \t]*)// <gen:%s>\n.*?// </gen:%s>" % (name, name), re.S)
        if not pat.search(text):
            raise SystemExit(f"marker <gen:{name}> not found in {SCENE}")
        text = pat.sub(lambda m: f"{m.group(1)}// <gen:{name}>\n{fn()}\n{m.group(1)}// </gen:{name}>", text)
    SCENE.write_text(text)

if __name__ == "__main__":
    main()
