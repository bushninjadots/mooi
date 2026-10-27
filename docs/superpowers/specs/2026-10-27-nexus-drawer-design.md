# Control Nexus as a drawer — design

Date: 2026-10-27 · Status: approved in conversation (the user chose: one Nexus; a right-side drawer;
the twelve sections; "we can always change") · Decision record: D98 when built.

## Why

The Control Nexus has two views — a full-screen node-graph workspace (D76–D84) and a compact hub —
and neither is what the user wants: cards that read "—", tiles that lead nowhere, and a full-screen
overlay that takes the desktop away. The user: "perfect the control nexus … it needs all the
important info inside and buttons leading somewhere", "something unobtrusive but has everything".

## Success

- One Nexus: a drawer on the right edge, under the bar, the full height of the screen below it,
  420 px wide. The desktop beside it stays visible and usable — no dimming, no full-screen surface.
- Everything important is in it, in one scrolling column, and **every tile does something real**:
  a toggle flips, a row connects or switches, a reading opens its island or its tool.
- It opens from the bar's Nexus mark and `mooi nexus`, and closes on Esc, its ×, the mark again, or a
  click anywhere else (it loses the keyboard → it closes).
- It is drawn in the island style (island.style: plate · tether) with the island kit, so the Nexus
  and the islands are one family; light and dark, corners and reduced motion honoured.
- Data is read only while it is open; closed, the program is not running (as today).

## The drawer

A `kind: panel` surface anchored `top_right`, `size: 420, full`, its top margin the bar's reserve
(read from settings: bar.offset + bar.height + 6), level `top` (over windows), `keyboard: on_demand`
— the compositor gives it the keyboard on open; `on blur` closes it. It slides in from the right on
a spring (~220 ms), and out the same way, then quits.

The body is one IslandFrame-like plate (plate: a chamfered Ferrolume plate down the edge; tether: a
rounded slab with the accent rim) holding a header and a scrolling column of **sections**. A
section is a header line (its name, a short summary on the right, a fold chevron) and its body.
Folded sections show only their header; which are folded is kept in `nexus.folded` (a list of ids).

## Sections, top to bottom

1. **Header** — avatar, name, `user@host`, the time and date; buttons: Settings, Lock, Power menu, ×.
2. **Quick toggles** — a 3-column grid: Wi-Fi, Bluetooth, Mute, Mic, Do not disturb, Night light,
   Keep awake, Battery saver, Record. Each lit when on; a press flips it.
3. **Levels** — volume, microphone, brightness (press, drag, wheel).
4. **Now playing** — only while something plays: cover, title, artist, transport, progress; the
   cover opens the music player.
5. **Notifications** — the latest five (app, title, how long ago); a press opens the Signal Field;
   *Clear all*. The bar is the only notification receiver, so it writes `nexus-feed.json` (the
   latest five, no bodies) whenever its list changes; the Nexus watches that file and asks the bar
   to clear (`emit` over `pleamar --say mooi`).
6. **Connections** — Wi-Fi: the network in use and up to four others (a press joins a known one;
   an unknown secured one opens the settings window's network page); Bluetooth: paired devices with
   their battery, a press connects or disconnects.
7. **Sound** — the output devices (a press makes one the default) and the apps playing, each with a
   level (press, drag, wheel).
8. **Machine** — CPU (with temperature), memory, disk, GPU as small gauges; the battery line (charge,
   time left); a press on the gauges opens btop.
9. **Today** — the date and the next six days as a strip, and the weather now (glyph, temperature,
   word); a press on either opens the bar's calendar / weather island.
10. **System updates** — "48 waiting · 26 packages · 5 AUR · 17 Flatpak" or "Up to date", and
    *Update* (the bar's updater). The bar writes `updates.json` after every look.
11. **Workspaces** — a strip of the workspaces in use; a press goes there.
12. **Shortcuts** — Wallpaper studio, Notes, Board, Overview, Screenshot, Clipboard, Diagnostics.

## Talking to the bar

The Nexus is a program of its own and cannot read the bar's facts. It asks the bar with
`pleamar --say mooi "emit …"` for what only the bar does (open an island, clear notifications, run
the updater, record, keep awake, battery saver lives in settings), and reads two small files the bar
writes into mooi's data folder: `nexus-feed.json` (notifications) and `updates.json`. Islands opened
from the Nexus close the drawer first.

## What retires

The node-graph workspace, the hub and their customisation (arrangements, card layout, hub order):
shell/mooi-nexus.plm and .luau are rewritten; lib/nexusgraph, lib/nexuslayout, lib/nexusnode and
lib/nexushub and their tests go, with the `nexus.*` settings only they read (config migration drops
them). lib/nexus and lib/telemetry stay where still used. Git history keeps all of it.

## Testing

Unit: the feed and the updates file as the bar writes them (pure builders in lib), the drawer's
section order and folding (lib/nexusdrawer, pure). Live: open from the mark; every section drawn in
both styles and screenshotted; each kind of tile pressed once where it is safe (a toggle on and off,
a level, a section folded and back, an island opened from Today); blur closes; the bar's idle frames
unchanged; scene.sh and integration.sh still pass.

## Deviation, found while building

"A click anywhere else closes it" is not possible for a drawer that leaves the desktop usable: a
layer surface hears nothing outside itself, and holding the keyboard to notice a blur would take
the keyboard from every window. So it closes on Esc, ×, the mark, losing the keyboard (once it has
it), the workspace changing, or another *app* taking the focus — by class, since Hyprland names the
focused window only by title and class, and titles change by themselves.

Update: with Hyprland's focus following the mouse, a focus change or a blur happens on every mouse
move, so neither closes the drawer any more — Esc, ×, the mark, or a workspace change do.
