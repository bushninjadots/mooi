#!/bin/sh
# The Control Nexus deck (D102), its lifecycle on the real compositor.
#
# Starts the Nexus alone with a temporary HOME and data folder, so nothing of the user's is read
# or written: its edge from settings.json, moved live; Cascade; the workspace preview growing out;
# a scene saved and removed (nexus-scenes.json, in the temporary folder); and the deck ending
# itself when asked to close. It reads Hyprland's windows and workspaces but moves none of them,
# and changes no volume, brightness or switch.
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
ok() { n=$((n + 1)); echo "  ok    $1"; }
bad() { n=$((n + 1)); fail=$((fail + 1)); echo "  FAIL  $1"; }
is() { if [ "$2" = "$3" ]; then ok "$1 ($2)"; else bad "$1 (got '$2', expected '$3')"; fi; }
wait_value() { # fact expected [attempts]
    i=0
    while [ "$i" -lt "${3:-40}" ]; do
        [ "$(get "$1")" = "$2" ] && return 0
        sleep 0.2; i=$((i + 1))
    done
    return 1
}
cleanup() {
    if [ -n "$pid" ]; then say quit >/dev/null 2>&1; kill "$pid" 2>/dev/null; wait "$pid" 2>/dev/null; fi
    rm -rf "$out"
}
trap cleanup EXIT INT TERM

if say "get dk_open" >/dev/null 2>&1; then
    echo "Control Nexus is already open; close it first (Escape)"
    exit 2
fi

# The Nexus's data folder is mooi's (bin/mooi links it); here, a temporary one.
mkdir -p "$out/home/.cache" "$out/data/pleamar/mooi"
ln -s "$out/data/pleamar/mooi" "$out/data/pleamar/mooi-nexus"
settings="$out/data/pleamar/mooi/settings.json"
printf '{"nexus":{"edge":"bottom","identity":{"name":"Lab","avatar":"","banner":""}}}\n' > "$settings"
set_edge() { jq --arg e "$1" --arg m "$2" '.nexus.edge = $e | .nexus.mode = $m' "$settings" > "$settings.tmp" && mv "$settings.tmp" "$settings"; }

HOME="$out/home" XDG_DATA_HOME="$out/data" pleamar --scene "$root/shell/mooi-nexus.plm" --no-hud --stall 0 > "$out/nexus.log" 2>&1 &
pid=$!
if wait_value dk_open true 50; then ok "it opens"; else bad "it never opened"; sed -n 1,30p "$out/nexus.log"; exit 1; fi

echo "edges"
wait_value dk_w 0 1 >/dev/null
is "along the bottom by default" "$(get dk_edge)" 0
is "a strip, not a column" "$(get dk_vert)" false
is "twelve quick settings" "$(get quick.count)" 12
is "the first deck's cards" "$(get pf_on)$(get pn_on)$(get pa_on)$(get pw_on)$(get ps_on)$(get pq_on)$(get pu_on)" truetruetruetruetruetruetrue
is "and the rest on the shelf" "$(get hid.count)" 4
is "the circuit wires each card" "$(get nodes.count)" 7
case "$(get faders.count)" in [2-6]) ok "the mixer has its faders" ;; *) bad "faders: $(get faders.count)" ;; esac
case "$(get tiles.count)" in [2-9]|1[0-2]) ok "the workspaces, and +" ;; *) bad "tiles: $(get tiles.count)" ;; esac
is "the scenes, and Save" "$(get scn.count)" 5
set_edge left deck
if wait_value dk_edge 2; then ok "moved to the left as the settings changed"; else bad "the edge did not follow the settings ($(get dk_edge))"; fi
is "down a side it is a column" "$(get dk_vert)" true
set_edge right deck
wait_value dk_edge 3 >/dev/null && ok "and to the right" || bad "not to the right ($(get dk_edge))"
set_edge top deck
wait_value dk_edge 1 >/dev/null && ok "and to the top" || bad "not to the top ($(get dk_edge))"

echo "what grows out"
say "emit dk_hov_ws 0" "fact dk_hws 0" >/dev/null
sleep 0.4
case "$(get big_t)" in WORKSPACE*) ok "a workspace's preview says which ($(get big_t))" ;; *) bad "no preview title ($(get big_t))" ;; esac
gy=$(get gw_y); dy=$(get dk_y); dh=$(get dk_h)
if [ "${gy%.*}" -ge "$(( ${dy%.*} + ${dh%.*} ))" ]; then ok "below a deck along the top"; else bad "the preview is not below the deck (y $gy, deck $dy + $dh)"; fi
say "emit dk_hov_scene 0" >/dev/null
sleep 0.3
case "$(get diff_t)" in FOCUS*) ok "a scene says what it would change" ;; *) bad "no scene title ($(get diff_t))" ;; esac

echo "scenes"
say "emit dk_naming_on 4" >/dev/null; sleep 0.3; say "text dk_name_in Lab scene" "emit dk_save_named" >/dev/null   # + Save, named
sleep 0.5
is "Save adds a scene" "$(get scn.count)" 6
is "under the name typed" "$(jq -r '.scenes[4].name' "$out/data/pleamar/mooi/nexus-scenes.json" 2>/dev/null)" "Lab scene"
if jq -e '.scenes | length == 5' "$out/data/pleamar/mooi/nexus-scenes.json" >/dev/null 2>&1; then ok "kept in nexus-scenes.json"; else bad "nexus-scenes.json was not written"; fi
say "emit dk_unscene 4" >/dev/null
sleep 0.5
is "a right press removes it" "$(get scn.count)" 5

echo "arranging"
say "emit dk_edit_on 1" >/dev/null; sleep 0.2
is "✎ arranges" "$(get dk_edit)" true
say "emit dk_hide 4" >/dev/null; sleep 0.4
is "a part hidden" "$(get pu_on)" false
is "and listed to show again" "$(get hid.count)" 5
is "kept in settings.json" "$(jq -r '.nexus.hidden[0]' "$settings")" music
say "emit dk_drop 8000025" >/dev/null; sleep 0.4       # Scenes let go before everything (code 8, x 0, y 100: 1000000·code + 1000·x/4 + y/4)
is "a card carried to the front" "$(jq -r '.nexus.parts[0]' "$settings")" scenes
is "numbered first" "$(get pn_n)" 01
say "emit dk_show 4" "emit dk_reset" >/dev/null; sleep 0.4
is "Reset puts every card back" "$(jq -r '.nexus.parts[0]' "$settings")$(get pu_on)" profiletrue
say "emit dk_rows_set 2" >/dev/null; sleep 0.5
is "two rows of cards" "$(get dk_rows)$(jq -r '.nexus.rows' "$settings")" 22
echo "the same cards on every edge"
cards() { c=0; for f in pw_on ps_on pm_on pq_on pu_on pc_on pt_on pf_on pn_on pa_on py_on; do [ "$(get "$f")" = true ] && c=$((c+1)); done; echo "$c"; }
say "emit dk_edge_set 0" >/dev/null; sleep 0.7
base=$(cards)
for pair in "1 top" "2 left" "3 right"; do
    set -- $pair
    say "emit dk_edge_set $1" >/dev/null; sleep 0.7
    is "the same cards along the $2" "$(cards)" "$base"
done
say "emit dk_edge_set 1" >/dev/null; sleep 0.7      # back along the top, a strip: a card's size shows there
say "emit dk_large_set 1" >/dev/null; sleep 0.4
is "a large profile" "$(jq -r '.nexus.profile' "$settings")" large
w0=$(get pq_w); say "emit dk_size 3" >/dev/null; sleep 0.4
is "⇔ makes Quick settings large" "$(jq -r '.nexus.sizes[0]' "$settings")$(get pq_sz)" quick_lL
w1=$(get pq_w); if [ "${w1%.*}" -gt "${w0%.*}" ]; then ok "and wider ($w0 → $w1)"; else bad "not wider ($w0 → $w1)"; fi
say "emit dk_edge_set 2" >/dev/null; sleep 0.6
is "the edge chosen on the deck" "$(jq -r '.nexus.edge' "$settings")" left
say "emit dk_edit_on 0" >/dev/null

echo "cascade"
set_edge bottom cascade
wait_value dk_cascade true >/dev/null && ok "Cascade is chosen in the settings" || bad "Cascade did not follow the settings"
c0=$(get cy_0); c8=$(get cy_8)
if [ "${c8%.*}" -gt "${c0%.*}" ]; then ok "its shelves are stacked down the edge"; else bad "shelves not stacked ($c0, $c8)"; fi

echo "the music feed"
viz="$out/data/pleamar/mooi/viz-levels.txt"
printf 'v1 %s 900 400 700 500 1 0 41\n' "$(yes 500 | head -32 | tr '\n' ' ')" > "$viz"
i=0; v0=0
while [ "$i" -lt 25 ]; do
    v0=$(get dv0)
    case "$v0" in 0.[4-6]*) break ;; esac
    sleep 0.2; i=$((i + 1))
done
case "$v0" in
    0.[4-6]*) ok "the deck reads the shared feed (dv0 $v0)" ;;
    *) bad "the deck does not follow viz-levels.txt (dv0 $v0)" ;;
esac

echo "closing"
say "emit nx_close" >/dev/null
i=0
while [ "$i" -lt 30 ] && kill -0 "$pid" 2>/dev/null; do sleep 0.1; i=$((i + 1)); done
if kill -0 "$pid" 2>/dev/null; then bad "it did not end after closing"; else ok "it slid away and ended"; pid=''; fi
if grep -qi "error" "$out/nexus.log"; then bad "the log has errors: $(grep -i error "$out/nexus.log" | head -3)"; else ok "no errors in its log"; fi

echo
echo "$n checks, $fail failed"
[ "$fail" -eq 0 ]
