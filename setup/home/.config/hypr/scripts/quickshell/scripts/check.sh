#!/usr/bin/env bash
# Local checks for the shell repo (no CI):
#   - QML syntax/type lint with qmllint (Qt declarative tools).
#   - JavaScript syntax for the plain .js modules with node --check (the QML
#     `.pragma library` directive is stripped first).
#
# Usage: scripts/check.sh
set -u
cd "$(dirname "$0")/.." || exit 1

QT_QML_DIR="${QT_QML_DIR:-/usr/lib/qt6/qml}"
# qmllint exits non-zero without a message on this file (upstream limitation
# with the current Quickshell qmltypes); the shell itself loads it at runtime.
QMLLINT_ALLOWLIST=("./ui/Main.qml")

fail=0

if ! command -v qmllint >/dev/null 2>&1; then
    echo "error: qmllint not found (install the Qt declarative development tools)" >&2
    exit 2
fi

allowed() {
    local f
    for f in "${QMLLINT_ALLOWLIST[@]}"; do
        [ "$1" = "$f" ] && return 0
    done
    return 1
}

qml_total=0
qml_checked=0
while IFS= read -r f; do
    qml_total=$((qml_total + 1))
    allowed "$f" && continue
    qml_checked=$((qml_checked + 1))
    if ! qmllint -I "$QT_QML_DIR" "$f" >/dev/null 2>&1; then
        echo "qmllint FAIL: $f"
        fail=1
    fi
done < <(find . -name '*.qml' -not -path './.git/*' | sort)
echo "qmllint: $qml_checked/$qml_total QML files checked (allowlist: ${QMLLINT_ALLOWLIST[*]})"

if command -v node >/dev/null 2>&1; then
    # node --check needs a .js extension (mktemp default has none).
    tmp="$(mktemp /tmp/qs-shell-check-XXXXXX.js)"
    while IFS= read -r f; do
        grep -v '^[[:space:]]*\.pragma' "$f" > "$tmp"
        if ! node --check "$tmp" >/dev/null 2>&1; then
            echo "node --check FAIL: $f"
            fail=1
        fi
    done < <(find . -name '*.js' -not -path './.git/*' | sort)
    rm -f "$tmp"
    echo "node --check: JS modules checked"

    # Semantic smoke test: node --check only validates syntax, so a key
    # swallowed by a trailing `//` comment (valid JS) would silently disable
    # a widget. Assert the core widget names resolve to a layout.
    if node -e '
        const fs = require("fs"), vm = require("vm");
        const src = fs.readFileSync("core/WindowRegistry.js", "utf8")
            .replace(/^[ \t]*\.pragma[^\n]*\n/, "");
        const ctx = {}; vm.createContext(ctx); vm.runInContext(src, ctx);
        const required = ["calendar", "bar-editor", "network", "idle",
                          "applauncher", "clipboard", "wallpaper"];
        const missing = required.filter(n => !ctx.getLayout(n, 0, 0, 1920, 1080, 1));
        if (missing.length) {
            console.error("WindowRegistry: missing layouts: " + missing.join(", "));
            process.exit(1);
        }
    '; then
        echo "node semantic: WindowRegistry widget layouts present"
    else
        echo "node semantic FAIL: WindowRegistry widget layouts missing"
        fail=1
    fi
else
    echo "note: node not found, skipping the JS syntax check" >&2
fi

if [ "$fail" -eq 0 ]; then
    echo "shell: checks OK"
fi
exit "$fail"
