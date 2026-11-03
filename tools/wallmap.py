#!/usr/bin/env python3
"""The wallpaper, read for the desktop widgets (D139): `mooi wallmap <file>` runs this.

Frames the picture the way the picker shows it (fill and crop to the screen, centred), cuts its
subject out with rembg when it is installed, and measures a 32 x 18 grid: luma, Lab colour, detail
(edge density) and how much of each cell is subject; plus the picture's mood. Results are cached by
the picture's content, so a wallpaper seen before is instant; the latest are copied into mooi's data
folder as wall-cut.png and wall-map.json (the widgets watch the second).

  tools/wallmap.py <file> <data folder> [width height] [model]
"""
import hashlib, json, os, shutil, subprocess, sys, tempfile

COLS, ROWS = 32, 18
VIDEO = (".mp4", ".webm", ".mkv", ".mov", ".gif")
VERSION = 2               # of the analysis: a change here reads every picture again


def run(*args, **kw):
    return subprocess.run(args, check=True, capture_output=True, **kw).stdout


def grid_bytes(src, mode, extra=()):
    """the picture shrunk to the grid, as raw bytes of `mode` (rgb or gray)"""
    return run("magick", src, *extra, "-scale", f"{COLS}x{ROWS}!", "-depth", "8", f"{mode}:-")


def lab(r, g, b):
    """sRGB 0-255 to Lab, L in 0..1, a and b roughly -1..1"""
    def lin(c):
        c /= 255
        return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4
    R, G, B = lin(r), lin(g), lin(b)
    X = (0.4124 * R + 0.3576 * G + 0.1805 * B) / 0.95047
    Y = 0.2126 * R + 0.7152 * G + 0.0722 * B
    Z = (0.0193 * R + 0.1192 * G + 0.9505 * B) / 1.08883
    f = lambda t: t ** (1 / 3) if t > 0.008856 else 7.787 * t + 16 / 116
    fx, fy, fz = f(X), f(Y), f(Z)
    return (116 * fy - 16) / 100, 500 * (fx - fy) / 128, 200 * (fy - fz) / 128


def analyse(still, cut, has_cut):
    rgb = grid_bytes(still, "rgb")
    # detail: gradient strength on a 10x finer grey copy, averaged into each cell (as it is, not
    # levelled, so a calm dark picture reads calm)
    FW, FH = COLS * 10, ROWS * 10
    g = run("magick", still, "-colorspace", "gray", "-scale", f"{FW}x{FH}!", "-depth", "8", "gray:-")
    px = lambda x, y: g[min(FH - 1, max(0, y)) * FW + min(FW - 1, max(0, x))]
    edges = []
    for cy in range(ROWS):
        for cx in range(COLS):
            tot = 0
            for y in range(cy * 10, cy * 10 + 10):
                for x in range(cx * 10, cx * 10 + 10):
                    gx = px(x + 1, y) - px(x - 1, y)
                    gy = px(x, y + 1) - px(x, y - 1)
                    tot += (gx * gx + gy * gy) ** 0.5
            edges.append(min(255, int(tot / 100 * 3)))
    alpha = grid_bytes(cut, "gray", ("-alpha", "extract")) if has_cut else bytes(COLS * ROWS)
    cells, ls, sats, ds = [], [], [], []
    for i in range(COLS * ROWS):
        r, g, b = rgb[i * 3], rgb[i * 3 + 1], rgb[i * 3 + 2]
        L, A, B = lab(r, g, b)
        d, s = edges[i] / 255, alpha[i] / 255
        cells.append({"l": round(L, 3), "a": round(A, 3), "b": round(B, 3), "d": round(d, 3), "s": round(s, 3)})
        ls.append(L); ds.append(d); sats.append(min(1.0, (A * A + B * B) ** 0.5))
    mean = lambda v: sum(v) / len(v)
    var = mean([(x - mean(ls)) ** 2 for x in ls])
    mood = {"luma": round(mean(ls), 3), "sat": round(mean(sats), 3),
            "contrast": round(min(1.0, (var ** 0.5) * 3), 3), "detail": round(mean(ds), 3)}
    return cells, mood


def main():
    src, folder = sys.argv[1], sys.argv[2]
    w = int(sys.argv[3]) if len(sys.argv) > 3 else 1920
    h = int(sys.argv[4]) if len(sys.argv) > 4 else 1080
    model = sys.argv[5] if len(sys.argv) > 5 else "bria-rmbg"
    with open(src, "rb") as fh:
        key = hashlib.file_digest(fh, "sha1").hexdigest()[:16] + f"-{w}x{h}-{model}-v{VERSION}"
    cache = os.path.join(os.path.expanduser("~/.cache/mooi/wallmap"), key)
    os.makedirs(cache, exist_ok=True)
    still, cut, mp = (os.path.join(cache, n) for n in ("still.png", "cut.png", "map.json"))
    moving = src.lower().endswith(VIDEO)
    if not moving:
        # an animated WebP or PNG moves too: count its frames
        try:
            moving = int(run("magick", "identify", "-format", "%n\n", src).split()[0]) > 1
        except (subprocess.CalledProcessError, ValueError, IndexError):
            pass
    cached = None
    if os.path.exists(mp):
        try:
            with open(mp) as fh:
                cached = json.load(fh)
        except (OSError, ValueError):
            cached = None
        # a cut-out that failed (rembg missing, offline, killed) is tried again once it can be made
        if cached and not cached.get("cut") and not moving and shutil.which("rembg") and not os.path.exists(cut):
            cached = None
    if not cached:
        frame = src + "[0]"
        run("magick", frame, "-resize", f"{w}x{h}^", "-gravity", "center", "-extent", f"{w}x{h}", still)
        has_cut = os.path.exists(cut) and not moving
        if not has_cut and not moving and shutil.which("rembg"):
            raw = os.path.join(cache, "cut-raw.png")
            try:
                subprocess.run(["nice", "-n", "19", "rembg", "i", "-m", model, still, raw], check=True, capture_output=True)
                # a soft edge, so the subject does not look pasted on
                run("magick", raw, "(", "+clone", "-alpha", "extract", "-blur", "0x1.5", ")", "-alpha", "off", "-compose", "copy_opacity", "-composite", cut)
                os.remove(raw)
                has_cut = True
            except subprocess.CalledProcessError:
                has_cut = False
        cells, mood = analyse(still, cut, has_cut)
        cached = {"cols": COLS, "rows": ROWS, "cells": cells, "mood": mood, "cut": has_cut,
                  "depth": has_cut and not moving, "w": w, "h": h, "cutpath": cut if has_cut else "",
                  "rembg": shutil.which("rembg") or ""}
    # the path it is shown from now (the same picture may be set from another place)
    cached["src"] = src
    t = tempfile.NamedTemporaryFile("w", dir=cache, delete=False, suffix=".json")
    with t:
        json.dump(cached, t)
    os.replace(t.name, mp)
    # into mooi's data folder: the cut-out first, then the map (the widgets watch the map)
    os.makedirs(folder, exist_ok=True)
    if os.path.exists(cut):
        t = tempfile.NamedTemporaryFile(dir=folder, delete=False, suffix=".png"); t.close()
        shutil.copyfile(cut, t.name); os.replace(t.name, os.path.join(folder, "wall-cut.png"))
    t = tempfile.NamedTemporaryFile(dir=folder, delete=False, suffix=".json"); t.close()
    shutil.copyfile(mp, t.name); os.replace(t.name, os.path.join(folder, "wall-map.json"))
    print(os.path.join(folder, "wall-map.json"))


if __name__ == "__main__":
    main()
