#!/bin/sh
# Control Nexus (D65), isolated lifecycle smoke test.
#
# Starts a test copy of the bar and Nexus with a temporary HOME and XDG data/config folders.
# The bar scene is copied as `mooi-lab.plm`, so the test has its own socket and can run beside
# the user's live mooi; Nexus keeps its usual socket, so an open Nexus is still refused.
# It does not change volume, brightness, workspaces, wallpapers, notifications, or the user's
# settings.
#
# This is a compositor/live test, not a headless test. Run from anywhere:
#   tests/nexus.sh
set -u
root=$(cd "$(dirname "$0")/.." && pwd)
PATH="$root/bin:$PATH"
export PATH
out=${TMPDIR:-/tmp}/mooi-nexus-test.$$
mkdir -p "$out"
fail=0; n=0; pid=''; nexus_started=0

say() { pleamar --say mooi-nexus "$@" 2>&1; }
get() { say "get $1" | tail -1; }
bsay() { pleamar --say mooi-lab "$@" 2>&1; }
bget() { bsay "get $1" | tail -1; }
ok() { n=$((n + 1)); echo "  ok    $1"; }
bad() { n=$((n + 1)); fail=$((fail + 1)); echo "  FAIL  $1"; }
is() { if [ "$2" = "$3" ]; then ok "$1 ($2)"; else bad "$1 (got '$2', expected '$3')"; fi; }

cleanup() {
    # Never send quit to an instance that existed before this test started.
    if [ "$nexus_started" -eq 1 ]; then say quit >/dev/null 2>&1; fi
    if [ -n "$pid" ]; then
        bsay quit >/dev/null 2>&1
        kill "$pid" 2>/dev/null
        wait "$pid" 2>/dev/null
    fi
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
    echo "a previous mooi-lab is still running; wait for it to end"
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
ln -s "$out/data/pleamar/mooi" "$out/data/pleamar/mooi-lab"
lab="$out/shell"
cp -R "$root/shell" "$lab"
cp "$lab/mooi.plm" "$lab/mooi-lab.plm"
cp "$lab/mooi.luau" "$lab/mooi-lab.luau"

# A banner imported through the real CLI, into the temporary data folder: the plate should draw
# a band copy of it (cropped once with ImageMagick), not the picture squeezed into the strip.
banner_ok=0
if command -v magick >/dev/null 2>&1 && command -v jq >/dev/null 2>&1; then
    printf '{"nexus":{"identity":{"name":"mooi system","avatar":"","banner":""}}}' \
        > "$out/data/pleamar/mooi/settings.json"
    printf '%s' 'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==' \
        | base64 --decode > "$out/banner.png"
    if HOME="$out/home" XDG_DATA_HOME="$out/data" XDG_CONFIG_HOME="$out/config" \
        XDG_STATE_HOME="$out/state" "$root/bin/mooi" identity banner "$out/banner.png" >/dev/null 2>&1; then
        banner_ok=1
    fi
fi

echo "start an isolated bar scene"
HOME="$out/home" XDG_DATA_HOME="$out/data" XDG_CONFIG_HOME="$out/config" \
    MOOI_SAFE=1 MOOI_SHELL="$lab" \
    pleamar --scene "$lab/mooi-lab.plm" --no-hud --stall 0 --seconds 90 \
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
# Two activations inside the keyboard hand-off window must still start only one Nexus.
bsay "emit open_nexus" >/dev/null
bsay "emit open_nexus" >/dev/null
if wait_up; then nexus_started=1; ok "rapid repeated activation starts Nexus once"; else bad "the Nexus program did not start"; cat "$out/bar.log"; exit 1; fi
is "the bar marks Nexus as open" "$(bget nexus_open)" true
is "pin defaults to off" "$(get nx_pinned)" false
say "emit nx_pin" >/dev/null
if wait_value nexus nx_pinned true 10; then ok "pin control turns pinning on"; else bad "pin control did not turn pinning on"; fi
say "emit nx_pin" >/dev/null
if wait_value nexus nx_pinned false 10; then ok "pin control turns pinning off"; else bad "pin control did not turn pinning off"; fi

if [ "$banner_ok" -eq 1 ]; then
    echo "the identity banner is drawn as a band copy"
    if wait_value nexus nx_banner_on true 20; then ok "the imported banner is drawn"; else bad "the imported banner was not drawn"; fi
    band=''
    for _ in $(seq 1 30); do
        band=$(get nx_banner_path)
        case "$band" in *-228-band.jpg) break ;; esac
        sleep 0.2
    done
    case "$band" in
        *-228-band.jpg) ok "the plate draws a band copy, not the photograph" ;;
        *) bad "the plate did not make a band copy (path '$band')" ;;
    esac
    if [ -f "$band" ]; then ok "the band copy is in mooi's data folder"; else bad "the band copy is missing"; fi
fi

echo "the layout hides, reorders and restores every module"
is "every module starts on" "$(get nx_mod_count)" 6
is "every control card starts on" "$(get nx_tile_count)" 4
is "the player starts on" "$(get nx_mod_on_player)" 1
is "three named layouts start" "$(get nxlayout.count)" 3
say "emit nx_layout" >/dev/null
if wait_value nexus nx_layout_on true 10; then ok "the layout panel opens"; else bad "the layout panel did not open"; fi
say "emit nx_mod_toggle 1" >/dev/null
if wait_value nexus nx_mod_on_display 0 10; then ok "a card can be put away"; else bad "the card was not put away"; fi
is "the cards close the gap" "$(get nx_tile_count)" 3
say "emit nx_mod_up 9" >/dev/null
if wait_value nexus nx_mod_slot_tx 4 10; then ok "a plate can be moved earlier in its band"; else bad "the plate did not move"; fi
is "the plate it passed takes its place" "$(get nx_mod_slot_rx)" 5
say "emit nx_mod_toggle 1" >/dev/null
if wait_value nexus nx_tile_count 4 10; then ok "a hidden card can be turned back on"; else bad "the card did not come back"; fi
say "emit nx_mod_reset" >/dev/null
if wait_value nexus nx_mod_slot_cpu 0 10; then ok "the catalogue order comes back"; else bad "the order was not restored"; fi
is "the instruments are all back" "$(get nx_mod_count)" 6
is "the player is back" "$(get nx_mod_on_player)" 1

echo "a named layout switches the plate and comes back"
say "emit nx_layout_pick 2" >/dev/null
if wait_value nexus nx_tile_count 2 10; then ok "MINIMAL keeps two cards"; else bad "MINIMAL did not apply"; fi
is "MINIMAL leaves the instruments out" "$(get nx_mod_count)" 0
is "MINIMAL keeps the player" "$(get nx_mod_on_player)" 1
say "emit nx_layout_pick 0" >/dev/null
if wait_value nexus nx_mod_count 6 10; then ok "FULL comes back"; else bad "FULL did not come back"; fi
say "emit nx_layout" >/dev/null
if wait_value nexus nx_layout_on false 10; then ok "the layout panel closes"; else bad "the layout panel did not close"; fi

echo "the system overview answers from local reads, and toggles"
if wait_value nexus nx_telemetry_on true 40; then ok "the local collector reports itself ready"; else bad "the local collector never reported ready"; fi
is "a distribution was read" "$(get nx_distro | grep -v 'Reading system' | wc -l | tr -d ' ')" 1
cpu=''
for _ in $(seq 1 30); do cpu=$(get nx_cpu_value); case "$cpu" in *%) break ;; esac; sleep 0.2; done
is "the CPU load was sampled" "$(printf '%s' "$cpu" | grep '%' | wc -l | tr -d ' ')" 1
is "the root filesystem was read" "$(get nx_disk_value | grep 'used' | wc -l | tr -d ' ')" 1
say "emit nx_about" >/dev/null
if wait_value nexus nx_about_on true 10; then ok "the overview opens"; else bad "the overview did not open"; fi
say "emit nx_about" >/dev/null
if wait_value nexus nx_about_on false 10; then ok "the overview closes back to the controls"; else bad "the overview did not close"; fi

echo "the audio view answers from the sound server"
say "emit nx_audio" >/dev/null
if wait_value nexus nx_audio_on true 10; then ok "the audio view opens"; else bad "the audio view did not open"; fi
is "the views are exclusive" "$(get nx_about_on)" false
is "the microphone level is answered" "$(get audio.input | grep -E '^[0-9]+([.][0-9]+)?$' | wc -l | tr -d ' ')" 1
is "the Bluetooth presence is answered" "$(get bluetooth.present | grep -E '^(true|false)$' | wc -l | tr -d ' ')" 1
bt_count=$(get btdev.count)
is "the Bluetooth device list is filled" "$(printf '%s' "$bt_count" | grep -E '^[0-9]+$' | wc -l | tr -d ' ')" 1
if [ "${bt_count:-0}" -gt 0 ] 2>/dev/null; then
    is "the first Bluetooth row carries a name" "$(get btdev.0.name | grep -v '^$' | wc -l | tr -d ' ')" 1
fi
say "emit nx_audio" >/dev/null
if wait_value nexus nx_audio_on false 10; then ok "the audio view closes back to the controls"; else bad "the audio view did not close"; fi

echo "the application mixer reads the sound server's streams"
say "emit nx_mixer" >/dev/null
if wait_value nexus nx_mixer_on true 10; then ok "the mixer opens"; else bad "the mixer did not open"; fi
is "the audio view is closed" "$(get nx_audio_on)" false
is "the overview is closed" "$(get nx_about_on)" false
streams=$(get nxapp.count)
is "the stream list is filled" "$(printf '%s' "$streams" | grep -E '^[0-9]+$' | wc -l | tr -d ' ')" 1
if [ "${streams:-0}" -gt 0 ] 2>/dev/null; then
    is "the first stream row carries a name" "$(get nxapp.0.name | grep -v '^$' | wc -l | tr -d ' ')" 1
fi
say "emit nx_mixer" >/dev/null
if wait_value nexus nx_mixer_on false 10; then ok "the mixer closes back to the controls"; else bad "the mixer did not close"; fi

echo "the workspace view lists the compositor's workspaces"
say "emit nx_spaces" >/dev/null
if wait_value nexus nx_spaces_on true 10; then ok "the workspace view opens"; else bad "the workspace view did not open"; fi
is "the mixer is closed" "$(get nx_mixer_on)" false
ws_count=$(get nxws.count)
is "the workspace list is filled" "$(printf '%s' "$ws_count" | grep -E '^[0-9]+$' | wc -l | tr -d ' ')" 1
if [ "${ws_count:-0}" -gt 0 ] 2>/dev/null; then
    is "the first workspace carries an id" "$(get nxws.0.id | grep -E '^[0-9]+$' | wc -l | tr -d ' ')" 1
fi
say "emit nx_spaces" >/dev/null
if wait_value nexus nx_spaces_on false 10; then ok "the workspace view closes back to the controls"; else bad "the workspace view did not close"; fi

echo "the power view reads the battery and arms without acting"
say "emit nx_power" >/dev/null
if wait_value nexus nx_power_on true 10; then ok "the power view opens"; else bad "the power view did not open"; fi
is "the mixer is closed" "$(get nx_mixer_on)" false
is "the battery presence is answered" "$(get battery.present | grep -E '^(true|false)$' | wc -l | tr -d ' ')" 1
if [ "$(get battery.present)" = true ]; then
    health=''
    for _ in $(seq 1 30); do
        health=$(get nx_battery_health)
        case "$health" in "HEALTH "[0-9]*%) break ;; esac
        sleep 0.2
    done
    is "the battery health was read from UPower" "$(printf '%s' "$health" | grep -E '^HEALTH [0-9]+%$' | wc -l | tr -d ' ')" 1
    is "the battery time is answered or explained" "$(get nx_battery_time | grep -v '^$' | wc -l | tr -d ' ')" 1
fi
say "emit nx_suspend" >/dev/null
if wait_value nexus nx_armed 1 10; then ok "a session action arms on the first press"; else bad "the session action did not arm"; fi
sleep 3.2
is "the armed action expires without acting" "$(get nx_armed)" 0
say "emit nx_power" >/dev/null
if wait_value nexus nx_power_on false 10; then ok "the power view closes back to the controls"; else bad "the power view did not close"; fi

bsay "emit open_nexus" >/dev/null
if wait_gone; then nexus_started=0; ok "the same trigger closes the program"; else bad "the same trigger left Nexus running"; fi
if wait_value bar nexus_open false 30; then ok "the bar clears its open state"; else bad "the bar kept a stale open state"; fi

echo "reopen and close with Escape"
bsay "emit open_nexus" >/dev/null
if wait_up; then nexus_started=1; ok "Nexus can reopen after closing"; else bad "Nexus failed to reopen"; exit 1; fi
say "key Escape" >/dev/null
if wait_gone; then nexus_started=0; ok "Escape closes and exits Nexus"; else bad "Escape did not close Nexus"; fi
if wait_value bar nexus_open false 30; then ok "the bar clears state after Escape"; else bad "the bar kept stale state after Escape"; fi

echo "a replaced identity image gets a new file name, so the plate reads it"
idroot="$out/identity-cli/data/pleamar/mooi"
mkdir -p "$idroot" "$out/identity-cli/run"
printf '{"nexus":{"identity":{"name":"mooi system","avatar":"","banner":""}}}' > "$idroot/settings.json"
printf '%s' 'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==' | base64 --decode > "$out/one.png"
cp "$out/one.png" "$out/two.png"
run_identity() {
    HOME="$out/home" XDG_DATA_HOME="$out/identity-cli/data" XDG_CONFIG_HOME="$out/config" \
        XDG_STATE_HOME="$out/identity-cli/state" XDG_RUNTIME_DIR="$out/identity-cli/run" \
        "$root/bin/mooi" "$@"
}
run_identity identity avatar "$out/one.png" >/dev/null 2>&1
first=$(jq -r '.nexus.identity.avatar' "$idroot/settings.json" 2>/dev/null)
run_identity identity avatar "$out/two.png" >/dev/null 2>&1
second=$(jq -r '.nexus.identity.avatar' "$idroot/settings.json" 2>/dev/null)
if [ -n "$first" ] && [ "${first##*/}" != "${second##*/}" ]; then
    ok "a second import writes a different file name"
else
    bad "a second import reused the first file name ('$first' → '$second')"
fi
if [ -n "$second" ] && [ -f "$idroot/$second" ]; then ok "the imported avatar is in the data folder"; else bad "the imported avatar is missing"; fi
is "the previous avatar file is removed" "$(find "$idroot/identity" -name 'avatar*' -type f | wc -l | tr -d ' ')" 1

echo
echo "$n checks, $fail failed"
[ "$fail" -eq 0 ]
