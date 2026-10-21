-- Signal Loom (D50): mooi's notifications as signals. Pure, so tests/unit runs it under plain
-- Lua 5.4 (written in the subset Lua 5.4 and Luau share); shell/signals.luau feeds it the
-- notification server's list and hands what it works out to the scene.
--
-- What a notification can tell us is what the server passes: { id, app, title, body, icon,
-- image, urgency, time, actions = { { key, label } } }. Nothing here is guessed beyond that: no
-- progress, no category, no "this looks urgent" from the words. Three tiers:
--   whisper       a low-urgency notice, one from an app you muted, or anything but an urgent one
--                 while you are not to be disturbed: a slim signal that comes and goes
--   manifest      a normal notice: a segment that unfolds with what it says and what it offers
--   intervention  one its sender marked critical: it stays until it is dealt with
-- Related notices are one signal: the same app and the same title (a conversation, a repeated
-- job) are a thread; a thread's newest notice speaks for it, with how many there are.

local M = {}

M.WHISPER, M.MANIFEST, M.INTERVENTION = 0, 1, 2
M.TITLE_MAX, M.BODY_MAX, M.APP_MAX, M.LABEL_MAX = 120, 600, 40, 24

local function cut(s, n)
    if #s <= n then return s end
    -- never in the middle of a character: back off to the start of one
    local i = n
    while i > 0 and string.byte(s, i + 1) and string.byte(s, i + 1) >= 0x80 and string.byte(s, i + 1) < 0xC0 do i = i - 1 end
    return string.sub(s, 1, i) .. "…"
end

local ENTITIES = { amp = "&", lt = "<", gt = ">", quot = '"', apos = "'" }

-- A notification's text as plain text: the body markup the standard allows (<b>, <i>, <u>,
-- <a href>, <img>) taken out, its entities read, control characters made spaces, runs of space
-- made one, and cut to `n`. Anything that is not a string is "".
function M.plain(s, n)
    if type(s) ~= "string" then return "" end
    s = string.gsub(s, "<[^>]*>", "")
    s = string.gsub(s, "&(%a+);", function(e) return ENTITIES[e] or ("&" .. e .. ";") end)
    s = string.gsub(s, "&#(%d+);", function(d)
        local c = tonumber(d)
        return (c and c >= 32 and c < 127) and string.char(c) or " "
    end)
    s = string.gsub(s, "%c", " ")
    s = string.gsub(string.gsub(s, "^%s+", ""), "%s+$", "")
    s = string.gsub(s, "%s%s+", " ")
    return cut(s, n or M.BODY_MAX)
end

-- The urgency the sender gave it: the server passes the standard's number (0 low, 1 normal,
-- 2 critical); a name is taken too. Anything else is normal.
function M.urgency(u)
    if u == 2 or u == "critical" then return "critical" end
    if u == 0 or u == "low" then return "low" end
    return "normal"
end

-- One notification as the loom keeps it, whatever came in: every field there and of its type.
-- `actions` keeps the buttons the app offers (not "default", which is a press on the notice
-- itself); `default` says whether it has one.
function M.clean(n)
    if type(n) ~= "table" or n.id == nil then return nil end
    local out = {
        id = n.id, app = M.plain(n.app, M.APP_MAX), title = M.plain(n.title, M.TITLE_MAX),
        body = M.plain(n.body, M.BODY_MAX),
        icon = type(n.icon) == "string" and n.icon or "", image = type(n.image) == "string" and n.image or "",
        urgency = M.urgency(n.urgency),
        time = tonumber(n.time) or 0, actions = {}, default = false,
    }
    for _, a in ipairs(type(n.actions) == "table" and n.actions or {}) do
        if type(a) == "table" and type(a.key) == "string" then
            if a.key == "default" then out.default = true
            elseif #out.actions < 3 then
                local label = M.plain(a.label, M.LABEL_MAX)
                if label ~= "" then out.actions[#out.actions + 1] = { key = a.key, label = label } end
            end
        end
    end
    return out
end

-- The tier a notice arrives at. `opts`: { muted = { [app] = true }, quiet = bool }.
function M.tier(n, opts)
    opts = opts or {}
    if n.urgency == "critical" then return M.INTERVENTION end
    if n.urgency == "low" then return M.WHISPER end
    if opts.muted and opts.muted[n.app] then return M.WHISPER end
    if opts.quiet then return M.WHISPER end
    return M.MANIFEST
end

-- The layout a notice takes, from what it carries (never from its words): an alert (critical),
-- a conversation (it brings a picture: a sender's photo, a contact), or an event.
M.EVENT, M.CONVERSATION, M.ALERT = 0, 1, 2
function M.kind(n)
    if n.urgency == "critical" then return M.ALERT end
    if n.image ~= "" then return M.CONVERSATION end
    return M.EVENT
end

-- The key a notice is grouped under. `mode`: "thread" (app and title: a conversation, a repeated
-- job), "app" (everything from one app), or "off" (each on its own).
function M.key(n, mode)
    if mode == "off" then return "#" .. tostring(n.id) end
    if mode == "app" then return string.lower(n.app) end
    return string.lower(n.app) .. "\31" .. string.lower(n.title)
end

-- The notices in groups, newest first: { key, app, title, newest = notice, items = { … newest
-- first }, count, critical = any is, time = the newest one's }. `list` is newest first already
-- (the server's order), and so is each group's `items`.
function M.groups(list, mode)
    local out, by = {}, {}
    for _, n in ipairs(list) do
        local k = M.key(n, mode)
        local g = by[k]
        if not g then
            g = { key = k, app = n.app, title = n.title, newest = n, items = {}, count = 0, critical = false, time = n.time }
            by[k] = g; out[#out + 1] = g
        end
        g.items[#g.items + 1] = n
        g.count = g.count + 1
        if n.urgency == "critical" then g.critical = true end
    end
    return out
end

-- A notice's signature: what, if it changed under the same id, is an update (the app replaced
-- it) — the segment pulses in place instead of arriving again.
function M.signature(n)
    return table.concat({ n.title, n.body, n.urgency, tostring(#n.actions), n.image }, "\31")
end

-- What changed between two lists (each id → signature): { added, changed, removed }, ids.
function M.diff(before, list)
    local now, added, changed, removed = {}, {}, {}, {}
    for _, n in ipairs(list) do
        local sig = M.signature(n)
        now[n.id] = sig
        if before[n.id] == nil then added[#added + 1] = n.id
        elseif before[n.id] ~= sig then changed[#changed + 1] = n.id end
    end
    for id in pairs(before) do if now[id] == nil then removed[#removed + 1] = id end end
    table.sort(removed, function(a, b) return tostring(a) < tostring(b) end)
    return { added = added, changed = changed, removed = removed, sigs = now }
end

-- How long a signal stays out, in ms, by tier (0: until dealt with). `linger` is the manifest's
-- (signals.linger, seconds); a whisper stays half as long, at least two seconds.
function M.ttl(tier, linger)
    linger = (tonumber(linger) or 7) * 1000
    if tier == M.INTERVENTION then return 0 end
    if tier == M.WHISPER then return math.max(2000, math.floor(linger / 2)) end
    return linger
end

-- The groups that are out on screen now, at most `max`, and how many more there would be. A
-- group is out while its newest notice is within its time (`seen[id]`: when the loom first
-- showed it, ms; `tiers[id]`) — or always, at the intervention tier — unless snoozed
-- (`snooze[id]`: until when) or let go from the cluster (`shelved[id]`). While `hold`, nothing
-- runs out (the pointer is on the cluster). An intervention is never the one left waiting: they
-- come first (nearest the edge), then the rest, newest first.
function M.live(groups, st, now, max, linger, hold)
    local urgent, rest = {}, {}
    for _, g in ipairs(groups) do
        local n = g.newest
        local snoozed = st.snooze[n.id] and st.snooze[n.id] > now
        if not snoozed and not st.shelved[n.id] then
            local tier = st.tiers[n.id] or M.MANIFEST
            local ttl = M.ttl(tier, linger)
            local since = st.seen[n.id] or now
            if hold or ttl == 0 or now - since < ttl then
                if tier == M.INTERVENTION then urgent[#urgent + 1] = g else rest[#rest + 1] = g end
            end
        end
    end
    local out, more = {}, 0
    for _, list in ipairs({ urgent, rest }) do
        for _, g in ipairs(list) do
            if #out < max then out[#out + 1] = g else more = more + 1 end
        end
    end
    return out, more
end

-- Which slot each live group takes. A group keeps its slot while it is out (so a new message
-- in a thread updates the segment it is in, and nothing else moves); a new one takes a free
-- slot — not one still retracting (`busy[slot]`). `slots`: slot (1 … n) → group key. Returns the
-- new slots and the slots whose group went (to retract).
function M.place(slots, live, n, busy)
    local want, out, gone, leaving = {}, {}, {}, {}
    for _, g in ipairs(live) do want[g.key] = true end
    for s = 1, n do
        local k = slots[s]
        if k ~= nil and want[k] then out[s] = k; want[k] = "placed"
        elseif k ~= nil then gone[#gone + 1] = s; leaving[s] = true end
    end
    for _, g in ipairs(live) do
        if want[g.key] == true then
            for s = 1, n do
                if out[s] == nil and not leaving[s] and not (busy and busy[s]) then
                    out[s] = g.key; want[g.key] = "placed"; break
                end
            end
        end
    end
    return out, gone
end

-- Where each live group's segment sits along the cluster: from the origin edge outward, in
-- the order of `live` (newest nearest the edge), each `heights[tier]` tall, `gap` apart. A group
-- that follows one from the same app is linked to it (drawn joined: a shared seam).
function M.stack(live, heights, gap, tiers)
    local y, out = 0, {}
    for i, g in ipairs(live) do
        local tier = tiers[g.newest.id] or M.MANIFEST
        local h = heights[tier] or heights[M.MANIFEST]
        local linked = i > 1 and live[i - 1].app == g.app
        if linked then y = y - math.floor(gap / 2) end
        out[g.key] = { y = y, h = h, linked = linked }
        y = y + h + gap
    end
    return out, y
end

-- A time as the loom says it, `t` seconds since 1970 against `now`: "now", "4 min", "2 h",
-- "3 d".
function M.ago(t, now)
    local d = math.max(0, (tonumber(now) or 0) - (tonumber(t) or 0))
    if d < 45 then return "now" end
    if d < 3600 then return string.format("%d min", math.floor(d / 60 + 0.5)) end
    if d < 86400 then return string.format("%d h", math.floor(d / 3600 + 0.5)) end
    return string.format("%d d", math.floor(d / 86400 + 0.5))
end

-- Where a notice sits on the activity rail (0 now … 1 the rail's far end, `span` seconds back),
-- on a square-root scale so the last minutes have room; nil past the end.
function M.rail(t, now, span)
    local d = (tonumber(now) or 0) - (tonumber(t) or 0)
    if d < 0 then d = 0 end
    if d > span then return nil end
    return math.sqrt(d / span)
end

return M
