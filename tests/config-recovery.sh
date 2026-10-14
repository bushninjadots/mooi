#!/bin/sh
# Broken and partly-wrong settings must never stop mooi from starting.
# Backs up the real settings.json and puts it back afterwards.
set -u
root=$(cd "$(dirname "$0")/.." && pwd)
dir="${XDG_DATA_HOME:-$HOME/.local/share}/pleamar/mooi"
file="$dir/settings.json"
good="$dir/settings.known-good.json"
backup=$(mktemp); backup_good=$(mktemp); had=false; had_good=false
[ -e "$file" ] && { cp "$file" "$backup"; had=true; }
[ -e "$good" ] && { cp "$good" "$backup_good"; had_good=true; }
restore() {
    if $had; then cp "$backup" "$file"; else rm -f "$file"; fi
    if $had_good; then cp "$backup_good" "$good"; else rm -f "$good"; fi
    rm -f "$backup" "$backup_good"
}
trap restore EXIT
fail=0; n=0
say() { pleamar --say mooi "$@" 2>&1 | tail -1; }
check() { n=$((n + 1)); got=$(say "get $1"); if [ "$got" = "$2" ]; then echo "  ok    $3"; else echo "  FAIL  $3 ($1 = '$got', expected '$2')"; fail=$((fail + 1)); fi; }
run_with() { # settings-text
    mkdir -p "$dir"; printf '%s' "$1" > "$file"
    pleamar --scene "$root/shell/mooi.plm" --no-hud --stall 0 --seconds 8 >/dev/null 2>&1 &
    for _ in $(seq 1 20); do sleep 0.3; say "get open" >/dev/null 2>&1 && say "get open" | grep -q none && break; done
    sleep 0.4
}

echo "a clean file is applied and remembered as known-good"
run_with '{ "version": 1, "spine": { "max_workspaces": 7, "clock": false } }'
check ws_max 7 "max_workspaces = 7 applied"; check show_clock false "clock hidden"; check cfg_error false "no error shown"
say quit >/dev/null; sleep 1

echo "broken JSON falls back to the known-good file"
run_with '{ "spine": { "max_workspaces": '
check open none "the shell still starts"; check cfg_error true "the error dot is shown"
check ws_max 7 "known-good value kept (7)"
say quit >/dev/null; sleep 1

echo "a wrong value falls back for that field only"
run_with '{ "spine": { "max_workspaces": 99, "clock": false } }'
check ws_max 10 "out-of-range → default 10"; check show_clock false "the valid field is still applied"; check cfg_error true "the error dot is shown"
say quit >/dev/null; sleep 1

echo "safe mode ignores the file"
mkdir -p "$dir"; printf '%s' '{ "spine": { "clock": false } }' > "$file"
MOOI_SAFE=1 pleamar --scene "$root/shell/mooi.plm" --no-hud --stall 0 --seconds 8 >/dev/null 2>&1 &
for _ in $(seq 1 20); do sleep 0.3; say "get open" >/dev/null 2>&1 && break; done; sleep 0.4
check show_clock true "defaults used under MOOI_SAFE=1"
say quit >/dev/null; sleep 1

echo; echo "$n checks, $fail failed"
[ "$fail" -eq 0 ]
