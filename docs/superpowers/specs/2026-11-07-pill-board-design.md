# The Pill unfolds (the Board)

Date: 2026-11-07 · Status: design agreed with the owner on a working prototype, spec awaiting review ·
Decision: D170 · Part of: `docs/superpowers/specs/2026-11-06-the-pill-design.md` (D168, D169)
Prototype: the session scratchpad's `proto/index.html` (recorded; not in the repo)

## 1. Why

A press on an idle Pill opened only the calendar. In Pill mode the centre modules are not drawn, and with
`pill.sides = hide` nothing else is either, so the Pill was the only door to the desktop and it opened onto
one room. The owner asked (2026-11-07) for the Pill to **open up into what is relevant**, creatively, with
any face; for **music with a visualiser that looks amazing**; to **choose what the Pill shows from every
bar module**; and for **BMO's real face** — expressions, blinking and everything.

## 2. The Board

- **One gesture for every face.** A left press on the Pill — time, BMO, Nexus, any module face, any
  activity — **unfolds the Pill itself** into a board: the capsule grows down from the bar on the
  material's spring (no separate pop-up) and what it was showing stays in place at its top (the **lip**).
  With the frame on it stays joined to the band.
- **Hover** (closed): the Pill swells a little and a row of lit **pins** peeks from its lower edge — the
  hint that it opens.
- **Inside:** a **core** (the room) above a row of up to **eight pads**. Each pad is wired to the core by a
  **trace** fanned out like a board router's, with a via at the core; each pad shows the module's glyph and
  a live reading (63 %, harbour, 2 new…) and an ember badge where it counts something.
- **The core's rooms.** It opens on **Now**: the activity's room if one is showing (music → the player;
  a notification → it; volume/brightness → the slider; battery → power), otherwise the clock — the time
  large, the date, week, weather, a week strip with event dots and the next event, and signals waiting.
  Pressing a pad **re-routes** the core to that module's room (its trace lights solid); pressing it again,
  **◂ NOW**, or Esc goes back. A module whose island is a switch or an action (Keep awake, Mic, Focus,
  Recorder, Screenshot, Overview, Search, Settings, Nexus) does it in place: switches light their pad.
- **Alive:** pointing at a pad sends current pulsing down its trace; faint pulses run the traces now and
  then; a new signal arrives as an ember **packet** down the Signals trace and bumps its badge.
- **Closing:** a press outside, Esc (from Now), or a press on the lip (except BMO's, §5). It folds back.
- **Right press** keeps the old direct jumps: the calendar from idle, the full player from music, the
  activity's own island otherwise. **Wheel** over a pad with a level (volume, brightness) changes it.
  **Keyboard:** ←→ across the pads, ↵ presses one, Esc backs out.
- Size: 640 × 356 (the core 592 × 172); edit mode (§4) adds the parts bin below.

## 3. Music: the board plays

- While something plays the board **plays it**: every trace carries a pair of the sixteen bands
  (`vb0…vb15`), brightening and thickening with them, and each kick fires packets out along the traces.
- The **Now Playing** room: the art as a **record that turns** (it stops when paused), title, artist and
  album, seek with times, ⏮ ⏯ ⏭, and the volume (a press goes to Sound). Two visualisers, chosen with a
  chip in the room's corner and kept in `pill.viz`:
  - **HALO** (default): 48 spokes in a ring round the record, coloured from the art, a soft glow that
    breathes on the bass; a faint river on the floor.
  - **RIVER**: the spectrum as a mirrored ribbon flowing along the core's floor in the art's colours,
    with a short afterimage.
- Nothing draws when the board is closed or nothing plays; reduced motion stills it (`still`), as
  `ui/viz.plm` does.

## 4. Choosing what the Pill shows

- **✎ EDIT** in the board's corner (and the same rows in Settings → Bar & Frame → The Pill). The pads
  jiggle; a **parts bin** opens below with **every bar module** (the 32 of the edit shelf, `barlayout.ORDER`).
  Press a part to add it to the first empty pad; drag a part onto a pad to replace it; drag a pad onto a
  pad to swap; × removes. Eight at most. **✓ DONE** or Esc keeps it.
- **The face** — what the closed Pill shows when nothing is happening — is chosen in the same bin: Time,
  BMO, Nexus, or a module face (Weather, Resources, Media, Battery, Workspaces, Network, Signals): its glyph
  and a short reading.
- Settings: `pill.face` widens from `time · bmo · nexus` to those ids; new `pill.pads` (ids, ≤ 8, default
  `volume, brightness, network, bluetooth, notifications, clock, battery, nexus`); new `pill.viz`
  (`halo · river`). Setter codes appended (append-only, mirrored in `lib/setters.luau` and gen-settings).

## 5. BMO, really

- The face is **the desktop BMO's face** (`shell/bmo/bmo.plm`'s screen, eyes with highlights, ^ squints,
  brows, two-curve mouth, tongue, blush), drawn at 58 × 40 from **the same numbers** (`bmo/brain.FACES`),
  gliding between rows. The closed Pill is 50 tall with him (others 41).
- He **looks** at the pointer anywhere on screen (`look`), **blinks** every 2.2–7 s, and his **mood
  drifts** (happy, content, curious, playful) through `lib/pillface` as now.
- **Reactions:** pointed at → curious; the board opens → excited, "hi!"; pointing at a pad → curious and
  he names it; a switch pressed → happy; a signal → surprised, then excited, "a letter!"; **poked** (a
  press on his lip while open) → giggle, "hee hee!", "that tickles", and the fourth poke in 3 s → grumpy,
  "hey!" (brain.poke). While he speaks his mouth flaps and the closed Pill widens to fit the line.
- **Music** → he sings: mouth opening on the bass, a small head bob. **Editing** → focused. Left alone
  14 s → sleepy; 30 s → asleep with a drifting z (night forces sleepy, as D169). Pointing again after a
  long quiet → surprised, "oh! hi".
- BMO → Talk off (`bmo.talk = off`) silences his lines but not his faces (closes D169's M3).

## 6. Pieces

- `lib/pill.luau` (pure): `press(view, face, button) → action` (§2's table) and `pads(cfg) → list`
  (validates `pill.pads`: known ids, no repeats, ≤ 8).
- `lib/pillpads.luau` (new, pure): each module's pad — glyph, reading from the bar's state, room or
  action — one table, unit-tested for every id in `barlayout.ORDER`.
- `lib/pillface.luau`: gains `react(st, name, now, ms)`, `say` widths, the idle sleep and the "oh! hi".
- Rooms: each module's island body becomes a component (`ui/island.plm` kit) so the same body is drawn
  in its island and in the core; modules without an island get a small generic room (glyph, reading,
  its two main actions).
- `ui/pill.plm`: `PillBoard` (lip, core, traces, pads, bin, viz), `BmoFace` redrawn at full detail.
- `lib/chassis.luau`: the Pill piece grows to the board's size while open (`geo.pill.h`), so the frame's
  join follows the unfold.
- `signals.luau`: `recent(n)` and clear, for the Signals room (no notification watch elsewhere; D169).

## 7. Testing

- Unit: `pill.press` for every face × activity × button; `pill.pads` validation; `pillpads` for all 32
  ids; `pillface.react`, the poke count, sleep times; settings rows and setters.
- Live (`tests/pill.sh`, restoring settings, players, volume and mute): open from each face; a pad
  re-routes and back; a switch pad toggles and restores; edit adds, swaps, removes and saves `pill.pads`;
  the face choice saves; music opens on the player with HALO and RIVER; Esc and an outside press close;
  right press jumps. Screenshots of each, and a recording of the unfold.
- Performance: closed, the board costs nothing; open with music, frame time within 2 ms of today's Pill.
