import QtQuick
import Quickshell
import "."

// ═══════════════════════════════════════════════════════════════════════════
// SettingsScope — scoped accessor over a SettingsStore.
//
//   SettingsScope { store: myStore; scope: "mascots" }
//   scope.section.x    // reactive read
//   scope.set("x", 1)  // scoped write
//
// `store` defaults to the global `Settings` singleton; a plugin passes its own
// per-plugin SettingsStore so its state lives in its own file.
// ═══════════════════════════════════════════════════════════════════════════

Scope {
    id: scope

    required property string scope
    property var store: Settings

    readonly property var section: {
        let d = store ? store.data : null;
        let v = (d && typeof d === "object") ? d[scope] : undefined;
        return (v !== null && v !== undefined && typeof v === "object" && !Array.isArray(v)) ? v : {};
    }
    readonly property bool ready: store ? store.ready : false
    readonly property int revision: store ? store.revision : 0

    signal keyChanged(string key)
    signal changed(var section)

    Connections {
        target: scope.store
        function onChanged(s, k) { if (s === scope.scope) scope.keyChanged(k); }
        function onScopeChanged(s) { if (s === scope.scope) scope.changed(scope.section); }
    }

    function get(key, fallback) { return store.get(scope.scope + "." + key, fallback); }
    function has(key) { return store.has(scope.scope + "." + key); }
    function all() { return store.section(scope.scope); }
    function set(key, value) { store.set(scope.scope + "." + key, value); }
    function unset(key) { store.set(scope.scope + "." + key, null); }
    function setMany(patch, immediate) { let w = {}; w[scope.scope] = patch; store.setMany(w, immediate); }
}
