-- Quick notes (D51): the pad behind the bar's notes module. The working-out is lib/notes (pure,
-- tested); this file owns the file, the dropdown's rows and the small things a press does.
--
-- The dropdown is drawn in the bar's own scene (shell/mooi.plm), so a note is written, listed and
-- copied without another surface: the input's text arrives as `text:qn_draft`, its Enter as
-- `submit:qn_draft`, and everything else is an event from a press. notes.json is in mooi's data
-- folder, beside settings.json, and is read again if something else writes it.

local pad = require("lib/notes")

return function(ctx)
    local FILE = "notes.json"
    local items = {}
    local draft = ""
    local said_gen = 0

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

    local function show()
        fact.qn_count = #items
        local rows = {}
        for i, n in ipairs(items) do
            if i > pad.ROW_MAX then break end
            rows[#rows + 1] = { id = n.id, text = pad.one_line(n.text, pad.PREVIEW), when = pad.ago(now_s(), n.time), n = i - 1 }
        end
        model.qn = rows
    end

    local function load()
        local ok, t = pcall(sys.ask, "files.read", FILE, "json")
        items = (ok and pad.decode(t)) or {}
        show()
    end

    local function add(text_in)
        local t = pad.clean(text_in)
        if t == "" then say("WRITE SOMETHING FIRST"); return end
        local note
        items, note = pad.add(items, t, now_s())
        if not note then say("WRITE SOMETHING FIRST"); return end
        save(); show()
        draft = ""
        text.qn_draft = ""
        fact.qn_drafting = false
        emit("qn_added")
        say("SAVED")
        log("notes · saved (" .. #items .. ")")
    end

    on("text:qn_draft", function(v)
        draft = type(v) == "string" and v or ""
        fact.qn_drafting = pad.clean(draft) ~= ""
    end)
    on("submit:qn_draft", function() add(draft) end)
    on("qn_add", function() add(draft) end)
    on("qn_toggle", function()
        fact.qn_open = not fact.qn_open
        if not fact.qn_open then draft = ""; text.qn_draft = ""; fact.qn_drafting = false end
    end)
    on("qn_copy", function(v)
        local n = pad.find(items, math.floor(tonumber(v) or -1))
        if not n then return end
        run("wl-copy", {}, nil, { input = n.text, output = false })
        say("COPIED")
    end)
    on("qn_del", function(v)
        local id = math.floor(tonumber(v) or -1)
        local _, gone = pad.remove(items, id)
        if not gone then return end
        save(); show(); say("DELETED")
    end)

    -- Anything else writing the file (a hand, a later mooi command) is followed, but a write of
    -- our own is harmless: it reads back the same list.
    pcall(sys.watch, "files:" .. FILE, function() load() end)

    load()
    fact.qn_open = false
    text.qn_said = ""

    return {}
end
