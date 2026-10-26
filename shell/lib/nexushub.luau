-- The Nexus hub's arrangement: what the compact plate under the mark holds, in which order, and
-- where each part sits. Pure: no files, no facts — tests/unit runs it under Lua 5.4, and
-- shell/mooi-nexus.luau publishes what `layout` returns.
--
-- The plate is a column. The hero is always first (it carries the plate's own controls: settings,
-- the whole workspace, close, customise) and is one of five faces; the sections under it are the
-- user's to order and hide. `settings.nexus.hub` keeps the choice:
--   { hero = "identity", size = "compact", order = { "tiles", … }, hidden = { "places", … } }

local M = {}

-- The hero's faces, in the order the customise strip offers them, and the height each one takes.
M.HEROES = {
    { id = "identity", name = "IDENTITY", h = 92 },
    { id = "player",   name = "PLAYER",   h = 128 },
    { id = "reactor",  name = "REACTOR",  h = 112 },
    { id = "both",     name = "ID + PLAYER", h = 160 },
    { id = "minimal",  name = "MINIMAL",  h = 46 },
}
M.HERO_INDEX = {}
for i, h in ipairs(M.HEROES) do M.HERO_INDEX[h.id] = i end

-- The sections under the hero, in their shipped order. `h` is the drawn height; `levels` loses a
-- row where the machine has no backlight, and `media` is drawn only while a player owns the
-- session (and never when the hero already is the player).
M.SECTIONS = {
    { id = "tiles",  name = "SWITCHES",   h = 106 },
    { id = "levels", name = "LEVELS",     h = 72 },
    { id = "media",  name = "NOW PLAYING", h = 64 },
    { id = "gauges", name = "MACHINE",    h = 56 },
    { id = "spaces", name = "WORKSPACES", h = 26 },
    { id = "places", name = "SHORTCUTS",  h = 24 },
}
M.SECTION_INDEX = {}
for i, s in ipairs(M.SECTIONS) do M.SECTION_INDEX[s.id] = i end

-- The plate's two widths.
M.SIZES = { compact = 452, wide = 540 }

M.GAP = 8          -- between two sections
M.HERO_GAP = 10    -- under the hero
M.FOOT = 12        -- under the last section
M.STUB = 24        -- a hidden section while customising: its name and SHOW
M.EDIT_BAR = 62    -- the customise strip under the hero: its faces, the width, reset and done

-- The hub's choice, whatever the file holds: a known hero and size, every section exactly once
-- (unknown names dropped, missing ones appended in their shipped place), and only known names in
-- `hidden`.
function M.normalize(v)
    v = type(v) == "table" and v or {}
    local out = {
        hero = M.HERO_INDEX[v.hero] and v.hero or "identity",
        size = M.SIZES[v.size] and v.size or "compact",
        order = {},
        hidden = {},
    }
    local seen = {}
    if type(v.order) == "table" then
        for _, id in ipairs(v.order) do
            if type(id) == "string" and M.SECTION_INDEX[id] and not seen[id] then
                seen[id] = true
                out.order[#out.order + 1] = id
            end
        end
    end
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
    local hid = {}
    if type(v.hidden) == "table" then
        for _, id in ipairs(v.hidden) do
            if type(id) == "string" and M.SECTION_INDEX[id] and not hid[id] then
                hid[id] = true
                out.hidden[#out.hidden + 1] = id
            end
        end
    end
    return out
end

local function hidden_set(hub)
    local set = {}
    for _, id in ipairs(hub.hidden) do set[id] = true end
    return set
end

function M.is_hidden(hub, id)
    return hidden_set(hub)[id] == true
end

-- Move a section one place up (-1) or down (1). Returns a new choice and whether it moved.
function M.move(hub, id, dir)
    hub = M.normalize(hub)
    local at
    for k, s in ipairs(hub.order) do if s == id then at = k end end
    local to = at and at + (dir < 0 and -1 or 1)
    if not at or to < 1 or to > #hub.order then return hub, false end
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

-- Where everything sits. `env` says what the machine and the moment allow:
--   backlight   the levels keep their third row
--   media       a player owns the session
--   editing     the customise mode is on: hidden sections show as stubs, and the player's
--               section is shown even with nothing playing, so it can be placed
-- Returns { w, h, hero, hero_h, edit_y, rows = { { id, name, y, h, on, stub, first, last } … } } with
-- one row per section in the user's order; `on` is false for a section that takes no room, and
-- `edit_y` is where the customise strip goes (-1 while not customising).
function M.layout(hub, env)
    hub = M.normalize(hub)
    env = type(env) == "table" and env or {}
    local hide = hidden_set(hub)
    local hero = M.HEROES[M.HERO_INDEX[hub.hero]]
    local player_hero = hub.hero == "player" or hub.hero == "both"
    local y = hero.h + M.HERO_GAP
    local edit_y = -1
    if env.editing then edit_y = y; y = y + M.EDIT_BAR + M.GAP end
    local rows, any = {}, false
    for k, id in ipairs(hub.order) do
        local def = M.SECTIONS[M.SECTION_INDEX[id]]
        local h = def.h
        if id == "levels" and not env.backlight then h = 48 end
        local present = true
        if id == "media" then present = (env.media == true or env.editing == true) and not player_hero end
        local row = { id = id, name = def.name, y = y, h = 0, on = false, stub = false,
                      first = k == 1, last = k == #hub.order }
        if hide[id] or not present then
            if env.editing then
                -- a stub says the section is there to be shown again (or, for the player's
                -- section under a player hero, why it is not drawn)
                row.h, row.stub = M.STUB, true
            end
        else
            row.h, row.on = h, true
        end
        if row.h > 0 then
            y = y + row.h + M.GAP
            any = true
        end
        rows[k] = row
    end
    local h = (any or env.editing) and (y - M.GAP + M.FOOT) or (hero.h + M.FOOT)
    return { w = M.SIZES[hub.size], h = h, hero = hub.hero, hero_h = hero.h, edit_y = edit_y, rows = rows }
end

return M
