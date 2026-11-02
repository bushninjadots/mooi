#!/bin/sh
# Static contract checks for the two action-button components used by Settings and Lumen.
# This deliberately checks semantic behaviour, not geometry or palette: the two surfaces
# must remain visually distinct.
set -eu
root=$(cd "$(dirname "$0")/.." && pwd)
ferro="$root/shell/ui/ferrolume.plm"
lumen="$root/shell/ui/lumen.plm"
settings="$root/shell/mooi-settings.plm"
wallpaper="$root/shell/mooi-wallpaper.plm"
n=0

has() {
    file=$1
    needle=$2
    what=$3
    n=$((n + 1))
    if grep -Fq "$needle" "$file"; then
        printf '  ok    %s\n' "$what"
    else
        printf '  FAIL  %s\n' "$what" >&2
        exit 1
    fi
}

uses() {
    file=$1
    needle=$2
    minimum=$3
    what=$4
    count=$(grep -Fc "$needle" "$file" || true)
    n=$((n + 1))
    if [ "$count" -ge "$minimum" ]; then
        printf '  ok    %s (%s uses)\n' "$what" "$count"
    else
        printf '  FAIL  %s (expected at least %s, found %s)\n' "$what" "$minimum" "$count" >&2
        exit 1
    fi
}

echo "mooi action-button contract"
# Ferrolume / Settings: stable button role, meaningful label, disabled metadata and one
# explicit event emission. The active flag belongs on the hit zone, not just the drawing.
has "$ferro" 'component SButton(' "Ferrolume exposes SButton"
has "$ferro" 'role: button; label: label; active: en' "Ferrolume hit target declares role, label and enabled state"
has "$ferro" 'on press hit { emit press(n) }' "Ferrolume emits the supplied action payload"
uses "$settings" 'SButton(' 2 "Settings consumes the shared Ferrolume button"

# Lumen / Wallpaper Studio keeps its own shape, tone and sizing while meeting the same
# interaction contract.
has "$lumen" 'component Button(' "Lumen exposes its own Button treatment"
has "$lumen" 'role: button; label: label; active: en' "Lumen hit target declares role, label and enabled state"
has "$lumen" 'on press hit { emit press(n) }' "Lumen emits the supplied action payload"
uses "$wallpaper" 'Button(' 2 "Wallpaper Studio consumes Lumen buttons"

printf '  %s checks passed\n' "$n"
