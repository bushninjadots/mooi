-- Window class → icon, through the .desktop files pleamar's `apps` service lists.
-- A class is matched against, in order: StartupWMClass, the desktop id (also its
-- last dotted part: org.gnome.Nautilus → nautilus), the Exec program, the name.

local M = {}

local function key(s) return string.lower(tostring(s or "")) end

local function program(exec)
    local first = string.match(tostring(exec or ""), "^%s*(%S+)") or ""
    return string.match(first, "([^/]+)$") or first
end

-- Builds a lookup from the service's list. Earlier, stronger matches win.
function M.index(list)
    local by = { wmclass = {}, id = {}, exec = {}, name = {} }
    for _, a in ipairs(list or {}) do
        local icon = a.icon
        if type(icon) == "string" and icon ~= "" then
            local function put(map, k) if k ~= "" and map[k] == nil then map[k] = icon end end
            put(by.wmclass, key(a.wmclass))
            put(by.id, key(a.id))
            put(by.id, key(string.match(tostring(a.id or ""), "([^.]+)$")))
            put(by.exec, key(program(a.exec)))
            put(by.name, key(a.name))
        end
    end
    return by
end

-- The icon for a class, or nil.
function M.icon_for(index, class)
    local k = key(class)
    if k == "" or not index then return nil end
    return index.wmclass[k] or index.id[k] or index.exec[k] or index.name[k]
end

-- The .desktop entry a window of `class` belongs to ({ id, exec, … } from the service's list), by the
-- same matches as its icon, in the same order; nil when none (D43: what an environment reopens).
function M.app_for(list, class)
    local k = key(class)
    if k == "" then return nil end
    local tests = {
        function(a) return key(a.wmclass) == k end,
        function(a) return key(a.id) == k or key(string.match(tostring(a.id or ""), "([^.]+)$")) == k end,
        function(a) return key(program(a.exec)) == k end,
        function(a) return key(a.name) == k end,
    }
    for _, t in ipairs(tests) do
        for _, a in ipairs(list or {}) do if t(a) then return a end end
    end
    return nil
end

-- One letter to stand in for a missing icon.
function M.letter(class)
    return string.sub(string.match(tostring(class or ""), "[%w]") or "", 1, 1)
end

return M
