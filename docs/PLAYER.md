# mooi · the music player (plan)

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

## The shapes

1. **The panel** (~1080 × 640, unfolding from the media module like the hub from the Arch mark):
   - left: the **turntable** (the record, the tonearm, the visualiser ring) and the transport;
   - middle: the track — title, artist, album, year, format (FLAC · 44.1 kHz · 16 bit) — the
     **waveform scrubber**, the time, volume, shuffle/repeat;
   - right: a tabbed pane — QUEUE · LIBRARY · LYRICS · PLAYERS.
2. **Full screen** (F, or a button): the cover enlarged and blurred over the whole screen, the
   record big and centred, lyrics flowing beside it with the current line lit, the visualiser
   as a wide ring/horizon. Esc returns to the panel, Esc again closes.

## The look: a turntable

- **The record:** the cover as the label of a black vinyl with fine grooves (rings) and a sheen that
  turns; it spins at 33⅓ while playing and coasts to a stop on pause (a spring, not a cut).
- **The tonearm:** pivots from the plinth's corner; its angle *is* the progress — set down at the
  outer groove, it travels inward to the label as the song plays. Dragging the arm seeks.
- **The visualiser ring:** cava's bands as a ring of bars round the record's edge (24 or 48 bands),
  breathing with the bass; in full screen also a horizon line under the record.
- **The waveform scrubber:** for library tracks, a waveform made once per file with ffmpeg
  (`showwavespic`, cached), drawn as a bar with the played part lit; a press or drag seeks.
- **Colour:** the shell's palette by default; an option to take the accent from the cover
  (matugen on the cover, dry run — the same call Lumen uses), so each album relights the player.
- Motion respects reduced motion and the saver (the record stops spinning, the ring rests).

## Lyrics

Local first: `<song>.lrc` beside the file, then LRCLIB (`https://lrclib.net/api/get?artist_name=…&track_name=…&album_name=…&duration=…`),
cached in the data folder so a song is asked for once. Synced lines are shown with the current one
lit and the next ones fading; plain lyrics scroll; no lyrics says so. A press on a line seeks there.

## Keys

Space play/pause · ←/→ seek 5 s (Shift: 30 s) · ↑/↓ volume · N/P next/previous · S shuffle · R repeat
· L lyrics · Q queue · / search the library · F full screen · Esc back / close.

## Build order

1. **Backend (pure, tested):** `lib/player.luau` — parse `mpc` output (status, current, queue,
   list/find), lyric files (LRC with timestamps, offsets, multiple stamps per line), LRCLIB answers,
   the tonearm angle and the waveform's played fraction from position/length, the library's
   browse tree and search.
2. **The program:** the panel with the turntable, the transport, seek, volume, shuffle/repeat, the
   queue; mpd events through `mpc idleloop` (no polling); cover extraction and caching.
3. **Library and remote:** browse and search, add/play next; the MPRIS side through the media service
   and `playerctl`; the source switch.
4. **Lyrics:** local and LRCLIB, synced view.
5. **Full screen**, the waveform, the cover-led colour option; the bar's media module opening it.
6. Settings (source preference, cover colours, ring bands), docs, tests, a live pass.

## Not possible (said, not faked)

- MPRIS gives no queue or library for other players: the remote side controls, it does not browse.
- Seek and volume through MPRIS depend on the player supporting them (`playerctl` reports when not).
- Pleamar cannot decode audio itself: the waveform is a picture made by ffmpeg, the visualiser is
  cava listening to the output.
