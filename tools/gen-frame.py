#!/usr/bin/env python3
"""Generates the pieces of shell/mooi.plm that pleamar cannot repeat itself: a `body` holds
shapes, not `repeat`s. The helix's pinched middle is the one block left that needs it; run it
after changing it, and it rewrites the text between `// <gen:NAME>` and `// </gen:NAME>` in
shell/mooi.plm.

  tools/gen-frame.py
"""
import re, pathlib

SCENE = pathlib.Path(__file__).resolve().parent.parent / "shell" / "mooi.plm"

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

GEN = {
    "slices": lambda: slices("            ", "pick(bar_surface, fl.hull, fl.hull, fl.hull, fl.hull, fl.steel_700)"),
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
