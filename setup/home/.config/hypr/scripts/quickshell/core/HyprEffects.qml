pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// ═══════════════════════════════════════════════════════════════════════════
// HyprEffects — shared state for the window-effect knobs.
//
// Single source for the BarEditor Hyprland tab and the Window Controls
// widget (SUPER+SHIFT+B). Talks to core/scripts/hypr-effects.sh:
//   · refresh()  reads the live values (hyprctl -j, robust parsing: gaps
//                arrive as "css gap data", not "int:").
//   · set(k,v)   applies ONLY that knob (JSON state + .lua + live
//                `hyprctl eval`, no reload) with drag debounce.
//
// The old flow had one reader per UI (both with parsing bugs) and rewrote all
// 12 knobs together: one change clobbered the rest. Now there is a single
// reader and a single partial writer.
// ═══════════════════════════════════════════════════════════════════════════

Item {
    id: root

    readonly property string scriptPath: Quickshell.env("HOME") + "/.config/hypr/scripts/quickshell/core/scripts/hypr-effects.sh"

    // Same keys as window-effects.json (see SPECS in the script).
    property var values: ({
        active_opacity: 0.85,
        inactive_opacity: 0.80,
        rounding: 20,
        blur_size: 8,
        blur_passes: 3,
        gaps_in: 16,
        gaps_out: 25,
        border_size: 2,
        shadow_range: 35,
        shadow_render_power: 5,
        shadow_offset_x: 0,
        shadow_offset_y: 10
    })

    function get(key) { return root.values[key]; }

    // Re-read the live values (when each UI opens and on demand).
    function refresh() { reader.running = true; }

    Process {
        id: reader
        command: ["bash", root.scriptPath, "read"]
        stdout: StdioCollector {
            onStreamFinished: {
                if (!this.text) return;
                let next = {};
                for (let k in root.values) next[k] = root.values[k];
                let lines = this.text.trim().split("\n");
                for (let i = 0; i < lines.length; i++) {
                    let eq = lines[i].indexOf("=");
                    if (eq < 0) continue;
                    let key = lines[i].slice(0, eq).trim();
                    let num = parseFloat(lines[i].slice(eq + 1).trim());
                    if (key in next && !isNaN(num)) next[key] = num;
                }
                root.values = next;
            }
        }
    }

    // Preview with drag debounce: touched keys accumulate and 200 ms later a
    // single `preview key=val ...` is sent — JSON + live eval, NO Lua writes.
    // Rewriting the Lua overrides makes Hyprland auto-reload its config (the
    // visible "all windows restart" while dragging), so they are only written
    // on persist().
    property var _pending: ({})
    property var _changed: ({})
    Timer {
        id: flushTimer
        interval: 200
        onTriggered: root.flush()
    }
    function set(key, v) {
        if (typeof v !== "number" || isNaN(v)) return;
        if (root.values[key] === v) return;
        let next = {};
        for (let k in root.values) next[k] = root.values[k];
        next[key] = v;
        root.values = next;
        root._pending[key] = v;
        root._changed[key] = v;
        flushTimer.restart();
    }
    // Apply pending previews now (live, no reload).
    function flush() {
        let args = [];
        for (let k in root._pending) args.push(k + "=" + root._pending[k]);
        root._pending = {};
        if (args.length === 0) return;
        Quickshell.execDetached(["bash", root.scriptPath, "preview"].concat(args));
    }
    // Write the Lua overrides once (called when the UI closes / Save): this
    // triggers a single Hyprland auto-reload, never one per knob movement.
    function persist() {
        let args = [];
        for (let k in root._changed) args.push(k + "=" + root._changed[k]);
        root._pending = {};
        root._changed = {};
        if (args.length === 0) return;
        Quickshell.execDetached(["bash", root.scriptPath, "apply"].concat(args));
    }

    // Reset defaults: effects only (gaps and border untouched, same as the
    // original reset of both UIs).
    function resetEffects() {
        root.set("active_opacity", 0.85);
        root.set("inactive_opacity", 0.80);
        root.set("rounding", 20);
        root.set("blur_size", 8);
        root.set("blur_passes", 3);
        root.set("shadow_range", 35);
        root.set("shadow_render_power", 5);
        root.set("shadow_offset_x", 0);
        root.set("shadow_offset_y", 10);
        root.flush();
    }

    Component.onCompleted: root.refresh()
}
