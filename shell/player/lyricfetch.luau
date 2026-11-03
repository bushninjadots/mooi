-- Finding a song's lyrics, shared by the player (player/lyrics.luau) and the desktop widgets: the
-- cache first, then a `.lrc` beside the song, then LRCLIB (once: the answer, even "none", is kept
-- in the data folder by the song's key). Draws nothing: `done(raw, source)` gets the LRC text, or
-- "none" / "instrumental", and where it came from.
local P = require("lib/player")

return function(ctx)
    local read = ctx.read

    return function(key, artist, title, album, seconds, path, done)
        local cache = "player-lyrics/" .. P.hash(key) .. ".lrc"
        local function ask_lrclib()
            if artist == "" or title == "" then done("none", ""); return end
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
                        done(keep, "LYRICS · LRCLIB")
                        return
                    end
                end
                -- 404 is LRCLIB's "not known": remembered, so the song is not asked about again
                if code == 22 then pcall(sys.call, "files.write", cache, "none") end
                done(ans and "" or "none", "")
            end)
        end
        local cached = read(cache)
        if type(cached) == "string" and cached ~= "" then done(cached, "LYRICS · SAVED"); return end
        local beside = P.lrc_beside(path)
        if beside then
            run("cat", { beside }, function(out, code)
                if code == 0 and out and out ~= "" then done(out, "LYRICS · BESIDE THE SONG") else ask_lrclib() end
            end)
        else
            ask_lrclib()
        end
    end
end
