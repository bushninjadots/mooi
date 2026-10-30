#!/bin/sh
# The shared music feed, read by the notch and the player (D112).
#
# Starts each scene alone, in a temporary HOME and data folder (nothing of the user's is read or
# written), writes viz-levels.txt the way the bar does, and asks the scene whether its inner
# visualiser followed it: the notch's Music panel (`mv0`) and the player's ring (`nv0`). Then a
# frame that says cava is missing, and a silent frame that must rest the bars instead of freezing
# them. No media player is involved: the feed is the only input, which is the point — one producer,
# every surface.
#
# This is a compositor test, not a headless one. Run from anywhere:
#   tests/feed.sh
set -u
root=$(cd "$(dirname "$0")/.." && pwd)
out=${TMPDIR:-/tmp}/mooi-feed-test.$$
mkdir -p "$out/home" "$out/data/pleamar/mooi"
fail=0; n=0; pid=''; scene=''
viz="$out/data/pleamar/mooi/viz-levels.txt"

ok() { n=$((n + 1)); echo "  ok    $1"; }
bad() { n=$((n + 1)); fail=$((fail + 1)); echo "  FAIL  $1"; }
cleanup() {
    if [ -n "$pid" ]; then pleamar --say "$scene" quit >/dev/null 2>&1; kill "$pid" 2>/dev/null; wait "$pid" 2>/dev/null; fi
    rm -rf "$out"
}
trap cleanup EXIT INT TERM

# one line of the feed: 32 bands, bass, high, beat, phase, playing, missing, seq
feed() { # band playing missing seq
    printf 'v1 %s %s %s 700 500 %s %s %s\n' \
        "$(yes "$1" | head -32 | tr '\n' ' ' | sed 's/ $//')" "$1" "$1" "$2" "$3" "$4" > "$viz"
}
get() { pleamar --say "$scene" "get $1" 2>&1 | tail -1; }
say() { pleamar --say "$scene" "$@" >/dev/null 2>&1; }
wait_value() { # fact expected [attempts]
    i=0
    while [ "$i" -lt "${3:-40}" ]; do
        [ "$(get "$1")" = "$2" ] && return 0
        sleep 0.2; i=$((i + 1))
    done
    return 1
}
wait_between() { # fact low high [attempts]: a number inside a range
    i=0; v=none
    while [ "$i" -lt "${4:-40}" ]; do
        v=$(get "$1")
        case "$v" in
            *[!0-9.]*|'') : ;;
            *) awk -v v="$v" -v lo="$2" -v hi="$3" 'BEGIN { exit !(v >= lo && v <= hi) }' && { echo "$v"; return 0; } ;;
        esac
        sleep 0.2; i=$((i + 1))
    done
    echo "$v"
    return 1
}
start() { # scene (its data folder is mooi's, as bin/mooi links it)
    scene=$1
    ln -sfn "$out/data/pleamar/mooi" "$out/data/pleamar/$scene"
    HOME="$out/home" XDG_DATA_HOME="$out/data" pleamar --scene "$root/shell/$scene.plm" --no-hud --stall 0 \
        > "$out/$scene.log" 2>&1 &
    pid=$!
    i=0
    while [ "$i" -lt 50 ]; do
        [ -n "$(get pl_open 2>/dev/null)" ] && return 0
        [ -n "$(get nt_open 2>/dev/null)" ] && return 0
        [ -n "$(get dk_open 2>/dev/null)" ] && return 0
        sleep 0.2; i=$((i + 1))
    done
    return 1
}
stop() {
    pleamar --say "$scene" quit >/dev/null 2>&1
    kill "$pid" 2>/dev/null; wait "$pid" 2>/dev/null
    pid=''
}
until_fact() { # command, fact, expected: the logic may still be coming up, so ask again
    i=0
    while [ "$i" -lt 40 ]; do
        pleamar --say "$scene" "$1" >/dev/null 2>&1
        sleep 0.25
        [ "$(get "$2")" = "$3" ] && return 0
        i=$((i + 1))
    done
    return 1
}
no_errors() {
    if grep -qi "error" "$out/$scene.log"; then bad "errors in $scene's log: $(grep -i "error" "$out/$scene.log" | head -1)"
    else ok "no errors in its log"; fi
}

if [ -z "${WAYLAND_DISPLAY:-}" ]; then
    echo "feed: no compositor session"
    exit 2
fi

echo "the notch reads the feed"
if start mooi-notch; then ok "it opens"; else bad "it never opened"; sed -n 1,20p "$out/mooi-notch.log"; exit 1; fi
until_fact "emit nt_show 1" nt_tab 1 && ok "the Music panel is open" || bad "the Music panel did not open (nt_tab $(get nt_tab))"
# The file watch can coalesce two quick writes, and a real producer writes thirty times a second,
# so a surface recovers on the next frame either way; here the same line is simply written again.
write_until() { # fact low high band playing missing
    i=0; v=none
    while [ "$i" -lt 5 ]; do
        feed "$4" "$5" "$6" $((30 + i))
        sleep 0.8
        v=$(get "$1")
        case "$v" in
            *[!0-9.]*|'') : ;;
            *) awk -v v="$v" -v lo="$2" -v hi="$3" 'BEGIN { exit !(v >= lo && v <= hi) }' && { echo "$v"; return 0; } ;;
        esac
        i=$((i + 1))
    done
    echo "$v"
    return 1
}
write_until_true() { # fact band playing missing
    i=0
    while [ "$i" -lt 5 ]; do
        feed "$2" "$3" "$4" $((30 + i))
        sleep 0.8
        [ "$(get "$1")" = true ] && return 0
        i=$((i + 1))
    done
    return 1
}
if v=$(write_until mv0 0.7 0.9 800 1 0); then ok "mv0 follows the line ($v)"; else bad "mv0 did not follow it ($v)"; fi
write_until_true mu_viz_missing 800 1 1 && ok "a missing frame says so" || bad "mu_viz_missing stayed $(get mu_viz_missing)"
feed 0 0 0 3
if wait_value mv0 0 >/dev/null; then ok "a silent frame rests it"; else bad "mv0 stayed at $(get mv0)"; fi
no_errors
stop

echo "the player reads the feed"
if start mooi-player; then ok "it opens"; else bad "it never opened"; sed -n 1,20p "$out/mooi-player.log"; exit 1; fi
# the player's ring rests unless it is up and playing; the feed supplies the rest
until_fact "fact pstate playing" pstate playing && ok "it is playing" || bad "pstate stayed $(get pstate)"
feed 800 1 0 4
if v=$(wait_between nv0 0.7 0.9); then ok "nv0 follows the line ($v)"; else bad "nv0 did not follow it ($v)"; fi
feed 0 0 0 5
if v=$(wait_between nv0 0.02 0.04); then ok "a silent frame rests it ($v)"; else bad "nv0 stayed at $v"; fi
no_errors
stop

echo
echo "$n checks, $fail failed"
[ "$fail" -eq 0 ]
