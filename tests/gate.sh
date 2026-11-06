#!/bin/sh
# The gate CI can run: everything except the Pleamar scene compile and the live suites.
# `bin/mooi check` runs this, then compiles every scene itself, so local and CI mean the same
# thing (audit 2026-11-06, G12). `--no-pleamar` is accepted (and is the only mode here) so CI's
# invocation says plainly what it is not doing.
set -eu
root=$(cd "$(dirname "$0")/.." && pwd)
cd "$root"

echo "launcher and test scripts"
bash -n bin/mooi    # the launcher is bash ([[ =~ ]], process substitution); dash rejects it
for t in tests/*.sh setup/*.sh; do sh -n "$t"; done
if command -v shellcheck >/dev/null 2>&1; then
    shellcheck -S error -f gcc bin/mooi tests/*.sh setup/*.sh || exit 1
else
    echo "shellcheck: not installed; syntax checked with sh -n only"
fi

echo "logic files parse with Lua 5.4"
for f in shell/*.luau shell/lib/*.luau shell/player/*.luau shell/bmo/*.luau; do
    F="$f" lua5.4 -e 'local _, e = loadfile(os.getenv("F")); if e then io.stderr:write(e, "\n"); os.exit(1) end' || exit 1
done

echo "settings.json has one write policy"
# A write is `sys.call("files.write", FILE, …)` where FILE is "settings.json", or the name spelled
# out. Every such call outside lib/settingsfile must say why on its line (`settings-write: ok`);
# the old pattern here matched neither spelling and could never fail (fourth pass, L7).
bad=""
for f in $(grep -RIl --include='*.luau' -e 'FILE[^=]*= *"settings\.json"' -e '"settings\.json"' shell); do
    case "$f" in shell/lib/settingsfile.luau) continue ;; esac
    if grep -Eq 'FILE[^=]*= *"settings\.json"' "$f"; then pat='"files\.write", *(FILE|"settings\.json")'
    else pat='"files\.write", *"settings\.json"'; fi
    hits=$(grep -En "$pat" "$f" | grep -v 'settings-write: ok' || true)
    [ -z "$hits" ] || bad="$bad$(printf '%s\n' "$hits" | sed "s|^|$f:|")
"
done
if [ -n "$bad" ]; then
    echo "a scene writes settings.json whole; use lib/settingsfile.save (or mark why: settings-write: ok):" >&2
    printf '%s' "$bad" >&2
    exit 1
fi

echo "unit suites"
lua5.4 shell/bmo/test.lua || exit 1
lua5.4 tests/unit/run.lua || exit 1

echo "suites that need no compositor"
sh tests/components.sh
sh tests/apps-sync.sh
sh tests/theme-pack.sh
sh tests/kitty-shaders.sh

echo "test suites and docs agree"
for t in tests/*.sh; do
    name="tests/$(basename "$t")"
    if ! grep -Fq "$name" docs/TESTING.md; then
        echo "docs/TESTING.md does not name $name" >&2
        exit 1
    fi
done
for name in $(grep -o 'tests/[A-Za-z0-9_-]*\.sh' docs/TESTING.md | sort -u); do
    if [ ! -f "$name" ]; then
        echo "docs/TESTING.md names $name, which does not exist" >&2
        exit 1
    fi
done

echo "gate: ok"
