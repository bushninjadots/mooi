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
- **B — Narrow Linux collector:** collect a fixed allowlist of system facts through an explicit Pleamar-supported mechanism. Sample CPU/network deltas over time; keep static identity facts separate from live metrics; validate values and bound command time.
- **C — Nexus telemetry surface:** add CPU/RAM/storage/network readings and an expanded System/About view using existing Ferrolume tokens, compact technical labels and no wall of oversized cards.
- **D — Identity personalisation:** editable display name, avatar and banner, safe image selection/copying, reset controls and persisted settings. Image paths must remain inside mooi-owned storage.
- **E — Hardware expansion:** temperature/GPU/fan/device data behind capability checks, then richer audio routing and display details.
- **F — verification:** run bin/mooi check, tests/nexus.sh, and a real-session smoke test for absent sensors, no battery, no media, missing tools and external display setups.

## Data-source policy

Prefer kernel interfaces and small established commands with stable output. Treat each sensor/device as optional. Never shell-interpolate untrusted display strings into commands. Do not repeatedly spawn heavy commands at frame rate; use a modest polling interval or event notifications, and compute throughput from counter deltas. Static information should be collected once and refreshed deliberately; live readings should be sampled separately. No network requests are needed for local system statistics.

## Six design directions

The Nexus must carry all six mooi directions without turning into a theme demo: **Spatial & Futuristic**, **Industrial & Technical**, **Organic & Fluid**, **Minimal & Elegant**, **Cyberpunk & Expressive**, and **Playful & Interactive**. These are design ingredients for one coherent interface, not six unrelated skins. The existing Ferrolume palette/tokens remain the default visual language; layouts and module density may be customised.
