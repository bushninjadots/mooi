#!/usr/bin/env python3
"""mooi's wallpaper index (D145): every picture and live wallpaper in the folders, read once.

    wallindex.py CACHE DATA HUES FOLDER...

CACHE   ~/.cache/mooi/walls: thumbs/ and stills/ go here
DATA    mooi's data folder: walls-index.json and walls-orbit.png go here (a Pleamar scene reads only
        its own folder)
HUES    the notch's wallpaper-hues.json (path → hue, or false for grey), reused where it has one

For each file: its kind (still · animated · video), a 320×180 thumbnail cut to fill, its mean
colour as a hue (none for grey), a lightness 0..1, and for a video a full-size still (a frame a
second in) for the desk to draw while mpvpaper starts. Only new and changed files are read (by
mtime); files that have gone are dropped. walls-index.json is rewritten every 200 files, so the picker
fills in while a first pass runs. walls-orbit.png is the colour orbit's every picture as one dot of its
colour, placed as shell/lib/walls.luau places them. One pass at a time (a lock in CACHE).
"""
import colorsys
import fcntl
import json
import math
import os
import subprocess
import sys
import time
import warnings

from PIL import Image, ImageDraw, ImageOps

# The folders are the user's own pictures, some very large (a 191-megapixel scan was refused by
# Pillow's default 89 MP guard): a higher bound, still a bound, and no warning per picture.
Image.MAX_IMAGE_PIXELS = 400_000_000
warnings.simplefilter("ignore", Image.DecompressionBombWarning)

THUMB = (320, 180)
STILL_EXT = {"jpg", "jpeg", "png", "webp", "avif", "jxl", "bmp"}
ANIMATED_EXT = {"gif", "apng"}
VIDEO_EXT = {"mp4", "webm", "mkv", "mov", "m4v", "avi"}
GREY_SAT = 0.12          # below this a picture has no hue worth placing (the notch's rule too)
ORBIT = {"inner": 0.34, "outer": 1.0, "grey": 0.2, "size": 1024, "dot": 5}


def djb2(path):
    """The same name the notch gives a thumbnail (lib/notch.thumb_name), so both read one."""
    h = 5381
    for b in path.encode("utf-8"):
        h = (h * 33 + b) % 4294967296
    return "%08x" % h


def kind_of(path):
    ext = path.rsplit(".", 1)[-1].lower() if "." in os.path.basename(path) else ""
    if ext in VIDEO_EXT:
        return "video"
    if ext in ANIMATED_EXT:
        return "animated"
    if ext in STILL_EXT:
        return "still"
    return None


def cover(im, size):
    return ImageOps.fit(im.convert("RGB"), size, Image.LANCZOS, centering=(0.5, 0.5))


def colour_of(im):
    """Mean colour → (hue 0..360 or None, lightness 0..1, '#rrggbb')."""
    r, g, b = im.convert("RGB").resize((1, 1), Image.BOX).getpixel((0, 0))
    h, l, s = colorsys.rgb_to_hls(r / 255, g / 255, b / 255)
    v = max(r, g, b) / 255
    sat = (v - min(r, g, b) / 255) / v if v > 0 else 0
    return (None if sat < GREY_SAT else h * 360), l, "#%02x%02x%02x" % (r, g, b)


def video_still(path, out):
    for at in ("1", "0"):
        r = subprocess.run(["ffmpeg", "-v", "error", "-y", "-ss", at, "-i", path, "-frames:v", "1",
                            "-q:v", "2", out], capture_output=True)
        if r.returncode == 0 and os.path.exists(out) and os.path.getsize(out) > 0:
            return True
    return False


def read_one(path, cache, hues):
    kind = kind_of(path)
    key = djb2(path)
    thumb = os.path.join(cache, "thumbs", key + ".jpg")
    item = {"path": path, "kind": kind, "mtime": int(os.path.getmtime(path)), "thumb": thumb}
    if kind == "video":
        still = os.path.join(cache, "stills", key + ".jpg")
        if not video_still(path, still):
            raise ValueError("ffmpeg could not read a frame")
        item["still"] = still
        src = Image.open(still)
    else:
        src = Image.open(path)
        if getattr(src, "is_animated", False) and getattr(src, "n_frames", 1) > 1:
            item["kind"] = "animated"
        src.seek(0)
        # a JPEG decoded at a fraction of its size, still larger than the thumbnail: much faster
        if src.format == "JPEG":
            src.draft("RGB", (THUMB[0] * 2, THUMB[1] * 2))
    t = cover(src, THUMB)
    t.save(thumb, "JPEG", quality=80)
    hue, luma, rgb = colour_of(t)
    known = hues.get(path)
    if known is False:
        hue = None
    elif isinstance(known, (int, float)):
        hue = float(known) % 360
    item["hue"] = None if hue is None else round(hue, 1)
    item["grey"] = hue is None
    item["luma"] = round(luma, 3)
    item["rgb"] = rgb
    return item


def place(it, gi, greys):
    if it.get("grey"):
        a = 360 * gi / max(1, greys)
        r = ORBIT["grey"]
    else:
        a = it["hue"]
        r = ORBIT["inner"] + (ORBIT["outer"] - ORBIT["inner"]) * it.get("luma", 0.5)
    rad = math.radians(a)
    return math.sin(rad) * r, -math.cos(rad) * r


def draw_orbit(items, out):
    n = ORBIT["size"]
    half = n / 2 - ORBIT["dot"] - 2
    im = Image.new("RGBA", (n, n), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    greys = sum(1 for it in items if it.get("grey"))
    gi = 0
    for it in items:
        x, y = place(it, gi, greys)
        if it.get("grey"):
            gi += 1
        cx, cy = n / 2 + x * half, n / 2 + y * half
        rr = ORBIT["dot"]
        d.ellipse((cx - rr, cy - rr, cx + rr, cy + rr), fill=it.get("rgb", "#888888"))
    tmp = out + ".tmp.png"
    im.save(tmp)
    os.replace(tmp, out)


def order(items):
    # by hue (greys last), then name: the strip walks the colours in turn
    return sorted(items, key=lambda it: (1 if it.get("grey") else 0, it.get("hue") or 0,
                                         os.path.basename(it["path"]).lower()))


def write(data, items, skipped, done):
    doc = {"version": 1, "at": int(time.time()), "complete": done,
           "items": order(items), "skipped": skipped}
    tmp = os.path.join(data, "walls-index.json.tmp")
    with open(tmp, "w") as f:
        json.dump(doc, f)
    os.replace(tmp, os.path.join(data, "walls-index.json"))


def main():
    if len(sys.argv) < 5:
        print(__doc__, file=sys.stderr)
        return 2
    cache, data, hues_path, folders = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4:]
    os.makedirs(data, exist_ok=True)
    for sub in ("thumbs", "stills"):
        os.makedirs(os.path.join(cache, sub), exist_ok=True)
    lock = open(os.path.join(cache, "index.lock"), "w")
    try:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except OSError:
        print("wallindex: a pass is already running", file=sys.stderr)
        return 0
    try:
        with open(hues_path) as f:
            hues = json.load(f)
        if not isinstance(hues, dict):
            hues = {}
    except (OSError, ValueError):
        hues = {}
    old, old_skipped = {}, {}
    try:
        with open(os.path.join(data, "walls-index.json")) as f:
            doc = json.load(f)
        for it in doc.get("items", []):
            old[it["path"]] = it
        for it in doc.get("skipped", []):
            old_skipped[it["path"]] = it
    except (OSError, ValueError, KeyError, TypeError, AttributeError):
        pass

    files = []
    for folder in folders:
        try:
            names = sorted(os.listdir(folder))
        except OSError:
            continue
        for name in names:
            p = os.path.join(folder, name)
            if os.path.isfile(p) and kind_of(p):
                files.append(p)

    items, skipped, fresh = [], [], 0
    for p in files:
        prev = old.get(p)
        try:
            mtime = int(os.path.getmtime(p))
        except OSError:
            continue
        if prev and prev.get("mtime") == mtime and os.path.exists(prev.get("thumb", "")):
            items.append(prev)
            continue
        bad = old_skipped.get(p)
        if bad and bad.get("mtime") == mtime:   # tried before and unreadable: not again until it changes
            skipped.append(bad)
            continue
        try:
            items.append(read_one(p, cache, hues))
        except Exception as e:  # one bad file never stops the pass
            why = str(e).replace(p, "it")[:120]
            skipped.append({"path": p, "mtime": mtime, "why": why})
        fresh += 1
        if fresh % 200 == 0:
            write(data, items, skipped, False)
            draw_orbit(order(items), os.path.join(data, "walls-orbit.png"))
    write(data, items, skipped, True)
    draw_orbit(order(items), os.path.join(data, "walls-orbit.png"))
    print("wallindex: %d pictures (%d read now, %d skipped)" % (len(items), fresh, len(skipped)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
