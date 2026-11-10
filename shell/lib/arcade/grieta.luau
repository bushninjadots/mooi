-- La Grieta (D283; k4's typing roguelike, written fresh for mooi). Pure: a crack, words falling from it, a line to
-- hold, three lives, waves and the upgrades chosen between them. Its own seeded random numbers, so a game is the
-- same for the same seed and the tests can say what happens.

local M = { LIVES = 3, LINE = 84, MAX_WORDS = 16 }

-- common English words of three to nine letters. Ours, not k4's: a small pool for the crack to spend.
local WORDS = [[
the and you that was for are with his they this have from one had word but not what all were when your can said
there use each which she how their will other about out many then them these some her would make like him into time
has look two more write see number way could people than first water been call who oil its now find long down day
did get come made may part over new sound take only little work know place year live back give most very after
thing our just name good sentence man think say great where help through much before line right too mean old any
same tell boy follow came want show also around form three small set put end does another well large must big even
such because turn here why ask went men read need land home move try kind hand picture again change off play spell
air away animal house point page letter mother answer found study still learn should world high every near add food
between own below country plant last school father keep tree never start city earth eye light thought head under
story saw left few while along might close something seem next hard open example begin life always those both paper
together got group often run important until children side feet car mile night walk white sea began grow took river
four carry state once book hear stop without second later miss idea enough eat face watch far really almost above
girl sometimes mountain cut young talk soon list song being leave family body music color stand sun question fish
area mark dog horse bird problem complete room knew since ever piece told usually friend easy heard order red door
sure become top ship across today during short better best however low hours black products happened whole measure
remember early waves reached listen wind rock space covered fast several hold himself toward five step passed vowel
true hundred against pattern numeral table north slowly money map farm pulled draw voice seen cold cried plan notice
south sing war ground fall king town unit figure certain field travel wood fire upon
]]

local LIST, SEEN = {}, {}
for w in WORDS:gmatch("%a+") do
    w = string.lower(w)
    local n = #w
    if n >= 3 and n <= 9 and not SEEN[w] then
        SEEN[w] = true
        LIST[#LIST + 1] = w
    end
end

local UPGRADES = {
    { id = "slow", name = "Slow fall", line = "The crack lets go more gently.", glyph = "󰁅" },
    { id = "life", name = "Extra life", line = "One more word may slip past.", glyph = "󰋑" },
    { id = "long", name = "Long words", line = "Seven letters or more are worth double.", glyph = "󰛖" },
    { id = "seal", name = "Seal charge", line = "Tab seals every word on screen.", glyph = "󰆙" },
}

local function rand(st, n)
    -- a linear congruential step held below 2^31: the same in Lua 5.4 and Luau
    st.seed = (st.seed * 1103515245 + 12345) % 2147483648
    return (st.seed // 65536) % n
end

local function starts(text, prefix)
    return #prefix > 0 and text:sub(1, #prefix) == prefix
end

local function on_screen(st, text)
    for _, w in ipairs(st.words) do if w.text == text then return true end end
    return false
end

-- the next wave: more words, closer together, quicker down the board
function M.start_wave(st, wave)
    st.wave = wave
    st.spawn_left = 5 + wave * 3
    st.spawn_every = math.max(430, 1600 - wave * 110)
    st.spawn_in = 520
    st.base_speed = 2.0 + wave * 0.38
end

function M.worth(st, text)
    local n = #text
    local mult = 1
    if n >= 7 and (st.long or 0) > 0 then mult = 1 + st.long end
    return n * st.wave * mult
end

function M.new(seed)
    local st = {
        seed = math.floor(tonumber(seed) or 1) % 2147483648,
        state = "ready", wave = 1, score = 0, lives = M.LIVES, typed = "",
        words = {}, next_id = 1, spawn_left = 0, spawn_in = 0, spawn_every = 1000,
        base_speed = 2, slow = 0, long = 0, charges = 0, pick = 0, options = {},
        flash = 0, sealed = 0,
    }
    M.start_wave(st, 1)
    return st
end

-- one word out of the crack; a word may be handed in (the tests do), which does not spend the wave's count
function M.spawn(st, text)
    local given = text
    if not given then
        if st.spawn_left <= 0 or #st.words >= M.MAX_WORDS then return nil end
        for _ = 1, 6 do
            local t = LIST[1 + rand(st, #LIST)]
            if not on_screen(st, t) then text = t; break end
            text = t
        end
        st.spawn_left = st.spawn_left - 1
    end
    local w = {
        id = st.next_id, text = text, x = 5 + rand(st, 80), y = 0,
        speed = st.base_speed * (0.80 + rand(st, 41) / 100) * (0.86 ^ (st.slow or 0)),
    }
    st.next_id = st.next_id + 1
    st.words[#st.words + 1] = w
    return w
end

local function wave_over(st)
    if st.state == "playing" and st.spawn_left <= 0 and #st.words == 0 then
        st.state = "choose"
        st.options = M.offers(st)
        st.pick = 0
        return true
    end
    return false
end

-- after a word leaves, the letters typed may no longer begin anything: then the line is empty again
local function reconcile(st)
    if st.typed == "" then return end
    for _, w in ipairs(st.words) do if starts(w.text, st.typed) then return end end
    st.typed = ""
end

-- move everything by `ms` milliseconds. Returns the things worth a sound: spawns, a life lost, a wave cleared,
-- the end. Words that reach the line are gone and cost one life.
function M.tick(st, ms)
    local events = {}
    if st.state ~= "playing" then return events end
    ms = math.max(0, tonumber(ms) or 0)
    st.flash = math.max(0, st.flash - ms)
    if st.spawn_left > 0 then
        st.spawn_in = st.spawn_in - ms
        while st.spawn_in <= 0 and st.spawn_left > 0 do
            local w = M.spawn(st)
            if w then events[#events + 1] = { kind = "spawn" } end
            st.spawn_in = st.spawn_in + st.spawn_every
        end
    end
    for i = #st.words, 1, -1 do
        local w = st.words[i]
        w.y = w.y + w.speed * ms / 1000
        if w.y >= M.LINE then
            table.remove(st.words, i)
            st.lives = st.lives - 1
            events[#events + 1] = { kind = "hit", text = w.text }
            reconcile(st)
        end
    end
    if st.lives <= 0 then
        st.lives = 0
        st.state = "over"
        st.typed = ""
        events[#events + 1] = { kind = "over" }
    elseif wave_over(st) then
        events[#events + 1] = { kind = "wave" }
    end
    return events
end

-- one letter: it must begin a word on screen. An exact word is sealed at once. A letter that begins nothing
-- flashes the line and is not kept. Returns "typed", "sealed" (with the word and its worth) or "wrong".
function M.type(st, ch)
    if st.state ~= "playing" then return "idle" end
    ch = string.lower(tostring(ch or "")):sub(1, 1)
    if not ch:match("^[a-z]$") then return "idle" end
    local candidate = st.typed .. ch
    local hit, any = nil, false
    for i, w in ipairs(st.words) do
        if starts(w.text, candidate) then
            any = true
            if w.text == candidate and not hit then hit = i end
        end
    end
    if not any then
        st.flash = 180
        return "wrong"
    end
    st.typed = candidate
    if hit then
        local w = table.remove(st.words, hit)
        local gain = M.worth(st, w.text)
        st.score = st.score + gain
        st.sealed = st.sealed + #w.text
        st.typed = ""
        wave_over(st)
        return "sealed", w.text, gain, w.x, w.y
    end
    return "typed"
end

function M.backspace(st)
    st.typed = st.typed:sub(1, math.max(0, #st.typed - 1))
    return st.typed
end

-- Tab: spend a charge, seal everything on screen, and take its letters
function M.use_seal(st)
    if st.state ~= "playing" or st.charges <= 0 or #st.words == 0 then return 0, 0 end
    local sum = 0
    for _, w in ipairs(st.words) do sum = sum + M.worth(st, w.text) end
    st.charges = st.charges - 1
    st.score = st.score + sum
    st.words = {}
    st.typed = ""
    wave_over(st)
    return sum, st.score
end

-- three of the four, taken in turn from the seed
function M.offers(st)
    local out = {}
    local at = rand(st, #UPGRADES)
    for i = 1, 3 do
        out[i] = UPGRADES[(at + i - 1) % #UPGRADES + 1]
    end
    return out
end

function M.select(st, dir)
    if st.state ~= "choose" or #st.options == 0 then return st.pick end
    st.pick = (st.pick + (dir < 0 and -1 or 1)) % #st.options
    return st.pick
end

-- choose an upgrade (0, 1 or 2) and begin the next wave
function M.choose(st, i)
    if st.state ~= "choose" then return nil end
    i = math.floor(tonumber(i) or st.pick or 0)
    local up = st.options[i + 1]
    if not up then return nil end
    if up.id == "slow" then
        st.slow = st.slow + 1
    elseif up.id == "life" then
        st.lives = math.min(5, st.lives + 1)
    elseif up.id == "long" then
        st.long = st.long + 1
    elseif up.id == "seal" then
        st.charges = st.charges + 1
    end
    st.state = "playing"
    st.options = {}
    st.pick = 0
    M.start_wave(st, st.wave + 1)
    return up.id
end

function M.start(st)
    if st.state == "ready" then st.state = "playing"; return true end
    return false
end

M.WORDS = LIST
M.UPGRADES = UPGRADES

return M
