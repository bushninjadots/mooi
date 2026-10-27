# mooi · the music player

**Asked for (2026-10-26):** a press on the bar's media module opens mooi's own music player, and it
looks super cool. **Chosen:** your mpd library first, plus a remote for any other player; a large
panel that unfolds from the media module with a full-screen mode; a turntable as its signature
look; synced lyrics from LRCLIB and local `.lrc` files.

## What it is

A program of its own (`shell/mooi-player.plm` + `.luau`), like the Nexus and Lumen: it holds the
keyboard while it is up, declares its own surface, and is started by the bar
(`open_player`, `mooi player`). The bar's media module opens it on a press (its wheel and its
right press keep their meaning). It paints from palette.json like everything else, and the cover's
own colours can lead (see *Look*).

### Two sources, one face

| | **Library (mpd)** | **Remote (MPRIS)** |
| --- | --- | --- |
| what | your 2,374 songs, 1,229 albums, 705 artists, through `mpc` | whatever else plays: kew, a browser, Spotify |
| browse | artists → albums → tracks, search, recently added | — |
| queue | the mpd queue: add, play next, reorder, remove, clear, save as a playlist | — |
| control | play/pause, next/previous, **seek**, volume, shuffle, repeat, single, consume | play/pause, next/previous, seek, volume, shuffle, loop via `playerctl` (where the player allows) |
| cover | the file's embedded art or `cover.jpg` beside it (extracted once, cached by album) | `mpris:artUrl` (file, https, data) |
| progress | `mpc status` / `idleloop` events, no polling | the media service's position, carried at its rate |

A source switch in the header: LIBRARY · NOW PLAYING ELSEWHERE (lit when another player plays).
When mpd is not running the library side says so and the remote side still works.

## Three sizes (D92)

1. **The mini card** — a press on the bar's music icon. A signal board in the Control Nexus's
   language, hanging under the icon: the cover is the core node inside a progress ring (press:
   play/pause; press or drag round the ring: seek), previous/next are pad nodes wired to it by 45°
   traces, the title a readout, the volume a via up a trace, a visualiser on the bus, pulses along the
   traces while it plays. **OPEN PLAYER** grows the same window into the panel. It takes no keyboard;
   a press outside closes it.
2. **The panel** — OPEN PLAYER, `mooi player` or Super+Alt+M: the chosen **view** on the left plate,
   the track, transport and volume in the middle, the pane on the right (QUEUE · LIBRARY · LYRICS · EQ).
3. **Full screen** — FULL or `f`: the view large. Esc steps back one size (full → panel → closed);
   a press on the empty background, or the ✕, goes back to the panel.

Everything is drawn in one surface (a second full-screen surface took no presses — D92 / 4e15fff).

## Three views (`player.view`, chips in the header)

- **DJ deck** (default) — the turntable: the cover as the record's label, the tonearm (its angle is
  the progress; carried, it seeks), a strobe-dot ring, **CUE** (back to where you last carried the
  song, else its start), **33⅓ / 45** and a **pitch** fader (±8 %) — the record's spin only: mpd cannot
  change speed, and the fader says so — and two **VU** meters from the low and high bands.
- **Cover stage** — the cover large, lifted off its own colours blurred behind, the synced lyrics
  beneath with the sung line large, lit and centred; a press on a line sings from there.
- **Instrument rack** — machined panels: the analyser, a lit time readout, the file's format
  (FLAC · 44.1 kHz · 16 bit · stereo, from ffmpeg), the EQ's three knobs (low/mid/high, turnable while
  the EQ is on), and the song's real waveform as the scrubber.

## Visualisers (`shell/ui/viz.plm`, shared with the bar)

Spectrum, Mirror, Ring, Aurora, LED matrix, Orbit — or off — chosen per place (`player.viz_mini`,
`viz_deck`, `viz_stage`, `viz_rack`, `viz_full`) by the chip on each visualiser. They read sixteen
common bands (`vb0…vb15`) each scene maps from its cava, and take their colours as parameters: the
main accent rising into the second. The bar's media visualiser is the same library (`bar.visualizer`'s
mirror/bars/line/dots → Mirror/Spectrum/Aurora/LED), so it follows the wallpaper like the rest of the bar.

## Library

Every song read once (`mpc listall`), shown four ways — **ALBUMS** as a 3 × 3 grid of covers,
**ARTISTS** and **GENRES** opening onto their albums, **SONGS** as the detailed list with a cover on
every row — sorted (artist/album/year, and title/time for songs) and searched over everything.
Covers come from the files (embedded, else cover/folder/front beside them), one process at a time for
the page on screen, cached in `~/.cache/mooi/covers` at 256 and 64 px; an album without one gets the
palette's two tones and its initials. Untagged songs say "No tags" and sort last.

## Lyrics

Local first (`<song>.lrc` beside the file), then LRCLIB, cached by the song. Synced lines follow the
song; a press on one seeks there; **−0.5 / +0.5** in the LYRICS pane nudges a song whose lines run early
or late (±10 s, kept per song in `player-lyrics.json`).

## Equaliser (EasyEffects underneath)

Ten bands (31 Hz–16 kHz) and a preamp, ±12 dB; presets Flat, Bass, Treble, Vocal, Rock, Electronic,
Acoustic, then your own EasyEffects presets (loaded as they are, never written), and SAVE AS
(`mooi-<name>.json`). mooi writes `~/.local/share/easyeffects/output/mooi.json` and loads it; on first
use it starts EasyEffects' service. EasyEffects keeps its state across runs, so **off gives back the
preset that was loaded before mooi's** (bypass only when there was none). State: `player-eq.json`.

## Video (the music video as the visual)

**VIDEO** on the deck and the stage (panel and full screen): yt-dlp fetches the song's video once
(≤ 720p, `~/.cache/mooi/videos`; YouTube refuses mpv's own stream), mpd pauses, and mpv plays it in
the view's 16:9 box, placed by a Hyprland rule (floating, pinned, never focused, no border). The
player is an overlay, drawn above every window, so mpv sits under it and the player leaves that box
undrawn. MUSIC (the same chip), Escape, a new size or view, or the video's end close it, and mpd picks
up where the video reached (the video's clock since it began). Fetching shows its progress.

## Keys

Space play/pause · ←/→ seek 5 s (Shift: 30 s) · ↑/↓ volume · N/P next/previous · S shuffle · R repeat
· Q queue · F full screen · Esc back one size (or close the video).

## Not possible (said, not faked)

- MPRIS gives no queue or library for other players: the remote side controls, it does not browse; VIDEO
  is for library songs.
- mpd has no speed control: the deck's pitch and 33/45 turn the record, not the music.
- Seek and volume through MPRIS depend on the player supporting them (`playerctl` reports when not).
- Pleamar cannot decode audio: the waveform is a picture made by ffmpeg, the visualisers are cava
  listening to the output.

## Status (2026-10-27, D92)

The overhaul is built and live: three sizes, three views, six visualisers (shared with the bar), the
library with covers, lyrics offsets, the EasyEffects equaliser and the video. Plan and spec:
`docs/superpowers/plans/2026-10-27-music-player.md`, `docs/superpowers/specs/2026-10-27-music-player-design.md`.
