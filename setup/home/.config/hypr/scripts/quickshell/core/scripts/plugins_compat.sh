#!/usr/bin/env bash
# plugins_compat.sh — evaluate a plugin's `compat` requirements against the
# running host and print a verdict as JSON on stdout.
#
# Usage:
#   plugins_compat.sh <<< '<compat-json>'
#
# Environment (all optional; empty = "cannot verify"):
#   HOST_API            host API version            (plugin-api.json → api)
#   SHELL_VERSION       shell release version        (plugin-api.json → shell)
#   HYPRLAND_VERSION    hyprland binary version
#   QUICKSHELL_VERSION  quickshell version
#   QT_VERSION          Qt version
#
# Verdict:
#   {"state":"ok|warn|incompat","ok":bool,"reason":str,
#    "requires":{...},"seen":{...}}
#
# Rules:
#   - A declared constraint that is satisfied          -> contributes nothing
#   - A declared constraint that is violated           -> state=incompat
#   - A constraint we cannot verify (no version)        -> state=warn
#   - An unparsable constraint string                  -> state=warn (fail open)
#   - No `compat` at all                               -> state=ok
#
# Range syntax (space/comma = AND):
#   >=1.0  >1.0  <=2.0  <2.0  =1.2.3  1.2.3   ^1.2.0   ~1.2.0
# `^` = same major, >= v.  `~` = same major.minor, >= v.
set -euo pipefail

compat="$(cat)"

if ! command -v jq >/dev/null 2>&1; then
    printf '%s\n' '{"state":"warn","ok":true,"reason":"jq unavailable","requires":{},"seen":{}}'
    exit 0
fi

HOST_API="${HOST_API:-}"
SHELL_VERSION="${SHELL_VERSION:-}"
HYPRLAND_VERSION="${HYPRLAND_VERSION:-}"
QUICKSHELL_VERSION="${QUICKSHELL_VERSION:-}"
QT_VERSION="${QT_VERSION:-}"

# ver_gt A B -> prints 1 if A > B else 0 (GNU sort -V semantics)
ver_gt() { [ "$(printf '%s\n%s\n' "$1" "$2" | sort -V | tail -1)" = "$1" ] && echo 1 || echo 0; }
ver_eq() { [ "$1" = "$2" ] && echo 1 || echo 0; }

# satisfies VER RANGE -> rc 0 satisfied, 1 violated, 2 unparsable
satisfies() {
    local ver="$1" range="$2"
    [ -z "$range" ] && return 0
    range="${range//,/ }"
    local part op v
    for part in $range; do
        case "$part" in
            ">="*) op=">="; v="${part#>=}";;
            "<="*) op="<="; v="${part#<=}";;
            ">"*)  op=">";  v="${part#>}";;
            "<"*)  op="<";  v="${part#<}";;
            "="*)  op="=";  v="${part#=}";;
            "^"*)  op="^";  v="${part#^}";;
            "~"*)  op="~";  v="${part#\~}";;
            *)     op="=";  v="$part";;
        esac
        v="${v// /}"
        [ -z "$v" ] && return 2
        [[ "$v" =~ ^[0-9]+([.][0-9]+)*$ ]] || return 2
        local gt eq; gt="$(ver_gt "$ver" "$v")"; eq="$(ver_eq "$ver" "$v")"
        case "$op" in
            ">=") [ "$gt" = 1 ] || [ "$eq" = 1 ] || return 1;;
            "<=") [ "$gt" = 0 ] || [ "$eq" = 1 ] || return 1;;
            ">")  [ "$gt" = 1 ] || return 1;;
            "<")  [ "$gt" = 0 ] && [ "$eq" = 0 ] || return 1;;
            "=")  [ "$eq" = 1 ] || return 1;;
            "^")  [ "${ver%%.*}" = "${v%%.*}" ] || return 1
                  [ "$gt" = 1 ] || [ "$eq" = 1 ] || return 1;;
            "~")  [ "${ver%.*}" = "${v%.*}" ] || return 1
                  [ "$gt" = 1 ] || [ "$eq" = 1 ] || return 1;;
        esac
    done
    return 0
}

declare -A SEEN=(
    [host]="$HOST_API"
    [shell]="$SHELL_VERSION"
    [hyprland]="$HYPRLAND_VERSION"
    [quickshell]="$QUICKSHELL_VERSION"
    [qt]="$QT_VERSION"
)

state="ok"
reason=""

for key in host shell hyprland quickshell qt; do
    range="$(jq -r --arg k "$key" '.[$k] // empty' <<<"$compat")"
    [ -z "$range" ] && continue
    ver="${SEEN[$key]}"
    if [ -z "$ver" ]; then
        [ "$state" = incompat ] || state="warn"
        [ -n "$reason" ] || reason="cannot verify '$key' (version unknown)"
        continue
    fi
    if satisfies "$ver" "$range"; then
        :
    else
        rc=$?
        if [ "$rc" = 2 ]; then
            [ "$state" = incompat ] || state="warn"
            reason="unparsable constraint for '$key': '$range'"
        else
            state="incompat"
            reason="requires $key $range (this host provides $ver)"
        fi
    fi
done

ok=true; [ "$state" = incompat ] && ok=false

jq -n \
    --arg state "$state" \
    --argjson ok "$ok" \
    --arg reason "$reason" \
    --argjson compat "$compat" \
    --arg host "$HOST_API" --arg shell "$SHELL_VERSION" \
    --arg hyprland "$HYPRLAND_VERSION" --arg quickshell "$QUICKSHELL_VERSION" --arg qt "$QT_VERSION" \
    '{state:$state, ok:$ok, reason:$reason, requires:$compat,
      seen:{host:$host, shell:$shell, hyprland:$hyprland, quickshell:$quickshell, qt:$qt}}'
