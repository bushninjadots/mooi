-- BMO's shared pet state (D209). Pure: the bar owns the clock, the dice and the files; this decides
-- what care, neglect and events mean. The desktop body, the bar face, the Pill and the Sigil all read
-- this one state, so there is one BMO rather than three lookalikes.
--
--   charge    his battery, 0–1
--   bond      how attached he is, 0–1
--   mischief  how naughty he feels, 0–1
--   grump     how close he is to a tantrum, 0–1
--   mood      one of brain.MOODS; grump can put an angry face over it

local brain = require("bmo/brain")

local M = {}

M.SAY_MS = 4000
M.POKE_WINDOW = 3
M.DRIFT_MS = 180
M.CHAT_MS = 45
M.SLEEPY_MS = 600
M.ASLEEP_MS = 1200
M.CHARGE_AWAKE = 4 * 3600      -- seconds from full to empty awake
M.CHARGE_ASLEEP = 600          -- seconds from empty to full asleep

local function clamp(v, lo, hi, d)
    v = tonumber(v)
    if not v or v ~= v then return d or lo end
    if v < lo then return lo elseif v > hi then return hi end
    return v
end

local function num(v, d)
    v = tonumber(v)
    if not v or v ~= v then return d end
    return v
end

local function valid_face(f)
    return type(f) == "string" and brain.FACES[f] ~= nil
end

function M.new(now)
    now = num(now, 0)
    return {
        version = 1, rev = 0, at = now,
        charge = 0.6, bond = 0.2, mischief = 0.3, grump = 0.05,        mood = "happy", asleep = false, nap = false, charging = false,
        reaction = { face = nil, until_at = 0 },
        say = { text = "", until_at = 0 },
        last = {}, pokes = {}, recent = {}, last_cmd = nil,
        mood_at = now, touched = now, chat_at = now,    }
end

-- Whatever the file held, this is a usable BMO. A broken document is a fresh one, not an error.
function M.normalise(doc, now)
    now = num(now, 0)
    if type(doc) ~= "table" then return M.new(now) end
    local st = M.new(now)
    st.rev = math.max(0, math.floor(num(doc.rev, 0)))
    st.at = num(doc.at, now)
    st.last_cmd = type(doc.last_cmd) == "string" and doc.last_cmd or nil
    st.charge = clamp(doc.charge, 0, 1, 0.6)
    st.bond = clamp(doc.bond, 0, 1, 0.2)
    st.mischief = clamp(doc.mischief, 0, 1, 0.3)
    st.grump = clamp(doc.grump, 0, 1, 0.05)
    st.mood = brain.is_mood(doc.mood) and doc.mood or "happy"
    st.asleep = doc.asleep == true
    st.nap = doc.nap == true
    st.charging = doc.charging == true
    st.mood_at = num(doc.mood_at, now)
    st.touched = num(doc.touched, now)
    st.chat_at = num(doc.chat_at, now)
    if type(doc.reaction) == "table" then
        st.reaction.face = valid_face(doc.reaction.face) and doc.reaction.face or nil
        st.reaction.until_at = num(doc.reaction.until_at, 0)
    end
    if type(doc.say) == "table" then
        st.say.text = type(doc.say.text) == "string" and doc.say.text or ""
        st.say.until_at = num(doc.say.until_at, 0)
    end
    if type(doc.last) == "table" then for k, v in pairs(doc.last) do st.last[k] = num(v, 0) end end
    if type(doc.pokes) == "table" then
        for _, t in ipairs(doc.pokes) do
            t = tonumber(t)
            if t and now - t < M.POKE_WINDOW then st.pokes[#st.pokes + 1] = t end
        end
    end
    if type(doc.recent) == "table" then
        for _, line in ipairs(doc.recent) do
            if type(line) == "string" then st.recent[#st.recent + 1] = line end
        end
        while #st.recent > 4 do table.remove(st.recent, 1) end
    end
    return st
end

local function speak(st, line, now)
    if type(line) == "string" and line ~= "" then
        st.say.text, st.say.until_at = line, now + M.SAY_MS
        brain.remember(st.recent, line)
    end
end

local function react(st, face, ms, now)
    if valid_face(face) then st.reaction.face, st.reaction.until_at = face, now + (ms or 1400) end
end

-- Time passing. env = { hour, talk, music }; r1, r2 in [0, 1).
function M.tick(st, now, env, r1, r2)
    now = num(now, st.at)
    env = type(env) == "table" and env or {}
    local dt = clamp(now - st.at, 0, 3600)
    st.at = now
    local quiet = now - st.touched
    st.asleep = st.nap or quiet >= M.ASLEEP_MS

    if st.asleep then
        st.charge = clamp(st.charge + dt / M.CHARGE_ASLEEP, 0, 1)
    else
        st.charge = clamp(st.charge - dt / M.CHARGE_AWAKE, 0, 1)
    end
    st.grump = clamp(st.grump - dt / 1800, 0, 1)
    st.mischief = clamp(st.mischief - dt / 1200, 0, 1)

    if st.asleep then
        st.mood = "sleepy"
    elseif st.charge < 0.15 and st.grump > 0.15 then
        st.mood = "grumpy"
    elseif st.grump >= 0.35 then
        st.mood = "grumpy"
    elseif now - st.mood_at >= M.DRIFT_MS then
        st.mood = brain.drift({ energy = st.charge, music = env.music == true }, r1 or 0.5)
        st.mood_at = now
    end

    if not st.asleep and now - st.chat_at >= M.CHAT_MS then
        st.chat_at = now
        if (r2 or 1) < brain.idle_chance(env.talk) then
            speak(st, brain.chatter("idle", env.talk, false, st.recent, r1 or 0.5), now)
        end
    end
    return st
end

-- An intent. Returns the state, ok, and a short reason when it was refused.
function M.apply(st, cmd, now)
    now = num(now, st.at)
    cmd = type(cmd) == "table" and cmd or {}
    local kind = cmd.kind
    local arg = type(cmd.arg) == "table" and cmd.arg or {}
    st.rev = st.rev + 1
    if kind == "poke" then
        local kept = {}
        for _, t in ipairs(st.pokes) do if now - t < M.POKE_WINDOW then kept[#kept + 1] = t end end
        kept[#kept + 1] = now
        st.pokes = kept
        local p = brain.poke(st.mood, #kept, num(arg.r, 0.5))
        react(st, p.face, p.ms, now)
        if p.mood and brain.is_mood(p.mood) then st.mood, st.mood_at = p.mood, now end
        speak(st, p.say or (#kept == 1 and brain.chatter("poke", "chatty", false, st.recent, num(arg.r, 0.5))), now)
        st.grump = clamp(st.grump + (#kept >= 5 and 0.16 or 0.03), 0, 1)
        st.mischief = clamp(st.mischief + 0.02, 0, 1)
        st.touched = now
    elseif kind == "pet" then
        st.asleep, st.nap = false, false
        st.bond = clamp(st.bond + 0.03, 0, 1)
        st.grump = clamp(st.grump - 0.12, 0, 1)
        st.mood, st.mood_at = "happy", now
        react(st, "content", 1600, now)
        speak(st, "mmm.", now)
        st.last.pet, st.touched = now, now
    elseif kind == "play" then
        st.asleep, st.nap = false, false
        st.bond = clamp(st.bond + 0.02, 0, 1)
        st.mischief = clamp(st.mischief + 0.08, 0, 1)
        st.charge = clamp(st.charge - 0.03, 0, 1)
        st.mood, st.mood_at = "playful", now
        react(st, "giggle", 1400, now)
        speak(st, "wheee!", now)
        st.last.play, st.touched = now, now
    elseif kind == "nap" then
        st.nap, st.asleep, st.mood = true, true, "sleepy"
        speak(st, "goodnight…", now)
        st.touched = now
    elseif kind == "wake" then
        st.nap, st.asleep = false, false
        st.mood, st.mood_at = "happy", now
        react(st, "surprised", 1200, now)
        speak(st, "huh? I'm up!", now)
        st.touched = now
    elseif kind == "charge_start" then
        st.charging, st.asleep, st.nap = true, false, false
        st.mood, st.mood_at = "happy", now
        st.touched = now
    elseif kind == "charge_stop" then
        st.charging = false
        st.touched = now
    elseif kind == "charge_step" then
        local d = clamp(arg.delta, -1, 1)
        local before = st.charge
        st.charge = clamp(st.charge + d, 0, 1)
        st.asleep, st.nap = false, false
        if d > 0 and st.charge >= 1 then
            react(st, "dizzy", 2200, now)
            speak(st, "too much…", now)
            st.grump = clamp(st.grump + 0.03, 0, 1)
        elseif math.abs(d) > 0 then
            react(st, d > 0 and "happy" or "sleepy", 900, now)
        end
        st.touched = now
    elseif kind == "set_mood" then
        if brain.is_mood(arg.mood) then
            st.mood, st.mood_at = arg.mood, now
            st.grump = arg.mood == "grumpy" and math.max(st.grump, 0.4) or st.grump
            st.touched = now
        else
            return st, false, "unknown mood"
        end
    elseif kind == "react" then
        if valid_face(arg.face) then
            react(st, arg.face, num(arg.ms, 1400), now)
            speak(st, arg.say, now)
        else
            return st, false, "unknown face"
        end
        st.touched = now
    elseif kind == "say" then
        speak(st, arg.text, now)
        st.touched = now
    elseif kind == "herdr_blocked" then
        react(st, "surprised", 1400, now)
        if num(arg.r, 1) < 0.25 then speak(st, "your agent needs you!", now) end
        st.touched = now
    elseif kind == "chat" or kind == "confirm" or kind == "dismiss" or kind == "quick_setting"
        or kind == "summon" or kind == "panel" then
        st.touched = now
    else
        return st, false, "unknown intent"
    end
    st.last[kind] = now
    return st, true
end

-- What the faces draw: a reaction wins, then sleep, then how he feels.
function M.view(st, now, music)
    now = num(now, st.at)
    local face
    if st.reaction.face and now < st.reaction.until_at then face = st.reaction.face
    elseif st.asleep then face = "asleep"
    elseif st.grump >= 0.7 then face = "angry"
    elseif music and st.mood ~= "grumpy" and st.mood ~= "sleepy" then face = "singing"
    else face = st.mood end
    if not valid_face(face) then face = "happy" end
    return {
        face = face,
        say = (st.say.until_at > now) and st.say.text or "",
        charge = st.charge, bond = st.bond, mischief = st.mischief, grump = st.grump,
        mood = st.mood, asleep = st.asleep, rev = st.rev,
    }
end

return M
