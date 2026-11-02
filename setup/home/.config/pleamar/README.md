# pleamar in ArchEclipse

[pleamar](https://github.com/k4ditano/pleamar) is a shell runtime where every
property is a spring and the animation runs on its own render thread, so it
never waits on logic. It works alongside Quickshell here in two ways.

## 1. Tide: the shell frame, drawn by pleamar

`shells/tide/` is the Frame shell style, rewritten as a pleamar scene.
Settings › Bar › Frame › **Frame Engine** picks who draws it:

| Engine | Who draws the frame |
| --- | --- |
| Quickshell | `widgets/frame/FrameField.qml`: a full-screen shader in the bar's surface, plus a JavaScript spring that ticks every frame |
| Tide (pleamar) | `shells/tide/tide.plm`, on its own layer under the bar. The body morph springs, the music swell (its own cava), the notification glint and the colour fades all run in pleamar's renderer |

With Tide, Quickshell (`services/PleamarFrame.qml`) only reports where each
body should be. It writes `fact` lines down one open socket
(`$XDG_RUNTIME_DIR/pleamar/tide.sock`), at 30 Hz while things move and 4 Hz
once nothing has. Measured idle on this machine: Quickshell went from 4.9% to
0.3% CPU, and Tide sits at ~0% because pleamar does not paint while nothing
moves.

Tide also adds **Frame Glass › Frost**: the compositor blurs behind the
frame's silhouette (as strong as Hyprland's own blur size) and its edge catches
the light. There is no refracting lens. pleamar's lens bends a capture of the
screen, and that capture includes Quickshell's own text drawn above this
layer, so the lens showed a ghost of the bar. A saved "liquid" counts as
frost.

Performance (Renoir iGPU, measured with `pleamar --say tide probe` and then
`probe report`): 60 fps against 60 Hz, 0 late frames while panels open and
close, ~0.4 ms CPU per frame. A `body` is one quad over its whole bounding
box, which is the full screen here, so every shape in it is evaluated for
every pixel. Keep it to plain boxes. The four `path` fillets it used to have
dropped it to 30 fps; the inner corners now come from the smooth union
(`blend` on the side boxes). While music plays, **tide crests** ride the inner edge of the
band with the beat.

- Edit `gen-tide.py`, never the generated scenes. pleamar cannot `repeat`
  inside a `body`, so the 16 body slots are generated — as six scenes,
  `scenes/<swell|crests|pulse>[-solid]/tide.plm` (each beside a link to
  `tide.luau`): a body evaluates every shape it holds for every pixel of its
  box (here the whole screen), hidden or not, so each scene carries only its
  music style's shapes, and only the `-solid` ones (Retro/Terminal) the
  shadow. They must all be named `tide.plm`: pleamar names the socket
  (`tide.sock`) and pairs the logic by the file's name. PleamarFrame picks
  one by look and music style (music off → pulse) once settings load. Run
  `python3 gen-tide.py && for f in scenes/*/tide.plm; do pleamar --check $f; done`.
- Hyprland draws it under the bar with
  `hl.layer_rule({ match = { namespace = "pleamar" }, order = 10 })` in
  `hypr/config/layerrule.lua`. A higher order draws below.
- If pleamar is missing or the scene breaks, Quickshell keeps drawing
  FrameField, so the frame never disappears.
- It is one scene, so it draws the primary monitor's bodies. Multi-monitor
  would need one Tide per output.

**Music styles** (Settings › Frame › Music Swell › Style, Tide only):
*Swell* uses the Quickshell frame's maths: the band's inner edge moves in by
60% of the reach on average, with lobes rolling ±40% on top. It rises over a
wide shoulder under the bar, the bodies bulge, and their melt into the band
deepens with the level. Tide's cava reads cooler than Quickshell's shared
feed did, so the swell height gets ×1.6 to match. *Crests* sends drops riding along
the band. *Pulse* leaves the shape still and makes the border beat (wider and
brighter on the bass, lit on the treble). The size follows Swell Strength:
at 50% the reach is 9 px, so raise it for a bolder swell.

**Living Frame** (Settings › Frame, Tide only): a bead runs the top band
the way you switch workspaces, volume and brightness beads ride the right
and left edges to their new level, a comet circles the frame on a
notification, a sweep runs the bottom on a new track, and bodies go gooey
while they move (the blend grows with spring velocity, `vel()`). Each one is
a spring that runs once from pleamar's own services (`workspaces`, `audio`,
`brightness`, `media`), so idle costs nothing.

**Moods** (always on with Tide; each eases in and out once, none loops):

| What | On the frame |
| --- | --- |
| Screen recording | the border turns red, with a red dot on the left edge under the bar |
| Mic / camera / screen shared | amber / green / blue dots down the right edge (`LiveActivity`) |
| A countdown (`!timer`) | an accent rail fills along the bottom edge; a comet and a glint when it ends |
| A screenshot (`screenshot.sh`) | a white shutter flash (`pleamar --say tide "emit shutter"`) |
| Charger plugged in | two beads rise up the sides |
| Battery under 15 % | the border warms to amber |

Quickshell sends the first four as facts (`PleamarFrame.globals`); Tide reads
the battery itself.

**Retro** (ArchEclipse Settings › Interface › Look, from Vitreus): Quickshell
sends `retro` plus the ink (`dr dg db`); Tide eases `rk` in and gives the
silhouette a lit lip (rim) and a hard ink shadow (4.5, 5.5, no blur). The
opaque putty fill, ink border and squarer corners arrive as the usual facts.
**Terminal** (same place): Quickshell sends `term` and the phosphor as
`dr dg db`; Tide eases `tk` in and the shadow slot becomes a centred glow
(16 px, a little more on the beat) with a faint rim. Fill (black, 96%) and
the phosphor border arrive as the usual facts.

Docked windows and frame-docked widgets are ordinary bodies (`win:<addr>`,
`dock:<id>`) in the 16 slots.

## Desk: honeycomb wallpapers, glass clock, webcam

`shells/desk/` is one scene with three surfaces, each there only while in use.
`bin/pleamar-keep` keeps it alive from Hyprland's autostart. It is controlled
from Settings › Desktop › Desk.

- **Honeycomb transition**: with Transition › Honeycomb
  (`~/.config/pleamar/wallpaper-transition`), qs-wallpaperpicker hands the
  new wallpaper to Desk (`text target` + `emit go`) instead of swapping it.
  Desk opens it through hexagons from the pointer, then calls
  `qs ipc call wallpaper commit <path>`, which swaps instantly underneath and
  runs matugen. If Desk is not running, the picker swaps as usual. If Desk
  never commits (it crashed mid-way), the picker swaps it itself after 6 s.
  A pick made while a transition runs is queued, not dropped. The surface
  is on the *bottom* level: the `order` rule for Tide matches every pleamar
  surface and would put a background-level one under the wallpaper.
- **Glass clock**: Vitreus's single-stroke digits (`clockface.plm`) as one
  frosted body. It is tinted from matugen's colours, and matugen's hook sends
  `emit recolor`. Six layouts, nine positions, size, smoky or accent tint,
  24 h or 12 h.
- **Webcam bubble**: ffmpeg writes frames atomically and the scene reloads them
  at 15 fps. Drag to move, scroll to size, right-click to close. The camera
  is only open while the bubble shows.
- Settings live in `~/.local/share/pleamar/desk/desk.json` (with `cam_on`,
  which is never restored on start). The glass clock and webcam are also in
  the desktop widgets' editor › Add menu (group "pleamar"), and in
  ArchEclipse Settings › Desktop › Desktop Widgets. `clockface.plm`
  and `hexreveal.wgsl` are from [Vitreus](https://github.com/natepayn3/Vitreus)
  (MIT, `LICENSE.vitreus`).

## Polkit: the password dialog

`shells/polkit/` is the session's polkit agent: a dimmed backdrop, a frosted
card in the theme's colours, and a shake on a wrong password. It is built on
pleamar's `polkit` service, so polkit's own helper checks the password and the
scene only carries it: nothing is kept or logged. `bin/polkit-agent` stops
hyprpolkitagent and starts this one, and if it has not become the agent
within 5 s it brings hyprpolkitagent back. `polkit-agent classic` switches
back for the session. It costs nothing while hidden (no perpetual `wave`).

## 2. Marea: a whole shell, as a Shell Style

[Marea](https://github.com/k4ditano/marea-plm) replaces the whole Quickshell
bar: notifications, control centre, finder, lock screen and screenshots, all
in one pleamar scene. It cannot run beside Quickshell because both want to be
the notification daemon and the tray host. So it is an engine switch:

| How | |
| --- | --- |
| Settings › Bar › Shell Style › *Marea (pleamar)* | switch to Marea |
| `SUPER + CTRL + SHIFT + B` | toggle ArchEclipse ⇄ Marea |
| "Switch Shell" in any app launcher (Marea's finder too) | toggle |
| `~/.config/hypr/scripts/shell-engine.sh [get \| set marea \| set quickshell \| toggle]` | from a terminal |

The choice is stored in `~/.config/pleamar/shell-engine`. `bar.sh` (autostart,
`SUPER+SHIFT+B`) starts whichever shell is chosen. The lock, launcher and
screen-record keys go through `hypr/scripts/shell-ipc.sh`, which sends them to
whichever shell is running. In Marea mode, click her for the control centre
and right-click for her menu.

**ArchEclipse Settings while Marea runs:** `SUPER + L` (or "ArchEclipse
Settings" in her finder) opens the Settings panel as a floating window. It is
Quickshell in a settings-only mode (`ARCHECLIPSE_SETTINGS_ONLY=1`, see
`shell.qml`): no bar, no notification daemon, no lock screen and no Tide, so
nothing clashes with Marea. Press it again, or close the window, to quit.

## Where things live

| Path | What |
| --- | --- |
| `~/.local/bin/pleamar` | the runtime, built from `~/Downloads/pleamar-main` (`cargo build --release`) |
| `~/.local/share/pleamar/src/marea-plm` | Marea (git clone); `~/.local/bin/marea` links to it |
| `~/.local/share/pleamar/marea/settings.json` | Marea's own settings (her wallpaper points at `~/.cache/current_wallpaper`) |
| `~/.config/pleamar/shells/tide` | Tide: scene, generator, logic, cava config |

To update Marea: `git -C ~/.local/share/pleamar/src/marea-plm pull`. To
update pleamar, pull the newer source, rebuild, and copy the binary to
`~/.local/bin`.
