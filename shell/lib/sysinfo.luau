-- What the bar reads that no pleamar service reports: the processor, the memory, the
-- temperature, the network's throughput, and the weather. Pure parsers over what the
-- logic's `run` hands back (/proc files, `sensors -j`, open-meteo's JSON), so tests/unit
-- runs them under plain Lua 5.4 (written in the subset Lua 5.4 and Luau share).

local M = {}

-- /proc/stat → the busy fraction since `prev` (nil the first time) and the new sample.
function M.cpu(text, prev)
    local fields = {}
    local line = string.match(text or "", "cpu%s+([%d%s]+)")
    if not line then return nil, prev end
    for n in string.gmatch(line, "%d+") do fields[#fields + 1] = tonumber(n) end
    local idle = (fields[4] or 0) + (fields[5] or 0)           -- idle + iowait
    local total = 0
    for i = 1, math.min(#fields, 8) do total = total + fields[i] end   -- not guest time, counted twice
    local now = { idle = idle, total = total }
    if not prev or total <= prev.total then return nil, now end
    local busy = 1 - (idle - prev.idle) / (total - prev.total)
    return math.max(0, math.min(1, busy)), now
end


-- Per-core counters from /proc/stat. The caller compares two samples to derive usage.
function M.cpu_cores(text)
    local out = {}
    for line in string.gmatch(text or "", "[^\n]+") do
        local name, rest = string.match(line, "^(cpu%d+)%s+(.+)$")
        if name then
            local fields = {}
            for n in string.gmatch(rest, "%d+") do fields[#fields + 1] = tonumber(n) end
            if #fields >= 4 then
                local total, idle = 0, (fields[4] or 0) + (fields[5] or 0)
                for i = 1, math.min(#fields, 8) do total = total + fields[i] end
                out[name] = { total = total, idle = idle }
            end
        end
    end
    return out
end

-- DRM sysfs GPU busy percentage, where supported by the active driver.
function M.gpu_busy(text)
    local n = tonumber(string.match(text or "", "^%s*(%d+)%s*$"))
    if not n or n < 0 or n > 100 then return nil end
    return n / 100
end

-- Format a decoded hyprctl monitors -j response; prefer the focused output.
function M.display_summary(monitors)
    if type(monitors) ~= 'table' then return nil end
    local selected, count = nil, 0
    for _, monitor in ipairs(monitors) do
        if type(monitor) == 'table' then
            count = count + 1
            if monitor.focused == true then selected = monitor end
        end
    end
    if not selected then for _, monitor in ipairs(monitors) do if type(monitor) == 'table' then selected = monitor; break end end end
    if not selected then return nil end
    local name = type(selected.name) == 'string' and selected.name or 'Display'
    local width, height = tonumber(selected.width), tonumber(selected.height)
    local refresh, scale = tonumber(selected.refreshRate), tonumber(selected.scale)
    if not width or not height or width <= 0 or height <= 0 then return nil end
    local hz = refresh and refresh > 0 and string.format(' · %.0f Hz', refresh) or ''
    local scale_text = scale and scale > 0 and string.format(' · %.2fx', scale) or ''
    local suffix = count > 1 and string.format(' · +%d', count - 1) or ''
    return string.format('%s · %dx%d%s%s%s', name, width, height, hz, scale_text, suffix), count
end
-- PCI display-controller names from lspci text. Returns an empty list when unavailable.
function M.gpu_devices(text)
    local out = {}
    for line in string.gmatch(text or "", "[^\n]+") do
        if string.match(line, "VGA compatible controller") or string.match(line, "3D controller") or string.match(line, "Display controller") then
            local name = string.match(line, "controller:%s*(.+)$") or string.match(line, "^%x+:%s*(.+)$") or string.match(line, "^%S+%s+(.+)$") or line
            name = string.gsub(name, "^%s+", "")
            if name ~= "" then out[#out + 1] = name end
        end
    end
    return out
end

-- Parse `lsblk -dn -o NAME,SIZE,TYPE,MODEL`; only physical/virtual whole disks.
function M.storage_devices(text)
    local out = {}
    for line in string.gmatch(text or "", "[^\n]+") do
        local name, size, kind, model = string.match(line, "^%s*(%S+)%s+(%S+)%s+(%S+)%s*(.-)%s*$")
        if name and kind == "disk" then
            out[#out + 1] = { name = name, size = size, model = model ~= "" and model or "Model unavailable" }
        end
    end
    return out
end
-- /proc/meminfo → the used fraction and the used and total GiB.
function M.mem(text)
    local total = tonumber(string.match(text or "", "MemTotal:%s+(%d+)"))
    local avail = tonumber(string.match(text or "", "MemAvailable:%s+(%d+)"))
    if not total or not avail or total == 0 then return nil end
    local used = total - avail
    return used / total, used / 1048576, total / 1048576
end

-- /proc/meminfo in full: what is in use, what is still available, and the swap beside it.
-- `mem` keeps the three numbers the plate's bars need; this is what the node's readings show.
function M.mem_detail(text)
    text = text or ""
    local total = tonumber(string.match(text, "MemTotal:%s+(%d+)"))
    local avail = tonumber(string.match(text, "MemAvailable:%s+(%d+)"))
    if not total or not avail or total == 0 then return nil end
    local swap_total = tonumber(string.match(text, "SwapTotal:%s+(%d+)")) or 0
    local swap_free = tonumber(string.match(text, "SwapFree:%s+(%d+)")) or 0
    return {
        used_gib = (total - avail) / 1048576,
        total_gib = total / 1048576,
        available_gib = avail / 1048576,
        swap_used_gib = math.max(0, swap_total - swap_free) / 1048576,
        swap_total_gib = swap_total / 1048576,
    }
end

-- /proc/loadavg: the three averages, and how many tasks are runnable of how many exist.
function M.loadavg(text)
    local one, five, fifteen = string.match(text or "", "([%d%.]+)%s+([%d%.]+)%s+([%d%.]+)")
    local running, total = string.match(text or "", "(%d+)/(%d+)")
    if not one then return nil end
    return {
        one = tonumber(one), five = tonumber(five), fifteen = tonumber(fifteen),
        running = tonumber(running) or 0, total = tonumber(total) or 0,
    }
end

-- A cpufreq file is in kHz; the node shows it in GHz with two decimals.
function M.clock_ghz(text)
    local khz = tonumber(string.match(text or "", "^%s*(%d+)"))
    if not khz or khz <= 0 then return nil end
    return khz / 1000000
end

-- /proc/net/dev → bytes received and sent, summed over every interface but loopback.
function M.net(text)
    local rx, tx = 0, 0
    for name, rest in string.gmatch(text or "", "\n%s*([%w%.%-_]+):([^\n]*)") do
        if name ~= "lo" then
            local n = {}
            for v in string.gmatch(rest, "%d+") do n[#n + 1] = tonumber(v) end
            rx = rx + (n[1] or 0); tx = tx + (n[9] or 0)
        end
    end
    return rx, tx
end

-- A byte rate, in the bar's glyph language: three significant characters and a unit.
function M.rate(bytes_per_s)
    local b = math.max(0, bytes_per_s or 0)
    if b < 1000 then return string.format("%dB", math.floor(b)) end
    if b < 1e6 then return string.format("%dK", math.floor(b / 1e3)) end
    if b < 1e7 then return string.format("%.1fM", b / 1e6) end
    if b < 1e9 then return string.format("%dM", math.floor(b / 1e6)) end
    return string.format("%.1fG", b / 1e9)
end

-- `sensors -j` (decoded) → the processor's temperature in °C: AMD's Tctl/Tdie, Intel's
-- package, or failing those the hottest reading any chip gives.
function M.temp(sensors)
    if type(sensors) ~= "table" then return nil end
    local best, any = nil, nil
    for chip, readings in pairs(sensors) do
        if type(readings) == "table" then
            for label, values in pairs(readings) do
                if type(values) == "table" then
                    for key, v in pairs(values) do
                        if type(v) == "number" and string.match(key, "^temp%d+_input$") then
                            if (string.match(chip, "^k10temp") and (label == "Tctl" or label == "Tdie"))
                                or (string.match(chip, "^coretemp") and string.match(label, "^Package")) then
                                best = v
                            end
                            if v > 0 and v < 150 and (any == nil or v > any) then any = v end
                        end
                    end
                end
            end
        end
    end
    return best or any
end

-- open-meteo's WMO weather codes, in five kinds the bar has a glyph for, and a short word.
function M.weather(code, is_day)
    local c = tonumber(code) or -1
    if c == 0 or c == 1 then return is_day == 0 and "night" or "clear", (c == 0) and "CLEAR" or "FAIR" end
    if c == 2 or c == 3 then return "cloud", (c == 2) and "PARTLY" or "CLOUDY" end
    if c == 45 or c == 48 then return "fog", "FOG" end
    if (c >= 51 and c <= 67) or (c >= 80 and c <= 82) then return "rain", (c >= 80) and "SHOWER" or "RAIN" end
    if (c >= 71 and c <= 77) or c == 85 or c == 86 then return "snow", "SNOW" end
    if c >= 95 then return "storm", "STORM" end
    return "cloud", "—"
end

M.WEATHER_KINDS = { "clear", "night", "cloud", "fog", "rain", "snow", "storm" }

return M
