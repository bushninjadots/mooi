#!/bin/sh
# The bar, clicked: Pleamar's fake pointer is moved onto a module and pressed, and the scene
# answers. The module's own x and width are read from a first run (the same layout answers the
# second), so the click is aimed at what the scene placed, not at a number chosen here.
#
# It shows mooi on screen for ~20 s; stop mooi first (bin/mooi stop), which also keeps --say
# from reaching anything else.
# Run from anywhere: tests/pointer.sh
set -u
root=$(cd "$(dirname "$0")/.." && pwd)
out=${TMPDIR:-/tmp}/mooi-pointer.$$
mkdir -p "$out"
fail=0; n=0
pid=''
say() { pleamar --say mooi "$@" 2>&1; }
get() { say "get $1" | tail -1; }
ok() { n=$((n + 1)); echo "  ok    $1"; }
bad() { n=$((n + 1)); fail=$((fail + 1)); echo "  FAIL  $1"; }
is() { if [ "$2" = "$3" ]; then ok "$1 ($2)"; else bad "$1 (got '$2', expected '$3')"; fi }
cleanup() { [ -n "$pid" ] && { say quit >/dev/null 2>&1; kill "$pid" 2>/dev/null; wait "$pid" 2>/dev/null; }; }
trap cleanup EXIT INT TERM
start() { # extra pleamar options
    MOOI_SAFE=1 pleamar --scene "$root/shell/mooi.plm" --no-hud --stall 0 --seconds 40 "$@" \
        >> "$out/scene.log" 2>&1 &
    pid=$!
    for _ in $(seq 1 25); do sleep 0.3; say "get open" >/dev/null 2>&1 && break; done
}
wait_open() { # what (up to 3 s)
    for _ in $(seq 1 30); do [ "$(get open)" = "$1" ] && return 0; sleep 0.1; done; return 1
}

if say "get open" >/dev/null 2>&1; then
    echo "mooi is already running; stop it first (bin/mooi stop)"; exit 2
fi

start
sleep 0.5
# The module carrying a system readout: whichever the machine has (they all open the same
# island). Its x/width are what the scene laid out. The module row starts 8 px down (fl.top)
# and is bar.height deep, so it sits low in a 30 px bar: the press goes near the bar's foot,
# not 8 px down (which is the row's very edge and does not register).
xd=''
for m in battery volume brightness network bluetooth; do
    if [ "$(get "p_$m")" = true ]; then
        xd=$(get "x_$m"); wd=$(get "w_$m"); which=$m; break
    fi
done
if [ -z "$xd" ]; then bad "no system readout is placed on the bar"; say quit >/dev/null; exit 1; fi
# Not every readout opens the *system* island: the battery one opens the power island (the
# session menu with its health). What is checked is that the press opens what its module
# says it opens — so the expectation follows the module, it is not assumed.
want=system
[ "$which" = battery ] && want=power
o=$(get st_offset)
h=$(get st_height)
cx=$((xd + wd / 2)); cy=$((o + h - 6))
say quit >/dev/null 2>&1
kill "$pid" 2>/dev/null; wait "$pid" 2>/dev/null; pid=''
# The first run must really be gone: two scenes named mooi would both answer `get open`, and
# the one without the mouse could be the one heard.
for _ in $(seq 1 30); do say "get open" >/dev/null 2>&1 || break; sleep 0.1; done

echo "a press on the bar ($which at $cx,$cy) opens the $want island"
start --mouse "$cx,$cy@900 click@1200"
if wait_open "$want"; then ok "the click opened it"; else bad "the click did not open it (open = $(get open), expected $want)"; fi
moved=$(grep -c '^mouse' "$out/scene.log" || true)
if [ "$moved" -ge 2 ]; then ok "the pointer was moved and pressed ($moved events)";
else bad "the pointer never reached the scene ($moved events)"; fi
say "key Escape" >/dev/null
if wait_open none; then ok "Escape closes it again"; else bad "Escape left it open ($(get open))"; fi

echo
echo "$n checks, $fail failed · log $out/scene.log"
[ "$fail" -eq 0 ]
