-- The only config entrypoint. Edit the modules in config/ (and config/custom/);
-- files in legacy/ are not read. Quickshell's config/user-*.lua are loaded as overlays —
-- see legacy/README.md.
-- -- Hyprland Lua config entrypoint.
hl.env("XDG_MENU_PREFIX,arch-", "1")
hl.env("XDG_CURRENT_DESKTOP,Hyprland", "1")
hl.env("XDG_SESSION_TYPE,wayland", "1")
hl.env("XDG_SESSION_DESKTOP,Hyprland", "1")

local function require_all(configs)
	for _, name in ipairs(configs) do
		require("config." .. name)
	end
end

local function require_custom_dir()
	local home = os.getenv("HOME") or ""
	local custom_dir = home .. "/.config/hypr/config/custom"
	-- Quoted path + sorted output: deterministic load order, safe with
	-- spaces in $HOME. Keep custom modules self-contained regardless.
	local handle = io.popen('ls -1 -- "' .. custom_dir .. '" 2>/dev/null | sort')

	if not handle then
		return
	end

	for file in handle:lines() do
		local module = file:match("^(.*)%.lua$")

		if module then
			require("config.custom." .. module)
		end
	end

	handle:close()
end

-- Overlays written by quickshell's Settings panel (Input, Keybindings, animations). They are
-- applied after the modules so a save wins, and before custom/ so mooi's own keys and look keep
-- the last word. Missing files are skipped; a broken one is reported and the rest still loads.
local function require_overlays()
	local home = os.getenv("HOME") or ""
	for _, name in ipairs({ "user-input", "user-keybinds", "user-animations" }) do
		local path = home .. "/.config/hypr/config/" .. name .. ".lua"
		local file = io.open(path, "r")

		if file then
			file:close()
			local ok, err = pcall(require, "config." .. name)

			if not ok then
				print("[hypr] " .. name .. " not applied: " .. tostring(err))
			end
		end
	end
end

require_all({
	"animations",
	"bind",
	"decoration",
	"device",
	"env",
	"exec",
	"general",
	"gesture",
	"input",
	"layerrule",
	"layouts",
	"misc",
	"monitor",
	"windowrule",
	"workspace",
})

require_overlays()
require_custom_dir()
