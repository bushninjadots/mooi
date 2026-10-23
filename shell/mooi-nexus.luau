-- Control Nexus (D65): the system command centre, a program of its own. The scene
-- (`mooi-nexus.plm`) draws the plate and reads the bar's own services; this file paints the
-- shell's colours into it, keeps the player's text fields, and is the only place that calls
-- the system. The data folder is mooi's (bin/mooi links mooi-nexus to it), so settings.json
-- and palette.json are shared with the bar and a wallpaper change re-lights the plate too.

local config = require("lib/config")
local ferro = require("lib/ferro")
local style = require("lib/style")
local nexus = require("lib/nexus")

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
local format_time = nexus.format_time

local function clear_media()
    fact.nx_has = false
    fact.nx_playing = false
    fact.nx_progress = 0
    fact.nx_media_time_on = false
    fact.nx_album_on = false
    fact.nx_player_on = false
    text.nx_elapsed = ""
    text.nx_duration = ""
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
    fact.nx_media_time_on = fact.nx_has and length > 0
    local safe_position = math.max(0, math.min(length, position))
    fact.nx_progress = (fact.nx_has and length > 0) and safe_position / length or 0
    text.nx_elapsed = fact.nx_media_time_on and format_time(safe_position) or ""
    text.nx_duration = fact.nx_media_time_on and format_time(length) or ""
    fact.nx_album_on = album ~= ""
    fact.nx_player_on = player ~= ""
    text.nx_title = title
    text.nx_artist = artist
    text.nx_album = album
    text.nx_player = player
end)

-- ── The controls ────────────────────────────────────────────
-- A wheel asks for a new level every notch; the system is told at most every 40 ms, always
-- the latest. The services remain the source of truth for displayed values. If a command
-- raises an error, the footer reports which operation failed without exposing raw internals.
local notice_serial = 0
local function report_control_failure(label)
    notice_serial = notice_serial + 1
    local serial = notice_serial
    text.nx_notice_text = label .. " FAILED"
    fact.nx_notice = true
    after(2600, function()
        if notice_serial == serial then fact.nx_notice = false end
    end)
end

local function control_call(label, service, value)
    local ok, result
    if value == nil then
        ok, result = pcall(sys.call, service)
    else
        ok, result = pcall(sys.call, service, value)
    end
    if not ok or result == false then report_control_failure(label); return false end
    return true
end

local pending = {}
local flushing = false
local function flush()
    flushing = false
    if pending.vol ~= nil then control_call("VOLUME", "audio.volume", pending.vol) end
    if pending.bri ~= nil then control_call("BRIGHTNESS", "brightness.level", pending.bri) end
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
on("nx_mute", function() control_call("MUTE", "audio.mute") end)
on("nx_media", function(v)
    local label, service = nexus.media_action(v)
    if service then control_call(label, service) end
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
