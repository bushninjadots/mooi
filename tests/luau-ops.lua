-- tests/gate.sh: no logic file uses an operator Luau lacks (`&`, `|`, binary `~`, `<<`, `>>`). Lua 5.4 runs the
-- unit suite and has them all, so only this catches one before Pleamar refuses the file at start.
-- Usage: lua5.4 tests/luau-ops.lua DIR…
local bad = 0
for _, dir in ipairs(arg) do
    local p = io.popen("find '" .. dir:gsub("'", "") .. "' -name '*.luau'")
    for f in p:lines() do
        local n = 0
        for line in io.lines(f) do
            n = n + 1
            local code = line:gsub("\\.", ""):gsub('%b""', '""'):gsub("%b''", "''"):gsub("%-%-.*$", "")
            if code:find("[%w_%)%]]%s*[&|]%s*[%w_%(]") or code:find("<<", 1, true) or code:find(">>", 1, true)
                or code:find("[%w_%)%]]%s*~%s*[^=%s]") then
                io.stderr:write(f .. ":" .. n .. ": an operator Luau does not have: " .. line .. "\n")
                bad = bad + 1
            end
        end
    end
    p:close()
end
os.exit(bad == 0 and 0 or 1)
