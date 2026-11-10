-- The node's state (D226, spec docs/superpowers/specs/2026-11-09-dynamic-pill-node-design.md §3). Pure.
-- What the node is now: what was opened on purpose (held: the launcher, the universe, the system cluster) wins;
-- else the strongest event still alive (a notice over a volume change over a workspace change); else the music
-- while the pointer is near; else the seed. A fresh event is first a reaction — the seed stretching toward it.

local M = {}

M.PRIORITY = { universe = 100, done = 95, launcher = 90, time = 85, system = 80, notice = 70, volume = 60, workspaces = 50, media = 40, rest = 0 }
M.LIFE = { notice = 6000, volume = 1800, workspaces = 1500, media = 4000 }
M.REACT_MS = 140

function M.new() return { events = {}, held = {} } end

function M.push(st, kind, now, data)
    st.events[kind] = { at = now, till = now + (M.LIFE[kind] or 2000), data = data }
end
function M.hold(st, kind) st.held[kind] = true end
function M.release(st, kind) st.held[kind] = nil end
function M.held(st, kind) return st.held[kind] == true end

-- the kind to show, whether it is still a reaction, and its data
function M.current(st, now, ctx)
    ctx = ctx or {}
    local best, bp
    for k in pairs(st.held) do
        local p = M.PRIORITY[k] or 0
        if not best or p > bp then best, bp = k, p end
    end
    if best then return best, false, nil end
    local ev
    for k, e in pairs(st.events) do
        if now < e.till then
            local p = M.PRIORITY[k] or 0
            if not best or p > bp then best, bp, ev = k, p, e end
        else
            st.events[k] = nil
        end
    end
    if best then return best, now - ev.at < M.REACT_MS, ev.data end
    if ctx.playing and ctx.near then return "media", false, nil end
    return "rest", false, nil
end

-- when the next event ends (for one timer, not a poll); nil when none is live
function M.next_change(st, now)
    local t
    for _, e in pairs(st.events) do if e.till > now and (not t or e.till < t) then t = e.till end end
    return t
end

return M
