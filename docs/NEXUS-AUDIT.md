# mooi · Control Nexus — Phase 0 audit

*2026-10-23 · repository `~/Projects/mooi` · Pleamar 0.4.6 (language 0.4)*

This is the Phase 0 reconnaissance for Control Nexus: what exists, what can be reused, what has
to be built, how the new component fits the shell, and which limits are real on this machine.
It is deliberately written before any Nexus scene or logic exists.

## 1. Baseline

| Check | Result |
| --- | --- |
| `./bin/mooi check` | exits 0: all four scenes compile, all Lua parses, **166 unit tests, 0 failed** |
| `./bin/mooi status` | session mode, keeper running, theme watch following the current wallpaper |
| Pleamar | `pleamar 0.4.6 · language 0.4` |
| Display | single `eDP-1`, 1920 × 1080, scale 1, workspace reserve `[0, 33, 0, 0]` |
| Compositor | Hyprland |
| Repository state | HEAD `00e72d8`; extensive uncommitted D64 work is preserved and untouched |
| Existing bar | running from the live snapshot at `~/.local/state/mooi/live` |

The uncommitted tree is the working baseline. Nothing in this audit reverts, commits or prunes
it. Phase 1 changes are additive where possible and are listed in `docs/NEXUS-PROGRESS.md`.

## 2. The architecture we must keep

- **One bar scene** — `shell/mooi.plm` + `shell/mooi.luau`. It owns the bar, islands, command
  membrane, Atlas/Overview and Shutter. Pleamar scenes share no state, so they do not get
  folded together.
- **The properties of the bar surface** are the scene's first surface. Its `keyboard:` mode and
  the last declared `while` are global to the scene. An island must never declare `keyboard:`;
  adding another declarer silently replaces the bar's condition. This is why the board and the
  wallpaper studio became separate programs (D64 and before it).
- **Standalone programs** — `mooi-settings`, `mooi-wallpaper`, `mooi-board` are separate
  scenes, started by the bar's logic with `pleamar --scene … --no-hud`, and given mooi's data
  folder through symlinks made by `bin/mooi`.
- **Bar modules** are declared in `shell/lib/barlayout.luau` (`MODULES`, `ORDER`, `DEFAULT`),
  drawn in `shell/mooi.plm` through per-module facts (`x_`, `p_`, `w_`, `m_`, `fi_`, `g_`) and
  springs (`xs_`, `ws_`, `pv_`), and positioned by `shell/bar.luau`. The generated edit region
  in `mooi.plm` comes from `tools/gen-settings.py`; it must be regenerated, not hand-edited.
- **Colour** — `palette.json` (Matugen) → `shell/lib/theme.luau` for semantic tokens and
  `shell/lib/ferro.luau` for the nineteen Ferrolume roles. Scenes paint `fr_*` and `c_*`
  facts; `theme/tokens.plm` and `theme/ferrolume.plm` read them. A standalone program copies
  the fact block and paints the same roles. There is no second palette.
- **Settings** — `shell/lib/config.luau`, schema version 1, dotted paths, defaults,
  validation, migration, known-good backup, atomic Pleamar writes and a live file watch.
  `MOOI_SAFE=1` disables writes. Settings are mooi's own `settings.json`.
- **Motion** — named critical-damped springs in `theme/tokens.plm` and `theme/ferrolume.plm`.
  `--reduced-motion` settles them instantly.
- **Keyboard, outside press, honesty** — the bar's `dismiss` layer closes islands; overlay
  programs use a full-screen `away` zone. Hyprland actions are verified by read-back, not by a
  process's exit code alone. Missing services are reported as missing, never faked.

## 3. Source-file map

### Must be touched for the foundation

| File | Why |
| --- | --- |
| `shell/lib/barlayout.luau` | register the `nexus` bar module and its place in the default right side |
| `shell/mooi.plm` | module facts, springs, Arch icon, trigger group, edit region, event |
| `shell/icons/arch.svg` | the bar's Arch mark (no installed Arch icon was found) |
| `tools/gen-settings.py` | add `nexus` to `MODULES` / `NAMES`, then regenerate the edit region and settings lists |
| `shell/mooi.luau` | start/stop the Nexus program, publish `nexus_open`, log failures |
| `shell/mooi-nexus.plm` | the Nexus program: full-screen overlay, floating plate, modules |
| `shell/mooi-nexus.luau` | Nexus startup, palette painting, pin persistence, close |
| `shell/lib/config.luau` | `nexus.*` persisted settings (starting with `pinned`) |
| `bin/mooi` | data-folder link, snapshot check, `mooi nexus`, compile check, help |
| `tests/nexus.sh` | live program test in the board/wallpaper style (added after the scene works) |
| `docs/NEXUS-PROGRESS.md` | phase, changes, results, blockers, next step |
| `docs/DECISIONS.md` | D65 when the foundation is accepted |

### Read for reuse, not replaced

`shell/mooi-board.plm` and `shell/mooi-board.luau` are the closest standalone-program
templates: the same `fr_/pr_/c_/st_` colour block, full-screen overlay surface, `away` press,
entrance springs, data-folder link and palette watch. `shell/mooi-wallpaper.plm` shows a larger
program with more services. `shell/mooi-settings.plm` shows generated settings UI and live sound
controls. `shell/signals.luau` + `ui/loom.plm` own notifications. `shell/lib/sysinfo.luau` owns
pure CPU/RAM/network/temperature readers. `shell/lib/hypr.luau` owns validated window actions.

## 4. What already exists and can be reused

### Bar, surface and motion

- the existing bar strip and its module contract;
- `Chamfer`, `CutButton`, `Pill`, text/box/line/zone primitives;
- `fl.*` roles and `Theme.*` semantic tokens;
- motion springs (`m.enter`, `m.exit`, `m.expand`, `m.collapse`, `fl.relight`, `fl.flow`);
- the outside-press and Escape conventions;
- `--reduced-motion` and the settings `motion.speed` pacing in `bin/mooi`.

### Real services already exposed to Pleamar

`workspaces`, `workspaces.focus`, `window`, `apps`, `clock`, `clock.seconds`, `files`,
`files.write`, `env`, `audio` (volume, mute, input, input mute, outputs, inputs, apps),
`brightness` (present, level), `battery` (present, percent, charging), `network` (online, kind,
name, strength, networks), `bluetooth` (present, powered, discovering, devices), `media`
(playing, title, artist, album, length, position, art, player, players), `apps.launch`,
`thumbnails`, `tray`, `notifications`, `notification_history`, and `session.*` commands.

### Data and persistence

- `settings.json` schema, validation and safe writes;
- `palette.json` and the theme watch;
- per-scene data folders linked to mooi's;
- `MOOI_SAFE` test mode;
- unit-test and live-scene test conventions.

### Existing integrations verified on this machine

| Capability | State | Reuse |
| --- | --- | --- |
| Audio | PipeWire 1.6.10 + WirePlumber; `wpctl` works | Pleamar `audio` service |
| Brightness | `amdgpu_bl1`, 65535, 100 % | Pleamar `brightness` service |
| Battery | `battery_BAT1`, line power `ADP1`; UPower active | Pleamar `battery` service |
| Network | NetworkManager active; `wlan0` connected | Pleamar `network` service |
| Bluetooth | BlueZ active; controller present, powered off | Pleamar read state now; writes later |
| Media | mpd MPRIS session, `playerctl` installed | Pleamar `media` service |
| Notifications | Pleamar owns `org.freedesktop.Notifications` | existing Signal Loom |
| Temperature / CPU / RAM | `sensors` and `/proc` readable | `shell/lib/sysinfo.luau` |
| Power profiles | **power-profiles-daemon masked/inactive** | unavailable state, no fake profiles |
| Arch icon | no installed Arch asset found | author `shell/icons/arch.svg` |

## 5. New work required

1. **Bar trigger** — a new `nexus` module, Arch icon, active/open state, edit-mode grip and
   generated settings row. It must open and close the same program.
2. **Nexus program** — a full-screen overlay scene with a right-anchored floating plate, an
   outside-press layer, Escape, pin, entrance/exit springs and the shared colour block.
3. **Module host inside Nexus** — a first structured layout (profile header, system status,
   media, workspace, quick actions, a reserved editor area) with module boundaries that can
   grow into the editor. Phase 1 is layout only; no drag/drop yet.
4. **Persistent settings** — `nexus.pinned` now; later `nexus.*` layout, order, spans, profile
   paths, theme and motion overrides. Live readings stay out of settings.
5. **Program lifecycle** — duplicate-start guard, close-by-same-trigger, clean exit, bar badge.
6. **Packaging and tests** — link/snapshot/check/command in `bin/mooi`; live test in the style
   of `tests/board.sh`; progress document and D65.

## 6. Integration decision

**Nexus is a standalone Pleamar program, not an island in the bar scene.**

Reasons:

- the main scene's single keyboard clause makes a keyboard-owning panel in the bar unsafe;
- Nexus needs a full-screen outside-press layer, a free-floating surface and eventually a
  visual editor with focus, text inputs, drag/drop and undo — exactly the reasons the board and
  the wallpaper studio are programs;
- a standalone program can be launched, closed, refreshed and tested without touching the
  running bar's scene;
- it still integrates with the bar through a real module, the same data folder, the shared
  palette and the existing `spawn`/`--say` lifecycle.

The bar module is the anchor. The program is the room it opens.

## 7. Phase plan

| Phase | Scope | Gate |
| --- | --- | --- |
| **0** | this audit and progress document | no code changes yet |
| **1** | bar trigger, Arch mark, standalone Nexus surface, positioning, open/close/pin, outside press, Escape, shared tokens, real read-only status, `mooi nexus`, live test | bar still works; panel opens once, closes cleanly, settings persist |
| **2** | audio/media controls, brightness, notifications, network/Bluetooth, battery/power, monitoring, workspace/actions | each control changes real state; unavailable states are honest |
| **3** | profile banner/avatar, wallpaper-adaptive colours, geometry/density overrides | images validate; palette changes propagate; fallbacks |
| **4** | spatial motion, reduced motion, performance safeguards | responsive open/close, no duplicate panels or flicker |
| **5** | visual editor, grid, inspector, drag/drop, resize, undo/redo/reset | changes persist and are reversible |
| **6** | presets, import/export, advanced graphs/effects | validated import cannot execute code |
| **7** | integration/polish, multi-monitor, restart, packaging | measured, documented, no mock paths |

## 8. Phase 1 acceptance criteria

- the Arch trigger appears in the real bar and opens Nexus;
- pressing it again, Escape or an outside press closes the same program;
- the bar remains functional and can still open settings, wallpaper and board;
- the panel is inside the usable 1920 × 1080 area under the 33 px bar reserve;
- pinned state survives a restart;
- live readings come from Pleamar services, not constants;
- volume/mute/brightness/media controls (if included in the first increment) act on the real
  system and report failure instead of claiming success;
- `./bin/mooi check` passes and a live test exercises open, close and re-open without duplicate
  surfaces;
- the progress document names what is built, what is untested and what is next.

## 9. Known limitations and blockers

- **Power profiles unavailable** — `powerprofilesctl get` fails because
  `org.freedesktop.UPower.PowerProfiles` is masked. Nexus must show unavailable, not a fake
  profile selector, until the service is enabled by the user.
- **Bluetooth write path** — the bar reads BlueZ state but does not toggle the controller. A
  safe write path needs testing and a permission decision; Phase 2.
- **No Arch asset installed** — the mark will be an authored line icon in `shell/icons/`.
- **Fixed surface sizes** — Pleamar surfaces are declared at a size; the Nexus plate must be
  laid out for the current display and clamped, not resized arbitrarily by the user yet.
- **Single scene keyboard rule** — any future keyboard-bearing panel must stay a standalone
  program or wait for a framework change.
- **No free-form layout promise** — Phase 5 starts with a grid. Arbitrary pixel positioning is
  not promised until the renderer and persistence model support it reliably.
- **Live tests need the user's bar left alone** — use an isolated runtime like `tests/board.sh`;
  do not restart the user's session without asking.
- **No mocks in production** — test fixtures may mock, but the shipped scene must show the
  actual service values or an explicit unavailable state.

## 10. First safe increment

The first increment is the smallest end-to-end slice:

1. add the `nexus` bar module and Arch mark;
2. add the standalone `mooi-nexus` scene and logic with shared colours and a fixed right-anchored
   plate;
3. open/close/pin, outside press, Escape, single instance;
4. show real clock, audio, brightness, battery, network, Bluetooth, workspace and media state;
5. include only the safest real controls: volume scroll, mute, brightness scroll and media
   transport. No destructive session actions, no fake power profiles;
6. persist `nexus.pinned`;
7. wire `bin/mooi nexus`, link/snapshot/check, add a live test and update the progress document.

Everything else waits for its phase.
