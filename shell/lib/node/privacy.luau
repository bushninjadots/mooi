-- The node's privacy watch (D230): is the microphone or the camera in use, and did that just change. Pure: it
-- reads the decoded JSON of `pactl -f json list source-outputs` and the text `fuser` prints, and answers names
-- and a word. It asks nothing and watches nothing itself.

local M = {}

-- the tools that hold the microphone open to listen to it themselves, never the owner
local IGNORED = { pleamar = true, pavucontrol = true, cava = true }

local function lower(v) return type(v) == "string" and v:lower() or "" end

-- the applications using the microphone, once each and in name order; monitors, peak meters and mooi's own
-- helpers do not count
function M.mic_users(list)
    local out, seen = {}, {}
    if type(list) ~= "table" then return out end
    for _, item in ipairs(list) do
        if type(item) == "table" then
            local props = type(item.properties) == "table" and item.properties or {}
            local binary = lower(props["application.process.binary"])
            local media = lower(props["media.name"])
            local monitor = lower(props["stream.monitor"]) == "true"
            if not monitor and not media:find("peak detect", 1, true) and not IGNORED[binary] then
                local name = props["application.name"]
                if type(name) ~= "string" or name == "" then name = props["application.process.binary"] end
                if type(name) ~= "string" or name == "" then name = "Unknown" end
                if not seen[name] then
                    seen[name] = true
                    out[#out + 1] = name
                end
            end
        end
    end
    table.sort(out, function(a, b)
        local la, lb = a:lower(), b:lower()
        if la == lb then return a < b end
        return la < lb
    end)
    return out
end

-- fuser's answer: a `/dev/videoN:` line with at least one process on it means the camera is open
function M.camera_in_use(text)
    if type(text) ~= "string" then return false end
    for line in text:gmatch("[^\r\n]+") do
        local rest = line:match("^%s*/dev/video%d+%s*:(.*)$")
        if rest and rest:find("%d") then return true end
    end
    return false
end

-- what just happened to a yes/no: "started", "stopped", or nothing when it did not change
function M.changed(before, after)
    before = before and true or false
    after = after and true or false
    if before == after then return nil end
    return after and "started" or "stopped"
end

return M
