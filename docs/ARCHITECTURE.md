# Architecture

mooi is **one Pleamar scene** (`shell/mooi.plm`) with one Luau logic (`shell/mooi.luau`) on top of Hyprland. It is one scene because Pleamar scenes share no state (limitation G22), and the Spine, Islands and Membranes must.

```
     Hyprland (windows, workspaces, focus, keys)        the system (PipeWire, backlight, power, NM)
        │ socket events / ext-workspace   ▲ hyprctl         │ pleamar services          ▲ sys.call
        ▼                                 │                 ▼                           │
┌─ pleamar process ───────────────────────┼─────────────────────────────────────────────┼──┐
│  render thread · shell/mooi.plm         │      logic thread · shell/mooi.luau          │  │
│   surfaces: Spine · window_island ·     │       settings (lib/config)                  │  │
│             system_island               │       window target + actions (lib/hypr) ────┘  │
│   the slot `open` + rules (never wait)  │       system requests, coalesced 40 ms ─────────┘
│   springs and layers (lifecycle)        │       icons (lib/apps)                          │
│   ui/island.plm: IslandFrame, Level     │                                                 │
│                 ◄──────── facts / texts / events ────────►                                │
└───────────────────────────────────────────────────────────────────────────────────────────┘
     ▲ pleamar --say mooi …   (bin/mooi, Super+Alt+Space)          bin/mooi keeper: restarts, takeover
```

## Who owns what

| State | Owner | Notes |
| --- | --- | --- |
| Windows, workspaces, focus | **Hyprland** | Never mirrored. Read on demand (`hyprctl -j`) or from the `workspaces` service (Hyprland socket; ext-workspace if the socket is gone) |
| Volume, mute, brightness, battery, network | **the system** | Shown from Pleamar's services. A requested change shows only once the service reports it |
| `open` (none / window / system): the island slot | **scene rules** | Input on the render thread, so Escape and the Spine buttons work even if the logic hangs. The logic closes the window island only if it still holds the slot |
| `phase` (compact / expanded) | scene rules | Depth of whichever island holds the slot |
| `sel`, `wsel`, `arming`, `srow` | scene rules | Selection and close confirmation |
| `busy` | set by rules, cleared by the logic | A window action is with Hyprland; actions are refused while it holds |
| Window target | logic, **from Hyprland** | Captured by address when the window island opens, refreshed after every action |
| Settings | `~/.local/share/pleamar/mooi/settings.json` | The only on-disk source. JSON, versioned, schema in `lib/config.luau` |
| Tokens | `shell/theme/tokens.plm` | Colours, geometry, motion; components use semantic names only |

## The island slot and lifecycle

```
                open_window                       activate(Move)
   none ─────────────────────────► window/compact ───────────────► window/expanded
    ▲ ▲ ◄── Esc / button / × / 30 s idle ──┘  ▲ ◄────────── Esc ───────┘
    │ │                                        │
    │ └── target gone · closed · moved (logic)  open_system / open_window hand the slot over
    │                                        ▼
    └────── Esc / button ─────────────── system
```

Escape takes the topmost level first: a pending close confirmation, then the expanded state, then the island.

Each island has its own reveal spring (`rv.window`, `rv.system`). `entering` and `exiting` are not states: they are that spring travelling (`layer life.*`: `m.enter` in, `m.exit` out). Handing the slot over moves both springs at once, each from where it is. Rapid switching therefore never leaves a half-open island (tested: window → system → window inside 120 ms). A surface stays mapped while its spring is above 0.004, so it never vanishes before it has left.

Global modes (Rest / Focus / Explore / Workshop / Ambient) are still only specified. They will be one more scene-owned enum above the slot.

## The motion framework

| Token | Spring | Duration | Used by |
| --- | --- | --- | --- |
| `m.instant` | 12247, 221 | 60 ms | state flips that must not lag |
| `m.select` | 3062, 111 | 120 ms | selection.change, focus.change, feedback text, level values |
| `m.enter` | 1361, 74 | 180 ms | surface.enter |
| `m.exit` | 2249, 95 | 140 ms | surface.exit |
| `m.expand` / `m.collapse` | 1102, 66 / 1722, 83 | 200 / 160 ms | window island depth |
| `m.confirm` | 765, 55 | 240 ms | state.confirm: the Spine pulses the workspace a window was moved to |
| `m.reflow` | 911, 60 | 220 ms | layout.reflow: the workspace column |

All are critically damped, which means no overshoot and the duration is time to 99 %. `tests/scene.sh` measures five of them on every run. `--reduced-motion` settles every spring at once (tested: 0 frames between open and closed).

## Adding an island

1. Add a value to `fact open` and a reveal spring `rv.<name>` with its `layer life.<name>`.
2. Declare `surface <name>_island` anchored next to its Spine anchor, with `keyboard: exclusive while open == <name>` and `open: open == <name> or rv.<name> > 0.004`.
3. Draw it inside `IslandFrame(rv.<name>, w, h[, up: true])` from `ui/island.plm`.
4. Add `on open_<name>` rules (toggle and hand-over), its keys guarded by `while open == <name>`, and an Escape rule.
5. Add it to `tests/scene.sh`.

## Actions: the honesty loop

```
rule: activate(k) → busy = true; emit act(k)
logic: read window by address ── gone? → "That window is gone", close the island
       build Lua dispatch (lib/hypr: address validated as ^0x%x+$)
       hyprctl dispatch … ── not "ok"? → "Hyprland refused: …"
       read window back ── compare with before (close: poll 6 × 250 ms)
       → op_done "Floating" / op_failed "Hyprland did not change floating"
```

"ok" from `hyprctl` is not trusted: Hyprland answers "ok" for an address that does not exist. Without Hyprland's IPC, the window island opens and says there is nothing to act on, and actions stay refused (`tests/degraded.sh`).

## Configuration and recovery

1. `MOOI_SAFE=1` (or `bin/mooi run --safe`): built-in defaults, and the file is not read.
2. File missing: defaults, which are then written to the file.
3. File broken (not JSON): `settings.known-good.json`, the last file that loaded with no problems; otherwise defaults. The Spine shows a heat-coloured dot.
4. A field wrong (type or range): that field's default, the rest applied, the dot shown.
5. Unknown keys: logged and ignored. A newer `version`: noted.

The file is watched, so edits apply live. `motion.reduced` is read by `bin/mooi` at launch (it maps to `--reduced-motion`).

## Files

| | |
| --- | --- |
| `shell/mooi.plm` | the scene: Spine, both islands, rules |
| `shell/ui/island.plm` | shared pieces: `IslandFrame`, `Level` |
| `shell/theme/tokens.plm` | palette, semantic colours, geometry, motion springs |
| `shell/mooi.luau` | glue: settings, window target and actions, system requests, icons |
| `shell/lib/config.luau` · `hypr.luau` · `apps.luau` | pure modules, unit-tested under Lua 5.4 |
| `bin/mooi` | launcher, keeper and shell switch (SWITCHING.md) |
| `tests/` | unit, scene lifecycle and motion, live Hyprland and system, degraded IPC, config recovery |
