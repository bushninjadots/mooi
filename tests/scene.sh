#!/bin/sh
# Drives the real scene through its lifecycle and checks the state after each step,
# measures the islands' springs against their tokens, then checks reduced motion.
#
# It shows mooi on screen for ~25 s and an island holds the keyboard while open.
# It never runs a Hyprland action and never changes volume or brightness.
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
start() { # extra pleamar options
    MOOI_SAFE=1 pleamar --scene "$root/shell/mooi.plm" --no-hud --stall 0 --seconds 40 "$@" 2> "$out/scene.log" &
    pid=$!
    for _ in 1 2 3 4 5 6 7 8 9 10; do sleep 0.3; get open >/dev/null 2>&1 && break; done
}

if say "get open" >/dev/null 2>&1; then
    echo "mooi is already running; stop it first (bin/mooi stop)"; exit 2
fi

start --record rv.window,depth,rv.system > "$out/record.tsv"

echo "window island"
expect open none "starts with no island"
step "emit open_window";  expect open window "open → window island"
expect phase compact "…compact"
expect sel 0 "selection starts on Float"
step "key Right"; step "key Right"; expect sel 2 "→ → selects Pin"
step "key Left"; step "key Left"; step "key Left"; expect sel 4 "← wraps to Close"
step "key Return"; expect arming true "Close asks for confirmation first"
step "key Escape"; expect arming false "Esc cancels the confirmation first"
expect open window "…and keeps the island open"
step "key Left"; step "key Return"; expect phase expanded "Move expands"
step "key Escape"; expect phase compact "Esc collapses before it closes"
step "key Escape"; expect open none "Esc again dismisses"

echo "system island"
step "emit open_system"; expect open system "open → system island"
step "key Down"; expect srow 1 "↓ selects Brightness"
step "key Up"; expect srow 0 "↑ back to Volume"
step "key Escape"; expect open none "Esc dismisses"

echo "one slot"
step "emit open_window"; step "emit open_system"
expect open system "opening system while window is open hands the slot over"
sleep 0.3; expect_num rv.window lt 0.001 "…and the window island has left"
step "emit open_window"; expect phase compact "the window island comes back compact"
step "key Escape"

echo "interruption"
say "emit open_window" >/dev/null; sleep 0.06; say "emit open_system" >/dev/null; sleep 0.06
say "emit open_window" >/dev/null; sleep 0.6
expect open window "window → system → window inside 120 ms ends on window"
expect_num rv.system lt 0.001 "…the system island never stays half-open"
expect_num rv.window gt 0.999 "…the window island is fully there"
step "key Escape"
say "emit open_window" >/dev/null; sleep 0.06; say "emit open_window" >/dev/null; sleep 0.06
say "emit open_window" >/dev/null; sleep 0.06; say "emit open_window" >/dev/null; sleep 0.6
expect open none "four rapid toggles end closed"
expect_num rv.window lt 0.001 "…and the surface settled closed"
step "emit open_window"; sleep 0.1; step "emit open_window"; sleep 0.3
expect open none "reopen then close mid-way settles"

say quit >/dev/null 2>&1; wait "$pid" 2>/dev/null

echo "motion (1% → 99% of travel, measured)"
measure() { # column direction label target_ms
    grep -P '^[\d.]+\t' "$out/record.tsv" | awk -F'\t' -v c="$1" -v dir="$2" -v label="$3" -v want="$4" '
      { t=$1+0; v=$c+0
        if (dir=="up")   { if (v>0.01 && a==0) a=t; if (a>0 && v>=0.99 && b==0) b=t }
        if (dir=="down") { if (v>=0.99) seen=1; if (seen && v<0.99 && a==0) a=t; if (a>0 && v<=0.01 && b==0) b=t } }
      END { if (b>0) { d=b-a; ok=(d<=want*1.15+17); printf "  %s %-28s %4.0f ms (token %d ms)\n", ok?"ok   ":"FAIL ", label, d, want; exit ok?0:1 }
            else { printf "  FAIL  %-28s no complete transition recorded\n", label; exit 1 } }'
}
measure 2 up "surface.enter (window)" 180 || fail=$((fail + 1))
measure 2 down "surface.exit (window)" 140 || fail=$((fail + 1))
measure 3 up "surface.expand (depth)" 200 || fail=$((fail + 1))
measure 3 down "surface.collapse (depth)" 160 || fail=$((fail + 1))
measure 4 up "surface.enter (system)" 180 || fail=$((fail + 1))

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
echo "$n state checks + 5 motion checks, $fail failed · logs in $out"
[ "$fail" -eq 0 ]
