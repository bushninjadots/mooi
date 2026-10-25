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
    echo "the imported identity banner is drawn"
    if wait_value nexus nx_banner_on true 20; then ok "the imported banner is drawn"; else bad "the imported banner was not drawn"; fi
    banner_path=$(get nx_banner_path)
    case "$banner_path" in
        "$out"/*) ok "the banner is read from mooi's own data folder" ;;
        *) bad "the banner path is outside the data folder ('$banner_path')" ;;
    esac
    if [ -f "$banner_path" ]; then ok "the imported banner is where the plate reads it"; else bad "the imported banner is missing"; fi
fi

echo "the workspace starts from three arrangements"
is "three arrangements are seeded" "$(get nx_arrangement_count)" 3
is "the showing arrangement is named" "$(get nx_arrangement_name)" FULL
case "$(get nx_node_count)" in
    8|9|10) ok "the default arrangement has 8 to 10 anchors" ;;
    *) bad "default arrangement has $(get nx_node_count) nodes" ;;
esac
is "the centre starts on the core" "$(get nx_focus)" core
is "the mode starts as circuit" "$(get nx_mode)" circuit
is "the banner starts full" "$(get nx_banner_mode)" full

echo "the node field publishes one row per drawable node"
is "the model holds the canvas rows" "$(get nx_nodes.count)" "$(get nx_node_count)"
is "the first row carries a whole-pixel x" "$(get nx_nodes.0.x | grep -E '^-?[0-9]+$' | wc -l | tr -d ' ')" 1
is "the first row carries a reading" "$(get nx_nodes.0.value | grep -v '^$' | wc -l | tr -d ' ')" 1
is "the first row carries its size limits" "$(get nx_nodes.0.minw | grep -E '^[0-9]+$' | wc -l | tr -d ' ')" 1

echo "a node is selected, moved and put back"
say "emit nx_cycle_sel" >/dev/null
if wait_value nexus nx_sel 1 10; then ok "Tab selects the first node"; else bad "Tab did not select a node"; fi
say "fact nx_cw 1600" >/dev/null
say "fact nx_ch 900" >/dev/null
say "fact nx_gx 304" >/dev/null
say "fact nx_gy 208" >/dev/null
say "emit nx_drop 1" >/dev/null
if wait_value nexus nx_nodes.0.x 304 10; then ok "a dropped node keeps its snapped x"; else bad "the drop did not move the node (x $(get nx_nodes.0.x))"; fi
is "a dropped node keeps its snapped y" "$(get nx_nodes.0.y)" 208
say "emit nx_min 1" >/dev/null
if wait_value nexus nx_nodes.0.mini true 10; then ok "a node's body can be minimized"; else bad "the body did not minimize"; fi
say "emit nx_min 1" >/dev/null
if wait_value nexus nx_nodes.0.mini false 10; then ok "a minimized node restores its body"; else bad "the body did not come back"; fi

echo "a node is removed from the layout and restored"
before=$(get nx_node_count)
say "emit nx_remove 1" >/dev/null
if wait_value nexus nx_removed_count 1 10; then ok "the node leaves the canvas"; else bad "the node was not removed"; fi
is "the canvas is one node lighter" "$(get nx_node_count)" "$((before - 1))"
is "the drawer names what was removed" "$(get nx_removed.0.title)" "Nexus Core"
say "emit nx_restore 1" >/dev/null
if wait_value nexus nx_removed_count 0 10; then ok "the removed node goes back"; else bad "the node was not restored"; fi
is "the canvas count comes back" "$(get nx_node_count)" "$before"

echo "focus swaps the centre and the mode hides what is not essential"
say "emit nx_focus_node 2" >/dev/null
if wait_value nexus nx_focus system 10; then ok "a node can take the centre"; else bad "the focus did not move"; fi
is "the status strip names the centre" "$(get nx_focus_name)" "System"
say "emit nx_mode_switch 1" >/dev/null
if wait_value nexus nx_mode minimal 10; then ok "MINIMAL applies"; else bad "MINIMAL did not apply"; fi
is "MINIMAL draws only the essential nodes" "$(get nx_node_count)" 4
say "emit nx_mode_switch 0" >/dev/null
if wait_value nexus nx_mode circuit 10; then ok "CIRCUIT comes back"; else bad "CIRCUIT did not come back"; fi

echo "arrangements and the banner switch from the header"
say "emit nx_arrangement 3" >/dev/null
if wait_value nexus nx_arrangement_name MINIMAL 10; then ok "the third arrangement shows"; else bad "the arrangement did not switch"; fi
if wait_value nexus nx_morph 0 30; then ok "the switch settles instead of cutting"; else bad "the morph never finished"; fi
say "emit nx_arrangement 1" >/dev/null
if wait_value nexus nx_arrangement_name FULL 10; then ok "the first arrangement comes back"; else bad "the arrangement did not come back"; fi
say "emit nx_banner_cycle" >/dev/null
if wait_value nexus nx_banner_mode compact 10; then ok "the banner steps down to compact"; else bad "the banner did not step"; fi
is "the banner's name follows" "$(get nx_banner_name)" "COMPACT"
say "emit nx_banner_cycle" >/dev/null
if wait_value nexus nx_banner_mode strip 10; then ok "the banner steps to the strip"; else bad "the banner did not reach the strip"; fi
say "emit nx_banner_cycle" >/dev/null
if wait_value nexus nx_banner_mode hidden 10; then ok "the banner can be hidden"; else bad "the banner did not hide"; fi
say "emit nx_banner_cycle" >/dev/null
if wait_value nexus nx_banner_mode full 10; then ok "the banner wraps to full"; else bad "the banner did not wrap"; fi

echo "tidy keeps every node on the canvas"
say "fact nx_cw 1600" >/dev/null
say "fact nx_ch 900" >/dev/null
say "emit nx_tidy" >/dev/null
sleep 0.4
fits=1
for i in 0 1 2 3 4 5 6 7 8 9; do
    x=$(get "nx_nodes.$i.x")
    [ -z "$x" ] && continue
    w=$(get "nx_nodes.$i.w")
    [ $((x + w)) -le 1600 ] 2>/dev/null || fits=0
done
if [ "$fits" -eq 1 ]; then ok "no node outgrows the canvas after TIDY"; else bad "a node sits outside the canvas after TIDY"; fi

echo "safe mode leaves the settings file alone"
if command -v jq >/dev/null 2>&1; then
    saved=$(jq -r '(.nexus.arrangements // []) | length' "$out/data/pleamar/mooi/settings.json" 2>/dev/null)
    is "no arrangement was written under MOOI_SAFE=1" "${saved:-0}" 0
fi

echo "the connection layer draws the authored graph"
is "the model holds the drawn traces" "$(get nx_edges.count)" "$(get nx_edge_count)"
case "$(get nx_edge_count)" in
    5|6|7|8|9|10) ok "the default arrangement has 5 to 10 traces" ;;
    *) bad "the default arrangement has $(get nx_edge_count) traces" ;;
esac
is "the first trace has at least two points" "$(get nx_edges.0.n > /dev/null 2>&1; get nx_edges.0.n | grep -E '^[2-4]$' | wc -l | tr -d ' ')" 1
is "the first trace carries whole-pixel points" "$(get nx_edges.0.x1 | grep -E '^-?[0-9]+$' | wc -l | tr -d ' ')" 1
say "emit nx_hover_edge 1" >/dev/null
if wait_value nexus nx_hover_edge 1 10; then ok "hovering a trace names it"; else bad "hover did not reach the trace"; fi
is "the hovered trace is lit" "$(get nx_edges.0.hot)" true
say "emit nx_hover_edge 0" >/dev/null
say "emit nx_edge_pick 1" >/dev/null
if wait_value nexus nx_edge_sel 1 10; then ok "a press picks the trace"; else bad "the trace was not picked"; fi
is "both endpoints are marked" "$(get nx_nodes.$(get nx_edges.0.from_id).endsel 2>/dev/null | wc -l | tr -d ' ')" 1
before_edges=$(get nx_edge_count)
say "emit nx_edge_hide" >/dev/null
if wait_value nexus nx_edges_hidden 1 10; then ok "the picked trace can be hidden"; else bad "the trace was not hidden"; fi
is "the canvas is one trace lighter" "$(get nx_edge_count)" "$((before_edges - 1))"
say "emit nx_edges_restore" >/dev/null
if wait_value nexus nx_edges_hidden 0 10; then ok "RESTORE FULL NETWORK brings it back"; else bad "the trace did not come back"; fi
is "the trace count comes back" "$(get nx_edge_count)" "$before_edges"

echo "focus isolates the focused node's own traces"
say "emit nx_focus_node 2" >/dev/null
if wait_value nexus nx_focus system 10; then ok "the system node takes the centre"; else bad "the system node did not focus"; fi
dimmed=0
for i in 0 1 2 3 4 5 6 7 8 9; do
    [ "$(get nx_edges.$i.dim)" = true ] && dimmed=$((dimmed + 1))
done
if [ "$dimmed" -gt 0 ]; then ok "unrelated traces recede ($dimmed dimmed)"; else bad "no trace receded from the focused node"; fi
say "emit nx_restore_centre" >/dev/null
if wait_value nexus nx_focus core 10; then ok "the core takes the centre back"; else bad "the core did not return"; fi

echo "the system overview answers from local reads, and toggles"
if wait_value nexus nx_telemetry_on true 40; then ok "the local collector reports itself ready"; else bad "the local collector never reported ready"; fi
is "a distribution was read" "$(get nx_distro | grep -v 'Reading system' | wc -l | tr -d ' ')" 1
cpu=''
for _ in $(seq 1 30); do cpu=$(get nx_cpu_value); case "$cpu" in *%) break ;; esac; sleep 0.2; done
is "the CPU load was sampled" "$(printf '%s' "$cpu" | grep '%' | wc -l | tr -d ' ')" 1
is "the root filesystem was read" "$(get nx_disk_value | grep 'used' | wc -l | tr -d ' ')" 1
echo "the focused node carries its detail body"
say "emit nx_focus_node 2" >/dev/null
if wait_value nexus nx_focus system 10; then ok "the system node takes the centre"; else bad "the system node did not focus"; fi
is "the detail body publishes its rows" "$(get nx_nodes.1.rows)" 8
is "the first row is labelled" "$(get nx_nodes.1.r1l)" "DISTRIBUTION"
is "the second row carries a reading" "$(get nx_nodes.1.r2v | grep -v '^$' | wc -l | tr -d ' ')" 1

echo "RESTORE CENTRE puts the core back, and the keys walk the history"
say "emit nx_restore_centre" >/dev/null
if wait_value nexus nx_focus core 10; then ok "RESTORE CENTRE re-focuses the core"; else bad "the core did not come back to the centre"; fi
say "fact nx_cw 1600" >/dev/null
say "fact nx_ch 900" >/dev/null
# the focus swap morphs; read the settled position, not a frame of the move
wait_value nexus nx_morph 0 30 >/dev/null 2>&1
home_x=$(get nx_nodes.0.x)
is "the core is back on the canvas" "$(get nx_nodes.0.focus)" true
say "fact nx_gx 416" >/dev/null
say "fact nx_gy 320" >/dev/null
say "emit nx_drop 1" >/dev/null
if wait_value nexus nx_nodes.0.x 416 10; then ok "a second drop records a new position"; else bad "the second drop did not land"; fi
say "emit nx_undo" >/dev/null
if wait_value nexus nx_nodes.0.x "$home_x" 10; then ok "Ctrl+Z puts the node back"; else bad "undo did not restore the position (x $(get nx_nodes.0.x))"; fi
say "emit nx_redo" >/dev/null
if wait_value nexus nx_nodes.0.x 416 10; then ok "Ctrl+Shift+Z brings the drop back"; else bad "redo did not restore the drop"; fi

echo "the audio detail body answers from the sound server"
say "emit nx_focus_node 5" >/dev/null
if wait_value nexus nx_nodes.4.r1l "OUTPUT" 10; then ok "the audio node publishes its routing rows"; else bad "the audio rows were not published"; fi
is "the detail body stops at four rows" "$(get nx_nodes.4.rows)" 4
is "the microphone level is answered" "$(get audio.input | grep -E '^[0-9]+([.][0-9]+)?$' | wc -l | tr -d ' ')" 1
is "the Bluetooth presence is answered" "$(get bluetooth.present | grep -E '^(true|false)$' | wc -l | tr -d ' ')" 1
is "the stream list is answered" "$(printf '%s' "$(get nx_mix.count)" | grep -E '^[0-9]+$' | wc -l | tr -d ' ')" 1

echo "the workspaces detail body lists the compositor's workspaces"
say "emit nx_focus_node 7" >/dev/null
if wait_value nexus nx_nodes.6.kind 10 10; then ok "the workspaces node takes the centre"; else bad "the workspaces node did not focus"; fi
is "the workspace list is answered" "$(printf '%s' "$(get nx_ws.count)" | grep -E '^[0-9]+$' | wc -l | tr -d ' ')" 1
say "emit nx_restore_centre" >/dev/null
if wait_value nexus nx_focus core 10; then ok "the core can take the centre back"; else bad "the core did not return"; fi

echo "the module library names what is on the canvas, removed, or not connected"
is "the catalogue is published in full" "$(get nx_lib.count)" 19
is "the first library row is on the canvas" "$(get nx_lib.0.state)" 0
is "an unconnected module is marked" "$(get nx_lib.18.state)" 2
is "an unconnected module says why" "$(get nx_lib.18.note | grep -c .)" 1
say "emit nx_remove 1" >/dev/null
wait_value nexus nx_removed_count 1 10 >/dev/null
lib_row=''
for i in $(seq 0 18); do
    if [ "$(get nx_lib.$i.state)" = 1 ]; then lib_row=$i; break; fi
done
is "a removed node appears in the library" "$(printf '%s' "$lib_row" | grep -E '^[0-9]+$' | wc -l | tr -d ' ')" 1
say "emit nx_restore 1" >/dev/null
if wait_value nexus nx_removed_count 0 10; then ok "the library puts the node back"; else bad "the node did not come back"; fi

echo "the library adds a module the arrangement does not carry yet"
add_code=''
for i in $(seq 0 18); do
    if [ "$(get nx_lib.$i.state)" = 3 ]; then add_code=$(get nx_lib.$i.code); break; fi
done
is "a library row offers to add a missing module" "$(printf '%s' "$add_code" | grep -E '^[0-9]+$' | wc -l | tr -d ' ')" 1
before=$(get nx_node_count)
say "emit nx_lib_add $add_code" >/dev/null
if wait_value nexus nx_node_count $((before + 1)) 10; then ok "the pressed module joins the canvas"; else bad "the module was not added"; fi
added=''
for i in $(seq 0 18); do
    if [ "$(get nx_lib.$i.code)" = "$add_code" ]; then added=$(get nx_lib.$i.state); fi
done
is "the added module reads as on the canvas" "$added" 0
say "emit nx_undo" >/dev/null
if wait_value nexus nx_node_count "$before" 10; then ok "undo takes the added module back off"; else bad "undo did not remove the module"; fi
is "the whole catalogue is counted" "$(get nx_lib_total)" 19
is "nineteen modules take two pages" "$(get nx_lib_pages)" 2
say "emit nx_lib_page 1" >/dev/null
if wait_value nexus nx_lib_page 2 10; then ok "the library turns to its second page"; else bad "the page did not turn"; fi
say "emit nx_lib_page -1" >/dev/null
if wait_value nexus nx_lib_page 1 10; then ok "and back to the first"; else bad "the page did not turn back"; fi
say "emit nx_lib_page -1" >/dev/null
sleep 0.3
is "a page before the first stays on the first" "$(get nx_lib_page)" 1

echo "the trace menu lists what was put away, and gives it back one at a time"
say "emit nx_edge_pick 1" >/dev/null
if wait_value nexus nx_edge_sel 1 10; then ok "a trace is picked before hiding it"; else bad "the trace was not picked"; fi
say "emit nx_edge_hide" >/dev/null
if wait_value nexus nx_hidden_count 1 10; then ok "the hidden trace is listed"; else bad "the hidden trace was not listed"; fi
is "the put-away list names it" "$(get nx_hidden.0.label | grep -c .)" 1
say "emit nx_edge_show 1" >/dev/null
if wait_value nexus nx_hidden_count 0 10; then ok "one trace comes back by its slot"; else bad "the trace did not come back"; fi

echo "the appearance panel changes what the scene draws"
say "fact nx_look_key 5" >/dev/null
say "fact nx_look_val 1" >/dev/null
say "emit nx_look" >/dev/null
if wait_value nexus nx_grid false 10; then ok "the grid can be turned off"; else bad "the grid did not change"; fi
say "emit nx_look" >/dev/null
if wait_value nexus nx_grid true 10; then ok "the grid comes back"; else bad "the grid stayed off"; fi
say "fact nx_look_key 1" >/dev/null
say "fact nx_look_val 1" >/dev/null
say "emit nx_look" >/dev/null
if wait_value nexus nx_accent 2 10; then ok "the accent role steps to FLARE"; else bad "the accent did not change"; fi
is "the accent's name follows" "$(get nx_accent_name)" FLARE
say "fact nx_look_key 4" >/dev/null
say "fact nx_look_val -20" >/dev/null
say "emit nx_look" >/dev/null
if wait_value nexus nx_glow 40 10; then ok "the glow is bounded and applied"; else bad "the glow did not change ($(get nx_glow))"; fi
say "fact nx_look_key 7" >/dev/null
say "fact nx_look_val 1" >/dev/null
say "emit nx_look" >/dev/null
if wait_value nexus nx_edge_style 2 10; then ok "the edge style steps to CURVED"; else bad "the edge style did not change"; fi
say "fact nx_look_key 8" >/dev/null
say "fact nx_look_val 1" >/dev/null
say "emit nx_look" >/dev/null
if wait_value nexus nx_edge_labels false 10; then ok "trace labels can be turned off"; else bad "the labels did not change"; fi
say "emit nx_look" >/dev/null
if wait_value nexus nx_edge_labels true 10; then ok "the labels come back"; else bad "the labels stayed off"; fi

echo "a node's size preset and its reset"
say "emit nx_focus_node 3" >/dev/null
row=''
for i in $(seq 0 9); do
    if [ "$(get nx_nodes.$i.id)" = 3 ]; then row=$i; break; fi
done
if wait_value nexus "nx_nodes.$row.focus" true 10; then ok "a node is selected through the centre"; else bad "the node was not focused"; fi
# The focus travels over ~320 ms and the logic is blocked while it settles, so the preset is
# measured against the width the node has come to rest at, not the one it had mid-morph.
wait_value nexus nx_morph 0 20 >/dev/null
before_w=$(get "nx_nodes.$row.w")
say "emit nx_node_preset 3" >/dev/null
after_w=$before_w
i=0
while [ "$i" -lt 20 ]; do
    try=$(get "nx_nodes.$row.w")
    if printf '%s' "$try" | grep -Eq '^[0-9]+$' && [ "$try" != "$before_w" ]; then after_w=$try; break; fi
    i=$((i + 1)); sleep 0.2
done
if [ "$after_w" != "$before_w" ]; then ok "a size preset resizes the node ($before_w → $after_w)"; else bad "the size preset did nothing"; fi
say "emit nx_node_reset" >/dev/null
reset_w=$after_w
i=0
while [ "$i" -lt 20 ]; do
    try=$(get "nx_nodes.$row.w")
    if printf '%s' "$try" | grep -Eq '^[0-9]+$' && [ "$try" != "$after_w" ]; then reset_w=$try; break; fi
    i=$((i + 1)); sleep 0.2
done
if [ "$reset_w" != "$after_w" ]; then ok "RESET NODE returns the type's size ($reset_w)"; else bad "the reset did not change the size"; fi

echo "arrangements can be added, copied and deleted"
say "emit nx_arr_new" >/dev/null
if wait_value nexus nx_arrangement_count 4 10; then ok "a new arrangement is kept"; else bad "the arrangement was not added"; fi
is "the new arrangement has its own name" "$(get nx_arrangement_name)" LAYOUT
say "emit nx_arr_dup" >/dev/null
if wait_value nexus nx_arrangement_count 5 10; then ok "the arrangement can be copied"; else bad "the copy was not made"; fi
say "emit nx_arr_del" >/dev/null
if wait_value nexus nx_arrangement_count 4 10; then ok "an arrangement can be deleted"; else bad "the delete did nothing"; fi
say "emit nx_arr_del" >/dev/null
if wait_value nexus nx_arrangement_count 3 10; then ok "the list comes back to three"; else bad "the list did not shrink back"; fi

echo "Escape closes the docked panel before the workspace"
say "fact nx_panel library" >/dev/null
is "the panel can be opened" "$(get nx_panel)" library
say "key Escape" >/dev/null
if wait_value nexus nx_panel none 10; then ok "Escape puts the panel away"; else bad "Escape left the panel open"; fi
if say "get nx_open" >/dev/null 2>&1; then ok "the workspace stays open when the panel closes"; else bad "Escape closed the whole workspace"; fi
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
