-- The Sigil's sources (D207): what every module can become. Pure. A source is one entry: its group (the
-- pointer ring's), its glyph and display kinds (lib/surface/shapes), how urgent its events are, its compact
-- words from a reading (nil reading → a dash: a dead feed shows as such), and what a press opens. In this
-- phase a press opens the module's existing panel; detail views built from the parts come later (plan,
-- "Phasing").

local M = {}

M.WAVE1 = { "clock", "calendar", "weather", "music", "volume", "notifications", "workspaces", "windows",
            "resources", "battery", "network", "bluetooth", "bmo" }
M.LATER = { "notes", "stash", "clipboard", "wallpaper", "search", "settings", "nexus", "desk", "screenshot",
            "recorder", "power", "mic", "temperature", "health" }

local DASH = { t1 = "—", t2 = "" }
local function pct(v) return string.format("%d%%", math.floor((tonumber(v) or 0) * 100 + 0.5)) end
local function str(v) return v == nil and "" or tostring(v) end

local E = {
    clock = { group = "time", glyph = "clock", display = "clock", press = { kind = "island", target = "calendar" },
              compact = function(r) if not r then return DASH end return { t1 = str(r.time), t2 = str(r.date) } end },
    calendar = { group = "time", glyph = "card", display = "card", press = { kind = "island", target = "calendar" },
                 compact = function(r) if not r then return DASH end return { t1 = str(r.date), t2 = str(r.weekday) } end },
    weather = { group = "time", glyph = "horizon", display = "horizon", press = { kind = "island", target = "weather" },
                compact = function(r) if not r or r.temp == nil then return DASH end
                    return { t1 = string.format("%d°", math.floor(tonumber(r.temp) + 0.5)), t2 = str(r.word) } end },
    music = { group = "sound", glyph = "wave", display = "disc", press = { kind = "island", target = "music" },
              urgency = { start = "gentle" },
              compact = function(r) if not r or not r.title or r.title == "" then return DASH end
                  return { t1 = str(r.title), t2 = str(r.artist) } end },
    volume = { group = "sound", glyph = "ribbon", display = "ribbon", press = { kind = "island", target = "sound" },
               compact = function(r) if not r or r.volume == nil then return DASH end
                   return { t1 = pct(r.volume), t2 = r.muted and "muted" or "", val = tonumber(r.volume) } end },
    notifications = { group = "you", glyph = "card", display = "card", press = { kind = "nexus" },
                      urgency = { arrive = "notable" },
                      compact = function(r) if not r then return DASH end
                          if r.title and r.title ~= "" then return { t1 = str(r.title), t2 = str(r.app) } end
                          return { t1 = string.format("%d signals", tonumber(r.count) or 0), t2 = "" } end },
    workspaces = { group = "work", glyph = "spaces", display = "spaces", press = { kind = "overview" },
                   compact = function(r) if not r or r.active == nil then return DASH end
                       return { t1 = tostring(r.active), t2 = "", val = tonumber(r.active) } end },
    windows = { group = "work", glyph = "card", display = "card", press = { kind = "overview" },
                compact = function(r) if not r or not r.title then return DASH end return { t1 = str(r.title), t2 = str(r.class) } end },
    resources = { group = "machine", glyph = "bars", display = "ring", press = { kind = "island", target = "stats" },
                  compact = function(r) if not r or r.cpu == nil then return DASH end
                      return { t1 = "CPU " .. pct(r.cpu), t2 = r.mem and ("MEM " .. pct(r.mem)) or "", val = tonumber(r.cpu) } end },
    battery = { group = "machine", glyph = "ribbon", display = "ring", press = { kind = "island", target = "power" },
                urgency = { low = "urgent" },
                compact = function(r) if not r or r.percent == nil then return DASH end
                    return { t1 = string.format("%d%%", math.floor(tonumber(r.percent) + 0.5)), t2 = r.charging and "charging" or "",
                             val = (tonumber(r.percent) or 0) / 100 } end },
    network = { group = "machine", glyph = "dots", display = "dots", press = { kind = "island", target = "system" },
                compact = function(r) if not r then return DASH end
                    if not r.online then return { t1 = "Offline", t2 = "" } end
                    return { t1 = str(r.name), t2 = r.strength and string.format("%d%%", r.strength) or "", val = (tonumber(r.strength) or 0) / 100 } end },
    bluetooth = { group = "machine", glyph = "dots", display = "dots", press = { kind = "island", target = "system" },
                  compact = function(r) if not r then return DASH end
                      if (tonumber(r.connected) or 0) == 0 then return { t1 = r.powered and "On" or "Off", t2 = "" } end
                      return { t1 = str(r.name), t2 = string.format("%d connected", r.connected) } end },
    bmo = { group = "bmo", glyph = "face", display = "face", press = { kind = "bmo" },
            compact = function(r) if not r then return DASH end return { t1 = str(r.say ~= "" and r.say or "BMO"), t2 = "" } end },
}

local INDEX = {}
for i, id in ipairs(M.WAVE1) do E[id].id = id; INDEX[id] = i end

function M.get(id) return E[id] end
function M.index(id) return INDEX[id] end

-- a bar module → the source it is (wave 1 or later); nil for modules that are not sources
local MODULE = { workspaces = "workspaces", window = "windows", media = "music", resources = "resources",
                 weather = "weather", notifications = "notifications", mic = "mic", volume = "volume",
                 battery = "battery", network = "network", bluetooth = "bluetooth", clock = "clock",
                 screenshot = "screenshot", recorder = "recorder", clipboard = "clipboard", power = "power",
                 overview = "workspaces", settings = "settings", notes = "notes", wallpaper = "wallpaper",
                 nexus = "nexus" }
function M.for_module(module_id) return MODULE[module_id] end

return M
