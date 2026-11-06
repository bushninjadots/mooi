-- mooi's lock screen (D160), the logic: the shell's colours, the wallpaper behind the plate, and
-- PAM. The scene owns the lock (ext-session-lock: `locked` opens it; the compositor confirms it in
-- `lock.held`); this decides only what a password is worth, and what the screen says meanwhile.
--
-- `files.read` only reaches this scene's own folder (`~/.local/share/pleamar/mooi-lock`), and the
-- palette, the settings and `wall.json` are the shell's (`…/pleamar/mooi`). `mooi lock` copies the
-- three in before it starts this, and again before every lock, which is why they are read here by
-- their plain names. A copy that is missing or refused leaves the scene's own colours on screen: a
-- lock that cannot find its theme still locks.

local config = require("lib/config")
local ferro = require("lib/ferro")

local function read(name, kind)
    local ok, v
    if kind then ok, v = pcall(sys.ask, "files.read", name, kind)
    else ok, v = pcall(sys.ask, "files.read", name) end
    return ok and v or nil
end

local settings = config.parse(read("settings.json"), json.decode)
if type(settings) ~= "table" then settings = {} end
local palette = read("palette.json", "json")
local ROLES = { "ground", "hull", "steel_900", "trace_dim", "trace", "phos", "ember", "muted", "ink" }

-- The backdrop (Settings → Lock): how far the wallpaper behind the plate is blurred, and how far it
-- is dimmed. Read from the settings.json `mooi lock` copies beside this scene, so a change lands on
-- the next lock; nothing unreadable is allowed to blank the screen — the design's own stands in.
local BLUR = { off = 0, light = 22, medium = 54, heavy = 96 }
local function backdrop()
    local l = type(settings.lock) == "table" and settings.lock or {}
    fact.lk_blur = BLUR[l.blur] or BLUR.medium
    local dim = tonumber(l.dim) or 72
    fact.lk_dim = math.max(0, math.min(90, dim)) / 100
end
backdrop()

-- Whether the lock wears the Nexus's two pictures (Settings → Lock: `lock.banner` for the strip
-- along the top, `lock.avatar` for the plate above the clock), each on unless turned off and
-- independent of the other — a banner without your face, or your face without a banner. Read from
-- the same copy of settings.json as the backdrop, so a choice lands on the next lock.
local function pictures()
    local l = type(settings.lock) == "table" and settings.lock or {}
    fact.lk_ban_on = l.banner ~= false
    fact.lk_av_on = l.avatar ~= false
end
pictures()

local function paint()
    local theme = type(settings.theme) == "table" and settings.theme or {}
    local ok, out = pcall(ferro.resolve, theme.source, palette, theme.signal, false, ferro.options(settings))
    if not ok or type(out) ~= "table" then return end
    for _, role in ipairs(ROLES) do
        local c = out[role]
        if type(c) == "table" then
            fact["lk_" .. role .. "_r"], fact["lk_" .. role .. "_g"], fact["lk_" .. role .. "_b"] = c.r, c.g, c.b
        end
    end
end
paint()
pcall(sys.watch, "files:palette.json", function() palette = read("palette.json", "json"); paint() end)
pcall(sys.watch, "files:settings.json", function()
    settings = config.parse(read("settings.json"), json.decode)
    if type(settings) ~= "table" then settings = {} end
    backdrop()
    pictures()
    paint()
end)

-- The wallpaper the shell is wearing: `wall.json` says which one. An animated picture (a GIF, an
-- animated PNG or WebP) is one the renderer plays itself, so the file is drawn as it stands. A video
-- is not: the desk wears it with mpvpaper, and a lock surface has nothing underneath it. `mooi lock`
-- hands this scene the video's still instead, and a short loop as an animated WebP once it has made
-- one — so `kind` is only read here for the case where that copy is older than the code.
local function wallpaper()
    local w = read("wall.json", "json")
    local src = type(w) == "table" and w.source or nil
    local still = type(w) == "table" and w.still or nil
    if type(w) == "table" and w.kind == "video" and type(still) == "string" and not tostring(src):match("%.webp$") then
        src = still
    end
    text.wp = type(src) == "string" and src or ""
    fact.has_wall = text.wp ~= ""
end
wallpaper()
pcall(sys.watch, "files:wall.json", wallpaper)

-- Whose screen this is. `USER` is what the session runs as; a shell that did not export it still has
-- `LOGNAME`, and `HOME` names the same person (the last part of the path) if neither is set.
local function whoami()
    local n = tostring(sys.ask("env", "USER") or sys.ask("env", "LOGNAME") or "")
    if n == "" then n = tostring(sys.ask("env", "HOME") or ""):match("([^/]+)/?$") or "" end
    text.who = string.upper(n)
end
whoami()

-- The pictures on the lock (D161): the Nexus's banner (a strip along the top) and its profile
-- picture (a plate above the clock), both copied beside this scene by `mooi lock`; `identity.json`
-- names the two copies.
local function picture()
    local p = read("identity.json", "json")
    -- The paths `mooi lock` wrote (`…/pleamar/mooi-lock/banner.jpg`, `…/avatar.jpg`, whole): an image
    -- fact draws a path as it stands, and a bare name beside the scene is not one — that, and not the
    -- file, was why neither picture showed. The wallpaper here is an absolute path for the same
    -- reason. A path that does not resolve draws nothing, which is the same screen as having none.
    local t = type(p) == "table" and p or {}
    local av = type(t.avatar) == "string" and t.avatar or ""
    local bn = type(t.banner) == "string" and t.banner or ""
    text.picpath, fact.has_pic = av, av ~= ""
    text.banpath, fact.has_ban = bn, bn ~= ""
end
picture()
pcall(sys.watch, "files:identity.json", picture)

-- ── What the glass says about the session ─────────────────────────────────
-- The three services the bar reads: the song (`media`), the battery, and how many notices are
-- waiting (`notification_history`, which the Signal Loom keeps). A locked screen that says nothing
-- about the session behind it is a wall; these two lines are what make it a door. Read live from the
-- compositor's services, so nothing has to be copied in.
pcall(sys.watch, "media", function(m)
    local t = type(m) == "table" and m or {}
    local title, artist = tostring(t.title or ""), tostring(t.artist or "")
    fact.lk_playing, fact.lk_track_on = t.playing == true, title ~= ""
    text.lk_track = (artist ~= "" and (title .. " · " .. artist)) or title
end)
pcall(sys.watch, "battery", function(b)
    local t = type(b) == "table" and b or {}
    fact.lk_batt, fact.lk_batt_pct, fact.lk_charging = t.present == true, tonumber(t.percent) or 0, t.charging == true
end)
-- the notices waiting, as Signal Loom keeps them (its feed, carried into this folder by `mooi lock`):
-- watching a notification service here would claim the name from the shell
local function notes_waiting()
    local ok, f = pcall(sys.ask, "files.read", "nexus-feed.json", "json")
    fact.lk_notes = (ok and type(f) == "table" and tonumber(f.count)) or 0
end
pcall(sys.watch, "files:nexus-feed.json", notes_waiting)
notes_waiting()

-- ── The music, drawn ─────────────────────────────────────────────────────
-- cava's bands reach the glass the way the palette does: the bar writes them into the shell's folder
-- and the carrier `mooi lock` starts copies the line into this one (a scene reads nowhere else).
-- lib/vizfeed decodes it and thins 32 bands to the sixteen the visualiser draws; no feed, or a line
-- that will not decode, is silence — a visualiser that keeps its last frame looks like a stuck one.
local vizfeed = require("lib/vizfeed")
local viz_seq = nil
local function bands()
    local t = vizfeed.decode(read("viz-levels.txt"))
    if not t or not vizfeed.newer(viz_seq, t.seq) then return end
    viz_seq = t.seq
    local thin = vizfeed.resample(t.bands, 16)
    for i = 0, 15 do fact["vb" .. tostring(i)] = math.max(0, math.min(1, thin[i + 1] or 0)) end
end
bands()
-- The file watch coalesces — four of cava's thirty lines a second reach a handler — and a
-- visualiser fed at fifteen frames a second is a slideshow rather than music. Like the Nexus's
-- card, the bars are read at the feed's own pace while something plays; `vizfeed.newer` refuses a
-- line already drawn, so a tick that finds the same seq writes no facts and costs nothing.
pcall(sys.watch, "files:viz-levels.txt", bands)
every(33, function() if fact.lk_playing then bands() end end)

-- ── The tries PAM has left ──────────────────────────────────────────────
-- A lock screen cannot ask PAM how many attempts remain, only whether one password was right, so
-- `mooi lock` copies the system's own tally in (`lockout.json`: the `deny` threshold, `unlock_time`,
-- and the misses already on record) and this counts this lock's attempts on top of it. The password
-- still goes to PAM alone; nothing here decides whether one is right.
local lockout = { deny = 3, unlock = 600, used = 0 }

local function tries_text()
    local left = lockout.deny - lockout.used
    if left <= 0 then
        return string.format("LOGIN LOCKED · WAIT %d MIN", math.max(1, math.floor(lockout.unlock / 60 + 0.5)))
    elseif left == 1 then
        return "1 TRY LEFT BEFORE THE LOGIN LOCKS"
    end
    return string.format("%d TRIES LEFT BEFORE THE LOGIN LOCKS", left)
end

local function tally()
    local t = read("lockout.json", "json")
    if type(t) == "table" then
        lockout.deny = tonumber(t.deny) or lockout.deny
        lockout.unlock = tonumber(t.unlock) or lockout.unlock
        lockout.used = tonumber(t.used) or 0
    end
    text.tries = lockout.used > 0 and tries_text() or ""
end

tally()
pcall(sys.watch, "files:lockout.json", tally)

-- ── The password ─────────────────────────────────────────────────────────
-- `auth.check` asks PAM whether that is the session owner's password: true or false. A wrong one
-- takes a couple of seconds on purpose, and the system counts it like any other failed login.

local function quiet()
    text.password = ""
    text.status = ""
    fact.wrong = false
end

on("tryauth", function()
    local pw = text.password
    if fact.authing or fact.right or pw == "" then return end
    fact.authing, fact.wrong = true, false
    text.status = "VERIFYING…"

    local ok = sys.ask("auth.check", pw)
    fact.authing = false
    text.password = ""

    if ok then
        lockout.used = 0
        text.tries = ""
        fact.right = true
        text.status = "UNLOCKED"
        after(260, function()
            fact.locked = false
            fact.right = false
            text.status = ""
        end)
    else
        lockout.used = lockout.used + 1
        text.tries = tries_text()
        fact.wrong = true
        text.status = "INCORRECT"
        after(1600, function()
            if fact.wrong then fact.wrong = false; text.status = "" end
        end)
    end
end)

-- ── Power ─────────────────────────────────────────────────────────────────
-- One press arms, a second does it; four seconds of nothing puts it back. `systemctl` is the
-- session's own way out: polkit allows the active seat to power off or reboot without a prompt, so
-- no password agent has to come up over the lock.
local armed = { what = nil, timer = nil }

local function disarm()
    if armed.timer then cancel(armed.timer); armed.timer = nil end
    armed.what = nil
    fact.armed = 0
    text.pwr_label, text.rbt_label, text.pwr_note = "POWER OFF", "REBOOT", ""
end

local function fire(what)
    disarm()
    text.pwr_note = what == "poweroff" and "POWERING OFF…" or "REBOOTING…"
    run("systemctl", { what })
end

local function power(what)
    if armed.what == what then
        fire(what)
        return
    end
    disarm()
    armed.what = what
    fact.armed = what == "poweroff" and 1 or 2
    if what == "poweroff" then text.pwr_label, text.pwr_note = "POWER OFF?", "PRESS AGAIN TO POWER OFF"
    else text.rbt_label, text.pwr_note = "REBOOT?", "PRESS AGAIN TO REBOOT" end
    armed.timer = after(4000, function() if armed.what == what then disarm() end end)
end

-- ── The transport ────────────────────────────────────────────────────────
-- Three keys that change the song from the lock: `media.*` is the compositor's own door to the
-- player (the bar's module uses the same calls), so nothing here has to know which player it is.
-- A press is fire-and-forget: the media service says what happened back through the watch above.
on("lk_prev", function() pcall(sys.call, "media.previous") end)
on("lk_toggle", function() pcall(sys.call, "media.toggle") end)
on("lk_next", function() pcall(sys.call, "media.next") end)

on("pwr_off", function() power("poweroff") end)
on("rbt", function() power("reboot") end)

-- Esc clears what was typed, and takes back a power button that was only armed.
on("clear", function()
    if fact.authing then return end
    disarm()
    quiet()
end)
