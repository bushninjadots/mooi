# The Pill opens up (the Hub)

Date: 2026-11-07 · Status: design agreed in chat, spec awaiting review · Decision: D170
Part of: `docs/superpowers/specs/2026-11-06-the-pill-design.md` (D168, D169)

## 1. Why

A left press on the Pill opened the calendar whenever nothing was happening, which is most of the time.
In Pill mode the centre modules are not drawn, and with `pill.sides = hide` nothing else is either, so the
Pill is the only way into the desktop's controls — and from idle it reached only the calendar. The owner
asked (2026-11-07) for the Pill to **open up into what is relevant**, as a phone's island does, with the
**left press opening it** and the **right press keeping the old direct jumps**.

## 2. What a press does

| The Pill shows | Left press | Right press |
| --- | --- | --- |
| time (idle) | **the Hub** (§3) | the calendar (as before) |
| BMO's face | **the Hub**, and BMO notices (a poke) | a poke only |
| Nexus face | the Control Nexus (the face's purpose) | **the Hub** |
| music | **the music island**: art, title, seek, ⏮ ⏯ ⏭, the bars — in the bar, under the Pill | the full player (`open_player`, as before) |
| a notification | the notification centre (Signal Loom's field, as before) | **the Hub** |
| volume / brightness | the sound / display island, with its slider (as before) | **the Hub** |
| battery | the power island (as before) | **the Hub** |
| recording | stops recording (as before) | **the Hub** |

- The rule a person can learn: **left opens what the Pill is showing; right opens the Hub** — except idle,
  where left is already the Hub, so right keeps the calendar, and music, where right keeps the full player.
- A press on the Pill while one of its surfaces is open closes it (a toggle). A hidden Pill (D169) comes
  back on the first press, as now. Moon presses are unchanged (pin for 6 s).
- Every surface the Pill opens hangs from the Pill: `isl_cx` is the Pill's centre (as now).

## 3. The Hub

A new island, `open = hub`, drawn with the bar's island kit (`IslandFrame`, `IsleHead`, `IsleBtn`,
`IsleRule`) so it has the same material, tether, reveal and frame join as every other island. 340 wide;
its height follows what it holds. Top to bottom:

1. **Head**: the time, large, and the date with the ISO week. Pressing the head opens the calendar.
2. **Now playing** (only while a player is loaded): art colour chip, title · artist, and ⏮ ⏯ ⏭.
   Pressing the title opens the music island.
3. **Signals** (only when there are any): the newest three from Signal Loom — app, summary, how long ago.
   Pressing one opens Loom's field; "Clear" dismisses them, as Loom's own clear does. Read from Loom in
   the same program (no notification watch here; D169's ownership rule stands).
4. **The tiles**, one row: **Sound**, **Display** (only with a brightness device), **Network** (the system
   island), **Power**, **Nexus**. Each swaps the Hub for its island, or opens the Nexus.

- Closing: Esc, a press outside it (the screen-wide dismiss zone, as the other islands), or a second
  press on the Pill. Keyboard: ←→ across the tiles, ↵ opens, as the islands' own keys.
- Nothing in the Hub reads anything while it is closed.
- Only in Pill mode; the other shapes keep their modules and are unchanged.

## 4. Pieces

- `lib/pill.luau` (pure) gains `press(main, face, button) → action`, one table from §2, so the whole table
  is unit-tested; `bar.luau`'s `pill_press` handler only carries the action out. `event pill_press` takes
  the button (0 left, 1 right).
- `signals.luau` gains `recent(n)` (newest n shown signals, as `nexus-feed.json` items) and the existing
  clear; the Hub's rows come from it.
- The scene: the Hub island in `shell/mooi.plm` beside the other `*_island` groups; `ui/pill.plm`'s zone
  gains `on press right pillz { emit pill_press(1) }`; the dismiss zone's `show:` and closers gain `hub`.

## 5. Testing

- Unit: every row of §2 through `pill.press`; `signals.recent` order and limit.
- Live (`tests/pill.sh`, restoring settings and players): left on idle → `open == hub`; right on idle →
  `calendar`; left on music → `music`; right on music → the player; a tile → its island; a second press
  closes; Esc closes. Screenshots of the Hub with and without music and signals.
