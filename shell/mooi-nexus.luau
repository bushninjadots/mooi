-- Control Nexus (D65): the system command centre, a program of its own. The scene
-- (`mooi-nexus.plm`) draws the plate and reads the bar's own services; this file paints the
-- shell's colours into it, keeps the player's text fields, and is the only place that calls
-- the system. The data folder is mooi's (bin/mooi links mooi-nexus to it), so settings.json
-- and palette.json are shared with the bar and a wallpaper change re-lights the plate too.

local config = require("lib/config")
local ferro = require("lib/ferro")
local style = require("lib/style")

local FILE = "settings.json"
local PALETTE = "palette.json"

local function read(name, kind)
    local ok, v
    if kind then ok, v = pcall(sys.ask, "files.read", name, kind)
    else ok, v = pcall(sys.ask, "files.read", name) end
    return ok and v or nil
end

local function env(name, fallback)
    local ok, v = pcall(sys.ask, "env", name)
    if ok and type(v) == "string" and v ~= "" then return v end
    return fallback
end

local settings = config.parse(read(FILE), json.decode)
local palette = read(PALETTE, "json")

-- The same roles the bar wears, from the same palette and settings; the tokens glide to them.
local function paint()
    local out = ferro.resolve(settings.theme.source, palette, settings.theme.signal, false, ferro.options(settings))
    if not out then return end
    for _, role in ipairs(ferro.ROLES) do
        local c = out[role]
        fact["fr_" .. role .. "_r"] = c.r
        fact["fr_" .. role .. "_g"] = c.g
        fact["fr_" .. role .. "_b"] = c.b
    end
end
paint()
pcall(sys.watch, "files:" .. PALETTE, function()
    palette = read(PALETTE, "json")
    paint()
end)
pcall(sys.watch, "files:" .. FILE, function()
    settings = config.parse(read(FILE), json.decode)
    fact.nx_pinned = settings.nexus.pinned == true
end)

-- The glow the plate carries follows the theme's finish, as the bar's does.
local look = style.facts(settings)
if look and look.st_glow then fact.st_glow = look.st_glow end

-- Who is here: the session's own answers, never a made-up name. Each has a plain fallback
-- for a session that does not export it.
text.nx_user = env("USER", "operator")
text.nx_host = env("HOSTNAME", "Arch Linux")
text.nx_session = env("XDG_CURRENT_DESKTOP", "Hyprland")
fact.nx_pinned = settings.nexus and settings.nexus.pinned == true

-- The player: the service's text fields can be drawn, but not compared, so the facts that say
-- "there is something here" and the fields themselves are kept on this side of the boundary.
local function clear_media()
    fact.nx_has = false
    fact.nx_playing = false
    fact.nx_progress = 0
    fact.nx_album_on = false
    fact.nx_player_on = false
    text.nx_title = ""
    text.nx_artist = ""
    text.nx_album = ""
    text.nx_player = ""
end
clear_media()
pcall(sys.watch, "media", function(m)
    if type(m) ~= "table" then clear_media(); return end
    local title = type(m.title) == "string" and m.title or ""
    local artist = type(m.artist) == "string" and m.artist or ""
    local album = type(m.album) == "string" and m.album or ""
    local player = type(m.player) == "string" and m.player or ""
    local length = tonumber(m.length) or 0
    local position = tonumber(m.position) or 0

    fact.nx_has = title ~= ""
    fact.nx_playing = m.playing == true
    fact.nx_progress = (fact.nx_has and length > 0) and math.max(0, math.min(1, position / length)) or 0
    fact.nx_album_on = album ~= ""
    fact.nx_player_on = player ~= ""
    text.nx_title = title
    text.nx_artist = artist
    text.nx_album = album
    text.nx_player = player
end)

-- ── The controls ────────────────────────────────────────────
-- A wheel asks for a new level every notch; the system is told at most every 40 ms, always
-- the latest. What the plate shows is what the services report back, so a refused change
-- simply does not show.
local pending = {}
local flushing = false
local function flush()
    flushing = false
    if pending.vol then pcall(sys.call, "audio.volume", pending.vol) end
    if pending.bri then pcall(sys.call, "brightness.level", pending.bri) end
    pending = {}
end
local function request(kind, v)
    local n = tonumber(v)
    if not n then return end
    if n < 0 then n = 0 elseif n > 1 then n = 1 end
    if kind == "bri" and n < 0.01 then n = 0.01 end
    pending[kind] = n
    if not flushing then flushing = true; after(40, flush) end
end

on("nx_vol", function(v) request("vol", v) end)
on("nx_bri", function(v) request("bri", v) end)
on("nx_mute", function() pcall(sys.call, "audio.mute") end)
on("nx_media", function(v)
    local n = tonumber(v) or 0
    if n < -0.5 then pcall(sys.call, "media.previous")
    elseif n > 0.5 then pcall(sys.call, "media.next")
    else pcall(sys.call, "media.toggle") end
end)

-- Pinned: a press toggles the setting and writes it, so the Nexus opens pinned next time.
-- If the write is refused the press is undone, and the plate keeps saying what is true.
on("nx_pin", function()
    if type(settings.nexus) ~= "table" then settings.nexus = { pinned = false } end
    local pinned = not settings.nexus.pinned
    settings.nexus.pinned = pinned
    if tostring(sys.ask("env", "MOOI_SAFE") or "") ~= "1" then
        local ok = pcall(sys.call, "files.write", FILE, settings)
        if not ok then
            settings.nexus.pinned = not pinned
            return
        end
    end
    fact.nx_pinned = pinned
end)

-- The entrance: the plate unfolds under the mark (the scene's springs).
fact.nx_open = 1

-- ×, Escape, or a press outside the plate: it leaves the way it came, then the program ends
-- and the compositor gives the keyboard back to whatever is under it.
on("nx_close", function()
    if fact.nx_open == 0 then return end
    fact.nx_open = 0
    after(240, function() run("pleamar", { "--say", "mooi-nexus", "quit" }) end)
end)
