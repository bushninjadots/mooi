#!/bin/sh
# The Sigil live (D207): on the running mooi, sigil.pill = sigil, then it is asked what it shows
# (`pleamar --say mooi-sigil get …`): nothing running in classic mode, the Pill host drawn and the bar's
# classic Pill off, each resting source, the display on hover and gone after, an island host beside the Pill
# showing something else, music and the cover's colour, a crash loop and the bar's stand-in clock, and the
# frame budget with music playing (SHOTS=dir keeps screenshots). Restores settings.json byte for byte, the
# volume and mute, and the players as they were. Never moves the pointer.
set -u
root=$(cd "$(dirname "$0")/.." && pwd)
for c in jq wpctl playerctl grim; do command -v "$c" >/dev/null 2>&1 || { echo "sigil: $c is required"; exit 2; }; done
"$root/bin/mooi" status 2>/dev/null | grep -q "the desktop" || { echo "sigil: mooi is not running as the desktop"; exit 2; }
D="${XDG_DATA_HOME:-$HOME/.local/share}/pleamar/mooi"
F="$D/settings.json"
L="${XDG_STATE_HOME:-$HOME/.local/state}/mooi/mooi.log"
t=$(mktemp -d)
cp "$F" "$t/restore.json"
: > "$t/players"
for p in $(playerctl -l 2>/dev/null); do printf '%s %s\n' "$p" "$(playerctl -p "$p" status 2>/dev/null || echo none)" >> "$t/players"; done
vol=$(wpctl get-volume @DEFAULT_AUDIO_SINK@ | awk '{ print $2 }')
muted=$(wpctl get-volume @DEFAULT_AUDIO_SINK@ | grep -c MUTED)
restore() {
    cp "$t/restore.json" "$F"
    wpctl set-volume @DEFAULT_AUDIO_SINK@ "$vol"
    [ "$muted" = 1 ] && wpctl set-mute @DEFAULT_AUDIO_SINK@ 1
    while read -r p s; do
        case $s in Playing) playerctl -p "$p" play >/dev/null 2>&1 ;; *) playerctl -p "$p" pause >/dev/null 2>&1 ;; esac
    done < "$t/players"
    rm -rf "$t"
}
trap 'restore' EXIT
trap 'exit 130' INT TERM HUP PIPE

fail=0; n=0
ok()  { n=$((n + 1)); echo "  ok    $1"; }
bad() { n=$((n + 1)); fail=$((fail + 1)); echo "  FAIL  $1"; }
is()  { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1 ('$2', expected '$3')"; fi }
sg()  { timeout 3 pleamar --say mooi-sigil "get $1" 2>/dev/null; }
bar() { timeout 3 pleamar --say mooi "get $1" 2>/dev/null; }
set_() { jq "$1" "$t/restore.json" > "$F.tmp" && mv "$F.tmp" "$F"; sleep "${2:-3}"; }
pid() { for p in $(pgrep -x pleamar); do tr '\0' ' ' < "/proc/$p/cmdline" 2>/dev/null | grep -q 'mooi-sigil\.plm' && echo "$p"; done; }
shot() { [ -n "${SHOTS:-}" ] && grim -g "$2" "$SHOTS/$1.png"; }
within() { awk -v v="$1" -v a="$2" -v b="$3" 'BEGIN { exit !(v >= a - 0.5 && v <= b + 0.5) }'; }

echo "classic mode, no Sigil module: nothing runs"
set_ '.bar.mode="pill" | .sigil.pill="classic"' 4
is "mooi-sigil is not running" "$(pid)" ""

echo "the Sigil in the Pill"
set_ '.bar.mode="pill" | .sigil.pill="sigil" | .sigil.rest="clock"' 5
is "it has a host" "$(sg h0_on)" true
is "the bar heard it is up" "$(bar sigil_up)" true
is "the classic Pill steps aside" "$(bar pill_on)" false
px=$(bar pill_x); pw=$(bar pill_w)
for i in 0 31 63; do
    x=$(sg "h0_tx$i")
    if within "$x" "$px" "$((px + pw))"; then ok "point $i inside the Pill ($x)"; else bad "point $i inside the Pill ($x not in $px…$((px + pw)))"; fi
done
shot pill-clock "$((px - 120)),0 $((pw + 240))x50"

echo "each resting source"
for pair in clock:1 calendar:2 workspaces:7 bmo:13; do
    id=${pair%%:*}; want=${pair##*:}
    set_ ".bar.mode=\"pill\" | .sigil.pill=\"sigil\" | .sigil.rest=\"$id\"" 3
    playerctl -a pause >/dev/null 2>&1; sleep 1
    is "at rest on $id" "$(sg h0_src)" "$want"
    shot "rest-$id" "$((px - 120)),0 $((pw + 240))x50"
done

echo "the display, on hover"
set_ '.bar.mode="pill" | .sigil.pill="sigil" | .sigil.rest="clock"' 3
timeout 3 pleamar --say mooi-sigil "emit sg_hover 1" >/dev/null 2>&1; sleep 1.2
is "hovered: the display" "$(sg h0_form)" 2
d=$(sg h0_drop); if awk -v v="$d" 'BEGIN { exit !(v > 0.5) }'; then ok "the display's surface is open"; else bad "the display's surface is open ($d)"; fi
shot display-clock "$((px - 260)),0 $((pw + 520))x290"
timeout 3 pleamar --say mooi-sigil "emit sg_hover 0" >/dev/null 2>&1; sleep 1.5
is "left: compact again" "$(sg h0_form)" 1
d=$(sg h0_drop); if awk -v v="$d" 'BEGIN { exit !(v < 0.02) }'; then ok "the display's surface closes"; else bad "the display's surface closes ($d)"; fi

echo "an island host beside the Pill"
right=$(jq -c '.bar.right + ["sigil"]' "$t/restore.json")
set_ ".bar.mode=\"pill\" | .pill.sides=\"show\" | .sigil.pill=\"sigil\" | .sigil.rest=\"clock\" | .bar.right=$right" 5
is "the island has a host" "$(sg h1_on)" true
a=$(sg h0_src); b=$(sg h1_src)
if [ -n "$a" ] && [ "$a" != "$b" ]; then ok "it shows something else ($a / $b)"; else bad "it shows something else ($a / $b)"; fi

echo "music, and the cover's colour"
set_ '.bar.mode="pill" | .sigil.pill="sigil" | .sigil.rest="clock"' 3
if playerctl status >/dev/null 2>&1; then
    playerctl play >/dev/null 2>&1; sleep 4
    # a real notice arriving now rightly outranks music for 6 s (the director): wait it out, once
    [ "$(sg h0_src)" = 6 ] && sleep 6.5
    is "playing: music" "$(sg h0_src)" 4
    r=$(sg h0_r); c=$(bar pc1_r)
    if awk -v a="$r" -v b="$c" 'BEGIN { exit !(a - b < 0.04 && b - a < 0.04) }'; then ok "the cover's colour ($r ≈ $c)"; else bad "the cover's colour ($r vs $c)"; fi
    timeout 3 pleamar --say mooi-sigil "emit sg_hover 1" >/dev/null 2>&1; sleep 1.2
    shot display-music "$((px - 260)),0 $((pw + 520))x290"
    timeout 3 pleamar --say mooi-sigil "emit sg_hover 0" >/dev/null 2>&1; sleep 1
    echo "the budget, with music playing"
    timeout 30 pleamar --report mooi-sigil --seconds 8 --out "$t/report.txt" >/dev/null 2>&1
    cp=$(awk -F'|' '/^\| compose/ { c = $3 } /^\| paint/ { p = $3 } END { printf "%.3f", c + p }' "$t/report.txt")
    if awk -v v="$cp" 'BEGIN { exit !(v > 0 && v < 1.0) }'; then ok "compose + paint under 1 ms ($cp ms)"; else bad "compose + paint under 1 ms ($cp ms)"; fi
    [ -n "${SHOTS:-}" ] && cp "$t/report.txt" "$SHOTS/report.txt"
    playerctl pause >/dev/null 2>&1
else
    echo "  (no player: music, the cover's colour and the budget not checked)"
fi

echo "a crash loop: the bar's clock stands in"
before=$(grep -c "sigil · gave up" "$L" 2>/dev/null); before=${before:-0}
k=0
while [ $k -lt 6 ]; do
    p=$(pid); [ -n "$p" ] && kill -9 "$p" 2>/dev/null
    k=$((k + 1)); w=0
    # mooi waits 1 s more after each quick end (up to 5 s) before starting it again
    while [ -z "$(pid)" ] && [ $w -lt 16 ]; do sleep 0.5; w=$((w + 1)); done
done
sleep 7
after=$(grep -c "sigil · gave up" "$L" 2>/dev/null); after=${after:-0}
if [ "$after" -gt "$before" ]; then ok "mooi gave up after five quick ends"; else bad "mooi gave up after five quick ends"; fi
is "the bar knows it is down" "$(bar sigil_up)" false
shot fallback "$((px - 120)),0 $((pw + 240))x50"

echo
echo "$n checks, $fail failed"
[ "$fail" -eq 0 ]
