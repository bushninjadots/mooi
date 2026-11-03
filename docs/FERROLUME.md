# The Ferrolume bar

mooi's top bar, built to the **Ferrolume** design system (claude.ai → design systems →
Ferrolume), in a compact 46 px strip. Why: DECISIONS D20 (the bar) and D21 (compact, the
instruments, the colour engine, the switches).

**Bring it up:** the login starts it (`bin/mooi session`); Super+Shift+B restarts it and
Super+Alt+Shift+Space stops it. The binds live in `~/.config/hypr/config/custom/mooi.lua`.
`bin/mooi session` / `bin/mooi stop` do the same from a terminal.

## Working on it

Your shell runs from a snapshot (`~/.local/state/mooi/live`), so editing the repo never reloads
it half-way. `bin/mooi refresh` copies the repo in and restarts the scene, keeping the keeper.
`bin/mooi run --safe` runs the repo directly for development.

## Files

| File | What |
| --- | --- |
| `shell/theme/ferrolume.plm` | Tokens (`fl.*`): the colour roles (read from springs), springs, compact geometry |
| `shell/ui/ferrolume.plm` | Pieces: `Frame`, `Slab`, `DnaBack`/`DnaRung`, `HelixBlock`, `Cell`, `Readout`, `Ring`, `TrayIcon`, `NoteRow`, `ClipRow`, `ModCell`, `MenuRow`, `FlPlate` |
| `shell/icons/*.svg` | The icon set: 24 px grid, 1.6 strokes, square caps, octagons for circles; tinted per state, layers lit separately (Wi-Fi arcs, volume waves) |
| `shell/bar.luau` | The bar's logic: layout, readers (CPU, RAM, temperature, throughput, keyboard, weather, cava), actions, tray, notifications |
| `shell/lib/barlayout.luau` | The module catalogue and the layout arithmetic (unit-tested) |
| `shell/lib/sysinfo.luau` | Parsers for /proc, `sensors -j`, open-meteo (unit-tested) |
| `shell/lib/ferro.luau` | The colour engine (unit-tested) |
| `shell/mooi.plm` | The bar section (*The bar · Ferrolume*) and the side panel |

## Layout

Three lists in `settings.json`, left to right; `+` joins modules into one frame:

```json
"bar": {
  "left":   ["workspaces", "window"],
  "center": ["media"],
  "right":  ["resources", "network+bluetooth", "volume+mic", "brightness+battery",
             "tray", "notifications", "clock", "screenshot+recorder+caffeine", "actions+atlas", "power+core"]
}
```

`"gap"` is a **spacer**, as many as you like and never joined into a group: on the left or the
right it stretches, taking the room between its side and the centre (shared with that side's other
spacers), so what follows it is pushed toward the middle; in the centre it is 24 px. With spacers
any module can sit anywhere along the bar. The **Layout** page of the settings arranges all of it
(below); the lists are what it writes.

Modules: `workspaces window media resources bandwidth keyboard weather tray notifications mic
volume brightness battery network bluetooth clock caffeine recorder screenshot clipboard power
actions atlas core focus`. `focus` and `weather` start on the shelf rather than the bar (edit mode places them); the weather it asks ipinfo.io where you are (from your IP address) and open-meteo for the forecast, so placing it is yours to choose. A module placed twice or misspelled is reported and the default layout is
used. In the bar menu's MODULES grid a press steps a module's frame (AUTO, BEZEL, PLATE,
BRACKET, NONE, OFF) and a right press merges it into the entry before it or splits it out of
its group. Modules the machine lacks (battery, backlight, an empty tray) take no room.

| Module | Shows | Press · right · middle · wheel |
| --- | --- | --- |
| workspaces | the instrument and the tag (W3 ×2) | that workspace · — · — · step |
| window | the focused window's class and title | window actions |
| media | prev/next slabs, visualizer, track | prev/next · play/pause |
| resources | CPU %, RAM %, TMP °C | — |
| bandwidth | down and up per second | — |
| keyboard | the layout's code | — |
| weather | conditions, °C (open-meteo, located by IP; the city on the rail) | — |
| tray | the tray's icons | click · its menu · secondary |
| notifications | the bell and how many wait | the notices panel |
| mic | MIC % or OFF | mute · — · — · level |
| volume | VOL % and a ring | System island · — · mute · level |
| brightness | BRI % and a ring | System island · — · — · level |
| battery | BAT % with charge state, a ring | System island |
| network | NET signal %, ETH, OFF | System island |
| bluetooth | BT ON/OFF or connected devices | System island |
| clock | time and date | — |
| caffeine | keep awake (an idle/sleep inhibitor) | on/off |
| recorder | wf-recorder into ~/Videos | an area · the screen (again: stop) |
| screenshot | grim into ~/Pictures/Screenshots, and the clipboard | an area · the screen |
| clipboard | cliphist's last text entries | the clipboard panel |
| power | wlogout | menu · lock (hyprlock) |
| actions, atlas | mooi's window actions and Atlas | open |
| core | search | open · the bar menu |
| focus | a focus block, then its break: a ring of what is left and the minutes (FOCUS 24:58, BREAK 04:59); a toast when each ends | start or stop · skip to what comes next · — · the block's length, 5–90 min, at rest |

## Switches

**The window** (tools/gen-settings.py) is pages with a heading over each real part of them: Quick (the few choices that change
the most), Colour, Bar, Workspaces, Media, Screen frame, Modules, Windows, Input, Keys, System. A row
that does not apply is not shown, and the rows under it glide up (`gy_*` springs); a search field
looks through every row's name, what it does and its page (lib/settings_index, generated), and a
result opens its page at it.

**Presets first.** `bar.style` (instrument · glass · floating · minimal · steel) writes the bar's
material, outline, weight, outline colour, shadow, backdrop, hover and opacity together;
`theme.preset` (phosphor · neon_noir · concrete · gunmetal · alien · titanium) writes the finish,
colourfulness, base and its shades, glow and aberration (lib/style). The settings window shows
"Custom" when the details differ from every preset; the details live on their own pages (Colour
details, Bar details) so the first pages stay short.

The settings window groups these by what they reach: **Appearance** (colour, base, light and
shape for everything mooi draws — bar, islands, panels — and the window borders), **The bar**
(build, outline, hover, depth and glass), **Windows** (Hyprland: edges, spacing, opacity, shadow,
blur, layout), **Input** (touchpad and mouse scrolling). Every number is a slider (drag, click or
wheel); on the Windows and Input sliders the lowest step is KEEP, Hyprland's own value.

| Setting | Values | |
| --- | --- | --- |
| `bar.mode` | `islands` · `full` · `notch` | a frame per group, one panel across the screen, or pieces hanging from the top edge (the centre a notch, the sides flush with the corners, joined to the edge by inner fillets) |
| `bar.radius` | 0–16 | the corners of islands, panel and notch |
| `bar.outline_width` · `bar.outline_colour` | 1–3 · `subtle` `bright` `accent` | the outline's weight and colour |
| `bar.pill` | `soft` · `outline` · `underline` · `glow` | what lights under the pointer |
| `bar.shadow` | `off` · `soft` · `medium` · `strong` | a shadow under the bar's material |
| `bar.opacity` · `bar.frost` · `bar.smoke` | 20–100 · 0–100 · 0–80 | how solid the material is; glass frosting; glass and blur tint |
| `bar.bg` · `bar.bg_colour` | `black` `wallpaper` `accent` `graphite` `navy` `plum` `forest` `wine` `sand` `custom` · `#rrggbb` | the bar's background; text is re-held to its contrast floors on it (a light one darkens the text) |
| `bar.bg_light` · `bar.bg_sat` · `bar.bg_hue` | −10–40 · 0–150 · −180–180 | the background's lightness shift, saturation (100 = as is) and hue turn |
| `fx.aberration` · `fx.glow` | 0–100 · 0–160 | chromatic aberration (glass dispersion; readings and the clock split red from cyan) · glow strength |
| `theme.finish` · `theme.saturation` | `luminous` · `matte` · `neon` · −50–50 | matte: calmer signals, a quarter of the glow · neon: signals near full saturation and lit, 1.7× glow · the palette's colourfulness |
| `bar.bg` industrial tones | `obsidian` `gunmetal` `concrete` `titanium` `oxide` `alien` | the base everything stands on; a base in the unreadable middle band of luminance is moved to its nearer side |
| `desktop.opacity_active` · `.opacity_inactive` | 49 (keep) · 50–100 % | the windows' opacity |
| `desktop.shadow` · `.shadow_size` | `keep` `off` `soft` `deep` `neon` · 2–40 px | window shadows; neon is a glow in the palette's main colour |
| `bar.surface` | `solid` · `glass` · `blur` · `clear` · `mech` | the frames' or the panel's material (`mech`: machined housings, bolts, bays, vents) |
| `bar.workspaces` | `dna` · `prism` · `cells` | the workspace instrument (full + dna: the panel's edges are the helix) |
| `bar.visualizer` | `mirror` · `bars` · `line` · `dots` · `off` | real audio (cava) while something plays |
| `bar.frame` | `line` · `corners` · `none` | the outline round every group (round the whole panel in full mode) unless its module says otherwise; older names (`bezel`, `bracket`, `plate`, `bar.border`) are migrated |
| `bar.modules.<m>.show` / `.frame` | `true`/`false` · `inherit` … `none` | per module |
| `bar.ground` | `black` · `tinted` · `clear` | the strip behind the islands |
| `bar.rail`, `bar.accents`, `bar.labels`, `bar.wheel` | `bar.wheel`: `step` · `off` · `invert` | the rail; cuts, drops, slashes; numbers; the wheel |
| `bar.foot_visualizer` | `true` · `false` | each island's bottom border as eight bars joined at their feet, stepping out with the music |
| `notifications.server` | `takeover` · `always` · `never` | when mooi receives the session's notifications |
| `bar.helix_frame` | `true` · `false` | the workspace island's own edges as the DNA's strands (islands mode) |
| `media.mode` | `full` · `compact` · `art` · `viz` | what the player shows |
| `media.idle` | `collapse` · `keep` · `hide` | with nothing playing: a pill, as it is, or off the bar |
| `frame.on` · `frame.band` · `frame.music` · `frame.style` · `frame.reach` · `frame.edges` | | the screen frame (below) |
| `theme.*` | source, scheme, color_index, contrast, signal | see Colour |
| `tray.style` | `themed` · `original` | tray icons tinted to the bar's colours, or as the apps draw them |
| `desktop.manage` · `.border` · `.border_colour` · `.gaps_in` · `.gaps_out` · `.rounding` · `.dim_inactive` | | Hyprland's window look, applied live with `hyprctl eval` (only while `manage` is on) |
| `desktop.layout` · `.column` · `.column_fit` | `keep` `dwindle` `master` `scrolling` `monocle` · 9 (keep) · 10–100 % · `keep` `fit` `center` | Hyprland's layout, and the scrolling layout's column width and how a focused column comes into view |
| `desktop.touchpad_natural` · `.touchpad_speed` · `.mouse_natural` · `.mouse_speed` · `.blur` | `keep` first; speeds 4 (keep) · 5–200 % | scrolling direction and speed for touchpad and mouse; window blur. `keep` writes nothing; going back to `keep` makes Hyprland re-read its own config |
| `keys.search` … `keys.stop` | `"SUPER + ALT + Space"` … `"SUPER + ALT + P"` for the wallpaper studio | mooi's keys; written to `hypr.lua`, and Hyprland re-reads its config when they differ from what it last bound (`hypr.loaded`) |

Colours follow the wallpaper: `bin/mooi theme-watch` (started with mooi) re-runs Matugen with
the theme settings whenever `~/.cache/current_wallpaper` changes, and mooi re-lights in 300 ms.

## Settings and edit mode

The MOOI mark on the rail (or a right press on search) opens **mooi · settings**, a window of
its own, laid out as Ryoku's settings are: a rail of pages in groups — LOOK (Quick, Colour), BAR
(Bar, Layout, Workspaces, Media), DESKTOP (Frame, Windows, Input), SYSTEM (Keys, System) — and
search over every row (Ctrl+F or /; Enter opens the first, Escape clears). Each page is a stack of
titled `//CARDS_`; a row that cannot apply is hidden and the rows under it glide up. Every control
applies the moment it is pressed. A setting that is not its default has a **revert arrow** left of
its control; each page has **Reset this page** (press twice: the first arms it for three seconds).

**Layout** is the bar's arrangement: the bar to scale (a press selects a module), what is selected
and what it can do — move ◀ ▶ (across into the next list at an end), join the entry before or after,
split from its group, send to the left, centre or right, remove to the shelf, and its own outline —
then the three lists and the shelf as chips, and **+ Spacer** on each list. **Edit on the bar**
(bottom left, Super+Alt+E) is the same on the bar itself: drag a module to move it (the others make
room as you go), drop it on another's middle to group them, drop it on the shelf below the bar to
hide it, drag one up from the shelf to place it; a press selects one (← → move it, Delete hides it).
Keys: press Change, then the new combination (Esc cancels); a combination two actions share is
flagged.

**Shape** (the Bar page): Layout (islands, full, notch), **Thickness** (24–44 px), **From the edge**
(0–40 px down from the top), **Length** (30–100 % of the screen, centred) and corner rounding. The
windows leave the bar exactly its strip, following it live (seven empty reserve surfaces, D31).

The window is generated: change `tools/gen-settings.py`, run it. So are the helix's pinched
middle and the frame's swell lobes (`tools/gen-frame.py`), which pleamar's bodies cannot repeat.

## The screen frame

Settings (the Screen frame page): on or off; the band's thickness, inner corners (`frame.radius`),
inner edge (`frame.edge`: a line, a neon line that glows, none) and solidity (`frame.opacity`);
music as one choice (`frame.motion`: off, swell, ripples, pulse — it writes `frame.music` and
`frame.style`), its strength and which edges move. While it is on and mooi styles the windows, the
windows' outer gap is at least the band and 4 px, so the windows never cover it.

A band round the screen whose top is the bar's own strip (`frame.*`): thickness, swell with
the music (cava) as a rolling **swell**, **crests** or a **pulse** of the border, its reach,
and which edges move. It wears the bar's colour (translucent with a glass or frosted bar, steel
on a mechanism). It sits in the windows' outer gap and reserves nothing itself.

It is a surface of its own (`frame_surface`, level `bottom`, `reserve: -1`), and while still it
is drawn from plain shapes; the melted `body` takes over only while the swell moves. Measured
(`pleamar --report`, islands opening and closing): the body on the bar's surface left 24–38 %
of frames late, the plain band 5 % (the same as no frame). Glass behind the band, even the
strip alone, costs a third of the frames, so the band is never glass (D24).

## Colour

`lib/ferro.luau` builds the nineteen roles from the palette's hue, then holds each to the
floor the design promises by moving lightness only: phos 7:1 on the ground, ember 6:1,
muted 4.5:1, strokes 3:1, ink 4.5:1 on its fills, engraving 4.5:1 on steel. Hull, traces,
fills and steel take the palette's hue, so the metal belongs to the scheme. The second signal
is the palette's own tertiary or secondary if one stands ≥ 60° round the wheel from the
phosphor, else the complement; a grey palette keeps the whole bar grey and parts the signals
by lightness. A critical battery (< 10 %, not charging) paints the Alert palette. Every
change — wallpaper, scheme, Alert — glides over 300 ms (one spring per colour channel). A
wallpaper palette whose text would be unreadable has its text roles lifted to the floor (a
note says so) instead of being refused.

## The workspace switchers

**Motion, the same in every one** (D31): the highlight is a liquid — its head on a quick spring,
its tail on a slow one — that stretches toward the workspace it is going to and gathers there; each
workspace lights by how much of the highlight covers it; on arrival a ping rings out of the new one.
The sliding instruments (DNA, prism) add a detent: their focus brackets give and flare. The map is
`spine.max_workspaces` at least ("Always shown"), and reaches the workspace you are on and the last
one with windows past that.

Everyday (no tag, their own pitch): **pills** — after ii / iNiR: occupied workspaces sit on plates
that join where neighbours are occupied, the active one a lit pill that slides there and stretches
as it travels, empty ones a dot; **segments** — after ArchEclipse: thin bars (lit active,
occupied, dim empty) that open under the pointer to show each workspace's most recent app
(Hyprland's clients and the .desktop icons; asked only while this switcher is chosen); **dots** — the
active one stretched into a pill; **numbers** — an underline slides under the active one.
**Compass** — a heading tape: the workspaces' numbers and minor ticks slide under a fixed lubber
line on the instrument's spring, the ends fading. **Radar** — a scope: each workspace a blip at its
bearing, larger the more windows, the sweep turning to the active one with a fading trail, the
blip it rests on ringed; the workspace and its windows beside it.
Instruments, below: DNA, prism, cells.


The window holds every workspace when they fit (up to seven), so an instrument is never longer
than what it carries; past seven it scrolls and keeps the focus inside. While the focus moves, a
comet rides the rail above it (accents on).

- **DNA** (default): two strands (phos, ember) of a double helix, 60° of turn per workspace,
  one rung per workspace with a node on each strand — solid when it has windows, a ring when
  empty, larger the more windows. Depth is weight and brightness. The rung at the focus slot
  stands upright and morphs into the workspace's lit capsule; while the instrument moves the
  helix takes an extra turn in the direction of travel (from the spring's velocity) and
  settles upright. Only occupied workspaces carry their number (every one under the pointer),
  so the strands stay the thing you read.
- **Prism**: steel triangular prisms on a collared shaft, 144° a step, in the palette's steel;
  the number is on the face turned toward you.
- **Cells**: Ferrolume's grid — a small crosshair (empty), a recessed square with a pip per
  window (occupied), lit on the well (active); the corner marks close on the one in use or under
  the pointer.

Tuning in `shell/theme/ferrolume.plm`: `fl.pitch`, `fl.reach`, `fl.dna_amp`, `fl.dna_twist`,
`fl.helix_turn`, `spring fl.helix`; the liquid and the ping: `spring fl.ws_head`, `fl.ws_tail`,
`fl.ping`.
