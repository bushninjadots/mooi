-- screenshots — converted from the hyprland core (keybinds.lua → SCREENSHOTS).
--
-- The loader evaluates this file with the SDK injected as `...`:
--   mod.script("screenshot.sh") -> <plugin>/scripts/screenshot.sh
-- Options mirror the original binds (locked = true).
local mod = ...

local shot = "bash " .. mod.script("screenshot.sh")

mod.bind("Print", mod.exec(shot),
         { label = "Screenshot: area", locked = true })
mod.bind("SHIFT_L + Print", mod.exec(shot .. " --edit"),
         { label = "Screenshot: area + edit", locked = true })
mod.bind("SUPER + Print", mod.exec(shot .. " --full"),
         { label = "Screenshot: full screen", locked = true })
mod.bind("SUPER + SHIFT + Print", mod.exec(shot .. " --full --edit"),
         { label = "Screenshot: full + edit", locked = true })

mod.log("screenshots loaded")
