#!/bin/sh
# Control Nexus (D65), isolated lifecycle smoke test.
#
# Starts a test copy of the bar and Nexus with a temporary HOME and XDG data/config folders.
# It does not change volume, brightness, workspaces, wallpapers, notifications, or the user's
# settings. It refuses to run if a real mooi or Nexus instance is already answering.
#
# This is a compositor/live test, not a headless test. Run from anywhere:
#   tests/nexus.sh
set -u
root=$(cd "$(dirname "$0")/.." && pwd)
out=${TMPDIR:-/tmp}/mooi-nexus-test.$$
mkdir -p "$out"
fail=0; n=0; pid=''

say() { pleamar --say mooi-nexus "$@" 2>&1; }
get() { say "get $1" | tail -1; }
bsay() { pleamar --say mooi "$@" 2>&1; }
bget() { bsay "get $1" | tail -1; }
ok() { n=$((n + 1)); echo "  ok    $1"; }
bad() { n=$((n + 1)); fail=$((fail + 1)); echo "  FAIL  $1"; }
is() { if [ "$2" = "$3" ]; then ok "$1 ($2)"; else bad "$1 (got '$2', expected '$3')"; fi; }

cleanup() {
    bsay quit >/dev/null 2>&1
    say quit >/dev/null 2>&1
    if [ -n "$pid" ]; then kill "$pid" 2>/dev/null; wait "$pid" 2>/dev/null; fi
    rm -rf "$out"
}
trap cleanup EXIT INT TERM

wait_value() { # scene-name, fact, expected, attempts
    scene=$1; fact=$2; expected=$3; tries=${4:-60}
    i=0
    while [ "$i" -lt "$tries" ]; do
        if [ "$scene" = bar ]; then got=$(bget "$fact"); else got=$(get "$fact"); fi
        [ "$got" = "$expected" ] && return 0
        sleep 0.2
        i=$((i + 1))
    done
    return 1
}
wait_gone() {
    for _ in $(seq 1 60); do
        if ! say "get nx_open" >/dev/null 2>&1; then return 0; fi
        sleep 0.2
    done
    return 1
}
wait_up() {
    for _ in $(seq 1 60); do
        if say "get nx_open" >/dev/null 2>&1; then
            sleep 0.2
            say "get nx_open" >/dev/null 2>&1 && return 0
        fi
        sleep 0.2
    done
    return 1
}

if bsay "get open" >/dev/null 2>&1; then
    echo "mooi is already running; stop it first (bin/mooi stop)"
    exit 2
fi
if say "get nx_open" >/dev/null 2>&1; then
    echo "Control Nexus is already open; close it first (Escape)"
    exit 2
fi

# Isolate all user data used by the two scenes. The Nexus scene expects its own data-folder
# name, linked to the same temporary mooi folder as bin/mooi would link in a normal launch.
mkdir -p "$out/home" "$out/data/pleamar/mooi" "$out/config"
ln -s "$out/data/pleamar/mooi" "$out/data/pleamar/mooi-nexus"

echo "start an isolated bar scene"
HOME="$out/home" XDG_DATA_HOME="$out/data" XDG_CONFIG_HOME="$out/config" \
    MOOI_SAFE=1 MOOI_SHELL="$root/shell" \
    pleamar --scene "$root/shell/mooi.plm" --no-hud --stall 0 --seconds 90 \
    >"$out/bar.log" 2>&1 &
pid=$!

if wait_value bar open none 30; then
    ok "bar scene answers in the temporary environment"
else
    bad "bar scene did not become ready"
    cat "$out/bar.log"
    exit 1
fi

echo "open and close from the Arch-mark event"
bsay "emit open_nexus" >/dev/null
if wait_up; then ok "the Nexus program starts"; else bad "the Nexus program did not start"; cat "$out/bar.log"; exit 1; fi
is "the bar marks Nexus as open" "$(bget nexus_open)" true
is "pin defaults to off" "$(get nx_pinned)" false

bsay "emit open_nexus" >/dev/null
if wait_gone; then ok "the same trigger closes the program"; else bad "the same trigger left Nexus running"; fi
if wait_value bar nexus_open false 30; then ok "the bar clears its open state"; else bad "the bar kept a stale open state"; fi

echo "reopen and close with Escape"
bsay "emit open_nexus" >/dev/null
if wait_up; then ok "Nexus can reopen after closing"; else bad "Nexus failed to reopen"; exit 1; fi
say "key Escape" >/dev/null
if wait_gone; then ok "Escape closes and exits Nexus"; else bad "Escape did not close Nexus"; fi
if wait_value bar nexus_open false 30; then ok "the bar clears state after Escape"; else bad "the bar kept stale state after Escape"; fi

echo
echo "$n checks, $fail failed"
[ "$fail" -eq 0 ]
