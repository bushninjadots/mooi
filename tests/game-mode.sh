#!/bin/sh
# Game mode (D266) without a compositor: `bin/mooi game-mode` against a stand-in hyprctl that answers getoption
# with what this machine's Hyprland 0.57 says and records every eval. On reads the eight options, keeps them in
# game-mode.json and asks for the plain look; off gives each back in Hyprland's Lua terms — gaps as the table it
# takes, booleans and numbers as they were — and removes the file. A Hyprland that does not answer leaves nothing.
# Nothing of the real data folder or the session is read or written.
# Run from anywhere: tests/game-mode.sh
set -u
root=$(cd "$(dirname "$0")/.." && pwd)
command -v jq >/dev/null 2>&1 || { echo "game-mode: jq is required"; exit 2; }
t=$(mktemp -d); trap 'rm -rf "$t"' EXIT
export HOME="$t/home" XDG_DATA_HOME="$t/data" XDG_STATE_HOME="$t/state" XDG_RUNTIME_DIR="$t/run" MOOI_PLEAMAR=true
mkdir -p "$HOME" "$XDG_RUNTIME_DIR" "$t/bin"
F=$XDG_DATA_HOME/pleamar/mooi/game-mode.json
cat > "$t/bin/hyprctl" <<'H'
#!/bin/sh
[ -f "$STUB/dead" ] && exit 1
case "$1" in
    getoption) case "$2" in
        animations:enabled|decoration:blur:enabled) printf '{"option":"%s","bool":true,"set":true}' "$2" ;;
        decoration:shadow:enabled) printf '{"option":"%s","bool":false,"set":true}' "$2" ;;
        decoration:rounding) printf '{"option":"%s","int":2,"set":true}' "$2" ;;
        general:gaps_in) printf '{"option":"%s","css":"5 5 5 5","set":true}' "$2" ;;
        general:gaps_out) printf '{"option":"%s","css":"16 12 16 12","set":true}' "$2" ;;
        general:border_size) printf '{"option":"%s","int":1,"set":true}' "$2" ;;
        misc:vrr) printf '{"option":"%s","int":0,"set":false}' "$2" ;;
        *) exit 1 ;; esac ;;
    eval) printf '%s\n' "$2" >> "$STUB/evals" ;;
esac
H
printf '#!/bin/sh\nexit 1\n' > "$t/bin/powerprofilesctl"
chmod +x "$t/bin/hyprctl" "$t/bin/powerprofilesctl"
export PATH="$t/bin:$PATH" STUB="$t"
fail=0; n=0
ok()  { n=$((n + 1)); echo "  ok    $1"; }
bad() { n=$((n + 1)); fail=$((fail + 1)); echo "  FAIL  $1"; }
is()  { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1 ('$2', expected '$3')"; fi; }
has() { if grep -Fq -- "$2" "$t/evals" 2>/dev/null; then ok "$1"; else bad "$1 (no: $2)"; fi; }
gm() { bash "$root/bin/mooi" game-mode "$@" 2>&1; }

echo "on: what it changes is kept, then the plain look is asked for"
is "status before" "$(gm status)" off
is "on says so" "$(gm on)" "game mode on"
is "the file is there" "$([ -f "$F" ] && echo yes)" yes
is "eight options kept" "$(jq '.options | length' "$F")" 8
is "gaps kept as Hyprland reads them" "$(jq -r '.options["general:gaps_out"]' "$F")" "16 12 16 12"
has "animations, blur and shadows off, gaps 0, VRR on" "animations = { enabled = false }, decoration = { blur = { enabled = false }, shadow = { enabled = false }, rounding = 0 }, general = { gaps_in = 0, gaps_out = 0, border_size = 1 }, misc = { vrr = 1 }"
is "on twice changes nothing" "$(gm on)" "game mode is already on"
is "status" "$(gm status)" on

echo "off: each option given back in Hyprland's Lua terms"
: > "$t/evals"
is "off says so" "$(gm off)" "game mode off"
has "a boolean" 'hl.config({ animations = { enabled = true } })'
has "a nested boolean" 'hl.config({ decoration = { blur = { enabled = true } } })'
has "a number" 'hl.config({ decoration = { rounding = 2 } })'
has "gaps as the table" 'hl.config({ general = { gaps_out = { top = 16, right = 12, bottom = 16, left = 12 } } })'
has "a boolean that was false stays false" 'hl.config({ decoration = { shadow = { enabled = false } } })'
has "VRR as it was" 'hl.config({ misc = { vrr = 0 } })'
is "one call each" "$(wc -l < "$t/evals" | tr -d ' ')" 8
is "the file is gone" "$([ -f "$F" ] && echo yes || echo no)" no
is "off twice changes nothing" "$(gm off)" "game mode is off"

echo "a Hyprland that does not answer: nothing kept"
touch "$t/dead"
gm on >/dev/null; is "no file" "$([ -f "$F" ] && echo yes || echo no)" no
rm -f "$t/dead"
is "toggle turns it on" "$(gm)" "game mode on"
is "toggle turns it off" "$(gm)" "game mode off"

echo "$n checks, $fail failed"
[ "$fail" -eq 0 ]
