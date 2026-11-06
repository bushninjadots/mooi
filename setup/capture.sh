#!/bin/sh
# Capture the shareable desktop configuration into setup/home — a public starting point for anyone,
# never a copy of the author. Per-user state (notes, board, identity, settings, caches, project lists,
# bookmarks, credentials) stays local, home paths become @HOME@ (install.sh puts the installer's own
# back), and the capture refuses to finish while anything still names the person who ran it.
#
# The author's full package lists (everything this machine has installed, hardware included) go to
# setup/personal/, which is gitignored: `install.sh --personal` restores this exact machine from a
# local checkout, while the public lists (setup/packages.*) stay curated to what mooi needs.
set -eu
root=$(cd "$(dirname "$0")/.." && pwd)
out="$root/setup/home"
personal="$root/setup/personal"
command -v rsync >/dev/null || { echo "capture: rsync is needed (pacman -S rsync)" >&2; exit 1; }

CONFIG="hypr desktop-widgets kitty matugen environment.d pleamar gtk-3.0 gtk-4.0 qt5ct qt6ct"
# Runtime state and personal files, wherever they sit in those folders.
EXCLUDE="--exclude=.git --exclude=.gitignore --exclude=__pycache__ --exclude=node_modules --exclude=*.log --exclude=.cache
 --exclude=*.bak --exclude=*.bak-* --exclude=*.bak.* --exclude=bak-* --exclude=*.before-* --exclude=*.orig
 --exclude=AGENTS.md --exclude=CLAUDE.md --exclude=.claude
 --exclude=hypr/wallpapers --exclude=hypr/legacy --exclude=hypr/evremap
 --exclude=hypr/config/custom/browser.lua --exclude=hypr/config/custom/discord_client.lua
 --exclude=pleamar/shells --exclude=kitty/sidecar/state --exclude=gtk-3.0/bookmarks
 --exclude=desktop-widgets/docs"

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

# Neutral starter state for mooi: never the user's notes, board, settings, identity or caches.
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

# ── Make it nobody's ──────────────────────────────────────────────────────────────────────────────
# pleamar's autostart names shells that are not captured; their lines would fail on another machine.
auto="$out.new/.config/pleamar/autostart"
[ -f "$auto" ] && { grep -v '/\.config/pleamar/shells/' "$auto" > "$auto.new" || :; mv "$auto.new" "$auto"; }
# The GitHub heatmap widget starts with no account: the installer's own is theirs to type.
w="$out.new/.config/desktop-widgets/settings/widgets.json"
if [ -f "$w" ] && command -v jq >/dev/null 2>&1; then
    jq '.heatmapUsername = ""' "$w" > "$w.new" && mv "$w.new" "$w"
fi
# Every home path becomes @HOME@; install.sh writes the installer's home in its place.
home_re=$(printf '%s' "$HOME" | sed 's/[][\.*^$|/]/\\&/g')
grep -rIl -- "$HOME" "$out.new" 2>/dev/null | while IFS= read -r f; do
    sed -i "s|$home_re|@HOME@|g" "$f"
done
# The author's GitHub login, where it is only an example or a default, becomes GitHub's own example.
login=$(gh api user -q .login 2>/dev/null || :)
if [ -n "$login" ]; then
    grep -rIlw -- "$login" "$out.new" 2>/dev/null | while IFS= read -r f; do
        sed -i "s/\\b$login\\b/octocat/g" "$f"
    done
fi

# ── Refuse what still names someone ─────────────────────────────────────────────────────────────
# Credentials, and the identity of whoever ran this: their user name in a path, their git name and
# email, their GitHub login. Anything found stops the capture and nothing is replaced.
creds='(gh[pousr]_[A-Za-z0-9]{30,}|github_pat_[A-Za-z0-9_]{30,}|sk-ant-[A-Za-z0-9_-]{20,}|sk-[A-Za-z0-9]{32,}|AKIA[0-9A-Z]{16}|-----BEGIN [A-Z ]*PRIVATE KEY)'
who="/home/$(id -un)"
for v in "$(git config user.email 2>/dev/null || :)" "$(git config user.name 2>/dev/null || :)" "$login"; do
    [ -n "$v" ] && who="$who|$(printf '%s' "$v" | sed 's/[][\.*^$|(){}+?]/\\&/g')"
done
set +e
hits=$(grep -rIlE "$creds" "$out.new"; grep -rIliE -- "$who" "$out.new")
rc=$?
set -e
if [ -n "$hits" ]; then
    echo "capture: these hold a credential or name you ($who); nothing was replaced:" >&2
    printf '%s\n' "$hits" | sort -u >&2
    rm -rf "$out.new"; exit 1
fi
[ "$rc" -le 1 ] || { echo "capture: the privacy scan could not run; nothing was replaced" >&2; rm -rf "$out.new"; exit 1; }

# This machine's full package lists, for `install.sh --personal`: local only (setup/personal is ignored).
mkdir -p "$personal"
pacman -Qqen > "$personal/packages.pacman" 2>/dev/null || :
pacman -Qqem > "$personal/packages.aur" 2>/dev/null || :
src="${XDG_DATA_HOME:-$HOME/.local/share}/pleamar/src/pleamar"
if [ -d "$src/.git" ]; then
    printf '%s %s\n' "$(git -C "$src" remote get-url origin)" "$(git -C "$src" rev-parse HEAD)" > "$root/setup/pleamar.ref"
fi

rm -rf "$out" && mv "$out.new" "$out"
echo "captured shareable setup into setup/: $(du -sh "$out" | cut -f1)"
