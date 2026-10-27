-- BMO's brain, unit-tested. Run: lua5.4 companion/bmo/test.lua (from the repo root)
package.path = "companion/bmo/?.luau;" .. package.path
local B = require("brain")

local failed, total = 0, 0
local function test(name, fn)
    total = total + 1
    local ok, err = pcall(fn)
    if ok then print("  ok    " .. name) else failed = failed + 1; print("  FAIL  " .. name .. ": " .. tostring(err)) end
end
local function eq(a, b, what) if a ~= b then error((what or "") .. ": " .. tostring(a) .. " ~= " .. tostring(b), 2) end end

test("every mood has a face", function()
    for _, m in ipairs(B.MOODS) do assert(B.FACES[m], m) end
    for _, f in ipairs({ "asleep", "giggle", "singing", "yawn", "content" }) do assert(B.FACES[f], f) end
end)

test("a reaction wins, then the activity, then the mood", function()
    eq(B.expression({ mood = "happy", activity = "sleeping", reaction = "surprised" }), "surprised")
    eq(B.expression({ mood = "happy", activity = "sleeping", reaction = "" }), "asleep")
    eq(B.expression({ mood = "grumpy", activity = "dancing" }), "singing")
    eq(B.expression({ mood = "curious", activity = "idle" }), "curious")
end)

test("the weighted pick is stable and covers its range", function()
    eq(B.pick({ a = 1, b = 1 }, 0), "a")
    eq(B.pick({ a = 1, b = 1 }, 0.99), "b")
    eq(B.pick({ a = 0 }, 0.5), nil)
end)

test("still never moves on its own; music sometimes dances", function()
    eq(B.decide({ mood = "excited", still = true, can_walk = true, wander = 3 }, 0, 0.5), "rest")
    eq(B.decide({ mood = "happy", music = true, can_walk = true, wander = 2 }, 0.1, 0.5), "dance")
end)

test("no walking when wandering is off or he may not", function()
    for i = 0, 99 do
        local r = i / 100
        assert(B.decide({ mood = "excited", wander = 0, can_walk = true }, 0.9, r) ~= "walk")
        assert(B.decide({ mood = "excited", wander = 3, can_walk = false }, 0.9, r) ~= "walk")
    end
end)

test("five quick pokes make him grumpy; three make him excited", function()
    eq(B.poke("happy", 5, 0.5).mood, "grumpy")
    eq(B.poke("happy", 3, 0.5).move, "big_hop")
    eq(B.poke("happy", 3, 0.5).mood, "excited")
    eq(B.poke("sleepy", 1, 0.5).move, "nod")
end)

test("energy drains awake, faster at night, and fills asleep", function()
    eq(B.energy(1, 720, false, false), 0.9)
    eq(B.energy(1, 360, false, true), 0.9)
    eq(B.energy(0.5, 60, true, false), 0.6)
    eq(B.energy(0, 10, false, false), 0)
end)

test("settings are read whatever the file holds", function()
    local s = B.settings({ wander = 9, size = "x", motion = "wild", above = 1, doze = 0 })
    eq(s.wander, 3); eq(s.size, 0.9); eq(s.motion, "calm"); eq(s.above, false); eq(s.doze, 1)
    eq(B.settings(nil).music, true)
end)

print(string.format("\n%d tests, %d failed", total, failed))
os.exit(failed == 0 and 0 or 1)
