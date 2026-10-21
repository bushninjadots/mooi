#!/bin/sh
# The media transport, live: a real MPRIS player (VLC, with two tagged files) and the real
# scene. The bar's reading is checked against the player itself, and each transport command
# is checked twice — what mooi shows, and what the player says it is doing.
#
# Needs playerctl, vlc and ffmpeg. Stop mooi first (bin/mooi stop): it talks to the scene by
# name and shows it on screen. Leaves nothing behind; VLC and the scene are its own.
# Run from anywhere: tests/media.sh
set -u
root=$(cd "$(dirname "$0")/.." && pwd)
out=${TMPDIR:-/tmp}/mooi-media.$$
mkdir -p "$out"
fail=0; n=0
scene_pid=''
vlc_pid=''
player=''

say() { pleamar --say mooi "$@" 2>&1; }
get() { say "get $1" | tail -1; }
ok() { n=$((n + 1)); echo "  ok    $1"; }
bad() { n=$((n + 1)); fail=$((fail + 1)); echo "  FAIL  $1"; }
is() { if [ "$2" = "$3" ]; then ok "$1 ($2)"; else bad "$1 (got '$2', expected '$3')"; fi }
cleanup() {
    [ -n "$scene_pid" ] && { say quit >/dev/null 2>&1; kill "$scene_pid" 2>/dev/null; }
    [ -n "$vlc_pid" ] && kill "$vlc_pid" 2>/dev/null
}
trap cleanup EXIT INT TERM

for tool in playerctl vlc ffmpeg; do
    command -v "$tool" >/dev/null 2>&1 || { echo "media: $tool is required"; exit 2; }
done
if say "get open" >/dev/null 2>&1; then
    echo "mooi is already running; stop it first (bin/mooi stop)"; exit 2
fi
if playerctl -l 2>/dev/null | grep -q '^vlc'; then
    echo "a VLC player is already running; close it first (the test starts its own)"; exit 2
fi
# The media service reports the player that is playing; another one playing would be chosen
# instead of the test's VLC, and every check after that would be about the wrong player.
for p in $(playerctl -l 2>/dev/null); do
    [ "$(playerctl -p "$p" status 2>/dev/null)" = Playing ] && { echo "another player is playing ($p); stop it first"; exit 2; }
done

# Two files whose titles are their tags: VLC reports a WAV's path, not a title.
ffmpeg -hide_banner -loglevel error -y -f lavfi -i "sine=frequency=440:duration=30" \
    -metadata title=Alpha -metadata artist=Mooi -c:a flac "$out/a.flac" || exit 1
ffmpeg -hide_banner -loglevel error -y -f lavfi -i "sine=frequency=660:duration=30" \
    -metadata title=Beta -metadata artist=Mooi -c:a flac "$out/b.flac" || exit 1

vlc -I dummy --no-video --no-one-instance "$out/a.flac" "$out/b.flac" > "$out/vlc.log" 2>&1 &
vlc_pid=$!
player=''
for _ in $(seq 1 40); do
    sleep 0.2
    player=$(playerctl -l 2>/dev/null | grep -m1 '^vlc')
    [ -n "$player" ] && [ "$(playerctl -p "$player" status 2>/dev/null)" = Playing ] && break
done
if [ -z "$player" ] || [ "$(playerctl -p "$player" status 2>/dev/null)" != Playing ]; then
    echo "the test's VLC never started playing (see $out/vlc.log)"; exit 1
fi

# The reading waits for the player, so give it a moment after the scene starts.
start() {
    MOOI_SAFE=1 pleamar --scene "$root/shell/mooi.plm" --no-hud --stall 0 --seconds 90 \
        > "$out/scene.log" 2>&1 &
    scene_pid=$!
    for _ in $(seq 1 25); do sleep 0.3; say "get open" >/dev/null 2>&1 && break; done
}
wait_for() { # what expected (up to 3 s)
    for _ in $(seq 1 30); do [ "$(get "$1")" = "$2" ] && return 0; sleep 0.1; done; return 1
}
wait_player() { # playerctl field expected (up to 3 s)
    for _ in $(seq 1 30); do [ "$(playerctl -p "$player" metadata --format "{{$1}}" 2>/dev/null)" = "$2" ] && return 0; sleep 0.1; done; return 1
}

start
echo "the bar reads the player the system reports"
is "media_on" "$(get media_on)" true
is "the title" "$(get med.title)" Alpha
is "it is playing" "$(get med.playing)" true

echo "play/pause goes to the player"
say "emit media_cmd 0" >/dev/null
wait_for med.playing false && ok "mooi says paused" || bad "mooi still shows it playing"
is "the player is paused" "$(playerctl -p "$player" status 2>/dev/null)" Paused
say "emit media_cmd 0" >/dev/null
wait_for med.playing true && ok "mooi says playing again" || bad "mooi still shows it paused"
is "the player is playing again" "$(playerctl -p "$player" status 2>/dev/null)" Playing

echo "next and previous reach the player, and the bar follows"
say "emit media_cmd 1" >/dev/null
wait_player title Beta && ok "the player moved to Beta" || bad "the player did not move to Beta"
wait_for med.title Beta && ok "the bar shows Beta" || bad "the bar still shows $(get med.title)"
say "emit media_cmd -1" >/dev/null
wait_player title Alpha && ok "the player moved back to Alpha" || bad "the player did not move back"
wait_for med.title Alpha && ok "the bar shows Alpha" || bad "the bar still shows $(get med.title)"

echo
echo "$n checks, $fail failed · log $out/scene.log"
[ "$fail" -eq 0 ]
