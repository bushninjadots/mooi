local home = os.getenv("HOME") or ""
local scriptsDir = home .. "/.config/hypr/scripts"
local themeScriptsDir = home .. "/.config/hypr/theme/scripts"
local wallpaperPicker = home .. "/.config/qs-wallpaperpicker/bin/qs-wallpaperpicker"

hl.on("hyprland.start", function()
    -- NOTE: no `hyprpm reload && hyprctl reload` here — it re-triggers this
    -- on-start block (reload loop / slow start). Run hyprpm manually once
    -- after plugin changes instead.
    -- Draws the wallpaper (and is the SUPER+W picker); recolours via matugen.
    hl.exec_cmd(wallpaperPicker)
    -- The desktop widgets are mooi's own now (shell/mooi-widgets, D137), started by the bar.
    hl.exec_cmd(scriptsDir .. "/compile-run-binaries.sh")
    hl.exec_cmd("systemctl --user start hyprpolkitagent")
    hl.exec_cmd(themeScriptsDir .. "/system-theme.sh apply")
    hl.exec_cmd("nm-applet")
    -- The clipboard history (cliphist) is fed by custom/session.lua.
    hl.exec_cmd("blueman-applet")
end)
