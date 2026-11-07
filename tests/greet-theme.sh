#!/bin/sh
# The login screen in mooi's palette (D190), without a greeter installed: `bin/mooi greet-theme`
# writes sysc-greet's theme from palette.json — the eleven roles it insists on, each taken from the
# token mooi means, and the name the greeter follows — and a recolour rewrites it. A palette that
# lost a token still leaves a complete theme, because sysc-greet refuses a theme with a field
# missing. Where no greeter folder exists (or it cannot be written) the command says so, exits 1 and
# writes nothing. `theme_sync` calls the same writer, which is what makes a recolour reach it.
# Nothing of the real data folder, ~/.config or /var is read or written.
# Run from anywhere: tests/greet-theme.sh
set -u
root=$(cd "$(dirname "$0")/.." && pwd)
command -v jq >/dev/null 2>&1 || { echo "greet-theme: jq is required"; exit 2; }
t=$(mktemp -d); trap 'chmod -R u+rwX "$t" 2>/dev/null; rm -rf "$t"' EXIT
export HOME="$t/home" XDG_CONFIG_HOME="$t/config" XDG_DATA_HOME="$t/data" \
    XDG_STATE_HOME="$t/state" XDG_RUNTIME_DIR="$t/run"
D=$XDG_DATA_HOME/pleamar/mooi; T=$t/theme
mkdir -p "$D" "$T" "$HOME" "$XDG_RUNTIME_DIR"
fail=0; n=0
ok()  { n=$((n + 1)); echo "  ok    $1"; }
bad() { n=$((n + 1)); fail=$((fail + 1)); echo "  FAIL  $1"; }
is()  { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1 ('$2', expected '$3')"; fi; }
theme() { # MODE, then the palette's own entry, as Matugen writes them
    printf '{"version":1,"mode":"%s","colours":{%s}}' "$1" "$2" > "$D/palette.json"
}
write() { MOOI_SYSC_THEME_DIR="$T" bash "$root/bin/mooi" greet-theme 2>&1; }
field() { sed -n 's/^'"$1"' = "\(.*\)"$/\1/p' "$T/mooi.toml"; }
roles() { grep -c '^[a-z_]* = "#[0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f]"$' "$T/mooi.toml"; }
dark='"surface_dim":"#101418","surface_container_high":"#283039","outline":"#8b96a3","on_surface":"#e3e6ea","on_surface_variant":"#bcc4ce","primary":"#7fc8a9","secondary":"#7aa7d9","tertiary":"#d9a86c","error":"#ffb4ab"'

echo "a palette becomes the greeter's theme: the eleven roles sysc-greet requires"
theme dark "$dark"
out=$(write)
case $out in *"wears mooi's palette"*) ok "it says what it did" ;; *) bad "it says what it did ('$out')" ;; esac
is "the theme is named for the menu" "$(sed -n 's/^name = "\(.*\)"$/\1/p' "$T/mooi.toml")" "Mooi"
is "and the follow file names it" "$(cat "$T/theme" 2>/dev/null)" "Mooi"
is "the name file is the name and nothing else" "$(wc -c < "$T/theme")" "5"
is "all eleven roles, no more" "$(roles)" "11"
is "the folder holds the theme and its name" "$(ls "$T" | sort | tr '\n' ' ')" "mooi.toml theme "

echo "the mapping: mooi's tokens, not sysc-greet's own colours"
is "base is the dimmest surface" "$(field bg_base)" "#101418"
is "the active row is the highest container" "$(field bg_active)" "#283039"
is "the primary" "$(field primary)" "#7fc8a9"
is "the secondary" "$(field secondary)" "#7aa7d9"
is "the accent is the tertiary" "$(field accent)" "#d9a86c"
is "warning is the tertiary too: mooi keeps no warn role" "$(field warning)" "#d9a86c"
is "danger is the ember" "$(field danger)" "#ffb4ab"
is "words" "$(field fg_primary)" "#e3e6ea"
is "second words" "$(field fg_secondary)" "#bcc4ce"
is "muted words are the outline" "$(field fg_muted)" "#8b96a3"
is "the focus ring is the primary" "$(field border_focus)" "#7fc8a9"

echo "the same state in Settings: one line, and the command that answers it"
is "followed here" "$(MOOI_SYSC_THEME_DIR="$T" bash "$root/bin/mooi" greet-theme --status)" "Mooi · followed"
rm -f "$T/theme"
is "the greeter has another theme" "$(MOOI_SYSC_THEME_DIR="$T" bash "$root/bin/mooi" greet-theme --status)" "Mooi · not followed"
printf 'Mooi\n' > "$T/theme"
is "no greeter at all" "$(MOOI_SYSC_THEME_DIR="$t/none" bash "$root/bin/mooi" greet-theme --status)" "not set up (setup/install.sh)"
if grep -q 'The login screen' "$root/shell/mooi-settings.plm"; then ok "the Theme & colour page has the card"; else bad "the Theme & colour page has the card"; fi
if grep -q 'text gr_theme { at:' "$root/shell/mooi-settings.plm"; then ok "the window draws the fact"; else bad "the window draws the fact"; fi
# an info row is a reading, not a setting: it is on its page and in the window, and (like the
# Advanced page's Version and Power's Charge) deliberately not among the search's rows
if grep -q 'What it wears' "$root/shell/lib/settings_index.luau"; then bad "a reading stays out of the settings search"; else ok "a reading stays out of the settings search"; fi
if grep -q 'greet-theme", "--status"' "$root/shell/mooi-settings.luau"; then ok "and asks the script for it"; else bad "and asks the script for it"; fi

echo "a recolour rewrites it, and a token the palette lost still leaves a whole theme"
theme dark '"surface_dim":"#000000","primary":"#12ab34","on_surface":"#ffffff","error":"#ff0000"'
write >/dev/null
is "the primary follows the palette" "$(field primary)" "#12ab34"
is "a token it no longer carries falls back" "$(field bg_active)" "#2b2930"
is "the warning falls back too, not to nothing" "$(field warning)" "#e6b450"
is "still eleven roles: a theme missing one is refused by the greeter" "$(roles)" "11"

echo "day is the same theme with the day's palette"
theme light '"surface_dim":"#f6f3ee","primary":"#3f6f52","on_surface":"#1b1c18","error":"#ba1a1a"'
write >/dev/null
is "a light base" "$(field bg_base)" "#f6f3ee"
is "dark words on it" "$(field fg_primary)" "#1b1c18"

echo "a folder that cannot be written: a word, exit 1, and the last good theme kept"
chmod 500 "$T"
before=$(cat "$T/mooi.toml")
theme dark '"primary":"#deadbe"'
out=$(write); code=$?
is "it exits 1" "$code" "1"
case $out in *"no writable greeter theme folder"*) ok "it says why" ;; *) bad "it says why ('$out')" ;; esac
is "the theme on disk is the last good one" "$(cat "$T/mooi.toml")" "$before"
chmod 700 "$T"

echo "a machine with no greeter: a word, and nothing written"
rm -rf "$T"
out=$(MOOI_SYSC_THEME_DIR="$T" bash "$root/bin/mooi" greet-theme 2>&1); code=$?
is "it exits 1" "$code" "1"
case $out in *"no writable greeter theme folder"*) ok "it says where the folder comes from" ;; *) bad "it says where the folder comes from ('$out')" ;; esac
if [ -e "$T/mooi.toml" ]; then bad "nothing was written"; else ok "nothing was written"; fi

echo "and the lock brings it along: the login screen behind it wears the palette it covers"
if sed -n '/^lock_start()/,/^}/p' "$root/bin/mooi" | grep -q 'greet_theme'; then
    ok "lock_start refreshes the theme before the lock comes up"
else bad "lock_start refreshes the theme before the lock comes up"; fi

echo "and a recolour brings it along: theme_sync calls the same writer"
if sed -n '/^theme_sync()/,/^}/p' "$root/bin/mooi" | grep -q 'greet_theme'; then
    ok "theme_sync calls greet_theme"
else bad "theme_sync calls greet_theme"; fi
if grep -q 'MOOI_SYSC_THEME_DIR' "$root/bin/mooi"; then ok "the folder can be pointed elsewhere"; else bad "the folder can be pointed elsewhere"; fi

echo
echo "$n checks, $fail failed"
[ "$fail" -eq 0 ]
