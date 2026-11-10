# Panel visualiser and week weather — implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans. Steps use checkbox syntax.

**Goal:** A small spectrum along the open panel's bottom edge while music plays, and a Weather page reached by pressing Home's weather.

**Architecture:** The panel scene already receives 32 mirrored band facts. A new pure `lib/node/week.luau` turns the Nexus's cached weather into current conditions plus at most seven day rows; a new scene page id 11 draws them. The logic adds the panel to `wants_bands`, fills the page, and opens it from a Home press zone.

**Spec:** this plan (approved design in conversation, 2026-11-10)

## Global Constraints

- Never edit `shell/mooi-node.plm`; edit `tools/gen-node.py` and run `python3 tools/gen-node.py`.
- Every event is declared in the scene. Luau: no bitwise, `goto`, or empty-matching `gmatch`; locals before use.
- Colours from `fl.*` and `nd_acc`; Nerd Font for glyphs.
- Branch `oc-home-profile`; no push, merge, rebase or reset.

## Task 1: the week's rows

**Files:** create `shell/lib/node/week.luau`; modify `tests/unit/node_helpers.lua`.

- [ ] Write a failing unit section for `WEEK.week`: seven rows and labels (`TODAY`, then weekdays), six-day input stays six, `lo_v == 0` and the warmest `hi_v == 1`, wet codes counted in `summary`, `nil` for no document, `now == nil` without current conditions.
- [ ] Run `lua5.4 tests/unit/run.lua` and see the new tests fail because the module is missing.
- [ ] Implement `WEEK.week(doc)` returning `{ city, now, rows, high, low, wet, summary }`; rows `{ label, glyph, hi, lo, hi_n, lo_n, lo_v, hi_v, wet }`. Use `lib/calendar.weekday` and `lib/node/home.weather`.
- [ ] Run the suite and see it pass.

## Task 2: draw it and wire it

**Files:** `shell/lib/node/geometry.luau`, `tools/gen-node.py`, `shell/mooi-node.luau`, `shell/lib/forecast.luau`, tests, docs.

- [ ] `PANEL_H.weather = 570`.
- [ ] `forecast.url`: `forecast_days=7`.
- [ ] Scene declarations: `model wkw max 7`, weather texts, `event nd_hweather`.
- [ ] Home: `pwx` zone over the weather, emits `nd_hweather`.
- [ ] Weather group (`nd_pgp == 11`): current card, summary, seven rows with track and range, empty state; Home icon lit on 11.
- [ ] Bottom spectrum: 32 bars from `nd_sp0…31`, 8 px high, inside the bottom edge, show while the panel is open and music is playing or paused.
- [ ] Logic: require `WEEK`; `wants_bands` includes the playing panel; `PANEL_PAGES.weather = 11`; `PANEL_TITLE.weather`; `show_weather_week`; `PANEL_SHOW.weather`; `nd_hweather`; watch `nexus-weather.json`; request the feed when a playing panel opens.
- [ ] Tests: scene strings for `pwx`, `emit nd_hweather`, `model wkw`, `text nd_wtemp`, `for w in wkw`, the bar loop, `PANEL_H.weather`; add to the existing D280 scene section.
- [ ] Docs: D282 and `docs/NODE.md` Home/Weather lines.
- [ ] Checks: `python3 tools/gen-node.py`; `pleamar --check shell/mooi-node.plm`; `lua5.4 tests/unit/run.lua`; `lua5.4 tests/luau-ops.lua shell`; `bash tests/gate.sh`; the `_ENV` allowlist.
- [ ] Commit once, ending `Co-Authored-By: opencode <noreply@opencode.ai>`.
- [ ] `./bin/mooi refresh` and `./bin/mooi pill`, then verify the strip while music plays and the weather page when the weather is pressed.
