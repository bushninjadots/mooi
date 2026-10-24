-- Pure parsers for the Control Nexus system overview.
-- Inputs are text read by the system-data bridge; this module does not execute commands,
-- read arbitrary files, or assume that optional hardware exists.

local M = {}
local function clean(value)
    if type(value) ~= "string" then return nil end
    value = value:gsub("^%s+", ""):gsub("%s+$", "")
    return value ~= "" and value or nil
end

function M.uptime(text)
    local seconds = tonumber(string.match(text or "", "^%s*(%d+%.?%d*)"))
    if not seconds or seconds < 0 then return nil end
    seconds = math.floor(seconds)
    local days = math.floor(seconds / 86400)
    local hours = math.floor((seconds % 86400) / 3600)
    local minutes = math.floor((seconds % 3600) / 60)
    if days > 0 then return string.format("%dd %dh %dm", days, hours, minutes) end
    if hours > 0 then return string.format("%dh %dm", hours, minutes) end
    return string.format("%dm", minutes)
end

function M.os_release(text)
    local out = {}
    for line in string.gmatch(text or "", "[^\n]+") do
        local key, value = string.match(line, "^([A-Z_]+)=(.*)$")
        if key and value then
            value = clean(value)
            if value then
                local quote = value:sub(1, 1)
                if (quote == '"' or quote == "'") and value:sub(-1) == quote and #value >= 2 then
                    value = value:sub(2, -2)
                    if quote == '"' then value = value:gsub('\\"', '"'):gsub('\\\\', '\\') end
                else
                    value = value:gsub("%s+#.*$", "")
                end
                out[key] = value
            end
        end
    end
    return { name = out.PRETTY_NAME or out.NAME, id = out.ID, version = out.VERSION_ID,
        codename = out.VERSION_CODENAME or out.UBUNTU_CODENAME }
end

function M.cpu_model(text)
    return clean(string.match(text or "", "\n?model name%s*:%s*([^\n]+)"))
        or clean(string.match(text or "", "\n?Hardware%s*:%s*([^\n]+)"))
end

-- Parse df -Pk output for the root mount only.
function M.disk(text)
    for row in string.gmatch(text or "", "[^\n]+") do
        if not string.match(row, "^Filesystem%s") then
            local fs, total, used, avail, percent, mount =
                string.match(row, "^%s*(%S+)%s+(%d+)%s+(%d+)%s+(%d+)%s+(%d+)%%%s+(%S+)")
            if fs and mount == "/" then
                total, used, avail, percent = tonumber(total), tonumber(used), tonumber(avail), tonumber(percent)
                if total and total > 0 and used and avail and percent then
                    return { filesystem = fs, total_kib = total, used_kib = used, available_kib = avail,
                        used_fraction = math.max(0, math.min(1, used / total)), percent = math.max(0, math.min(100, percent)) }
                end
            end
        end
    end
    return nil
end

-- UPower's human report (`upower -i …`): the battery's health (full charge against design
-- capacity), its state, and the time it predicts. Locale decimal commas appear on this machine
-- ("30,1302 Wh"), so both separators are accepted. No battery, or no report, returns nil.
function M.upower(text)
    if type(text) ~= "string" or text == "" then return nil end
    local function number(value)
        if not value then return nil end
        return tonumber((value:gsub(",", ".")))
    end
    local health = number(string.match(text, "capacity:%s*([%d.,]+)%%"))
    local state = clean(string.match(text, "\n%s*state:%s*([%w-]+)"))
    -- Lua patterns have no alternation: each direction and unit is asked for plainly.
    local direction, value, unit
    for _, d in ipairs({ "empty", "full" }) do
        value, unit = string.match(text, "time to " .. d .. ":%s*([%d.,]+)%s*(hour)")
        if value then direction = d; break end
    end
    if not direction then
        for _, d in ipairs({ "empty", "full" }) do
            value, unit = string.match(text, "time to " .. d .. ":%s*([%d.,]+)%s*(minute)")
            if value then direction = d; break end
        end
    end
    local minutes
    local amount = number(value)
    if direction and amount then
        minutes = math.floor((unit == "hour" and amount * 60 or amount) + 0.5)
    end
    if health and (health < 0 or health > 100) then health = nil end
    if not health and not state and not minutes then return nil end
    return { health = health, state = state, direction = minutes and direction or nil, minutes = minutes }
end

function M.identity(os_text, kernel_text, hostname_text, uptime_text, cpuinfo_text)
    local os = M.os_release(os_text)
    return { distro = os.name, distro_id = os.id, distro_version = os.version,
        kernel = clean(kernel_text), hostname = clean(hostname_text), uptime = M.uptime(uptime_text),
        cpu = M.cpu_model(cpuinfo_text) }
end

return M
