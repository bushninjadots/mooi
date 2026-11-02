-- Session fixes from the dotfiles audit (2026-10-21). Machine-local, beside mooi.lua, so an
-- ArchEclipse update that rewrites config/*.lua cannot undo them.
local home = os.getenv("HOME") or ""
local scripts = home .. "/.config/hypr/scripts"

-- Idle: hypridle (lock after 10 min, suspend after 20 — hypridle.conf) as the saved mode says
-- (idle-mode.sh: ~/.config/hypr/idle-settings.json). Only the top-level autostart.lua started it,
-- and Hyprland never loads that file, so nothing ever locked or slept on its own.
hl.on("hyprland.start", function()
    hl.exec_cmd(scripts .. "/idle-mode.sh boot")
    -- The clipboard's history for mooi's clipboard panel (cliphist): only the unloaded autostart.lua
    -- fed it, so the panel never saw what was copied.
    hl.exec_cmd("pgrep -f 'wl-paste --type text --watch cliphist' >/dev/null || wl-paste --type text --watch cliphist store")
    hl.exec_cmd("pgrep -f 'wl-paste --type image --watch cliphist' >/dev/null || wl-paste --type image --watch cliphist store")
end)

-- Lock and suspend with whichever shell is up: these keys called ArchEclipse's lock over IPC, which
-- does nothing while mooi holds the desktop — and the suspend key waited on it, so it never slept.
pcall(hl.unbind, "SUPER + SHIFT + Escape")
pcall(hl.unbind, "SUPER + CTRL + Escape")
hl.bind("SUPER + SHIFT + Escape", hl.dsp.exec_cmd(scripts .. "/lock-session.sh"))
hl.bind("SUPER + CTRL + Escape", hl.dsp.exec_cmd(scripts .. "/lock-session.sh --suspend"))
