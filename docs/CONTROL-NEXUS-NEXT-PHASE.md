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
5. **Customisation:** enable/disable and rearrange Nexus modules, saved layouts, palette integration and reduced-motion/performance settings.

## Parser foundation

shell/lib/telemetry.luau contains pure parsers for uptime, /etc/os-release, CPU model and root-disk output. They accept supplied text and do not execute commands or read host files themselves. This keeps parsing testable and makes unsupported or malformed data return nil rather than fabricated values.

## Staged implementation

- **A — Parser foundation:** deterministic parsers and fixture tests; no new host permissions or UI assumptions.
- **B — Narrow Linux collector (implemented on this branch):** the Nexus logic now uses an explicit allowlist of `cat`, `df`, `uname`, `hostname` and optional `sensors` calls. It samples CPU and network counters on a two-second loop, separates static identity from live metrics, and renders missing temperature data as N/A. Verify command availability and sandbox permissions in a real Pleamar session before merging.
- **C — First telemetry surface (implemented on this branch):** the Nexus scene adds six compact live instruments for CPU, RAM, temperature, root storage and network receive/transmit rates. The first System Overview view is implemented on the follow-on branch: it displays distribution name/ID/version, kernel, uptime, CPU model, memory, root storage and network rates. GPU, display enumeration, a copyable diagnostics action, and identity personalisation remain outstanding.
- **D — Identity personalisation (first asset slice implemented):** schema-validated name/avatar/banner settings; themed header renders imported avatar and banner images via Pleamar's `image … = from text, width, height`; `mooi identity` imports supported local images into mooi-owned data storage and persists generated relative paths. The in-shell text editor and visual file picker are still outstanding. The display name can currently be set via the CLI. The first About view currently uses the host/session strings as its identity. Image paths must remain inside mooi-owned storage.
- **E — Hardware expansion:** GPU/fan/device data behind capability checks, richer audio routing and display details, plus a copyable diagnostics summary.

## System Identity CLI

- `mooi identity show` — inspect the configured name and asset paths.
- `mooi identity name "Studio Rig"` — set the display name (48 characters max).
- `mooi identity avatar ~/Pictures/avatar.png` — import a PNG/JPEG/WebP/AVIF avatar into `$(XDG_DATA_HOME:-~/.local/share)/pleamar/mooi/identity/`.
- `mooi identity banner ~/Pictures/banner.webp` — import a wide banner into the same local folder.
- `mooi identity reset` — restore the default name and clear imported identity images.

The CLI refuses to rewrite malformed JSON and uses temporary files before replacing settings/assets. The file picker and editor remain a separate UI task.
- **F — verification:** run bin/mooi check, tests/nexus.sh, and a real-session smoke test for absent sensors, no battery, no media, missing tools and external display setups.

## Data-source policy

Prefer kernel interfaces and small established commands with stable output. Treat each sensor/device as optional. Never shell-interpolate untrusted display strings into commands. Do not repeatedly spawn heavy commands at frame rate; use a modest polling interval or event notifications, and compute throughput from counter deltas. Static information should be collected once and refreshed deliberately; live readings should be sampled separately. No network requests are needed for local system statistics.

## Six design directions

The Nexus must carry all six mooi directions without turning into a theme demo: **Spatial & Futuristic**, **Industrial & Technical**, **Organic & Fluid**, **Minimal & Elegant**, **Cyberpunk & Expressive**, and **Playful & Interactive**. These are design ingredients for one coherent interface, not six unrelated skins. The existing Ferrolume palette/tokens remain the default visual language; layouts and module density may be customised.


## In-Nexus System Identity editor

The identity header opens an editor from the avatar area. The editor provides a native Pleamar text field for the display name, save/cancel actions, and avatar/banner image-picking actions. Name changes are persisted to `settings.json`; image selection calls `zenity` and delegates import to `mooi identity avatar|banner`. The picker requires `zenity`; image imports are disabled in `MOOI_SAFE=1` mode. If the picker is unavailable, Nexus displays a notice rather than silently changing settings.

Verification still required on the target Arch/Pleamar session: confirm the text field event name and focus behavior, verify `files.write` success semantics, inspect editor placement at the actual Nexus dimensions, and exercise save/cancel, unavailable-picker, unsupported-image, and safe-mode paths.


## Copyable diagnostics slice

Control Nexus now includes a compact **COPY DIAGNOSTICS** action. It invokes `mooi diagnostics copy`, which collects a short local-only report containing distribution, kernel, hostname, desktop/session, uptime, CPU model, memory, root filesystem use, and available PCI graphics controllers. The report is copied with `wl-copy` or `xclip`; `mooi diagnostics show` prints the same report to the terminal. No network request is made. GPU discovery is optional and reports unavailable if `lspci` is missing or no PCI display device is found.

The report deliberately excludes usernames, IP addresses, MAC addresses, serial numbers, process lists, and environment dumps. Verify the generated report and clipboard behavior locally before sharing diagnostics publicly.
