-- quicknotes — scratch notepad plugin (equisdots plugin standard).
--
-- The loader evaluates this file with the SDK injected as `...`; the panel is
-- declared as provides.panels.quicknotes and toggled through the shell's panel
-- manager (qs_manager, a core session script).
local mod = ...

local home = os.getenv("HOME") or ""
mod.bind("SUPER + Y",
         mod.exec("bash " .. home .. "/.config/hypr/scripts/qs_manager.sh toggle quicknotes"),
         { label = "QuickNotes: toggle panel" })

mod.log("quicknotes loaded")
