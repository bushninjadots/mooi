-- The board (D52): a Kanban board, opened from the quick-notes pad's rail. The working-out is
-- lib/board (pure, tested); this file owns board.json, lays the board out for the scene, and
-- answers what a press, a drag, a key or a typed word asks for.
--
-- The scene draws only what can be seen: each column's cards inside its view (the wheel scrolls a
-- column), the chosen card's details in the pane, a drop line while a card is carried. Edits in the
-- pane are saved as you type (a moment after the last key), so closing never loses a word.

local kb = require("lib/board")

return function(ctx)
    local FILE = "board.json"
    local UNDO_MS = 10000
    local GEO = { x0 = 16, y0 = 60, width = 872, height = 636, gap = 12 }   -- the scene's columns area
    local b = kb.new()
    local sel, selcol = -1, -1      -- the chosen card (an id), the chosen column (an id)
    local query, tagf = "", 0
    local scroll = {}               -- column id → px
    local undo = nil                -- { kind, … } the last thing that can be taken back
    local undo_gen, said_gen, edit_gen = 0, 0, 0
    local offset = 0                -- the zone's seconds east of UTC, for "today"
    local lay = { cols = {}, cards = {} }
    local pane_for = nil            -- the card the pane's fields were filled from (filled once: typing is never overwritten)

    local function now_s() local ok, t = pcall(os.time); return ok and t or 0 end
    local function today() return kb.today(now_s(), offset) end
    local function save() if not ctx.safe_mode then sys.call("files.write", FILE, kb.encode(b)) end end

    local function say(word)
        said_gen = said_gen + 1
        local gen = said_gen
        text.kb_said = word
        fact.kb_saying = word ~= ""
        if word ~= "" then after(1800, function() if said_gen == gen then text.kb_said = ""; fact.kb_saying = false end end) end
    end
    local function stand_undo(u, word)
        undo = u
        undo_gen = undo_gen + 1
        local gen = undo_gen
        fact.kb_can_undo = true
        say(word)
        after(UNDO_MS, function() if undo_gen == gen then undo = nil; fact.kb_can_undo = false end end)
    end

    local function ago(t)
        local d = now_s() - (tonumber(t) or 0)
        if d < 60 then return "now" end
        if d < 3600 then return math.floor(d / 60) .. "m" end
        if d < 86400 then return math.floor(d / 3600) .. "h" end
        return math.floor(d / 86400) .. "d"
    end

    -- The pane: the chosen card, else the chosen column.
    local function show_pane()
        local c = sel >= 0 and kb.card(b, sel)
        if not c then sel = -1 end
        fact.kb_sel = sel
        fact.kb_d_has = c ~= nil and c ~= false
        if not c then pane_for = nil end
        if c then
            local col = kb.column(b, c.col)
            if pane_for ~= c.id then
                pane_for = c.id
                text.kb_title = c.title
                text.kb_note = c.note
            end
            fact.kb_d_tag = c.tag
            fact.kb_d_due_st = kb.due_state(c.due, today())
            text.kb_d_due = c.due and kb.due_text(c.due, today()) or "no due day"
            fact.kb_d_done = c.done_at ~= nil
            text.kb_d_meta = string.upper(col and col.title or "") .. " · MADE " .. string.upper(ago(c.created))
                .. (c.updated ~= c.created and (" · CHANGED " .. string.upper(ago(c.updated))) or "")
                .. (c.done_at and (" · DONE " .. string.upper(ago(c.done_at))) or "")
            selcol = c.col
        end
        local col = kb.column(b, selcol)
        if not col then selcol = b.columns[1].id; col = b.columns[1] end
        fact.kb_selcol = selcol
        text.kb_colname = col.title
        text.kb_col_title = string.upper(col.title)
        fact.kb_col_wip = col.wip
        fact.kb_col_empty = #kb.cards_in(b, selcol) == 0
        fact.kb_col_last = b.columns[#b.columns].id == selcol
        fact.kb_cols_full = #b.columns >= kb.MAX_COLUMNS
    end

    local function show()
        lay = kb.layout(b, { x0 = GEO.x0, y0 = GEO.y0, width = GEO.width, height = GEO.height, gap = GEO.gap,
                             scroll = scroll, query = query, tag = tagf })
        local t = today()
        local cols = {}
        for i, c in ipairs(lay.cols) do
            scroll[c.id] = c.scroll
            cols[i] = { id = c.id, title = string.upper(c.title), x = c.x, w = c.w, n = c.count, wip = c.wip, over = c.over,
                        sel = c.id == selcol and sel < 0, chosen = c.id == selcol, more_up = c.scroll > 0, more_down = c.len - c.scroll > c.view + 2,
                        done = i == #lay.cols }
        end
        local cards = {}
        local top, bottom = GEO.y0 + kb.HEAD_H, GEO.y0 + GEO.height
        local done_col = b.columns[#b.columns].id
        for _, k in ipairs(lay.cards) do
            if k.shown and k.y + k.h > top and k.y < bottom and #cards < 80 then
                local c = kb.card(b, k.id)
                cards[#cards + 1] = { id = k.id, col = k.col, x = k.x, y = k.y, w = k.w, h = k.h, title = c.title, note = c.note,
                                      noted = c.note ~= "", tag = c.tag, due = kb.due_text(c.due, t), due_st = k.col == done_col and 0 or kb.due_state(c.due, t),
                                      dated = c.due ~= nil, done = k.col == done_col, sel = k.id == sel, age = ago(c.updated) }
            end
        end
        model.kcols = cols
        model.kcards = cards
        local st = kb.stats(b, t)
        fact.kb_count = st.cards
        fact.kb_late = st.late
        fact.kb_due_today = st.today
        fact.kb_archived = st.archived
        fact.kb_done_n = #kb.cards_in(b, done_col)
        fact.kb_tagf = tagf
        fact.kb_filtering = query ~= "" or tagf > 0
        show_pane()
    end

    local function load()
        local ok, t = pcall(sys.ask, "files.read", FILE, "json")
        b = (ok and t ~= nil) and kb.decode(t) or kb.new()
        show()
    end

    local function changed(word) save(); show(); if word then say(word) end end

    -- ── Choosing ──
    on("kb_pick", function(v)
        local id = math.floor(tonumber(v) or -1)
        if kb.card(b, id) then sel = id; show() end
    end)
    on("kb_pickcol", function(v)
        local id = math.floor(tonumber(v) or -1)
        if kb.column(b, id) then selcol = id; sel = -1; show() end
    end)
    on("kb_unpick", function() sel = -1; show() end)
    -- The keys' way about: 1 left · 2 right · 3 up · 4 down, through what is shown.
    on("kb_nav", function(v)
        v = math.floor(tonumber(v) or 0)
        local ci, k = 1, 0
        if sel >= 0 then ci, k = kb.place_of(b, sel)
        else local _, i = kb.column(b, selcol); ci = i or 1 end
        local function shown_in(col_i)
            local out = {}
            for _, c in ipairs(kb.cards_in(b, b.columns[col_i].id)) do if kb.shows(c, query, tagf) then out[#out + 1] = c end end
            return out
        end
        if v == 1 or v == 2 then
            ci = math.max(1, math.min(#b.columns, ci + (v == 1 and -1 or 1)))
            local list = shown_in(ci)
            selcol = b.columns[ci].id
            sel = #list > 0 and list[math.max(1, math.min(k > 0 and k or 1, #list))].id or -1
        else
            local list = shown_in(ci)
            if #list == 0 then return end
            local at = 0
            for i, c in ipairs(list) do if c.id == sel then at = i end end
            at = math.max(1, math.min(#list, at + (v == 3 and -1 or 1)))
            sel = list[at].id
        end
        -- keep the chosen card in its column's view
        local lc = sel >= 0 and kb.card(b, sel)
        if lc then
            show()
            for _, k2 in ipairs(lay.cards) do
                if k2.id == sel then
                    local top, bottom = GEO.y0 + kb.HEAD_H, GEO.y0 + GEO.height
                    if k2.y < top then scroll[lc.col] = (scroll[lc.col] or 0) - (top - k2.y) - 8
                    elseif k2.y + k2.h > bottom then scroll[lc.col] = (scroll[lc.col] or 0) + (k2.y + k2.h - bottom) + 8 end
                end
            end
        end
        show()
    end)

    -- ── Cards ──
    local function add(title, note, col, word)
        local c, why = kb.add(b, col, title, note, now_s())
        if not c then say(string.upper(why)); return nil end
        sel = c.id; selcol = col; scroll[col] = 0
        changed(word or "ADDED")
        return c
    end
    on("submit:kb_new", function(v)
        if add(v, "", selcol >= 0 and selcol or b.columns[1].id) then text.kb_new = ""; fact.kb_drafting = false end
    end)
    on("text:kb_new", function(v) fact.kb_drafting = type(v) == "string" and v ~= "" end)
    -- The pane's fields are saved a moment after the last key.
    local edits = {}                -- "field:id" → the latest keystroke's generation
    local function later(field)
        edit_gen = edit_gen + 1
        local gen, id = edit_gen, sel
        local key = field .. ":" .. id
        edits[key] = gen
        return function(v)
            after(450, function()
                if edits[key] ~= gen or id < 0 or not kb.card(b, id) then return end
                edits[key] = nil
                local f = {}; f[field] = v
                if kb.update(b, id, f, now_s()) then save(); show() end
            end)
        end
    end
    on("text:kb_title", function(v) if sel >= 0 then later("title")(v) end end)
    on("text:kb_note", function(v) if sel >= 0 then later("note")(v) end end)
    on("submit:kb_title", function(v) if sel >= 0 and kb.update(b, sel, { title = v }, now_s()) then changed("SAVED") end end)
    on("submit:kb_note", function(v) if sel >= 0 and kb.update(b, sel, { note = v }, now_s()) then changed("SAVED") end end)
    on("kb_tag", function(v)
        if sel >= 0 and kb.update(b, sel, { tag = math.floor(tonumber(v) or 0) }, now_s()) then changed() end
    end)
    on("kb_due", function(v)
        local names = { [0] = "none", "today", "tomorrow", "week" }
        if sel >= 0 and kb.update(b, sel, { due = kb.preset(names[math.floor(tonumber(v) or 0)] or "none", today()) }, now_s()) then changed() end
    end)
    -- 1 left · 2 right · 3 up · 4 down: the chosen card, a column or a place.
    on("kb_step", function(v)
        v = math.floor(tonumber(v) or 0)
        if sel < 0 then return end
        local dx = (v == 1 and -1) or (v == 2 and 1) or 0
        local dy = (v == 3 and -1) or (v == 4 and 1) or 0
        if kb.step(b, sel, dx, dy, now_s()) then
            local c = kb.card(b, sel)
            selcol = c.col
            changed(c.done_at and dx ~= 0 and "DONE" or nil)
        end
    end)
    -- A card carried and let go: where the scene says it was let go (kb_gx, kb_gy, beside the event).
    local function target(id)
        local col, index = kb.drop_target(lay, tonumber(fact.kb_gx) or 0, tonumber(fact.kb_gy) or 0, id)
        return col, index
    end
    on("kb_over", function(v)
        local id = math.floor(tonumber(v) or -1)
        local col, index = target(id)
        if not col then fact.kb_ty = -1; return end
        -- the drop line: under the card it would follow, or at the top of the column
        local y, x, w = GEO.y0 + kb.HEAD_H - 4, 0, 0
        local k = 0
        for _, c in ipairs(lay.cols) do if c.id == col then x, w = c.x, c.w end end
        for _, c in ipairs(lay.cards) do
            if c.col == col and c.id ~= id then
                k = k + 1
                if k == index - 1 and c.shown then y = c.y + c.h + kb.CARD_GAP / 2 end
            end
        end
        fact.kb_tx, fact.kb_tw, fact.kb_ty = x, w, y
    end)
    on("kb_drop", function(v)
        local id = math.floor(tonumber(v) or -1)
        fact.kb_ty = -1
        local col, index = target(id)
        if col and kb.move(b, id, col, index, now_s()) then
            sel = id; selcol = col
            local c = kb.card(b, id)
            changed(c and c.done_at and "DONE" or "MOVED")
        end
    end)
    on("kb_del", function()
        if sel < 0 then return end
        local taken = kb.remove(b, sel)
        if not taken then return end
        sel = -1
        save(); show()
        stand_undo({ kind = "card", taken = taken }, "DELETED")
    end)
    on("kb_copy", function()
        local c = sel >= 0 and kb.card(b, sel)
        if not c then return end
        run("wl-copy", {}, nil, { input = c.title .. (c.note ~= "" and ("\n" .. c.note) or ""), output = false })
        say("COPIED")
    end)
    on("kb_archive", function()
        local before = { cards = {}, archive = #b.archive }
        for _, c in ipairs(b.cards) do before.cards[#before.cards + 1] = c end
        local n = kb.archive_done(b, now_s())
        if n == 0 then say("NOTHING DONE TO ARCHIVE"); return end
        if sel >= 0 and not kb.card(b, sel) then sel = -1 end
        save(); show()
        stand_undo({ kind = "archive", cards = before.cards, n = n }, n .. " ARCHIVED")
    end)
    on("kb_undo", function()
        local u = undo
        if not u then return end
        undo = nil; fact.kb_can_undo = false
        if u.kind == "card" then
            if kb.restore(b, u.taken) then sel = u.taken.card.id end
        elseif u.kind == "archive" then
            b.cards = u.cards
            for _ = 1, u.n do table.remove(b.archive, 1) end
        elseif u.kind == "column" then
            table.insert(b.columns, math.min(u.index, #b.columns + 1), u.column)
        end
        changed("PUT BACK")
    end)

    -- ── Columns ──
    on("kb_addcol", function()
        local c, why = kb.add_column(b, "")
        if not c then say(string.upper(why)); return end
        selcol = c.id; sel = -1
        changed("COLUMN ADDED")
        emit("kb_focus_col")
    end)
    on("submit:kb_colname", function(v)
        if kb.rename_column(b, selcol, v) then changed("RENAMED") end
    end)
    on("kb_wip", function(v)
        if kb.set_wip(b, selcol, math.floor(tonumber(v) or 0)) then changed() end
    end)
    on("kb_colmove", function(v)
        if kb.move_column(b, selcol, (tonumber(v) or 0) < 0.5 and -1 or 1) then changed() end
    end)
    on("kb_delcol", function()
        local col, i = kb.column(b, selcol)
        local ok, why = kb.remove_column(b, selcol)
        if not ok then say(string.upper(why)); return end
        selcol = b.columns[math.min(i, #b.columns)].id
        save(); show()
        stand_undo({ kind = "column", column = col, index = i }, "COLUMN REMOVED")
    end)
    on("kb_scroll", function(v)
        -- 1000 · column + 10 · wheel + 500 (the wheel in tenths: a touchpad's small steps count)
        v = math.floor((tonumber(v) or 0) + 0.5)
        local col = math.floor(v / 1000)
        local wheel = ((v % 1000) - 500) / 10
        scroll[col] = (scroll[col] or 0) - wheel * 60
        show()
    end)

    -- ── Finding ──
    on("text:kb_search", function(v) query = type(v) == "string" and v or ""; show() end)
    on("kb_filter", function(v)
        local t = math.floor(tonumber(v) or 0)
        tagf = (tagf == t) and 0 or t
        show()
    end)
    on("kb_clearfilter", function() query = ""; tagf = 0; text.kb_search = ""; show() end)

    on("fact:kb_open", function(v) if v then load() end end)
    pcall(sys.watch, "files:" .. FILE, function() load() end)
    run("date", { "+%z" }, function(out, code)
        local sign, h, m = string.match(tostring(out or ""), "([+-])(%d%d)(%d%d)")
        if code == 0 and sign then
            offset = (tonumber(h) * 3600 + tonumber(m) * 60) * (sign == "-" and -1 or 1)
            show()
        end
    end)

    fact.kb_ty = -1
    fact.kb_can_undo = false
    text.kb_said = ""
    load()

    return {
        -- a note sent from the pad: its first line the title, the rest its note, at the top of the first column
        add_note = function(title, note)
            local c = add(title, note, b.columns[1].id, "FROM NOTES")
            return c ~= nil
        end,
    }
end
