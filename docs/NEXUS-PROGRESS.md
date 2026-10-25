# mooi · Control Nexus — progress

*Updated 2026-10-25.*

## Current phase

**Visual refinement pass in progress on `work/control-nexus-visual-refinement`.** This pass is intentionally limited to hierarchy, spacing and clear view labels before expanding feature scope. Runtime verification is pending; the source edits have not yet been compiled locally.

**Phase 1 complete; Phase 2 begun.** Phase 0 reconnaissance is `docs/NEXUS-AUDIT.md`; the staged
plan is `docs/CONTROL-NEXUS-NEXT-PHASE.md`. The first Phase 2 increment — audio routing and the
Bluetooth radio — is built; connecting devices and app volumes come next.

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
- **Audio routing view (Phase 2).** A second header view: press **OUTPUT** or **INPUT** to cycle
  the default device, wheel the **MICROPHONE** row to set its level, press it to mute, and toggle
  the **Bluetooth** radio. Device names come from the audio service (`outputs` / `inputs`), the
  microphone level from `audio.input` / `input_muted`, and the radio from `bluetooth.present` /
  `powered`. An absent adapter says `N/A`; a refused call is reported in the footer.
  `lib/nexus.next_device` / `default_device` are pure and unit-tested.

## Files changed

New earlier: `docs/NEXUS-AUDIT.md`, `docs/NEXUS-PROGRESS.md`, `shell/mooi-nexus.plm`,
`shell/mooi-nexus.luau`, `shell/icons/arch.svg`, `docs/CONTROL-NEXUS-NEXT-PHASE.md`,
`shell/lib/telemetry.luau`, `tests/nexus.sh`.

Modified in this build pass:

- `shell/mooi-nexus.plm` — resolved the merge markers left by the branch consolidation;
  System Overview view and its toggle; the audio routing view and its toggle; identity presence
  facts and initial; availability-aware Bluetooth footer; input declaration brought to the
  language's current properties; command allowlist (`hyprctl`, `mooi`, `zenity`, no `sh`).
- `shell/mooi-nexus.luau` — resolved merge markers; fixed `env()` being used before it was
  declared (the logic died at startup); `sync_identity()` publishes name, initial, paths and
  presence facts from one place; per-identity writes respect `MOOI_SAFE`; GPU busy read over
  fixed `card0…card2` paths instead of a shell; distro row carries the OS version; audio
  device names and the microphone/Bluetooth paths are read back from the services.
- `shell/lib/nexus.luau` — `next_device` / `default_device` for routing lists.
- `tests/unit/run.lua` — fixtures and the routing test (183 tests now).
- `shell/lib/sysinfo.luau` — `cpu_cores` split on a literal `\n` instead of a newline; the
  display scale formats as `1.00x`.
- `tests/unit/run.lua` — new telemetry fixtures use real newlines; the layout fixture now
  reflects the real default `media.idle = "collapse"` (nothing playing).
- `tests/nexus.sh` — checks the local collector and the System Overview toggle.

## Verification

- `./bin/mooi check`: **all five scenes compile** (bar, settings, wallpaper studio, board,
  Nexus), **183 unit tests, 0 failed**.
- **Isolated run** (temporary `HOME`/`XDG`, `MOOI_SAFE=1`, no effect on the running bar):
  real readings — EndeavourOS, kernel `7.2.11-arch1-1`, uptime, CPU load with 12 cores,
  memory, 80 % root disk, `eDP-1 · 1920x1080 · 60 Hz · 1.00x`, GPU 13 %, 50 °C; pin on/off;
  Overview on/off; Escape ended the program; no runtime errors.
- **Identity:** saving in safe mode is refused with a notice and settings are untouched;
  with writes enabled the name persists to `settings.json` and survives a restart.
- **Audio view (isolated):** the output named `Ryzen HD Audio Controller Speaker`, the input
  `Ryzen HD Audio Controller Digital Microphone`, `audio.input = 0` and `input_muted = false`,
  Bluetooth `present = true`, `powered = false`; the audio and overview views are mutually
  exclusive; no runtime errors. The write paths (cycling a device, mic level/mute, powering the
  radio) were **not** exercised, so the user's audio and Bluetooth were left untouched.
- **Live deployment:** after `bin/mooi refresh` the Arch mark is on the real bar (`x_nexus` =
  1097), `bin/mooi nexus` opens the program, the bar marks `nexus_open` true, the AUDIO view
  names the real output device, and Escape ends it and clears the bar's state.
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
- Power profiles (power-profiles-daemon is masked): still unavailable, as the audit requires.
- The Phase 2 write calls (audio default, microphone level/mute, Bluetooth power) are built on
  the documented service calls but were not fired at the live devices; only their read-back and
  refusal paths are in place. Bluetooth device connection and the app-volume list are not built.

## Visual refinement pass — 2026-10-25

- Increased the panel's target height from 660 to 700 px (still clamped to the available screen height) to give the existing footer and lower content breathing room.
- Made the view labels stable: `OVERVIEW` and `AUDIO` keep their names while the selected state uses the existing accent treatment, instead of changing the active tab to the ambiguous label `BACK`.
- Added a low-key right-aligned current-view label (`LIVE CONTROLS`, `SYSTEM OVERVIEW`, or `AUDIO ROUTING`) so the header row communicates context.
- Separated the six live readings with a restrained `RESOURCE TELEMETRY / LOCAL METRICS` section label and a little extra vertical gap. This preserves the compact instrument style rather than adding large cards.
- **Not yet verified:** Pleamar compilation, exact text fit, the panel's lower edge at different display heights, pointer states and screenshots on the actual desktop. Do not treat this pass as runtime-tested until those checks run.

## Next step

1. Finish Phase 2: Bluetooth device list with connect/disconnect, app volumes, battery/power
   details, workspace and quick actions.
2. A visual pass with a real pointer over the header, tiles, Overview, audio view and identity
   editor.
3. Add paging or denser rows to the Overview before adding more hardware detail.
