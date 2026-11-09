-- BMO's hands (D209): the small, explicit vocabulary between what he says and what the machine does.
-- Pure: the bar runs the commands. Every action is checked against its tier and the home folder here,
-- so a model cannot widen its own permissions. No sudo, no credentials, no paths outside `$HOME`.

local M = {}

M.LOOK = { search_files = true, read_file = true, get_context = true, get_setting = true,
           herdr_list = true, herdr_read = true, fetch_url = true }
M.DO = { open_app = true, open_url = true, focus_window = true, media = true, notify = true,
         set_setting = true }
M.CHANGE = { write_file = true, delete_file = true, run_command = true }

function M.tier(kind)
    if M.LOOK[kind] then return "look" end
    if M.DO[kind] then return "do" end
    if M.CHANGE[kind] then return "change" end
end

-- A reply may be plain words, or one JSON object `{ "say": "...", "action": { "kind": ..., ... } }`.
-- Returns the words to show and the action (or nil). A malformed object is words, never a crash.
function M.parse(reply, decode)
    local text = tostring(reply or "")
    local body = text:match("^%s*(%b{})%s*$")
    if not body or type(decode) ~= "function" then return text, nil end
    local ok, doc = pcall(decode, body)
    if not ok or type(doc) ~= "table" or type(doc.action) ~= "table" then return text, nil end
    local say = type(doc.say) == "string" and doc.say or ""
    return say, doc.action
end

local function under(path, home)
    if type(path) ~= "string" or path == "" then return false end
    path = path:gsub("/+$", "")
    home = tostring(home or ""):gsub("/+$", "")
    if home == "" then return false end
    return path == home or path:sub(1, #home + 1) == home .. "/"
end

local SECRET = { "%.ssh/", "%.gnupg/", "%.config/herdr/herdr%.sock", "id_rsa", "id_ed25519",
                 "credentials", "%.env$", "%.pem$", "%.key$" }

-- Returns ok, reason. `home` is the user's home; `trusted` raises Do to no-confirm (Change still asks).
function M.check(action, home)
    if type(action) ~= "table" or type(action.kind) ~= "string" then return false, "no action" end
    local tier = M.tier(action.kind)
    if not tier then return false, "unknown action" end
    if action.kind == "run_command" then
        local cmd = tostring(action.command or "")
        if cmd:match("^%s*sudo") or cmd:match("[;&|]%s*sudo") then return false, "no sudo" end
        if cmd:match("rm%s+%-[rR]f%s+/%s*$") or cmd:match("mkfs") or cmd:match("dd%s+if=") then
            return false, "refused"
        end
    end
    for _, key in ipairs({ "path", "file", "dir" }) do
        if action[key] ~= nil then
            if not under(action[key], home) then return false, "outside home" end
            local low = tostring(action[key]):lower()
            for _, pat in ipairs(SECRET) do if low:find(pat) then return false, "secret path" end end
        end
    end
    return true, tier
end

-- The command a Do action runs (Look actions are read by the bar's own helpers).
function M.command(action)
    if type(action) ~= "table" then return nil end
    if action.kind == "open_url" and type(action.url) == "string" and action.url:match("^https?://") then
        return "xdg-open", { action.url }
    end
    if action.kind == "open_app" and type(action.app) == "string" and action.app:match("^[%w%-%._]+$") then
        return action.app, {}
    end
    if action.kind == "focus_window" and type(action.match) == "string" then
        return "hyprctl", { "dispatch", "focuswindow", action.match }
    end
    if action.kind == "notify" and type(action.text) == "string" then
        return "notify-send", { "BMO", action.text }
    end
    if action.kind == "media" then
        return "playerctl", { action.arg == "next" and "next" or action.arg == "previous" and "previous" or "play-pause" }
    end
    return nil
end

return M
