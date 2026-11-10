#!/bin/sh
# Your monitors (D290) without a screen: `bin/mooi display` against a stand-in hyprctl that remembers the rules it is
# given. A trial applies at once and is put back by itself 15 s later; Keep stops the revert and writes monitors.lua;
# a trial on a trial goes back to what was last kept; bad words never reach Hyprland. The 15 s wait is cut to the
# test's by MOOI_DISPLAY_WAIT. Nothing of the real data folder or session is touched.
# Run from anywhere: tests/displays.sh
set -u
root=$(cd "$(dirname "$0")/.." && pwd)
command -v jq >/dev/null 2>&1 || { echo "displays: jq is required"; exit 2; }
t=$(mktemp -d); trap 'rm -rf "$t"' EXIT
export HOME="$t/home" XDG_DATA_HOME="$t/data" XDG_STATE_HOME="$t/state" XDG_RUNTIME_DIR="$t/run" MOOI_PLEAMAR=true MOOI_DISPLAY_WAIT=1
mkdir -p "$HOME" "$XDG_RUNTIME_DIR" "$t/bin" "$XDG_DATA_HOME/pleamar/mooi"
D=$XDG_DATA_HOME/pleamar/mooi
cat > "$t/bin/hyprctl" <<'H'
#!/bin/sh
case "$1" in
    -j) printf '[{"name":"eDP-1","width":1920,"height":1080,"refreshRate":60.0,"scale":1,"x":0,"y":0}]' ;;
    eval) printf '%s\n' "$2" >> "$STUB/rules" ;;
esac
H
chmod +x "$t/bin/hyprctl"; export PATH="$t/bin:$PATH" STUB="$t"
fail=0; n=0
ok()  { n=$((n + 1)); echo "  ok    $1"; }
bad() { n=$((n + 1)); fail=$((fail + 1)); echo "  FAIL  $1"; }
is()  { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1 ('$2', expected '$3')"; fi; }
d() { bash "$root/bin/mooi" display "$@" >/dev/null 2>&1; echo $?; }
last() { tail -n 1 "$t/rules" 2>/dev/null; }

echo "a trial applies at once and goes back by itself"
is "try" "$(d try eDP-1 1280x720@60 0x0 1)" 0
is "applied" "$(last)" 'hl.monitor({ output = "eDP-1", mode = "1280x720@60", position = "0x0", scale = 1 })'
sleep 2
is "put back" "$(last)" 'hl.monitor({ output = "eDP-1", mode = "1920x1080@60", position = "0x0", scale = 1 })'
is "no trial left" "$([ -f "$D/display-pending.json" ] && echo yes || echo no)" no

echo "a trial on a trial goes back to what was kept, not the first trial"
d try eDP-1 1280x720@60 0x0 1 >/dev/null; d try eDP-1 1024x768@60 0x0 1.5 >/dev/null
is "the first is remembered" "$(jq -r .prev.mode "$D/display-pending.json")" 1920x1080@60
is "revert now" "$(d revert)" 0
is "put back" "$(last)" 'hl.monitor({ output = "eDP-1", mode = "1920x1080@60", position = "0x0", scale = 1 })'

echo "Keep stops the revert and writes the start-up file"
d try eDP-1 1680x1050@60 auto 1.25 >/dev/null
is "keep" "$(d keep)" 0
sleep 2
is "not put back" "$(last)" 'hl.monitor({ output = "eDP-1", mode = "1680x1050@60", position = "auto", scale = 1.25 })'
is "monitors.lua" "$(grep -c 'output = "eDP-1", mode = "1680x1050@60", position = "auto", scale = 1.25' "$D/monitors.lua")" 1

echo "bad words never reach Hyprland"
: > "$t/rules"
is "a name" "$(d try 'eDP-1"; os.exit' 1920x1080@60 0x0 1)" 2
is "a mode" "$(d try eDP-1 'big' 0x0 1)" 2
is "a scale" "$(d try eDP-1 1920x1080@60 0x0 'x')" 2
is "nothing applied" "$(wc -l < "$t/rules" | tr -d ' ')" 0

echo "$n checks, $fail failed"
[ "$fail" -eq 0 ]
