#!/bin/sh
# Neovim, lazygit, Starship and Obsidian in mooi's palette (D298), without the session: `bin/mooi apps-sync` in a
# throwaway XDG tree. On, each gets mooi's own file beside the owner's (a colorscheme and its plugin file, a lazygit
# theme laid over config.yml, a prompt of mooi's, a snippet in each vault switched on) and apps-env.lua names the
# right configs; off, mooi's files go, the vault's snippet list is the owner's again, and the owner's own files were
# never touched. hyprctl is stubbed. Run from anywhere: tests/apps-more.sh
set -u
root=$(cd "$(dirname "$0")/.." && pwd)
command -v jq >/dev/null 2>&1 && command -v lua5.4 >/dev/null 2>&1 || { echo "apps-more: jq and lua5.4 are required"; exit 2; }
t=$(mktemp -d); trap 'rm -rf "$t"' EXIT
export HOME="$t/home" XDG_CONFIG_HOME="$t/config" XDG_DATA_HOME="$t/data" XDG_STATE_HOME="$t/state" XDG_RUNTIME_DIR="$t/run"
C=$XDG_CONFIG_HOME; D=$XDG_DATA_HOME/pleamar/mooi; V="$t/vault"
mkdir -p "$C/nvim" "$C/lazygit" "$C/obsidian" "$V/.obsidian" "$D" "$t/bin" "$HOME" "$XDG_RUNTIME_DIR"
for b in pkill hyprctl lazygit starship; do printf '#!/bin/sh\nexit 0\n' > "$t/bin/$b"; chmod +x "$t/bin/$b"; done
PATH="$t/bin:$PATH"; export PATH
printf 'gui:\n  showIcons: true\n' > "$C/lazygit/config.yml"
printf 'format = "$all"\n' > "$C/starship.toml"
printf 'vim.opt.number = true\n' > "$C/nvim/init.lua"
printf '{"vaults":{"a":{"path":"%s"}}}' "$V" > "$C/obsidian/obsidian.json"
printf '{"enabledCssSnippets":["mine"]}' > "$V/.obsidian/appearance.json"
fail=0; n=0
ok()  { n=$((n + 1)); echo "  ok    $1"; }
bad() { n=$((n + 1)); fail=$((fail + 1)); echo "  FAIL  $1"; }
is()  { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1 ('$2', expected '$3')"; fi; }
apps() { # nvim lazygit starship obsidian
    lua5.4 -e "package.path='$root/shell/?.luau;'..package.path
        local m = require('lib/appcolors').material(require('lib/ferro').resolve('mooi', nil, 'auto', false, {}))
        local keys = {} ; for k in pairs(m) do keys[#keys + 1] = k end ; table.sort(keys)
        io.write('{\"kitty\":false,\"gtk\":false,\"qt\":false,\"files\":true,\"nvim\":$1,\"lazygit\":$2,\"starship\":$3,\"obsidian\":$4,\"colors\":{')
        for i, k in ipairs(keys) do io.write((i > 1 and ',' or '') .. '\"' .. k .. '\":\"' .. m[k] .. '\"') end
        io.write('}}')" > "$D/apps.json" || exit 1
}
sync() { bash "$root/bin/mooi" apps-sync >/dev/null 2>&1; }
yes_() { if [ -e "$1" ]; then echo yes; else echo no; fi; }

echo "on: mooi's files beside the owner's"
apps true true true true; sync
is "the colorscheme" "$(yes_ "$C/nvim/colors/mooi.lua")" yes
is "rendered, no tag left" "$(grep -c '{{colors' "$C/nvim/colors/mooi.lua")" 0
is "worn at start" "$(grep -c 'colorscheme, "mooi"' "$C/nvim/plugin/mooi-theme.lua")" 1
is "lazygit's theme" "$(yes_ "$C/lazygit/mooi-theme.yml")" yes
is "Starship's prompt" "$(grep -c 'palette = "mooi"' "$C/mooi/starship.toml")" 1
is "the vault's snippet" "$(yes_ "$V/.obsidian/snippets/mooi.css")" yes
is "and it is switched on, beside the owner's" "$(jq -c .enabledCssSnippets "$V/.obsidian/appearance.json")" '["mine","mooi"]'
is "the environment names mooi's" "$(grep -c "mooi-theme.yml" "$D/apps-env.lua")$(grep -c "mooi/starship.toml" "$D/apps-env.lua")" 11
is "a second sync adds nothing" "$(sync; jq -c .enabledCssSnippets "$V/.obsidian/appearance.json")" '["mine","mooi"]'

echo "off: mooi's files go, the owner's were never touched"
apps false false false false; sync
is "no colorscheme" "$(yes_ "$C/nvim/colors/mooi.lua")$(yes_ "$C/nvim/plugin")" nono
is "no lazygit theme" "$(yes_ "$C/lazygit/mooi-theme.yml")" no
is "no prompt" "$(yes_ "$C/mooi/starship.toml")" no
is "no snippet, the owner's list" "$(yes_ "$V/.obsidian/snippets/mooi.css")$(jq -c .enabledCssSnippets "$V/.obsidian/appearance.json")" 'no["mine"]'
is "the environment names the owner's" "$(grep -c "mooi" "$D/apps-env.lua")" 0
is "config.yml untouched" "$(cat "$C/lazygit/config.yml")" "$(printf 'gui:\n  showIcons: true')"
is "starship.toml untouched" "$(cat "$C/starship.toml")" 'format = "$all"'
is "init.lua untouched" "$(cat "$C/nvim/init.lua")" 'vim.opt.number = true'

echo "$n checks, $fail failed"
[ "$fail" -eq 0 ]
