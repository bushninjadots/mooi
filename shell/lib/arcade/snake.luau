-- Snake (D276; k4's example game, ported to mooi's arcade). Pure: a board, a snake, food and a step; the logic
-- ticks it and draws it. Its own small random numbers, so a game is the same for the same seed (and the tests can
-- say what happens).

local M = { W = 28, H = 18, START = 4 }

local DIRS = { up = { 0, -1 }, down = { 0, 1 }, left = { -1, 0 }, right = { 1, 0 } }
local OPPOSITE = { up = "down", down = "up", left = "right", right = "left" }

local function rand(st)
    -- a linear congruential step held below 2^31: the same in Lua 5.4 and Luau
    st.seed = (st.seed * 1103515245 + 12345) % 2147483648
    return st.seed
end

local function occupied(st, x, y)
    for _, c in ipairs(st.body) do if c.x == x and c.y == y then return true end end
    return false
end

function M.place_food(st)
    local free = st.w * st.h - #st.body
    if free <= 0 then st.food = nil; return end
    local n = rand(st) % free
    for y = 0, st.h - 1 do
        for x = 0, st.w - 1 do
            if not occupied(st, x, y) then
                if n == 0 then st.food = { x = x, y = y }; return end
                n = n - 1
            end
        end
    end
end

function M.new(seed, w, h)
    local st = { w = w or M.W, h = h or M.H, seed = math.floor(tonumber(seed) or 1) % 2147483648, dir = "right", next_dir = "right",
                 body = {}, score = 0, alive = true, grow = 0 }
    local cy = st.h // 2
    for i = 0, M.START - 1 do st.body[#st.body + 1] = { x = st.w // 2 - i, y = cy } end
    M.place_food(st)
    return st
end

-- a turn asked for: never straight back into itself; kept for the next step, so two quick keys between steps
-- cannot fold it over
function M.turn(st, dir)
    if not DIRS[dir] then return end
    if dir == OPPOSITE[st.dir] then return end
    st.next_dir = dir
end

-- one step: "moved", "ate", "dead" (a wall or itself) or "won" (the board is full)
function M.step(st)
    if not st.alive then return "dead" end
    st.dir = st.next_dir
    local d = DIRS[st.dir]
    local head = st.body[1]
    local nx, ny = head.x + d[1], head.y + d[2]
    if nx < 0 or ny < 0 or nx >= st.w or ny >= st.h then st.alive = false; return "dead" end
    -- moving into the cell the tail is leaving is allowed, unless the snake is growing (then the tail stays)
    for i, c in ipairs(st.body) do
        if c.x == nx and c.y == ny and not (i == #st.body and st.grow == 0) then
            st.alive = false
            return "dead"
        end
    end
    table.insert(st.body, 1, { x = nx, y = ny })
    local ate = st.food and st.food.x == nx and st.food.y == ny
    if ate then st.score = st.score + 1; st.grow = st.grow + 2 end
    if st.grow > 0 then st.grow = st.grow - 1 else table.remove(st.body) end
    if ate then
        M.place_food(st)
        if not st.food then return "won" end
        return "ate"
    end
    return "moved"
end

-- how fast it runs: quicker as it grows, never quicker than 60 ms a step
function M.interval(st) return math.max(60, 140 - st.score * 3) end

return M
