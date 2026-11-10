-- Senda (D291; k4's autobattler, written fresh for mooi). Pure: a road of eight stages, a team of up to four
-- creatures, and automatic battles in rounds. Its own seeded random numbers, so the same seed walks the same road
-- and the tests can say what happens. Elements are a five-step wheel; every creature carries one passive.

local M = { STAGES = 8, TEAM_MAX = 4, LOG_MAX = 5 }

M.ELEMENTS = { "fire", "water", "leaf", "stone", "spark" }
M.GLYPHS = {
    fire = "󰈸",
    water = "󰖌",
    leaf = "󰌪",
    stone = "󰟾",
    spark = "󱐋",
}
M.ELEMENT_NAMES = {
    fire = "Fire", water = "Water", leaf = "Leaf", stone = "Stone", spark = "Spark",
}
M.BEATS = { fire = "leaf", leaf = "stone", stone = "spark", spark = "water", water = "fire" }
M.PASSIVES = {
    mend = "Mends the team each round",
    first = "Strikes first",
    thorns = "Hurts whoever hits it",
}

local CREATURES = {
    -- fire
    { name = "Emberling", element = "fire", hp = 31, atk = 5, spd = 5, passive = "mend" },
    { name = "Cindercub", element = "fire", hp = 33, atk = 6, spd = 4, passive = "first" },
    { name = "Pyra", element = "fire", hp = 30, atk = 6, spd = 6, passive = "thorns" },
    { name = "Flintail", element = "fire", hp = 32, atk = 5, spd = 5, passive = "first" },
    { name = "Ashfin", element = "fire", hp = 34, atk = 5, spd = 4, passive = "mend" },
    { name = "Scorch", element = "fire", hp = 31, atk = 6, spd = 5, passive = "thorns" },
    -- water
    { name = "Mirel", element = "water", hp = 37, atk = 3, spd = 4, passive = "mend" },
    { name = "Brooklet", element = "water", hp = 35, atk = 4, spd = 6, passive = "first" },
    { name = "Tidelet", element = "water", hp = 38, atk = 3, spd = 3, passive = "thorns" },
    { name = "Rill", element = "water", hp = 36, atk = 4, spd = 5, passive = "mend" },
    { name = "Waveling", element = "water", hp = 34, atk = 4, spd = 6, passive = "first" },
    { name = "Brin", element = "water", hp = 39, atk = 3, spd = 4, passive = "thorns" },
    -- leaf
    { name = "Mosskit", element = "leaf", hp = 36, atk = 4, spd = 4, passive = "mend" },
    { name = "Thornlet", element = "leaf", hp = 33, atk = 5, spd = 5, passive = "thorns" },
    { name = "Fern", element = "leaf", hp = 34, atk = 4, spd = 7, passive = "first" },
    { name = "Bramble", element = "leaf", hp = 37, atk = 5, spd = 4, passive = "thorns" },
    { name = "Sprig", element = "leaf", hp = 32, atk = 4, spd = 6, passive = "mend" },
    { name = "Leafling", element = "leaf", hp = 35, atk = 5, spd = 6, passive = "first" },
    -- stone
    { name = "Pebble", element = "stone", hp = 38, atk = 4, spd = 4, passive = "thorns" },
    { name = "Crag", element = "stone", hp = 46, atk = 6, spd = 2, passive = "first" },
    { name = "Basalt", element = "stone", hp = 44, atk = 5, spd = 2, passive = "mend" },
    { name = "Dunem", element = "stone", hp = 42, atk = 5, spd = 3, passive = "thorns" },
    { name = "Shard", element = "stone", hp = 40, atk = 6, spd = 4, passive = "first" },
    { name = "Boulder", element = "stone", hp = 48, atk = 4, spd = 1, passive = "mend" },
    -- spark
    { name = "Sparkit", element = "spark", hp = 27, atk = 6, spd = 8, passive = "first" },
    { name = "Volt", element = "spark", hp = 29, atk = 5, spd = 7, passive = "mend" },
    { name = "Zapp", element = "spark", hp = 26, atk = 7, spd = 9, passive = "thorns" },
    { name = "Flicker", element = "spark", hp = 28, atk = 6, spd = 8, passive = "first" },
    { name = "Static", element = "spark", hp = 31, atk = 5, spd = 6, passive = "mend" },
    { name = "Glint", element = "spark", hp = 30, atk = 6, spd = 7, passive = "thorns" },
}

local function next(r, n)
    r = (r * 1103515245 + 12345) % 2147483648
    return r, (r // 65536) % n
end

local function say(st, line)
    table.insert(st.log, 1, line)
    while #st.log > M.LOG_MAX do table.remove(st.log) end
end

local function alive(c)
    return c and c.hp > 0
end

local function first_living(list)
    for _, c in ipairs(list) do
        if alive(c) then return c end
    end
end

local function clone(base, level, boss)
    level = math.max(1, math.floor(tonumber(level) or 1))
    local max_hp = base.hp + (level - 1) * 6
    if boss then max_hp = math.floor(max_hp * 1.5 + 0.5) end
    return {
        name = boss and ("Medal " .. base.name) or base.name,
        base = base.name,
        element = base.element,
        glyph = M.GLYPHS[base.element],
        max_hp = max_hp,
        hp = max_hp,
        atk = base.atk + (level - 1) + (boss and 2 or 0),
        spd = base.spd,
        passive = base.passive,
        level = level,
        boss = boss or false,
    }
end

local function build_order(st)
    local order = {}
    for i, c in ipairs(st.team) do
        if alive(c) then order[#order + 1] = { side = "team", i = i, spd = c.spd } end
    end
    for i, c in ipairs(st.foes) do
        if alive(c) then order[#order + 1] = { side = "foe", i = i, spd = c.spd } end
    end
    table.sort(order, function(a, b)
        if a.spd == b.spd then
            if a.side == b.side then return a.i < b.i end
            return a.side == "team"
        end
        return a.spd > b.spd
    end)
    return order
end

local function build_openers(st)
    local out = {}
    for i, c in ipairs(st.team) do
        if alive(c) and c.passive == "first" then out[#out + 1] = { side = "team", i = i, spd = c.spd } end
    end
    for i, c in ipairs(st.foes) do
        if alive(c) and c.passive == "first" then out[#out + 1] = { side = "foe", i = i, spd = c.spd } end
    end
    table.sort(out, function(a, b)
        if a.spd == b.spd then
            if a.side == b.side then return a.i < b.i end
            return a.side == "team"
        end
        return a.spd > b.spd
    end)
    return out
end

local function ref_creature(st, ref)
    if not ref then return nil end
    if ref.side == "team" then return st.team[ref.i] end
    return st.foes[ref.i]
end

local function attack(st, actor, targets, side, events)
    local target = first_living(targets)
    if not target then return end
    local mult, label = M.advantage(actor.element, target.element)
    local dmg = math.max(1, math.floor(actor.atk * mult + 0.5))
    target.hp = math.max(0, target.hp - dmg)
    local tag = label == "strong" and " (strong)" or label == "weak" and " (weak)" or ""
    say(st, string.format("%s hits %s for %d%s.", actor.name, target.name, dmg, tag))
    events[#events + 1] = { kind = "hit", side = side, target = target.name, dmg = dmg, mult = mult }
    if target.hp <= 0 then
        say(st, target.name .. " falls.")
        events[#events + 1] = { kind = "fall", side = side, name = target.name }
    end
    if target.passive == "thorns" then
        local back = math.max(1, dmg // 3)
        actor.hp = math.max(0, actor.hp - back)
        say(st, string.format("%s's thorns bite %s for %d.", target.name, actor.name, back))
        events[#events + 1] = { kind = "thorn", side = side, name = actor.name, dmg = back }
        if actor.hp <= 0 then
            say(st, actor.name .. " falls.")
            events[#events + 1] = { kind = "fall", side = side, name = actor.name }
        end
    end
end

local function mend_side(st, list, side, events)
    for _, c in ipairs(list) do
        if alive(c) and c.passive == "mend" then
            local healed = false
            for _, ally in ipairs(list) do
                if alive(ally) and ally.hp < ally.max_hp then
                    ally.hp = math.min(ally.max_hp, ally.hp + 2 + (c.level or 1))
                    healed = true
                end
            end
            if healed then
                say(st, c.name .. " mends the " .. (side == "team" and "team" or "foes") .. ".")
                events[#events + 1] = { kind = "mend", side = side, by = c.name }
            end
        end
    end
end

local function check_end(st, events)
    if not first_living(st.foes) then
        st.cleared = math.max(st.cleared, st.stage)
        st.best = math.max(st.best, st.cleared)
        events[#events + 1] = { kind = "win" }
        if st.stage >= M.STAGES then
            st.state = "won"
            say(st, "The road is walked.")
        else
            -- camp (D291 review): every creature gets back a third of what it lost, the fallen too, before the road's
            -- choice; a rest is still the way to come back whole
            for _, c in ipairs(st.team) do c.hp = math.min(c.max_hp, c.hp + (c.max_hp - c.hp) // 3) end
            st.state = "choose"
            st.offers = M.offers(st)
            st.pick = 0
            say(st, "Stage " .. st.stage .. " cleared. Make camp.")
        end
        return true
    end
    if not first_living(st.team) then
        st.state = "over"
        say(st, "The road ends at stage " .. st.stage .. ".")
        events[#events + 1] = { kind = "lose" }
        return true
    end
    return false
end

local function start_stage(st)
    -- (D291 review) one foe to start, two up to the first medal, three after; a level every four stages
    local count
    if st.stage == 1 then count = 1
    elseif st.stage <= 4 then count = 2
    else count = 3 end
    local level = 1 + (st.stage - 1) // 4
    local r = (st.seed + st.stage * 104729) % 2147483648
    st.foes = {}
    for i = 1, count do
        local at
        r, at = next(r, #CREATURES)
        local boss = st.stage % 4 == 0 and i == 1
        st.foes[i] = clone(CREATURES[at + 1], level, boss)
    end
    st.state = "battle"
    st.round = 1
    st.offers = nil
    st.pick = 0
    st.opening = build_openers(st)
    st.order = build_order(st)
    st.turn = 1
    say(st, "Stage " .. st.stage .. ". " .. (st.stage % 4 == 0 and "A medal stands on the road." or "The road sends its own."))
end

function M.advantage(a, b)
    if not a or not b then return 1, "even" end
    if M.BEATS[a] == b then return 1.5, "strong" end
    if M.BEATS[b] == a then return 0.67, "weak" end
    return 1, "even"
end

function M.new(seed)
    local st = {
        seed = math.floor(tonumber(seed) or 1) % 2147483648,
        stage = 1, cleared = 0, best = 0, team = {}, foes = {},
        state = "battle", round = 1, log = {}, offers = nil, pick = 0,
        opening = {}, order = {}, turn = 1,
    }
    local r = st.seed
    local a, b
    r, a = next(r, #CREATURES)
    repeat r, b = next(r, #CREATURES) until b ~= a
    st.team[1] = clone(CREATURES[a + 1], 1)
    st.team[2] = clone(CREATURES[b + 1], 1)
    say(st, "The road begins.")
    start_stage(st)
    return st
end

function M.offers(st)
    if type(st) ~= "table" or type(st.team) ~= "table" then return {} end
    local r = (st.seed + (st.stage or 1) * 7919) % 2147483648
    local names = {}
    for _, c in ipairs(st.team) do names[c.base] = true end
    local pool = {}
    for i, base in ipairs(CREATURES) do
        if not names[base.name] then pool[#pool + 1] = i end
    end
    local out = {}
    for _ = 1, 2 do
        if #pool > 0 then
            local at
            r, at = next(r, #pool)
            local base = CREATURES[table.remove(pool, at + 1)]
            out[#out + 1] = {
                kind = "recruit", title = base.name,
                line = M.ELEMENT_NAMES[base.element] .. " · " .. M.PASSIVES[base.passive],
                glyph = M.GLYPHS[base.element], base = base.name,
                full = #st.team >= M.TEAM_MAX,
            }
        end
    end
    local hurt, target = false, nil
    for _, c in ipairs(st.team) do
        if c.hp < c.max_hp then hurt = true end
        if not target or c.level < target.level then target = c end
    end
    if hurt then
        out[#out + 1] = { kind = "rest", title = "Rest", line = "Heal the whole team to full.", glyph = "󰋑", full = false }
    else
        out[#out + 1] = {
            kind = "train", title = "Train",
            line = "Raise " .. target.name .. " to level " .. (target.level + 1) .. ".",
            glyph = "󰓥", full = false,
        }
    end
    return out
end

function M.choose(st, i)
    if type(st) ~= "table" or st.state ~= "choose" or type(st.offers) ~= "table" then return false end
    i = math.floor(tonumber(i) or -1)
    local o = st.offers[i + 1]
    if not o then return false end
    if o.kind == "recruit" then
        if #st.team >= M.TEAM_MAX then return false end
        local base = nil
        for _, c in ipairs(CREATURES) do
            if c.name == o.base then base = c; break end
        end
        if not base then return false end
        st.team[#st.team + 1] = clone(base, 1 + (st.stage - 1) // 3)
        say(st, base.name .. " joins the road.")
    elseif o.kind == "train" then
        local target = nil
        for _, c in ipairs(st.team) do
            if not target or c.level < target.level then target = c end
        end
        if target then
            target.level = target.level + 1
            target.max_hp = target.max_hp + 6
            target.hp = target.hp + 6
            target.atk = target.atk + 1
            say(st, target.name .. " reaches level " .. target.level .. ".")
        end
    elseif o.kind == "rest" then
        for _, c in ipairs(st.team) do c.hp = c.max_hp end
        say(st, "The team rests by the fire.")
    else
        return false
    end
    st.offers = nil
    st.pick = 0
    st.stage = st.stage + 1
    if st.stage > M.STAGES then
        st.state = "won"
        say(st, "The road is walked.")
        return true
    end
    start_stage(st)
    return true
end

-- one action: an opening strike, a round action, or the end of a round (mends, then a new order)
function M.battle_step(st)
    local events = {}
    if type(st) ~= "table" or st.state ~= "battle" then return events end
    if check_end(st, events) then return events end
    if st.opening and #st.opening > 0 then
        local ref = table.remove(st.opening, 1)
        local c = ref_creature(st, ref)
        if c and c.hp > 0 then
            if ref.side == "team" then attack(st, c, st.foes, "team", events)
            else attack(st, c, st.team, "foe", events) end
        end
        if check_end(st, events) then return events end
        return events
    end
    if not st.order or st.turn > #st.order then
        mend_side(st, st.team, "team", events)
        mend_side(st, st.foes, "foe", events)
        if check_end(st, events) then return events end
        st.round = st.round + 1
        st.order = build_order(st)
        st.turn = 1
        events[#events + 1] = { kind = "round", round = st.round }
        return events
    end
    local ref = st.order[st.turn]
    local c = ref_creature(st, ref)
    st.turn = st.turn + 1
    if c and c.hp > 0 then
        if ref.side == "team" then attack(st, c, st.foes, "team", events)
        else attack(st, c, st.team, "foe", events) end
    end
    if check_end(st, events) then return events end
    return events
end

M.CREATURES = CREATURES

return M
