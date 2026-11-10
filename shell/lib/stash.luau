-- Stash (D54): the little box on the left edge. Pure, so tests/unit runs it under plain
-- Lua 5.4 (written in the subset Lua 5.4 and Luau share); shell/stash.luau owns the folder,
-- the copies and the scene's rows.
--
-- An item is { id, kind, name, detail, url, time, src, poster, folder }: the button opens
-- `url` (a link, a copied file in the stash folder, or a piece of text), `src` is where a file
-- came from, `poster` a picture made for a video or a song's cover, `folder` the folder it was
-- put in (0 or nil: the root). Kinds: 0 link · 1 image · 2 video · 3 file · 4 text · 5 audio.
-- A folder is { id, name, time }, one level deep: a folder holds items, never another folder,
-- which is all that keeping a few kinds of thing apart needs. Nothing here touches the disk:
-- it says what an item is and where it belongs, which is all the tests and the rows need.

local M = {}

M.MAX = 60               -- how many are kept; the oldest fall off
M.ROW_MAX = 5            -- rows the panel shows; the rest wait in the file
M.FOLDER_MAX = 5         -- how many folders the panel offers room for
M.NAME_MAX = 64          -- one line of a name
M.SRC_MAX = 4096         -- a path or address as long as the system can hold

local IMAGE = { png = true, jpg = true, jpeg = true, jfif = true, gif = true, webp = true,
                avif = true, apng = true, jxl = true, bmp = true, svg = true, ico = true,
                tif = true, tiff = true, heic = true, heif = true }
local VIDEO = { mp4 = true, mkv = true, webm = true, mov = true, avi = true, m4v = true,
                mpg = true, mpeg = true, ogv = true, ts = true, m2ts = true, flv = true,
                wmv = true, vob = true, mts = true, mxf = true, asf = true, f4v = true,
                ["3gp"] = true, ["3g2"] = true, divx = true, rmvb = true }
local AUDIO = { mp3 = true, m4a = true, m4b = true, aac = true, flac = true, ogg = true,
                oga = true, opus = true, wav = true, wma = true, aiff = true, aif = true,
                alac = true, mka = true, mid = true, midi = true, amr = true, ac3 = true,
                dts = true, ape = true, mp2 = true, spx = true, wv = true, ra = true }

-- Cut at `n`, never in the middle of a character: back off to the start of one, then mark it.
local function cut(s, n)
    if #s <= n then return s end
    local i = n
    while i > 0 and string.byte(s, i + 1) and string.byte(s, i + 1) >= 0x80 and string.byte(s, i + 1) < 0xC0 do i = i - 1 end
    return string.sub(s, 1, i) .. "…"
end

-- One line, whitespace runs a space, cut.
local function one_line(s, n)
    if type(s) ~= "string" then return "" end
    s = string.gsub(s, "%s+", " ")
    s = string.gsub(string.gsub(s, "^ ", ""), " $", "")
    return cut(s, n or M.NAME_MAX)
end

function M.basename(path)
    if type(path) ~= "string" then return "" end
    local p = string.gsub(path, "/+$", "")
    return string.match(p, "([^/]+)$") or p
end

-- A file:// URI as the path it names, with its %xx escapes read back. Anything else is
-- returned as it is (trimmed).
function M.path_of(s)
    if type(s) ~= "string" then return "" end
    s = string.gsub(string.gsub(s, "^%s+", ""), "%s+$", "")
    if string.sub(s, 1, 7) ~= "file://" then return s end
    local p = string.sub(s, 8)
    p = string.gsub(p, "%%(%x%x)", function(h) return string.char(tonumber(h, 16)) end)
    return p
end

function M.is_url(s)
    return type(s) == "string" and string.match(s, "^%a[%w+.-]*://") ~= nil
end

-- What a dropped string is: a link, an image, a video, another file, or text.
function M.kind_of(s)
    if type(s) ~= "string" or s == "" then return 4 end
    if string.match(s, "^https?://") or string.match(s, "^ftp://") or string.match(s, "^mailto:") then return 0 end
    local path = string.match(s, "^[^?#]*") or s
    local ext = string.match(path, "%.([%w]+)$")
    ext = string.lower(ext or "")
    if IMAGE[ext] then return 1 end
    if VIDEO[ext] then return 2 end
    if AUDIO[ext] then return 5 end
    if string.sub(s, 1, 1) == "/" or string.sub(s, 1, 2) == "./" or string.sub(s, 1, 2) == "~/" or M.is_url(s) then return 3 end
    return 4
end

function M.extension(s)
    local path = string.match(s or "", "^[^?#]*") or ""
    return string.lower(string.match(path, "%.([%w]+)$") or "")
end

-- A name and a detail line for what was dropped. The link is a host and its path; a file is
-- its own name and its extension; text is its first line.
function M.describe(s, kind)
    kind = kind or M.kind_of(s)
    if kind == 0 then
        local host = string.match(s, "^%a[%w+.-]*://([^/]+)") or s
        host = string.gsub(host, "^www%.", "")
        local path = string.match(s, "^%a[%w+.-]*://[^/]+(/.*)$") or ""
        if path == "" or path == "/" then return one_line(host, M.NAME_MAX), "LINK" end
        return one_line(host, M.NAME_MAX), one_line(path, 60)
    elseif kind == 4 then
        return one_line(s, M.NAME_MAX), "TEXT"
    else
        local name = M.basename(s)
        if name == "" then name = "item" end
        local ext = M.extension(s)
        local name_for = { [1] = "IMAGE", [2] = "VIDEO", [3] = "FILE", [5] = "AUDIO" }
        local label = ext ~= "" and string.upper(ext) or (name_for[kind] or "FILE")
        return one_line(name, M.NAME_MAX), label
    end
end

-- A file name safe for the stash folder: letters, digits, `-`, `_`, `.` and spaces (which
-- become `_`), the rest one `_`; never empty, never a hidden file, never too long.
function M.safe_name(s)
    s = type(s) == "string" and s or ""
    s = string.gsub(s, "[^%w%-%._ \128-\255]", "_")
    s = string.gsub(s, "%s+", "_")
    s = string.gsub(s, "^%.+", "")
    if s == "" then s = "item" end
    return cut(s, 80)
end

-- The order every list is kept in: newest first, then the higher id.
local function before(a, b)
    if a.time ~= b.time then return a.time > b.time end
    return a.id > b.id
end
M.before = before

function M.find(list, id)
    for _, it in ipairs(list or {}) do if it.id == id then return it end end
    return nil
end

-- The item a file came from, so the same file dropped twice is one item.
function M.find_src(list, src)
    for _, it in ipairs(list or {}) do if it.src == src and src ~= "" then return it end end
    return nil
end

function M.find_url(list, url)
    for _, it in ipairs(list or {}) do if it.url == url and url ~= "" then return it end end
    return nil
end

-- Move an item to the top: it was dropped again, or opened.
function M.bump(list, item, now)
    if type(item) ~= "table" then return list, nil end
    item.time = math.floor(tonumber(now) or item.time or 0)
    table.sort(list, before)
    return list, item
end

-- Add an item (newest first). Nothing without a url is an item: the list comes back with nil.
function M.add(list, item, now)
    list = list or {}
    if type(item) ~= "table" then return list, nil end
    local url = type(item.url) == "string" and item.url or ""
    if url == "" then return list, nil end
    local id = 0
    for _, it in ipairs(list) do if it.id > id then id = it.id end end
    local kind = math.floor(tonumber(item.kind) or 4)
    if kind < 0 or kind > 5 then kind = 4 end
    local name, detail = item.name, item.detail
    if type(name) ~= "string" or name == "" then name, detail = M.describe(url, kind) end
    local out = { id = id + 1, kind = kind, name = one_line(name, M.NAME_MAX),
                  detail = type(detail) == "string" and one_line(detail, 60) or "",
                  url = cut(url, M.SRC_MAX), time = math.floor(tonumber(now) or 0) }
    if type(item.src) == "string" and item.src ~= "" then out.src = cut(item.src, M.SRC_MAX) end
    if type(item.poster) == "string" and item.poster ~= "" then out.poster = item.poster end
    local folder = math.floor(tonumber(item.folder) or 0)
    if folder > 0 then out.folder = folder end
    table.insert(list, 1, out)
    table.sort(list, before)
    while #list > M.MAX do table.remove(list) end
    return list, out
end

-- Remove one item; says whether it was there.
function M.remove(list, id)
    for i, it in ipairs(list or {}) do
        if it.id == id then table.remove(list, i); return list, it end
    end
    return list, nil
end

-- ── Folders (one level) ──────────────────────────────────────────────
-- A name as a folder chip says it: one line, cut, and never empty.
function M.folder_label(s)
    local n = one_line(s, 16)
    if n == "" then n = "FOLDER" end
    return n
end

function M.folder_find(folders, id)
    for _, f in ipairs(folders or {}) do if f.id == id then return f end end
    return nil
end

-- A new folder at the end of the row, an id of its own, capped. Anything without a name is
-- still a folder (the scene says so first), it just says FOLDER.
function M.folder_add(folders, name, now)
    folders = folders or {}
    if #folders >= M.FOLDER_MAX then return folders, nil end
    local id = 0
    for _, f in ipairs(folders) do if f.id > id then id = f.id end end
    local out = { id = id + 1, name = M.folder_label(name), time = math.floor(tonumber(now) or 0) }
    folders[#folders + 1] = out
    return folders, out
end

-- A folder taken away: its items are not, they go back to the root.
function M.folder_remove(folders, items, id)
    local gone
    for i, f in ipairs(folders or {}) do
        if f.id == id then gone = table.remove(folders, i); break end
    end
    if gone then
        for _, it in ipairs(items or {}) do if it.folder == id then it.folder = nil end end
    end
    return folders, gone
end

-- What a folder holds, and the ones in it: the root (0 or nil) is everything that was never
-- put anywhere.
function M.folder_count(items, id)
    id = math.floor(tonumber(id) or 0)
    local n = 0
    for _, it in ipairs(items or {}) do if (it.folder or 0) == id then n = n + 1 end end
    return n
end

function M.in_folder(items, id)
    id = math.floor(tonumber(id) or 0)
    local out = {}
    for _, it in ipairs(items or {}) do if (it.folder or 0) == id then out[#out + 1] = it end end
    return out
end

-- Where an item goes when its tray is pressed: the first folder, the next one after
-- where it is, and home again after the last. Folders are few and named, so a press that
-- walks them is quicker than a menu; the row says where it is, and the panel where it goes.
function M.folder_next(folders, id)
    local at = 0
    for i, f in ipairs(folders or {}) do if f.id == id then at = i end end
    local next = (folders or {})[at + 1]
    return next and next.id or 0
end

-- An item put in a folder (0 sends it back to the root); says whether it was there.
function M.move(items, id, folder)
    local it = M.find(items, id)
    if not it then return items, nil end
    folder = math.floor(tonumber(folder) or 0)
    if folder > 0 then it.folder = folder else it.folder = nil end
    it.time = it.time or 0
    return items, it
end

-- How long ago, for a row: seconds from `now`, small and quiet.
function M.ago(now, t)
    local d = math.floor((tonumber(now) or 0) - (tonumber(t) or 0))
    if d < 60 then return "now" end
    if d < 3600 then return math.floor(d / 60) .. "m" end
    if d < 86400 then return math.floor(d / 3600) .. "h" end
    if d < 2419200 then return math.floor(d / 86400) .. "d" end
    return math.floor(d / 604800) .. "w"
end

-- How long a video or a song runs, as its row says it: `3:41`, and `1:02:03` past the hour.
-- Anything that is not a length is `0:00`, so a row is never given nonsense.
function M.length(secs)
    local s = math.floor(tonumber(secs) or 0)
    if s < 0 then s = 0 end
    local m = math.floor(s / 60)
    local h = math.floor(m / 60)
    if h > 0 then return string.format("%d:%02d:%02d", h, m % 60, s % 60) end
    return string.format("%d:%02d", m, s % 60)
end

-- The rows the panel shows: the page brought into range, and each row's place on it. A
-- picture is the video's poster, a song's cover, or an image's own file; otherwise the row
-- draws a glyph.
-- The box's filter (the chips): 0 everything, 1 pictures and videos, 2 links, 3 files and songs,
-- 4 text; and a search, by name and detail, case-insensitive. Pure: the list is not changed.
M.KINDS = { [1] = { [1] = true, [2] = true }, [2] = { [0] = true }, [3] = { [3] = true, [5] = true }, [4] = { [4] = true } }
function M.filter(list, kind, query)
    local want = M.KINDS[tonumber(kind) or 0]
    local q = string.lower(tostring(query or ""):gsub("^%s+", ""):gsub("%s+$", ""))
    if not want and q == "" then return list or {} end
    local out = {}
    for _, it in ipairs(list or {}) do
        local ok = not want or want[it.kind] == true
        if ok and q ~= "" then
            local hay = string.lower(tostring(it.name or "") .. " " .. tostring(it.detail or "") .. " " .. tostring(it.url or ""))
            ok = string.find(hay, q, 1, true) ~= nil
        end
        if ok then out[#out + 1] = it end
    end
    return out
end

function M.page(list, page, now, size, names)
    size = size or M.ROW_MAX
    local total = #(list or {})
    local pages = math.max(1, math.ceil(total / size))
    page = math.floor(tonumber(page) or 0)
    if page < 0 then page = 0 end
    if page > pages - 1 then page = pages - 1 end
    local from = page * size + 1
    local to = math.min(from + size - 1, total)
    local rows = {}
    for i = from, to do
        local it = list[i]
        local fname = names and it.folder and names[it.folder]
        local detail = (fname and fname ~= "" and (fname .. " · ") or "") .. (it.detail ~= "" and (it.detail .. " · ") or "")
        local picture = it.poster or (it.kind == 1 and it.url or "")
        rows[#rows + 1] = { id = it.id, kind = it.kind, name = it.name,
                            sub = detail .. M.ago(now, it.time), n = i - from,
                            url = it.url, picture = picture, pictured = picture ~= "" }
    end
    return rows, page, total > 0 and from or 0, to, total, pages
end

-- The file read back: whatever is not an item is dropped, ids are made unique (a repeated
-- or missing one gets a new number, so nothing is lost), newest first, capped. A file
-- written by an older mooi, or by hand, never raises. It answers the items and the folders:
-- an item whose folder is not in the file is one that was never put anywhere.
function M.decode(t)
    local out = {}
    local seen = {}
    local loose = {}
    if type(t) ~= "table" then return out, {} end
    local rows = type(t.items) == "table" and t.items or t
    if type(rows) ~= "table" then return out, {} end
    for _, r in ipairs(rows) do
        if type(r) == "table" and type(r.url) == "string" and r.url ~= "" then
            local id = tonumber(r.id)
            local kind = math.floor(tonumber(r.kind) or 4)
            if kind < 0 or kind > 5 then kind = 4 end
            local name = one_line(r.name, M.NAME_MAX)
            local detail = one_line(r.detail, 60)
            if name == "" then name, detail = M.describe(r.url, kind) end
            local it = { id = id, kind = kind, name = name, detail = detail, url = cut(r.url, M.SRC_MAX),
                         time = math.floor(tonumber(r.time) or 0) }
            if type(r.src) == "string" and r.src ~= "" then it.src = cut(r.src, M.SRC_MAX) end
            if type(r.poster) == "string" and r.poster ~= "" then it.poster = r.poster end
            local folder = math.floor(tonumber(r.folder) or 0)
            if folder > 0 then it.folder = folder end
            if id and id >= 1 and id == math.floor(id) and not seen[id] then
                seen[id] = true
                out[#out + 1] = it
            else
                loose[#loose + 1] = it
            end
        end
    end
    local max = 0
    for id in pairs(seen) do if id > max then max = id end end
    for _, it in ipairs(loose) do
        max = max + 1
        it.id = max
        out[#out + 1] = it
    end
    table.sort(out, before)
    while #out > M.MAX do table.remove(out) end
    -- The folders, in the order they were made, with ids of their own; whatever is not one is
    -- dropped, and an item that named a folder that is not there goes back to the root.
    local folders, have = {}, {}
    local declared = type(t.folders) == "table" and t.folders or {}
    for _, f in ipairs(declared) do
        if #folders >= M.FOLDER_MAX then break end
        local id = type(f) == "table" and math.floor(tonumber(f.id) or 0) or 0
        if id >= 1 and not have[id] then
            have[id] = true
            folders[#folders + 1] = { id = id, name = M.folder_label(f.name), time = math.floor(tonumber(f.time) or 0) }
        end
    end
    for _, it in ipairs(out) do
        if it.folder and not have[it.folder] then it.folder = nil end
    end
    return out, folders
end

-- What came in on the panel's inbox (D279): plain strings are things to keep (the clipboard's
-- text, a path, an address), a table is an op on the box (`clear`, or `remove` one item by id).
-- Anything else is dropped. The bar decides what a string is (lib/stash.kind_of decides the kind).
function M.inbox(box)
    local out = {}
    for _, e in ipairs(type(box) == "table" and box or {}) do
        if type(e) == "string" and e ~= "" then
            out[#out + 1] = { op = "take", text = e }
        elseif type(e) == "table" then
            local op = tostring(e.op or "")
            local id = math.floor(tonumber(e.id) or 0)
            if op == "clear" then out[#out + 1] = { op = "clear" }
            elseif op == "remove" and id >= 1 then out[#out + 1] = { op = "remove", id = id } end
        end
    end
    return out
end

-- The glyph a row wears: a link, a picture, a film, a file, text, a song; a file is the fallback.
local GLYPHS = { "󰌷", "󰋩", "󰕧", "󰈔", "󰦨", "󰎆" }
function M.glyph(kind)
    return GLYPHS[math.floor(tonumber(kind) or -1) + 1] or GLYPHS[4]
end

-- What is written to the file.
function M.encode(list, folders)
    local rows = {}
    for _, it in ipairs(list or {}) do
        rows[#rows + 1] = { id = it.id, kind = it.kind, name = it.name, detail = it.detail,
                            url = it.url, time = it.time, src = it.src, poster = it.poster,
                            folder = it.folder }
    end
    local fs = {}
    for _, f in ipairs(folders or {}) do
        fs[#fs + 1] = { id = f.id, name = f.name, time = f.time }
    end
    return { version = 1, items = rows, folders = fs }
end

return M
