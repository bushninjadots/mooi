-- mooi (~/Projects/mooi): the shell being built beside ArchEclipse. Machine-local, so an
-- ArchEclipse update that rewrites config/bind.lua cannot drop these again.
--
-- mooi's keys and (when its settings say so) the desktop's look are chosen in mooi's settings
-- window; mooi writes them to its data folder as a Lua table (shell/lib/desktop.luau) and this
-- file reads it at every start and reload. Missing or unreadable, the defaults below are used.
local home = os.getenv("HOME")
local state = home .. "/.local/share/pleamar/mooi/hypr.lua"
local ok, cfg = pcall(dofile, state)
if not ok or type(cfg) ~= "table" then cfg = {} end

local mooi = cfg.mooi or (home .. "/Projects/mooi/bin/mooi")
local keys = cfg.keys or {
    { "SUPER + ALT + Space", "toggle" },
    { "SUPER + ALT + W", "window" },
    { "SUPER + ALT + SHIFT + Space", "stop" },
}
local bound = {}
for _, k in ipairs(keys) do
    --- mooi: one of its keys (chosen in mooi's settings → Keys). One bound earlier to the same keys
    --- (ArchEclipse's SUPER+TAB, its own overview) is let go first, so a press does one thing.
    pcall(hl.unbind, k[1])
    pcall(hl.bind, k[1], hl.dsp.exec_cmd(mooi .. " " .. k[2]))
    bound[#bound + 1] = k[1] .. "=" .. k[2]
end
-- mooi's wallpaper picker (D145: the strip and the colour orbit, `mooi walls`). Super+W was the
-- wallpaper-styles picker's (config/bind.lua): let go first, so a press opens only mooi's. Super+Alt+L
-- (the studio's key, kept for the hand that knows it) opens it too. Bound here because they are not
-- keys the settings window manages.
pcall(hl.unbind, "SUPER + W")
pcall(hl.bind, "SUPER + W", hl.dsp.exec_cmd(mooi .. " walls"))
pcall(hl.bind, "SUPER + ALT + L", hl.dsp.exec_cmd(mooi .. " walls"))

-- mooi's touchpad gestures (Settings → Overview → Touchpad swipe; none unless chosen): each runs one
-- of mooi's commands, the way its keys do.
for _, g in ipairs(type(cfg.gestures) == "table" and cfg.gestures or {}) do
    local cmd = mooi .. " " .. tostring(g[3])
    pcall(hl.gesture, { fingers = g[1], direction = g[2], action = function() hl.exec_cmd(cmd) end })
    bound[#bound + 1] = "gesture " .. tostring(g[1]) .. " " .. tostring(g[2]) .. "=" .. tostring(g[3])
end
-- mooi as the whole desktop (Settings → Advanced, session.standalone; mooi's D48): it starts at login,
-- and the keys that reached ArchEclipse's panels go to mooi — or, where mooi has nothing like them, are
-- let go. With ArchEclipse uninstalled (2026-10-21; archive in ~/.local/state/mooi/) this holds whatever
-- the setting says: there is no other shell to fall back to.
local archeclipse = io.open(home .. "/.config/quickshell/archeclipse/shell.qml", "r")
if archeclipse then archeclipse:close() end
if cfg.standalone == true or not archeclipse then
    hl.on("hyprland.start", function() hl.exec_cmd(mooi .. " session") end)
    local take = {
        { "SUPER + A", "toggle" },                   -- search and apps: the one key for them (Super alone does nothing, 2026-10-29)
        { "SUPER + r", "system" },                   -- the system panel (its right panel)
        { "SUPER + l", "lock" },                     -- mooi's lock screen (D160; was ArchEclipse's notices)
        { "SUPER + SHIFT + v", "clipboard" },        -- clipboard history
        { "SUPER + SHIFT + R", "record" },           -- record the screen (again: stop)
        { "SUPER + CTRL + SHIFT + R", "record area" },
        { "SUPER + SHIFT + B", "session" },          -- (re)start the shell: mooi, not ArchEclipse's bar
    }
    for _, t in ipairs(take) do
        pcall(hl.unbind, t[1])
        pcall(hl.bind, t[1], hl.dsp.exec_cmd(mooi .. " " .. t[2]))
    end
    pcall(hl.unbind, "SUPER + Escape")               -- the power menu mooi's own session button opens
    pcall(hl.bind, "SUPER + Escape", hl.dsp.exec_cmd("wlogout -b 5 -p layer-shell"))
    for _, k in ipairs({ "SUPER + SUPER_L", "SUPER + ALT_L", "SUPER + m", "SUPER + period", "SUPER + SHIFT + n" }) do
        pcall(hl.unbind, k)                          -- toggle bar, media panel, emoji, notes: ArchEclipse's alone
    end
    -- D171: Super alone, on release (never after Super+a key): the Pill comes back; twice, its board
    -- D208: Super's press begins Surface's Reveal (after a hold); its release ends it — or, quick, is the tap
    -- above (`mooi reveal up` falls back to `mooi pill` when Surface is not running)
    pcall(hl.bind, "SUPER + SUPER_L", hl.dsp.exec_cmd(mooi .. " reveal down"))
    pcall(hl.bind, "SUPER + SUPER_L", hl.dsp.exec_cmd(mooi .. " reveal up"), { release = true })
    -- D171: Super + wheel asks the bar: over a pill it turns the views, elsewhere the workspace
    pcall(hl.unbind, "SUPER + mouse_down")
    pcall(hl.unbind, "SUPER + mouse_up")
    pcall(hl.bind, "SUPER + mouse_down", hl.dsp.exec_cmd(mooi .. " wheel 1"))
    pcall(hl.bind, "SUPER + mouse_up", hl.dsp.exec_cmd(mooi .. " wheel -1"))
    bound[#bound + 1] = "standalone"
end

-- The windows' opening and closing (Settings → Windows → Windows waking): a rule each, tagged
-- `_default`, in front of the two shaders mooi wrote beside its keys. Empty while the effects are
-- off, and then the windows animate exactly as Hyprland says. Letting go of them needs this file
-- read again, so "window" rides in what mooi compares with hypr.loaded below, as the keys do.
local window = type(cfg.window) == "table" and cfg.window or {}
for _, rule in ipairs(window) do pcall(hl.window_rule, rule) end

-- What was bound, for mooi to compare with what it wants (it reloads Hyprland when they differ).
if #window > 0 then bound[#bound + 1] = "window" end
local f = io.open(home .. "/.local/share/pleamar/mooi/hypr.loaded", "w")
if f then f:write(table.concat(bound, "|")); f:close() end

-- The look mooi manages (window borders, gaps, corners); empty while it does not.
if type(cfg.look) == "string" and cfg.look ~= "" then
    local fn = load(cfg.look)
    if fn then pcall(fn) end
end

--- mooi's settings window floats, centred, at its own size
-- the Pill's drop terminal (D171): floating, pinned, a fixed size near the top
hl.window_rule({
    match = { class = "^(mooi-drop)$" },
    float = true,
    pin = true,
    size = "960 420",
    move = "480 54",
})
hl.window_rule({
    match = { title = "^(mooi · settings)$" },
    float = true,
    center = true,
    size = "1180 800",
})
