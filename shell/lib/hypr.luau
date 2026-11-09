-- Hyprland adapter: the only place that knows Hyprland's command syntax.
-- Pure (builds commands, reads replies); mooi.luau runs them with `run`.
--
-- Verified on Hyprland 0.56.2 with a Lua config (docs/AUDIT.md):
--   · dispatch takes Lua: `hyprctl dispatch 'hl.dsp.window.float({ … })'`;
--     the legacy `focuswindow address:…` form is rejected.
--   · window dispatchers accept `window = "address:0x…"`.
--   · an unknown address still answers "ok", so success is never taken from
--     the reply: it is read back from `hyprctl -j clients`.
--   · acting on a window on another workspace moves focus there.

local M = {}

M.ACTIONS = { "float", "fullscreen", "pin", "move", "close" }
-- What the command membrane offers on any window it lists (a contextual satellite).
M.SATELLITE = { "focus", "bring", "float", "fullscreen", "close" }

function M.valid_address(a)
    return type(a) == "string" and string.match(a, "^0x%x+$") ~= nil
end

local function target(address)
    return 'window = "address:' .. address .. '"'
end

-- Hyprland's Lua config takes dispatch as Lua (`hyprctl dispatch workspace 3` is refused): a workspace
-- to go to, a command to run, a window to close by its class (2026-11-07).
local function quoted(s) return '"' .. tostring(s):gsub("\\", "\\\\"):gsub('"', '\\"') .. '"' end
function M.go_workspace(n) return 'hl.dsp.focus({ workspace = ' .. quoted(n) .. ' })' end
function M.exec(cmd) return 'hl.dsp.exec_cmd(' .. quoted(cmd) .. ')' end
function M.close_class(class) return 'hl.dsp.window.close({ window = ' .. quoted("class:" .. class) .. ' })' end

-- The Lua expression for `hyprctl dispatch`, or nil and why.
function M.dispatch(action, address, opts)
    opts = opts or {}
    if not M.valid_address(address) then return nil, "invalid window address" end
    local w = target(address)
    if action == "focus" then
        return 'hl.dsp.focus({ ' .. w .. ' })'
    elseif action == "float" then
        return 'hl.dsp.window.float({ action = "toggle", ' .. w .. ' })'
    elseif action == "fullscreen" then
        return 'hl.dsp.window.fullscreen({ action = "toggle", ' .. w .. ' })'
    elseif action == "pin" then
        return 'hl.dsp.window.pin({ ' .. w .. ' })'
    elseif action == "move" or action == "bring" then
        local ws = opts.workspace
        if type(ws) ~= "number" or ws ~= math.floor(ws) or ws < 1 or ws > 99 then
            return nil, "invalid workspace"
        end
        return string.format('hl.dsp.window.move({ workspace = %d, follow = %s, %s })',
            ws, (action == "move" and opts.follow) and "true" or "false", w)
    -- D194: Loom / Fold parks a structure's windows on its own special workspace (`special:loom-s3`),
    -- off every workspace, still running; `move` with `follow = false` brings one back
    elseif action == "park" then
        local p = opts.park
        if type(p) ~= "string" or not string.match(p, "^loom%-s%d+$") then return nil, "invalid park" end
        return string.format('hl.dsp.window.move({ workspace = "special:%s", follow = false, %s })', p, w)
    -- D224: burying — the window to the hidden workspace the Subsurface keeps, leaving a tile under the wallpaper
    elseif action == "bury" then
        return string.format('hl.dsp.window.move({ workspace = "special:mooi-buried", follow = false, %s })', w)
    elseif action == "close" then
        return 'hl.dsp.window.close({ ' .. w .. ' })'
    -- The shutter's (D35), each checked on Hyprland 0.56.2 against a window read back:
    elseif action == "maximize" then
        return 'hl.dsp.window.fullscreen({ mode = "maximized", action = "toggle", ' .. w .. ' })'
    elseif action == "center" then
        return 'hl.dsp.window.center({ ' .. w .. ' })'
    elseif action == "size" then
        local sw, sh = tonumber(opts.w), tonumber(opts.h)
        if not sw or not sh or sw < 100 or sh < 100 or sw > 8000 or sh > 8000 then return nil, "invalid size" end
        return string.format('hl.dsp.window.resize({ x = %d, y = %d, %s })', math.floor(sw), math.floor(sh), w)
    elseif action == "swap" then
        local d = opts.direction
        if d ~= "l" and d ~= "r" and d ~= "u" and d ~= "d" then return nil, "invalid direction" end
        return string.format('hl.dsp.window.move({ direction = "%s", %s })', d, w)
    -- The Overview's rearranging (D45), each checked on Hyprland 0.56.2 with throwaway windows read
    -- back: a swap with one particular window (`target`), and a floating window put at a spot of the
    -- layout (`x`, `y`: where the monitors are laid out, not the screen's own corner).
    elseif action == "swap_with" then
        if not M.valid_address(opts.target) then return nil, "invalid window to swap with" end
        return string.format('hl.dsp.window.swap({ target = "address:%s", %s })', opts.target, w)
    elseif action == "place" then
        local x, y = tonumber(opts.x), tonumber(opts.y)
        if not x or not y or x ~= x or y ~= y or math.abs(x) > 100000 or math.abs(y) > 100000 then return nil, "invalid spot" end
        return string.format('hl.dsp.window.move({ x = %d, y = %d, %s })', math.floor(x + 0.5), math.floor(y + 0.5), w)
    elseif action == "opacity" then
        local a = tonumber(opts.alpha)
        if not a or a < 0.1 or a > 1 then return nil, "invalid opacity" end
        return string.format('hl.dsp.window.set_prop({ prop = "opacity", value = "%.2f", %s })', a, w)
    end
    return nil, "unknown action " .. tostring(action)
end

-- One client from `hyprctl -j clients` / `activewindow`, reduced to what mooi uses.
function M.client(c)
    if type(c) ~= "table" or not M.valid_address(c.address) then return nil end
    local ws = type(c.workspace) == "table" and c.workspace.id or nil
    return {
        address = c.address,
        class = tostring(c.class or ""),
        title = tostring(c.title or ""),
        floating = c.floating == true,
        pinned = c.pinned == true,
        -- Hyprland's mode: 0 none, 1 maximized, 2 fullscreen. Compared as a number,
        -- shown as fullscreen only from 2, so a maximized window is not called fullscreen.
        fullscreen_mode = tonumber(c.fullscreen) or 0,
        fullscreen = (tonumber(c.fullscreen) or 0) >= 2,
        workspace = tonumber(ws) or 0,
        -- where it is, in the compositor's logical pixels, and on which monitor (its id)
        x = type(c.at) == "table" and tonumber(c.at[1]) or 0, y = type(c.at) == "table" and tonumber(c.at[2]) or 0,
        w = type(c.size) == "table" and tonumber(c.size[1]) or 0, h = type(c.size) == "table" and tonumber(c.size[2]) or 0,
        monitor = tonumber(c.monitor) or 0,
        pid = tonumber(c.pid) or 0,
        -- 0 is the window that has (or last had) focus; higher is longer ago.
        recency = tonumber(c.focusHistoryID) or 999,
        focused = tonumber(c.focusHistoryID) == 0,
    }
end

function M.find(clients, address)
    if type(clients) ~= "table" then return nil end
    for _, c in ipairs(clients) do
        if c.address == address then return M.client(c) end
    end
    return nil
end

-- Every window worth listing (mapped, not hidden), most recently focused first.
function M.windows(clients)
    local out = {}
    if type(clients) ~= "table" then return out end
    for _, c in ipairs(clients) do
        if c.mapped ~= false and c.hidden ~= true then
            local w = M.client(c)
            if w then out[#out + 1] = w end
        end
    end
    table.sort(out, function(a, b) return a.recency < b.recency end)
    return out
end

-- The shell a terminal window runs, from `ps -o pid=,comm= --ppid <terminal> --sort=start_time`:
-- the newest child that is a shell. A terminal starts helpers beside it (kitty's `kitten`s), and the
-- newest child is often one of those, in the home folder whatever the shell is in.
M.SHELLS = { zsh = true, bash = true, fish = true, sh = true, dash = true, ksh = true, tcsh = true, nu = true, xonsh = true, elvish = true }
function M.terminal_shell(ps_out)
    local found = nil
    for pid, comm in string.gmatch(tostring(ps_out or ""), "(%d+)%s+([^\n]+)") do
        if M.SHELLS[string.match(comm, "^%-?([%w_%.]+)") or ""] then found = tonumber(pid) end
    end
    return found
end

-- Did the action happen? Compares the window before and after (after == nil: gone).
function M.verify(action, before, after, opts)
    opts = opts or {}
    if action == "close" then
        if after == nil then return true, "Closed " .. before.class end
        return false, before.class .. " is still open (it may be asking something)"
    end
    if after == nil then return false, "The window went away" end
    if action == "focus" then
        if after.focused then return true, "Focused " .. after.class end
        return false, "Hyprland did not focus " .. after.class
    elseif action == "bring" then
        if after.workspace == opts.workspace then
            return true, string.format("Brought %s here", after.class)
        end
        return false, string.format("%s is still on workspace %d", after.class, after.workspace)
    elseif action == "float" then
        if after.floating ~= before.floating then
            return true, after.floating and "Floating" or "Tiled"
        end
        return false, "Hyprland did not change floating"
    elseif action == "fullscreen" then
        if after.fullscreen_mode ~= before.fullscreen_mode then
            return true, after.fullscreen and "Fullscreen" or "Left fullscreen"
        end
        return false, "Hyprland did not change fullscreen"
    elseif action == "pin" then
        if not before.floating then return false, "Only floating windows can be pinned" end
        if after.pinned ~= before.pinned then
            return true, after.pinned and "Pinned to every workspace" or "Unpinned"
        end
        return false, "Hyprland did not change pinning"
    elseif action == "maximize" then
        if after.fullscreen_mode ~= before.fullscreen_mode then
            return true, (after.fullscreen_mode == 1) and "Maximized" or "Restored"
        end
        return false, "Hyprland did not change it"
    elseif action == "center" then
        if not before.floating then return false, "Only a floating window can be centred" end
        return true, "Centred"           -- already centred, it does not move: that is still centred
    elseif action == "size" then
        if math.abs(after.w - (tonumber(opts.w) or 0)) <= 2 and math.abs(after.h - (tonumber(opts.h) or 0)) <= 2 then
            return true, string.format("%d × %d", after.w, after.h)
        end
        return false, string.format("It stayed %d × %d (it may hold a size of its own)", after.w, after.h)
    elseif action == "swap" then
        if after.x ~= before.x or after.y ~= before.y then return true, "Swapped" end
        return false, "Nothing to swap with that way"
    elseif action == "swap_with" then
        if after.x ~= before.x or after.y ~= before.y then return true, "Swapped" end
        return false, "Hyprland kept them where they were"
    elseif action == "place" then
        if math.abs(after.x - (tonumber(opts.x) or 0)) <= 2 and math.abs(after.y - (tonumber(opts.y) or 0)) <= 2 then return true, "Placed" end
        return false, "It did not go there (it may not be floating)"
    elseif action == "move" then
        if after.workspace == opts.workspace then
            return true, string.format("Moved to workspace %d", opts.workspace)
        end
        return false, string.format("Still on workspace %d", after.workspace)
    end
    return false, "unknown action"
end

-- Close is asynchronous (the program decides), so it is polled for a while.
M.CLOSE_POLLS = 6
M.CLOSE_POLL_MS = 250

return M
