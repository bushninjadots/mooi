-- System updates (the bar's updates module): how many are waiting, from pacman's
-- `checkupdates`, the AUR helper's `-Qua` and Flatpak's `remote-ls --updates`, and the one
-- command the module's press runs in a terminal. Pure, so tests/unit runs it.

local M = {}

-- Lines of the form "name old -> new" (checkupdates, paru/yay -Qua); held ones ("[ignored]")
-- are not waiting.
function M.count_pkgs(out)
    local n = 0
    for line in tostring(out or ""):gmatch("[^\n]+") do
        if line:match("^%S+ %S+ %-> %S+") and not line:find("%[ignored%]") then n = n + 1 end
    end
    return n
end

-- Flatpak's application ids, one a line (a header, if any, is not one).
function M.count_apps(out)
    local n = 0
    for line in tostring(out or ""):gmatch("[^\n]+") do
        if line:match("^[%w_%-]+%.[%w_%-%.]+$") then n = n + 1 end
    end
    return n
end

local function plural(n, one, many) return n .. " " .. (n == 1 and one or many) end

-- The total and the words the module's tooltip and notice use.
function M.summary(repo, aur, flat)
    repo, aur, flat = repo or 0, aur or 0, flat or 0
    local total = repo + aur + flat
    if total == 0 then return { total = 0, text = "Up to date" } end
    local parts = { plural(total, "update", "updates") }
    if repo > 0 then parts[#parts + 1] = plural(repo, "package", "packages") end
    if aur > 0 then parts[#parts + 1] = aur .. " AUR" end
    if flat > 0 then parts[#parts + 1] = flat .. " Flatpak" end
    return { total = total, text = table.concat(parts, " · ") }
end

-- Worth a notice: more are waiting than at the last check (not the first check after starting).
function M.should_notify(before, now)
    return before ~= nil and now > before
end

-- The shell line the terminal runs: the AUR helper there is (paru, then yay, else pacman), then
-- Flatpak when it is installed, then it waits so what happened can be read.
function M.command(have)
    have = have or {}
    local steps = {}
    if have.paru then steps[#steps + 1] = "paru -Syu"
    elseif have.yay then steps[#steps + 1] = "yay -Syu"
    else steps[#steps + 1] = "sudo pacman -Syu" end
    if have.flatpak then steps[#steps + 1] = "flatpak update" end
    return table.concat(steps, "; ") .. "; printf '\\n\\033[1mDone. Press Enter to close.\\033[0m'; read _"
end

return M
