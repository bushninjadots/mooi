#!/bin/sh
# setup/greeter.sh — the login screen on its own: greetd running sysc-greet's Hyprland greeter, in
# place of sddm (D190). setup/install.sh runs it as its last step; run it alone to set the login
# screen up again (a theme to re-link, sddm turned back on, a machine that skipped the step).
#
#   setup/greeter.sh              the greeter's account and folders, /etc/greetd/config.toml (a
#                                 foreign one kept beside it), the theme link, sddm off, greetd on
#   setup/greeter.sh --dry-run    the same, into a scratch folder: nothing is installed, nothing in
#                                 /etc is touched, no sudo, no service changed
#   setup/greeter.sh --help
#
# A dry run writes where MOOI_GREETER_ROOT says (a temporary folder by default) and takes sysc-greet
# as installed; anything that would need root is printed as `would: …`. tests/setup-greeter.sh runs
# it, so the config this step writes can be checked without root.
set -eu
here=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$here/.." && pwd)
dry=false
for a in "$@"; do
    case "$a" in
        --dry-run) dry=true ;;
        -h|--help) sed -n '2,14p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) echo "greeter: I don't know «$a» (--dry-run, --help)" >&2; exit 2 ;;
    esac
done
say() { printf '\033[1;36msetup ·\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33msetup ·\033[0m %s\n' "$*" >&2; }

if $dry; then
    scratch=${MOOI_GREETER_ROOT:-$(mktemp -d)}
    greetd_dir=$scratch/etc/greetd
    greeter_home=$scratch/var/lib/greeter
    cache_dir=$scratch/var/cache/sysc-greet
    theme_dir=$scratch/var/lib/sysc-greet/shell-theme
    themes_dir=$scratch/usr/share/sysc-greet/themes
    mkdir -p "$themes_dir" "$greetd_dir" "$theme_dir" "$greeter_home" "$cache_dir"
    say "login screen: a dry run into $scratch — nothing is installed, written to /etc, or enabled"
elif ! command -v sysc-greet >/dev/null 2>&1; then
    warn "sysc-greet is not installed (sysc-greet-hyprland, from the AUR): the login screen is as it was"
    exit 0
else
    greetd_dir=/etc/greetd
    greeter_home=/var/lib/greeter
    cache_dir=/var/cache/sysc-greet
    theme_dir=/var/lib/sysc-greet/shell-theme
    themes_dir=/usr/share/sysc-greet/themes
fi
# Root-only work — the account, ownership, the services — is printed in a dry run. The file work
# below is real either way, because in a dry run it happens inside the scratch folder, which is the
# point: the config that would land in /etc can be read and checked.
as() { if $dry; then printf '  would: %s\n' "$*"; else "$@"; fi; }
if $dry; then
    cp_root() { cp -a "$1" "$2"; }
    ln_root() { ln -s "$1" "$2"; }
else
    cp_root() { sudo cp -a "$1" "$2"; }
    ln_root() { sudo ln -s "$1" "$2"; }
fi

say "login screen: greetd with sysc-greet (in place of sddm)"
if ! id greeter >/dev/null 2>&1; then
    if $dry; then
        printf '  would: sudo useradd -M -d /var/lib/greeter -G video,render,input -s /usr/bin/nologin greeter\n'
    else
        sudo useradd -M -d /var/lib/greeter -G video,render,input -s /usr/bin/nologin greeter
    fi
fi
as sudo mkdir -p "$cache_dir" "$greeter_home/Pictures/wallpapers" \
    "$greeter_home/.cache" "$greeter_home/.config" "$greeter_home/.local/state"
as sudo chown -R greeter:greeter "$cache_dir" "$greeter_home"
as sudo chmod 755 "$greeter_home"
# The greeter's own Lua config comes from the package: it starts fullscreen kitty and asks Hyprland to
# quit when kitty does.
if $dry; then
    printf '  would: look for /etc/greetd/hyprland-greeter-config.lua (the AUR package installs it)\n'
elif [ ! -f "$greetd_dir/hyprland-greeter-config.lua" ]; then
    warn "sysc-greet-hyprland installed without /etc/greetd/hyprland-greeter-config.lua: reinstall it from the AUR"
fi
# A config that already runs this greeter is kept. Anything else — the stock agreety one, another
# greeter, or the one this machine had (two [default_session] tables, which greetd cannot parse) — is
# kept beside it and replaced: enabling greetd over a config it rejects boots to a black screen.
cfg=$greetd_dir/config.toml
if ! grep -qs 'hyprland-greeter-config' "$cfg"; then
    if [ -e "$cfg" ]; then
        cp_root "$cfg" "$cfg.before-mooi-$(date +%Y-%m-%d)" \
            && say "login screen: the old $cfg is kept beside it"
    fi
    tmp=$(mktemp)
    cat > "$tmp" <<'GREETD'
[terminal]
vt = 1

[default_session]
command = "start-hyprland -- --config /etc/greetd/hyprland-greeter-config.lua"
user = "greeter"
GREETD
    if $dry; then install -m644 "$tmp" "$cfg"; else sudo install -Dm644 "$tmp" "$cfg"; fi
    rm -f "$tmp"
    say "login screen: wrote $cfg"
fi
# The greeter picks its colours from a theme it finds by name: /var/lib/sysc-greet/shell-theme is the
# one folder it reads that its own user does not need root to rewrite, and upstream's installer makes
# it owned by the person at the keyboard for exactly that reason. `mooi greet-theme` writes the
# palette there, and the system-wide theme file is a link to it, so a recolour reaches the login screen
# with no password. Follow sysc-shell is on in its F1 menu by default.
theme_user=${SUDO_USER:-$(id -un)}
as sudo mkdir -p "$theme_dir"
as sudo chown "$theme_user": "$theme_dir"
as sudo chmod 755 "$theme_dir"
link=$themes_dir/mooi.toml
if [ ! -e "$link" ] && [ ! -L "$link" ]; then
    ln_root "$theme_dir/mooi.toml" "$link" \
        && say "login screen: mooi's theme linked into sysc-greet's themes"
fi
MOOI_SYSC_THEME_DIR="$theme_dir" "$root/bin/mooi" greet-theme >/dev/null 2>&1 || :
if $dry; then
    printf '  would: sudo systemctl disable sddm\n  would: sudo systemctl enable greetd\n'
else
    sudo systemctl disable sddm >/dev/null 2>&1 || :
    sudo systemctl enable greetd >/dev/null 2>&1 && say "login screen: greetd enabled"
fi
