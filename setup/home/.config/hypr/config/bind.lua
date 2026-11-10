local home = os.getenv("HOME") or ""
local scriptsDir = home .. "/.config/hypr/scripts"
local screenshot = scriptsDir .. "/screenshot.sh"
local terminal = "kitty"
-- Lock (hyprlock) and lock-then-suspend: scripts/lock-session.sh.
local lock = scriptsDir .. "/lock-session.sh"
local suspend = scriptsDir .. "/lock-session.sh --suspend"
-- Focused monitor, resolved at keypress time. Uses activeworkspace (small JSON)
-- instead of full monitors list to avoid a hyprctl+jq scan per keypress.
local monitor = "$(hyprctl activeworkspace -j | jq -r '.monitor')"
local resizeAmount = 25
local changeBrightness = scriptsDir .. "/change-brightness.sh"
local volUp = "wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%+"
local volDown = "wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-"
local volMute = "wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle"


hl.config({
    binds = {
        workspace_back_and_forth = 1,
        allow_workspace_cycles = 1,
        pass_mouse_when_bound = 0,
    },
})

local mainMod = "SUPER"

-- Window Management
--- fullscreen active window
hl.bind(mainMod .. " + F", hl.dsp.window.fullscreen({ action = "toggle" }))
--- close active window
hl.bind(mainMod .. " + Q", hl.dsp.window.close())
--- kill active window
hl.bind(mainMod .. " + SHIFT + Q", hl.dsp.window.kill())
--- float for active window
hl.bind(mainMod .. " + SPACE", hl.dsp.window.float({ action = "toggle" }))
--- pin active window
hl.bind(mainMod .. " + CTRL + Space", hl.dsp.window.pin())

-- Open Apps
--- open terminal
hl.bind(mainMod .. " + Return", hl.dsp.exec_cmd(terminal))
--- open floating terminal
hl.bind(mainMod .. " + CTRL + Return", hl.dsp.exec_cmd("[float] " .. terminal))
--- open btop in workspace 5
hl.bind(mainMod .. " + P", hl.dsp.exec_cmd("[workspace 5] " .. terminal .. " btop"))
--- open file manager
hl.bind(mainMod .. " + E", hl.dsp.exec_cmd("nautilus"))

-- Status Bar and Panels
--- open the default web browser
hl.bind(mainMod .. " + B", hl.dsp.exec_cmd([[gtk-launch "$(xdg-settings get default-web-browser)" || zen-browser]]))
--- toggle wallpaper picker (the style chosen in Settings -> Wallpaper Picker)
hl.bind(mainMod .. " + w", hl.dsp.exec_cmd(home .. "/Projects/mooi/bin/mooi walls"))

-- Screenshot and Screen Record Keybinds
--- screenshot workspace
hl.bind(mainMod .. " + SHIFT + S", hl.dsp.exec_cmd(screenshot .. " --now"))
--- screenshot area
hl.bind(mainMod .. " + CTRL + SHIFT + S", hl.dsp.exec_cmd(screenshot .. " --area"))

-- Special Workspace Keybinds
--- move to special workspace
hl.bind(mainMod .. " + CTRL + S", hl.dsp.window.move({ workspace = "special" }))
--- toggle special workspace
hl.bind(mainMod .. " + S", hl.dsp.workspace.toggle_special())

-- Media, Brightness and Volume Controls
--- volume up (XF86 + ALT fallback share one command)
hl.bind("ALT + F12", hl.dsp.exec_cmd(volUp), { locked = true, repeating = true })
hl.bind("XF86AudioRaiseVolume", hl.dsp.exec_cmd(volUp),
    { locked = true, repeating = true })
--- volume down (XF86 + ALT fallback share one command)
hl.bind("ALT + F11", hl.dsp.exec_cmd(volDown), { locked = true, repeating = true })
hl.bind("XF86AudioLowerVolume", hl.dsp.exec_cmd(volDown),
    { locked = true, repeating = true })
--- toggle mute
hl.bind("XF86AudioMute", hl.dsp.exec_cmd(volMute), { locked = true })

--- brightness up (XF86 + ALT fallback share one command)
hl.bind("ALT + F3", hl.dsp.exec_cmd(changeBrightness .. " +10"), { locked = true, repeating = true })
hl.bind("XF86MonBrightnessUp", hl.dsp.exec_cmd(changeBrightness .. " +10"), { locked = true, repeating = true })
--- brightness down (XF86 + ALT fallback share one command)
hl.bind("ALT + F2", hl.dsp.exec_cmd(changeBrightness .. " -10"), { locked = true, repeating = true })
hl.bind("XF86MonBrightnessDown", hl.dsp.exec_cmd(changeBrightness .. " -10"), { locked = true, repeating = true })

-- Lock keys (mooi D265): the node's gauge says whether Caps Lock or Num Lock is now on. non_consuming, so the
-- key still reaches the keyboard; ignore_mods, since Hyprland counts the lock itself as a modifier.
--- caps lock shown
hl.bind("Caps_Lock", hl.dsp.exec_cmd(home .. "/Projects/mooi/bin/mooi osd caps"), { non_consuming = true, locked = true, ignore_mods = true })
--- num lock shown
hl.bind("Num_Lock", hl.dsp.exec_cmd(home .. "/Projects/mooi/bin/mooi osd num"), { non_consuming = true, locked = true, ignore_mods = true })

-- System Controls
--- lock
hl.bind(mainMod .. " + SHIFT + Escape", hl.dsp.exec_cmd(lock))
--- suspend
hl.bind(mainMod .. " + CTRL + Escape", hl.dsp.exec_cmd(suspend))
--- shutdown
hl.bind(mainMod .. " + CTRL + SHIFT + Escape", hl.dsp.exec_cmd("shutdown now"))

-- Window Resize, Move and Focus
--- expand left
hl.bind(mainMod .. " + SHIFT + left", hl.dsp.window.resize({ x = -resizeAmount, y = 0, relative = true }),
    { repeating = true })
--- expand right
hl.bind(mainMod .. " + SHIFT + right", hl.dsp.window.resize({ x = resizeAmount, y = 0, relative = true }),
    { repeating = true })
--- expand up
hl.bind(mainMod .. " + SHIFT + up", hl.dsp.window.resize({ x = 0, y = -resizeAmount, relative = true }),
    { repeating = true })
--- expand down
hl.bind(mainMod .. " + SHIFT + down", hl.dsp.window.resize({ x = 0, y = resizeAmount, relative = true }),
    { repeating = true })

--- move left
hl.bind(mainMod .. " + CTRL + left", hl.dsp.window.move({ direction = "l" }))
--- move right
hl.bind(mainMod .. " + CTRL + right", hl.dsp.window.move({ direction = "r" }))
--- move up
hl.bind(mainMod .. " + CTRL + up", hl.dsp.window.move({ direction = "u" }))
--- move down
hl.bind(mainMod .. " + CTRL + down", hl.dsp.window.move({ direction = "d" }))

--- focus left
hl.bind(mainMod .. " + left", hl.dsp.focus({ direction = "left" }))
--- focus right
hl.bind(mainMod .. " + right", hl.dsp.focus({ direction = "right" }))
--- focus up
hl.bind(mainMod .. " + up", hl.dsp.focus({ direction = "up" }))
--- focus down
hl.bind(mainMod .. " + down", hl.dsp.focus({ direction = "down" }))

-- Workspace Keybinds
for i = 1, 10 do
    local key = i % 10
    --- switch workspace [key]
    hl.bind(mainMod .. " + " .. key, hl.dsp.focus({ workspace = i }))
    --- move to workspace [key]
    hl.bind(mainMod .. " + CTRL + " .. key, hl.dsp.window.move({ workspace = i }))
    --- silent move to workspace [key]
    hl.bind(mainMod .. " + SHIFT + " .. key, hl.dsp.window.move({ workspace = i, follow = false }))
end

-- NumPad Workspaces Keybinds
local numpad_keys = {
    "KP_End",
    "KP_Down",
    "KP_Next",
    "KP_Left",
    "KP_Begin",
    "KP_Right",
    "KP_Home",
    "KP_Up",
    "KP_Prior",
    "KP_Insert"
}

for index, key_name in ipairs(numpad_keys) do
    local workspace_id = tostring(index + 10)

    --- switch Workspace [key]
    hl.bind(mainMod .. " + " .. key_name, hl.dsp.focus({ workspace = workspace_id }))
    --- move to workspace [key]
    hl.bind(mainMod .. " + CTRL + " .. key_name, hl.dsp.window.move({ workspace = workspace_id }))
    --- silent move to workspace [key]
    hl.bind(mainMod .. " + SHIFT + " .. key_name, hl.dsp.window.move({ workspace = workspace_id, follow = false }))
end

--- previous workspace
hl.bind(mainMod .. " + SHIFT + TAB", hl.dsp.focus({ workspace = "prev" }))

--- next workspace
hl.bind(mainMod .. " + mouse_down", hl.dsp.focus({ workspace = "e+1" }))
--- previous workspace
hl.bind(mainMod .. " + mouse_up", hl.dsp.focus({ workspace = "e-1" }))

--- move to next workspace
hl.bind(mainMod .. " + mouse:272", hl.dsp.window.drag(), { mouse = true })
--- move to previous workspace
hl.bind(mainMod .. " + mouse:273", hl.dsp.window.resize(), { mouse = true })
