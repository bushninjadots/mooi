# Control Nexus: system overview build phase

This phase extends the existing Control Nexus from quick controls into a dependable system command centre. It is split into **data**, **presentation**, and **personalisation** so missing sensors or optional tools never take down the panel.

## Current baseline (repository audit)

- shell/mooi-nexus.plm subscribes to Pleamar services for workspaces, clock, audio, brightness, battery, network, Bluetooth and media. Its identity header currently displays environment-derived user, host and session strings.
- shell/mooi-nexus.luau owns palette integration, media state, settings persistence and control actions. It does not yet collect CPU, RAM, disk, kernel or distribution details for the Nexus.
- shell/lib/sysinfo.luau already parses CPU utilisation from /proc/stat, memory from /proc/meminfo, network byte counters from /proc/net/dev, and optional temperature data from decoded sensors -j. Those helpers support existing bar telemetry; they are not currently wired into Nexus.
- The current Nexus service declarations do not provide a general CPU/memory/disk/hardware telemetry service.
- Pleamar files.read is sandboxed to a scene's own data directory, so it is not a way to read arbitrary Linux paths. System information needs a narrow, explicit bridge rather than trying to pass /proc paths to that API.

## Requirements

1. **Live telemetry:** CPU load, RAM used/available, root filesystem usage, network receive/send rates, temperatures and GPU information only when supported. Show a clear unavailable state when the host cannot provide a metric.
2. **System identity:** editable display name, profile picture and wide banner, with image assets stored in mooi's own data directory and theme-aware text/accents.
3. **About this system:** distro/version, kernel, session, hostname, uptime, CPU model, memory, storage, graphics and displays where safely discoverable; allow copying a concise diagnostic summary.
4. **Connected hardware:** audio inputs/outputs, Bluetooth devices, network, displays and power state with relevant controls.
5. **Customisation:** enable/disable and rearrange Nexus modules, saved layouts, palette integration and reduced-motion/performance settings. **Started (D72), widened (D73):** every module of the plate — the four control cards, the six live instruments and the player — has a saved on/off state and order within its band, edited from the LAYOUT panel, and three named layouts ship (FULL, FOCUS, MINIMAL) with SAVE AS and DELETE, stored as `nexus.layouts` / `nexus.layout`; palette integration and reduced motion were already in place. The six header views are not yet part of a layout.

## Parser foundation

shell/lib/telemetry.luau contains pure parsers for uptime, /etc/os-release, CPU model and root-disk output. They accept supplied text and do not execute commands or read host files themselves. This keeps parsing testable and makes unsupported or malformed data return nil rather than fabricated values.

## Staged implementation

- **A — Parser foundation:** deterministic parsers and fixture tests; no new host permissions or UI assumptions.
- **B — Narrow Linux collector (implemented on this branch):** the Nexus logic now uses an explicit allowlist of `cat`, `df`, `uname`, `hostname` and optional `sensors` calls. It samples CPU and network counters on a two-second loop, separates static identity from live metrics, and renders missing temperature data as N/A. Verify command availability and sandbox permissions in a real Pleamar session before merging.
- **C — First telemetry surface (implemented and verified):** the Nexus scene adds six compact live instruments for CPU, RAM, temperature, root storage and network receive/transmit rates. The **System Overview** view is now built and toggles from the header: distribution name/version, kernel, uptime, CPU model, memory, root storage, displays and GPU, host, session and workspace/time. GPU busy is read only where the driver exposes `gpu_busy_percent`; the focused Hyprland display is summarised from `hyprctl monitors -j`; **COPY DIAGNOSTICS** runs the local-only `mooi diagnostics copy`.
- **D — Identity personalisation (implemented and verified):** schema-validated name/avatar/banner settings; the themed header renders imported avatar and banner images via Pleamar's `image … = from text, width, height`; `mooi identity` imports supported local images into mooi-owned data storage and persists a fresh relative path per import (`identity/<kind>-<epoch>-<pid>.<ext>`), so replacing a picture is read while the scene is up. The in-shell editor (native input, save/cancel, safe-mode refusal) and the `zenity` image picker are built; the picker steps the surface down and gives the keyboard up while the dialog is above an overlay (D69). Image paths must remain inside mooi-owned storage.
- **E — Hardware expansion (implemented, with gaps):** GPU/fan/device data behind capability checks, richer audio routing and display details, plus a copyable diagnostics summary. The Bluetooth device list is built: up to five rows from the `bluetooth` service (name, connected/paired/new), a press calling `bluetooth.connect` / `bluetooth.disconnect` with the row's address, and `NO DEVICES KNOWN` when the service reports none. The row states reach the scene as 0/1 through `lib/nexus.bt_rows` (pure, unit-tested), and the connect/disconnect write has not yet been fired at a live device. The application mixer is built as a third header view: up to seven streams from `audio.apps`, wheel for `audio.app_volume` in 5 % steps (batched and read back) and a press for `audio.app_mute`, through `lib/nexus.app_rows` (pure, unit-tested). The System Overview now uses 22 px rows and adds CPU load, temperature and network rates. A fifth **SPACES** view lists the compositor's first ten workspaces as blocks (id, window count, current/show); a press calls `workspaces.focus` with the id kept for the block, and `lib/nexus.ws_rows` maps the service's boolean `active` to 0/1, zero-pads the label and keeps the cap (pure, unit-tested). **POWER** carries battery health and the time UPower predicts (`upower -e` / `-i`, through `lib/telemetry.upower`) beside percent and charging state, with `N/A` when the tool, battery or prediction is absent; LOCK and the four session actions are built (LOCK acts at once, the others ask again).

## System Identity CLI

- `mooi identity show` — inspect the configured name and asset paths.
- `mooi identity name "Studio Rig"` — set the display name (48 characters max).
- `mooi identity avatar ~/Pictures/avatar.png` — import a PNG/JPEG/WebP/AVIF avatar into `$(XDG_DATA_HOME:-~/.local/share)/pleamar/mooi/identity/`.
- `mooi identity banner ~/Pictures/banner.webp` — import a wide banner into the same local folder.
- `mooi identity remove avatar|banner` — clear one imported image and forget its path.
- `mooi identity reset` — restore the default name and clear imported identity images.

The CLI refuses to rewrite malformed JSON and uses temporary files before replacing settings/assets. The in-Nexus editor and image picker now call these commands; under `MOOI_SAFE=1` the editor refuses to save.
- **F — verification:** run bin/mooi check, tests/nexus.sh, and a real-session smoke test for absent sensors, no battery, no media, missing tools and external display setups.
- **G — module layout and named layouts (implemented and verified):** the whole plate is a saved catalogue of eleven modules in three bands, so a module moves only among its own kind. The LAYOUT panel turns each one off or on, moves it earlier or later, and RESTORE returns the catalogue; slots compact inside each band, and the player keeps its full-width row. The panel's chips switch between named layouts (FULL, FOCUS, MINIMAL on a fresh file); SAVE AS names the current arrangement and DELETE removes the showing one, with at most six and never none. The settings are `nexus.layouts` (`{ name, modules }` records, a new `layouts` schema kind) and `nexus.layout`; a file carrying only D72's `nexus.modules` is migrated once into a CUSTOM layout that is what shows (`lib/nexus.layout_state`, so the defaults' `FULL` cannot hide it), and a later save clears the old key. `lib/nexus.modules`, `layout_action`, `module_rows`, `layouts`, `layout_named`, `layout_add` and `layout_remove` are pure and unit-tested. `tests/nexus.sh` checks eleven modules and three layouts, hides, moves within a band, restores, and switches MINIMAL/FULL in the temporary environment; live, the panel saved the edited FOCUS order and drew MINIMAL as two cards and the player.
- **H — the banner band (implemented and verified):** the identity banner is cover-cropped once into a band copy at the plate's aspect (`identity/<name>-228-band.jpg`, 1456×228 since D74, `magick`, cached beside the import) and drawn from that; the imported file is untouched, and without ImageMagick the original is drawn as before. The 2560×1440 example fills the header instead of shrinking to a 149 px thumbnail. `tests/nexus.sh` imports a banner through the CLI and checks the plate draws a `-228-band.jpg`.
- **I — the banner summary and palette (implemented and verified):** the 114 px identity band carries a fastfetch-like summary on two monospaced lines — OS, kernel, uptime, CPU (its model without the graphics suffix), memory and root — composed and column-padded in the logic (`nx_spec_1`/`nx_spec_2`), plus a **PALETTE** strip of fourteen shell roles drawn as small chamfered swatches from the same tokens every card paints. Both are left out on a narrow plate (`cw > 520` / `cw > 460`). The band copy's name carries its height, so an old crop is never stretched. The layout panel, which shares the plate, now closes an open view and shows itself 60 ms later; drawing both in one frame lost the panel's text (a Pleamar culling quirk).
- **Firing the writes (D72):** with a real `mpv` stream, mixer mute and wheel volume are now verified against `pactl` (63 % → 58 %, `Mute: yes`); this uncovered that `lib/nexus.app_rows` dropped numeric stream ids, leaving every row without a handle. The Bluetooth radio was powered on and off through the Nexus (it had been rfkill-blocked, so the first attempt was refused and reported); a connect press reached BlueZ but no known device was reachable, so connect/disconnect on a device is still unproven. The POWER text is covered by a fake-UPower discharging fixture (`HEALTH 81%`, `2H 18M LEFT`), and the SPACES label inversion (`CURRENT` on the wrong workspace) was found and fixed while pressing a block.

## Data-source policy

Prefer kernel interfaces and small established commands with stable output. Treat each sensor/device as optional. Never shell-interpolate untrusted display strings into commands. Do not repeatedly spawn heavy commands at frame rate; use a modest polling interval or event notifications, and compute throughput from counter deltas. Static information should be collected once and refreshed deliberately; live readings should be sampled separately. No network requests are needed for local system statistics.

## Six design directions

The Nexus must carry all six mooi directions without turning into a theme demo: **Spatial & Futuristic**, **Industrial & Technical**, **Organic & Fluid**, **Minimal & Elegant**, **Cyberpunk & Expressive**, and **Playful & Interactive**. These are design ingredients for one coherent interface, not six unrelated skins. The existing Ferrolume palette/tokens remain the default visual language; layouts and module density may be customised.


## In-Nexus System Identity editor

The identity header opens an editor from the avatar area. The editor provides a native Pleamar text field for the display name, save/cancel actions, and avatar/banner image-picking actions. Name changes are persisted to `settings.json`; image selection calls `zenity` and delegates import to `mooi identity avatar|banner`. The picker requires `zenity`; image imports are disabled in `MOOI_SAFE=1` mode. If the picker is unavailable, Nexus displays a notice rather than silently changing settings.

The editor's text field event, focus and save path were exercised in an isolated run (a save persisted and the header followed it), and the `mooi identity` import it calls now works after the escaped parameter expansions in `bin/mooi` were repaired. `bin/mooi` also puts its own `bin` on `PATH` so the picker and the diagnostics copy can run `mooi` by name. The whole picker path was then exercised on the live session: the real `zenity` dialog opened above the Nexus, the chosen file imported through `mooi identity`, `AVATAR IMAGE UPDATED` appeared and the new picture was drawn with the editor still open; a `.jpg` avatar replaced by a different `.jpg`, and the banner likewise, changed on the plate without a restart. Still to exercise: a physical pointer press on the editor's rows, cancel and unsupported-image paths from the picker, and editor placement at every plate width.


## Copyable diagnostics slice

Control Nexus now includes a compact **COPY DIAGNOSTICS** action. It invokes `mooi diagnostics copy`, which collects a short local-only report containing distribution, kernel, hostname, desktop/session, uptime, CPU model, memory, root filesystem use, and available PCI graphics controllers. The report is copied with `wl-copy` or `xclip`; `mooi diagnostics show` prints the same report to the terminal. No network request is made. GPU discovery is optional and reports unavailable if `lspci` is missing or no PCI display device is found.

The report deliberately excludes usernames, IP addresses, MAC addresses, serial numbers, process lists, and environment dumps. Verify the generated report and clipboard behavior locally before sharing diagnostics publicly.


## CPU-core and optional GPU telemetry

The live collector counts numbered CPU cores from `/proc/stat` and annotates the aggregate CPU load label with the detected count. Pure parsers expose per-core cumulative counters and parse the optional DRM `gpu_busy_percent` sysfs reading; unavailable, malformed or out-of-range GPU readings stay marked unavailable. Unit tests cover both parser paths. GPU utilisation is driver-dependent; this does not imply that every Intel, AMD or NVIDIA setup exports that interface. VRAM and display topology remain future work.


## Display intelligence

Control Nexus queries `hyprctl monitors -j` through the active Hyprland session. A tested formatter prefers the focused monitor and reports its connector name, pixel resolution, refresh rate and scale when available, plus a compact count of additional displays. Missing command output, malformed JSON or invalid dimensions display as `DISPLAY INFO N/A`. This uses compositor-reported values rather than assuming a particular connector or monitor model. A full per-monitor inventory and per-output controls remain future work.


## Hardware inventory command

Added `mooi hardware`, a local read-only inventory for CPU model, PCI graphics controllers (via optional `lspci`), whole-disk devices and models (via optional `lsblk`), and connected displays reported by Hyprland. Missing tools or unavailable display data produce explanatory fallback text. Pure Lua parsers for GPU controller and whole-disk output have unit coverage. This does not read serial numbers, mount paths, partition contents, or personal files. It is a terminal inventory in this phase; a dedicated in-Nexus hardware detail view remains a later UI task.
