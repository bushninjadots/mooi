-- BMO's geometry, pure: the monitors he could stand on, which one is his, and where he lands when
-- one of them changes. bmo.luau asks Hyprland and keeps the result; this only does the arithmetic,
-- so it can be tested without a compositor (tests/unit/run.lua runs it under Lua 5.4).
--
-- The rule: his monitor is the one he was on if it is still there (a desktop does not move him just
-- because another screen got the focus); if it went away, the monitor shaped like the surface he
-- draws on; failing that the focused one; failing that the first. A monitor that changed size keeps
-- him where he was in proportion, so a bigger screen does not leave him at the edge — and a measure
-- that finds nothing changed moves him not at all.

local M = {}

-- `hyprctl -j monitors` decoded, as the monitors he could use, in logical pixels. Disabled outputs
-- are left out (he cannot stand where nothing is drawn), and a turned monitor is as wide as it is
-- tall, like the bar's own measure (bar.luau).
function M.monitors(list)
    local out = {}
    for _, m in ipairs(type(list) == "table" and list or {}) do
        local w, h = tonumber(m.width), tonumber(m.height)
        local s = tonumber(m.scale) or 1
        if m.disabled ~= true and w and h and w > 0 and h > 0 and s > 0 then
            local lw, lh = math.floor(w / s + 0.5), math.floor(h / s + 0.5)
            if (tonumber(m.transform) or 0) % 2 == 1 then lw, lh = lh, lw end
            out[#out + 1] = {
                name = tostring(m.name or ""),
                id = tonumber(m.id),
                w = lw, h = lh,
                -- x and y are already layout (logical) pixels; only the size is in the monitor's own
                x = math.floor(tonumber(m.x) or 0),
                y = math.floor(tonumber(m.y) or 0),
                focused = m.focused == true,
            }
        end
    end
    return out
end

-- Which monitor is his. `name` is the one he was on (kept in bmo-state.json), `w`/`h` what his
-- surface last said it measures (nil while it has not said). Never nil unless there is no monitor
-- at all.
function M.choose(list, name, w, h)
    if type(list) ~= "table" or #list == 0 then return nil end
    if type(name) == "string" and name ~= "" then
        for _, m in ipairs(list) do if m.name == name then return m end end
    end
    if tonumber(w) and tonumber(h) then
        for _, m in ipairs(list) do if m.w == tonumber(w) and m.h == tonumber(h) then return m end end
    end
    for _, m in ipairs(list) do if m.focused then return m end end
    return list[1]
end

-- Where he goes when his monitor is `pick`, given where he stood on `prev` (nil at startup). In
-- proportion only when it is the same monitor at another size and he is already standing; the same
-- numbers otherwise, so an ordinary measure — a focus change, another monitor plugged in — does not
-- move him.
function M.fit(prev, pick, x, y, standing)
    local nx, ny = tonumber(x) or 0, tonumber(y) or 0
    if prev and pick and prev.name == pick.name and standing == true
       and (prev.w ~= pick.w or prev.h ~= pick.h) and (prev.w or 0) > 0 and (prev.h or 0) > 0 then
        nx = nx * pick.w / prev.w
        ny = ny * pick.h / prev.h
    end
    return nx, ny
end

return M
