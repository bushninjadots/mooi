-- Your monitors (D290; k4's Pantallas and Minflair's display settings, ported): the choices Settings → Displays
-- steps through, and the rule each makes. Pure: `hyprctl -j monitors` in, one monitor's next mode, scale or place
-- out, as the words `mooi display try` takes. Applying, the trial and the revert are bin/mooi's.

local M = {}

M.SCALES = { 1, 1.25, 1.5, 1.75, 2 }
M.PLACES = { "auto", "left", "right", "above", "below" }

-- "1920x1080@60.00Hz" → "1920x1080@60"; nil when it is not a mode
function M.mode(s)
    local w, h, r = tostring(s or ""):match("^(%d+)x(%d+)@([%d%.]+)")
    if not w then return nil end
    return w .. "x" .. h .. "@" .. math.floor(tonumber(r) + 0.5)
end

-- the monitor's mode now, as its availableModes write it
function M.current(m)
    return string.format("%dx%d@%d", tonumber(m.width) or 0, tonumber(m.height) or 0, math.floor((tonumber(m.refreshRate) or 0) + 0.5))
end

-- the mode one step on (d = 1) or back (d = -1) in its list, round; the list's own order is largest first
function M.next_mode(m, d)
    local modes = {}
    for _, s in ipairs(type(m.availableModes) == "table" and m.availableModes or {}) do
        local x = M.mode(s)
        if x then
            local seen = false
            for _, y in ipairs(modes) do if y == x then seen = true end end
            if not seen then modes[#modes + 1] = x end
        end
    end
    if #modes == 0 then return M.current(m) end
    local cur, at = M.current(m), 1
    for i, x in ipairs(modes) do if x == cur then at = i end end
    return modes[(at - 1 + d) % #modes + 1]
end

-- the scale one step on or back, held within the list (never round: 2 → 1 by surprise would be unkind)
function M.next_scale(m, d)
    local s, at = tonumber(m.scale) or 1, 1
    for i, v in ipairs(M.SCALES) do if math.abs(v - s) < 0.01 then at = i end end
    return M.SCALES[math.max(1, math.min(#M.SCALES, at + d))]
end

-- where a monitor goes next beside the first one: auto, then to its left, right, above, below, round
function M.next_place(place)
    local at = 1
    for i, p in ipairs(M.PLACES) do if p == place then at = i end end
    return M.PLACES[at % #M.PLACES + 1]
end

-- the place as Hyprland's position, next to the anchor monitor (the first that is not this one)
function M.position(place, m, list)
    if place == "auto" or place == nil then return "auto" end
    local a = nil
    for _, o in ipairs(list or {}) do if o.name ~= m.name then a = o; break end end
    if not a then return "auto" end
    local aw = math.floor((tonumber(a.width) or 0) / (tonumber(a.scale) or 1))
    local ah = math.floor((tonumber(a.height) or 0) / (tonumber(a.scale) or 1))
    local mw = math.floor((tonumber(m.width) or 0) / (tonumber(m.scale) or 1))
    local mh = math.floor((tonumber(m.height) or 0) / (tonumber(m.scale) or 1))
    local ax, ay = tonumber(a.x) or 0, tonumber(a.y) or 0
    if place == "left" then return (ax - mw) .. "x" .. ay end
    if place == "right" then return (ax + aw) .. "x" .. ay end
    if place == "above" then return ax .. "x" .. (ay - mh) end
    return ax .. "x" .. (ay + ah)
end

-- what is safe to hand to `mooi display try` (it reaches a Lua line Hyprland runs)
function M.safe(name, mode, pos, scale)
    return tostring(name):match("^[%w%-%.]+$") ~= nil and tostring(mode):match("^%d+x%d+@%d+$") ~= nil
        and (pos == "auto" or tostring(pos):match("^%-?%d+x%-?%d+$") ~= nil) and tonumber(scale) ~= nil
end

return M
