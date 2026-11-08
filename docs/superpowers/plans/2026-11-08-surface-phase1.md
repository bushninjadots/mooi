# Surface, phase 1: the engine and the touch — implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `mooi-surface` (the Sigil grown up): hold Super and the Aperture opens through the windows at the pointer, a Pill and a Hub rise in it, Music can be opened or dragged out and left on the desktop as a Presence that remembers itself and wakes when approached, and a Presence can be moved with undo.

**Architecture:** the Sigil's program, modules and generator are renamed (`mooi-sigil` → `mooi-surface`, `lib/sigil` → `lib/surface`, `gen-sigil` → `gen-surface`), keeping the bar hosts working. New pure modules `lib/surface/presence.luau` (model, memory, validation) and `lib/surface/reveal.luau` (stages, hub picking, release outcomes) carry the decisions; the scene gains a `reveal` overlay (mapped only while revealing) and a `desk` layer (level bottom) for Presences.

**Tech Stack:** Pleamar 0.7.11 scenes + WGSL group shader, Luau (Lua 5.4 tests), Python generators, Hyprland Lua binds, POSIX sh live tests.

**Spec:** `docs/superpowers/specs/2026-11-08-surface-design.md`

**Phasing calls (this plan, not the spec):** the edit gesture in phase 1 is **right-press on a Presence → edit mode** (drag moves, ↶ ↷ undo/redo, Done/Esc), because Pleamar scenes cannot see a held modifier on a click; Alt+Super comes when the binding work allows it. Music's modes in phase 1: ghost, embedded, full.

## Global Constraints

- Draw only on the program's own surfaces; never in the frame's band; effects only on the wallpaper image the program draws, in a patch, only while active.
- Never watch `notifications`/`notification_history` outside `signals.luau`.
- Setter codes append-only; generated files edited only through their generators (`gen-settings`, `gen-frame`, `gen-surface`); a new module goes in `tools/gen-settings.py` MODULES.
- A scene's data folder needs a link in `bin/mooi` `settings_link`; an event sent between programs must be declared in the receiving scene.
- `mooi.luau`'s main chunk is at 200 locals: state in the existing global table (renamed `SURFACE`).
- Each layer < 1 ms compose + paint at 60 fps; nothing mapped or repainting while idle; reduced motion = instant.
- Live tests restore `settings.json` and `surface.json` byte for byte; never move the real pointer.

## Review Focus

1. **A Super shortcut held past the delay** (no "up" ever arrives): the reveal must close on a workspace or focus change, Esc, a click outside, or 6 s idle — Task 3 test `reveal: a reveal never outlives its safeguards`.
2. **`surface.json` hand-edited or broken** (unknown source, NaN position, a Presence off-screen): dropped or clamped, the rest stands — Task 2 test `presence: bad entries dropped, positions clamped`.
3. **The monitor shrinks**: Presences come back on screen, never lost — Task 2 test `presence: a smaller screen clamps, never loses`.
4. **Leaving a Presence on top of another**: it is nudged clear, never stacked exactly — Task 2 test `presence: a drop onto another is nudged clear`.
5. **No wallpaper path yet / a video wallpaper**: the aperture still opens (plain subsurface), no error — Task 4 check in the scene test and `tests/surface.sh`.

---

### Task 1: Rename the Sigil into Surface (no behaviour change)

**Files:** `git mv` `shell/mooi-sigil.{plm,luau}` → `shell/mooi-surface.*`, `shell/lib/sigil/` → `shell/lib/surface/`, `tools/gen-sigil.py` → `tools/gen-surface.py`, `tests/sigil.sh` → `tests/surface.sh`; edit `shell/mooi.luau` (`SIGIL` → `SURFACE`, `sigil_sync` → `surface_sync`, spawn path), `bin/mooi` (SCENES `mooi-surface.plm:Surface`, settings_link `mooi-surface`), `shell/mooi.plm` (event `surface_ready`, facts `surface_up`, keep `sigil_mode`), `shell/ui/pill.plm` (`sigil_mode and not surface_up`), `.github/workflows/check.yml`, `tests/gate.sh` (glob `shell/lib/surface/*.luau`), `docs/TESTING.md`, `tests/unit/run.lua` (requires and source checks). Settings stay `sigil.*` (the bar hosts'); the `sigil` bar module keeps its id.

- [x] Step 1: update the unit tests' paths and names first (requires `lib/surface/…`, files `mooi-surface.*`, `surface_ready`, `SURFACE`); run → FAIL (files missing).
- [x] Step 2: move and edit; `python3 tools/gen-surface.py`.
- [x] Step 3: `lua5.4 tests/unit/run.lua` → all pass; `bin/mooi check` → gate ok, 15 scenes compile; `grep -rn "mooi-sigil\|lib/sigil\|gen-sigil\|sigil_ready\|sigil_up\|SIGIL" shell bin tools tests .github` → nothing.
- [x] Step 4: commit `surface: the Sigil renamed — mooi-surface, lib/surface (D208)`.

### Task 2: `lib/surface/presence.luau` — the Presence and its memory

**Interfaces — Produces:** `M.FORMS = {"pill","bar","island","orb","freeform","woven"}`; `M.MODES = {"ghost","embedded","full"}`; `M.new(source, x, y, screen) -> P` (`P = {id, source, form = "pill", mode = "ghost", fx, fy (0…1 of the screen), w, h, workspace = "all", state = "persistent", links = {}}`); `M.load(doc, screen) -> {P…}, problems` (validates: unknown source or form dropped with a problem; non-numbers dropped; positions clamped into the screen); `M.save(list) -> doc` (`{version = 1, presences = [...]}`); `M.place(list, P, screen) -> P` (nudges a drop that overlaps another by > 50 % to the nearest free side, 12 px gap); `M.screen_box(P, screen) -> {x,y,w,h}`; `M.undo_stack()` → `{push(doc), undo() -> doc|nil, redo() -> doc|nil}` (depth 50).

- [x] Step 1: tests (section `surface: presence`): `presence: new is a ghost pill where dropped`, `presence: save and load round-trip`, `presence: bad entries dropped, positions clamped`, `presence: a smaller screen clamps, never loses`, `presence: a drop onto another is nudged clear`, `presence: undo and redo walk the edits, a new edit clears redo`. Run → FAIL.
- [x] Step 2: implement. Step 3: run → pass; full suite green. Step 4: commit `surface: the Presence and its memory (D208)`.

### Task 3: `lib/surface/reveal.luau` — stages, picking, release

**Interfaces — Produces:** `M.GROUPS = {"time","sound","machine","work","you","desk"}` (+ `"window"` when over a window); `M.DELAY = 250`, `M.OPEN_MS = 350`, `M.EXPAND_MS = 400`, `M.IDLE_MS = 6000`, `M.R = 120` (aperture radius, px), `M.RING = 170` (hub radius); `M.state()`; `M.down(st, now)`, `M.up(st, now) -> "tap"|"release"|nil`; `M.tick(st, now, pointer) -> st` (stage 0 none · 1 touch · 2 open · 3 hub · 4 approach · 5 expand; anchors at the pointer when stage 3 begins); `M.pick(st, pointer) -> {group = i|nil, source = id|nil}` (angle from the anchor beyond 46 px picks a group; beyond `RING` picks a source of that group in a second ring); `M.release(st, pointer) -> {kind = "cancel"|"open"|"leave", source, x, y}` (`leave` when the pointer is past `RING + 60` with a source picked); `M.close_on(event) -> boolean` (true for `workspace`, `focus`, `escape`, `outside`, `idle`); group sources: time {clock, calendar, weather}, sound {music, volume}, machine {resources, battery, network, bluetooth}, work {workspaces, windows}, you {notifications}, desk {} (wave 2).

- [x] Step 1: tests (section `surface: reveal`): `reveal: a tap is a tap, a hold opens in stages`, `reveal: the hub picks by angle, the second ring by distance`, `reveal: release cancels, opens or leaves`, `reveal: a reveal never outlives its safeguards`. Run → FAIL.
- [x] Step 2: implement. Step 3: pass, suite green. Step 4: commit `surface: the reveal's stages and choices (D208)`.

### Task 4: The scene — the reveal overlay and the Aperture; the desk layer

**Files:** `tools/gen-surface.py`, new `shell/shaders/aperture.wgsl`, regenerated `shell/mooi-surface.plm`.
**Interfaces:** facts `rv_on`, `rv_stage`, `rv_x`, `rv_y` (anchor), `rv_r` (radius target), `rv_pick_g`, `rv_pick_s`, `rv_open` (0…1 expand), text `rv_wall` (wallpaper path), text `rv_t1`/`rv_t2` (the Pill's words), texts `rv_g0…rv_g6` (group labels), `rv_s0…rv_s3` (second-ring labels); Presence slots `p0…p7`: facts `pk_on, pk_x, pk_y, pk_w, pk_h, pk_mode, pk_src, pk_r/g/b`, texts `pk_t1, pk_t2`, fact `pk_prog` (0…1), `pk_edit`; events `rv_press`, `pp_press(k)`, `pp_rpress(k)`, `pp_drag(k)` (with `pointer.x/y`), `pp_drop(k)`, `pp_ctl(k*10 + n)` (prev/play/next), `ed_undo`, `ed_redo`, `ed_done`.
- `surface reveal`: full screen, `level: overlay`, `open: rv_on`, keyboard exclusive while open; the Aperture = a group clipped to a circle of sprung radius at the sprung anchor, holding `image` of `rv_wall` at screen size, with `shader: aperture, …` (darkens and tints inside, lit rim, slight lens at the rim); the Pill (a capsule with `rv_t1`) at its centre; group labels round the rim at `RING`, the picked one lit; the second ring's labels; a zone for the aperture only (click-through elsewhere); `on key Escape` → `emit rv_esc`.
- `surface desk`: full screen, `level: bottom`, `open: any pk_on`; each slot draws its mode (ghost: glyph + `pk_t1` + a progress hairline; embedded: `pk_t1` large + `pk_t2`; full: + ‹ ▶ › zones); waking: a `near` expression from `cursor` distance raises the drawn mode one step; right-press → `pp_rpress`; in edit (`pk_edit`) a dashed outline, drag → `pp_drag`, release → `pp_drop`, an ↶ ↷ Done strip.
- [x] Step 1: test (section `surface: scene`): the plm has `surface reveal {`, `open: rv_on`, `shader: aperture`, `surface desk {`, `level: bottom`, `pp_drag`, and still no `notification`; the shader file has `fn shade(s: Shader)`. Run → FAIL.
- [x] Step 2: generator + shader. Step 3: `pleamar --check` ok; test passes; generator deterministic. Step 4: commit `surface: the Aperture and the desk layer (D208)`.

### Task 5: The Super binding and the logic

**Files:** `bin/mooi` (`reveal down|up` → `pleamar --say mooi-surface "emit rv_down"` / `"emit rv_up"`), `~/.config/hypr/config/custom/mooi.lua` and its `setup/home/…` copy (press bind `SUPER + SUPER_L` → `mooi reveal down`; the release bind → `mooi reveal up`), `shell/mooi-surface.luau`, `shell/mooi-surface.plm` (events `rv_down`, `rv_up` declared), `docs/DECISIONS.md` D208.
**Behaviour:** `rv_down` → `reveal.down`; a 50 ms tick while active runs `reveal.tick` and writes the facts; `rv_up` → `reveal.up`: `"tap"` → `pleamar --say mooi "emit pill_call"` (today's Super tap), `"release"` → `reveal.release` → cancel / open (the source's press, as the Sigil's) / leave (`presence.new` + `presence.place`, save `surface.json`); safeguards: `sys.watch("workspaces")`, `sys.watch("window")` → close; `rv_esc`, a press outside, `IDLE_MS` → close. The wallpaper path: `run("readlink", {"-f", HOME .. "/.cache/current_wallpaper"})` on start and on palette change. Presences: load `surface.json` on start, slots `p0…p7` written from the list (music's words from the media service), `pp_ctl` → `media.previous/toggle/next`, `pp_rpress` → edit mode, `pp_drag/drop` → move + undo push + save, `ed_undo/redo/done`.
- [x] Step 1: unit test (section `surface: logic`): the logic requires `lib/surface/presence` and `lib/surface/reveal`, handles `rv_down`, `rv_up`, `pp_drop`, writes `surface.json`, closes on `workspaces`; `bin/mooi` has `reveal)`; the Hyprland file binds `mooi reveal down` and `mooi reveal up`. Run → FAIL.
- [x] Step 2: implement; `hyprctl reload` after copying the bind; run `setup/capture.sh` before committing.
- [x] Step 3: unit pass; `bin/mooi check` ok. Live smoke on the desk (owner absent — no pointer driving): `mooi reveal down`, wait 0.8 s, screenshot (the aperture at the pointer), `pleamar --say mooi-surface "get rv_stage"` ≥ 2, `mooi reveal up` → closed; a workspace change mid-reveal closes it.
- [x] Step 4: commit `surface: hold Super — the reveal, Music left behind, moved with undo (D208)`.

### Task 6: Live suite, docs, review

- [x] `tests/surface.sh` grows: reveal stages via `emit rv_down/rv_up` (stage ≥ 2 after 0.8 s; tap → `pill_call` reaches mooi; closes on a workspace change and on `rv_esc`); a Presence left via facts (`fact rv_x`… then `emit rv_leave_test`) appears in `surface.json` and survives a `mooi refresh`; edit move + undo restores the position; `pleamar --report mooi-surface` with the reveal open < 1 ms per layer; restores settings, `surface.json`, the Hyprland bind state untouched.
- [x] DECISIONS D208, STATUS, TESTING; the plan ticked; final review by a fresh reviewer; fixes with failing tests first; merge, push, CI green.
