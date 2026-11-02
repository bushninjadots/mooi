.pragma library

function getScale(mw, mh, userScale) {
    if (arguments.length === 2) {
        userScale = mh;
        mh = mw * (1080.0 / 1920.0);
    }

    if (mw <= 0 || mh <= 0) return 1.0;
    
    let rw = mw / 1920.0;
    let rh = mh / 1080.0;
    let r = Math.min(rw, rh);
    
    let baseScale = 1.0;
    
    if (r <= 1.0) {
        baseScale = Math.max(0.35, Math.pow(r, 0.85));
    } else {
        baseScale = Math.pow(r, 0.5);
    }
    
    return baseScale * (userScale !== undefined ? userScale : 1.0);
}

function s(val, scale) {
    return Math.round(val * scale);
}


// ═══ POPUP POSITION OVERRIDES ═══════════════════════════════════════════════
// settings.widgets.<name>.position places any widget anywhere on screen.
// "default" keeps the widget's own layout; the rest anchor with a margin.
var POSITION_IDS = ["default", "top-left", "top-center", "top-right",
                    "center-left", "center", "center-right",
                    "bottom-left", "bottom-center", "bottom-right"];
function positionLayout(t, pos, mw, mh, userScale) {
    if (!t || !pos || pos === "default") return t;
    let scale = getScale(mw, mh, userScale);
    let m = s(20, scale);
    let cx = Math.floor((mw - t.w) / 2);
    let cy = Math.floor((mh - t.h) / 2);
    if (pos === "top-left")          { t.rx = m;         t.ry = m; }
    else if (pos === "top-center")   { t.rx = cx;        t.ry = m; }
    else if (pos === "top-right")    { t.rx = mw - t.w - m; t.ry = m; }
    else if (pos === "center-left")  { t.rx = m;         t.ry = cy; }
    else if (pos === "center")       { t.rx = cx;        t.ry = cy; }
    else if (pos === "center-right") { t.rx = mw - t.w - m; t.ry = cy; }
    else if (pos === "bottom-left")  { t.rx = m;         t.ry = mh - t.h - m; }
    else if (pos === "bottom-center"){ t.rx = cx;        t.ry = mh - t.h - m; }
    else if (pos === "bottom-right") { t.rx = mw - t.w - m; t.ry = mh - t.h - m; }
    return t;
}

function getLayout(name, mx, my, mw, mh, userScale) {
    let scale = getScale(mw, mh, userScale);

    let base = {
        // --- Top Right Popups ---
        "battery":   { w: s(801, scale), h: s(760, scale), rx: mw - s(805, scale), ry: s(60, scale), comp: "ui/bar/popups/battery/BatteryPopup.qml" },
        "network":   { w: s(900, scale), h: s(700, scale), rx: mw - s(904, scale), ry: s(60, scale), comp: "ui/bar/popups/network/NetworkPopup.qml" },
        "volume":    { w: s(450, scale), h: s(700, scale), rx: mw - s(455, scale), ry: s(60, scale), comp: "ui/bar/popups/volume/VolumePopup.qml" },
        
        // --- Central Standard Tools ---
        "applauncher": { w: s(800, scale), h: s(700, scale), rx: Math.floor((mw/2)-(s(800, scale)/2)), ry: Math.floor((mh/2)-(s(700, scale)/2)), comp: "ui/bar/popups/applauncher/appLauncher.qml" },
        "idle": { w: s(560, scale), h: s(430, scale), rx: Math.floor((mw/2)-(s(560, scale)/2)), ry: Math.floor((mh/2)-(s(430, scale)/2)), comp: "ui/panels/idle/IdlePopup.qml" },

        // --- Central Large Tools ---
        "focustime": { w: s(900, scale), h: s(700, scale), rx: Math.floor((mw/2)-(s(900, scale)/2)), ry: Math.floor((mh/2)-(s(700, scale)/2)), comp: "ui/panels/focustime/FocusTimePopup.qml" },

        // --- Extralarge / Custom Centered ---
        "updater": { w: s(950, scale), h: s(850, scale), rx: Math.floor((mw/2)-(s(950, scale)/2)), ry: Math.floor((mh/2)-(s(850, scale)/2)), comp: "ui/bar/popups/updater/UpdaterPopup.qml" },
        "system-monitor": { w: s(720, scale), h: s(600, scale), rx: Math.floor((mw/2)-(s(720, scale)/2)), ry: Math.floor((mh/2)-(s(600, scale)/2)), comp: "ui/bar/popups/system-monitor/SystemMonitor.qml" },
        "palette": { w: mw - s(40, scale), h: Math.min(s(880, scale), mh - s(60, scale)), rx: s(20, scale), ry: Math.floor((mh - Math.min(s(880, scale), mh - s(60, scale))) / 2), comp: "ui/panels/palette/PaletteWidget.qml" },
        "scale": { w: s(520, scale), h: s(560, scale), rx: Math.floor((mw/2)-(s(520, scale)/2)), ry: Math.floor((mh/2)-(s(560, scale)/2)), comp: "ui/panels/scale/ScalePicker.qml" },
        "window-controls": { w: s(480, scale), h: s(800, scale), rx: Math.floor((mw/2)-(s(480, scale)/2)), ry: Math.floor((mh/2)-(s(800, scale)/2)), comp: "ui/panels/window-controls/WindowControls.qml" },
        "bar-editor": { w: Math.min(s(1260, scale), mw - s(40, scale)), h: s(760, scale), rx: Math.floor((mw - Math.min(s(1260, scale), mw - s(40, scale))) / 2), ry: Math.floor((mh/2)-(s(760, scale)/2)), comp: "ui/bar/BarEditor.qml" },
        "plugins": { w: s(1000, scale), h: s(780, scale), rx: Math.floor((mw/2)-(s(1000, scale)/2)), ry: Math.floor((mh/2)-(s(780, scale)/2)), comp: "ui/panels/plugins/PluginsPanel.qml" },
        
        // --- Top Left Edge ---
        "music":     { w: s(700, scale), h: s(650, scale), rx: s(5, scale), ry: s(60, scale), comp: "ui/bar/popups/music/MusicPopup.qml" },

        // --- Screen Spanning Panels ---
        
        // Full-screen desktop-widget editor: covers the whole monitor (rx/ry 0)
        // so redactor-local coordinates equal the widget layout coordinates.
        "widgets-redactor": { w: mw, h: mh, rx: 0, ry: 0, comp: "ui/widgets/WidgetRedactor.qml" },
        
        // --- Utility ---
        "hidden":    { w: 1, h: 1, rx: -5000 - mx, ry: -5000 - my, comp: "" } 
    };

    if (!base[name]) return null;
    
    let t = base[name];
    t.x = mx + t.rx;
    t.y = my + t.ry;
    
    return t;
}

function getPopupLayout(mw, mh, userScale) {
    if (arguments.length === 2) {
        userScale = mh;
        mh = mw * (1080.0 / 1920.0);
    }
    
    let scale = getScale(mw, mh, userScale);
    return {
        w: s(350, scale),
        marginTop: s(60, scale),
        marginRight: s(20, scale),
        spacing: s(12, scale),
        radius: s(14, scale),
        padding: s(12, scale)
    };
}
