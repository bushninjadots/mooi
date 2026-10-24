# mooi · Control Nexus — progress

*Updated 2026-10-24.*

## Current phase

**Phase 1 complete; Phase 2 next.** Phase 0 reconnaissance is `docs/NEXUS-AUDIT.md`; the staged
plan is `docs/CONTROL-NEXUS-NEXT-PHASE.md`.

## Built

- **Bar trigger.** A `nexus` module (the Arch mark, `shell/icons/arch.svg`) in
  `DEFAULT.right`; a press opens or closes exactly one standalone program, and the bar carries
  `nexus_open` so its own state is real.
- **Program.** `shell/mooi-nexus.plm` + `shell/mooi-nexus.luau` — a full-screen overlay with a
  right-anchored plate under the bar, an outside-press dismissal (unless pinned), ×, Escape,
  entrance/exit springs, the shared palette and theme tokens, and a duplicate-start guard.
- **Readings.** Clock/date, workspace, audio, brightness, battery, network, Bluetooth
  (present/powered), media; distro + version, kernel, uptime, CPU model, CPU load with core
  count, memory, root filesystem, network RX/TX rates, temperature, DRM GPU busy where the
  driver exposes it, and the Hyprland display summary. Missing sensors stay `N/A`.
- **Safe controls.** Output volume (wheel, click to mute), brightness (wheel), media transport
  (previous / play-pause / next). A refused call is reported in the footer, never faked.
- **System Overview.** A read-only panel toggled from the header: distro + version, kernel,
  uptime, CPU, memory, root storage, displays, GPU, host, session, workspace/time, and
  **COPY DIAGNOSTICS** (`mooi diagnostics copy`, local-only). Back returns to the controls.
- **System Identity.** Editable display name through a native Pleamar input, plus avatar and
  banner imports (`zenity` → `mooi identity`), rendered by the scene's own images. Paths stay
  inside mooi's data folder; writes are refused under `MOOI_SAFE=1`.
- **Persistence.** `nexus.pinned` and `nexus.identity.*` in `settings.json` (schema v1,
  validated, atomic writes).

## Files changed

New earlier: `docs/NEXUS-AUDIT.md`, `docs/NEXUS-PROGRESS.md`, `shell/mooi-nexus.plm`,
`shell/mooi-nexus.luau`, `shell/icons/arch.svg`, `docs/CONTROL-NEXUS-NEXT-PHASE.md`,
`shell/lib/telemetry.luau`, `tests/nexus.sh`.

Modified in this build pass:

- `shell/mooi-nexus.plm` — resolved the merge markers left by the branch consolidation;
  System Overview view and its toggle; identity presence facts and initial; availability-aware
  Bluetooth footer; input declaration brought to the language's current properties; command
  allowlist (`hyprctl`, `mooi`, `zenity`, no `sh`).
- `shell/mooi-nexus.luau` — resolved merge markers; fixed `env()` being used before it was
  declared (the logic died at startup); `sync_identity()` publishes name, initial, paths and
  presence facts from one place; per-identity writes respect `MOOI_SAFE`; GPU busy read over
  fixed `card0…card2` paths instead of a shell; distro row carries the OS version.
- `shell/lib/sysinfo.luau` — `cpu_cores` split on a literal `\n` instead of a newline; the
  display scale formats as `1.00x`.
- `tests/unit/run.lua` — new telemetry fixtures use real newlines; the layout fixture now
  reflects the real default `media.idle = "collapse"` (nothing playing).
- `tests/nexus.sh` — checks the local collector and the System Overview toggle.

## Verification

- `./bin/mooi check`: **all five scenes compile** (bar, settings, wallpaper studio, board,
  Nexus), **182 unit tests, 0 failed**.
- **Isolated run** (temporary `HOME`/`XDG`, `MOOI_SAFE=1`, no effect on the running bar):
  real readings — EndeavourOS, kernel `7.2.11-arch1-1`, uptime, CPU load with 12 cores,
  memory, 80 % root disk, `eDP-1 · 1920x1080 · 60 Hz · 1.00x`, GPU 13 %, 50 °C; pin on/off;
  Overview on/off; Escape ended the program; no runtime errors.
- **Identity:** saving in safe mode is refused with a notice and settings are untouched;
  with writes enabled the name persists to `settings.json` and survives a restart.
- **Lifecycle:** a live mooi is running on this machine, so the combined test was reproduced
  in a temporary copy of `shell/` with the bar scene renamed `mooi-lab` (its own socket):
  two rapid activations start exactly one Nexus, the bar marks `nexus_open` true, the same
  trigger closes it and clears the bar, reopening works, and Escape ends it. No bar errors.

## Not checked

- A real hand/pointer on the new Overview toggle and COPY DIAGNOSTICS (the facts were driven
  with `pleamar --say`).
- The Overview's on-screen density at every plate width, and multi-monitor placement.
- `tests/nexus.sh` end to end against the live bar: it correctly refuses while mooi runs; its
  checks were exercised by the `mooi-lab` equivalent above.
- Power profiles (power-profiles-daemon is masked) and Bluetooth writes: still unavailable /
  read-only, as the audit requires.

## Next step

1. Phase 2 integrations, one at a time with read-back: audio routing and input, Bluetooth
   writes, battery/power details, workspace and quick actions.
2. A visual pass with a real pointer over the header, tiles, Overview and identity editor.
3. Add paging or denser rows to the Overview before adding more hardware detail.
