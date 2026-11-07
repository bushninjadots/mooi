-- BMO's face in the Pill (D169). Pure: the bar's logic owns the clock and the dice and asks this what
-- he looks like and says. Everything about him comes from bmo/brain — his faces, his moods and how they
-- drift, what a poke does and his lines — so the Pill's BMO is the desktop BMO's face, not a copy.

local brain = require("bmo/brain")

local M = {
    SAY_MS = 4000,           -- a line stays this long
    POKE_WINDOW = 3000,      -- pokes counted together (brain.poke's "last three seconds")
    DRIFT_MS = 180000,       -- a mood drifts after about three minutes
    CHAT_MS = 45000,         -- an idle moment comes this often, and may come with a line
    -- D170: left alone (the Pill not pointed at or pressed) he gets sleepy, then falls asleep
    SLEEPY_MS = 600000,
    ASLEEP_MS = 1200000,
}

-- `now` is when the Pill started: he is left alone from the first moment, not only after a first touch
-- (D202: never touched, he used to stay awake for ever and the sleepy faces were unreachable).
function M.new(mood, now)
    return { mood = brain.is_mood(mood) and mood or "happy", face = nil, face_until = 0, say = "", say_until = 0,
             pokes = {}, recent = {}, mood_at = 0, chat_at = 0, touched = tonumber(now) or 0, asleep = false }
end

local function show(st, face, ms, now)
    if face and brain.FACES[face] then st.face, st.face_until = face, now + (ms or 1200) end
end

local function speak(st, line, now, talk)
    if talk == "off" then return end          -- BMO → Talk off: his faces, not his lines (D169 M3)
    if line and line ~= "" then
        st.say, st.say_until = line, now + M.SAY_MS
        brain.remember(st.recent, line)
    end
end

-- A press. Returns brain.poke's answer ({ face, ms, mood?, say? }).
function M.poke(st, now, r, talk)
    local kept = {}
    for _, t in ipairs(st.pokes) do if now - t < M.POKE_WINDOW then kept[#kept + 1] = t end end
    kept[#kept + 1] = now
    st.pokes = kept
    local p = brain.poke(st.mood, #kept, r or 0.5)
    show(st, p.face, p.ms, now)
    if p.mood and brain.is_mood(p.mood) then st.mood, st.mood_at = p.mood, now end
    speak(st, p.say or (#kept == 1 and brain.chatter("poke", "chatty", false, st.recent, r or 0.5)) or nil, now, talk)
    return p
end

-- D170: something happened: a brain.FACES face for `ms` (the board opening, a pad pointed at, a signal)
function M.react(st, face, now, ms) show(st, face, ms or 1200, now) end

-- D170: a line of his own choosing (a pad's name), unless Talk is off
function M.say(st, line, now, talk) speak(st, line, now, talk) end

-- D170: the Pill pointed at or pressed. True when it woke him (the caller shows surprise and an "oh! hi").
function M.touch(st, now)
    local was = st.asleep == true or (st.touched ~= nil and now - st.touched >= M.SLEEPY_MS)
    st.touched = now
    if was then st.asleep = false; st.mood, st.mood_at = "happy", now end
    return was
end

-- Time passing. env = { hour (0–23), talk (off · rare · chatty) }; r1, r2 in [0, 1).
function M.tick(st, now, env, r1, r2)
    local night = env.hour ~= nil and (env.hour >= 23 or env.hour < 6)
    local quiet = st.touched and (now - st.touched) or 0
    st.asleep = quiet >= M.ASLEEP_MS
    if quiet >= M.SLEEPY_MS then
        st.mood = "sleepy"
    elseif night then
        st.mood = "sleepy"
    elseif now - st.mood_at >= M.DRIFT_MS or st.mood_at == 0 then
        st.mood = brain.drift({ energy = 1 }, r1 or 0.5)
        st.mood_at = now
    end
    if now - st.chat_at >= M.CHAT_MS or st.chat_at == 0 then
        st.chat_at = now
        local chance = brain.idle_chance(env.talk)
        if (r2 or 1) < chance then
            -- his short idle lines only: a joke would stretch the Pill across the bar
            speak(st, brain.chatter("idle", env.talk, false, st.recent, r1 or 0), now, env.talk)
        end
    end
end

-- What he looks like now: { face = a brain.FACES name, say = his line or "" }.
function M.view(st, now, music)
    local reacting = st.face and now < st.face_until
    local face = reacting and st.face or (music and "singing" or st.mood)     -- D170: music: he sings along
    if face == "sleepy" and (st.asleep or now - st.mood_at > 600000) then face = "asleep" end
    return { face = brain.FACES[face] and face or "happy", say = now < st.say_until and st.say or "" }
end

-- The numbers the scene draws a face from (one row of brain.FACES).
function M.numbers(face)
    return brain.FACES[face] or brain.FACES.happy
end

return M
