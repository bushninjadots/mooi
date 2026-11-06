#!/bin/sh
# Kitty's own screen shaders (kitty ≥ 0.49), without the session: `bin/mooi kitty-shaders` writes a
# small conf beside the settings and points kitty.conf at it with one `include` line at the end,
# then asks kitty to read its config again. Your own `custom_shaders` line is never touched, a run
# with nothing changed is quiet, and the switch off takes exactly the conf and the include away.
# Nothing of the real ~/.config or data folder is read or written, and pkill is stubbed out.
# Run from anywhere: tests/kitty-shaders.sh
set -u
root=$(cd "$(dirname "$0")/.." && pwd)
command -v jq >/dev/null 2>&1 || { echo "kitty-shaders: jq is required"; exit 2; }
t=$(mktemp -d); trap 'rm -rf "$t"' EXIT
export HOME="$t/home" XDG_CONFIG_HOME="$t/config" XDG_DATA_HOME="$t/data" \
    XDG_STATE_HOME="$t/state" XDG_RUNTIME_DIR="$t/run"
C=$XDG_CONFIG_HOME; D=$XDG_DATA_HOME/pleamar/mooi
mkdir -p "$C/kitty" "$D" "$t/bin" "$HOME" "$XDG_RUNTIME_DIR"
printf '#!/bin/sh\nexit 0\n' > "$t/bin/pkill"; chmod +x "$t/bin/pkill"
PATH="$t/bin:$PATH"; export PATH
fail=0; n=0
ok()    { n=$((n + 1)); echo "  ok    $1"; }
bad()   { n=$((n + 1)); fail=$((fail + 1)); echo "  FAIL  $1"; }
is()    { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1 ('$2', expected '$3')"; fi; }
has()   { if grep -q -- "$2" "$3" 2>/dev/null; then ok "$1"; else bad "$1 ($3 has no '$2')"; fi; }
lacks() { if grep -q -- "$2" "$3" 2>/dev/null; then bad "$1 ($3 has '$2')"; else ok "$1"; fi; }

settings() { # on|off SHADER [CUSTOM] [TINT] [COLOUR]
    if [ "$1" = on ]; then o=true; else o=false; fi
    jq -n --argjson on "$o" --arg s "$2" --arg c "${3:-}" --arg t "${4:-55}" --arg k "${5:-primary}" \
      '{desktop: {kitty_shader_on: $on, kitty_shader: $s, kitty_shader_custom: $c, kitty_shader_tint: ($t | tonumber), kitty_shader_colour: $k}}' > "$D/settings.json"
}
sync() { sh "$root/bin/mooi" kitty-shaders 2>&1; }

printf 'font_size 11\ncustom_shaders northern-lights\n' > "$C/kitty/kitty.conf"

echo "the switch on: mooi's include, after your own lines"
settings on crt
out=$(sync)
is "it says which shader" "$out" "kitty: custom_shaders crt"
has "the conf file names it" '^custom_shaders crt$' "$D/kitty-shaders.conf"
is "the include is the last line" "$(tail -n 1 "$C/kitty/kitty.conf")" "include $D/kitty-shaders.conf"
has "your own line is still there" '^custom_shaders northern-lights$' "$C/kitty/kitty.conf"
is "the include is there once" "$(grep -cF "include $D/kitty-shaders.conf" "$C/kitty/kitty.conf")" "1"

echo "a second run changes nothing and does not churn kitty"
before=$(cksum "$C/kitty/kitty.conf")
out=$(sync)
is "it is quiet" "$out" ""
is "kitty.conf is byte for byte the same" "$(cksum "$C/kitty/kitty.conf")" "$before"

echo "another shader: the same one include, rewritten in place"
settings on tft
sync >/dev/null
has "the conf file follows" '^custom_shaders tft$' "$D/kitty-shaders.conf"
is "still exactly one include" "$(grep -cF "include $D/kitty-shaders.conf" "$C/kitty/kitty.conf")" "1"
is "and it is still last" "$(tail -n 1 "$C/kitty/kitty.conf")" "include $D/kitty-shaders.conf"

echo "Mine: a pipeline of your own, by path"
settings on custom "/home/you/.config/kitty/shaders/mine.pipeline"
sync >/dev/null
has "the conf file names the path" '^custom_shaders /home/you/.config/kitty/shaders/mine.pipeline$' "$D/kitty-shaders.conf"

echo "Mine with nothing chosen is refused, and writes nothing"
settings on custom ""
before=$(cat "$D/kitty-shaders.conf")
out=$(sync)
case $out in *"no pipeline is named"*) ok "it says why" ;; *) bad "it says why ('$out')" ;; esac
is "the conf file is as it was" "$(cat "$D/kitty-shaders.conf")" "$before"

echo "a name with a space is refused: it would be two shaders"
settings on custom "my shader"
out=$(sync)
case $out in *"cannot hold spaces"*) ok "it says why" ;; *) bad "it says why ('$out')" ;; esac
is "and the last good conf file is kept" "$(cat "$D/kitty-shaders.conf")" "$before"

echo "Mooi CRT: kitty's crt tinted with the bar's primary, rendered from palette.json"
printf '{"version":1,"mode":"dark","colours":{"primary":"#a7c8ff"}}' > "$D/palette.json"
tint_of() { # #rrggbb → the same arithmetic the writer does, independently
    python3 -c 'import sys
def lin(v):
    c = int(v, 16) / 255
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4
h = sys.argv[1]
r, g, b = (lin(h[i:i+2]) for i in (0, 2, 4))
m = max(r, g, b) or 1
print("%.6f, %.6f, %.6f" % (r / m, g / m, b / m))' "$1"
}
settings on mooi-crt
sync >/dev/null
want=$(tint_of a7c8ff)
has "the pipeline sets TINT from the palette" "var float4 TINT = float4($want, 0.55)" "$D/kitty-mooi-crt.pipeline"
has "the pipeline runs kitty's crt" 'shaders crt' "$D/kitty-mooi-crt.pipeline"
is "the conf points at the pipeline by path" "$(grep '^custom_shaders' "$D/kitty-shaders.conf")" "custom_shaders $D/kitty-mooi-crt.pipeline"
is "the include is still last" "$(tail -n 1 "$C/kitty/kitty.conf")" "include $D/kitty-shaders.conf"

 echo "and it follows the palette: another primary, another tint"
printf '{"version":1,"mode":"dark","colours":{"primary":"#ff7043"}}' > "$D/palette.json"
sync >/dev/null
has "the new colour is in the pipeline" "float4($(tint_of ff7043), 0.55)" "$D/kitty-mooi-crt.pipeline"

 echo "no palette yet: it says so and wears kitty's own crt"
rm -f "$D/palette.json"
out=$(sync)
case $out in *"no palette yet"*) ok "it says why" ;; *) bad "it says why ('$out')" ;; esac
is "the conf falls back to the plain shader" "$(grep '^custom_shaders' "$D/kitty-shaders.conf")" "custom_shaders crt"
if [ -f "$D/kitty-mooi-crt.pipeline" ]; then bad "the stale pipeline is gone"; else ok "the stale pipeline is gone"; fi

printf '{"version":1,"mode":"dark","colours":{"primary":"#a7c8ff"}}' > "$D/palette.json"
settings on mooi-crt
sync >/dev/null
has "the pipeline is back with a palette" "var float4 TINT" "$D/kitty-mooi-crt.pipeline"

echo "the strength is a setting: absent means 55 %"
jq -n --argjson on true --arg s mooi-crt '{desktop: {kitty_shader_on: $on, kitty_shader: $s}}' > "$D/settings.json"
sync >/dev/null
has "the default strength is 0.55" "float4(.*, 0.55)" "$D/kitty-mooi-crt.pipeline"

echo "and it dials from subtle to strong"
settings on mooi-crt "" 20
sync >/dev/null
has "20 % is 0.20" "float4(.*, 0.20)" "$D/kitty-mooi-crt.pipeline"
settings on mooi-crt "" 90
sync >/dev/null
has "90 % is 0.90" "float4(.*, 0.90)" "$D/kitty-mooi-crt.pipeline"
settings on mooi-crt "" 0
sync >/dev/null
has "0 % is no tint at all" "float4(.*, 0.00)" "$D/kitty-mooi-crt.pipeline"
settings on mooi-crt "" 140
sync >/dev/null
has "above 100 is clamped to 1.00" "float4(.*, 1.00)" "$D/kitty-mooi-crt.pipeline"

echo "the colour is a setting too: any palette role can drive it"
printf '{"version":1,"mode":"dark","colours":{"primary":"#a7c8ff","secondary":"#bdc7dc","error":"#ffb4ab"}}' > "$D/palette.json"
settings on mooi-crt "" 55 secondary
sync >/dev/null
has "secondary drives the tint" "float4($(tint_of bdc7dc), 0.55)" "$D/kitty-mooi-crt.pipeline"
settings on mooi-crt "" 55 error
sync >/dev/null
has "error drives the tint" "float4($(tint_of ffb4ab), 0.55)" "$D/kitty-mooi-crt.pipeline"
settings on mooi-crt "" 55 bogus
sync >/dev/null
has "a role the palette lacks falls back to primary" "float4($(tint_of a7c8ff), 0.55)" "$D/kitty-mooi-crt.pipeline"

echo "the switch off: exactly what mooi added goes"
settings off crt
out=$(sync)
is "it says so" "$out" "kitty: your own shaders again"
lacks "the include is gone" "kitty-shaders.conf" "$C/kitty/kitty.conf"
if [ -f "$D/kitty-shaders.conf" ]; then bad "the conf file is gone too"; else ok "the conf file is gone too"; fi
if [ -f "$D/kitty-mooi-crt.pipeline" ]; then bad "mooi's pipeline is gone too"; else ok "mooi's pipeline is gone too"; fi
is "kitty.conf is your own two lines again" "$(cat "$C/kitty/kitty.conf")" "font_size 11
custom_shaders northern-lights"

echo "a machine with no kitty.conf: it says so instead of making one"
rm -f "$C/kitty/kitty.conf"
settings on crt
out=$(sync)
case $out in *"nothing to point at it"*) ok "it says why" ;; *) bad "it says why ('$out')" ;; esac
if [ -f "$C/kitty/kitty.conf" ]; then bad "no kitty.conf was created"; else ok "no kitty.conf was created"; fi

echo
echo "$n checks, $fail failed"
[ "$fail" -eq 0 ]
