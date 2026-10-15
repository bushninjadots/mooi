# Phase 0 audit

Date: 2026-10-14 (on Pleamar 0.3.7; since upgraded to 0.4.6, see DECISIONS.md D4). Everything marked **verified** was run or read on this machine.
**Assumed** marks things not yet checked.

## 1. Machine

| | Verified |
| --- | --- |
| OS | EndeavourOS, Linux 7.2.9-arch1-1 |
| Compositor | Hyprland 0.56.2 (tag v0.56.2), **Lua configuration** (`~/.config/hypr/config/*.lua`) |
| GPU | AMD Barcelo / Renoir iGPU, RADV over Vulkan (as Pleamar reports it) |
| Displays | Only `eDP-1` 1920×1080@60, scale 1, was connected during the audit. The LG over HDMI was **not** plugged in, so multi-monitor is untested |
| Toolchain | cargo/rustc 1.98.1, gcc 16.2, clang 23, cmake, meson, ninja, python 3.14, node 22, bun, lua 5.4, luajit. **No** `luau` CLI |
| Theming | matugen 4.2.0 (`~/.config/matugen/config.toml`), wallust 3.5.2 also installed |
| Pleamar | `~/.local/bin/pleamar` **0.3.7 · language 0.4**, built locally from `~/Downloads/pleamar-main` (not a git checkout; locally patched, see §3) |

## 2. What already runs (must not be disturbed)

- **ArchEclipse** Quickshell shell (`qs -n -p ~/.config/quickshell/archeclipse`): a full-screen frame on the `top` layer with a 32 px top band. It **owns `org.freedesktop.Notifications`** (verified with `busctl`).
- `desktop-widgets` and `qs-wallpaperpicker`, both Quickshell instances.
- Pleamar scenes started by Hyprland: **Desk** and **Polkit** (`~/.config/pleamar/bin/pleamar-keep`). **Tide**, the ArchEclipse frame, is an optional Pleamar scene with socket `tide.sock`. **Marea** is an alternative whole shell (engine switch).
- `layerrule.lua` has `hl.layer_rule({ match = { namespace = "pleamar" }, order = 10 })`. Every Pleamar surface uses the namespace `pleamar` (hard-coded: `src/platform/wayland.rs:640`), so **mooi's surfaces get this rule too**. `order` only sorts within a level, and mooi's island is on `overlay`, so it is unaffected. Watch this if a mooi surface ever shares the `top` level with Tide.
- **Super+Space is taken** (`bind.lua:43`, toggle floating). Super+Ctrl+Space is pin. The brief's proposed shortcut conflicts.

## 3. Pleamar: what it is, verified

Sources: `pleamar --docs reference|guide|recipes|logic|measuring` (the docs of the exact installed version), the local source tree, and upstream `github.com/k4ditano/pleamar` (BSD-3-Clause).

- **It is a shell toolkit that runs on the compositor you already have**, like Quickshell. pleamar-wm is a separate, optional compositor and is **not needed**. Verified by running mooi on Hyprland.
- **Surfaces**: wlr-layer-shell panels with `anchor`, `margin`, `level` (background/bottom/top/overlay), `reserve` (exclusive zone, optionally `while expr`), `keyboard: none|on_demand|exclusive [while expr]`, `screens: all|each|"NAME"`, `open: expr`. Several named surfaces in one process share facts and rules. Also `kind: window` and `kind: lock` (ext-session-lock).
- **Rendering**: wgpu (Vulkan here). Shapes are SDFs. `body` melts shapes into one silhouette with shadow, border, rim and glass. Groups take blur, glow, masks and blend modes. It paints only while something moves; `time` keeps it awake.
- **Animation**: every `prop` is a spring, evaluated on the render thread, which never waits for the logic. Springs retarget from their current value and velocity, which is what makes interruption work. `~Nms` declares a critically damped spring that reaches 99 % in N ms. `layer` claims choose transitions by state. `--reduced-motion` settles springs at once and stops ambient motion.
- **Logic**: Luau in a sandbox (no `io`/`os`), 64 MB cap, handlers cut off after 2 s. It talks to the scene through facts, texts, models and events only. System access is declared in `permissions { run: …; services: … }`.
- **Services verified on this machine**: `workspaces` (Hyprland socket events), `workspaces.focus`, `window` (focused window's class/title/monitor), `apps` (.desktop files), `clock`, `files` (a per-scene folder: `~/.local/share/pleamar/mooi/`), `env`.
- **Services documented but not used yet**: audio, battery, brightness, network, bluetooth, media (MPRIS), tray, notifications, notification_history, `thumbnails` (ext-image-copy-capture, which Hyprland supports per the docs; this is the basis for Atlas previews), polkit.
- **External control**: `pleamar --say <scene> "emit x" | "get fact" | "key Escape" | quit`, over `$XDG_RUNTIME_DIR/pleamar/<scene>.sock`. The socket name is the **file name**, so mooi is `mooi.plm` and does not collide with `tide.sock`.
- **Measurement**: `--record props` (per-frame values), `--report` (frame timing report), `PLEAMAR_TIMING=1`, `--check` (compile only), `--mouse` (scripted input), `--seconds N`.
- **Config format**: JSON is the only format the runtime reads and writes (limitation F1). Writes are atomic.

### Pleamar limits that shape the design (from `docs/08-limitations.md`, upstream)

| | Effect on mooi |
| --- | --- |
| S1 · surface size is fixed and declared | Islands declare their largest size, and the input region lets clicks through the empty part. Size changes need a reload |
| S2 · `screens: each` is capped at 4 copies, and a copy cannot be pinned to a named monitor | Multi-monitor Spine is possible but needs care (Phase 4) |
| G22 · two scenes share no state | The whole shell is **one scene** with several named surfaces |
| P14 · every frame damages the whole surface | Keep surfaces small. The Spine is 48 px wide and the island 360×260, not full-screen catchers |
| S9 · no recovery from a GPU reset | Needs a supervisor that restarts it (Desk uses `pleamar-keep`) |
| S4 · the input region is zone boxes, not shapes | Acceptable |
| `window` on Hyprland gives only the focused window, no list | Window lists and actions go through mooi's own Hyprland adapter (`hyprctl -j clients`) |
| Pleamar's Hyprland commands: only `workspaces.focus` | Window actions are mooi's adapter (`shell/lib/hypr.luau`) |

### Version

Upstream released **0.4.6** on the audit day. The installed binary is **0.3.7**, and Desk and Polkit depend on it. mooi is built and tested on 0.3.7. Upgrading is a decision for you (see STATUS.md).

### Pleamar runs its logic with `--stall 600` by default

Every logic decision is followed by a 600 ms block, as a demonstration of decoupling (`pleamar --help`). Desk runs that way. mooi passes `--stall 0`.

## 4. Hyprland integration, verified by experiment

| Finding | How |
| --- | --- |
| `hyprctl dispatch` takes **Lua**: `hl.dsp.focus({ window = "address:0x…" })`. The legacy `focuswindow address:…` errors | ran both |
| Window dispatchers accept `window = "address:0x…"`: float, pin, fullscreen, move (`workspace`, `follow`), close | `tests/integration.sh`, each checked with `hyprctl -j clients` |
| **An unknown address still answers `ok`** | dispatched to `0xdeadbeef` |
| **Acting on a window on another workspace moves focus there** | float toggle on a workspace-2 window switched the active workspace; focus was restored afterwards |
| A Pleamar layer holding the keyboard does not change `activewindow` | the island captured the right target with its keyboard held |
| **A layer holding the keyboard keeps Hyprland from giving it to a window** | with the membrane open, `hl.dsp.focus({ window = … })` for another window changes nothing (`focusHistoryID` stays); the same dispatch right after the island lets the slot go works |
| **A `keyboard:` clause is read once for the scene, from the first surface** | compiler (`pending_keyboard`, `scene.surface().keyboard`) and measured: with the islands each declaring `keyboard: exclusive while open == <name>`, no key reached the open island at all (typing went to the window below, Escape did nothing); one clause on the Spine (`open != none`) fixed both |
| `thumbnails` works on Hyprland: `capturing` is true, and each report carries `id`, `title`, `app`, `picture` (a path with a version) and `stale` | the Atlas wall drew real previews; `picture` is `…/pleamar/thumbnails/<pid>/<n>.png?<version>` |
| **A thumbnail's `id` is the compositor's own** (`18000015`), not a Hyprland address | compared the service's ids with `hyprctl -j clients` addresses |
| `move … follow = false` keeps the user's workspace | integration test |
| `fullscreen` in `hyprctl` JSON is a mode: 0 none, 1 maximized, 2 fullscreen | observed `2` on a fullscreen kitty |

Consequences: success is **never** taken from the dispatch reply. mooi reads the window back and compares. Actions target the window by address, captured when the island opens.

## 5. Suitability verdict

**Pleamar is suitable for the Spine and Islands, and the vertical slice proves it** (see TESTING.md for numbers). It has springs on a render thread that never blocks, interruption by construction, real layer-shell control, a sandboxed and permissioned logic, scriptable state checks, and a near-zero idle cost. Its costs are a young language (0.x, breaking changes allowed), a single-author upstream moving fast (five releases on the audit day), and the limits above.

Evaluated since: `thumbnails` on Hyprland — `capturing` is true here (ext-image-copy-capture), pictures arrive as versioned files and the Atlas draws them (§4). Not yet evaluated: notification ownership hand-off, multi-monitor behaviour with the LG attached, and theme hot-swap through `rgb()` facts (Matugen).

## 6. Measured (slice 1, this machine)

| | Result |
| --- | --- |
| Idle CPU, island hidden | 0.13 % (15 s); 0.10 % on a second run |
| Idle CPU, island open and still | 0.10 % (10 s); about 1 frame per second (clock) |
| 30 toggles in 4 s | 7 % CPU during the burst, 1 % right after |
| Memory | RSS 60 MB, **PSS 35 MB** |
| Frames while animating | mean 16.8 ms, p99 22.4 ms, max 31.4 ms (212 frames) at 60 Hz. Some frames exceed 16.7 ms; not yet attributed |
| First frame | 134 ms after launch |
| Motion contracts (1 % → 99 %) | enter 183 ms / 180 · exit 134–151 ms / 140 · expand 200 ms / 200 · collapse 168 ms / 160 |
| Input-to-visible latency | **not measured** (needs a camera or a presentation-time probe) |

A first reading of 3.8 % with the island open was taken while `grim` captured the screen. Measured again without a capture, it was 0.10 %, and `--record` showed about one frame per second. A capture most likely makes Pleamar repaint. Measure without one.

## 7. Contrast of the provisional tokens

WCAG ratios against the surfaces used. `fg.muted` was raised from `#6E7B80` (3.8:1 on surface.primary) to `#8A979C` (5.5:1). `slate` (2.1:1) is never used for text.

| | bg.primary | surface.primary | surface.elevated |
| --- | --- | --- | --- |
| fg.primary | 15.1 | 13.6 | 12.0 |
| fg.secondary | 8.3 | 7.5 | 6.6 |
| fg.muted | 6.2 | 5.5 | 4.9 |
| signal | 14.4 | 13.0 | 11.5 |
| heat | 8.4 | 7.6 | 6.7 |

## 8. Risks

1. **Notification ownership.** Pleamar's `notifications` service makes the scene *the* notification server and takes it from ArchEclipse. Do not declare it until Phase 6 has a hand-off plan.
2. **Upstream churn.** Language 0.x, five releases in one day. Mitigation: pin the binary mooi is tested against, and run `bin/mooi check` after any upgrade.
3. **Exclusive keyboard.** An island holding the keyboard while the logic is stuck could trap input. Mitigation: Escape, the Spine button and a 30 s idle dismissal are scene rules on the render thread, independent of the logic.
4. **Hyprland focus side effect.** Window actions can move focus. Satellites only act on the window they were opened for, on the current workspace.
5. **Multi-monitor is unverified** (only eDP-1 was connected).
6. **Shared layer namespace** `pleamar` with Tide and Desk (see §2).
