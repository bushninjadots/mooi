# Status

_Last updated 2026-11-06. History lives in [docs/CHANGELOG.md](docs/CHANGELOG.md); decisions are in
[docs/DECISIONS.md](docs/DECISIONS.md)._

## What is true now

- The shell is built and in daily use: the Ferrolume bar and its islands, Control Nexus, the side
  notch, the music player, desktop widgets, the wallpaper picker, the board, the desk/frame
  programs, BMO and the lock screen.
- The public snapshot is neutral: setup capture writes empty notes/board/stash, a minimal settings
  document and no identity pictures (the two tracked identity images were removed on 2026-11-06;
  see docs/AUDIT-2026-11-06.md, G1).
- `bin/mooi check` compiles every scene by enumeration (13, including `mooi-lock.plm`) and runs
  `tests/gate.sh`; CI runs the same gate where Pleamar is not needed. On 2026-11-06 the gate passed:
  **397 unit tests, 0 failed; 27 BMO tests, 0 failed; 13 scenes compile; Pleamar 0.7.11 · language
  0.9**.
- The generators (`tools/gen-settings.py`, `tools/gen-frame.py`) are deterministic and CI fails if
  their output differs from the committed scenes.

## Verified, with dates

| Area | Last verified | Evidence |
| --- | --- | --- |
| Unit + BMO suites | 2026-11-06 | `bin/mooi check`, exit 0 |
| Scene compilation (all 13) | 2026-11-06 | `bin/mooi check`, exit 0 |
| Generator determinism | 2026-11-06 | run on a `/tmp` copy, no diff |
| The bar's chassis (every shape × outline × frame × swell) | 2026-11-06 | `tests/chassis.sh`, 93 checks, 0 failed (D165) |
| Live session, pointer, multi-monitor, behavioural suites | 2026-11-01 or earlier | docs/TESTING.md; not re-run in the 2026-11-06 audit |
| Performance | 2026-11-06 | music playing, swell on: bar 7.9 %, frame 9.3 % of a core, GPU ~60 % busy (same as before stage 1) |

## Open items

1. The bar redesign (D164) is in stages; stage 1 (one chassis) is done, stage 2 (Ferrolume perfected)
   is next — docs/superpowers/specs/2026-11-06-bar-redesign-design.md.
2. `shell/mooi.plm`, `mooi-settings.plm` and `mooi-frame.plm` remain large generated/monolithic
   files; the panel extraction is incremental (G8).
3. Theme packages have a model and a terminal interface, not yet a browser or a visual editor.
4. Multi-monitor behaviour, 25 %/150 % scale, and input-to-visible latency remain unverified.
5. `shell/mooi-notch.luau` and `shell/mooi-nexus.luau` still share their non-weather panels; the
   weather panel is now shared (`lib/weatherpanel`), the rest is the next increment.

The full 2026-11-06 review, including the fixes applied, is
[docs/AUDIT-2026-11-06.md](docs/AUDIT-2026-11-06.md).
