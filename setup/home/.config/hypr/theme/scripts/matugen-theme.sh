#!/bin/bash
# Recolour the desktop from the current wallpaper with matugen, in the
# system's light/dark mode. qs-wallpaperpicker does the same when a wallpaper
# is set; this runs it again when the mode changes (system-theme.sh switch).

set -euo pipefail

readonly SCRIPTS_DIR="${HOME}/.config/hypr/theme/scripts"
# A still of the wallpaper (a video's frame), kept by `mooi wall apply` (mooi D145).
readonly STILL="${HOME}/.cache/current_wallpaper"

command -v matugen >/dev/null || { echo "matugen is not installed" >&2; exit 1; }
[[ -e "${STILL}" ]] || { echo "No wallpaper set yet (${STILL} missing)" >&2; exit 0; }

mode="$("${SCRIPTS_DIR}/system-theme.sh" get)"
# The same extraction as the picker and mooi (audit 2026-10-31), so a day/night switch does not
# recolour the apps with a different scheme from the one they were set with.
if [[ -x "${SCRIPTS_DIR}/matugen-extract" ]]; then
    args=$("${SCRIPTS_DIR}/matugen-extract")
else
    args="--source-color-index 0"
fi
# shellcheck disable=SC2086
matugen image "$(readlink -f "${STILL}")" ${args} -m "${mode}"
