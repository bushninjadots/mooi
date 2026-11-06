#!/bin/sh
# setup/install.sh — rebuild this desktop on a fresh Arch-based system (EndeavourOS here) from the repo:
# the packages, pleamar at the exact commit it ran on, the Hyprland config and its helpers, mooi's own
# settings and state, the fonts and themes, and the login screen. setup/capture.sh made what it reads.
#
#   git clone git@github.com:bushninjadots/mooi.git ~/Projects/mooi
#   ~/Projects/mooi/setup/install.sh          everything
#   ~/Projects/mooi/setup/install.sh --no-packages   the files only (packages already there)
#
# Whatever it replaces in your home is moved, not deleted, to ~/.setup-backup-<date>/ first.
# Run it as yourself (it asks for sudo for packages and the login screen). Then log out and pick the
# Hyprland session: mooi starts with it.
set -eu
here=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$here/.." && pwd)
packages=true
for a in "$@"; do
    case "$a" in
        --no-packages) packages=false ;;
        -h|--help) sed -n '2,12p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) echo "install: I don't know «$a» (--no-packages, --help)" >&2; exit 2 ;;
    esac
done
say() { printf '\033[1;36msetup ·\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33msetup ·\033[0m %s\n' "$*" >&2; }
[ "$(id -u)" -ne 0 ] || { echo "install: run it as yourself, not root (it uses sudo where it must)" >&2; exit 1; }
command -v pacman >/dev/null || { echo "install: this is for Arch-based systems (pacman)" >&2; exit 1; }
[ -d "$here/home" ] || { echo "install: $here/home is missing: run setup/capture.sh on the old machine first" >&2; exit 1; }

# ── 1. Packages ──────────────────────────────────────────────────────────────────────────────────
# What the repos you have offer is installed; anything they do not (another distribution's repo, a
# package since renamed) is listed at the end rather than stopping everything. Then the AUR's, with
# paru or yay (paru is built from the AUR if neither is there).
missing=""
if $packages; then
    say "packages: updating and installing from the repositories (sudo)"
    # -Syu, not -Sy: Arch does not support installing onto a partly upgraded system. Unattended on
    # purpose; run with --no-packages to manage packages yourself.
    sudo pacman -Syu --needed --noconfirm base-devel git rsync
    avail=$(mktemp)
    pacman -Slq | sort -u > "$avail"
    have=$(grep -Fxf "$avail" "$here/packages.pacman" || :)
    missing=$(grep -Fvxf "$avail" "$here/packages.pacman" | tr '\n' ' ' || :)
    rm -f "$avail"
    [ -z "$have" ] || printf '%s\n' "$have" | sudo pacman -S --needed --noconfirm -
    # Iosevka Nerd Font was not copied (690 MB): it is a package
    sudo pacman -S --needed --noconfirm ttf-iosevka-nerd 2>/dev/null || warn "ttf-iosevka-nerd not found; the bar's icons fall back"
    # the widgets read the wallpaper with ImageMagick and cut its subject out with rembg via uv (D139);
    # both come in as dependencies here, so the captured list does not name them
    sudo pacman -S --needed --noconfirm imagemagick uv python || warn "imagemagick / uv not installed; the widgets will not read the wallpaper"
    # the wallpapers (D145): the picker's index reads them with Pillow, a video's frame with ffmpeg,
    # and mpvpaper (from the AUR list) plays a video wallpaper under mooi's desk
    sudo pacman -S --needed --noconfirm python-pillow ffmpeg jq || warn "python-pillow / ffmpeg not installed; the wallpaper picker cannot read the folders"
    helper=""
    for h in paru yay; do command -v "$h" >/dev/null && { helper=$h; break; }; done
    if [ -z "$helper" ]; then
        say "packages: building paru for the AUR"
        tmp=$(mktemp -d)
        git clone --quiet https://aur.archlinux.org/paru-bin.git "$tmp/paru-bin"
        (cd "$tmp/paru-bin" && makepkg -si --noconfirm)
        rm -rf "$tmp"
        helper=paru
    fi
    say "packages: from the AUR with $helper"
    # one at a time, so one that no longer builds does not take the rest with it
    while IFS= read -r p; do
        [ -n "$p" ] || continue
        pacman -Qq "$p" >/dev/null 2>&1 && continue
        "$helper" -S --needed --noconfirm "$p" >/dev/null 2>&1 || missing="$missing $p(aur)"
    done < "$here/packages.aur"
    # rembg, for the widgets' depth (D139): its own Python 3.13 (onnxruntime trails the system's)
    if ! command -v rembg >/dev/null; then
        if command -v uv >/dev/null; then
            say "packages: rembg (the wallpaper's subject cut out, for widgets behind it)"
            uv tool install --python 3.13 "rembg[cpu,cli]" >/dev/null 2>&1 || missing="$missing rembg(uv)"
        else
            missing="$missing rembg(uv)"
        fi
    fi
fi

# ── 2. pleamar, at the commit this desktop ran on ────────────────────────────────────────────────
url=$(cut -d' ' -f1 "$here/pleamar.ref"); ref=$(cut -d' ' -f2 "$here/pleamar.ref")
src="${XDG_DATA_HOME:-$HOME/.local/share}/pleamar/src"
say "pleamar: $url at ${ref%"${ref#???????}"}"
# rustup puts a `cargo` in place that does nothing until a toolchain is chosen
if command -v rustup >/dev/null && ! rustup default >/dev/null 2>&1; then rustup default stable; fi
command -v cargo >/dev/null || { echo "install: cargo is needed to build pleamar (pacman -S rustup; rustup default stable)" >&2; exit 1; }
mkdir -p "$src"
[ -d "$src/pleamar/.git" ] || git clone --quiet "$url" "$src/pleamar"
git -C "$src/pleamar" fetch --quiet origin
git -C "$src/pleamar" -c advice.detachedHead=false checkout --quiet "$ref"
if [ "$(git -C "$src/pleamar" rev-parse HEAD)" != "$(cat "$src/pleamar/target/.setup-built" 2>/dev/null)" ] || [ ! -x "$src/pleamar/target/release/pleamar" ]; then
    (cd "$src/pleamar" && cargo build --release --quiet)
    git -C "$src/pleamar" rev-parse HEAD > "$src/pleamar/target/.setup-built"
fi
mkdir -p "$HOME/.local/bin"
install -m755 "$src/pleamar/target/release/pleamar" "$HOME/.local/bin/pleamar.new" && mv -f "$HOME/.local/bin/pleamar.new" "$HOME/.local/bin/pleamar"
install -m755 "$src/pleamar/install.sh" "$HOME/.local/bin/pleamar-update"
echo "$src" > "$HOME/.local/bin/.pleamar-src"
: > "$HOME/.local/bin/.pleamar-alone"

# ── 3. The files: config, mooi's state, fonts, themes ────────────────────────────────────────────
backup="$HOME/.setup-backup-$(date +%Y%m%d-%H%M%S)"
say "files: into your home (what they replace goes to $backup)"
# each top-level thing the capture holds (~/.config/hypr, ~/.local/share/fonts, …) is replaced whole,
# so nothing of an old config is left mixed into the new one
# (read line by line, not split by the shell: a name with a space in it stays one name; fourth pass, L12)
(cd "$here/home" && find . -mindepth 1 -maxdepth 3 \( -path './.config/*' -o -path './.local/share/*' -o -path './.icons' -o -path './.themes' \) -prune -print | sed 's|^\./||') > "$backup.list" || exit 1
while IFS= read -r item <&3; do
    case "$item" in .local/share/pleamar) continue ;; esac
    if [ -e "$HOME/$item" ] || [ -L "$HOME/$item" ]; then
        mkdir -p "$backup/$(dirname "$item")"
        mv "$HOME/$item" "$backup/$item"
    fi
    mkdir -p "$HOME/$(dirname "$item")"
    cp -a "$here/home/$item" "$HOME/$item"
done 3< "$backup.list"
rm -f "$backup.list"
# mooi's state folder: its files laid over, never the whole folder (caches and pictures it makes stay)
mkdir -p "$HOME/.local/share/pleamar/mooi"
if [ -d "$HOME/.local/share/pleamar/mooi" ] && [ -n "$(ls -A "$HOME/.local/share/pleamar/mooi" 2>/dev/null)" ]; then
    mkdir -p "$backup/.local/share/pleamar" && cp -a "$HOME/.local/share/pleamar/mooi" "$backup/.local/share/pleamar/"
fi
cp -a "$here/home/.local/share/pleamar/mooi/." "$HOME/.local/share/pleamar/mooi/"
fc-cache -f >/dev/null 2>&1 || :
if [ -f "$here/home/.gsettings" ] && command -v gsettings >/dev/null 2>&1; then
    while read -r k v; do
        [ -n "$v" ] && gsettings set org.gnome.desktop.interface "$k" "$(printf '%s' "$v" | tr -d "'")" 2>/dev/null || :
    done < "$here/home/.gsettings"
fi

# ── 4. mooi where Hyprland looks for it ──────────────────────────────────────────────────────────
# (~/.config/hypr/config/custom/mooi.lua runs ~/Projects/mooi/bin/mooi)
if [ "$root" != "$HOME/Projects/mooi" ]; then
    if [ -e "$HOME/Projects/mooi" ]; then
        warn "mooi is at $root but Hyprland runs ~/Projects/mooi, which is something else: move one of them"
    else
        mkdir -p "$HOME/Projects" && ln -s "$root" "$HOME/Projects/mooi"
        say "linked ~/Projects/mooi → $root"
    fi
fi
"$root/bin/mooi" check >/dev/null 2>&1 || warn "\`mooi check\` found something missing: run it to see what"

# ── 5. The login screen ──────────────────────────────────────────────────────────────────────────
if $packages && pacman -Qq sddm >/dev/null 2>&1; then
    sudo systemctl enable sddm >/dev/null 2>&1 && say "login screen: sddm enabled"
fi

say "done. Log out, choose the Hyprland session, and mooi starts with it."
[ -d "$HOME/Pictures/wallpapers" ] || warn "your wallpapers (~/Pictures/wallpapers, 8 GB) are not in the repo: copy them over from a backup"
[ -n "$(printf '%s' "$missing" | tr -d ' ')" ] && warn "not installed (not in your repositories, or the AUR build failed): $missing"
warn "not restored: the kernel's command line (/etc/kernel/cmdline) and other system files; see setup/README.md"
exit 0
