#!/bin/sh
# The Pill live (D168): on the running mooi, Shape → Pill, then real things happen and the Pill is asked
# what it shows (`pleamar --say mooi get …`): idle and music with the player, a volume change as a moon
# for two seconds and as the split partner, the side groups hidden, and back to Islands with the centre
# modules where they were. Restores settings.json byte for byte, the exact volume and mute, and the
# player as it was. Never moves the pointer.
set -u
root=$(cd "$(dirname "$0")/.." && pwd)
for c in jq wpctl playerctl; do command -v "$c" >/dev/null 2>&1 || { echo "pill: $c is required"; exit 2; }; done
"$root/bin/mooi" status 2>/dev/null | grep -q "the desktop" || { echo "pill: mooi is not running as the desktop"; exit 2; }
D="${XDG_DATA_HOME:-$HOME/.local/share}/pleamar/mooi"
F="$D/settings.json"
t=$(mktemp -d)
cp "$F" "$t/restore.json"
was=$(playerctl status 2>/dev/null || echo none)
# every player, not just the default: mooi shows whichever one is playing
: > "$t/players"
for p in $(playerctl -l 2>/dev/null); do printf '%s %s\n' "$p" "$(playerctl -p "$p" status 2>/dev/null || echo none)" >> "$t/players"; done
vol=$(wpctl get-volume @DEFAULT_AUDIO_SINK@ | awk '{ print $2 }')
muted=$(wpctl get-volume @DEFAULT_AUDIO_SINK@ | grep -c MUTED)
restore() {
    cp "$t/restore.json" "$F"
    wpctl set-volume @DEFAULT_AUDIO_SINK@ "$vol"
    [ "$muted" = 1 ] && wpctl set-mute @DEFAULT_AUDIO_SINK@ 1
    if [ "$was" = Playing ]; then playerctl play >/dev/null 2>&1; else playerctl pause >/dev/null 2>&1; fi
    while read -r p s; do
        case $s in Playing) playerctl -p "$p" play >/dev/null 2>&1 ;; *) playerctl -p "$p" pause >/dev/null 2>&1 ;; esac
    done < "$t/players"
    rm -rf "$t"
}
trap 'restore' EXIT
trap 'exit 130' INT TERM HUP

fail=0; n=0
ok()  { n=$((n + 1)); echo "  ok    $1"; }
bad() { n=$((n + 1)); fail=$((fail + 1)); echo "  FAIL  $1"; }
is()  { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1 ('$2', expected '$3')"; fi }
get() { pleamar --say mooi "get $1" 2>/dev/null; }
set_() { jq "$1" "$t/restore.json" > "$F.tmp" && mv "$F.tmp" "$F"; sleep 3; }

echo "the Pill, with the side groups"
set_ '.bar.mode="pill" | .pill.sides="show" | .pill.multi="satellites" | .pill.off=[] | .pill.order=["battery","record","notify","music","osd","idle"]'
is "Pill mode is on" "$(get pill_on)" true
playerctl -a pause >/dev/null 2>&1; sleep 1.5
is "nothing playing: the time and workspaces" "$(get pill_kind)" 0
if playerctl status >/dev/null 2>&1; then
    playerctl play >/dev/null 2>&1; sleep 2
    is "playing: music" "$(get pill_kind)" 1
    wpctl set-volume @DEFAULT_AUDIO_SINK@ 1%+; sleep 0.6
    is "a volume change: a moon beside the music" "$(get moon_k0)" 2
    sleep 2.6
    is "two seconds on: the moon is gone" "$(get moon_k0)" -1
    set_ '.bar.mode="pill" | .pill.sides="show" | .pill.multi="split"'
    wpctl set-volume @DEFAULT_AUDIO_SINK@ 1%-; sleep 0.6
    is "split: the volume shares the Pill" "$(get pill_split)" true
    is "split: music stays the main" "$(get pill_kind)" 1
else
    echo "  ..    no player: music, volume and split cases skipped"
fi
islands=$(jq '.islands | length' "$D/bar-geo.json")
[ "$islands" -gt 0 ] && ok "the side groups are islands ($islands)" || bad "no side islands with sides = show"

echo "the Pill alone"
set_ '.bar.mode="pill" | .pill.sides="hide"'
is "no side islands" "$(jq '.islands | length' "$D/bar-geo.json")" 0
[ "$(jq '.pill.w' "$D/bar-geo.json")" -gt 0 ] && ok "the Pill is placed" || bad "no Pill in bar-geo.json"

echo "back to Islands"
cp "$t/restore.json" "$F.tmp" && jq '.bar.mode="islands"' "$F.tmp" > "$F" && rm -f "$F.tmp"; sleep 3
is "Pill mode is off" "$(get pill_on)" false
first=$(jq -r '.bar.center[0] // empty' "$t/restore.json" | cut -d+ -f1)
if [ -n "$first" ]; then is "the centre group is back ($first)" "$(get "p_$first")" true; fi

echo "$n checks, $fail failed"
[ "$fail" -eq 0 ]
