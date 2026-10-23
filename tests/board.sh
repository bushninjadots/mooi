#!/bin/sh
# The board, as a program of its own (D64), live: the bar starts it (`emit open_board`, as the
# pad's rail, its key and `mooi board` do) and closes it again; the board reads mooi's own
# board.json through the link `bin/mooi` makes; a press on the board leaves it up, and a press
# outside it — or Escape — takes it away, after which the program ends by itself.
#
# The press is a fake pointer, without a move of its own: `ydotool` parks the cursor where it
# should land (the desktop, then the board's plate), the board comes up under it, and Pleamar's
# `--mouse "click@…"` presses there. A move in the fake script leaves every zone in this session
# (the scene gets the leave and no enter for it), and `ydotool`'s own clicks reach no zone at all,
# so neither is used.
#
# It runs the bar and the board on this machine's compositor for ~30 s and writes only in a
# temporary home. Stop mooi first: the script starts its own scenes and talks to them by name.
# Run from anywhere: tests/board.sh
set -u
root=$(cd "$(dirname "$0")/.." && pwd)
out=${TMPDIR:-/tmp}/mooi-board.$$
mkdir -p "$out"
fail=0; n=0; pid=''
data=$out/data/pleamar

say() { pleamar --say mooi-board "$@" 2>&1; }
get() { say "get $1" | tail -1; }
bsay() { pleamar --say mooi "$@" 2>&1; }
bget() { bsay "get $1" | tail -1; }
ok() { n=$((n + 1)); echo "  ok    $1"; }
bad() { n=$((n + 1)); fail=$((fail + 1)); echo "  FAIL  $1"; }
is() { if [ "$2" = "$3" ]; then ok "$1 ($2)"; else bad "$1 (got '$2', expected '$3')"; fi }
cleanup() {
    [ -n "$pid" ] && { bsay quit >/dev/null 2>&1; say quit >/dev/null 2>&1; kill "$pid" 2>/dev/null; wait "$pid" 2>/dev/null; }
    rm -rf "$out"
}
trap cleanup EXIT INT TERM
gone() { # the board's socket answers no more
    for _ in $(seq 1 70); do sleep 0.1; say "get board_in" >/dev/null 2>&1 || return 0; done
    return 1
}
up() {
    for _ in $(seq 1 60); do sleep 0.15; [ "$(get board_in)" = 1 ] && return 0; done
    return 1
}
inside() { # every zone of the last frame sits below the plate's head, not at the screen's top
    line=$(grep '^regions · surface 0 (board):' "$out/board.log" | tail -1)
    [ -n "$line" ] || return 1
    printf '%s\n' "$line" | grep -oE '\[[0-9-]+, [0-9-]+, [0-9-]+, [0-9-]+\]' | tail -n +2 |
        tr -d '[] ' | awk -F, '$2 < 150 { bad = 1 } END { exit bad }'
}

if bsay "get open" >/dev/null 2>&1; then
    echo "mooi is already running; stop it first (bin/mooi stop)"; exit 2
fi
if say "get board_in" >/dev/null 2>&1; then
    echo "a board is already open; close it first (Escape)"; exit 2
fi

# mooi's own file, and the link bin/mooi makes for the board's data folder.
mkdir -p "$data/mooi" "$out/home" "$out/config"
ln -sfn "$data/mooi" "$data/mooi-board"
cat > "$data/mooi/board.json" <<'JSON'
{ "version": 1, "next_id": 4,
  "columns": [ { "id": 1, "title": "Inbox", "wip": 0 },
               { "id": 2, "title": "Doing", "wip": 3 },
               { "id": 3, "title": "Done", "wip": 0 } ],
  "cards": [ { "id": 1, "col": 1, "title": "Buy milk", "note": "", "tag": 0, "created": 0, "updated": 0 },
             { "id": 2, "col": 2, "title": "Call Ana", "note": "", "tag": 2, "created": 0, "updated": 0 },
             { "id": 3, "col": 3, "title": "Ship it", "note": "", "tag": 0, "created": 0, "updated": 0, "done_at": 0 } ],
  "archive": [] }
JSON

start_bar() { # extra pleamar options
    HOME=$out/home XDG_DATA_HOME=$out/data XDG_CONFIG_HOME=$out/config MOOI_SAFE=1 \
        MOOI_SHELL="$root/shell" pleamar --scene "$root/shell/mooi.plm" --no-hud --stall 0 \
        --seconds 90 "$@" > "$out/bar.log" 2>&1 &
    pid=$!
    for _ in $(seq 1 40); do sleep 0.25; bsay "get open" >/dev/null 2>&1 && break; done
}

echo "the bar starts the board on request, and closes it on the same request"
start_bar
is "the bar reads the board's file for its badge" "$(bget kb_count)" 3
bsay "emit open_board" >/dev/null
if up; then ok "the board's program comes up"; else bad "the board did not come up"; fi
is "it reads mooi's own board.json through the link" "$(get kb_count)" 3
is "and one of them is done" "$(get kb_done_n)" 1
bsay "emit open_board" >/dev/null
if gone; then ok "the same request closes it again"; else bad "the board stayed open"; fi
is "and the bar still knows how many cards there are" "$(bget kb_count)" 3

bsay quit >/dev/null 2>&1; kill "$pid" 2>/dev/null; wait "$pid" 2>/dev/null; pid=''
for _ in $(seq 1 30); do bsay "get open" >/dev/null 2>&1 || break; sleep 0.1; done
start_board() { # extra pleamar options; the pointer is parked before the scene starts
    HOME=$out/home XDG_DATA_HOME=$out/data XDG_CONFIG_HOME=$out/config \
        PLEAMAR_REGIONS=1 pleamar --scene "$root/shell/mooi-board.plm" --no-hud --stall 0 \
        --seconds 60 "$@" > "$out/board.log" 2>&1 &
    pid=$!
    up || { bad "the board did not open"; exit 1; }
    sleep 1
}

if command -v ydotool >/dev/null 2>&1; then
    # The press is a fake one Pleamar sends with no move of its own: the real pointer is parked
    # where it should press (ydotool), the board comes up under it, and the click lands there. A
    # move in the fake script leaves every zone (this session's compositor sends the scene no
    # enter for it), so none is asked for.
    echo "a press outside the board closes it, and the program ends by itself"
    ydotool mousemove -a 60 60 >/dev/null 2>&1
    start_board --mouse "click@3000"
    if inside; then ok "its content sits inside the plate, head and columns whole"
    else bad "the board's content is drawn outside its plate (cropped)"; fi
    if grep -q '\[-3, -3, 1923, 1083\]' "$out/board.log"; then
        ok "its plate covers the whole screen"
    else
        bad "nothing on the surface covers the whole screen"
    fi
    if gone; then ok "a press on the desktop outside it closes it"; else bad "the press outside did not close it"; fi
    wait "$pid" 2>/dev/null; code=$?
    if [ "$code" -eq 0 ]; then ok "and the program ended by itself"; else bad "the program ended with $code"; fi
    pid=''

    echo "a press on the board itself leaves it up; Escape takes it away"
    ydotool mousemove -a 1400 500 >/dev/null 2>&1
    start_board --mouse "click@3000"
    sleep 1
    is "a press on its plate does not close it" "$(get board_in)" 1
    say "key Escape" >/dev/null
    if gone; then ok "Escape closes it"; else bad "Escape did not close it"; fi
    wait "$pid" 2>/dev/null
    pid=''
else
    echo "  skip  the outside press (ydotool is not installed)"
    start_board
    if inside; then ok "its content sits inside the plate, head and columns whole"
    else bad "the board's content is drawn outside its plate (cropped)"; fi
    say "emit close_board" >/dev/null
    if gone; then ok "the event its plate emits folds it and quits (no pointer to press with)";
    else bad "the board did not close"; fi
    wait "$pid" 2>/dev/null
    pid=''
fi

echo
echo "$n checks, $fail failed"
[ "$fail" -eq 0 ]
