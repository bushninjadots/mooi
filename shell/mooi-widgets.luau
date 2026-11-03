-- The desktop widgets' logic (D137): widgets.json through lib/widgets into the scene's model, what
-- is playing (any player, through the media service), its lyrics (player/lyricfetch, the
-- player's own cache) and the bar's visualiser feed. The data folder is mooi's (bin/mooi links
-- mooi-widgets to it), so settings.json, palette.json and widgets.json are the shell's own.

local config = require("lib/config")
local ferro = require("lib/ferro")
local style = require("lib/style")
local W = require("lib/widgets")
local P = require("lib/player")
local vizfeed = require("lib/vizfeed")
local coverart = require("lib/cover")

local function read(name, kind)
    local ok, v
    if kind then ok, v = pcall(sys.ask, "files.read", name, kind)
    else ok, v = pcall(sys.ask, "files.read", name) end
    return ok and v or nil
end
local HOME = tostring(sys.ask("env", "HOME"))
local folder = (function()
    local ok, f = pcall(sys.ask, "files.folder")
    return ok and type(f) == "string" and f ~= "" and f or (HOME .. "/.local/share/pleamar/mooi")
end)()
local COVERS = folder .. "/player-covers"
local fetch = require("player/lyricfetch")({ read = read })
-- the player's caches, which this may be the first to use
run("mkdir", { "-p", COVERS, folder .. "/player-lyrics" })

-- ── The shell's colours, corners and finish, as the board wears them ──
local settings = config.parse(read("settings.json"), json.decode)
local palette = read("palette.json", "json")
local function paint()
    fact.cn_kind, fact.cn_scale = style.corners(settings)
    local look = style.facts(settings)
    if look and look.st_glow then fact.st_glow = look.st_glow end
    local motion = type(settings.motion) == "table" and settings.motion or {}
    fact.viz_still = motion.reduced == true or motion.saver == "always"
    local out = ferro.resolve(settings.theme.source, palette, settings.theme.signal, false, ferro.options(settings))
    if not out then return end
    for _, role in ipairs(ferro.ROLES) do
        local c = out[role]
        fact["fr_" .. role .. "_r"], fact["fr_" .. role .. "_g"], fact["fr_" .. role .. "_b"] = c.r, c.g, c.b
    end
end
paint()
pcall(sys.watch, "files:palette.json", function() palette = read("palette.json", "json"); paint() end)
pcall(sys.watch, "files:settings.json", function() settings = config.parse(read("settings.json"), json.decode); paint() end)

-- ── The widgets ──
-- The room under the bar: the surface says how big it is once it is placed (`screen` is not known
-- while this file loads), so until then a 1080p screen under a 34 px bar.
local room = { w = 1920, h = 1046, top = 0 }
local doc = nil
local playing = false

-- Calm: nothing pointed at and no fade under way, so the surface can drop to a few frames a second.
local hovered, calm_at = {}, 0
local function unsettle()
    fact.wg_calm = false
    calm_at = os.time() + 2
end
every(1000, function()
    if fact.wg_calm or fact.editing or next(hovered) ~= nil or os.time() < calm_at then return end
    fact.wg_calm = true
end)

-- The editor's selection (widget ids) and its undo history (D138).
local selected, hist = {}, W.history()
-- what a gesture holds while it lasts (a carried widget, a handle, a slider, a marquee), the panel's
-- place once dragged, and the doc as last saved (what the file watch compares against)
local pending, grab, slide, marq0, panel_at, last_saved = nil, nil, nil, nil, nil, nil
local show_selection     -- defined with the editor below; load() needs it
local function is_sel(id) for _, s in ipairs(selected) do if s == id then return true end end; return false end

local function publish()
    local rows = {}
    for _, w in ipairs(doc.widgets) do
        local st = W.idle_state(w, playing)
        local o = w.options or {}
        rows[#rows + 1] = {
            kind = w.kind == "visualiser" and 1 or 0,
            lay = W.LAYOUT_INDEX[w.layout] or 0,
            mode = W.MODE_INDEX[w.mode] or 0,
            x = w.x, y = w.y, w = w.w, h = w.h, u = W.scale(w),
            idle = W.IDLE_INDEX[w.idle] or 1,
            st = ({ shown = 0, rest = 1, hidden = 2, marker = 3 })[st],
            op = ({ shown = 1, rest = 0.35, hidden = 0, marker = 0 })[st],
            glow = tonumber(o.glow) or 0, plate = o.plate == true,
            lyr = o.lyrics ~= false, prog = o.progress ~= false,
            gh = st == "hidden" or st == "marker",
            bars = math.floor(tonumber(o.bars) or 64), gap = tonumber(o.gap) or 0.3,
            peaks = o.peaks ~= false, refl = o.reflection == true,
            vslot = -1, opa = w.opacity or 1, txt = tonumber(o.text) or 1, locked = w.locked == true,
            sel = is_sel(w.id),
        }
    end
    -- which visualiser draws from which lane's bars (three at most, lib/widgets MAX_VIZ)
    local nv = 0
    for i, w in ipairs(doc.widgets) do
        if w.kind == "visualiser" then nv = nv + 1; rows[i].vslot = math.min(nv, 3) - 1 end
    end
    model.wg = rows
    fact.wg_nviz = W.count_kind(doc, "visualiser")
    -- the lanes: each visualiser's place and look, read by the scene's three Lane groups
    local lane = 0
    for i, w in ipairs(doc.widgets) do
        if w.kind == "visualiser" and lane < 3 then
            local r = rows[i]
            local L = ({ "A", "B", "C" })[lane + 1]
            local f = "l" .. L .. "_"
            fact[f .. "on"], fact[f .. "k"] = true, i - 1
            fact[f .. "x"], fact[f .. "y"], fact[f .. "w"], fact[f .. "h"], fact[f .. "u"] = r.x, r.y, r.w, r.h, r.u
            fact[f .. "mode"], fact[f .. "n"], fact[f .. "gap"], fact[f .. "glow"] = r.mode, r.bars, r.gap, r.glow
            fact[f .. "peaks"], fact[f .. "refl"], fact[f .. "plate"] = r.peaks, r.refl, r.plate
            fact[f .. "st"], fact[f .. "gh"], fact[f .. "opa"] = r.st, r.gh, r.opa
            fact[f .. "sel"] = r.sel and not r.locked
            lane = lane + 1
        end
    end
    for j = lane, 2 do fact["l" .. ({ "A", "B", "C" })[j + 1] .. "_on"] = false end
    -- a slot that went (removed, or the file changed) cannot keep the surface awake
    hovered = W.prune_hover(hovered, #rows)
    for i = 0, W.MAX - 1 do
        local r = rows[i + 1]
        fact["op" .. i] = r and r.op or 0
        if not r then fact["hl" .. i] = 0 end
    end
    unsettle()
end

local function load()
    local raw = read(W.FILE)
    local d, problems = W.parse(raw, json.decode, room)
    for _, p in ipairs(problems) do log("widgets · " .. p) end
    if d.bad then
        run("mv", { "-f", folder .. "/" .. W.FILE, folder .. "/" .. W.FILE .. ".bad" })
        log("widgets · widgets.json kept as widgets.json.bad; the defaults are shown")
    end
    doc = d
    publish()
    if show_selection then show_selection() end
end

-- Saved whole: files.write writes beside the file and then moves it into place.
local function save()
    last_saved = W.encode(doc)
    pcall(sys.call, "files.write", W.FILE, last_saved)
end
-- a gesture ends without being saved: back to the doc it started from
local function drop_gestures(restore)
    if restore then
        if grab then doc = grab.before elseif slide then doc = slide.before end
    end
    pending, grab, slide, marq0 = nil, nil, nil, nil
    fact.wg_rk, fact.wg_dk = -1, -1
end

load()
pcall(sys.watch, "files:" .. W.FILE, function()
    local raw = read(W.FILE)
    if raw == nil then return end
    local ok, t = pcall(json.decode, raw)
    if ok and last_saved and W.same_doc(t, last_saved) then return end
    if ok and not grab and not slide and not W.should_reload(t, doc) then return end
    -- changed elsewhere (Settings): undo would bring back what is not there any more, and a held
    -- slider or handle would put back what was there when it was taken
    drop_gestures(false)
    W.clear(hist)
    load()
end)
-- packed as width · 4096 + height (under 2^24)
on("wg_room", function(v)
    v = math.floor(tonumber(v) or 0)
    local w, h = math.floor(v / 4096), v % 4096
    if w < 200 or h < 200 or (w == room.w and h == room.h) then return end
    room.w, room.h = w, h
    drop_gestures(false)
    W.clear(hist)
    load()
end)

-- ── What is playing ──
local np = { key = nil, data = nil, t = 0, at = os.time(), rate = 1, len = 0, sung = nil, art = nil, art_path = nil }
local function set_cover(path)
    text.np_cover_path = path or ""
    fact.np_cover_on = path ~= nil and path ~= ""
end
local function show_lyric()
    local a, b, c, at = P.lyric_lines(np.data, np.t, 0)
    if at == np.sung then return end
    np.sung = at
    text.np_prev, text.np_line, text.np_next = a, b, c
    fact.np_sung = at > 0 and b ~= ""
    -- the new line fades in
    fact.np_line_in = 0
    after(40, function() fact.np_line_in = 1 end)
end
local function lyrics_for(m)
    local artist, title = tostring(m.artist or ""), tostring(m.title or "")
    local key = "remote:" .. artist .. "\t" .. title
    if key == np.key then return end
    np.key, np.data, np.sung = key, nil, nil
    show_lyric()
    if artist == "" or title == "" then return end
    local path = coverart.path(type(m.url) == "string" and m.url or "")
    fetch(key, artist, title, tostring(m.album or ""), np.len, path, function(raw, _)
        if np.key ~= key then return end
        if raw == "none" or raw == "instrumental" or raw == "" then np.data = nil
        else np.data = P.parse_lrc(raw) end
        show_lyric()
    end)
end
local function show_progress()
    fact.np_progress = np.len > 0 and math.min(1, np.t / np.len) or 0
    fact.np_arm_at = P.arm(fact.np_progress, playing and "playing" or (fact.np_has and "paused" or "stopped"))
end

pcall(sys.watch, "media", function(m)
    local has = type(m) == "table" and type(m.title) == "string" and m.title ~= ""
    local was = playing
    playing = has and m.playing == true
    fact.np_has, fact.np_playing = has, playing
    if not has then
        text.np_title, text.np_artist = "", ""
        np.key, np.data, np.len, np.t = nil, nil, 0, 0
        set_cover(nil)
    else
        text.np_title, text.np_artist = m.title, tostring(m.artist or "")
        np.t, np.at, np.rate = tonumber(m.position) or 0, os.time(), tonumber(m.rate) or 1
        np.len = tonumber(m.length) or 0
        lyrics_for(m)
        local art = type(m.art) == "string" and m.art or ""
        local path = coverart.path(art)
        if path then set_cover(path)
        elseif coverart.remote(art) then
            -- fetched once per picture; a slow answer for the last song is not shown on this one
            if np.art == art then
                if np.art_path then set_cover(np.art_path) end
            else
                np.art, np.art_path = art, nil
                local dest = COVERS .. "/remote-" .. P.hash(art) .. ".img"
                run("curl", { "-fsSL", "--max-time", "8", "-o", dest, art }, function(_, code)
                    if code == 0 and np.art == art then np.art_path = dest; set_cover(dest) end
                end)
            end
        else set_cover(nil) end
    end
    show_progress()
    show_lyric()
    if was ~= playing then publish() end
end)
-- the song's clock between the service's readings, in quarter seconds
every(250, function()
    if not playing then return end
    np.t = np.t + 0.25 * np.rate
    show_progress()
    if np.data and np.data.synced then show_lyric() end
end)

-- ── The hands (calm until touched) ──
-- Pointed at: the hands come at once and stay 1.2 s after the pointer leaves.
local away_seq = {}
on("wg_hov", function(v)
    v = math.floor(tonumber(v) or 0)
    local k, on_it = math.floor(v / 10), v % 10 == 1
    if k < 0 or k >= W.MAX then return end
    away_seq[k] = (away_seq[k] or 0) + 1
    if on_it then
        hovered[k] = true
        fact["hl" .. k] = 1
        unsettle()
    else
        hovered[k] = nil
        local mine = away_seq[k]
        after(1200, function() if away_seq[k] == mine then fact["hl" .. k] = 0; unsettle() end end)
    end
end)
on("wg_ctl", function(v)
    local c = math.floor(tonumber(v) or 0) % 10
    pcall(sys.call, ({ [0] = "media.previous", [1] = "media.toggle", [2] = "media.next" })[c] or "media.toggle")
end)
on("wg_seek", function(v)
    local f = (math.floor(tonumber(v) or 0) % 1000) / 999
    if np.len <= 0 then return end
    np.t = f * np.len
    run("playerctl", { "position", string.format("%.1f", np.t) })
    show_progress(); show_lyric()
end)
local volume = nil
pcall(sys.watch, "audio", function(a) if type(a) == "table" then volume = tonumber(a.volume) end end)
on("wg_vol", function(v)
    if not volume then return end
    for _, w in ipairs(doc.widgets) do
        if w.kind == "nowplaying" and W.find(doc, w.id) == math.floor((tonumber(v) or 0) / 10) + 1 then
            if (w.options or {}).scroll_volume == false then return end
        end
    end
    volume = math.max(0, math.min(1, volume + (math.floor(tonumber(v) or 0) % 10 == 1 and 0.05 or -0.05)))
    pcall(sys.call, "audio.volume", volume)
end)
on("wg_open", function() run("mooi", { "player" }) end)

-- ── Edit mode: carry, pull, choose, add (lib/widgets works it out; saved once per gesture) ──
fact.wg_snap = true
local function panel()
    local k = fact.wg_sel
    local w = doc.widgets[k + 1]
    if not w then fact.wg_sel = -1; return end
    if panel_at then fact.wg_px, fact.wg_py = panel_at[1], panel_at[2]
    else fact.wg_px, fact.wg_py = W.panel_spot(w, 320, w.kind == "visualiser" and 530 or 406, room) end
    local o = w.options or {}
    fact.wg_sk = w.kind == "visualiser" and 1 or 0
    fact.wg_sl = W.LAYOUT_INDEX[w.layout] or 0
    fact.wg_sm = W.MODE_INDEX[w.mode] or 0
    fact.wg_si = W.IDLE_INDEX[w.idle] or 1
    fact.wg_o3, fact.wg_o4, fact.wg_o5, fact.wg_o6 = o.lyrics ~= false, o.progress ~= false, o.plate == true, o.scroll_volume ~= false
    fact.wg_o7, fact.wg_o8 = o.peaks ~= false, o.reflection == true
    fact.wg_og = tonumber(o.glow) or 0
    fact.wg_ob, fact.wg_ogap, fact.wg_osm = tonumber(o.bars) or 64, tonumber(o.gap) or 0.3, tonumber(o.smooth) or 0.5
    fact.wg_otx, fact.wg_oop, fact.wg_olk = tonumber(o.text) or 1, w.opacity or 1, w.locked == true
    text.wg_readout = string.format("%d × %d · %d, %d", w.w, w.h, w.x, w.y)
    local L = W.LAYOUTS[W.layout_of(w)]
    local maxw = L.max and L.max[1] or room.w
    fact.wg_osc = maxw > L.min[1] and math.max(0, math.min(1, (w.w - L.min[1]) / (maxw - L.min[1]))) or 0
end
-- the selection's count and the panel's widget (the last one chosen)
show_selection = function()
    local keep = {}
    for _, id in ipairs(selected) do if W.find(doc, id) then keep[#keep + 1] = id end end
    selected = keep
    fact.wg_nsel = #selected
    if #selected == 0 then fact.wg_sel = -1
    else fact.wg_sel = W.find(doc, selected[#selected]) - 1 end
    publish()
    if fact.wg_sel >= 0 then panel() end
end
local function commit(d)
    doc = d
    save()
    show_selection()
end
-- every change the editor makes goes through here, so it can be undone
local function change(d, note)
    if note and note ~= "" then text.wg_note = note; after(2500, function() if text.wg_note == note then text.wg_note = "" end end) end
    if W.same_doc(W.encode(d), W.encode(doc)) then return end
    W.push(hist, doc)
    commit(d)
end
local function skipped_note(n) return n > 0 and string.format("%d LOCKED, LEFT WHERE %s", n, n == 1 and "IT WAS" or "THEY WERE") or "" end
local function choose(ids) selected = ids; show_selection() end

on("wg_edit", function(v)
    local on_it = math.floor(tonumber(v) or 0) == 1
    fact.editing = on_it
    if not on_it then selected = {}; drop_gestures(true); publish() end
    show_selection()
end)
-- slot · 10 + 0 choose only this · 1 add or take away (a right press) · 2 none
on("wg_sel", function(v)
    v = math.floor(tonumber(v) or 0)
    local k, op = math.floor(v / 10), v % 10
    local w = doc.widgets[k + 1]
    if op == 2 or not w then choose({}); return end
    if op == 0 then
        if not is_sel(w.id) then choose({ w.id }) else choose(selected) end
    else
        local out, had = {}, false
        for _, id in ipairs(selected) do if id == w.id then had = true else out[#out + 1] = id end end
        if not had then out[#out + 1] = w.id end
        choose(out)
    end
end)
on("wg_pick", function(v) local w = doc.widgets[math.floor(tonumber(v) or -1) + 1]; if w then choose({ w.id }) end end)
-- the marquee: where it started, then where it ended (px, x · 4096 + y)
on("wg_marq0", function(v) v = math.floor(tonumber(v) or 0); marq0 = { math.floor(v / 4096), v % 4096 } end)
on("wg_marq1", function(v)
    if not marq0 then return end
    v = math.floor(tonumber(v) or 0)
    local x1, y1 = math.floor(v / 4096), v % 4096
    choose(W.ids_of(doc, W.marquee(doc, marq0[1], marq0[2], x1, y1)))
    marq0 = nil
end)
-- carrying: the one held snaps; the rest of the selection comes along by as much
on("wg_drag", function(v)
    local k, gx, gy = W.unpack(v)
    local w = doc.widgets[k + 1]
    if not w or w.locked then return end
    local x, y, ww, hh, g
    if fact.wg_snap then x, y, ww, hh, g = W.snap(doc, k + 1, gx * W.GRID, gy * W.GRID, w.w, w.h, room)
    else
        local r = W.clamp_rect({ x = gx * W.GRID, y = gy * W.GRID, w = w.w, h = w.h }, room)
        x, y, ww, hh, g = r.x, r.y, r.w, r.h, {}
    end
    pending = { k = k, x = x, y = y, w = ww, h = hh }
    fact.wg_dksel = is_sel(w.id)
    fact.wg_sx, fact.wg_sy, fact.wg_sw, fact.wg_sh = x, y, ww, hh
    fact.wg_gvx, fact.wg_ghy = g.vx or -1, g.hy or -1
    text.wg_readout = string.format("%d × %d · %d, %d", ww, hh, x, y)
end)
on("wg_drop", function(v)
    local k = math.floor(tonumber(v) or -1)
    local p = pending
    pending = nil
    fact.wg_gvx, fact.wg_ghy = -1, -1
    local w = doc.widgets[k + 1]
    if not p or p.k ~= k or not w then return end
    local dx, dy = p.x - w.x, p.y - w.y
    local d = W.set_rect(doc, w.id, p.x, p.y, p.w, p.h, room)
    local others = {}
    if is_sel(w.id) then for _, id in ipairs(selected) do if id ~= w.id then others[#others + 1] = id end end end
    local sk = 0
    if #others > 0 then d, sk = W.nudge(d, others, dx, dy, room) end
    if not is_sel(w.id) then selected = { w.id } end
    change(d, skipped_note(sk))
end)
-- a handle held (slot · 8 + handle 0 … 7), pulled (dx + 2048) · 4096 + (dy + 2048), let go
on("wg_hgrab", function(v)
    v = math.floor(tonumber(v) or 0)
    local w = doc.widgets[math.floor(v / 8) + 1]
    if not w or w.locked then grab = nil; return end
    grab = { id = w.id, handle = v % 8, before = doc }
    if not is_sel(w.id) then selected = { w.id } end
    fact.wg_rk = math.floor(v / 8)
end)
on("wg_hmove", function(v)
    if not grab then return end
    v = math.floor(tonumber(v) or 0)
    local dx, dy = math.floor(v / 4096) - 2048, v % 4096 - 2048
    local x, y, w, h = W.resize_from(grab.before, grab.id, grab.handle, dx, dy, room)
    -- drawn at its new size as it is pulled (saved when let go)
    doc = W.set_rect(grab.before, grab.id, x, y, w, h, room)
    fact.wg_sx, fact.wg_sy, fact.wg_sw, fact.wg_sh = x, y, w, h
    publish()
    text.wg_readout = string.format("%d × %d · %d, %d", w, h, x, y)
end)
on("wg_hdrop", function()
    if not grab then return end
    local before = grab.before
    grab = nil
    fact.wg_rk = -1
    local now = doc
    doc = before
    change(now)
end)
on("wg_add", function(v)
    local vis = math.floor(tonumber(v) or 0) == 1
    local d, id = W.add(doc, vis and "visualiser" or "nowplaying", room)
    if not id then
        local full = #doc.widgets >= W.MAX
        change(doc, full and "EIGHT WIDGETS IS THE MOST" or "THREE VISUALISERS IS THE MOST")
        return
    end
    selected = { id }
    change(d)
end)
local function remove_selected()
    local d = doc
    for _, id in ipairs(selected) do
        local _, w = W.find(d, id)
        if w and not w.locked then d = W.remove(d, id) end
    end
    change(d)
end
local function duplicate_selected()
    local d, made = doc, {}
    for _, id in ipairs(selected) do
        local id2
        d, id2 = W.duplicate(d, id, room)
        if id2 then made[#made + 1] = id2 end
    end
    if #made > 0 then selected = made end
    change(d)
end
local function toggle_lock()
    local any_unlocked = false
    for _, id in ipairs(selected) do local _, w = W.find(doc, id); if w and not w.locked then any_unlocked = true end end
    local d = doc
    for _, id in ipairs(selected) do d = W.set_field(d, id, "locked", any_unlocked) end
    change(d)
end
local function undo_redo(back)
    local d = back and W.undo(hist, doc) or W.redo(hist, doc)
    if d then commit(d) end
end
-- the keys while editing: 1-4 ← → ↑ ↓ by 8 px · 5-8 by 1 px · 9 delete · 10 duplicate · 11 undo ·
-- 12 redo · 13 select all · 14 lock · 15 forward · 16 backward
on("wg_key", function(v)
    local c = math.floor(tonumber(v) or 0)
    if c >= 1 and c <= 8 then
        local step = c <= 4 and W.GRID or 1
        local dir = (c - 1) % 4
        local dx = ({ [0] = -step, step, 0, 0 })[dir]
        local dy = ({ [0] = 0, 0, -step, step })[dir]
        local d, sk = W.nudge(doc, selected, dx, dy, room)
        change(d, skipped_note(sk))
    elseif c == 9 then remove_selected()
    elseif c == 10 then duplicate_selected()
    elseif c == 11 then undo_redo(true)
    elseif c == 12 then undo_redo(false)
    elseif c == 13 then
        local all = {}
        for _, w in ipairs(doc.widgets) do all[#all + 1] = w.id end
        choose(all)
    elseif c == 14 then toggle_lock()
    elseif c == 15 then change(W.raise(doc, selected, "forward"))
    elseif c == 16 then change(W.raise(doc, selected, "backward")) end
end)
-- the toolbar: 1-6 align left / centre / right / top / middle / bottom · 7-8 distribute · 9-10 match
-- width / height · 11 to the front · 12 to the back · 13 lock · 14 snapping on or off
local ALIGN = { "left", "centre", "right", "top", "middle", "bottom" }
on("wg_tool", function(v)
    local c = math.floor(tonumber(v) or 0)
    local d, sk = doc, 0
    if c >= 1 and c <= 6 then d, sk = W.align(doc, selected, ALIGN[c], room)
    elseif c == 7 or c == 8 then d, sk = W.distribute(doc, selected, c == 7 and "h" or "v", room)
    elseif c == 9 or c == 10 then d, sk = W.match(doc, selected, c == 9 and "w" or "h", room)
    elseif c == 11 then d = W.raise(doc, selected, "front")
    elseif c == 12 then d = W.raise(doc, selected, "back")
    elseif c == 13 then toggle_lock(); return
    elseif c == 14 then fact.wg_snap = not fact.wg_snap; return end
    change(d, skipped_note(sk))
end)
-- the panel: slot · 1000 + what · 100 + value (what: 1 layout or mode · 2 at rest · 3-6 lyric line,
-- progress, plate, wheel volume · 7 peaks · 8 reflection · 9 duplicate (1) / remove (2) / lock (3))
on("wg_opt", function(v)
    v = math.floor(tonumber(v) or 0)
    local k, what, val = math.floor(v / 1000), math.floor((v % 1000) / 100), v % 100
    local w = doc.widgets[k + 1]
    if not w then return end
    local d = doc
    if what == 1 then
        if w.kind == "visualiser" then d = W.set_mode(doc, w.id, W.MODES[val + 1])
        else d = W.set_layout(doc, w.id, W.NP_LAYOUTS[val + 1], room) end
    elseif what == 2 then d = W.set_idle(doc, w.id, W.IDLES[val + 1])
    elseif what >= 3 and what <= 8 then
        d = W.set_option(doc, w.id, ({ [3] = "lyrics", [4] = "progress", [5] = "plate", [6] = "scroll_volume", [7] = "peaks", [8] = "reflection" })[what], val == 1)
    elseif what == 9 and val == 1 then selected = { w.id }; duplicate_selected(); return
    elseif what == 9 and val == 2 then selected = { w.id }; remove_selected(); return
    elseif what == 9 and val == 3 then selected = { w.id }; toggle_lock(); return
    end
    change(d)
end)
-- a slider (slot · 10000 + which · 1000 + value 0 … 999), live while held; `done` saves it
-- which: 1 opacity · 2 bars · 3 glow · 4 gap · 5 smoothing · 6 text size · 7 scale
local function slider_doc(base, w, which, f)
    if which == 1 then return W.set_field(base, w.id, "opacity", 0.3 + 0.7 * f)
    elseif which == 2 then return W.set_option(base, w.id, "bars", 16 + f * 112)
    elseif which == 3 then return W.set_option(base, w.id, "glow", f)
    elseif which == 4 then return W.set_option(base, w.id, "gap", f * 0.6)
    elseif which == 5 then return W.set_option(base, w.id, "smooth", f)
    elseif which == 6 then return W.set_option(base, w.id, "text", 0.8 + f * 0.6)
    elseif which == 7 then
        -- scale round the centre, from the layout's least to its most
        local L = W.LAYOUTS[W.layout_of(w)]
        local maxw = L.max and L.max[1] or room.w
        local nw = L.min[1] + (maxw - L.min[1]) * f
        local nh = w.h * nw / w.w
        local cw, ch = W.clamp_size(w, nw, nh)
        return W.set_rect(base, w.id, w.x + (w.w - cw) / 2, w.y + (w.h - ch) / 2, cw, ch, room)
    end
    return base
end
on("wg_slide", function(v)
    v = math.floor(tonumber(v) or 0)
    local k, which, val = math.floor(v / 10000), math.floor((v % 10000) / 1000), v % 1000
    local w = (slide and slide.before or doc).widgets[k + 1]
    if not w then return end
    if not slide then slide = { before = doc } end
    doc = slider_doc(slide.before, w, which, val / 999)
    publish()
    panel()
end)
on("wg_slid", function()
    if not slide then return end
    local now = doc
    doc = slide.before
    slide = nil
    change(now)
end)
-- the panel's place, when its header is dragged (x · 4096 + y)
on("wg_pmove", function(v)
    v = math.floor(tonumber(v) or 0)
    panel_at = { math.max(0, math.min(room.w - 320, math.floor(v / 4096))), math.max(0, math.min(room.h - 60, v % 4096)) }
    fact.wg_px, fact.wg_py = panel_at[1], panel_at[2]
end)

-- ── The visualiser's feed (the bar's one cava) ──
local function any_viz()
    for _, w in ipairs(doc.widgets) do if w.kind == "visualiser" then return true end end
    return false
end
local viz_seq, viz_at, last_beat = nil, 0, 0
local rings = { { 0, 0 }, { 0, 0 }, { 0, 0 }, { 0, 0 } }
-- Each visualiser slot's own bars (D138): smoothed levels and peak dots, as many as its `bars`.
local SLOTS = { "vzA", "vzB", "vzC" }
local lanes = { {}, {}, {} }            -- { lev = {}, pk = {}, hold = {} }
local frame_n = 0
local scope_hist = { {}, {}, {} }
local function hush()
    for i = 0, 15 do fact["vb" .. i] = 0.03 end
    for i = 0, 31 do fact["vs" .. i] = 0.03 end
    fact.np_beat = 0
    for k = 1, 4 do rings[k] = { 0, 0 }; fact["rp_a" .. (k - 1)] = 0 end
    for k = 1, 3 do lanes[k] = {}; model[SLOTS[k]] = {} end
end
-- the visualisers that get bars of their own: lanes 1…3 by list order (three at most)
local function viz_slots()
    local out, n = {}, 0
    for _, w in ipairs(doc.widgets) do
        if w.kind == "visualiser" then
            n = n + 1
            if n <= 3 then out[n] = w end
        end
    end
    return out
end
local function feed_lane(k, w, bands)
    local o = w.options or {}
    local n = math.floor(tonumber(o.bars) or 64)
    local target = vizfeed.resample(bands, n)
    local L = lanes[k]
    if L.n ~= n then L.n, L.lev, L.pk, L.hold = n, {}, {}, {} end
    -- rise at once, fall by `smooth` (0 quick … 1 slow); peaks hold 12 frames (400 ms), then fall 1.2 a second
    local fall = 0.02 + (1 - (tonumber(o.smooth) or 0.5)) * 0.16
    local now = frame_n
    local rows = {}
    for i = 1, n do
        local v = math.max(target[i], (L.lev[i] or 0) - fall)
        L.lev[i] = v
        local p = L.pk[i] or 0
        if v >= p then p = v; L.hold[i] = now + 12
        elseif now > (L.hold[i] or 0) then p = math.max(v, p - 0.04) end
        L.pk[i] = p
        rows[i] = { v = v, pk = p }
    end
    model[SLOTS[k]] = rows
end
local function take_viz()
    local t, wide
    local ok2, raw2 = pcall(sys.ask, "files.read", vizfeed.FILE_V2)
    if ok2 and type(raw2) == "string" then
        t = vizfeed.decode_v2(raw2)
        if t and not vizfeed.newer(viz_seq, t.seq) then t = nil end
        wide = t ~= nil
    end
    if not t then
        local ok, raw = pcall(sys.ask, "files.read", vizfeed.FILE)
        if not ok or type(raw) ~= "string" then return end
        t = vizfeed.decode(raw)
        if not t or not vizfeed.newer(viz_seq, t.seq) then return end
    end
    viz_seq, viz_at = t.seq, os.time()
    if not t.playing then hush(); return end
    local b = vizfeed.resample(t.bands, 16)
    for i = 0, 15 do fact["vb" .. i] = b[i + 1] end
    local s32 = vizfeed.resample(t.bands, 32)
    for i = 0, 31 do fact["vs" .. i] = s32[i + 1] end
    frame_n = frame_n + 1
    local slots = viz_slots()
    local scope = false
    for k, w in ipairs(slots) do
        feed_lane(k, w, t.bands)
        if w.mode == "scope" then scope = true end
    end
    -- the scope's afterimages: the last three frames of 24 bands, one every other frame
    if scope and frame_n % 2 == 0 then
        scope_hist[3], scope_hist[2] = scope_hist[2], scope_hist[1]
        scope_hist[1] = vizfeed.resample(t.bands, 24)
        for h = 1, 3 do
            local f = scope_hist[h]
            for i = 0, 23 do fact["so" .. (h - 1) .. "_" .. i] = f[i + 1] or 0.03 end
        end
    end
    local beat = (tonumber(t.beat) or 0) > 0.9 and last_beat <= 0.9
    last_beat = tonumber(t.beat) or 0
    if beat then
        fact.np_beat = 1
        after(60, function() fact.np_beat = 0 end)
        table.remove(rings, 1)
        rings[4] = { 0.02, math.min(1, 0.5 + (b[2] or 0)) }
    end
    fact.viz_wide = wide == true
end
every(33, function()
    if not (playing and any_viz() and not fact.viz_still) then return end
    take_viz()
    for k = 1, 4 do
        local r = rings[k]
        if r[2] > 0.02 then
            r[1] = r[1] + 0.025; r[2] = r[2] * 0.96
            fact["rp_r" .. (k - 1)], fact["rp_a" .. (k - 1)] = math.min(1.2, r[1]), r[2]
        elseif fact["rp_a" .. (k - 1)] ~= 0 then fact["rp_a" .. (k - 1)] = 0 end
    end
end)
-- The bar runs the one cava and writes the feed for a few seconds after each ask (D118).
every(3000, function()
    if playing and any_viz() and not fact.viz_still then run("pleamar", { "--say", "mooi", "emit feed_want" }) end
end)
every(400, function()
    if viz_seq and not vizfeed.fresh(viz_at * 1000, os.time() * 1000) then viz_seq, viz_at = nil, 0; hush() end
end)
