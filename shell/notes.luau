-- Quick notes (D51): the pad behind the bar's notes module. The working-out is lib/notes (pure,
-- tested); this file owns the file, the dropdown's rows and the small things a press does.
--
-- The dropdown is drawn in the bar's own scene (shell/mooi.plm), so a note is written, edited,
-- listed and copied without another surface: the input's text arrives as `text:qn_draft`, its
-- Enter as `submit:qn_draft`, and everything else is an event from a press. notes.json is in
-- mooi's data folder, beside settings.json, and is read again if something else writes it.

local pad = require("lib/notes")

return function(ctx)
    local FILE = "notes.json"
    local UNDO_MS = 8000
    local items = {}
    local draft = ""
    local said_gen = 0
    local undo_gen = 0
    local last = nil          -- the note just forgotten, while Undo still stands
    local page = 0            -- the first row shown (the wheel moves it)
    local sel = -1            -- the row the keys act on (an id), -1 none

    local function now_s() local ok, t = pcall(os.time); return ok and t or 0 end
    local function save() if not ctx.safe_mode then sys.call("files.write", FILE, pad.encode(items)) end end

    -- A word under the pad for a moment ("COPIED", "DELETED"): the last one stops the one before it.
    local function say(word)
        said_gen = said_gen + 1
        local gen = said_gen
        text.qn_said = word
        fact.qn_saying = word ~= ""
        if word ~= "" then after(1600, function() if said_gen == gen then text.qn_said = ""; fact.qn_saying = false end end) end
    end

    local function reset_draft()
        draft = ""
        text.qn_draft = ""
        text.pk_qn = ""              -- D201: the Pill's Notes room writes here too
        fact.qn_drafting = false
        fact.qn_editing = false
        fact.qn_edit_id = -1
        text.qn_add_label = "ADD"
    end

    local query = ""
    local function show()
        local list = pad.filter(items, query)
        local total = #list
        page = math.max(0, math.min(page, math.max(total - pad.ROW_MAX, 0)))
        fact.qn_page = page
        fact.qn_from = total > 0 and page + 1 or 0
        fact.qn_to = math.min(page + pad.ROW_MAX, total)
        fact.qn_count = total
        local rows = {}
        for i = page + 1, math.min(page + pad.ROW_MAX, total) do
            local n = list[i]
            -- the first line is the note's name, the rest one quiet line under it (D86)
            local first, rest = pad.split(n.text)
            rows[#rows + 1] = { id = n.id, text = pad.one_line(first, pad.PREVIEW), more = pad.one_line(rest, pad.PREVIEW), two = rest ~= "",
                                when = pad.ago(now_s(), n.time), n = i - 1 - page,
                                pinned = n.pinned == true, sel = n.id == sel, tag = n.tag or 0, done = n.done == true }
        end
        fact.qn_searching = query ~= ""
        model.qn = rows
        fact.qn_sel = sel
    end

    local function load()
        local ok, t = pcall(sys.ask, "files.read", FILE, "json")
        items = (ok and pad.decode(t)) or {}
        page = 0
        show()
    end

    -- Undo stands for a little while after a note is forgotten; a second delete replaces it.
    local function stand_undo(note)
        last = note and { id = note.id, text = note.text, time = note.time } or nil
        undo_gen = undo_gen + 1
        local gen = undo_gen
        fact.qn_can_undo = last ~= nil
        if last then after(UNDO_MS, function() if undo_gen == gen then last = nil; fact.qn_can_undo = false end end) end
    end

    local function add()
        local t = pad.clean(draft)
        if t == "" then say("WRITE SOMETHING FIRST"); return end
        local note
        local was_edit = fact.qn_editing
        if was_edit then
            items, note = pad.update(items, fact.qn_edit_id, t, now_s())
            if not note then say("THAT NOTE IS GONE"); reset_draft(); show(); return end
            say("UPDATED")
        else
            items, note = pad.add(items, t, now_s())
            say("SAVED")
        end
        save(); show(); reset_draft()
        emit("qn_focus")
        log("notes · " .. (was_edit and "edited" or "saved") .. " (" .. #items .. ")")
    end

    local function edit(id)
        local n = pad.find(items, id)
        if not n then return end
        -- the input is one line: a note that was written with more (by hand) is edited as one
        draft = pad.one_line(n.text, pad.TEXT_MAX)
        text.qn_draft = draft
        fact.qn_drafting = draft ~= ""
        fact.qn_editing = true
        fact.qn_edit_id = n.id
        text.qn_add_label = "SAVE"
        emit("qn_focus")
    end

    -- The row actions, by name: a press emits them, the keys call them on the chosen row.
    local handlers = {}
    local function handle(name, fn) handlers[name] = fn; on(name, fn) end

    on("text:qn_draft", function(v)
        draft = type(v) == "string" and v or ""
        fact.qn_drafting = pad.clean(draft) ~= ""
    end)
    on("submit:qn_draft", function() add() end)
    -- D201: the Pill's Notes room (the board grows into it) — the same notes, its own field
    on("text:pk_qn", function(v)
        draft = tostring(v or "")
        fact.qn_drafting = pad.clean(draft) ~= ""
    end)
    on("submit:pk_qn", function() add() end)
    on("qn_add", function() add() end)
    -- D258: notes written on the node arrive in an inbox file (never on a command line); each is added, the box emptied
    local function inbox()
        local ok, box = pcall(sys.ask, "files.read", "notes-inbox.json", "json")
        if not ok or type(box) ~= "table" or #box == 0 then return end
        -- D279: the panel can pin or remove a kept note as well as add one; a plain string is
        -- still a note, so an older panel keeps working.
        local changed
        items, changed = pad.receive(items, box, now_s())
        pcall(sys.call, "files.write", "notes-inbox.json", "[]")
        if changed then save(); show() end
    end
    pcall(sys.watch, "files:notes-inbox.json", inbox)
    inbox()
    -- D86: a note's colour (its stripe, pressed), its tick, and the search
    on("qn_tag", function(v)
        local id = math.floor(tonumber(v) or -1)
        items = pad.tag(items, id); save(); show()
    end)
    on("qn_done", function(v)
        local id = math.floor(tonumber(v) or -1)
        local _, done = pad.done(items, id)
        if done ~= nil then save(); show(); say(done and "DONE" or "OPEN AGAIN") end
    end)
    on("text:qn_query", function(v) query = tostring(v or ""); page = 0; show() end)
    on("qn_toggle", function()
        fact.qn_open = not fact.qn_open
        if not fact.qn_open then reset_draft() end
    end)
    handle("qn_copy", function(v)
        local n = pad.find(items, math.floor(tonumber(v) or -1))
        if not n then return end
        run("wl-copy", {}, nil, { input = n.text, output = false })
        say("COPIED")
    end)
    handle("qn_edit", function(v)
        edit(math.floor(tonumber(v) or -1))
    end)
    on("qn_cancel", function() reset_draft(); emit("qn_focus") end)
    handle("qn_del", function(v)
        local id = math.floor(tonumber(v) or -1)
        local n = pad.find(items, id)
        if not n then return end
        if fact.qn_editing and fact.qn_edit_id == id then reset_draft() end
        local _, gone = pad.remove(items, id)
        if not gone then return end
        stand_undo(n)
        save(); show(); say("DELETED")
    end)
    on("qn_undo", function()
        if not last then return end
        local note
        items, note = pad.restore(items, last, now_s())
        if not note then return end
        last = nil; fact.qn_can_undo = false
        save(); show(); say("RESTORED")
        log("notes · restored (" .. #items .. ")")
    end)
    -- Pinned: it stays at the top, and the cap never takes it.
    handle("qn_pin", function(v)
        local id = math.floor(tonumber(v) or -1)
        local pinned
        items, pinned = pad.pin(items, id)
        if pinned == nil then return end
        sel = id
        save(); show(); say(pinned and "PINNED" or "UNPINNED")
    end)
    -- Sent to the board: a card at the top of its first column (the note stays here too).
    handle("qn_board", function(v)
        local n = pad.find(items, math.floor(tonumber(v) or -1))
        if not n or not ctx.to_board then return end
        local title, rest = pad.split(n.text)
        if ctx.to_board(title, rest) then say("ON THE BOARD") end
    end)
    -- The keys: ↑↓ choose a row (scrolling it into view), and the chosen one is what Alt+C, Alt+E,
    -- Alt+P, Alt+B and Alt+Delete act on.
    on("qn_nav", function(v)
        local list = pad.filter(items, query)   -- the rows that are shown, searched or not
        if #list == 0 then return end
        local at = 0
        for i, n in ipairs(list) do if n.id == sel then at = i end end
        at = math.max(1, math.min(#list, at + ((tonumber(v) or 0) < 0.5 and -1 or 1)))
        sel = list[at].id
        if at <= page then page = at - 1 elseif at > page + pad.ROW_MAX then page = at - pad.ROW_MAX end
        show()
    end)
    on("qn_act", function(v)
        if sel < 0 or not pad.find(items, sel) then return end
        v = math.floor(tonumber(v) or 0)
        local names = { "qn_copy", "qn_edit", "qn_pin", "qn_board", "qn_del" }
        local ev = names[v]
        if ev and handlers[ev] then handlers[ev](sel) end
    end)
    -- Closed from outside (another panel, Escape, idle) while a note was being changed: the change
    -- is let go, so the pad opens fresh next time.
    on("fact:qn_open", function(v) if not v then if fact.qn_editing then reset_draft() end; sel = -1; show() end end)
    on("qn_scroll", function(v)
        local d = tonumber(v) or 0
        page = math.max(0, math.min(page - d, math.max(#items - pad.ROW_MAX, 0)))
        show()
    end)

    -- Anything else writing the file (a hand, `mooi note`) is followed; a write of our own reads
    -- back the same list.
    pcall(sys.watch, "files:" .. FILE, function() load() end)

    load()
    fact.qn_open = false
    fact.qn_editing = false
    fact.qn_edit_id = -1
    fact.qn_can_undo = false
    text.qn_said = ""
    text.qn_add_label = "ADD"

    return {}
end
