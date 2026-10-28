-- The activity map's counting (D105): every minute, the app with the focus (Hyprland's active
-- window), added to activity.json in the data folder (lib/activity), which the Control Nexus draws.
-- Nothing is counted while the screen is locked or no window has the focus.

local activity = require("lib/activity")

local FILE = "activity.json"

return function(ctx)
    local doc = nil
    local function load()
        if doc then return doc end
        local ok, t = pcall(sys.ask, "files.read", FILE, "json")
        doc = ok and type(t) == "table" and t or {}
        return doc
    end
    every(60000, function()
        run("hyprctl", { "-j", "activewindow" }, function(out, code)
            if code ~= 0 then return end
            local ok, w = pcall(json.decode, out or "")
            local app = ok and type(w) == "table" and tostring(w.class or "") or ""
            if app == "" then return end
            local t = os.date("*t")
            doc = activity.add(load(), t, app)
            if not ctx.safe_mode then pcall(sys.call, "files.write", FILE, doc) end
        end)
    end)
end
