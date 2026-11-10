#!/bin/sh
# Text from the screen (D269) without a screen: `bin/mooi capture text` with stand-ins for slurp (a region), grim (a
# picture of known words, drawn with ImageMagick) and wl-copy / notify-send (files), and the real tesseract. The
# words reach the clipboard and the notice; an Esc at the region copies nothing and says nothing; a blank region
# copies nothing and says so; a missing tool is named. Skipped where tesseract or magick is not installed (CI).
# Run from anywhere: tests/capture-text.sh
set -u
root=$(cd "$(dirname "$0")/.." && pwd)
command -v tesseract >/dev/null 2>&1 && command -v magick >/dev/null 2>&1 || { echo "capture-text: skipped (no tesseract or magick)"; exit 0; }
t=$(mktemp -d); trap 'rm -rf "$t"' EXIT
export HOME="$t/home" XDG_DATA_HOME="$t/data" XDG_STATE_HOME="$t/state" XDG_RUNTIME_DIR="$t/run" MOOI_PLEAMAR=true
mkdir -p "$HOME" "$XDG_RUNTIME_DIR" "$t/bin"
magick -size 420x80 xc:white -fill black -pointsize 36 -annotate +12+52 'Hello mooi 42' "$t/words.png"
magick -size 420x80 xc:white "$t/blank.png"
cp "$t/words.png" "$t/shown.png"
printf '#!/bin/sh\n[ -f "%s/esc" ] && exit 1\necho "0,0 420x80"\n' "$t" > "$t/bin/slurp"
printf '#!/bin/sh\ncat "%s/shown.png"\n' "$t" > "$t/bin/grim"
printf '#!/bin/sh\ncat > "%s/clip"\n' "$t" > "$t/bin/wl-copy"
printf '#!/bin/sh\nshift 2; printf "%%s\\n" "$*" >> "%s/notices"\n' "$t" > "$t/bin/notify-send"
chmod +x "$t/bin/"*
export PATH="$t/bin:$PATH"
fail=0; n=0
ok()  { n=$((n + 1)); echo "  ok    $1"; }
bad() { n=$((n + 1)); fail=$((fail + 1)); echo "  FAIL  $1"; }
is()  { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1 ('$2', expected '$3')"; fi; }
run() { bash "$root/bin/mooi" capture text >/dev/null 2>&1; echo $?; }

echo "a region's words go to the clipboard"
is "it succeeds" "$(run)" 0
is "the words are copied" "$(cat "$t/clip" 2>/dev/null)" "Hello mooi 42"
is "a notice says what" "$(head -n 1 "$t/notices")" "Copied the text Hello mooi 42"

echo "Esc at the region: nothing copied, nothing said"
rm -f "$t/clip" "$t/notices"; touch "$t/esc"
is "it ends quietly" "$(run)" 0
is "no clipboard" "$([ -e "$t/clip" ] && echo yes || echo no)" no
is "no notice" "$([ -e "$t/notices" ] && echo yes || echo no)" no
rm -f "$t/esc"

echo "a region with no words: nothing copied, and it says so"
cp "$t/blank.png" "$t/shown.png"
is "it fails" "$(run)" 1
is "no clipboard" "$([ -e "$t/clip" ] && echo yes || echo no)" no
is "the notice" "$(cat "$t/notices")" "Text from the screen No words found there"

echo "a missing tool is named"
# a PATH of links to the system's programs with slurp left out, and no stand-in for it: the real one is never
# reachable, so nothing waits for a region on a real screen
mkdir -p "$t/sys"
for f in /usr/bin/*; do case "${f##*/}" in slurp) ;; *) ln -s "$f" "$t/sys/" 2>/dev/null ;; esac; done
rm -f "$t/notices" "$t/bin/slurp"
PATH="$t/bin:$t/sys"
is "it fails" "$(run)" 1
is "the notice names it" "$(cat "$t/notices")" "Text from the screen Needs: slurp"

echo "$n checks, $fail failed"
[ "$fail" -eq 0 ]
