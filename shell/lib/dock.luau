-- The dock (D280; k4's Dual mode's dock, ported): what it holds and what a press does. Pure: the pinned list from
-- Settings, the apps Pleamar knows (`apps` service) and Hyprland's windows (`hyprctl -j clients`) in; the dock's
-- items out. An item is an app: pinned ones stay, running ones come and go, and windows of one app share its item.

local M = { MAX = 14 }

local function low(s) return string.lower(tostring(s or "")) end

-- the key an app goes by: its desktop id without `.desktop`, lowered
function M.key(s)
    s = low(s):gsub("%.desktop$", "")
    return s
end

-- the app a window belongs to: its class against the apps' wmclass, then their id, then the id's last part
-- (org.gnome.Nautilus → nautilus), else nil
function M.app_for(class, apps)
    local c = low(class)
    if c == "" then return nil end
    for _, a in ipairs(apps or {}) do if type(a) == "table" and low(a.wmclass) == c then return a end end
    for _, a in ipairs(apps or {}) do if type(a) == "table" and M.key(a.id) == c then return a end end
    for _, a in ipairs(apps or {}) do
        if type(a) == "table" then
            local tail = M.key(a.id):match("([^%.]+)$")
            if tail == c or tail == c:match("([^%.]+)$") then return a end
        end
    end
    return nil
end

local function app_by_key(key, apps)
    for _, a in ipairs(apps or {}) do if type(a) == "table" and M.key(a.id) == key then return a end end
    return M.app_for(key, apps)
end

-- the items: the pinned first in their order, then each running app not pinned, in the order its first window
-- appeared; each with its windows' addresses, whether one has the focus, and how it is launched
function M.items(pinned, apps, clients, active)
    local out, by = {}, {}
    local function add(key, app, is_pinned)
        if by[key] or #out >= M.MAX then return by[key] end
        local it = { key = key, name = app and tostring(app.name or key) or key, icon = app and tostring(app.icon or "") or "",
                     exec = app and tostring(app.exec or "") or "", pinned = is_pinned, windows = {}, active = false }
        out[#out + 1] = it
        by[key] = it
        return it
    end
    for _, k in ipairs(type(pinned) == "table" and pinned or {}) do
        local key = M.key(k)
        if key ~= "" then add(key, app_by_key(key, apps), true) end
    end
    for _, c in ipairs(type(clients) == "table" and clients or {}) do
        if type(c) == "table" and c.mapped ~= false and type(c.address) == "string" then
            local class = tostring(c.class or "")
            local ws = type(c.workspace) == "table" and tostring(c.workspace.name or "") or ""
            -- mooi's own surfaces and windows put away under the wallpaper are not apps in the dock
            if class ~= "" and class ~= "pleamar" and not ws:match("^special:mooi") then
                local app = M.app_for(class, apps)
                local key = app and M.key(app.id) or low(class)
                local it = by[key] or add(key, app, false)
                if it then
                    it.windows[#it.windows + 1] = c.address
                    if c.address == active then it.active = true end
                    if it.icon == "" then it.icon = low(class) end
                end
            end
        end
    end
    return out
end

-- what a press on an item does: { "launch", exec } when nothing of it runs; { "focus", address } — the next of its
-- windows after the one with the focus, so pressing again walks through them
function M.press(item, active)
    if type(item) ~= "table" then return nil end
    local w = item.windows or {}
    if #w == 0 then return item.exec ~= "" and { "launch", item.exec } or nil end
    for i, a in ipairs(w) do if a == active then return { "focus", w[i % #w + 1] } end end
    return { "focus", w[1] }
end

-- pinning: added at the end, taken out where it is; the list returned is new
function M.toggle_pin(pinned, key)
    local out, had = {}, false
    for _, k in ipairs(type(pinned) == "table" and pinned or {}) do
        if M.key(k) == key then had = true else out[#out + 1] = k end
    end
    if not had then out[#out + 1] = key end
    return out, not had
end

-- a Hyprland window address as `hyprctl dispatch` takes it, or nil
function M.address(a) return type(a) == "string" and a:match("^0x%x+$") ~= nil and a or nil end

return M
