# Widgets 2c: Clock, Notes and GitHub

Date: 2026-11-03 · Status: approved in conversation ("yes good go ahead"); the user waived spec review.

## Kinds and limits

Three new kinds in `lib/widgets`, all in the same widgets program. Each gets the editor, depth,
wallpaper adaptation, idle rules and Settings rows that the other widgets have.

| Kind | Layouts | Limit | Drawn |
|---|---|---|---|
| `clock` | `digital`, `analogue`, `words`, `info` | up to 8 | in the widget loop |
| `notes` | `list` | at most 1 (one shared list) | as a scene-level lane |
| `github` | `card`, `commits`, `pulse` | at most 2 | as scene-level lanes G1 and G2 |

**Options:**

- clock: `h24` (default true), `seconds` (default true)
- github: `repo` (default "bushninjadots/mooi")
- notes: `rows` (6)

## Clock

The logic sets facts `ck_h`, `ck_m`, `ck_s`, `ck_day`, `ck_date` and `ck_words` once a second, and
only while a clock exists. The scene glides the second hand with a spring.

- **digital:** HH:MM in large Exo 2, with a seconds arc. The date and weekday sit under it.
- **analogue:** a steel dial with 60 ticks, numerals at 12/3/6/9, hour and minute hands, and a
  phosphor second hand.
- **words:** `lib/clockface.words(h, m)` writes the time out ("ten past four", "quarter to five",
  "five o'clock", "twenty-five past eleven"), rounded to the nearest five minutes, with "just
  after" or "nearly" for the in-between minutes. The date is shown in mono.
- **info:** the time and date, plus a strip with:
  - the weather (glyph, temperature, high and low) from `nexus-weather.json` via `lib/forecast`
  - the battery (the battery service)
  - the next due card from `board.json` via `lib/clockface.next_due(board, today)`: the earliest
    due day ≥ today among cards not in the last column, given as "TODAY · <title>",
    "TOMORROW · …" or "<WEEKDAY> · …"
  - the ISO week

## Notes

The list comes from `notes.json` via `lib/notes` (decode, encode, add, update, pin, done, remove),
watched live.

- **The lane:** a list of up to `rows`, pinned first, with a "+N MORE" line.
- **Rows:** each has pin / done / × on hover.
- **Editing:** clicking a row edits it in place in an input field (keyboard on demand while
  editing); Enter saves, Esc cancels.
- **Adding:** "+ NOTE" adds a note through the same field.

## GitHub

`lib/ghparse` turns `gh` answers into display rows.

- **card:** a GraphQL `repository(owner, name)` query gives the description, stars, forks, open
  issues and pull requests, primary language and `pushedAt`.
- **commits:** the last 8 commits on the default branch (message headline, author, committed date,
  abbreviated oid) with their status-check rollup state.
- **runs:** `gh api repos/o/r/actions/runs?per_page=6` gives each run's name, status, conclusion,
  branch and time.
- **activity:** `gh api repos/o/r/stats/commit_activity` gives the last 12 weeks' totals. A 202
  answer means GitHub is still working it out, so the logic asks again later.

**Refresh and cache.** Every 5 minutes (1 minute while a run is in progress), cached in
`gh-<owner>-<repo>.json`. Without `gh` or a sign-in, the widget says what to do. A press on the
title, a commit or a run opens it with `xdg-open`.

## Tests

- `lib/clockface`: words (exact, past, to, o'clock, noon and midnight, rounding), hand angles,
  next_due.
- `lib/ghparse`: card, commits, runs, activity, and refusing junk.
- `lib/widgets`: the new kinds, their limits and their defaults.
- Live: screenshots of each layout, GitHub against bushninjadots/mooi, and the GPU.
