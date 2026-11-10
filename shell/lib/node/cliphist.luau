-- The node's clipboard history (D246): the lines `cliphist list` prints, read as entries with a kind and
-- a label, and the argv that decodes one. Pure: it reads text and answers tables, and runs nothing itself.

local M = {}

local function trim(s)
    return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

-- a text preview: one line, no runs of space, cut to 80 characters with an ellipsis
local function text_preview(body)
    local s = trim((body:gsub("%s+", " ")))
    if #s > 80 then
        -- cut on a character's first byte, never inside one (an accent or an emoji split in two shows as garbage)
        local cut = 77
        while cut > 1 and (s:byte(cut + 1) or 0) >= 0x80 and (s:byte(cut + 1) or 0) < 0xC0 do cut = cut - 1 end
        s = s:sub(1, cut) .. "…"
    end
    return s
end

-- the size and, for an image, the format and dimensions in a cliphist binary line
local function binary(body)
    local rest = body:match("^%[%[ binary data%s+(.-)%s*%]%]%s*$")
        or body:match("^%[%[ binary data%s*(.*)$")
    if not rest then return nil end
    local num, unit = rest:match("(%d+[%.,]?%d*)%s*(%a+)")
    local fmt, w, h = rest:match("(%a+)%s+(%d+)x(%d+)")
    local label
    if fmt and w and h then
        label = "Image · " .. w .. "×" .. h .. " · " .. fmt:upper()
    elseif num and unit then
        label = "Binary · " .. num .. " " .. unit
    else
        label = "Binary"
    end
    return { kind = fmt and w and h and "image" or "binary", label = label }
end

-- the clipboard's entries, newest first as cliphist prints them; ids are digits only
function M.parse(text, limit)
    local out = {}
    if type(text) ~= "string" then return out end
    local n = math.floor(tonumber(limit) or 12)
    if n <= 0 then return out end
    for line in text:gmatch("[^\r\n]+") do
        local id, body = line:match("^(%d+)\t(.*)$")
        if id then
            body = trim(body)
            if body ~= "" then
                local b = binary(body)
                if b then
                    out[#out + 1] = { id = id, preview = body, kind = b.kind, label = b.label }
                else
                    local preview = text_preview(body)
                    if preview ~= "" then
                        out[#out + 1] = { id = id, preview = preview, kind = "text", label = preview }
                    end
                end
                if #out >= n then break end
            end
        end
    end
    return out
end

-- the argv that decodes one entry; nil unless the id is digits only
function M.decode_args(id)
    local s = type(id) == "number" and tostring(id) or id
    if type(s) ~= "string" or not s:match("^%d+$") then return nil end
    return { "cliphist", "decode", s }
end

return M
