#!/bin/sh
# The bar's chassis live (D164 stage 1): every Shape × Outline × Frame × Swell on the running mooi,
# screenshotted and measured — the foot of the bar's pieces sits at one height whatever the frame
# does, the outline's weight follows the Outline choice (none draws nothing), and in islands mode no
# outline crosses a gap between two pieces (the old "empty humps"). The frame's edge is held at
# "line" and the bar's surface at "solid": neon's glow and glass's light rim are the materials' own,
# not the outline, and are not what this measures.
#
# It needs mooi running as the desktop, grim, jq and ImageMagick. It changes settings.json for about
# two minutes and restores it byte for byte afterwards (also on Ctrl-C), with the player as it was.
# It never moves the pointer or sends a key.
set -u
root=$(cd "$(dirname "$0")/.." && pwd)
for c in grim jq magick; do command -v "$c" >/dev/null 2>&1 || { echo "chassis: $c is required"; exit 2; }; done
"$root/bin/mooi" status 2>/dev/null | grep -q "the desktop" || { echo "chassis: mooi is not running as the desktop"; exit 2; }
D="${XDG_DATA_HOME:-$HOME/.local/share}/pleamar/mooi"
F="$D/settings.json"
t=$(mktemp -d)
cp "$F" "$t/restore.json"
# the styles' own values (lib/style), so each style is shown as it is defined
lua5.4 - "$root" > "$t/presets.json" <<'LUA'
package.path = arg[1] .. "/shell/?.luau;" .. package.path
local st = require("lib/style")
local out = {}
for _, p in ipairs(st.BAR_PRESETS) do
    local parts = {}
    for k, v in pairs(p.set) do
        local key = k:match("^bar%.(.+)$")
        if key then parts[#parts + 1] = string.format("%q: %s", key, type(v) == "string" and string.format("%q", v) or tostring(v)) end
    end
    out[#out + 1] = string.format("%q: {%s}", p.name, table.concat(parts, ","))
end
print("{" .. table.concat(out, ",") .. "}")
LUA
was=$(playerctl status 2>/dev/null || echo none)
restore() {
    cp "$t/restore.json" "$F"
    [ "$was" = Playing ] || playerctl pause >/dev/null 2>&1
    rm -rf "$t"
}
trap 'restore' EXIT
trap 'exit 130' INT TERM HUP   # closing the terminal restores too (review)
playerctl play >/dev/null 2>&1

fail=0; n=0
ok()  { n=$((n + 1)); }
bad() { n=$((n + 1)); fail=$((fail + 1)); echo "  FAIL  $1"; }

# the grey levels (0-255) of the column x from row y0, h rows down
col() { magick "$1" -crop "1x$4+$2+$3" +repage -colorspace gray -depth 8 txt:- | awk -F'[()]' 'NR > 1 { split($2, a, ","); printf "%d ", a[1] }'; }

off=$(jq -r '.bar.offset // 0' "$t/restore.json")
height=$(jq -r '.bar.height // 30' "$t/restore.json")
rail=$(jq -r '.bar.rail // false' "$t/restore.json")
top=$((off + 8)); [ "$rail" = true ] && top=$((off + 15))

for shape in islands full notch; do
    feet=""
    for edge in none thin regular bold; do
        case $edge in none) fr=none; ow=2 ;; thin) fr=line; ow=1 ;; regular) fr=line; ow=2 ;; bold) fr=line; ow=3 ;; esac
        for frame in false true; do
            for swell in false true; do
                mo=off; [ "$swell" = true ] && mo=swell
                jq --arg m "$shape" --arg e "$edge" --arg fr "$fr" --argjson ow "$ow" --argjson on "$frame" --argjson mu "$swell" --arg mo "$mo" \
                    '.bar.mode=$m | .bar.edge=$e | .bar.frame=$fr | .bar.outline_width=$ow | .frame.on=$on | .frame.music=$mu | .frame.motion=$mo | .frame.style="swell" | .frame.edge="line" | .bar.surface="solid"' \
                    "$t/restore.json" > "$F.tmp" && mv "$F.tmp" "$F"
                sleep 3
                shot="$t/$shape-$edge-$frame-$swell.png"
                grim -g "0,0 1920x130" "$shot"
                g="$D/bar-geo.json"
                case $shape in
                    islands) x=$(jq -r '[.islands[] | select(.w > 0)][0] | (.x + .w / 2 | floor)' "$g") ;;
                    full) x=$(jq -r '.panel | (.x + .w / 4 | floor)' "$g") ;;   # clear of the frame's corner, which swells
                    notch) x=$(jq -r '(.left // .center) | (.x + .w / 2 | floor)' "$g") ;;
                esac
                if [ "$shape" = notch ]; then foot=$((off + 6 + height + 1)); else foot=$((top + height)); fi
                y0=$((foot - 4))
                vals=$(col "$shot" "$x" "$y0" 14)
                bg=$(echo "$vals" | awk '{ print $NF }')
                # the line's core: rows lit past 35 % of the way from the background to the brightest row
                # (a 2 px line off the pixel grid also tints its neighbours; that is antialiasing)
                lit=$(echo "$vals" | awk -v bg="$bg" '{ m = bg; for (i = 1; i <= NF - 4; i++) if ($i > m) m = $i
                       c = 0; if (m > bg + 25) for (i = 1; i <= NF - 4; i++) if ($i > bg + 0.35 * (m - bg)) c++; print c }')
                peak=$(echo "$vals" | awk -v y0="$y0" '{ m = -1; at = -1; for (i = 1; i <= NF - 4; i++) if ($i > m) { m = $i; at = y0 + i - 1 }; print at }')
                name="$shape · outline $edge · frame $frame · swell $swell"
                echo "  ..    $name: foot y=$peak, $lit rows lit"
                if [ "$edge" = none ] && [ "$shape" = islands ] && [ "$frame" = false ]; then
                    # a line is brighter than both the plate's own fill (inside, 3 rows above the foot) and
                    # the ground below; a lighter glass fill meeting a dark shadow is an edge, not a line
                    line=$(echo "$vals" | awk '{ f = $2; b = $NF; base = (f > b ? f : b); m = 0
                           for (i = 3; i <= NF - 4; i++) if ($i > m) m = $i; print (m > base + 25) ? 1 : 0 }')
                    if [ "$line" -eq 0 ]; then ok; else bad "$name: an outline is drawn at x=$x"; fi
                elif [ "$edge" != none ]; then
                    if [ "$lit" -ge 1 ] && [ "$lit" -le 3 ]; then ok; else bad "$name: outline weight $lit rows at x=$x (want 1-3)"; fi
                    d=$((peak - foot)); [ "$d" -lt 0 ] && d=$((-d))
                    # the border sits on or just inside the piece's edge: within 2 px of the model's foot,
                    # and (checked per shape below) within 1 px of every other state
                    if [ "$d" -le 2 ]; then ok; else bad "$name: foot at y=$peak, want $foot"; fi
                    feet="$feet $peak"
                fi
                if [ "$shape" = islands ]; then
                    gx=$(jq -r '[.islands[] | select(.w > 0)] | [range(1; length) as $i | {g: (.[$i].x - (.[$i-1].x + .[$i-1].w)), m: ((.[$i].x + .[$i-1].x + .[$i-1].w) / 2 | floor)}] | max_by(.g) | .m' "$g")
                    # between the plates' top and their foot: above the row is the band's (it may swell there)
                    gv=$(col "$shot" "$gx" "$top" $((foot - top - 2)))
                    gb=$(col "$shot" "$gx" $((foot + 10)) 1)
                    hump=$(echo "$gv" | awk -v bg="$gb" '{ c = 0; for (i = 1; i <= NF; i++) if ($i > bg + 25) c++; print c }')
                    if [ "$hump" -eq 0 ]; then ok; else bad "$name: an outline crosses the gap at x=$gx ($hump rows): a hump"; fi
                fi
            done
        done
    done
    lo=$(echo "$feet" | tr ' ' '\n' | grep . | sort -n | head -1)
    hi=$(echo "$feet" | tr ' ' '\n' | grep . | sort -n | tail -1)
    if [ -n "$lo" ] && [ $((hi - lo)) -le 1 ]; then ok; else bad "$shape: the foot moves between states (y $lo…$hi)"; fi
    echo "$shape: foot y $lo…$hi"
done

# ── Styles (D166): every style with the frame off and on, still and swelling, in islands mode ──
# A style with an outline has one line at the foot; one without (floating, minimal) has none even with
# the frame on; no state crosses the gaps between islands; the foot holds one height.
for style in instrument glass floating hairline minimal; do
    for frame in false true; do
        for swell in false true; do
            mo=off; [ "$swell" = true ] && mo=swell
            jq --arg st "$style" --argjson on "$frame" --argjson mu "$swell" --arg mo "$mo" --slurpfile pr "$t/presets.json" \
                '.bar.mode="islands" | .bar.style=$st | (.bar += $pr[0][$st]) | .frame.on=$on | .frame.music=$mu | .frame.motion=$mo | .frame.style="swell" | .frame.edge="line" | .frame.islands="float"' \
                "$t/restore.json" > "$F.tmp" && mv "$F.tmp" "$F"
            sleep 3
            shot="$t/style-$style-$frame-$swell.png"
            grim -g "0,0 1920x130" "$shot"
            g="$D/bar-geo.json"
            x=$(jq -r '[.islands[] | select(.w > 0)][0] | (.x + .w / 2 | floor)' "$g")
            # a style may turn the info rail on, which moves the row down: this state's own top
            stop=$((off + 8)); [ "$(jq -r '.bar.rail' "$F")" = true ] && stop=$((off + 15))
            foot=$((stop + height)); y0=$((foot - 4))
            vals=$(col "$shot" "$x" "$y0" 14)
            name="style $style · frame $frame · swell $swell"
            line=$(echo "$vals" | awk '{ f = $2; b = $NF; base = (f > b ? f : b); m = 0; at = 0
                   for (i = 3; i <= NF - 4; i++) if ($i > m) { m = $i; at = i }; print (m > base + 25) ? at : 0 }')
            case $style in floating | minimal) want=0 ;; *) want=1 ;; esac
            if [ "$want" = 0 ]; then
                if [ "$line" -eq 0 ]; then ok; else bad "$name: a line where the style has none"; fi
            else
                if [ "$line" -gt 0 ]; then ok; else bad "$name: no line where the style has one"; fi
                d=$((y0 + line - 1 - foot)); [ "$d" -lt 0 ] && d=$((-d))
                if [ "$line" -eq 0 ] || [ "$d" -le 2 ]; then ok; else bad "$name: foot at y=$((y0 + line - 1)), want $foot"; fi
            fi
            gx=$(jq -r '[.islands[] | select(.w > 0)] | [range(1; length) as $i | {g: (.[$i].x - (.[$i-1].x + .[$i-1].w)), m: ((.[$i].x + .[$i-1].x + .[$i-1].w) / 2 | floor)}] | max_by(.g) | .m' "$g")
            gv=$(col "$shot" "$gx" "$stop" $((foot - stop - 2)))
            gb=$(col "$shot" "$gx" $((foot + 10)) 1)
            hump=$(echo "$gv" | awk -v bg="$gb" '{ c = 0; for (i = 1; i <= NF; i++) if ($i > bg + 25) c++; print c }')
            if [ "$hump" -eq 0 ]; then ok; else bad "$name: an outline crosses the gap at x=$gx"; fi
        done
    done
done

# ── Attach (D166): the band comes down to the islands' top; the gaps are recesses, not tabs ──
for swell in false true; do
    mo=off; [ "$swell" = true ] && mo=swell
    jq --argjson mu "$swell" --arg mo "$mo" '.bar.mode="islands" | .frame.on=true | .frame.islands="attach" | .frame.music=$mu | .frame.motion=$mo | .frame.edge="line" | .bar.frame="line" | .bar.outline_width=2 | .bar.surface="solid"' \
        "$t/restore.json" > "$F.tmp" && mv "$F.tmp" "$F"
    sleep 3
    shot="$t/attach-$swell.png"; grim -g "0,0 1920x130" "$shot"
    g="$D/bar-geo.json"
    foot=$((top + height))
    gx=$(jq -r '[.islands[] | select(.w > 0)] | [range(1; length) as $i | {g: (.[$i].x - (.[$i-1].x + .[$i-1].w)), m: ((.[$i].x + .[$i-1].x + .[$i-1].w) / 2 | floor)}] | max_by(.g) | .m' "$g")
    gv=$(col "$shot" "$gx" $((top + 3)) $((foot - top - 5)))
    gb=$(col "$shot" "$gx" $((foot + 10)) 1)
    tab=$(echo "$gv" | awk -v bg="$gb" '{ c = 0; for (i = 1; i <= NF; i++) if ($i > bg + 25) c++; print c }')
    if [ "$tab" -eq 0 ]; then ok; else bad "attach · swell $swell: a line inside the recess at x=$gx (a tab)"; fi
    x=$(jq -r '[.islands[] | select(.w > 0)][0] | (.x + .w / 2 | floor)' "$g")
    vals=$(col "$shot" "$x" $((foot - 4)) 14)
    peak=$(echo "$vals" | awk -v y0=$((foot - 4)) '{ m = -1; at = -1; for (i = 1; i <= NF - 4; i++) if ($i > m) { m = $i; at = y0 + i - 1 }; print at }')
    d=$((peak - foot)); [ "$d" -lt 0 ] && d=$((-d))
    if [ "$d" -le 2 ]; then ok; else bad "attach · swell $swell: foot at y=$peak, want $foot"; fi
done

echo "$n checks, $fail failed"
[ "$fail" -eq 0 ]
