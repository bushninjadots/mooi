import QtQuick
import Quickshell
import Quickshell.Io

// ═══════════════════════════════════════════════════════════════════════════
// SettingsStore — a reactive JSON settings store bound to ONE file (the
// traps: in-place mutation, one-edit lag, missed async initial load).
//
// Invariants:
//   - `data` is IMMUTABLE: reassigned (copy-on-write) on every commit, never
//     mutated in place → reading `data`/`get()` in a binding IS a dependency.
//   - STATE BEFORE NOTIFY: `data` is assigned BEFORE `revision` is bumped and
//     before any signal, so handlers always read post-commit state.
//   - The initial async load goes through the SAME commit path, so consumers
//     get the initial values without an extra edit.
//
// One instance per file: the global store (Settings, singleton) and one per
// plugin (its own settings.json) so plugin state never mixes with the core.
// ═══════════════════════════════════════════════════════════════════════════

Scope {
    id: settings

    readonly property string _configDir: {
        let x = Quickshell.env("XDG_CONFIG_HOME");
        return (x && x !== "") ? x : (Quickshell.env("HOME") + "/.config");
    }
    property string filePath: _configDir + "/hypr/settings.json"

    property var data: ({})
    property bool ready: false
    property string loadError: ""

    property int _rev: 0
    readonly property int revision: _rev

    signal changed(string scope, string key)
    signal scopeChanged(string scope)
    signal committed(var scopes)

    property var _pending: ({})
    property string _lastText: ""

    function _isObj(v) { return v !== null && v !== undefined && typeof v === "object" && !Array.isArray(v); }

    // deep merge; objects recurse, arrays/primitives replace
    function _merge(base, patch) {
        if (!_isObj(patch)) return patch;
        let out = _isObj(base) ? Object.assign({}, base) : {};
        for (let k in patch) out[k] = _isObj(patch[k]) ? _merge(out[k], patch[k]) : patch[k];
        return out;
    }

    function get(path, fallback) {
        let segs = String(path).split(".");
        let cur = data;
        for (let i = 0; i < segs.length; i++) {
            if (!_isObj(cur) || cur[segs[i]] === undefined) return fallback;
            cur = cur[segs[i]];
        }
        return cur;
    }
    function has(path) { return get(path, undefined) !== undefined; }
    function section(scope) { return _isObj(data[scope]) ? data[scope] : {}; }

    function set(path, value) {
        let segs = String(path).split(".");
        let patch = {}, cur = patch;
        for (let i = 0; i < segs.length - 1; i++) { cur[segs[i]] = {}; cur = cur[segs[i]]; }
        cur[segs[segs.length - 1]] = value;
        _commit(patch, true);
    }
    function setMany(patch, immediate) { _commit(patch || {}, true); if (immediate) flush(); }

    function _commit(patch, write) {
        data = _merge(data, patch);   // 1. state first
        _rev = _rev + 1;              // 2. scalar dependency, after assignment
        for (let s in patch) {        // 3. then notify
            scopeChanged(s);
            committed([s]);
            for (let k in patch[s]) changed(s, k);
        }
        if (write) { _pending = _merge(_pending, patch); writeTimer.restart(); }
    }

    function applyExternal(text) {
        if (text === _lastText) return;
        _lastText = text;
        let parsed;
        try { parsed = JSON.parse(text); } catch (e) { loadError = String(e); return; }
        if (!_isObj(parsed)) return;
        let touched = {};
        for (let k in parsed) if (JSON.stringify(parsed[k]) !== JSON.stringify(data[k])) touched[k] = true;
        data = parsed;
        _rev = _rev + 1;
        for (let s in touched) scopeChanged(s);
        if (!ready) ready = true;
    }

    Timer { id: writeTimer; interval: 200; onTriggered: settings.flush() }
    function flush() {
        if (!_isObj(_pending) || Object.keys(_pending).length === 0) return;
        let patch = _pending; _pending = ({});
        let json = JSON.stringify(patch).replace(/'/g, "'\\''");
        let cmd = "mkdir -p \"$(dirname '" + filePath + "')\"; " +
                  "[ -f '" + filePath + "' ] || echo '{}' > '" + filePath + "'; " +
                  "tmp=$(mktemp '" + filePath + "'.tmp.XXXXXX) && " +
                  "jq '. * " + json + "' '" + filePath + "' > \"$tmp\" && mv \"$tmp\" '" + filePath + "'";
        Quickshell.execDetached(["bash", "-c", cmd]);
    }

    Component.onCompleted: read.running = true

    Process {
        id: read
        command: ["bash", "-c", "cat '" + settings.filePath + "' 2>/dev/null || echo '{}'"]
        stdout: StdioCollector {
            onStreamFinished: {
                settings.applyExternal(this.text.trim() || "{}");
                if (!settings.ready) settings.ready = true;
            }
        }
    }

    Process {
        id: watch
        command: ["bash", "-c",
            "f='" + settings.filePath + "'; while [ ! -f \"$f\" ]; do sleep 1; done; " +
            "inotifywait -qq -e modify,close_write,create,move \"$f\""]
        running: true
        stdout: StdioCollector {
            onStreamFinished: { watch.running = false; settings.reread(); watch.running = true; }
        }
    }
    Process {
        id: reread
        command: ["bash", "-c", "cat '" + settings.filePath + "' 2>/dev/null || echo '{}'"]
        stdout: StdioCollector { onStreamFinished: settings.applyExternal(this.text.trim() || "{}") }
    }
    function reread() { reread.running = false; reread.running = true; }
}
