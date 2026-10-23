-- Signal Loom (D50): the notifications, as signals that unfold from an edge, and the Signal
-- Field they open into. The working-out is lib/signals (pure, tested); this file receives the
-- notices, keeps the loom's state and hands the scene its rows.
--
-- One receiver per session, and the newest shell takes it: mooi takes it while it holds the
-- desktop (or always, or never: notifications.server). The server keeps every notice until it
-- is dismissed or acted on (`notifications.keep`), so the Field is the notification centre; the
-- signals are what passes. Nothing here polls: a signal's time out is a timer of its own.

local sig = require("lib/signals")

local SLOTS = 6               -- the scene's `loom` rows: a slot is where a signal unfolds
local FILE = "signals.json"   -- the apps you muted (whisper only), in mooi's data folder
local SNOOZE_MS = 15 * 60 * 1000
local RAIL_SPAN = 6 * 3600    -- the activity rail: the last six hours
local ANCHOR = { top_right = "top_right", top_left = "top_left", bottom_right = "bottom_right", bottom_left = "bottom_left" }

return function(ctx)
    local list = {}           -- the server's notices, cleaned, newest first
    local missed = {}         -- the history: the ones that went away on their own, unseen
    local locals = {}         -- mooi's own signals (the focus timer): never the server's
    local local_n = 0
    local sigs = {}           -- id → signature, to tell an update from an arrival
    local st = { seen = {}, tiers = {}, snooze = {}, shelved = {} }
    local slots = {}          -- slot → group key
    local busy = {}           -- slot → true while it retracts
    local groups_by_slot = {} -- slot → the group out there now
    local timers = {}         -- group key → its time-out's generation
    local hold = false        -- the pointer is on the cluster: nothing runs out
    local held_over = {}      -- keys whose time ran out while held
    local pulses = {}         -- slot → how many updates it has shown
    local muted = {}
    local hour = 12
    local field = { sel = 0, item = 0, clusters = {}, items = {} }

    local function S() return ctx.settings() end
    local function now_ms() local ok, t = pcall(os.time); return (ok and t or 0) * 1000 end
    local function now_s() local ok, t = pcall(os.time); return ok and t or 0 end

    local function claim()
        local mode = S().notifications.server
        -- "takeover": whenever mooi holds the desktop — a takeover, or a standalone session (D48)
        return mode == "always" or (mode == "takeover" and ctx.mode ~= "beside")
    end
    -- Do not disturb, now: always, while a focus block runs, or in the quiet hours.
    local function quiet()
        local n = S().notifications
        if n.dnd == "on" then return true end
        if n.dnd == "focus" then return fact.foc_state == 1 end
        if n.dnd == "hours" then
            local from, to = n.quiet_from, n.quiet_to
            if from == to then return false end
            if from < to then return hour >= from and hour < to end
            return hour >= from or hour < to
        end
        return false
    end

    local function load_muted()
        local ok, t = pcall(sys.ask, "files.read", FILE, "json")
        muted = {}
        if ok and type(t) == "table" and type(t.muted) == "table" then
            for _, app in ipairs(t.muted) do if type(app) == "string" and app ~= "" then muted[app] = true end end
        end
    end
    local function save_muted()
        if ctx.safe_mode then return end
        local out = {}
        for app in pairs(muted) do out[#out + 1] = app end
        table.sort(out)
        sys.call("files.write", FILE, { muted = out })
    end

    -- Every notice there is: mooi's own first (they are the newest), then the server's.
    local function all()
        if #locals == 0 then return list end
        local out = {}
        for _, n in ipairs(locals) do out[#out + 1] = n end
        for _, n in ipairs(list) do out[#out + 1] = n end
        return out
    end
    local function find(id)
        for _, n in ipairs(all()) do if n.id == id then return n end end
        return nil
    end

    -- ── The cluster ────────────────────────────────────────────
    local recompute
    local function expire(key)
        local gen = (timers[key] or 0) + 1
        timers[key] = gen
        return gen
    end
    -- A group's time out: from when it last changed, as long as its tier says (an urgent one
    -- has none). Held by the pointer, it waits for the pointer to leave.
    local function arm(g)
        local tier = st.tiers[g.newest.id] or sig.MANIFEST
        local ttl = sig.ttl(tier, S().signals.linger)
        local gen = expire(g.key)
        if ttl == 0 then return end
        after(ttl, function()
            if timers[g.key] ~= gen then return end
            if hold then held_over[g.key] = g.newest.id; return end
            st.shelved[g.newest.id] = true
            recompute()
        end)
    end

    local function heights()
        local comfy = S().signals.density == "comfortable"
        -- compact: narrow and one line; comfortable: wide, two lines (the scene sizes the width)
        return { [sig.WHISPER] = comfy and 32 or 28, [sig.MANIFEST] = comfy and 84 or 58, [sig.INTERVENTION] = comfy and 118 or 100 }
    end

    function recompute()
        local s = S().signals
        local everything = all()
        local groups = sig.groups(everything, s.grouping)
        local live, more = sig.live(groups, st, now_ms(), s.max, s.linger, true)
        local placed, gone = sig.place(slots, live, SLOTS, busy)
        local at, len = sig.stack(live, heights(), 8, st.tiers)
        for _, slot in ipairs(gone) do
            busy[slot] = true
            local mine = slot
            after(420, function() busy[mine] = nil; recompute() end)
        end
        slots = placed
        local by_key = {}
        for _, g in ipairs(live) do by_key[g.key] = g end
        local rows = {}
        local t = now_s()
        local private = s.private
        for slot = 1, SLOTS do
            local key = slots[slot]
            local g = key and by_key[key]
            local old = groups_by_slot[slot]
            groups_by_slot[slot] = g
            if g then
                local n = g.newest
                local tier = st.tiers[n.id] or sig.MANIFEST
                local p = at[g.key]
                local acts = n.actions
                rows[slot] = {
                    out = true, tier = tier, kind = sig.kind(n), app = string.upper(n.app ~= "" and n.app or "notice"),
                    title = n.title, body = private and "" or n.body, when = sig.ago(n.time, t), many = g.count,
                    icon = n.icon, iconed = n.icon ~= "", image = private and "" or n.image,
                    pictured = not private and n.image ~= "", acts = #acts,
                    a1 = acts[1] and acts[1].label or "", a2 = acts[2] and acts[2].label or "", a3 = acts[3] and acts[3].label or "",
                    y = p.y, h = p.h, linked = p.linked, pulse = pulses[slot] or 0, has_default = n.default,
                }
                if not old or old.key ~= g.key then pulses[slot] = 0 end
            else
                -- a slot keeps what it showed while it retracts, only no longer out
                local prev = model.loom and model.loom[slot]
                local r = {}
                if type(prev) == "table" then for k, v in pairs(prev) do r[k] = v end end
                r.out = false
                rows[slot] = r
            end
        end
        model.loom = rows
        fact.loom_more = more
        fact.loom_count = #live
        fact.loom_len = math.max(len - 8, 0)
    end

    -- ── The Field ──────────────────────────────────────────────
    -- Clusters by app (a group of threads), newest first, then what was missed; the chosen
    -- cluster's notices in the focus area; every notice on the activity rail.
    local function show_field()
        local everything = all()
        local by_app = sig.groups(everything, "app")
        local clusters, crows = {}, {}
        local t = now_s()
        for _, g in ipairs(by_app) do
            if #clusters < 12 then
                clusters[#clusters + 1] = { kind = 0, items = g.items, app = g.app }
                crows[#crows + 1] = { app = string.upper(g.app ~= "" and g.app or "notice"), title = g.newest.title, many = g.count,
                                      when = sig.ago(g.time, t), critical = g.critical, muted = muted[g.app] == true, missed = false }
            end
        end
        if #missed > 0 then
            clusters[#clusters + 1] = { kind = 2, items = missed, app = "" }
            crows[#crows + 1] = { app = "MISSED", title = "Went by while you were away", many = #missed,
                                  when = sig.ago(missed[1].time, t), critical = false, muted = false, missed = true }
        end
        field.clusters = clusters
        if field.sel >= #clusters then field.sel = math.max(#clusters - 1, 0) end
        local c = clusters[field.sel + 1]
        local items, irows = {}, {}
        if c then
            local threads = sig.groups(c.items, "thread")
            for _, th in ipairs(threads) do
                for _, n in ipairs(th.items) do
                    if #items < 30 then
                        items[#items + 1] = n
                        local snoozed = st.snooze[n.id] and st.snooze[n.id] > now_ms()
                        irows[#irows + 1] = { title = n.title ~= "" and n.title or "(no title)", body = n.body, when = sig.ago(n.time, t),
                                              tier = c.kind == 2 and 0 or (st.tiers[n.id] or sig.MANIFEST), critical = n.urgency == "critical", acts = #n.actions,
                                              a1 = n.actions[1] and n.actions[1].label or "", a2 = n.actions[2] and n.actions[2].label or "",
                                              a3 = n.actions[3] and n.actions[3].label or "", has_default = n.default and c.kind ~= 2,
                                              missed = c.kind == 2, snoozed = snoozed == true, thread = th.count,
                                              first = th.items[1] == n, image = n.image, pictured = n.image ~= "" }
                    end
                end
            end
        end
        field.items = items
        if field.item >= #items then field.item = math.max(#items - 1, 0) end
        local rail = {}
        for ci, cl in ipairs(clusters) do
            if cl.kind == 0 then
                for _, n in ipairs(cl.items) do
                    local x = sig.rail(n.time, t, RAIL_SPAN)
                    if x and #rail < 60 then rail[#rail + 1] = { x = x, tier = st.tiers[n.id] or sig.MANIFEST, cluster = ci - 1 } end
                end
            end
        end
        model.fclus = crows
        model.fitems = irows
        model.frail = rail
        fact.fld_sel = field.sel
        fact.fld_item = field.item
        text.fld_app = crows[field.sel + 1] and crows[field.sel + 1].app or ""
        fact.fld_muted = crows[field.sel + 1] ~= nil and crows[field.sel + 1].muted
        fact.fld_lost = c ~= nil and c.kind == 2
        fact.note_count = #list + #locals
        fact.note_missed = #missed
        fact.dnd_now = quiet()
    end

    local function refresh() recompute(); show_field() end

    -- ── Notices in ─────────────────────────────────────────────
    local function take(raw)
        local out = {}
        for _, n in ipairs(type(raw) == "table" and raw or {}) do
            local c = sig.clean(n)
            if c then out[#out + 1] = c end
        end
        return out
    end

    -- New ones get their tier as they arrive (a later mute does not change one already out) and
    -- a time out; one updated in place pulses where it is and starts its time again.
    local function arrived(d)
        local q = quiet()
        for _, id in ipairs(d.added) do
            local n = find(id)
            if n then
                st.tiers[id] = sig.tier(n, { muted = muted, quiet = q })
                st.seen[id] = now_ms()
            end
        end
        for _, id in ipairs(d.removed) do
            st.tiers[id], st.seen[id], st.snooze[id], st.shelved[id] = nil, nil, nil, nil
        end
        recompute()
        -- arm every group whose newest notice is new or changed; pulse a changed one's slot
        local fresh = {}
        for _, id in ipairs(d.added) do fresh[id] = true end
        for _, id in ipairs(d.changed) do fresh[id] = "changed" end
        for slot = 1, SLOTS do
            local g = groups_by_slot[slot]
            if g and fresh[g.newest.id] then
                if fresh[g.newest.id] == "changed" or g.count > 1 then pulses[slot] = (pulses[slot] or 0) + 1 end
                arm(g)
            end
        end
        -- a newer notice joined a thread already out: it pulses too (recompute put it there)
        recompute()
        show_field()
    end

    local function took(raw)
        list = take(raw)
        local d = sig.diff(sigs, list)
        -- mooi's own signals stay in the signatures, so the server's list does not drop them
        for _, n in ipairs(locals) do d.sigs[n.id] = sig.signature(n) end
        sigs = d.sigs
        arrived(d)
    end

    -- ── Acting on them ─────────────────────────────────────────
    local function is_local(id) return type(id) == "string" and string.sub(id, 1, 5) == "mooi:" end
    local function drop_local(id)
        for i, n in ipairs(locals) do if n.id == id then table.remove(locals, i); break end end
        sigs[id] = nil
        st.tiers[id], st.seen[id] = nil, nil
    end
    local function dismiss(id)
        if is_local(id) then drop_local(id); refresh(); return end
        pcall(sys.call, "notifications.dismiss", id)
    end
    local function invoke(n, key)
        if is_local(n.id) then dismiss(n.id); return end
        local ok = pcall(sys.call, "notifications.invoke", n.id, key)
        if not ok then log("signals · could not invoke " .. tostring(key) .. " on " .. tostring(n.id)) end
        pcall(sys.call, "notifications.dismiss", n.id)
    end

    -- A press on a signal: its app's own default (and it goes); without one, the Field opens at it.
    on("loom_open", function(v)
        local g = groups_by_slot[math.floor(tonumber(v) or -1) + 1]
        if not g then return end
        if g.newest.default then invoke(g.newest, "default"); return end
        for i, c in ipairs(field.clusters) do if c.app == g.app and c.kind == 0 then field.sel = i - 1 end end
        field.item = 0
        show_field()
        emit("loom_field")
    end)
    -- One of its buttons: 10 · slot + which.
    on("loom_act", function(v)
        v = math.floor(tonumber(v) or -1)
        local g = groups_by_slot[math.floor(v / 10) + 1]
        local a = g and g.newest.actions[v % 10 + 1]
        if a then invoke(g.newest, a.key) end
    end)
    -- Dismissed: every notice in the signal's group (a thread's are one conversation's).
    on("loom_dismiss", function(v)
        local g = groups_by_slot[math.floor(tonumber(v) or -1) + 1]
        if not g then return end
        for _, n in ipairs(g.items) do dismiss(n.id) end
    end)
    -- Let go of, not dismissed: it waits in the Field.
    on("loom_shelve", function(v)
        local g = groups_by_slot[math.floor(tonumber(v) or -1) + 1]
        if not g then return end
        st.shelved[g.newest.id] = true
        recompute()
    end)
    -- The pointer on the cluster holds the signals out; leaving, those that ran out meanwhile go
    -- a moment later.
    on("loom_hover", function(v)
        hold = (tonumber(v) or 0) > 0.5
        if hold then return end
        local waiting = held_over
        held_over = {}
        after(1200, function()
            if hold then for k, id in pairs(waiting) do held_over[k] = id end; return end
            for _, id in pairs(waiting) do st.shelved[id] = true end
            recompute()
        end)
    end)

    local function field_item(v)
        local n = field.items[math.floor(tonumber(v) or -1) + 1]
        local c = field.clusters[field.sel + 1]
        return n, c and c.kind == 2
    end
    on("fld_pick", function(v)
        local i = math.floor(tonumber(v) or 0)
        if i >= 0 and i < #field.clusters then field.sel = i; field.item = 0; show_field() end
    end)
    on("fld_choose", function(v)
        local i = math.floor(tonumber(v) or 0)
        if i >= 0 and i < #field.items then field.item = i; fact.fld_item = i end
    end)
    on("fld_open", function(v)
        local n, gone = field_item(v)
        if not n then return end
        if gone then pcall(sys.call, "notifications.forget", n.id); return end
        if n.default then invoke(n, "default") end
    end)
    on("fld_act", function(v)
        v = math.floor(tonumber(v) or -1)
        local n, gone = field_item(math.floor(v / 10))
        local a = n and not gone and n.actions[v % 10 + 1]
        if a then invoke(n, a.key) end
    end)
    on("fld_dismiss", function(v)
        local n, gone = field_item(v)
        if not n then return end
        if gone then pcall(sys.call, "notifications.forget", n.id) else dismiss(n.id) end
    end)
    -- The whole chosen cluster: one app's notices (or every missed one).
    on("fld_dismiss_all", function()
        local c = field.clusters[field.sel + 1]
        if not c then return end
        if c.kind == 2 then pcall(sys.call, "notifications.clear_history"); return end
        for _, n in ipairs(c.items) do dismiss(n.id) end
    end)
    -- Snoozed: out of sight for fifteen minutes (the server keeps it), then it arrives again.
    on("fld_snooze", function(v)
        local n, gone = field_item(v)
        if not n or gone then return end
        local id = n.id
        st.snooze[id] = now_ms() + SNOOZE_MS
        st.shelved[id] = true
        show_field(); recompute()
        after(SNOOZE_MS, function()
            if not st.snooze[id] then return end
            st.snooze[id], st.shelved[id] = nil, nil
            st.seen[id] = now_ms()
            refresh()
            for slot = 1, SLOTS do
                local g = groups_by_slot[slot]
                if g and g.newest.id == id then arm(g) end
            end
        end)
    end)
    -- Muted: that app's notices whisper from now on (they are still kept); again, it speaks.
    on("fld_mute", function()
        local c = field.clusters[field.sel + 1]
        if not c or c.kind ~= 0 or c.app == "" then return end
        muted[c.app] = not muted[c.app] or nil
        save_muted()
        show_field()
    end)
    on("note_clear", function()
        sys.call("notifications.clear"); pcall(sys.call, "notifications.clear_history")
        locals = {}
        refresh()
    end)
    -- The quick switch: do not disturb on, or off.
    on("note_dnd", function()
        local n = S().notifications
        n.dnd = (n.dnd == "off") and "on" or "off"
        ctx.save()
        show_field()
    end)

    -- ── Settings ───────────────────────────────────────────────
    local function apply()
        local s = S().signals
        fact.loom_anchor = ANCHOR[s.edge] or "top_right"
        fact.loom_bottom = string.sub(s.edge, 1, 6) == "bottom"
        fact.loom_left = string.find(s.edge, "left", 1, true) ~= nil
        fact.loom_chamfer = s.chamfer
        fact.loom_travel = s.travel / 100
        fact.loom_fx = s.effects
        fact.loom_comfy = s.density == "comfortable"
        if fact.notes_on then refresh() end
    end

    -- ── Start ──────────────────────────────────────────────────
    load_muted()
    fact.notes_on = claim()
    apply()
    if fact.notes_on then
        sys.watch("notifications", took)
        -- (asked once the service runs: it starts with the watch above)
        local kept, why = pcall(sys.call, "notifications.keep", true)
        if not kept then log("signals · could not keep the notices: " .. tostring(why)) end
        pcall(sys.watch, "notification_history", function(l)
            missed = take(l)
            show_field()
        end)
        sys.watch("clock", function(c)
            local h = type(c) == "table" and tonumber(c.hour)
            if h and h ~= hour then hour = h; fact.dnd_now = quiet() end
        end)
    end

    return {
        apply = apply,
        -- do not disturb, looked at again (a focus block started or ended)
        requiet = function() if fact.notes_on then fact.dnd_now = quiet() end end,
        -- one of mooi's own signals (the focus timer's): it unfolds like any other, never reaches
        -- the server, and a press lets it go
        signal = function(app, title, body)
            local_n = local_n + 1
            local n = sig.clean({ id = "mooi:" .. local_n, app = app, title = title, body = body, urgency = "normal", time = now_s() })
            table.insert(locals, 1, n)
            sigs[n.id] = sig.signature(n)
            arrived({ added = { n.id }, changed = {}, removed = {} })
        end,
    }
end
