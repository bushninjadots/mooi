#!/bin/sh
# mooi without Hyprland's IPC: it still draws (Wayland is fine) but cannot read or
# command windows and workspaces. It must start, say so, and keep everything else.
# Shows mooi on screen for ~8 s; changes nothing.
set -u
root=$(cd "$(dirname "$0")/.." && pwd)
fail=0; n=0
say() { pleamar --say mooi "$@" 2>&1; }
get() { say "get $1" | tail -1; }
check() { n=$((n + 1)); if [ "$2" = "$3" ]; then echo "  ok    $1"; else echo "  FAIL  $1 (got '$2', expected '$3')"; fail=$((fail + 1)); fi; }

say "get open" >/dev/null 2>&1 && { echo "mooi is already running; stop it first"; exit 2; }
log=${TMPDIR:-/tmp}/mooi-degraded.$$.log
HYPRLAND_INSTANCE_SIGNATURE=no-such-instance MOOI_SAFE=1 \
    pleamar --scene "$root/shell/mooi.plm" --no-hud --stall 0 --seconds 20 > "$log" 2>&1 &
pid=$!
for _ in $(seq 1 20); do sleep 0.3; get open >/dev/null 2>&1 && break; done

echo "Hyprland IPC unreachable"
check "the shell starts" "$(get open)" none
# Pleamar falls back to the Wayland ext-workspace protocol when Hyprland's socket is
# not there (platform/compositor.rs), so the Spine keeps real workspaces.
check "workspaces still arrive (ext-workspace) and match Hyprland" "$(get wss.total)" "$(hyprctl -j workspaces | jq '[.[] | select(.id > 0)] | length')"
say "emit open_window" >/dev/null; sleep 1.2
check "the window island opens anyway" "$(get open)" window
check "it has no target" "$(get target_ok)" false
check "and says why" "$(get feedback)" "Nothing to act on: no window has focus"
say "emit activate 0" >/dev/null; sleep 0.4
check "actions stay refused" "$(get busy)" false
say "key Escape" >/dev/null; sleep 0.3
check "Esc still dismisses" "$(get open)" none
say "emit open_system" >/dev/null; sleep 0.4
check "the system island still works" "$(get open)" system
say "key Escape" >/dev/null
say quit >/dev/null 2>&1; wait "$pid" 2>/dev/null
echo; echo "$n checks, $fail failed · log $log"
[ "$fail" -eq 0 ]
