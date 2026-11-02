-- rss-reader — feed reader plugin (equisdots plugin standard).
--
-- The loader evaluates this file with the SDK injected as `...`; the panel is
-- declared as provides.panels.rss-reader and toggled through the shell's
-- panel manager (qs_manager, a core session script).
local mod = ...

local home = os.getenv("HOME") or ""
mod.bind("SUPER + O",
         mod.exec("bash " .. home .. "/.config/hypr/scripts/qs_manager.sh toggle rss-reader"),
         { label = "RSS Reader: toggle panel" })

mod.log("rss-reader loaded")
