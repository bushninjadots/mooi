# Widgets 2a (editor + visualiser) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** An editor with multi-select, 8 handles, keyboard, undo, align and lock, and a draggable panel with sliders and thumbnails; plus a visualiser with 16–128 bars from a 64-band feed and upgraded looks for every mode.

**Architecture:**
- `lib/widgets` gains doc version 2 and pure editor operations, including an undo history.
- `lib/vizfeed` gains a v2 line and `resample`; the bar writes v2 from a 64-band cava.
- The widgets logic resamples per visualiser into scene models (`vzA/B/C`, one record per bar) plus
  32 global bands (`vs0…31`).
- A new `ui/vizwide.plm` draws the widget versions of the 12 modes. `ui/viz.plm` stays as it is for
  the player and the bar.

**Tech Stack:** Pleamar 0.7.11 (language 0.9), Luau / Lua 5.4 subset, `tests/unit/run.lua`.

**Spec:** `docs/superpowers/specs/2026-11-03-widgets-editor-viz-design.md`

## Global Constraints

- **Language.** Every `.plm` is `language 0.9`. Every `.luau` parses under lua5.4.
- **Event payloads** stay under 2^24.
- **Saving.** `widgets.json` is written with `files.write` once per finished gesture.
- **New per-widget fields:** `z`, `locked`, `opacity` (0.3–1, default 1).
- **Visualiser options:** `bars` 16–128 (default 64), `gap` 0–0.6 (0.3), `smooth` 0–1 (0.5),
  `peaks` (true), `reflection` (false).
- **Now Playing option:** `text` 0.8–1.4 (1).
- **Cost.** GPU under 8 % for a Sleeve plus a full-width visualiser, at 64 and at 128 bars. Use
  straight steps, never curves, for anything animated.
- **Testing.** Live checks go through `pleamar --say` events and screenshots; never drive the
  user's pointer.
- **Before every commit:** run `bash setup/capture.sh`. Commits end with the Co-Authored-By line and
  are pushed to `origin main`.

## Review Focus

1. **Undo after Settings changed the file.** Must not resurrect stale state. → test `history cleared on external change` (T1).
2. **Align with a locked widget in the selection.** It is skipped, the others move. → test `align skips locked` (T1).
3. **Resize from the left edge past the minimum.** The right edge stays put; no drift. → test `resize from left keeps right edge at min` (T1).
4. **Bars set above 64 with only a v1 (32-band) feed.** Smooth resampling, no zeros. → test `resample 32→128 has no gaps` (T2).
5. **Four visualisers.** The 4th shares slot C's bands; nothing breaks. → live check (T3).

---

### Task 1: `lib/widgets` v2 and editor operations

**Files:** Modify `shell/lib/widgets.luau`; test `tests/unit/run.lua` (`widgets` section).

**Produces:**
- **Version 2:** `W.VERSION = 2`; `parse` accepts version 1 and 2 and fills the new fields and
  options; `encode` writes version 2 with `z` = list index.
- **Fixed constants:** the spec's option defaults and clamps live in `W.OPTIONS`; `W.OPTION_RANGES`
  holds the numeric ranges.
- **Ordering and locking:**
  - `W.set_field(doc, id, key, value) -> doc` handles `opacity` and `locked`.
  - `W.raise(doc, ids, dir) -> doc` takes `dir` = "front" | "back" | "forward" | "backward".
- **Moving:**
  - `W.nudge(doc, ids, dx, dy, screen) -> doc, skipped`
  - `W.align(doc, ids, how, screen) -> doc, skipped` with `how` in left / centre / right / top /
    middle / bottom
  - `W.distribute(doc, ids, axis, screen) -> doc, skipped` with axis "h" | "v"
  - `W.match(doc, ids, dim, screen) -> doc, skipped` with dim "w" | "h", matching the first selected
- **Resizing:** `W.resize_from(doc, id, handle, dx, dy, screen) -> x, y, w, h`. `handle` is
  0–7: tl, t, tr, r, br, b, bl, l. It keeps the opposite edge fixed, uses `clamp_size` and keeps the
  Record's aspect.
- **Selection:** `W.marquee(doc, x0, y0, x1, y1) -> mask`, a bit mask over slots.
  `W.ids_of(doc, mask)` and `W.mask_of(doc, ids)` convert between masks and id lists.
- **Undo history:** `W.history()` returns `{ undo = {}, redo = {}, max = 30 }`.
  - `W.push(h, doc)` records a change.
  - `W.undo(h, current) -> doc | nil` and `W.redo(h, current) -> doc | nil`
  - `W.clear(h)` empties it.

- [ ] **Step 1: Write the failing tests.**
  - `v1 file loads as v2 defaults` (bars 64, opacity 1, locked false)
  - `options clamp to their ranges`
  - `align skips locked`
  - `align left lines lefts`
  - `distribute spaces evenly`
  - `match width`
  - `nudge clamps on screen`
  - `resize from left keeps right edge at min`
  - `resize tl keeps record aspect`
  - `marquee selects touched`
  - `raise front/back reorders`
  - `history undo/redo round-trip`
  - `history cleared on external change` (the caller clears it; the test checks that `W.clear`
    empties both stacks)
  - `history caps at 30`
- [ ] **Step 2: Run them and see them fail.** `lua5.4 tests/unit/run.lua | grep -A1 FAIL`
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Verify.** `lua5.4 tests/unit/run.lua | tail -1` gives 0 failed.
- [ ] **Step 5: Commit.**

### Task 2: Feed v2 (64 bands) and resample

**Files:** Modify `shell/lib/vizfeed.luau` and `shell/bar.luau` (cava `bars = 64`; write v1 by
taking every other band, plus v2 in `viz-levels-v2.txt`); test `tests/unit/run.lua` (`vizfeed`).

**Produces:**
- `vizfeed.FILE_V2 = "viz-levels-v2.txt"`, `vizfeed.BANDS_V2 = 64`
- `encode_v2(t)` and `decode_v2(text) -> t | nil`, where `t.bands` has 64 entries
- `resample(bands, n) -> table`

- [ ] **Step 1: Write the failing tests.**
  - `v2 round-trips`
  - `v1 still decodes`
  - `resample 64→16 averages and keeps endpoints`
  - `resample 32→128 has no gaps` (no value is 0 where both neighbours are above 0.1)
  - `resample n=1`
- [ ] **Step 2: See them fail.**
- [ ] **Step 3: Implement.** The bar keeps feeding v1 so the player, Nexus, notch and frame are
  unchanged: it publishes a v1 line from the 64 bands mapped down to 32 with `vizfeed.map`.
- [ ] **Step 4: Verify.**
  - Unit tests pass and `bin/mooi check` passes.
  - Live: `viz-levels-v2.txt` updates while playing, and the player's visualiser still moves.
- [ ] **Step 5: Commit.**

### Task 3: The widgets logic feeds N bars

**Files:** Modify `shell/mooi-widgets.luau` and `shell/mooi-widgets.plm`.

**Produces (scene):**
- `model vzA max 128 { v: number; pk: number }`, and the same for `vzB` and `vzC`
- `fact vs0…vs31`: global bands for the path modes
- `fact so0_0…so0_23`, `so1_*`, `so2_*`: the Scope's afterimage frames
- The `wg` record gains `bars`, `gap`, `peaks`, `refl`, `vslot` (0–2, −1 for none), `opa` and
  `txt`.

**Logic:**
- Read v2 when it is fresh (else v1); smooth per slot by `smooth`.
- Peaks hold 400 ms, then fall at 1.2 per second.
- Write models only for visualisers that are shown; the 4th or later visualiser maps to slot C.
- The 16-band `vb*` facts and `vs*` come from the same frame.

- [ ] **Step 1: Implement and compile.**
- [ ] **Step 2: Live check.** Feed through `emit`-free play at volume 0 isn't enough, so use a
  scratch copy with synthetic bands (as in D137), and check the models change, along with the
  4-visualiser case.
- [ ] **Step 3: Commit.**

### Task 4: `ui/vizwide.plm`, the 12 modes upgraded

**Files:** Create `shell/ui/vizwide.plm`; modify `shell/ui/widgets.plm` so `Visualiser` uses it.

Each mode follows spec §3: bar modes over `for b in vzX`, path modes over `vs*`, Scope with three
afterimages, Dust with 2 depth layers and trails, Ripple with a refraction band, Orbit with arcs,
and Ring with spokes per bar plus an inner waveform.

- [ ] **Step 1: Lab mockup.** Build all 12 at 64 bars on synthetic music, screenshot it, and show it
  to the user (they waived waiting, so carry on).
- [ ] **Step 2: Integrate.** Compile, then take a live screenshot.
- [ ] **Step 3: GPU.** Measure every mode at 64 and 128 bars; trim anything over 8 %.
- [ ] **Step 4: Commit.**

### Task 5: Editor scene

**Files:** Modify `shell/mooi-widgets.plm`, `shell/mooi-widgets.luau` and `shell/ui/widgets.plm`.

**Events:**
- `wg_sel(n)`: n = slot · 10 + 0 select only / 1 toggle / 2 clear
- `wg_marq(pack(x0/8, y0/8) · 4096 + …)`: sent as two events, `wg_marq0(x · 4096 + y)` and
  `wg_marq1(x · 4096 + y)`, in px
- `wg_handle(slot · 65536 + handle · 4096 + …)`: sent as `wg_hgrab(slot · 8 + handle)`, then
  `wg_hmove(dx+2048 · 4096 + dy+2048)`, then `wg_hdrop`
- `wg_key(code)`: 1–4 arrows, 5–8 Shift+arrows, 9 delete, 10 duplicate, 11 undo, 12 redo,
  13 select all, 14 lock, 15 forward, 16 backward
- `wg_tool(code)`: 1–6 align, 7–8 distribute, 9–10 match, 11 front, 12 back, 13 lock

**Logic:** selection mask, undo history (cleared on an external reload), live resize preview facts,
readout text, and the "N locked skipped" note.

- [ ] **Step 1: Implement.**
- [ ] **Step 2: Live check** through events and screenshots.
- [ ] **Step 3: Commit.**

### Task 6: Panel v2 and Settings sliders

**Files:** Modify `shell/ui/widgets.plm`, `shell/mooi-widgets.*`, `shell/ui/ferrolume.plm`,
`tools/gen-settings.py` and `shell/mooi-settings.luau`.

**The panel:**
- 320 px, with a drag header (`wg_pmove`) and a collapse control.
- Thumbnails: mini components at 0.32 scale, or a mini `vizwide` grid.
- Sliders: a `WSlider` component sending `wg_opt` with new codes, live while dragged and saved on
  release.
- Readouts, Lock, Duplicate and Remove.

**Settings → Widgets:** each row gets Bars and Opacity sliders.

- [ ] **Step 1: Implement.**
- [ ] **Step 2: Live check** through events and screenshots.
- [ ] **Step 3: Commit.**

### Task 7: Log, check, ship

- [ ] Write D138 in `docs/DECISIONS.md` and update `docs/TODO.md`.
- [ ] `bin/mooi check`, capture, commit, push.
- [ ] Final whole-branch review by a fresh reviewer; fix the Important findings.
