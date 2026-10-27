-- The stats island's readings (D97): the load, memory and swap (/proc), the root disk (`df -P /`),
-- the busiest processes (`ps -eo comm,%cpu --sort=-%cpu`), the GPU's busy share (amdgpu's
-- gpu_busy_percent). Pure, so tests/unit runs it; what cannot be read reads as nothing.

local M = {}

local GIB = 1024 * 1024    -- kB in a GiB

function M.loadavg(out)
    local a, b, c = tostring(out or ""):match("^%s*([%d.]+)%s+([%d.]+)%s+([%d.]+)")
    if not a then return nil end
    return tonumber(a), tonumber(b), tonumber(c)
end

-- { total, used, frac, swap_total, swap_used } in GiB (used = total − available).
function M.meminfo(out)
    local v = {}
    for k, n in tostring(out or ""):gmatch("(%w+):%s+(%d+)") do v[k] = tonumber(n) end
    local total = (v.MemTotal or 0) / GIB
    local used = math.max(0, (v.MemTotal or 0) - (v.MemAvailable or v.MemFree or 0)) / GIB
    local st = (v.SwapTotal or 0) / GIB
    local su = math.max(0, (v.SwapTotal or 0) - (v.SwapFree or 0)) / GIB
    return { total = total, used = used, frac = total > 0 and used / total or 0, swap_total = st, swap_used = su }
end

-- The root file system: { frac, text "used / size GiB" }.
function M.df(out)
    for line in tostring(out or ""):gmatch("[^\n]+") do
        local size, used, pct, mount = line:match("^%S+%s+(%d+)%s+(%d+)%s+%d+%s+(%d+)%%%s+(%S+)")
        if size and mount == "/" then
            return { frac = tonumber(pct) / 100,
                     text = string.format("%d / %d GiB", math.floor(tonumber(used) / GIB + 0.5), math.floor(tonumber(size) / GIB + 0.5)) }
        end
    end
    return { frac = 0, text = "—" }
end

-- The `n` busiest processes as { name, cpu }, without `ps` itself.
function M.top(out, n)
    local list = {}
    for line in tostring(out or ""):gmatch("[^\n]+") do
        local name, cpu = line:match("^%s*(.-)%s+([%d.]+)%s*$")
        if name and name ~= "" and name ~= "ps" then
            list[#list + 1] = { name = name, cpu = tonumber(cpu) or 0 }
            if #list >= n then break end
        end
    end
    return list
end

-- The GPU's busy share 0..1, or nil when the file says nothing.
function M.gpu(out)
    local n = tostring(out or ""):match("^%s*(%d+)%s*$") or tostring(out or ""):match("\n%s*(%d+)%s*\n?$")
    return n and tonumber(n) / 100 or nil
end

return M
