#!/bin/sh
# Lumen's picture, live (D59): the studio is opened on a folder of test pictures, one is chosen,
# and the screen is photographed where the picture is. The screenshot must hold the picture, not
# one flat colour: a preview declared as a 1 × 1 cell once painted its average colour over the
# whole screen while every control worked. The same crop of the preview is compared with it.
#
# It shows the studio on screen for ~15 s and writes only in a temporary home. It never applies a
# wallpaper, moves a window or touches the desktop's own `wallpapers.json`.
#
# The background key (D62) is checked on a creature on a white field with white eyes: the field
# becomes the typed colour, the eyes stay white — the background is what the picture's edge is
# joined to, not every pixel of its colour. The folder picker is walked with a typed path, HOME,
# PICTURES and PARENT, and through a folder that is a **link**.
# Run from anywhere: tests/wallpaper.sh
set -u
root=$(cd "$(dirname "$0")/.." && pwd)
out=${TMPDIR:-/tmp}/mooi-wallpaper.$$
mkdir -p "$out"
fail=0; n=0; pid=''

say() { pleamar --say mooi-wallpaper "$@" 2>&1; }
get() { say "get $1" | tail -1; }
ok() { n=$((n + 1)); echo "  ok    $1"; }
bad() { n=$((n + 1)); fail=$((fail + 1)); echo "  FAIL  $1"; }
is() { if [ "$2" = "$3" ]; then ok "$1 ($2)"; else bad "$1 (got '$2', expected '$3')"; fi }

cleanup() {
    [ -n "$pid" ] && { say quit >/dev/null 2>&1; kill "$pid" 2>/dev/null; wait "$pid" 2>/dev/null; }
    rm -rf "$out"
}
trap cleanup EXIT INT TERM
stop_studio() {
    say quit >/dev/null 2>&1; kill "$pid" 2>/dev/null; wait "$pid" 2>/dev/null; pid=''
    for _ in $(seq 1 30); do say "get studio_in" >/dev/null 2>&1 || break; sleep 0.1; done
}
wait_for() { # a fact's name, the value wanted, and how many tries
    for _ in $(seq 1 "${3:-60}"); do sleep 0.2; [ "$(get "$1")" = "$2" ] && return 0; done
    return 1
}

if say "get studio_in" >/dev/null 2>&1; then
    echo "the wallpaper studio is already open; close it first (Escape)"; exit 2
fi

# A picture four colours apart, so a preview that is one averaged pixel is unmistakable.
mkdir -p "$out/pics" "$out/home/Pictures" "$out/data" "$out/config"
magick -size 800x450 xc:'#d02020' /tmp/.mooi-wp-a.$$.png
magick -size 800x450 xc:'#20c040' /tmp/.mooi-wp-b.$$.png
magick -size 800x450 xc:'#2040d0' /tmp/.mooi-wp-c.$$.png
magick -size 800x450 xc:'#e0c020' /tmp/.mooi-wp-d.$$.png
magick /tmp/.mooi-wp-a.$$.png /tmp/.mooi-wp-b.$$.png +append "$out/top.png"
magick /tmp/.mooi-wp-c.$$.png /tmp/.mooi-wp-d.$$.png +append "$out/bottom.png"
magick "$out/top.png" "$out/bottom.png" -append "$out/pics/quadrants.png"
rm -f /tmp/.mooi-wp-a.$$.png /tmp/.mooi-wp-b.$$.png /tmp/.mooi-wp-c.$$.png /tmp/.mooi-wp-d.$$.png "$out/top.png" "$out/bottom.png"

HOME=$out/home XDG_DATA_HOME=$out/data XDG_CONFIG_HOME=$out/config \
    pleamar --scene "$root/shell/mooi-wallpaper.plm" --no-hud --seconds 60 > "$out/scene.log" 2>&1 &
pid=$!
up=''
for _ in $(seq 1 40); do
    sleep 0.25
    if say "get studio_in" >/dev/null 2>&1; then sleep 0.2; say "get studio_in" >/dev/null 2>&1 && up=1; fi
    [ -n "$up" ] && break
    up=''
done
if [ -z "$up" ]; then bad "the studio did not come up"; echo; echo "$n passed, $fail failed"; exit 1; fi
sleep 1

echo "the studio reads the folder and a picture is chosen"
say "emit open_browse" >/dev/null; sleep 0.4
say "text src_folder $out/pics" >/dev/null
say "emit set_folder" >/dev/null
chosen=''
for _ in $(seq 1 40); do
    sleep 0.2
    [ "$(get count_label)" = "1 IN THE FOLDER" ] && { chosen=1; break; }
done
[ -n "$chosen" ] && ok "the folder is read (1 picture)" || bad "the folder was not read: $(get count_label)"
say "emit pick_source 0" >/dev/null
for _ in $(seq 1 60); do sleep 0.25; [ "$(get has_preview)" = true ] && break; done
is "a preview is made" "$(get has_preview)" true
preview=$(get prev_file)
if [ -f "$preview" ]; then ok "the preview is a file"; else bad "no preview at '$preview'"; fi

# Where the picture is, under no chrome: header 118, the right rail at width - 444, dock from
# height - 248, so a sixth in from the left and a fifth down, two fifths wide and a quarter tall,
# is always picture.
size=$(hyprctl -j monitors 2>/dev/null | jq -r '[.[] | select(.focused)][0] | "\(.width) \(.height)"' 2>/dev/null)
sw=${size% *}; sh=${size#* }
[ -n "$sw" ] && [ "$sw" -gt 0 ] || { echo "could not read the screen size"; exit 2; }
cx=$((sw / 6)); cy=$((sh / 5)); cw=$((sw * 2 / 5)); ch=$((sh / 4))
sleep 1
grim -g "$cx,$cy ${cw}x${ch}" "$out/seen.png" 2>/dev/null
if [ -s "$out/seen.png" ]; then ok "the screen was photographed"; else bad "the screen could not be photographed"; fi

colours=$(magick "$out/seen.png" -format '%k' info: 2>/dev/null)
if [ "${colours:-0}" -gt 8 ]; then ok "the picture is on screen ($colours colours, not one flat fill)"
else bad "the picture is one flat fill ($colours colours)"; fi

# What should be there: the preview, at the screen's size, with the studio's 8 % shade over it.
if [ -f "$preview" ]; then
    magick "$preview" -resize "${sw}x${sh}!" "$out/expect-full.png"
    magick "$out/expect-full.png" -fill black -colorize 8% -crop "${cw}x${ch}+${cx}+${cy}" +repage "$out/expect.png"
    magick compare -metric RMSE "$out/seen.png" "$out/expect.png" null: 2> "$out/rmse" || true
    rmse=$(sed 's/.*(\(.*\))/\1/' "$out/rmse")
    awk -v v="$rmse" 'BEGIN{exit !(v < 0.04)}' \
        && ok "the screen is the chosen picture (RMSE ${rmse:-?})" \
        || bad "the screen is not the chosen picture (RMSE ${rmse:-?})"
fi

echo "the source view is a picture too"
for _ in $(seq 1 40); do [ -n "$(get src_file)" ] && break; sleep 0.25; done
[ -f "$(get src_file)" ] && ok "the source view is made" || bad "no source view"
say "fact comparing true" >/dev/null; sleep 0.8
grim -g "$cx,$cy ${cw}x${ch}" "$out/source.png" 2>/dev/null
scolours=$(magick "$out/source.png" -format '%k' info: 2>/dev/null)
if [ "${scolours:-0}" -gt 8 ]; then ok "the unedited source is on screen ($scolours colours)"
else bad "the source view is one flat fill ($scolours colours)"; fi
say "fact comparing false" >/dev/null

echo "the backdrop reads the picture's edges and is drawn round it"
# A pale picture inside a solid frame: the frame is what the edges wear, and a matte of it is
# unmistakable against the picture's own white.
mkdir -p "$out/back"
magick -size 800x450 xc:'#f0f0f0' \
    -fill '#204060' -draw 'rectangle 0,0 799,39' -draw 'rectangle 0,410 799,449' \
    -draw 'rectangle 0,0 39,449' -draw 'rectangle 760,0 799,449' "$out/back/framed.png"
old=$(get prev_file)
say "emit open_browse" >/dev/null; sleep 0.3
say "text src_folder $out/back" >/dev/null
say "emit set_folder" >/dev/null
seen=''
for _ in $(seq 1 40); do sleep 0.2; [ "$(get count_label)" = "1 IN THE FOLDER" ] && { seen=1; break; }; done
[ -n "$seen" ] && ok "the framed picture is found" || bad "the framed folder was not read: $(get count_label)"
say "emit pick_source 0" >/dev/null
for _ in $(seq 1 60); do
    sleep 0.25
    [ "$(get src_name)" = framed.png ] && [ "$(get prev_file)" != "$old" ] && [ "$(get has_preview)" = true ] && break
done
is "the framed picture is chosen" "$(get src_name)" framed.png
backdrop=$(get prev_file)
[ -f "$backdrop" ] && ok "its preview is made" || bad "no preview for the framed picture"

edge=''
for _ in $(seq 1 40); do sleep 0.25; edge=$(get bg_hex0); [ "$edge" = "#204060" ] && break; done
is "the colour is read from the picture's corners" "$edge" "#204060"
is "and its edges" "$(get bg_hex1)" "#204060"

say "emit set_tab 4" >/dev/null; sleep 0.3
is "the backdrop tab is shown" "$(get tab)" 4
say "emit pick_bg 2" >/dev/null
for _ in $(seq 1 40); do sleep 0.25; [ "$(get bg_sel)" = 2 ] && break; done
is "the corners' colour is chosen" "$(get bg_sel)" 2
matte=''
for _ in $(seq 1 40); do sleep 0.25; matte=$(get prev_file); [ "$matte" != "$backdrop" ] && break; done
[ -f "$matte" ] && ok "the preview is drawn again with the matte" || bad "the matte's preview was not made"
# JPEG moves a colour a little, so the matte is read as a mean and held to a few levels of it.
corner=$(magick "$matte" -crop 40x40+0+0 +repage -format '%[fx:int(mean.r*255)],%[fx:int(mean.g*255)],%[fx:int(mean.b*255)]' info: 2>/dev/null)
centre=$(magick "$matte" -crop 40x40+780+430 +repage -format '%[fx:int(mean.r*255)],%[fx:int(mean.g*255)],%[fx:int(mean.b*255)]' info: 2>/dev/null)
awk -v c="${corner:-0,0,0}" 'BEGIN{split(c,p,","); exit !(p[1]>26 && p[1]<38 && p[2]>58 && p[2]<70 && p[3]>90 && p[3]<102)}' \
    && ok "the matte is the picture's own edge colour ($corner)" \
    || bad "the matte is not the picture's edge colour ($corner, expected ~32,64,96)"
awk -v c="${centre:-0,0,0}" 'BEGIN{split(c,p,","); exit !(p[1]>200 && p[2]>200 && p[3]>200)}' \
    && ok "and the picture still sits on it ($centre)" \
    || bad "the picture was not drawn over the matte ($centre)"

echo "the still that is applied is made at the screen's size, matte and all"
say "emit apply_now" >/dev/null
still=''
for _ in $(seq 1 80); do
    sleep 0.25
    still=$(ls -t "$out/home/.cache/mooi/wallpaper"/wall-*.png 2>/dev/null | head -1)
    # A PNG takes a moment to write; the file exists before it is whole, so it is only read once
    # ImageMagick can identify it.
    [ -n "$still" ] && [ -n "$(magick identify -format '%m' "$still" 2>/dev/null)" ] && break
    sleep 0.25
    still=''
done
[ -f "$still" ] && ok "the still is rendered" || bad "no still was rendered"
if [ -f "$still" ]; then
    is "at the screen's size" "$(magick identify -format '%wx%h' "$still" 2>/dev/null)" "${sw}x${sh}"
    # Lossless (D63): the still is a PNG, so a flat fill arrives at the exact colour asked for —
    # a JPEG moved it a level or two, which is what this reads.
    is "and lossless" "$(magick identify -format '%m' "$still" 2>/dev/null)" PNG
    scall=$(magick "$still" -crop 40x40+0+0 +repage -format '%[fx:int(mean.r*255)],%[fx:int(mean.g*255)],%[fx:int(mean.b*255)]' info: 2>/dev/null)
    awk -v c="${scall:-0,0,0}" 'BEGIN{split(c,p,","); exit !(p[1]==32 && p[2]==64 && p[3]==96)}' \
        && ok "with the matte in the picture's colour, exactly ($scall)" \
        || bad "the still has no matte ($scall, expected exactly 32,64,96)"
fi

echo "the picture's own background is keyed out into the backdrop"
# A flat field in the detected colour with a white subject in it: keyed, the field must become the
# backdrop and the subject must stay.
mkdir -p "$out/key"
magick -size 800x450 xc:'#204060' -fill '#f0f0f0' -draw 'rectangle 250,125 549,324' "$out/key/keyed.png"
say "emit open_browse" >/dev/null; sleep 0.3
say "text src_folder $out/key" >/dev/null
say "emit set_folder" >/dev/null
wait_for count_label "1 IN THE FOLDER" && ok "the keyable picture is found" || bad "the keyable folder was not read: $(get count_label)"
old=$(get prev_file)
say "emit pick_source 0" >/dev/null
for _ in $(seq 1 60); do sleep 0.25; [ "$(get src_name)" = keyed.png ] && [ "$(get prev_file)" != "$old" ] && break; done
is "it is chosen" "$(get src_name)" keyed.png
say "emit set_tab 4" >/dev/null; sleep 0.3
say "emit pick_bg 0" >/dev/null
for _ in $(seq 1 40); do sleep 0.25; [ "$(get prev_file)" != "$old" ] && break; done
pre_key=$(get prev_file)
say "emit toggle_key" >/dev/null
wait_for key_on 1 && ok "the key is on" || bad "the key did not turn on ($(get key_on))"
keyed=''
for _ in $(seq 1 60); do sleep 0.25; keyed=$(get prev_file); [ "$keyed" != "$pre_key" ] && break; done
field=$(magick "$keyed" -crop 30x30+216+438 +repage -format '%[fx:int(mean.r*255)],%[fx:int(mean.g*255)],%[fx:int(mean.b*255)]' info: 2>/dev/null)
subject=$(magick "$keyed" -crop 30x30+785+435 +repage -format '%[fx:int(mean.r*255)],%[fx:int(mean.g*255)],%[fx:int(mean.b*255)]' info: 2>/dev/null)
awk -v c="${field:-255,255,255}" 'BEGIN{split(c,p,","); exit !(p[1]<24 && p[2]<24 && p[3]<24)}' \
    && ok "the picture's background became the backdrop ($field)" \
    || bad "the background was not keyed out ($field)"
awk -v c="${subject:-0,0,0}" 'BEGIN{split(c,p,","); exit !(p[1]>200 && p[2]>200 && p[3]>200)}' \
    && ok "and the subject was kept ($subject)" \
    || bad "the subject went with it ($subject)"

kept=''
for _ in $(seq 1 40); do sleep 0.2; grep -q '"edges"' "$out/data/pleamar/mooi-wallpaper/wallpapers.json" 2>/dev/null && { kept=1; break; }; done
[ -n "$kept" ] && ok "the edges read are kept in wallpapers.json" \
    || bad "the edges were not kept in wallpapers.json"

echo "a white background goes, the white inside the subject stays, and any colour fills it"
# A creature on a white field, with white eyes: a colour key would take the eyes with the field,
# but the background is what the edge is joined to, so the eyes are not part of it (D62).
mkdir -p "$out/alien"
magick -size 800x450 xc:'#f4f4f4' \
    -fill '#101010' -draw 'ellipse 400,225 150,110 0,360' \
    -fill '#ffffff' -draw 'ellipse 350,200 40,26 0,360' -draw 'ellipse 450,200 40,26 0,360' \
    "$out/alien/alien.png"
say "emit open_browse" >/dev/null; sleep 0.3
say "text src_folder $out/alien" >/dev/null
say "emit set_folder" >/dev/null
wait_for count_label "1 IN THE FOLDER" 40 && ok "the creature is found" || bad "the creature's folder was not read: $(get count_label)"
old=$(get prev_file)
say "emit pick_source 0" >/dev/null
for _ in $(seq 1 60); do sleep 0.25; [ "$(get src_name)" = alien.png ] && [ "$(get prev_file)" != "$old" ] && break; done
is "it is chosen" "$(get src_name)" alien.png
say "emit reset_recipe" >/dev/null; sleep 0.6
say "emit toggle_key" >/dev/null
wait_for key_on 1 40 && ok "the background is keyed" || bad "the key did not turn on ($(get key_on))"
# The key's own preview is still being drawn; the colour is chosen after it lands, so what is
# compared below is the custom render and not the keyed one.
sleep 1.5
pre_custom=$(get prev_file)
say "text bg_custom_hex #c02040" >/dev/null; sleep 0.3
say "emit use_bg_custom" >/dev/null
wait_for bg_sel 5 40 && ok "the typed colour is the backdrop" || bad "the custom backdrop was not chosen ($(get bg_sel))"
is "and it is kept in lower case" "$(get bg_custom_hex)" "#c02040"
custom=''
for _ in $(seq 1 60); do sleep 0.25; custom=$(get prev_file); [ "$custom" != "$pre_custom" ] && break; done
[ -f "$custom" ] && ok "a preview is drawn with it" || bad "no preview with the custom colour"
sleep 0.5
cfill=$(magick "$custom" -colorspace sRGB -crop 12x12+80+80 +repage -format '%[fx:int(mean.r*255)],%[fx:int(mean.g*255)],%[fx:int(mean.b*255)]' info: 2>/dev/null)
ceye=$(magick "$custom" -colorspace sRGB -crop 12x12+700+400 +repage -format '%[fx:int(mean.r*255)],%[fx:int(mean.g*255)],%[fx:int(mean.b*255)]' info: 2>/dev/null)
cbody=$(magick "$custom" -colorspace sRGB -crop 12x12+800+450 +repage -format '%[fx:int(mean.r*255)],%[fx:int(mean.g*255)],%[fx:int(mean.b*255)]' info: 2>/dev/null)
awk -v c="${cfill:-255,255,255}" 'BEGIN{split(c,p,","); exit !(p[1]>176 && p[1]<208 && p[2]>18 && p[2]<46 && p[3]>50 && p[3]<78)}' \
    && ok "the white background became the typed colour ($cfill)" \
    || bad "the background is not the typed colour ($cfill, expected ~192,32,64)"
awk -v c="${ceye:-0,0,0}" 'BEGIN{split(c,p,","); exit !(p[1]>220 && p[2]>220 && p[3]>220)}' \
    && ok "the white eye inside the creature stayed white ($ceye)" \
    || bad "the eye went with the background ($ceye)"
awk -v c="${cbody:-255,255,255}" 'BEGIN{split(c,p,","); exit !(p[1]<40 && p[2]<40 && p[3]<40)}' \
    && ok "and the creature stayed dark ($cbody)" \
    || bad "the creature was not kept ($cbody)"

if grep -q '"bg_custom": "#c02040"' "$out/data/pleamar/mooi-wallpaper/wallpapers.json" 2>/dev/null; then
    ok "the colour is kept with the picture's recipe"
else
    bad "the custom colour was not written in wallpapers.json"
fi

echo "a palette swatch fills the background, and an edit can be taken back"
sleep 1
say "emit pick_swatch 0" >/dev/null
wait_for sw_sel 0 40 && ok "the first swatch is the fill" || bad "the swatch was not chosen ($(get sw_sel))"
is "and its colour is in the field" "$(get bg_custom_hex)" "#000000"
palette=''
for _ in $(seq 1 60); do sleep 0.25; palette=$(get prev_file); [ "$palette" != "$custom" ] && break; done
psw=$(magick "$palette" -colorspace sRGB -crop 12x12+80+80 +repage -format '%[fx:int(mean.r*255)]' info: 2>/dev/null)
awk -v v="${psw:-255}" 'BEGIN{exit !(v<24)}' \
    && ok "the picture's background is that colour ($psw)" \
    || bad "the swatch did not fill the background ($psw)"
wait_for can_undo 1 20 && ok "there is something to take back" || bad "no history was kept"
say "emit undo_recipe" >/dev/null
wait_for bg_custom_hex "#c02040" 40 && ok "undo returns the colour before it" \
    || bad "undo did not go back ($(get bg_custom_hex))"
back=''
for _ in $(seq 1 60); do sleep 0.25; back=$(get prev_file); [ "$back" != "$palette" ] && break; done
bsw=$(magick "$back" -colorspace sRGB -crop 12x12+80+80 +repage -format '%[fx:int(mean.r*255)],%[fx:int(mean.g*255)],%[fx:int(mean.b*255)]' info: 2>/dev/null)
awk -v c="${bsw:-0,0,0}" 'BEGIN{split(c,p,","); exit !(p[1]>176 && p[1]<208 && p[2]>18 && p[2]<46 && p[3]>50 && p[3]<78)}' \
    && ok "and the preview with it ($bsw)" \
    || bad "the undone preview is not the colour before it ($bsw)"
wait_for can_redo 1 20 && ok "and something to put forward" || bad "no redo was offered"
say "emit redo_recipe" >/dev/null
wait_for bg_custom_hex "#000000" 40 && ok "redo puts the swatch back" \
    || bad "redo did not return ($(get bg_custom_hex))"

echo "the folder picker goes anywhere: a typed path, and a folder that is a link"
rmdir "$out/home/Pictures" 2>/dev/null
mkdir -p "$out/linked/walls" "$out/home/Downloads"
magick -size 80x45 xc:'#20c040' "$out/linked/walls/link.png"
ln -sfn "$out/linked" "$out/home/Pictures"
say "emit open_picker" >/dev/null
wait_for picking true 40 && ok "the picker opens" || bad "the picker did not open"
say "submit pick_typed $out/pics" >/dev/null
wait_for pick_path "$out/pics" 40 && ok "a typed folder is gone to ($out/pics)" || bad "the typed folder was not entered ($(get pick_path))"
say "emit pick_up" >/dev/null; sleep 0.5
is "and the parent is one press" "$(get pick_path)" "$out"
say "emit pick_jump 1" >/dev/null
wait_for pick_path "$out/home/Pictures" 40 && ok "PICTURES jumps to the home folder's pictures" \
    || bad "PICTURES went somewhere else ($(get pick_path))"
wait_for pick_count "1 FOLDERS" 40 && ok "a folder that is a link is listed ($(get pick_count))" \
    || bad "the linked folder was not read ($(get pick_count))"
say "emit pick_dir 0" >/dev/null; sleep 0.6
is "and entered" "$(get pick_path)" "$out/home/Pictures/walls"
say "emit pick_choose" >/dev/null; sleep 1
wait_for picking false 40 && ok "the folder is taken" || bad "the picker stayed open"
wait_for count_label "1 IN THE FOLDER" 40 && ok "and its pictures are read through the link ($(get count_label))" \
    || bad "the pictures behind the link were not read ($(get count_label))"

echo "a restart starts a new picture on the settings' defaults, from the cached colours"
stop_studio
mkdir -p "$out/fresh" "$out/data/pleamar/mooi-wallpaper"
magick -size 800x450 xc:'#f0f0f0' "$out/fresh/plain.png"
cat > "$out/data/pleamar/mooi-wallpaper/settings.json" <<'JSON'
{ "wallpaper": { "matte": 10, "backdrop": "black", "key": false, "fuzz": 18 } }
JSON
HOME=$out/home XDG_DATA_HOME=$out/data XDG_CONFIG_HOME=$out/config \
    pleamar --scene "$root/shell/mooi-wallpaper.plm" --no-hud --seconds 60 > "$out/scene2.log" 2>&1 &
pid=$!
for _ in $(seq 1 40); do sleep 0.25; [ "$(get studio_in)" = 1 ] && break; done
sleep 1.5
say "emit open_browse" >/dev/null; sleep 0.3
say "text src_folder $out/fresh" >/dev/null
say "emit set_folder" >/dev/null
wait_for count_label "1 IN THE FOLDER" && ok "a new folder is read" || bad "the new folder was not read: $(get count_label)"
say "emit pick_source 0" >/dev/null
for _ in $(seq 1 60); do sleep 0.25; [ "$(get src_name)" = plain.png ] && [ "$(get has_preview)" = true ] && break; done
sleep 0.8
fresh=$(get prev_file)
edge=$(magick "$fresh" -colorspace sRGB -crop 30x30+0+0 +repage -format '%[fx:int(mean.r*255)],%[fx:int(mean.g*255)],%[fx:int(mean.b*255)]' info: 2>/dev/null)
middle=$(magick "$fresh" -colorspace sRGB -crop 30x30+785+435 +repage -format '%[fx:int(mean.r*255)],%[fx:int(mean.g*255)],%[fx:int(mean.b*255)]' info: 2>/dev/null)
awk -v c="${edge:-255,255,255}" 'BEGIN{split(c,p,","); exit !(p[1]<24 && p[2]<24 && p[3]<24)}' \
    && ok "the settings' matte and backdrop open with the picture ($edge)" \
    || bad "the settings' defaults were not used ($edge)"
awk -v c="${middle:-0,0,0}" 'BEGIN{split(c,p,","); exit !(p[1]>200 && p[2]>200 && p[3]>200)}' \
    && ok "and the picture is inset into it ($middle)" \
    || bad "the picture was not inset ($middle)"
say "emit pick_source 0" >/dev/null
wait_for bg_note CACHED 40 && ok "its edges come back from the cache" \
    || bad "the cached edges were not used ($(get bg_note))"

echo
echo "$n passed, $fail failed"
[ "$fail" -eq 0 ]
