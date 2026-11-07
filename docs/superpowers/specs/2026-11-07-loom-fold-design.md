# mooi — Loom / Fold: dual-mode architecture and design

Date: 2026-11-07 · Status: approved 2026-11-07; Phase 1 built (D194), Phase 2 — the Accordion — built (D195) ·
Decisions: D194, D195

> **Loom connects. Fold transforms.** Loom / Fold is an optional interaction system *inside* mooi — never a
> replacement for it. One installation, three selectable experiences, one shared foundation.

## 1. What the owner asked for

From the brief, kept in their terms:

- A new interaction system, **Loom / Fold**, that treats windows, apps, files and environments as objects
  that can be connected (Loom) and reshaped (Fold) — first into **Accordions** (a sequence of apps as thin
  stacked panels) and **Cubes** (a whole working environment folded into one object), later Ring, Spine,
  Cluster, Branch, Island.
- **Three operating modes**, chosen in Settings and reversible without losing anything:
  **Native mooi** (today's shell, recognisably itself), **Hybrid** (today's shell plus chosen Loom / Fold
  features), **Loom / Fold** (the complete spatial experience, still usable every day).
- **One shared object and relationship model** for all three modes; Hybrid uses the same engines as full mode.
- **Safety first**: no data lost on a mode switch, structures and connections preserved, configuration
  backed up, a crash or failed start falls back to native mooi, and there is always a way back.
- Real windows, real functionality behind every thread and fold — not visual demos. 60 FPS where the
  hardware allows, nothing rendering while idle, reduced motion that keeps every function.
- Visuals in mooi's identity (industrial, mechanical, origami, precise, fine lines, controlled light), not a
  generic sci-fi theme; colours from mooi's theme engine and Matugen, never hard-coded.
- Build in phases; mode management and the shared object model first.

## 2. Phase 0 — what mooi is, as built (assessment)

Verified in the repository and the running desktop on 2026-11-07.

### 2.1 Runtime and authority

- **Pleamar 0.7.11 (language 0.9)** renders every surface; each `.plm` scene is its own process with its
  own Luau logic. **Hyprland 0.57 with a Lua config** owns windows, focus, workspaces and monitors; mooi asks
  it (`hyprctl dispatch <lua>`, built only in `lib/hypr`) and reads results back (`hyprctl -j clients`). It
  keeps no competing window-manager state (docs/ARCHITECTURE.md §1, §3).
- **Programs**: the bar (`mooi.plm`) is kept alive by `bin/mooi`'s keeper (restart, give up after three quick
  deaths). The bar's logic starts the other programs itself — the frame (`frame_sync`, five quick deaths
  then the bar draws its own plates), BMO (a wanted/happening state machine with generations, `bmo_sync`),
  the notch. Each program's data folder is a link to mooi's (`settings_link`), so all share
  `settings.json` and the other documents.
- **Settings**: one validated document, `~/.local/share/pleamar/mooi/settings.json`, schema in
  `lib/config.luau` (defaults, enums, migrations, versioned), setter codes append-only (`lib/setters` ↔
  `tools/gen-settings.py`), the settings window generated from `gen-settings.py`. `MOOI_SAFE=1` / `mooi run
  --safe` ignores the document.
- **Persistence**: each tool owns a JSON document in the shared folder (environments.json, board.json,
  notes, stash…), read with `sys.ask("files.read")`, written with `files.write`, cleaned by a pure module.

### 2.2 What already exists that Loom / Fold builds on

| Existing | Where | Becomes |
| --- | --- | --- |
| **Saved environments** (D43): capture the desktop (apps by .desktop id, folder, workspace, names, accents, groups), plan a restore against open windows, move what is open, launch what is missing, never close anything | `lib/environments.luau` (pure, tested), `shell/environments.luau` | the **Cube**'s restore engine |
| **Workspace identities and groups** (D42): names, accents, groups of workspaces | `lib/atlas.luau` | structure metadata, accents for structures |
| **The Overview (Atlas)**: window tiles, drag between workspaces, carry/undo of moves (`apply_moves`, `M.undo`) | `lib/atlas.luau`, `mooi.luau` | where structures are manipulated in Hybrid; undo for transformations |
| **The window adapter**: focus, float, move to workspace, maximise, centre, size, close, by address, read back | `lib/hypr.luau` | the only path to real windows (extended with special workspaces) |
| **Live miniatures** (`thumbnails` service, D176 workspace viewer) | `lib/deskprev.luau`, `pillboard.luau` | the faces of Accordion layers and Cube faces |
| **Window controls** (the Shutter, D35) | `shell/shutter.luau` | per-object actions |
| **Program supervision** (frame, BMO) | `mooi.luau` | the pattern for supervising the Loom / Fold program |

### 2.3 What the platform can and cannot do (limits that shape the design)

- **A scene cannot hold other programs' windows under Hyprland.** Pleamar's `windows win max N` puts a
  compositor inside the scene only under *pleamar-wm*; under Hyprland, plain `pleamar` "holds no windows".
  So Accordions and Cubes **move real windows through Hyprland** (special workspaces, workspace moves,
  floating geometry) and **draw them with `thumbnails`**. No embedding, no reparenting.
- **No perspective transforms.** Shapes can be any path (a projected cube's faces are quads computed in
  Luau), images can be scaled on each axis but not skewed. A Cube turns as projected quads with its face
  content scaled across, not texture-mapped — a mechanical, drawn look, which suits mooi.
- **Shaders** (WGSL, one per box) paint procedural light, grain and edges; they do not sample images.
- **Input**: a scene's zones only receive the pointer over its own surfaces; dragging a *real* window onto
  a scene's zone is not delivered. Inserting a window into a structure is done by keys, the Overview's tiles
  (which are scene objects), or a structure's own menu. Touchpad gestures come from Hyprland's gesture
  binds; Pleamar gestures work inside a scene.
- **Hyprland binds** live in `~/.config/hypr/config/custom/mooi.lua`; Super+wheel and Super alone are taken
  (D171). New defaults must avoid those.
- **mooi.luau's main chunk is at Lua's 200-local limit**: new subsystems enter it as `require("x")({…})`
  statements or fields of existing tables.
- **Watching notifications in any program steals the D-Bus name** — Loom / Fold never watches them.

## 3. Architecture

### 3.1 The shape

```
                 ┌──────────── MOOI CORE (unchanged) ────────────┐
                 │ bar · islands · Pill · Overview · frame · notch │
                 │ settings.json · theme · keeper (bin/mooi)       │
                 └───────┬───────────────────────────┬───────────┘
                         │ settings.loom              │ loom.json (read)
               ┌─────────▼─────────┐        ┌─────────▼──────────┐
               │ loomkeeper (in the │ starts │ mooi-loom program   │
               │ bar's logic): mode,│───────▶│ tracker · structures│
               │ supervision,       │ stops  │ loom · fold · render│
               │ recovery, unpark   │◀───────│ persistence · input │
               └────────────────────┘ health └─────────┬──────────┘
                                                        │ hyprctl (lib/hypr)
                                                   ┌────▼────┐
                                                   │ Hyprland │
                                                   └──────────┘
```

- **Native mooi** does not start the program at all: zero cost, zero risk.
- **Hybrid** and **Loom / Fold** run the same program with a different set of effective features; full mode
  adds the spatial surface and routes navigation to it.
- A crash of `mooi-loom` cannot take the bar down (separate process); the keeper, living in the bar, can
  always return windows the program had parked.

### 3.2 Units (each one purpose, tested alone)

| Unit | File | Pure? | Purpose |
| --- | --- | --- | --- |
| Object model | `shell/lib/loom.luau` | yes | DesktopObject, Structure, Connection, WorkspaceEnvironment: create, validate, clean a document, query relations, ids. Versioned. |
| Modes and features | `shell/lib/loommode.luau` | yes | the three modes, the feature list, dependencies, effective features for a mode, explanations of what cannot be on and why |
| Parking | `shell/lib/loompark.luau` | yes | plans that put windows on `special:loom-<id>` and bring them back (Hyprland commands via `lib/hypr`), and the unpark-all plan the keeper runs |
| Accordion rules | `shell/lib/loomaccordion.luau` | yes | Phase 2: states, order, layer geometry, the plans each interaction becomes |
| Cube rules | `shell/lib/loomcube.luau` | yes | Phase 3: faces, roles, projection of the turning cube, partial unfold, mapping to `lib/environments` |
| Connections | `shell/lib/loomlinks.luau` | yes | Phase 4: the five kinds and what each does; thread geometry (tension, curvature) |
| Transformations | `shell/lib/loomxform.luau` | yes | Phase 5: structure → structure preserving ids, members, connections, metadata; journal records |
| Window tracking | `shell/mooi-loom.luau` | no | registers windows as objects from `hyprctl -j clients` on workspace/window events; re-matches identities after restarts |
| Rendering and input | `shell/mooi-loom.plm` (+ `shell/ui/loom*.plm`) | no | the overlays (accordion strips, threads, cube), opened only while there is something to draw |
| Supervision and mode | `shell/loomkeeper.luau` | no | in the bar's logic: wanted vs happening (as BMO), start/stop, quick-death recovery, unpark on death, health for Settings |
| Settings | `lib/config.luau`, `tools/gen-settings.py` | — | the `loom` section and the Interaction → Loom / Fold page |
| Command line | `bin/mooi loom …` | — | `status`, `off` (always works), `mode <native|hybrid|loomfold>`, `unpark` |

**The interfaces native mooi uses** (no direct calls into the program's state):

- **Read**: `loom.json` (the model) and `loom-state.json` (health: pid, mode, features, started, objects,
  last error, recovery flag) in the shared folder — read-only for everyone but `mooi-loom`.
- **Ask**: `pleamar --say mooi-loom "emit loom_cmd …"` — create a structure, add the focused window, fold,
  unfold, connect, transform. The bar, the Pill, the Overview and Hyprland binds (`mooi loom …`) all use it.

### 3.3 The shared model (`loom.json`, version 1)

```json
{
  "version": 1,
  "objects": {
    "o12": { "id": "o12", "kind": "window", "app": "kitty", "desktop": "kitty.desktop",
             "title": "~/Projects/mooi", "address": "0x55d1…", "pid": 4412,
             "state": "live", "workspace": 2, "at": [40, 60, 900, 640], "floating": false,
             "parent": "s3", "meta": { "cwd": "/home/…/mooi" } }
  },
  "structures": {
    "s3": { "id": "s3", "kind": "accordion", "name": "Writing", "members": ["o12", "o14", "o9"],
            "state": "compressed", "arrangement": { "order": ["o12", "o14", "o9"], "open": ["o12"] },
            "parked_on": "special:loom-s3", "saved": { }, "accent": "phos" }
  },
  "connections": {
    "c1": { "id": "c1", "from": "o12", "to": "s5", "kind": "workflow", "directed": true, "meta": { "step": 1 } }
  },
  "environments": {
    "e1": { "id": "e1", "structures": ["s3"], "windows": [], "relations": [], "restore": { } }
  },
  "journal": [ { "id": "j7", "op": "fold", "target": "s3", "moves": [], "state": "done", "at": 0 } ]
}
```

- **Identity**: an object's `id` is mooi's and permanent. `address` and `pid` are the window's *current*
  handle and change on restart; on start the tracker re-matches by `desktop`/`app` + `title` + `cwd` (the
  same matching `lib/environments.plan` does) and marks the rest `absent` — kept, never deleted, shown dim,
  and relaunched from their .desktop entry when their structure unfolds (`environments.launch_line`).
- **Window state vs application state**: `state` is the window's (`live`, `parked`, `absent`); the app's is
  its `desktop`/`meta` (what to relaunch, where).
- **Parked windows** are windows on `special:loom-<structure>` — still running, off every workspace. The
  list of parked windows is always in `loom.json`, so anyone (the keeper) can return them.
- **Journal**: every operation that moves windows writes `pending` before it moves anything and `done`
  after; a start that finds `pending` completes or rolls it back (§5.4).
- Limits as everywhere in mooi: 512 objects, 64 structures, 512 connections, 20 environments, journal 50.

### 3.4 Modes and features (`lib/loommode`)

Settings (`loom` section, defaults first):

| Key | Values | Meaning |
| --- | --- | --- |
| `loom.mode` | `native` · `hybrid` · `loomfold` | the operating mode |
| `loom.fold` | bool (true) | Fold: structures and their transformations |
| `loom.accordions` | bool (true) | needs Fold |
| `loom.cubes` | bool (true) | needs Fold |
| `loom.loom` | bool (true) | Loom: connections |
| `loom.motion` | `full` · `calm` · `off` | how much it moves (off: states change instantly; mooi's reduced motion forces off) |
| `loom.restore` | bool (true) | unfold the last environment's structures at login |

- **Native**: nothing runs; the feature switches are kept, untouched, for the day the owner comes back.
- **Hybrid**: the program runs with exactly the switched-on features whose dependencies hold.
- **Loom / Fold**: every feature that exists is on, whatever the switches say (they are Hybrid's), and the
  spatial surface is the navigation (§6.3).
- `effective(mode, switches, built)` returns the features on and, for each one off, why ("Accordions need
  Fold", "not built yet"). Only **built** features are shown in Settings; the page never offers a switch for
  something that does nothing.

## 4. The structures

### 4.1 Accordion (Phase 2) — a sequence of apps you can pull from

**Under Hyprland**: an Accordion's windows are parked on `special:loom-<id>` except the ones pulled out.
Drawn as a **strip of thin machined layers** at a screen edge the owner picks (default: right), one layer
per window — 6 px slivers with the app's accent edge, its icon and title appearing as the strip is pointed
at. The strip is a small overlay surface; nothing else of the screen is covered.

| State | What it looks like | What the windows do |
| --- | --- | --- |
| compressed | the layers flat together, a 24 px spine | all parked but the one in use |
| partially extended | the layers separate, each showing icon + title | unchanged |
| expanded | a column of layers with live miniatures | unchanged — miniatures only |
| fanned | the layers spread in an arc over the screen, large miniatures | unchanged — a chooser |
| pulled | one layer slides out of the stack | that window comes to the current workspace, focused (others stay parked) |
| pushed back | the layer slides home | the window returns to the park |
| tiled ("open all") | the strip empties | every member comes to the current workspace, Hyprland tiles them |

Interactions: point → extend; press a layer → pull it; press the pulled one again or drag it home → push
back; wheel over the strip → next/previous layer (keyboard: `Super+Alt+[`/`]`); drag a layer along the
strip → reorder; drag one off → remove (the window comes out and stays); "Add focused window" (`Super+Alt+A`
and the strip's menu) → insert; the Overview's tile dragged onto the strip → insert; two strips → merge;
a layer's menu → split here; "Make a Cube" → transformation (§4.4).

Saved: order, which are pulled, the edge, the accent. Restored at login when `loom.restore` is on.

### 4.2 Cube (Phase 3) — a whole environment as one object

**Under Hyprland**: a Cube *is* a saved environment (`lib/environments`) plus a live membership. Unfolded,
its windows sit on their workspaces where they were; folded, they are parked on `special:loom-<id>` and the
Cube is a compact object (a small projected cube, 56 px) docked where the owner left it (the bar's side, the
desktop, the spatial view). Unfolding restores workspaces and floating geometry and launches what is absent.

Faces (assignable, defaults from the brief): **front** main app · **right** supporting apps · **left** files
and resources · **top** quick actions · **bottom** background processes · **back** related environments.
Each face is a list of member objects (or actions, or linked Cubes).

| State | Meaning |
| --- | --- |
| unfolded | members on their workspaces |
| folding / unfolding | the windows are being moved (journaled) while the cube closes / opens |
| folded | all parked; the cube shows its front face |
| rotating | turning to another face (drawn; no windows move) |
| partially unfolded | only the chosen face's members come out |
| expanding | a face opened as a larger panel of miniatures to pick one |
| detached | one member pulled out of a folded Cube, the rest stay folded |

Interactions: wheel or a circular drag over it → rotate; press a face → open (partial unfold); double press
→ fold/unfold all; pull a miniature out → detach; "Add focused window to face…" → insert; drag the cube onto
a workspace → move the environment there; "Duplicate layout" → a new Cube with the same arrangement and
no windows (its apps launch on unfold).

Drawn as projected quads (§2.3): edges as hairlines, faces as machined plates in the theme's surfaces, the
facing side carrying its miniature, the others their icons; one key light, a soft shadow under it.

### 4.3 Loom (Phase 4) — connections that do something

| Kind | Means | Does |
| --- | --- | --- |
| association | "these go together" | focusing one offers the other (a thread lights; `Super+Alt+L` jumps along it) |
| containment | "belongs to" | the structure's membership (an Accordion's or Cube's members are contained) — drawn only on request |
| workflow | an ordered sequence | `Super+Alt+→/←` steps through it; opening the first offers to unfold the rest |
| dependency | one needs another | folding/closing the needed one warns that its dependants lose it; unfolding a dependant brings it |
| navigation | a route | a press on the thread goes to the other end's workspace and focuses it |

Threads are drawn on an overlay between the ends' on-screen places (window geometry from Hyprland, a
structure's own place): fine 1 px lines with slight sag (tension from distance), a directed one with a
small arrowhead; pulling one (drag) reveals its other end even across workspaces (a ghost miniature).
Connections refer to ids, so folding, moving and transforming never break them; a connection whose end is
`absent` is drawn dashed.

### 4.4 Transformations (Phase 5)

One engine, `lib/loomxform`: `transform(model, structure_id, to_kind, opts) → model', journal_entry, moves`.
It keeps every member id, every connection, the metadata and the saved arrangement (the old one is kept in
`saved.<kind>` so a round trip returns exactly). Supported first: Accordion → Cube (members become the front
and right faces in order), Cube → Accordion (faces flattened in face order), Accordion → two Accordions
(split at a layer), Accordions → one Cube (each Accordion a face), Cube → partial unfold, connected Cubes →
one environment. A structure is never deleted and recreated.

### 4.5 Later structures (Phase 8)

Ring, Spine, Cluster, Branch, Island are new `kind`s with their own rules module and renderer; the model,
parking, journal, connections and transformations do not change. Nothing for them is built before Phase 7.

## 5. Modes in practice: switching, safety, recovery

### 5.1 Switching

- Settings → **Interaction → Loom / Fold → Mode** (three pictures), or `mooi loom mode <m>`, or an optional
  bind. The keeper hears the settings change and starts or stops the program; no restart of the shell or the
  computer is needed.
- **Native → Hybrid**: the program starts; structures saved earlier reappear (their strips, docked cubes);
  nothing about the bar changes.
- **Hybrid → Loom / Fold**: the spatial surface becomes available and navigation routes to it (§6.3).
- **→ Native**: the program is asked to stop; it **unparks every window** (all structures shown unfolded on
  their workspaces, as the owner last had them) and writes the model; the structures stay saved, folded
  state remembered, for the next time.

### 5.2 Backups

Before every mode switch and before every transformation, `loom.json` is copied to `loom.json.bak.<n>`
(five kept). `settings.json` is untouched by Loom / Fold except its own `loom` section, written by the
settings window like any other.

### 5.3 Recovery

- **Program death**: the keeper restarts it (1 s, 2 s, 3 s…); three deaths within 10 s each → it stops
  trying, sets `recovery: true` in `loom-state.json`, notifies once ("Loom / Fold stopped after repeated
  failures; your windows are back on their workspaces"), and **unparks every window listed in loom.json**
  itself (the keeper uses `lib/loompark.unpark_all`, so a dead program never strands a window).
- **Failed start** (bad document): the program refuses an invalid `loom.json` (the cleaner keeps what is
  valid, the rest goes to `loom.json.rejected`) and starts with what remains.
- **The way back always exists**: `mooi loom off` (writes `loom.mode = native` through the settings file
  and unparks), `mooi run --safe` (ignores settings: native), and the page's **Start again** after a recovery.

### 5.4 Interrupted operations

The journal's `pending` entry lists the moves an operation will make. On start, a pending fold is
**rolled back** (its windows are unparked: never hide what the owner did not see hidden), a pending unfold is
**completed** (bring the rest out). Either way the result is "windows visible", the safe side.

## 6. Experience

### 6.1 Visual language

- mooi's Ferrolume, not a new theme: machined plates in the theme's surface tokens (`fl.hull`, `fl.well`,
  `fl.trace`), hairline edges, the accent (`fl.phos`) for what is live, the ember for warnings; Matugen's
  palette arrives through the same tokens, so the owner's wallpaper colours everything. No hard-coded colour.
- Structures look like **objects with thickness**: a layer is a thin plate with a lit top edge and a darker
  side; a cube has one key light from the top-left and a soft contact shadow. Threads are 1 px lines with a
  faint glow only while active.
- Avoid: big rounded cards, pill shapes, glassmorphism, neon, gradients for decoration.
- Hybrid draws only its own small objects over the native shell; full mode adds the spatial surface with its
  own backdrop (the wallpaper, dimmed and blurred by the compositor).

### 6.2 Motion

- Springs from the theme (`m.*`), interruptible by construction (a spring retargets mid-flight). Folding is
  a sequence: the layers close one after another (40 ms apart), the cube's faces fold in on its hinges;
  unfolding reverses it. Attraction and tension are springs on the thread's sag and the objects' offsets.
- `loom.motion = off` or mooi's reduced motion: every state changes at once; nothing is lost.
- Idle costs nothing: overlays are closed while there is nothing to draw, and the surface's `rate:` drops to
  10 while nothing moves.

### 6.3 Full Loom / Fold mode

- The **spatial view** is a full-screen surface (opened by `Super+Tab`, or the bar's mark) showing every
  structure and loose window as objects on a plane: Cubes, Accordions, threads between them, windows not in
  any structure as small plates. Pressing one unfolds/focuses it and the view gets out of the way.
- Navigation in this mode routes the Overview's key and Super+wheel to the spatial view; the bar stays
  (it is mooi), the owner can hide it in Bar & Frame as today.
- Everything in the spatial view is also reachable by keyboard (arrows move between objects, Enter opens,
  `F` folds, `C` connects to the next chosen, Esc leaves).

### 6.4 Input defaults (all rebindable in Settings → Keys)

| Action | Default | Notes |
| --- | --- | --- |
| Add focused window to the active Accordion | `Super+Alt+A` | creates one if none |
| Next / previous layer | `Super+Alt+]` / `[` | wheel over the strip too |
| Fold / unfold the focused window's structure | `Super+Alt+F` | double press on the object too |
| Every layer out (open all) | `Super+Alt+U` | `O` is the Overview's (D195) |
| Take the focused window out | `Super+Alt+R` | |
| Connect focused window to… | `Super+Alt+C`, then pick | drag between objects in the spatial view |
| Jump along a connection | `Super+Alt+L` | |
| Spatial view (full mode) | `Super+Tab` | |
| Cancel any drag or pick | `Esc` | |

Super alone, Super+wheel, and every existing mooi bind keep their meaning in Native and Hybrid.

## 7. Settings page: Interaction → Loom / Fold

Shown as it grows — only what exists:

- **Phase 1**: *Mode* (Native · Hybrid · Loom / Fold, three pictures, marked **experimental**), the status
  line (running · stopped · recovered after failures, with **Start again**), and *Motion*.
- **Phase 2** adds *Accordions* (switch, needs Fold) and *Strip edge*.
- **Phase 3** adds *Cubes* (switch, needs Fold) and *Restore at login*.
- **Phase 4** adds *Loom* (switch) and *Threads* (always · when relevant · on request).
- Dependencies are explained on the row ("needs Fold — turn Fold on first"), never silently refused.

## 8. Performance and compatibility

- Native: nothing extra runs. Hybrid: one Pleamar program with closed surfaces while idle; window tracking
  reacts to the workspaces service's events and reads `hyprctl -j clients` at most every 250 ms while things
  change, never on a timer while idle.
- Measured per phase against today's numbers (bar 7.9 %, frame 9.3 % of a core with music): Hybrid with an
  Accordion idle must add < 0.5 % of a core.
- Multi-monitor: special workspaces are global in Hyprland; a structure remembers its monitor and unparks
  there; strips are per monitor (`screens: each`).

## 9. Testing

- Every pure unit (`lib/loom*`) unit-tested in `tests/unit/run.lua` with no scene: document cleaning
  (bad ids, dangling references, over limits), identity re-matching, effective features and their
  explanations, parking plans, the journal's recovery decisions, each transformation's preservation.
- The keeper behaviourally (stand-ins for `spawn`, `after`, `run`): start/stop on mode change, the
  quick-death rule, unpark on death, `mooi loom off`.
- A live suite `tests/loom.sh` per phase on throwaway `kitty --class mooi-probe` windows, restoring
  settings and loom.json byte for byte: a fold parks them, an unfold returns them to the same workspace and
  geometry, a kill of `mooi-loom` mid-fold returns them, a mode switch to Native leaves none parked.
- `bin/mooi check` compiles `mooi-loom.plm` with the others.

## 10. Roadmap

| Phase | Delivers | Done when |
| --- | --- | --- |
| 0 | this assessment and design | approved |
| **1** | `lib/loom`, `lib/loommode`, `lib/loompark`, the `loom` settings section and page (mode + status + motion), `loomkeeper` (supervision, recovery, unpark), the `mooi-loom` program (window tracking, persistence, health), `mooi loom status|off|mode|unpark` | Native unchanged (gate + chassis/pill suites pass); Hybrid starts and stops the program; its death three times returns to stopped with recovery shown; a parked window is always returned |
| 2 | Accordion with real windows: strip, pull/push, reorder, add/remove, tiled, fanned, save/restore | the live suite's accordion section |
| 3 | Cube on `lib/environments`: fold/unfold/partial/detach, faces, rotation, docking, restore | the cube section |
| 4 | Loom: the five kinds, threads, navigation keys, connection survival across folds | the loom section |
| 5 | Transformations with the journal | round trips preserve ids, members, connections |
| 6 | The spatial view, gestures (Hyprland gesture binds), contextual menus | full mode usable for a working day |
| 7 | Settings completion, polish, performance measurement, multi-monitor | performance budget met |
| 8 | Ring, Spine, Cluster, Branch, Island | after 7 |

## 11. The backend boundary, and pleamar-wm (D195)

Every window move goes through `lib/hypr` (the commands) and `lib/loompark` (parking); nothing else knows
the compositor. That is the boundary a second backend replaces. **pleamar-wm** (a compositor whose window
manager is a Pleamar scene) would make a far richer one — a structure could draw the live windows
themselves, scaled on its springs, and `send win(k) aside` is parking — but today it holds at most 16 windows
and 4 monitors and would replace every Hyprland integration mooi has. So Loom / Fold stays on Hyprland; a
pleamar-wm session for Loom / Fold mode alone (its window-manager scene being the spatial view) is a later,
optional backend, after a nested spike shows a hosted window can be scaled and transformed.

## 12. Risks and limits

- **Special workspaces are visible to the owner's own binds** (`togglespecialworkspace`): a parked
  Accordion can be shown by Hyprland directly. Accepted; the strip notices and shows those layers as pulled.
- **Window identity across restarts is a heuristic** (app + title + folder); a renamed title can mismatch.
  Absent objects are kept, never deleted; the owner can re-attach one by adding the window again.
- **No real 3D**: cubes are drawn projections; face content is scaled, not perspective-mapped.
- **Two programs touching windows**: the Overview and Loom / Fold both move windows. Rule: Loom / Fold
  re-reads Hyprland after every move and never assumes; the Overview's moves of a parked window simply
  unpark it (the tracker sees it leave the special workspace).
- **Settings files edited by other tools in parallel** (seen on 2026-11-07): Loom / Fold writes only its
  own section through the settings window's normal path.
