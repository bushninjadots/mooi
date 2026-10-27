-- The player's lyrics: a `.lrc` beside the song, the cache, LRCLIB; synced lines follow the song.
-- A part of mooi-player.luau, given what it needs.
local P = require("lib/player")

return function(ctx)
    local folder, read, mpc = ctx.folder, ctx.read, ctx.mpc
    local lyrics_for, est_sync
    -- ── Lyrics ───────────────────────────────────────────────────
    -- A `.lrc` beside the song first, then LRCLIB (once: the answer, even "none", is kept in the data
    -- folder by the song). Synced lines follow the song: the logic carries the time on between mpd's
    -- readings in quarter seconds, and the lit line moves with it.
    local LYR = folder .. "/player-lyrics"
    run("mkdir", { "-p", LYR })
    local lyr = { key = nil, data = nil, at = -1 }
    -- each song's nudge (lyrics that run early or late), kept by the song in player-lyrics.json
    local OFFSETS = "player-lyrics.json"
    local offsets = read(OFFSETS, "json")
    if type(offsets) ~= "table" then offsets = {} end
    local function offset() return lyr.key and tonumber(offsets[P.hash(lyr.key)]) or 0 end
    local function show_offset()
        local o = offset()
        text.lyr_offset = o == 0 and "ON TIME" or string.format("%s%.1f S", o > 0 and "+" or "", o)
    end
    local est = { t = 0, playing = false }
    local LYR_ROWS = 9
    est_sync = function(t, playing) est.t = tonumber(t) or 0; est.playing = playing end

    local function show_lyrics()
        local d = lyr.data
        fact.lyr_on = d ~= nil and #d.lines > 0
        fact.lyr_synced = d ~= nil and d.synced == true
        local rows = {}
        if d and #d.lines > 0 then
            local cur = d.synced and P.lyric_at(d, est.t, offset()) or 0
            lyr.at = cur
            -- the lit line sits third from the top, the coming ones under it
            local first = d.synced and math.max(1, cur - 2) or math.max(1, lyr.scroll or 1)
            for i = first, math.min(#d.lines, first + LYR_ROWS - 1) do
                local l = d.lines[i]
                rows[#rows + 1] = { text = l.text ~= "" and l.text or "♪", cur = i == cur, dist = math.abs(i - math.max(cur, 1)),
                                    t = math.floor(l.t * 10), n = #rows }
            end
        end
        model.lyr = rows
    end

    lyrics_for = function(key, artist, title, album, seconds, path)
        if lyr.key == key then return end
        lyr.key, lyr.data, lyr.scroll = key, nil, 1
        show_offset()
        text.lyr_note = "LOOKING FOR THE LYRICS…"
        show_lyrics()
        local cache = "player-lyrics/" .. P.hash(key) .. ".lrc"
        local function got(raw, source)
            if lyr.key ~= key then return end
            if raw == "none" then lyr.data = nil; text.lyr_note = "NO LYRICS FOUND FOR THIS SONG"
            elseif raw == "instrumental" then lyr.data = nil; text.lyr_note = "INSTRUMENTAL"
            else lyr.data = P.parse_lrc(raw); text.lyr_note = source end
            show_lyrics()
        end
        local function ask_lrclib()
            if artist == "" or title == "" then got("none", ""); return end
            run("curl", { "-fsSL", "--max-time", "10", "-H", "User-Agent: mooi (https://github.com/bushninjadots/mooi)",
                          P.lrclib_url(artist, title, album, seconds) }, function(out, code)
                local ans = nil
                if code == 0 then
                    local ok, t = pcall(json.decode, out or "")
                    ans = ok and P.from_lrclib(t) or nil
                    if ok and type(t) == "table" then
                        local keep = t.instrumental == true and "instrumental" or (t.syncedLyrics ~= nil and t.syncedLyrics ~= json.null and t.syncedLyrics)
                            or (t.plainLyrics ~= nil and t.plainLyrics ~= json.null and t.plainLyrics) or "none"
                        if type(keep) ~= "string" then keep = "none" end
                        pcall(sys.call, "files.write", cache, keep)
                        got(keep, "LYRICS · LRCLIB")
                        return
                    end
                end
                -- 404 is LRCLIB's "not known": remembered, so the song is not asked about again
                if code == 22 then pcall(sys.call, "files.write", cache, "none") end
                got(ans and "" or "none", "")
            end)
        end
        local cached = read(cache)
        if type(cached) == "string" and cached ~= "" then got(cached, "LYRICS · SAVED"); return end
        local beside = P.lrc_beside(path)
        if beside then
            run("cat", { beside }, function(out, code)
                if code == 0 and out and out ~= "" then got(out, "LYRICS · BESIDE THE SONG") else ask_lrclib() end
            end)
        else
            ask_lrclib()
        end
    end

    -- the quarter-second clock, only while there are lyrics to follow
    every(250, function()
        if fact.pl_open == 0 or not lyr.data or not lyr.data.synced then return end
        if est.playing then est.t = est.t + 0.25 end
        if P.lyric_at(lyr.data, est.t, offset()) ~= lyr.at then show_lyrics() end
    end)
    on("lyr_seek", function(v)
        local t = (tonumber(v) or 0) / 10
        if fact.src == "library" then mpc({ "seek", P.clock(t) }) else run("playerctl", { "position", tostring(t) }) end
        est.t = t
        show_lyrics()
    end)
    on("lyr_scroll", function(d)
        if not lyr.data or lyr.data.synced then return end
        lyr.scroll = math.max(1, math.min(#lyr.data.lines, (lyr.scroll or 1) + ((tonumber(d) or 0) > 0 and -3 or 3)))
        show_lyrics()
    end)

    -- ± half a second for this song (the lines come earlier with +)
    on("lyr_nudge", function(d)
        if not lyr.key then return end
        local h = P.hash(lyr.key)
        offsets[h] = P.clamp_offset(offset() + ((tonumber(d) or 0) > 0 and 0.5 or -0.5))
        if offsets[h] == 0 then offsets[h] = nil end
        pcall(sys.call, "files.write", OFFSETS, offsets)
        show_offset()
        show_lyrics()
    end)
    show_offset()

    return { lyrics_for = lyrics_for, est_sync = est_sync }
end
