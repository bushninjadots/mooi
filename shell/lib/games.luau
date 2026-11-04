-- The games installed on the machine (D156): Steam's — an appmanifest_*.acf in every library its
-- libraryfolders.vdf names — and the desktop's own — the .desktop entries filed under Game. Pure:
-- shell/mooi-notch.luau runs `grep` and `find` and hands this what they printed.

local M = {}

-- A VDF value's escaped backslashes (a library on Windows-formatted media: "D:\\SteamLibrary").
function M.unescape(s)
    return (tostring(s or ""):gsub("\\\\", "\\"))
end

-- Every library Steam knows: its libraryfolders.vdf's "path" values, unescaped, each once.
function M.libraries(vdf)
    local out, seen = {}, {}
    for line in tostring(vdf or ""):gmatch("[^\n]+") do
        local p = line:match('^%s*"path"%s*"(.-)"%s*$')
        if p then
            p = M.unescape(p)
            if p ~= "" and not seen[p] then seen[p] = true; out[#out + 1] = p end
        end
    end
    return out
end

-- The manifests, from one `grep '"(appid|name|installdir)"'` over their files: a new appid starts a
-- new one (the key is first in a manifest). Each { appid, name, installdir }.
function M.manifests(listing)
    local out, cur = {}, nil
    for line in tostring(listing or ""):gmatch("[^\n]+") do
        local k, v = line:match('^%s*"([%w_]+)"%s*"(.-)"%s*$')
        if k == "appid" then
            if cur then out[#out + 1] = cur end
            cur = { appid = v }
        elseif cur and k == "name" then cur.name = v
        elseif cur and k == "installdir" then cur.installdir = v end
    end
    if cur then out[#out + 1] = cur end
    return out
end

-- Proton, the runtimes and the redistributables are manifests too, and they are not games.
function M.is_game(m)
    local name = tostring(m and m.name or "")
    if name == "" or tostring(m and m.appid or ""):match("^%d+$") == nil then return false end
    local low = name:lower()
    return not (low:find("^steam linux runtime") or low:find("^steamworks common redistributables")
             or low:find("^steamworks sdk") or low:find("^steamvr") or low:find("^steam audio")
             or low == "proton" or low:find("^proton "))
end

-- The programs that only start games: a menu entry for one of these is not a game itself.
M.LAUNCHERS = {
    ["steam"] = true, ["net.lutris.Lutris"] = true, ["com.heroicgameslauncher.hgl"] = true,
    ["heroic"] = true, ["com.usebottles.bottles"] = true, ["net.davidotek.pupgui2"] = true,
    ["ru.linux_gaming.PortProton"] = true, ["io.github.Faugus.faugus-launcher"] = true,
    ["com.github.Matoking.protontricks"] = true,
}

-- The .desktop entries `grep -r` printed (its `file:Key=Value` lines), one per file.
function M.desktops(listing)
    local by, order = {}, {}
    for line in tostring(listing or ""):gmatch("[^\n]+") do
        local file, k, v = line:match("^(.-):([%w]+)=(.*)$")
        if file and k then
            local e = by[file]
            if not e then
                e = { id = ((file:match("([^/]+)$") or ""):gsub("%.desktop$", "")), path = file }
                by[file], order[#order + 1] = e, e
            end
            local slot = k == "Name" and "name" or k == "Exec" and "exec" or k == "Categories" and "categories"
                      or k == "Icon" and "icon" or k == "NoDisplay" and "nodisplay" or k == "Hidden" and "hidden"
                      or k == "Terminal" and "terminal"
            if slot and e[slot] == nil then e[slot] = v end
        end
    end
    return order
end

-- Is it a game's menu entry: filed under Game, shown in the menu, not a terminal program, and not
-- one of the launchers above.
function M.is_desktop_game(e)
    if type(e) ~= "table" or tostring(e.name or "") == "" then return false end
    if e.nodisplay == "true" or e.hidden == "true" or e.terminal == "true" then return false end
    if M.LAUNCHERS[e.id] then return false end
    for c in tostring(e.categories or ""):gmatch("[^;]+") do if c == "Game" then return true end end
    return false
end

-- The icons the menus' games ask for, to be looked up by name: its Icon=, else its id, one each.
-- An Icon= that is already a path is not looked up; the entry carries it.
function M.icon_names(listing)
    local out, seen = {}, {}
    for _, e in ipairs(M.desktops(listing)) do
        if M.is_desktop_game(e) then
            local name = tostring(e.icon or e.id or ""):match("^([%w%-%._+]+)$")
            if name and not seen[name] then seen[name] = true; out[#out + 1] = name end
        end
    end
    return out
end

-- The icon files `find` printed, by name: as big as the theme has it (the size in its folder's
-- name — `256x256`, `512x512`, a scalable one — the shorter path when two are the same). Only PNGs:
-- the scene reads pictures, not drawings.
function M.icons(listing)
    local out, score = {}, {}
    for line in tostring(listing or ""):gmatch("[^\n]+") do
        local name = line:match("([^/]+)%.png$")
        if name and name ~= "" then
            local s = tonumber(line:match("/(%d+)x%d+/")) or (line:find("/scalable/") and 4096) or 128
            local was = score[name]
            if not was or s > was or (s == was and #line < #out[name]) then
                score[name], out[name] = s, line
            end
        end
    end
    return out
end

-- The pictures `find` printed (…/<appid>/header.jpg, library_header.jpg, library_600x900.jpg):
-- appid → { path, wide }. A header is drawn as it is; a portrait poster (`wide` false) is cropped
-- to fill the row. A header wins over a poster, whichever is found first.
function M.headers(listing)
    local out = {}
    for line in tostring(listing or ""):gmatch("[^\n]+") do
        local id, name = line:match("/(%d+)/([%w_]+)%.jpg$")
        if id then
            local wide = name == "header" or name == "library_header"
            local cur = out[id]
            if not cur or (wide and not cur.wide) then out[id] = { path = line, wide = wide } end
        end
    end
    return out
end

-- ── The games nothing installed: a folder with a launcher in it ──
-- Steam's are its own; a GOG copy, an extracted repack, or one PortProton or umu runs is a folder
-- somebody put on the disk (~/games, ~/Games, ~/GOG Games, PortProton's prefixes). `find` prints the
-- launchers those roots hold: two levels under a root, deeper inside a PortProton prefix.
M.PREFIX_DIRS = { drive_c = true, dosdevices = true, pfx = true, umu = true, shadercache = true,
                  config_info = true, Modlist_Downloads = true, creation_sync_guard = true }

local function base(p) return (tostring(p or ""):match("([^/]+)$") or "") end
local function folder(p) return (tostring(p or ""):match("^(.*)/[^/]*$") or "") end

local function native(name)
    return name:match("%.sh$") ~= nil or name:match("%.AppImage$") ~= nil
        or name:match("%.x86_64$") ~= nil or name:match("%.run$") ~= nil
end
local function windows(name) return name:match("%.[eE][xX][eE]$") ~= nil end
-- A wine or umu prefix is a machine, not a game: nothing directly in it is the game's own folder.
local function in_prefix(p)
    for seg in tostring(p or ""):gmatch("[^/]+") do if M.PREFIX_DIRS[seg] then return true end end
    return false
end
-- Crash handlers, uninstallers, installers and redistributables sit beside a game's own program.
local function not_program(name)
    local low = name:lower()
    return low:find("unitycrash") ~= nil or low:find("crashhandler") ~= nil or low:find("createdump") ~= nil
        or low:find("elevate") ~= nil or low:find("vcredist") ~= nil or low:find("dxsetup") ~= nil
        or low:match("^unins") ~= nil or low:match("^setup") ~= nil or low:match("^install") ~= nil
end

-- A folder's name as a title: "RimWorld", not "Sandustry-AnkerGames" or "Homeworld [GOG]".
function M.title(name)
    return (tostring(name or ""):gsub("%s*%[[^%]]*%]$", ""):gsub("%s*%(GOG%)$", "")
        :gsub("%-AnkerGames$", ""):gsub("^%s+", ""):gsub("%s+$", ""))
end

-- The games those roots hold, from every launcher `find` printed: a row per folder — where it is
-- (`dir`), the program in it (nil when a native launcher is there for `mooi game` to find itself),
-- and whether PortProton has to run it — by name. A folder holding only an installer is not a game
-- yet, and a prefix's `drive_c` is not one of its games.
M.ICON_NAMES = { ["icon.png"] = true, ["logo.png"] = true, ["game.png"] = true, ["steam_icon.png"] = true }
function M.on_disk(listing)
    local by, order, icons = {}, {}, {}
    local function row(d)
        local r = by[d]
        if not r then r = { dir = d, name = M.title(base(d)) }; by[d], order[#order + 1] = r, r end
        return r
    end
    for line in tostring(listing or ""):gmatch("[^\n]+") do
        local f, d = base(line), folder(line)
        local prefix = line:match("/prefixes/([^/]+)/")
        -- PortProton keeps its games inside a prefix's drive_c, so there only Windows itself is left out
        local skip
        if prefix then skip = line:find("/windows/") ~= nil or line:find("/dosdevices/") ~= nil
        else skip = in_prefix(line) end
        if d ~= "" and not skip then
            if M.ICON_NAMES[f:lower()] then icons[d] = line
            elseif prefix then
                local r = row(d)
                r.name, r.proton = M.title(prefix), true
                if r.exe == nil and windows(f) and not not_program(f) then r.exe = f end
            elseif native(f) and not not_program(f) then
                row(d).native = true
            elseif windows(f) and not not_program(f) then
                local r = row(d)
                if r.exe == nil then r.exe = f end
            end
        end
    end
    local out = {}
    for _, r in ipairs(order) do
        if r.native or r.exe then
            if r.native then r.exe = nil end        -- `mooi game` finds the launcher in the folder
            r.kind = r.proton and "PORTPROTON" or (r.native and "NATIVE" or "WINE")
            r.icon = icons[r.dir]
            out[#out + 1] = r
        end
    end
    table.sort(out, function(a, b) return a.name:lower() < b.name:lower() end)
    return out
end

-- The list the arc walks: Steam's games, the folders on disk, then the desktop's, each by name, one
-- to a name. `headers` is M.headers' map of the pictures Steam keeps, `iconmap` M.icons' of the menus'
-- icons. A row is { name, sub, steam, disk, appid | id | dir, pic, wide, icon, exe, proton }.
function M.collect(manifest_listing, desktop_listing, headers, local_listing, iconmap, max)
    local out, seen = {}, {}
    local function add(row)
        local key = row.name:lower()
        if not seen[key] then seen[key] = true; out[#out + 1] = row end
    end
    for _, m in ipairs(M.manifests(manifest_listing)) do
        if M.is_game(m) then
            local h = headers and headers[m.appid]
            add({ name = m.name, sub = "STEAM · " .. m.appid, steam = true, appid = m.appid,
                  pic = h and h.path or "", wide = h ~= nil and h.wide == true })
        end
    end
    for _, g in ipairs(M.on_disk(local_listing)) do
        add({ name = g.name, sub = "LOCAL · " .. g.kind, steam = false, disk = true, dir = g.dir,
              exe = g.exe, proton = g.proton == true, pic = g.icon or "", wide = false,
              icon = g.icon ~= nil })
    end
    for _, e in ipairs(M.desktops(desktop_listing)) do
        if M.is_desktop_game(e) then
            local want = tostring(e.icon or e.id or "")
            local pic = want:match("^/") and want or (iconmap and iconmap[want] or "")
            add({ name = e.name, sub = "APP · " .. e.id, steam = false, id = e.id, pic = pic, wide = false,
                  icon = pic ~= "" })
        end
    end
    table.sort(out, function(a, b)
        local ra = a.steam and 1 or (a.disk and 2 or 3)
        local rb = b.steam and 1 or (b.disk and 2 or 3)
        if ra ~= rb then return ra < rb end
        return a.name:lower() < b.name:lower()
    end)
    while #out > math.max(1, math.floor(tonumber(max) or 400)) do out[#out] = nil end
    return out
end

-- Only one source: 0 all of them · 1 Steam's · 2 the desktop's · 3 the folders on disk.
function M.filter(list, src)
    src = math.floor(tonumber(src) or 0)
    if src == 0 then return list end
    local out = {}
    for _, g in ipairs(list or {}) do
        local want = src == 1 and g.steam == true or src == 3 and g.disk == true
                  or (src == 2 and not g.steam and not g.disk)
        if want then out[#out + 1] = g end
    end
    return out
end

-- ── The pictures the machine does not have: Steam's store knows a game by its name ──
-- A cache file's name for a game: its title in dashes and a short hash of the title exactly, so two
-- games that read alike keep apart and one game always lands on the same file.
local function norm(s) return (tostring(s or ""):lower():gsub("[^%w]+", "")) end
function M.slug(name)
    local s = tostring(name or "")
    local h = 5381
    for i = 1, #s do h = (h * 33 + s:byte(i)) % 2147483647 end
    local base = (s:lower():gsub("[^%w]+", "-"):gsub("^-", ""):gsub("%-$", ""))
    if #base > 40 then base = (base:sub(1, 40):gsub("%-$", "")) end
    return (base ~= "" and base or "game") .. "-" .. string.format("%06x", h % 0xffffff)
end

function M.urlencode(s)
    return (tostring(s or ""):gsub("[^%w%-%._~]", function(c) return string.format("%%%02X", c:byte()) end))
end

function M.search_url(name)
    return "https://store.steampowered.com/api/storesearch/?cc=us&l=en&term=" .. M.urlencode(name)
end

-- The pictures a store page has, best first: the 616 × 353 capsule, the card's own shape, then its
-- header. No appid, nothing to ask.
function M.art_urls(appid)
    local id = tostring(appid or "")
    if not id:match("^%d+$") then return {} end
    local base = "https://cdn.cloudflare.steamstatic.com/steam/apps/" .. id .. "/"
    return { base .. "capsule_616x353.jpg", base .. "header.jpg" }
end

-- The search's answer's appid for a game, from the `{ name, id }` pairs its items hold: the same
-- title, whatever its case and punctuation, or the store's longer one where ours stops at a colon or
-- a dash ("Hotline Miami 2" is "Hotline Miami 2: Wrong Number"). A name that merely starts the same
-- ("Hydra" and "Hydra Heli 2") is not that game, and is not taken.
function M.appid(items, name)
    local want = norm(name)
    if want == "" then return nil end
    local raw = tostring(name or ""):lower()
    for _, it in ipairs(items or {}) do
        local id = tostring(it and it.id or "")
        local got = tostring(it and it.name or "")
        if id:match("^%d+$") and got ~= "" then
            if norm(got) == want then return id end
            local low = got:lower()
            if #want >= 6 and low:sub(1, #raw) == raw and low:sub(#raw + 1, #raw + 1):match("^[:%-(]") then return id end
        end
    end
    return nil
end

-- The pictures the cache holds, from one `find` over it: `key.jpg` → where it is.
function M.online(listing)
    local out = {}
    for line in tostring(listing or ""):gmatch("[^\n]+") do
        local key = line:match("([^/]+)%.jpg$")
        if key and key ~= "" then out[key] = line end
    end
    return out
end

-- The games the store was already asked about, whatever it answered: `key.json` → true.
function M.asked(listing)
    local out = {}
    for line in tostring(listing or ""):gmatch("[^\n]+") do
        local key = line:match("([^/]+)%.json$")
        if key and key ~= "" then out[key] = true end
    end
    return out
end

-- A row still wants a picture of its own when it has none, only a menu's small icon, or a portrait
-- poster cropped into a card that is not its shape. A header — or a capsule already fetched — is the
-- card's shape and is left alone.
function M.bare(g)
    if type(g) ~= "table" then return false end
    return g.pic == nil or g.pic == "" or g.icon == true or g.wide ~= true
end

-- Every row M.bare still wants one takes the picture the cache holds, drawn as it is: a capsule is
-- already the card's shape. Steam's own header, and a capsule fetched before, keep their place.
function M.dress(rows, art)
    for _, g in ipairs(rows or {}) do
        local p = art and art[M.slug(g.name)]
        if p and M.bare(g) then
            g.pic, g.wide, g.icon, g.online = p, true, false, true
        end
    end
    return rows
end

return M
