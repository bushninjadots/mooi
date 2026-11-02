import QtQuick
import "../../core"

// ============================================================================
// WidgetRegistry — catalog of desktop-widget types, variants and face files.
//
// Deliberately NOT a singleton: each consumer (widgets/Widgets.qml and the
// future redactor) instantiates its own copy, so component caches never leak
// across subsystems. No dependency on I18n/Scaler/reusables/ThemeBackend:
// icons are raw Nerd Font glyphs and labels are plain English.
//
// Types (id -> metadata):
//   visualizer (bars | continuous), time (digital | analog | minimal),
//   music (full | round), weather (compact | full | round),
//   image (rect | rounded | round) — requiresFilePicker,
//   date (card), system (rings), calendar (month), battery (card),
//   countdown (card).
//
// API:
//   faceFile(type, variant)                       -> resolved URL or ""
//   faceComponent(type, variant)                  -> cached Component or null
//   variantList(type)                             -> [{id, file, icon, label}]
//   typeList()                                    -> [{id, name, icon, ...}]
//   allTypes()                                    -> [typeId, ...]
//   defaultVariant(type)                          -> variant id
//   defaultSize(type)                             -> {w, h}
//   allowsStretchWidth(type)                      -> bool (redactor toolbar)
// ============================================================================

QtObject {
    id: registry

    property var componentCache: ({})

    readonly property var coreTypes: ({
        "visualizer": {
            name: "Visualizer",
            icon: "󰎈",
            defaultWidth: 640,
            defaultHeight: 180,
            defaultVariant: "bars",
            stretchWidth: true,
            requiresFilePicker: false,
            variants: {
                "bars": { file: "faces/VisualizerFace.qml", icon: "1", label: "Bars" },
                "continuous": { file: "faces/VisualizerFaceContinuous.qml", icon: "2", label: "Continuous" }
            }
        },
        "time": {
            name: "Clock",
            icon: "󰥔",
            defaultWidth: 250,
            defaultHeight: 120,
            defaultVariant: "digital",
            stretchWidth: true,
            requiresFilePicker: false,
            variants: {
                "digital": { file: "faces/ClockFaceDigital.qml", icon: "1", label: "Digital" },
                "analog": { file: "faces/ClockFaceAnalog.qml", icon: "2", label: "Analog" },
                "minimal": { file: "faces/ClockFaceMinimal.qml", icon: "3", label: "Minimal" }
            }
        },
        "music": {
            name: "Music",
            icon: "󰝚",
            defaultWidth: 340,
            defaultHeight: 120,
            defaultVariant: "full",
            stretchWidth: true,
            requiresFilePicker: false,
            variants: {
                "full": { file: "faces/MusicFace.qml", icon: "1", label: "Full" },
                "round": { file: "faces/MusicFaceRound.qml", icon: "2", label: "Round" }
            }
        },
        "image": {
            name: "Image",
            icon: "󰋩",
            defaultWidth: 300,
            defaultHeight: 200,
            defaultVariant: "rect",
            stretchWidth: false,
            requiresFilePicker: true,
            variants: {
                "rect": { file: "faces/ImageFaceRect.qml", icon: "1", label: "Rect" },
                "rounded": { file: "faces/ImageFaceRounded.qml", icon: "2", label: "Rounded" },
                "round": { file: "faces/ImageFaceRound.qml", icon: "3", label: "Round" }
            }
        },
        "date": {
            name: "Date",
            icon: "󰃴",
            defaultWidth: 340,
            defaultHeight: 150,
            defaultVariant: "card",
            stretchWidth: true,
            requiresFilePicker: false,
            variants: {
                "card": { file: "faces/DateGreetingFace.qml", icon: "1", label: "Card" }
            }
        },
        "system": {
            name: "System",
            icon: "󰍛",
            defaultWidth: 340,
            defaultHeight: 170,
            defaultVariant: "rings",
            stretchWidth: true,
            requiresFilePicker: false,
            variants: {
                "rings": { file: "faces/SystemFace.qml", icon: "1", label: "Rings" }
            }
        },
        "calendar": {
            name: "Calendar",
            icon: "󰃭",
            defaultWidth: 280,
            defaultHeight: 280,
            defaultVariant: "month",
            stretchWidth: false,
            requiresFilePicker: false,
            variants: {
                "month": { file: "faces/CalendarFace.qml", icon: "1", label: "Month" }
            }
        },
        "battery": {
            name: "Battery",
            icon: "󰁹",
            defaultWidth: 200,
            defaultHeight: 150,
            defaultVariant: "card",
            stretchWidth: false,
            requiresFilePicker: false,
            variants: {
                "card": { file: "faces/BatteryFace.qml", icon: "1", label: "Card" }
            }
        },
        "countdown": {
            name: "Countdown",
            icon: "󰔛",
            defaultWidth: 340,
            defaultHeight: 150,
            defaultVariant: "card",
            stretchWidth: true,
            requiresFilePicker: false,
            variants: {
                "card": { file: "faces/CountdownFace.qml", icon: "1", label: "Card" }
            }
        }
    })

    // Plugin-provided widget faces (provides.widgets.faces): a plugin owns the
    // widget TYPES it ships (variant files relative to its UI root), so a plugin
    // can bring its own desktop widgets. Plugins win on id collisions.
    readonly property var pluginTypes: {
        PluginsCatalog.rev;
        let out = {};
        let list = PluginsCatalog.plugins || [];
        for (let i = 0; i < list.length; i++) {
            let p = list[i] || {};
            if (p.enabled !== true) continue;
            let faces = p.provides && p.provides.widgets && p.provides.widgets.faces;
            if (!faces || typeof faces !== "object") continue;
            for (let tid in faces) {
                let t = faces[tid];
                if (!t || typeof t !== "object" || !t.variants) continue;
                let variants = {};
                for (let vid in t.variants) {
                    let v = t.variants[vid] || {};
                    let comp = String(v.comp || v.file || "");
                    if (comp === "") continue;
                    let rel = PluginsCatalog.isManaged(p)
                        ? ("../plugins/" + p.id + "/" + comp.replace(/^\.\//, ""))
                        : PluginsCatalog.uiUrl(p, comp);
                    variants[vid] = { file: rel, icon: v.icon, label: v.label };
                }
                out[tid] = {
                    name: t.name || tid, icon: t.icon || "",
                    defaultWidth: t.defaultWidth, defaultHeight: t.defaultHeight,
                    defaultVariant: t.defaultVariant, stretchWidth: t.stretchWidth === true,
                    requiresFilePicker: t.requiresFilePicker === true,
                    variants: variants, _plugin: p.id
                };
            }
        }
        return out;
    }

    // Merged catalog: the core types plus the plugin-provided ones (plugin wins).
    readonly property var types: {
        let out = {};
        for (let k in coreTypes) out[k] = coreTypes[k];
        for (let k in pluginTypes) out[k] = pluginTypes[k];
        return out;
    }

    // Face file URL for a type+variant (variant falls back to the type default).
    function faceFile(type, variant) {
        let t = registry.types[type];
        if (!t) return "";
        let v = t.variants[variant] || t.variants[t.defaultVariant];
        return v ? Qt.resolvedUrl(v.file) : "";
    }

    // Cached face Component for a type+variant (used by the redactor proxies).
    function faceComponent(type, variant) {
        let t = registry.types[type];
        if (!t) return null;
        let vKey = (variant && t.variants && t.variants[variant]) ? variant : t.defaultVariant;
        let cacheKey = type + "_" + vKey;
        if (registry.componentCache[cacheKey]) {
            return registry.componentCache[cacheKey];
        }
        let fileUrl = registry.faceFile(type, vKey);
        if (!fileUrl) return null;
        let comp = Qt.createComponent(fileUrl);
        if (comp) {
            registry.componentCache[cacheKey] = comp;
        }
        return comp;
    }

    function variantList(type) {
        let t = registry.types[type];
        if (!t || !t.variants) return [];
        return Object.keys(t.variants).map(k => Object.assign({ id: k }, t.variants[k]));
    }

    function typeList() {
        return Object.keys(registry.types).map(k => Object.assign({ id: k }, registry.types[k]));
    }

    // All type ids in catalog order (keyboard iteration order is insertion order).
    function allTypes() {
        return Object.keys(registry.types);
    }

    function defaultVariant(type) {
        return registry.types[type] ? registry.types[type].defaultVariant : "";
    }

    function defaultSize(type) {
        let t = registry.types[type];
        if (!t) return { w: 250, h: 120 };
        return {
            w: t.defaultWidth || 250,
            h: t.defaultHeight || 120
        };
    }

    // Whether the redactor may stretch this type horizontally.
    function allowsStretchWidth(type) {
        let t = registry.types[type];
        return t ? (t.stretchWidth === true) : false;
    }
}
