-- file-search — file search plugin (equisdots plugin standard).
--
-- The loader evaluates this file with the SDK injected as `...`; the panel is
-- declared as provides.panels.file-search and toggled through the shell's
-- panel manager (qs_manager, a core session script).
local mod = ...

local home = os.getenv("HOME") or ""
mod.bind("SUPER + apostrophe",
         mod.exec("bash " .. home .. "/.config/hypr/scripts/qs_manager.sh toggle file-search"),
         { label = "File search: toggle panel" })

mod.log("file-search loaded")
