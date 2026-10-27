-- The player's library (mpd): artists → albums → songs, and a search. A part of mooi-player.luau,
-- given what it needs; the queue and the transport stay in the spine.
local P = require("lib/player")

return function(ctx)
    local mpc, refresh_queue, say = ctx.mpc, ctx.refresh_queue, ctx.say
    -- ── The library (mpd) ────────────────────────────────────────
    -- Artists (by their album artist) → their albums → the album's songs, and a search over every
    -- song. The artists' list is read once a session; the rest when it is opened. A row's ▶ plays it
    -- now (the queue becomes it), its + adds it to the queue, a press on it goes into it.
    local LROWS = 9
    local lib = { level = 0, artist = nil, album = nil, page = 0, rows = {}, query = "" }
    local artists = nil

    local function show_lib()
        local list = lib.rows
        local pages = math.max(1, math.ceil(#list / LROWS))
        lib.page = math.max(0, math.min(lib.page, pages - 1))
        local rows = {}
        for i = lib.page * LROWS + 1, math.min(#list, (lib.page + 1) * LROWS) do
            local r = list[i]
            rows[#rows + 1] = { name = r.name, sub = r.sub or "", n = #rows, k = i, song = r.file ~= nil }
        end
        model.librows = rows
        fact.lib_count = #list
        fact.lib_page = lib.page
        fact.lib_pages = pages
        fact.lib_level = lib.level
        text.lib_where = lib.level == 0 and "ARTISTS" or lib.level == 1 and string.upper(lib.artist or "")
            or lib.level == 2 and string.upper((lib.album or "") .. "  ·  " .. (lib.artist or "")) or ("SEARCH · " .. string.upper(lib.query))
    end

    local function open_artists()
        lib.level, lib.page = 0, 0
        local function fill()
            lib.rows = {}
            for _, a in ipairs(artists or {}) do lib.rows[#lib.rows + 1] = { name = a } end
            show_lib()
        end
        if artists then fill(); return end
        text.lib_where = "READING THE LIBRARY…"
        run("mpc", { "list", "albumartist" }, function(out, code)
            artists = code == 0 and P.parse_names(out) or {}
            if lib.level == 0 then fill() end
        end)
    end
    local function open_artist(a)
        lib.level, lib.artist, lib.page = 1, a, 0
        run("mpc", { "list", "album", "albumartist", a }, function(out)
            lib.rows = {}
            for _, al in ipairs(P.parse_names(out)) do lib.rows[#lib.rows + 1] = { name = al, sub = a } end
            show_lib()
        end)
    end
    local function open_album(a, al)
        lib.level, lib.artist, lib.album, lib.page = 2, a, al, 0
        run("mpc", { "-f", P.SONG_FMT, "find", "albumartist", a, "album", al }, function(out)
            lib.rows = {}
            local songs = P.parse_songs(out)
            table.sort(songs, function(x, y) return (tonumber(x.track:match("%d+")) or 0) < (tonumber(y.track:match("%d+")) or 0) end)
            for _, sg in ipairs(songs) do
                lib.rows[#lib.rows + 1] = { name = sg.title, sub = (sg.track ~= "" and (sg.track .. "  ·  ") or "") .. P.clock(sg.seconds), file = sg.file }
            end
            show_lib()
        end)
    end
    local function search(q)
        lib.query = q
        if q == "" then open_artists(); return end
        lib.level, lib.page = 3, 0
        run("mpc", { "-f", P.SONG_FMT, "search", "any", q }, function(out)
            if lib.query ~= q then return end
            lib.rows = {}
            for _, sg in ipairs(P.parse_songs(out)) do
                if #lib.rows >= 200 then break end
                lib.rows[#lib.rows + 1] = { name = sg.title, sub = sg.artist .. "  ·  " .. sg.album, file = sg.file }
            end
            show_lib()
        end)
    end

    -- What a row is, as mpc's words: a song is its file; an album or an artist, a find.
    local function row_find(r)
        if r.file then return nil, r.file end
        if lib.level == 0 then return { "albumartist", r.name } end
        if lib.level == 1 then return { "albumartist", lib.artist, "album", r.name } end
    end
    local function add_row(r, play_now)
        local find, file = row_find(r)
        local function go()
            if find then
                local args = { "findadd" }
                for _, a in ipairs(find) do args[#args + 1] = a end
                mpc(args, function() refresh_queue(); if play_now then mpc({ "play" }) end end)
            elseif file then
                mpc({ "add", file }, function()
                    refresh_queue()
                    if play_now then mpc({ "play" }) end
                end)
            end
        end
        if play_now then mpc({ "clear" }, go) else go() end
        say(play_now and "PLAYING · " .. string.upper(r.name) or "ADDED · " .. string.upper(r.name))
    end

    on("lib_open", function(v)
        local r = lib.rows[math.floor(tonumber(v) or 0)]
        if not r then return end
        if lib.level == 0 then open_artist(r.name)
        elseif lib.level == 1 then open_album(lib.artist, r.name)
        else add_row(r, true) end
    end)
    on("lib_play", function(v) local r = lib.rows[math.floor(tonumber(v) or 0)]; if r then add_row(r, true) end end)
    on("lib_add", function(v) local r = lib.rows[math.floor(tonumber(v) or 0)]; if r then add_row(r, false) end end)
    on("lib_back", function()
        if lib.level == 2 and lib.artist then open_artist(lib.artist)
        elseif lib.level == 3 then text.lib_query = ""; lib.query = ""; open_artists()
        else open_artists() end
    end)
    on("lib_page", function(d) lib.page = lib.page + ((tonumber(d) or 0) > 0 and 1 or -1); show_lib() end)
    local search_gen = 0
    on("text:lib_query", function(v)
        search_gen = search_gen + 1
        local g = search_gen
        after(250, function() if g == search_gen then search(tostring(v or "")) end end)
    end)

    return { open_artists = open_artists, ready = function() return artists ~= nil end }
end
