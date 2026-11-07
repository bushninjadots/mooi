#!/bin/sh
# setup/install.sh — put mooi's desktop on a fresh Arch-based system (EndeavourOS, Arch): the packages
# mooi needs, pleamar at the commit mooi was built against, Hyprland's config and its helpers, mooi's
# neutral starting state, the fonts and themes, and the login screen. Nothing in it is anyone's own:
# no settings, notes, pictures or accounts — you start from defaults and sign in to your own services.
#
#   git clone https://github.com/bushninjadots/mooi.git ~/Projects/mooi
#   ~/Projects/mooi/setup/install.sh                 everything
#   ~/Projects/mooi/setup/install.sh --no-packages   the files only (packages already there)
#   ~/Projects/mooi/setup/install.sh --personal      the author's own machine: the full package lists
#                                                    setup/capture.sh keeps in setup/personal/ (local only)
#   ~/Projects/mooi/setup/install.sh --dry-run       the login screen's step only, printed into a
#                                                    scratch folder: nothing installed or changed
#
# Whatever it replaces in your home is moved, not deleted, to ~/.setup-backup-<date>/ first.
# Run it as yourself (it asks for sudo for packages and the login screen). Then log out and pick the
# Hyprland session: mooi starts with it.
set -eu
here=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$here/.." && pwd)
packages=true
personal=false
dry=false
for a in "$@"; do
    case "$a" in
        --no-packages) packages=false ;;
        --personal) personal=true ;;
        --dry-run) dry=true ;;
        -h|--help) sed -n '2,14p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) echo "install: I don't know «$a» (--no-packages, --personal, --dry-run, --help)" >&2; exit 2 ;;
    esac
done
say() { printf '\033[1;36msetup ·\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33msetup ·\033[0m %s\n' "$*" >&2; }
[ "$(id -u)" -ne 0 ] || { echo "install: run it as yourself, not root (it uses sudo where it must)" >&2; exit 1; }
# --dry-run is the login screen's step and nothing else: steps 1–4 install packages and write into the
# home, and a preview of those is not a preview — it is the same work. The greeter's step is config
# and accounts, and it can say exactly what it would do (setup/greeter.sh --dry-run). It installs
# nothing, so it does not need pacman (CI runs it on Ubuntu: the check came first and failed it, D206).
if $dry; then
    sh "$here/greeter.sh" --dry-run
    exit 0
fi
command -v pacman >/dev/null || { echo "install: this is for Arch-based systems (pacman)" >&2; exit 1; }
[ -d "$here/home" ] || { echo "install: $here/home is missing: run setup/capture.sh on the old machine first" >&2; exit 1; }

# ── 1. Packages ──────────────────────────────────────────────────────────────────────────────────
# What the repos you have offer is installed; anything they do not (another distribution's repo, a
# package since renamed) is listed at the end rather than stopping everything. Then the AUR's, with
# paru or yay (paru is built from the AUR if neither is there).
missing=""
# The public lists are what mooi needs; --personal reads the author's full lists instead, which only
# exist in a checkout where setup/capture.sh ran (setup/personal/ is never committed).
list_pacman="$here/packages.pacman" list_aur="$here/packages.aur"
if $personal; then
    [ -f "$here/personal/packages.pacman" ] || { echo "install: --personal needs setup/personal/ (made by setup/capture.sh on your machine)" >&2; exit 1; }
    list_pacman="$here/personal/packages.pacman" list_aur="$here/personal/packages.aur"
fi
wanted() { sed -e 's/#.*//' -e 's/[[:space:]]*$//' -e '/^$/d' "$1" 2>/dev/null; }
if $packages; then
    say "packages: updating and installing from the repositories (sudo)"
    # -Syu, not -Sy: Arch does not support installing onto a partly upgraded system. Unattended on
    # purpose; run with --no-packages to manage packages yourself.
    sudo pacman -Syu --needed --noconfirm base-devel git rsync
    avail=$(mktemp)
    pacman -Slq | sort -u > "$avail"
    have=$(wanted "$list_pacman" | grep -Fxf "$avail" || :)
    missing=$(wanted "$list_pacman" | grep -Fvxf "$avail" | tr '\n' ' ' || :)
    rm -f "$avail"
    [ -z "$have" ] || printf '%s\n' "$have" | sudo pacman -S --needed --noconfirm -
    # the widgets cut the wallpaper's subject out with rembg, through uv (D139): optional
    sudo pacman -S --needed --noconfirm uv 2>/dev/null || warn "uv not installed; the widgets will not cut out the wallpaper's subject"
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
    done <<EOF
$(wanted "$list_aur")
EOF
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
home_sed=$(printf '%s' "$HOME" | sed 's/[&|\\]/\\&/g')
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
    # the capture wrote @HOME@ where the author's home was: this is yours
    grep -rIl -- '@HOME@' "$HOME/$item" 2>/dev/null | while IFS= read -r f; do
        sed -i "s|@HOME@|$home_sed|g" "$f"
    done
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

# ── 5. The login screen: greetd runs sysc-greet's Hyprland greeter ───────────────────────────────
# The step is a script of its own (setup/greeter.sh, D190): the greeter's account and folders, the
# greetd config (a foreign one kept beside it), the theme and its link, then sddm off and greetd on.
# Run that on its own to set the login screen up again; `setup/greeter.sh --dry-run` — which
# `install.sh --dry-run` reaches — writes it all into a scratch folder, printing what would need root.
if $packages; then
    sh "$here/greeter.sh"
fi

say "done. Log out, choose the Hyprland session, and mooi starts with it."
[ -d "$HOME/Pictures/wallpapers" ] || warn "no wallpapers yet: put pictures in ~/Pictures/wallpapers (or pick a folder in Settings → Wallpapers)"
[ -n "$(printf '%s' "$missing" | tr -d ' ')" ] && warn "not installed (not in your repositories, or the AUR build failed): $missing"
warn "not restored: the kernel's command line (/etc/kernel/cmdline) and other system files; see setup/README.md"
exit 0
