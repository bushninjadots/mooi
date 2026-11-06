# The bar, stage 4 — Modules, density and one component contract

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** every bar module renders through one contract (icon, value, label, a small graph, a warn state), carries its own options, and follows the Density setting; then the missing components are added and the media transport loses its red/green split.

**Architecture:** `bar.modules.<id>` already holds `show`, `frame` and the Look card's fields (`lib/modlook`). Stage 4 adds the options the spec names — `display`, `minimal`, `accent`, `warn`, and per-module actions — to the schema, resolves them in a pure `lib/modtier` (density × the module's own choice → what to draw), and renders every module through `shell/ui/module.plm`. The bar keeps owning placement, data and presses; the component owns only the drawing, exactly as the Pill's content does.

**Tech Stack:** Pleamar 0.7.11 scenes + Lua logic, Python generators, POSIX sh live tests, Lua 5.4 unit tests.

**Spec:** `docs/superpowers/specs/2026-11-06-bar-redesign-design.md` §5 (modules and density), §7 (consistency rules), §9 (build order: stage 4 follows the Pill).

## Global Constraints

- Requires with slash paths; no `goto`; `show:` is ignored on shapes inside a `body`; a box with `stroke: 0` is filled; events from outside a scene must be declared.
- `settings.json` only through `lib/settingsfile`; setter codes append-only; generated files change only through their generators (`tools/gen-settings.py` owns the settings scene and `lib/settings_index.luau`).
- Nothing that already works may regress: `bar.modules.<id>.show`, `frame`, the Look card's six fields and their setter codes keep their meaning.
- Densities: `minimal` (a module may hide, show only its icon, or move into the Pill), `balanced` (icon + value), `rich` (labels and graphs). A module's own choice always wins over the density.
- Spacing comes from the 4 px grid (§7), not from a module: 8 within a module, 12 between modules, 24 between groups; one height, one text baseline.
- Colour comes from roles (accent, warn, critical, text, secondary), never a literal, except a module's own `accent` colour.
- After logic changes: `bin/mooi session`, then no new `runtime error` in `~/.local/state/mooi/mooi.log`.
- Live tests restore `settings.json` byte for byte, the volume and the playback; never move the pointer.
- Commits end with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`; `setup/capture.sh` before a pushed commit.

## Review Focus

1. Switching Density minimal → balanced → rich → minimal leaves every module in place, with the side groups' widths following the content rather than jumping in the same frame.
2. A module that is `minimal = hide` disappears from the row but keeps its place in the layout lists, so density rich brings it back exactly where it was.
3. A module with `minimal = into the Pill` appears as a moon in Pill mode and as its normal self in the other shapes; switching back to islands restores it.
4. A module's own `display` beats the density in every shape, and a group shows its head's options.
5. `warn` thresholds colour the value only (never the plate), and a module with no threshold ignores the field.
6. Every new component survives a bar restart and a settings round-trip; an unknown component id is refused by validation, not drawn as an empty plate.

---

## File Structure

| File | Responsibility |
| --- | --- |
| `shell/lib/config.luau` | `bar.density`; per-module `display`, `minimal`, `accent`, `warn`, `actions` rows; validation |
| `shell/lib/modtier.luau` (new) | pure: density + a module's choices + its data → `{ show, icon, value, label, graph, warn }` |
| `shell/lib/modules.luau` | the component registry: id → name, category, facts it reads, default options |
| `shell/ui/module.plm` (new) | one component: icon, value, label, sparkline/graph, warn/critical tint |
| `shell/mooi.plm` | every module group drawn through the component |
| `shell/bar.luau` | feeds each module's facts; placement follows the component's width; presses unchanged |
| `tools/gen-settings.py` → settings scene/index | Settings → Bar & Frame → Modules gains Display, Minimal, Accent, Warn; Density on top |
| `shell/mooi-settings.luau` | the new events, through `lib/modlook`'s code scheme (append-only) |
| `tests/unit/run.lua` | `modtier` cases, new-component registry, density precedence |
| `tests/chassis.sh` | density × shape × frame × swell: one foot, no hump, no width jump |
| `docs/DECISIONS.md`, `docs/TESTING.md`, `STATUS.md` | D170, the suite, stage 4 done |

---

### Task 1: Density and the per-module options in the schema

**Files:** Modify `shell/lib/config.luau`; Modify `shell/lib/modules.luau`; Test `tests/unit/run.lua`

**Interfaces:**
- `bar.density` (`minimal` · `balanced` · `rich`, default `balanced`), appended after the existing bar rows.
- Per module, beside `show` and `frame`: `display` (`style` · `icon` · `icon+value` · `label+value` · `graph`), `minimal` (`style` · `hide` · `icon` · `pill`), `accent` (`style` · `primary` · `warn` · `critical` · `#rrggbb`), `warn` (`off` · `soft` · `strong`), `actions` (three strings from a fixed verb list: `none`, `island`, `toggle-<id>`, `exec-<name>`).
- `modules.REGISTRY[id] = { name, category, facts = {…}, graph = bool, warnable = bool }`; `show` defaults true only for the registry's `default_on` ids.
- Validation refuses an unknown id, an unknown action verb and a colour that is not a role or `#rrggbb`.

- [ ] **Step 1: Failing tests** — a settings file without `bar.density` gains `balanced`; each option round-trips; an unknown module id and a bad action are refused with a problem naming the path; a module's `display` default is `style`, meaning "the density decides".
- [ ] **Step 2: Run** `lua5.4 tests/unit/run.lua --filter "modules"` — Expected: FAIL (module missing)
- [ ] **Step 3: Implement** the rows and `lib/modules.luau`.
- [ ] **Step 4: Run** — PASS; suite `0 failed`.
- [ ] **Step 5: Commit** `bar: density, and each module's own options (D170)`

---

### Task 2: `lib/modtier` — what a module shows

**Files:** Create `shell/lib/modtier.luau`; Test `tests/unit/run.lua` (section "modtier")

**Interfaces:**
- `modtier.resolve(s, id) → { show, display, accent, warn, actions }`: the module's own value, else the density's: minimal → `icon` (or the module's `minimal`), balanced → `icon+value`, rich → `label+value` (+ graph where the registry says it has one).
- `modtier.shape(module, data) → { icon, value, label, graph = {…}, warn = 0|1|2 }`; `warn` is 0 unless the registry marks the module warnable, the setting is on, and the data carries the threshold.
- `modtier.into_pill(s, id) → bool`: true only when the module chose `minimal = pill` and the shape is Pill.

- [ ] **Step 1: Failing tests** — density precedence in all three tiers; a module's own `display` beats each tier; `into_pill` only in Pill mode; warn tints only the value and only for a warnable module with a threshold; a group resolves through its head.
- [ ] **Step 2: Run** — FAIL.
- [ ] **Step 3: Implement**.
- [ ] **Step 4: Run** — PASS.
- [ ] **Step 5: Commit** `modtier: what each module shows, and how density decides (D170)`

---

### Task 3: One component draws every module

**Files:** Create `shell/ui/module.plm`; Modify `shell/mooi.plm`; Test `tests/unit/run.lua` (source-level), `pleamar --check`

**Interfaces:**
- `component Module()` draws from facts `m_<id>_kind`, `m_<id>_icon`, `m_<id>_value`, `m_<id>_label`, `m_<id>_graph`, `m_<id>_warn`; one baseline, one height, the 4 px grid's 8 px inside.
- The bar sets one fact set per module id from `modtier.shape`; a module with `show = false` is not laid out at all.
- Zones keep the module's existing ids (`press_<id>`, `scroll_<id>`), so pointer tests and the editor keep working.

- [ ] **Step 1: Failing test** — the scene imports `ui/module.plm`, declares the facts, and every registry id appears in exactly one group; `pleamar --check shell/mooi.plm`.
- [ ] **Step 2–3:** FAIL → implement; `pleamar --check` ok.
- [ ] **Step 4: Verify live** — each density on the real bar; screenshots of the three tiers; `mooi session` log clean.
- [ ] **Step 5: Commit** `bar: every module through one component (D170)`

---

### Task 4: The new components

**Files:** Modify `shell/lib/modules.luau`, `shell/bar.luau` (facts), `shell/mooi.plm`; Test `tests/unit/run.lua`

**Interfaces:** each is a registry entry plus its facts:
- `gpu` (load %, temperature where the driver reports it), `disk` (free % of the largest mount), `power` (profile), `timer` (a countdown started from the terminal), `pomodoro` (25/5 by default, a press starts, a second pauses), `title` (the focused window's title, truncated), `record` (screen recording state, warn while on), `spacer` and `divider` (no facts; layout only), `group` (several ids on one plate through the existing `a+b` entries).

- [ ] **Step 1: Failing tests** — the registry lists every new id with its category; `spacer`/`divider` are refused as group heads; `title` truncates to the grid's width; `pomodoro`'s state machine (start, pause, phase end) with a fake clock.
- [ ] **Step 2–4:** FAIL → implement → PASS; each new component seen on the live bar (screenshots).
- [ ] **Step 5: Commit** `bar: the new modules, from GPU to pomodoro (D170)`

---

### Task 5: The media transport, themed

**Files:** Modify `shell/ui/module.plm` (or a `ui/transport.plm` it imports), `shell/bar.luau`; Test `tests/unit/run.lua`

**Interfaces:** previous · play/pause · next drawn from the palette's roles, no literal red/green; the glyph follows the state; a press sends the same `media` events as today.

- [ ] **Step 1: Failing test** — no literal colour in the transport's props; three zones map to `prev`, `toggle`, `next`; the state glyph follows `media_playing`.
- [ ] **Step 2–4:** FAIL → implement → PASS; the three buttons checked on the live bar with the player.
- [ ] **Step 5: Commit** `media: the transport in the bar's own colours (D170)`

---

### Task 6: Settings, live tests, docs

**Files:** Modify `tools/gen-settings.py`, `shell/mooi-settings.luau`, `docs/TESTING.md`, `docs/DECISIONS.md` (D170), `STATUS.md`; extend `tests/chassis.sh`; extend `tests/unit/run.lua`

- [ ] **Step 1:** Settings → Bar & Frame: Density beside Shape, and Display / Minimal / Accent / Warn in each module's Look card; regenerate both files; generator determinism checked.
- [ ] **Step 2:** `chassis.sh` gains density × shape × frame × swell — the foot holds, no hump, and a module's width follows its display without moving the group.
- [ ] **Step 3:** Live pass with each density and the new components; screenshots for the owner; a performance sample against §3's budget.
- [ ] **Step 4:** Docs and the gate (`bin/mooi check`), `setup/capture.sh`, commit `docs: the modules verified (D170)`.
