-- Pure helpers for Control Nexus behaviour, kept separate so unit tests can exercise
-- the mapping without invoking a real media player or compositor.

local M = {}

function M.media_action(value)
    local n = tonumber(value)
    if n == 1 then return "PREVIOUS TRACK", "media.previous" end
    if n == 2 then return "NEXT TRACK", "media.next" end
    if n == 0 then return "PLAY / PAUSE", "media.toggle" end
    return nil
end

function M.format_time(seconds)
    local n = math.max(0, math.floor(tonumber(seconds) or 0))
    local hours = math.floor(n / 3600)
    local minutes = math.floor((n % 3600) / 60)
    local remainder = n % 60
    if hours > 0 then
        return string.format("%d:%02d:%02d", hours, minutes, remainder)
    end
    return string.format("%02d:%02d", minutes, remainder)
end

function M.media_progress(position, length)
    local duration = math.max(0, tonumber(length) or 0)
    local current = math.max(0, tonumber(position) or 0)
    if duration <= 0 then return 0, 0 end
    if current > duration then current = duration end
    return current, current / duration
end

-- Which device an audio list is using now: its name, or nil when the list is empty.
function M.default_device(list)
    if type(list) ~= "table" then return nil end
    for _, device in ipairs(list) do
        if type(device) == "table" and device.default then
            return type(device.name) == "string" and device.name ~= "" and device.name or nil
        end
    end
    return nil
end

-- The Bluetooth rows the scene draws: the service's records with their two states as 0/1,
-- because a record's boolean field is a presence claim where the scene needs a value. Unknown
-- names are given something to draw, and at most `max` rows are kept.
-- Workspaces, for the blocks the Nexus draws: a record's boolean `active` is a presence claim,
-- so the block gets 0/1 to compare, plus a two-digit label and the window count. Records
-- without a number are skipped, and the list stops at the scene's cap.
function M.ws_rows(list, max)
    local out = {}
    if type(list) ~= "table" then return out end
    for _, w in ipairs(list) do
        if max and #out >= max then break end
        if type(w) == "table" then
            local id = tonumber(w.id)
            if id then
                local windows = tonumber(w.windows) or 0
                out[#out + 1] = { id = id, label = string.format("%02d", id), windows = windows,
                    active = w.active and 1 or 0 }
            end
        end
    end
    return out
end

function M.bt_rows(devices, max)
    local rows = {}
    if type(devices) ~= "table" then return rows end
    for _, device in ipairs(devices) do
        if max and #rows >= max then break end
        if type(device) == "table" then
            rows[#rows + 1] = {
                name = type(device.name) == "string" and device.name ~= "" and device.name or "Unknown device",
                address = type(device.address) == "string" and device.address or "",
                paired = device.paired == true and 1 or 0,
                connected = device.connected == true and 1 or 0,
            }
        end
    end
    return rows
end

-- The application streams the mixer draws: one row per stream, the id kept for the press and
-- the volume clamped to 0..1. A stream with no name still gets something to draw; a record that
-- is not a table is skipped so the rows stay contiguous and an index is a row.
function M.app_rows(apps, max)
    local rows = {}
    if type(apps) ~= "table" then return rows end
    for _, app in ipairs(apps) do
        if max and #rows >= max then break end
        if type(app) == "table" then
            local volume = tonumber(app.volume) or 0
            if volume < 0 then volume = 0 elseif volume > 1 then volume = 1 end
            local title = type(app.title) == "string" and app.title or ""
            local icon = type(app.icon) == "string" and app.icon or ""
            -- A stream's id is what the sound server calls it: a number on PulseAudio and
            -- PipeWire alike, so a text-only check would drop every real row's handle.
            local id = app.id
            if type(id) ~= "string" and type(id) ~= "number" then id = "" end
            rows[#rows + 1] = {
                id = id,
                icon = icon,
                has_icon = icon ~= "" and 1 or 0,
                name = type(app.name) == "string" and app.name ~= "" and app.name or "Unknown stream",
                title = title,
                has_title = title ~= "" and 1 or 0,
                volume = volume,
                pct = math.floor(volume * 100 + 0.5),
                muted = app.muted == true and 1 or 0,
                playing = app.playing == true and 1 or 0,
            }
        end
    end
    return rows
end

-- The plate's modules, in the order a fresh layout uses, each with the band whose shape it
-- takes: the four control cards are two columns wide, the live instruments three, the player
-- the full width. `catalogue` is fixed: a saved layout says which of them are on and in what
-- order, never what exists (D72, D73).
M.BANDS = {
    { id = "tiles", name = "CONTROL CARDS" },
    { id = "instruments", name = "INSTRUMENTS" },
    { id = "player", name = "MEDIA" },
}
M.MODULES = {
    { id = "output", name = "OUTPUT", band = "tiles" },
    { id = "display", name = "DISPLAY", band = "tiles" },
    { id = "network", name = "NETWORK", band = "tiles" },
    { id = "power", name = "POWER", band = "tiles" },
    { id = "cpu", name = "CPU LOAD", band = "instruments" },
    { id = "memory", name = "MEMORY", band = "instruments" },
    { id = "temp", name = "CPU TEMP", band = "instruments" },
    { id = "storage", name = "ROOT STORAGE", band = "instruments" },
    { id = "rx", name = "NETWORK RX", band = "instruments" },
    { id = "tx", name = "NETWORK TX", band = "instruments" },
    { id = "player", name = "MEDIA PLAYER", band = "player" },
}

local function module(id)
    for _, m in ipairs(M.MODULES) do
        if m.id == id then return m end
    end
end

local function catalogue_index(id)
    for i, m in ipairs(M.MODULES) do
        if m.id == id then return i - 1 end
    end
end

function M.module(id)
    return module(id)
end

-- The saved layout as the list of modules that are on, in order. A settings file that has
-- never carried one (or was hand-edited into nonsense) draws the whole catalogue; a table is
-- taken as it is, with unknown or repeated ids dropped, so disabling everything is allowed.
function M.modules(value)
    if type(value) ~= "table" then
        local all = {}
        for i, m in ipairs(M.MODULES) do all[i] = m.id end
        return all
    end
    local out, seen = {}, {}
    for _, id in ipairs(value) do
        if type(id) == "string" and module(id) and not seen[id] then
            out[#out + 1] = id
            seen[id] = true
        end
    end
    return out
end

-- One press on the layout panel: a module off or back on, one place up or down among the
-- modules of its own band, or the catalogue's order again. A card cannot be moved into the
-- instrument grid: its shape belongs to the band.
function M.layout_action(layout, action, id)
    local list = M.modules(layout)
    if action == "reset" then return M.modules(nil) end
    local at
    for i, value in ipairs(list) do
        if value == id then at = i; break end
    end
    if action == "toggle" then
        if at then table.remove(list, at)
        elseif module(id) then list[#list + 1] = id end
    elseif (action == "up" or action == "down") and at then
        local step = action == "up" and -1 or 1
        local band = module(id).band
        local i = at + step
        while i >= 1 and i <= #list do
            if module(list[i]).band == band then
                list[at], list[i] = list[i], list[at]
                break
            end
            i = i + step
        end
    end
    return list
end

-- The number of modules of one band that are on: the plate needs it to know how tall that
-- band is before it draws the next one.
function M.band_count(layout, band)
    local n = 0
    for _, id in ipairs(M.modules(layout)) do
        if module(id).band == band then n = n + 1 end
    end
    return n
end

-- The panel's rows: by band, the modules that are on first in their saved order and with the
-- slot the plate draws them in, then the ones that are off with no slot. A disabled row is
-- still there to be turned back on, which is what makes the panel a way back from an empty
-- plate. `y`/`hy` place the row and its band heading in the panel.
function M.module_rows(layout)
    local enabled = M.modules(layout)
    local on, slot = {}, {}
    for _, id in ipairs(enabled) do on[id] = true end
    for _, band in ipairs(M.BANDS) do
        local n = 0
        for _, id in ipairs(enabled) do
            if module(id).band == band.id then
                slot[id] = n
                n = n + 1
            end
        end
    end

    local rows, y = {}, 0
    for _, band in ipairs(M.BANDS) do
        local first = #rows + 1
        for _, id in ipairs(enabled) do
            if module(id).band == band.id then
                rows[#rows + 1] = { id = id, name = module(id).name, band = band.id, on = 1,
                    slot = slot[id], c = catalogue_index(id), y = 0, hy = 0 }
            end
        end
        for _, m in ipairs(M.MODULES) do
            if m.band == band.id and not on[m.id] then
                rows[#rows + 1] = { id = m.id, name = m.name, band = m.band, on = 0,
                    slot = -1, c = catalogue_index(m.id), y = 0, hy = 0 }
            end
        end
        if #rows >= first then
            rows[first].heading = band.name
            rows[first].hy = y
            y = y + 18
            for i = first, #rows do
                rows[i].y = y
                y = y + 26
            end
        end
    end
    for _, row in ipairs(rows) do
        row.heading = row.heading or ""
        row.has_heading = row.heading ~= "" and 1 or 0
    end
    return rows
end

-- The named layouts a settings file carries: an array of { name, modules }, at most six, with
-- a plain unique name each. Nothing, or nothing usable, gives the three the plate knows.
function M.layouts(value)
    local out, seen = {}, {}
    if type(value) == "table" then
        for _, layout in ipairs(value) do
            if type(layout) == "table" and type(layout.name) == "string" then
                local name = layout.name:gsub("^%s+", ""):gsub("%s+$", "")
                if name ~= "" and #name <= 16 and not name:find("[%c]") and not seen[name] then
                    seen[name] = true
                    out[#out + 1] = {
                        name = name,
                        modules = type(layout.modules) == "table" and M.modules(layout.modules) or {},
                    }
                end
            end
        end
    end
    if #out == 0 then return M.default_layouts() end
    return out
end

function M.default_layouts()
    local function ids(...)
        local list = {}
        for _, id in ipairs({ ... }) do
            if module(id) then list[#list + 1] = id end
        end
        return list
    end
    local all = {}
    for _, m in ipairs(M.MODULES) do all[#all + 1] = m.id end
    return {
        { name = "FULL", modules = all },
        { name = "FOCUS", modules = ids("output", "display", "network", "power",
            "cpu", "memory", "storage", "player") },
        { name = "MINIMAL", modules = ids("output", "display", "player") },
    }
end

-- The list a name stands for, or the first layout when there is no such name.
function M.layout_named(layouts, name)
    for _, layout in ipairs(layouts) do
        if layout.name == name then return layout.modules, layout.name end
    end
    return layouts[1] and layouts[1].modules or {}, layouts[1] and layouts[1].name
end

-- What a settings file means: the named layouts, the one showing and its modules. A file from
-- before the named layouts (a `nexus.modules` list and no `nexus.layouts`) keeps its arrangement
-- as a CUSTOM layout and shows that, whatever name the settings' defaults put beside it; the
-- defaults would otherwise say FULL and hide the order the user had.
function M.layout_state(saved_layouts, saved_modules, saved_name)
    local list = M.layouts(saved_layouts)
    local migrated = type(saved_layouts) ~= "table" and type(saved_modules) == "table"
    if migrated then
        table.insert(list, 1, { name = "CUSTOM", modules = M.modules(saved_modules) })
    end
    local name = migrated and "CUSTOM" or (type(saved_name) == "string" and saved_name or nil)
    local modules, picked = M.layout_named(list, name or list[1].name)
    return list, picked, modules
end

-- A copy of the current order under a new name; nil when the name is taken, unusable, or there
-- is no room for another layout.
function M.layout_add(layouts, name, modules)
    name = type(name) == "string" and name:gsub("^%s+", ""):gsub("%s+$", ""):upper() or ""
    if name == "" or #name > 16 or name:find("[%c]") or #layouts >= 6 then return nil end
    for _, layout in ipairs(layouts) do
        if layout.name == name then return nil end
    end
    local out = {}
    for i, layout in ipairs(layouts) do out[i] = layout end
    out[#out + 1] = { name = name, modules = M.modules(modules) }
    return out, name
end

-- The layouts without the named one; nil when it is the only one left.
function M.layout_remove(layouts, name)
    if #layouts <= 1 then return nil end
    local out = {}
    for _, layout in ipairs(layouts) do
        if layout.name ~= name then out[#out + 1] = layout end
    end
    if #out == #layouts then return nil end
    return out
end

-- The battery's detail line, as the POWER view says it: UPower's health and prediction, or
-- N/A when the report has nothing to say. The service still carries percent and charging.
function M.battery_detail(detail)
    local health, left = "HEALTH N/A", "TIME N/A"
    if type(detail) ~= "table" then return health, left end
    local percent = tonumber(detail.health)
    if percent and percent >= 0 and percent <= 100 then
        health = string.format("HEALTH %d%%", math.floor(percent + 0.5))
    end
    local minutes = tonumber(detail.minutes)
    if minutes and minutes >= 0 then
        left = string.format("%dH %02dM %s", math.floor(minutes / 60), math.floor(minutes % 60),
            detail.direction == "full" and "TO FULL" or "LEFT")
    elseif detail.state == "fully-charged" then left = "ON AC · FULL"
    elseif detail.state == "charging" then left = "CHARGING"
    elseif detail.state == "discharging" then left = "TIME UNKNOWN"
    end
    return health, left
end

-- The id after the current default, wrapping; nil when there is nothing to choose.
function M.next_device(list)
    if type(list) ~= "table" or #list == 0 then return nil end
    local index = 0
    for i, device in ipairs(list) do
        if type(device) == "table" and device.default then index = i break end
    end
    local next_device = list[(index % #list) + 1]
    if type(next_device) ~= "table" then return nil end
    if type(next_device.id) ~= "string" and type(next_device.id) ~= "number" then return nil end
    return next_device.id, next_device.name
end

return M
