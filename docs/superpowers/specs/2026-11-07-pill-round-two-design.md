# The Pill, round two: views, many pills, motion, the stash

Date: 2026-11-07 · Status: drafted from the owner's requests (2026-11-07), awaiting review · Decision: D171
Builds on: D168 (the Pill), D169 (faces, hiding, nodes), D170 (the board)

## 1. What the owner asked for

Scroll through views; any view can be the face, not just the clock; each view at the detail the owner
wants (icons only, moderate, detailed); several pills that tuck away when not in use and come back when
called or when something relevant happens; islands that are connected show it (a node shooting across,
or running along the frame's border); a Super-held scroll for a second, actions menu; a fixed-size
terminal from the island; a wallpaper switcher that fits inside; a profile card (picture, banner, bio,
GitHub); diagnostics, system actions, alerts, apps, search, visualiser-only; the Pill as the stash (drop
anything in, drag it out); alerts springing a node out with a pulse, a shutdown effect when many close,
BMO's game-over; themed like the bar with a border and a live circuit backdrop; smooth, fluid, unique,
customisable.

## 2. Views — one list for the face and the board

- A **view** is something the Pill can show: every module of the bar (32), plus the Pill's own: BMO,
  Nexus, Visualiser, Profile, Diagnostics, Actions, Apps, Search, Wallpaper, Workspaces, Stash.
- Each view has a **closed** form (the face) and an **open** form (its room on the board).
- Each view has a **detail**: `icon` (just the glyph), `brief` (glyph and a reading — today's faces), or
  `full` (a second line or a small graph). The same three levels the bar's modules get in stage 4
  (`modlook.display`), so one setting means the same thing everywhere.
- **Scroll over the closed Pill** turns its face to the next view in the owner's list (`pill.views`);
  the **default** view (`pill.face`) is where it rests and returns after `pill.rest` seconds idle
  (or stays where it was turned, if 0). **Scroll over the board** turns its rooms (as now), over the same
  list.

## 3. Many pills

- Up to **three pills**: the centre one, and optional left and right ones (`pill.extra`), each with its
  own views, default, detail, pads and hiding. A left pill for music and a right one for the system,
  say.
- Each pill **when idle** (`hide`): `stay`, `tuck` (a dot or a sliver — today's hiding), or `vanish`
  (gone; its edge of the band shows a faint seam). It comes back when **pointed at** (its seam or dot),
  **called** (a key per pill, `mooi pill left|centre|right`), or when **something relevant** happens to
  one of its views (music starts → the music pill; a signal → the one with Alerts).

## 4. Connections and motion

- **Connected islands pulse.** When something moves from one island to another — a moon pinned into the
  Pill, a signal arriving for the pill that shows Alerts, the volume pill answering the media pill — a
  **node shoots across**: along the frame's band when the frame is on, otherwise along a faint trace
  between them; both ends pulse as it lands. The bar's style decides its look (plate: a lit chip;
  tether: a bead on a hairline).
- **An alert springs a node** out of the Pill's side with a pulse, then it settles back in.
- **Many closing at once** (moons expiring, the board folding with docked chips): a quick **shutdown**
  — each part dims in sequence along its trace, a last pulse runs home.
- **BMO**: a **game over** (8-bit blink and "GAME OVER") when a recording or a timer ends, and a
  **power-down** — eyes narrowing to a line, then off — when his pill tucks away.
- Every motion is on the material's springs, respects reduced motion (`motion.reduced`, the saver), and
  nothing animates while the Pill is idle except BMO's blink.

## 5. Look

- The board and the pills follow the bar's **style and surface** (plate, tether, glass) with a proper
  **border** in that style.
- A **live circuit backdrop** behind the board's core: faint traces in the accent, current flowing along
  them, brighter near the pointer, carrying the music's bands while something plays. Intensity in
  Settings, off in Lite.
- **Lit from inside**: a pad or tile that is on glows from within (Vitrum's idea).
- **Lite**: one switch (and automatic on battery) that turns off the backdrop, glow and the motion.

## 6. New rooms

- **Visualiser**: the whole core is the music (HALO or RIVER, larger), nothing else.
- **Actions**: lock, sleep, log out, restart, power off; screenshot, record; keep awake, do not disturb,
  game mode; the drop-down terminal.
- **Diagnostics**: "about this computer" tiles — CPU, GPU, memory, disk, temperatures, uptime, kernel,
  updates waiting — live.
- **Apps** (pinned, a grid of icons) and **Search** (a field that hands to mooi's command surface).
- **Wallpaper**: a strip of the owner's wallpapers sized to the core, previewed as you scroll, applied
  with a press.
- **Workspaces**: each workspace with its windows' icons; a press switches.
- **Profile**: picture and banner (files the owner chooses), name and bio (`profile.*` settings), and
  GitHub (from the notch's GitHub reader): contributions, open PRs.
- **Stash**: §8.

## 7. Super layer and the terminal

- **Super held** while pointing at a pill turns its scroll into an **actions** scroll (the Actions room's
  items one by one on the face; a press does it). Pleamar must say whether a scene can see a held
  modifier: probed first; if it cannot, the actions layer is a **middle press** (toggle) instead.
- **The drop terminal**: a kitty window (`class mooi-drop`) at a fixed size (`pill.term_size`, default
  960 × 420), floating, pinned, placed under the pill that called it; a second call hides it. From the
  Actions room, a pad, or a key.

## 8. The Pill as the stash

- Drop anything on a pill — files, links, text, code, images, music — and it goes into mooi's stash
  (`shell/stash.luau`, the same store as the stash dock). The pill pulses to take it.
- The **Stash** room shows what is there with a preview by kind; **drag one out** to drop it into an app
  (copy), or press it to copy it to the clipboard.

## 9. Customising

Settings → The Pill: the views (on/off and order), the default view and its rest time, the detail per
view, the extra pills (left/right: their views, hiding, key), hiding per pill, the backdrop's intensity,
Lite, the terminal's size. The board's ✎ EDIT gains the views list.

## 10. Stages

1. **Views and detail**: the view list, scroll on the closed Pill, rest-to-default, `icon`/`brief`/`full`
   for every view; Visualiser, Actions, Diagnostics, Workspaces, Wallpaper rooms.
2. **Many pills and connections**: left/right pills, stay/tuck/vanish, wake on call or relevance, the
   node that shoots across, alert springs, the shutdown, BMO's game-over and power-down.
3. **Look**: the bar's style and border on the board, the live circuit backdrop, lit-from-inside, Lite.
4. **The stash, the terminal, the Super layer, Profile, Apps, Search.**

Each stage is planned, built with tests, checked live and pushed on its own.
