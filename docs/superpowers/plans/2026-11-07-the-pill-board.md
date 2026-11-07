# The Pill Board Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** a press on the Pill unfolds it into a board — a core of rooms over eight pads wired by traces — with
music playing the board, pads and face chosen from every bar module, and BMO's real face.

**Architecture:** the board is an island (`open == board`) drawn with the island kit (`IslandFrame`) anchored at
the Pill, so it pours from the Pill with the frame on and follows `island.style` without it. Pure tables
(`lib/pill`, `lib/pillpads`, `lib/pillface`) decide; `shell/pillboard.luau` carries out presses, feeds the
rooms and saves; `shell/ui/pillboard.plm` draws. Rooms are compact new views over the data the islands
already gather (`islands.luau` gathers for `open == X` **or** the board's room `X`).

**Tech Stack:** Pleamar 0.7.11 scenes, Luau logic, Lua 5.4 unit tests (`tests/unit/run.lua`), live
`tests/pill.sh`.

**Spec:** `docs/superpowers/specs/2026-11-07-pill-board-design.md` (D170)

## Global Constraints

- Only Signal Loom watches notifications (D169); other code reads Loom (`loom.recent`).
- Setter codes are append-only, mirrored in `lib/setters.luau` and `tools/gen-settings.py`.
- Never hand-edit inside `<gen:edit>`; Settings rows come from `tools/gen-settings.py`.
- A bar control lives on the bar's own surface; the board (a panel) lives on `popup_surface` like the islands.
- Events the logic must hear are declared `event x ->`.
- Live tests restore settings.json byte for byte, volume, mute and players; trap EXIT INT TERM HUP PIPE.
- Don't drive the real pointer; scripted presses (`pleamar --say press`) plus one real click by the owner.

## Review Focus

1. A pad whose module is missing on this machine (no battery, no brightness, no bluetooth): its pad still
   draws a reading ("—") and a press does nothing harmful.
2. `pill.pads` hand-edited with unknown ids, repeats or more than eight: the board shows the valid ones.
3. Opening the board while another island is open, and opening an island (module, keyboard) while the
   board is open: one at a time, never two.
4. Closing the board mid-room stops the room's readers (stats every 2 s, power every 10 s).
5. Music stopping while the board shows Now Playing: the room falls back to idle's Now.

## Rulings carried from the spec (made while planning)

- R1 Rooms are compact new views (592 × 160) over the islands' data, not the island bodies (300–440 wide,
  up to 356 tall: they do not fit the core).
- R2 The board is an island (`IslandFrame`); with the frame on it pours from the Pill (the frame's own
  pour), which is the unfold. The lip is the Pill itself, on the bar's surface, above the board.
- R3 Edit mode uses presses, not drags: press a pad to select it, a part to put it there (or in the first
  empty pad), × to empty it, ◂ ▸ to move the selected pad.
- R4 Docked moons are chips in the board's header row (the lip is on another surface).
- R5 BMO gets sleepy 10 min and asleep 20 min after the last time the Pill was touched (a surface cannot
  see the pointer elsewhere), and night still makes him sleepy (D169).
- R6 Pads of modules without a room do exactly what their module's press does (same events); one that
  opens another surface (side panel, app, menu) closes the board.
- R7 Now drops the "next event" line (mooi has no event source).

---

### Task 1: pure tables — press, pads, faces, settings rows

**Files:** Modify `shell/lib/pill.luau`, `shell/lib/config.luau`, `shell/lib/setters.luau`,
`tools/gen-settings.py`; Create `shell/lib/pillpads.luau`; Test `tests/unit/run.lua`

**Interfaces — Produces:**
- `pill.press(main, face, button) → { kind = "board"|"room"|"calendar"|"player"|"poke"|"nexus"|"island", room?, island? }`
  - left: face `nexus` and idle → `nexus`; otherwise `board` (room `now`); face `bmo` while the board is open is handled
    by the caller (a poke).
  - right: idle → `calendar`; music → `player`; osd → `island` (sound|display); battery → `island` power;
    notify → `room` signals; record → `room` now.
- `pill.FACES = { "time","bmo","nexus","weather","resources","media","battery","workspaces","network","notifications" }`;
  `FACE_W` gains the module faces (width from their text: `44 + 7 * #text`, at least 104).
- `pill.pads(list) → list` — known ids (pillpads), no repeats, at most 8, order kept; nil/garbage → default.
- `pillpads.ORDER` = `barlayout.ORDER`; `pillpads.get(id) → { icon = n, room = name|nil, act = event|nil, arg = n|nil, switch = bool, closes = bool }`;
  `pillpads.index(id) → n` (0-based, for the scene); `pillpads.DEFAULT = { "volume","brightness","network","bluetooth","notifications","clock","battery","nexus" }`.
- Rooms: `now`, `calendar` (clock), `sound` (volume, mic), `display` (brightness), `connections` (network, bluetooth),
  `power` (battery), `resources`, `weather`, `signals` (notifications).
- Settings: `pill.face` values = `pill.FACES`; `pill.pads` (ids ≤ 8, default `pillpads.DEFAULT`); `pill.viz` (`halo`·`river`).
  Codes appended: `"pill.pads", "pill.viz"` (pill.face's values widen; its code stays).

- [ ] Tests first: `pill.press` table for every face × activity × button; `pill.pads` validation (unknown,
      repeats, nine, nil); `pillpads.get` defined for every `barlayout.ORDER` id, each with a room or an act;
      config rows and setters mirror. Run `lua5.4 tests/unit/run.lua` → FAIL (missing).
- [ ] Implement; run → PASS; commit `pill: the board's tables (D170)`.

### Task 2: BMO — reactions, sleep, the talk switch

**Files:** Modify `shell/lib/pillface.luau`; Test `tests/unit/run.lua`

**Produces:** `pillface.react(st, face, now, ms)` (a brain.FACES name shown `ms`); `pillface.say(st, line, now, talk)`
(silent when `talk == "off"`); `poke(st, now, r, talk)` respects talk (closes D169 M3); `tick` sets sleepy
after `SLEEPY_MS = 600000` and asleep after `ASLEEP_MS = 1200000` since `st.touched`; `touch(st, now)` → returns
true when he was asleep (the caller says "oh! hi" and shows surprised).

- [ ] Tests (react shows then lapses; talk off silences poke and say; sleep thresholds; touch wakes) → FAIL;
      implement → PASS; commit `pillface: reactions, sleep, the talk switch (D170)`.

### Task 3: the board — open, close, pads, traces, rooms' wiring

**Files:** Create `shell/pillboard.luau`, `shell/ui/pillboard.plm`; Modify `shell/mooi.plm` (import, events,
facts, `life.board` layer, dismiss, the island group), `shell/mooi.luau` (wire it), `shell/bar.luau`
(`pill_press` → `pill.press`; right press; `pill_now` and face state shared via ctx), `shell/islands.luau`
(gather for the board's room), `shell/ui/pill.plm` (right press, moon right press)

**Produces:** facts `bd_room` (0 now · 1 calendar · 2 sound · 3 display · 4 connections · 5 power · 6 resources ·
7 weather · 8 signals), `bd_n`, `bd_k0..7` (pillpads index or −1), `bd_lit0..7`, `bd_sel` (edit), `bd_edit`;
events `bd_pad(i)`, `bd_hover(i)`, `bd_back`, `bd_chip(k)`, `bd_edit_cmd(n)`, `bd_part(n)`, `bd_face(n)`,
`bd_viz`, `pill_rpress`, `pill_rmoon(k)`.

- [ ] Unit tests (source checks as the suite does): events declared with `->`; `open == board` in dismiss and
      the `life.board` layer; islands.luau's readers start for `bd_room`; pillboard emits only known events → FAIL.
- [ ] Implement the board: `IslandFrame(rv.board, 640, H …)` anchored at the Pill; header (room title, docked
      chips, ✎ EDIT, ◂ NOW); core; 8 traces fanned from pins to pads (a lit trace on the selected room, a
      travelling dot on hover and on a timer); pads (icon, reading, badge); keyboard ←→ ↵ Esc.
- [ ] Rooms: Now (idle), Calendar, Sound, Display, Connections, Power, Resources, Weather, Signals.
- [ ] → PASS; `pleamar --check shell/mooi.plm`; commit `pill: the board (D170)`.

### Task 4: music plays the board

**Files:** Modify `shell/ui/pillboard.plm`, `shell/pillboard.luau`, `shell/mooi.plm` (record spin while the
board plays), `shell/bar.luau` (`want_viz`, `music_isl` while the board shows Now Playing)

- [ ] Tests: `want_viz` includes the board; the record turns for the board too → FAIL.
- [ ] Now Playing room: record with the cover, title, artist, album, seek, ⏮ ⏯ ⏭, volume chip; HALO (48
      spokes, the art's colours via `fl.ember`/`fl.phos` mix like the island) and RIVER (mirrored bands
      ribbon with a 3-step afterimage via props); traces brighten with their pair of bands; `pill.viz` chip.
- [ ] → PASS; commit `pill: the board plays the music (D170)`.

### Task 5: edit mode, faces from modules, Settings regrouped

**Files:** Modify `shell/ui/pillboard.plm`, `shell/pillboard.luau`, `shell/ui/pill.plm` (module faces),
`shell/bar.luau` (face text and width), `tools/gen-settings.py` (Closed/Open cards, viz, "Edit on the board"),
regenerate.

- [ ] Tests: `bd_part` places in the selected or first empty pad and saves `pill.pads`; × empties; ◂ ▸ swap;
      `bd_face` saves `pill.face`; generated settings have the Open card → FAIL.
- [ ] Implement; regenerate settings; → PASS; commit `pill: choose its pads and face (D170)`.

### Task 6: BMO's real face in the Pill

**Files:** Modify `shell/ui/pill.plm` (BmoFace at full detail: highlights, ^ squints, brows, two-curve mouth,
tongue, blush; 50 × 34), `shell/mooi.plm` (facts `pb_tg`, props), `shell/bar.luau` (reactions wired:
hover curious, board opens excited "hi!", pad hover curious + name, switch happy, signal surprised→excited,
poke while open, singing with the bass while playing, focused while editing, touch/sleep), `shell/lib/chassis.luau`
(the Pill piece `geo.pill.h` for BMO's taller face).

- [ ] Tests: BmoFace draws the tongue and highlights; reactions wired (source checks); chassis honours `h` → FAIL.
- [ ] Implement → PASS; commit `pill: BMO's real face (D170)`.

### Task 7: live checks, docs

**Files:** Modify `tests/pill.sh`, `docs/DECISIONS.md` (D170), `docs/TESTING.md`, `STATUS.md`

- [ ] Live: open from time/BMO/Nexus faces; pad → room → back; switch pad toggles and restores; edit adds,
      swaps, removes, saves; face saves; music opens Now Playing; HALO/RIVER; Esc and outside close; right
      press jumps; screenshots. Restores everything.
- [ ] `sh tests/gate.sh`; docker CI; capture; commit; final review; fix pass; merge; push.
