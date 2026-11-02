.pragma library
// ═══════════════════════════════════════════════════════════════════════════
// shell · core — Personalization
//
// Generic option API for the ported subsystems that do not need a dedicated
// module (the bar uses BarLayout.js, notifications use Notifications.js).
// Every subsystem exposes a named option set with sane defaults mirroring the
// current behaviour; values live in settings.json under the matching section:
//
//   "lock": { ... }, "battery": { ... }, "volume": { ... }, ...
//
// Pure functions: no QML objects touched. Wiring a component means replacing
// its hardcoded value with value(section, raw, key).
// ═══════════════════════════════════════════════════════════════════════════
var SECTIONS = {
    "lock": {
        revealDurationMs: 300,
        clockPollMs: 1000,
        batteryPollMs: 5000,
        wallpaperBlur: 1.0,   // 0 = off
        wallpaperDim: 0.45,   // base-color overlay opacity on the wallpaper
        showClock: true,      // clock below the password field
        showBattery: true,    // battery chip in the corner (laptops)
        showPower: true,      // power off / reboot row
        clockScale: 1.0       // 0.6 – 1.6
    },
    "battery": {
        popupWidth: 801,
        lowThreshold: 20,
        pollMs: 5000
    },
    "volume": {
        popupWidth: 450,
        step: 5,
        syncDelayMs: 600,
        pollMs: 1000
    },
    "music": {
        popupWidth: 700,
        popupHeight: 650
    },
    "network": {
        popupWidth: 900,
        popupHeight: 700,
        powerAnimMs: 250,
        busyTimeoutMs: 15000,
        failClearMs: 4000
    },
    "calendar": {
        popupWidth: 1450,
        popupHeight: 750
    },
    "updater": {
        popupWidth: 950,
        popupHeight: 850
    },
    "applauncher": {
        popupWidth: 800,
        popupHeight: 700,
        showIcons: false
    },
    "system-monitor": {
        popupWidth: 720,
        popupHeight: 600,
        pollMs: 5000,
        historyLength: 30
    },
    "focustime": {
        popupWidth: 900,
        popupHeight: 700
    },
    "idle": {
        popupWidth: 560,
        popupHeight: 430
    },
    "scale": {
        popupWidth: 520,
        popupHeight: 560,
        pollMs: 250
    },
    "window-controls": {
        popupWidth: 480,
        popupHeight: 800,
        activeOpacity: 0.85,
        inactiveOpacity: 0.80,
        blurSize: 8,
        blurPasses: 3,
        roundness: 20
    },
    "tray": {
        tint: false,        // recolor tray icons with the palette
        useAccent: false,   // tint with the module accent instead of content color
        size: 18
    },
    "widgets": {
        redactorWidth: 1920,
        redactorHeight: 1080
    }
};

function has(section) {
    return SECTIONS.hasOwnProperty(section);
}

function defaults(section) {
    if (!has(section)) return {};
    let out = {};
    let def = SECTIONS[section];
    for (let key in def) out[key] = def[key];
    return out;
}

// Normalized section: known options with valid user values (defaults fill in).
function normalize(section, raw) {
    let out = defaults(section);
    if (!has(section) || !raw || typeof raw !== "object" || Array.isArray(raw)) return out;
    for (let key in out) {
        let v = raw[key];
        if (typeof out[key] === "boolean") {
            if (v !== undefined) out[key] = (v === true);
        } else if (typeof v === "number" && v >= 0) {
            out[key] = v;
        } else if (typeof v === "string" && v !== "") {
            out[key] = v;
        }
    }
    return out;
}

function value(section, raw, key) {
    let o = normalize(section, raw);
    return o.hasOwnProperty(key) ? o[key] : undefined;
}

// New section with one option changed (for editors / API users).
function setOption(section, raw, key, val) {
    let out = normalize(section, raw);
    if (out.hasOwnProperty(key)) out[key] = val;
    return out;
}

// Ready-to-save patch for Config.updateJsonBulk:
//   Config.updateJsonBulk(patch("lock", Config.rawSettings.lock, "fadeMs", 4000))
function patch(section, raw, key, val) {
    let p = {};
    p[section] = setOption(section, raw, key, val);
    return p;
}
