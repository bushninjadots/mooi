#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════════════
# plugins_scan.sh — discovery for the equisdots plugin standard (shell side).
#
# Emits a single JSON array: one object per installed plugin, sorted by name.
# A plugin is any directory containing a plugin.json manifest, scanned in:
#
#   user    $PLUGINS_USER     (default ~/.config/hypr/plugins-user)   — wins
#   managed $PLUGINS_MANAGED  (default ~/.config/hypr/plugins)        — dots
#
# AUTONOMY: each plugin owns its settings in ITS OWN file
# (<dir>/settings.json), never mixed into the core settings.json. This scan
# resolves `enabled` from the plugin's OWN file (the manifest's toggle path, or
# <scope>.enabled, falling back to the manifest's defaultEnabled). The
# shell-side metadata `plugins.<id>.config` (the settings-menu switch) stays in
# the core settings.json (the shell owns it). Every entry gets "_base".
#
# PERFORMANCE: per-plugin work (compat probe) is the cost, so the scan runs the
# per-directory producers in PARALLEL (xargs -P). Precedence (user wins on id
# collisions) is preserved by tagging each entry with an origin rank and
# sorting by it before the reduce. Each producer writes one JSON line < PIPE_BUF
# so parallel writes stay atomic.
#
# Env (all optional): PLUGINS_USER, PLUGINS_MANAGED, PLUGINS_SETTINGS
# ═══════════════════════════════════════════════════════════════════════════

set -u

if ! command -v jq >/dev/null 2>&1; then
    printf '[]\n'
    exit 0
fi

USER_DIR="${PLUGINS_USER:-${XDG_CONFIG_HOME:-$HOME/.config}/hypr/plugins-user}"
MANAGED_DIR="${PLUGINS_MANAGED:-${XDG_CONFIG_HOME:-$HOME/.config}/hypr/plugins}"
SETTINGS="${PLUGINS_SETTINGS:-${XDG_CONFIG_HOME:-$HOME/.config}/hypr/settings.json}"
NPROC="$(nproc 2>/dev/null || getconf _NPROCESSORS_ONLN 2>/dev/null || echo 4)"

# Core settings.json: only the shell metadata (plugins.<id>.config) is read here.
settings_obj='{}'
if [ -f "$SETTINGS" ] && jq -e . "$SETTINGS" >/dev/null 2>&1; then
    settings_obj=$(jq -c . "$SETTINGS")
fi

# Compatibility annotation (see equisdots/plugin-api).
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMPAT="$SCRIPT_DIR/plugins_compat.sh"
API_FILE="${PLUGINS_API_FILE:-$SCRIPT_DIR/../../plugin-api.json}"
HOST_API="$(jq -r '.api // empty' "$API_FILE" 2>/dev/null || true)"
SHELL_VERSION="$(jq -r '.shell // empty' "$API_FILE" 2>/dev/null || true)"

# Everything `one` needs must be exported so the xargs children inherit it.
export settings_obj COMPAT HOST_API SHELL_VERSION
export PLUGINS_API_FILE PLUGINS_HYPRLAND PLUGINS_QS PLUGINS_QT

# One manifest -> one normalized object. `enabled` resolves from the plugin's
# OWN settings file; `config` (settings-menu switch) from settings.json.
# RANK (0=user, 1=managed) is baked in so user entries win the reduce below.
one() {
    local dir="$1" pset='{}'
    [ -f "$dir/plugin.json" ] || return 0
    if [ -f "$dir/settings.json" ]; then
        pset="$(jq -c . "$dir/settings.json" 2>/dev/null || echo '{}')"
        [ -n "$pset" ] || pset='{}'
    fi
    local verdict='{"state":"ok","ok":true,"reason":""}'
    if [ -x "$COMPAT" ]; then
        local c; c=$(jq -c '.compat // empty' "$dir/plugin.json" 2>/dev/null || true)
        if [ -n "$c" ] && [ "$c" != "null" ]; then
            verdict=$(HOST_API="$HOST_API" SHELL_VERSION="$SHELL_VERSION" \
                      HYPRLAND_VERSION="${PLUGINS_HYPRLAND:-}" \
                      QUICKSHELL_VERSION="${PLUGINS_QS:-}" \
                      QT_VERSION="${PLUGINS_QT:-}" \
                      bash "$COMPAT" <<<"$c" 2>/dev/null || echo "$verdict")
        fi
    fi
    jq -c --arg base "$dir" --argjson pset "$pset" --argjson settings "$settings_obj" \
          --argjson verdict "$verdict" --argjson orank "${RANK:-1}" '
        . as $m
        | select(($m.id // "") != "")
        | ($m.scope // ("plugins." + $m.id)) as $scope
        | ($m.toggle // ($scope + ".enabled")) as $toggle
        | ($toggle | split(".")) as $path
        | (try ($pset | getpath($path)) catch null) as $val
        | (try ($settings | getpath(["plugins", $m.id, "config"])) catch null) as $cfg
        | ($m + {
            _base: $base,
            toggle: $toggle,
            enabled: (if $val == null then ($m.defaultEnabled // false) else ($val == true) end),
            config: (if $cfg == null then true else ($cfg == true) end),
            dirMismatch: (($base | split("/") | last) != $m.id),
            orank: $orank
          }) | .compat = $verdict' "$dir/plugin.json" 2>/dev/null || true
}
export -f one

# Parallel scan of one directory (a line per plugin; lines stay atomic).
scan_parallel() {
    local dir="$1"
    [ -n "$dir" ] && [ -d "$dir" ] || return 0
    find "$dir" -mindepth 1 -maxdepth 1 -type d -print0 2>/dev/null \
        | xargs -0 -r -P "$NPROC" -n1 bash -c 'one "$1"' _
}

# Id integrity (local, never silent): the user dir is scanned first and wins
# on id collisions (documented precedence), but every shadowed copy is listed
# on the winner under "shadowed" — a duplicate can only happen visibly.
{ RANK=0 scan_parallel "$USER_DIR"; RANK=1 scan_parallel "$MANAGED_DIR"; } \
    | jq -s 'sort_by(.orank // 1)
             | reduce .[] as $x (
                 [];
                 if any(.[]; .id == $x.id)
                 then map(if .id == $x.id
                          then .shadowed = ((.shadowed // []) + [{
                                 base: $x._base,
                                 dirMismatch: ($x.dirMismatch // false)
                               }])
                          else . end)
                 else . + [$x]
                 end
             )
             | map(.shadowed = (.shadowed // []))
             | map(del(.orank))
             | sort_by((.name // .id) | ascii_downcase)' \
    || printf '[]\n'
