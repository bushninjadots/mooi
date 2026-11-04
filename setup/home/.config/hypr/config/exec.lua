local home = os.getenv("HOME") or ""
local scriptsDir = home .. "/.config/hypr/scripts"
local themeScriptsDir = home .. "/.config/hypr/theme/scripts"

hl.on("hyprland.start", function()
    -- NOTE: no `hyprpm reload && hyprctl reload` here — it re-triggers this
    -- on-start block (reload loop / slow start). Run hyprpm manually once
    -- after plugin changes instead.
    -- The wallpaper is mooi's (its desk draws it, `mooi walls` picks it: mooi D145); the Quickshell
    -- picker that drew it here is retired (archived in ~/.local/state/mooi/archive/skwd-2026-11-04).
    -- The desktop widgets are mooi's own now (shell/mooi-widgets, D137), started by the bar.
    hl.exec_cmd(scriptsDir .. "/compile-run-binaries.sh")
    hl.exec_cmd("systemctl --user start hyprpolkitagent")
    hl.exec_cmd(themeScriptsDir .. "/system-theme.sh apply")
    hl.exec_cmd("nm-applet")
    -- The clipboard history (cliphist) is fed by custom/session.lua.
    hl.exec_cmd("blueman-applet")
end)
