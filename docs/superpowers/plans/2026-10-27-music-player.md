# mooi music player overhaul — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Turn mooi's music player into one program with three sizes (mini → panel → full), three views, six visualisers (shared with the bar), a library with covers, lyrics polish, an EasyEffects equaliser and music video as the visual.

**Architecture:** One pleamar scene (`shell/mooi-player.plm`) split into `include` parts under `shell/player/`, one shared component library `shell/ui/viz.plm` (imported by the player and the bar), Luau logic split into modules under `shell/player/`, and pure, unit-tested helpers in `shell/lib/player.luau`, `shell/lib/vizbands.luau`, `shell/lib/eqpreset.luau`. mpd via `mpc`, MPRIS via `playerctl`, cava for bands, EasyEffects for EQ, yt-dlp + mpv for video.

**Tech Stack:** pleamar language 0.4 scenes, Luau logic (`sys.*`, `run`, `spawn`, `fact`, `model`, `text`), Lua 5.4 unit tests (`tests/unit/run.lua`), bash (`bin/mooi`), Hyprland 0.56 Lua config.

**Spec:** `docs/superpowers/specs/2026-10-27-music-player-design.md`

## Global Constraints

- Everything the player draws is in **one surface** (a second full-screen surface takes no presses — 4e15fff).
- Keyboard: `exclusive` in panel and full, **none in mini**.
- Every new setting gets a row in `lib/config` SCHEMA (unknown keys are dropped — D85); settings-page controls are appended to `SETTERS` in both `tools/gen-settings.py` and `shell/lib/setters.luau` (never inserted: codes would move).
- Colours only from palette roles (`fl.*`); light and dark both (palette.json `mode`, D91).
- Visualisers: reduced motion and the battery saver draw them still or off; one cava process, only while a visualiser shows and music plays.
- Never fake what a source cannot do: mpd has no speed control (pitch fader is visual, said in its label); the rack's scrubber is cava bands over time, not a waveform (said).
- Covers: only the visible page is made, ≤ 24 queued, **one** `ffmpeg`/`magick` process at a time; cache `~/.cache/mooi/covers/<hash>-<64|256>.jpg`.
- Network only on a press (lyrics already; video only on VIDEO).
- Never overwrite the user's EasyEffects presets (`live_eq`, `vespera_eq`); mooi writes only `output/mooi.json`.
- `bin/mooi check` must pass after every task; live-test with `pleamar --say mooi-player …` **and** real clicks (`ydotool mousemove --absolute -x X -y Y; ydotool click 0xC0`), screenshots with `grim`, dark and light (`mooi mode light|dark`). Ask before switching the user's workspace; poll `hyprctl -j activeworkspace` until it lands.
- Logic changes go live only after a real restart of the program (required modules are cached).
- Commit after every task; push finished pieces (user's standing preference).

## Review Focus

1. **Odd tags** — songs with no album, no artist, a compilation ("Various Artists"), or non-ASCII names: albums group by `albumartist`, falling back to `artist`, then "Unknown artist"; a missing album is "Unknown album"; nothing crashes or vanishes. (Task 4 test `library: odd tags still make albums`.)
2. **Scrolling past pages of missing covers** — paging fast must drop the old page's queued covers, never run two cover processes, never block the UI. (Task 4 test `covers: a new page replaces the queue`.)
3. **A non-mpd source** (Spotify, a browser) — library, EQ and video still behave: library says it reads mpd only, VIDEO is disabled with its reason, EQ still works (system-wide). (Task 8 test `video: offered only for mpd songs with a title`; Task 4 live check.)
4. **The bar icon pressed while the player is open in any size** — it closes (today's toggle), never opens a second program or resizes. (Task 2 test `sizes: the bar's press closes from every size`.)
5. **Light mode legibility** — generated covers, visualisers and the deck/stage/rack materials read on paper. (Task 4 test `covers: generated tones hold contrast in light and dark`; Task 5 live screenshots in both modes.)

---

### Task 1: Split the player into parts and modules (no visible change)

**Files:**
- Create: `shell/player/panel.plm` (`part Panel`), `shell/player/full.plm` (`part Full`)
- Create: `shell/player/transport.luau` (mpc/playerctl/status/queue/song), `shell/player/lyrics.luau`, `shell/player/library.luau`
- Modify: `shell/mooi-player.plm` (keeps facts, events, springs, the surface, keys; `include "player/panel.plm"` and `include "player/full.plm"` inside the surface), `shell/mooi-player.luau` (spine: settings, paint, requires the modules, wires events)
- Modify: `bin/mooi` (the live copy must carry `shell/player/`; check `snapshot()`/refresh copies the directory)

**Interfaces:**
- Produces: each logic module returns a table built by `M.new(ctx)` where `ctx = { mpc = mpc, say = say, read = read, settings = settings, folder = folder }`; the spine keeps the existing event names unchanged (`pl_toggle` … `lyr_scroll`).
- Produces: parts read the surface's lets (`pw`, `ph`, `px`, `py`, `rcx`, `rcy`, `rr`, `mx`, `mw`, `qx`, `qw`; `fw`, `fh` in Full).

- [ ] **Step 1:** Screenshot the panel and full screen as they are (open with `bin/mooi player`, `pleamar --say mooi-player "emit pl_full"`), saved to the scratchpad as the baseline.
- [ ] **Step 2:** Move the panel's group (the `show: pl_a > 0.004 and not full` group) into `part Panel`, and the full-screen block into `part Full`; include both where they were.
- [ ] **Step 3:** Run `pleamar --check shell/mooi-player.plm` — expect `ok`.
- [ ] **Step 4:** Move the logic into the three modules; the spine requires them (`require("player/transport")` — check the require root is `shell/`, as `require("lib/player")` is).
- [ ] **Step 5:** Run `bin/mooi check` — expect all scenes ok and `N tests, 0 failed`.
- [ ] **Step 6:** `bin/mooi refresh`, reopen, screenshot both; compare with the baseline — identical layout; play/pause, queue, library and lyrics still answer (`pleamar --say mooi-player "get pstate"` after `emit pl_toggle`).
- [ ] **Step 7:** Commit `Split the player into parts and modules`.

### Task 2: Three sizes — mini, panel, full

**Files:**
- Create: `shell/player/mini.plm` (`part Mini`)
- Modify: `shell/mooi-player.plm` (`fact size: mini | panel | full = panel` replaces `full`; size springs `pl_w`, `pl_h`, `pl_x`; `keyboard: exclusive while size != mini`; keys), `shell/mooi-player.luau`, `shell/lib/player.luau`
- Modify: `shell/mooi.luau:1498-1515` (`open_player` writes `{ x = …, size = "mini" }`), `bin/mooi` (`mooi player [--panel]`; Super+Alt+M passes `--panel`)
- Test: `tests/unit/run.lua`

**Interfaces:**
- Produces: `P.size_after(size: string, action: string) -> string | nil` in `lib/player` — actions `"open"`, `"escape"`, `"outside"`, `"grow"`, `"full"`, `"bar"`; returns the next size or `nil` for closed.
- Produces: event `pl_size ->` (0 mini · 1 panel · 2 full) replacing `pl_full`'s toggle; `pl_full` kept as an alias that emits full/panel.
- Consumes: `player-anchor.json` `{ x: number, size: "mini" | "panel" }`.

- [ ] **Step 1: Write the failing tests**

```lua
test("sizes: escape steps back one size", function()
    eq(player.size_after("full", "escape"), "panel", "full → panel")
    eq(player.size_after("panel", "escape"), nil, "panel → closed")
    eq(player.size_after("mini", "escape"), nil, "mini → closed")
end)
test("sizes: the mini card grows, and closes on a press outside", function()
    eq(player.size_after("mini", "grow"), "panel", "OPEN PLAYER")
    eq(player.size_after("mini", "outside"), nil, "outside the card")
    eq(player.size_after("panel", "full"), "full", "FULL"); eq(player.size_after("full", "full"), "panel", "FULL again")
end)
test("sizes: the bar's press closes from every size", function()
    for _, s in ipairs({ "mini", "panel", "full" }) do eq(player.size_after(s, "bar"), nil, s) end
end)
```

- [ ] **Step 2:** Run `lua5.4 tests/unit/run.lua` — expect the three FAIL (`size_after` nil).
- [ ] **Step 3:** Implement `P.size_after` (a table of transitions; `"open"` returns its argument size).
- [ ] **Step 4:** Run tests — PASS.
- [ ] **Step 5:** Build `part Mini` (360 × 168, chamfered, hanging from `pl_cx`, top `pl_top`): cover 96 px (`image cover`), title, artist, seek bar (`pl_seek`), prev/play/next, volume (`pl_vol`), **OPEN PLAYER** (`emit pl_size(1)`), a visualiser strip slot (filled in Task 3; a plain bar of `nv*` until then), outside zone → `pl_close`. Nothing playing: the last track greyed with PLAY, or "NOTHING PLAYING — OPEN THE LIBRARY" (OPEN PLAYER lands on the LIBRARY pane). Panel and Full show by `size`; the panel grows from the card with the springs.
- [ ] **Step 6:** `bin/mooi check`; deploy; live: real click on the bar's ♪ → mini (screenshot); real click on OPEN PLAYER → panel; FULL → full; Escape full → panel → closed; real click outside the mini → closed; ♪ again with the player open → closes. Keyboard: with mini open, typing in kitty still works.
- [ ] **Step 7:** Commit `Player: a mini card first, then the panel, then full screen`.

### Task 3: Six visualisers in `ui/viz.plm`, the bar's included

**Files:**
- Create: `shell/ui/viz.plm` (`library Viz`), `shell/lib/vizbands.luau`
- Modify: `shell/mooi-player.plm` (import; `model vzb max 24 { v: number }` replaces `nv0…nv23`; `fact vz_peak.*` as needed), player parts (use the components), `shell/mooi-player.luau` (fill `vzb`), `shell/mooi.plm` (import; the media module's visualiser → `Viz.*`, coloured `fl.phos` → `fl.ember`/`fl.flare` by level), `shell/mooi.luau` / `shell/bar.luau` (fill the bar's `vzb` from its cava), `shell/lib/config.luau` (rows below), `tools/gen-settings.py` + `shell/lib/setters.luau` (append), Settings → Media page
- Test: `tests/unit/run.lua`

**Interfaces:**
- Produces components, all `(x: number, y: number, w: number, h: number, t1: color, t2: color, still: bool)` reading the scene's `vzb` model: `Spectrum`, `Mirror`, `Aurora`, `LED`, `Orbit`; and `Ring(cx: number, cy: number, r: number, reach: number, t1: color, t2: color, still: bool)`. If a component cannot iterate a scene model, use `repeat k in 0..23` over `vzb.$k.v` (check `pleamar --docs reference` "component").
- Produces: `vizbands.levels(bands: {number}) -> low, mid, high` (means of bands 1–6, 7–16, 17–24), `vizbands.peaks(prev: {number}, now: {number}, dt: number) -> {number}` (a peak never below its band; falls 1.2 units/s), `vizbands.STYLES = { "spectrum", "mirror", "ring", "aurora", "led", "orbit", "off" }`, `vizbands.from_bar(v: string) -> string` (bars→spectrum, mirror→mirror, dots→led, line→aurora, off→off).
- Settings: `player.viz_mini` (mirror), `player.viz_deck` (ring), `player.viz_stage` (aurora), `player.viz_rack` (led), `player.viz_full` (ring), enum of `vizbands.STYLES`.

- [ ] **Step 1: Write the failing tests**

```lua
local vizbands = require("lib/vizbands")
test("viz: low, mid and high from 24 bands", function()
    local b = {}; for i = 1, 24 do b[i] = (i <= 6) and 1 or ((i <= 16) and 0.5 or 0) end
    local lo, mid, hi = vizbands.levels(b)
    eq(lo, 1, "low"); eq(mid, 0.5, "mid"); eq(hi, 0, "high")
end)
test("viz: peaks fall slowly and never below the band", function()
    local p = vizbands.peaks({ 1, 0.2 }, { 0.5, 0.6 }, 0.25)
    eq(p[1], 0.7, "falls 1.2/s"); eq(p[2], 0.6, "rises to the band at once")
end)
test("viz: the bar's styles map onto the set", function()
    eq(vizbands.from_bar("bars"), "spectrum", "bars"); eq(vizbands.from_bar("dots"), "led", "dots")
    eq(vizbands.from_bar("line"), "aurora", "line"); eq(vizbands.from_bar("off"), "off", "off")
end)
```

- [ ] **Step 2:** Run tests — FAIL (module missing).
- [ ] **Step 3:** Implement `lib/vizbands`.
- [ ] **Step 4:** Run tests — PASS.
- [ ] **Step 5:** Write the six components (mockups: `.superpowers/brainstorm/*/content/visualisers.html`); place them: mini strip, deck ring, stage behind, rack panel, full; a chip on each cycles its setting (`emit viz_next(place)`, logic writes the setting).
- [ ] **Step 6:** The bar: replace the media module's four styles with `Viz.*` per `vizbands.from_bar(bar.visualizer)`, colours `t1 = fl.phos`, `t2 = fl.ember` (flare at peaks).
- [ ] **Step 7:** `bin/mooi check`; live with music playing (mpd at low volume, restored after): screenshot each style in each place, dark and light; the bar's visualiser is violet → pink with this wallpaper; reduced motion (`motion.reduced`) draws them still.
- [ ] **Step 8:** Commit `Six visualisers, shared by the player and the bar`.

### Task 4: Library — covers, albums, detailed list, artists, genres

**Files:**
- Create: `shell/player/library.plm` (`part Library`)
- Modify: `shell/lib/player.luau`, `shell/player/library.luau`, `shell/player/panel.plm` (pane LIBRARY shows the part), `shell/mooi-player.plm` (models below), `shell/lib/config.luau` (`player.library` albums|artists|genres|songs, `player.sort` artist|album|year)
- Test: `tests/unit/run.lua`

**Interfaces:**
- Produces in `lib/player`: `P.LIB_FMT` (mpc format with `%albumartist%\t%artist%\t%album%\t%date%\t%genre%\t%title%\t%time%\t%file%`), `P.albums(rows) -> { {artist, album, year, n, file} }` (grouping rule in Review Focus 1), `P.sort(list, key: "artist"|"album"|"year"|"title"|"time") -> list`, `P.cover_file(cache_dir, file, size: 64|256) -> path` (uses `P.hash`), `P.cover_tones(name, roles) -> { a = color, b = color, initials = string }`.
- Produces in `player/library.luau`: `lib:show(grouping, page)`, `lib:open(k)`, `lib:search(q)`, `lib:covers_for_page()` (the queue), events `lib_group ->` (0–3), `lib_sort ->`.
- Scene models (a `let` cannot hold a colour, so a generated cover's two tones travel as channels): `model albums max 24 { name: text; sub: text; k: number; art: image 256, 256; has_art: bool; ar: number; ag: number; ab: number; br: number; bg: number; bb: number; ini: text }`, `model songs max 12 { title: text; artist: text; album: text; year: text; time: text; k: number; art: image 64, 64; has_art: bool }`.

- [ ] **Step 1: Write the failing tests**

```lua
test("library: odd tags still make albums", function()
    local rows = { { albumartist = "", artist = "Björk", album = "Post", date = "1995", file = "a.flac" },
                   { albumartist = "Various Artists", artist = "X", album = "Hits", date = "", file = "b.flac" },
                   { albumartist = "", artist = "", album = "", date = "", file = "c.flac" } }
    local al = player.albums(rows)
    eq(#al, 3, "three albums"); eq(al[1].artist, "Björk", "falls back to artist")
    eq(al[2].artist, "Various Artists", "albumartist first")
    eq(al[3].artist, "Unknown artist", "no artist"); eq(al[3].album, "Unknown album", "no album")
end)
test("library: sorting by year puts undated last", function()
    local s = player.sort({ { year = "" }, { year = "2001" }, { year = "1995" } }, "year")
    eq(s[1].year, "1995", "oldest first"); eq(s[3].year, "", "undated last")
end)
test("covers: a cache path per file and size", function()
    eq(player.cover_file("/c", "a/b.flac", 64) ~= player.cover_file("/c", "a/b.flac", 256), true, "sizes differ")
    eq(string.match(player.cover_file("/c", "a/b.flac", 64), "^/c/%x+%-64%.jpg$") ~= nil, true, "shape")
end)
test("covers: generated tones hold contrast in light and dark", function()
    for _, mode in ipairs({ "dark", "light" }) do
        local roles = ferro.resolve("fixed", { mode = mode }, "auto", false)
        local t = player.cover_tones("Bleed American", roles)
        eq(t.initials, "BA", mode .. " initials")
        assert(ferro.contrast(roles.engrave, t.a) >= 3, mode .. ": initials read on the cover")
    end
end)
```

and in `player/library.luau`'s pure helper (export `M.next_cover_queue(old: {string}, page: {string}, cached: {[string]: bool}) -> {string}` — the page's uncached files only, ≤ 24, old entries dropped):

```lua
test("covers: a new page replaces the queue", function()
    local q = require("player/library").next_cover_queue({ "old1", "old2" }, { "p1", "p2", "p3" }, { p2 = true })
    eq(#q, 2, "only the page's uncached"); eq(q[1], "p1", "in order"); eq(q[2], "p3", "skips cached")
end)
```

- [ ] **Step 2:** Run — FAIL.
- [ ] **Step 3:** Implement the `lib/player` functions and `next_cover_queue` (`player/library.luau` must be requirable without `sys` at load: keep side effects inside `M.new`).
- [ ] **Step 4:** Run — PASS.
- [ ] **Step 5:** Cover maker in `player/library.luau`: one process at a time — `ffmpeg -y -i <file> -an -vcodec copy <tmp>` else `cover|folder|front.(jpg|png)` beside the file, then `magick <src> -resize 256x256^ -gravity center -extent 256x256 <256>` and 64; on finish set the row's `art`/`has_art`, start the next.
- [ ] **Step 6:** `part Library`: grouping chips ALBUMS · ARTISTS · GENRES · SONGS, sort chip, search field, the grid (columns `clamp(floor(qw / 132), 4, 6)`), album page (PLAY ALL, ADD, tracks), the detailed list with column-sort, paging; non-mpd source → "The library reads mpd" line; mpd down (mpc exits non-zero) → "MPD IS NOT RUNNING — systemctl --user start mpd" in the library and queue, while the transport keeps working for MPRIS sources.
- [ ] **Step 7:** `bin/mooi check`; live: covers appear page by page (`ls ~/.cache/mooi/covers | wc -l` grows by ≤ page size), page fast 5× → one cover process at a time (`pgrep -c ffmpeg` ≤ 1), open an album, play it, search "free bird", sort by year; screenshots dark and light.
- [ ] **Step 8:** Commit `Player library: covers, albums, songs, artists and genres`.

### Task 5: The three views and their materials

**Files:**
- Create: `shell/player/deck.plm` (`part Deck`), `shell/player/stage.plm` (`part Stage`), `shell/player/rack.plm` (`part Rack`)
- Modify: `shell/player/panel.plm`, `shell/player/full.plm` (each draws the chosen view into `vx, vy, vw, vh`), `shell/mooi-player.plm` (`fact view: deck | stage | rack`, chips), `shell/mooi-player.luau`, `shell/lib/player.luau`, `shell/lib/config.luau` (`player.view` deck)
- Test: `tests/unit/run.lua`

**Interfaces:**
- Produces: `P.parse_audio(s: string) -> { rate: number, bits: number, channels: number } | nil` (mpd's `audio: 44100:16:2`; `f` for float bits → 32), `P.cue_point(last_seek: number | nil, now: number) -> number` (last seek if within the song and before now, else 0).
- Produces: event `pl_view ->` (0 deck · 1 stage · 2 rack), `pl_cue ->`.

- [ ] **Step 1: Write the failing tests**

```lua
test("views: mpd's audio format reads as rate, bits, channels", function()
    local a = player.parse_audio("44100:16:2"); eq(a.rate, 44100, "rate"); eq(a.bits, 16, "bits"); eq(a.channels, 2, "ch")
    eq(player.parse_audio("48000:f:2").bits, 32, "float"); eq(player.parse_audio(""), nil, "none")
end)
test("views: cue goes to the last seek, else the start", function()
    eq(player.cue_point(42, 90), 42, "last seek"); eq(player.cue_point(nil, 90), 0, "none"); eq(player.cue_point(120, 90), 0, "seek after now")
end)
```

- [ ] **Step 2:** Run — FAIL. **Step 3:** Implement. **Step 4:** Run — PASS.
- [ ] **Step 5:** `part Deck`: plinth in steel roles, platter with strobe ring (dots `repeat` 90 at the rim, rotation `vang`), the cover as label, tonearm (existing seek logic), pitch fader (±8 %, scales `spd` only; label "SPIN · NOT SPEED" for mpd), CUE (`pl_cue`), 33/45 chip, two VU meters from `vizbands.levels` low/high, ring visualiser. `part Stage`: cover large with shadow, the cover palette blurred behind (`image cover` blur 60), lyrics beside (Task 6 polishes), Aurora behind. `part Rack`: chamfered hull panels — analyser (LED/Spectrum), track + format (`parse_audio`), LED time, scrubber from band history (label "BANDS, NOT A WAVEFORM"), three EQ knobs (wired in Task 7; inert with "EQ OFF" until then).
- [ ] **Step 6:** `bin/mooi check`; live: each view in panel and full, dark and light, cover colours on/off; CUE works; view chip remembered across reopen.
- [ ] **Step 7:** Commit `Player views: the DJ deck, the cover stage and the instrument rack`.

### Task 6: Lyrics — the sung line, and an offset

**Files:**
- Modify: `shell/lib/player.luau`, `shell/player/lyrics.luau`, `shell/player/stage.plm`, `shell/player/full.plm`, `shell/player/panel.plm` (± nudge in the LYRICS pane)
- Test: `tests/unit/run.lua`

**Interfaces:**
- Produces: `P.lyric_at(lyrics, t, offset)` — existing signature gains `offset` (seconds, default 0); `P.clamp_offset(x) -> number` (±10 s, 0.5 s steps). Offsets kept in `player-lyrics.json` `{ [P.hash(file)] = seconds }`. Event `lyr_nudge ->` (-1 / 1).

- [ ] **Step 1: Write the failing tests**

```lua
test("lyrics: an offset moves the sung line", function()
    local l = player.parse_lrc("[00:10.00]one\n[00:20.00]two")
    eq(player.lyric_at(l, 19, 0), 1, "before the offset"); eq(player.lyric_at(l, 19, 1.5), 2, "1.5 s early")
    eq(player.clamp_offset(12.3), 10, "capped"); eq(player.clamp_offset(0.74), 0.5, "steps of 0.5")
end)
```

(Use `lyric_at`'s current return shape — check it; adapt the asserted index field if it returns a table.)

- [ ] **Step 2:** Run — FAIL. **Step 3:** Implement. **Step 4:** Run — PASS (existing lyric tests still pass).
- [ ] **Step 5:** Stage and full: the sung line 28 px bold lit, neighbours fading by distance; press seeks (existing `lyr_seek`); pane shows `−0.5 s · +0.5 s` and the current offset.
- [ ] **Step 6:** Live with a synced song: nudge twice, reopen → offset kept; screenshot stage.
- [ ] **Step 7:** Commit `Lyrics: the sung line large, and a per-song offset`.

### Task 7: Equaliser through EasyEffects

**Files:**
- Create: `shell/lib/eqpreset.luau`, `shell/player/eq.luau`, `shell/player/eq.plm` (`part Eq`)
- Modify: `shell/mooi-player.plm` (pane EQ; `run` permissions add `easyeffects`), `shell/player/rack.plm` (knobs), `shell/lib/config.luau` (`player.eq.on` false, `player.eq.preset` "flat", `player.eq.bands` list of 10 numbers −12…12, `player.eq.preamp` 0), `bin/mooi` (nothing to link: presets live in EasyEffects' own folder)
- Test: `tests/unit/run.lua`

**Interfaces:**
- Produces: `eqpreset.FREQS = { 31, 62, 125, 250, 500, 1000, 2000, 4000, 8000, 16000 }`, `eqpreset.PRESETS = { flat, bass, treble, vocal, rock, electronic, acoustic }` (each 10 dB values), `eqpreset.easyeffects(bands, preamp) -> table` (the preset document; **read `~/.local/share/easyeffects/output/live_eq.json` first and mirror its schema for EasyEffects 8.3**), `eqpreset.knobs(bands) -> lo, mid, hi` (means of 1–3, 4–7, 8–10), `eqpreset.from_knob(bands, which: 1|2|3, value) -> bands` (shifts that group so its mean is `value`, clamped ±12).
- Produces: events `eq_band ->` (100·band + dB+12), `eq_preset ->` (index), `eq_toggle ->`, `eq_save ->`.

- [ ] **Step 1: Write the failing tests**

```lua
local eqpreset = require("lib/eqpreset")
test("eq: ten bands round-trip through the EasyEffects document", function()
    local doc = eqpreset.easyeffects(eqpreset.PRESETS.rock, -2)
    local back = eqpreset.bands_from(doc)            -- the inverse, also exported
    for i = 1, 10 do eq(back[i], eqpreset.PRESETS.rock[i], "band " .. i) end
end)
test("eq: the rack's knobs move their bands", function()
    local b = eqpreset.from_knob(eqpreset.PRESETS.flat, 1, 6)
    local lo = eqpreset.knobs(b); eq(lo, 6, "low knob"); eq(b[4], 0, "mid untouched")
    eq(eqpreset.from_knob(b, 1, 30)[1], 12, "clamped")
end)
test("eq: every preset has ten bands within ±12 dB", function()
    for name, p in pairs(eqpreset.PRESETS) do
        eq(#p, 10, name); for _, v in ipairs(p) do assert(v >= -12 and v <= 12, name) end
    end
end)
```

- [ ] **Step 2:** Run — FAIL. **Step 3:** Implement (`bands_from` exported too). **Step 4:** Run — PASS.
- [ ] **Step 5:** `player/eq.luau`: on enable, start `easyeffects --service-mode --hide-window` if `pgrep -x easyeffects` finds none; write `output/mooi.json`; `easyeffects -l mooi`; band changes debounce 150 ms; off → load the user's previous preset if one was active (`easyeffects -a`? check 8.3's CLI with `easyeffects --help`) else bypass; EasyEffects missing → pane line "Install EasyEffects for the equaliser".
- [ ] **Step 6:** `part Eq`: ten vertical sliders with Hz labels, preamp, preset chips (mooi's seven, then the user's EasyEffects presets listed from `output/*.json`, loadable with `easyeffects -l <name>` and never written), SAVE AS (name field → `player.eq` custom presets in settings), ON switch; the rack's knobs two-way.
- [ ] **Step 7:** Live: enable, pick BASS → `cat ~/.local/share/easyeffects/output/mooi.json` shows the bands, EasyEffects reports the preset loaded; the user's `live_eq.json`/`vespera_eq.json` unchanged (`cksum` before/after); screenshot the pane dark and light.
- [ ] **Step 8:** Commit `Player equaliser through EasyEffects`.

### Task 8: Music video as the visual

**Files:**
- Create: `shell/player/video.luau`
- Modify: `shell/lib/player.luau`, `shell/player/deck.plm`, `shell/player/stage.plm`, `shell/player/full.plm` (VIDEO chip; the visual box left undrawn while `video_on`, with a 1 px frame), `shell/mooi-player.plm` (`run` adds `yt-dlp`, `mpv`, `hyprctl`, `socat`; facts `video_on`, `video_busy`, `vbx/vby/vbw/vbh`), `shell/lib/config.luau` (`player.video` true)
- Test: `tests/unit/run.lua`

**Interfaces:**
- Produces: `P.video_query(artist: string, title: string) -> string | nil` (`ytsearch1:<artist> - <title> official video`; nil without a title), `P.video_allowed(src: string, song) -> bool, reason: string` (mpd source and a title), `P.resume_at(video_t: number, song_len: number) -> number` (clamped to the song, 0 if beyond).
- Produces: events `video_toggle ->`.
- mpv: `mpv --no-border --title=mooi-video --force-window=immediate --ytdl-format="bv*[height<=1080]+ba/b" --input-ipc-server=$XDG_RUNTIME_DIR/mooi-video.sock <url>`; rule applied once per session with `hyprctl eval` (`hl.window_rule` for `title:^mooi-video$`: float, pin, no focus, no border, no shadow — confirm the Lua rule API by passing a bogus argument, as D45 did); placed with `hyprctl dispatch` move/resize to the box (`vbx…` in screen coordinates) under the player's overlay.

- [ ] **Step 1: Write the failing tests**

```lua
test("video: the search names the song", function()
    eq(player.video_query("Jimmy Eat World", "The Middle"), "ytsearch1:Jimmy Eat World - The Middle official video", "query")
    eq(player.video_query("X", ""), nil, "no title, no search")
end)
test("video: offered only for mpd songs with a title", function()
    local ok, why = player.video_allowed("remote", { title = "a" }); eq(ok, false, "remote"); eq(why ~= "", true, "says why")
    eq((player.video_allowed("library", { title = "a" })), true, "mpd song")
end)
test("video: mpd resumes where the video reached", function()
    eq(player.resume_at(65.2, 243), 65.2, "inside"); eq(player.resume_at(300, 243), 0, "past the end")
end)
```

- [ ] **Step 2:** Run — FAIL. **Step 3:** Implement. **Step 4:** Run — PASS.
- [ ] **Step 5:** `player/video.luau`: press → `video_busy`; `mpc pause`; spawn mpv; wait for its window (`hyprctl -j clients`, ≤ 3 s) → place it; follow its time over the IPC socket (`{"command":["get_property","time-pos"]}` every 500 ms) into the progress; stop (chip, Escape, view change, track end) → quit mpv, `mpc seek <resume_at>`, `mpc play`. Not mapped / refused → fallback A: leave mpv floating and centred over the player, footer "VIDEO IN A WINDOW". No result → "NO VIDEO FOUND".
- [ ] **Step 6:** Live (the user's speakers: low volume, ask first if they are in a call): VIDEO on deck → video fills the record box, progress follows, close → mpd resumes near the video time; same in full screen; with Spotify as source the chip is disabled with its reason. Screenshot.
- [ ] **Step 7:** Commit `Player: the music video as the visual`.

### Task 9: Docs, decision, push

**Files:**
- Modify: `docs/PLAYER.md` (sizes, views, visualisers, library, EQ, video), `docs/DECISIONS.md` (D92), `README.md` (player line)

- [ ] **Step 1:** Write D92 (what changed, what was checked live, what was not) and update PLAYER.md/README.
- [ ] **Step 2:** `bin/mooi check` — all pass; `git push`.
- [ ] **Step 3:** Update the session handoff memory and the roadmap (music player done; next: the system-wide corner style).
