-- mooi's board, as a program of its own (D64). `shell/board.luau` is the board itself (with
-- `lib/board` the pure part): this file paints the shell's colours into the scene, starts it, and
-- puts it away again. The board's file is mooi's own (bin/mooi links the data folder), so a card
-- sent from the pad arrives here through `board.json` and the watch below.

local config = require("lib/config")
local ferro = require("lib/ferro")
local style = require("lib/style")

local FILE = "settings.json"
local PALETTE = "palette.json"

local function read(name, kind)
    local ok, v
    if kind then ok, v = pcall(sys.ask, "files.read", name, kind)
    else ok, v = pcall(sys.ask, "files.read", name) end
    return ok and v or nil
end

local settings = config.parse(read(FILE), json.decode)
local palette = read(PALETTE, "json")

-- The same roles the bar wears, from the same palette and settings; the tokens glide to them.
local function paint()
    local out = ferro.resolve(settings.theme.source, palette, settings.theme.signal, false, ferro.options(settings))
    if not out then return end
    for _, role in ipairs(ferro.ROLES) do
        local c = out[role]
        fact["fr_" .. role .. "_r"] = c.r
        fact["fr_" .. role .. "_g"] = c.g
        fact["fr_" .. role .. "_b"] = c.b
    end
end
paint()
pcall(sys.watch, "files:" .. PALETTE, function()
    palette = read(PALETTE, "json")
    paint()
end)

-- The glow the board's plates and cards carry follows the theme's finish, as the bar's does.
local look = style.facts(settings)
if look and look.st_glow then fact.st_glow = look.st_glow end

require("board")({ safe_mode = false })

-- The entrance: a bar across, then the board drops open around it (the scene's springs).
fact.board_in = 1

-- A press outside the board, its ×, or Escape: it leaves the way it came, then the program ends
-- and the compositor gives the keyboard back to whatever is under it.
on("close_board", function()
    if fact.board_in == 0 then return end
    fact.board_in = 0
    after(240, function() run("pleamar", { "--say", "mooi-board", "quit" }) end)
end)
