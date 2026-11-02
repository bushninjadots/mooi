#!/usr/bin/env bash
# Local checks for the hyprland config repo (no CI):
#   - Lua syntax for every config module with luac -p.
#   - Deprecated Hyprland options: hyprctl deprecated-config when a session is up
#     (it sees the overlays and custom/ too), plus a static grep for the options
#     Hyprland 0.57 dropped, so an edit cannot reintroduce them unnoticed.
#   - Bash syntax for the installer/scripts with bash -n.
#   - shellcheck (advisory) when available.
#
# Usage: scripts/check.sh
set -u
cd "$(dirname "$0")/.." || exit 1

fail=0

if ! command -v luac >/dev/null 2>&1; then
    echo "error: luac not found (install the Lua compiler)" >&2
    exit 2
fi

lua_total=0
while IFS= read -r f; do
    lua_total=$((lua_total + 1))
    if ! luac -p "$f" >/dev/null 2>&1; then
        echo "luac FAIL: $f"
        fail=1
    fi
done < <(find config -name '*.lua' -not -path '*/.git/*' | sort)
echo "luac: $lua_total Lua modules checked"

# Options Hyprland 0.57 marks deprecated (config/values/ConfigValues.cpp and the Lua rule
# bindings): both special_scale_factor variants, misc:layers_hog_keyboard_focus,
# debug:invalidate_fp16, the on_created_empty workspace rule and the lock_active() dispatcher.
# Matched only as assignments/calls, so the comments that explain the removals do not trip it.
deprecated_re='(special_scale_factor|layers_hog_keyboard_focus|invalidate_fp16|on_created_empty)[[:space:]]*='
dep_static=0
while IFS= read -r hit; do
    echo "deprecated option: $hit"
    dep_static=$((dep_static + 1))
done < <(grep -rnE "$deprecated_re" hyprland.lua config 2>/dev/null)
if grep -rqE '\.lock_active[[:space:]]*\(' hyprland.lua config 2>/dev/null; then
    echo "deprecated dispatcher: lock_active() — use group.lock() instead"
    dep_static=$((dep_static + 1))
fi

if command -v hyprctl >/dev/null 2>&1 && hyprctl version >/dev/null 2>&1; then
    dep_live="$(hyprctl deprecated-config 2>/dev/null)"
    if [ -n "$dep_live" ] && [ "$dep_live" != "all good!" ]; then
        printf '%s\n' "$dep_live" | sed 's/^/deprecated (live): /'
        fail=1
    else
        echo "deprecated: live session reports all good!"
    fi
else
    echo "deprecated: no running session, static check only"
fi
[ "$dep_static" -gt 0 ] && fail=1

sh_total=0
while IFS= read -r f; do
    sh_total=$((sh_total + 1))
    if ! bash -n "$f" 2>/dev/null; then
        echo "bash -n FAIL: $f"
        fail=1
    fi
    if command -v shellcheck >/dev/null 2>&1; then
        shellcheck -S warning "$f" >/dev/null 2>&1 || echo "shellcheck note: $f (advisory)"
    fi
done < <(find . -name '*.sh' -not -path './.git/*' | sort)
echo "bash -n: $sh_total scripts checked"

if [ "$fail" -eq 0 ]; then
    echo "hyprland: checks OK"
fi
exit "$fail"
