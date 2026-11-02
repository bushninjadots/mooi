pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// ═══════════════════════════════════════════════════════════════════════════
// PluginsCatalog — discovery for the equisdots plugin standard (shell side).
//
// Scans the managed and user plugin dirs through core/scripts/plugins_scan.sh
// and exposes one ordered array:
//
//   plugins  [{ id, name, version, author, description, type, toggle,
//               enabled, settingsTab?, _base, ... }] — one per installed
//            plugin, sorted by name. `enabled` already resolves the effective
//            switch from settings.json (toggle path / defaultEnabled).
//
// User plugins override managed ones on id collisions (scan order: user
// first). Drop a folder with a plugin.json in `~/.config/hypr/plugins-user/`
// and call refresh() (or restart the shell) and it shows up.
//
// The Settings → Plugins page renders this catalog; `rev` bumps after every
// scan so bindings re-evaluate.
//
// Besides the installed scan, the catalog reads the install registry copy
// (plugins-registry.json, deployed by `dots`) to expose the *available*
// plugins — registry entries whose id is not installed yet — for the Plugins
// page's install flow (`dots plugins add <id>`). The scan itself never needs
// the registry: installed plugins stay discovery-driven.
// ═══════════════════════════════════════════════════════════════════════════

Item {
    id: catalog

    readonly property string home: Quickshell.env("HOME")
    readonly property string script: home + "/.config/hypr/scripts/quickshell/core/scripts/plugins_scan.sh"
    readonly property string managed: home + "/.config/hypr/plugins"
    readonly property string userDir: home + "/.config/hypr/plugins-user"
    readonly property string settings: home + "/.config/hypr/settings.json"

    property var plugins: []
    property int rev: 0

    // ── available (install registry, deployed by dots) ────────────────────
    readonly property string registryPath: home + "/.config/hypr/scripts/quickshell/plugins-registry.json"
    property var registry: ({ version: 0, plugins: [] })
    property int registryRev: 0

    function parseRegistry() {
        try {
            let o = JSON.parse(registryFile.text() || "{}");
            registry = (o && typeof o === "object") ? o : ({ version: 0, plugins: [] });
        } catch (e) {
            registry = ({ version: 0, plugins: [] });
        }
        registryRev++;
    }

    function registryEntries() {
        return (registry && Array.isArray(registry.plugins)) ? registry.plugins : [];
    }

    function isInstalled(id) {
        return plugins.some(p => p && p.id === id);
    }

    // Registry entries whose id is not installed yet (user plugins win: an id
    // lives in either the installed scan or this list, never both).
    function availablePlugins() {
        return registryEntries().filter(r => r && r.id && !isInstalled(r.id));
    }

    // ── plugin bar modules (manifest provides.bar.modules) ────────────────
    // Bar modules shipped by plugins: `<id> = { comp, label?, icon? }` (comp
    // relative to the plugin UI root). The core catalog keeps the slot id for
    // layout/defaults; the bar resolves the implementation here for enabled,
    // compatible plugins.
    function barModuleEntries() {
        let out = [];
        let list = plugins || [];
        for (let i = 0; i < list.length; i++) {
            let p = list[i] || {};
            if (p.enabled !== true) continue;
            if (p.compat && p.compat.ok === false) continue;
            let b = (p.provides && typeof p.provides === "object") ? p.provides.bar : null;
            let mods = (b && typeof b === "object") ? b.modules : null;
            if (!mods || typeof mods !== "object") continue;
            for (let id in mods) {
                let e = mods[id] || {};
                out.push({ id: id, entry: e, plugin: p,
                           label: e.label || id, icon: e.icon || "" });
            }
        }
        return out;
    }

    function barModule(id) {
        let list = barModuleEntries();
        for (let i = 0; i < list.length; i++) if (list[i].id === id) return list[i];
        return null;
    }

    // ── plugin bars (manifest provides.bar.provider) ──────────────────────
    // A complete bar shipped by a plugin: `{ comp, label?, icon? }` (comp
    // relative to the plugin UI root). The plugin's own master switch owns it
    // and its settings page is its menu; the shell mounts the comp through
    // PluginHosts exactly like a host adapter (same handle injection, same
    // surfaces/frameObstacle contracts). Managed plugins only — the comp
    // lives in the shell tree so it can import the core kit.
    function barProviderEntries() {
        let out = [];
        let list = plugins || [];
        for (let i = 0; i < list.length; i++) {
            let p = list[i] || {};
            if (p.enabled !== true) continue;
            if (p.compat && p.compat.ok === false) continue;
            let b = (p.provides && typeof p.provides === "object") ? p.provides.bar : null;
            let prov = (b && typeof b === "object") ? b.provider : null;
            if (!prov || typeof prov !== "object" || !prov.comp) continue;
            out.push({ id: String(p.id), comp: String(prov.comp).replace(/^\.\//, ""), entry: prov, plugin: p });
        }
        return out;
    }

    function barProviderComp(id) {
        let list = barProviderEntries();
        for (let i = 0; i < list.length; i++) if (list[i].id === id) return list[i].comp;
        return "";
    }

    // Component URL for a plugin bar module: root-relative for managed
    // plugins (resolved from the caller at ui/bar depth as "../plugins/..."),
    // absolute path for user plugins.
    function barModuleComp(id) {
        let hit = barModule(id);
        if (!hit || !hit.entry.comp) return "";
        return isManaged(hit.plugin)
            ? "../plugins/" + hit.plugin.id + "/" + String(hit.entry.comp).replace(/^\.\//, "")
            : uiPath(hit.plugin, hit.entry.comp);
    }

    function refresh() {
        scan.running = false;
        scan.running = true;
        registryFile.reload();
    }

    // ── origin ────────────────────────────────────────────────────────────
    // Managed plugins are deployed by dots into the shell tree; user plugins
    // live in `~/.config/hypr/plugins-user/`.
    function isManaged(p) {
        if (!p) return false;
        let base = String(p._base || "");
        return base.indexOf(home + "/.config/hypr/plugins-user/") !== 0;
    }

    // ── UI resolution (shared by the shell integrations) ──────────────────
    // Absolute path of a plugin's UI root: managed plugins resolve to the
    // shell-tree deploy (ui/plugins/<id>); user plugins to their own folder.
    // `rel` appends a repo-relative path (settings pages, provided dirs, ...).
    function uiPath(p, rel) {
        if (!p || !p.id) return "";
        let base = String(p._base || "");
        let rootDir = PluginsCatalog.isManaged(p)
                      ? home + "/.config/hypr/scripts/quickshell/ui/plugins/" + p.id
                      : base;
        if (!rel) return rootDir;
        return rootDir + "/" + String(rel).replace(/^\.\//, "");
    }
    function uiUrl(p, rel) {
        let path = uiPath(p, rel);
        return path === "" ? "" : "file://" + path;
    }

    Process {
        id: scan
        running: true
        clearEnvironment: false
        environment: ({
            PLUGINS_MANAGED: catalog.managed,
            PLUGINS_USER: catalog.userDir,
            PLUGINS_SETTINGS: catalog.settings
        })
        command: ["bash", catalog.script]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    let o = JSON.parse(this.text);
                    catalog.plugins = Array.isArray(o) ? o : [];
                    catalog.rev++;
                } catch (e) {}
            }
        }
    }

    // Install registry copy (deployed by dots). Watched so the Available list
    // follows add/remove and the copy appearing after the first `dots plugins`
    // run; a missing file just resolves to an empty registry.
    FileView {
        id: registryFile
        path: catalog.registryPath
        watchChanges: true
        onLoaded: catalog.parseRegistry()
        onFileChanged: catalog.parseRegistry()
        onLoadFailed: catalog.parseRegistry()
    }
}
