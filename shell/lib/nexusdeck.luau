-- The Nexus Deck (D102): its geometry on any edge, the workspaces as miniatures, what is waiting,
-- the window you are in, and scenes (whole setups switched at once). Pure, so tests/unit runs it;
-- shell/mooi-nexus.luau reads the system and hands this what it found.

local M = {}

M.EDGES = { "bottom", "top", "left", "right" }
M.STRIP_MAX = 1900     -- the deck's widest along the top or the bottom
M.COLUMN_W = 404       -- its width along a side
M.GAP = 10             -- from the screen's edge
M.HEAD = 38            -- the strip's top row: scenes, what is waiting, who you are
M.BODY = 214           -- and the parts' row under it
M.CHIP_W, M.CHIP_H, M.CHIP_GAP = 76, 24, 4
M.SPINE_W = 58         -- the spine's tabs on the right edge (D100), kept clear on that side
M.TILE_GAP = 10        -- between the workspaces' miniatures
M.WAIT_MIN = 260       -- what is waiting never gets less than this along the head

-- The deck's parts: what each is called, its width along a strip (the mixer's follows its faders,
-- the workspaces take what is left), its height down a column, and which give way first when
-- there is no room (the highest number first). Every one can be moved and hidden (✎ on the deck).
M.PARTS = {
    window = { word = "This window", w = 280, h = 156, keep = 3 },
    spaces = { word = "Workspaces", min = 300, keep = 1 },
    mixer = { word = "Mixer", h = 184, keep = 4 },
    quick = { word = "Quick settings", w = 404, h = 196, keep = 2 },
    music = { word = "Music", w = 284, h = 118, keep = 5 },
    machine = { word = "Machine", w = 236, h = 140, keep = 6 },
    today = { word = "Today", w = 222, h = 134, keep = 7 },
}
M.ORDER = { "window", "spaces", "mixer", "quick", "music", "machine", "today" }

local function edge_of(e)
    for _, x in ipairs(M.EDGES) do if x == e then return x end end
    return "bottom"
end
M.edge_of = edge_of

local function rect(x, y, w, h) return { x = math.floor(x + 0.5), y = math.floor(y + 0.5), w = math.floor(w + 0.5), h = math.floor(h + 0.5) } end

-- An order of parts as it can be trusted: known ids once each, in the order given, the rest after.
function M.clean_parts(list)
    local out, seen = {}, {}
    for _, id in ipairs(type(list) == "table" and list or {}) do
        if M.PARTS[id] and not seen[id] then seen[id] = true; out[#out + 1] = id end
    end
    for _, id in ipairs(M.ORDER) do if not seen[id] then out[#out + 1] = id end end
    return out
end

-- `id` moved to sit at place `to` among the parts that are shown (`hidden` stay where they were).
function M.move(order, id, to, hidden)
    hidden = hidden or {}
    local shown, rest = {}, {}
    for _, x in ipairs(order) do
        if x ~= id then
            if hidden[x] then rest[#rest + 1] = x else shown[#shown + 1] = x end
        end
    end
    to = math.max(1, math.min(#shown + 1, math.floor(tonumber(to) or 1)))
    table.insert(shown, to, id)
    for _, x in ipairs(rest) do shown[#shown + 1] = x end
    return shown
end

local function mixer_w(n) return 34 + math.max(3, math.min(6, tonumber(n) or 4)) * 36 end

-- Where the deck sits, where its head's bays are and where each part is, inside a screen `sw` × `sh`
-- whose top `top` px the bar keeps. `opts`: `parts` (the order), `hidden` (a set), `faders` (how many
-- the mixer has), `tiles` and `aspect` (the workspaces' miniatures), `spine` (keep the right edge's
-- tabs clear), `scenes` (chips, Save among them). Parts that do not fit give way, the least kept
-- first: they are listed in `d.dropped`. Rects are the deck's.
function M.layout(edge, sw, sh, top, opts)
    edge, opts = edge_of(edge), opts or {}
    sw, sh, top = tonumber(sw) or 1920, tonumber(sh) or 1080, tonumber(top) or 0
    local chips = math.max(1, tonumber(opts.scenes) or 5)
    local hidden = opts.hidden or {}
    local order = M.clean_parts(opts.parts)
    local aspect = (tonumber(opts.aspect) or 0) > 0 and opts.aspect or 16 / 9
    local ntiles = math.max(1, tonumber(opts.tiles) or 2)
    local d = { edge = edge, vertical = edge == "left" or edge == "right", bays = {}, parts = {}, dropped = {} }
    local b = d.bays
    local shown = {}
    for _, id in ipairs(order) do if not hidden[id] then shown[#shown + 1] = id end end
    local function drop_least(total, room, size)
        while total > room and #shown > 1 do
            local worst, at = nil, nil
            for i, id in ipairs(shown) do
                if id ~= "spaces" and (not worst or M.PARTS[id].keep > M.PARTS[worst].keep) then worst, at = id, i end
            end
            if not at then break end
            table.remove(shown, at)
            d.dropped[#d.dropped + 1] = worst
            total = total - size(worst)
        end
    end
    if not d.vertical then
        d.h = M.HEAD + M.BODY
        local room = math.min(sw - 2 * M.GAP, M.STRIP_MAX)
        local function width(id)
            if id == "mixer" then return mixer_w(opts.faders) end
            if id == "spaces" then return M.PARTS.spaces.min end
            return M.PARTS[id].w
        end
        local total = 0
        for _, id in ipairs(shown) do total = total + width(id) end
        drop_least(total, room, width)
        total = 0
        for _, id in ipairs(shown) do total = total + width(id) end
        -- the workspaces as wide as their miniatures want, in what is left
        local spaces_w = 0
        for _, id in ipairs(shown) do
            if id == "spaces" then
                local th = M.BODY - 30 - 10 - 16
                local want = 28 + (ntiles) * (th * aspect + M.TILE_GAP) - M.TILE_GAP
                spaces_w = math.max(M.PARTS.spaces.min, math.min(want, room - total + M.PARTS.spaces.min))
                total = total - M.PARTS.spaces.min + spaces_w
            end
        end
        local sc_w = 70 + chips * (M.CHIP_W + M.CHIP_GAP)
        local id_w = 300
        d.w = math.max(total, sc_w + M.WAIT_MIN + id_w)
        d.w = math.min(d.w, room)
        d.x = (sw - d.w) / 2
        d.y = edge == "top" and top + 6 or sh - d.h - M.GAP
        b.scenes = rect(0, 0, sc_w, M.HEAD)
        b.ident = rect(d.w - id_w, 0, id_w, M.HEAD)
        b.wait = rect(sc_w, 0, d.w - sc_w - id_w, M.HEAD)
        -- the parts side by side; any room over is shared out so they meet the deck's edges
        local extra = (d.w - total) / math.max(1, #shown)
        local x = 0
        for _, id in ipairs(shown) do
            local w = (id == "spaces" and spaces_w or width(id)) + extra
            d.parts[#d.parts + 1] = { id = id, x = math.floor(x + 0.5), y = M.HEAD, w = math.floor(w + 0.5), h = M.BODY }
            x = x + w
        end
    else
        d.w = M.COLUMN_W
        d.x = edge == "left" and M.GAP or sw - d.w - M.GAP - (opts.spine and M.SPINE_W or 0)
        d.y = top + 6
        local room = sh - d.y - M.GAP
        local per_row = math.floor((d.w - 28 + M.CHIP_GAP) / (M.CHIP_W + M.CHIP_GAP))
        local sc_h = 30 + math.ceil(chips / per_row) * (M.CHIP_H + M.CHIP_GAP) + 6
        b.ident = rect(0, 0, d.w, 44)
        b.scenes = rect(0, 44, d.w, sc_h)
        b.wait = rect(0, 44 + sc_h, d.w, 112)
        local head = 44 + sc_h + 112
        local tw = (d.w - 28 - M.TILE_GAP) / 2
        local spaces_h = 30 + math.ceil(ntiles / 2) * (tw / aspect + 16 + M.TILE_GAP) + 10
        local function height(id) return id == "spaces" and spaces_h or M.PARTS[id].h end
        local total = head
        for _, id in ipairs(shown) do total = total + height(id) end
        drop_least(total, room, height)
        local y = head
        for _, id in ipairs(shown) do
            local h = height(id)
            d.parts[#d.parts + 1] = { id = id, x = 0, y = math.floor(y + 0.5), w = d.w, h = math.floor(h + 0.5) }
            y = y + h
        end
        d.h = math.min(room, y)
    end
    for _, part in ipairs(d.parts) do d.bays[part.id] = part end
    d.x, d.y, d.w, d.h = math.floor(d.x + 0.5), math.floor(d.y + 0.5), math.floor(d.w + 0.5), math.floor(d.h + 0.5)
    -- the way it slides in from (and what grows out of it goes): away from its edge
    d.out_x = edge == "left" and -1 or (edge == "right" and 1 or 0)
    d.out_y = edge == "top" and -1 or (edge == "bottom" and 1 or 0)
    return d
end

-- Which place among the shown parts a part let go at `pos` (along the deck: x on a strip, y down a
-- column, in the deck's coordinates) takes: before the first part whose middle is past it.
function M.place_at(d, pos)
    local n = 1
    for _, part in ipairs(d.parts) do
        local mid = d.vertical and (part.y + part.h / 2) or (part.x + part.w / 2)
        if pos > mid then n = n + 1 end
    end
    return n
end

-- The scene chips' places in their bay: one row along a strip, wrapped rows down a column.
function M.chips(n, bay, vertical)
    local out = {}
    local x0, y0 = vertical and 16 or 68, vertical and 30 or 6
    local per_row = vertical and math.max(1, math.floor((bay.w - 28 + M.CHIP_GAP) / (M.CHIP_W + M.CHIP_GAP))) or n
    for i = 0, n - 1 do
        local r, c = math.floor(i / per_row), i % per_row
        out[#out + 1] = { x = x0 + c * (M.CHIP_W + M.CHIP_GAP), y = y0 + r * (M.CHIP_H + M.CHIP_GAP), w = M.CHIP_W, h = M.CHIP_H }
    end
    return out
end

-- Where a panel `pw` × `ph` that grows out of the deck goes: beside the deck on its open side,
-- level with `a` (a rect in the deck), kept on the screen `sw` × `sh` below the bar's `top`.
function M.grow(d, a, pw, ph, sw, sh, top)
    local function clamp(v, lo, hi) return math.max(lo, math.min(hi, v)) end
    top = (tonumber(top) or 0) + 6
    local ax, ay = d.x + a.x + a.w / 2, d.y + a.y + a.h / 2
    local x, y
    if d.edge == "bottom" or d.edge == "top" then
        x = clamp(ax - pw / 2, M.GAP, sw - pw - M.GAP)
        y = d.edge == "bottom" and d.y - ph - M.GAP or d.y + d.h + M.GAP
    else
        y = clamp(ay - ph / 2, top, sh - ph - M.GAP)
        x = d.edge == "left" and d.x + d.w + M.GAP or d.x - pw - M.GAP
    end
    return math.floor(x + 0.5), math.floor(y + 0.5)
end

-- ── The workspaces as miniatures ─────────────────────────────

-- The workspaces of the monitor `mon` (hyprctl -j workspaces), numbered ones only, in order, the
-- active one always among them even when it is empty.
function M.spaces(list, mon, active)
    local out, seen = {}, {}
    for _, w in ipairs(type(list) == "table" and list or {}) do
        local id = tonumber(w.id)
        if id and id > 0 and (mon == nil or w.monitor == mon) and not seen[id] then
            seen[id] = true
            out[#out + 1] = { id = id, name = tostring(w.name or id), windows = tonumber(w.windows) or 0 }
        end
    end
    active = tonumber(active)
    if active and active > 0 and not seen[active] then out[#out + 1] = { id = active, name = tostring(active), windows = 0 } end
    table.sort(out, function(a, b) return a.id < b.id end)
    for _, s in ipairs(out) do s.active = s.id == active end
    return out
end

-- The first workspace number not taken: where "+" goes.
function M.free_space(spaces)
    local taken = {}
    for _, s in ipairs(spaces or {}) do taken[s.id] = true end
    for id = 1, 99 do if not taken[id] then return id end end
    return 1
end

-- The tiles' places in the workspaces bay, one more for "+": a row along a strip, columns down a
-- column, each the monitor's shape (`aspect` = width / height), as large as the room allows.
function M.tiles(n, bay, vertical, aspect)
    aspect = (tonumber(aspect) or 0) > 0 and aspect or 16 / 9
    local count = n + 1
    local pad_x, top, bottom = 14, 30, 10
    local room_w, room_h = bay.w - 2 * pad_x, bay.h - top - bottom
    local out = {}
    if not vertical then
        local h = room_h - 16                    -- a line under each for its name
        local w = h * aspect
        local fit = (room_w - M.TILE_GAP * (count - 1)) / count
        if w > fit then w = fit; h = w / aspect end
        for i = 0, count - 1 do
            out[#out + 1] = rect(pad_x + i * (w + M.TILE_GAP), top + (room_h - 16 - h), w, h)
        end
    else
        local cols = 2
        local w, h, rows
        repeat
            w = (room_w - M.TILE_GAP * (cols - 1)) / cols
            h = w / aspect
            rows = math.ceil(count / cols)
            if rows * (h + 16 + M.TILE_GAP) - M.TILE_GAP > room_h then cols = cols + 1 end
        until rows * (h + 16 + M.TILE_GAP) - M.TILE_GAP <= room_h or cols > 4
        for i = 0, count - 1 do
            local r, c = math.floor(i / cols), i % cols
            out[#out + 1] = rect(pad_x + c * (w + M.TILE_GAP), top + r * (h + 16 + M.TILE_GAP), w, h)
        end
    end
    return out
end

-- Every window on the monitor `mon` (hyprctl -j clients, monitors), as a part of its screen
-- (0..1 each way), so a tile of any size can draw it. Mapped and not hidden; floating ones last,
-- so they are drawn over the tiled ones.
function M.windows(clients, mon)
    local out = {}
    if type(clients) ~= "table" or type(mon) ~= "table" then return out end
    local mx, my = tonumber(mon.x) or 0, tonumber(mon.y) or 0
    local scale = tonumber(mon.scale) or 1
    local mw, mh = (tonumber(mon.width) or 1920) / scale, (tonumber(mon.height) or 1080) / scale
    for _, c in ipairs(clients) do
        local ws = type(c.workspace) == "table" and tonumber(c.workspace.id) or nil
        if c.mapped ~= false and c.hidden ~= true and ws and ws > 0 and c.monitor == mon.id
           and type(c.at) == "table" and type(c.size) == "table" then
            local function clamp(v) return math.max(0, math.min(1, v)) end
            out[#out + 1] = {
                ws = ws, address = tostring(c.address or ""), app = tostring(c.class or ""), title = tostring(c.title or ""),
                nx = clamp(((tonumber(c.at[1]) or 0) - mx) / mw), ny = clamp(((tonumber(c.at[2]) or 0) - my) / mh),
                nw = clamp((tonumber(c.size[1]) or 0) / mw), nh = clamp((tonumber(c.size[2]) or 0) / mh),
                floating = c.floating == true, focused = tonumber(c.focusHistoryID) == 0,
            }
        end
    end
    table.sort(out, function(a, b)
        if a.floating ~= b.floating then return not a.floating end
        return a.ws < b.ws
    end)
    return out
end

-- The window you are in: the most recently focused one on the active workspace.
function M.focused(clients, active)
    local best = nil
    for _, c in ipairs(type(clients) == "table" and clients or {}) do
        local ws = type(c.workspace) == "table" and tonumber(c.workspace.id) or nil
        if ws == tonumber(active) and c.mapped ~= false and c.hidden ~= true then
            local r = tonumber(c.focusHistoryID) or 999
            if not best or r < best.r then best = { r = r, c = c } end
        end
    end
    return best and best.c or nil
end

-- That window's own sound: the stream (audio.apps) whose program or name is its app, by its
-- process first. nil when it plays nothing.
function M.stream(apps, class, pid)
    local k = string.lower(tostring(class or ""))
    if k == "" then return nil end
    for i, a in ipairs(type(apps) == "table" and apps or {}) do
        if pid and tonumber(a.pid) == tonumber(pid) then return i, a end
    end
    for i, a in ipairs(type(apps) == "table" and apps or {}) do
        for _, f in ipairs({ a.binary, a.name, a.id }) do
            local v = string.lower(tostring(f or ""))
            if v ~= "" and (string.find(v, k, 1, true) or string.find(k, v, 1, true)) then return i, a end
        end
    end
    return nil
end

-- ── What is waiting ──────────────────────────────────────────
-- From what the drawer read, the things worth a press, most pressing first: each a word, the
-- action's word and its code (`go` a mooi-nexus GO code, or `tog` a toggle).
function M.waiting(s)
    s = s or {}
    local out = {}
    local function add(word, act, go, tog, hot) out[#out + 1] = { word = word, act = act, go = go or -1, tog = tog or -1, hot = hot == true } end
    if s.recording then add("Recording the screen", "STOP", nil, 8, true) end
    local bat = tonumber(s.battery)
    if bat and bat <= 20 and not s.charging then add(string.format("Battery %d%%", math.floor(bat + 0.5)), s.saver and "OK" or "SAVER", nil, s.saver and -1 or 7, true) end
    local notes = tonumber(s.notes) or 0
    if notes > 0 then
        local first = s.first_note and s.first_note ~= "" and (" · " .. s.first_note) or ""
        add(string.format("%d new%s", notes, first), "OPEN", 30, nil, true)
    end
    local upd = tonumber(s.updates) or 0
    if upd > 0 then add(string.format("%d update%s waiting", upd, upd == 1 and "" or "s"), "UPDATE", 13) end
    if s.weather and s.weather ~= "" then add(s.weather, "DAY", 12) end
    if s.quiet then add("Quiet is on", "END", nil, 4) end
    if #out == 0 then add("All quiet", "WEEK", 11) end
    return out
end

-- ── Scenes ───────────────────────────────────────────────────
-- A scene is a whole setup at once: some of the switches (`saver` is the power-saver profile), the
-- levels, and if it likes a saved environment (D43) restored with it, by name. What it leaves out
-- stays as it is. Saved in the data folder's nexus-scenes.json.
M.SWITCHES = { "quiet", "night", "awake", "saver", "wifi", "bluetooth" }
M.WORDS = { quiet = "quiet", night = "night light", awake = "keep awake", saver = "power saver", wifi = "Wi-Fi", bluetooth = "Bluetooth" }
M.MAX = 7
M.DEFAULTS = {
    { name = "Focus", quiet = true, awake = true },
    { name = "Night", night = true, quiet = true, brightness = 35 },
    { name = "Present", quiet = true, awake = true, night = false },
    { name = "Saver", saver = true, brightness = 50, bluetooth = false },
}

local function level(v)
    v = tonumber(v)
    if not v then return nil end
    return math.max(0, math.min(100, math.floor(v + 0.5)))
end

-- A scene list as it can be trusted: named (at most 12 letters), its switches true or false,
-- its levels 0..100; at most M.MAX. Nothing usable gives the defaults.
function M.clean(list)
    local out = {}
    for _, s in ipairs(type(list) == "table" and list or {}) do
        if type(s) == "table" and type(s.name) == "string" then
            local name = s.name:gsub("^%s+", ""):gsub("%s+$", "")
            if name ~= "" and #out < M.MAX then
                local c = { name = string.sub(name, 1, 12) }
                for _, k in ipairs(M.SWITCHES) do if type(s[k]) == "boolean" then c[k] = s[k] end end
                c.volume, c.brightness = level(s.volume), level(s.brightness)
                if type(s.env) == "string" and s.env ~= "" then c.env = string.sub(s.env, 1, 40) end
                out[#out + 1] = c
            end
        end
    end
    if #out == 0 then
        for _, s in ipairs(M.DEFAULTS) do
            local c = {}
            for k, v in pairs(s) do c[k] = v end
            out[#out + 1] = c
        end
    end
    return out
end

-- The desktop as it is now, as a scene called `name`.
function M.capture(state, name)
    state = state or {}
    local c = { name = string.sub(tostring(name or "Mine"), 1, 12) }
    for _, k in ipairs(M.SWITCHES) do if type(state[k]) == "boolean" then c[k] = state[k] end end
    c.volume, c.brightness = level(state.volume), level(state.brightness)
    return c
end

-- What switching to the scene would change, in words: only what differs from `state`.
function M.diff(scene, state)
    state = state or {}
    local out = {}
    for _, k in ipairs(M.SWITCHES) do
        if scene[k] ~= nil and scene[k] ~= state[k] then out[#out + 1] = M.WORDS[k] .. (scene[k] and " on" or " off") end
    end
    if scene.volume and scene.volume ~= level(state.volume) then out[#out + 1] = string.format("volume %d%%", scene.volume) end
    if scene.brightness and state.brightness ~= nil and scene.brightness ~= level(state.brightness) then
        out[#out + 1] = string.format("screen %d%%", scene.brightness)
    end
    if scene.env then out[#out + 1] = "restore " .. scene.env end
    return out
end

-- The steps that make it so: switches to flip (only those that differ) and levels to set (0..1).
function M.steps(scene, state)
    state = state or {}
    local out = {}
    for _, k in ipairs(M.SWITCHES) do
        if scene[k] ~= nil and scene[k] ~= state[k] then out[#out + 1] = { flip = k } end
    end
    if scene.volume and scene.volume ~= level(state.volume) then out[#out + 1] = { level = "volume", to = scene.volume / 100 } end
    if scene.brightness and state.brightness ~= nil and scene.brightness ~= level(state.brightness) then
        out[#out + 1] = { level = "brightness", to = scene.brightness / 100 }
    end
    return out
end

-- The scene the desktop already is (every part of it holds), or nil.
function M.live(scenes, state)
    for i, s in ipairs(scenes or {}) do
        if not s.env and #M.diff(s, state) == 0 then return i end
    end
    return nil
end

return M
