#!/bin/sh
# The Pill live (D168): on the running mooi, Shape → Pill, then real things happen and the Pill is asked
# what it shows (`pleamar --say mooi get …`): idle and music with the player, a volume change as a moon
# for two seconds and as the split partner, the side groups hidden, a press, its faces (D169), hiding
# when idle and nodes, the board it unfolds into (D170: rooms, a switch pad, edit, the face, music,
# Escape, the right press; SHOTS=dir keeps screenshots), and back to Islands with the centre
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
# PIPE too: a run killed by a closed pipe left the Pill's settings behind once (sh skips EXIT on a signal)
trap 'exit 130' INT TERM HUP PIPE

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

echo "a press reaches the logic (it once never left the scene): the board unfolds (D170)"
set_ '.bar.mode="pill" | .pill.sides="show" | .pill.face="time" | .pill.autohide=false'
playerctl -a pause >/dev/null 2>&1
# wait for the pause to reach the Pill: pressed while it still shows music, it opens the player
i=0; while [ "$(get pill_kind)" != 0 ] && [ $i -lt 20 ]; do sleep 0.25; i=$((i + 1)); done
# seen open at any moment of a second, and pressed once more if not: an open island's dismiss zone
# covers the screen, so a click elsewhere by whoever is at the desk can close it at once. Closing it
# mid-run was seen intermittently in the full run (never alone, 12 of 12) and is not yet explained.
seen=none
for try in 1 2; do
    pleamar --say mooi "emit pill_press" >/dev/null 2>&1
    i=0; while [ $i -lt 10 ]; do o=$(get open); [ "$o" = board ] && seen=board && break; sleep 0.1; i=$((i + 1)); done
    [ "$seen" = board ] && break
    echo "  ..    the board did not stay open; pressing again"
done
is "idle, pressed: the board unfolds" "$seen" board
pleamar --say mooi "fact open none" >/dev/null 2>&1; sleep 0.4
pleamar --say mooi "emit pill_rpress" >/dev/null 2>&1; sleep 0.5
is "right press: the calendar, as before" "$(get open)" calendar
pleamar --say mooi "fact open none" >/dev/null 2>&1

echo "its face (D169)"
set_ '.bar.mode="pill" | .pill.face="bmo" | .pill.autohide=false'
is "BMO's face" "$(get pill_face)" 1
pleamar --say mooi "emit pill_press" >/dev/null 2>&1; sleep 0.8
# D170: a press opens the board and he says hi; the Pill widens past his 72 px face to fit it
w=$(get pill_w); w=${w%.*}
[ "${w:-0}" -gt 72 ] && ok "a press: he greets the board (the Pill is $w px)" || bad "a press: no greeting (pill_w $w)"
pleamar --say mooi "emit pill_press" >/dev/null 2>&1; sleep 0.5
is "pressed again while open: a poke, the board stays" "$(get open)" board
[ -n "${SHOTS:-}" ] && grim -g "560,0 800x60" "$SHOTS/bmo.png"
pleamar --say mooi "fact open none" >/dev/null 2>&1
set_ '.bar.mode="pill" | .pill.face="nexus"'
is "the Nexus button" "$(get pill_face)" 2

echo "hidden when idle (D169)"
# D172 replaced pill.autohide with the three-way pill.hide; a file that carries an explicit hide keeps it
set_ '.bar.mode="pill" | .pill.face="time" | .pill.hide="tuck" | .pill.off=["battery","record","notify","music","osd"]'
# a hover emitted by the section above stays held until the pointer really leaves, and this run never moves
# it: clear it, so what is checked is the Pill's own resting mode (it held it peeked and never hid)
pleamar --say mooi "emit pill_hover 0" >/dev/null 2>&1; sleep 0.6
is "idle: a sliver" "$(get pill_hidden)" true
is "44 px wide" "$(jq '.pill.w' "$D/bar-geo.json")" 44
is "the chassis is told" "$(jq '.pill.slim' "$D/bar-geo.json")" true
pleamar --say mooi "emit pill_hover" >/dev/null 2>&1; sleep 0.8
is "pointed at: back" "$(get pill_hidden)" false
sleep 4.5
is "and away again after 4 s" "$(get pill_hidden)" true

echo "when idle: stay, tuck, vanish — and the record (D172)"
set_ '.bar.mode="pill" | .pill.face="time" | .pill.shape="attached" | .pill.hide="stay" | .pill.autohide=false | .pill.off=["battery","record","notify","music","osd"]'
pleamar --say mooi "emit pill_hover 0" >/dev/null 2>&1; sleep 0.6
is "stay: never tucked away" "$(get pill_hidden)" false
set_ '.bar.mode="pill" | .pill.face="time" | .pill.hide="tuck" | .pill.off=["battery","record","notify","music","osd"]'
is "tuck: the sliver" "$(get pill_hidden)/$(jq '.pill.w' "$D/bar-geo.json")" true/44
set_ '.bar.mode="pill" | .pill.face="time" | .pill.hide="vanish" | .pill.off=["battery","record","notify","music","osd"]'
is "vanish: gone, and no width" "$(get pill_hidden)/$(get pill_vanish)/$(jq '.pill.w' "$D/bar-geo.json")" true/true/0
pleamar --say mooi "emit pill_call" >/dev/null 2>&1; sleep 0.6
is "called: back" "$(get pill_hidden)" false
sleep 4.5
is "and gone again after the peek" "$(get pill_hidden)/$(get pill_vanish)" true/true
if playerctl status >/dev/null 2>&1; then
    set_ '.bar.mode="pill" | .pill.face="time" | .pill.shape="record" | .pill.hide="stay" | .pill.autohide=false'
    playerctl play >/dev/null 2>&1; sleep 2.5
    is "a disc, not a capsule" "$(get pill_shape)/$(get pill_record)/$(jq -r '.pill.shape' "$D/bar-geo.json")" 3/true/record
    w=$(get pill_w); h=$(get pill_h)
    [ "${w%.*}" = "${h%.*}" ] && ok "the disc is square ($w × $h)" || bad "the disc is not square ($w × $h)"
    [ -n "${SHOTS:-}" ] && grim -g "860,0 220x60" "$SHOTS/record.png"
    playerctl -a pause >/dev/null 2>&1; sleep 1.5
else
    echo "  ..    no player: the record skipped"
fi
set_ '.bar.mode="pill" | .pill.face="time" | .pill.shape="attached" | .pill.hide="stay"'

echo "nodes (D169)"
set_ '.bar.mode="pill" | .pill.multi="nodes" | .pill.autohide=false'
is "pads on traces" "$(jq '.nodes' "$D/bar-geo.json")" true

echo "the board (D170)"
set_ '.bar.mode="pill" | .pill.sides="show" | .pill.face="time" | .pill.autohide=false | .pill.pads=["volume","clock","weather","caffeine"] | .pill.viz="halo"'
playerctl -a pause >/dev/null 2>&1
i=0; while [ "$(get pill_kind)" != 0 ] && [ $i -lt 20 ]; do sleep 0.25; i=$((i + 1)); done
caf=$(get caffeine_on)
shot() { [ -n "${SHOTS:-}" ] && grim -g "460,0 1000x560" "$SHOTS/$1.png"; }
pleamar --say mooi "emit pill_press" >/dev/null 2>&1; sleep 1.2
is "open on Now" "$(get open)/$(get pk_room)" board/0
is "its four pads" "$(get pk_n)" 4
shot board
pleamar --say mooi "emit pk_pad 0" >/dev/null 2>&1; sleep 0.6
is "the volume pad: Sound" "$(get pk_room)" 2
shot sound
pleamar --say mooi "emit pk_pad 2" >/dev/null 2>&1; sleep 0.6
is "the weather pad: Weather" "$(get pk_room)" 7
pleamar --say mooi "emit pk_key 3" >/dev/null 2>&1; sleep 0.4
is "Escape: back to Now" "$(get pk_room)/$(get open)" 0/board
pleamar --say mooi "emit pk_pad 3" >/dev/null 2>&1; sleep 0.8
[ "$(get caffeine_on)" != "$caf" ] && ok "a switch pad acts in place (keep awake)" || bad "keep awake did not change"
pleamar --say mooi "emit pk_pad 3" >/dev/null 2>&1; sleep 0.8
is "and back" "$(get caffeine_on)" "$caf"
pleamar --say mooi "emit pk_edit_cmd 0" >/dev/null 2>&1; sleep 0.5
is "edit" "$(get pk_edit)" true
pleamar --say mooi "emit pk_part 3" >/dev/null 2>&1; sleep 0.8
is "a part added and saved" "$(jq -c '.pill.pads' "$F")" '["volume","clock","weather","caffeine","resources"]'
shot edit
pleamar --say mooi "emit pk_edit_cmd 14" >/dev/null 2>&1; sleep 0.8
is "× takes it off" "$(jq '.pill.pads | length' "$F")" 4
pleamar --say mooi "emit pk_face 3" >/dev/null 2>&1; sleep 1.5
is "the face: weather, saved" "$(jq -r '.pill.face' "$F")/$(get pill_face)" weather/3
pleamar --say mooi "emit pk_key 3" >/dev/null 2>&1; sleep 0.4
is "Escape leaves edit" "$(get pk_edit)" false
pleamar --say mooi "emit pk_key 3" >/dev/null 2>&1; sleep 0.6
is "Escape again: it folds away" "$(get open)" none
if playerctl status >/dev/null 2>&1; then
    playerctl play >/dev/null 2>&1; sleep 2.5
    pleamar --say mooi "emit pill_press" >/dev/null 2>&1; sleep 1.5
    is "music: Now Playing" "$(get pk_music)/$(get pk_room)" true/0
    shot halo
    pleamar --say mooi "emit pk_viz" >/dev/null 2>&1; sleep 1.5
    is "the river" "$(get pk_viz)" 1
    shot river
    pleamar --say mooi "fact open none" >/dev/null 2>&1
    playerctl -a pause >/dev/null 2>&1
else
    echo "  ..    no player: Now Playing skipped"
fi

echo "views, shapes and Super (D171)"
set_ '.bar.mode="pill" | .pill.face="time" | .pill.shape="attached" | .pill.autohide=false | .pill.views=["time","weather","workspaces"] | .pill.rest=2'
playerctl -a pause >/dev/null 2>&1; i=0; while [ "$(get pill_kind)" != 0 ] && [ $i -lt 20 ]; do sleep 0.25; i=$((i + 1)); done
pleamar --say mooi "emit pill_scroll -1" >/dev/null 2>&1; sleep 0.6
is "the wheel turns to the next view (weather)" "$(get pill_face)" 3
pleamar --say mooi "emit pill_scroll -1" >/dev/null 2>&1; sleep 0.6
is "and the next (workspaces)" "$(get pill_face)" 7
sleep 3
is "back to its face after pill.rest" "$(get pill_face)" 0
set_ '.bar.mode="pill" | .pill.face="time" | .pill.shape="dot" | .pill.autohide=false'
sleep 4.5
is "the dot: idle, a dot" "$(get pill_hidden)/$(get pill_w)" true/14
is "the chassis is told" "$(jq -r '.pill.shape' "$D/bar-geo.json")" dot
pleamar --say mooi "emit pill_call" >/dev/null 2>&1; sleep 0.6
is "Super: it comes back" "$(get pill_hidden)" false
pleamar --say mooi "emit pill_call" >/dev/null 2>&1; sleep 1
is "Super twice: the board" "$(get open)" board
pleamar --say mooi "emit pk_key 3" >/dev/null 2>&1; sleep 0.4

echo "back to Islands"
cp "$t/restore.json" "$F.tmp" && jq '.bar.mode="islands"' "$F.tmp" > "$F" && rm -f "$F.tmp"; sleep 3
is "Pill mode is off" "$(get pill_on)" false
first=$(jq -r '.bar.center[0] // empty' "$t/restore.json" | cut -d+ -f1)
if [ -n "$first" ]; then is "the centre group is back ($first)" "$(get "p_$first")" true; fi

echo "$n checks, $fail failed"
[ "$fail" -eq 0 ]
