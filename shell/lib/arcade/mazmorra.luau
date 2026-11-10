-- Mazmorra (D284; k4's idle dungeon, written fresh for mooi). Pure: a hero climbs a dungeon a floor at a time,
-- fights resolve by themselves, gold buys four upgrades, and time away is fought through when the arcade comes
-- back (at most eight hours). Seeded, so a run is the same for the same seed and the tests can say what happens.

local M = { OFFLINE_CAP = 8 * 3600, BOOST = 30, REST = 120 }

local MONSTERS = {
    { name = "Slime", glyph = "󰯈" },
    { name = "Bat", glyph = "󱍢" },
    { name = "Rat", glyph = "󰚌" },
    { name = "Wisp", glyph = "󰞇" },
    { name = "Golem", glyph = "󰣇" },
}

local UPGRADES = {
    { id = "atk", name = "Attack", glyph = "󰓥" },
    { id = "hp", name = "Health", glyph = "󰋑" },
    { id = "spd", name = "Speed", glyph = "󰓅" },
    { id = "luck", name = "Luck", glyph = "󰆘" },
}

local function rand(st, n)
    st.seed = (st.seed * 1103515245 + 12345) % 2147483648
    return (st.seed // 65536) % n
end

local function say(st, line)
    table.insert(st.log, 1, line)
    while #st.log > 5 do table.remove(st.log) end
end

function M.cost(level)
    level = math.max(0, math.floor(tonumber(level) or 0))
    return 12 + level * 10 + level * level * 3
end

function M.hero_max(st)
    return 40 + (st.hp or 0) * 12
end

function M.price(st, which)
    local up = UPGRADES[(math.floor(tonumber(which) or -1)) + 1]
    if not up then return nil end
    return M.cost(st[up.id] or 0)
end

function M.monster_for(st, floor)
    local base = MONSTERS[((floor - 1) % #MONSTERS) + 1]
    local boss = floor % 10 == 0
    local hp = math.floor((8 + floor * 4) * (boss and 2.4 or 1))
    return {
        name = boss and ("Elder " .. base.name) or base.name,
        glyph = base.glyph,
        hp = hp,
        max_hp = hp,
        dmg = 1 + floor // 4 + (boss and 3 or 0),
        boss = boss,
        floor = floor,
    }
end

function M.spawn(st)
    st.monster = M.monster_for(st, st.floor)
    st.hero_t = 0
    st.mon_t = 0
end

function M.new(seed)
    local st = {
        seed = math.floor(tonumber(seed) or 1) % 2147483648,
        floor = 1, best = 1, last_boss = 1, gold = 0,
        atk = 0, hp = 0, spd = 0, luck = 0,
        hero_hp = 40, monster = nil, hero_t = 0, mon_t = 0,
        boost = 0, rest = 0, carry = 0, last = 0, kills = 0, deaths = 0, log = {},
    }
    st.hero_hp = M.hero_max(st)
    M.spawn(st)
    say(st, "Floor 1: something stirs in the dark.")
    return st
end

-- a floor falls: gold, a line in the log, the next floor's monster
local function kill(st)
    local m, floor = st.monster, st.floor
    local drop = 4 + floor + rand(st, 3 + (st.luck or 0) * 2) + (m.boss and 8 or 0)
    st.gold = st.gold + drop
    st.kills = st.kills + 1
    if m.boss then st.last_boss = floor end
    say(st, string.format("Floor %d: a %s falls, +%d gold", floor, m.name, drop))
    st.floor = floor + 1
    st.best = math.max(st.best, st.floor)
    M.spawn(st)
end

local function die(st)
    local back = math.max(1, st.last_boss or 1)
    say(st, string.format("Floor %d: the hero falls, back to %d", st.floor, back))
    st.deaths = st.deaths + 1
    st.floor = back
    st.hero_hp = M.hero_max(st)
    M.spawn(st)
end

local function second(st)
    local boosted = (st.boost or 0) > 0
    local rate = (1 + (st.spd or 0) * 0.22) * (boosted and 2 or 1)
    st.hero_t = st.hero_t + rate
    while st.hero_t >= 1 and st.monster do
        st.hero_t = st.hero_t - 1
        st.monster.hp = st.monster.hp - (3 + (st.atk or 0) * 2)
        if st.monster.hp <= 0 then kill(st) end
    end
    if st.monster then
        st.mon_t = st.mon_t + 1
        while st.mon_t >= 1 and st.monster do
            st.mon_t = st.mon_t - 1
            st.hero_hp = st.hero_hp - st.monster.dmg
            if st.hero_hp <= 0 then die(st) end
        end
    end
    if st.boost > 0 then
        st.boost = st.boost - 1
        if st.boost <= 0 then st.boost = 0; st.rest = M.REST end
    elseif st.rest > 0 then
        st.rest = math.max(0, st.rest - 1)
    end
end

-- `seconds` of fight, one second at a time; the clock is the arcade's, or the time away on return
function M.tick(st, seconds)
    seconds = math.max(0, tonumber(seconds) or 0)
    if seconds <= 0 then return 0 end
    st.carry = (st.carry or 0) + seconds
    local n = math.floor(st.carry)
    st.carry = st.carry - n
    n = math.min(n, M.OFFLINE_CAP)
    for _ = 1, n do second(st) end
    return n
end

-- time away, capped at eight hours; the last time is moved to now whether there was time or not
function M.offline(st, now)
    now = math.floor(tonumber(now) or os.time())
    local last = tonumber(st.last) or 0
    if last <= 0 then st.last = now; return 0 end
    local away = math.max(0, now - last)
    if away > M.OFFLINE_CAP then away = M.OFFLINE_CAP end
    if away > 0 then M.tick(st, away) end
    st.last = now
    return away
end

-- Space: double speed for thirty seconds, then two minutes before it can be asked for again
function M.boost(st)
    if (st.boost or 0) > 0 or (st.rest or 0) > 0 then return false end
    st.boost = M.BOOST
    say(st, "Boost: the hero moves twice as fast for 30 s.")
    return true
end

-- buy an upgrade by its place in the four (0 attack, 1 health, 2 speed, 3 luck)
function M.buy(st, which)
    local i = math.floor(tonumber(which) or -1)
    local up = UPGRADES[i + 1]
    if not up then return false end
    local price = M.cost(st[up.id] or 0)
    if st.gold < price then return false, price end
    st.gold = st.gold - price
    st[up.id] = (st[up.id] or 0) + 1
    if up.id == "hp" then
        st.hero_hp = math.min(M.hero_max(st), st.hero_hp + 12)
    end
    say(st, string.format("%s is now %d (%d gold).", up.name, st[up.id], price))
    return true, price
end

-- what a saved run needs back; a table from arcade.json, or nil when there is nothing usable
function M.restore(t)
    if type(t) ~= "table" or type(t.floor) ~= "number" then return nil end
    local st = M.new(tonumber(t.seed) or 1)
    for k, v in pairs(t) do
        if st[k] ~= nil and type(st[k]) == type(v) then st[k] = v end
    end
    st.hero_max = M.hero_max(st)
    st.hero_hp = math.max(1, math.min(tonumber(st.hero_hp) or st.hero_max, st.hero_max))
    if type(st.monster) ~= "table" or type(st.monster.hp) ~= "number" then M.spawn(st) end
    st.carry = 0
    return st
end

M.MONSTERS = MONSTERS
M.UPGRADES = UPGRADES

return M
