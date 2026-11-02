pragma Singleton
import QtQuick
import Quickshell
import "../core/WindowRegistry.js" as LayoutMath
import "../ui/bar"
import "sdk"

// ═══════════════════════════════════════════════════════════════════════════
// HostApi — per-plugin factory for the injected PluginHost handle.
//
// Binds the shell services (live Colors, Caching, PluginsCatalog, the editor
// scale) to the SDK's PluginHost and caches one handle per plugin id, so the
// host adapter and the settings page receive the SAME handle.
//
// Consumers: ui/PluginHosts.qml (host adapters) and ui/bar/BarEditor.qml
// (settings pages p_<id>), both via Loader.setSource(url, { host }).
// ═══════════════════════════════════════════════════════════════════════════

Scope {
    id: api

    Colors { id: sharedColors }
    Caching { id: sharedCaching }

    readonly property var primaryScreen: {
        let s = Quickshell.screens;
        return (s && s.length > 0) ? s[0] : null;
    }
    readonly property real baseScale: primaryScreen
        ? LayoutMath.getScale(primaryScreen.width, primaryScreen.height, Config.uiScale) : 1.0

    function scaleFn(v) { return LayoutMath.s(v, baseScale); }

    property var _handles: ({})
    Component { id: hostComp; PluginHost {} }
    Component { id: storeComp; SettingsStore {} }

    function forPlugin(entry) {
        let id = (entry && entry.id !== undefined) ? String(entry.id) : "";
        if (id === "") return null;
        let h = _handles[id];
        if (h) { h.manifest = entry; return h; }
        // Per-plugin settings store: the plugin's OWN file (self-contained; never
        // mixed with the core settings.json). Path: <registry>/<id>/settings.json.
        let store = storeComp.createObject(api, {
            filePath: String(entry && entry._base ? entry._base : "") + "/settings.json"
        });
        h = hostComp.createObject(api, {
            manifest: entry,
            colors: sharedColors,
            caching: sharedCaching,
            catalog: PluginsCatalog,
            widgetsSource: LayoutMath,
            statsSource: SysData,
            settingsStore: store,
            scaleFn: api.scaleFn
        });
        if (h) _handles[id] = h;
        return h;
    }
    function forget(id) { delete _handles[String(id)]; }
}
