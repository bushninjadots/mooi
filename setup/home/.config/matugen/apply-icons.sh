#!/bin/bash
# Folders in the palette: a small local icon theme that inherits Papirus and
# recolours only its folder SVGs. Papirus draws every folder from one blue
# (#5294e2, shaded #4877b1) at every size, so the palette's primary and a darker
# shade of it replace those two and nothing else in the set moves. The theme is
# written under ~/.local/share/icons/Papirus-Mooi; mooi's `apps-sync` points the
# icon theme at it when it exists and back at Papirus-Dark/Light when it does not,
# so turning the apps switch off leaves the icon set as it was.
# Usage: apply-icons.sh [palette.json]   (default: ~/.cache/quickshell/colors.json)
set -u
C="${XDG_CONFIG_HOME:-$HOME/.config}"
palette="${1:-$HOME/.cache/quickshell/colors.json}"
[ -f "$palette" ] || exit 0
command -v python3 >/dev/null 2>&1 || exit 0
data="${XDG_DATA_HOME:-$HOME/.local/share}"
settings="$data/pleamar/mooi/settings.json"
# The Files switch owns this layer: off means Papirus stays exactly as installed.
if [ -f "$settings" ] && command -v jq >/dev/null 2>&1; then
    # `.files != false` rather than `.files // true`: jq's alternative operator counts false as
    # missing, so the latter would read the switch as on even when it is off.
    [ "$(jq -r '.apps.files != false' "$settings" 2>/dev/null)" = false ] && exit 0
fi

out=$(python3 - "$palette" "$data" <<'PY'
import configparser, json, os, shutil, subprocess, sys, tempfile

palette_path, data_home = sys.argv[1], sys.argv[2]
try:
    c = json.load(open(palette_path))
except Exception:
    sys.exit(1)

primary = c.get("primary")
surface = c.get("surface")
container = c.get("primary_container")
# The quickshell template writes flat lowercase hexes; mooi's palette.json nests
# them under "colours"; Matugen's own JSON uses colors.<role>.default.hex.
colours = c.get("colours") or {}
primary = primary or colours.get("primary")
surface = surface or colours.get("surface_dim") or colours.get("surface_container_low")
container = container or colours.get("primary_container")
if isinstance(c.get("colors"), dict):
    def role(name):
        r = c["colors"].get(name)
        if isinstance(r, dict) and isinstance(r.get("default"), dict):
            return r["default"].get("hex")
        return r if isinstance(r, str) else None
    primary = primary or role("primary")
    surface = surface or role("surface")
    container = container or role("primary_container")
if not (primary and surface):
    sys.exit(1)

def rgb(h):
    h = h.lstrip("#")
    return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4))

def lum(h):
    def f(v):
        v /= 255.0
        return v / 12.92 if v <= 0.03928 else ((v + 0.055) / 1.055) ** 2.4
    r, g, b = rgb(h)
    return 0.2126 * f(r) + 0.7152 * f(g) + 0.0722 * f(b)

base = "Papirus-Dark" if lum(surface) < 0.5 else "Papirus-Light"
base_dir = None
for root in ("/usr/share/icons", os.path.join(data_home, "icons")):
    p = os.path.join(root, base)
    if os.path.isdir(p):
        base_dir = p
        break
if not base_dir:
    sys.exit(1)

def shade(h, amount):
    r, g, b = rgb(h)
    return "#%02x%02x%02x" % (int(r * (1 - amount)), int(g * (1 - amount)), int(b * (1 - amount)))

def mix(a, b, t):
    ar, ag, ab = rgb(a)
    br, bg, bb = rgb(b)
    return "#%02x%02x%02x" % (int(ar + (br - ar) * t), int(ag + (bg - ag) * t), int(ab + (bb - ab) * t))

# Papirus's folder blue (#5294e2) is a medium tone, so the flat accent (a pale
# primary in a dark scheme) would read as pastel beside the rest of the set. Mix
# it most of the way to the scheme's container role: the folder keeps the
# accent's hue but sits at the weight Papirus drew it, and its shade follows.
body = mix(primary, container, 0.55) if container else shade(primary, 0.35)
shade_hex = shade(body, 0.28)
replace = {"#5294e2": body, "#4877b1": shade_hex, "#5294E2": body, "#4877B1": shade_hex}

cp = configparser.RawConfigParser(strict=False, interpolation=None)
cp.optionxform = str
cp.read(os.path.join(base_dir, "index.theme"))
sections = [s for s in cp.sections() if s.endswith("/places")]

names = ("folder", "folder-open", "folder-drag-accept", "inode-directory", "folder-new")
icons_dir = os.path.join(data_home, "icons")
out_dir = os.path.join(icons_dir, "Papirus-Mooi")
os.makedirs(icons_dir, exist_ok=True)
tmp = tempfile.mkdtemp(prefix=".Papirus-Mooi-", dir=icons_dir)
written = []

for sec in sections:
    src_dir = os.path.join(base_dir, sec)
    for name in names:
        src = os.path.join(src_dir, name + ".svg")
        if not os.path.exists(src):
            continue
        try:
            text = open(os.path.realpath(src), encoding="utf-8", errors="ignore").read()
        except OSError:
            continue
        if "#5294e2" not in text and "#4877b1" not in text:
            continue
        for old, new in replace.items():
            text = text.replace(old, new)
        dst_dir = os.path.join(tmp, sec)
        os.makedirs(dst_dir, exist_ok=True)
        open(os.path.join(dst_dir, name + ".svg"), "w", encoding="utf-8").write(text)
        if sec not in written:
            written.append(sec)

normal = sorted(s for s in written if "@2x" not in s)
scaled = sorted(s for s in written if "@2x" in s)
lines = ["[Icon Theme]",
         "Name=Papirus-Mooi",
         "Comment=Papirus with folders in the desktop palette",
         "Inherits=" + base,
         "Example=folder",
         ""]
if normal:
    lines.append("Directories=" + ",".join(normal))
if scaled:
    lines.append("ScaledDirectories=" + ",".join(scaled))
lines.append("")
for sec in sorted(written):
    lines += ["[%s]" % sec,
              "Context=" + cp.get(sec, "Context", fallback="Places"),
              "Size=" + cp.get(sec, "Size", fallback="48"),
              "Type=" + cp.get(sec, "Type", fallback="Fixed"),
              ""]
open(os.path.join(tmp, "index.theme"), "w", encoding="utf-8").write("\n".join(lines))

if os.path.isdir(out_dir):
    shutil.rmtree(out_dir)
os.rename(tmp, out_dir)
if shutil.which("gtk-update-icon-cache"):
    subprocess.run(["gtk-update-icon-cache", "-q", "-f", out_dir],
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=False)
print(base, body, shade_hex, len(written))
PY
)
[ -n "$out" ] || exit 0
set -- $out
base=$1

# Keep the desktop on the override only while the icon theme is Papirus's own, so
# a set the user picked by hand is not overridden. settings.ini is what GTK 3/4
# read when it is set; apps-sync writes the same name into it.
if command -v gsettings >/dev/null 2>&1; then
    cur=$(gsettings get org.gnome.desktop.interface icon-theme 2>/dev/null | tr -d "'")
    case "$cur" in
        Papirus*)
            gsettings set org.gnome.desktop.interface icon-theme Papirus-Mooi 2>/dev/null || true
            for v in 3 4; do
                f="$C/gtk-$v.0/settings.ini"
                [ -f "$f" ] && sed -i "s|^gtk-icon-theme-name=.*|gtk-icon-theme-name=Papirus-Mooi|" "$f"
            done
            ;;
    esac
fi
echo "icons: Papirus-Mooi (folders $2, shade $3, over $base, $4 sizes)"
