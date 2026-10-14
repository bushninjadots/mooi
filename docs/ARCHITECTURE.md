# Architecture

Tidal Shell is **one Pleamar scene** (`shell/tidal.plm`) with one Luau logic (`shell/tidal.luau`) on top of Hyprland. It is one scene because Pleamar scenes share no state (limitation G22), and the Spine, Islands and Membranes must.

```
             Hyprland  (owns windows, workspaces, focus, keybinds)
                │ socket events               ▲ hyprctl dispatch (Lua), hyprctl -j
                ▼                             │
┌─ pleamar process ──────────────────────────┼────────────────────────────┐
│  render thread                             │   logic thread (Luau)      │
│  shell/tidal.plm                           │   shell/tidal.luau         │
│   · surfaces: Spine (unnamed), island      │    · settings: load/validate│
│   · springs, layers (lifecycle)            │    · target capture        │
│   · rules: input → phase  (never waits)    │    · actions + read-back   │
│   · services: workspaces, clock            │   lib/config  lib/hypr     │
│                   ◄── facts / texts / events ──►   lib/apps (pure)    │
└────────────────────────────────────────────────────────────────────────┘
        ▲ pleamar --say tidal "emit open_window"   (bin/tidal open, keybinds)
```

## Who owns what

| State | Owner | Notes |
| --- | --- | --- |
| Windows, workspaces, focus | **Hyprland** | Never mirrored. Read on demand (`hyprctl -j`) or from the `workspaces` service |
| `phase` (hidden / compact / expanded) | **scene rules** | Driven by input on the render thread, so Escape and the Spine button work even if the logic hangs. The logic sets it only to `hidden` (target gone, close or move finished) or back to `compact` (a failed move) |
| `sel`, `wsel`, `arming` | scene rules | Selection and close confirmation |
| `busy` | set by rules, cleared by the logic | An action is with Hyprland. Actions are refused while it holds |
| Target window (`floating`, `fullscreen`, …) | logic, **from Hyprland** | Captured by address when the island opens and refreshed after every action |
| Settings | `~/.local/share/pleamar/tidal/settings.json` | The only on-disk source. JSON, versioned, schema in `lib/config.luau` |
| Motion and colour tokens | `shell/theme/tokens.plm` | Semantic names only in components |

## Surface lifecycle

```
            open_window                 activate(Move)
 hidden ─────────────────► compact ─────────────────────► expanded
   ▲  ◄──── Esc / button ──┘  ▲  ◄──────────── Esc ─────────┘
   │                          │
   └── target gone / closed / moved (logic)
```

`entering` and `exiting` are not separate states. They are the `reveal` spring travelling (`layer life`: `m.enter` going in, `m.exit` going out). Reversing mid-way retargets the spring from where it is, so there is no jump. The surface stays mapped while `reveal > 0.004`, so it never vanishes before it has left. Same for `depth` (`m.expand` / `m.collapse`).

Global modes (Rest / Focus / Explore / Workshop / Ambient) are **not implemented yet**. Only Rest exists. They will be one enum fact owned by the scene, with each surface's `phase` subordinate to it (see SPEC.md §2).

## Actions: the honesty loop

```
rule: activate(k) → busy = true; emit act(k)
logic: read window by address ── gone? → "That window is gone", phase = hidden
       build Lua dispatch (lib/hypr: address validated as ^0x%x+$)
       hyprctl dispatch … ── not "ok"? → "Hyprland refused: …"
       read window back ── compare with before (close: poll 6 × 250 ms)
       → op_done "Floating" / op_failed "Hyprland did not change floating"
```

"ok" from `hyprctl` is not trusted: Hyprland answers "ok" for an address that does not exist.

## Configuration and recovery

1. `TIDAL_SAFE=1` (or `bin/tidal run --safe`): built-in defaults, and the file is not read.
2. File missing: defaults, which are then written to the file.
3. File broken (not JSON): `settings.known-good.json`, the last file that loaded with no problems; otherwise defaults. The Spine shows a heat-coloured dot.
4. A field wrong (type or range): that field's default, the rest applied, the dot shown.
5. Unknown keys: logged and ignored. A newer `version`: noted.

The file is watched, so edits apply live. `motion.reduced` is read by `bin/tidal` at launch (it maps to `--reduced-motion`).

## Files

| | |
| --- | --- |
| `shell/tidal.plm` | the scene: Spine, island, rules |
| `shell/theme/tokens.plm` | palette, semantic colours, motion springs |
| `shell/tidal.luau` | glue: settings, target, actions, icons |
| `shell/lib/config.luau` · `hypr.luau` · `apps.luau` | pure modules, unit-tested under Lua 5.4 |
| `bin/tidal` | dev launcher (`run`, `stop`, `open`, `say`, `check`) |
| `tests/` | unit, scene lifecycle and motion, live Hyprland, config recovery |
