-- The Nexus hub's arrangement: what the plate under the mark holds, in which order, and where each
-- part sits. Pure: no files, no facts — tests/unit runs it under Lua 5.4, and
-- shell/mooi-nexus.luau publishes what `layout` returns.
--
-- The plate is a hero across the top (it carries the plate's own controls: customise, settings,
-- the whole workspace, close) and, under it, two columns: the main one, and a narrow rail beside
-- it where a section runs lengthways — the visualiser as a column of bands, the machine as a
-- stack of gauges, the levels as upright sliders. `settings.nexus.hub` keeps the choice:
--   { hero = "identity", size = "compact", order = { "tiles", … }, hidden = { … }, side = { … } }

local M = {}

-- The hero's faces, in the order the customise strip offers them, and the height each one takes.
M.HEROES = {
    { id = "identity", name = "IDENTITY", h = 104 },
    { id = "player",   name = "PLAYER",   h = 140 },
    { id = "reactor",  name = "REACTOR",  h = 124 },
    { id = "both",     name = "ID + PLAYER", h = 176 },
    { id = "minimal",  name = "MINIMAL",  h = 52 },
}
M.HERO_INDEX = {}
for i, h in ipairs(M.HEROES) do M.HERO_INDEX[h.id] = i end

-- The sections under the hero, in their shipped order: `h` in the main column, `side` in the rail
-- (nil where the section has no upright form). `levels` loses a row where the machine has no
-- backlight; `media` is drawn only while a player owns the session, never under a player hero;
-- `spaces` in the rail grows with the workspaces (two to a row).
M.SECTIONS = {
    { id = "tiles",  name = "SWITCHES",    h = 124, side = 320 },
    { id = "levels", name = "LEVELS",      h = 92,  side = 196 },
    { id = "media",  name = "NOW PLAYING", h = 78,  side = 236 },
    { id = "viz",    name = "VISUALISER",  h = 58,  side = 300 },
    { id = "gauges", name = "MACHINE",     h = 70,  side = 292 },
    { id = "spaces", name = "WORKSPACES",  h = 34,  side = 0 },
    { id = "places", name = "SHORTCUTS",   h = 32,  side = 196 },
}
M.SECTION_INDEX = {}
for i, s in ipairs(M.SECTIONS) do M.SECTION_INDEX[s.id] = i end
-- Shipped hidden: the standalone visualiser is a choice, not a default.
M.HIDDEN_DEFAULT = { "viz" }

-- The main column's two widths, and the rail's.
M.SIZES = { compact = 476, wide = 584 }
M.RAIL = 164
M.PAD = 16         -- the plate's inner margin
M.GAP = 12         -- between two sections
M.HERO_GAP = 14    -- under the hero
M.FOOT = 16        -- under the last section
M.STUB = 26        -- a hidden section while customising: its name and SHOW
M.EDIT_BAR = 66    -- the customise strip under the hero: its faces, the width, reset and done
M.CAPTION = 14     -- each section's engraved name above it

local function set_of(list)
    local set = {}
    for _, id in ipairs(list or {}) do set[id] = true end
    return set
end

local function ids(list)
    local out, seen = {}, {}
    if type(list) == "table" then
        for _, id in ipairs(list) do
            if type(id) == "string" and M.SECTION_INDEX[id] and not seen[id] then
                seen[id] = true
                out[#out + 1] = id
            end
        end
    end
    return out
end

-- The hub's choice, whatever the file holds: a known hero and size, every section exactly once
-- (unknown names dropped, missing ones put back in their shipped place), and only known names in
-- `hidden` and `side` (a section with no upright form never goes to the rail).
function M.normalize(v)
    v = type(v) == "table" and v or {}
    local out = {
        hero = M.HERO_INDEX[v.hero] and v.hero or "identity",
        size = M.SIZES[v.size] and v.size or "compact",
        order = ids(v.order),
        hidden = type(v.hidden) == "table" and ids(v.hidden) or ids(M.HIDDEN_DEFAULT),
        side = {},
    }
    local seen = set_of(out.order)
    for _, s in ipairs(M.SECTIONS) do
        if not seen[s.id] then
            -- a section the file does not name goes back where it ships: after the last named
            -- section that ships before it
            local at = 0
            for k, id in ipairs(out.order) do
                if M.SECTION_INDEX[id] < M.SECTION_INDEX[s.id] then at = k end
            end
            table.insert(out.order, at + 1, s.id)
            seen[s.id] = true
        end
    end
    for _, id in ipairs(ids(v.side)) do
        if id == "spaces" or M.SECTIONS[M.SECTION_INDEX[id]].side then out.side[#out.side + 1] = id end
    end
    return out
end

function M.is_hidden(hub, id) return set_of(hub.hidden)[id] == true end
function M.is_side(hub, id) return set_of(hub.side)[id] == true end

-- Move a section one place up (-1) or down (1) among the sections of its own column. Returns a
-- new choice and whether it moved.
function M.move(hub, id, dir)
    hub = M.normalize(hub)
    local side = M.is_side(hub, id)
    local at
    for k, s in ipairs(hub.order) do if s == id then at = k end end
    if not at then return hub, false end
    local step = dir < 0 and -1 or 1
    local to = at + step
    while to >= 1 and to <= #hub.order and M.is_side(hub, hub.order[to]) ~= side do to = to + step end
    if to < 1 or to > #hub.order then return hub, false end
    hub.order[at], hub.order[to] = hub.order[to], hub.order[at]
    return hub, true
end

-- Hide a shown section, or show a hidden one. Returns a new choice and whether it is now hidden.
function M.toggle(hub, id)
    hub = M.normalize(hub)
    if not M.SECTION_INDEX[id] then return hub, false end
    local keep, was = {}, false
    for _, s in ipairs(hub.hidden) do
        if s == id then was = true else keep[#keep + 1] = s end
    end
    if not was then keep[#keep + 1] = id end
    hub.hidden = keep
    return hub, not was
end

-- Send a section to the rail, or bring it back to the main column. Returns a new choice and
-- whether it is now in the rail (a section with no upright form stays where it is).
function M.toggle_side(hub, id)
    hub = M.normalize(hub)
    local def = M.SECTIONS[M.SECTION_INDEX[id] or 0]
    if not def then return hub, false end
    local keep, was = {}, false
    for _, s in ipairs(hub.side) do
        if s == id then was = true else keep[#keep + 1] = s end
    end
    if not was then keep[#keep + 1] = id end
    hub.side = keep
    return hub, not was
end

-- Where everything sits. `env` says what the machine and the moment allow:
--   backlight   the levels keep their brightness row
--   media       a player owns the session
--   spaces      how many workspaces the rail's grid holds
--   editing     the customise mode is on: hidden sections show as stubs, the player's section is
--               shown even with nothing playing, so it can be placed
-- Returns { w, h, main_w, rail_w, rail_x, hero, hero_h, edit_y, rows } with one row per section in
-- the user's order: { id, name, x, y, w, h, on, stub, side, first, last } — `on` is false for a
-- section that takes no room, and `first`/`last` are within its own column.
function M.layout(hub, env)
    hub = M.normalize(hub)
    env = type(env) == "table" and env or {}
    local hide, side = set_of(hub.hidden), set_of(hub.side)
    local hero = M.HEROES[M.HERO_INDEX[hub.hero]]
    local player_hero = hub.hero == "player" or hub.hero == "both"
    local main_w = M.SIZES[hub.size]
    local top = hero.h + M.HERO_GAP
    local edit_y = -1
    if env.editing then edit_y = top; top = top + M.EDIT_BAR + M.GAP end

    -- what each section takes, and whether there is a rail at all
    local rows, rail_used = {}, false
    for k, id in ipairs(hub.order) do
        local def = M.SECTIONS[M.SECTION_INDEX[id]]
        local in_side = side[id] == true
        local h = in_side and def.side or def.h
        if id == "levels" and not env.backlight then h = in_side and 140 or 62 end
        if id == "spaces" and in_side then
            h = 40 * math.max(1, math.ceil((tonumber(env.spaces) or 2) / 2))
        end
        local present = true
        if id == "media" then present = (env.media == true or env.editing == true) and not player_hero end
        local row = { id = id, name = def.name, x = 0, y = 0, w = 0, h = 0, on = false, stub = false, side = in_side }
        if hide[id] or not present then
            if env.editing then row.h, row.stub = M.STUB, true end
        else
            row.h, row.on = h, true
        end
        if row.h > 0 and in_side then rail_used = true end
        rows[k] = row
    end

    local rail_w = rail_used and M.RAIL or 0
    local rail_x = M.PAD + main_w + M.GAP
    local width = M.PAD + main_w + (rail_used and (M.GAP + rail_w) or 0) + M.PAD
    local ym, ys = top, top
    local last_main, last_side, first_main, first_side
    for k, row in ipairs(rows) do
        if row.h > 0 then
            local cap = row.stub and 0 or M.CAPTION
            if row.side then
                row.x, row.w, row.y = rail_x, rail_w, ys + cap
                ys = ys + cap + row.h + M.GAP
                first_side = first_side or k; last_side = k
            else
                row.x, row.w, row.y = M.PAD, main_w, ym + cap
                ym = ym + cap + row.h + M.GAP
                first_main = first_main or k; last_main = k
            end
        end
    end
    for k, row in ipairs(rows) do
        row.first = k == (row.side and first_side or first_main)
        row.last = k == (row.side and last_side or last_main)
    end
    local bottom = math.max(ym, ys)
    local any = bottom > top
    local h = (any or env.editing) and (bottom - M.GAP + M.FOOT) or (hero.h + M.FOOT)
    return { w = width, h = h, main_w = main_w, rail_w = rail_w, rail_x = rail_x, hero = hub.hero,
             hero_h = hero.h, edit_y = edit_y, rows = rows }
end

return M
