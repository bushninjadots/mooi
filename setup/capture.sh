#!/bin/sh
# Capture only shareable desktop configuration. Per-user state (notes, board,
# identity, settings, caches and credentials) stays local and is intentionally not
# kept in the public repo. The checked-in files are a clean default, not a copy of
# this machine's runtime state.
set -eu
root=$(cd "$(dirname "$0")/.." && pwd)
out="$root/setup/home"
command -v rsync >/dev/null || { echo "capture: rsync is needed (pacman -S rsync)" >&2; exit 1; }

# keep shareable config only; runtime state is excluded from capture.
CONFIG="hypr desktop-widgets kitty matugen environment.d pleamar gtk-3.0 gtk-4.0 qt5ct qt6ct"
EXCLUDE="--exclude=.git --exclude=.gitignore --exclude=hypr/wallpapers --exclude=hypr/legacy --exclude=*.bak --exclude=*.before-* \
 --exclude=pleamar/shells --exclude=__pycache__ --exclude=node_modules --exclude=*.log --exclude=.cache"

rm -rf "$out.new"
mkdir -p "$out.new/.config" "$out.new/.local/share/pleamar/mooi"
dead=$(mktemp)
for d in $CONFIG; do
    [ -e "$HOME/.config/$d" ] || { echo "capture: ~/.config/$d is not here; skipped" >&2; continue; }
    (cd "$HOME/.config" && find "$d" -xtype l) | sed 's|^|/|' > "$dead"
    # shellcheck disable=SC2086
    rsync -a --copy-unsafe-links --exclude-from="$dead" $EXCLUDE "$HOME/.config/$d" "$out.new/.config/"
done
rm -f "$dead"

# Replace the live state directory with neutral defaults. This is a starting point,
# never a copy of the user's notes, board, settings, identity or caches.
cat > "$out.new/.local/share/pleamar/mooi/settings.json" <<'JSON'
{"version":2}
JSON
cat > "$out.new/.local/share/pleamar/mooi/notes.json" <<'JSON'
{"notes":[],"version":1}
JSON
cat > "$out.new/.local/share/pleamar/mooi/board.json" <<'JSON'
{"archive":[],"cards":[],"columns":[{"id":1,"title":"To do","wip":0},{"id":2,"title":"Doing","wip":0},{"id":3,"title":"Done","wip":0}],"next_id":1,"version":1}
JSON
cat > "$out.new/.local/share/pleamar/mooi/stash.json" <<'JSON'
{"folders":[],"items":[],"version":1}
JSON

mkdir -p "$out.new/.local/share"
[ -d "$HOME/.local/share/fonts" ] && rsync -a --exclude=.git --exclude=IosevkaNerdFont --exclude=iosevka-nerd-font.ttf "$HOME/.local/share/fonts" "$out.new/.local/share/"
for d in .icons .themes; do [ -d "$HOME/$d" ] && rsync -a --exclude=.git "$HOME/$d" "$out.new/"; done
if command -v gsettings >/dev/null 2>&1; then
    for k in icon-theme cursor-theme gtk-theme color-scheme font-name; do
        printf '%s %s\n' "$k" "$(gsettings get org.gnome.desktop.interface "$k" 2>/dev/null)"
    done > "$out.new/.gsettings"
fi

# Credentials never go in: a file that looks like it holds one stops the capture.
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

pacman -Qqen > "$root/setup/packages.new.pacman" 2>/dev/null || :
pacman -Qqem > "$root/setup/packages.new.aur" 2>/dev/null || :
src="${XDG_DATA_HOME:-$HOME/.local/share}/pleamar/src/pleamar"
if [ -d "$src/.git" ]; then
    printf '%s %s\n' "$(git -C "$src" remote get-url origin)" "$(git -C "$src" rev-parse HEAD)" > "$root/setup/pleamar.ref"
fi
mv "$root/setup/packages.new.pacman" "$root/setup/packages.pacman"
mv "$root/setup/packages.new.aur" "$root/setup/packages.aur"

rm -rf "$out" && mv "$out.new" "$out"
echo "captured shareable setup into setup/: $(du -sh "$out" | cut -f1)"
