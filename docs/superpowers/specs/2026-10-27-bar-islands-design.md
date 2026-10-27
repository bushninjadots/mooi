# Bar islands — design

Date: 2026-10-27 · Status: approved by delegation (the user: "do what you think is best … yes for
everything", then away) · Decision record: D97 when built.

## Why

Clicking things on the bar opens four different-looking apps: the System, Window and Search islands
are soft "machined" glass (ui/island.plm `IslandFrame`); the Signal Field, the Control Nexus and the
mini player are Ferrolume plates. Most modules open nothing at all (resources, weather, clock,
battery) or the same System island (volume, brightness). The user asked for one island design for
every pop-up under the bar, with two looks to choose from — **Ferrolume plate** and **a style of our
own** — and for richer islands: system statistics, a calendar, weather, and better sound, display
and power islands, plus view states for the clock and the media module.

The Control Nexus is **out of scope**: the user wants it perfected on its own terms ("it can be
different; it needs all the important info inside and buttons leading somewhere"). It gets its own
spec after this one.

## Success

- Every island under the bar is drawn by one kit, so it looks and behaves the same, in either style.
- `island.style` switches all of them live: `plate` (default) or `tether`.
- A press on resources, weather, clock, volume, brightness or battery opens an island made for it,
  under that module; a press elsewhere, Escape or the same module again closes it.
- Each island shows what matters at a glance and has buttons that do something real.
- Light and dark, every corner style (look.corners), reduced motion: all honoured.
- The bar still rests when nothing moves (D96): no island adds a `time` or an endless animation;
  island data is read only while that island is open.

## The two styles

Both share geometry: an island hangs under the module that opened it (centred on it, kept on the
screen), is 300–360 px wide, grows down from the bar on the existing reveal spring (`rv.*`), and
lays out as **header · body rows · footer actions**. The kit decides how each part looks.

**Plate (Ferrolume)** — the bar's own language. A chamfered plate (`Chamfer`, so it follows
look.corners) in `fl.hull`, a `fl.trace` edge whose top run is lit `fl.phos`; the header is Share
Tech Mono caps with a short lit trace under it; rows are separated by dim dotted traces; buttons are
cut-corner chips (`CutButton` shape) that light `fl.phos` on hover and fill when chosen; meters are
segmented bars like the bar's readouts.

**Tether (ours)** — an island that is visibly *attached* to its module: a hairline tether drops
from the module's bottom edge to the island, ending in a small lit node where it meets the body.
The body is a rounded slab (radius from look.corner_size; square when look.corners is square) with a
deep vertical gradient (`surface.elevated` → `bg.primary`), a 1 px rim in the accent at low opacity
that brightens along the top edge, and a soft shadow. Headers are larger and quieter (Exo 2, the
title in `fg.primary`, a muted subtitle); rows are soft inset cards; buttons are pills; meters are
smooth tracks with a round thumb. Calm where Plate is technical.

The existing machined look retires: `IslandFrame` becomes style-aware, so the Window, System and
Search islands take whichever style is chosen without being rewritten.

## The kit (shell/ui/island.plm)

- `IslandFrame(rv, w, h, up, centre, aw, ah, tx)` — draws the body in the chosen style (reads the
  scene fact `isl_style`: 0 plate, 1 tether). `tx` is where the tether meets the body, from the
  island's left (the module's centre; the island is clamped to the screen, the tether is not).
- `IsleHead(w, title, sub)` — the header line: title left, a live subtitle right.
- `IsleRule(w, y)` — a divider in the style.
- `IsleMeter(x, y, w, v, hot)` — a level 0…1 (segmented in plate, a smooth track in tether).
- `IsleBtn(x, y, w, word, lit, hover)` — a button face (cut chip / pill); the zone is the caller's.
- `IsleStat(x, y, label, value)` — a small label over a large value.

Components only draw; every zone and rule stays in the scene where the island lives (pleamar's
rule: one surface per program for presses).

## The islands

All live in the bar's surface (`open` gains `stats | calendar | weather | sound | display | power`),
each with its `rv.*` spring and `life.*` layer, Escape and the outside-press plate (D55) closing it,
and the opening module's press toggling it.

**Stats** (resources) — CPU % with a meter and the load average; memory used / total and swap; the
temperature; the GPU's busy %; the root disk's use; the three processes using most CPU (name and %).
Buttons: *btop* (opens it in kitty), *nvtop* when installed. Read every 2 s while open (`ps`, /proc,
`df`, the amdgpu busy file), in shell/lib/stats.luau (pure parsing, unit-tested).

**Calendar** (clock, left press) — the month as a 6 × 7 grid from Monday, today lit, days of the
other months dimmed; the header says the month and year and the subtitle the ISO week; ‹ › and the
wheel move a month, *Today* comes back. shell/lib/calendar.luau builds the 42 cells (pure, tested).

**Weather** (weather) — now: the big temperature, the word, feels-like, wind, humidity, today's high
and low; the next 6 hours (hour, icon, temperature); 5 days (day, icon, high/low). One open-meteo
request (current + hourly + daily) when it opens, kept 10 minutes. Parsing in shell/lib/forecast.luau
(tested). Button: *Refresh*.

**Sound** (volume) — the level with a meter (press or drag sets it, the wheel nudges), mute; the
output devices (the default lit; a press switches: `audio.default`); the microphone's level and mute.
Button: *Mixer* (pavucontrol if installed, else nothing shown).

**Display** (brightness) — the brightness meter (press/drag/wheel); *Night light* on/off (hyprsunset
at 4000 K, killed to turn off); the theme mode *Dark · Light · Auto* (the existing `set_mode`).

**Power** (battery) — the percent big, charging or not, and the time to full/empty (upower); the
power profile *Saver · Balanced · Performance* (powerprofilesctl, shown only when it answers); *Keep
awake* (the existing `caffeine`).

The **System** island stays (`mooi system` and its key still open it), restyled by the kit.

## View states

- **Clock** — a right press cycles `clock.view`: `full` (time and date, today's look) → `time` →
  `seconds` (HH:MM:SS) → back. Left press opens the calendar. Saved in settings.
- **Media** — a right press cycles `media.mode` (full → compact → art → viz), the existing four
  modes. Play/pause stays on the left press over the visualiser/track.

## Settings

`island.style` (plate | tether, default plate) and `clock.view` (full | time | seconds) in
lib/config; *Islands* (Plate · Tether) on Settings → Colour beside Corners; `clock.view` on the Bar
page. Both appended to SETTERS in tools/gen-settings.py and lib/setters.luau.

## Out of scope

The Control Nexus (next spec); the Signal Field and the side panels (already plates; their own
redesign is a later step); per-app volumes (the audio service lists apps, but the rows would crowd
the island — later).

## Testing

Unit (tests/unit/run.lua): calendar cells (month starts, leap years, today), forecast parsing
(missing fields, wrong types), stats parsing (ps, /proc/loadavg, df, meminfo). Live: each island
opened from its module with `--say press`, drawn in both styles and screenshotted; Escape and an
outside press close it; the bar's idle frame count stays 0 with every island closed; scene.sh and
integration.sh still pass.
