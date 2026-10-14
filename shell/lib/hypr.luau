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

function M.valid_address(a)
    return type(a) == "string" and string.match(a, "^0x%x+$") ~= nil
end

local function target(address)
    return 'window = "address:' .. address .. '"'
end

-- The Lua expression for `hyprctl dispatch`, or nil and why.
function M.dispatch(action, address, opts)
    opts = opts or {}
    if not M.valid_address(address) then return nil, "invalid window address" end
    local w = target(address)
    if action == "float" then
        return 'hl.dsp.window.float({ action = "toggle", ' .. w .. ' })'
    elseif action == "fullscreen" then
        return 'hl.dsp.window.fullscreen({ action = "toggle", ' .. w .. ' })'
    elseif action == "pin" then
        return 'hl.dsp.window.pin({ ' .. w .. ' })'
    elseif action == "move" then
        local ws = opts.workspace
        if type(ws) ~= "number" or ws ~= math.floor(ws) or ws < 1 or ws > 99 then
            return nil, "invalid workspace"
        end
        return string.format('hl.dsp.window.move({ workspace = %d, follow = %s, %s })',
            ws, opts.follow and "true" or "false", w)
    elseif action == "close" then
        return 'hl.dsp.window.close({ ' .. w .. ' })'
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
    }
end

function M.find(clients, address)
    if type(clients) ~= "table" then return nil end
    for _, c in ipairs(clients) do
        if c.address == address then return M.client(c) end
    end
    return nil
end

-- Did the action happen? Compares the window before and after (after == nil: gone).
function M.verify(action, before, after, opts)
    opts = opts or {}
    if action == "close" then
        if after == nil then return true, "Closed " .. before.class end
        return false, before.class .. " is still open (it may be asking something)"
    end
    if after == nil then return false, "The window went away" end
    if action == "float" then
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
