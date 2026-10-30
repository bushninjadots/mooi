# Music on Every Edge Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** One shared audio feed drives a reusable rim of bars around the real border of every phase-one mooi surface, so music moves them as one system and silence leaves every border exactly as it is today.

**Architecture:** `shell/bar.luau` becomes the only cava producer: it analyses 32 bands and atomically writes one versioned `viz-levels.txt` line at up to 30 Hz. Nexus, notch and player drop their own cava and watch that file, mapping 32 bands into their existing fact names. A new Pleamar library, `shell/ui/rim.plm`, draws bars outward from any straight edge (or four edges of a rectangle) from shared `rm*` facts, with per-side group glow. Geometry is drawn over each surface's existing border; no second base border is added.

**Tech Stack:** Luau scenes, Pleamar 0.4.6 (`language 0.4`), cava, plain Lua 5.4 unit tests, shell integration tests, Python settings generator.

**Spec:** `docs/superpowers/specs/2026-10-29-music-surface-rims-design.md`

## Global Constraints

- Pleamar 0.4.6 · language 0.4; verify every `.plm` with `pleamar --check`.
- One cava process at a time, 32 bands, 30 fps, pipewire/raw/ascii, `noise_reduction = 66`.
- Feed format, exactly: `v1 <32 ints 0..1000> <bass> <high> <beat> <phase> <playing> <missing> <seq>`.
- Feed file name: `viz-levels.txt`; stale after 2000 ms; publish max 30 times a second, keepalive at least every 500 ms, immediately on play/pause/stop.
- Rim facts: `rm0 … rm15`, `rm_bass`, `rm_high`, `rm_beat`, `rm_phase`, `rm_gain`, `rm_glow`, `rm_on`.
- Bar height = `reach * rm_gain * band * (0.75 + 0.25 * rm_beat) * (0.9 + 0.1 * sin(2π(rm_phase - pos)))`; `reach` 8–12 px; `rm_gain` caps at 1.5; fill `mix(tint, hot, 0.35 * rm_beat)`; 1 px cap in `line_c`.
- Bar density ≈ one per 12–16 px, minimum 6, maximum 32 per edge.
- Glow: one group per side, radius `7 * scale`, amount `0.7 * rm_beat` gated by `rm_glow` and `rm_on`.
- At rest (`rm_on = 0`) a rim draws nothing. No rim on the screen frame, monitor, Settings, board, wallpaper, desk or BMO.
- `motion.reduced` and `motion.saver == "always"` force rims to rest and stop cava for the rim alone.
- Master setting `music.rim` (default true), strength `music.rim_gain` (integer 25–150, default 100), glow `music.rim_glow` (default true). `bar.foot_visualizer` is read only when `music.rim` is absent. `frame.music` defaults to false.
- Preserve every existing inner visualiser: `lv0..lv15`, `vb0..vb15`, `mv0..mv23`, `nv0..nv23`, `dv0..dv31`, `ui/viz.plm`, `player.viz_*`.
- Never break `config.validate`'s never-throw contract; a bad feed line must decode to `nil`, never raise.
- Commit after every task; run `lua tests/unit/run.lua` before each commit.

## Review Focus

- A truncated, unknown-version or wrong-band-count feed line must be ignored, not crash a scene. Tested in Task 1.
- A repeated or older `seq` must not re-apply a frame, and a stale producer must settle the rims instead of freezing them. Tested in Tasks 1 and 5.
- A legacy config with `bar.foot_visualizer: false` and no `music.rim` must keep music off every edge. Tested in Task 3.
- `music.rim_gain` outside 25–150 or not whole must fall back to 100 with a reported problem, never reach geometry. Tested in Task 3.
- While music plays, `pgrep -c cava` must be exactly 1 across bar, Nexus, notch and player. Tested in Task 13.

---

### Task 0: Green baseline for yesterday's tree

**Files:**
- Modify: `shell/lib/wallpaper.luau:718-729`
- Test: `tests/unit/run.lua:2028-2044`

**Interfaces:**
- Consumes: nothing.
- Produces: a clean tree whose full unit suite and scene compiles pass, committed as the base for the rim work.

- [ ] **Step 1: Fix the sparse-table validity check**

Replace the `hex` accumulation in `M.state` so validity is explicit; `#` on a sparse table is undefined. Keep the accepted shape `{ c = { hex, hex, hex }, at = number }`:

```lua
local hex, good = {}, true
for i = 1, 3 do
    local h = tostring(c[i] or "")
    if h:match("^#%x%x%x%x%x%x$") then hex[i] = string.lower(h) else good = false end
end
if good then out.edges[k] = { c = hex, at = tonumber(e.at) or 0 } end
```

- [ ] **Step 2: Run the unit suite**

Run: `lua tests/unit/run.lua`
Expected: every test passes (previously `253 tests, 1 failed` at the wallpaper edges test).

- [ ] **Step 3: Compile every scene**

Run: `for f in shell/mooi.plm shell/mooi-nexus.plm shell/mooi-notch.plm shell/mooi-settings.plm shell/mooi-player.plm shell/bmo/bmo.plm; do pleamar --check "$f" || exit 1; done`
Expected: each prints its property count and exits 0.

- [ ] **Step 4: Commit yesterday's work as the baseline**

```bash
git add -A
git commit -m "Nexus two-row deck and wallpaper colours; the bar's foot bars; a BMO guard (D111)"
```

---

### Task 1: The feed codec

**Files:**
- Create: `shell/lib/vizfeed.luau`
- Test: `tests/unit/run.lua` (append a `vizfeed:` section before the summary)

**Interfaces:**
- Consumes: nothing; pure Lua.
- Produces:
  - `vizfeed.VERSION = "v1"`, `vizfeed.BANDS = 32`, `vizfeed.FILE = "viz-levels.txt"`, `vizfeed.STALE_MS = 2000`
  - `vizfeed.encode(t) -> string`
  - `vizfeed.decode(text) -> table | nil` with fields `bands` (array of 32 numbers 0..1), `bass`, `high`, `beat`, `phase` (0..1), `playing` (boolean), `missing` (boolean), `seq` (integer)
  - `vizfeed.silent(seq) -> table` (all zero bands, `playing = false`, `missing = false`, given `seq`)
  - `vizfeed.newer(prev_seq, seq) -> boolean`
  - `vizfeed.fresh(last_ms, now_ms) -> boolean`
  - `vizfeed.map(bands, n) -> table` with `n` values sampled evenly from the 32, endpoints preserved

- [ ] **Step 1: Write the failing codec tests**

Append to `tests/unit/run.lua`:

```lua
local vizfeed = require("lib/vizfeed")
test("vizfeed: a full frame round-trips", function()
    local t = vizfeed.silent(7)
    t.bands[1], t.bands[16], t.bands[32] = 1, 0.5, 0.25
    t.bass, t.high, t.beat, t.phase, t.playing, t.missing, t.seq = 0.9, 0.4, 1, 0.75, true, false, 8
    local back = vizfeed.decode(vizfeed.encode(t))
    eq(back.seq, 8, "the counter"); eq(back.bands[1], 1, "the first band")
    eq(back.bands[16], 0.5, "a middle band"); eq(back.bands[32], 0.25, "the last band")
    eq(back.playing, true, "playing"); eq(back.missing, false, "not missing")
    eq(back.phase, 0.75, "phase"); eq(back.beat, 1, "beat")
end)
test("vizfeed: a partial or unknown line is refused without throwing", function()
    eq(vizfeed.decode(""), nil, "empty")
    eq(vizfeed.decode("v2 1 2 3"), nil, "unknown version")
    local line = vizfeed.encode(vizfeed.silent(1))
    eq(vizfeed.decode(line:sub(1, #line - 6)), nil, "truncated")
    eq(vizfeed.decode(line:gsub("v1 ", "v1 5 ")), nil, "too many bands")
end)
test("vizfeed: trailing fields are accepted for forward compatibility", function()
    local t = vizfeed.silent(3); t.playing = true
    local back = vizfeed.decode(vizfeed.encode(t) .. " future field")
    eq(back.seq, 3, "the known part still reads")
end)
test("vizfeed: only a newer counter is new", function()
    eq(vizfeed.newer(4, 5), true, "newer"); eq(vizfeed.newer(5, 5), false, "same")
    eq(vizfeed.newer(5, 4), false, "older"); eq(vizfeed.newer(nil, 1), true, "first")
end)
test("vizfeed: freshness is a two-second window", function()
    eq(vizfeed.fresh(1000, 3000), true, "at the edge"); eq(vizfeed.fresh(1000, 3001), false, "past it")
    eq(vizfeed.fresh(nil, 3000), false, "never seen")
end)
test("vizfeed: 32 bands map onto 16 and 24 in order", function()
    local b = {}
    for i = 1, 32 do b[i] = i / 32 end
    local sixteen = vizfeed.map(b, 16)
    eq(#sixteen, 16, "sixteen"); eq(sixteen[1], b[1], "first"); eq(sixteen[16], b[32], "last")
    local twentyfour = vizfeed.map(b, 24)
    eq(#twentyfour, 24, "twenty-four"); eq(twentyfour[1], b[1], "first"); eq(twentyfour[24], b[32], "last")
    eq(vizfeed.map(b, 16)[2] < vizfeed.map(b, 16)[3], true, "order kept")
end)
```

- [ ] **Step 2: Run the tests to see them fail**

Run: `lua tests/unit/run.lua`
Expected: FAIL at `require("lib/vizfeed")` (module not found) or the first `vizfeed` test.

- [ ] **Step 3: Implement the codec**

`encode` writes fixed-width integers: `math.floor(clamp(v, 0, 1) * 1000 + 0.5)` for each band and for `bass/high/beat/phase`; `playing` and `missing` are 0/1; `seq` is the raw integer. Join with single spaces. `decode` splits on whitespace, requires `VERSION`, requires exactly 39 numeric fields after it (32 bands + 4 scalars + playing + missing + seq), rejects any non-numeric token, scales bands and the four scalars by `/1000`, clamps them, converts flags with `== 1`, and returns `nil` on any shortfall. Ignore fields after the 39th. `map` returns `n` values at `round(1 + (i-1) * 31/(n-1))` for `i = 1..n` (for `n == 1`, return the mean).

- [ ] **Step 4: Run the tests to see them pass**

Run: `lua tests/unit/run.lua`
Expected: the six `vizfeed:` tests pass and the suite is green.

- [ ] **Step 5: Commit**

```bash
git add shell/lib/vizfeed.luau tests/unit/run.lua
git commit -m "vizfeed: one versioned line of 32 bands, decoded defensively"
```

---

### Task 2: The shared analysis (level, high, beat, phase)

**Files:**
- Modify: `shell/lib/vizfeed.luau`
- Test: `tests/unit/run.lua`

**Interfaces:**
- Consumes: `vizfeed` from Task 1.
- Produces: `vizfeed.analyse(prev, bands, dt) -> state` where `state` has `level`, `high`, `bass`, `beat`, `phase` (0..1), `tempo` (seconds per beat or 0), `last_beat` (seconds), `t` (seconds). `prev` may be `nil`. `bands` is 32 numbers 0..1 and `dt` is seconds.

- [ ] **Step 1: Write the failing analysis tests**

```lua
test("vizfeed: analysis follows the bass and treble with an envelope", function()
    local b = {}; for i = 1, 32 do b[i] = 0.8 end
    local s = vizfeed.analyse(nil, b, 1 / 30)
    eq(s.bass > 0.8, true, "bass lifted"); eq(s.level > 0, true, "level moves")
    local quiet = {}; for i = 1, 32 do quiet[i] = 0 end
    local down = vizfeed.analyse(s, quiet, 1 / 30)
    eq(down.level < s.level, true, "and releases, slower than it attacked")
end)
test("vizfeed: a rising bass edge beats once, then waits out the refractory", function()
    local loud = {}; for i = 1, 32 do loud[i] = 0.9 end
    local quiet = {}; for i = 1, 32 do quiet[i] = 0 end
    local a = vizfeed.analyse(nil, quiet, 1 / 30)
    local beat = vizfeed.analyse(a, loud, 1 / 30)
    eq(beat.beat > 0.9, true, "the edge beats")
    local again = vizfeed.analyse(beat, loud, 1 / 30)
    eq(again.beat < beat.beat, true, "it decays")
    eq(vizfeed.analyse(again, loud, 1 / 30).beat < again.beat, true, "and keeps decaying")
end)
test("vizfeed: phase turns and wraps in 0..1", function()
    local b = {}; for i = 1, 32 do b[i] = 0.2 end
    local s = { level = 0, high = 0, bass = 0.2, beat = 0, phase = 0.98, tempo = 0, last_beat = 0, t = 0 }
    local n = vizfeed.analyse(s, b, 0.1)
    eq(n.phase < 0.98, true, "wrapped"); eq(n.phase >= 0, true, "and stayed in range")
    eq(n.t > s.t, true, "time advances")
end)
```

- [ ] **Step 2: Run them and see the failure**

Run: `lua tests/unit/run.lua`
Expected: FAIL with `attempt to call a nil value (field 'analyse')`.

- [ ] **Step 3: Implement `analyse`**

Copy the existing bar recipe, operating on normalized bands: `bass = min(1, sqrt(mean(b[1..4])) * 1.4)`, `high = min(1, sqrt(mean(b[27..32])) * 1.8)`. `level` attack 16, release `2.6 + 3 * level`; `high` attack 14, release 4; both use `min(1, rate * dt)`. A beat fires when `bass > 0.55` and `prev.bass <= 0.55` and `t - last_beat >= 0.25`; on a beat set `beat = 1`, `last_beat = t`, and if the previous interval is 0.25–2 s set `tempo` to a 0.5-weighted blend of it, else keep `tempo`. Otherwise decay `beat` by `max(0, prev.beat - 4 * dt)`. Advance `phase` by `dt / tempo` when `tempo > 0`, else `dt * (0.35 + 0.65 * level)`, wrapping with `% 1`.

- [ ] **Step 4: Run the tests**

Run: `lua tests/unit/run.lua`
Expected: all `vizfeed:` tests, including the three analysis tests, pass.

- [ ] **Step 5: Commit**

```bash
git add shell/lib/vizfeed.luau tests/unit/run.lua
git commit -m "vizfeed: one envelope, one beat and one phase for every surface"
```

---

### Task 3: Settings, the legacy alias and the frame default

**Files:**
- Modify: `shell/lib/config.luau:44`, `:62`, `:313-315`, `:539-550`
- Modify: `tools/gen-settings.py:15-64`, `:196`, `:422-423`
- Modify: `shell/lib/setters.luau` (generated `SETTERS` mirror)
- Modify: `shell/mooi.luau:80`, `shell/mooi-nexus.luau` (`dk_viz`), `shell/mooi-notch.luau`, `shell/mooi-player.luau` (fact publishing)
- Generated: `shell/mooi-settings.plm`, `shell/lib/settings_index.luau`, edit grips in `shell/mooi.plm`
- Test: `tests/unit/run.lua`

**Interfaces:**
- Consumes: `config` schema/defaults/validate from `shell/lib/config.luau`.
- Produces:
  - `settings.music.rim`, `settings.music.rim_gain`, `settings.music.rim_glow`
  - `fact.music_rim`, `fact.music_rim_gain`, `fact.music_rim_glow` in every scene that draws a rim (bar, Nexus, notch, player)
  - `bar.foot_visualizer` still validates, but only supplies `music.rim` when the latter is absent
  - `frame.music` default false

- [ ] **Step 1: Write the failing config tests**

```lua
test("config: music on every edge, with the old foot switch as the fallback", function()
    local s = config.validate({ music = { rim = false } })[1]
    eq(s.music.rim, false, "the master reads")
    eq(config.validate({ music = { rim = true }, bar = { foot_visualizer = false } })[1].music.rim, true, "the master wins when both are present")
    eq(config.validate({ bar = { foot_visualizer = false } })[1].music.rim, false, "the old switch is read when the master is absent")
    eq(config.validate({ bar = { foot_visualizer = true } })[1].music.rim, true, "including on")
    eq(config.defaults().music.rim, true, "on by default")
end)
test("config: the rim's strength and glow", function()
    eq(config.defaults().music.rim_gain, 100, "100 by default")
    eq(config.defaults().music.rim_glow, true, "glow by default")
    local s, problems = config.validate({ music = { rim_gain = 300 } })
    eq(s.music.rim_gain, 100, "out of range falls back")
    eq(#problems, 1, "and is reported")
    eq(config.validate({ music = { rim_gain = 25 } })[1].music.rim_gain, 25, "the low end")
    eq(config.validate({ music = { rim_gain = 150 } })[1].music.rim_gain, 150, "the high end")
end)
test("config: the screen frame's music is off by default", function()
    eq(config.defaults().frame.music, false, "retired unless asked for")
end)
```

- [ ] **Step 2: Run them and see the failure**

Run: `lua tests/unit/run.lua`
Expected: FAIL on `music.rim` (nil) and on `frame.music` (true).

- [ ] **Step 3: Add the schema and the alias**

Add near the other `bar` rows:

```lua
-- music on every mooi edge: the master, its strength and the halo
{ path = "music.rim", kind = "boolean", default = true },
{ path = "music.rim_gain", kind = "integer", default = 100, min = 25, max = 150 },
{ path = "music.rim_glow", kind = "boolean", default = true },
```

Change `frame.music` to `default = false`. In `M.validate`, after the schema loop and before the layout check, apply the alias only when the raw file has no `music.rim`:

```lua
-- D112: the bar's foot switch was the first rim. A file that predates music.rim keeps its answer.
local master = get(t, "music.rim")
local legacy = get(t, "bar.foot_visualizer")
if master == nil and legacy ~= nil then
    if type(legacy) == "boolean" then
        set(out, "music.rim", legacy)
        notes[#notes + 1] = "music.rim: read from bar.foot_visualizer"
    end
end
```

Do not rewrite `bar.foot_visualizer` in the file and do not add it to `migrate`.

- [ ] **Step 4: Run the config tests**

Run: `lua tests/unit/run.lua`
Expected: the three new config tests pass; the rest stay green.

- [ ] **Step 5: Add the setters and regenerate Settings**

Add to `tools/gen-settings.py` `SETTERS`, after `"bar.foot_visualizer"`:

```python
"music.rim", "music.rim_gain", "music.rim_glow",
```

Replace the Bar row at line ~196 with the master, strength and glow rows (keep the old key's row out of the window; the alias is described in the master's description):

```python
("toggle", "Music on every edge", "The whole border of every mooi surface steps with the music; the old foot switch is honoured when this is absent", "music.rim", "music_rim", None, "not st_notch"),
("slider", "Edge strength", "How far the bars reach out of the border", "music.rim_gain", 25, 150, "{sv_music_rim_gain, 0}%", "music_rim"),
("toggle", "Edge glow", "A halo on each lit edge, only while music plays", "music.rim_glow", "music_rim_glow", None, "music_rim"),
```

Relabel the Nexus rows at lines ~422–423, keeping their paths and behaviour:

```python
("toggle", "Music on the deck's edges", "The deck's own override; off keeps its plain border even when the master is on", "nexus.visualiser", "sv_nexus_visualiser", None, "sv_nexus_mode == 0"),
("choice", "Bars on the deck's edges", "How many bars the deck's border is cut into; the notches' outer faces carry their own share", "nexus.bars", "sv_nexus_bars", ["8", "12", "16", "24"], "sv_nexus_mode == 0 and sv_nexus_visualiser == 1"),
```

Run `python3 tools/gen-settings.py`, then inspect `git diff --stat` to confirm it rewrote `shell/mooi-settings.plm`, `shell/lib/settings_index.luau` and the edit grips only.

- [ ] **Step 6: Publish the facts in each scene**

In `shell/mooi.luau`, replace `fact.bar_foot_viz = ...` with the three facts:

```lua
fact.music_rim = s.music.rim
fact.music_rim_gain = s.music.rim_gain / 100
fact.music_rim_glow = s.music.rim_glow
```

Do the same in `mooi-nexus.luau` (its settings table is `n`), `mooi-notch.luau` and `mooi-player.luau`, where each scene reads its own `settings`/`n`. Remove `bar_foot_viz` from the settings scene only if nothing still reads it. In `mooi-nexus.luau`, keep `fact.dk_viz = n.visualiser ~= false`; the deck override combines with the master in the rim.

- [ ] **Step 7: Compile and test**

Run: `lua tests/unit/run.lua`, then `for f in shell/mooi.plm shell/mooi-nexus.plm shell/mooi-notch.plm shell/mooi-settings.plm shell/mooi-player.plm; do pleamar --check "$f" || exit 1; done`
Expected: all green; `mooi-settings.plm` has the three new rows and facts.

- [ ] **Step 8: Commit**

```bash
git add shell/lib/config.luau shell/lib/setters.luau shell/lib/settings_index.luau shell/mooi-settings.plm shell/mooi.plm shell/mooi.luau shell/mooi-nexus.luau shell/mooi-notch.luau shell/mooi-player.luau tools/gen-settings.py tests/unit/run.lua
git commit -m "Settings: music on every edge, its strength and glow; the foot switch kept as the alias"
```

---

### Task 4: The bar becomes the only producer

**Files:**
- Modify: `shell/bar.luau:267-361`
- Modify: `shell/lib/vizfeed.luau` (add `should_publish`)
- Test: `tests/unit/run.lua`

**Interfaces:**
- Consumes: `vizfeed.encode`, `silent`, `analyse` (Tasks 1–2).
- Produces: `viz-levels.txt` in the scene's files folder; `fact.fbass`, `fact.fhigh`, `fact.fph`, `fact.lv0..lv15` derived from the same 32 bands; `vizfeed.should_publish(prev, now, now_ms, last_ms, keepalive) -> boolean` (pure cadence helper).

- [ ] **Step 1: Write the failing cadence test**

```lua
test("vizfeed: publishing is capped at 30 a second and keeps alive at 2 Hz", function()
    local a = vizfeed.silent(1); a.bands[1] = 0.9
    local b = vizfeed.silent(2); b.bands[1] = 0.9
    eq(vizfeed.should_publish(a, b, 100, 0, 500), true, "50 ms since the last publish")
    eq(vizfeed.should_publish(a, b, 520, 500, 500), false, "same bands, not yet due")
    eq(vizfeed.should_publish(a, b, 1000, 500, 500), true, "the keepalive wins")
    local changed = vizfeed.silent(3); changed.bands[1] = 0.1
    eq(vizfeed.should_publish(a, changed, 520, 500, 500), true, "a real change goes at once")
end)
```

- [ ] **Step 2: Run it and see the failure**

Run: `lua tests/unit/run.lua`
Expected: FAIL with `should_publish` nil.

- [ ] **Step 3: Implement the cadence helper**

`should_publish(prev, now, now_ms, last_ms, keepalive)` returns true when `now_ms - last_ms >= 33`, when any band or scalar differs from `prev` by more than `0.002`, or when `now_ms - last_ms >= keepalive`. Compare `playing`, `missing` and `seq` separately; `seq` always differs and must not count as a content change.

- [ ] **Step 4: Test the helper**

Run: `lua tests/unit/run.lua`
Expected: the cadence test passes.

- [ ] **Step 5: Make cava produce 32 bands and publish**

In `bar.luau`: change `bars = 16` to `bars = 32`; open up the parser's cap to 31 and collect all 32 `b[]` values. Keep `lv0..lv15` from bands 1..16 exactly as today (same indices and epsilon). Feed the 32 normalized bands to `vizfeed.analyse`, keep `fact.fbass/fhigh/fph` from the returned state, and publish:

```lua
local seq = 0
local last_ms, last_at, prev = 0, 0, nil
local function publish(state, missing)
    seq = seq + 1
    local t = { bands = bands, bass = state.bass, high = state.high, beat = state.beat,
                phase = state.phase, playing = playing, missing = missing, seq = seq }
    if prev and not vizfeed.should_publish(prev, t, now_ms, last_ms, 500) then return end
    prev, last_ms, last_at = t, now_ms, os.time()
    sys.call("files.write", vizfeed.FILE, vizfeed.encode(t))
end
```

Use the cava frame count for `now_ms` (`frame * 1000 / 30`) rather than a clock. On `hush()` and on pause/stop, increment `seq`, write `vizfeed.encode(vizfeed.silent(seq))` immediately, and reset `prev`. Pass `missing = viz_missing` so a machine without cava publishes the flag once.

- [ ] **Step 6: Include the rim in what starts cava**

In `readers()`:

```lua
local want_rim = s.music.rim == true and not (s.motion.reduced or s.motion.saver == "always")
local want_viz = placed.media and s.bar.visualizer ~= "off" and s.media.mode ~= "art"
local want_swell = s.frame.on and s.frame.music
if playing and (want_viz or want_swell or want_rim) and not ctx.saving() and not viz_missing then listen() else hush() end
```

While `motion.reduced` or `motion.saver == "always"` is on, publish silence once and do not start cava for the rim alone.

- [ ] **Step 7: Verify by hand**

Run: `lua tests/unit/run.lua`
Expected: green.
Then in a live session with music playing: `cat "${XDG_DATA_HOME:-$HOME/.local/share}/pleamar/mooi/viz-levels.txt"` twice a second apart. Expected: `v1` plus 39 fields, the `seq` rising, the first field changing with the music. Pause: one silent line, `seq` still rising, `playing` 0. `pgrep -c cava` → 1.

- [ ] **Step 8: Commit**

```bash
git add shell/bar.luau shell/lib/vizfeed.luau tests/unit/run.lua
git commit -m "Bar: 32 bands, one analysis and one published feed for every surface"
```

---

### Task 5: The Nexus reads the feed; its cava goes

**Files:**
- Modify: `shell/mooi-nexus.luau:510-548` and its `run:` permissions at `shell/mooi-nexus.plm:19`
- Test: `tests/nexus.sh`

**Interfaces:**
- Consumes: `vizfeed.decode`, `newer`, `fresh`, `map`, `FILE`.
- Produces: `dv0..dv31` from the shared bands while the deck is open; `fact.mus_on`; `mu_viz_missing` equivalent (`fact.dk_missing` not needed if the existing notice remains).

- [ ] **Step 1: Write the failing integration check**

Append to `tests/nexus.sh`, following its existing start/wait/`pleamar --say` style:

```bash
viz="$out/data/pleamar/mooi/viz-levels.txt"
printf 'v1 %s 900 400 700 500 1 0 41\n' "$(yes 500 | head -32 | tr '\n' ' ')" >"$viz"
sleep 1
say_get mooi-nexus dv0 | grep -q '0\.[4-6]'
```

Use the harness's actual `say_get`/`get` helper name; the assertion is `dv0` follows the 500/1000 band within a second.

- [ ] **Step 2: Run it and see the failure**

Run: `tests/nexus.sh`
Expected: FAIL — `dv0` stays 0 because the scene still spawns its own cava.

- [ ] **Step 3: Replace cava with the feed watch**

Delete `CAVA`, the config write, `spawn("cava", ...)`, `hush()`'s kill and all `sent` bookkeeping from `mooi-nexus.luau`. Add:

```lua
local viz_seq, viz_at = nil, 0
local function rest_viz()
    for i = 0, 31 do fact["dv" .. i] = 0 end
end
local function take_viz()
    local ok, raw = pcall(sys.ask, "files.read", vizfeed.FILE)
    if not ok or type(raw) ~= "string" then return end
    local t = vizfeed.decode(raw)
    if not t or not vizfeed.newer(viz_seq, t.seq) then return end
    viz_seq, viz_at = t.seq, os.time()
    if not (fact.dk_open and fact.dk_viz) then return end
    for i = 0, 31 do fact["dv" .. i] = t.bands[i + 1] end
    fact.mus_on = t.playing == true
    if t.missing then notice("CAVA MISSING · pacman -S cava") end
end
pcall(sys.watch, "files:" .. vizfeed.FILE, take_viz)
every(500, function()
    if fact.dk_open and fact.dk_viz and viz_seq and not vizfeed.fresh(viz_at * 1000, os.time() * 1000) then
        viz_seq, viz_at = nil, 0
        rest_viz()
        fact.mus_on = false
    end
end)
```

Call `take_viz()` once at startup. Remove `cava` from `shell/mooi-nexus.plm`'s `run:` permissions.

- [ ] **Step 4: Run the integration check**

Run: `tests/nexus.sh`
Expected: PASS; the existing 37 checks still pass. Then `pgrep -c cava` while only the Nexus is open and music plays → 0 (the bar owns the one cava).

- [ ] **Step 5: Commit**

```bash
git add shell/mooi-nexus.luau shell/mooi-nexus.plm tests/nexus.sh
git commit -m "Nexus: the deck reads the shared feed; its own cava is gone"
```

---

### Task 6: The notch reads the feed; its cava goes

**Files:**
- Modify: `shell/mooi-notch.luau:261-318`; `shell/mooi-notch.plm:16` (permissions)
- Test: compile + live feed injection

**Interfaces:**
- Consumes: `vizfeed.decode`, `newer`, `fresh`, `map`, `FILE`.
- Produces: `mv0..mv23` sampled from the 32 bands while the Music tab is open; `fact.mu_viz_missing` from the feed's `missing`.

- [ ] **Step 1: Add a failing assertion to the notch's existing test harness**

Whatever harness starts `mooi-notch` (`tests/scene.sh` or `tests/media.sh`), write a feed line with all bands 800 and assert `mv0` is 0.8 within a second — and that `pgrep -c cava` stays 1 with the bar running. If no notch harness exists, add the check to `tests/integration.sh` using the same temp-folder pattern as `tests/nexus.sh`.

- [ ] **Step 2: Run it and see the failure**

Run the harness. Expected: FAIL — `mv0` does not follow the injected file.

- [ ] **Step 3: Replace cava with the feed watch**

Delete `cava`, `CAVA`, the config write, the spawn and `sent` from `mooi-notch.luau`. Add a `take_viz()` with the same shape as Task 5, but gated on `fact.nt_open and fact.nt_tab == 1`, writing `fact["mv" .. i] = vizfeed.map(t.bands, 24)[i + 1]` for `i = 0..23`. Set `fact.mu_viz_missing = t.missing == true` and keep the existing "CAVA MISSING" display. On stale (2 s), zero `mv` and set `mu_viz_missing` unchanged. Call `take_viz()` at startup and from the existing `nt_open`, tab and `nt_close` handlers instead of `viz()`. Remove `cava` from `shell/mooi-notch.plm`'s permissions.

- [ ] **Step 4: Verify**

Run the harness; expected PASS. `pleamar --check shell/mooi-notch.plm` → 0. Open the Music tab with music playing: bars follow, then stop the bar's feed (`pkill -STOP` the bar's cava) — after 2 s the bars settle to zero, not freeze.

- [ ] **Step 5: Commit**

```bash
git add shell/mooi-notch.luau shell/mooi-notch.plm tests
git commit -m "Notch: the panels read the shared feed; its own cava is gone"
```

---

### Task 7: The player reads the feed; its cava goes

**Files:**
- Modify: `shell/mooi-player.luau:329-374`; `shell/mooi-player.plm:16`
- Test: compile + live feed injection

**Interfaces:**
- Consumes: `vizfeed.decode`, `newer`, `fresh`, `map`, `FILE`.
- Produces: `nv0..nv23` sampled from the 32 bands while the player is open; `fact.viz_missing` retained for the existing message.

- [ ] **Step 1: Add the failing assertion**

Extend the player's harness (same pattern as Task 6) to inject all-800 bands and assert `nv0` is 0.8 within a second, then a stale file asserts `nv0` settles to 0.03.

- [ ] **Step 2: Run it and see the failure**

Expected: FAIL — `nv0` does not move.

- [ ] **Step 3: Replace cava with the feed watch**

Delete `CAVA`, the config write, `spawn`, `hush()`'s kill and `sent`. Add `take_viz()` gated on `fact.pl_open ~= 0 and fact.pstate == "playing" and not fact.viz_still`, writing `fact["nv" .. i] = vizfeed.map(t.bands, 24)[i + 1]` for `i = 0..23`. Leave `player.viz_*` and every use of `nv` untouched. On stale, write `0.03` to every `nv`. Call `take_viz()` at startup and in the existing `viz()` call sites; remove `cava` from `shell/mooi-player.plm` permissions.

- [ ] **Step 4: Verify**

Run the harness → PASS. `pleamar --check shell/mooi-player.plm` → 0. Open mini, panel and cinema with music: the inner visualisers still move; `pgrep -c cava` → 1 with the bar.

- [ ] **Step 5: Commit**

```bash
git add shell/mooi-player.luau shell/mooi-player.plm tests
git commit -m "Player: the inner visualisers read the shared feed; its own cava is gone"
```

---

### Task 8: The `Rim` library

**Files:**
- Create: `shell/ui/rim.plm`
- Test: `pleamar --check shell/ui/rim.plm` plus a scratch scene render

**Interfaces:**
- Consumes scene facts `rm0..rm15`, `rm_bass`, `rm_high`, `rm_beat`, `rm_phase`, `rm_gain`, `rm_glow`, `rm_on`.
- Produces `library Rim` with:
  - `component Edge(u0: number, u1: number, span0: number, span1: number, at: number, dir: number, n: number, tint: color, hot: color, line_c: color, reach: number = 10, vertical: bool = false)`
  - `component Rect(x: number, y: number, w: number, h: number, r: number, mask: number, tint: color, hot: color, line_c: color, reach: number = 10, density: number = 14)`
  - each `Edge` wraps its bars in one `group { glow: 7, 0.7 * rm_beat * rm_glow, hot }`; there is no separate public glow component

Mask bits: `1` top, `2` right, `4` bottom, `8` left. `Rect` draws only enabled sides and leaves `r + 1` px corner gaps.

- [ ] **Step 1: Write the library header and the contract**

`shell/ui/rim.plm` starts `language 0.4`, imports `../theme/tokens.plm` and `../theme/ferrolume.plm`, then `library Rim { ... }`. The header documents the eight facts, the mask bits and the rest rule: when `rm_on < 0.5`, every bar height is 0 and nothing but the existing border shows.

- [ ] **Step 2: Implement `Edge`**

Use the `EdgeBars` technique (`shell/mooi-nexus.plm:778-815`) generalised:

```
let e = clamp(dir, -1, 1)
let pos = (u - span0) / max(1, span1 - span0)       // band place along the whole edge
let band = pick(round(pos * 15.99), rm0 … rm15)
let wave = 0.9 + 0.1 * sin(6.28318 * (rm_phase - pos))
let h = reach * clamp(rm_gain, 0, 1.5) * band * (0.75 + 0.25 * rm_beat) * wave * rm_on
```

One `group { show: rm_on > 0.5 and u1 - u0 > 2; glow: 7, 0.7 * rm_beat * rm_glow, hot }` containing `repeat b in 0..31`; each bar has `us = u0 + b * ew`, `uc = us + ew/2`, `on = b < n - 0.5`, `p0 = at - e * 1.2`, `p1 = at + e * hb`; draw a `box` fill `mix(tint, hot, 0.35 * rm_beat)`, a 1 px cap `line_c`, a step line to the previous bar and an end line at `b > n - 1.5`. `Edge` takes `at` as the coordinate perpendicular to the run and `u` along it; `vertical = false` means a horizontal edge (runs in x, grows in y) and `true` a vertical edge (runs in y, grows in x).

- [ ] **Step 3: Implement `Rect`**

Compute `n` per side: `clamp(round(len / density), 6, 32)`. Draw `Edge` for each enabled mask bit, with `span0/span1` the whole side length and `u0/u1` the side minus `r + 1` at both ends. For top: `at = y`, `dir = -1`, `vertical = false`; right: `at = x + w`, `dir = 1`, `vertical = true`; bottom: `at = y + h`, `dir = 1`, `vertical = false`; left: `at = x`, `dir = -1`, `vertical = true`.

- [ ] **Step 4: Check it compiles**

Run: `pleamar --check shell/ui/rim.plm`
Expected: exit 0 with a property count.

- [ ] **Step 5: Render a scratch check**

Add a temporary surface to the library (not committed) or import it into a copy of `mooi-nexus.plm`, set the `rm*` facts by hand (`rm_on 1`, `rm_gain 1`, `rm_beat 0.5`, `rm_phase 0.25`, alternating `rm0..rm15`), run the scene and confirm bars grow outward on all four sides and vanish at `rm_on 0`. Remove the scratch code.

- [ ] **Step 6: Commit**

```bash
git add shell/ui/rim.plm
git commit -m "Rim: bars on any straight edge, four-sided rects and per-side glow"
```

---

### Task 9: Rims on the bar (all modes and pop-ups)

**Files:**
- Modify: `shell/mooi.plm` (imports; `BarFoot`; islands/full frame call sites; notch pieces)
- Modify: `shell/ui/island.plm` (`IslandFrame` optional `rim`)
- Modify: `shell/mooi.luau` (map the feed to `rm*` facts for the bar)
- Test: `pleamar --check shell/mooi.plm` + visual matrix

**Interfaces:**
- Consumes: `Rim.Edge`, `Rim.Rect` (Task 8); `vizfeed` (Task 4); `music_rim*` facts (Task 3).
- Produces: bars on every exposed bar edge; the old `BarFoot` becomes one `Rim.Edge` on the notch pieces' bottom edges.

- [ ] **Step 1: Map the feed to rim facts in the bar scene**

In `mooi.luau`, keep the producer's 32 bands in a local, and on each publish set `fact.rm0..rm15` by folding pairs (`vizfeed.map(bands, 16)`), `fact.rm_bass`, `rm_high`, `rm_beat`, `rm_phase`, `rm_gain = s.music.rim_gain / 100`, `rm_glow = s.music.rim_glow and 1 or 0`, `rm_on = (playing and s.music.rim and not reduced and not saver) and 1 or 0`. On silence set `rm_on = 0`.

- [ ] **Step 2: Replace `BarFoot`**

Delete `component BarFoot` and its eight hard-coded heights. At each of the three notch-piece call sites, draw `Rim.Edge` along the piece's bottom edge with the piece's width as `span`, `at = fy`, `dir = 1`, `n = clamp(round(width / 14), 6, 32)`. The left piece keeps its left edge (`mask` 12 on a `Rim.Rect` if the piece is rectangular enough), centre bottom only, right piece right + bottom (`mask` 6). Use `fillc` = the piece's own hull and `line_c` = its `wv_edge` so it reads as the existing border lifting.

- [ ] **Step 3: Islands and full panel**

For islands mode, wrap each island frame: after `Frame(fx-3, fw+6, 0, f.style)` / `MechHousing`, draw `Rim.Rect(fx-3, 0, fw+6, bar_h, radius, 14, fillc, hot, edgec, reach)` — left, right and bottom, top masked because it is flush with the screen edge. For the full panel draw `Rim.Rect(0, 0, width, height, radius, 14, ...)`.

- [ ] **Step 4: Pop-ups**

Add `rim: bool = false` to `IslandFrame` in `shell/ui/island.plm`. When true, draw `Rim.Rect(left, top, iw, ih, irad, 14, ...)` inside the revealed group (before `children`) so the bars hug the body and clip with it. Pass `rim: true` at the 12 bar pop-up call sites listed in the plan research (`mooi.plm` lines 3945, 4038, 4074, 4119, 4156, 4207, 4252, 4289, 4348, 4407, 4435, 4641). Scenes without `rm*` facts draw nothing because `rm_on` is absent/0.

- [ ] **Step 5: Check and look**

Run: `pleamar --check shell/mooi.plm` → 0. With music: islands, full panel and notch each show bars only on exposed edges; pop-ups show left/right/bottom; at rest no extra line appears. Turn `music.rim` off in Settings → all bars vanish. Cycle solid/glass/blur/clear/mech: bars use the surface's own fill, no double border.

- [ ] **Step 6: Commit**

```bash
git add shell/mooi.plm shell/ui/island.plm shell/mooi.luau
git commit -m "Bar: the rim on every mode and pop-up; the foot bars generalised"
```

---

### Task 10: Rims on the Nexus deck, cards and tabs

**Files:**
- Modify: `shell/mooi-nexus.plm:770-877` (replace `EdgeBars` with `Rim.Edge`; import `ui/rim.plm`)
- Modify: `shell/mooi-nexus.luau` (map feed to `rm*`)
- Test: `tests/nexus.sh` + visual matrix

**Interfaces:**
- Consumes: `Rim.Edge`, `Rim.Rect`; `dk_bars`, `dk_vz`, `dk_edge`, `dk_vert`, `dk_notches`.
- Produces: the deck's open side and notch outer faces carry `Rim.Edge`; cards get glow only when focused.

- [ ] **Step 1: Map the feed in the Nexus scene**

On each accepted frame (Task 5), also set `rm0..rm15` from `vizfeed.map(t.bands, 16)`, `rm_bass/high/beat/phase`, `rm_gain = music_rim_gain`, `rm_glow = music_rim_glow and 1 or 0`, `rm_on = (t.playing and fact.dk_viz and fact.music_rim and not still) and 1 or 0`. When the deck closes or the feed is stale, `rm_on = 0`.

- [ ] **Step 2: Replace `EdgeBars` with `Rim.Edge`**

Keep the `DeckFrame` geometry and stretches. Replace each `EdgeBars(u0, u1, d, n, fillc, edgec)` with `Rim.Edge(u0, u1, 0, side_len, at, dir, n, fillc, accent, edgec, 12)` where `side_len` is `w` or `h`, `at` is `0`/`w`/`h` plus the notch offset `d` and `dir` faces outward. Delete `ht = 24 * dk_vz` and the `dk_vz` height multiplier: `Rim` owns height and the master. Keep `dk_bars` as `n`. Delete the old `EdgeBars` component.

- [ ] **Step 3: Notch tabs**

Replace the tabs' `EdgeBars(ex + 14, ex + 154, 34, ...)` with `Rim.Edge(..., at = tab outer face, dir = outward, n = clamp(round(140/14), 6, 32))`.

- [ ] **Step 4: Cards**

For the focused/cascade card only, wrap its plate in `Rim.Rect(0, 0, cw, ch, r, 15, ...)` with `reach = 8`. Every other card gets the existing glow only (no bars), so five spectra do not compete. `nexus.visualiser` off forces `rm_on = 0` on the deck and cards while leaving the master alone.

- [ ] **Step 5: Check and look**

Run: `pleamar --check shell/mooi-nexus.plm` → 0; `tests/nexus.sh` → PASS. Look at the deck on all four edges, horizontal and vertical, notches on and off: bars skip the notch gaps, continue on each tab's outer face, grow outward, and settle at rest. Master off → plain border; Nexus override off → plain deck while the bar still rims.

- [ ] **Step 6: Commit**

```bash
git add shell/mooi-nexus.plm shell/mooi-nexus.luau
git commit -m "Nexus: the deck and its notch tabs draw the shared rim"
```

---

### Task 11: Rims on the notch

**Files:**
- Modify: `shell/mooi-notch.plm` (panels, nub, fan tabs)
- Modify: `shell/mooi-notch.luau` (map feed to `rm*`)
- Test: `pleamar --check shell/mooi-notch.plm` + visual matrix

**Interfaces:**
- Consumes: `Rim.Rect`, `Rim.Edge`; panel geometry and `nt_*` facts.
- Produces: every open panel carries a four-sided rim; the nub glows only; fan tabs get a lit edge and glow, no bars.

- [ ] **Step 1: Map the feed**

On each accepted notch frame, set `rm0..rm15` from `vizfeed.map(t.bands, 16)`, the scalars, and `rm_on = (t.playing and fact.music_rim and not still) and 1 or 0`. On stale or closed, `rm_on = 0`.

- [ ] **Step 2: Panels**

In each panel body (the same box the panel's border path follows), draw `Rim.Rect(x, y, w, h, radius, 15, fillc, hot, edgec, 10)` immediately after the border path. Do not add a second base border.

- [ ] **Step 3: Nub and fan**

The nub gets no rim; keep or add `group { glow: 6, 0.5 * rm_beat * rm_glow, hot }` around its existing shape. Fan hexagons cannot carry straight bars: keep their existing edge and add the same glow amount, never `Rim.Edge`.

- [ ] **Step 4: Check and look**

Run: `pleamar --check shell/mooi-notch.plm` → 0. Open each panel: bars on all four exposed sides; the inner Music bars still move; the nub and fan glow on the beat but grow no bars; at rest the plain border returns.

- [ ] **Step 5: Commit**

```bash
git add shell/mooi-notch.plm shell/mooi-notch.luau
git commit -m "Notch: panels carry the shared rim; the fan and nub only glow"
```

---

### Task 12: Rims on the player

**Files:**
- Modify: `shell/player/mini.plm`, `shell/player/panel.plm`, `shell/player/full.plm`
- Modify: `shell/mooi-player.luau` (map feed to `rm*`)
- Test: `pleamar --check shell/mooi-player.plm` + visual matrix

**Interfaces:**
- Consumes: `Rim.Rect`; each view's outer plate coordinates.
- Produces: mini gets left/right/bottom, panel all four, cinema the inner plate's four (none when edge-to-edge); inner visualisers unchanged.

- [ ] **Step 1: Map the feed**

On each accepted player frame set `rm0..rm15` from `vizfeed.map(t.bands, 16)`, the scalars, `rm_gain` from the master strength, `rm_glow`, and `rm_on = (t.playing and fact.music_rim and not fact.viz_still) and 1 or 0`. On stale/close, `rm_on = 0`.

- [ ] **Step 2: Mini**

In `player/mini.plm`, after the `mbody` border, draw `Rim.Rect(0, 0, cw, ch, radius, 14, fillc, hot, edgec, 10)`.

- [ ] **Step 3: Panel**

In `player/panel.plm`, after the outer plate's border, draw `Rim.Rect(0, 0, pw, ph, radius, 15, fillc, hot, edgec, 10)`.

- [ ] **Step 4: Cinema**

In `player/full.plm`, draw `Rim.Rect` round the inner plate only (`Stage`/`Rack` frame), never the screen. If the view is edge-to-edge (`big` and full-bleed), draw nothing.

- [ ] **Step 5: Check and look**

Run: `pleamar --check shell/mooi-player.plm` → 0. Mini/panel/cinema all rim; the ring/spectrum and `player.viz_*` still behave exactly as before; at rest no extra line.

- [ ] **Step 6: Commit**

```bash
git add shell/player/mini.plm shell/player/panel.plm shell/player/full.plm shell/mooi-player.luau
git commit -m "Player: mini, panel and cinema carry the shared rim"
```

---

### Task 13: Integration, performance and the decision record

**Files:**
- Modify: `tests/nexus.sh`, `tests/integration.sh` / `tests/scene.sh`
- Modify: `docs/DECISIONS.md` (new D112)
- Modify: `docs/FERROLUME.md` if the new library belongs in its index
- Modify: `STATUS.md` / `README.md` only if they enumerate settings

**Interfaces:**
- Consumes: everything above.
- Produces: proof of one cava, feed lifecycle, master/override behaviour, and the performance sample.

- [ ] **Step 1: One cava**

Run the full shell with music: `pgrep -c cava` → exactly 1 for 30 s. With `music.rim` off and the bar's own visualiser/`frame.music` off, `pgrep -c cava` → 0.

- [ ] **Step 2: Feed lifecycle**

While playing, `viz-levels.txt`'s `seq` rises at 25–30 Hz and stalls at most 500 ms. Pause → one `playing 0` line; `seq` still rises on the next start. Delete the file while a consumer is open → no error, rims rest after 2 s, the file returns on the next publish.

- [ ] **Step 3: Master and override**

`music.rim` off → no bars anywhere. Nexus override off with master on → only the deck is plain. Legacy file with only `bar.foot_visualizer: false` → no bars anywhere; Settings shows the master off with the alias note.

- [ ] **Step 4: Reduced motion**

`motion.reduced` on → every rim rests, cava stops unless the bar's own visualiser or the frame swell still wants it. Same for `motion.saver == "always"`.

- [ ] **Step 5: Performance sample**

With the bar in each mode, sample 60 s with the rim on and 60 s off using the project's existing frame-time measurement; record the late-frame percentage. Target ≤5% and no regression against the rim-off sample. If exceeded, lower the bar count per edge first, then the glow radius, then disable glow on the largest surface.

- [ ] **Step 6: Manual matrix**

Walk: bar islands / full / notch; Nexus top / bottom / left / right and vertical; notch fan and each panel; player mini / panel / cinema; solid / glass / blur / clear / mech; motion reduced; cava absent. Record any deviation in the commit message or `docs/DECISIONS.md`.

- [ ] **Step 7: Write D112**

Add to `docs/DECISIONS.md`, in the existing style:

```markdown
## D112 · 2026-10-30 · Music on every edge
One cava in the bar, one `viz-levels.txt` line, and `ui/rim.plm` on every phase-one surface. …
```

Record the settings (`music.rim`, `music.rim_gain`, `music.rim_glow`), the `bar.foot_visualizer` alias, `frame.music` defaulting off, and the measured late-frame figures.

- [ ] **Step 8: Full verification**

Run: `lua tests/unit/run.lua`, every `pleamar --check`, `tests/nexus.sh`, the notch/player/integration harnesses.
Expected: all green. Then commit:

```bash
git add -A
git commit -m "Music on every edge: one feed, one rim, measured (D112)"
```

---

## Plan self-review

- **Spec coverage:** feed (Tasks 1–4), consumers (5–7), Rim (8), surfaces (9–12), settings and frame default (3), retirement and measurement (13). Standalone scenes are explicitly out of scope.
- **Types:** `vizfeed` names and return fields are used consistently in every consumer task; `Rim.Edge`/`Rect` signatures are fixed once in Task 8 and only called by later tasks.
- **Known gap:** the bar's `want_viz` still uses `s.motion` implicitly through `readers()`; Task 4 adds the explicit reduced/saver gate for the rim only. The existing inner visualisers keep their current motion behaviour.
- **Known gap:** `mooi-nexus.plm`'s `mus_on` currently comes from the media title; Task 5 replaces it with the feed's `playing` so the rim stops on pause even when the title remains.
