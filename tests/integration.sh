#!/bin/sh
# Live Hyprland test: every island action against a throwaway window, checked twice —
# by what Tidal reports, and independently with `hyprctl -j clients`.
#
# Touches the live session: opens a small kitty window ("tidal-probe") on the current
# workspace and moves one to workspace 9, then closes them and gives focus back.
set -u
root=$(cd "$(dirname "$0")/.." && pwd)
log=${TMPDIR:-/tmp}/tidal-integration.$$.log
fail=0; n=0
probe_class=tidal-probe

say() { pleamar --say tidal "$@" 2>&1; }
get() { say "get $1" | tail -1; }
client() { hyprctl -j clients | jq -r --arg a "$1" ".[] | select(.address == \$a) | $2"; }
ok() { n=$((n + 1)); echo "  ok    $1"; }
bad() { n=$((n + 1)); fail=$((fail + 1)); echo "  FAIL  $1"; }
wait_idle() { for _ in $(seq 1 40); do [ "$(get busy)" = false ] && return 0; sleep 0.1; done; return 1; }
check() { # what jq-field expected
    got=$(client "$addr" "$2")
    if [ "$got" = "$3" ]; then ok "$1 (hyprctl: $2 = $got · tidal: $(get feedback))"
    else bad "$1: hyprctl $2 = '$got', expected '$3' · tidal said: $(get feedback)"; fi
}
spawn_probe() {
    hyprctl dispatch "hl.dsp.exec_cmd(\"kitty --class $probe_class sleep 300\")" >/dev/null
    for _ in $(seq 1 50); do
        addr=$(hyprctl -j clients | jq -r --arg c "$probe_class" '[.[] | select(.class == $c)] | last | .address // empty')
        [ -n "$addr" ] && break; sleep 0.1
    done
    [ -n "$addr" ] || { echo "probe window never appeared"; exit 1; }
    hyprctl dispatch "hl.dsp.focus({ window = \"address:$addr\" })" >/dev/null; sleep 0.3
}
open_on_probe() {
    say "emit open_window" >/dev/null
    for _ in $(seq 1 30); do [ "$(get target_ok)" = true ] && break; sleep 0.1; done
    [ "$(get tgt_class)" = "$probe_class" ] && ok "island targets the probe" || bad "island targeted '$(get tgt_class)'"
}
act() { say "emit activate $1" >/dev/null; sleep 0.15; wait_idle || bad "action $1 never finished"; sleep 0.1; }

home_addr=$(hyprctl -j activewindow | jq -r '.address // empty')
started=false
if ! say "get phase" >/dev/null 2>&1; then
    TIDAL_SAFE=1 pleamar --scene "$root/shell/tidal.plm" --no-hud --stall 0 > "$log" 2>&1 &
    started=true
    for _ in $(seq 1 20); do sleep 0.3; say "get phase" >/dev/null 2>&1 && break; done
fi

echo "probe 1: float, pin, fullscreen, close"
spawn_probe; open_on_probe
act 0; check "float" .floating true
act 2; check "pin (floating)" .pinned true
act 2; check "unpin" .pinned false
act 1; check "fullscreen" .fullscreen 2
act 1; check "leave fullscreen" .fullscreen 0
act 0; check "tile again" .floating false
act 4; [ "$(get arming)" = true ] && [ -n "$(client "$addr" .address)" ] && ok "close waits for confirmation" || bad "close did not wait"
act 4; [ -z "$(client "$addr" .address)" ] && ok "close (window gone · tidal: $(get feedback))" || bad "window still open"
[ "$(get phase)" = hidden ] && ok "island hides when its window is gone" || bad "phase $(get phase)"

echo "probe 2: move to workspace 9"
spawn_probe; open_on_probe
here=$(hyprctl -j activeworkspace | jq .id)
say "emit activate 3" >/dev/null; sleep 0.3
[ "$(get phase)" = expanded ] && ok "Move expands" || bad "Move did not expand"
say "emit pick_ws 9" >/dev/null; sleep 0.2; wait_idle
check "moved to workspace 9" .workspace.id 9
[ "$(hyprctl -j activeworkspace | jq .id)" = "$here" ] && ok "user stays on workspace $here (follow off)" || bad "workspace changed"
hyprctl dispatch "hl.dsp.window.close({ window = \"address:$addr\" })" >/dev/null

echo "failure is reported honestly"
spawn_probe; open_on_probe
hyprctl dispatch "hl.dsp.window.close({ window = \"address:$addr\" })" >/dev/null; sleep 0.5
act 0
[ "$(get feedback)" = "That window is gone" ] && ok "acting on a vanished window reports it" || bad "said: $(get feedback)"

[ -n "$home_addr" ] && hyprctl dispatch "hl.dsp.focus({ window = \"address:$home_addr\" })" >/dev/null
$started && say quit >/dev/null
echo
echo "$n checks, $fail failed"
[ "$fail" -eq 0 ]
