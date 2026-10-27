-- The modules' own islands (D97): what each reads, only while it is open, and what its buttons
-- do. The scene draws them (shell/mooi.plm, the *_island groups, in the kit of ui/island.plm);
-- parsing is pure and tested (lib/calendar, lib/stats, lib/forecast). Nothing here runs while
-- every island is closed.

local calendar = require("lib/calendar")

return function(ctx)
    -- ── The clock: what it shows (clock.view), a right press for the next ───
    local VIEWS = { "full", "time", "seconds" }
    on("clock_next", function()
        local s = ctx.settings()
        local i = 1
        for k, v in ipairs(VIEWS) do if v == s.clock.view then i = k end end
        s.clock.view = VIEWS[i % #VIEWS + 1]
        fact.clock_view = i % #VIEWS
        ctx.save()
    end)

    -- ── The calendar ─────────────────────────────────────────
    local cal = { y = 0, m = 0 }
    local function today()
        return { y = tonumber(os.date("%Y")), m = tonumber(os.date("%m")), d = tonumber(os.date("%d")) }
    end
    local function show_month()
        local t = today()
        local month = calendar.month(cal.y, cal.m, t)
        local rows = {}
        for i, c in ipairs(month.cells) do
            rows[i] = { n = i - 1, day = c.day, cur = c.cur, today = c.today, weekend = c.weekend }
        end
        model.cal = rows
        text.cal_title = month.title
        local home = cal.y == t.y and cal.m == t.m
        fact.cal_home = home
        text.cal_sub = home and string.format("Week %d · %s", calendar.iso_week(t.y, t.m, t.d), os.date("%A"))
                            or string.format("%+d month%s", (cal.y - t.y) * 12 + (cal.m - t.m),
                                             math.abs((cal.y - t.y) * 12 + (cal.m - t.m)) == 1 and "" or "s")
    end
    on("cal_shift", function(v)
        local n = math.floor(tonumber(v) or 1)
        if n == 1 then local t = today(); cal.y, cal.m = t.y, t.m
        else cal.y, cal.m = calendar.shift(cal.y, cal.m, n == 0 and -1 or 1) end
        show_month()
    end)
    on("fact:open", function(v)
        if v == "calendar" then local t = today(); cal.y, cal.m = t.y, t.m; show_month() end
    end)
end
