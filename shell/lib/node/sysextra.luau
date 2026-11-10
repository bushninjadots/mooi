-- The System page's two more cards (D270; Minflair's GPU and storage readings, ported). Pure: what the kernel,
-- nvidia-smi and df print in, a reading out. The logic asks only while the page is open.

local M = {}

-- where a GPU says how busy it is (AMD and Intel's newer drivers, through the kernel): card0 … card3, tried once
M.BUSY = {}
for i = 0, 3 do M.BUSY[#M.BUSY + 1] = "/sys/class/drm/card" .. i .. "/device/gpu_busy_percent" end
-- the NVIDIA tool's question, for a machine whose card does not say through the kernel
M.NVIDIA = { "--query-gpu=utilization.gpu", "--format=csv,noheader,nounits" }

local function pct(v)
    v = tonumber(v)
    if not v or v ~= v or v < 0 then return nil end
    return math.min(100, v)
end

-- `gpu_busy_percent` is one number; nvidia-smi prints one per card, the first is the one shown
function M.busy(text) return pct(tostring(text or ""):match("^%s*(%d+%.?%d*)")) end

-- `df -P PATH`: the last line's capacity column, and the size and use in bytes (1024-blocks)
function M.disk(text)
    local last
    for line in tostring(text or ""):gmatch("[^\n]+") do last = line end
    if not last then return nil end
    local size, used, _, cap = last:match("^%S+%s+(%d+)%s+(%d+)%s+(%d+)%s+(%d+)%%")
    if not cap then return nil end
    return { pct = pct(cap), size = tonumber(size) * 1024, used = tonumber(used) * 1024 }
end

return M
