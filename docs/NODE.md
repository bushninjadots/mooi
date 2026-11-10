# The node

The node is the small living thing at the top of the screen: a seed that grows into whatever is
happening and folds back when it is over. It is also called the Dynamic Pill. It can show the music,
a notice, the volume, the workspaces, the microphone, the battery, the search line, the time, the
player and one panel with everything else, and it can be shaped and coloured to suit you.

It is one program, `mooi-node`, which mooi starts and keeps while the bar's shape is Pill and
Settings → Bar & Frame → The Pill → The node is on. It asks the system only for what it needs, when
it needs it; between events it has nothing of its own to draw.

## What it is

The node begins as a seed. When something happens — a song starts, a notice arrives, you change the
volume or the workspace, a timer finishes — the seed stretches towards the news and grows the shape
that belongs to it. When the moment passes, it folds back into the seed.

The seed rests at the top of the screen, at the left, the centre or the right, as you choose. You can
rest the pointer on it to unfold it, click it, or use the keys below. What it shows is decided in this
order:

1. A panel you opened stays until you let it go.
2. Otherwise the strongest thing happening just now is shown.
3. Otherwise, if music is playing and the pointer is near, the music.
4. Otherwise the seed.

A fresh event first shows as a quick reaction: the seed stretches towards it for a moment before the
shape grows. Everything grows out of the body rather than appearing beside it, and each part can
follow at its own pace, depending on the look.

## At rest

At rest the node is the seed, breathing gently. Its shape, size, roundness, character and distance
from the top are all yours, and so is the depth of its breathing. With Breathing at 0 it is still; if
you have reduced motion turned on, it does not breathe at all.

### The seed shapes

There are six seeds:

- **Line** — a short, rounded bar. This is the default.
- **Dot** — a small round seed, at most 16 pixels across.
- **Ring** — the same small size, drawn as a ring.
- **Twin** — two short bodies side by side.
- **Bar** — a longer, squarer bar.
- **Clock** — a capsule with the time in it (see below).

You can set the seed's width (6–80 px), its height (2–16 px), its roundness (0–100%), its distance
from the top of the screen (0–40 px) and its character: Organic, Minimal, Technical or Cyber. The
character changes the details it wears — a soft glow, a bare hairline, ticks and brackets, or a
broken outline that glitches when it changes.

### The panel

Super, or a press on the resting pill, grows one panel straight down out of it. It is 500 pixels wide on
every page and as tall as the page needs. Super again, Esc, or a press on an empty part of it lets it go.

- **Home** — the music (cover, song, transport, a seek bar; press the cover for the player), four buttons
  for Wi-Fi, Silent, Timer and Bluetooth, volume and brightness sliders, the three newest notices with
  `Clear all`, and the page icons. A button's icon does what it says; its name opens the radio's page.
- **Calendar**, **Notes**, **Clipboard**, **Stash**, **Wallpaper** and **Power** — what the shelf's
  branches held, now pages of the same panel.
- **Wi-Fi** — the network in use, its strength and whether it is locked, then the networks in reach,
  strongest first: bars, a lock, and `known` for one used before. Press a known or open network to join
  it; a locked new one asks for its password in a secret line. `×` forgets a known one. The refresh
  icon scans.
- **Bluetooth** — the adapter and the device in use, with its battery when it says. The devices follow,
  connected first then paired then the rest; press one to connect or disconnect it. The refresh icon
  looks for more. Without an adapter the page says so.
- **System** — CPU, memory, temperature, network and battery as cards, each with its last twenty samples.
  Press the processor, memory or heat card for btop.

Every page ends in the same row of icons: home, calendar, notes, clipboard, stash, wallpaper, system,
Wi-Fi, Bluetooth, settings, Control Nexus and power. The current page is lit. Wi-Fi and Bluetooth are
pages here; time is the Timer button's page, studio is Settings' own, and Control Nexus leaves the panel
for `mooi nexus`, as Settings does.

### The time capsule

While a time tool is running, the seed becomes a capsule. It shows the tool's name on the left and
its value on the right, a line drains along its floor as time passes, and a sweep of light crosses
it. In a timer's, focus phase's or alarm's last minute it turns warm and the sweep runs faster.

If more than one thing is running, the capsule shows the most pressing: an alarm within ten minutes
first, then a timer, then focus, then a stopwatch. The other tools keep counting in the panel.

### The clock seed

If you choose the Clock seed, the node rests as a small capsule showing the time in mooi's own 5×7
pixel letters, two pixels to a cell. It changes when the minute turns, and costs nothing in between.
While a timer or other time tool is running, its capsule takes the clock's place, and the clock
returns when the tool is done.

## What it grows by itself

These are the shapes the node grows when something happens. Each folds back after a few seconds.
Resting the pointer on the node holds a notice, and keeps the music strip out while a song plays.
Each has its own press.

### Music

When a song starts and Music is on, the seed grows a strip with the cover, the song's title and
artist, a progress line and the visualiser you chose (bars, wave, dots or off). It has three
controls: back, play or pause, and next. Press the strip to open the player. The strip stays while
the pointer is near it.

### Notices

When a notice arrives and Notices is on, the node grows a column of cards. Notices are gathered by
application: one card per app, showing that app's newest notice and how many it has sent
(`FIREFOX · 3`). You see as many cards as your Notices setting allows (1–5, three by default), and
`+N MORE` counts the notices still waiting, not the cards.

Each card has the app's name, the notice's title, an action button when the notice offers one, and a
`×` to dismiss it. A line drains along the first card over its six seconds; resting the pointer on
the node holds it. Pressing a card opens the notice, its action button does the action, and the `×`
dismisses it. The notice's body is never sent to the node: only the app, the title and the actions
leave the bar.

If On the wallpaper is on, a new notice also ripples the wallpaper under the node.

### The gauge

When a reading changes, the seed grows into a bar that fills to it, with an icon and the reading
under it, for about two seconds. It is a reading, not a control. It grows for:

- the volume, when it changes by more than 0.4% (`VOLUME N%`), and the speakers being muted or
  unmuted (`MUTED`);
- the microphone being muted or unmuted (`MICROPHONE OFF` is warm);
- the screen's brightness (`BRIGHTNESS N%`), when the machine has a backlight;
- the power cable going in or coming out (`CHARGING · N%`, `ON BATTERY · N%`);
- Caps Lock and Num Lock (`CAPS LOCK ON`); the lock keys still work as usual;
- game mode turning on or off.

The last change is the one shown. Settings → The Pill → Gauges turns all of them off.

### Workspaces

When you change workspace, the node grows a rail of the workspaces for a second and a half, with the
active one marked. Press a workspace to go there.

### The microphone and camera

Every two seconds, while Microphone and camera is on, the node asks PipeWire which applications are
recording and whether a camera is open. The moment either starts or stops, it grows a card:

- `MICROPHONE ON` or `MICROPHONE OFF`, with the applications' names, or `In use` / `No longer in
  use` when it cannot name them.
- `CAMERA ON` or `CAMERA OFF`.

The card stays for three and a half seconds. Visualisers listening to the speakers, peak meters and
mooi's own helpers are not counted as microphone users.

### The battery

When the battery falls below 20% while unplugged, the node grows a warm card once, at the crossing.
It reads `BATTERY N%` and `Plug in soon`; when upower can say, the detail becomes `About 42 min left
· plug in soon`. It stays for six seconds. It does not appear at start-up just because the battery
is already low, and it does not appear while charging.

### What a press does

Pressing the body depends on what is showing:

- the music strip opens the player;
- the time capsule opens the time panel;
- the panel closes;
- otherwise, if music is playing, the music strip opens;
- otherwise the panel opens at home.

Cards have their own presses, described above.

## What you open

### Super

A tap of Super (press and release it without another key) wakes the node. While a panel you opened
is showing — the search, the orbit, the time panel, the player or the node's panel — Super lets go
of it. It does not sweep away a passing card, and it never dismisses a finished timer: that waits for
your answer.

At rest, a tap of Super opens the panel at home.

### Super+Space — the search line

Super+Space opens the search line. Type, and the node looks for:

- **Applications** — the apps you use most first, then the ones whose names match.
- **mooi's commands** — Settings, The Pill's studio, the time panel, the wallpaper picker, arranging
  the widgets, Control Nexus, the music player, clipboard history, quick notes, the board, every
  workspace, light or dark, locking the screen, recording the screen and game mode. Nothing that stops,
  restarts or rewrites anything is in the list.
- **Open windows** — by title or application; each row is tagged `WINDOW` and the workspace it is on.
- **Sums** — `200+10%` gives `= 220`, `2^10` gives `= 1024`, `sqrt(9)` gives `= 3`.
- **Conversions** — `5 km in mi` gives `= 3.10686 mi`, `20 c to f` gives `= 68 f`, and
  `2 GB in MiB` gives `= 1907.35 MiB`.
- **SSH hosts** — the `Host` names in `~/.ssh/config`, by name or by the address they go to; `ssh`
  alone lists them all. A row is tagged `SSH`, and Return opens your terminal on `ssh NAME`. Patterns
  such as `Host *` are rules, not hosts, and are left out.
- **Packages** — start with `pkg ` (or `pacman ` or `aur `): `pkg ripgrep` asks the repositories and,
  when paru or yay is installed, the AUR, once you stop typing. Up to five rows come back, the
  repositories' first and the AUR's best two after, the exact name leading; each is tagged with its
  repository, and `INSTALLED` when it is. Return opens your terminal on the install (`sudo pacman -S`
  or `paru -S`), so the password and every question are yours; it waits for Return when it is done.
  **Update the system** does the same with `-Syu`.

A sum or conversion comes first. Then come strong command and window matches, then applications,
then weaker ones, up to six rows. Each row says what it is: `MOOI`, `WINDOW · 3`, or `=`.
Use ↑ and ↓ to choose, Return to take the row, and Esc to close. Taking an application launches it, a
command runs its `mooi` subcommand, a window comes to the front, and a sum or conversion is copied to
the clipboard. The desktop steps back behind the search by the amount set in Search dim.

If the node is not running, Super+Space still opens mooi's usual search.

### Super+Tab — the workspaces' orbit

Super+Tab shows the workspaces in a ring round the node, with the active one in front. Each tile
shows up to four application classes on that workspace, joined by ` · `. ← and → turn the ring, the
wheel does the same, Return goes to the workspace in front, and Esc closes it. You can also press a
workspace. Past the last workspace the ring carries on round rather than spinning back.

If the node is not running, Super+Tab opens the Overview instead.

### Super+K — the shortcuts

Super+K opens the panel on **Shortcuts**: every key Hyprland has bound right now, in words. Each row is
the keys, as people say them (`Super + Shift + S`), and what they do. The words come from the
`--- what it does` comment above each bind in Hyprland's config, and from mooi's own names for its keys;
a bind nothing names says what Hyprland knows of it, such as `Close the window` or `Workspace 3`. Super's
keys come first, then the others, then the workspace numbers.

Type to filter: every word must be in the keys or the words. ↑ and ↓ or the wheel scroll three rows at
a time; the foot counts what is below. Super+K again, Super or Esc lets it go. The sheet asks Hyprland
each time it opens, so a key changed a minute ago shows as it is now. It is also in the search line as
**Keyboard shortcuts**, and `mooi node keys` opens it.

### Super+T — time

Super+T opens the time panel: a timer, a stopwatch, focus rounds and an alarm, all in one place. The
mode you are using fills the panel, with its readout in mooi's 5×7 letters, a strip of 30 cells
showing its progress, and its own buttons. The other three sit on a rail along the floor, still
counting; press one to switch to it.

- **Timer** — set from one minute to 24 hours, five minutes by default. `+1M`, `+5M`, `+10M` and
  `-1M` change it; the main button starts, pauses or resumes it, and Reset puts it back. While it
  runs, the main button reads `PAUSE`, and `RESUME` when paused.
- **Stopwatch** — counts up, with hundredths. Start, stop, go on, reset, and Lap. Laps are kept
  newest first, up to 99, and the status shows the latest lap and its split.
- **Focus** — 25 minutes of focus, then a 5-minute break; after four rounds the break is 15 minutes.
  Start, pause, resume, stop or skip. A finished phase waits for you to start the next one, so the
  panel tells you when to take the break and when to go back.
- **Alarm** — a daily alarm at a local time, 07:30 and off by default. `H+`, `H-`, `M+` and `M-`
  move it; Set turns it on and Turn off turns it off. It re-arms for the next day after it rings.

While any of them runs, the resting seed shows the capsule described above. When one finishes, the
node becomes a card that pulses and chimes three soft notes of its own. Answer it with a click on it
(or on OK). It never takes the keyboard, so a timer that ends while you type steals no keys; the
pointer resting on it or Super will not dismiss it, and if several things
finish, they wait their turn, oldest first. If a time tool finishes under a fullscreen window, where
you cannot see the node, a desktop notification says so too.

The panel never takes the keyboard. Super, or a press on an empty part of the panel, folds it away.
Everything is kept in `node-time.json` against the wall clock, so a timer survives a restart.

### The player

Press the music strip, or the panel's cover, and it grows into the player. A large cover sits on the
left — square or round, as you chose — with the title and its source over its foot, so the record is
named where it is seen. The title and artist are beside it, then a seek bar with the position and
length. Drag the bar to seek; the player is told once the drag rests.

The transport is a row of icons: Shuffle, Back, Play or pause, Next and Repeat. Play is the larger,
in a filled accent circle; the others light when they are on. Repeat cycles off, the whole playlist
and the one track, and the track repeat is marked with a small `1`. The player never takes the
keyboard; Super, or a press on an empty part of the panel, lets it go.

Across the middle, the music is mirrored as a wave: 28 bars rising and falling above and below the
centre, from the bar's own visualiser feed. The node asks for that feed only while the player is
open, every three seconds.

The three meters have their own inset card on the right, each a column of ten segments with its icon
under it: `VOL` for the volume, `LIGHT` for the screen's brightness (hidden when there is no
backlight) and `MIC` for the microphone. Drag a meter to set it; the `MIC` icon mutes and unmutes the
microphone, and its segments go quiet while it is muted.

The `MIX` switch, beside the song, turns the lower half into a mixer: one row for each application
playing (a browser with many tabs is one row), with a level to drag and a mute. It shows up to four
rows, and `NOTHING ELSE PLAYS` when no application is playing. The rows are read once a second only
while the mixer is shown, and the reading pauses while you drag a level, so a row does not jump back
under your hand.

If Lyrics in the player is on, the player shows the line being sung, lit, and the next line under it,
in place of the spectrum. A song with no current line shows `♪`. The words come from the shared
lyrics cache or from LRCLIB, once per song; see Privacy below.

### The system page

The panel's system page shows the machine in five cards: `CPU`, `RAM`, `TEMP`, `NET` and `BAT`, each with
its value and its last twenty samples. A reading turns warm when the processor is over 85%, memory over
90%, the temperature over 85°, the network is offline, or the battery is below 20% and unplugged. A
reading that is not available shows `—`. Press the processor, memory or heat card for btop.

## The studio

The studio is where the node's look is made. Open it with `mooi node studio`, or with Settings → Bar &
Frame → The Pill → Its look → Open the studio. The desktop steps back, and the real node — not a copy
— stands on a stage under the title `THE PILL · STUDIO` and the name of the look.

Above the stage are eight preview chips: `REST`, `MUSIC`, `NOTICE`, `VOLUME`, `RAIL`, `SYSTEM`,
`SEARCH` and `TOUR`. Press a chip to see that state. Tour moves through them every 2.2 seconds.
Pressing the node on the stage moves to the next chip.

Below the stage is the deck, with seven pages: Presets, Pill, Shape, Surface, Motion, Music and Parts, and
the buttons `RESET`, `SHUFFLE` and `DONE`. Sliders are dragged; choices are chips. A row that cannot matter
under the look as it stands is dimmed and says why, and its slider or chips cannot be moved (D261). Changes
are written to `node-look.json` 300 milliseconds after they stop, and a hand edit of that file is worn at once.

### Presets

Four cards, each drawing its own seed at three times its size:

- **Organic** — Soft and elastic: it breathes, and leans into the music.
- **Minimal** — A point. Fast, restrained, next to no glow.
- **Technical** — Ruled and precise: ticks, brackets, square corners.
- **Cyber** — Quick and broken: segments, an ember glow, a glitch on every change.

The card of the look you are wearing is lit, unless you have changed it into a look of your own.
Press a card to wear that preset. `RESET` wears the current preset again and clears your changes;
`SHUFFLE` makes a new look of its own, held to stay legible; `DONE` closes the studio.

### Shape

- **Seed** — Line, Dot, Ring, Twin, Bar or Clock.
- **Seed width** — 6–80 px.
- **Seed height** — 2–16 px.
- **Roundness** — 0–100%, from square corners to a full capsule.
- **Character** — Organic, Minimal, Technical or Cyber.
- **From the top** — 0–40 px below the screen's edge.

### Surface

- **Texture** — Solid, Hollow, Segmented, Scan or Dotted.
- **Fill** — 30–100%, how solid the body is.
- **Outline** — 0.0–3.0 px, the edge's weight.
- **Glow** — 0–100%, how much light it gives off.
- **Colour** — Signal, Ember, Ink or Steel, from the palette.
- **Glow colour** — the same four choices for the light.

### Motion

- **Speed** — Soft, Quick or Snap: how quickly it changes shape.
- **Bounce** — None, Some or Lots: how far it overshoots and settles.
- **Growth** — Slow, Normal or Fast: how quickly what unfolds grows out of it.
- **Stagger** — 0–100%: parts one after another, or all at once.
- **Breathing** — 0–100%: how deeply the seed breathes at rest; 0 is still.
- **Music** — 0–100%: how much it moves with what plays.

### Parts

- **Visualiser** — Bars, Wave, Dots or Off, for the music inside the media capsule.
- **Cover** — Square or Round.
- **Notices** — 1–5 cards.
- **Search dim** — 0–60%: how far the desktop steps back behind the search.
- **Orbit** — 300–700 px: how wide the workspaces' orbit is.

### Your looks

Three slots keep looks you have made. Each row has `SAVE HERE`, `WEAR` and `CLEAR`. `SAVE HERE` copies
the look you are wearing into that slot, `WEAR` puts it back on, and `CLEAR` empties the slot. A full
row is named after its preset (with `, made your own` if you changed it), its seed, its texture and its
glow, such as `Organic, made your own · Line seed · Solid · 70% glow`. An empty row says `Empty: save
the look you are wearing here`.

### The keyboard in the studio

- Esc closes the studio.
- Return closes it on the Presets page; on the other pages it moves the current row forward.
- Tab goes to the next page.
- ↑ and ↓ move between rows.
- ← and → change the value; on the Presets page they change the preset.

The look is kept in `node-look.json` in mooi's data folder (see Files). The studio writes the values
in the units it shows: per cent, pixels, and tenths of a pixel for the outline.

## Settings

Settings → Bar & Frame → The Pill. If the bar is not in the Pill shape, the page tells you to choose
Shape → Pill above.

| Row | Setting | Default | What it does |
| --- | --- | --- | --- |
| The node | `node.on` | on | A tiny seed at the top that grows what is happening and folds back. |
| Its look | — | — | Opens the studio. |
| Your pointer | `node.pointer` | Normal | How readily it unfolds when the pointer rests on it: Off, Low, Normal or High. |
| Where | `node.anchor` | Centre | Where it sits at the top: Left, Centre or Right. |
| Side groups | `pill.sides` | Show | The left and right groups as islands beside it, or the Pill alone. This is a bar setting, not a node setting. |
| Music | `node.media` | on | A strip with the cover, the song and its controls when music starts. |
| Notices | `node.notices` | on | A column of cards with each new notice and its action. |
| Workspaces | `node.workspaces` | on | A rail with the workspaces when you change them. |
| Gauges | `node.volume` | on | A gauge for the volume, the light, a mute, Caps or Num Lock and the cable. |
| System | `node.system` | on | Processor, memory, temperature, network and battery on the panel's system page. |
| On the wallpaper | `node.wallpaper` | on | A notice ripples the wallpaper under it. |
| Lyrics in the player | `node.lyrics` | off | The words in time with the song, from the cache or LRCLIB. |
| Microphone and camera | `node.privacy` | on | A card when either starts or stops. |

The page also carries the four keys:

| Row | Setting | Default |
| --- | --- | --- |
| The Pill: search | `keys.node_launch` | `SUPER + space` |
| The Pill: workspaces | `keys.node_universe` | `SUPER + Tab` |
| The Pill: time | `keys.node_time` | `SUPER + T` |
| The Pill: shortcuts | `keys.node_keys` | `SUPER + K` |

One older setting still exists in the file but has no row: `node.personality` (Organic by default)
only seeds the look before the studio has saved one; once `node-look.json` exists, the look comes from
it.

If you have reduced motion turned on, the node does not breathe, whatever the look's Breathing says.

## Keys and commands

| Key or command | What it does |
| --- | --- |
| Super (tap) | Wakes the node; lets go of a panel you opened. At rest, opens the panel at home. |
| Super+Space | The search line. |
| Super+Tab | The workspaces' orbit. |
| Super+T | The time panel. |
| Esc | Closes the search, the orbit or the studio. |
| ← and → | Turn the orbit; change a value in the studio. |
| ↑ and ↓ | Move between rows in the search and the studio. |
| Tab | The next page in the studio. |
| Return | Takes the chosen search row; goes to the workspace in front; moves a studio row forward. |
| Wheel | Turns the orbit. |
| `mooi node wake` | Wakes the node. |
| `mooi node launch` | Opens the search line. |
| `mooi node universe` | Opens the workspaces' orbit. |
| `mooi node studio` | Opens the studio. |
| `mooi node time` | Opens the time panel. |
| Super+K · `mooi node keys` | The shortcut sheet. |
| `mooi pill` | Wakes the node; does nothing when it is not running. |

Without a node, `mooi node launch` opens mooi's usual search and `mooi node universe` opens the
Overview; the other `mooi node` commands do nothing. Super+Space and Super+Tab behave the same way.

## Privacy and what it asks the system

The node is local. It does not send anything anywhere except the one lyrics request described below.

- **Microphone and camera** — while Microphone and camera is on, every two seconds it runs
  `pactl -f json list sources` and `pactl -f json list source-outputs`, and `fuser` on
  `/dev/video0` to `/dev/video3`. It ignores streams that record from a monitor source (a visualiser
  listening to the speakers), media named "peak detect", and the binaries `pleamar`, `pavucontrol`
  and `cava`, so those are not reported as applications using the microphone.
- **The player** — while it is open, once a second it asks `playerctl` for the current song and its
  state, and every two seconds it asks `brightnessctl -m` for the backlight and `pactl` for the
  microphone's volume and mute. It asks the bar for the visualiser's bands every three seconds. All
  of this stops when the player closes.
- **The mixer** — while its page is shown, once a second it reads `pactl -f json list sink-inputs`;
  dragging a level sends `pactl set-sink-input-volume`, and a mute sends
  `pactl set-sink-input-mute`. The reading pauses while you drag.
- **The battery** — when the low-battery card appears, it asks `upower -i
  /org/freedesktop/UPower/devices/DisplayDevice` for the time left.
- **The workspace and windows** — `hyprctl -j clients` when the search or the orbit opens, and
  `hyprctl` to focus a workspace or a window. `hyprctl -j monitors` once, for the screen's size.
- **A finished time tool** — if it finishes under a fullscreen window, `hyprctl -j activewindow`
  checks, and `notify-send` shows a desktop notification.
- **The shortcut sheet** — when it opens, `hyprctl binds -j` for what is bound, and `mooi keys-text`,
  which prints Hyprland's own config files, for the words. Nothing is written.
- **SSH and packages** — when the search line opens, `cat ~/.ssh/config` for the host names. A package
  search runs `mooi pkg search`, which asks `pacman -Ss` (the local database) and `paru -Ssa` or
  `yay -Ssa`, **which sends the words you typed to aur.archlinux.org**. Nothing is installed or
  connected without your Return, and then only in a terminal you see.
- **The lock keys** — Hyprland's `Caps_Lock` and `Num_Lock` binds run `mooi osd caps|num`, which asks
  `hyprctl devices -j` whether the main keyboard's lock is on. Nothing is read from the keyboard itself.
- **Copying an answer** — a chosen sum or conversion goes to `wl-copy`.
- **The wallpaper and the bar** — `pleamar` carries a notice's ripple to the wallpaper, asks the bar
  for the visualiser's bands, and sends a notice's action back to mooi.
- **Lyrics** — only when Lyrics in the player is on, and only for a song with no saved answer, the
  node asks LRCLIB with `curl`. It sends the song's artist, title and length, and nothing else. The
  answer, including "none" or "instrumental", is kept so the song is asked about once.

A notice's body never leaves the bar. The node receives the app, the title, the actions and a flag;
under private signals even the title is blank. The microphone and camera checks are local readings
from PipeWire and `fuser`, not recordings, and nothing is kept from them.

## Files

Everything lives in mooi's data folder, `${XDG_DATA_HOME:-$HOME/.local/share}/pleamar/mooi/`:

- **`node-look.json`** — the look: its 25 values, whether it is your own, and the three saved slots.
  The studio writes it 300 ms after a change; you can edit it by hand and the node will wear it at
  once.
- **`node-time.json`** — the timer, stopwatch, focus rounds and alarm, kept against the wall clock so
  they survive a restart.
- **`player-lyrics/<hash>.lrc`** — the shared lyrics cache, one file per song, holding the words or
  `none` / `instrumental`. mooi's own player uses the same cache, so a song is asked about once
  between them.

The node also reads mooi's `settings.json` and `palette.json`, like the rest of mooi. It writes
nothing else.
