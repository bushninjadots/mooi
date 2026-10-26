-- Lumen's logic (the wallpaper studio). One picture at a time, a recipe of numbers, and a
-- cached screen-shaped base that every preview and the final still are cut from. Edits never
-- touch the source: a preview is a new file, and APPLY renders the screen's size and hands it
-- to the wallpaper picker (`qs ipc call wallpaper set`), which draws it and makes the palette.
--
-- The folder is mooi's own (bin/mooi links mooi-wallpaper to it), so wallpapers.json and
-- palette.json are the shell's, and a new wallpaper re-lights this studio too.

local config = require("lib/config")
local ferro = require("lib/ferro")
local W = require("lib/wallpaper")

local HOME = tostring(sys.ask("env", "HOME"))
local CACHE = HOME .. "/.cache/mooi/wallpaper"
local PICKER = HOME .. "/.config/qs-wallpaperpicker"
-- Where the picker remembers the folder it reads (used only when the studio has never been told a
-- folder of its own).
local PICKER_SETTINGS = PICKER .. "/settings.json"
local CURRENT = HOME .. "/.cache/current_wallpaper_source"
local CURRENT_STILL = HOME .. "/.cache/current_wallpaper"
local FILE, PALETTE = "wallpapers.json", "palette.json"

local function read(name, kind)
    -- A nil `kind` is not "no kind" to the service: it is a third argument it refuses, and the
    -- pcall then quietly handed back a file that did not exist. The two-argument form is the one
    -- that reads the text (mooi-settings.luau does the same).
    local ok, v
    if kind then ok, v = pcall(sys.ask, "files.read", name, kind)
    else ok, v = pcall(sys.ask, "files.read", name) end
    return ok and v or nil
end
local function trim(s) return (tostring(s or ""):gsub("^%s+", ""):gsub("%s+$", "")) end
local base_name = W.base_name
local function clamp(v, lo, hi) if v < lo then return lo end; if v > hi then return hi end; return v end
local function round(v) return math.floor(v + 0.5) end

local settings = config.parse(read("settings.json"), json.decode)
local palette = read(PALETTE, "json")
local state = W.state(read(FILE, "json"))

local screen_w, screen_h = 1920, 1080
local base_w, base_h = 2880, 1620
local source, base, srcview, recipe = nil, nil, nil, W.neutral()
-- The base's real size (it keeps the picture's shape), and the proxy: the same picture small
-- enough to grade in a few tens of milliseconds, which is what a drag is drawn from.
local base_dims = { w = 0, h = 0 }
local proxy, proxy_dims = nil, { w = 0, h = 0 }
local DRAFT_W, DRAFT_H = 960, 540
local current_source = nil
local query = ""
local sources, filtered = nil, {}
-- The folder the source wall reads, the text in its field, and the tiles whose pictures are being
-- made. A source is only thumbnailed once it is on the page, so a folder of a thousand pictures
-- costs a page, not a thousand.
local folder, folder_input = "", ""
-- The three colours read from the picture's edges (D60), and the one the backdrop uses.
local bg_hex = { "#000000", "#000000", "#000000" }
-- What is in the custom colour's field. The field is the truth for what was typed (as the folder
-- field is): the logic writes it, and the `text:` event keeps what the hands put there, so a
-- half-typed colour is never mistaken for the one in the recipe.
local hex_input = W.CUSTOM_DEF
local function backdrop()
    local mode = tonumber(recipe.bg) or 0
    local hex = nil
    if mode == 5 then hex = recipe.bg_custom
    elseif mode >= 2 then hex = bg_hex[mode - 1] end
    return { mode = mode, hex = hex, edge = bg_hex[1], blur = recipe.bg_blur, dim = recipe.bg_dim }
end

-- The studio's own defaults (D61): how a picture that has no recipe yet opens. They are settings,
-- so the BACKDROP tab starts where the settings window says instead of always at none.
local function studio_defaults()
    local d = W.neutral()
    local ws = settings.wallpaper
    if type(ws) == "table" then
        d.matte = tonumber(ws.matte) or d.matte
        d.bg = W.BG_INDEX[ws.backdrop] or d.bg
        d.key = ws.key and 1 or 0
        d.key_fuzz = tonumber(ws.fuzz) or d.key_fuzz
    end
    return W.clean(d)
end

local scan_gen = 0
local thumbs, thumb_queued, thumb_queue = {}, {}, {}
local thumb_running, THUMB_WORKERS = 0, 3
local preview_n, previews = 0, {}
local applying = false
local pal_busy, pal_pending = false, nil
local save_gen = 0

-- ── The shell's colours ──────────────────────────────────────
-- The same roles the bar wears, from the same palette and settings; the scene glides to them.
-- The backdrop's palette (D63) is built here too: it is the shell's colours, so it is re-made
-- whenever the theme's are.
local swatch_rows = {}
-- The recipe's own history (D63): one entry per burst of edits, so UNDO goes back to before a
-- slider's drag and not to its last millimetre. `committed` is the state the next burst came from.
local hist, future = {}, {}
local committed = nil
local burst, burst_gen = false, 0
local function swatch_sel()
    if tonumber(recipe.bg) ~= 5 then return -1 end
    for i, s in ipairs(swatch_rows) do if s.hex == recipe.bg_custom then return i - 1 end end
    return -1
end
local function build_swatches(out)
    local rows = {}
    for i, s in ipairs(W.SWATCHES) do
        local c = s.role and out and out[s.role] or nil
        local hex = s.hex or (c and ferro.to_hex(c)) or "#000000"
        local h = hex:gsub("#", "")
        rows[i] = { name = s.name, hex = hex,
                    r = c and c.r or tonumber(h:sub(1, 2), 16) / 255,
                    g = c and c.g or tonumber(h:sub(3, 4), 16) / 255,
                    b = c and c.b or tonumber(h:sub(5, 6), 16) / 255 }
    end
    swatch_rows = rows
    model.swatches = rows
    fact.sw_sel = swatch_sel()
    fact.swatch_count = #rows
end
local function paint()
    local out = ferro.resolve(settings.theme.source, palette, settings.theme.signal, false, ferro.options(settings))
    if not out then return end
    for _, role in ipairs(ferro.ROLES) do
        local c = out[role]
        fact["fr_" .. role .. "_r"] = c.r
        fact["fr_" .. role .. "_g"] = c.g
        fact["fr_" .. role .. "_b"] = c.b
    end
    build_swatches(out)
end
paint()
pcall(sys.watch, "files:" .. PALETTE, function()
    palette = read(PALETTE, "json")
    paint()
end)

local function save_now()
    sys.call("files.write", FILE, state)
end
-- A slider sends a run of values; the file is written once the run settles.
local function save_soon()
    save_gen = save_gen + 1
    local g = save_gen
    after(450, function()
        if save_gen == g then save_now() end
    end)
end

-- ── The picture's background ─────────────────────────────────
-- Its three edge colours become nine facts, so a swatch is drawn in the colour it will use (a
-- fact is the only way the logic hands a colour to the scene).
local function publish_background(cols)
    if type(cols) ~= "table" or #cols < 3 then return end
    bg_hex = cols
    for i = 1, 3 do
        local hex = bg_hex[i]
        fact["bg_c" .. (i - 1) .. "_r"] = tonumber(hex:sub(2, 3), 16) / 255
        fact["bg_c" .. (i - 1) .. "_g"] = tonumber(hex:sub(4, 5), 16) / 255
        fact["bg_c" .. (i - 1) .. "_b"] = tonumber(hex:sub(6, 7), 16) / 255
    end
    text.bg_hex0, text.bg_hex1, text.bg_hex2 = bg_hex[1], bg_hex[2], bg_hex[3]
end

-- The picture's own edges, read once per source (D60) and kept in wallpapers.json (D61) so the
-- swatches are right before ImageMagick has run again. `done` runs either way, so a picture whose
-- edges cannot be read still gets its preview.
local function detect_background(path, cached, done)
    if cached then
        publish_background(cached)
        text.bg_note = "CACHED"
    end
    local args = W.edge_args(path)
    if not args then text.bg_note = "EDGES UNREADABLE"; if done then done() end; return end
    run("magick", args, function(out)
        local cols = W.edge_colours(out)
        if cols then
            local same = cached and cached[1] == cols[1] and cached[2] == cols[2] and cached[3] == cols[3]
            if not same then
                publish_background(cols)
                W.remember_edges(state, path, cols, os.time())
                save_soon()
            end
            text.bg_note = same and "CACHED" or "READ NOW"
        else
            text.bg_note = "EDGES UNREADABLE"
        end
        if done then done() end
    end)
end

-- ── The vibes and the sliders ────────────────────────────────
local vibe_rows = {}
for i, p in ipairs(W.PRESETS) do vibe_rows[i] = { id = p.id, name = p.name, hint = p.hint } end
model.vibes = vibe_rows

local function publish()
    local id = W.matches(recipe)
    local name, hint, sel = "CUSTOM", "your own grade", -1
    for i, p in ipairs(W.PRESETS) do
        if p.id == id then name, hint, sel = p.name, p.hint, i - 1 end
    end
    text.vibe_name, text.vibe_hint = name, hint
    fact.vibe_sel = sel
    fact.bg_sel = recipe.bg
    fact.key_on = recipe.key
    -- The colour the CUSTOM backdrop fills with, as facts: the scene can only be handed colours
    -- that way, and the swatch has to be drawn in the colour it will use.
    local hex = recipe.bg_custom or W.CUSTOM_DEF
    fact.bg_cu_r = tonumber(hex:sub(2, 3), 16) / 255
    fact.bg_cu_g = tonumber(hex:sub(4, 5), 16) / 255
    fact.bg_cu_b = tonumber(hex:sub(6, 7), 16) / 255
    text.bg_custom_hex = hex
    hex_input = hex
    fact.sw_sel = swatch_sel()
    fact.can_undo = #hist > 0
    fact.can_redo = #future > 0
    fact.fx, fact.fy = recipe.fx, recipe.fy
    fact.fit_on = recipe.fit > 0
    fact.rot = recipe.rotate
    fact.flip_h = recipe.flip % 2 == 1
    fact.flip_v = recipe.flip >= 2
    fact.zoom_now = recipe.zoom
    local rows = {}
    for _, f in ipairs(W.FIELDS) do
        if f.tab == fact.tab then
            rows[#rows + 1] = { label = f.label, v = recipe[f.key] - f.min, span = f.max - f.min,
                                shown = W.fmt(f.key, recipe[f.key]), code = f.index }
        end
    end
    model.sliders = rows
end

-- ── Rendering ────────────────────────────────────────────────
local function next_preview()
    preview_n = preview_n + 1
    local p = CACHE .. "/preview-" .. preview_n .. ".jpg"
    previews[#previews + 1] = p
    if #previews > 8 then run("rm", { "-f", table.remove(previews, 1) }) end
    return p
end

-- The palette the bar would wear, from the preview that is on the glass, exactly as the bar
-- derives it (lib/ferro + the settings' scheme, source colour and contrast).
local function palette_from(file)
    if not file then return end
    if pal_busy then pal_pending = file; return end
    pal_busy = true
    run("matugen", { "image", file, "-m", "dark", "--dry-run", "-j", "hex",
                     "--type", "scheme-" .. tostring(settings.theme.scheme),
                     "--source-color-index", tostring(settings.theme.color_index),
                     "--contrast", tostring(settings.theme.contrast) }, function(out, code)
        pal_busy = false
        local done = false
        if code == 0 then
            local ok, t = pcall(json.decode, out or "")
            if ok and type(t) == "table" and type(t.colors) == "table" then
                local roles = {}
                for name, v in pairs(t.colors) do
                    if type(v) == "table" and type(v.dark) == "table" then roles[name] = v.dark.color end
                end
                local res = ferro.resolve("wallpaper", { colours = roles }, settings.theme.signal, false, ferro.options(settings))
                if res and res.phos and res.ember then
                    fact.pal_phos_r, fact.pal_phos_g, fact.pal_phos_b = res.phos.r, res.phos.g, res.phos.b
                    fact.pal_ember_r, fact.pal_ember_g, fact.pal_ember_b = res.ember.r, res.ember.g, res.ember.b
                    text.pal_phos, text.pal_ember = ferro.to_hex(res.phos), ferro.to_hex(res.ember)
                    text.pal_note = settings.theme.source == "wallpaper" and "THE BAR WEARS THIS" or "THEME IS FIXED"
                    done = true
                end
            end
        end
        if not done then text.pal_note = "NO PALETTE FROM THIS PICTURE" end
        if pal_pending then local f = pal_pending; pal_pending = nil; palette_from(f) end
    end)
end

-- One render at a time, the newest request first. A draft (the proxy, small) answers a drag at
-- once; the full preview (the base) follows when the edits settle; the compare view (the frame
-- without the grade) is remade only when the frame itself changed. Every render is stamped with
-- the request it answered, so a slow one that finishes after a newer one is never shown.
local function screen() return { w = screen_w, h = screen_h } end
local busy, want = false, {}
local req_gen, shown_gen = 0, 0
local compare_key = nil
local settle_gen = 0
local pan_pending = false
local pump

local function rm_cache(path)
    if not path then return end
    run("rm", { "-f", path, (path:gsub("%.mpc$", ".cache")) })
end

local function start(kind, gen)
    busy = true
    if kind == "compare" then
        local key = W.frame_key(recipe)
        local out = CACHE .. "/source-" .. W.hash(source or "") .. "-" .. tostring(gen % 2) .. ".jpg"
        run("magick", W.args(W.ungraded(recipe), base, out, W.PREVIEW_W, W.PREVIEW_H, base_dims.w, base_dims.h, backdrop(), screen()), function(_, code)
            busy = false
            if code == 0 then srcview = out; text.src_file = out; compare_key = key end
            pump()
        end)
        return
    end
    local draft = kind == "draft" and proxy ~= nil
    local out = next_preview()
    local args = draft
        and W.args(recipe, proxy, out, DRAFT_W, DRAFT_H, proxy_dims.w, proxy_dims.h, backdrop(), screen())
        or W.args(recipe, base, out, W.PREVIEW_W, W.PREVIEW_H, base_dims.w, base_dims.h, backdrop(), screen())
    if draft then
        -- a draft is a quick JPEG; the full preview keeps its colour detail (lib/wallpaper)
        args[#args - 1] = "82"
    end
    run("magick", args, function(_, code)
        busy = false
        if code == 0 then
            if gen >= shown_gen then
                shown_gen = gen
                text.prev_file = out
                fact.has_preview = true
                fact.failed = false
                if pan_pending then pan_pending = false; fact.pan_dx = 0; fact.pan_dy = 0 end
                text.status = (draft and "DRAFT · " or "PREVIEW · ") .. W.summary(recipe)
                if not draft and gen == req_gen then
                    fact.loading = false
                    palette_from(out)
                    if compare_key ~= W.frame_key(recipe) then want.compare = gen end
                end
            end
        else
            fact.loading = false
            fact.failed = true
            text.status = "COULD NOT RENDER THE PREVIEW"
        end
        pump()
    end)
end

pump = function()
    if busy or not base then return end
    -- the newest full render beats a draft; a draft beats the compare view
    if want.full then local g = want.full; want.full = nil; want.draft = nil; start("full", g); return end
    if want.draft then local g = want.draft; want.draft = nil; start("draft", g); return end
    if want.compare then local g = want.compare; want.compare = nil; start("compare", g); return end
end

-- `quick`: a draft now and the full preview once nothing has changed for a moment.
local function render_preview(quick)
    if not base then return end
    req_gen = req_gen + 1
    fact.loading = true
    if quick and proxy then
        want.draft = req_gen
        settle_gen = settle_gen + 1
        local g = settle_gen
        after(260, function()
            if g == settle_gen then want.full = req_gen; pump() end
        end)
    else
        want.full = req_gen
    end
    pump()
end

-- ── A picture ────────────────────────────────────────────────
local function identify(path)
    run("magick", { "identify", "-format", "%w %h", path }, function(out, code)
        log("wallpaper · identify (" .. tostring(code) .. ") · " .. tostring(out))
        local w, h = tostring(out or ""):match("(%d+)%s+(%d+)")
        if w then
            text.src_meta = string.format("%d × %d · %.1f MP", tonumber(w), tonumber(h), tonumber(w) * tonumber(h) / 1000000)
        else
            text.src_meta = ""
        end
    end)
end

local function load_source(path, close_after, retried)
    if type(path) ~= "string" or path == "" then return end
    source = path
    local rec = state.recipes[path]
    recipe = rec and W.clean(rec.r) or studio_defaults()
    -- A history belongs to the picture it was made on.
    hist, future, committed = {}, {}, W.clean(recipe)
    burst = false
    if not rec then
        log(string.format("wallpaper · no grade for this picture; the studio's defaults (%d %% matte, %s)",
            recipe.matte, W.BG_NAME[recipe.bg + 1] or "black"))
    end
    W.remember(state, source, recipe, os.time())
    fact.loading = true
    fact.failed = false
    fact.applied = false
    fact.has_preview = false
    text.src_name = base_name(path)
    text.src_meta = ""
    text.status = "READING THE PICTURE…"
    publish()
    save_soon()

    local old_base, old_view, old_proxy = base, srcview, proxy
    srcview, proxy, base = nil, nil, nil
    compare_key = nil
    want = {}
    text.src_file = ""
    local b = CACHE .. "/base-" .. W.hash(path) .. ".mpc"
    local args = W.base_args(path, b, base_w, base_h)
    run("magick", args, function(out, code)
        if code ~= 0 then
            log("wallpaper · base failed (" .. tostring(code) .. ") · " .. table.concat(args, " ") .. " · " .. tostring(out))
            if not retried and current_source and current_source ~= path then
                load_source(current_source, close_after, true)
            else
                fact.loading = false
                fact.failed = true
                text.status = "COULD NOT READ THAT PICTURE"
            end
            return
        end
        if old_base and old_base ~= b then rm_cache(old_base) end
        if old_proxy then rm_cache(old_proxy) end
        if old_view then run("rm", { "-f", old_view }) end
        fact.has_source = true
        identify(path)
        if close_after then fact.browsing = false end
        -- The base keeps the picture's shape, so its size is read rather than assumed; the proxy is
        -- made from it at a draft's scale. The backdrop's colours are read before the preview is
        -- drawn: a recipe that already has a backdrop must land in the picture's own colours, not
        -- the last picture's.
        run("magick", { "identify", "-format", "%w %h", b }, function(out2)
            local w, h = tostring(out2 or ""):match("(%d+)%s+(%d+)")
            if source ~= path then return end
            base_dims = { w = tonumber(w) or base_w, h = tonumber(h) or base_h }
            base = b
            local px = CACHE .. "/proxy-" .. W.hash(path) .. ".mpc"
            local f = math.min(1, 1440 / math.max(1, base_w))
            run("magick", { b, "-resize", string.format("%.4f%%", f * 100), px }, function(_, pcode)
                if pcode ~= 0 or source ~= path then return end
                run("magick", { "identify", "-format", "%w %h", px }, function(out3)
                    local pw, ph = tostring(out3 or ""):match("(%d+)%s+(%d+)")
                    if source ~= path or not pw then return end
                    proxy, proxy_dims = px, { w = tonumber(pw), h = tonumber(ph) }
                end)
            end)
            detect_background(path, W.edges_of(state, path), function() render_preview(false) end)
        end)
    end)
end

-- What is on the desktop now. The picker keeps the source link and the still link; either is
-- a real path, and a missing one is answered with nil.
local function read_current(cb)
    run("readlink", { "-f", CURRENT }, function(out, code)
        local p = trim(out)
        if code == 0 and p ~= "" then cb(p); return end
        run("readlink", { "-f", CURRENT_STILL }, function(out2, code2)
            local q = trim(out2)
            cb(code2 == 0 and q ~= "" and q or nil)
        end)
    end)
end

-- ── The source wall ──────────────────────────────────────────
-- The tiles on the page that do not have their picture yet are queued; one `magick` runs at a
-- time, so paging makes a page of thumbnails and never a storm of them.
local build_hits

local function pump_thumbs()
    while thumb_running < THUMB_WORKERS and #thumb_queue > 0 do
        local job = table.remove(thumb_queue, 1)
        if job.gen == scan_gen and not thumbs[job.path] then
            thumb_running = thumb_running + 1
            local out = CACHE .. "/thumbs/" .. W.hash(job.path .. ":" .. tostring(job.mtime)) .. ".jpg"
            run("magick", W.thumb_args(job.path, out, 282, 158), function(_, code)
                if job.gen ~= scan_gen or code ~= 0 then
                    thumb_running = thumb_running - 1
                    pump_thumbs()
                    return
                end
                thumbs[job.path] = out
                job.entry.thumb, job.entry.ready = out, 1
                run("magick", { "identify", "-format", "%w %h", job.path .. "[0]" }, function(meta)
                    local w, h = tostring(meta or ""):match("(%d+)%s+(%d+)")
                    if w and job.gen == scan_gen then job.entry.dims = w .. "×" .. h end
                    thumb_running = thumb_running - 1
                    if job.gen == scan_gen then build_hits() end
                    pump_thumbs()
                end)
            end)
        end
    end
end

function build_hits()
    filtered = {}
    local q = string.lower(query)
    for _, s in ipairs(sources or {}) do
        if q == "" or string.find(string.lower(s.name), q, 1, true) then filtered[#filtered + 1] = s end
    end
    fact.hit_count = #filtered
    fact.pages = math.max(1, math.ceil(#filtered / 18))
    fact.page = clamp(fact.page, 0, fact.pages - 1)
    -- a page rebuilt because a thumbnail arrived keeps the tile that is lit
    fact.sel = clamp(fact.sel, 0, math.max(0, math.min(18, #filtered - fact.page * 18) - 1))
    local rows = {}
    local start = fact.page * 18
    for i = 1, math.min(18, #filtered - start) do
        local s = filtered[start + i]
        if thumbs[s.path] then s.thumb, s.ready = thumbs[s.path], 1 end
        rows[i] = { x = 48 + ((i - 1) % 6) * 308, y = 190 + math.floor((i - 1) / 6) * 208,
                    name = s.name, thumb = s.thumb or "", ready = s.ready or 0, dims = s.dims, slot = i - 1 }
        if not s.ready and not thumb_queued[s.path] then
            thumb_queued[s.path] = true
            thumb_queue[#thumb_queue + 1] = { path = s.path, mtime = s.mtime, entry = s, gen = scan_gen }
        end
    end
    model.hits = rows
    text.page_label = string.format("PAGE %02d / %02d", fact.page + 1, fact.pages)
    if sources == nil then
        text.count_label = "READING THE FOLDER…"
    elseif #sources == 0 then
        text.count_label = "NO PICTURES IN THAT FOLDER · THE CURRENT WALLPAPER IS ALWAYS HERE"
    elseif q == "" then
        text.count_label = #sources .. " IN THE FOLDER"
    else
        text.count_label = #filtered .. " OF " .. #sources
    end
    pump_thumbs()
end

-- Read `folder` with `find` (one level: a wallpaper folder holds pictures, not trees; `-L` so a
-- folder that is a link — a mounted disk linked into the home folder, say — is read as the folder
-- it points at). The choice is mooi's own and lives in wallpapers.json, so the studio opens on it
-- next time.
local function scan_folder(path, retried)
    path = W.folder_path(path, HOME)
    folder = path
    folder_input = path
    text.src_folder = path
    text.folder_show = path ~= "" and path or "NO FOLDER YET"
    if path == "" then
        sources, filtered = {}, {}
        build_hits()
        text.count_label = "NO FOLDER · TYPE ONE ABOVE"
        return
    end
    scan_gen = scan_gen + 1
    local gen = scan_gen
    sources = nil
    thumb_queued = {}
    fact.page = 0
    fact.sel = 0
    state.folder = path
    save_soon()
    build_hits()
    run("find", { "-L", path, "-maxdepth", "1", "-type", "f", "-printf", "%T@\t%p\n" }, function(out, code)
        if gen ~= scan_gen then return end
        if code ~= 0 then
            -- A folder that is not there (or cannot be read) is not a dead end: home is shown,
            -- and said so, so a first run on a machine with no ~/Pictures still finds pictures.
            if not retried and path ~= HOME then
                scan_folder(HOME, true)
                text.status = "THAT FOLDER COULD NOT BE READ · HERE IS HOME"
                return
            end
            sources = {}
            build_hits()
            text.count_label = "THAT FOLDER COULD NOT BE READ"
            return
        end
        sources = W.parse_find(out)
        build_hits()
    end)
end

local function open_browse()
    fact.browsing = true
    fact.page = 0
    fact.sel = 0
    if sources then build_hits() else scan_folder(folder) end
end

-- ── The folder picker ─────────────────────────────────────────
-- A wall of the folder's own subfolders, so a folder is chosen rather than typed — and a field for
-- the folder itself, so a folder anywhere (`/mnt/…`, `~/Downloads/pics`) is one line away. It
-- reads one level at a time with `find -L`; the rows are the page's, ten to a page, A→Z.
local PICK_PER_PAGE = 10
local pick_path = ""
local pick_all = {}
local pick_typed = ""

local function show_picker_dirs()
    fact.pick_pages = math.max(1, math.ceil(#pick_all / PICK_PER_PAGE))
    fact.pick_page = clamp(fact.pick_page, 0, fact.pick_pages - 1)
    local rows = {}
    local start = fact.pick_page * PICK_PER_PAGE
    for i = 1, math.min(PICK_PER_PAGE, #pick_all - start) do
        local d = pick_all[start + i]
        rows[i] = { name = d.name, slot = i - 1 }
    end
    model.dirs = rows
    text.pick_page_l = string.format("PAGE %02d / %02d", fact.pick_page + 1, fact.pick_pages)
    text.pick_count = #pick_all == 0 and "NO SUBFOLDERS" or (#pick_all .. " FOLDERS")
end

local enter_picker
local function read_picker_dirs(path, fallback)
    pick_all = {}
    show_picker_dirs()
    run("find", { "-L", path, "-mindepth", "1", "-maxdepth", "1", "-type", "d", "-printf", "%f\n" }, function(out, code)
        if not fact.picking or path ~= pick_path then return end
        if code == 0 then
            pick_all = W.parse_dirs(out, path)
        elseif fallback and fallback ~= path then
            enter_picker(fallback)
            return
        end
        show_picker_dirs()
        if code ~= 0 then text.pick_count = "THAT FOLDER COULD NOT BE READ" end
    end)
end

function enter_picker(path, fallback)
    pick_path = W.folder_path(path, HOME)
    if pick_path == "" then pick_path = HOME end
    fact.pick_page = 0
    pick_typed = pick_path
    text.pick_path = pick_path
    text.pick_typed = pick_path
    read_picker_dirs(pick_path, fallback)
end

local function open_picker()
    fact.picking = true
    enter_picker(folder ~= "" and folder or HOME)
end

-- A folder written in the picker's field: `~`, a name under home, or a whole path, taken as it is.
local function go_to(typed)
    local want = W.folder_path(typed, HOME)
    if want == "" then return end
    enter_picker(want)
end

local function pick_dir(slot)
    local d = pick_all[fact.pick_page * PICK_PER_PAGE + (tonumber(slot) or -1) + 1]
    if d then enter_picker(d.path) end
end

local function pick_choose()
    fact.picking = false
    scan_folder(pick_path)
end

local function pick_source(slot)
    local i = fact.page * 18 + (tonumber(slot) or -1) + 1
    local s = filtered[i]
    if s then load_source(s.path, true) end
end

-- The live wallpaper's folder: the pictures beside the one on the desk right now.
local function folder_current()
    if current_source and current_source ~= "" then scan_folder(W.folder_of(current_source)); return end
    read_current(function(p)
        if p then current_source = p; scan_folder(W.folder_of(p))
        else text.count_label = "NO WALLPAPER ON THE DESKTOP" end
    end)
end

local function shuffle()
    local pool = #filtered > 0 and filtered or (sources or {})
    if #pool == 0 then return end
    local s = pool[math.random(#pool)]
    load_source(s.path, true)
end

local function use_current()
    read_current(function(p)
        if not p then
            text.status = "NO WALLPAPER ON THE DESKTOP"
            return
        end
        current_source = p
        load_source(p, true)
    end)
end

-- ── Editing ──────────────────────────────────────────────────
-- A burst is a run of edits closer together than the settle time (a slider's drag, a colour typed
-- a letter at a time). The first edit of a burst keeps the state it started from, and that is what
-- UNDO returns to; the rest of the burst adds nothing.
local function checkpoint()
    if burst or not committed then return end
    burst = true
    burst_gen = burst_gen + 1
    local g = burst_gen
    after(650, function() if burst_gen == g then burst = false end end)
    hist[#hist + 1] = committed
    if #hist > 50 then table.remove(hist, 1) end
    future = {}
end

local function changed(restored)
    if not restored then checkpoint() end
    committed = W.clean(recipe)
    fact.applied = false
    publish()
    if source then W.remember(state, source, recipe, os.time()) end
    save_soon()
    render_preview(true)
end

local function undo_recipe()
    if #hist == 0 then return end
    future[#future + 1] = W.clean(recipe)
    recipe = W.clean(table.remove(hist))
    burst = false
    changed(true)
    text.status = "UNDONE"
end

local function redo_recipe()
    if #future == 0 then return end
    hist[#hist + 1] = W.clean(recipe)
    recipe = W.clean(table.remove(future))
    burst = false
    changed(true)
    text.status = "REDONE"
end

local function pick_vibe(i)
    local p = W.PRESETS[(tonumber(i) or -1) + 1]
    if not p then return end
    -- A vibe is the picture's look; the crop and the backdrop are the frame's, and stay.
    local z, fx, fy = recipe.zoom, recipe.fx, recipe.fy
    local matte, bg, blur, dim = recipe.matte, recipe.bg, recipe.bg_blur, recipe.bg_dim
    local key, fuzz = recipe.key, recipe.key_fuzz
    recipe = W.preset(p.id)
    recipe.zoom, recipe.fx, recipe.fy = z, fx, fy
    recipe.matte, recipe.bg, recipe.bg_blur, recipe.bg_dim = matte, bg, blur, dim
    recipe.key, recipe.key_fuzz = key, fuzz
    changed()
end

local function vibe_step(d)
    local n = #W.PRESETS
    local cur = 0
    local id = W.matches(recipe)
    for i, p in ipairs(W.PRESETS) do if p.id == id then cur = i end end
    if cur == 0 then cur = (tonumber(d) or 1) > 0 and 0 or n + 1 end
    local i = cur + ((tonumber(d) or 1) > 0 and 1 or -1)
    if i < 1 then i = n elseif i > n then i = 1 end
    pick_vibe(i - 1)
end

local function set_tab(n)
    fact.tab = clamp(round(tonumber(n) or 0), 0, #W.TABS - 1)
    publish()
end

local function apply()
    if applying or not base then return end
    applying = true
    fact.loading = true
    text.status = "RENDERING FOR THE DESKTOP…"
    -- Lossless (D63): this is the picture the desktop wears, so nothing is thrown away getting it
    -- there (the preview is the JPEG that trades detail for speed, and it is not the one applied).
    local out = CACHE .. "/wall-" .. os.time() .. "-" .. W.hash(source or "") .. ".png"
    run("magick", W.args(recipe, base, out, screen_w, screen_h, base_dims.w, base_dims.h, backdrop(), screen()), function(_, code)
        if code ~= 0 then
            applying = false
            fact.loading = false
            text.status = "COULD NOT RENDER THE STILL"
            return
        end
        local function applied(how)
            applying = false
            fact.loading = false
            local old = state.applied and state.applied.file
            state.applied = { source = source, file = out, at = os.time() }
            fact.applied = true
            text.status = how
            if old and old ~= out then run("rm", { "-f", old }) end
            save_now()
        end
        run("qs", { "-p", PICKER, "ipc", "call", "wallpaper", "set", out }, function(_, qcode)
            if qcode == 0 then applied("APPLIED · THE DESKTOP IS WEARING IT"); return end
            -- the picker is not running: the wallpaper daemon itself takes the still (the palette
            -- then waits for the picker, which is what makes it)
            run("awww", { "img", out, "--transition-type", "fade", "--transition-duration", "0.6" }, function(_, acode)
                if acode == 0 then applied("APPLIED WITH AWWW · THE PICKER WAS NOT RUNNING, SO THE PALETTE WAITS")
                else
                    applying = false
                    fact.loading = false
                    text.status = "COULD NOT APPLY · START THE WALLPAPER PICKER (qs-wallpaperpicker) OR AWWW"
                end
            end)
        end)
    end)
end

-- SAVE A COPY: the same still the desktop would get, kept in ~/Pictures/Lumen under the picture's
-- own name, so an edit can be used anywhere (the source is still never written).
local function save_copy()
    if applying or not base then return end
    applying = true
    text.status = "SAVING A COPY…"
    local dir = HOME .. "/Pictures/Lumen"
    local name = base_name(source or "wallpaper"):gsub("%.[%w]+$", "")
    local out = dir .. "/" .. name .. "-lumen-" .. os.date("%Y%m%d-%H%M%S") .. ".png"
    run("mkdir", { "-p", dir }, function()
        run("magick", W.args(recipe, base, out, screen_w, screen_h, base_dims.w, base_dims.h, backdrop(), screen()), function(_, code)
            applying = false
            text.status = code == 0 and ("SAVED · ~/Pictures/Lumen/" .. base_name(out)) or "COULD NOT SAVE THE COPY"
        end)
    end)
end

local function close()
    if source then W.remember(state, source, recipe, os.time()) end
    save_now()
    for _, f in ipairs(previews) do run("rm", { "-f", f }) end
    if base then rm_cache(base) end
    if proxy then rm_cache(proxy) end
    if srcview then run("rm", { "-f", srcview }) end
    run("pleamar", { "--say", "mooi-wallpaper", "quit" })
end

-- ── The hands and the keys ───────────────────────────────────
on("set_value", function(raw)
    local n = math.floor(tonumber(raw) or 0)
    local code, off = math.floor(n / 1000), n % 1000
    local f = W.FIELDS[code + 1]
    if not f then return end
    recipe[f.key] = clamp(off + f.min, f.min, f.max)
    changed()
end)
on("pick_vibe", pick_vibe)
on("vibe_step", vibe_step)
on("set_tab", set_tab)
on("step_tab", function(d)
    local n = #W.TABS
    set_tab(((fact.tab + ((tonumber(d) or 1) > 0 and 1 or -1)) % n + n) % n)
end)
on("pick_swatch", function(n)
    -- A colour from the palette (D63): the row's hex is the fill, and the field follows it, so what
    -- is typed and what is picked are one thing.
    local s = swatch_rows[(tonumber(n) or -1) + 1]
    if not s then return end
    recipe.bg_custom = s.hex
    recipe.bg = 5
    if recipe.matte == 0 and recipe.key == 0 then recipe.matte = 6 end
    changed()
end)
on("undo_recipe", undo_recipe)
on("redo_recipe", redo_recipe)
on("pick_bg", function(n)
    recipe.bg = clamp(round(tonumber(n) or 0), 0, 5)
    -- A backdrop with no matte is hidden under the picture, so choosing one opens the matte enough
    -- to see it (D60). A keyed picture already has a hole in it, so it is left full-bleed.
    if recipe.bg > 0 and recipe.matte == 0 and recipe.key == 0 then recipe.matte = 6 end
    changed()
end)
local function use_custom()
    -- The typed colour is the answer to "any colour I want" (D62): read it, keep the last good
    -- one if it is not a hex, and fill with it.
    local hex = string.lower(trim(hex_input))
    if not hex:match("^#%x%x%x%x%x%x$") then
        hex_input = recipe.bg_custom or W.CUSTOM_DEF
        text.bg_custom_hex = hex_input
        text.status = "A BACKDROP COLOUR IS #RRGGBB"
        return
    end
    recipe.bg_custom = hex
    recipe.bg = 5
    if recipe.matte == 0 and recipe.key == 0 then recipe.matte = 6 end
    changed()
end
on("use_bg_custom", use_custom)
on("submit:bg_custom_hex", function(v)
    hex_input = tostring(v or "")
    use_custom()
end)
-- The picture is carried by the hand: the scene moves the preview while it is dragged and sends
-- the distance on release (`pan_dx`, `pan_dy`, screen pixels); the crop follows and the scene's
-- offset is let go when the next preview arrives, so the picture does not jump back first.
on("pan_done", function()
    local dx, dy = tonumber(fact.pan_dx) or 0, tonumber(fact.pan_dy) or 0
    if not base or (dx == 0 and dy == 0) then fact.pan_dx = 0; fact.pan_dy = 0; return end
    recipe.fx, recipe.fy = W.pan(recipe, base_dims.w, base_dims.h, screen_w, screen_h,
        dx / math.max(1, screen_w), dy / math.max(1, screen_h))
    pan_pending = true
    changed()
end)
-- The wheel zooms round the pointer (`zoom_px`, `zoom_py`): what is under it stays under it.
on("zoom_at", function(d)
    if not base then return end
    local n = tonumber(d) or 0
    if n == 0 then return end
    n = math.max(-5, math.min(5, n))
    local z = recipe.zoom * (1.1 ^ n)
    if math.abs(z - 100) < 3 then z = 100 end
    local px = (tonumber(fact.zoom_px) or screen_w / 2) / math.max(1, screen_w)
    local py = (tonumber(fact.zoom_py) or screen_h / 2) / math.max(1, screen_h)
    local zoom, fx, fy = W.zoom_at(recipe, base_dims.w, base_dims.h, screen_w, screen_h, px, py, z)
    if zoom == recipe.zoom and fx == recipe.fx and fy == recipe.fy then return end
    recipe.zoom, recipe.fx, recipe.fy = zoom, fx, fy
    changed()
end)
-- The frame's switches: fill or fit, a quarter turn either way, a mirror.
on("set_fit", function()
    recipe.fit = recipe.fit > 0 and 0 or 1
    changed()
end)
on("rotate_step", function(d)
    recipe.rotate = ((recipe.rotate + ((tonumber(d) or 1) > 0 and 1 or -1)) % 4 + 4) % 4
    changed()
end)
on("flip_toggle", function(n)
    local bit = (tonumber(n) or 1) == 2 and 2 or 1
    local h, v = recipe.flip % 2, math.floor(recipe.flip / 2)
    if bit == 1 then h = 1 - h else v = 1 - v end
    recipe.flip = h + v * 2
    changed()
end)
on("frame_reset", function()
    recipe.zoom, recipe.fx, recipe.fy, recipe.rotate, recipe.flip = 100, 50, 50, 0, 0
    changed()
end)
on("save_copy", function() save_copy() end)
on("reset_recipe", function()
    recipe = studio_defaults()
    changed()
    text.status = "RESET · CTRL+Z BRINGS IT BACK"
end)
on("toggle_key", function()
    -- Unlike choosing a backdrop, keying needs no matte: the fill shows through the background the
    -- picture itself gave up, so a full-bleed keyed picture still shows it (D61).
    recipe.key = recipe.key > 0 and 0 or 1
    changed()
end)
on("open_browse", open_browse)
on("close_browse", function() fact.browsing = false end)
on("open_picker", open_picker)
on("pick_dir", pick_dir)
on("pick_up", function() enter_picker(W.parent(pick_path)) end)
on("pick_go", function() go_to(pick_typed) end)
-- Enter in the field. The submit carries the text, and it arrives before the field's own text is
-- written back, so the event's own value is the one used.
on("submit:pick_typed", function(v)
    pick_typed = tostring(v or "")
    go_to(pick_typed)
end)
on("pick_jump", function(n)
    local n = round(tonumber(n) or 0)
    if n == 1 then enter_picker(HOME .. "/Pictures", HOME)
    elseif n == 2 then enter_picker("/")
    else enter_picker(HOME) end
end)
on("text:pick_typed", function(v) pick_typed = tostring(v or "") end)
on("pick_page", function(d)
    if not fact.picking then return end
    fact.pick_page = clamp(fact.pick_page + ((tonumber(d) or 1) > 0 and 1 or -1), 0, fact.pick_pages - 1)
    show_picker_dirs()
end)
on("pick_choose", pick_choose)
on("pick_cancel", function() fact.picking = false end)
on("set_folder", function()
    -- The field is the truth: what was last typed in it (the `text:` event), not what the logic last
    -- wrote there. Clearing it is a real answer: the wall says there is no folder.
    scan_folder(folder_input)
end)
on("submit:src_folder", function(v)
    folder_input = tostring(v or "")
    scan_folder(folder_input)
end)
on("folder_current", folder_current)
on("pick_source", pick_source)
on("browse_page", function(d)
    if not sources then return end
    fact.page = clamp(fact.page + ((tonumber(d) or 1) > 0 and 1 or -1), 0, fact.pages - 1)
    fact.sel = 0
    build_hits()
end)
-- Up and Down walk the wall's tiles (the filter keeps the caret, and Enter in it opens the one
-- that is lit); walking past either end of a page turns it.
on("sel_step", function(d)
    if not sources or #filtered == 0 then return end
    local i = fact.page * 18 + fact.sel + ((tonumber(d) or 1) > 0 and 1 or -1)
    i = clamp(i, 0, #filtered - 1)
    local page = math.floor(i / 18)
    if page ~= fact.page then fact.page = page; build_hits() end
    fact.sel = i - page * 18
end)
on("shuffle", shuffle)
on("use_current", use_current)
on("apply_now", apply)
on("close_studio", close)
on("text:src_query", function(v)
    query = tostring(v or "")
    if sources then fact.page = 0; fact.sel = 0; build_hits() end
end)
on("text:src_folder", function(v) folder_input = tostring(v or "") end)
on("text:bg_custom_hex", function(v) hex_input = tostring(v or "") end)

-- ── Up ───────────────────────────────────────────────────────
math.randomseed(os.time())
run("mkdir", { "-p", CACHE .. "/thumbs" }, function()
    fact.studio_in = 1
    run("hyprctl", { "-j", "monitors" }, function(out)
        local ok, t = pcall(json.decode, out or "")
        if ok and type(t) == "table" then
            local mon
            for _, m in ipairs(t) do if m.focused then mon = m end end
            mon = mon or t[1]
            if mon and tonumber(mon.width) and tonumber(mon.height) then
                screen_w, screen_h = round(tonumber(mon.width)), round(tonumber(mon.height))
            end
        end
        base_w = math.min(3840, round(screen_w * 1.5))
        base_h = math.min(2160, round(screen_h * 1.5))
        log(string.format("wallpaper · screen %dx%d · base %dx%d", screen_w, screen_h, base_w, base_h))
        read_current(function(cur)
            current_source = cur
            -- The folder to read: the studio's own choice, else the live wallpaper's folder, else the
            -- one the desktop's wallpaper picker is set to, else Pictures.
            local want_folder = state.folder
            -- The stills the studio hands the desktop live in its own cache; their folder is not a
            -- folder of pictures, so it is never where the wall opens (a session that applied a
            -- still would otherwise start on it). Pictures, else home, does.
            if want_folder == CACHE then want_folder = "" end
            if want_folder == "" and cur then want_folder = W.folder_of(cur) end
            if want_folder == CACHE then want_folder = "" end
            if want_folder == "" then
                local picker = read(PICKER_SETTINGS, "json")
                if type(picker) == "table" and type(picker.wallpaperDir) == "string" then
                    want_folder = W.folder_path(picker.wallpaperDir, HOME)
                end
            end
            if want_folder == "" then want_folder = HOME .. "/Pictures" end
            scan_folder(want_folder)

            local want = state.last
            if (not want or want == "") and state.applied then want = state.applied.source end
            if (not want or want == "") then want = cur end
            if not want or want == "" then
                fact.loading = false
                text.status = "NO WALLPAPER YET · PICK ONE"
                open_browse()
                return
            end
            load_source(want, false)
        end)
    end)
end)
