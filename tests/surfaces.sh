#!/bin/sh
# The panels are drawn on the pop-up surface, not on the strip's (D117). The strip's surface is
# 1920×160 — the tallest bar the config allows — so a panel left loose on it is cut off at its
# foot, and nothing on it may reach below the strip. Every panel's rows must therefore be on
# popup_surface, under the strip and inside it, and the press-away plate that takes a press
# outside a panel must reach the surface's own foot.
#
# The surface is read from Pleamar's own region dump (PLEAMAR_REGIONS=1), which is what the
# compositor gets: a row that is missing is a row that cannot be pressed.
#
#   tests/surfaces.sh          at the scale the session is on
#   tests/surfaces.sh 1.5      at 1.5, and back to the scale it found afterwards
#
# It shows mooi on screen for ~20 s; stop mooi first (bin/mooi stop).
# Run from anywhere: tests/surfaces.sh
set -u
root=$(cd "$(dirname "$0")/.." && pwd)
out=${TMPDIR:-/tmp}/mooi-surfaces.$$
log=$out/scene.log
mkdir -p "$out"
fail=0; n=0; pid=''; restored=''
say() { pleamar --say mooi "$@" 2>&1; }
get() { say "get $1" | tail -1; }
ok() { n=$((n + 1)); echo "  ok    $1"; }
bad() { n=$((n + 1)); fail=$((fail + 1)); echo "  FAIL  $1"; }
num() { case "$1" in ''|*[!0-9]*) return 1 ;; *) return 0 ;; esac; }
# The dump is spaced out on this build (`"scale": 1`), so the spaces go before the patterns.
scale_now() { hyprctl monitors -j 2>/dev/null | tr -d ' \n' | grep -o '"scale":[0-9.]*' | head -1 | cut -d: -f2; }
monitor_now() { hyprctl monitors -j 2>/dev/null | tr -d ' \n' | grep -o '"name":"[^"]*"' | head -1 | cut -d'"' -f4; }
cleanup() {
    [ -n "$pid" ] && { say quit >/dev/null 2>&1; kill "$pid" 2>/dev/null; wait "$pid" 2>/dev/null; pid=''; }
    [ -n "$restored" ] && hyprctl eval "hl.monitor({output=\"$restored\", scale=$orig})" >/dev/null 2>&1
}
trap cleanup EXIT INT TERM

if say "get open" >/dev/null 2>&1; then
    echo "mooi is already running; stop it first (bin/mooi stop)"; exit 2
fi

# Pleamar's fake mouse and regions are enough; nothing is clicked here.
orig=$(scale_now)
mon=$(monitor_now)
if [ -n "${1:-}" ]; then
    restored=$mon
    hyprctl eval "hl.monitor({output=\"$mon\", scale=$1})" >/dev/null 2>&1
    sleep 2
    echo "asked for scale $1, the monitor is at $(scale_now)"
fi

PLEAMAR_REGIONS=1 pleamar --scene "$root/shell/mooi.plm" --no-hud --stall 0 --seconds 90 \
    >> "$log" 2>&1 &
pid=$!
for _ in $(seq 1 60); do sleep 0.2; say "get open" >/dev/null 2>&1 && break; done
H=$(get popup_surface.height)
S=$(get st_res)
if ! num "$H" || ! num "$S"; then
    echo "the scene never answered (popup_surface.height='$H', st_res='$S') · $log"; exit 1
fi
echo "at scale $(scale_now): the pop-up surface is $H px tall, the strip $S px"

# The widest rect on a surface is the press-away plate (it spans the screen); the narrower ones
# are the panel's own rows. `$1` picks which to report: plate | bottom | top.
walk() { # pick
    awk -v pick="$1" '{
        s = $0; sub(/^[^:]*:[[:space:]]*/, "", s); gsub(/[][,]/, " ", s)
        k = split(s, a, " ")
        m = 0; found = 0; first = 0
        for (i = 1; i + 3 <= k; i += 4) {
            w = a[i + 2] - a[i]; y2 = a[i + 3]; y1 = a[i + 1]
            plate = (w >= 1000)
            take = (pick == "plate") ? plate : !plate
            if (!take) continue
            if (pick != "top") { if (!found || y2 > m) m = y2; found = 1 }
            else { if (!found || y1 < m) m = y1; found = 1 }
        }
        print (found ? m : "")
    }'
}
last() { grep -E "^regions · surface [0-9]+ \($1\):" "$log" | tail -1; }
strip_line() { grep -E "^regions · surface [0-9]+ \(\):" "$log" | tail -1; }

for p in window system weather calendar power; do
    say "fact open $p" >/dev/null 2>&1
    sleep 0.7
    line=$(last popup_surface)
    plate=$(printf '%s\n' "$line" | walk plate)
    bottom=$(printf '%s\n' "$line" | walk bottom)
    top=$(printf '%s\n' "$line" | walk top)
    strip=$(strip_line | walk bottom)
    if num "$plate" && [ "$plate" -ge "$H" ]; then
        ok "$p: the press-away plate reaches the surface's foot ($plate ≥ $H)"
    else bad "$p: the plate stops at ${plate:-nothing} of $H"; fi
    if num "$bottom" && [ "$bottom" -le "$H" ] && [ "$bottom" -gt "$S" ]; then
        ok "$p: its rows are on the pop-up surface, $top…$bottom inside 0…$H"
    else bad "$p: its rows end at ${bottom:-nothing} (strip $S, surface $H)"; fi
    if num "$strip" && [ "$strip" -le $((S + 40)) ]; then
        ok "$p: nothing below the strip is drawn on the strip's surface (lowest $strip)"
    else bad "$p: the strip's surface carries something at ${strip:-nothing} (strip $S)"; fi
    say "fact open none" >/dev/null 2>&1
done

say quit >/dev/null 2>&1; kill "$pid" 2>/dev/null; wait "$pid" 2>/dev/null; pid=''
echo
echo "$n checks, $fail failed · log $log"
[ "$fail" -eq 0 ]
