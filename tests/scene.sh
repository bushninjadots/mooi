#!/bin/sh
# Drives the real scene through its lifecycle against the bar that runs today (Ferrolume, the
# island kit D97, the deck D100+), checks the state after each step, and measures the islands'
# springs. It replaced the Mechanism-era suite, whose membrane and cluster assertions no longer
# described anything on screen (audit 2026-10-31, F2).
#
# It shows mooi on screen for ~40 s and an island holds the keyboard while open.
# It never moves windows, changes workspaces, changes volume or brightness, or launches apps.
# Run from anywhere: tests/scene.sh
set -u
root=$(cd "$(dirname "$0")/.." && pwd)
out=${TMPDIR:-/tmp}/mooi-scene-test.$$
mkdir -p "$out"
fail=0; n=0

say() { pleamar --say mooi "$@" 2>&1; }
get() { say "get $1" | tail -1; }
expect() { # name value [what]
    n=$((n + 1)); got=$(get "$1")
    if [ "$got" = "$2" ]; then echo "  ok    ${3:-$1 = $2}"
    else echo "  FAIL  ${3:-$1}: expected '$2', got '$got'"; fail=$((fail + 1)); fi
}
expect_num() { # name op value what   (op: lt | gt)
    n=$((n + 1)); got=$(get "$1")
    if awk -v v="$got" -v op="$2" -v w="$3" 'BEGIN { if (v == "") exit 1; exit !((op == "lt") ? (v + 0 < w) : (v + 0 > w)) }'
    then echo "  ok    $4"; else echo "  FAIL  $4 ($1 = '$got')"; fail=$((fail + 1)); fi
}
step() { say "$@" >/dev/null; sleep 0.35; }
# An island opens on the frame after the event; a fixed sleep raced it (a probe read `none` after
# 350 ms and `window` after 400). Ask until it is there.
wait_open() { # expected [tenths]
    i=0
    while [ "$i" -lt "${2:-40}" ]; do [ "$(get open)" = "$1" ] && return 0; sleep 0.1; i=$((i + 1)); done
    return 1
}
open_is() { # event expected what
    step "emit $1"
    if wait_open "$2"; then n=$((n + 1)); echo "  ok    $3"
    else n=$((n + 1)); echo "  FAIL  $3 (open = $(get open))"; fail=$((fail + 1)); fi
}
close_is() { # what
    step "key Escape"
    if wait_open none; then n=$((n + 1)); echo "  ok    $1"
    else n=$((n + 1)); echo "  FAIL  $1 (open = $(get open))"; fail=$((fail + 1)); fi
}
start() { # extra pleamar options
    MOOI_SAFE=1 pleamar --scene "$root/shell/mooi.plm" --no-hud --stall 0 --seconds 90 "$@" 2> "$out/scene.log" &
    pid=$!
    # A scene that answers once is not yet a scene that is up: one still shutting down from a
    # moment ago answers from its own socket while the new one is still binding. Two answers with
    # a beat between them is the condition wanted.
    up=''
    for _ in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15; do
        sleep 0.2
        if say "get open" >/dev/null 2>&1; then sleep 0.2; say "get open" >/dev/null 2>&1 && up=1; fi
        [ -n "$up" ] && break
        up=''
    done
}

if say "get open" >/dev/null 2>&1; then
    echo "mooi is already running; stop it first (bin/mooi stop)"; exit 2
fi

# The pointer is parked out of the way for the run, and put back on the way out. Hover selects a
# row, so a mouse left resting over a panel would decide those checks instead of the keys.
where=$(hyprctl cursorpos 2>/dev/null)
park_pointer() { # x y
    hyprctl dispatch "hl.dsp.cursor.move({x=$1, y=$2})" >/dev/null 2>&1 && return 0
    hyprctl dispatch movecursor "$1" "$2" >/dev/null 2>&1
}
restore_pointer() { [ -n "${where:-}" ] && park_pointer "${where%%,*}" "${where##*,}"; }
trap 'kill "${ka:-}" 2>/dev/null; restore_pointer' EXIT INT TERM
park_pointer 1917 540
sleep 0.2
# A real pointer move every few seconds is the presence the shell's idle net looks for.
keepalive() {
    while :; do
        sleep 7
        park_pointer 1917 540
        park_pointer 1916 540
    done
}

start --record rv.window,depth,rv.system,rv.command > "$out/record.tsv"
keepalive &
ka=$!

echo "the bar"
expect open none "starts with no island"
expect_num bar_x0 gt -1 "the bar has a left edge ($(get bar_x0))"
expect_num bar_x1 gt "$(get bar_x0)" "…and a right edge ($(get bar_x1))"
expect_num st_height gt 0 "…and a thickness ($(get st_height))"
expect_num st_offset gt -1 "…and a place from the screen's edge"

echo "the workspace instrument (whatever style the settings name)"
# `describe` lists what takes input, so it names exactly the blocks on the bar. The ids must be a
# contiguous run of positions, exactly one must be active, and that one must sit on the chain's
# own focus slot — all read from the description, so this cannot drift from the scene.
say "describe" | awk '/^main /{ p = 1; print; next } /^[^ ]/{ p = 0 } p' > "$out/describe.txt"
blocks=$(grep -cP '«Workspace [0-9]' "$out/describe.txt")
ids=$(grep -oP '«Workspace \K[0-9]+' "$out/describe.txt")
sel_line=$(grep -P '«Workspace [0-9]' "$out/describe.txt" | grep '· selected')
active_id=$(printf '%s' "$sel_line" | grep -oP '«Workspace \K[0-9]+')
chain_line=$(grep -P 'list +chain ' "$out/describe.txt")
slot_x=$(printf '%s' "$chain_line" | grep -oP 'at \K[0-9]+')
slot_w=$(printf '%s' "$chain_line" | grep -oP '[0-9]+(?=×)')
centres=$(grep -P '«Workspace [0-9]' "$out/describe.txt" | grep -oP 'at \K[0-9]+')
pitch=$(printf '%s\n' "$centres" | awk 'NR > 1 { d = $1 - p; if (m == "" || d < m) m = d } { p = $1 } END { print (m == "" ? 0 : m) }')
reach=$(awk -v z="$slot_w" -v p="$pitch" -v a="$active_id" -v c="$(get spaces.count)" 'BEGIN {
    if (p <= 0) { print 0; exit }
    f = int(z / p / 2 + 0.001); lo = a - f; if (lo < 1) lo = 1; hi = a + f; if (hi > c) hi = c
    print hi - lo + 1 }')
n=$((n + 1))
if [ "$blocks" = "$reach" ] && [ "$blocks" -ge 1 ]
then echo "  ok    the chain drew the window's reach ($blocks of $(get spaces.count), from position ${active_id:-?})"
else echo "  FAIL  the chain drew $blocks blocks; its window reaches $reach from position ${active_id:-?}"; fail=$((fail + 1)); fi
n=$((n + 1))
contiguous=1; prev=""
for id in $ids; do
    [ -n "$prev" ] && [ "$id" != "$((prev + 1))" ] && contiguous=0
    prev=$id
done
if [ "$contiguous" = 1 ]; then echo "  ok    …and they are neighbouring positions ($(echo $ids | tr '\n' ' '))"
else echo "  FAIL  the blocks are not a contiguous run: $(echo $ids | tr '\n' ' ')"; fail=$((fail + 1)); fi
n=$((n + 1))
if [ "$(printf '%s' "$sel_line" | grep -c '· selected')" = 1 ]; then echo "  ok    exactly one block is the active position"
else echo "  FAIL  the chain does not mark exactly one block active"; fail=$((fail + 1)); fi
if [ -n "$slot_x" ] && [ -n "$sel_line" ]; then
    bx=$(printf '%s' "$sel_line" | grep -oP 'at \K[0-9]+' | head -1)
    bw=$(printf '%s' "$sel_line" | grep -oP '[0-9]+×' | head -1 | tr -d '×')
    n=$((n + 1))
    if awk -v b="$bx" -v w="$bw" -v x="$slot_x" -v z="$slot_w" 'BEGIN { c = b + w / 2; s = x + z / 2; d = c - s; if (d < 0) d = -d; exit !(d <= 1.5) }'
    then echo "  ok    …and it sits on the focus slot (centre $((bx + bw / 2)), slot $((slot_x + slot_w / 2)))"
    else echo "  FAIL  the active block is not on the focus slot (centre $((bx + bw / 2)), slot $((slot_x + slot_w / 2)))"; fail=$((fail + 1)); fi
    n=$((n + 1))
    if awk -v x="$slot_x" -v z="$slot_w" -v lo="$(get bar_x0)" -v hi="$(get bar_x1)" 'BEGIN { exit !(x >= lo && x + z <= hi) }'
    then echo "  ok    …and the chain sits inside the bar ($slot_x…$((slot_x + slot_w)) in $(get bar_x0)…$(get bar_x1))"
    else echo "  FAIL  the chain ($slot_x…$((slot_x + slot_w))) is not inside the bar ($(get bar_x0)…$(get bar_x1))"; fail=$((fail + 1)); fi
fi
zx=$(printf '%s' "$chain_line" | grep -oP 'at \K[0-9]+')
zw=$(printf '%s' "$chain_line" | grep -oP '[0-9]+(?=×)')
counts=$(awk -v zx="$zx" -v zw="$zw" '
    /«Workspace [0-9]/ {
        match($0, /at [0-9]+/); x = substr($0, RSTART + 3, RLENGTH - 3) + 0
        match($0, /[0-9]+×/);    w = substr($0, RSTART, RLENGTH - 1) + 0
        c = x + w / 2; act = ($0 !~ /inactive/); within = (c >= zx && c <= zx + zw)
        if (act && within) ins++; else if (!act && !within) outs++; else bad++
    }
    END { printf "%d %d %d", ins + 0, outs + 0, bad + 0 }' "$out/describe.txt")
ins=$(echo "$counts" | cut -d' ' -f1); outs=$(echo "$counts" | cut -d' ' -f2); bad=$(echo "$counts" | cut -d' ' -f3)
n=$((n + 1))
if [ "$bad" = 0 ] && [ "$ins" = "$reach" ]; then
    echo "  ok    the window decides what is pressable: $ins blocks inside it take the press, $outs past its edge do not"
else echo "  FAIL  the chain's window and its press do not agree (inside $ins, outside $outs, neither $bad)"; fail=$((fail + 1)); fi
expect bar_wheel step "the wheel over the chain steps a workspace"

echo "window island"
open_is open_window window "open → window island"
expect phase compact "…compact"
expect sel 0 "selection starts on Float"
step "key Right"; step "key Right"; expect sel 2 "→ → selects the third action"
step "key Left"; step "key Left"; step "key Left"; expect sel 4 "← wraps to Close"
step "key Return"; expect arming true "Close asks for confirmation first"
step "key Escape"; expect arming false "Esc cancels the confirmation first"
expect open window "…and keeps the island open"
step "key Left"; step "key Return"; expect phase expanded "Move expands the island"
step "key Escape"; expect phase compact "Esc collapses before it closes"
close_is "Esc again dismisses"

echo "system island"
open_is open_system system "open → system island"
expect srow 0 "the first row is selected"
step "key Down"; expect srow 1 "↓ selects the next row"
step "key Up"; expect srow 0 "↑ back to the first"
close_is "Esc dismisses"

echo "one slot"
step "emit open_window"; wait_open window
step "emit open_system"
if wait_open system; then n=$((n + 1)); echo "  ok    opening system while window is open hands the slot over"
else n=$((n + 1)); echo "  FAIL  the slot was not handed over (open = $(get open))"; fail=$((fail + 1)); fi
sleep 0.3; expect_num rv.window lt 0.001 "…and the window island has left"
close_is "Esc closes the system island"

echo "interruption"
say "emit open_window" >/dev/null; sleep 0.06; say "emit open_system" >/dev/null; sleep 0.06
say "emit open_window" >/dev/null; sleep 0.7
expect open window "window → system → window inside 120 ms ends on window"
expect_num rv.system lt 0.001 "…the system island never stays half-open"
expect_num rv.window gt 0.999 "…the window island is fully there"
step "key Escape"
say "emit open_window" >/dev/null; sleep 0.06; say "emit open_window" >/dev/null; sleep 0.06
say "emit open_window" >/dev/null; sleep 0.06; say "emit open_window" >/dev/null; sleep 0.7
expect open none "four rapid toggles end closed"
expect_num rv.window lt 0.001 "…and the surface settled closed"
step "emit open_window"; sleep 0.1; step "emit open_window"; sleep 0.3
expect open none "reopen then close mid-way settles"

echo "Overview"
open_is open_overview overview "the Overview opens"
expect_num spaces.count gt 0 "the configured slots are listed ($(get spaces.count))"
if [ "$(get spaces.count)" -ge 1 ]; then expect spaces.0.id 1 "the map starts at workspace 1"; fi
active=$(hyprctl -j activeworkspace | jq .id)
if [ "$active" -ge 1 ] && [ "$active" -le "$(get spaces.count)" ]; then
    expect spaces.$((active - 1)).active true "the service marks the active workspace ($active)"
fi
windows=$(hyprctl -j clients | jq '[.[] | select(.mapped != false and .hidden != true)] | length')
expect atlas_tiles.count "$windows" "every window Hyprland lists is a tile"
close_is "Esc closes the Overview"
expect atlas_tiles.count "$windows" "…and the board stays whole while it leaves"

echo "command membrane (searches only; never opens a result)"
open_is open_command command "open → command membrane"
expect cmode list "…showing results"
for _ in 1 2 3 4 5 6 7 8 9 10 11 12; do step "key Up"; done
expect csel 0 "…the first result is selected (↑ stops at the top)"
step "text query >sys"; expect_num res.count gt 0 "> finds mooi actions ($(get res.count))"
step "text query zzqxzzqx"; expect res.count 0 "nothing matches nonsense"
n=$((n + 1))
if [ -n "$(get cempty)" ]; then echo "  ok    …and the empty state says something ($(get cempty))"
else echo "  FAIL  the empty state is blank"; fail=$((fail + 1)); fi
step "text query @"; expect_num res.count gt 0 "@ lists windows ($(get res.count))"
if [ "$(get res.count)" -gt 0 ]; then expect res.0.kind win "…and the first is a window"; fi
step "key Down"; step "key Up"; expect csel 0 "↓ ↑ move the selection"
step "key Tab"; expect cmode actions "Tab opens a window's satellite actions"
step "key Escape"; expect cmode list "Esc goes back to the results"
expect open command "…keeping the membrane open"
close_is "Esc again dismisses"
step "emit open_command"; expect query "" "reopening starts with an empty field"
close_is "Esc closes it"

say quit >/dev/null 2>&1; wait "$pid" 2>/dev/null

echo "motion (1% → 99% of travel, measured; a generous bound, not the token's exact time)"
measure() { # column direction label
    grep -P '^[\d.]+\t' "$out/record.tsv" | awk -F'\t' -v c="$1" -v dir="$2" -v label="$3" '
      { t=$1+0; v=$c+0
        if (dir=="up")   { if (v>0.01 && a==0) a=t; if (a>0 && v>=0.99 && b==0) b=t }
        if (dir=="down") { if (v>=0.99) seen=1; if (seen && v<0.99 && a==0) a=t; if (a>0 && v<=0.01 && b==0) b=t } }
      END { if (b>0) { d=b-a; ok=(d>=40 && d<=900); printf "  %s %-22s %4.0f ms\n", ok?"ok   ":"FAIL ", label, d; exit ok?0:1 }
            else { printf "  FAIL  %-22s no complete transition recorded\n", label; exit 1 } }'
}
measure 2 up "window enters" || fail=$((fail + 1))
measure 2 down "window leaves" || fail=$((fail + 1))
measure 3 up "expanded" || fail=$((fail + 1))
measure 3 down "collapsed" || fail=$((fail + 1))
measure 4 up "system enters" || fail=$((fail + 1))
measure 5 up "membrane enters" || fail=$((fail + 1))
measure 5 down "membrane leaves" || fail=$((fail + 1))

echo "reduced motion"
start --reduced-motion --record rv.window > "$out/reduced.tsv"
step "emit open_window"; step "key Escape"; step "emit open_window"; step "key Escape"
say quit >/dev/null 2>&1; wait "$pid" 2>/dev/null
n=$((n + 1))
mid=$(grep -P '^[\d.]+\t' "$out/reduced.tsv" | awk -F'\t' '$2 > 0.001 && $2 < 0.999 { m++ } END { print m + 0 }')
full=$(grep -P '^[\d.]+\t' "$out/reduced.tsv" | awk -F'\t' '$2 >= 0.999 { f++ } END { print f + 0 }')
if [ "$mid" -eq 0 ] && [ "$full" -gt 0 ]; then echo "  ok    open/close land at once ($full frames open, 0 in between)"
else echo "  FAIL  reduced motion: $mid frames mid-transition, $full open"; fail=$((fail + 1)); fi

echo
echo "$n state checks + 7 motion checks, $fail failed · logs in $out"
[ "$fail" -eq 0 ]
