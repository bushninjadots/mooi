# The Pill

Date: 2026-11-06 · Status: design approved in brainstorming, spec awaiting review · Decision: D168
Part of: `docs/superpowers/specs/2026-11-06-bar-redesign-design.md` (D164 §4, stage 3)
Mockups: `.superpowers/brainstorm/583795-1793963491/content/` (pill, pill-shape)

## 1. What it is

A capsule at the top centre that becomes whatever is happening, then shrinks back. The owner chose
(2026-11-06): **Satellites** by default with **Split** as an option; Pill mode either **alone** or **with
the side groups** as quiet islands; with the frame on, the Pill **hangs from the band** and its moons
pinch off it.

## 2. Shape and settings

| Setting | Values | Default | Meaning |
| --- | --- | --- | --- |
| `bar.mode` | gains `pill` | — | Shape → Pill |
| `pill.sides` | `show` · `hide` | `show` | the left and right groups as islands beside the Pill, or the Pill alone |
| `pill.multi` | `satellites` · `split` | `satellites` | two things at once (§4) |
| `pill.moons` | 1–4 | 3 | moons shown at most |
| `pill.off` | ids | `[]` | activities that may not take the Pill |
| `pill.order` | ids | `battery, record, notify, music, osd, idle` | priority, first wins |

- In Pill mode the bar's **centre group becomes the Pill**; its modules are not drawn as modules (their
  information is the Pill's idle and music states). With `pill.sides = show` the left and right groups
  are islands as in Islands mode; with `hide` they are not drawn.
- Settings → Bar & Frame: Shape gains **Pill**; The Pill fold holds: with the side groups (Show/Hide),
  two at once (Satellites/Split), moons at most (1–4), and the activities in order with an on/off each
  (move up/down buttons; the list is short).

## 3. States (the activities)

| Activity | Comes from | Shows | Lasts |
| --- | --- | --- | --- |
| `battery` | battery service | ⚠ and percent when ≤ 15 % and not charging; ⚡ and percent for 4 s when charging starts | while low; 4 s |
| `record` | the bar's recorder (`fact.recording`) | ● REC and the elapsed time | while recording |
| `notify` | the notification service (Signal Loom) | app and summary of the newest | 6 s after it arrives |
| `music` | media service | art colour chip, title, live bars | while something plays |
| `osd` | audio and brightness changes | VOL or BRI, a bar, the value | 2 s after the last change |
| `idle` | clock, workspaces | the time and the workspace dots | always (the fallback) |

- The highest-priority **active** activity (by `pill.order`, minus `pill.off`) is the Pill's **main**.
  The next active ones (up to `pill.moons`) are **moons**. `idle` is never a moon.
- **Satellites**: moons are small circles beside the Pill, each showing its activity's glyph; they bud
  off with the material's motion. **Split**: the Pill shows main and the first moon side by side in two
  halves joined by a pinch; other moons wait.
- The Pill's width follows its content and moves on the bar's spring (`fl.flow`); a notification grows
  it taller (two lines) for its 6 s.
- **Clicks**: music → the player's mini card; notify → the notification centre; osd → the sound or
  display island; record → stops recording; battery → the power island; idle → the calendar.
  **Scroll**: over music or osd-volume changes the volume; over idle switches workspace. A moon click
  makes it main for 6 s.

## 4. Geometry and the frame

- `lib/chassis` gains the Pill: in `pill` mode a piece for the Pill (`r` = half its height) and one per
  moon (circles), plus the side islands (floating plates, as Islands mode) when `pill.sides = show`.
- With the frame on, the Pill piece and the moons are **joined** to the band (`j`, a small blend), so the
  Pill hangs from it like a notch and the moons pinch off it; with the frame off they float.
- The Pill's foot is the bar's foot (one bottom edge, D165). Swell moves the band and the Pill with it.

## 5. Where it is computed and drawn

- `shell/lib/pill.luau` (pure): activities in, `{ main, moons, split, width, two_lines }` out, with the
  timing rules above; unit-tested with a fake clock.
- The bar's logic feeds it from the services it already watches and writes facts (`pill_main`,
  `pill_text`, `pill_sub`, `pill_w`, `moon0..3`, …) and the Pill's place into `bar-geo.json` (`pill`,
  `moons`) for the frame.
- `shell/ui/pill.plm`: the Pill's content (per state) and the moons' glyphs, drawn by the bar scene; the
  frame draws their bodies (chassis), as for every other piece.

## 6. Testing

- Unit: `lib/pill` (priority, off, moons cap, split, timing: OSD 2 s, notify 6 s, charging 4 s, battery
  threshold, idle fallback); config (new keys, `bar.mode = pill`); chassis (Pill and moon pieces, joined
  with the frame, foot); settings (Pill choice, fold rows).
- Live: `tests/chassis.sh` gains Pill mode (sides show/hide × frame off/on × swell): one foot, no humps
  beside the Pill; a `tests/pill.sh` drives activities through `pleamar --say` (a fake notification via
  `notify-send`, a volume nudge restored after, the player's play/pause) and screenshots each state and
  the satellites/split cases, restoring volume, playback and settings.

## 7. Out of scope

- The Pill as a placeable component in Full/Notch/Islands (D164 §4 last line) — after this stage.
- Liquid and Cartridge materials (their Pill motion comes with them).
- A timer activity (no timer exists yet; `pill.order` can gain it later).
