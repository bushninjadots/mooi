-- The Mechanical Shutter (D35): a window's controls unfolding from its edge as a column of
-- plates on an angular track. This is its pure core, so tests/unit runs it: where it goes
-- (placement) and what it offers (the action registry). shell/shutter.luau runs it; the scene
-- (shell/mooi.plm, `shutter_surface`) draws what this decides.
--
-- Coordinates are the monitor's own logical pixels; `area` is the monitor less what is reserved
-- along its edges (the bar).

local M = {}

M.PLATES = { "arrange", "workspace", "behaviour", "connections" }
M.LABELS = { arrange = "ARRANGE", workspace = "WORKSPACE", behaviour = "BEHAVIOUR", connections = "CONNECTIONS" }

-- Sizes, standard and compact (shutter.density).
M.SIZES = {
    standard = { pw = 148, ph = 42, gap = 6, reach = 24, panel = 248, row = 34, pad = 8 },
    compact = { pw = 120, ph = 34, gap = 4, reach = 18, panel = 220, row = 30, pad = 6 },
}

local function clamp(v, lo, hi) if v < lo then return lo end if v > hi then return hi end return v end

-- Where it deploys. `win` and `area` are { x, y, w, h }; `opts` = { edge = "auto" | "right" |
-- "left" | "inside", density, plates = n }. Outside the window's right edge when the plates and an
-- open panel fit there, else its left; when neither fits (a tiled window filling the screen) it
-- unfolds inside the window's right edge, the panel opening inward. Returns
--   side    "right" | "left" | "inside"
--   dir     +1 the panel opens to the right of the plates, -1 to the left
--   anchor  { x, y } the window's corner the track leaves from
--   spine   x of the track's vertical run; plates { { x, y }, … }
--   pw, ph  a plate's size; sizes (the table above)
function M.place(win, area, opts)
    opts = opts or {}
    local s = M.SIZES[opts.density or "standard"] or M.SIZES.standard
    local n = opts.plates or #M.PLATES
    local colh = n * s.ph + (n - 1) * s.gap
    local right_room = (area.x + area.w) - (win.x + win.w)
    local left_room = win.x - area.x
    local need = s.reach + s.pw + s.pad + s.panel + s.pad
    local order = { "right", "left", "inside" }
    if opts.edge == "left" then order = { "left", "right", "inside" }
    elseif opts.edge == "inside" then order = { "inside" } end
    local side = "inside"
    for _, o in ipairs(order) do
        if (o == "right" and right_room >= need) or (o == "left" and left_room >= need) or o == "inside" then side = o; break end
    end
    local out = { side = side, pw = s.pw, ph = s.ph, sizes = s, plates = {} }
    local x, dir
    if side == "right" then
        x = win.x + win.w + s.reach; dir = 1
        out.anchor = { x = win.x + win.w, y = win.y }
        out.spine = x - 9
    elseif side == "left" then
        x = win.x - s.reach - s.pw; dir = -1
        out.anchor = { x = win.x, y = win.y }
        out.spine = x + s.pw + 9
    else
        -- inside: the column stands just within the right edge; the track runs down that edge
        x = win.x + win.w - s.pw - 16; dir = -1
        out.anchor = { x = win.x + win.w, y = win.y }
        out.spine = win.x + win.w - 7
    end
    -- the column starts a little below the window's top, inside the area, never off its foot
    local y0 = clamp(win.y + 18, area.y + s.pad, area.y + area.h - colh - s.pad)
    x = clamp(x, area.x + s.pad, area.x + area.w - s.pw - s.pad)
    for i = 1, n do out.plates[i] = { x = x, y = y0 + (i - 1) * (s.ph + s.gap) } end
    out.dir = dir
    out.anchor.y = clamp(out.anchor.y, area.y, area.y + area.h)
    out.anchor.x = clamp(out.anchor.x, area.x, area.x + area.w)
    return out
end

-- The panel a plate opens, `rows` tall: beside the plate on the side its `dir` says, its top level
-- with the plate's, held inside the area (it slides up rather than off the foot). When the side
-- it should open to has no room it opens the other way, so it is always on screen.
function M.panel(place, i, rows, area, extra)
    local s = place.sizes
    local p = place.plates[i]
    local h = 30 + rows * s.row + (extra or 0)
    local w = s.panel
    local x = (place.dir > 0) and (p.x + s.pw + s.pad) or (p.x - s.pad - w)
    if x + w > area.x + area.w - s.pad or x < area.x + s.pad then
        x = (place.dir > 0) and (p.x - s.pad - w) or (p.x + s.pw + s.pad)
    end
    x = clamp(x, area.x + s.pad, area.x + area.w - w - s.pad)
    local y = clamp(p.y, area.y + s.pad, area.y + area.h - h - s.pad)
    return { x = x, y = y, w = w, h = h, from_left = x > p.x }
end

-- ── The action registry ──────────────────────────────────────
-- Each plate's actions for this window as it is now. An action the window cannot take now is
-- not offered (a tiled window has no size to set, a tiled one cannot be pinned): the shutter
-- never shows a control that would do nothing. `win` is lib/hypr's client plus { ws, floating,
-- fullscreen_mode, opacity }; `ctx` = { spaces = n (the map's length), active_ws, cwd, repo,
-- siblings = n, terminal = bool }.
-- A row: { id, label, hint, kind = "act" | "branch" | "danger", toggle = it shows a state, on }.
function M.actions(plate, win, ctx)
    ctx = ctx or {}
    local out = {}
    local function add(id, label, hint, kind, on) out[#out + 1] = { id = id, label = label, hint = hint or "", kind = kind or "act", on = on == true, toggle = on ~= nil } end
    if plate == "arrange" then
        add("maximize", (win.fullscreen_mode == 1) and "Restore" or "Maximize", "Fill the work area, or back", "act", win.fullscreen_mode == 1)
        add("fullscreen", (win.fullscreen_mode == 2) and "Leave fullscreen" or "Fullscreen", "The whole monitor", "act", win.fullscreen_mode == 2)
        if win.floating then
            add("center", "Centre", "In the middle of the work area")
            add("size", "Size…", "Small, medium or large", "branch")
        else
            add("swap", "Swap…", "Trade places with a neighbour", "branch")
        end
        add("float", win.floating and "Tile" or "Float", win.floating and "Back into the layout" or "Lift it out of the layout", "act", win.floating)
    elseif plate == "workspace" then
        local ws = tonumber(win.workspace) or 0
        if ws > 1 then add("prev", "To workspace " .. (ws - 1), "The previous one, staying here") end
        if ws >= 1 and ws < 99 then add("next", "To workspace " .. (ws + 1), "The next one, staying here") end
        add("move", "Move to…", "Choose a workspace", "branch")
        add("follow", "Move and go…", "Take it there and follow", "branch")
        if ctx.active_ws and ws ~= ctx.active_ws and ctx.active_ws >= 1 then
            add("bring", "Bring here", "To workspace " .. ctx.active_ws .. ", where you are")
        end
    elseif plate == "behaviour" then
        add("float", "Floating", "Out of the tiling", "act", win.floating)
        if win.floating then add("pin", "Pinned", "On every workspace", "act", win.pinned) end
        add("opacity", "Opacity…", "How see-through it is", "branch")
        add("close", "Close window", "Ask it to close", "danger")
    elseif plate == "connections" then
        if ctx.cwd and ctx.cwd ~= "" then
            add("open_dir", "Open folder", ctx.cwd)
            if ctx.terminal then add("term_here", "Terminal here", ctx.cwd) end
            add("copy_path", "Copy path", ctx.cwd)
            if ctx.repo and ctx.repo ~= "" and ctx.repo ~= ctx.cwd then add("open_repo", "Open repository", ctx.repo) end
        end
        if (ctx.siblings or 0) > 0 then add("siblings", "Other " .. (win.class ~= "" and win.class or "app") .. " windows…", ctx.siblings .. " open", "branch") end
        add("copy_title", "Copy title", win.title ~= "" and win.title or "(no title)")
    end
    return out
end

-- The choices a branch opens (the third level): { label, value }.
M.SIZES_FLOAT = { { "Small", 960, 600 }, { "Medium", 1280, 800 }, { "Large", 1600, 960 } }
M.OPACITY = { 100, 90, 80, 70 }
M.SWAP = { { "Left", "l" }, { "Right", "r" }, { "Up", "u" }, { "Down", "d" } }

-- Is the window still the one the shutter was opened on, where it was? A closed window, or one
-- moved to a workspace not shown, dismisses it; moved or resized, it follows.
function M.track(before, now)
    if not now then return "gone" end
    if before and (before.x ~= now.x or before.y ~= now.y or before.w ~= now.w or before.h ~= now.h) then return "moved" end
    return "same"
end

return M
