#!/usr/bin/env bash
# launched by `map alt+g` — toggles the gh-sidecar window in the current tab:
#   no sidecar here        -> become the panel (fit split, run the TUI)
#   sidecar exists, idle    -> focus it
#   sidecar exists, focused -> close it
set -u
. "$(dirname -- "${BASH_SOURCE[0]}")/lib.sh"

# no remote control available (started outside kitty) -> plain TUI fallback
if ! kitty @ ls >/dev/null 2>&1; then
  exec "$SC_DIR/sidecar"
fi

me=$(sc_self)

other=$(sc_sidecar_other)
if [ -n "$other" ]; then
  id=${other%% *}; state=${other##* }
  if [ "$state" = true ]; then
    # panel is focused: toggle off
    kitty @ close-window --match "id:$id" >/dev/null 2>&1 || true
  else
    kitty @ focus-window --match "id:$id" >/dev/null 2>&1 || true
  fi
  exit 0
fi

# become the panel
kitty @ set-window-title --match "id:$me" gh-sidecar >/dev/null 2>&1 || true
kitty @ focus-window --match "id:$me" >/dev/null 2>&1 || true

# guard against alt+g being mashed out: if another panel appeared, hand over
sleep 0.15
other=$(sc_sidecar_other)
if [ -n "$other" ]; then
  kitty @ set-window-title --match "id:$me" ' ' >/dev/null 2>&1 || true
  kitty @ focus-window --match "id:${other%% *}" >/dev/null 2>&1 || true
  exit 0
fi

# fit the split: aim for SIDECAR_PCT percent for this (right) pane
fit() {
  local main pct share diff tries=0
  main=$(sc_main_window_id) || return 0
  [ -n "$main" ] || return 0
  pct=$SIDECAR_PCT
  # tall/fat layouts: bias = percentage of the left (main) column
  kitty @ action --match "id:$main" layout_action bias $((100 - pct)) >/dev/null 2>&1 || true
  while [ "$tries" -lt 3 ]; do
    sleep 0.2
    share=$(kitty @ ls 2>/dev/null | jq -r --argjson me "$me" '
      first(
        .[] as $ow | $ow.tabs[] as $tab
        | select(any($tab.windows[]; .id == $me))
        | ($tab.windows | map(.width) | add) as $tot
        | ($tab.windows[] | select(.id == $me) | .width)
        | (. / $tot * 100 | round)
      ) // empty')
    case $share in ''|*[!0-9]*) return 0 ;; esac
    diff=$((pct - share))
    [ "${diff#-}" -le 4 ] && return 0
    if [ "$diff" -gt 0 ]; then
      kitty @ action --match "id:$main" resize_window narrower "$diff" >/dev/null 2>&1 || return 0
    else
      kitty @ action --match "id:$main" resize_window wider "$((-diff))" >/dev/null 2>&1 || return 0
    fi
    tries=$((tries + 1))
  done
}
fit

exec "$SC_DIR/sidecar"
