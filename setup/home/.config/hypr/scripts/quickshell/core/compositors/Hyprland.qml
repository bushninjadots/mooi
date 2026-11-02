// ═══════════════════════════════════════════════════════════════════════════
// shell · core/compositors — Hyprland backend
//
// Hyprland implementation of the Compositor surface. It keeps the exact
// commands and scripts used before the port (workspaces.sh, kb_fetch.sh,
// hyprctl) so behaviour is unchanged.
// ═══════════════════════════════════════════════════════════════════════════
import QtQuick
import Quickshell

QtObject {
    id: backend

    readonly property var workspacesCommand: ["bash", "-c", "~/.config/hypr/scripts/workspaces.sh"]
    readonly property var keyboardCommand: ["bash", "-c", "~/.config/hypr/scripts/quickshell/core/scripts/watchers/kb_fetch.sh"]

    readonly property var focusCommand: ["bash", "-c",
        "hyprctl activewindow -j 2>/dev/null | jq -r 'if (.class != null and .class != \"\" and .address != null and .address != \"\") then (.class + \"\\n\" + .title) else empty end' 2>/dev/null"]

    // Spec → Lua value. Solid borders are 0xAARRGGBB numbers; gradients are
    // the table the 0.56 API expects: { colors = { 0x..., 0x... }, angle = N }.
    function borderLua(spec) {
        const alpha = (spec && spec.alpha) ? String(spec.alpha) : "ee";
        const hex = String((spec && spec.hex) || "#ffffff").replace("#", "");
        const first = "0x" + alpha + hex;
        const second = (spec && spec.second) ? String(spec.second).replace("#", "") : "";
        if (/^[0-9a-fA-F]{6}$/.test(second)) {
            const angle = Math.round(Number((spec && spec.angle) || 0));
            return "{ colors = { " + first + ", 0x" + alpha + second + " }, angle = " + angle + " }";
        }
        return first;
    }

    // Push the active/inactive window border specs live. Spec: { hex, alpha,
    // second, angle } (Colors.borderSpec).
    function setWindowBorders(activeSpec, inactiveSpec) {
        const lua = 'hl.config({ general = { col = { active_border = ' + borderLua(activeSpec)
                  + ', inactive_border = ' + borderLua(inactiveSpec) + ' } } })';
        Quickshell.execDetached(["bash", "-c", "hyprctl eval '" + lua + "' 2>/dev/null"]);
    }

    function switchWorkspace(name) {
        Quickshell.execDetached(["bash", "-c", "~/.config/hypr/scripts/qs_manager.sh " + name]);
    }

    function cycleKeyboardLayout() {
        Quickshell.execDetached(["hyprctl", "switchxkblayout", "main", "next"]);
    }
}
