#!/bin/sh
# Quick notes (D51), live: the pad's module, its dropdown and its file. A note is written as the
# input would send it (`text` then `submit`), added with the Add button's event, copied, forgotten
# and found again after a restart. Where the module is on this machine's bar, a real pointer press
# opens the dropdown and Escape closes it.
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
cleanup() {
    [ -n "$pid" ] && { say quit >/dev/null 2>&1; kill "$pid" 2>/dev/null; wait "$pid" 2>/dev/null; }
    if [ -f "$out/notes.bak" ]; then cp "$out/notes.bak" "$notes"; else rm -f "$notes"; fi
}
trap cleanup EXIT INT TERM
start() { # extra pleamar options
    MOOI_SHELL="$root/shell" pleamar --scene "$root/shell/mooi.plm" --no-hud --stall 0 --seconds 60 "$@" \
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
if [ -f "$notes" ] && grep -q 'Buy milk' "$notes"; then ok "and written to notes.json"; else bad "notes.json does not hold it ($notes)"; fi
say "text qn_draft    " >/dev/null; sleep 0.2
say "emit qn_add" >/dev/null; sleep 0.3
is "an empty note is refused" "$(get qn_count)" 1

echo "Enter saves and takes the draft away"
say "submit qn_draft Call Ana" >/dev/null; sleep 0.5
is "the second note is saved" "$(get qn_count)" 2
is "the draft is cleared" "$(get qn_drafting)" false

echo "a press copies one, a press on × forgets it"
say "emit qn_copy 2" >/dev/null; sleep 0.4
is "the newest note is on the clipboard" "$(wl-paste 2>/dev/null)" "Call Ana"
say "emit qn_del 2" >/dev/null; sleep 0.3
is "it is forgotten" "$(get qn_count)" 1

echo "closing empties the draft; the file survives a restart"
say "text qn_draft loose ends" >/dev/null; sleep 0.2
say "emit qn_toggle" >/dev/null; sleep 0.2
is "the pad is closed" "$(get qn_open)" false
say "emit qn_toggle" >/dev/null; sleep 0.2
is "reopened, the draft is gone" "$(get qn_drafting)" false
say "key Escape" >/dev/null; sleep 0.3
is "Escape closes it" "$(get qn_open)" false
stop
start
is "the note is still there after a restart" "$(get qn_count)" 1

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
