-- The player's library (mpd), a part of mooi-player.luau: every song read once with `mpc listall`
-- (lib/player LIB_FMT), then shown four ways — ALBUMS as a grid of covers (normal), ARTISTS and
-- GENRES as lists that open onto their albums, SONGS as the detailed list — searched and sorted in
-- memory. Covers come from the songs themselves (the embedded picture, else a cover/folder/front
-- image beside the file), made one at a time for the page on screen only, and kept in
-- ~/.cache/mooi/covers at 256 and 64 px; an album with none gets a cover in the palette's tones.
local P = require("lib/player")

local M = {}

M.PAGE = 9           -- rows a page, and covers in the grid (3 × 3)
M.QUEUE_MAX = 24     -- covers waiting at most

-- The covers a new page asks for: its files not yet known, in order, at most QUEUE_MAX. What the
-- last page still wanted is dropped — paging fast never builds a backlog.
function M.next_cover_queue(old, page, cached)
    local out = {}
    for _, f in ipairs(page or {}) do
        if #out >= M.QUEUE_MAX then break end
        if not (cached or {})[f] then out[#out + 1] = f end
    end
    return out
end

-- The songs an artist's or a genre's row stands for (the same rule the lists are built by).
function M.files_for(all, group, name)
    local out = {}
    for _, r in ipairs(all or {}) do
        local v
        if group == "artists" then v = (r.albumartist ~= "" and r.albumartist) or (r.artist ~= "" and r.artist) or "Unknown artist"
        else v = (r.genre ~= "" and r.genre) or "No genre" end
        if v == name then out[#out + 1] = r.file end
    end
    return out
end

function M.new(ctx)
    local mpc, refresh_queue, say = ctx.mpc, ctx.refresh_queue, ctx.say
    local home, music_dir, roles = ctx.home, ctx.music_dir, ctx.roles
    local COVERS = home .. "/.cache/mooi/covers"
    run("mkdir", { "-p", COVERS })

    local GROUPS = { "albums", "artists", "genres", "songs" }
    local SORTS = { albums = { "artist", "album", "year" }, songs = { "title", "artist", "album", "year", "time" } }
    local all = nil                 -- every song, read once a session
    local st = { group = ctx.group or "albums", sort = ctx.sort or "artist", page = 0, query = "", drill = nil }
    local list = {}                 -- what the page is cut from
    local mode = "grid"             -- grid (albums) · rows (everything else)

    -- ── covers ────────────────────────────────────────────────
    local known = {}                -- file → true (made, or none to make)
    local has = {}                  -- file → true when a picture exists
    local queue, busy = {}, false
    local on_cover = function() end
    local function art_for(file, size) return has[file] and P.cover_file(COVERS, file, size) or "" end
    local function make_next()
        if busy or #queue == 0 then return end
        local file = table.remove(queue, 1)
        if known[file] then make_next(); return end
        busy = true
        local big, small = P.cover_file(COVERS, file, 256), P.cover_file(COVERS, file, 64)
        local path = P.path(music_dir(), file)
        local dir = path:match("^(.*)/[^/]*$") or "."
        local tries = { path, dir .. "/cover.jpg", dir .. "/folder.jpg", dir .. "/front.jpg", dir .. "/cover.png", dir .. "/folder.png" }
        local function finish(ok)
            known[file] = true; has[file] = ok or nil; busy = false
            if ok then on_cover(file) end
            make_next()
        end
        local function try(i)
            if i > #tries then finish(false); return end
            run("ffmpeg", { "-v", "error", "-y", "-i", tries[i], "-an", "-frames:v", "1",
                            "-vf", "scale=256:256:force_original_aspect_ratio=increase,crop=256:256", big }, function(_, code)
                if code ~= 0 then try(i + 1); return end
                run("magick", { big, "-resize", "64x64", small }, function(_, c2) finish(c2 == 0) end)
            end)
        end
        -- already made in an earlier session?
        run("magick", { "identify", small }, function(_, have)
            if have == 0 then finish(true) else try(1) end
        end)
    end
    local function want_covers(files)
        queue = M.next_cover_queue(queue, files, known)
        make_next()
    end

    -- ── what is shown ─────────────────────────────────────────
    local function matches(r)
        if st.query == "" then return true end
        local q = string.lower(st.query)
        for _, k in ipairs({ "title", "artist", "album", "albumartist", "genre" }) do
            if string.find(string.lower(tostring(r[k] or "")), q, 1, true) then return true end
        end
        return false
    end
    local function songs_where(pred)
        local out = {}
        for _, r in ipairs(all or {}) do if matches(r) and pred(r) then out[#out + 1] = r end end
        return out
    end
    local function names(field)
        local count, order = {}, {}
        for _, r in ipairs(songs_where(function() return true end)) do
            local v = field == "artists" and ((r.albumartist ~= "" and r.albumartist) or (r.artist ~= "" and r.artist) or "Unknown artist")
                      or ((r.genre ~= "" and r.genre) or "No genre")
            if not count[v] then count[v] = 0; order[#order + 1] = v end
            count[v] = count[v] + 1
        end
        local out = {}
        for _, v in ipairs(order) do out[#out + 1] = { name = v, sub = count[v] == 1 and "1 song" or (count[v] .. " songs") } end
        return P.sort(out, "name")
    end

    local function show()
        local pages = math.max(1, math.ceil(#list / M.PAGE))
        st.page = math.max(0, math.min(st.page, pages - 1))
        local first = st.page * M.PAGE + 1
        local files, grid, rows = {}, {}, {}
        for i = first, math.min(#list, first + M.PAGE - 1) do
            local r = list[i]
            if r.file then files[#files + 1] = r.file end
            if mode == "grid" then
                local t = P.cover_tones(r.album, roles())
                grid[#grid + 1] = { name = r.album, sub = r.artist .. (r.year ~= "" and ("  ·  " .. r.year) or ""), k = i, n = #grid,
                                    art = art_for(r.file, 256), has_art = has[r.file] == true, ini = t.initials,
                                    ar = t.a.r, ag = t.a.g, ab = t.a.b, br = t.b.r, bg = t.b.g, bb = t.b.b }
            else
                rows[#rows + 1] = { name = r.name or r.title, sub = r.sub or "", n = #rows, k = i, song = r.title ~= nil,
                                    art = r.file and art_for(r.file, 64) or "", has_art = r.file ~= nil and has[r.file] == true,
                                    thumb = r.file ~= nil, time = r.seconds and P.clock(r.seconds) or "" }
            end
        end
        model.albums = grid
        model.librows = rows
        fact.lib_grid = mode == "grid"
        fact.lib_count = #list
        fact.lib_page = st.page
        fact.lib_pages = pages
        fact.lib_level = st.drill and 1 or 0
        fact.lib_group = ({ albums = 0, artists = 1, genres = 2, songs = 3 })[st.group] or 0
        text.lib_sort = string.upper(st.sort)
        local where = st.drill and string.upper(st.drill.label) or ({ albums = "ALBUMS", artists = "ARTISTS", genres = "GENRES", songs = "SONGS" })[st.group]
        if st.query ~= "" then where = where .. "  ·  “" .. string.upper(st.query) .. "”" end
        text.lib_where = where
        want_covers(files)
    end

    local function song_row(r)
        r.sub = P.song_line(r)
        return r
    end
    local function rebuild()
        if not all then return end
        local d = st.drill
        if d and d.kind == "album" then
            mode = "rows"
            list = {}
            for _, r in ipairs(songs_where(function(r)
                local a = (r.albumartist ~= "" and r.albumartist) or (r.artist ~= "" and r.artist) or "Unknown artist"
                return a == d.artist and ((r.album ~= "" and r.album) or "Unknown album") == d.album end)) do
                list[#list + 1] = song_row(r)
            end
            list = P.album_tracks(list)
        elseif d then        -- an artist or a genre: its albums, as the grid
            mode = "grid"
            list = P.sort(P.albums(songs_where(function(r)
                if d.kind == "artist" then
                    return ((r.albumartist ~= "" and r.albumartist) or (r.artist ~= "" and r.artist) or "Unknown artist") == d.name
                end
                return ((r.genre ~= "" and r.genre) or "No genre") == d.name end)), "year")
        elseif st.group == "albums" then
            mode = "grid"
            list = P.sort(P.albums(songs_where(function() return true end)), st.sort)
        elseif st.group == "songs" then
            mode = "rows"
            list = {}
            for _, r in ipairs(songs_where(function() return true end)) do
                r.year = r.date:sub(1, 4)
                list[#list + 1] = song_row(r)
            end
            list = P.sort(list, st.sort)
        else
            mode = "rows"
            list = names(st.group)
        end
        show()
    end

    local function load(done)
        if all then if done then done() end; return end
        text.lib_where = "READING THE LIBRARY…"
        local fields = {}
        for i, f in ipairs(P.LIB_FIELDS) do fields[i] = f end
        run("mpc", { "-f", P.LIB_FMT, "listall" }, function(out, code)
            if code ~= 0 then
                all = nil; model.albums = {}; model.librows = {}; fact.lib_count = 0
                text.lib_where = "MPD IS NOT RUNNING — systemctl --user start mpd"
                return
            end
            all = P.parse_songs(out, fields)
            for _, r in ipairs(all) do r.date = r.date or ""; r.genre = r.genre or ""; r.album = r.album or ""; r.albumartist = r.albumartist or "" end
            if done then done() end
        end)
    end

    -- ── what a press asks for ─────────────────────────────────
    local function add(r, play_now)
        local files = {}
        if r.file and r.title then files[1] = r.file
        elseif r.name and not r.album then files = M.files_for(all, st.group, r.name)   -- an artist's or a genre's row
        else
            for _, s in ipairs(all or {}) do
                local a = (s.albumartist ~= "" and s.albumartist) or (s.artist ~= "" and s.artist) or "Unknown artist"
                if a == r.artist and ((s.album ~= "" and s.album) or "Unknown album") == r.album then files[#files + 1] = s.file end
            end
        end
        if #files == 0 then return end
        local function go()
            local args = { "add" }
            for _, f in ipairs(files) do args[#args + 1] = f end
            mpc(args, function() refresh_queue(); if play_now then mpc({ "play" }) end end)
        end
        -- played from here while another player shows: the player turns to mpd, which is what plays
        if play_now and ctx.use_library then ctx.use_library() end
        if play_now then mpc({ "clear" }, go) else go() end
        say((play_now and "PLAYING · " or "ADDED · ") .. string.upper(r.title or r.album or ""))
    end

    on_cover = function(file)
        -- a cover arrived: the page shows it if it is still on screen
        local first = st.page * M.PAGE + 1
        for i = first, math.min(#list, first + M.PAGE - 1) do
            if list[i].file == file then show(); return end
        end
    end

    on("lib_open", function(v)
        local r = list[math.floor(tonumber(v) or 0)]
        if not r then return end
        if mode == "grid" then
            st.drill = { kind = "album", artist = r.artist, album = r.album, label = r.album .. "  ·  " .. r.artist, back = st.drill }
            st.page = 0; rebuild()
        elseif r.title then add(r, true)
        else
            st.drill = { kind = st.group == "genres" and "genre" or "artist", name = r.name, label = r.name }
            st.page = 0; rebuild()
        end
    end)
    on("lib_play", function(v) local r = list[math.floor(tonumber(v) or 0)]; if r then add(r, true) end end)
    on("lib_add", function(v) local r = list[math.floor(tonumber(v) or 0)]; if r then add(r, false) end end)
    on("lib_back", function()
        if st.drill then st.drill = st.drill.back; st.page = 0; rebuild()
        elseif st.query ~= "" then st.query = ""; text.lib_query = ""; rebuild() end
    end)
    on("lib_page", function(d) st.page = st.page + ((tonumber(d) or 0) > 0 and 1 or -1); show() end)
    on("lib_group", function(v)
        st.group = GROUPS[(math.floor(tonumber(v) or 0)) + 1] or "albums"
        st.drill, st.page = nil, 0
        local sorts = SORTS[st.group]
        if sorts then
            local ok = false
            for _, s in ipairs(sorts) do if s == st.sort then ok = true end end
            if not ok then st.sort = sorts[1] end
        end
        if ctx.remember then ctx.remember(st.group, st.sort) end
        rebuild()
    end)
    on("lib_sort", function()
        local sorts = SORTS[st.group] or SORTS.albums
        local at = 1
        for i, s in ipairs(sorts) do if s == st.sort then at = i end end
        st.sort = sorts[at % #sorts + 1]; st.page = 0
        if ctx.remember then ctx.remember(st.group, st.sort) end
        rebuild()
    end)
    local gen = 0
    on("text:lib_query", function(v)
        gen = gen + 1
        local g = gen
        after(250, function()
            if g ~= gen then return end
            st.query = tostring(v or ""); st.page = 0; rebuild()
        end)
    end)

    return {
        open = function() load(rebuild) end,
        ready = function() return all ~= nil end,
    }
end

return M
