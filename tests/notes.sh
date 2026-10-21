#!/bin/sh
# Quick notes (D51), live: the pad's module, its dropdown and its file. A note is written as the
# input would send it (`text` then `submit`), added with the Add button's event, changed in place,
# copied, forgotten, put back with Undo, paged with the wheel, and saved from the terminal with
# `mooi note`. Where the module is on this machine's bar, a real pointer press opens the dropdown.
#
# It writes notes.json in mooi's data folder; the file is put back as it was (or removed if there
# was none). Stop mooi first: the script starts its own scene and talks to it by name.
# Run from anywhere: tests/notes.sh
set -u
root=$(cd "$(dirname "$0")/.." && pwd)
out=${TMPDIR:-/tmp}/mooi-notes.$$
mkdir -p "$out"
fail=0; n=0
pid=''
notes=${XDG_DATA_HOME:-$HOME/.local/share}/pleamar/mooi/notes.json

say() { pleamar --say mooi "$@" 2>&1; }
get() { say "get $1" | tail -1; }
ok() { n=$((n + 1)); echo "  ok    $1"; }
bad() { n=$((n + 1)); fail=$((fail + 1)); echo "  FAIL  $1"; }
is() { if [ "$2" = "$3" ]; then ok "$1 ($2)"; else bad "$1 (got '$2', expected '$3')"; fi }
has() { if grep -q "$2" "$3" 2>/dev/null; then ok "$1"; else bad "$1 ($3 does not hold '$2')"; fi }
cleanup() {
    [ -n "$pid" ] && { say quit >/dev/null 2>&1; kill "$pid" 2>/dev/null; wait "$pid" 2>/dev/null; }
    if [ -f "$out/notes.bak" ]; then cp "$out/notes.bak" "$notes"; else rm -f "$notes"; fi
}
trap cleanup EXIT INT TERM
start() { # extra pleamar options
    MOOI_SHELL="$root/shell" pleamar --scene "$root/shell/mooi.plm" --no-hud --stall 0 --seconds 90 "$@" \
        > "$out/scene.log" 2>&1 &
    pid=$!
    for _ in $(seq 1 30); do sleep 0.3; say "get open" >/dev/null 2>&1 && break; done
}
stop() {
    say quit >/dev/null 2>&1; kill "$pid" 2>/dev/null; wait "$pid" 2>/dev/null; pid=''
    for _ in $(seq 1 30); do say "get open" >/dev/null 2>&1 || break; sleep 0.1; done
}

if say "get open" >/dev/null 2>&1; then
    echo "mooi is already running; stop it first (bin/mooi stop)"; exit 2
fi
[ -f "$notes" ] && cp "$notes" "$out/notes.bak"
rm -f "$notes"

start
echo "the pad opens and a note is written, as the input would send it"
say "emit qn_toggle" >/dev/null; sleep 0.3
is "the pad is open" "$(get qn_open)" true
say "text qn_draft Buy milk" >/dev/null; sleep 0.3
is "the input says it has something" "$(get qn_drafting)" true
say "emit qn_add" >/dev/null; sleep 0.4
is "the note is kept" "$(get qn_count)" 1
if [ -f "$notes" ]; then has "and written to notes.json" 'Buy milk' "$notes"; else bad "notes.json was not written"; fi
say "text qn_draft    " >/dev/null; sleep 0.2
say "emit qn_add" >/dev/null; sleep 0.3
is "an empty note is refused" "$(get qn_count)" 1

echo "Enter saves and takes the draft away"
say "submit qn_draft Call Ana" >/dev/null; sleep 0.5
is "the second note is saved" "$(get qn_count)" 2
is "the draft is cleared" "$(get qn_drafting)" false

echo "a press copies one, a press on × forgets it, Undo puts it back"
say "emit qn_copy 2" >/dev/null; sleep 0.4
is "the newest note is on the clipboard" "$(wl-paste 2>/dev/null)" "Call Ana"
say "emit qn_del 2" >/dev/null; sleep 0.3
is "it is forgotten" "$(get qn_count)" 1
is "Undo is offered" "$(get qn_can_undo)" true
say "emit qn_undo" >/dev/null; sleep 0.4
is "it is back" "$(get qn_count)" 2
has "and the file holds it again" 'Call Ana' "$notes"

echo "a note is changed where it stands"
say "emit qn_edit 2" >/dev/null; sleep 0.4
is "the note is being changed" "$(get qn_editing)" true
is "the row is the second note" "$(get qn_edit_id)" 2
is "the button says Save" "$(get qn_add_label)" SAVE
is "the draft holds what it said" "$(get qn_draft)" "Call Ana"
say "submit qn_draft Call Ana back" >/dev/null; sleep 0.5
is "it is saved, not added again" "$(get qn_count)" 2
is "the button is Add again" "$(get qn_add_label)" ADD
has "the file has the new text" 'Call Ana back' "$notes"
if grep -q 'Ana back back' "$notes"; then bad "the old text was kept too"; else ok "and not the old text as a second note"; fi

echo "Escape cancels a change before it closes the pad"
say "emit qn_edit 2" >/dev/null; sleep 0.3
say "key Escape" >/dev/null; sleep 0.3
is "the change is cancelled" "$(get qn_editing)" false
is "the pad is still open" "$(get qn_open)" true

echo "closing empties the draft; the file survives a restart"
say "text qn_draft loose ends" >/dev/null; sleep 0.2
say "emit qn_toggle" >/dev/null; sleep 0.2
is "the pad is closed" "$(get qn_open)" false
say "emit qn_toggle" >/dev/null; sleep 0.2
is "reopened, the draft is gone" "$(get qn_drafting)" false

echo "more notes than rows: the wheel pages through them"
i=1; while [ $i -le 5 ]; do say "submit qn_draft note $i" >/dev/null; sleep 0.2; i=$((i + 1)); done
is "seven notes" "$(get qn_count)" 7
is "the first page starts at one" "$(get qn_from)" 1
is "and ends at six" "$(get qn_to)" 6
say "emit qn_scroll -1" >/dev/null; sleep 0.3
is "the wheel moves down a row" "$(get qn_from)" 2
is "and stops at the last" "$(get qn_to)" 7
say "emit qn_scroll 9" >/dev/null; sleep 0.3
is "and back to the top" "$(get qn_page)" 0

echo "the terminal can save one too"
"$root/bin/mooi" note "from the cli" || bad "mooi note failed"
sleep 0.5
is "the count follows" "$(get qn_count)" 8
has "and the file has it" 'from the cli' "$notes"
say "key Escape" >/dev/null; sleep 0.3
is "Escape closes it" "$(get qn_open)" false
stop
start
is "every note is still there after a restart" "$(get qn_count)" 8

# A pointer press needs the module on the bar; it is placeable, not forced on any layout.
if [ "$(get p_notes)" = true ]; then
    x=$(get x_notes); w=$(get w_notes); o=$(get st_offset); h=$(get st_height)
    stop
    echo "a real press on the module opens the dropdown, and Escape closes it"
    start --mouse "$((x + w / 2)),$((o + h - 6))@900 click@1200"
    sleep 1.5
    is "the press opened it" "$(get qn_open)" true
    say "key Escape" >/dev/null; sleep 0.3
    is "Escape closed it" "$(get qn_open)" false
else
    echo "  skip  the module is not on this bar (edit mode places it)"
fi

echo
echo "$n checks, $fail failed · log $out/scene.log"
[ "$fail" -eq 0 ]
