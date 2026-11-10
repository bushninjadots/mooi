# Porting k4 and Minflair into mooi (2026-11-10)

The owner asked for two Quickshell desktops to be adapted and ported into mooi, "features and all", in
Pleamar: **k4** (github.com/k4ditano/k4, MIT, a Dynamic Island whose every part is a plugin) and
**Minflair** (github.com/t4lentles5/minflair, GPL-3.0, a themed Hyprland desktop with Convex, Island and
Gaming bar styles). Both were read at their heads of 2026-11-10 (k4 `5b1406c`, Minflair `05fdc71`).

**Port, not copy.** Both are QML. mooi is Pleamar scenes and Luau logic, so nothing is transplanted: each
feature is rebuilt the mooi way, in the node's one-body language (docs/superpowers/specs/2026-11-10-pill-panel-redesign.md),
from the palette, with the house rules (argv-only commands, narrow permissions, nothing written that mooi
does not own). No code, text or asset of either project is copied, so neither licence binds mooi.

## The map

Each feature of the two projects, and what mooi does with it. **Have** means mooi already does it.

| Feature | From | mooi |
| --- | --- | --- |
| Dynamic island that grows with events | k4 | Have: the node (D226–D264) |
| Control centre: Wi-Fi, Bluetooth, sound, player | both | Have: the panel's home; Wi-Fi and Bluetooth pages (D263) |
| Launcher with calculator, web search, commands | both | Have: the search line (D234–D238, D256) |
| Notifications with actions, history, grouping | both | Have |
| Clipboard history, tray, calendar, weather, power menu, lock | both | Have |
| Pomodoro | Minflair | Have: Super+T focus rounds (D231) |
| Live Hyprland look: gaps, borders, blur, animations | k4 | Have: Settings → Windows (lib/desktop) |
| Video wallpapers, palette from the picture, transitions | k4 | Have (D145); Tide exists |
| GitHub, quotes, system monitor | Minflair | Have |
| **On-screen display**: brightness, microphone, mute, Caps/Num Lock, power plugged | Minflair | **Wave 1**: the node's gauge grows to every reading |
| **Shortcut sheet**, searchable (Super+K) | both | **Wave 1**: a panel page, read from Hyprland itself |
| **SSH hosts** from `~/.ssh/config` | k4 | **Wave 1**: rows in the search line |
| **Packages**: search, install, update (pacman and the AUR) | both | **Wave 1**: `pkg` in the search line, run in a terminal you see |
| **Game mode**: no animations, blur, shadows, gaps; VRR; performance profile | Minflair | **Wave 1**: `mooi game-mode`, put back exactly |
| **Text from the screen** (OCR) | Minflair | **Wave 1**: `mooi capture text`, copied |
| **GPU and disk** cards | Minflair | **Wave 1**: on the System page |
| Dual mode: the bar becomes a dock | k4 | Wave 2: a dock is a new program and a new design |
| Per-device sound output | k4 | Wave 2: the player's mixer gains the outputs (`audio.outputs`) |
| Update available ("N commits behind") | k4 | Wave 2 |
| Theme appliers for btop, lazygit, starship, nvim, Obsidian | Minflair | Wave 2: opt-in per app, as GTK/Qt already are |
| Battery charge limit (80 %) | Minflair | Wave 2: needs a root helper; the owner decides |
| Monitors page, display scale | both | Wave 2 |
| Ask about the screen / region / selection | k4 | Wave 2: through mooi's Claude, not Codex |
| Island terminal sessions | k4 | Wave 2 |
| Plugins, their store and agent skill | k4 | Not planned: mooi is one program per surface, not a plugin host; a decision for the owner |
| Video editor | k4 | Not planned: an application, not a shell feature |
| Games, Digivice, Medabots | k4 | Not planned: k4's own content and art; mooi has its games and BMO |
| SDDM theme, zsh, starship, nvim, kitty configs | Minflair | Not planned: mooi has greetd (D190); the rest are personal dotfiles |
| Rust installer CLI, component manifest, doctor | Minflair | Not planned: mooi has setup/install.sh and `mooi diagnostics` |

## Wave 1, in detail

**The gauge (OSD).** The node's volume gauge (kind 3) becomes the gauge for any reading: an icon, a label
and a fill. It grows for the volume and mute (the `audio` service), the microphone's mute
(`audio.input_muted`), the brightness (`brightness.level`), the power cable (the `battery` service's
`charging` turning), game mode, and Caps Lock and Num Lock. The locks have no service: Hyprland's binds on
`Caps_Lock` and `Num_Lock` (non-consuming, so the key still works) run `mooi osd caps|num`, which reads
the LED under `/sys/class/leds` and tells the node. Settings → The Pill → Volume becomes **Gauges**, the
same setting (`node.volume`).

**The shortcut sheet.** A panel page, `keys`, opened by Super+K (`keys.node_keys`), by `mooi node keys`
and from the search line. It asks `hyprctl binds -j` when it opens, so it shows what is bound now,
including mooi's own keys, never a file that may be stale. Each row is the keys, written as people say
them (`Super + Shift + S`), and what it does: the bind's description when it has one, mooi's own name for
mooi's commands, else the dispatcher and its argument made readable. A filter line takes the keyboard;
↑ ↓ and the wheel scroll.

**SSH.** The search line reads `~/.ssh/config`'s `Host` names (not patterns with `*` or `?`) when it opens.
A host that matches is a row tagged `SSH`; Return opens the owner's terminal on `ssh HOST`. Nothing is
connected without a press.

**Packages.** A query that starts with `pkg ` searches the repositories (`pacman -Ss`) and, when paru or
yay is installed, the AUR, after the typing rests. A row is tagged `REPO` or `AUR`; Return opens the
terminal on `sudo pacman -S NAME` or `paru -S NAME`, so the password and the confirmation are the owner's,
in a terminal they see. The commands gain **Update the system**, which does the same with `-Syu`.

**Game mode.** `mooi game-mode [on|off]` (no argument: the other one). On: it reads what it will change
with `hyprctl getoption` — animations, blur, shadows, rounding, gaps, border size, VRR — keeps it in
`game-mode.json` in mooi's data folder, then turns animations, blur and shadows off, rounding and gaps to 0,
VRR on, and the power profile to performance when `powerprofilesctl` is there. Off puts back exactly what
was kept and deletes the file. A command in the search line and a gauge reading say which.

**Text from the screen.** `mooi capture text`: choose a region (slurp), grim photographs it, tesseract
reads it, and the words go to the clipboard (wl-copy) with a notice. Without tesseract it says so. A
command in the search line.

**GPU and disk.** The System page gains `GPU` (busy %, from `/sys/class/drm/card*/device/gpu_busy_percent`
or `nvidia-smi`, read every two seconds only while the page shows) and `DISK` (the home folder's file
system, `df`), as cards like the others.

## Testing

Each piece is pure where it can be (`lib/node/keysheet`, `lib/node/ssh`, `lib/node/pkgs`, `lib/gamemode`)
and unit-tested; the scene compiles; `bin/mooi check` is green before each commit. Live: the gauge and the
sheet are driven with `pleamar --say` emits, never by moving the owner's pointer.
