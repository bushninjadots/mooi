#!/bin/sh
# The node live (D226): the Dynamic Pill on the running mooi, in Pill mode — asked what it is through
# `pleamar --say mooi-node get …` while mooi's own commands drive it: the seed at rest, Super's wake (the system
# cluster, or the music), the launcher (Super+Space: it holds the keyboard, Esc gives it back), the universe
# (Super+Tab), and the settings it obeys (off: it is not running). SHOTS=dir keeps screenshots. Restores
# settings.json byte for byte. Never moves the pointer.
set -u
root=$(cd "$(dirname "$0")/.." && pwd)
for c in jq grim; do command -v "$c" >/dev/null 2>&1 || { echo "node: $c is required"; exit 2; }; done
"$root/bin/mooi" status 2>/dev/null | grep -q "the desktop" || { echo "node: mooi is not running as the desktop"; exit 2; }
D="${XDG_DATA_HOME:-$HOME/.local/share}/pleamar/mooi"
F="$D/settings.json"
t=$(mktemp -d)
cp "$F" "$t/restore.json"
restore() { cp "$t/restore.json" "$F"; rm -rf "$t"; }
trap 'restore' EXIT
trap 'exit 130' INT TERM HUP PIPE

fail=0; n=0
ok()  { n=$((n + 1)); echo "  ok    $1"; }
bad() { n=$((n + 1)); fail=$((fail + 1)); echo "  FAIL  $1"; }
is()  { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1 ('$2', expected '$3')"; fi }
nd()  { timeout 3 pleamar --say mooi-node "get $1" 2>/dev/null; }
set_() { jq "$1" "$t/restore.json" > "$F.tmp" && mv "$F.tmp" "$F"; sleep "${2:-3}"; }
running() { pgrep -af 'mooi-node\.plm' >/dev/null && echo yes || echo no; }
shot() { [ -n "${SHOTS:-}" ] && grim -g "$2" "$SHOTS/$1.png"; }
# the node's kind, waiting a moment for it to become `want` (the logic answers within a few hundred ms)
kind_is() { w=0; while [ "$(nd nd_kind)" != "$2" ] && [ $w -lt 10 ]; do sleep 0.2; w=$((w + 1)); done; is "$1" "$(nd nd_kind)" "$2"; }

echo "Pill mode, the node on: it runs, a seed at rest"
set_ '.bar.mode="pill" | .node.on=true | .node.personality="organic"' 5
is "the node runs in Pill mode" "$(running)" yes
kind_is "at rest: the seed" 0
is "the seed is small" "$(nd nd_tw)" 22
shot seed "0,0 1920x120"

echo "Super wakes it; again closes it"
"$root/bin/mooi" node wake; sleep 0.8
k=$(nd nd_kind)
if [ "$k" = 5 ] || [ "$k" = 1 ]; then ok "woken: the system cluster (or the music)"; else bad "woken ('$k', expected 5 or 1)"; fi
shot wake "560,0 800x320"
"$root/bin/mooi" node wake
kind_is "Super again: back to the seed" 0

echo "Super+Space: the launcher holds the keyboard; Esc gives it back"
"$root/bin/mooi" node launch
kind_is "the launcher" 6
is "it holds the keyboard" "$(nd nd_kb)" true
shot launch "560,0 800x420"
pleamar --say mooi-node "emit nd_key 27" >/dev/null 2>&1
kind_is "Esc: back to the seed" 0
is "the keyboard given back" "$(nd nd_kb)" false

echo "Super+Tab: the universe"
"$root/bin/mooi" node universe
kind_is "the workspaces round it" 7
shot universe "0,0 1920x1080"
pleamar --say mooi-node "emit nd_key 27" >/dev/null 2>&1
kind_is "Esc: back to the seed" 0

echo "the settings it obeys"
set_ '.bar.mode="pill" | .node.on=false' 5
is "off: it is not running" "$(running)" no
set_ '.bar.mode="notch"' 5
is "another shape: it is not running" "$(running)" no

echo
echo "$n checks, $fail failed"
[ "$fail" -eq 0 ]
