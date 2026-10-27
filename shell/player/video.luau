-- The music video as the visual (the music player overhaul), a part of mooi-player.luau. VIDEO
-- finds the song's video (yt-dlp fetches it once into ~/.cache/mooi/videos — YouTube refuses mpv's
-- own stream), pauses mpd, and plays it in
-- an mpv window placed exactly in the view's visual box by a Hyprland rule made at that moment
-- (float, pinned, never focused, no border or shadow). The player is an overlay layer — drawn above
-- every window — so mpv sits under it and the player leaves that box undrawn. Closing it (VIDEO
-- again, a new size or view, the video's end) quits mpv and mpd picks up where the video reached.
-- Its position is the clock since mpv began playing (mpv's status line is not line by line).
local P = require("lib/player")

local M = {}

function M.new(ctx)
    local say, mpc = ctx.say, ctx.mpc
    local mpv = nil
    local started = nil        -- os.time() when the picture began
    local len = 0              -- the song's length, for where mpd picks up
    local was_playing = false
    local VIDEOS = ctx.home .. "/.cache/mooi/videos"
    run("mkdir", { "-p", VIDEOS })
    -- what it needs, asked once: a missing tool is named on the chip, not taken for a missing video
    local missing = ""
    local function probe(cmd)
        run(cmd, { "--version" }, function(_, code)
            if code ~= 0 then missing = missing == "" and cmd or (missing .. " and " .. cmd) end
            text.video_why = missing ~= "" and ("VIDEO NEEDS " .. string.upper(missing)) or ""
            fact.video_tools = missing == ""
        end)
    end
    probe("mpv"); probe("yt-dlp")

    local function show(on, busy)
        fact.video_on = on
        fact.video_busy = busy
    end

    local cancelled = false    -- closed by a hand, not ended by a failure
    local function finish(found)
        local t = started and P.resume_at(os.time() - started, len) or nil
        mpv, started = nil, nil
        show(false, false)
        if not found and not cancelled then say("NO VIDEO FOUND FOR THIS SONG") end
        cancelled = false
        if t and t > 0 then mpc({ "seek", P.clock(t) }, function() if was_playing then mpc({ "play" }) end end)
        elseif was_playing then mpc({ "play" }) end
    end

    -- A process killed from here does not call back, so the closing is done here: mpd picks up,
    -- then the program (mpv or yt-dlp) is told to go.
    local function stop()
        if not mpv then return end
        local id = mpv
        cancelled = true
        finish(started ~= nil)
        kill(id, "term")
    end

    local function start()
        local song, src = ctx.song(), fact.src
        local ok, why = P.video_allowed(src, song)
        if not ok then say(string.upper(why)); return end
        if missing ~= "" then say("VIDEO NEEDS " .. string.upper(missing)); return end
        local q = P.video_query(song.artist, song.title)
        local st = ctx.status()
        len = tonumber(song.seconds) or 0
        was_playing = st ~= nil and st.state == "playing"
        local x, y = math.floor(tonumber(fact.vbx) or 0), math.floor(tonumber(fact.vby) or 0)
        local w, h = math.floor(tonumber(fact.vbw) or 640), math.floor(tonumber(fact.vbh) or 360)
        show(true, true)
        say("LOOKING FOR THE VIDEO…")
        -- the rule first, so the window maps where it belongs and never takes the focus
        run("hyprctl", { "eval", string.format(
            'hl.window_rule({ match = { title = "^mooi-video$" }, float = true, pin = true, no_focus = true, no_initial_focus = true, ' ..
            'border_size = 0, no_shadow = true, rounding = 0, no_anim = true, no_blur = true, opaque = true, size = "%d %d", move = "%d %d" })',
            w, h, x, y) }, function()
            mpc({ "pause" })
            local file = P.video_file(VIDEOS, song.artist, song.title)
            local function play()
                local mine
                local found = false
                mine = spawn("mpv", { "--title=mooi-video", "--force-window=immediate", "--no-border", "--keep-open=no",
                                      "--osc=no", "--no-input-default-bindings",
                                      "--force-media-title=" .. (song.artist ~= "" and (song.artist .. " — ") or "") .. song.title .. " (video)",
                                      file }, function(line)
                    if mpv ~= mine then return end
                    if not found and (line:find("%(%+%) Video") or line:find("AV:") or line:find("^%s*VO:")) then
                        found = true
                        started = os.time()
                        show(true, false)
                        say("VIDEO · " .. string.upper(song.title))
                    end
                end, function()
                    if mpv == mine then finish(found) end
                end, { errors = true })
                mpv = mine
            end
            -- kept from an earlier time? Else yt-dlp fetches it (≤ 720p, one file), saying how far it is
            run("ls", { file }, function(_, have)
                if have == 0 then play(); return end
                local mine
                mine = spawn("yt-dlp", { "-q", "--newline", "--progress", "--no-playlist", "--no-warnings",
                                         "-f", "b[height<=720][ext=mp4]/b[height<=720]/b", "-o", file, q }, function(line)
                    local pct = P.video_progress(line)
                    if pct and mpv == mine then say(string.format("FETCHING THE VIDEO · %d%%", math.floor(pct))) end
                end, function(_, code)
                    if mpv ~= mine then return end
                    mpv = nil
                    if code == 0 then play() else finish(false) end
                end, { errors = true })
                mpv = mine
            end)
        end)
    end

    on("video_toggle", function() if mpv then stop() else start() end end)
    on("video_stop", function() stop() end)

    -- while the video plays, the progress follows its clock (mpd is paused meanwhile)
    every(1000, function()
        if not started or len <= 0 then return end
        local t = os.time() - started
        fact.progress = math.min(1, t / len)
        text.t_elapsed = P.clock(t)
        if ctx.est then ctx.est(t, true) end   -- the lyrics follow the video, not the paused mpd
    end)

    return { stop = stop }
end

return M
