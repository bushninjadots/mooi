# Status

_Last updated 2026-11-07. History lives in [docs/CHANGELOG.md](docs/CHANGELOG.md); decisions are in
[docs/DECISIONS.md](docs/DECISIONS.md)._

## What is true now

- The shell is built and in daily use: the Ferrolume bar and its islands, Control Nexus, the side
  notch, the music player, desktop widgets, the wallpaper picker, the board, the desk/frame
  programs, BMO and the lock screen.
- The public snapshot is neutral: setup capture writes empty notes/board/stash, a minimal settings
  document and no identity pictures (the two tracked identity images were removed on 2026-11-06;
  see docs/AUDIT-2026-11-06.md, G1).
- `bin/mooi check` compiles every scene by enumeration (13, including `mooi-lock.plm`) and runs
  `tests/gate.sh`; CI runs the same gate where Pleamar is not needed. On 2026-11-07 the gate passed:
  **607 unit tests, 0 failed; 27 BMO tests, 0 failed; 14 scenes compile; Pleamar 0.7.11 · language
  0.9**.
- The generators (`tools/gen-settings.py`, `tools/gen-frame.py`) are deterministic and CI fails if
  their output differs from the committed scenes.

## Verified, with dates

| Area | Last verified | Evidence |
| --- | --- | --- |
| Unit + BMO suites | 2026-11-07 | `tests/gate.sh`: 607 unit + 27 BMO, 0 failed |
| Scene compilation (all 14) | 2026-11-07 | `bin/mooi check`, exit 0 (gate green: 606 unit + 27 BMO) |
| Generator determinism | 2026-11-06 | run on a `/tmp` copy, no diff |
| The bar's chassis, styles and attach (every shape × outline × frame × swell; every style; Pill mode) | 2026-11-06 | `tests/chassis.sh`, 190 checks, 0 failed (D167, D168) |
| The Pill and its board: states, moons, split, faces, hiding, nodes, the board's rooms, pads, edit, music | 2026-11-07 | `tests/pill.sh`, 47 checks, 0 failed (D168–D171); the press check retries once (a real click at the desk can close it, D170) |
| The Pill when idle (stay · tuck · vanish), with the song's colours (D172; the record retired by D202) | 2026-11-07 | unit suite and scene compile; `tests/pill.sh` extended, the live run not yet made |
| The Pill feels the pointer (warmth, the dot's lean), the half disc on a workspace or view change (D173) | 2026-11-07 | unit suite, scene compile; the look has not been seen live |
| The Pill's settings page: the stage, the shape and resting-form cards, warmth and ping (D174) | 2026-11-07 | unit suite, both scenes compile, generator deterministic; the page not yet seen live |
| Wake where you left it, and the desk's first slice (D175) | 2026-11-07 | unit suite, both scenes compile, generator deterministic; the desk not yet seen live |
| The desk as the workspace viewer, with live miniatures (D176) | 2026-11-07 | unit suite, both scenes compile, generator deterministic; the viewer not yet seen live |
| The desk's sizes, presses and look: the opened vial, tint, glow (D177) | 2026-11-07 | unit suite, both scenes compile, generator deterministic; not yet seen live |
| The Pill's search, its stash, the internet panel (D178), the right button's choice (D179) | 2026-11-07 | unit suite, both scenes compile, generator deterministic; not yet seen live |
| The desk's visual editor in Settings (D180) | 2026-11-07 | unit suite, both scenes compile, generator deterministic; not yet seen live |
| The Pill becomes its board (one body), the peek, the edge flash, the new editor, the simpler page (D188) | 2026-11-07 | unit 572/0, 13 scenes, generators deterministic; opening, resize, peek, editor and page seen live; closing and the peek's fold-on-leave not yet watched |
| The fold: closing keeps the card or editor until the body is back in the capsule; rooms at their true heights (D189) | 2026-11-07 | unit 575/0, 13 scenes; the peek's fold-on-leave and the editor's close recorded live at 60 fps (emits, not a real pointer) |
| ArchEclipse's Pill: the glance face, the two-row reveal, the mirror spectrum (D191) | 2026-11-07 | unit 578/0, 13 scenes; glance and reveal seen live, the owner's pointer across the reveal recorded; the spectrum not yet seen playing |
| The Pill's audit: every room photographed; wallpaper bleed, empty network list, visualiser band, Bluetooth button fixed (D193) | 2026-11-07 | unit 592/0; docs/AUDIT-PILL-2026-11-07.md |
| Loom / Fold Phase 1: the model, modes, parking, the keeper, the program, `mooi loom` (D194) | 2026-11-07 | unit 592/0, 14 scenes; Hybrid start, park detection, unpark, crash return, recovery, Start again and `off` checked live on a throwaway window |
| Loom / Fold Phase 2: the Accordion — rules, plans, the strip, settings, keys (D195) | 2026-11-07 | unit 596/0; fold, reorder, switch off/on, closing windows checked live on throwaway windows; pull/step/add by key not yet tried by the owner |
| BMO as the Pill: his screen in the capsule, a hop, a typed line, notes, marks, sleep; the mark during other activities (D196) | 2026-11-07 | unit 597/0; resting, playful and curious faces and the hop seen live |
| Loom / Fold Phase 3: the Cube — rules, projection, keys K/J, partial unfold; BMO centred; keys applied at start (D197) | 2026-11-07 | unit 600/0; fold, unfold, turn, partial checked live on a test copy |
| The Pill's music as Cue draws it, the Notes room, four pads that open rooms (D201) | 2026-11-07 | unit 606/0, 14 scenes compile; not yet seen live (needs the desk and a player) |
| The Pill's audit: dead surface pruned, one height, board-open hiding, peek rows, room names (D202) | 2026-11-07 | unit 606/0, BMO 27/0, 14 scenes compile, settings regenerated; the live suite not re-run |
| The board's rooms on a rail: direct jumps, ↑↓ turning, the turn's light (D203) | 2026-11-07 | unit 607/0, 14 scenes compile; not yet seen live |
| The morph: `pill.shape = morph`, one outline of twelve sprung points, capsule · blob · drop · bead (D204) | 2026-11-07 | unit 621/0, 14 scenes; seen live (idle, drop, blob, reduced motion); frame measured: ~70 ms a frame while it flows vs ~27 attached, so the music ripple is off |
| More pills: a second and a third, each a face, placed anywhere and clamped (D205) | 2026-11-07 | unit 621/0; seen live (automatic gaps, 25 %/50 % placement clamped beside the Pill, the wheel) |
| The Sigil, phase 1: its own program, the line in the Pill and islands, wave-1 sources, director, palette, settings (D207) | 2026-11-07 | unit 667/0, 15 scenes; live tests/sigil.sh 21/22 (the miss a real notice outranking music; fixed check re-run ok); 0.74–0.86 ms with music |
| Surface, phase 1: hold Super — the Aperture through the windows, the hub, a Presence left, remembered and moved with undo (D208) | 2026-11-08 | unit 683/0, 15 scenes; live tests/surface.sh 35/0; reveal 0.75 ms a frame |
| A motion change restarts the bar instead of stopping it (D206) | 2026-11-07 | unit 621/0; seen live: reduced motion on and off, back in ~4 s each |
| The login screen on this desk (D190): greetd + sysc-greet installed and enabled, sddm disabled, mooi's palette followed | 2026-11-07 | `gslapper` 1.5.3-2 and `sysc-greet-hyprland` 1.3.1-2 installed; `greetd` enabled / `sddm` disabled; `greet-theme --status` = `Mooi · followed`; the broken old config kept as `/etc/greetd/config.toml.bak`; **reboot pending** — no real login seen yet |
| Live session, pointer, multi-monitor, behavioural suites | 2026-11-01 or earlier | docs/TESTING.md; not re-run in the 2026-11-06 audit |
| Performance | 2026-11-06 | music playing, swell on: bar 7.9 %, frame 9.3 % of a core, GPU ~60 % busy (same as before stage 1) |

## Open items

1. The bar redesign (D164) is in stages: stage 1 (one chassis), Bar & Frame (styles, settings,
   per-module looks, D167), the Pill (D168, D169) and its board (D170) are done; round two's stage 1 (views, shapes, detail; D171) done, and stage 2's first slice
   (hiding three ways; D172) done, and the one-body Pill that becomes what it shows (D186–D189) finished — docs/superpowers/plans/2026-11-07-pill-many.md has the rest: many pills placed wherever the owner wants, connections
   and motion (including the owner's Venom-like morph), the look, then the stash/terminal/Super layer — and finally the bar's stage 4 (modules and density). Density stays hidden in
   Settings until then.
   Loom / Fold (D194) is in phases: Phases 1–4 (the foundation, the Accordion, the Cube, Loom) are built; Phase 5 is transformations
   (docs/superpowers/specs/2026-11-07-loom-fold-design.md §10).
2. `shell/mooi.plm`, `mooi-settings.plm` and `mooi-frame.plm` remain large generated/monolithic
   files; the panel extraction is incremental (G8).
3. Theme packages have a model and a terminal interface, not yet a browser or a visual editor.
4. Multi-monitor behaviour, 25 %/150 % scale, and input-to-visible latency remain unverified.
5. `shell/mooi-notch.luau` and `shell/mooi-nexus.luau` still share their non-weather panels; the
   weather panel is now shared (`lib/weatherpanel`), the rest is the next increment.

The full 2026-11-06 review, including the fixes applied, is
[docs/AUDIT-2026-11-06.md](docs/AUDIT-2026-11-06.md).
