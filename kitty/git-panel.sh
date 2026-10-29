#!/usr/bin/env bash
# mooi's terminal side panel, the git half (kitty/side.py opens it): the repository the main pane is in,
# redrawn when it changes — branch and upstream, ahead and behind, what is staged, changed and new,
# the last commits and the stashes. It follows the main pane's folder: MOOI_SIDE_PID is that pane's
# shell, and its cwd is read each tick, so a `cd` there moves the panel too. Read only: it never
# fetches, so it asks nothing of the network and changes nothing.
set -u

R=$'\e[0m' B=$'\e[1m' D=$'\e[2m'
# the terminal's own palette (mooi themes kitty from the wallpaper), so the panel wears the theme
RED=$'\e[31m' GRN=$'\e[32m' YLW=$'\e[33m' BLU=$'\e[34m' MAG=$'\e[35m' CYN=$'\e[36m'

where() {
    local d
    [ -n "${MOOI_SIDE_PID:-}" ] && d=$(readlink "/proc/$MOOI_SIDE_PID/cwd" 2>/dev/null) && { printf '%s' "$d"; return; }
    pwd
}

# cut to the panel's width, counting only what shows (not the colour codes)
fit() {
    local w=$1 line plain
    while IFS= read -r line; do
        plain=$(printf '%s' "$line" | sed 's/\x1b\[[0-9;]*m//g')
        if [ "${#plain}" -le "$w" ]; then printf '%s%s\n' "$line" "$R"
        else printf '%s%s…\n' "${plain:0:$((w - 1))}" "$R"; fi
    done
}

rule() { # title width
    local t=" $1 " w=$2 n
    n=$((w - ${#t} - 2)); [ "$n" -lt 1 ] && n=1
    printf '%s──%s%s%s%s\n' "$D" "$R$B$CYN" "$t" "$R$D" "$(printf '─%.0s' $(seq 1 "$n"))"
}

draw() {
    local dir cols rows top
    dir=$(where); cols=$(tput cols 2>/dev/null || echo 40); rows=$(tput lines 2>/dev/null || echo 24)
    if ! top=$(git -C "$dir" rev-parse --show-toplevel 2>/dev/null); then
        printf '%s %sno git here%s\n%s%s%s\n' "$YLW" "$B" "$R" "$D" "${dir/#$HOME/\~}" "$R"
        return
    fi

    local st head="" up="" ahead=0 behind=0 staged=() changed=() fresh=() clash=()
    st=$(git -C "$top" status --porcelain=v2 --branch 2>/dev/null)
    while IFS= read -r l; do
        case $l in
            '# branch.head '*) head=${l#\# branch.head } ;;
            '# branch.upstream '*) up=${l#\# branch.upstream } ;;
            '# branch.ab '*) set -- ${l#\# branch.ab }; ahead=${1#+}; behind=${2#-} ;;
            '1 '*|'2 '*)
                local xy=${l:2:2} path
                path=$(printf '%s' "$l" | cut -d' ' -f9-); path=${path%%$'\t'*}
                [ "${xy:0:1}" != . ] && staged+=("${xy:0:1} $path")
                [ "${xy:1:1}" != . ] && changed+=("${xy:1:1} $path") ;;
            'u '*) clash+=("$(printf '%s' "$l" | cut -d' ' -f11-)") ;;
            '? '*) fresh+=("${l#\? }") ;;
        esac
    done <<< "$st"
    [ "$head" = "(detached)" ] && head="detached @ $(git -C "$top" rev-parse --short HEAD 2>/dev/null)"

    {
        printf '%s\uf1d3 %s%s%s\n' "$MAG" "$B" "$(basename "$top")" "$R"
        local sync=""
        if [ -n "$up" ]; then
            [ "$ahead" -gt 0 ] && sync+=" ${GRN}↑$ahead${R}"
            [ "$behind" -gt 0 ] && sync+=" ${RED}↓$behind${R}"
            [ -z "$sync" ] && sync=" ${D}in step${R}"
            printf '%s\ue725 %s%s%s%s %s→ %s%s\n' "$BLU" "$B" "$head" "$R" "$sync" "$D" "$up" "$R"
        else
            printf '%s\ue725 %s%s%s %sno upstream%s\n' "$BLU" "$B" "$head" "$R" "$YLW" "$R"
        fi
        local clean=1
        if [ ${#clash[@]} -gt 0 ]; then clean=0; rule "conflicts ${#clash[@]}" "$cols"; printf "  ${RED}!${R} %s\n" "${clash[@]:0:6}"; fi
        if [ ${#staged[@]} -gt 0 ]; then clean=0; rule "staged ${#staged[@]}" "$cols"; for s in "${staged[@]:0:8}"; do printf '  %s%s%s %s\n' "$GRN" "${s:0:1}" "$R" "${s:2}"; done; fi
        if [ ${#changed[@]} -gt 0 ]; then clean=0; rule "changed ${#changed[@]}" "$cols"; for s in "${changed[@]:0:8}"; do printf '  %s%s%s %s\n' "$YLW" "${s:0:1}" "$R" "${s:2}"; done; fi
        if [ ${#fresh[@]} -gt 0 ]; then clean=0; rule "new ${#fresh[@]}" "$cols"; for s in "${fresh[@]:0:5}"; do printf '  %s?%s %s\n' "$D" "$R" "$s"; done; fi
        [ "$clean" = 1 ] && printf '%s✓ clean%s\n' "$GRN" "$R"
        rule "recent" "$cols"
        git -C "$top" log -n 8 --format="%h%x09%s%x09%cr" 2>/dev/null | while IFS=$'\t' read -r h s t; do
            t=${t/ ago/}; t=${t/ minutes/m}; t=${t/ minute/m}; t=${t/ hours/h}; t=${t/ hour/h}; t=${t/ days/d}; t=${t/ day/d}; t=${t/ weeks/w}; t=${t/ months/mo}; t=${t/ seconds/s}
            printf '  %s%s%s %s%4s%s %s\n' "$YLW" "$h" "$R" "$D" "$t" "$R" "$s"
        done
        local n; n=$(git -C "$top" stash list 2>/dev/null | wc -l)
        [ "$n" -gt 0 ] && { rule "stashes $n" "$cols"; git -C "$top" stash list -n 3 --format='  %gd %s' 2>/dev/null; }
    } | fit "$cols" | head -n "$((rows - 1))"
}

printf '\e[?25l'                      # no cursor
trap 'printf "\e[?25h"; exit 0' INT TERM HUP
trap 'last=""' WINCH                  # resized: draw again
last=""
while :; do
    now=$(draw 2>/dev/null)
    if [ "$now" != "$last" ]; then printf '\e[H\e[2J%s' "$now"; last=$now; fi
    sleep 2
done
