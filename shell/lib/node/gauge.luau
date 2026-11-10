-- The node's gauge (D265; Minflair's on-screen display, ported): each reading as the icon, the words and how full
-- the bar is. Pure, so the unit suite runs it; the logic decides when one grows.

local M = {}

local function pct(v) return math.floor(math.max(0, math.min(1, tonumber(v) or 0)) * 100 + 0.5) end

function M.volume(v, muted)
    if muted then return { icon = "󰝟", label = "MUTED", level = 0 } end
    local p = pct(v)
    return { icon = p == 0 and "󰕿" or p < 50 and "󰖀" or "󰕾", label = "VOLUME " .. p .. "%", level = p / 100 }
end

function M.mic(muted)
    if muted then return { icon = "󰍭", label = "MICROPHONE OFF", level = 0, warm = true } end
    return { icon = "󰍬", label = "MICROPHONE ON", level = 1 }
end

function M.light(l)
    local p = pct(l)
    return { icon = p < 50 and "󰃞" or "󰃠", label = "BRIGHTNESS " .. p .. "%", level = p / 100 }
end

-- the cable going in or coming out, with the battery as it stands
function M.cable(charging, bat)
    local p = tonumber(bat)
    local level = p and math.max(0, math.min(1, p / 100)) or (charging and 1 or 0)
    local tail = p and (" · " .. math.floor(p + 0.5) .. "%") or ""
    if charging then return { icon = "󰂄", label = "CHARGING" .. tail, level = level } end
    return { icon = "󰁹", label = "ON BATTERY" .. tail, level = level }
end

-- a key's lock light (`mooi osd caps|num`): which one, and whether it is lit now
local LOCKS = { caps = { "󰪛", "CAPS LOCK" }, num = { "󰎠", "NUM LOCK" } }
function M.lock(which, on)
    local l = LOCKS[which]
    if not l then return nil end
    return { icon = l[1], label = l[2] .. (on and " ON" or " OFF"), level = on and 1 or 0 }
end

-- game mode (D266) turned on or off
function M.game(on)
    return { icon = "󰊴", label = on and "GAME MODE ON" or "GAME MODE OFF", level = on and 1 or 0, warm = on }
end

-- `nd_osd`'s code from `mooi osd`: tens say which, the unit whether it is on (11 caps on, 20 num off, 31 game on)
function M.decode(v)
    v = math.floor(tonumber(v) or 0)
    local which, on = v // 10, v % 10 == 1
    if which == 1 then return M.lock("caps", on) end
    if which == 2 then return M.lock("num", on) end
    if which == 3 then return M.game(on) end
    return nil
end

return M
