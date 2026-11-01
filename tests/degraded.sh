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
    pleamar --scene "$root/shell/mooi.plm" --no-hud --stall 0 --seconds 30 > "$log" 2>&1 &
pid=$!
# Readiness is pleamar's own status, not `get`'s: `get` pipes through `tail`, whose status is 0
# whatever pleamar said, so the loop broke on its first try and the checks below raced the scene's
# startup — the island read 'none' and the note read '' (found 2026-11-01, re-running this suite).
ready=no
for _ in $(seq 1 60); do
    if pleamar --say mooi "get open" >/dev/null 2>&1; then ready=yes; break; fi
    sleep 0.3
done
if [ "$ready" != yes ]; then
    echo "  FAIL  the shell never answered on its socket"
    kill "$pid" 2>/dev/null; wait "$pid" 2>/dev/null
    echo; echo "1 checks, 1 failed · log $log"; exit 1
fi

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
