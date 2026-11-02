#!/bin/sh
# setup/capture.sh — copy this machine's desktop into the repo, so `setup/install.sh` can rebuild it
# on another one exactly. Run it before committing whenever the desktop changed (`mooi setup-capture`
# does). What is taken is the list below and nothing else; caches, generated files, wallpapers and
# credentials stay out. The repo is private: your own settings and notes come along.
set -eu
root=$(cd "$(dirname "$0")/.." && pwd)
out="$root/setup/home"
data="${XDG_DATA_HOME:-$HOME/.local/share}/pleamar/mooi"
command -v rsync >/dev/null || { echo "capture: rsync is needed (pacman -S rsync)" >&2; exit 1; }

# ~/.config: the compositor, its scripts and helpers, and what the shell's colours are written into
CONFIG="hypr qs-wallpaperpicker desktop-widgets wallpaper-styles kitty matugen environment.d pleamar gtk-3.0 gtk-4.0 qt5ct qt6ct"
# never: the 80 MB of wallpapers kept in hypr, its unread legacy files and backups, pleamar's other shells,
# and the dotfiles repo's own .gitignore files (they would hide files from this repo)
EXCLUDE="--exclude=.git --exclude=.gitignore --exclude=hypr/wallpapers --exclude=hypr/legacy --exclude=*.bak --exclude=*.before-* \
 --exclude=pleamar/shells --exclude=__pycache__ --exclude=node_modules --exclude=*.log --exclude=.cache"

# mooi's own state (~/.local/share/pleamar/mooi): the choices you made, not what it worked out
STATE="settings.json board.json notes.json wallpapers.json environments.json stash.json signals.json workspaces.json
 player-eq.json player-eq-ee.json nexus-anchor.json player-anchor.json notch-state.json bmo-state.json identity mooi-themes"

rm -rf "$out.new"
mkdir -p "$out.new/.config" "$out.new/.local/share/pleamar/mooi"
for d in $CONFIG; do
    [ -e "$HOME/.config/$d" ] || { echo "capture: ~/.config/$d is not here; skipped" >&2; continue; }
    # shellcheck disable=SC2086
    rsync -a $EXCLUDE "$HOME/.config/$d" "$out.new/.config/"
done
for f in $STATE; do
    [ -e "$data/$f" ] && cp -r "$data/$f" "$out.new/.local/share/pleamar/mooi/"
done
# hand-installed fonts (mooi's Share Tech Mono and Exo 2 among them; Iosevka Nerd Font, 690 MB, comes
# as the ttf-iosevka-nerd package instead), the cursors and the GTK theme
mkdir -p "$out.new/.local/share"
[ -d "$HOME/.local/share/fonts" ] && rsync -a --exclude=.git --exclude=IosevkaNerdFont --exclude=iosevka-nerd-font.ttf "$HOME/.local/share/fonts" "$out.new/.local/share/"
for d in .icons .themes; do [ -d "$HOME/$d" ] && rsync -a --exclude=.git "$HOME/$d" "$out.new/"; done
# the desktop's look GTK apps read (icon theme, cursor), as gsettings has it
if command -v gsettings >/dev/null 2>&1; then
    for k in icon-theme cursor-theme gtk-theme color-scheme font-name; do
        printf '%s %s\n' "$k" "$(gsettings get org.gnome.desktop.interface "$k" 2>/dev/null)"
    done > "$out.new/.gsettings"
fi

# Credentials never go in: a file that looks like it holds one stops the capture, and so does a scan
# that could not run (a grep error must not read as "nothing found").
creds='(gh[pousr]_[A-Za-z0-9]{30,}|github_pat_[A-Za-z0-9_]{30,}|sk-ant-[A-Za-z0-9_-]{20,}|sk-[A-Za-z0-9]{32,}|AKIA[0-9A-Z]{16}|-----BEGIN [A-Z ]*PRIVATE KEY)'
set +e
hits=$(grep -rIlE "$creds" "$out.new")
rc=$?
set -e
if [ "$rc" -gt 1 ] || [ -n "$hits" ]; then
    [ "$rc" -gt 1 ] && echo "capture: the credential scan could not run; nothing was replaced" >&2
    [ -n "$hits" ] && { echo "capture: these look like they hold a credential; nothing was replaced:" >&2; echo "$hits" >&2; }
    rm -rf "$out.new"; exit 1
fi

# The packages: what was installed by hand (pacman) and from the AUR, and pleamar's exact commit.
pacman -Qqen > "$root/setup/packages.new.pacman" 2>/dev/null || :
pacman -Qqem > "$root/setup/packages.new.aur" 2>/dev/null || :
src="${XDG_DATA_HOME:-$HOME/.local/share}/pleamar/src/pleamar"
if [ -d "$src/.git" ]; then
    printf '%s %s\n' "$(git -C "$src" remote get-url origin)" "$(git -C "$src" rev-parse HEAD)" > "$root/setup/pleamar.ref"
fi
mv "$root/setup/packages.new.pacman" "$root/setup/packages.pacman"
mv "$root/setup/packages.new.aur" "$root/setup/packages.aur"

rm -rf "$out" && mv "$out.new" "$out"
echo "captured into setup/: $(du -sh "$out" | cut -f1) of config and state, $(wc -l < "$root/setup/packages.pacman") pacman + $(wc -l < "$root/setup/packages.aur") AUR packages, pleamar $(cut -d' ' -f2 "$root/setup/pleamar.ref" | cut -c1-7)"
