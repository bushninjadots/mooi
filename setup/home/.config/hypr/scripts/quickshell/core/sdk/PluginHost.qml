import QtQuick
import Quickshell
import "."

// ═══════════════════════════════════════════════════════════════════════════
// PluginHost — the per-plugin handle injected into a plugin's host adapter and
// settings page (the shell-side analogue of the compositor's `mod` table).
//
// A plugin root declares:   required property PluginHost host
// The host factory (shell side) constructs it with the shell services bound to
// the required properties below. Plugins never import shell internals.
// ═══════════════════════════════════════════════════════════════════════════

QtObject {
    id: host

    required property var manifest      // the scan entry (id, _base, scope, provides, ...)
    required property var colors        // Colors-like: semantic role properties
    required property var caching       // Caching-like: cacheDir/stateDir/runDir/logDir
    required property var catalog       // PluginsCatalog-like: plugins, rev, uiPath()
    required property var widgetsSource // WindowRegistry.js module (getLayout/getScale)
    required property var statsSource   // SysData singleton (cpu/ramPercent/temp/subscribe)
    property var scaleFn: null          // function(v) -> real (the editor scale)
    property var settingsStore: null    // the plugin's OWN SettingsStore (its own settings.json)
    property var settingsSource: null   // (legacy alias; prefer settingsStore)

    readonly property string id: (manifest && manifest.id !== undefined) ? String(manifest.id) : ""
    readonly property string dir: (manifest && manifest._base !== undefined) ? String(manifest._base) : ""
    readonly property string apiVersion: SdkVersion.version

    readonly property string home: Quickshell.env("HOME")
    readonly property string settingsPath: home + "/.config/hypr/settings.json"   // legacy alias (core)
    // The plugin's OWN settings file — its state lives here, never mixed into
    // the core settings.json (autonomy).
    readonly property string settingsFilePath: dir !== "" ? (dir + "/settings.json") : ""

    readonly property var widgets: widgetsSource
    readonly property var stats: statsSource

    readonly property string scopeName: (manifest && manifest.scope !== undefined)
        ? String(manifest.scope) : ("plugins." + id)

    readonly property SettingsScope settings: SettingsScope {
        scope: host.scopeName
        store: host.settingsStore !== null ? host.settingsStore : Settings
    }

    readonly property var screens: Quickshell.screens

    function color(role, fallback) {
        if (typeof role === "string" && role.length > 0) {
            if (role.charAt(0) === "#") return role;
            if (colors && colors[role] !== undefined) return colors[role];
        }
        return fallback;
    }
    function s(v) { return scaleFn ? scaleFn(v) : v; }

    function script(name) { return dir + "/scripts/" + String(name); }
    // Read-only access to settings OUTSIDE the plugin's own scope (e.g. the
    // shell's uiScale / bar). Writes stay scoped.
    function global(path, fallback) { return Settings.get(path, fallback); }
    function cacheDir(name) { return caching ? caching.getCacheDir(name || id) : ""; }
    function stateDir(name) { return caching ? caching.getStateDir(name || id) : ""; }
    function runDir(name) { return caching ? caching.getRunDir(name || id) : ""; }
    function logDir(name) { return caching ? caching.getLogDir(name || id) : ""; }

    function exec(cmd) { Quickshell.execDetached(["bash", "-lc", String(cmd)]); }
    function log(msg) { console.log("[plugin:" + id + "] " + msg); }
}
