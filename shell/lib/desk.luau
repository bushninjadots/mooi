-- The desk (shell/mooi-desk.plm): the wallpaper drawn by mooi itself, so it can move — a parallax
-- that follows the workspaces and/or the pointer — and the picture's subject cut out and laid
-- over the desktop widgets, so they sit behind it. Pure: tests/unit runs it under Lua 5.4.
--
-- `settings.desk`:
--   on        false      the desk runs at all
--   parallax  "workspaces" | "pointer" | "both" | "off"
--   strength  0..100     how far the picture travels (it is drawn that much larger)
--   cutout    true       lay the subject (Lumen's cutout) over the widgets
--   depth     true       the subject travels further than the picture behind it

local M = {}

M.PARALLAX = { "off", "workspaces", "pointer", "both" }
M.PARALLAX_INDEX = { off = 0, workspaces = 1, pointer = 2, both = 3 }
M.CLOCK_POSITIONS = { "top-right", "top-left", "bottom-right", "bottom-left" }
M.DEFAULTS = {
    on = false, parallax = "workspaces", strength = 45, cutout = true, depth = true,
    clock = true, clock_position = "top-right", clock_24h = true, clock_seconds = false,
}

local function clamp(v, lo, hi) if v < lo then return lo end; if v > hi then return hi end; return v end

function M.normalize(v)
    v = type(v) == "table" and v or {}
    local out = {}
    out.on = v.on == true
    out.parallax = M.PARALLAX_INDEX[v.parallax] and v.parallax or M.DEFAULTS.parallax
    local s = tonumber(v.strength)
    out.strength = (s and s == s) and clamp(math.floor(s + 0.5), 0, 100) or M.DEFAULTS.strength
    out.cutout = v.cutout ~= false
    out.depth = v.depth ~= false
    out.clock = v.clock ~= false
    local valid_position = false
    for _, position in ipairs(M.CLOCK_POSITIONS) do if v.clock_position == position then valid_position = true end end
    out.clock_position = valid_position and v.clock_position or M.DEFAULTS.clock_position
    out.clock_24h = v.clock_24h ~= false
    out.clock_seconds = v.clock_seconds == true
    return out
end

-- How much larger the picture is drawn than the screen (each side gets half of it to travel in).
-- A strength of 0 still moves nothing; 100 is a tenth of the screen.
function M.overscan(strength)
    return clamp(tonumber(strength) or 0, 0, 100) / 1000
end

-- How much further the subject travels than the picture behind it, when `depth` is on.
M.DEPTH = 0.55

-- Where the active workspace sits along the row the parallax spans, 0 (the first) … 1 (the last).
-- The row runs to the highest workspace in use or the active one, at least four long, so a
-- switch from 1 to 2 is always a step and never the whole sweep.
function M.workspace_fraction(active, ids)
    active = math.max(1, math.floor(tonumber(active) or 1))
    local last = math.max(4, active)
    if type(ids) == "table" then
        for _, id in ipairs(ids) do
            local n = tonumber(id)
            if n and n > last and n < 100 then last = math.floor(n) end
        end
    end
    return (active - 1) / (last - 1)
end

-- The still the desk draws, the plate behind a floating subject, and the subject: Lumen writes
-- `desk.json` beside the settings when it applies a picture. They belong to the wallpaper only
-- while it is that picture; once the desktop wears another, the desk draws the new one alone.
function M.layers(state, current, cfg)
    cfg = M.normalize(cfg)
    local out = { wall = current or "", cut = "", floats = false }
    if type(state) ~= "table" or type(current) ~= "string" or current == "" then return out end
    if state.still ~= current then return out end
    local have_cut = type(state.cutout) == "string" and state.cutout ~= ""
    local have_plate = type(state.plate) == "string" and state.plate ~= ""
    if cfg.cutout and have_cut then
        out.cut = state.cutout
        -- a subject that travels further needs the picture behind it without the subject in it,
        -- or the subject would be seen twice
        if cfg.depth and have_plate and cfg.parallax ~= "off" then
            out.wall = state.plate
            out.floats = true
        end
    end
    return out
end


-- The first built-in desktop instrument. Kept pure so display formatting is deterministic in tests.
function M.clock_text(parts, use_24h, seconds)
    if type(parts) ~= "table" then return "--:--" end
    local hour = tonumber(parts.hour)
    local minute = tonumber(parts.min)
    local second = tonumber(parts.sec) or 0
    if not hour or not minute or hour < 0 or hour > 23 or minute < 0 or minute > 59
        or second < 0 or second > 59 then return "--:--" end
    hour, minute, second = math.floor(hour), math.floor(minute), math.floor(second)
    local suffix = ""
    if use_24h == false then
        suffix = hour >= 12 and " PM" or " AM"
        hour = hour % 12
        if hour == 0 then hour = 12 end
    end
    local out = string.format("%02d:%02d", hour, minute)
    if seconds == true then out = out .. string.format(":%02d", second) end
    return out .. suffix
end

return M
