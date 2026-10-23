-- The stash (D54): a box on the left edge that opens on hover. Anything dragged in from
-- another program is kept: files are copied into mooi's own stash folder, links and text are
-- written down. The working-out is lib/stash (pure, tested); this file owns the folder, the
-- copies, the video posters and the panel's rows.
--
-- Dropping is the one door: a browser hands the address over, a file manager its paths, a
-- text editor its text. What is let go on the panel is copied (a file kept somewhere of its
-- own, so moving the original does not empty the stash) and shown at once; a picture is read
-- from the copy, a video gets one frame of it and a song its own cover as their picture, both
-- tell their row how long they run, and everything else a glyph.
--
-- It works both ways: a row carries its file, address or text out to another program (the
-- scene's `carries:`), and dragging one back in — or onto a folder — moves it rather than
-- copying it again. Folders are the panel's own, one level deep: a folder is a place to put
-- things, and taking it away only sends its items back to the root.

local st = require("lib/stash")

return function(ctx)
    local FILE = "stash.json"
    local folder = tostring(sys.ask("files.folder") or "")
    local dir = folder ~= "" and (folder .. "/stash") or ""
    local items = {}
    local folders = {}
    local here = 0          -- the folder the box is in (0: everything)
    local page = 0
    local scroll = 0
    local seq = 0
    local said_gen = 0

    local function now_s() local ok, t = pcall(os.time); return ok and t or 0 end
    local function save() if not ctx.safe_mode then sys.call("files.write", FILE, st.encode(items, folders)) end end

    -- A word under the panel for a moment ("STASHED", "COPIED", "REMOVED").
    local function say(word)
        said_gen = said_gen + 1
        local gen = said_gen
        text.stash_said = word
        fact.stash_saying = word ~= ""
        if word ~= "" then after(1700, function() if said_gen == gen then text.stash_said = ""; fact.stash_saying = false end end) end
    end

    local function show()
        -- 0 is everything (the root among it), a folder is what was put there
        local list = here == 0 and items or st.in_folder(items, here)
        local names = {}
        for _, f in ipairs(folders) do names[f.id] = f.name end
        local rows, p, from, to, total, pages = st.page(list, page, now_s(), nil, names)
        page = p
        model.stash = rows
        local chips = {}
        for i, f in ipairs(folders) do
            chips[#chips + 1] = { name = f.name, held = st.folder_count(items, f.id),
                                  n = i - 1, lit = f.id == here and 1 or 0 }
        end
        model.stash_folders = chips
        fact.stash_here = here
        fact.stash_root = here == 0
        fact.stash_all = #items
        fact.stash_folders_n = #folders
        text.stash_here_name = here ~= 0 and (st.folder_find(folders, here) or {}).name or ""
        fact.stash_page = page
        fact.stash_pages = pages
        fact.stash_count = total
        fact.stash_from = from
        fact.stash_to = to
        fact.stash_empty = total < 1
    end

    local function load()
        local ok, t = pcall(sys.ask, "files.read", FILE, "json")
        if ok then items, folders = st.decode(t) else items, folders = {}, {} end
        here, page = 0, 0
        show()
    end

    -- One frame of a video, as its picture in the panel. It costs a moment of ffmpeg, on its
    -- own: the row is there before the frame is, with its glyph.
    local function poster_for(it)
        if dir == "" or ctx.safe_mode or not it then return end
        local out = dir .. "/poster-" .. it.id .. ".jpg"
        run("ffmpeg", { "-y", "-v", "error", "-ss", "0", "-i", it.url, "-frames:v", "1",
                        "-vf", "scale=160:160:force_original_aspect_ratio=increase", "-q:v", "5", out },
            function(_, code)
                if code ~= 0 then return end
                if not st.find(items, it.id) then run("rm", { "-f", "--", out }); return end
                it.poster = out
                save(); show()
            end)
    end

    -- A song's cover, if it carries one (mp3, m4a and flac usually do): the first frame of the
    -- embedded picture, written beside the copy. One that carries none leaves the row its glyph,
    -- which is no loss: the row says what it is either way.
    local function cover_for(it)
        if dir == "" or ctx.safe_mode or not it then return end
        local out = dir .. "/cover-" .. it.id .. ".jpg"
        run("ffmpeg", { "-y", "-v", "error", "-i", it.url, "-an", "-frames:v", "1", "-q:v", "4", out },
            function(_, code)
                if code ~= 0 then return end
                if not st.find(items, it.id) then run("rm", { "-f", "--", out }); return end
                it.poster = out
                save(); show()
            end)
    end

    -- How long it runs, from the file itself (`ffprobe`, which comes with ffmpeg): the row's
    -- detail line gains it, so a song reads `MP3 · 3:41 · now` and a film `MKV · 1:52:07 · now`.
    local function length_for(it)
        if not it then return end
        run("ffprobe", { "-v", "error", "-show_entries", "format=duration", "-of", "csv=p=0", it.url },
            function(out, code)
                if code ~= 0 or type(out) ~= "string" then return end
                local secs = tonumber(string.match(out, "^%s*([%d%.]+)"))
                if not secs or secs < 1 then return end
                local cur = st.find(items, it.id)
                if not cur then return end
                local ext = st.extension(cur.name ~= "" and cur.name or cur.url)
                local label = ext ~= "" and string.upper(ext) or (cur.kind == 5 and "AUDIO" or "VIDEO")
                cur.detail = label .. " · " .. st.length(secs)
                save(); show()
            end)
    end

    local function add_item(item, word, into)
        item.folder = into or here
        items, item = st.add(items, item, now_s())
        if not item then say("NOTHING TO STASH"); return nil end
        page = 0                       -- the newest is on the first page, where it can be seen
        -- Written down and shown first: the picture and the length are read from the file
        -- afterwards, and a tool that is missing (or not permitted) must not cost the item.
        save(); show(); say(word)
        if item.kind == 2 then poster_for(item); length_for(item) end
        if item.kind == 5 then cover_for(item); length_for(item) end
        log("stash · " .. item.name)
        return item
    end

    -- A file (or a folder) dragged in: copied into the stash folder under a name of its own,
    -- then written down. The same file dropped again is the item it already is, and moving it
    -- to the folder it was dropped on.
    local function add_file(src, into)
        if src == "" then return end
        local already = st.find_src(items, src)
        if already then
            st.bump(items, already, now_s())
            st.move(items, already.id, into or here)
            page = 0; save(); show(); say("ALREADY STASHED")
            return
        end
        if dir == "" then say("NO STASH FOLDER"); return end
        local kind = st.kind_of(src)
        local name, detail = st.describe(src, kind)
        -- Safe mode writes nothing: the original is written down as it is, and nothing is
        -- copied. The row works all the same; the stash folder stays as it was.
        if ctx.safe_mode then
            add_item({ kind = kind, name = name, detail = detail, url = src, src = src }, "STASHED (SAFE)", into)
            return
        end
        seq = seq + 1
        local dst = dir .. "/" .. now_s() .. "-" .. seq .. "-" .. st.safe_name(st.basename(src))
        run("cp", { "-R", "--", src, dst }, function(_, code)
            if code ~= 0 then
                say("COULD NOT STASH IT")
                log("stash · cp failed for " .. src)
                return
            end
            add_item({ kind = kind, name = name, detail = detail, url = dst, src = src }, "STASHED", into)
        end)
    end

    local function add_link(url, into)
        local already = st.find_url(items, url)
        if already then
            st.bump(items, already, now_s()); st.move(items, already.id, into or here)
            page = 0; save(); show(); say("ALREADY STASHED")
            return
        end
        local name, detail = st.describe(url, 0)
        add_item({ kind = 0, name = name, detail = detail, url = url }, "LINK STASHED", into)
    end

    local function add_text(text, into)
        if text == "" then return end
        local already = st.find_url(items, text)
        if already then
            st.bump(items, already, now_s()); st.move(items, already.id, into or here)
            page = 0; save(); show(); say("ALREADY STASHED")
            return
        end
        local name, detail = st.describe(text, 4)
        add_item({ kind = 4, name = name, detail = detail, url = text }, "STASHED", into)
    end

    -- Ours, and put back in: something dragged out of the box and let go on it again (or on a
    -- folder) is the same item, moved — never a second copy of our own copy.
    local function mine(s)
        return dir ~= "" and string.sub(s, 1, #dir + 1) == dir .. "/" and st.find_url(items, s) or nil
    end

    -- What came in: text, or a list of `file://…`. A line that is a file is copied, an address
    -- is written down, anything else is text.
    local function take(raw, into)
        local s = st.path_of(raw)
        if s == "" then return end
        local ours = mine(s)
        if ours then
            st.move(items, ours.id, into or here)
            if here ~= (into or here) then here = into or here end
            page = 0; save(); show(); say("MOVED")
            return
        end
        if string.match(s, "^%a[%w+.-]*://") then
            add_link(s, into)
        elseif string.sub(s, 1, 1) == "/" then
            add_file(s, into)
        else
            add_text(s, into)
        end
    end

    local function each(data)
        local out = {}
        if type(data) == "table" then
            for _, v in ipairs(data) do if type(v) == "string" and v ~= "" then out[#out + 1] = v end end
        elseif type(data) == "string" then
            for line in string.gmatch(data, "[^\r\n]+") do
                line = string.gsub(string.gsub(line, "^%s+", ""), "%s+$", "")
                if line ~= "" and string.sub(line, 1, 1) ~= "#" then out[#out + 1] = line end
            end
        end
        return out
    end

    -- The drop is sent to the zone under the pointer, so the plate, a row, a folder chip and the
    -- rail each hear it by their own name. A chip takes its own folder (the scene names them
    -- `zfolder.0` … by their slot); anything else goes into the folder the box is showing.
    local function received(data, into)
        local got = each(data)
        if #got == 0 then say("NOTHING TO STASH"); return end
        for _, raw in ipairs(got) do take(raw, into) end
    end
    local function slot_folder(slot)
        local f = folders[math.floor(tonumber(slot) or 0)]
        return f and f.id or 0
    end
    on("drop:zstash", function(data) received(data, here) end)
    on("drop:stashrow", function(data) received(data, here) end)
    on("drop:zstash_tab", function(data) received(data, here) end)
    on("drop:zstash_catch", function(data) received(data, here) end)
    on("drop:zall", function(data) received(data, 0) end)
    for slot = 1, st.FOLDER_MAX do
        on("drop:zfolder." .. (slot - 1), function(data) received(data, slot_folder(slot)) end)
    end

    -- The chips: a press goes in (or back out to everything, slot 0), and a right press takes
    -- the folder away — its items go back to the root, so nothing is lost with it. The chips
    -- are reached by their slot, which is the order they were made in, the same in both.
    on("stash_folder", function(v)
        here = slot_folder(v)
        page = 0
        show()
    end)
    on("stash_folder_del", function(v)
        local id = slot_folder(v)
        local gone
        folders, gone = st.folder_remove(folders, items, id)
        if not gone then return end
        if here == id then here = 0 end
        page = 0; save(); show(); say("FOLDER REMOVED")
    end)

    -- A row's tray: the item walks to the next folder, and home after the last. Folders are few
    -- and named, so a press that steps through them is quicker than a menu, and the row's line
    -- says where it is.
    on("stash_file", function(v)
        local id = math.floor(tonumber(v) or -1)
        local it = st.find(items, id)
        if not it then return end
        if #folders == 0 then say("MAKE A FOLDER FIRST"); return end
        local to = st.folder_next(folders, it.folder)
        st.move(items, id, to)
        save(); show()
        local f = to ~= 0 and st.folder_find(folders, to)
        say(f and string.upper(f.name) or "BACK AT THE ROOT")
    end)

    -- A name typed into the box's own field: the folder is made, the box goes into it, and the
    -- field is given back empty. A name that says nothing is no folder.
    on("submit:stash_new", function(v)
        text.stash_new = ""
        emit("stash_blur")
        local name = tostring(v or "")
        if name == "" then return end
        local made
        folders, made = st.folder_add(folders, name, now_s())
        if not made then say("NO ROOM FOR ANOTHER FOLDER"); return end
        here = made.id
        page = 0
        save(); show(); say(string.upper(made.name))
    end)

    -- A press: text is handed to the clipboard, everything else opened by its own program.
    on("stash_open", function(v)
        local id = math.floor(tonumber(v) or -1)
        local it = st.find(items, id)
        if not it then return end
        if it.kind == 4 then
            run("wl-copy", {}, nil, { input = it.url, output = false })
            say("COPIED")
            return
        end
        run("xdg-open", { it.url }, function(_, code)
            if code ~= 0 then say("NOTHING OPENS THAT") end
        end)
    end)

    -- A press on the ×: the item goes, and a copy of ours with it. A link or a piece of text
    -- is only a line here, so it goes without a trace.
    on("stash_del", function(v)
        local id = math.floor(tonumber(v) or -1)
        local it
        items, it = st.remove(items, id)
        if not it then return end
        if dir ~= "" and string.sub(it.url, 1, #dir + 1) == dir .. "/" then
            run("rm", { "-rf", "--", it.url })
            if it.poster then run("rm", { "-f", "--", it.poster }) end
        end
        save(); show(); say("REMOVED")
    end)

    -- The wheel pages the list: one page a notch, a touchpad's small steps adding up.
    on("stash_scroll", function(v)
        scroll = scroll + (tonumber(v) or 0)
        local steps = 0
        while scroll >= 1 do scroll = scroll - 1; steps = steps + 1 end
        while scroll <= -1 do scroll = scroll + 1; steps = steps - 1 end
        if steps == 0 then return end
        page = page - steps
        show()
    end)

    if dir ~= "" then run("mkdir", { "-p", dir }) end
    load()

    fact.stash_page = 0
    fact.stash_saying = false
    fact.stash_root = true
    text.stash_said = ""
    text.stash_here_name = ""
    text.stash_new = ""

    return {}
end
