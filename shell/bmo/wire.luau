-- BMO's wire: how a conversation with him gets across to the side notch, and the answer back.
--
-- The two are separate programs and `pleamar --say` takes its words on one line, split at the
-- spaces: a question is joined into the command and a reply into another. Flattening whitespace
-- was not enough — a quote, a backslash, a brace, a newline or an emoji in what you typed or in
-- what Claude said could end a word early and corrupt the rest of the command (found 2026-10-30).
--
-- So the words travel as one token and nothing else: the message's bytes (UTF-8, whatever it
-- holds) in URL-safe base64 without padding (RFC 4648 §5, `A-Z a-z 0-9 - _`). No space, semicolon,
-- brace, quote or backslash is in that alphabet, so the token is one word whatever the message is;
-- an empty message is `-` (no encoded message is one character long, so it cannot be confused).
-- `ask`/`say` build the order, `asked`/`said` read it back: both sides use these five, and only
-- these, so there is one protocol and not two.
--
-- Luau, pure: no timers, no facts, no system (tests/unit/run.lua runs it under Lua 5.4).

local M = {}

local ALPHABET = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_"
local VALUE = {}
for i = 1, #ALPHABET do VALUE[ALPHABET:sub(i, i)] = i - 1 end

-- What an empty message is, on the wire.
M.EMPTY = "-"

-- The message as one word. Bytes, not characters: UTF-8 passes through untouched, and so do
-- newlines, tabs and anything else a message may hold.
function M.encode(text)
    local s = tostring(text == nil and "" or text)
    if s == "" then return M.EMPTY end
    local out = {}
    for i = 1, #s, 3 do
        local a, b, c = s:byte(i), s:byte(i + 1), s:byte(i + 2)
        local n = a * 65536 + (b or 0) * 256 + (c or 0)
        local c1 = math.floor(n / 262144) % 64
        local c2 = math.floor(n / 4096) % 64
        local c3 = math.floor(n / 64) % 64
        local c4 = n % 64
        out[#out + 1] = ALPHABET:sub(c1 + 1, c1 + 1) .. ALPHABET:sub(c2 + 1, c2 + 1)
        if c then
            out[#out + 1] = ALPHABET:sub(c3 + 1, c3 + 1) .. ALPHABET:sub(c4 + 1, c4 + 1)
        elseif b then
            out[#out + 1] = ALPHABET:sub(c3 + 1, c3 + 1)
        end
    end
    return table.concat(out)
end

-- The message back. Anything outside the alphabet is skipped rather than refused: a token that
-- lost a character in a log still says as much of the message as survived.
function M.decode(token)
    local t = tostring(token == nil and "" or token)
    if t == "" or t == M.EMPTY then return "" end
    local acc, bits, out = 0, 0, {}
    for i = 1, #t do
        local v = VALUE[t:sub(i, i)]
        if v then
            acc = acc * 64 + v
            bits = bits + 6
            if bits >= 8 then
                bits = bits - 8
                local byte = math.floor(acc / (2 ^ bits)) % 256
                out[#out + 1] = string.char(byte)
                acc = acc % (2 ^ bits)
            end
        end
    end
    return table.concat(out)
end

-- ── The two orders, and the two readings ────────────────────
-- BMO → the side notch: the question goes in `nb_q` (mooi-notch.plm) and `nt_bmo_q` says it arrived.
function M.ask(question) return "text nb_q " .. M.encode(question) end
-- The side notch → BMO: the answer goes in `bmo_line` (bmo.plm) and `speak` says it arrived.
function M.say(answer) return "text bmo_line " .. M.encode(answer) end
-- What arrived, at each end (`text` is the scene's texts, read by name).
function M.asked(text) return M.decode(type(text) == "table" and text.nb_q or nil) end
function M.said(text) return M.decode(type(text) == "table" and text.bmo_line or nil) end

return M
