# Bar islands Implementation Plan

> Executed inline (superpowers:executing-plans) — the user delegated every choice and is away.

**Goal:** one island kit with two styles (plate, tether) and six new islands under the bar, plus
clock and media view states.

**Architecture:** the kit lives in shell/ui/island.plm and reads a scene fact `isl_style`; islands
live in shell/mooi.plm's own surface like the System island (`open` enum, `rv.*` spring, `life.*`
layer, D55 dismiss); their data is read by the bar logic only while open; pure parsing in shell/lib
with unit tests.

**Spec:** docs/superpowers/specs/2026-10-27-bar-islands-design.md

## Global Constraints

- No `time`, no endless `spin`: the bar must still draw 0 frames idle (D96).
- Island data read only while that island is open; nothing new runs while all are closed.
- `spawn(cmd, args, fn, on_exit)` — never nil for the line callback; zone `active:` means "takes presses".
- Settings appended to SETTERS in both tools/gen-settings.py and lib/setters.luau, then
  `python3 tools/gen-settings.py`.
- Never write settings.json while the settings window is open; restore anything a test changes.
- `bin/mooi check` green after every task; commit per task; push at the end of each working block.

## Review Focus

1. A module whose island is open is pressed again → it closes (not reopens).
2. The island under a module at the screen's edge stays on screen; the tether still points at the module.
3. Weather offline / open-meteo 503 → the island says so, keeps the last reading.
4. No battery / no brightness / no powerprofilesctl → those rows are hidden, not broken.
5. Calendar month arithmetic across year ends and leap Februaries.

### Task 1: Settings — island.style, clock.view
- config rows; SETTERS (both lists); Colour page "Islands" (Plate · Tether); Bar page "Clock shows";
  `fact.isl_style`, `fact.clock_view` in mooi.luau apply; scene facts. Test: setters round trip.

### Task 2: The kit
- IslandFrame style-aware + tether (`tx`); IsleHead, IsleRule, IsleMeter, IsleBtn, IsleStat.
- Window/System/Search islands pass `tx`. Live: System island screenshotted in both styles.

### Task 3: Island scaffolding
- `open` gains stats | calendar | weather | sound | display | power; rv/life per island; Escape;
  dismiss plate; module presses toggle (resources, weather, clock left, volume, brightness, battery).
- A shared anchor: `isl_cx` (the module's centre) set by the opening press.

### Task 4: Calendar — lib/calendar.luau (tested) + island + ‹ › Today, wheel
### Task 5: Stats — lib/stats.luau (tested) + reader while open + island + btop/nvtop
### Task 6: Weather — lib/forecast.luau (tested) + fetch on open (10 min cache) + island
### Task 7: Sound — level, mute, outputs (audio.default), mic; Mixer (pavucontrol)
### Task 8: Display — brightness, night light (hyprsunset), Dark · Light · Auto
### Task 9: Power — percent, state, time (upower), profiles (powerprofilesctl), keep awake
### Task 10: View states — clock right press cycles clock.view; media right press cycles media.mode
### Task 11: Verify both styles live, idle frames 0, scene/integration tests; D97, TODO, memory; push
