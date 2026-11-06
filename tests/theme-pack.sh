#!/bin/sh
# Theme packages from the terminal, without the session: `mooi theme save/list/apply` in a
# throwaway HOME and XDG tree. Checks the package format, the visual boundary, that applying
# replaces only theme settings (layouts and unknown sections stay), that invalid packages are
# refused with the settings untouched, and that safe mode writes nothing.
# Nothing of the real settings, themes or session is read or written.
set -u
root=$(cd "$(dirname "$0")/.." && pwd)
command -v lua5.4 >/dev/null 2>&1 || { echo "theme-pack: lua5.4 is required"; exit 2; }
command -v jq >/dev/null 2>&1 || { echo "theme-pack: jq is required"; exit 2; }
t=$(mktemp -d); trap 'rm -rf "$t"' EXIT
export HOME="$t/home" XDG_DATA_HOME="$t/data" XDG_CONFIG_HOME="$t/config" \
    XDG_STATE_HOME="$t/state" XDG_RUNTIME_DIR="$t/run"
D=$XDG_DATA_HOME/pleamar/mooi
mkdir -p "$D" "$HOME" "$XDG_RUNTIME_DIR" "$XDG_CONFIG_HOME" "$XDG_STATE_HOME"

fail=0; n=0
ok()    { n=$((n + 1)); echo "  ok    $1"; }
bad()   { n=$((n + 1)); fail=$((fail + 1)); echo "  FAIL  $1"; }
is()    { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1 ('$2', expected '$3')"; fi }
has()   { if grep -q -- "$2" "$3" 2>/dev/null; then ok "$1"; else bad "$1 ($3 has no '$2')"; fi }

out=""
attempt() { out=$("$@" 2>&1); status=$?; }

seed() {
    jq -n '{theme:{mode:"dark", source:"wallpaper", finish:"matte"},
            bar:{radius:7}, spine:{max_workspaces:7}, custom:{keep:"me"}}' > "$D/settings.json"
}
seed

echo "save: the current look becomes a package, with only visual settings"
attempt bash "$root/bin/mooi" theme save Foundry "Graphite and phosphor"
is "save exits 0" "$status" "0"
[ -f "$D/themes/foundry.json" ] && ok "the package was written to themes/foundry.json" || bad "no package file"
is "format" "$(jq -r '.format' "$D/themes/foundry.json")" "mooi-theme"
is "version" "$(jq -r '.version' "$D/themes/foundry.json")" "1"
is "name" "$(jq -r '.name' "$D/themes/foundry.json")" "Foundry"
is "description" "$(jq -r '.description' "$D/themes/foundry.json")" "Graphite and phosphor"
is "a visual setting is in the package" "$(jq -r '.settings.theme.mode' "$D/themes/foundry.json")" "dark"
is "layout lists are not" "$(jq -r '.settings.bar.left // "absent"' "$D/themes/foundry.json")" "absent"
is "workspace counts are not" "$(jq -r '.settings.spine // "absent"' "$D/themes/foundry.json")" "absent"
is "unknown sections are not" "$(jq -r '.settings.custom // "absent"' "$D/themes/foundry.json")" "absent"

echo "save: an existing name is refused, and --force replaces it"
attempt bash "$root/bin/mooi" theme save Foundry
is "a second save is refused" "$status" "1"
printf '%s' "$out" > "$t/out"
has "the refusal says how to replace it" "use --force" "$t/out"
attempt bash "$root/bin/mooi" theme save Foundry --force
is "--force saves over it" "$status" "0"

echo "list: saved packages are named"
attempt bash "$root/bin/mooi" theme list
is "list exits 0" "$status" "0"
printf '%s' "$out" > "$t/out"
has "it names the package" "Foundry" "$t/out"
jq -n '{format:"mooi-theme", version:1, name:"Broken", settings:{theme:{overrides:{"accent.nope":"#112233"}}}}' > "$D/themes/broken.json"
attempt bash "$root/bin/mooi" theme list
printf '%s' "$out" > "$t/out"
has "an invalid package is marked, not hidden" "INVALID" "$t/out"

echo "apply: only the package's leaves change; everything else stays"
jq '.theme.mode="light" | .bar.radius=2 | .spine.max_workspaces=3 | .custom.keep="still"' "$D/settings.json" > "$D/s.json" && mv "$D/s.json" "$D/settings.json"
attempt bash "$root/bin/mooi" theme apply Foundry
is "apply exits 0" "$status" "0"
is "the palette mode came from the package" "$(jq -r '.theme.mode' "$D/settings.json")" "dark"
is "the bar radius came from the package" "$(jq -r '.bar.radius' "$D/settings.json")" "7"
is "a non-visual setting stayed" "$(jq -r '.spine.max_workspaces' "$D/settings.json")" "3"
is "an unknown section stayed" "$(jq -r '.custom.keep' "$D/settings.json")" "still"

echo "apply: a package can be a file, and a bad one changes nothing"
jq '.theme.mode="light"' "$D/settings.json" > "$D/s.json" && mv "$D/s.json" "$D/settings.json"
attempt bash "$root/bin/mooi" theme apply "$D/themes/foundry.json"
is "apply by path exits 0" "$status" "0"
is "the mode came from the file" "$(jq -r '.theme.mode' "$D/settings.json")" "dark"
jq -n '{format:"mooi-theme", version:1, name:"Bad", settings:{theme:{overrides:{"accent.nope":"#112233"}}}}' > "$D/bad.json"
jq '.theme.mode="light"' "$D/settings.json" > "$D/s.json" && mv "$D/s.json" "$D/settings.json"
attempt bash "$root/bin/mooi" theme apply "$D/bad.json"
is "the bad package is refused" "$status" "1"
is "the refused package wrote nothing" "$(jq -r '.theme.mode' "$D/settings.json")" "light"

echo "apply: safe mode and a missing package are refused"
attempt env MOOI_SAFE=1 bash "$root/bin/mooi" theme apply Foundry
is "safe mode exits 1" "$status" "1"
attempt bash "$root/bin/mooi" theme apply nowhere
is "an unknown package exits 1" "$status" "1"
attempt bash "$root/bin/mooi" theme save
is "save without a name exits 2" "$status" "2"
attempt bash "$root/bin/mooi" theme
is "theme without a command exits 2" "$status" "2"

echo
echo "$n checks, $fail failed"
[ "$fail" -eq 0 ]
