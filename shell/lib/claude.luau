-- Claude in the shell (D106): the `claude` command (Claude Code, signed in as you) asked a question
-- and read back as it answers. Pure, so tests/unit runs it: the arguments, and what each line of
-- `--output-format stream-json` means. The notch's chat and BMO both ask through it.
--
-- Asked lean: no tools (it can say things, never do them), no plugins' hooks, no MCP servers, no
-- skills, no CLAUDE.md (it runs in the data folder) — a desktop chat, not a coding session.

local M = {}

M.PERSONAS = {
    chat = "You are Claude, answering inside mooi, the user's Linux desktop shell (Hyprland), from a small chat panel. "
        .. "Be warm, direct and brief: a few sentences or a short list; no headings; no tables. "
        .. "You cannot run commands or open files here; say what to do instead when it helps.",
    bmo = "You are BMO, the little living video game console from Adventure Time, living on the user's desktop. "
        .. "Answer as BMO: cheerful, curious, a little odd, speaking of yourself in the third person now and then. "
        .. "BMO loves jokes and puns: asked for one, tell a short, silly, kind joke; now and then slip a little pun in. "
        .. "One or two short sentences only — it has to fit in BMO's speech bubble.",
}

-- ── When Claude cannot answer (no credits, offline, signed out): a free model through opencode ──
-- (D143) `opencode run` with its free models, tried in turn; asked in the same persona, with the last
-- few turns written into the question (it keeps no session of ours). Run in an empty folder and
-- without --auto, so it can only talk: nothing it would need permission for is approved.
M.FALLBACK_MODELS = { "opencode/deepseek-v4.1-flash-free", "opencode/big-pickle", "opencode/beam-free" }

function M.fallback_args(prompt, persona, model, recent)
    local lines = { M.PERSONAS[persona or "chat"] or M.PERSONAS.chat,
                    "Answer in plain words only; do not use tools, files or commands." }
    if type(recent) == "table" and #recent > 0 then
        lines[#lines + 1] = "The conversation so far:"
        for _, t in ipairs(recent) do lines[#lines + 1] = tostring(t.who) .. ": " .. tostring(t.text) end
    end
    lines[#lines + 1] = "Now answer this: " .. tostring(prompt or "")
    return { "run", "-m", model or M.FALLBACK_MODELS[1], table.concat(lines, "\n") }
end

-- What `opencode run` printed, as the answer: its colours and its "> agent · model" line gone; nil
-- when it said nothing or only an error.
function M.fallback_text(out)
    local s = tostring(out or ""):gsub("\27%[[%d;]*m", "")
    local keep = {}
    for line in (s .. "\n"):gmatch("(.-)\n") do
        if not line:match("^%s*> ") then keep[#keep + 1] = line end
    end
    local t = table.concat(keep, "\n"):gsub("^%s+", ""):gsub("%s+$", "")
    if t == "" or t:match("^Error:") then return nil end
    return t
end

-- The arguments for one question. `session`: a previous answer's session, to go on from it.
function M.args(prompt, opts)
    opts = opts or {}
    local a = { "-p", tostring(prompt or ""), "--output-format", "stream-json", "--verbose", "--include-partial-messages",
                "--tools", "", "--disable-slash-commands", "--strict-mcp-config", "--setting-sources", "user",
                "--settings", '{"disableAllHooks": true}',
                "--append-system-prompt", M.PERSONAS[opts.persona or "chat"] or M.PERSONAS.chat }
    if type(opts.session) == "string" and opts.session:match("^[%w%-]+$") then
        a[#a + 1] = "--resume"; a[#a + 1] = opts.session
    end
    if type(opts.model) == "string" and opts.model:match("^[%w%-%.]+$") then
        a[#a + 1] = "--model"; a[#a + 1] = opts.model
    end
    return a
end

-- What one line of the stream says: { delta = text } as the answer grows, { done = true, text,
-- session, cost } at the end, { error = why } when it went wrong, or nil for everything else.
function M.read(line, decode)
    local ok, o = pcall(decode, line or "")
    if not ok or type(o) ~= "table" then return nil end
    if o.type == "stream_event" and type(o.event) == "table" then
        local e = o.event
        if e.type == "content_block_delta" and type(e.delta) == "table" and type(e.delta.text) == "string" then
            return { delta = e.delta.text }
        end
        return nil
    end
    if o.type == "result" then
        if o.is_error or o.subtype ~= "success" then
            return { error = tostring(o.result or o.subtype or "Claude could not answer"), session = o.session_id }
        end
        return { done = true, text = tostring(o.result or ""), session = o.session_id, cost = tonumber(o.total_cost_usd) }
    end
    return nil
end

-- A reply as lines that fit a panel `cols` characters wide (words kept whole, blank lines kept).
function M.wrap(text, cols)
    cols = math.max(8, tonumber(cols) or 48)
    local out = {}
    for para in (tostring(text or "") .. "\n"):gmatch("(.-)\n") do
        if para == "" then out[#out + 1] = ""
        else
            local line = ""
            for word in para:gmatch("%S+") do
                if #line == 0 then line = word
                elseif #line + 1 + #word <= cols then line = line .. " " .. word
                else out[#out + 1] = line; line = word end
            end
            if line ~= "" then out[#out + 1] = line end
        end
    end
    while #out > 0 and out[#out] == "" do out[#out] = nil end
    return out
end

return M
