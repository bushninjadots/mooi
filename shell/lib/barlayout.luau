-- The bar's layout: which modules there are, how wide each is, and where they go.
-- Pure: no pleamar globals, so tests/unit runs it under plain Lua 5.4 (written in the
-- subset Lua 5.4 and Luau share).
--
-- The bar is three lists of modules — left, centre, right (settings `bar.left`,
-- `bar.center`, `bar.right`) — read in order. An entry is one module (`"clock"`) or several
-- joined with `+` (`"network+bluetooth"`): a **group**, which shares one frame with a hairline
-- between its members. Splitting a group is writing its members as separate entries; merging
-- is joining them. A module that is hidden (`bar.modules.<id>.show`) or that the machine
-- cannot have (no battery, an empty tray) takes no room, and a group left empty disappears.
--
-- Two modes: **islands**, one frame per group with a gap between groups; **full**, one panel
-- across the screen, groups parted by a divider instead of a gap. The centre list is centred
-- on the screen when it fits there, and between the two sides when it does not.
--
-- A **spacer** (`"gap"`, as many as you like, never joined into a group) is room and nothing
-- else: in the left or right list it stretches, taking the room between its side and the centre
-- (shared with the others on that side), so what follows it is pushed toward the middle — a
-- module can sit anywhere along the bar. In the centre list it is a fixed 24 px. A **gap** of a
-- fixed width (`"gap:120"`) is what edit mode leaves when a module is dropped into empty space: the
-- module stays exactly where it was let go (at the start of the left list it is the distance from
-- the bar's left end, at the end of the right list the distance from its right end).

local M = {}

-- Every module, with its width at the bar's compact size. `width` may be a function of the
-- context (`ctx`: the workspace style, the tray's size), and `needs` names what the machine
-- must have for the module to be there at all.
M.MODULES = {
    workspaces = { width = function(ctx)
        -- the tag (30), the instrument, a margin (10); the scene's chain_span and cell pitch
        local n = math.max(1, tonumber(ctx.ws_count) or 10)
        if ctx.ws_style == "cells" then return 34 + n * 28 end
        -- the everyday switchers carry no tag: 8 px each side, then their own pitch
        if ctx.ws_style == "pills" then return 16 + 24 * n end
        if ctx.ws_style == "segments" then return 12 + 20 * n end
        if ctx.ws_style == "dots" then return 30 + 14 * n end
        if ctx.ws_style == "numbers" then return 16 + 22 * n end
        if ctx.ws_style == "compass" then return 166 end        -- a heading tape, five workspaces wide
        if ctx.ws_style == "radar" then return 76 end           -- a scope and the workspace beside it
        return 52 + 26 * math.min(n, 7)
    end },
    window = { width = 190 },
    -- The media's width is its mode's (media.mode): `full` — slabs, visualizer, track; `compact`
    -- — slabs and visualizer; `art` — the cover and the track; `viz` — the visualizer alone.
    -- With nothing playing (media.idle) it stays, collapses to a pill, or leaves the bar.
    media = { width = function(ctx)
        if not ctx.playing and ctx.media_idle == "collapse" then return 40 end
        local viz = ctx.visualizer ~= "off"
        if ctx.media_mode == "compact" then return viz and 170 or 84 end
        if ctx.media_mode == "art" then return 204 end
        if ctx.media_mode == "viz" then return viz and 96 or 40 end
        return viz and 280 or 212
    end, needs = "media" },
    resources = { width = 150 },
    bandwidth = { width = 82 },
    keyboard = { width = 50 },
    weather = { width = 78 },
    tray = { width = function(ctx) return 8 + 22 * ctx.tray end, needs = "tray" },
    notifications = { width = 46 },
    mic = { width = 66 },
    volume = { width = 84 },
    brightness = { width = 84, needs = "brightness" },
    battery = { width = 84, needs = "battery" },
    network = { width = 68 },
    bluetooth = { width = 64, needs = "bluetooth" },
    clock = { width = 120 },
    caffeine = { width = 30 },
    recorder = { width = 30 },
    screenshot = { width = 30 },
    clipboard = { width = 30 },
    power = { width = 30 },
    actions = { width = 32 },
    -- The Overview (D90, was the Workspace Atlas's place): a press opens it, as Super+Tab does.
    overview = { width = 32 },
    core = { width = 40 },
    -- A focus session and its break: a ring of what is left, and the minutes.
    focus = { width = 86 },
    -- mooi's own settings: the dial that opens them (and, right-pressed, the bar's menu).
    settings = { width = 32 },
    -- Quick notes (D51): the pad's page and how many are on it; a press opens the dropdown.
    notes = { width = 46 },
    -- Wallpapers: a framed picture; a press opens mooi's wallpaper picker (D145).
    wallpaper = { width = 32 },
    -- Control Nexus (D65): the Arch mark; a press opens the system command centre.
    nexus = { width = 32 },
    updates = { width = 42 },
    -- the side notch's doors (D106): Claude's chat, and GitHub with what waits there
    claude = { width = 32 },
    github = { width = 32 },
    -- D207: the Sigil hosted in an island — the living line at the bar's height
    sigil = { width = 180 },
    -- D209/D210: BMO's face, and Herdr's agents. Both start on the shelf.
    bmo = { width = 64 },
    herdr = { width = 56, needs = "herdr" },
}

-- In the order the scene declares their facts, and the bar menu lists them.
M.ORDER = {
    "workspaces", "window", "media", "resources", "bandwidth", "keyboard", "weather", "tray",
    "notifications", "mic", "volume", "brightness", "battery", "network", "bluetooth", "clock",
    "caffeine", "recorder", "screenshot", "clipboard", "power", "actions", "overview", "core", "focus", "settings",
    "notes", "wallpaper", "nexus", "updates", "claude", "github",
    "sigil",   -- D207
    "bmo",     -- D209
    "herdr",   -- D210
}

M.DEFAULT = {
    left = { "workspaces", "window" },
    center = { "media" },
    -- The focus timer, keep-awake, the weather, the screenshot and the recorder start on the
    -- shelf (edit mode places them): the default row is full, the weather asks ipinfo.io where
    -- you are (from your address), which is the user's to choose, and quick notes takes the
    -- screenshot pair's room (D51).
    right = { "resources", "network+bluetooth", "volume+mic", "brightness+battery",
              "tray", "notifications", "clock", "notes", "wallpaper", "nexus", "actions+overview",
              "settings+power+core" },
}

function M.known(id) return M.MODULES[id] ~= nil end

-- The room between groups: islands stand a little further apart (each frame is 3 px wider than
-- its modules each side, so the content never touches its edge); a joined bar parts them by a
-- divider instead.
function M.gap(mode) return (mode == "islands") and 16 or 10 end

-- Each module's place in M.ORDER, from 0: how a frame or a divider names the modules it sits
-- between, so the scene can draw it from those modules' own (animated) places.
M.INDEX = {}
for i, id in ipairs(M.ORDER) do M.INDEX[id] = i - 1 end

M.SPACER = "gap"
M.CENTRE_GAP = 24             -- a spacer's width in the centre list, where nothing stretches
-- A fixed gap's width, or nil: "gap:120" → 120.
function M.gap_width(entry)
    local n = type(entry) == "string" and tonumber(string.match(entry, "^gap:(%d+)$"))
    if n and n >= 1 and n <= 4000 then return n end
    return nil
end
function M.is_spacer(entry) return entry == M.SPACER or M.gap_width(entry) ~= nil end
function M.fixed_gap(w) return "gap:" .. tostring(math.max(1, math.floor(w + 0.5))) end

-- The members of one entry ("a+b+c"), or nil and why. A spacer has no members.
function M.split(entry)
    if type(entry) ~= "string" or entry == "" then return nil, "expected a module name" end
    if M.is_spacer(entry) then return {} end
    local out = {}
    for id in string.gmatch(entry, "[^+]+") do
        if not M.known(id) then return nil, "unknown module " .. id end
        out[#out + 1] = id
    end
    if #out == 0 then return nil, "expected a module name" end
    return out
end

-- Checks one list (settings bar.left / center / right). `seen` is shared by the three, so a
-- module is placed once.
function M.check_list(list, seen)
    if type(list) ~= "table" then return false, "expected a list of modules" end
    for i, entry in ipairs(list) do
        local ids, why = M.split(entry)
        if not ids then return false, string.format("entry %d: %s", i, why) end
        if #ids == 0 and not M.is_spacer(entry) then return false, string.format("entry %d: expected a module name", i) end
        for _, id in ipairs(ids) do
            if seen[id] then return false, "module " .. id .. " is placed twice" end
            seen[id] = true
        end
    end
    return true
end

function M.width(id, ctx)
    local w = M.MODULES[id].width
    if type(w) == "function" then return w(ctx) end
    return w
end

local function present(id, ctx, show)
    if show[id] == false then return false end
    local needs = M.MODULES[id].needs
    if needs == "tray" then return (ctx.tray or 0) > 0 end
    if needs == "battery" then return ctx.battery == true end
    if needs == "brightness" then return ctx.brightness == true end
    if needs == "bluetooth" then return ctx.bluetooth ~= false end
    if needs == "media" then return ctx.playing ~= false or ctx.media_idle ~= "hide" end
    return true
end

-- The groups of one list, with what is not there left out: { { ids, widths, w }, … }.
local function groups(list, ctx, show)
    local out = {}
    for src, entry in ipairs(list or {}) do
        local ids = M.split(entry)
        if M.is_spacer(entry) then
            local fixed = M.gap_width(entry)
            out[#out + 1] = { ids = {}, widths = {}, w = fixed or 0, spacer = true, fixed = fixed ~= nil, src = src }
        elseif ids then
            local g = { ids = {}, widths = {}, w = 0 }
            for _, id in ipairs(ids) do
                if present(id, ctx, show) then
                    local w = M.width(id, ctx)
                    g.ids[#g.ids + 1] = id; g.widths[#g.widths + 1] = w; g.w = g.w + w
                end
            end
            if #g.ids > 0 then out[#out + 1] = g end
        end
    end
    return out
end

local function span(gs, gap)
    local w = 0
    for i, g in ipairs(gs) do w = w + g.w + ((i > 1) and gap or 0) end
    return w
end

-- A list's spacers and its modules, with the ones that mean nothing dropped: a stretching spacer
-- at either end, or next to another; and a fixed gap where it measures nothing — after the left
-- list's last module, before the right list's first, at the centre list's ends.
local function trim(gs, side)
    local out = {}
    for _, g in ipairs(gs) do
        local drop = g.spacer and not g.fixed and (#out == 0 or out[#out].spacer)
        if g.spacer and g.fixed and #out == 0 and side ~= "left" then drop = true end
        if not drop then out[#out + 1] = g end
    end
    while #out > 0 and out[#out].spacer and (not out[#out].fixed or side ~= "right") do out[#out] = nil end
    -- a list that is only gaps holds nothing
    local any = false
    for _, g in ipairs(out) do if not g.spacer then any = true end end
    if not any then return {} end
    return out
end
local function spacers(gs)
    local n = 0
    for _, g in ipairs(gs) do if g.spacer and not g.fixed then n = n + 1 end end
    return n
end
-- Shares `room` among a list's spacers.
local function stretch(gs, room)
    local n = spacers(gs)
    if n == 0 then return end
    local each = math.max(0, room) / n
    for _, g in ipairs(gs) do if g.spacer and not g.fixed then g.w = each end end
end

-- The whole layout. `cfg` = { left, center, right, show = { id = bool }, frame = { id = n },
-- mode = "islands" | "full" }, `ctx` = { screen, inset, gap, ws_style, ws_count, visualizer,
-- tray, battery, brightness, bluetooth }. Returns
--   x        { id = left edge } for every module that is placed (others absent)
--   frames   { { x, w, style }, … } one per group (drawn as frames in islands mode)
--   dividers { { x, strong }, … } between members of a group, and (full mode) between groups
--   panel    { x, w } the full mode's panel, or nil
function M.layout(cfg, ctx)
    local gap = ctx.gap
    local full = cfg.mode == "full"
    -- a notch's pieces part their groups with dividers, as the full panel does
    local joined = full or cfg.mode == "notch"
    local show = cfg.show or {}
    local L = trim(groups(cfg.left, ctx, show), "left")
    local C = trim(groups(cfg.center, ctx, show), "center")
    local Rg = trim(groups(cfg.right, ctx, show), "right")
    for _, g in ipairs(C) do if g.spacer and not g.fixed then g.w = M.CENTRE_GAP end end
    local out = { x = {}, frames = {}, dividers = {}, spacers = {} }

    local last = nil         -- the last module placed, for the divider after it
    local function place(gs, x0, side)
        local x = x0
        local after_spacer = false
        for i, g in ipairs(gs) do
            if g.spacer then
                -- where each spacer lies, so edit mode can show it (`i`: its entry in the list)
                out.spacers[#out.spacers + 1] = { x = x - gap / 2, w = g.w + gap, own = g.w, side = side, i = g.src, fixed = g.fixed == true }
                after_spacer = true
                x = x + g.w + gap
            else
                if i > 1 and not after_spacer and joined then
                    out.dividers[#out.dividers + 1] = { x = x + gap / 2 - gap, strong = true, gap = gap,
                        p = M.INDEX[last], m = M.INDEX[g.ids[1]] }
                end
                after_spacer = false
                -- Every group has its box: islands mode frames it, full mode sets it in a bay when
                -- the bar is a mechanism.
                out.frames[#out.frames + 1] = { x = x, w = g.w, style = (cfg.frame or {})[g.ids[1]] or 0, id = g.ids[1],
                    a = M.INDEX[g.ids[1]], b = M.INDEX[g.ids[#g.ids]] }
                local mx = x
                for j, id in ipairs(g.ids) do
                    if j > 1 then out.dividers[#out.dividers + 1] = { x = mx, strong = false, gap = 0, p = M.INDEX[g.ids[j - 1]], m = M.INDEX[id] } end
                    out.x[id] = mx
                    mx = mx + g.widths[j]
                end
                last = g.ids[#g.ids]
                x = x + g.w + gap
            end
        end
    end

    local left_x = ctx.inset
    local left_w = span(L, gap)
    local right_w = span(Rg, gap)
    local right_x = ctx.screen - ctx.inset - right_w
    local center_w = span(C, gap)
    local cx = (ctx.screen - center_w) / 2
    local lo, hi = left_x + left_w + gap, right_x - gap
    if #L == 0 then lo = ctx.inset end
    if #Rg == 0 then hi = ctx.screen - ctx.inset end
    if cx < lo or cx + center_w > hi then cx = (lo + hi - center_w) / 2 end
    -- The spacers take what room is left: up to the centre, or — with no centre — up to the
    -- other side's modules (or the middle, when both sides stretch).
    local nl, nr = spacers(L), spacers(Rg)
    if nl > 0 or nr > 0 then
        local mid = ctx.screen / 2
        local l_end, r_start
        if #C > 0 then l_end, r_start = cx - gap, cx + center_w + gap
        elseif nl > 0 and nr > 0 then l_end, r_start = mid - gap / 2, mid + gap / 2
        else l_end, r_start = right_x - gap, left_x + left_w + gap end
        if nl > 0 then stretch(L, l_end - (left_x + left_w)); left_w = span(L, gap) end
        if nr > 0 then stretch(Rg, right_x - r_start); right_w = span(Rg, gap); right_x = ctx.screen - ctx.inset - right_w end
    end
    place(L, left_x, "left")
    place(C, math.floor(cx + 0.5), "center")
    place(Rg, right_x, "right")
    -- The three clusters' extents (the notch's pieces), nil where a cluster is empty.
    out.clusters = {
        left = (#L > 0) and { x = left_x, w = left_w } or nil,
        center = (#C > 0) and { x = math.floor(cx + 0.5), w = center_w } or nil,
        right = (#Rg > 0) and { x = right_x, w = right_w } or nil,
    }
    if full then
        -- the clusters' own seams, where one cluster ends and the next begins (a list's ends are
        -- modules: trim() leaves no spacer there)
        local function ends(gs) return M.INDEX[gs[#gs].ids[#gs[#gs].ids]], M.INDEX[gs[1].ids[1]] end
        if #L > 0 and #C > 0 then out.dividers[#out.dividers + 1] = { x = left_x + left_w + (cx - left_x - left_w) / 2, strong = true, gap = cx - left_x - left_w, p = (ends(L)), m = select(2, ends(C)) } end
        if #C > 0 and #Rg > 0 then out.dividers[#out.dividers + 1] = { x = cx + center_w + (right_x - cx - center_w) / 2, strong = true, gap = right_x - cx - center_w, p = (ends(C)), m = select(2, ends(Rg)) } end
        if #L > 0 and #C == 0 and #Rg > 0 then out.dividers[#out.dividers + 1] = { x = left_x + left_w + gap / 2, strong = true, gap = right_x - left_x - left_w, p = (ends(L)), m = select(2, ends(Rg)) } end
        out.panel = { x = ctx.inset - 6, w = ctx.screen - 2 * ctx.inset + 12 }
    end
    out.overflow = (#C > 0 and center_w > hi - lo) or (left_x + left_w > right_x)
    return out
end

local function copy_lists(cfg)
    local out = {}
    for _, side in ipairs({ "left", "center", "right" }) do
        out[side] = {}
        for i, e in ipairs(cfg[side] or {}) do out[side][i] = e end
    end
    return out
end

-- The three lists with `id` taken out of wherever it is (out of its group, if it is in one).
function M.without(cfg, id)
    local out = copy_lists(cfg)
    for _, side in ipairs({ "left", "center", "right" }) do
        local list = out[side]
        for i = #list, 1, -1 do
            local ids = M.split(list[i]) or {}
            if M.is_spacer(list[i]) then ids = { list[i] } end   -- a spacer stays where it is
            local kept = {}
            for _, m in ipairs(ids) do if m ~= id then kept[#kept + 1] = m end end
            if #kept == 0 then table.remove(list, i) else list[i] = table.concat(kept, "+") end
        end
    end
    return out
end

-- Edit mode: the lists after `id` is dropped at `x` on the bar (cfg/ctx as for `layout`).
-- Over a module: on the middle half of it, it joins that module's group; on either side, it goes
-- before or after it. In empty space it is placed **where it was let go**: on the left or the
-- right, a fixed gap is put in front of it (behind it, on the right) sized so its middle lands at
-- `x`, and a fixed gap that followed shrinks by what it took, so what was beyond stays where it
-- was; between the centre's modules it simply goes between them.
local MIN_GAP = 8
function M.drop(cfg, ctx, id, x)
    local lists = M.without(cfg, id)
    local probe = {}
    for k, v in pairs(cfg) do probe[k] = v end
    probe.left, probe.center, probe.right = lists.left, lists.center, lists.right
    local show = {}
    for k, v in pairs(cfg.show or {}) do show[k] = v end
    probe.show = show
    local out = M.layout(probe, ctx)
    local gap = ctx.gap
    local entries = {}
    for _, side in ipairs({ "left", "center", "right" }) do
        for i, e in ipairs(lists[side]) do
            local l, r = nil, nil
            for _, m in ipairs(M.split(e) or {}) do
                local mx = out.x[m]
                if mx then
                    l = l and math.min(l, mx) or mx
                    r = math.max(r or mx, mx + M.width(m, ctx))
                end
            end
            if l then entries[#entries + 1] = { side = side, i = i, l = l, r = r } end
        end
    end
    -- over a module: join it, or go beside it
    for _, en in ipairs(entries) do
        if x >= en.l and x <= en.r then
            local list = lists[en.side]
            local q = (x - en.l) / math.max(1, en.r - en.l)
            if q > 0.25 and q < 0.75 then list[en.i] = list[en.i] .. "+" .. id
            elseif q <= 0.25 then table.insert(list, en.i, id)
            else table.insert(list, en.i + 1, id) end
            return lists
        end
    end
    local w = M.width(id, ctx)
    local cl = out.clusters or {}
    local side
    if cl.center then
        if x < cl.center.x then side = "left" elseif x > cl.center.x + cl.center.w then side = "right" else side = "center" end
    elseif math.abs(x - ctx.screen / 2) < 90 then
        side = "center"           -- near the middle with no centre yet: it starts the centre
    else
        side = (x < ctx.screen / 2) and "left" or "right"
    end
    local list = lists[side]
    if side == "center" then
        -- between the centre's modules, in order
        local at = #list + 1
        for _, en in ipairs(entries) do if en.side == "center" and x < en.l and en.i < at then at = en.i end end
        table.insert(list, at, id)
        return lists
    end
    if side == "left" then
        local k, prev_r = 0, nil
        for _, en in ipairs(entries) do
            if en.side == "left" and en.r <= x and (not prev_r or en.r > prev_r) then k, prev_r = en.i, en.r end
        end
        local start = prev_r and (prev_r + gap) or ctx.inset
        local g = (x - w / 2) - start - gap
        local add = (g >= MIN_GAP) and { M.fixed_gap(g), id } or { id }
        for n, e in ipairs(add) do table.insert(list, k + n, e) end
        local after = list[k + #add + 1]
        local had = M.gap_width(after)
        if had then
            local left = had - (w + gap + ((g >= MIN_GAP) and (g + gap) or 0))
            if left >= MIN_GAP then list[k + #add + 1] = M.fixed_gap(left) else table.remove(list, k + #add + 1) end
        end
        return lists
    end
    -- the right: measured from what lies to the right of the drop, or the bar's right end
    local k, next_l = nil, nil
    for _, en in ipairs(entries) do
        if en.side == "right" and en.l >= x and (not next_l or en.l < next_l) then k, next_l = en.i, en.l end
    end
    local stop = next_l and (next_l - gap) or (ctx.screen - ctx.inset)
    local g = stop - (x + w / 2) - gap
    local at = k or (#list + 1)
    local add = (g >= MIN_GAP) and { id, M.fixed_gap(g) } or { id }
    local before = list[at - 1]
    local had = M.gap_width(before)
    for n, e in ipairs(add) do table.insert(list, at + n - 1, e) end
    if had then
        local left = had - (w + gap + ((g >= MIN_GAP) and (g + gap) or 0))
        if left >= MIN_GAP then list[at - 1] = M.fixed_gap(left) else table.remove(list, at - 1) end
    end
    return lists
end

-- Edit mode's arrows: `id` one place left (dir −1) or right (+1). Inside a group it trades
-- places with its neighbour, and at the group's edge it steps out of it; an entry trades
-- places with the next entry, and at the end of its list it crosses into the next list (left
-- → centre → right), so a module can be walked anywhere on the bar.
function M.nudge(cfg, id, dir)
    local lists = copy_lists(cfg)
    local sides = { "left", "center", "right" }
    for si, side in ipairs(sides) do
        local list = lists[side]
        for i, entry in ipairs(list) do
            local ids = M.split(entry) or {}
            for j, m in ipairs(ids) do
                if m == id then
                    if #ids > 1 then
                        local k = j + dir
                        if k >= 1 and k <= #ids then
                            ids[j], ids[k] = ids[k], ids[j]
                            list[i] = table.concat(ids, "+")
                        else
                            table.remove(ids, j)
                            list[i] = table.concat(ids, "+")
                            table.insert(list, (dir < 0) and i or (i + 1), id)
                        end
                    else
                        local k = i + dir
                        if k >= 1 and k <= #list then
                            list[i], list[k] = list[k], list[i]
                        elseif sides[si + dir] then
                            table.remove(list, i)
                            local other = lists[sides[si + dir]]
                            if dir < 0 then other[#other + 1] = entry else table.insert(other, 1, entry) end
                        end
                    end
                    return lists
                end
            end
        end
    end
    return lists
end

-- Edit mode's merge: `id` joins the entry before it (dir −1) or after it (+1) in its list;
-- already in a group, `split` takes it out (an entry of its own, just after the group).
function M.join(cfg, id, dir)
    local lists = copy_lists(cfg)
    for _, side in ipairs({ "left", "center", "right" }) do
        local list = lists[side]
        for i, entry in ipairs(list) do
            local ids = M.split(entry) or {}
            for j, m in ipairs(ids) do
                if m == id then
                    if dir == 0 then
                        if #ids > 1 then
                            table.remove(ids, j)
                            list[i] = table.concat(ids, "+")
                            table.insert(list, i + 1, id)
                        end
                    elseif #ids == 1 then
                        local k = i + dir
                        if k >= 1 and k <= #list then
                            list[k] = (dir < 0) and (list[k] .. "+" .. id) or (id .. "+" .. list[k])
                            table.remove(list, i)
                        end
                    end
                    return lists
                end
            end
        end
    end
    return lists
end

return M
