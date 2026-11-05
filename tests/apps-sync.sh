#!/bin/sh
# Your apps in mooi's palette, without the session: `bin/mooi apps-sync` renders Kitty, GTK and
# Qt into a throwaway XDG tree, then puts every file back when the switch goes off. It also
# covers the two ways the switch used to leave mooi behind: a gtk.css mooi created where there
# was none (it must be removed again, not kept), and a Matugen output mooi redirected (the
# user's own last gtk.css must come back, not mooi's render).
# Nothing of the real ~/.config, ~/.cache or data folder is read or written, and pkill is
# stubbed out. Run from anywhere: tests/apps-sync.sh
set -u
root=$(cd "$(dirname "$0")/.." && pwd)
command -v jq >/dev/null 2>&1 || { echo "apps-sync: jq is required"; exit 2; }
command -v lua5.4 >/dev/null 2>&1 || { echo "apps-sync: lua5.4 is required"; exit 2; }
t=$(mktemp -d); trap 'rm -rf "$t"' EXIT
export HOME="$t/home" XDG_CONFIG_HOME="$t/config" XDG_DATA_HOME="$t/data" \
    XDG_STATE_HOME="$t/state" XDG_RUNTIME_DIR="$t/run"
C=$XDG_CONFIG_HOME; D=$XDG_DATA_HOME/pleamar/mooi
mkdir -p "$C/kitty" "$C/matugen/templates" "$C/gtk-3.0" "$C/gtk-4.0" \
    "$C/qt5ct/colors" "$C/qt6ct" "$D" "$t/bin" "$HOME" "$XDG_RUNTIME_DIR"
printf '#!/bin/sh\nexit 0\n' > "$t/bin/pkill"; chmod +x "$t/bin/pkill"
PATH="$t/bin:$PATH"; export PATH
fail=0; n=0
ok()    { n=$((n + 1)); echo "  ok    $1"; }
bad()   { n=$((n + 1)); fail=$((fail + 1)); echo "  FAIL  $1"; }
is()    { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1 ('$2', expected '$3')"; fi }
has()   { if grep -q -- "$2" "$3" 2>/dev/null; then ok "$1"; else bad "$1 ($3 has no '$2')"; fi }
lacks() { if grep -q -- "$2" "$3" 2>/dev/null; then bad "$1 ($3 has '$2')"; else ok "$1"; fi }

# The palette document the bar writes (apps.json), built from the same libraries it uses, so
# every tag mooi's templates read has a colour and the numbers are not invented here.
apps() { # kitty gtk qt [files] (true/false; files defaults to on)
    lua5.4 -e "package.path='$root/shell/?.luau;'..package.path
        local m = require('lib/appcolors').material(require('lib/ferro').resolve('mooi', nil, 'auto', false, {}))
        local keys = {} ; for k in pairs(m) do keys[#keys + 1] = k end ; table.sort(keys)
        io.write('{\"kitty\":$1,\"gtk\":$2,\"qt\":$3,\"files\":${4:-true},\"colors\":{')
        for i, k in ipairs(keys) do io.write((i > 1 and ',' or '') .. '\"' .. k .. '\":\"' .. m[k] .. '\"') end
        io.write('}}')" > "$D/apps.json" || exit 1
}

sync() { sh "$root/bin/mooi" apps-sync; }

# ── a machine that already has colours of its own ────────────────────────────
printf 'font_size 11\ninclude colors-user.conf\n' > "$C/kitty/kitty.conf"
printf '/* the user gtk3 */\n@define-color accent_bg_color #123456;\n' > "$C/gtk-3.0/gtk.css"
printf '/* the user gtk4 */\n@define-color accent_bg_color #123456;\n' > "$C/gtk-4.0/gtk.css"
printf '/* user template 3 */\n@define-color accent_bg_color {{colors.primary.default.hex}};\n' > "$C/matugen/templates/gtk3.css"
printf '/* user template 4 */\n@define-color accent_bg_color {{colors.primary.default.hex}};\n' > "$C/matugen/templates/gtk4.css"
printf '[config]\n[templates.gtk3]\noutput_path = "~/.config/gtk-3.0/gtk.css"\n[templates.gtk4]\noutput_path = "~/.config/gtk-4.0/gtk.css"\n' > "$C/matugen/config.toml"
printf '[Appearance]\ncustom_palette=false\ncolor_scheme_path=/usr/share/qt5ct/colors/user.conf\nstyle=Fusion\n' > "$C/qt5ct/qt5ct.conf"
printf '[Appearance]\ncustom_palette=false\ncolor_scheme_path=/usr/share/qt6ct/colors/user.conf\nstyle=Fusion\n' > "$C/qt6ct/qt6ct.conf"

echo "the switches on: each app gets mooi's palette"
apps true true true
sync >/dev/null
accent=$(jq -r '.colors.primary' "$D/apps.json")
is "Kitty's include points at mooi" "$(grep '^include' "$C/kitty/kitty.conf")" "include colors-mooi.conf"
has "Kitty's colours were rendered" "cursor .*$accent" "$C/kitty/colors-mooi.conf"
lacks "no template tag was left behind in Kitty" '{{' "$C/kitty/colors-mooi.conf"
has "GTK 3 is mooi's, from the user's own template" "accent_bg_color $accent" "$C/gtk-3.0/gtk.css"
has "GTK 4 is mooi's, from the user's own template" "accent_bg_color $accent" "$C/gtk-4.0/gtk.css"
lacks "no template tag was left behind in GTK 4" '{{' "$C/gtk-4.0/gtk.css"
has "Matugen writes GTK 3 aside while mooi is on" 'output_path = "~/.cache/mooi/matugen-gtk-3.0.css"' "$C/matugen/config.toml"
has "Matugen writes GTK 4 aside while mooi is on" 'output_path = "~/.cache/mooi/matugen-gtk-4.0.css"' "$C/matugen/config.toml"
is "Matugen's last GTK 3 was kept to go back to" "$(cat "$HOME/.cache/mooi/matugen-gtk-3.0.css")" "/* the user gtk3 */
@define-color accent_bg_color #123456;"
has "Qt 5 reads mooi's scheme" "color_scheme_path=$C/qt5ct/colors/mooi.conf" "$C/qt5ct/qt5ct.conf"
has "Qt 6 reads mooi's scheme" "color_scheme_path=$C/qt6ct/colors/mooi.conf" "$C/qt6ct/qt6ct.conf"
has "Qt 5 uses the custom palette" "custom_palette=true" "$C/qt5ct/qt5ct.conf"

echo "the switches off: every file is what it was"
apps false false false
sync >/dev/null
is "Kitty's own include is back" "$(grep '^include' "$C/kitty/kitty.conf")" "include colors-user.conf"
is "GTK 3 is the user's again" "$(cat "$C/gtk-3.0/gtk.css")" "/* the user gtk3 */
@define-color accent_bg_color #123456;"
is "GTK 4 is the user's again" "$(cat "$C/gtk-4.0/gtk.css")" "/* the user gtk4 */
@define-color accent_bg_color #123456;"
has "Matugen's GTK 3 output is back" 'output_path = "~/.config/gtk-3.0/gtk.css"' "$C/matugen/config.toml"
has "Matugen's GTK 4 output is back" 'output_path = "~/.config/gtk-4.0/gtk.css"' "$C/matugen/config.toml"
has "Qt 5 is the user's again" "color_scheme_path=/usr/share/qt5ct/colors/user.conf" "$C/qt5ct/qt5ct.conf"
has "Qt 5's custom palette is the user's again" "custom_palette=false" "$C/qt5ct/qt5ct.conf"
has "Qt 6 is the user's again" "color_scheme_path=/usr/share/qt6ct/colors/user.conf" "$C/qt6ct/qt6ct.conf"
lacks "apps.state kept nothing behind" . "$D/apps.state"

echo "there was no gtk.css before mooi: turning GTK off removes the one mooi made"
rm -f "$C/gtk-3.0/gtk.css" "$C/gtk-4.0/gtk.css" "$C/matugen/templates/gtk3.css" "$C/matugen/templates/gtk4.css"
printf '[config]\n' > "$C/matugen/config.toml"
apps false true false
sync >/dev/null
[ -f "$C/gtk-3.0/gtk.css" ] && ok "GTK 3 was written where there was none" || bad "GTK 3 was not written"
[ -f "$C/gtk-4.0/gtk.css" ] && ok "GTK 4 was written where there was none" || bad "GTK 4 was not written"
# mooi's own GTK 4 template (used when the user has none) carries Nautilus's
# classes too, so those tags must resolve from apps.json like every other one.
lacks "mooi's own GTK 4 template leaves no tag behind in Nautilus's rules" '{{' "$C/gtk-4.0/gtk.css"
has "Nautilus's file selection is themed from mooi's own template" 'columnview > listview > row:selected' "$C/gtk-4.0/gtk.css"
has "Nautilus's Places selection is themed from mooi's own template" 'placessidebar row:selected' "$C/gtk-4.0/gtk.css"
lacks "the Files markers stay out of gtk.css" 'mooi:files:' "$C/gtk-4.0/gtk.css"

echo "the Files switch off: Nautilus's own classes are cut back out"
apps false true false false
sync >/dev/null
lacks "no Nautilus path bar rule" 'nautilus-pathbar' "$C/gtk-4.0/gtk.css"
lacks "no Nautilus Places rule" 'placessidebar' "$C/gtk-4.0/gtk.css"
lacks "no Nautilus selection rule" 'nautilus-grid-view' "$C/gtk-4.0/gtk.css"
lacks "the marked block leaves no marker behind" 'mooi:files:' "$C/gtk-4.0/gtk.css"
has "the rest of GTK is still mooi's" 'accent_bg_color' "$C/gtk-4.0/gtk.css"
apps false false false
sync >/dev/null
[ ! -e "$C/gtk-3.0/gtk.css" ] && ok "GTK 3's mooi-made file is gone" || bad "GTK 3's mooi-made file stayed"
[ ! -e "$C/gtk-4.0/gtk.css" ] && ok "GTK 4's mooi-made file is gone" || bad "GTK 4's mooi-made file stayed"

echo "Matugen owns the output but its file is missing: the switch off still removes mooi's"
printf '[config]\n[templates.gtk3]\noutput_path = "~/.config/gtk-3.0/gtk.css"\n' > "$C/matugen/config.toml"
rm -f "$HOME/.cache/mooi/matugen-gtk-3.0.css"   # nothing of the user's to put back
apps false true false
sync >/dev/null
[ -f "$C/gtk-3.0/gtk.css" ] && ok "GTK 3 was written" || bad "GTK 3 was not written"
apps false false false
sync >/dev/null
has "Matugen's GTK 3 output is back" 'output_path = "~/.config/gtk-3.0/gtk.css"' "$C/matugen/config.toml"
[ ! -e "$C/gtk-3.0/gtk.css" ] && ok "and mooi's file is gone, not left behind" || bad "mooi's file stayed"

echo "a Kitty include with trailing whitespace is still the line to replace"
printf 'font_size 11\ninclude colors-user.conf   \n' > "$C/kitty/kitty.conf"
rm -f "$D/apps.state"
apps true false false
sync >/dev/null
is "it was replaced, not duplicated" "$(grep -c '^include' "$C/kitty/kitty.conf")" "1"
is "and it is mooi's, cleanly" "$(grep '^include' "$C/kitty/kitty.conf")" "include colors-mooi.conf"
apps false false false
sync >/dev/null
is "the user's include is back" "$(grep '^include' "$C/kitty/kitty.conf")" "include colors-user.conf"

echo "apps.state lost while mooi's include is in place: the switch off still removes it"
printf 'font_size 11\ninclude colors-mooi.conf\n' > "$C/kitty/kitty.conf"
rm -f "$D/apps.state"
apps true false false
sync >/dev/null
apps false false false
sync >/dev/null
is "no mooi include is left behind" "$(grep -c '^include' "$C/kitty/kitty.conf")" "0"

echo "a qt5ct.conf with no custom_palette key gets one, and gets it removed again"
printf '[Appearance]\ncolor_scheme_path=/usr/share/qt5ct/colors/user.conf\nstyle=Fusion\n' > "$C/qt5ct/qt5ct.conf"
apps false false true
sync >/dev/null
has "the scheme is mooi's" "color_scheme_path=$C/qt5ct/colors/mooi.conf" "$C/qt5ct/qt5ct.conf"
has "custom_palette was added" "custom_palette=true" "$C/qt5ct/qt5ct.conf"
apps false false false
sync >/dev/null
has "the user's scheme is back" "color_scheme_path=/usr/share/qt5ct/colors/user.conf" "$C/qt5ct/qt5ct.conf"
lacks "the key mooi added is gone" '^custom_palette=' "$C/qt5ct/qt5ct.conf"

echo "the scheme was already mooi's but custom_palette was missing: off still removes what mooi added"
printf '[Appearance]\ncolor_scheme_path=%s\nstyle=Fusion\n' "$C/qt5ct/colors/mooi.conf" > "$C/qt5ct/qt5ct.conf"
apps false false true
sync >/dev/null
has "custom_palette was added" "custom_palette=true" "$C/qt5ct/qt5ct.conf"
apps false false false
sync >/dev/null
has "the scheme path is untouched" "color_scheme_path=$C/qt5ct/colors/mooi.conf" "$C/qt5ct/qt5ct.conf"
lacks "and the added key is gone" '^custom_palette=' "$C/qt5ct/qt5ct.conf"

echo "a Matugen line with spaces, a comment and an absolute path is put back verbatim"
cat > "$C/matugen/config.toml" <<'TOML'
[config]
[templates.gtk3]
output_path   =   "/home/someone/.config/gtk-3.0/gtk.css"   # mine
TOML
apps false true false
sync >/dev/null
has "the line was redirected" '~/.cache/mooi/matugen-gtk-3.0.css' "$C/matugen/config.toml"
apps false false false
sync >/dev/null
is "the user's line is back, exactly" "$(grep '^output_path' "$C/matugen/config.toml")" 'output_path   =   "/home/someone/.config/gtk-3.0/gtk.css"   # mine'

echo "a generated Papirus-Mooi is preferred for icons when it exists"
mkdir -p "$XDG_DATA_HOME/icons/Papirus-Mooi"
printf '[Icon Theme]\nName=Papirus-Mooi\n' > "$XDG_DATA_HOME/icons/Papirus-Mooi/index.theme"
apps false false true
sync >/dev/null
has "Qt points at the generated icon theme" "icon_theme=Papirus-Mooi" "$C/qt5ct/qt5ct.conf"
rm -rf "$XDG_DATA_HOME/icons/Papirus-Mooi"
apps false false false
sync >/dev/null

echo
echo "$n checks, $fail failed"
[ "$fail" -eq 0 ]
