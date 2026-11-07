# The Sigil: one living object that replaces the Pill — design

> Status: design approved in conversation (2026-11-07), awaiting review of this written spec.
> Replaces: the Pill (D168–D205: `lib/pill`, `ui/pill.plm`, `shell/pillboard.luau`, `ui/pillboard.plm`, the
> morph D204, the extra pills D205). Brainstorm mockups: `.superpowers/brainstorm/718473-1794068228/` (local,
> not in the repo).

## 1. What the owner asked for

- A complete redesign of the Pill, "awesome in every way, different, new, unconventional, with ultimate
  customisability in all aspects and functionality". The owner disliked everything about the current one.
- Of five directions shown (Organism, Instrument, Lens, Sigil, Field) the owner chose **Sigil** — a single
  living line that changes shape and reacts — mixed with **Field** — the bar as a field of points — and wants
  **beautiful displays that morph and shapeshift** to show things. **Organism goes into BMO** (later).
- **One object, many hosts** (option A): a standalone part that any bar layout can host. Hosts wanted: **the
  Pill** and **islands**; plus **the pointer** (hold Super and it comes to you) and **desk mode**, expanded.
- It must reach **everything the bar can**: notes, the wallpaper switcher, the Nexus, workspace overviews and
  switchers, settings, search, apps, weather, clock, resources, alerts and notifications, health reports, wifi,
  open windows, Bluetooth, volume, music and visualisers, the stash, the clipboard, calendars, desk mode — with
  the **choice to open any module up** into a detailed, expressive view.
- **Context-aware**: it reacts to what is pointed at or hovered, and to what is open and its window state,
  with settings and visuals tied to it. It can take **the shape of an app's icon** when cycling apps, and
  other shapes from context.
- **Swappable bodies**: the line we designed (Sigil), an organic morphing mass ("like Venom"), and high-tech
  circuitry with power pulses moving along a matrix (Circuit).
- **Colour**: dynamic with Matugen and the wallpaper, the album art's colours for music, and system events.
- **BMO**, the pet, incorporated.
- Separate, later: **mooi Pulse** (diagnostics in plain language, after github.com/Regncreative/PulseDiagnostics),
  **BMO's organism body**, and **desk mode** expanded. Each gets its own spec; this design leaves room for them.

## 2. What the spike established

A throwaway Pleamar scene (2026-11-07) drew a 64-point line on springs, morphing between three shapes, five
ways, each measured with `pleamar --report` for 7–8 s on this laptop (Ryzen 5 7430U, Radeon integrated):

| variant | compose | paint | CPU |
|---|---|---|---|
| 64 sprung points, straight segments | 0.05 ms | 0.27 ms | 3 % |
| the same with curves | 0.05 ms | 0.25 ms | 3 % |
| glow + three stroke passes | 0.06 ms | 0.31 ms | 4 % |
| halftone disc (293 dots) + line | 0.26 ms | 0.34 ms | 5 % |
| a filled mass melting in a `body` | 0.06 ms | 0.27 ms | 3 % |

All held 60 fps. The 70 ms measured for D204's morph came from drawing it **inside the frame's full-width band
bodies** (every tile composes it), not from the line. **Rule: the object draws on its own small surfaces, never
inside the frame's band.**

App icons: the outer silhouette of an icon sampled into 64 points reads well for shaped icons (Firefox's fox,
kitty's cat); round icons (Spotify, Steam) come out as circles, so for those the inner mark is traced.

## 3. Architecture

**One program, `mooi-sigil`** (`shell/mooi-sigil.plm`, `shell/mooi-sigil.luau`), started and respawned by
`shell/mooi.luau` exactly as the frame is (five quick deaths and it stays down; the bar then draws a plain clock
in the Pill's box so the bar is never bare).

Inputs:
- **Hosts:** `sigil-hosts.json`, written by the bar when its layout changes (as `bar-geo.json` is for the
  frame): each host's `id`, `kind` (`pill` · `island` · `pointer` · `desk`), `box` (x, y, w, h), `room`
  (height available below), `max_form`, `edge` (top · left · right · bottom), the screen.
- **What is happening:** the program asks Pleamar's services directly where they exist (`media`, `audio`,
  `audio.level`, `battery`, `brightness`, `network`, `bluetooth`, `workspaces`, `window`, `clock`, `apps`).
  What only mooi computes comes from the files mooi already writes (weather, resources, the visualiser feed,
  `nexus-feed.json` for notifications and signals). **It never watches `notifications` or
  `notification_history`**: doing so in a second program starts a notification server and steals the D-Bus
  name from Signal Loom; only `signals.luau` may.
- **Settings:** `settings.json` (`sigil.*`, below), validated by `lib/config`.

Outputs: actions as messages to the program that does them (`pleamar --say mooi …`, `mooi notes`, `mooi
player`, Hyprland dispatches through `lib/hypr`), as the Nexus does today.

Five pure modules, each unit-tested without a scene:

| module | does | depends on |
|---|---|---|
| `lib/sigil/sources.luau` | the catalogue: every source's forms, actions, urgency, glyph | nothing |
| `lib/sigil/shapes.luau` | the 64 outline points for every form in a box; traced icon silhouettes (cached) | nothing |
| `lib/sigil/director.luau` | what each host shows now: priorities, urgency, hover, context rules | sources |
| `lib/sigil/palette.luau` | the colour for a source now: base, album, event, override | nothing |
| `lib/sigil/bodies.luau` | each body's and temperament's numbers for the scene | nothing |

The scene draws **one component per host**: 64 points on springs, the chosen body, and the form's contents.

## 4. Sources and forms

Every source has up to four forms:

| form | size | what it is | where |
|---|---|---|---|
| glyph | ~20 px | the line's shape alone (a clock, a waveform, an app silhouette) | resting, the pointer ring |
| compact | bar height | glyph and one line of words or a level | islands, the full bar |
| display | ~600 × 220 | a shaped display: disc, ring, card, strip, ribbon, horizon… | the Pill, the pointer |
| detail | a panel up to full screen | the module opened up, interactive | grows out of the host that opened it |

A source declares: `id`, `group`, its forms, its actions (`press`, `wheel`, `alt`), its urgency for each
event (gentle · notable · urgent), its glyph and its default display shape.

Groups and sources (the pointer ring's groups):
- **Time:** clock, calendar, weather
- **Sound:** music (with visualisers), volume, microphone
- **Machine:** resources, battery, network/wifi, Bluetooth, temperature; health (with Pulse)
- **Work:** workspaces (overview and switcher), open windows, apps and programs, search
- **You:** notifications and alerts, notes, stash, clipboard
- **Desk:** wallpaper switcher, desk mode, the Nexus, settings, screenshot/record, power
- **This window** (only at the pointer, over a window): close, float, fullscreen, pin, send to workspace
- **bmo:** BMO himself (§8)

**Displays are one vocabulary of parts** — ring, ribbon, card, strip, disc, grid, list, graph, halftone image,
horizon — and every display and detail view is composed from them, morphing in place. The outline is always the
line; pictures arrive as halftone dots out of the field; numbers and words come in sharp.

Mocked displays (to carry into the build): the clock glyph; music as a disc with the cover in halftone that
rolls out into a baseline riding the bass, the title beside it; health as a ring filling to the score with a
trace of the last minute trailing from it; a notice as a card the line traces and the message typing in; the
24 hours as a skyline the stroke draws, errors and warnings filled; volume as a ribbon; weather as a horizon
with the sun on its arc.

**Waves** (one spec, built in order):
- **Wave 1:** clock, calendar, weather, music and visualiser, volume, notifications, workspaces, windows and
  apps switcher, resources, battery, network, Bluetooth, bmo.
- **Wave 2:** notes, stash, clipboard, wallpaper, search, settings, the Nexus, desk mode, screenshot/record,
  power, microphone, temperature, health (with Pulse).

## 5. Hosts

- **The Pill:** the centre of the bar in Pill mode, one instance, the object's home. Rests as glyph or
  compact; hover grows the display down from the bar (replacing the peek); a press or "open" grows the detail
  into a large centred panel (up to ~900 × 600).
- **An island:** a bar module, `sigil`, placed in any island or the full bar like any module, at the width the
  owner gives it. Compact inside the bar; a press drops its display or detail from under it. With several hosts
  the director gives each a different source.
- **The pointer:** **hold Super** — the line flies from its home to the pointer and opens a ring of the groups;
  moving toward a group opens a second ring of its sources; moving toward a source morphs it into its display;
  release opens it, release in the middle cancels. The wheel while holding steps the current ring. **Tap
  Super** brings what the Pill shows now to the pointer (today's Super-alone key, D171, reused). Over a window
  the ring gains **This window**.
- **Desk:** the full-screen host. The contract includes it; its design is the desk-mode spec.

Surfaces:
- a surface the height of the bar, always there, holding the resting forms and their zones;
- a second, mapped only while a display or detail is open, so it never blocks clicks on windows;
- a full-screen overlay mapped only while Super is held (and for the line's flight to and from the pointer).
Every control lives on the surface that receives the press (D170's lesson: a zone on another surface was drawn
but never got a real click).

Travel: when the pointer takes over, the line flies visibly from its home to the cursor and back — one object
moving, never a copy appearing.

## 6. Bodies, motion, colour

**Bodies** share the points and the contents; one per host (default: the same everywhere):
- **Sigil:** a luminous stroke — glow passes, a bright pen head running along it, the line rewriting itself
  front-first (each point follows with a lag along its length).
- **Venom:** a filled, glossy dark mass with a rim of light that faces the pointer; looser, bouncier springs;
  on a change, droplets pull away and melt back (`blend`); the contents inside the mass.
- **Circuit:** the outline as right-angled traces with pads at the corners and power pulses running along them;
  a change re-routes the traces; the field becomes a matrix grid.
- **The field** (dots behind the object, warmed by the pointer, lit near the object) is shared and can be off.

**Motion:** a temperament — **Calm · Lively · Restless** (stiffness, wobble, trail, breathing at rest) — plus
pointer reaction (drawn · pushed · ignore) and `motion.speed`. Reduced motion: every change happens at once, no
idle loops (Pleamar's `motion.reduced`, and mooi's `motion.reduced` / saver).

**Colour**, in layers, each easing into the next:
1. base — the wallpaper's Matugen palette (`palette.json`);
2. music — the album art's colours (the per-cover extraction D172 built and caches);
3. system events — the theme's status colours (warning amber, error red, success green);
4. optional — a fixed colour per source.

## 7. Customising it

- **Settings → The Sigil**, one short page: body (three pictures), temperament (three pictures), colour (follow
  everything · fixed), hosts on (Pill · islands · pointer).
- **Shape it, on the object** (right press → Edit): drag sources into each host and into the pointer ring's
  groups; press a source to choose its form or colour. What is seen is what is set.
- Everything else in the settings file (`sigil.*`): context rules, per-source colours, per-host bodies, the
  ring's order, temperament numbers.
- Setter codes stay append-only (`lib/setters.luau` ↔ `tools/gen-settings.py`); the settings page is generated
  as every page is.

## 8. Context and BMO

Context (the director's inputs):
- the focused window — app, title, fullscreen, floating, pinned. Defaults, editable in the file: focusing an app
  morphs the line into its icon's silhouette (inner mark for round icons) for a moment; the player or Spotify
  focused leads with music; a fullscreen window shrinks the object to its glyph and quiets it (urgent events
  still reach it);
- the bar module the pointer is over — previewed in the Pill;
- window states in the glyph (a pin mark while the focused window is pinned);
- at the pointer over a window, the **This window** group.

BMO:
- a `bmo` source: the line draws his face (eyes and mouth as part of the stroke), his line of words beside it in
  compact and display;
- his moods (`shell/bmo/brain`) may drive the temperament (excited → Restless, asleep → Calm);
- the organism body for BMO is a later spec; nothing here blocks it.

## 9. Retiring the Pill

1. **Side by side:** in Pill mode, `sigil.pill` chooses `classic` or `sigil` (default `classic` until wave 1 is
   done, then `sigil`).
2. **Classic removed** once wave 1 covers what it did, with a migration in `lib/config`: `pill.face` → the
   Pill host's resting source, `pill.views` → the wheel's order, `pill.pads` → the You and Desk groups,
   `pill.shape` / `pill.hide` → how the host rests. The morph (D204) and the extra pills (D205) go with it;
   islands hosting the sigil replace the extra pills. `lib/pill`, `lib/pillface`, `lib/pillpads`,
   `lib/pillrows`, `ui/pill.plm`, `shell/pillboard.luau`, `ui/pillboard.plm`, `lib/pillmorph` and the frame's
   morph outline are deleted; their tests go with them.

## 10. Failure

- `mooi-sigil` crashes: respawned (five quick tries); meanwhile the bar draws a plain clock in the Pill's box.
- A feed missing or stale: that source's compact form shows a dash and the director skips it.
- Bad settings: `lib/config` refuses the field and the default stands, reported as every other setting is.
- No hosts file yet: the program waits, drawing nothing.

## 11. Performance budget

- Each host surface under **1 ms** compose + paint per frame at 60 fps (`pleamar --report`).
- `rate: 60, 20 while calm` on every surface; no repaint while nothing moves; idle breathing only at 20 fps.
- Overlay and display surfaces unmapped when unused.
- The frame scene is not touched by the object at all.

## 12. Testing

- Unit (`tests/unit/run.lua`): every bar module in `lib/barlayout.ORDER` that the bar shows has a source entry;
  every form's points are 64 and inside their box, for every host size; the director's priorities, urgency,
  hover preview and fullscreen quieting; the palette's four layers and their order; the settings migration
  (each old `pill.*` key to its new place); bodies' and temperaments' numbers in range.
- Every scene compiles (`bin/mooi check`, CI).
- Live, `tests/sigil.sh`: driven through `pleamar --say`, restoring settings byte for byte and the players and
  volume, never moving the pointer; each wave-1 source's forms in the Pill and an island; the pointer host
  opened and cancelled by events; a crash and the fallback clock.
- Performance: `pleamar --report mooi-sigil` against §11, in each host, with music playing.
- Screenshots of every form in every body.

## 13. Out of scope here

mooi Pulse (diagnostics), BMO's organism body, desk mode expanded (each its own spec); multi-monitor beyond the
screen the bar is on; touch input.
