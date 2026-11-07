-- Where the Sigil may live (D207, spec §5): the bar's side. Pure. The Pill (in Pill mode, with sigil.pill =
-- "sigil") is one host with room to grow below; every placed `sigil` module is an island host, compact at the
-- bar's height. The Pill comes first; at most four (the scene's hosts 0…3).

local barlayout = require("lib/barlayout")

local M = { MAX = 4, ROOM = 240 }

-- settings; layout_out = barlayout.layout's result ({ x = { module → x } }); pill = { x, w } | nil;
-- look = { top, mod_h }; screen = its width
function M.build(settings, layout_out, pill, look, screen)
    local out = {}
    local sig = type(settings) == "table" and type(settings.sigil) == "table" and settings.sigil or {}
    local bar = type(settings) == "table" and type(settings.bar) == "table" and settings.bar or {}
    local top, mh = tonumber(look and look.top) or 0, tonumber(look and look.mod_h) or 24
    local rest = sig.rest or "clock"
    if bar.mode == "pill" and sig.pill == "sigil" and type(pill) == "table" and tonumber(pill.w) and pill.w > 0 then
        out[#out + 1] = { id = "pill", kind = "pill", box = { x = pill.x, y = top, w = pill.w, h = mh },
                          room = M.ROOM, max_form = "display", rest = rest }
    end
    local x = type(layout_out) == "table" and type(layout_out.x) == "table" and layout_out.x.sigil
    if x and #out < M.MAX then
        out[#out + 1] = { id = "isl1", kind = "island", box = { x = x, y = top, w = barlayout.width("sigil", { screen = screen }), h = mh },
                          room = 0, max_form = "compact", rest = rest }
    end
    return out
end

return M
