-- The Workspace Atlas's spatial view (D36): the monitors as they are laid out, to scale, each with
-- the windows of the workspace it shows where they really are, and its workspaces as chips under
-- it. Pure, so tests/unit runs it: the geometry and what a drop lands on. The scene draws it
-- (shell/mooi.plm, `atlas_island`); shell/mooi.luau feeds it Hyprland's monitors and clients.
--
-- A presentation, not a window manager: every position comes from Hyprland, and every move goes
-- back to it.

local M = {}

M.CHIP_W, M.CHIP_H, M.CHIP_GAP = 34, 22, 4

-- `monitors`: Hyprland's (`hyprctl -j monitors`, raw); `clients`: lib/hypr's; `spaces`: the
-- workspaces service's list ({ id, monitor = name, windows }); `box` = { x, y, w, h } the room for
-- the monitors, with chips under them (`chips_h` of it). Returns
--   mons  { { name, id, x, y, w, h, ws (the one it shows), scale } … } in the box's pixels
--   wins  { [address] = { x, y, w, h, mon } } the windows on what each monitor shows
--   chips { { x, y, w, h, ws, active, windows, mon } … }
function M.spatial(monitors, clients, spaces, box)
    local list = {}
    for _, m in ipairs(type(monitors) == "table" and monitors or {}) do
        if not m.disabled then
            local s = tonumber(m.scale) or 1
            local w = (tonumber(m.width) or 1920) / s
            local h = (tonumber(m.height) or 1080) / s
            if (tonumber(m.transform) or 0) % 2 == 1 then w, h = h, w end
            list[#list + 1] = { name = tostring(m.name), id = tonumber(m.id) or 0, gx = tonumber(m.x) or 0, gy = tonumber(m.y) or 0,
                                gw = w, gh = h, ws = type(m.activeWorkspace) == "table" and tonumber(m.activeWorkspace.id) or 0 }
        end
    end
    table.sort(list, function(a, b) if a.gx ~= b.gx then return a.gx < b.gx end return a.gy < b.gy end)
    local out = { mons = {}, wins = {}, chips = {} }
    if #list == 0 then return out end
    -- the layout's bounds, fitted into the box above the chips, centred
    local x0, y0, x1, y1 = math.huge, math.huge, -math.huge, -math.huge
    for _, m in ipairs(list) do
        x0 = math.min(x0, m.gx); y0 = math.min(y0, m.gy); x1 = math.max(x1, m.gx + m.gw); y1 = math.max(y1, m.gy + m.gh)
    end
    local chips_h = box.chips_h or (M.CHIP_H + 12)
    local avail_h = box.h - chips_h
    local scale = math.min(box.w / (x1 - x0), avail_h / (y1 - y0))
    local ox = box.x + (box.w - (x1 - x0) * scale) / 2
    local oy = box.y + (avail_h - (y1 - y0) * scale) / 2
    for i, m in ipairs(list) do
        local r = { name = m.name, id = m.id, ws = m.ws, scale = scale,
                    x = ox + (m.gx - x0) * scale, y = oy + (m.gy - y0) * scale, w = m.gw * scale, h = m.gh * scale }
        out.mons[i] = r
        -- its workspaces, in order, under it (as many as fit across it, the active one always)
        local mine = {}
        for _, s in ipairs(type(spaces) == "table" and spaces or {}) do
            if s.monitor == m.name and (tonumber(s.id) or 0) >= 1 then mine[#mine + 1] = s end
        end
        table.sort(mine, function(a, b) return a.id < b.id end)
        local cx = r.x
        for _, s in ipairs(mine) do
            if cx + M.CHIP_W <= r.x + math.max(r.w, M.CHIP_W) then
                out.chips[#out.chips + 1] = { x = cx, y = r.y + r.h + 8, w = M.CHIP_W, h = M.CHIP_H, ws = s.id,
                                              active = s.id == m.ws, windows = tonumber(s.windows) or 0, mon = i }
                cx = cx + M.CHIP_W + M.CHIP_GAP
            end
        end
    end
    for _, c in ipairs(type(clients) == "table" and clients or {}) do
        for i, m in ipairs(list) do
            if c.monitor == m.id and c.workspace == m.ws then
                local r = out.mons[i]
                out.wins[c.address] = { x = r.x + (c.x - m.gx) * scale, y = r.y + (c.y - m.gy) * scale,
                                        w = math.max(6, c.w * scale), h = math.max(6, c.h * scale), mon = i }
            end
        end
    end
    return out
end

-- What a window carried to (x, y) lands on: a chip (that workspace), or a monitor (the workspace it
-- shows). Returns the workspace id, or nil (nowhere it can go).
function M.drop(sp, x, y)
    for _, c in ipairs(sp.chips) do
        if x >= c.x and x <= c.x + c.w and y >= c.y and y <= c.y + c.h then return c.ws end
    end
    for _, m in ipairs(sp.mons) do
        if x >= m.x and x <= m.x + m.w and y >= m.y and y <= m.y + m.h then return (m.ws > 0) and m.ws or nil end
    end
    return nil
end

-- The Overview's grid on a monitor `w` × `h` (logical), after iNiR's workspace view: one panel
-- just under the bar (`top`, the bar's reserve), rows × columns of the screen at SCALE, smaller only
-- when that would not fit across the screen or above its lower part (the hint line goes under it).
-- `scale` is the workspace's share of the screen (Settings → Overview → Size; SCALE when not given).
-- Returns { cw, ch, gx, gy, gap }.
M.SCALE = 0.18
M.SEARCH_H = 40   -- the search row on top of the panel (D41)
function M.grid(w, h, rows, cols, top, scale)
    local gap = 6
    scale = tonumber(scale) or M.SCALE
    rows, cols, top = math.max(1, rows), math.max(1, cols), top or 0
    local asp = w / math.max(h, 1)
    local cw = math.min(w * scale, (w * 0.94 - (cols - 1) * gap) / cols, (h * 0.8 - top - M.SEARCH_H - (rows - 1) * gap) / rows * asp)
    return { cw = cw, ch = cw / asp, gap = gap, gx = (w - (cols * cw + (cols - 1) * gap)) / 2, gy = top + 28 + M.SEARCH_H }
end

-- The Overview as a strip (D38): `n` miniatures in one row just under the bar (`top`, the bar's
-- reserve), each 13 % of the screen's height, smaller when the row would pass 94 % of its width.
-- Same shape as `grid`, so the scene draws both alike.
function M.strip(w, h, n, top)
    local gap = 14
    n = math.max(1, n)
    local asp = w / math.max(h, 1)
    local cw = math.min(h * 0.13 * asp, (w * 0.94 - (n - 1) * gap) / n)
    return { cw = cw, ch = cw / asp, gap = gap, gx = (w - (n * cw + (n - 1) * gap)) / 2, gy = (top or 0) + 22 }
end

-- Privacy (D38): what the Atlas and the Overview may show of a window. `mode` is the setting
-- atlas.private — "off" (everything), "sensitive" (password managers and private browsing keep
-- their picture and title to themselves), "everything" (no pictures or titles at all, only app names:
-- for sharing the screen). Returns whether its picture is kept back, and the title to show.
M.SENSITIVE_APPS = { "keepassxc", "bitwarden", "1password", "enpass", "protonpass", "proton pass",
                     "seahorse", "kwalletmanager", "passwordsafe", "secrets", "authenticator" }
M.PRIVATE_TITLES = { "private browsing", "incognito", "inprivate", "private window" }
function M.private(mode, app, title)
    app, title = tostring(app or ""), tostring(title or "")
    if mode == "everything" then return true, app ~= "" and app or "window" end
    if mode ~= "sensitive" then return false, title end
    local a, t = string.lower(app), string.lower(title)
    for _, k in ipairs(M.SENSITIVE_APPS) do
        if string.find(a, k, 1, true) then return true, "Private window" end
    end
    for _, k in ipairs(M.PRIVATE_TITLES) do
        if string.find(t, k, 1, true) then return true, "Private window" end
    end
    return false, title
end

-- ── Several monitors (D44) ──────────────────────────────────
-- Where each workspace of a page (`ids`) lives, from the workspaces service's list (`spaces`: { id,
-- monitor }) and Hyprland's `monitors`: `mon` its monitor's name (only with more than one — with one
-- there is nothing to tell apart), `elsewhere` whether another monitor than the focused one shows
-- it right now. `multi` says whether there is more than one.
function M.cell_monitors(ids, spaces, monitors)
    local mons = {}
    for _, m in ipairs(type(monitors) == "table" and monitors or {}) do if not m.disabled then mons[#mons + 1] = m end end
    local out = { multi = #mons > 1 }
    local on, shown_by = {}, {}
    for _, s in ipairs(type(spaces) == "table" and spaces or {}) do on[tonumber(s.id) or -1] = s.monitor end
    for _, m in ipairs(mons) do
        local a = type(m.activeWorkspace) == "table" and tonumber(m.activeWorkspace.id) or nil
        if a and not m.focused then shown_by[a] = m.name end
    end
    for k, id in ipairs(ids) do
        out[k] = { mon = out.multi and (on[id] or "") or "", elsewhere = out.multi and shown_by[id] ~= nil }
    end
    return out
end

-- ── The Overview's hands (D39, D41) ─────────────────────────
-- The window after tile `current` (0-based) in cell `cell` — before it with `step` -1 —, going round;
-- -1 when the cell has none.
function M.next_window(tiles, cell, current, step)
    local n = #tiles
    step = (step == -1) and -1 or 1
    if step == -1 and current < 0 then current = n end
    for k = 1, n do
        local i = ((current + k * step) % n + n) % n
        if tiles[i + 1].ocell == cell then return i end
    end
    return -1
end

-- The Overview's search (D41): `query` against each window on the page (title or app) and each
-- workspace (its name, or its number typed alone), any case. Returns which tiles and cells match,
-- the first window found (0-based, -1 none) and the cell to go to (-1 none); a number goes to that
-- workspace before any window that has it in its title.
function M.search(tiles, cells, query)
    local q = string.lower((string.gsub(tostring(query or ""), "^%s*(.-)%s*$", "%1")))
    local out = { active = q ~= "", tiles = {}, cells = {}, first_tile = -1, first_cell = -1, count = 0 }
    local by_cell = {}
    for k, c in ipairs(cells) do
        local hit = out.active and (tostring(c.id) == q or (c.name ~= "" and string.find(string.lower(c.name), q, 1, true) ~= nil)
                                    or ((c.group or "") ~= "" and string.find(string.lower(c.group), q, 1, true) ~= nil))
        out.cells[k] = hit or false
        by_cell[k - 1] = k
    end
    local number = tonumber(q)
    if number then
        for k, c in ipairs(cells) do if c.id == number then out.first_cell = k - 1 end end
    end
    for i, t in ipairs(tiles) do
        local on_page = (t.ocell or -1) >= 0 and by_cell[t.ocell] ~= nil
        local hit = out.active and on_page and (string.find(string.lower(t.title or ""), q, 1, true) ~= nil
                                                or string.find(string.lower(t.app or ""), q, 1, true) ~= nil)
        out.tiles[i] = hit or false
        if hit then
            out.count = out.count + 1
            out.cells[t.ocell + 1] = true
            if out.first_tile < 0 and out.first_cell < 0 then out.first_tile, out.first_cell = i - 1, t.ocell end
        end
    end
    if out.first_cell < 0 then
        for k = 1, #cells do if out.cells[k] then out.first_cell = k - 1; break end end
    end
    for k = 1, #cells do if out.cells[k] and out.first_tile < 0 then out.count = out.count + 1; break end end
    return out
end

-- A workspace's menu (D41): only what can be done there. `held` is how many windows would move
-- here; `win` ({ app, marked }), when it was opened on a window, puts that window's rows first.
-- Each item: { kind, label, danger }.
function M.menu(cell, held, win)
    local items = {}
    local function add(kind, label, danger) items[#items + 1] = { kind = kind, label = label, danger = danger or false } end
    if win then
        add("mark", (win.marked and "Unmark " or "Mark ") .. win.app)
        add("close_win", "Close " .. win.app, true)
    end
    if not cell.active then add("go", "Go to workspace " .. cell.id) end
    if held > 0 then add("bring", held == 1 and "Move 1 window here" or ("Move " .. held .. " windows here")) end
    add("rename", "Rename")
    add("accent", "Next accent")
    add("group", cell.group and cell.group ~= "" and ("Group: " .. cell.group .. " ›") or "Group ›")
    local n = tonumber(cell.windows) or 0
    if n > 0 then add("close", n == 1 and "Close its window" or ("Close its " .. n .. " windows"), true) end
    return items
end

-- A window let go in its own workspace (D45): `px`, `py` where the pointer is, as a share of the cell;
-- `ox`, `oy` where on the window it was held, as a share of the cell too. A floating window is placed
-- there (its corner, kept on the screen); a tiled one let go on another tiled one swaps with it; on
-- anything else Hyprland's tiling decides, so nothing is done. Returns { kind = "place", fx, fy } ·
-- { kind = "swap", target } · { kind = "none", target? }.
function M.rearrange(tiles, i, px, py, ox, oy)
    local me = tiles[i + 1]
    if not me then return { kind = "none" } end
    if me.floating then
        local fx = math.max(0, math.min(1 - (me.fw or 0), px - (ox or 0)))
        local fy = math.max(0, math.min(1 - (me.fh or 0), py - (oy or 0)))
        return { kind = "place", fx = fx, fy = fy }
    end
    local under = nil
    for k, t in ipairs(tiles) do
        if k ~= i + 1 and t.ocell == me.ocell and px >= t.fx and px <= t.fx + t.fw and py >= t.fy and py <= t.fy + t.fh then under = t end
    end
    if under and not under.floating then return { kind = "swap", target = under.address } end
    return { kind = "none", target = under and under.address or nil }
end

-- What carrying tile `i` (0-based) to workspace `to` moves: every marked window when it is one of
-- them, else itself — less those already there. `marked` is a set of addresses. Each move keeps
-- where it came from, so it can be undone.
function M.carry(tiles, marked, i, to)
    local item = tiles[i + 1]
    if not item then return {} end
    local out = {}
    local function add(t)
        local from = tonumber(t.ws)
        if from ~= to then out[#out + 1] = { address = t.address, from = from, to = to } end
    end
    if marked[item.address] then
        for _, t in ipairs(tiles) do if marked[t.address] then add(t) end end
    else add(item) end
    return out
end

-- Undoing `moves`: only a window that still exists and is still where the move put it goes back
-- (one the user carried on since, or closed, is left alone). Returns the moves back and how many
-- were left out.
function M.undo(moves, clients)
    local now = {}
    for _, c in ipairs(type(clients) == "table" and clients or {}) do now[c.address] = c.workspace end
    local back, skipped = {}, 0
    for _, m in ipairs(moves or {}) do
        if now[m.address] == m.to and m.from then back[#back + 1] = { address = m.address, from = m.to, to = m.from }
        else skipped = skipped + 1 end
    end
    return back, skipped
end

-- ── Workspace identity (D39) ────────────────────────────────
-- A name and an accent per workspace, mooi's own (its data folder, `workspaces.json`): not a
-- Hyprland workspace rule, and never written into one. The accents are the palette's two signals.
M.NAME_MAX = 24
M.ACCENTS = { "none", "phos", "ember" }
M.VERSION = 1

local function cut(s, n)
    local ok, len = pcall(utf8.len, s)
    if not ok or not len then return string.sub(s, 1, n) end
    if len <= n then return s end
    return string.sub(s, 1, utf8.offset(s, n + 1) - 1)
end
local function accent_ok(a)
    for _, k in ipairs(M.ACCENTS) do if k == a then return a end end
    return "none"
end

-- A store read from disk, checked: unknown keys, junk and a newer version than this one are left
-- out (a newer file is not guessed at, and not written over until something is changed). Groups
-- (D42) are an ordered list: a name, an accent, the workspaces in it — each workspace in one group
-- at most (the first that claims it), no empty group, GROUPS_MAX of them.
M.GROUPS_MAX = 12
local function clean_name(s) return type(s) == "string" and cut((string.gsub(s, "^%s+", "")):gsub("%s+$", ""), M.NAME_MAX) or "" end
function M.identities(raw)
    local out = { version = M.VERSION, spaces = {}, groups = {}, canvas = {} }
    if type(raw) ~= "table" or (raw.version ~= nil and raw.version ~= M.VERSION) then return out end
    -- the canvas (D47): a territory's corner, anywhere on the field within a million pixels
    for k, v in pairs(type(raw.canvas) == "table" and raw.canvas or {}) do
        local id = tonumber(k)
        local x, y = type(v) == "table" and tonumber(v[1]), type(v) == "table" and tonumber(v[2])
        if id and id >= 1 and id == math.floor(id) and x and y and x == x and y == y and math.abs(x) < 1000000 and math.abs(y) < 1000000 then
            out.canvas[tostring(id)] = { math.floor(x + 0.5), math.floor(y + 0.5) }
        end
    end
    local claimed = {}
    for _, g in ipairs(type(raw.groups) == "table" and raw.groups or {}) do
        if type(g) == "table" and #out.groups < M.GROUPS_MAX then
            local ids = {}
            for _, v in ipairs(type(g.spaces) == "table" and g.spaces or {}) do
                local id = tonumber(v)
                if id and id >= 1 and id == math.floor(id) and not claimed[id] then claimed[id] = true; ids[#ids + 1] = id end
            end
            table.sort(ids)
            if #ids > 0 then
                local name = clean_name(g.name)
                out.groups[#out.groups + 1] = { name = name ~= "" and name or "Group", accent = g.accent == "none" and "none" or accent_ok(g.accent) == "none" and "phos" or g.accent, spaces = ids }
            end
        end
    end
    if type(raw.spaces) ~= "table" then return out end
    for k, v in pairs(raw.spaces) do
        local id = tonumber(k)
        if id and id >= 1 and id == math.floor(id) and type(v) == "table" then
            local name = clean_name(v.name)
            local accent = accent_ok(v.accent)
            if name ~= "" or accent ~= "none" then out.spaces[tostring(id)] = { name = name, accent = accent } end
        end
    end
    return out
end

function M.identity(store, id)
    local v = store and store.spaces and store.spaces[tostring(id)]
    return { name = v and v.name or "", accent = v and v.accent or "none" }
end

function M.name(store, id, name)
    local v = M.identity(store, id)
    store.spaces[tostring(id)] = { name = name, accent = v.accent }
    return M.identities(store)
end

function M.next_accent(store, id)
    local v = M.identity(store, id)
    local k = M.accent_index(v.accent)
    store.spaces[tostring(id)] = { name = v.name, accent = M.ACCENTS[(k + 1) % #M.ACCENTS + 1] }
    return M.identities(store)
end

-- ── Workspace groups (D42) ──────────────────────────────────
-- mooi's own way of keeping workspaces together ("Dev", 1 to 3): a name and a colour over them in the
-- Overview, found by its name. Not a Hyprland workspace, never written into its rules; taking a group
-- away leaves its workspaces and their windows exactly as they are. Each returns the checked store.
function M.group_of(store, id)
    for gi, g in ipairs(store.groups or {}) do
        for _, s in ipairs(g.spaces) do if s == id then return gi, g end end
    end
    return nil
end
local function without(store, id)
    for _, g in ipairs(store.groups) do
        for i = #g.spaces, 1, -1 do if g.spaces[i] == id then table.remove(g.spaces, i) end end
    end
end
function M.group_new(store, id, name)
    without(store, id)
    table.insert(store.groups, { name = name, accent = "phos", spaces = { id } })
    return M.identities(store)
end
function M.group_join(store, gi, id)
    if not store.groups[gi] then return store end
    without(store, id)
    table.insert(store.groups[gi].spaces, id)
    return M.identities(store)
end
function M.group_leave(store, id)
    without(store, id)
    return M.identities(store)
end
function M.group_rename(store, gi, name)
    if store.groups[gi] and clean_name(name) ~= "" then store.groups[gi].name = name end
    return M.identities(store)
end
function M.group_next_accent(store, gi)
    local g = store.groups[gi]
    if g then g.accent = M.ACCENTS[(M.accent_index(g.accent) + 1) % #M.ACCENTS + 1] end
    return M.identities(store)
end
function M.group_remove(store, gi)
    if store.groups[gi] then table.remove(store.groups, gi) end
    return M.identities(store)
end

-- How each cell of a page (`ids`, in order, `cols` across) wears its group: `grp` its group's index
-- (-1 none), `gacc` its accent by number, `gname` its name, `gfirst` whether the name is drawn here
-- (its first member on the page), `glink` whether the next cell in the row is in the same group (the
-- line runs across the gap).
function M.group_marks(store, ids, cols, slots)
    cols = math.max(cols or 1, 1)
    slots = slots or {}
    local function slot(k) return slots[k] or { sc = (k - 1) % cols, sr = math.floor((k - 1) / cols) } end
    local out, at = {}, {}
    for k, id in ipairs(ids) do
        local gi, g = M.group_of(store, id)
        out[k] = { grp = gi and gi - 1 or -1, gacc = g and M.accent_index(g.accent) or 0, gname = g and g.name or "", gfirst = false, glink = false }
        at[slot(k).sc .. "," .. slot(k).sr] = k
    end
    -- named on its first workspace in reading order (row, then column), joined to the one on its right
    local order = {}
    for k = 1, #ids do order[k] = k end
    table.sort(order, function(a, b)
        local sa, sb = slot(a), slot(b)
        if sa.sr ~= sb.sr then return sa.sr < sb.sr end
        return sa.sc < sb.sc
    end)
    local seen = {}
    for _, k in ipairs(order) do
        local grp = out[k].grp
        if grp >= 0 and not seen[grp] then seen[grp] = true; out[k].gfirst = true end
        local right = at[(slot(k).sc + 1) .. "," .. slot(k).sr]
        out[k].glink = grp >= 0 and right ~= nil and out[right].grp == grp
    end
    return out
end

-- The menu's group page for workspace `id`: join another, start one, or — in one — leave it,
-- rename it, its accent, take it away; and back. Each item: { kind, label, danger, group }.
function M.group_menu(store, id)
    local items = {}
    local function add(kind, label, gi, danger) items[#items + 1] = { kind = kind, label = label, group = gi or 0, danger = danger or false } end
    local mine, g = M.group_of(store, id)
    for gi, other in ipairs(store.groups) do
        if gi ~= mine and #items < 3 then add("gjoin", "Join " .. other.name, gi) end
    end
    add("gnew", "New group…")
    if mine then
        add("gleave", "Leave " .. g.name, mine)
        add("grename", "Rename " .. g.name .. "…", mine)
        add("gaccent", "Next colour for " .. g.name, mine)
        add("gremove", "Take " .. g.name .. " away", mine, true)
    end
    add("back", "‹ Back")
    return items
end

-- ── The canvas (D47) ────────────────────────────────────────
-- An infinite field the Overview's camera pans and zooms over. Each workspace is a territory on it:
-- its monitor at full size (one unit is one screen pixel, so 100 % is a territory the size of the
-- screen), placed where it was put — mooi's own arrangement, kept in workspaces.json (`canvas`: a
-- workspace's corner, x and y); Hyprland's workspaces stay numbered as they are.
M.ZMIN, M.ZMAX = 0.03, 1.5
M.GAP_X, M.GAP_Y = 0.12, 0.24          -- between territories laid out by themselves, as shares of one

local function overlaps(a, b, m)
    m = m or 0
    return a.x < b.x + b.w + m and b.x < a.x + a.w + m and a.y < b.y + b.h + m and b.y < a.y + a.h + m
end

-- Each workspace of `ids` as a territory { x, y, w, h }: where it was put, else the next free place
-- in reading order (`cols` across) that does not touch one already placed.
function M.territories(ids, canvas, W, H, cols)
    canvas = canvas or {}
    cols = math.max(cols or 5, 1)
    local sx, sy = W * (1 + M.GAP_X), H * (1 + M.GAP_Y)
    local out, placed, later = {}, {}, {}
    for k, id in ipairs(ids) do
        local v = canvas[tostring(id)]
        if v then out[k] = { x = v[1], y = v[2], w = W, h = H }; placed[#placed + 1] = out[k]
        else later[#later + 1] = k end
    end
    local spot = 0
    for _, k in ipairs(later) do
        local r
        repeat
            r = { x = math.floor((spot % cols) * sx + 0.5), y = math.floor(math.floor(spot / cols) * sy + 0.5), w = W, h = H }
            spot = spot + 1
            local free = true
            for _, p in ipairs(placed) do if overlaps(r, p, W * M.GAP_X / 2) then free = false end end
        until free or spot > 400
        out[k] = r; placed[#placed + 1] = r
    end
    return out
end

-- The territory (1-based) a world point is in, or nil on the open field.
function M.at_world(rects, x, y)
    for k = #rects, 1, -1 do
        local r = rects[k]
        if x >= r.x and x <= r.x + r.w and y >= r.y and y <= r.y + r.h then return k end
    end
    return nil
end

-- The camera (its world corner and zoom) that shows every territory in a `vw` × `vh` view whose
-- top `top` pixels are the bar's, `pad` clear all round.
function M.fit(rects, vw, vh, top, pad)
    if #rects == 0 then return 0, 0, 0.2 end
    local x0, y0, x1, y1 = math.huge, math.huge, -math.huge, -math.huge
    for _, r in ipairs(rects) do
        x0, y0 = math.min(x0, r.x), math.min(y0, r.y)
        x1, y1 = math.max(x1, r.x + r.w), math.max(y1, r.y + r.h)
    end
    local aw, ah = vw - 2 * pad, vh - top - 2 * pad
    local z = math.max(M.ZMIN, math.min(M.ZMAX, aw / (x1 - x0), ah / (y1 - y0)))
    local cx = (x0 + x1) / 2 - vw / 2 / z
    local cy = (y0 + y1) / 2 - (top + (vh - top) / 2) / z
    return cx, cy, z
end

-- The camera that fills a `vw`-wide screen with territory `r` (it has the screen's shape).
function M.focus_cam(r, vw)
    return r.x, r.y, vw / math.max(r.w, 1)
end

function M.snap(v, step) return math.floor(v / step + 0.5) * step end

-- The nearest territory from territory `k` (0-based) toward `dir`, by their centres — straight
-- that way before off to the side; nil when there is none that way.
function M.near(rects, k, dir)
    local me = rects[k + 1]
    if not me then return nil end
    local mx, my = me.x + me.w / 2, me.y + me.h / 2
    local best, score = nil, math.huge
    for j, r in ipairs(rects) do
        local dx, dy = r.x + r.w / 2 - mx, r.y + r.h / 2 - my
        local along, across = 0, 0
        if dir == "right" then along, across = dx, dy elseif dir == "left" then along, across = -dx, dy
        elseif dir == "down" then along, across = dy, dx else along, across = -dy, dx end
        if j ~= k + 1 and along > 1 then
            local sc = along + 3 * math.abs(across)
            if sc < score then best, score = j - 1, sc end
        end
    end
    return best
end

function M.canvas_place(store, id, x, y)
    store.canvas = store.canvas or {}
    store.canvas[tostring(id)] = { math.floor(x + 0.5), math.floor(y + 0.5) }
    return M.identities(store)
end

function M.canvas_reset(store)
    store.canvas = {}
    return M.identities(store)
end

-- The scene picks a colour by number: 0 none, 1 phos, 2 ember.
function M.accent_index(a)
    for i, k in ipairs(M.ACCENTS) do if k == a then return i - 1 end end
    return 0
end

return M
