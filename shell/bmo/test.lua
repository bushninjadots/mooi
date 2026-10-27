-- BMO's brain, unit-tested. Run: lua5.4 shell/bmo/test.lua (from the repo root)
package.path = "shell/bmo/?.luau;" .. package.path
local B = require("brain")

local failed, total = 0, 0
local function test(name, fn)
    total = total + 1
    local ok, err = pcall(fn)
    if ok then print("  ok    " .. name) else failed = failed + 1; print("  FAIL  " .. name .. ": " .. tostring(err)) end
end
local function eq(a, b, what) if a ~= b then error((what or "") .. ": " .. tostring(a) .. " ~= " .. tostring(b), 2) end end

test("throw: the flick's speed from the last samples of a drag", function()
    local vx, vy = B.release({ { x = 0, y = 0 }, { x = 10, y = -5 }, { x = 20, y = -10 }, { x = 30, y = -15 } }, 16)
    eq(math.floor(vx + 0.5), 625, "px/s across"); eq(math.floor(vy + 0.5), -312, "and up")
    local sx = B.release({ { x = 5, y = 5 } }, 16); eq(sx, 0, "one sample: no throw")
end)
test("throw: gravity, bounces that lose speed, an impact, and rest", function()
    local b = { x0 = 0, x1 = 1000, y0 = 0, y1 = 500 }
    local s = { x = 500, y = 100, vx = 0, vy = 0 }
    local n = B.fly(s, 0.1, b); assert(n.vy > 0 and n.y > 100, "falls")
    local hit = { x = 500, y = 499, vx = 0, vy = 800 }
    local h = B.fly(hit, 0.02, b); eq(h.y, 500, "stops at the floor"); assert(h.vy < 0, "bounces up"); assert(math.abs(h.vy) < 800, "loses speed")
    assert(h.impact >= 700, "an impact as hard as it came in")
    local w = B.fly({ x = 999, y = 200, vx = 900, vy = 0 }, 0.02, b); eq(w.x, 1000, "the right wall"); assert(w.vx < 0, "bounces back")
    local r = { x = 500, y = 500, vx = 3, vy = 0 }
    for _ = 1, 400 do r = B.fly(r, 0.016, b); if r.rest then break end end
    eq(r.rest, true, "comes to rest on the floor"); eq(r.y, 500, "standing")
end)

test("settings: mooi's companion section — sizes by name, place, variant, throw, talk, reactions", function()
    local c = B.settings({ size = "tiny", place = "bar", variant = "gameboy", throw = false, talk = "chatty",
                           react = { notes = false } })
    eq(c.size, 0.5, "tiny"); eq(c.place, "bar", "on the bar"); eq(c.variant, "gameboy", "variant")
    eq(c.throw, false, "no throwing"); eq(c.talk, "chatty", "talk")
    eq(c.react.notes, false, "notifications off"); eq(c.react.spaces, true, "the rest default on"); eq(c.react.battery, true, "battery")
    local d = B.settings({})
    eq(d.size, 0.9, "medium by default"); eq(d.place, "desktop", "desktop"); eq(d.variant, "classic", "classic")
    eq(d.throw, true, "throwing on"); eq(d.talk, "rare", "rare talk")
    eq(B.settings({ size = "huge", variant = "nope", talk = 5 }).variant, "classic", "unknown variant")
    eq(B.size_name(0.7), "small", "a size's name back")
end)

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
