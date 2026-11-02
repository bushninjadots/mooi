#!/bin/bash
# Copies the rendered ArchEclipse KDE scheme's colour groups into kdeglobals
# (KDE apps like Dolphin read them there) and selects the scheme. Keeps every
# other kdeglobals setting (widget style, icons, fonts).
python3 - <<'PY'
import configparser, os
src = os.path.expanduser("~/.local/share/color-schemes/ArchEclipse.colors")
dst = os.path.expanduser("~/.config/kdeglobals")
def load(p):
    cp = configparser.RawConfigParser(strict=False, interpolation=None)
    cp.optionxform = str
    if os.path.exists(p):
        cp.read(p)
    return cp
s, d = load(src), load(dst)
for sec in s.sections():
    if sec.startswith("Colors:") or sec == "WM":
        if not d.has_section(sec):
            d.add_section(sec)
        for k, v in s.items(sec):
            d.set(sec, k, v)
if not d.has_section("General"):
    d.add_section("General")
d.set("General", "ColorScheme", "ArchEclipse")
with open(dst, "w") as f:
    d.write(f, space_around_delimiters=False)
PY
