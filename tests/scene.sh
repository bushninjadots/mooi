#!/bin/sh
# Drives the real scene through its lifecycle and checks the state after each step,
# then measures how long the island's springs take against their tokens.
#
# It runs Tidal on screen for ~15 s and the island holds the keyboard while open.
# It never runs a Hyprland action (no Return on float/fullscreen/pin/close, no send).
# Run from anywhere: tests/scene.sh
set -u
root=$(cd "$(dirname "$0")/.." && pwd)
out=${TMPDIR:-/tmp}/tidal-scene-test.$$
mkdir -p "$out"
fail=0; n=0

say() { pleamar --say tidal "$@" 2>&1; }
get() { say "get $1" | tail -1; }
expect() { # name value [what]
    n=$((n + 1)); got=$(get "$1")
    if [ "$got" = "$2" ]; then echo "  ok    ${3:-$1 = $2}"
    else echo "  FAIL  ${3:-$1}: expected '$2', got '$got'"; fail=$((fail + 1)); fi
}
expect_zero() { # name what
    n=$((n + 1)); got=$(get "$1")
    if awk -v v="$got" 'BEGIN { exit !(v + 0 < 0.001 && v != "") }'; then echo "  ok    $2"
    else echo "  FAIL  $2: expected 0, got '$got'"; fail=$((fail + 1)); fi
}
step() { say "$@" >/dev/null; sleep 0.35; }

if pleamar --say tidal "get phase" >/dev/null 2>&1; then
    echo "a Tidal is already running; stop it first (bin/tidal stop)"; exit 2
fi

TIDAL_SAFE=1 pleamar --scene "$root/shell/tidal.plm" --no-hud --stall 0 --seconds 30 \
    --record reveal,depth > "$out/record.tsv" 2> "$out/scene.log" &
pid=$!
for _ in 1 2 3 4 5 6 7 8 9 10; do sleep 0.3; get phase >/dev/null 2>&1 && break; done

echo "lifecycle"
expect phase hidden "starts hidden"
step "emit open_window";  expect phase compact "open → compact"
expect sel 0 "selection starts on Float"
step "key Right"; step "key Right"; expect sel 2 "→ → selects Pin"
step "key Left"; step "key Left"; step "key Left"; expect sel 4 "← wraps to Close"
step "key Return"; expect arming true "Close asks for confirmation first"
step "key Escape"; expect arming false "Esc cancels the confirmation"
expect phase compact "…and keeps the island open"
step "key Left"; step "key Return"; expect phase expanded "Move expands"
step "key Escape"; expect phase compact "Esc collapses back"
step "key Escape"; expect phase hidden "Esc again dismisses"

echo "interruption"
say "emit open_window" >/dev/null; sleep 0.06; say "emit open_window" >/dev/null; sleep 0.06
say "emit open_window" >/dev/null; sleep 0.06; say "emit open_window" >/dev/null; sleep 0.6
expect phase hidden "four rapid toggles end hidden"
expect_zero reveal "…and the surface settled closed"
step "emit open_window"; sleep 0.2; step "emit open_window"; sleep 0.4
expect phase hidden "reopen then close mid-way settles"
step "emit open_window"; expect phase compact "opens again cleanly"
step "key Escape"

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
measure 2 up "surface.enter (reveal)" 180 || fail=$((fail + 1))
measure 2 down "surface.exit (reveal)" 140 || fail=$((fail + 1))
measure 3 up "surface.expand (depth)" 200 || fail=$((fail + 1))
measure 3 down "surface.collapse (depth)" 160 || fail=$((fail + 1))

echo
echo "$n state checks + 4 motion checks, $fail failed · logs in $out"
[ "$fail" -eq 0 ]
