-- What the desktop was used for (D105): a minute at a time, by day, hour and app. Pure, so
-- tests/unit runs it; shell/activity.luau asks Hyprland every minute and keeps activity.json.

local M = {}

M.KEEP_DAYS = 8

-- `doc` with one more minute of `app` at the time `t` (os.date's fields: year, month, day, hour);
-- days older than KEEP_DAYS go. An empty app counts the hour and no app (the desktop itself).
function M.add(doc, t, app)
    doc = type(doc) == "table" and doc or {}
    doc.days = type(doc.days) == "table" and doc.days or {}
    local key = string.format("%04d-%02d-%02d", t.year, t.month, t.day)
    local day = type(doc.days[key]) == "table" and doc.days[key] or {}
    day.hours = type(day.hours) == "table" and day.hours or {}
    day.apps = type(day.apps) == "table" and day.apps or {}
    local h = tostring(t.hour)
    day.hours[h] = (tonumber(day.hours[h]) or 0) + 1
    app = tostring(app or "")
    if app ~= "" then day.apps[app] = (tonumber(day.apps[app]) or 0) + 1 end
    doc.days[key] = day
    -- the oldest go: keys sort as dates
    local keys = {}
    for k in pairs(doc.days) do keys[#keys + 1] = k end
    table.sort(keys)
    for i = 1, #keys - M.KEEP_DAYS do doc.days[keys[i]] = nil end
    doc.version = 1
    return doc
end

return M
