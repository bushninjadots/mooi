# mooi · Control Nexus — progress

*Updated 2026-10-23.*

## Current phase

**Phase 1 — Nexus foundation** (Phase 0 audit complete: `docs/NEXUS-AUDIT.md`).

## Completed

- Phase 0 repository reconnaissance and architecture audit.
- Baseline verified: `./bin/mooi check`, 166 unit tests, 0 failed; all four scenes compile.
- Integration decision: Nexus is a standalone Pleamar overlay program, opened from a new bar
  module; the existing bar scene keeps its single keyboard clause.
- Service/hardware inventory recorded, including the unavailable power-profiles service.
- First increment implemented: bar trigger, Arch mark, Nexus overlay, open/close/pin, outside
  press, Escape, shared palette/tokens, real read-only status and safe live controls.

## Files changed

New:

- `docs/NEXUS-AUDIT.md`
- `docs/NEXUS-PROGRESS.md`
- `shell/mooi-nexus.plm`
- `shell/mooi-nexus.luau`
- `shell/icons/arch.svg`

Modified:

- `shell/lib/barlayout.luau` — `nexus` module registration.
- `shell/lib/config.luau` — `nexus.pinned`.
- `shell/mooi.plm` — facts, springs, icon, trigger, edit region (regenerated), event.
- `shell/mooi.luau` — program lifecycle and `nexus_open`.
- `tools/gen-settings.py` — Nexus module in generated settings/edit lists.
- `shell/mooi-settings.plm`, `shell/lib/settings_index.luau` — regenerated.
- `bin/mooi` — data link, snapshot, check, `mooi nexus`, help.

## Build and test results

Pending the first compile and live run. See the entries added below after verification.

## Blockers / limitations

- Power profiles are unavailable on this machine (power-profiles-daemon masked); Nexus will
  report the capability as unavailable rather than inventing profiles.
- Bluetooth currently has read-only integration in mooi. A tested write path is Phase 2.
- No installed Arch icon was found; the mark is authored in `shell/icons/arch.svg`.
- Multi-monitor and real hardware variations remain untested.

## Next step

1. Compile and fix.
2. Run the isolated live test for open, close, re-open and no duplicate program.
3. Refresh the live snapshot only after the isolated test passes; verify the bar was not
   disturbed.
4. Begin Phase 2 with audio and media, one integration at a time.
