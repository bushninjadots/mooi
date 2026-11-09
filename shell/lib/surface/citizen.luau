-- A citizen of the subsurface (the Subsurface spec §6, D214): a program that lives under the wallpaper —
-- mooi-widgets, mooi-viz, BMO — and shows its things only inside the opening mooi-surface owns. The scene half
-- is the generated `<gen:opening>` block (tools/gen-opening.py); this is the logic half, pure apart from the
-- `run` and `after` it is handed: the hello that asks for the hole, and the reports a citizen sends back.
-- (BMO's logic cannot require from shell/lib — Pleamar keeps a logic inside its own folder — so
-- shell/bmo/bmo.luau writes the same two sends out; tests/unit holds the two together.)

local M = { SURFACE = "mooi-surface", AGAIN_MS = 500 }

local function c12(v)
    v = tonumber(v) or 0
    if v ~= v then v = 0 end
    return math.floor(math.max(0, math.min(4095, v)) + 0.5)
end

-- a box as two numbers under 2^24 (Pleamar's numbers are float32, D124): x * 4096 + y, w * 4096 + h
function M.pack_box(b)
    if type(b) ~= "table" then return 0, 0 end
    return c12(b.x) * 4096 + c12(b.y), c12(b.w) * 4096 + c12(b.h)
end

function M.unpack_box(a, b)
    a, b = math.floor(tonumber(a) or 0), math.floor(tonumber(b) or 0)
    return { x = a // 4096, y = a % 4096, w = b // 4096, h = b % 4096 }
end

-- whether a box lies (at least partly) inside the hole: the rule every citizen's zones keep
function M.inside(hole, box)
    if type(hole) ~= "table" or type(box) ~= "table" then return false end
    if (hole.w or 0) <= 0 or (hole.h or 0) <= 0 then return false end
    return box.x < hole.x + hole.w and box.x + box.w > hole.x and box.y < hole.y + hole.h and box.y + box.h > hole.y
end

-- the arguments of the one `pleamar --say` that reports a box under a pair of event names
function M.say_box(ea, eb, box)
    local a, b = M.pack_box(box)
    return { "--say", M.SURFACE, "emit " .. ea .. " " .. a, "emit " .. eb .. " " .. b }
end

function M.say(event, value)
    return { "--say", M.SURFACE, "emit " .. event .. " " .. tostring(math.floor((tonumber(value) or 0) + 0.5)) }
end

-- On start: ask mooi-surface for the hole now, and again once the scene is surely listening — the first ask
-- can outrun the citizen's own scene (D210). `report` (optional) runs after each ask, to send what the
-- citizen knows (its boxes, its strip).
function M.hello(run, after, report)
    local function ask()
        run("pleamar", { "--say", M.SURFACE, "emit op_want" }, function() end)
        if report then report() end
    end
    ask()
    after(M.AGAIN_MS, ask)
end

return M
