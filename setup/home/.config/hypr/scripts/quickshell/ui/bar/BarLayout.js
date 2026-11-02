.pragma library

// ============================================================================
// BarLayout — generic, position-agnostic bar engine.
//
// The bar is now a "bar": a set of ZONES laid out along the bar's main axis
// (start → center → end). Zones are pure data — adding / renaming / removing /
// re-aligning a zone is a JSON edit, never a code change. Each zone carries
// its own visual options (unify, border) so new zones get full styling for
// free.
//
//   bar: {
//     enabled: true,          // master switch (off unmaps the bar windows)
//     position: "top" | "bottom" | "left" | "right",
//     palette:  "x",
//     thickness: 48,          // height (top/bottom) or width (left/right)
//     edgeGap: 8,             // distance from the screen edge
//     roundness: 1.0,
//     pillBg: true,
//     pillSolid: false,
//     barBg: false,
//     barOpacity: 0.85,
//     dragModules: true,
//     borderWidth: 0, borderColor: "surface1",
//     stylePreset: "modular", // "modular" | "solid" | "fill" — see STYLE_PRESETS
//     zones: [
//       { id, align: "start"|"center"|"end",
//         unify: false, borderWidth: 0, borderColor: "surface1",
//         modules: [ { id, enabled }, ... ] }
//     ]
//   }
//
// Legacy "topbar" settings (the old {left, center, right} model) are migrated
// automatically on first load.
//
// Style presets (Phase D3) are one-click shortcuts over the pill/bar flags:
// `stylePreset` is INFORMATIVE + a shortcut, never destructive — it only
// records which preset was applied last and never overrides manual tweaks
// (applyStylePreset() is the only function that rewrites the flag keys, and it
// touches exactly the keys its preset declares).
// ============================================================================

// --- module catalog (keep in sync with the modules under topbar/modules/) -----
var MODULES = [
    { id: "help",       label: "Help",        icon: "󰅖", component: "modules/HelpModule.qml" },
    { id: "search",     label: "Search",      icon: "󰍉", component: "modules/SearchModule.qml" },
    { id: "settings",   label: "Settings",    icon: "",  component: "modules/SettingsModule.qml" },
    { id: "update",     label: "Updates",     icon: "󰚰", component: "modules/UpdateModule.qml" },
    { id: "time",       label: "Clock",       icon: "󰅐", component: "modules/TimeModule.qml" },
    { id: "date",       label: "Date",        icon: "󰃭", component: "modules/DateModule.qml" },
    { id: "media",      label: "Media",       icon: "󰎈", component: "modules/MediaModule.qml" },
    { id: "workspaces", label: "Workspaces",  icon: "󰽿", component: "modules/WorkspacesModule.qml" },
    { id: "tray",       label: "System tray", icon: "󱊖", component: "modules/TrayModule.qml" },
    { id: "keyboard",   label: "Keyboard",    icon: "󰌌", component: "modules/KeyboardModule.qml" },
    { id: "wifi",       label: "Network",     icon: "󰤨", component: "modules/WifiModule.qml" },
    { id: "bluetooth",  label: "Bluetooth",   icon: "󰂯", component: "modules/BluetoothModule.qml" },
    { id: "sysmon",     label: "Resources",   icon: "󰍛", component: "" },  // implementation from the sysmon plugin (provides.bar.modules)
    { id: "volume",     label: "Volume",      icon: "󰕾", component: "modules/VolumeModule.qml" },
    { id: "battery",    label: "Battery",     icon: "󰁹", component: "modules/BatteryModule.qml" },
    { id: "recording",  label: "Recording",   icon: "",  component: "" },  // implementation from a plugin (provides.bar.modules)
    { id: "weather",    label: "Timex",       icon: "󰖐", component: "" },  // implementation from the timex plugin (provides.bar.modules)
    { id: "focus",      label: "Focus",       icon: "󰋼", component: "modules/FocusModule.qml" }
];

// Module groups used by normalizeBar()/defaultBar() when (re-)adding missing
// modules. NEW_ALWAYS_DISABLED ids were introduced after the zone era: they are
// re-added to existing bars in a disabled state so upgrades never change a
// user's bar layout without their say-so (they enable them in the Bar Editor).
var LEGACY_START_IDS = ["help", "search", "settings", "update", "time", "date", "media"];
var LEGACY_CENTER_IDS = ["workspaces"];
var LEGACY_END_IDS = ["tray", "keyboard", "wifi", "bluetooth", "sysmon", "volume", "battery", "recording"];

var NEW_ALWAYS_DISABLED = ["weather", "focus"];

var POSITIONS = ["top", "bottom", "left", "right"];
var ALIGNS = ["start", "center", "end"];

// --- style presets (Phase D3: one-click bar looks) -----------------------------
// Only the keys a preset declares are applied by applyStylePreset(), so a
// preset never clobbers unrelated manual tweaks:
//   modular: floating islands, no bar strip   -> pills on the raw desktop
//   solid:   continuous bar strip, pills keep their own fill (islands float
//            INSIDE the strip; accent islands stay colored pills)
//   fill:    like solid but edge-to-edge (edgeGap 0, strip touches the edge).
//            The user can re-raise "Edge margin" afterwards; stylePreset is
//            then just an informational label (see header comment).
var STYLE_PRESETS = {
    "modular": { pillBg: true, pillSolid: false, barBg: false },
    "solid": { barBg: true, pillBg: true },
    "fill": { barBg: true, pillBg: true, edgeGap: 0 }
};
var STYLE_PRESET_KEYS = ["modular", "solid", "fill"];

// Arrays that cross the QML <-> JS boundary through `property var` can arrive
// as QVariantList, which breaks `Array.isArray`. Length-based checks are safe.
function isList(x) {
    return x !== null && x !== undefined && typeof x.length === "number";
}

function getModule(id) {
    for (let i = 0; i < MODULES.length; i++) {
        if (MODULES[i].id === id) return MODULES[i];
    }
    return null;
}

function cloneModules(list) {
    let out = [];
    if (!isList(list)) return out;
    for (let i = 0; i < list.length; i++) {
        let e = list[i];
        if (typeof e === "string") {
            out.push({ id: e, enabled: true });
            continue;
        }
        if (!e || !e.id) continue;
        out.push({ id: e.id, enabled: e.enabled !== false });
    }
    return out;
}

// --- island fill API ---------------------------------------------------------
// Per-island and per-block fill control (personalization API). Values are
// canonical strings:
//   "default" -> inherit (zone value, then the bar-wide pill settings)
//   "on"      -> force the pill fill (ignores unified/barBg/pillBg defaults)
//   "off"     -> force a transparent island
// Booleans are accepted for convenience (true -> "on", false -> "off").
function normalizeFillMode(v) {
    if (v === true || v === "on" || v === "filled") return "on";
    if (v === false || v === "off" || v === "none") return "off";
    return "default";
}

// Set the fill for a whole block (zone); islands without their own value
// inherit it.
function setZoneFill(bar, zoneId, mode) {
    let out = cloneBar(bar);
    let zi = zoneIndex(out, zoneId);
    if (zi === -1) return out;
    out.zones[zi].fill = normalizeFillMode(mode);
    return out;
}

// Clock format for the bar (Qt.formatDateTime pattern).
function setTimeFormat(bar, fmt) {
    let out = cloneBar(bar);
    out.timeFormat = (typeof fmt === "string" && fmt.trim() !== "") ? fmt.trim() : "HH:mm:ss";
    return out;
}

// Date format for the zones engine (Qt.formatDateTime pattern).
function setDateFormat(bar, fmt) {
    let out = cloneBar(bar);
    out.dateFormat = (typeof fmt === "string" && fmt.trim() !== "") ? fmt.trim() : "dddd, MMMM dd";
    return out;
}

// Master switch for the whole bar (bar.enabled). Off unmaps every bar window
// (no UI, no reserved edge); the rest of the config is preserved so switching
// back on restores the bar exactly. Written by the editor (General page); the
// host (Bar.qml) reads the key straight from the parsed config.
function setBarEnabled(bar, v) {
    let out = cloneBar(bar);
    out.enabled = v === true;
    return out;
}

// Workspaces module: empty-workspace marker style + custom character.
function setWorkspacesMarker(bar, mode) {
    let out = cloneBar(bar);
    out.workspacesMarker = ["number", "dot", "letter", "custom"].indexOf(mode) !== -1 ? mode : "number";
    return out;
}
function setWorkspacesMarkerText(bar, ch) {
    let out = cloneBar(bar);
    out.workspacesMarkerText = (typeof ch === "string") ? ch.slice(0, 4) : "";
    return out;
}

// --- module personalization API ----------------------------------------------
// Per-module customization, keyed by module id. User values live in the bar
// config under "modules"; every field is optional:
//   "icon":   glyph override for components that call mod.glyph(...)
//   "color":  content color (a colors.* role name or a #hex string)
//   "fill":   per-island fill ("default" | "on" | "off")
//   "accent": accent role override (turns the island into an accent island)
// The bar-wide "iconColor" sets the default content color for every module.
// Islands that ship with a background by default (palette role fill); the user
// can still force "None" per module.
var DEFAULT_FILLED_MODULES = ["battery", "settings", "search", "time", "help"];

// Accent islands by default: their pill is filled with the palette role, so
// they recolor with the palette (like wifi/bluetooth). Overridable per module.
var DEFAULT_MODULE_ACCENTS = {
    "help":       "peach",
    "search":     "sapphire",
    "settings":   "mauve",
    "update":     "green",
    "time":       "teal",
    "date":       "blue",
    "media":      "pink",
    "tray":       "sapphire",
    "keyboard":   "color5",
    "wifi":       "color6",
    "bluetooth":  "color4",
    "sysmon":     "color1",
    "volume":     "color3",
    "battery":    "green",
    "recording":  "red",
    "weather":    "yellow",
    "focus":      "peach"
    // workspaces keeps its own palette look (bgRole crust + workspaceActive).
};

function defaultModuleConfig(id) {
    return {
        icon: "", color: "",
        accent: DEFAULT_MODULE_ACCENTS[id] !== undefined ? DEFAULT_MODULE_ACCENTS[id] : "",
        fill: (DEFAULT_FILLED_MODULES.indexOf(id) !== -1) ? "on" : "default",
        colors: {},       // per-slot color overrides (role name or #hex)
        size: 0,          // font px override (0 = module default)
        effect: "",       // per-module view effect ("typewriter" for the clock)
        cursor: true      // blinking cursor for the typewriter effect
    };
}

function normalizeModuleConfig(v, id) {
    let out = defaultModuleConfig(id);
    if (!v || typeof v !== "object") return out;
    if (typeof v.icon === "string") out.icon = v.icon;
    if (typeof v.color === "string") out.color = v.color;
    if (v.fill !== undefined) {
        // An explicit "default" returns to the module's built-in default
        // (filled for DEFAULT_FILLED_MODULES, bar-wide behavior otherwise).
        let mode = normalizeFillMode(v.fill);
        out.fill = (mode === "default") ? out.fill : mode;
    }
    if (typeof v.accent === "string") out.accent = v.accent;  // "" clears the default accent
    if (v.colors && typeof v.colors === "object" && !Array.isArray(v.colors)) {
        for (let slot in v.colors) {
            if (typeof v.colors[slot] === "string") out.colors[slot] = v.colors[slot];
        }
    }
    if (typeof v.size === "number" && v.size >= 0) out.size = Math.round(v.size);
    if (typeof v.effect === "string") out.effect = v.effect;
    if (v.cursor !== undefined) out.cursor = v.cursor === true;
    return out;
}

// Effective per-module config (defaults + user values).
function moduleConfig(bar, id) {
    if (!bar || !bar.modules || typeof bar.modules !== "object") return defaultModuleConfig(id);
    return normalizeModuleConfig(bar.modules[id], id);
}

function setModuleValue(bar, id, key, value) {
    let out = cloneBar(bar);
    if (!out.modules || typeof out.modules !== "object") out.modules = {};
    let cfg = normalizeModuleConfig(out.modules[id], id);
    cfg[key] = (key === "fill") ? normalizeFillMode(value) : value;
    out.modules[id] = cfg;
    return out;
}
function setModuleIcon(bar, id, glyph)  { return setModuleValue(bar, id, "icon", glyph); }
function setModuleColor(bar, id, color) { return setModuleValue(bar, id, "color", color); }
function setModuleFill(bar, id, mode)   { return setModuleValue(bar, id, "fill", mode); }
function setModuleAccent(bar, id, role) { return setModuleValue(bar, id, "accent", role); }
function setGlobalIconColor(bar, color) { let out = cloneBar(bar); out.iconColor = color; return out; }
function setModuleSize(bar, id, px)   { return setModuleValue(bar, id, "size", px); }
function setModuleEffect(bar, id, v) { return setModuleValue(bar, id, "effect", v); }
function setModuleCursor(bar, id, v) { return setModuleValue(bar, id, "cursor", v); }
// Per-slot color override (workspaces: active/activeText/occupied/empty/hover/
// marker/markerEmpty). Empty value removes the override.
function setModuleColorSlot(bar, id, slot, value) {
    let out = cloneBar(bar);
    if (!out.modules || typeof out.modules !== "object") out.modules = {};
    let cfg = normalizeModuleConfig(out.modules[id], id);
    if (typeof value === "string" && value !== "") cfg.colors[slot] = value;
    else delete cfg.colors[slot];
    out.modules[id] = cfg;
    return out;
}

// --- defaults -------------------------------------------------------------------
function defaultZone(id, align, modules) {
    return {
        id: id,
        align: align,
        unify: false,
        // Optional container behind the whole zone ("" = off). A color-role
        // name (surface0, mauve, ...); islands keep their own pills on top,
        // so this reads as "capsule inside a capsule". zoneBgSolid makes the
        // container opaque (translucent by default).
        zoneBg: "",
        zoneBgSolid: false,
        borderWidth: 0,
        borderColor: "surface1",
        modules: cloneModules(modules || [])
    };
}

function defaultBar() {
    let zones = [];
    for (let i = 0; i < ALIGNS.length; i++) {
        let align = ALIGNS[i];
        let mods = [];
        for (let m = 0; m < MODULES.length; m++) {
            let id = MODULES[m].id;
            // Legacy distribution: workspaces center, the rest split by
            // catalog order into start/end (weather/focus are appended below,
            // disabled, so fresh installs start exactly like current ones).
            if (align === "center" && LEGACY_CENTER_IDS.indexOf(id) !== -1) mods.push(id);
            else if (align === "start" && LEGACY_START_IDS.indexOf(id) !== -1) mods.push(id);
            else if (align === "end" && LEGACY_END_IDS.indexOf(id) !== -1) mods.push(id);
        }
        zones.push(defaultZone(align, align, mods));
    }
    // New islands ship disabled by default (opt-in in the Bar Editor).
    for (let z = 0; z < zones.length; z++) {
        if (zones[z].align !== "end") continue;
        for (let n = 0; n < NEW_ALWAYS_DISABLED.length; n++) {
            zones[z].modules.push({ id: NEW_ALWAYS_DISABLED[n], enabled: false });
        }
        break;
    }
    return {
        enabled: true,
        position: "top",
        palette: "x",
        thickness: 48,
        edgeGap: 8,
        roundness: 1.0,
        pillBg: true,
        pillSolid: false,
        barBg: false,
        stylePreset: "modular",
        barOpacity: 0.85,
        dragModules: true,
        borderWidth: 0,
        borderColor: "surface1",
        borderFollowPalette: true,
        borderActive: "",
        borderInactive: "",
        // Optional two-stop gradient (custom mode only): per-target flag,
        // second palette color and angle in degrees.
        borderGradientActive: false,
        borderGradientInactive: false,
        borderActive2: "",
        borderInactive2: "",
        borderAngleActive: 45,
        borderAngleInactive: 45,
        font: "Hack Nerd Font",
        timeFormat: "HH:mm:ss",
        dateFormat: "dddd, MMMM dd",
        modules: {},
        // How EMPTY workspaces render in the Workspaces module:
        // "number" (default), "dot", "letter" or "custom" (the character set in
        // workspacesMarkerText, e.g. a Japanese glyph). Occupied workspaces
        // always show app icons (see WorkspacesModule.qml).
        workspacesMarker: "number",
        workspacesMarkerText: "", // single custom character for marker "custom"
        zones: zones
    };
}

// --- normalization ---------------------------------------------------------------
// Turns whatever sits under settings.json's "bar" key into a safe, complete
// config. Unknown zone/module ids are dropped; missing zones/modules are re-added
// from the catalog so nothing silently disappears.
function normalizeBar(raw) {
    let def = defaultBar();
    if (!raw || typeof raw !== "object") return def;

    let out = {
        enabled: raw.enabled !== undefined ? (raw.enabled === true) : def.enabled,
        position: POSITIONS.indexOf(raw.position) !== -1 ? raw.position : def.position,
        palette: (raw.palette && String(raw.palette).trim() !== "") ? String(raw.palette).toLowerCase() : def.palette,
        thickness: (typeof raw.thickness === "number" && raw.thickness >= 24) ? raw.thickness : def.thickness,
        edgeGap: (typeof raw.edgeGap === "number" && raw.edgeGap >= 0) ? raw.edgeGap : def.edgeGap,
        roundness: (typeof raw.roundness === "number") ? Math.max(0, Math.min(1, raw.roundness)) : def.roundness,
        pillBg: raw.pillBg !== undefined ? (raw.pillBg === true) : def.pillBg,
        pillSolid: raw.pillSolid !== undefined ? (raw.pillSolid === true) : def.pillSolid,
        barBg: raw.barBg !== undefined ? (raw.barBg === true) : def.barBg,
        // stylePreset is a label for the one-click presets + an apply shortcut:
        // it is NEVER used to infer or override pillBg/barBg/... — old configs
        // without the key (even ones that happen to match a preset combo) keep
        // their real values and simply read "modular".
        stylePreset: (typeof raw.stylePreset === "string" && STYLE_PRESETS.hasOwnProperty(raw.stylePreset)) ? raw.stylePreset : def.stylePreset,
        barOpacity: (typeof raw.barOpacity === "number") ? Math.max(0.2, Math.min(1.0, raw.barOpacity)) : def.barOpacity,
        dragModules: raw.dragModules !== undefined ? (raw.dragModules === true) : def.dragModules,
        borderWidth: (typeof raw.borderWidth === "number") ? raw.borderWidth : def.borderWidth,
        borderColor: (typeof raw.borderColor === "string" && raw.borderColor !== "") ? raw.borderColor : def.borderColor,
        borderFollowPalette: raw.borderFollowPalette !== undefined ? (raw.borderFollowPalette === true) : def.borderFollowPalette,
        workspacesMarker: ["number", "dot", "letter", "custom"].indexOf(raw.workspacesMarker) !== -1 ? raw.workspacesMarker : def.workspacesMarker,
        workspacesMarkerText: (typeof raw.workspacesMarkerText === "string") ? raw.workspacesMarkerText.slice(0, 4) : def.workspacesMarkerText,
        borderActive: (typeof raw.borderActive === "string") ? raw.borderActive : def.borderActive,
        borderInactive: (typeof raw.borderInactive === "string") ? raw.borderInactive : def.borderInactive,
        borderGradientActive: raw.borderGradientActive !== undefined ? (raw.borderGradientActive === true) : def.borderGradientActive,
        borderGradientInactive: raw.borderGradientInactive !== undefined ? (raw.borderGradientInactive === true) : def.borderGradientInactive,
        borderActive2: (typeof raw.borderActive2 === "string") ? raw.borderActive2 : def.borderActive2,
        borderInactive2: (typeof raw.borderInactive2 === "string") ? raw.borderInactive2 : def.borderInactive2,
        borderAngleActive: (typeof raw.borderAngleActive === "number") ? Math.max(0, Math.min(360, raw.borderAngleActive)) : def.borderAngleActive,
        borderAngleInactive: (typeof raw.borderAngleInactive === "number") ? Math.max(0, Math.min(360, raw.borderAngleInactive)) : def.borderAngleInactive,
        font: (typeof raw.font === "string" && raw.font.trim() !== "") ? raw.font : def.font,
        timeFormat: (typeof raw.timeFormat === "string" && raw.timeFormat.trim() !== "") ? raw.timeFormat : def.timeFormat,
        dateFormat: (typeof raw.dateFormat === "string" && raw.dateFormat.trim() !== "") ? raw.dateFormat : def.dateFormat,
        // Per-module personalization map (see moduleConfig): kept verbatim;
        // entries are normalized on read.
        modules: (raw.modules && typeof raw.modules === "object" && !Array.isArray(raw.modules)) ? raw.modules : def.modules,
        zones: []
    };

    let seen = {};
    let list = isList(raw.zones) ? raw.zones : [];
    for (let i = 0; i < list.length; i++) {
        let z = list[i];
        if (!z || typeof z !== "object" || !z.id || seen[z.id]) continue;
        seen[z.id] = true;
        out.zones.push(defaultZone(
            z.id,
            ALIGNS.indexOf(z.align) !== -1 ? z.align : (z.align || "start"),
            z.modules
        ));
        let zi = out.zones.length - 1;
        out.zones[zi].unify = z.unify === true;
        out.zones[zi].zoneBg = (typeof z.zoneBg === "string") ? z.zoneBg : "";
        out.zones[zi].zoneBgSolid = z.zoneBgSolid === true;
        out.zones[zi].borderWidth = (typeof z.borderWidth === "number") ? z.borderWidth : out.borderWidth;
        out.zones[zi].borderColor = (typeof z.borderColor === "string" && z.borderColor !== "") ? z.borderColor : out.borderColor;
        // Keep EVERY module id: plugin-provided modules (provides.bar.modules)
        // are unknown to this JS catalog and must survive normalization, or the
        // bar would silently drop them on every apply. Only drop duplicates and
        // entries without an id.
        let clean = [];
        let mseen = {};
        for (let m = 0; m < out.zones[zi].modules.length; m++) {
            let mid = out.zones[zi].modules[m].id;
            if (!mid || mseen[mid]) continue;
            mseen[mid] = true;
            clean.push(out.zones[zi].modules[m]);
        }
        out.zones[zi].modules = clean;
    }

    // Re-add any catalog module missing from the config so it never silently
    // vanishes from the user's bar after an update. Legacy ids come back
    // enabled (as before); NEW_ALWAYS_DISABLED ids come back disabled so an
    // update never surprises the user with new islands.
    let allSeen = {};
    for (let z = 0; z < out.zones.length; z++) {
        for (let m = 0; m < out.zones[z].modules.length; m++) allSeen[out.zones[z].modules[m].id] = true;
    }
    let missingByAlign = { "start": [], "center": [], "end": [] };
    for (let m = 0; m < MODULES.length; m++) {
        if (allSeen[MODULES[m].id]) continue;
        let id = MODULES[m].id;
        // Entries are objects so the enabled flag survives whichever branch
        // (new zone or existing zone) finally places them.
        let entry = { id: id, enabled: NEW_ALWAYS_DISABLED.indexOf(id) === -1 };
        if (id === "workspaces") missingByAlign["center"].push(entry);
        else if (LEGACY_START_IDS.indexOf(id) !== -1) missingByAlign["start"].push(entry);
        else missingByAlign["end"].push(entry);
    }
    for (let align in missingByAlign) {
        if (missingByAlign[align].length === 0) continue;
        let target = null;
        for (let z = 0; z < out.zones.length; z++) {
            if (out.zones[z].align === align) { target = z; break; }
        }
        if (target === null) {
            out.zones.push(defaultZone(align, align, missingByAlign[align]));
        } else {
            for (let m = 0; m < missingByAlign[align].length; m++) {
                out.zones[target].modules.push(missingByAlign[align][m]);
            }
        }
    }

    return out;
}

// --- legacy migration --------------------------------------------------------------
// Old settings.json "topbar" = { left, center, right } + topbarBorder*/Unify*/Roundness.
function migrateFromTopbar(raw) {
    if (!raw || typeof raw.topbar !== "object") return null;

    let t = raw.topbar;
    let zoneOrder = ["left", "center", "right"];
    let alignOf = { "left": "start", "center": "center", "right": "end" };
    let zones = [];
    for (let i = 0; i < zoneOrder.length; i++) {
        let key = zoneOrder[i];
        let entries = isList(t[key]) ? t[key] : [];
        let mods = [];
        for (let m = 0; m < entries.length; m++) {
            let e = entries[m];
            let id = (typeof e === "string") ? e : (e ? e.id : "");
            if (id && getModule(id)) mods.push({ id: id, enabled: e && e.enabled !== false });
        }
        let cap = key.charAt(0).toUpperCase() + key.slice(1);
        zones.push(defaultZone(key, alignOf[key] || "start", mods));
        let zi = zones.length - 1;
        zones[zi].unify = raw["topbarUnify" + cap] === true;
        zones[zi].borderWidth = (typeof raw["topbarBorderWidth" + cap] === "number") ? raw["topbarBorderWidth" + cap] : 0;
        zones[zi].borderColor = (typeof raw["topbarBorderColor" + cap] === "string") ? raw["topbarBorderColor" + cap] : "surface1";
    }

    return {
        position: "top",
        palette: "x",
        thickness: 48,
        edgeGap: 8,
        roundness: (typeof raw.topbarRoundness === "number") ? raw.topbarRoundness : 1.0,
        pillBg: raw.topbarPillBg !== undefined ? raw.topbarPillBg === true : true,
        pillSolid: raw.topbarPillSolid !== undefined ? raw.topbarPillSolid === true : false,
        borderWidth: (typeof raw.topbarBorderWidth === "number") ? raw.topbarBorderWidth : 0,
        borderColor: (typeof raw.topbarBorderColor === "string") ? raw.topbarBorderColor : "surface1",
        zones: zones
    };
}

// Main entry: raw = parsed settings.json. Returns a complete bar config.
function getBar(raw) {
    if (raw && typeof raw.bar === "object" && raw.bar !== null) return normalizeBar(raw.bar);
    // Single migration point for pre-0.2 configs: the zones used to live under
    // "dock" (the even older "topbar" shape is converted by migrateFromTopbar).
    if (raw && typeof raw.dock === "object" && raw.dock !== null) return normalizeBar(raw.dock);
    let migrated = migrateFromTopbar(raw);
    return migrated ? normalizeBar(migrated) : defaultBar();
}

// --- zone helpers ------------------------------------------------------------------
function zoneIndex(bar, zoneId) {
    if (!bar || !isList(bar.zones)) return -1;
    for (let i = 0; i < bar.zones.length; i++) {
        if (bar.zones[i] && bar.zones[i].id === zoneId) return i;
    }
    return -1;
}

function zoneModel(zone) {
    let out = [];
    if (!zone || !isList(zone.modules)) return out;
    for (let i = 0; i < zone.modules.length; i++) {
        if (zone.modules[i] && zone.modules[i].enabled) out.push(zone.modules[i].id);
    }
    return out;
}

function isEnabled(bar, id) {
    if (!bar || !isList(bar.zones)) return false;
    for (let z = 0; z < bar.zones.length; z++) {
        let zone = bar.zones[z];
        if (!zone || !isList(zone.modules)) continue;
        for (let m = 0; m < zone.modules.length; m++) {
            if (zone.modules[m] && zone.modules[m].id === id) return zone.modules[m].enabled === true;
        }
    }
    return false;
}

// Pure helpers — always return a new object, never mutate the input.
function cloneBar(bar) {
    let out = JSON.parse(JSON.stringify(bar));
    return out;
}

function setEnabled(bar, id, value) {
    let out = cloneBar(bar);
    for (let z = 0; z < out.zones.length; z++) {
        for (let m = 0; m < out.zones[z].modules.length; m++) {
            if (out.zones[z].modules[m].id === id) out.zones[z].modules[m].enabled = value === true;
        }
    }
    return out;
}

function toggleEnabled(bar, id) {
    return setEnabled(bar, id, !isEnabled(bar, id));
}

// Move a module by delta slots inside its zone; at a zone edge hop into the
// neighbouring zone (ordered by alignment order start → center → end).
function moduleMove(bar, id, delta) {
    let out = cloneBar(bar);
    let zi = -1, idx = -1;
    for (let z = 0; z < out.zones.length && zi === -1; z++) {
        for (let m = 0; m < out.zones[z].modules.length; m++) {
            if (out.zones[z].modules[m].id === id) { zi = z; idx = m; break; }
        }
    }
    if (zi === -1) return out;

    let mods = out.zones[zi].modules;
    let next = idx + delta;
    if (next >= 0 && next < mods.length) {
        let tmp = mods[idx];
        mods[idx] = mods[next];
        mods[next] = tmp;
        return out;
    }

    // hop to the neighbouring zone
    let ordered = [];
    for (let z = 0; z < out.zones.length; z++) ordered.push(z);
    ordered.sort((a, b) => ALIGNS.indexOf(out.zones[a].align) - ALIGNS.indexOf(out.zones[b].align));
    let ziOrder = ordered.indexOf(zi);
    let tzOrder = ziOrder + delta;
    if (tzOrder < 0 || tzOrder >= ordered.length) return out;
    let tz = ordered[tzOrder];
    let entry = mods.splice(idx, 1)[0];
    if (delta > 0) out.zones[tz].modules.unshift(entry);
    else out.zones[tz].modules.push(entry);
    return out;
}

// --- drag & drop helpers (live island reordering, Phase D2) --------------------
// Number of ENABLED modules in a zone.
function enabledCount(zone) {
    if (!zone || !isList(zone.modules)) return 0;
    let n = 0;
    for (let i = 0; i < zone.modules.length; i++) {
        if (zone.modules[i] && zone.modules[i].enabled) n++;
    }
    return n;
}

// Index of `id` among the ENABLED modules of a zone (-1 when disabled/missing).
function enabledIndexOf(zone, id) {
    if (!zone || !isList(zone.modules)) return -1;
    let n = 0;
    for (let i = 0; i < zone.modules.length; i++) {
        let m = zone.modules[i];
        if (!m || !m.enabled) continue;
        if (m.id === id) return n;
        n++;
    }
    return -1;
}

// Is module `id` placed in ANY zone (enabled or not)?
function modulePlaced(bar, id) {
    if (!bar || !isList(bar.zones)) return false;
    for (let z = 0; z < bar.zones.length; z++) {
        let mods = bar.zones[z].modules || [];
        for (let m = 0; m < mods.length; m++) {
            let mid = (typeof mods[m] === "string") ? mods[m] : (mods[m] && mods[m].id);
            if (mid === id) return true;
        }
    }
    return false;
}

// Add module `id` to the bar (first placement): appends it ENABLED to the
// 'end' zone (fallback: the last zone). Used by the editor's "Add to bar"
// button so plugin-provided modules — which are not in the core catalog and
// therefore never auto-added by normalizeBar — become placeable from the UI.
// Returns a new bar; never mutates the input.
function addModuleToBar(bar, id) {
    if (!bar || !isList(bar.zones) || bar.zones.length === 0) return bar;
    let out = cloneBar(bar);
    if (modulePlaced(out, id)) return out;
    let zi = -1;
    for (let z = 0; z < out.zones.length; z++)
        if (out.zones[z].align === "end") { zi = z; break; }
    if (zi === -1) zi = out.zones.length - 1;
    if (!isList(out.zones[zi].modules)) out.zones[zi].modules = [];
    out.zones[zi].modules.push({ id: id, enabled: true });
    return out;
}

// Remove module `id` from every zone. Returns a new bar.
function removeModuleFromBar(bar, id) {
    if (!bar || !isList(bar.zones)) return bar;
    let out = cloneBar(bar);
    for (let z = 0; z < out.zones.length; z++) {
        let mods = out.zones[z].modules || [];
        out.zones[z].modules = mods.filter(m => ((typeof m === "string") ? m : (m && m.id)) !== id);
    }
    return out;
}

// Move module `id` into `targetZoneId` at `insertIndex`. The index is expressed
// over the target zone's ENABLED modules, IGNORING the dragged module itself
// (as if it had already left), and is clamped to [0, enabledCount]. The module
// keeps its `enabled` state. Returns a new bar; never mutates the input.
function moduleMoveTo(bar, id, targetZoneId, insertIndex) {
    if (!bar || !isList(bar.zones)) return bar;
    let out = cloneBar(bar);
    let srcZone = -1, srcIdx = -1;
    for (let z = 0; z < out.zones.length && srcZone === -1; z++) {
        let mods = out.zones[z].modules;
        for (let m = 0; m < mods.length; m++) {
            if (mods[m] && mods[m].id === id) { srcZone = z; srcIdx = m; break; }
        }
    }
    if (srcZone === -1) return out;
    let tz = zoneIndex(out, targetZoneId);
    if (tz === -1) return out;

    let entry = out.zones[srcZone].modules.splice(srcIdx, 1)[0];
    if (srcZone === tz) {
        // Removing from the same zone shifted indices: the target index was
        // computed without the dragged module, which is exactly the state we
        // are in now — insert directly.
        let cap = enabledCount(out.zones[tz]);
        let at = Math.max(0, Math.min(cap, isFinite(insertIndex) ? insertIndex : cap));
        let placed = false;
        let seen = 0;
        let mods = out.zones[tz].modules;
        for (let i = 0; i <= mods.length; i++) {
            if (seen === at) { mods.splice(i, 0, entry); placed = true; break; }
            if (i < mods.length && mods[i] && mods[i].enabled) seen++;
        }
        if (!placed) mods.push(entry);
        return out;
    }

    // Different zone: insert among its enabled modules at the requested slot.
    let cap = enabledCount(out.zones[tz]);
    let at = Math.max(0, Math.min(cap, isFinite(insertIndex) ? insertIndex : cap));
    let mods = out.zones[tz].modules;
    let seen = 0;
    let placed = false;
    for (let i = 0; i <= mods.length; i++) {
        if (seen === at) { mods.splice(i, 0, entry); placed = true; break; }
        if (i < mods.length && mods[i] && mods[i].enabled) seen++;
    }
    if (!placed) mods.push(entry);
    return out;
}

// --- style presets & quick layouts (Phase D3, pure) ------------------------------
// Apply a one-click style preset to a copy of `bar`. Only the keys declared by
// the preset are written; stylePreset records the preset for the editor badge.
// Invalid presets leave the bar untouched (still returns a clone: never
// returns the caller's object).
function applyStylePreset(bar, preset) {
    let out = cloneBar(bar);
    if (!STYLE_PRESETS.hasOwnProperty(preset)) return out;
    let p = STYLE_PRESETS[preset];
    for (let key in p) {
        if (p.hasOwnProperty(key)) out[key] = p[key];
    }
    out.stylePreset = preset;
    return out;
}

// Index of the first zone aligned `align` (-1 when none). Pure.
function firstZoneWithAlign(bar, align) {
    if (!bar || !isList(bar.zones)) return -1;
    for (let z = 0; z < bar.zones.length; z++) {
        if (bar.zones[z] && bar.zones[z].align === align) return z;
    }
    return -1;
}

// "Center all": gather every ENABLED module (in catalog order) into the first
// zone aligned `align`, creating that zone when the bar has none. Modules keep
// their enabled state; DISABLED entries are never moved (they stay in their own
// zones) and emptied zones are not removed. The target zone keeps its own
// disabled entries, appended after the enabled cluster so the visible islands
// read in a clean block. Returns a new bar; never mutates the input.
function arrangeAllInZone(bar, align) {
    if (!bar || !isList(bar.zones) || ALIGNS.indexOf(align) === -1) return bar;
    let out = cloneBar(bar);

    // Enabled module ids, ordered by the catalog (not by their current zones).
    let enabledHere = {};
    for (let z = 0; z < out.zones.length; z++) {
        let mods = out.zones[z].modules;
        if (!isList(mods)) continue;
        for (let m = 0; m < mods.length; m++) {
            if (mods[m] && mods[m].enabled) enabledHere[mods[m].id] = true;
        }
    }
    let wanted = [];
    for (let m = 0; m < MODULES.length; m++) {
        if (enabledHere[MODULES[m].id]) wanted.push(MODULES[m].id);
    }
    if (wanted.length === 0) return out;

    // Target zone: reuse the first `align` zone or append a fresh one.
    let zi = firstZoneWithAlign(out, align);
    if (zi === -1) {
        let nid = align;
        let n = 2;
        while (zoneIndex(out, nid) !== -1) nid = align + n++;
        out.zones.push(defaultZone(nid, align, []));
        zi = out.zones.length - 1;
    }

    // Strip every enabled entry from ALL zones (disabled entries stay where
    // they are), then rebuild the target as enabled-block + its own disabled.
    for (let z = 0; z < out.zones.length; z++) {
        let mods = out.zones[z].modules;
        if (!isList(mods)) continue;
        out.zones[z].modules = mods.filter(m => !(m && m.enabled));
    }
    let block = [];
    for (let i = 0; i < wanted.length; i++) block.push({ id: wanted[i], enabled: true });
    out.zones[zi].modules = block.concat(out.zones[zi].modules);
    return out;
}

// --- zone CRUD (used by the settings editor) ---------------------------------------
function addZone(bar, align, afterZoneId) {
    let out = cloneBar(bar);
    let id = "zone" + (Date.now() % 100000);
    let zi = zoneIndex(out, afterZoneId);
    let z = defaultZone(id, ALIGNS.indexOf(align) !== -1 ? align : "start", []);
    if (zi === -1) out.zones.push(z);
    else out.zones.splice(zi + 1, 0, z);
    return out;
}

function removeZone(bar, zoneId) {
    let out = cloneBar(bar);
    if (out.zones.length <= 1) return out; // keep at least one zone
    let zi = zoneIndex(out, zoneId);
    if (zi === -1) return out;
    // move orphaned modules to the first zone instead of dropping them
    let orphans = out.zones[zi].modules;
    out.zones.splice(zi, 1);
    if (orphans.length > 0 && out.zones.length > 0) {
        out.zones[0].modules = out.zones[0].modules.concat(orphans);
    }
    return out;
}

function renameZone(bar, zoneId, newId) {
    let out = cloneBar(bar);
    let zi = zoneIndex(out, zoneId);
    if (zi === -1) return out;
    let clean = String(newId || "").trim().toLowerCase().replace(/[^a-z0-9_-]/g, "");
    if (clean === "" || zoneIndex(out, clean) !== -1) return out;
    out.zones[zi].id = clean;
    return out;
}

function setZoneAlign(bar, zoneId, align) {
    let out = cloneBar(bar);
    let zi = zoneIndex(out, zoneId);
    if (zi === -1 || ALIGNS.indexOf(align) === -1) return out;
    out.zones[zi].align = align;
    return out;
}

function setZoneUnify(bar, zoneId, value) {
    let out = cloneBar(bar);
    let zi = zoneIndex(out, zoneId);
    if (zi === -1) return out;
    out.zones[zi].unify = value === true;
    return out;
}

// Set (or clear with "") the container background role of a zone. Pure.
function setZoneBg(bar, zoneId, role) {
    let out = cloneBar(bar);
    let zi = zoneIndex(out, zoneId);
    if (zi === -1) return out;
    out.zones[zi].zoneBg = String(role || "");
    return out;
}

// Opaque vs translucent container fill (pure).
function setZoneBgSolid(bar, zoneId, solid) {
    let out = cloneBar(bar);
    let zi = zoneIndex(out, zoneId);
    if (zi === -1) return out;
    out.zones[zi].zoneBgSolid = solid === true;
    return out;
}

function setZoneBorder(bar, zoneId, width, color) {
    let out = cloneBar(bar);
    let zi = zoneIndex(out, zoneId);
    if (zi === -1) return out;
    if (typeof width === "number") out.zones[zi].borderWidth = width;
    if (typeof color === "string" && color !== "") out.zones[zi].borderColor = color;
    return out;
}

// Flat list of every module for the settings editor, tagged with zone info.
function flatten(bar) {
    let out = [];
    if (!bar || !isList(bar.zones)) return out;
    for (let z = 0; z < bar.zones.length; z++) {
        let zone = bar.zones[z];
        if (!zone || !isList(zone.modules)) continue;
        for (let m = 0; m < zone.modules.length; m++) {
            let mod = getModule(zone.modules[m].id);
            if (!mod) continue;
            out.push({
                id: mod.id, label: mod.label, icon: mod.icon,
                zone: zone.id, zoneAlign: zone.align,
                enabled: zone.modules[m].enabled === true,
                isFirst: m === 0, isLast: m === zone.modules.length - 1
            });
        }
    }
    return out;
}
