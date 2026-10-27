#!/bin/sh
# Live Hyprland test: every island action against a throwaway window, checked twice —
# by what mooi reports, and independently with `hyprctl -j clients`.
#
# Touches the live session: opens a small kitty window ("mooi-probe") on the current
# workspace and moves one to workspace 9, visits workspace 9 and comes back, then
# closes them and gives focus back.
set -u
root=$(cd "$(dirname "$0")/.." && pwd)
log=${TMPDIR:-/tmp}/mooi-integration.$$.log
fail=0; n=0
probe_class=mooi-probe

say() { pleamar --say mooi "$@" 2>&1; }
get() { say "get $1" | tail -1; }
client() { hyprctl -j clients | jq -r --arg a "$1" ".[] | select(.address == \$a) | $2"; }
ok() { n=$((n + 1)); echo "  ok    $1"; }
bad() { n=$((n + 1)); fail=$((fail + 1)); echo "  FAIL  $1"; }
wait_idle() { for _ in $(seq 1 40); do [ "$(get busy)" = false ] && return 0; sleep 0.1; done; return 1; }
check() { # what jq-field expected
    got=$(client "$addr" "$2")
    if [ "$got" = "$3" ]; then ok "$1 (hyprctl: $2 = $got · mooi: $(get feedback))"
    else bad "$1: hyprctl $2 = '$got', expected '$3' · mooi said: $(get feedback)"; fi
}
open_probes() { hyprctl -j clients | jq --arg c "$probe_class" '[.[] | select(.class == $c)] | length'; }
probe_addresses() { hyprctl -j clients | jq -r --arg c "$probe_class" '.[] | select(.class == $c) | .address'; }
probe_pids() { hyprctl -j clients | jq -r --arg c "$probe_class" '.[] | select(.class == $c) | .pid'; }
close_probes() { # every probe left behind, gone: closing is a request, so this waits
    for c in $(probe_addresses); do
        hyprctl dispatch "hl.dsp.window.close({ window = \"address:$c\" })" >/dev/null
    done
    for _ in $(seq 1 30); do [ "$(open_probes)" -eq 0 ] && return 0; sleep 0.1; done
    for p in $(probe_pids); do kill "$p" 2>/dev/null; done
    for _ in $(seq 1 30); do [ "$(open_probes)" -eq 0 ] && return 0; sleep 0.1; done
    return 1
}
spawn_probe() {
    # Nothing an earlier step left behind: a second probe answers the same queries, and
    # every check after that would be about the wrong window.
    close_probes || bad "a $probe_class window would not go"
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
if ! say "get open" >/dev/null 2>&1; then
    MOOI_SAFE=1 pleamar --scene "$root/shell/mooi.plm" --no-hud --stall 0 > "$log" 2>&1 &
    started=true
    for _ in $(seq 1 20); do sleep 0.3; say "get open" >/dev/null 2>&1 && break; done
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
act 4; [ -z "$(client "$addr" .address)" ] && ok "close (window gone · mooi: $(get feedback))" || bad "window still open"
[ "$(get open)" = none ] && ok "island closes when its window is gone" || bad "open = $(get open)"

echo "probe 2: move to workspace 9"
spawn_probe; open_on_probe
here=$(hyprctl -j activeworkspace | jq .id)
say "emit activate 3" >/dev/null; sleep 0.3
[ "$(get phase)" = expanded ] && ok "Move expands" || bad "Move did not expand"
say "emit pick_ws 9" >/dev/null; sleep 0.2; wait_idle
check "moved to workspace 9" .workspace.id 9
[ "$(hyprctl -j activeworkspace | jq .id)" = "$here" ] && ok "user stays on workspace $here (follow off)" || bad "workspace changed"
[ "$(get flash_ws)" = 9 ] && ok "the Spine confirms workspace 9 (state.confirm pulse)" || bad "flash_ws = $(get flash_ws)"
hyprctl dispatch "hl.dsp.window.close({ window = \"address:$addr\" })" >/dev/null

echo "failure is reported honestly"
spawn_probe; open_on_probe
hyprctl dispatch "hl.dsp.window.close({ window = \"address:$addr\" })" >/dev/null
close_probes   # closing is a request: acting before it lands would hit the window
act 0
[ "$(get feedback)" = "That window is gone" ] && ok "acting on a vanished window reports it" || bad "said: $(get feedback)"

echo "command membrane: results and satellite actions on a probe"
no_stray_probes() { # nothing from an earlier step left behind to answer for the probe
    [ "$(open_probes)" -le 1 ] || bad "$(open_probes) $probe_class windows are open; a stray one would answer for the probe"
}
find_probe() { # opens the membrane listing only the probe window
    say "emit open_command" >/dev/null; sleep 0.5
    say "text query @$probe_class" >/dev/null; sleep 0.3
    [ "$(get res.0.kind)" = win ] && [ "$(get res.count)" = 1 ] && ok "@$probe_class finds the probe window" || bad "results: $(get res.count), first '$(get res.0.title)'"
}
sat() { say "emit csat_try $1" >/dev/null; sleep 0.15; wait_idle || bad "satellite $1 never finished"; sleep 0.1; }
spawn_probe
here=$(hyprctl -j activeworkspace | jq .id)
[ -n "$home_addr" ] && hyprctl dispatch "hl.dsp.focus({ window = \"address:$home_addr\" })" >/dev/null; sleep 0.3
find_probe
say "emit crun 0" >/dev/null; sleep 0.15; wait_idle; sleep 0.2
check "↵ on a window result focuses it" .focusHistoryID 0
[ "$(get open)" = none ] && ok "…and the membrane closes" || bad "open = $(get open)"
hyprctl dispatch "hl.dsp.window.move({ workspace = 9, follow = false, window = \"address:$addr\" })" >/dev/null; sleep 0.3
say "emit open_command" >/dev/null; sleep 0.5
say "text query 9" >/dev/null; sleep 0.3
say "emit crun 0" >/dev/null; sleep 0.8
[ "$(hyprctl -j activeworkspace | jq .id)" = 9 ] && ok "↵ on 'Workspace 9' goes there (hyprctl agrees)" || bad "active workspace $(hyprctl -j activeworkspace | jq .id)"
[ "$(get open)" = none ] && ok "…and closes once Hyprland confirms" || bad "open = $(get open)"
hyprctl dispatch "hl.dsp.focus({ workspace = $here })" >/dev/null; sleep 0.4
find_probe
sat 1; check "satellite Bring here (from 9 to $here)" .workspace.id "$here"
[ "$(hyprctl -j activeworkspace | jq .id)" = "$here" ] && ok "…without moving the user" || bad "workspace changed"
sat 2; check "satellite Float" .floating true
sat 2; check "satellite Float again tiles" .floating false
sat 4; [ "$(get carming)" = true ] && [ -n "$(client "$addr" .address)" ] && ok "satellite Close waits for confirmation" || bad "close did not wait"
sat 4; [ -z "$(client "$addr" .address)" ] && ok "satellite Close (window gone · mooi: $(get feedback))" || bad "window still open"
sleep 0.3; [ "$(get res.count)" = 0 ] && ok "…and the result disappears" || bad "still $(get res.count) results"
say "key Escape" >/dev/null; sleep 0.2

echo "the Overview opens and closes"
say "emit open_overview" >/dev/null; sleep 0.8
[ "$(get open)" = overview ] && ok "the Overview opens" || bad "open = $(get open)"
say "key Escape" >/dev/null; sleep 0.4
[ "$(get open)" = none ] && ok "Esc closes the Overview" || bad "open = $(get open)"

echo "the keyboard is really handed over (real keys, not --say)"
if command -v wtype >/dev/null 2>&1; then
    # A throwaway window holds the focus first: a key that does not reach the island
    # lands in it, not in whatever the user was doing.
    spawn_probe; open_on_probe; no_stray_probes
    say "key Escape" >/dev/null; sleep 0.3
    say "emit open_command" >/dev/null; sleep 0.6
    wtype "mooi"; sleep 0.4
    [ "$(get query)" = "mooi" ] && ok "typing reaches the field (the window below says $(hyprctl -j activewindow | jq -r '.class'))" || bad "typed 'mooi', the field says '$(get query)'"
    wtype -k Escape; sleep 0.5
    [ "$(get open)" = none ] && ok "Esc from a real keyboard closes the membrane" || bad "open = $(get open)"
    say "emit open_overview" >/dev/null; sleep 0.8
    wtype -k Escape; sleep 0.5
    [ "$(get open)" = none ] && ok "…and it closes the Overview too" || bad "open = $(get open)"
    hyprctl dispatch "hl.dsp.window.close({ window = \"address:$addr\" })" >/dev/null; sleep 0.3
else
    echo "  skip  wtype is not installed: the compositor's own keyboard was not tried"
fi

echo "system island: volume, mute, brightness (restored afterwards)"
vol_now() { wpctl get-volume @DEFAULT_AUDIO_SINK@ | awk '{ print $2 }'; }
muted_now() { wpctl get-volume @DEFAULT_AUDIO_SINK@ | grep -q MUTED && echo true || echo false; }
bri_now() { echo "$(brightnessctl get) $(brightnessctl max)" | awk '{ printf "%.2f", $1 / $2 }'; }
near() { awk -v a="$1" -v b="$2" 'BEGIN { d = a - b; if (d < 0) d = -d; exit !(d < 0.02) }'; }
vol0=$(vol_now); mute0=$(muted_now); bri0=$(brightnessctl get)
say "emit open_system" >/dev/null; sleep 0.3
say "emit vol 0.23" >/dev/null; sleep 0.6
near "$(vol_now)" 0.23 && ok "volume set to 0.23 (wpctl: $(vol_now) · island shows $(get audio.volume | cut -c1-4))" || bad "volume is $(vol_now)"
say "emit mute" >/dev/null; sleep 0.5
[ "$(muted_now)" != "$mute0" ] && ok "mute toggled (island: muted = $(get audio.muted))" || bad "mute did not change"
say "emit mute" >/dev/null; sleep 0.5
[ "$(muted_now)" = "$mute0" ] && ok "mute toggled back" || bad "mute not restored"
if [ "$(get brightness.present)" = true ]; then
    say "emit bri 0.5" >/dev/null; sleep 0.8
    near "$(bri_now)" 0.5 && ok "brightness set to 0.5 (brightnessctl: $(bri_now))" || bad "brightness is $(bri_now)"
    say "emit bri 0" >/dev/null; sleep 0.8
    awk -v b="$(bri_now)" 'BEGIN { exit !(b > 0) }' && ok "a slider at 0 never blacks the screen ($(bri_now))" || bad "brightness reached 0"
fi
for v in 0.30 0.31 0.32 0.33 0.34 0.35 0.36 0.37 0.38 0.39 0.40; do say "emit vol $v" >/dev/null; done; sleep 0.6
near "$(vol_now)" 0.40 && ok "a burst of requests ends on the last one (0.40)" || bad "after burst volume is $(vol_now)"
wpctl set-volume @DEFAULT_AUDIO_SINK@ "$vol0"; brightnessctl -q set "$bri0"
[ "$(muted_now)" = "$mute0" ] || wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle
say "key Escape" >/dev/null
echo "  (restored: volume $(vol_now), muted $(muted_now), brightness $(bri_now))"

[ -n "$home_addr" ] && hyprctl dispatch "hl.dsp.focus({ window = \"address:$home_addr\" })" >/dev/null
$started && say quit >/dev/null
echo
echo "$n checks, $fail failed"
[ "$fail" -eq 0 ]
